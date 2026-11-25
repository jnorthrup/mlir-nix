//===- LexRules.h - The input the lexer and the Confix scan read -----------*- C++ -*-===//
//
// The lexer (Parser.cpp) and the Confix scan (Confix.cpp) must agree on where every token begins and ends, down to
// which of two rules wins a tie.  The rules live in one place: lowered/kursive/LexDefault.mlir, the default state's
// longest match written in the kursive combinators (group g is Rule g - 1), walked by mlir::kursive::lexDefault
// (nixfe_confix_match is its bridge).  This header holds the view of the input they read and no rule.
//
//===----------------------------------------------------------------------===//
#ifndef NIX_LEXRULES_H
#define NIX_LEXRULES_H

#include <stddef.h>
#include <string_view>

namespace nixfe::lex {

/// The input, immutable, and its bounds-checked byte reads ('\0' past the end).
struct Rules {
  std::string_view src;
  explicit Rules(std::string_view s) : src(s) {}

  char at(size_t i) const { return i < src.size() ? src[i] : '\0'; }
  bool eof(size_t i) const { return i >= src.size(); }
};

} // namespace nixfe::lex

#endif // NIX_LEXRULES_H
