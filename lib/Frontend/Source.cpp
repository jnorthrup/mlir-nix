//===- Source.cpp - The immutable bytes of one input -------------------------===//

#include "Nix/AST.h"
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

namespace nixfe {

std::shared_ptr<const Source> Source::fromString(std::string text) {
  std::shared_ptr<Source> s(new Source());
  s->owned_ = std::move(text);
  s->data_ = s->owned_.data();
  s->size_ = s->owned_.size();
  return s;
}

std::shared_ptr<const Source> Source::mapFile(const std::string &path) {
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
  std::shared_ptr<Source> s(new Source());
  s->map_ = m;
  s->data_ = static_cast<const char *>(m);
  s->size_ = size_t(st.st_size);
  return s;
}

Source::~Source() {
  if (map_) ::munmap(map_, size_);
}

} // namespace nixfe
