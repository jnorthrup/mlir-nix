//===- Confix.h - The delimiters of a Nix source, found without tokens ---*- C++ -*-===//
//
// A source file nests: `{ ... }`, `[ ... ]`, `( ... )`, a string, an indented string, an interpolation `${ ... }`.
// Each is a band: the offsets of its opening and closing delimiters.  Finding the bands is a scan of the
// lexical structure, far cheaper than lexing, because it builds no token, no text and no position; and what it
// finds is what a lazy parse needs, since a band that nothing demands never has to be lexed, parsed or lowered.
// This is TrikeShed's Confix applied to Nix: the index first, the values when something asks.
//
// The scan follows the lexer's own rules (Nix/LexRules.h) and its state machine, so it agrees with it on every
// input; Parser.cpp's lexBands derives the same table from the lexer's tokens, and `mlnix-parse -b` compares the
// two over a corpus.
//
//===----------------------------------------------------------------------===//
#ifndef NIX_CONFIX_H
#define NIX_CONFIX_H

#include "Composite/Pack.h"
#include "Composite/Series.h"
#include "Nix/AST.h"
#include "mlir/Support/LLVM.h"
#include "llvm/Support/raw_ostream.h"

#include "NixDialect/NixSyntaxEnums.h.inc"

#include <string_view>

namespace nixfe::confix {

/// The kind of a band is the character that opens it, `$` for an interpolation and `'` for an indented string
/// (BandKind, generated from NixDialect/NixSyntax.td with the token kinds).
using enum BandKind;
using Kind = BandKind;

/// The bands of one source in the order they open (an outer band before the bands inside it): a column of
/// spans (opening offset j closing offset) and a column of kinds.  The opening delimiter of a band is at
/// `first`, its closing delimiter at `second` (a string's closing quote, an indented string's first closing quote).
struct Bands {
  composite::Cursor<join::TwInt, uint8_t> rows{{"span", "kind"}};
  uint32_t size() const { return rows.size(); }
  /// Empty the table and keep its storage, for a scan of the next source.
  void clear() {
    rows.col<0>().cells.clear();
    rows.col<1>().cells.clear();
  }
  join::TwInt span(uint32_t i) const { return rows.col<0>()[i]; }
  Kind kind(uint32_t i) const { return Kind(rows.col<1>()[i]); }
};

/// Scan the lexical structure of `src`.  False when it does not balance (a string or comment that does not end, a
/// closer that matches nothing, a path ending in a slash): the bands are then not to be used, and the lexer
/// will say what is wrong.
bool scan(std::string_view src, Bands &out);

/// The same table from the tokens of the real lexer.  The oracle of `scan`; it costs a lex.
bool lexBands(std::shared_ptr<Origin> origin, const ParseOptions &opts, Bands &out);

} // namespace nixfe::confix

#endif // NIX_CONFIX_H
