//===- Confix.cpp - The scan of a Nix source's delimiters -----------------===//
//
// The scan is the confix dialect's Nix scanner: confix.bands (include/NixDialect/Confix.td), whose body is
// lowered/nixfrontend/ConfixScan.mlir, lowered at build time and linked into NixFrontend.
// It is the lexer's state machine (Parser.cpp: DEFAULT, STRING, IND_STRING, INPATH, INPATH_SLASH, with the same
// stack) without tokens: only the transitions and the delimiters are kept, the character classes as tables.  This
// file is the bridge: it sizes the Bands storage, calls confix_scan_nix and adopts the rows it wrote.  The
// longest-match choice among the rules that can begin a token stays in Nix/LexRules.h, shared with the lexer, and
// is called back per general token (nixfe_confix_match).
//
//===----------------------------------------------------------------------===//

#include "Composite/Mutable.h"
#include "Nix/Confix.h"
#include "Nix/LexRules.h"

#include <stddef.h>

namespace nixfe::confix {

namespace {

/// The record confix_scan_nix reads and writes (Confix.td's confix.bands): the source, where the scan starts and
/// whether it is rooted (a scan from `need`), the band columns and ends to fill, their counts (in: already met, out:
/// after the scan) and their room.  Every field is 8 bytes, in this order.
struct ScanRec {
  const char *src;
  uint64_t n, start, rooted;
  uint64_t *span;
  uint8_t *kind;
  uint64_t *stmts;
  uint32_t *ends;
  uint64_t rows, nends, rowCap, endCap;
};
static_assert(sizeof(join::TwInt) == 8 && sizeof(ScanRec) == 96, "the record and TwInt are the dialect's layout");
static_assert(offsetof(ScanRec, span) == 32 && offsetof(ScanRec, rows) == 64, "the record's fields are 8 bytes apart");

extern "C" int32_t confix_scan_nix(ScanRec *rec);

/// The lexer's own choice among the rules that can begin at i (LexRules.h): the match's length in the high 32 bits,
/// its Rule in the low.
extern "C" uint64_t nixfe_confix_match(const char *src, uint64_t n, uint64_t i) {
  lex::Rules r(std::string_view(src, n));
  lex::Match m = r.matchDefault(i, i < n ? src[i] : '\0');
  return (uint64_t(m.len) << 32) | uint32_t(m.rule);
}

/// Scan from `start` into the bands, growing the storage and scanning again when it runs out of room (the status 2,
/// as confix.scan's YAML retry on Room).  The rows are adopted as the scan wrote them, a failure's partial rows too
/// (the bands are then not to be used); the opening map is rebuilt from them, first row at an offset winning.
bool runScan(std::string_view src, Bands &b, uint64_t start, bool rooted) {
  if (src.size() >= UINT32_MAX) return false; // segments are 32-bit
  auto &span = b.rows.col<BandCol::Span>();
  auto &kind = b.rows.col<BandCol::Kind>();
  auto &stmts = b.rows.col<BandCol::Stmts>();
  const uint64_t r0 = b.rows.size(), e0 = b.ends.size();
  uint64_t cap = src.size() / 48 + 16; // about one band per 56 bytes of nixpkgs
  for (;;) {
    b.rows.reserve(r0 + cap);
    b.ends.reserve(e0 + cap * 4 + 16);
    ScanRec rec{src.data(), src.size(), start, rooted ? 1u : 0u, reinterpret_cast<uint64_t *>(span.base()),
                kind.base(), reinterpret_cast<uint64_t *>(stmts.base()), b.ends.base(),
                r0, e0, r0 + cap, e0 + cap * 4 + 16};
    int32_t st = confix_scan_nix(&rec);
    if (st == 2) { cap *= 2; continue; }
    span.n = uint32_t(rec.rows);
    kind.n = uint32_t(rec.rows);
    stmts.n = uint32_t(rec.rows);
    b.ends.n = uint32_t(rec.nends);
    for (uint64_t k = r0; k < rec.rows; k++) b.opening.try_emplace(uint32_t(rec.span[k] >> 32), uint32_t(k));
    return st == 0;
  }
}

} // namespace

bool scan(std::string_view src, Bands &out) {
  out.src = src;
  return runScan(src, out, 0, false);
}

uint32_t Bands::need(uint32_t off) {
  if (uint32_t r = at(off); r != kNone) return r;
  return runScan(src, *this, off, true) ? at(off) : kNone;
}

} // namespace nixfe::confix

// The names and lookups of the kinds of tokens and bands, generated from NixDialect/NixSyntax.td.
#include "llvm/ADT/StringSwitch.h"
#include "NixDialect/NixSyntaxEnums.cpp.inc"
#include "Composite/TrikeShedEnums.cpp.inc"
