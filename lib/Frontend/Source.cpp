//===- Source.cpp - The immutable bytes of one input -------------------------===//

#include "Nix/Source.h"
#include <fcntl.h>
#include <stdio.h>
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

const Source *Source::fromString(composite::Text text) {
  Source *s = new Source();
  s->owned_ = composite::mv(text);
  s->data_ = s->owned_.data();
  s->size_ = s->owned_.size();
  return retain(s);
}

const Source *Source::mapFile(std::string_view path) {
  int fd = ::open(nixsys::CStr(path), O_RDONLY | O_CLOEXEC);
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

// The escaping of a Nix string literal is hollowed into lowered/nixfe/LiteralString.mlir (trikeshed.combineAll /
// slice / at / text / combine / drain over a constant escape table), lowered by --trikeshed-lower-cursors and linked
// into NixFrontend (mlnix-parse links it alone).  The entry drains into room reserved here (2 + 2 n: two quotes, at
// most two bytes a byte) and returns how many it wrote; the count is adopted (resize before, truncate after).
extern "C" size_t nixfe_ts_litstr(const char *p, size_t n, char *into, size_t cap);
void printLiteralString(composite::Text &out, std::string_view s) {
  size_t at = out.size(), room = 2 + 2 * s.size();
  out.resize(at + room);
  out.truncate(at + nixfe_ts_litstr(s.data(), s.size(), out.begin() + at, room));
}

void printFloat(composite::Text &out, double d) {
  char buf[64];
  int n = snprintf(buf, sizeof buf, "%g", d);
  out.put(buf, uint32_t(n));
}

composite::Text fixedFloat(double d) {
  char buf[512]; // "%f" of a finite double is at most 317 bytes: a sign, 309 digits, a point, six decimals
  int n = snprintf(buf, sizeof buf, "%f", d);
  return composite::Text(buf, size_t(n) < sizeof buf ? size_t(n) : sizeof buf - 1);
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

void printIdentifier(composite::Text &out, std::string_view s) {
  if (s.empty()) { out.put("\"\""); return; }
  if (isReservedKeyword(s)) { out.put('"').put(s.data(), uint32_t(s.size())).put('"'); return; }
  if (!isValidIdentifier(s)) { printLiteralString(out, s); return; }
  out.put(s.data(), uint32_t(s.size()));
}

Source::~Source() {
  if (map_) ::munmap(map_, size_);
}

} // namespace nixfe
