//===- Source.cpp - The immutable bytes of one input -------------------------===//

#include "Nix/Source.h"
#include <fcntl.h>
#include "Composite/Mutable.h"
#include "Nix/Os.h"
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

namespace nixfe {

/// A Source is never freed (a Name, and so the IR, may be a slice of it), nor an Origin: both are listed here, so a leak checker sees
/// them reachable, and the list is never walked.
static nixsys::Lock kept;
static composite::MutableSeries<const void *> *keptAll = new composite::MutableSeries<const void *>();
template <class T> static T *retain(T *s) {
  nixsys::Held g(kept);
  keptAll->append(s);
  return s;
}

Origin *newOrigin() { return retain(new Origin()); }

const Source *Source::fromString(std::string text) {
  Source *s = new Source();
  s->owned_ = std::move(text);
  s->data_ = s->owned_.data();
  s->size_ = s->owned_.size();
  return retain(s);
}

const Source *Source::mapFile(const std::string &path) {
  int fd = ::open(path.c_str(), O_RDONLY | O_CLOEXEC);
  if (fd < 0) return nullptr;
  struct stat st;
  if (::fstat(fd, &st) != 0 || !S_ISREG(st.st_mode) || st.st_size <= 0 || uint64_t(st.st_size) >= UINT32_MAX) {
    ::close(fd);
    return nullptr;
  }
  void *m = ::mmap(nullptr, size_t(st.st_size), PROT_READ, MAP_PRIVATE, fd, 0);
  ::close(fd);
  if (m == MAP_FAILED) return nullptr;
  Source *s = new Source();
  s->map_ = m;
  s->data_ = static_cast<const char *>(m);
  s->size_ = size_t(st.st_size);
  return retain(s);
}

void printLiteralString(std::ostream &str, std::string_view s) {
  str << '"';
  for (size_t i = 0; i < s.size(); i++) {
    char c = s[i];
    if (c == '"' || c == '\\') str << '\\' << c;
    else if (c == '\n') str << "\\n";
    else if (c == '\r') str << "\\r";
    else if (c == '\t') str << "\\t";
    else if (c == '$' && i + 1 < s.size() && s[i + 1] == '{') str << "\\$";
    else str << c;
  }
  str << '"';
}

static bool isReservedKeyword(std::string_view s) {
  static const char *kws[] = {"if", "then", "else", "assert", "with", "let", "in", "rec", "inherit"};
  for (auto *k : kws)
    if (s == k) return true;
  return false;
}

bool isValidIdentifier(std::string_view s) {
  if (s.empty() || isReservedKeyword(s)) return false;
  char c = s[0];
  if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_')) return false;
  for (char c : s)
    if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') ||
          c == '_' || c == '\'' || c == '-'))
      return false;
  return true;
}

void printIdentifier(std::ostream &str, std::string_view s) {
  if (s.empty()) { str << "\"\""; return; }
  if (isReservedKeyword(s)) { str << '"' << s << '"'; return; }
  if (!isValidIdentifier(s)) { printLiteralString(str, s); return; }
  str << s;
}

Source::~Source() {
  if (map_) ::munmap(map_, size_);
}

} // namespace nixfe
