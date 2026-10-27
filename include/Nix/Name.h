//===- Name.h - Text an op refers to, held by reference ----------*- C++ -*-===//
//
// A name, a string literal or a path in the IR is a Name: a pointer and a length into bytes that are alive for the
// whole run, not an attribute.  The context neither hashes nor uniques it (a uniqued StringAttr was a hash, a probe
// and, the first time, an allocation and a copy per name, a twentieth of the evaluation), so lowering a name is a
// 16-byte store; and two equal names are two Names, which nothing needs to be one.
//
// The bytes are either a slice of an input that is never unmapped, or a copy made by persist() in an arena that is
// never freed.  The null Name (no bytes) means "no name"; in an attribute path it is the computed component.
//
// `symbol` is the evaluator's Symbol for the text, plus one, written by the first evaluation that asks for it
// (0 = not yet).  A name in code that nobody runs is therefore never hashed at all, and one that runs is hashed once
// per op, not once per evaluation.  It belongs to the one EvalState of the process.
//
//===----------------------------------------------------------------------===//
#ifndef NIX_NAME_H
#define NIX_NAME_H

#include "llvm/ADT/Hashing.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/Support/Allocator.h"
#include "llvm/Support/ErrorHandling.h"
#include <cstdint>
#include <cstring>
#include <string>

namespace nixfe {

struct Name {
  const char *data = nullptr;
  uint32_t size = 0;
  mutable uint32_t symbol = 0; // evaluator Symbol + 1, 0 until asked for

  Name() = default;
  /// Text that is already alive for the whole run (a slice of an input that stays mapped).
  static Name of(llvm::StringRef s) { return s.empty() ? Name("", 0) : Name(s.data(), s.size()); }
  /// A copy of `s` that is.  One memcpy into a bump arena of the calling thread, which is never freed.
  static Name persist(llvm::StringRef s) {
    if (s.empty()) return Name("", 0);
    if (s.size() > UINT32_MAX) llvm::report_fatal_error("a name or literal of 4 GiB or more");
    static thread_local llvm::BumpPtrAllocator *arena = new llvm::BumpPtrAllocator();
    char *p = static_cast<char *>(arena->Allocate(s.size(), 1));
    std::memcpy(p, s.data(), s.size());
    return Name(p, static_cast<uint32_t>(s.size()));
  }

  llvm::StringRef str() const { return {data, size}; }
  std::string toString() const { return str().str(); }
  bool isNull() const { return data == nullptr; }
  /// Same bytes; the null Name is not the empty one.
  bool operator==(const Name &o) const { return isNull() == o.isNull() && str() == o.str(); }
  bool operator!=(const Name &o) const { return !(*this == o); }

  Name(const char *d, size_t n) : data(d), size(static_cast<uint32_t>(n)) {}
};

inline llvm::hash_code hash_value(const Name &n) { return llvm::hash_value(n.str()); }

} // namespace nixfe

#endif // NIX_NAME_H
