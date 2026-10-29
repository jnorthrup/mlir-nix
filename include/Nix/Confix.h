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
#include "Nix/Source.h"
#include "mlir/Support/LLVM.h"
#include "llvm/Support/raw_ostream.h"

#include "NixDialect/NixSyntaxEnums.h.inc"
#include "Composite/TrikeShedEnums.h.inc"

#include "llvm/ADT/DenseMap.h"

#include <algorithm>
#include <string_view>
#include <vector>

namespace nixfe::confix {

/// The kind of a band is the character that opens it, `$` for an interpolation and `'` for an indented string
/// (BandKind, generated from NixDialect/NixSyntax.td with the token kinds).
using enum BandKind;
using Kind = BandKind;

/// The bands of one source in the order they open (an outer band before the bands inside it): a column of
/// spans (opening offset j closing offset), a column of kinds, and a column of statements (layer 1 of
/// NixDialect/NixSyntax.td): the qualified semicolons and commas of each band, as `first j count` into `ends`, where a
/// band's are together and in order.  The opening delimiter of a band is at `first`, its closing delimiter at `second`
/// (a string's closing quote, an indented string's first closing quote, the `in` of a `let`).
///
/// The parser scans a band when it first needs the names it binds (a `let`, a `rec` set, a formals list, a set a binding
/// after a `rec` literal extends): from the band's opening delimiter to its closing one, inner bands included, and no
/// further.  The rest of the source is never scanned: 24.3% of the bytes the toplevel reads are inside such bands.  A
/// band already met is found by where it opens; a scan that runs over one again adds a second row the lookup ignores.
struct Bands {
  composite::Cursor<join::TwInt, uint8_t, join::TwInt> rows{BandCol{}};
  composite::MutableSeries<uint32_t> ends;
  llvm::DenseMap<uint32_t, uint32_t> opening; // where a band opens: its row
  std::string_view src;                       // the source of the rows: what `need` scans
  static constexpr uint32_t kNone = ~0u;

  uint32_t size() const { return rows.size(); }
  /// Empty the table for the source `s` and keep its storage.
  void clear(std::string_view s = {}) {
    rows.clear();
    ends.cells.clear();
    opening.clear();
    src = s;
  }
  join::TwInt span(uint32_t i) const { return rows.col<BandCol::Span>()[i]; }
  Kind kind(uint32_t i) const { return Kind(rows.col<BandCol::Kind>()[i]); }
  /// The ends of the statements of band i, in order: a view of `ends`.
  auto stmts(uint32_t i) const {
    join::TwInt s = rows.col<BandCol::Stmts>()[i];
    return composite::series(ends.cells.data() + s.first(), s.second());
  }
  /// The band that opens at `off`, or kNone when no scan has met one there.
  uint32_t at(uint32_t off) const {
    auto it = opening.find(off);
    return it == opening.end() ? kNone : it->second;
  }
  /// The band that opens at `off`, scanned now if no scan has met it: kNone if none opens there, or if the source does not
  /// balance from there (the parser says what is wrong when it gets there).
  uint32_t need(uint32_t off);
  bool operator==(const Bands &o) const { return rows.cols == o.rows.cols && ends == o.ends; }
};

/// Bands being written, as the scan or the lexer meets delimiters: the bands still open, and for each of them (and the
/// source) the semicolons its `with`s and `assert`s are still owed, and the qualified ends met so far.
struct Layers {
  explicit Layers(Bands &b) : out(b) {}
  void open(Kind k, size_t at) {
    stack.append({out.rows.append(join::TwInt(uint32_t(at), 0), uint8_t(k), join::TwInt()), 0, uint32_t(pend.size())});
    out.opening.try_emplace(uint32_t(at), stack.back().row);
  }
  /// Close the innermost band at `at`; it must be of kind `a` or `b`.
  bool close(Kind a, Kind b, size_t at) {
    if (stack.empty() || (out.kind(stack.back().row) != a && out.kind(stack.back().row) != b)) return false;
    Open o = stack.back();
    stack.pop();
    out.rows.col<BandCol::Span>()[o.row] = join::TwInt(out.span(o.row).first(), uint32_t(at));
    out.rows.col<BandCol::Stmts>()[o.row] = join::TwInt(out.ends.size(), uint32_t(pend.size() - o.from));
    out.ends.cells.insert(out.ends.cells.end(), pend.begin() + o.from, pend.end());
    pend.resize(o.from);
    return true;
  }
  /// A `with` or an `assert`: the next semicolon of its band is its own.
  void owe() { ++(stack.empty() ? owedRoot : stack.back().owed); }
  void semi(size_t at) {
    uint32_t &owed = stack.empty() ? owedRoot : stack.back().owed;
    if (owed) owed--;
    else if (!stack.empty()) pend.append(uint32_t(at));
  }
  void comma(size_t at) {
    if (!stack.empty()) pend.append(uint32_t(at));
  }
  bool inside(Kind k) const { return !stack.empty() && out.kind(stack.back().row) == k; }
  bool balanced() const { return stack.empty(); }

  struct Open {
    uint32_t row, owed, from; // the band, the semicolons it is owed, where its ends begin in `pend`
  };
  Bands &out;
  composite::MutableSeries<Open> stack;
  composite::MutableSeries<uint32_t> pend;
  uint32_t owedRoot = 0;
};

/// Scan the lexical structure of `src`.  False when it does not balance (a string or comment that does not end, a
/// closer that matches nothing, a path ending in a slash): the bands are then not to be used, and the lexer
/// will say what is wrong.
bool scan(std::string_view src, Bands &out);

/// The same table from the tokens of the real lexer.  The oracle of `scan`; it costs a lex.
bool lexBands(std::shared_ptr<Origin> origin, const ParseOptions &opts, Bands &out);

} // namespace nixfe::confix

#endif // NIX_CONFIX_H
