//===- StorePaths.cpp - NAR, store paths, ATerm derivations, utilities ----===//

#include "Composite/Mutable.h"
#include "Composite/Patricia.h"
#include "Composite/Rows.h"
#include "Composite/Text.h"
#include "Nix/Numbers.h"
#include "Nix/Os.h"
#include "Nix/Prefetch.h"
#include "Nix/Store.h"

#include <algorithm>
#include <cerrno>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <dirent.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

namespace nixstore {

//===----------------------------------------------------------------------===//
// File utilities
//===----------------------------------------------------------------------===//

composite::Text readFile(std::string_view path) {
  nixsys::CStr file(path);
  nixprefetch::note('F', file);
  int fd = open(file, O_RDONLY | O_CLOEXEC);
  if (fd < 0) throw Error(composite::cat("opening file '", path, "': ", strerror(errno)));
  composite::Text s;
  char buf[65536];
  while (true) {
    ssize_t n = read(fd, buf, sizeof buf);
    if (n < 0) {
      int e = errno;
      close(fd);
      throw Error(composite::cat("reading file '", path, "': ", strerror(e)));
    }
    if (n == 0) break;
    s.put(buf, size_t(n));
  }
  close(fd);
  return s;
}

void writeFile(std::string_view path, std::string_view data, mode_t mode) {
  nixsys::CStr file(path);
  int fd = open(file, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, mode);
  if (fd < 0) throw Error(composite::cat("creating file '", path, "': ", strerror(errno)));
  size_t off = 0;
  while (off < data.size()) {
    ssize_t n = write(fd, data.data() + off, data.size() - off);
    if (n < 0) {
      close(fd);
      throw Error(composite::cat("writing file '", path, "': ", strerror(errno)));
    }
    off += n;
  }
  close(fd);
}

bool pathExists(std::string_view path) {
  struct stat st;
  nixsys::CStr file(path);
  nixprefetch::note('L', file);
  return lstat(file, &st) == 0;
}

void createDirs(std::string_view path) {
  if (path.empty() || path == "/") return;
  struct stat st;
  nixsys::CStr file(path);
  if (lstat(file, &st) == 0) {
    if (S_ISDIR(st.st_mode)) return;
    if (S_ISLNK(st.st_mode) && stat(file, &st) == 0 && S_ISDIR(st.st_mode)) return;
    throw Error(composite::cat("'", path, "' is not a directory"));
  }
  createDirs(dirOf(path));
  if (mkdir(file, 0777) != 0 && errno != EEXIST)
    throw Error(composite::cat("creating directory '", path, "': ", strerror(errno)));
}

void deletePathRecursive(std::string_view path) {
  struct stat st;
  nixsys::CStr file(path);
  if (lstat(file, &st) != 0) return;
  if (S_ISDIR(st.st_mode)) {
    chmod(file, st.st_mode | S_IRWXU);
    if (DIR *d = opendir(file)) {
      composite::MutableSeries<composite::Text> names;
      while (auto *e = readdir(d)) {
        std::string_view n = e->d_name;
        if (n != "." && n != "..") names.append(composite::Text(n));
      }
      closedir(d);
      for (auto &n : names) deletePathRecursive(composite::cat(path, '/', n));
    }
    if (rmdir(file) != 0) throw Error(composite::cat("removing '", path, "': ", strerror(errno)));
  } else {
    if (unlink(file) != 0) throw Error(composite::cat("removing '", path, "': ", strerror(errno)));
  }
}

composite::Text baseNameOf(std::string_view p) {
  if (p.empty()) return "";
  size_t last = p.size();
  if (p.back() == '/' && last > 1) last--;
  size_t pos = p.rfind('/', last - 1);
  if (pos == std::string_view::npos) return composite::Text(p.substr(0, last));
  return composite::Text(p.substr(pos + 1, last - pos - 1));
}

composite::Text dirOf(std::string_view p) {
  auto pos = p.rfind('/');
  if (pos == std::string_view::npos) return ".";
  return pos == 0 ? composite::Text("/") : composite::Text(p.substr(0, pos));
}

composite::Text jsonEscape(std::string_view s) {
  composite::Text o("\"");
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

composite::Text jsonFloat(double d) {
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
  std::string_view s = buf; // a window on buf, which lives to the end of the function
  bool neg = s[0] == '-';
  if (neg) s = s.substr(1);
  auto epos = s.find('e');
  int exp10 = int(nixsys::readSigned(s.substr(epos + 1)).value);
  composite::Text digits;
  for (size_t i = 0; i < epos; i++)
    if (isdigit((unsigned char)s[i])) digits += s[i];
  while (digits.size() > 1 && digits.back() == '0') digits.pop_back();
  // nlohmann::detail::format_buffer: k = number of digits, n = exp10 + 1
  int k = (int)digits.size();
  int n = exp10 + 1;
  composite::Text out;
  if (neg) out += '-';
  const int minExp = -4, maxExp = 15;
  if (k <= n && n <= maxExp) {
    out.put(digits);
    out.put(size_t(n - k), '0');
    out += ".0";
  } else if (0 < n && n <= maxExp) {
    out.put(digits.substr(0, n));
    out += '.';
    out.put(digits.substr(n));
  } else if (minExp < n && n <= 0) {
    out += "0.";
    out.put(size_t(-n), '0');
    out.put(digits);
  } else {
    out.put(digits.substr(0, 1));
    if (k > 1) {
      out += '.';
      out.put(digits.substr(1));
    }
    out += "e";
    int e = n - 1;
    out += e < 0 ? '-' : '+';
    int ae = std::abs(e);
    if (ae < 10) out += "0";
    out.putInt(ae);
  }
  return out;
}

int runProgram(std::string_view prog, const composite::MutableSeries<composite::Text> &args, composite::Text *out,
               const composite::Text *input, std::string_view cwd) {
  int outPipe[2], inPipe[2];
  if (pipe(outPipe) != 0) throw Error("pipe failed");
  if (input && pipe(inPipe) != 0) throw Error("pipe failed");
  nixsys::CStr progC(prog), cwdC(cwd); // made before the fork, where an allocation is safe: the child only reads them
  pid_t pid = fork();
  if (pid < 0) throw Error("fork failed");
  if (pid == 0) {
    if (!cwd.empty() && chdir(cwdC) != 0) _exit(127);
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
    composite::MutableSeries<char *> argv;
    argv.append(const_cast<char *>(progC.c_str()));
    for (auto &a : args) argv.append(const_cast<char *>(a.c_str()));
    argv.append(nullptr);
    execvp(progC, argv.data());
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
    if (out) out->put(buf, size_t(n));
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
  bool noteKept = false; // a recorded run's first walk of a filtered tree: each entry the filter keeps goes into the list
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
  void dump(const composite::Text &path) {
    struct stat st;
    nixprefetch::note('L', path.c_str());
    if (lstat(path.c_str(), &st) != 0)
      throw Error(composite::cat("getting attributes of path '", path, "': ", strerror(errno)));
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
      if (fd < 0) throw Error(composite::cat("opening file '", path, "': ", strerror(errno)));
      char buf[65536];
      uint64_t left = st.st_size;
      while (left) {
        ssize_t n = read(fd, buf, std::min<uint64_t>(sizeof buf, left));
        if (n <= 0) { close(fd); throw Error(composite::cat("reading file '", path, "'")); }
        sink(std::string_view(buf, n));
        left -= n;
      }
      close(fd);
      pad(st.st_size);
    } else if (S_ISDIR(st.st_mode)) {
      str("type");
      str("directory");
      composite::MutableSeries<composite::Text> names;
      nixprefetch::note('D', path.c_str());
      DIR *d = opendir(path.c_str());
      if (!d) throw Error(composite::cat("opening directory '", path, "': ", strerror(errno)));
      while (auto *e = readdir(d)) {
        std::string_view n = e->d_name;
        if (n == "." || n == "..") continue;
        names.append(composite::Text(n));
      }
      closedir(d);
      composite::MutableSeries<const composite::Text *> order; // the names stay where they are: rows of pointers to them are sorted
      for (auto &n : names) order.append(&n);
      composite::sortRows(order.data(), order.size(), [](const composite::Text *a, const composite::Text *b) {
        return composite::lessChars(composite::series(a->data(), uint32_t(a->size())), composite::series(b->data(), uint32_t(b->size())));
      });
      for (const composite::Text *np : order) {
        const composite::Text &n = *np;
        composite::Text child;
        child.reserve(size_t(path.size()) + 1 + n.size()); // `path/name`, in one allocation
        child += path;
        child += '/';
        child += n;
        if (filter && !filter(child, {})) continue;
        if (noteKept) nixprefetch::noteKept(child.c_str());
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
      if (n < 0) throw Error(composite::cat("reading symlink '", path, "'"));
      str(std::string_view(buf, n));
    } else {
      throw Error(composite::cat("file '", path, "' has an unsupported type"));
    }
    str(")");
  }
};
} // namespace

void dumpPath(std::string_view path, const Sink &sink, const PathFilter &filter) {
  NarWriter w{sink, filter};
  w.str("nix-archive-1");
  w.dump(composite::Text(path));
}

namespace {
/// A tree a recorded run hashed, hashed again by the helper.  The helper writes it while Hashing; once Done it is only read.
struct Prehash {
  enum : uint8_t { Queued, Hashing, Done, Claimed }; // Claimed: asked for before the helper began it, and hashed by the asker
  composite::Atomic<uint8_t> state{Queued};
  bool filtered = false;
  composite::Text root;
  composite::Patricia<char> kept; // a filtered tree: the entries the recorded run's filter kept, keyed by bytes of its own (`names`)
  bool ok = false;
  Hash hash;
  uint64_t size = 0;
  struct Seen {
    uint32_t off, len; // the entry's path, in `text`
    char type;         // 'r', 'd', 's', 'u', or 0 when lstat failed
    bool kept;
  };
  composite::MutableSeries<char> text;
  composite::MutableSeries<Seen> seen; // a filtered tree: every entry the walk asked about, in its order, which is a walk's
  std::string_view path(const Seen &s) const { return {text.data() + s.off, s.len}; }
};
/// The trees by root, filtered or not; built before the helper starts and only read after, so the tries need no lock.
composite::Patricia<Prehash *> *prehashes = nullptr; // [2]
/// How the trees were answered (MLNIX_PREFETCH_DEBUG prints it at exit): the helper's hash, a filter that answered otherwise, hashed by the
/// evaluator because the helper had not begun it.
uint32_t prehashTaken, prehashRefiltered, prehashClaimed;

char typeOf(std::string_view path) {
  struct stat st;
  if (lstat(nixsys::CStr(path), &st) != 0) return 0;
  return S_ISREG(st.st_mode) ? 'r' : S_ISDIR(st.st_mode) ? 'd' : S_ISLNK(st.st_mode) ? 's' : 'u';
}
std::string_view typeName(char t) {
  switch (t) {
  case 'r': return "regular";
  case 'd': return "directory";
  case 's': return "symlink";
  case 'u': return "unknown";
  default: return {}; // the filter finds it itself
  }
}

/// A tree being hashed is waited for here (the evaluator asks for one now and then): the helper signals after each tree it finishes.
nixsys::Lock prehashLock;
nixsys::Signal prehashDone;

/// The helper's answer for the tree at `path`: waited for while it is being made, null when there is none or it failed.  One the helper has
/// not begun is claimed instead, and hashed by the caller.
Prehash *takePrehash(std::string_view path, bool filtered) {
  Prehash **pp = prehashes[filtered].find(path.data(), uint32_t(path.size()));
  if (!pp) return nullptr;
  Prehash *p = *pp;
  uint8_t s = Prehash::Queued;
  if (p->state.compare_exchange(s, Prehash::Claimed) || s == Prehash::Claimed) return ++prehashClaimed, nullptr;
  if (s == Prehash::Hashing) {
    nixsys::Held g(prehashLock);
    prehashDone.waitFor(prehashLock, [p] { return p->state.load(__ATOMIC_ACQUIRE) != Prehash::Hashing; });
  }
  return p->ok ? p : nullptr;
}
} // namespace

void startPrehash() {
  if (prehashes || nixprefetch::replayHashes.empty()) return;
  prehashes = new composite::Patricia<Prehash *>[2];
  if (getenv("MLNIX_PREFETCH_DEBUG"))
    atexit([] { fprintf(stderr, "prehash: %u trees taken, %u filtered otherwise, %u hashed here first\n", prehashTaken, prehashRefiltered, prehashClaimed); });
  composite::MutableSeries<Prehash *> order;
  for (const nixprefetch::ReplayHash &r : nixprefetch::replayHashes) {
    auto &byRoot = prehashes[r.filtered];
    if (byRoot.find(r.root.data(), uint32_t(r.root.size()))) continue; // a root is recorded once (noteRoot)
    // A tree and its kept names are the helper's own, never freed: the helper may still be hashing when the process ends, after the
    // replay list is gone.  The names go in one buffer, made once at its size, so a key never moves.
    auto *p = new Prehash();
    p->filtered = r.filtered;
    p->root = r.root.clone();
    size_t bytes = 0;
    for (const composite::Text &k : r.kept) bytes += k.size();
    char *names = static_cast<char *>(::operator new(bytes ? bytes : 1)), *at = names;
    for (const composite::Text &k : r.kept) {
      memcpy(at, k.data(), k.size());
      p->kept.set(at, uint32_t(k.size()), 1, [at] { return at; });
      at += k.size();
    }
    byRoot.set(p->root.data(), uint32_t(p->root.size()), p, [p] { return p->root.c_str(); });
    order.append(p);
  }
  nixsys::Thread::start([order = std::move(order)]() mutable {
    for (Prehash *p : order) {
      uint8_t s = Prehash::Queued;
      if (!p->state.compare_exchange(s, Prehash::Hashing)) continue; // claimed: the evaluator got there first
      try {
        HashSink hs(HashAlgo::SHA256);
        auto update = [&](std::string_view d) { hs.update(d); }; // the callables a Sink and a PathFilter lend: named, so they outlive the walk
        auto keepIt = [p](std::string_view c, std::string_view) {
          bool k = p->kept.find(c.data(), uint32_t(c.size())) != nullptr;
          uint32_t off = p->text.size();
          p->text.appendAll(c.data(), uint32_t(c.size()));
          p->seen.append({off, uint32_t(c.size()), typeOf(c), k});
          return k;
        };
        Sink sink = update;
        PathFilter keep = keepIt, none;
        NarWriter w{sink, p->filtered ? keep : none};
        w.str("nix-archive-1");
        w.dump(p->root);
        p->size = hs.bytes();
        p->hash = hs.finish();
        p->ok = true;
      } catch (...) {
        p->ok = false;
      }
      p->state.store(Prehash::Done, __ATOMIC_RELEASE);
      { nixsys::Held g(prehashLock); } // a waiter that saw Hashing under the lock is asleep before the signal, so it is woken
      prehashDone.notifyAll();
    }
  }).detach();
}

composite::Join<Hash, uint64_t> hashPath(std::string_view path, const PathFilter &filter, HashAlgo algo) {
  composite::Patricia<char> given; // a prehashed tree whose filter answered otherwise: the answers it gave (1 kept, 2 not), then the filter
  auto answerIt = [&given, &filter](std::string_view c, std::string_view t) {
    char *a = given.find(c.data(), uint32_t(c.size()));
    return a ? *a == 1 : filter(c, t);
  };
  PathFilter answered;
  if (prehashes && algo == HashAlgo::SHA256)
    if (Prehash *p = takePrehash(path, bool(filter))) {
      if (!filter) return ++prehashTaken, composite::Join<Hash, uint64_t>{p->hash, p->size};
      uint32_t k = 0;
      bool d = false;
      for (; k < p->seen.size(); k++) {
        const Prehash::Seen &s = p->seen[k];
        if ((d = filter(p->path(s), typeName(s.type))) != s.kept) break;
      }
      if (k == p->seen.size()) return ++prehashTaken, composite::Join<Hash, uint64_t>{p->hash, p->size};
      ++prehashRefiltered;
      // Entry k is answered otherwise: the tree is walked here.  The entries asked about so far come first in the walk too, and keep
      // their answers, so the filter is asked about each entry once.
      for (uint32_t i = 0; i <= k; i++) {
        std::string_view e = p->path(p->seen[i]);
        given.set(e.data(), uint32_t(e.size()), (i < k ? p->seen[i].kept : d) ? 1 : 2, [&] { return e.data(); }); // `text` is done growing
      }
      answered = answerIt;
    }
  HashSink hs(algo);
  auto update = [&](std::string_view d) { hs.update(d); };
  Sink sink = update;
  const PathFilter &f = answered ? answered : filter;
  NarWriter w{sink, f};
  composite::Text root(path);
  w.noteKept = algo == HashAlgo::SHA256 && nixprefetch::noteRoot(filter ? 'G' : 'H', root.c_str()) && filter;
  w.str("nix-archive-1");
  w.dump(root);
  uint64_t n = hs.bytes();
  return {hs.finish(), n};
}

void restorePath(std::string_view path, std::string_view nar) {
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
    if (str() != s) throw Error(composite::cat("bad NAR: expected '", s, "'"));
  };
  auto node = [&](auto &self, const composite::Text &dst) -> void {
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
      nixsys::CStr tgt(str());
      if (symlink(tgt, dst.c_str()) != 0) throw Error(composite::cat("creating symlink '", dst, "'"));
      expect(")");
    } else if (t == "directory") {
      if (mkdir(dst.c_str(), 0755) != 0) throw Error(composite::cat("creating directory '", dst, "'"));
      while (true) {
        auto tag = str();
        if (tag == ")") break;
        if (tag != "entry") throw Error("bad NAR");
        expect("(");
        expect("name");
        std::string_view name = str(); // a window on `nar`, which outlives the walk
        if (name.empty() || name == "." || name == ".." || name.find('/') != std::string_view::npos)
          throw Error(composite::cat("NAR contains invalid file name '", name, "'"));
        expect("node");
        self(self, composite::cat(dst, '/', name));
        expect(")");
      }
    } else {
      throw Error("bad NAR: unknown file type");
    }
  };
  expect("nix-archive-1");
  node(node, composite::Text(path));
}

//===----------------------------------------------------------------------===//
// Store paths
//===----------------------------------------------------------------------===//

void checkName(std::string_view name) {
  auto q = [&](std::string_view n) { return composite::cat("'", n, "'"); };
  if (name.empty()) throw Error("name must not be empty");
  if (name.size() > 211)
    throw Error(composite::cat("name ", q(name), " must be no longer than 211 characters"));
  if (name[0] == '.') {
    if (name.size() == 1) throw Error(composite::cat("name ", q(name), " is not valid"));
    if (name[1] == '-')
      throw Error(composite::cat("name ", q(name), " is not valid: first dash-separated component must not be '.'"));
    if (name[1] == '.') {
      if (name.size() == 2) throw Error(composite::cat("name ", q(name), " is not valid"));
      if (name[2] == '-')
        throw Error(composite::cat("name ", q(name), " is not valid: first dash-separated component must not be '..'"));
    }
  }
  for (char c : name)
    if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '+' ||
          c == '-' || c == '.' || c == '_' || c == '?' || c == '='))
      throw Error(composite::cat("name ", q(name), " contains illegal character '", c, "'"));
}

composite::Text makeStorePath(std::string_view storeDir, std::string_view type, const Hash &hash,
                              std::string_view name) {
  checkName(name);
  // The fingerprint `type:algo:hex:storeDir:name` and the path `storeDir/nix32-name`, each built in one string.
  std::string_view algo = algoName(hash.algo);
  composite::Text s;
  s.reserve(type.size() + algo.size() + 2 * hash.size() + storeDir.size() + name.size() + 4);
  s.append(type);
  s += ':';
  s += algo;
  s += ':';
  appendBase16(s, hash.bytes, hash.size());
  s += ':';
  s += storeDir;
  s += ':';
  s.append(name);
  Hash h = compressHash(hashString(HashAlgo::SHA256, s), 20);
  composite::Text path;
  path.reserve(storeDir.size() + 34 + name.size());
  path += storeDir;
  path += '/';
  appendNix32(path, h.bytes, 20);
  path += '-';
  path.append(name);
  return path;
}

composite::Text makeType(std::string_view storeDir, std::string_view type, const SortedSet &refs,
                         bool hasSelfRef) {
  composite::Text t(type);
  for (auto &r : refs) {
    t += ":";
    t += r;
  }
  if (hasSelfRef) t += ":self";
  return t;
}

composite::Text makeTextPath(std::string_view storeDir, std::string_view name, const Hash &hash,
                             const SortedSet &refs) {
  return makeStorePath(storeDir, makeType(storeDir, "text", refs, false), hash, name);
}

composite::Text makeFixedOutputPath(std::string_view storeDir, std::string_view name,
                                    FileIngestionMethod method, const Hash &hash,
                                    const SortedSet &refs) {
  if (method == FileIngestionMethod::Text) return makeTextPath(storeDir, name, hash, refs);
  if (method == FileIngestionMethod::NixArchive && hash.algo == HashAlgo::SHA256)
    return makeStorePath(storeDir, makeType(storeDir, "source", refs, false), hash, name);
  if (!refs.empty())
    throw Error(composite::cat("fixed output derivation '", name,
                               "' is not allowed to refer to other store paths."));
  composite::Text payload = composite::cat("fixed:out:", method == FileIngestionMethod::NixArchive ? "r:" : "",
                                           hash.to_string(HashFormat::Base16, true), ":");
  return makeStorePath(storeDir, "output:out", hashString(HashAlgo::SHA256, payload), name);
}

composite::Text outputPathName(std::string_view drvName, std::string_view output) {
  composite::Text s(drvName);
  if (output != "out") {
    s += "-";
    s += output;
  }
  return s;
}

composite::Text makeOutputPath(std::string_view storeDir, std::string_view output, const Hash &drvHash,
                               std::string_view drvName) {
  return makeStorePath(storeDir, composite::cat("output:", output), drvHash,
                       outputPathName(drvName, output));
}

composite::Text hashPlaceholder(std::string_view output) {
  Hash h = hashString(HashAlgo::SHA256, composite::cat("nix-output:", output));
  return composite::cat("/", h.to_string(HashFormat::Nix32, false));
}

bool isInStore(std::string_view storeDir, std::string_view path) {
  return path.size() > storeDir.size() + 1 && path.substr(0, storeDir.size()) == storeDir &&
         path[storeDir.size()] == '/';
}

composite::Text toStorePath(std::string_view storeDir, std::string_view path) {
  if (!isInStore(storeDir, path)) throw Error(composite::cat("path '", path, "' is not in the Nix store"));
  auto slash = path.find('/', storeDir.size() + 1);
  return composite::Text(slash == std::string_view::npos ? path : path.substr(0, slash));
}

bool isStorePath(std::string_view storeDir, std::string_view path) {
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

composite::Text storePathName(std::string_view storePath) {
  composite::Text base = baseNameOf(storePath);
  if (base.size() > 33) return composite::Text(base.substr(33));
  return base;
}

composite::Text storePathHashPart(std::string_view storePath) {
  return composite::Text(baseNameOf(storePath).substr(0, 32));
}

//===----------------------------------------------------------------------===//
// Derivations
//===----------------------------------------------------------------------===//

composite::Text DerivationOutput::methodAlgo() const {
  std::string_view prefix = method == FileIngestionMethod::NixArchive ? "r:"
                            : method == FileIngestionMethod::Text      ? "text:"
                                                                       : "";
  return composite::cat(prefix, algoName(kind == CAFixed ? hash.algo : hashAlgo));
}

composite::Text DerivationOutput::fixedPath(std::string_view storeDir, std::string_view drvName,
                                            std::string_view output) const {
  return makeFixedOutputPath(storeDir, outputPathName(drvName, output), method, hash);
}

bool Derivation::isFixed() const {
  return outputs.size() == 1 && outputs.begin()->first == "out" &&
         outputs.begin()->second.kind == DerivationOutput::CAFixed;
}

/// Appends `s` in quotes with ATerm escapes.  The bytes between two escapes are copied whole: the values of an
/// environment are scripts of kilobytes, and a byte-at-a-time push_back was a fiftieth of a NixOS evaluation.
/// The ATerm escape of `s` (no quotes) written at `w`, which has room for 2 * s.size() bytes; the end of what was written.  Every byte writes
/// either itself or a backslash and its escape letter, chosen by a table and advanced by one or two with no branch on the byte: a script full
/// of newlines and quotes costs no mispredicted branch per line.
static char *escapeInto(char *w, std::string_view s) {
  struct Escapes {
    char e[256] = {};
    constexpr Escapes() { e[uint8_t('"')] = '"'; e[uint8_t('\\')] = '\\'; e[uint8_t('\n')] = 'n'; e[uint8_t('\r')] = 'r'; e[uint8_t('\t')] = 't'; }
  };
  static constexpr Escapes kEsc;
  // Sixteen bytes at a time (the compilers' vector extension: SSE2 or NEON, no intrinsics): a block with none of the five bytes ATerm
  // escapes, as nearly all of a build script is, is copied whole; a block with one goes through the table a byte at a time.
  typedef unsigned char Block __attribute__((vector_size(16)));
  typedef unsigned long long Halves __attribute__((vector_size(16)));
  const char *p = s.data(), *end = p + s.size();
  for (; end - p >= 16; p += 16) {
    Block b;
    std::memcpy(&b, p, 16);
    Block hit = (b == '"') | (b == '\\') | (b == '\n') | (b == '\r') | (b == '\t');
    Halves h = (Halves)hit;
    if ((h[0] | h[1]) == 0) {
      std::memcpy(w, p, 16);
      w += 16;
      continue;
    }
    for (int i = 0; i < 16; i++) {
      unsigned char c = uint8_t(p[i]);
      char e = kEsc.e[c];
      w[0] = e ? '\\' : char(c);
      w[1] = e;
      w += 1 + (e != 0);
    }
  }
  for (; p < end; p++) {
    unsigned char c = uint8_t(*p);
    char e = kEsc.e[c];
    w[0] = e ? '\\' : char(c);
    w[1] = e;
    w += 1 + (e != 0);
  }
  return w;
}

/// Appends `s` in quotes with ATerm escapes.  A Text grows by what is put, so the worst case cannot be written in place first: each run of
/// s (half the buffer, as escaping doubles a byte at most) is escaped into a buffer on the stack and put whole.  Every byte escapes by itself,
/// so where the runs are cut changes nothing.
static void appendEscaped(composite::Text &out, std::string_view s) {
  char buf[4096];
  constexpr size_t kChunk = sizeof buf / 2;
  out += '"';
  for (size_t at = 0; at < s.size(); at += kChunk) {
    std::string_view part = s.substr(at, kChunk);
    out.put(buf, size_t(escapeInto(buf, part) - buf));
  }
  out += '"';
}

composite::Text escapeATermString(std::string_view s) {
  composite::Text r;
  r.reserve(s.size() + 2);
  appendEscaped(r, s);
  return r;
}

namespace {
/// The ATerm text, made into a Text.
struct TextOut {
  composite::Text &s;
  void c(char x) { s += x; }
  void lit(std::string_view v) { s.put(v); }
  void quoted(std::string_view v) { s += '"'; s.put(v); s += '"'; }
  void escaped(std::string_view v) { appendEscaped(s, v); }
  void reserve(size_t n) { s.reserve(s.size() + n); }
};
/// The ATerm text fed to a hash as it is made, through a buffer: a derivation's text (its whole environment) is never kept to be hashed.
struct HashOut {
  HashSink &h;
  char buf[16384];
  size_t n = 0;
  void flush() { if (n) h.update(std::string_view(buf, n)); n = 0; }
  void room(size_t k) { if (n + k > sizeof buf) flush(); }
  void c(char x) { room(1); buf[n++] = x; }
  void lit(std::string_view v) {
    if (v.size() > sizeof buf / 2) { flush(); h.update(v); return; }
    room(v.size());
    std::memcpy(buf + n, v.data(), v.size());
    n += v.size();
  }
  void quoted(std::string_view v) { c('"'); lit(v); c('"'); }
  void escaped(std::string_view v) {
    c('"');
    constexpr size_t kChunk = (sizeof buf) / 2 - 1; // escaping doubles a byte at most
    for (size_t at = 0; at < v.size(); at += kChunk) {
      std::string_view part = v.substr(at, kChunk);
      room(2 * part.size());
      n = size_t(escapeInto(buf + n, part) - buf);
    }
    c('"');
  }
  void reserve(size_t) {}
};

template <class Out>
void unparseTo(const Derivation &d, Out &out, bool maskOutputs, const DrvInputs *actualInputs) {
  const auto &outputs = d.outputs;
  const auto &inputDrvs = d.inputDrvs;
  const auto &inputSrcs = d.inputSrcs;
  const auto &platform = d.platform;
  const auto &builder = d.builder;
  const auto &args = d.args;
  const auto &env = d.env;
  const auto &structuredAttrs = d.structuredAttrs;

  // Note: the store dir is embedded in paths already.
  out.lit("Derive([");
  bool first = true;
  for (auto &[name, o] : outputs) {
    if (!first) out.c(',');
    first = false;
    out.c('(');
    out.quoted(name);
    out.c(',');
    switch (o.kind) {
    case DerivationOutput::InputAddressed:
      out.quoted(maskOutputs ? std::string_view("") : std::string_view(o.path));
      out.lit(",\"\",\"\"");
      break;
    case DerivationOutput::CAFixed:
      out.quoted(maskOutputs ? std::string_view("") : std::string_view(o.path));
      out.c(',');
      out.quoted(o.methodAlgo());
      out.c(',');
      out.quoted(o.hash.to_string(HashFormat::Base16, false));
      break;
    case DerivationOutput::CAFloating:
      out.lit("\"\",");
      out.quoted(o.methodAlgo());
      out.lit(",\"\"");
      break;
    case DerivationOutput::Deferred:
      out.lit("\"\",\"\",\"\"");
      break;
    case DerivationOutput::Impure:
      out.lit("\"\",");
      out.quoted(o.methodAlgo());
      out.lit(",\"impure\"");
      break;
    }
    out.c(')');
  }
  out.lit("],[");
  first = true;
  const auto &inputs = actualInputs ? *actualInputs : inputDrvs;
  for (auto &[path, outs] : inputs) {
    if (!first) out.c(',');
    first = false;
    out.c('(');
    out.quoted(path);
    out.lit(",[");
    bool f2 = true;
    for (auto &o : outs) {
      if (!f2) out.c(',');
      f2 = false;
      out.quoted(o);
    }
    out.lit("])");
  }
  out.lit("],[");
  first = true;
  for (auto &p : inputSrcs) {
    if (!first) out.c(',');
    first = false;
    out.quoted(p);
  }
  out.lit("],");
  out.quoted(platform);
  out.c(',');
  out.escaped(builder);
  out.lit(",[");
  first = true;
  for (auto &a : args) {
    if (!first) out.c(',');
    first = false;
    out.escaped(a);
  }
  out.lit("],[");
  first = true;
  // The environment in key order, with `__json` (the structured attributes, which win over an env entry of that name) at its place in
  // that order: env is a sorted map, so the walk slots it in; nothing is copied and no map is built.
  size_t envBytes = 0;
  for (auto &[k, v] : env) envBytes += k.size() + v.size() + 8;
  if (structuredAttrs) envBytes += structuredAttrs->size() + 16;
  out.reserve(envBytes);
  auto isOutput = [&](std::string_view k) {
    for (auto &[name, o] : outputs)
      if (name == k) return true;
    return false;
  };
  auto entry = [&](std::string_view k, std::string_view v) {
    if (!first) out.c(',');
    first = false;
    out.c('(');
    out.escaped(k);
    out.c(',');
    out.escaped(maskOutputs && isOutput(k) ? std::string_view() : v);
    out.c(')');
  };
  constexpr std::string_view kJson = "__json";
  bool json = structuredAttrs.has_value();
  for (auto &[k, v] : env) {
    if (json && std::string_view(k) >= kJson) { entry(kJson, *structuredAttrs); json = false; }
    if (structuredAttrs && k == kJson) continue;
    entry(k, v);
  }
  if (json) entry(kJson, *structuredAttrs);
  out.lit("])");
}
} // namespace

composite::Text Derivation::unparse(bool maskOutputs, const DrvInputs *actualInputs) const {
  composite::Text s;
  TextOut out{s};
  unparseTo(*this, out, maskOutputs, actualInputs);
  return s;
}

Hash Derivation::hashUnparsed(bool maskOutputs, const DrvInputs *actualInputs) const {
  HashSink h(HashAlgo::SHA256);
  HashOut out{h};
  unparseTo(*this, out, maskOutputs, actualInputs);
  out.flush();
  return h.finish();
}

namespace {
struct ATermParser {
  std::string_view s;
  size_t p = 0;
  [[noreturn]] void fail() { throw Error(composite::cat("invalid derivation (ATerm parse error at offset ", p, ")")); }
  void expect(std::string_view t) {
    if (s.substr(p, t.size()) != t) fail();
    p += t.size();
  }
  bool peek(char c) { return p < s.size() && s[p] == c; }
  composite::Text str() {
    expect("\"");
    composite::Text r;
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
  composite::MutableSeries<composite::Text> strs() {
    composite::MutableSeries<composite::Text> v;
    expect("[");
    while (!peek(']')) {
      v.append(str());
      if (peek(',')) p++;
    }
    expect("]");
    return v;
  }
};
} // namespace

Derivation parseDerivation(std::string_view text, composite::Text name) {
  Derivation d;
  d.name = composite::mv(name);
  ATermParser P{text};
  P.expect("Derive([");
  while (!P.peek(']')) {
    P.expect("(");
    composite::Text id = P.str();
    P.expect(",");
    composite::Text path = P.str();
    P.expect(",");
    composite::Text algo = P.str();
    P.expect(",");
    composite::Text hash = P.str();
    P.expect(")");
    DerivationOutput o;
    if (!algo.empty()) {
      std::string_view a = algo;
      o.method = FileIngestionMethod::Flat;
      if (a.rfind("r:", 0) == 0) { o.method = FileIngestionMethod::NixArchive; a = a.substr(2); }
      else if (a.rfind("text:", 0) == 0) { o.method = FileIngestionMethod::Text; a = a.substr(5); }
      auto ha = parseHashAlgo(a);
      if (!ha) throw Error(composite::cat("unknown hash algorithm '", a, "' in derivation"));
      o.hashAlgo = *ha;
      if (hash == "impure") o.kind = DerivationOutput::Impure;
      else if (!hash.empty()) {
        o.kind = DerivationOutput::CAFixed;
        o.hash = parseHash(hash, *ha);
        o.path = composite::mv(path);
      } else o.kind = DerivationOutput::CAFloating;
    } else if (path.empty()) {
      o.kind = DerivationOutput::Deferred;
    } else {
      o.kind = DerivationOutput::InputAddressed;
      o.path = composite::mv(path);
    }
    d.outputs[id] = composite::mv(o);
    if (P.peek(',')) P.p++;
  }
  P.expect("],[");
  while (!P.peek(']')) {
    P.expect("(");
    composite::Text path = P.str();
    P.expect(",");
    auto outs = P.strs();
    P.expect(")");
    d.inputDrvs[path] = SortedSet(outs.begin(), outs.end());
    if (P.peek(',')) P.p++;
  }
  P.expect("],");
  auto srcs = P.strs();
  d.inputSrcs = SortedSet(srcs.begin(), srcs.end());
  P.expect(",");
  d.platform = P.str();
  P.expect(",");
  d.builder = P.str();
  P.expect(",");
  d.args = P.strs();
  P.expect(",[");
  while (!P.peek(']')) {
    P.expect("(");
    composite::Text k = P.str();
    P.expect(",");
    composite::Text v = P.str();
    P.expect(")");
    if (k == "__json") d.structuredAttrs = composite::mv(v);
    else d.env[k] = composite::mv(v);
    if (P.peek(',')) P.p++;
  }
  P.expect("])");
  return d;
}

composite::Text derivationToJSON(std::string_view storeDir, std::string_view drvPath,
                                 const Derivation &drv) {
  composite::Text j = composite::cat("{", jsonEscape(drvPath), ":{");
  j += "\"args\":[";
  for (size_t i = 0; i < drv.args.size(); i++) {
    if (i) j += ',';
    j += jsonEscape(drv.args[i]);
  }
  j += "],\"builder\":";
  j += jsonEscape(drv.builder);
  j += ",\"env\":{";
  bool first = true;
  auto env = drv.env;
  if (drv.structuredAttrs) env["__json"] = drv.structuredAttrs->clone();
  for (auto &[k, v] : env) {
    if (!first) j += ',';
    j += jsonEscape(k);
    j += ':';
    j += jsonEscape(v);
    first = false;
  }
  j += "},\"inputDrvs\":{";
  first = true;
  for (auto &[p, outs] : drv.inputDrvs) {
    if (!first) j += ',';
    j += jsonEscape(p);
    j += ":{\"dynamicOutputs\":{},\"outputs\":[";
    bool f2 = true;
    for (auto &o : outs) {
      if (!f2) j += ',';
      j += jsonEscape(o);
      f2 = false;
    }
    j += "]}";
    first = false;
  }
  j += "},\"inputSrcs\":[";
  first = true;
  for (auto &p : drv.inputSrcs) {
    if (!first) j += ',';
    j += jsonEscape(p);
    first = false;
  }
  j += "],\"name\":";
  j += jsonEscape(drv.name);
  j += ",\"outputs\":{";
  first = true;
  for (auto &[n, o] : drv.outputs) {
    if (!first) j += ',';
    j += jsonEscape(n);
    j += ":{";
    first = false;
    switch (o.kind) {
    case DerivationOutput::InputAddressed:
      j += "\"path\":";
      j += jsonEscape(o.path);
      break;
    case DerivationOutput::CAFixed:
      j += "\"hash\":";
      j += jsonEscape(o.hash.to_string(HashFormat::Base16, false));
      j += ",\"hashAlgo\":";
      j += jsonEscape(o.methodAlgo());
      j += ",\"path\":";
      j += jsonEscape(o.path);
      break;
    case DerivationOutput::CAFloating:
    case DerivationOutput::Impure:
      j += "\"hashAlgo\":";
      j += jsonEscape(o.methodAlgo());
      break;
    case DerivationOutput::Deferred: break;
    }
    j += "}";
  }
  j += "},\"system\":";
  j += jsonEscape(drv.platform);
  j += "}}";
  (void)storeDir;
  return j;
}

} // namespace nixstore
