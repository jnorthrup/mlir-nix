//===- StorePaths.cpp - NAR, store paths, ATerm derivations, utilities ----===//

#include "Nix/Prefetch.h"
#include "Nix/Store.h"

#include <algorithm>
#include <cerrno>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <dirent.h>
#include <fcntl.h>
#include <sstream>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

namespace nixstore {

//===----------------------------------------------------------------------===//
// File utilities
//===----------------------------------------------------------------------===//

std::string readFile(const std::string &path) {
  nixprefetch::note('F', path.c_str());
  int fd = open(path.c_str(), O_RDONLY | O_CLOEXEC);
  if (fd < 0) throw Error("opening file '" + path + "': " + strerror(errno));
  std::string s;
  char buf[65536];
  while (true) {
    ssize_t n = read(fd, buf, sizeof buf);
    if (n < 0) {
      int e = errno;
      close(fd);
      throw Error("reading file '" + path + "': " + strerror(e));
    }
    if (n == 0) break;
    s.append(buf, n);
  }
  close(fd);
  return s;
}

void writeFile(const std::string &path, std::string_view data, mode_t mode) {
  int fd = open(path.c_str(), O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, mode);
  if (fd < 0) throw Error("creating file '" + path + "': " + strerror(errno));
  size_t off = 0;
  while (off < data.size()) {
    ssize_t n = write(fd, data.data() + off, data.size() - off);
    if (n < 0) {
      close(fd);
      throw Error("writing file '" + path + "': " + strerror(errno));
    }
    off += n;
  }
  close(fd);
}

bool pathExists(const std::string &path) {
  struct stat st;
  nixprefetch::note('L', path.c_str());
  return lstat(path.c_str(), &st) == 0;
}

void createDirs(const std::string &path) {
  if (path.empty() || path == "/") return;
  struct stat st;
  if (lstat(path.c_str(), &st) == 0) {
    if (S_ISDIR(st.st_mode)) return;
    if (S_ISLNK(st.st_mode) && stat(path.c_str(), &st) == 0 && S_ISDIR(st.st_mode)) return;
    throw Error("'" + path + "' is not a directory");
  }
  createDirs(dirOf(path));
  if (mkdir(path.c_str(), 0777) != 0 && errno != EEXIST)
    throw Error("creating directory '" + path + "': " + strerror(errno));
}

void deletePathRecursive(const std::string &path) {
  struct stat st;
  if (lstat(path.c_str(), &st) != 0) return;
  if (S_ISDIR(st.st_mode)) {
    chmod(path.c_str(), st.st_mode | S_IRWXU);
    if (DIR *d = opendir(path.c_str())) {
      std::vector<std::string> names;
      while (auto *e = readdir(d)) {
        std::string n = e->d_name;
        if (n != "." && n != "..") names.push_back(n);
      }
      closedir(d);
      for (auto &n : names) deletePathRecursive(path + "/" + n);
    }
    if (rmdir(path.c_str()) != 0) throw Error("removing '" + path + "': " + strerror(errno));
  } else {
    if (unlink(path.c_str()) != 0) throw Error("removing '" + path + "': " + strerror(errno));
  }
}

std::string baseNameOf(std::string_view p) {
  if (p.empty()) return "";
  size_t last = p.size();
  if (p.back() == '/' && last > 1) last--;
  size_t pos = p.rfind('/', last - 1);
  if (pos == std::string_view::npos) return std::string(p.substr(0, last));
  return std::string(p.substr(pos + 1, last - pos - 1));
}

std::string dirOf(std::string_view p) {
  auto pos = p.rfind('/');
  if (pos == std::string_view::npos) return ".";
  return pos == 0 ? "/" : std::string(p.substr(0, pos));
}

std::string jsonEscape(std::string_view s) {
  std::string o = "\"";
  for (unsigned char c : s) {
    switch (c) {
    case '"': o += "\\\""; break;
    case '\\': o += "\\\\"; break;
    case '\b': o += "\\b"; break;
    case '\f': o += "\\f"; break;
    case '\n': o += "\\n"; break;
    case '\r': o += "\\r"; break;
    case '\t': o += "\\t"; break;
    default:
      if (c < 0x20) {
        char buf[8];
        snprintf(buf, sizeof buf, "\\u%04x", c);
        o += buf;
      } else {
        o += char(c);
      }
    }
  }
  o += '"';
  return o;
}

std::string jsonFloat(double d) {
  if (std::isnan(d) || std::isinf(d)) return "null";
  if (d == 0) return std::signbit(d) ? "-0.0" : "0.0";
  // Shortest representation that round-trips (what grisu2 produces).
  char buf[64];
  int prec;
  for (prec = 1; prec <= 17; prec++) {
    snprintf(buf, sizeof buf, "%.*e", prec - 1, d);
    if (strtod(buf, nullptr) == d) break;
  }
  // buf: [-]d.ddde[+-]XX ; extract digits and exponent.
  std::string s = buf;
  bool neg = s[0] == '-';
  if (neg) s = s.substr(1);
  auto epos = s.find('e');
  int exp10 = atoi(s.c_str() + epos + 1);
  std::string digits;
  for (size_t i = 0; i < epos; i++)
    if (isdigit((unsigned char)s[i])) digits += s[i];
  while (digits.size() > 1 && digits.back() == '0') digits.pop_back();
  // nlohmann::detail::format_buffer: k = number of digits, n = exp10 + 1
  int k = (int)digits.size();
  int n = exp10 + 1;
  std::string out;
  const int minExp = -4, maxExp = 15;
  if (k <= n && n <= maxExp) {
    out = digits + std::string(n - k, '0') + ".0";
  } else if (0 < n && n <= maxExp) {
    out = digits.substr(0, n) + "." + digits.substr(n);
  } else if (minExp < n && n <= 0) {
    out = "0." + std::string(-n, '0') + digits;
  } else {
    out = digits.substr(0, 1);
    if (k > 1) out += "." + digits.substr(1);
    out += "e";
    int e = n - 1;
    out += e < 0 ? '-' : '+';
    int ae = std::abs(e);
    if (ae < 10) out += "0";
    out += std::to_string(ae);
  }
  return neg ? "-" + out : out;
}

int runProgram(const std::string &prog, const std::vector<std::string> &args, std::string *out,
               const std::string *input, const std::string &cwd) {
  int outPipe[2], inPipe[2];
  if (pipe(outPipe) != 0) throw Error("pipe failed");
  if (input && pipe(inPipe) != 0) throw Error("pipe failed");
  pid_t pid = fork();
  if (pid < 0) throw Error("fork failed");
  if (pid == 0) {
    if (!cwd.empty() && chdir(cwd.c_str()) != 0) _exit(127);
    dup2(outPipe[1], 1);
    close(outPipe[0]);
    close(outPipe[1]);
    if (input) {
      dup2(inPipe[0], 0);
      close(inPipe[0]);
      close(inPipe[1]);
    } else {
      int nul = open("/dev/null", O_RDONLY);
      dup2(nul, 0);
    }
    std::vector<char *> argv;
    argv.push_back(const_cast<char *>(prog.c_str()));
    for (auto &a : args) argv.push_back(const_cast<char *>(a.c_str()));
    argv.push_back(nullptr);
    execvp(prog.c_str(), argv.data());
    _exit(127);
  }
  close(outPipe[1]);
  if (input) {
    close(inPipe[0]);
    size_t off = 0;
    while (off < input->size()) {
      ssize_t n = write(inPipe[1], input->data() + off, input->size() - off);
      if (n <= 0) break;
      off += n;
    }
    close(inPipe[1]);
  }
  char buf[65536];
  while (true) {
    ssize_t n = read(outPipe[0], buf, sizeof buf);
    if (n <= 0) break;
    if (out) out->append(buf, n);
  }
  close(outPipe[0]);
  int status;
  waitpid(pid, &status, 0);
  if (WIFEXITED(status)) return WEXITSTATUS(status);
  return 128 + (WIFSIGNALED(status) ? WTERMSIG(status) : 0);
}

//===----------------------------------------------------------------------===//
// NAR
//===----------------------------------------------------------------------===//

namespace {
struct NarWriter {
  const Sink &sink;
  const PathFilter &filter;
  void u64(uint64_t n) {
    char b[8];
    for (int i = 0; i < 8; i++) b[i] = char((n >> (8 * i)) & 0xff);
    sink(std::string_view(b, 8));
  }
  void pad(uint64_t n) {
    static const char zeros[8] = {0};
    if (n % 8) sink(std::string_view(zeros, 8 - n % 8));
  }
  void str(std::string_view s) {
    u64(s.size());
    sink(s);
    pad(s.size());
  }
  void dump(const std::string &path) {
    struct stat st;
    nixprefetch::note('L', path.c_str());
    if (lstat(path.c_str(), &st) != 0)
      throw Error("getting attributes of path '" + path + "': " + strerror(errno));
    str("(");
    if (S_ISREG(st.st_mode)) {
      str("type");
      str("regular");
      if (st.st_mode & S_IXUSR) {
        str("executable");
        str("");
      }
      str("contents");
      u64(st.st_size);
      nixprefetch::note('F', path.c_str());
      int fd = open(path.c_str(), O_RDONLY | O_CLOEXEC);
      if (fd < 0) throw Error("opening file '" + path + "': " + strerror(errno));
      char buf[65536];
      uint64_t left = st.st_size;
      while (left) {
        ssize_t n = read(fd, buf, std::min<uint64_t>(sizeof buf, left));
        if (n <= 0) { close(fd); throw Error("reading file '" + path + "'"); }
        sink(std::string_view(buf, n));
        left -= n;
      }
      close(fd);
      pad(st.st_size);
    } else if (S_ISDIR(st.st_mode)) {
      str("type");
      str("directory");
      std::vector<std::string> names;
      nixprefetch::note('D', path.c_str());
      DIR *d = opendir(path.c_str());
      if (!d) throw Error("opening directory '" + path + "': " + strerror(errno));
      while (auto *e = readdir(d)) {
        std::string n = e->d_name;
        if (n == "." || n == "..") continue;
        names.push_back(n);
      }
      closedir(d);
      std::sort(names.begin(), names.end());
      for (auto &n : names) {
        std::string child = path + "/" + n;
        if (filter && !filter(child)) continue;
        str("entry");
        str("(");
        str("name");
        str(n);
        str("node");
        dump(child);
        str(")");
      }
    } else if (S_ISLNK(st.st_mode)) {
      str("type");
      str("symlink");
      str("target");
      char buf[PATH_MAX + 1];
      ssize_t n = readlink(path.c_str(), buf, PATH_MAX);
      if (n < 0) throw Error("reading symlink '" + path + "'");
      str(std::string_view(buf, n));
    } else {
      throw Error("file '" + path + "' has an unsupported type");
    }
    str(")");
  }
};
} // namespace

void dumpPath(const std::string &path, const Sink &sink, const PathFilter &filter) {
  NarWriter w{sink, filter};
  w.str("nix-archive-1");
  w.dump(path);
}

std::pair<Hash, uint64_t> hashPath(const std::string &path, const PathFilter &filter, HashAlgo algo) {
  HashSink hs(algo);
  dumpPath(path, [&](std::string_view d) { hs.update(d); }, filter);
  uint64_t n = hs.bytes();
  return {hs.finish(), n};
}

void restorePath(const std::string &path, std::string_view nar) {
  size_t p = 0;
  auto u64 = [&]() -> uint64_t {
    if (p + 8 > nar.size()) throw Error("NAR truncated");
    uint64_t n = 0;
    for (int i = 0; i < 8; i++) n |= uint64_t((unsigned char)nar[p + i]) << (8 * i);
    p += 8;
    return n;
  };
  auto str = [&]() -> std::string_view {
    uint64_t n = u64();
    if (p + n > nar.size()) throw Error("NAR truncated");
    std::string_view s = nar.substr(p, n);
    p += n;
    if (n % 8) p += 8 - n % 8;
    return s;
  };
  auto expect = [&](std::string_view s) {
    if (str() != s) throw Error("bad NAR: expected '" + std::string(s) + "'");
  };
  std::function<void(const std::string &)> node = [&](const std::string &dst) {
    expect("(");
    expect("type");
    auto t = str();
    if (t == "regular") {
      auto tag = str();
      bool exec = false;
      if (tag == "executable") { str(); exec = true; tag = str(); }
      if (tag != "contents") throw Error("bad NAR");
      auto c = str();
      writeFile(dst, c, exec ? 0755 : 0644);
      expect(")");
    } else if (t == "symlink") {
      expect("target");
      std::string tgt(str());
      if (symlink(tgt.c_str(), dst.c_str()) != 0) throw Error("creating symlink '" + dst + "'");
      expect(")");
    } else if (t == "directory") {
      if (mkdir(dst.c_str(), 0755) != 0) throw Error("creating directory '" + dst + "'");
      while (true) {
        auto tag = str();
        if (tag == ")") break;
        if (tag != "entry") throw Error("bad NAR");
        expect("(");
        expect("name");
        std::string name(str());
        if (name.empty() || name == "." || name == ".." || name.find('/') != std::string::npos)
          throw Error("NAR contains invalid file name '" + name + "'");
        expect("node");
        node(dst + "/" + name);
        expect(")");
      }
    } else {
      throw Error("bad NAR: unknown file type");
    }
  };
  expect("nix-archive-1");
  node(path);
}

//===----------------------------------------------------------------------===//
// Store paths
//===----------------------------------------------------------------------===//

void checkName(std::string_view name) {
  auto q = [&](std::string_view n) { return "'" + std::string(n) + "'"; };
  if (name.empty()) throw Error("name must not be empty");
  if (name.size() > 211)
    throw Error("name " + q(name) + " must be no longer than 211 characters");
  if (name[0] == '.') {
    if (name.size() == 1) throw Error("name " + q(name) + " is not valid");
    if (name[1] == '-')
      throw Error("name " + q(name) + " is not valid: first dash-separated component must not be '.'");
    if (name[1] == '.') {
      if (name.size() == 2) throw Error("name " + q(name) + " is not valid");
      if (name[2] == '-')
        throw Error("name " + q(name) + " is not valid: first dash-separated component must not be '..'");
    }
  }
  for (char c : name)
    if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '+' ||
          c == '-' || c == '.' || c == '_' || c == '?' || c == '='))
      throw Error("name " + q(name) + " contains illegal character '" + std::string(1, c) + "'");
}

std::string makeStorePath(const std::string &storeDir, std::string_view type, const Hash &hash,
                          std::string_view name) {
  checkName(name);
  std::string s = std::string(type) + ":" + hash.to_string(HashFormat::Base16, true) + ":" +
                  storeDir + ":" + std::string(name);
  Hash h = compressHash(hashString(HashAlgo::SHA256, s), 20);
  return storeDir + "/" + nix32Encode(h.bytes, 20) + "-" + std::string(name);
}

std::string makeType(const std::string &storeDir, std::string type, const std::set<std::string> &refs,
                     bool hasSelfRef) {
  for (auto &r : refs) {
    type += ":";
    type += r;
  }
  if (hasSelfRef) type += ":self";
  return type;
}

std::string makeTextPath(const std::string &storeDir, std::string_view name, const Hash &hash,
                         const std::set<std::string> &refs) {
  return makeStorePath(storeDir, makeType(storeDir, "text", refs, false), hash, name);
}

std::string makeFixedOutputPath(const std::string &storeDir, std::string_view name,
                                FileIngestionMethod method, const Hash &hash,
                                const std::set<std::string> &refs) {
  if (method == FileIngestionMethod::Text) return makeTextPath(storeDir, name, hash, refs);
  if (method == FileIngestionMethod::NixArchive && hash.algo == HashAlgo::SHA256)
    return makeStorePath(storeDir, makeType(storeDir, "source", refs, false), hash, name);
  if (!refs.empty())
    throw Error("fixed output derivation '" + std::string(name) +
                "' is not allowed to refer to other store paths.");
  std::string payload = "fixed:out:" +
                        std::string(method == FileIngestionMethod::NixArchive ? "r:" : "") +
                        hash.to_string(HashFormat::Base16, true) + ":";
  return makeStorePath(storeDir, "output:out", hashString(HashAlgo::SHA256, payload), name);
}

std::string outputPathName(std::string_view drvName, std::string_view output) {
  std::string s(drvName);
  if (output != "out") {
    s += "-";
    s += output;
  }
  return s;
}

std::string makeOutputPath(const std::string &storeDir, std::string_view output, const Hash &drvHash,
                           std::string_view drvName) {
  return makeStorePath(storeDir, "output:" + std::string(output), drvHash,
                       outputPathName(drvName, output));
}

std::string hashPlaceholder(std::string_view output) {
  Hash h = hashString(HashAlgo::SHA256, "nix-output:" + std::string(output));
  return "/" + h.to_string(HashFormat::Nix32, false);
}

bool isInStore(const std::string &storeDir, std::string_view path) {
  return path.size() > storeDir.size() + 1 && path.substr(0, storeDir.size()) == storeDir &&
         path[storeDir.size()] == '/';
}

std::string toStorePath(const std::string &storeDir, std::string_view path) {
  if (!isInStore(storeDir, path)) throw Error("path '" + std::string(path) + "' is not in the Nix store");
  auto slash = path.find('/', storeDir.size() + 1);
  return std::string(slash == std::string_view::npos ? path : path.substr(0, slash));
}

bool isStorePath(const std::string &storeDir, std::string_view path) {
  if (!isInStore(storeDir, path)) return false;
  std::string_view base = path.substr(storeDir.size() + 1);
  if (base.find('/') != std::string_view::npos) return false;
  if (base.size() < 34 || base[32] != '-') return false;
  for (size_t i = 0; i < 32; i++)
    if (!strchr(nix32Chars, base[i]) || !base[i]) return false;
  try {
    checkName(base.substr(33));
  } catch (Error &) {
    return false;
  }
  return true;
}

std::string storePathName(std::string_view storePath) {
  std::string base = baseNameOf(storePath);
  return base.size() > 33 ? base.substr(33) : base;
}

std::string storePathHashPart(std::string_view storePath) {
  return baseNameOf(storePath).substr(0, 32);
}

//===----------------------------------------------------------------------===//
// Derivations
//===----------------------------------------------------------------------===//

std::string DerivationOutput::methodAlgo() const {
  std::string prefix = method == FileIngestionMethod::NixArchive ? "r:"
                       : method == FileIngestionMethod::Text      ? "text:"
                                                                  : "";
  return prefix + algoName(kind == CAFixed ? hash.algo : hashAlgo);
}

std::string DerivationOutput::fixedPath(const std::string &storeDir, std::string_view drvName,
                                        std::string_view output) const {
  return makeFixedOutputPath(storeDir, outputPathName(drvName, output), method, hash);
}

bool Derivation::isFixed() const {
  return outputs.size() == 1 && outputs.begin()->first == "out" &&
         outputs.begin()->second.kind == DerivationOutput::CAFixed;
}

/// Appends `s` in quotes with ATerm escapes.  The bytes between two escapes are copied whole: the values of an
/// environment are scripts of kilobytes, and a byte-at-a-time push_back was a fiftieth of a NixOS evaluation.
static void appendEscaped(std::string &out, std::string_view s) {
  out += '"';
  size_t run = 0;
  for (size_t i = 0; i < s.size(); i++) {
    const char *escape;
    switch (s[i]) {
    case '"': escape = "\\\""; break;
    case '\\': escape = "\\\\"; break;
    case '\n': escape = "\\n"; break;
    case '\r': escape = "\\r"; break;
    case '\t': escape = "\\t"; break;
    default: continue;
    }
    out.append(s.data() + run, i - run);
    out += escape;
    run = i + 1;
  }
  out.append(s.data() + run, s.size() - run);
  out += '"';
}

std::string escapeATermString(std::string_view s) {
  std::string r;
  r.reserve(s.size() + 2);
  appendEscaped(r, s);
  return r;
}

static void unquoted(std::string &s, std::string_view v) {
  s += '"';
  s += v;
  s += '"';
}

std::string Derivation::unparse(bool maskOutputs,
                                const std::map<std::string, std::set<std::string>> *actualInputs) const {
  // Note: the store dir is embedded in paths already.
  std::string s = "Derive([";
  bool first = true;
  for (auto &[name, o] : outputs) {
    if (!first) s += ',';
    first = false;
    s += '(';
    unquoted(s, name);
    s += ',';
    switch (o.kind) {
    case DerivationOutput::InputAddressed:
      unquoted(s, maskOutputs ? "" : o.path);
      s += ",\"\",\"\"";
      break;
    case DerivationOutput::CAFixed:
      unquoted(s, maskOutputs ? "" : o.path);
      s += ',';
      unquoted(s, o.methodAlgo());
      s += ',';
      unquoted(s, o.hash.to_string(HashFormat::Base16, false));
      break;
    case DerivationOutput::CAFloating:
      s += "\"\",";
      unquoted(s, o.methodAlgo());
      s += ",\"\"";
      break;
    case DerivationOutput::Deferred:
      s += "\"\",\"\",\"\"";
      break;
    case DerivationOutput::Impure:
      s += "\"\",";
      unquoted(s, o.methodAlgo());
      s += ",\"impure\"";
      break;
    }
    s += ')';
  }
  s += "],[";
  first = true;
  const auto &inputs = actualInputs ? *actualInputs : inputDrvs;
  for (auto &[path, outs] : inputs) {
    if (!first) s += ',';
    first = false;
    s += '(';
    unquoted(s, path);
    s += ",[";
    bool f2 = true;
    for (auto &o : outs) {
      if (!f2) s += ',';
      f2 = false;
      unquoted(s, o);
    }
    s += "])";
  }
  s += "],[";
  first = true;
  for (auto &p : inputSrcs) {
    if (!first) s += ',';
    first = false;
    unquoted(s, p);
  }
  s += "],";
  unquoted(s, platform);
  s += ',';
  appendEscaped(s, builder);
  s += ",[";
  first = true;
  for (auto &a : args) {
    if (!first) s += ',';
    first = false;
    appendEscaped(s, a);
  }
  s += "],[";
  first = true;
  // The environment in key order, plus `__json` when there are structured attributes: views, not a copy of every value.
  std::map<std::string_view, std::string_view> envAll;
  size_t envBytes = 0;
  for (auto &[k, v] : env) {
    envAll.emplace_hint(envAll.end(), k, v);
    envBytes += k.size() + v.size() + 8;
  }
  if (structuredAttrs) {
    envAll["__json"] = *structuredAttrs;
    envBytes += structuredAttrs->size() + 16;
  }
  s.reserve(s.size() + envBytes);
  for (auto &[k, v] : envAll) {
    if (!first) s += ',';
    first = false;
    s += '(';
    appendEscaped(s, k);
    s += ',';
    appendEscaped(s, maskOutputs && outputs.count(std::string(k)) ? std::string_view() : v);
    s += ')';
  }
  s += "])";
  return s;
}

namespace {
struct ATermParser {
  std::string_view s;
  size_t p = 0;
  [[noreturn]] void fail() { throw Error("invalid derivation (ATerm parse error at offset " + std::to_string(p) + ")"); }
  void expect(std::string_view t) {
    if (s.substr(p, t.size()) != t) fail();
    p += t.size();
  }
  bool peek(char c) { return p < s.size() && s[p] == c; }
  std::string str() {
    expect("\"");
    std::string r;
    while (p < s.size() && s[p] != '"') {
      if (s[p] == '\\') {
        p++;
        if (p >= s.size()) fail();
        char c = s[p++];
        if (c == 'n') r += '\n';
        else if (c == 'r') r += '\r';
        else if (c == 't') r += '\t';
        else r += c;
      } else {
        r += s[p++];
      }
    }
    expect("\"");
    return r;
  }
  std::vector<std::string> strs() {
    std::vector<std::string> v;
    expect("[");
    while (!peek(']')) {
      v.push_back(str());
      if (peek(',')) p++;
    }
    expect("]");
    return v;
  }
};
} // namespace

Derivation parseDerivation(std::string_view text, std::string name) {
  Derivation d;
  d.name = std::move(name);
  ATermParser P{text};
  P.expect("Derive([");
  while (!P.peek(']')) {
    P.expect("(");
    std::string id = P.str();
    P.expect(",");
    std::string path = P.str();
    P.expect(",");
    std::string algo = P.str();
    P.expect(",");
    std::string hash = P.str();
    P.expect(")");
    DerivationOutput o;
    if (!algo.empty()) {
      std::string a = algo;
      o.method = FileIngestionMethod::Flat;
      if (a.rfind("r:", 0) == 0) { o.method = FileIngestionMethod::NixArchive; a = a.substr(2); }
      else if (a.rfind("text:", 0) == 0) { o.method = FileIngestionMethod::Text; a = a.substr(5); }
      auto ha = parseHashAlgo(a);
      if (!ha) throw Error("unknown hash algorithm '" + a + "' in derivation");
      o.hashAlgo = *ha;
      if (hash == "impure") o.kind = DerivationOutput::Impure;
      else if (!hash.empty()) {
        o.kind = DerivationOutput::CAFixed;
        o.hash = parseHash(hash, *ha);
        o.path = path;
      } else o.kind = DerivationOutput::CAFloating;
    } else if (path.empty()) {
      o.kind = DerivationOutput::Deferred;
    } else {
      o.kind = DerivationOutput::InputAddressed;
      o.path = path;
    }
    d.outputs[id] = o;
    if (P.peek(',')) P.p++;
  }
  P.expect("],[");
  while (!P.peek(']')) {
    P.expect("(");
    std::string path = P.str();
    P.expect(",");
    auto outs = P.strs();
    P.expect(")");
    d.inputDrvs[path] = std::set<std::string>(outs.begin(), outs.end());
    if (P.peek(',')) P.p++;
  }
  P.expect("],");
  auto srcs = P.strs();
  d.inputSrcs = std::set<std::string>(srcs.begin(), srcs.end());
  P.expect(",");
  d.platform = P.str();
  P.expect(",");
  d.builder = P.str();
  P.expect(",");
  d.args = P.strs();
  P.expect(",[");
  while (!P.peek(']')) {
    P.expect("(");
    std::string k = P.str();
    P.expect(",");
    std::string v = P.str();
    P.expect(")");
    if (k == "__json") d.structuredAttrs = v;
    else d.env[k] = v;
    if (P.peek(',')) P.p++;
  }
  P.expect("])");
  return d;
}

std::string derivationToJSON(const std::string &storeDir, const std::string &drvPath,
                             const Derivation &drv) {
  std::string j = "{" + jsonEscape(drvPath) + ":{";
  j += "\"args\":[";
  for (size_t i = 0; i < drv.args.size(); i++) j += (i ? "," : "") + jsonEscape(drv.args[i]);
  j += "],\"builder\":" + jsonEscape(drv.builder) + ",\"env\":{";
  bool first = true;
  auto env = drv.env;
  if (drv.structuredAttrs) env["__json"] = *drv.structuredAttrs;
  for (auto &[k, v] : env) {
    j += (first ? "" : ",") + jsonEscape(k) + ":" + jsonEscape(v);
    first = false;
  }
  j += "},\"inputDrvs\":{";
  first = true;
  for (auto &[p, outs] : drv.inputDrvs) {
    j += (first ? "" : ",") + jsonEscape(p) + ":{\"dynamicOutputs\":{},\"outputs\":[";
    bool f2 = true;
    for (auto &o : outs) { j += (f2 ? "" : ",") + jsonEscape(o); f2 = false; }
    j += "]}";
    first = false;
  }
  j += "},\"inputSrcs\":[";
  first = true;
  for (auto &p : drv.inputSrcs) { j += (first ? "" : ",") + jsonEscape(p); first = false; }
  j += "],\"name\":" + jsonEscape(drv.name) + ",\"outputs\":{";
  first = true;
  for (auto &[n, o] : drv.outputs) {
    j += (first ? "" : ",") + jsonEscape(n) + ":{";
    first = false;
    switch (o.kind) {
    case DerivationOutput::InputAddressed: j += "\"path\":" + jsonEscape(o.path); break;
    case DerivationOutput::CAFixed:
      j += "\"hash\":" + jsonEscape(o.hash.to_string(HashFormat::Base16, false)) +
           ",\"hashAlgo\":" + jsonEscape(o.methodAlgo()) + ",\"path\":" + jsonEscape(o.path);
      break;
    case DerivationOutput::CAFloating:
    case DerivationOutput::Impure:
      j += "\"hashAlgo\":" + jsonEscape(o.methodAlgo());
      break;
    case DerivationOutput::Deferred: break;
    }
    j += "}";
  }
  j += "},\"system\":" + jsonEscape(drv.platform) + "}}";
  (void)storeDir;
  return j;
}

} // namespace nixstore
