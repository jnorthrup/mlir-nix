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

#include <algorithm>
#include <atomic>
#include <string_view>
#include <thread>
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
/// The scan of a large source runs on a thread of its own, ahead of the parse that reads the table (layer 1 shoots
/// ahead; layers 2 and 3 take each band once it has closed).  The storage is reserved for the most bands the source can
/// hold, so no row moves while it is read; `through` says how far the scan has read (every band opening before it is
/// one of the first `opened` rows), and a band's span is stored last when it closes: a span whose second() is 0 is a
/// band still open.  The reads below wait for what they need; after a scan on the parse's own thread they never do.
struct Bands {
  composite::Cursor<join::TwInt, uint8_t, join::TwInt> rows{BandCol{}};
  composite::MutableSeries<uint32_t> ends;
  static constexpr uint32_t kDone = ~0u, kNone = ~0u;
  std::atomic<uint32_t> through{kDone}, opened{0};
  std::atomic<bool> balanced{true}; // the verdict, once `through` is kDone
  /// What a reader sees when the scan ended without balancing the source while it waited on a band.
  struct Refused {};

  uint32_t size() const { return through.load(std::memory_order_acquire) == kDone ? rows.size() : opened.load(std::memory_order_acquire); }
  /// Empty the table, open for a scan of the next source, and keep its storage.
  void clear() {
    rows.clear();
    ends.cells.clear();
    opened.store(0, std::memory_order_relaxed);
    through.store(0, std::memory_order_release);
  }
  /// The scan has ended, with this verdict: every wait is over.
  bool done(bool ok) { balanced = ok; through = kDone; return ok; }
  /// Room for every band and every end a source of n bytes can hold (a band takes two bytes, an end one), so that a scan
  /// on another thread never moves a row; the pages a scan does not reach are never touched.
  void reserveFor(size_t n) {
    rows.reserve(n / 2 + 2);
    ends.cells.reserve(n + 1);
  }
  static uint64_t word(const join::TwInt &s, std::memory_order o) { return std::atomic_ref(const_cast<uint64_t &>(s.raw)).load(o); }
  /// Whether band i has closed, without waiting.
  bool closed(uint32_t i) const { return join::TwInt(word(rows.col<BandCol::Span>()[i], std::memory_order_acquire)).second(); }
  /// The span of band i once it has closed.
  join::TwInt span(uint32_t i) const {
    for (bool done = false;; std::this_thread::yield()) {
      if (join::TwInt s(word(rows.col<BandCol::Span>()[i], std::memory_order_acquire)); s.second()) return s;
      if (done) throw Refused{};
      done = through.load(std::memory_order_acquire) == kDone;
    }
  }
  Kind kind(uint32_t i) const { return Kind(rows.col<BandCol::Kind>()[i]); }
  /// The ends of the statements of band i, in order, once it has closed: a view of `ends`.
  auto stmts(uint32_t i) const {
    span(i);
    join::TwInt s = rows.col<BandCol::Stmts>()[i];
    return composite::series(ends.cells.data() + s.first(), s.second());
  }
  /// The band that opens at `off`, or kNone when none does.
  uint32_t at(uint32_t off) const {
    while (through.load(std::memory_order_acquire) <= off) std::this_thread::yield();
    const join::TwInt *c = rows.col<BandCol::Span>().cells.data(), *e = c + size();
    auto it = std::lower_bound(c, e, off, [](const join::TwInt &s, uint32_t o) {
      return join::TwInt(word(s, std::memory_order_relaxed)).first() < o;
    });
    return it != e && join::TwInt(word(*it, std::memory_order_relaxed)).first() == off ? uint32_t(it - c) : kNone;
  }
  bool operator==(const Bands &o) const { return rows.cols == o.rows.cols && ends == o.ends; }
  /// The table of another, at its size (the storage reserved for a scan ahead stays with the other).
  void copyFrom(const Bands &o) { rows.cols = o.rows.cols, ends = o.ends, done(o.balanced); }
};

/// Bands being written, as the scan or the lexer meets delimiters: the bands still open, and for each of them (and the
/// source) the semicolons its `with`s and `assert`s are still owed, and the qualified ends met so far.
struct Layers {
  explicit Layers(Bands &b) : out(b) {}
  void open(Kind k, size_t at) {
    stack.push_back({out.rows.append(join::TwInt(uint32_t(at), 0), uint8_t(k), join::TwInt()), 0, uint32_t(pend.size())});
    out.opened.store(out.rows.size(), std::memory_order_release);
    out.through.store(uint32_t(at) + 1, std::memory_order_release);
  }
  /// Close the innermost band at `at`; it must be of kind `a` or `b`.
  bool close(Kind a, Kind b, size_t at) {
    if (stack.empty() || (out.kind(stack.back().row) != a && out.kind(stack.back().row) != b)) return false;
    Open o = stack.back();
    stack.pop_back();
    join::TwInt &span = out.rows.col<BandCol::Span>()[o.row];
    out.rows.col<BandCol::Stmts>()[o.row] = join::TwInt(out.ends.size(), uint32_t(pend.size() - o.from));
    out.ends.cells.insert(out.ends.cells.end(), pend.begin() + o.from, pend.end());
    pend.resize(o.from);
    std::atomic_ref<uint64_t>(span.raw).store(join::TwInt(span.first(), uint32_t(at)).raw, std::memory_order_release);
    out.through.store(uint32_t(at), std::memory_order_release);
    return true;
  }
  /// A `with` or an `assert`: the next semicolon of its band is its own.
  void owe() { ++(stack.empty() ? owedRoot : stack.back().owed); }
  void semi(size_t at) {
    uint32_t &owed = stack.empty() ? owedRoot : stack.back().owed;
    if (owed) owed--;
    else if (!stack.empty()) pend.push_back(uint32_t(at));
  }
  void comma(size_t at) {
    if (!stack.empty()) pend.push_back(uint32_t(at));
  }
  bool inside(Kind k) const { return !stack.empty() && out.kind(stack.back().row) == k; }
  bool balanced() const { return stack.empty(); }

  struct Open {
    uint32_t row, owed, from; // the band, the semicolons it is owed, where its ends begin in `pend`
  };
  Bands &out;
  std::vector<Open> stack;
  std::vector<uint32_t> pend;
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
