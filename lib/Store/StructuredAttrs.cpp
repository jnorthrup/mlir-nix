//===- StructuredAttrs.cpp - __structuredAttrs support for builders -------===//
//
// .attrs.json / .attrs.sh exactly as upstream's ParsedDerivation does, all of it in lowered/nixstore/StructuredAttrsOps.mlir
// (__json read by confix.checked, no DOM; the members sorted, the placeholders rewritten, both files one combineAll each,
// drained once), and rewritePlaceholders (runBuilder's environment and arguments) by the same rewrite.  Here: the record's
// arrays, the rooms the bytes land in, and the words of the two errors.
//
//===----------------------------------------------------------------------===//

#include "Nix/Store.h"

namespace nixstore {

/// The rooms the lowered writer asks for: decoded and rewritten strings (alive until the files are made), and the files.
struct SaRooms {
  composite::MutableSeries<composite::Text> rooms;
  composite::Text out[2];
};

extern "C" {
// confix.checked's request for more rows (0) or a deeper stack (1), for builtins.fromJSON's record as for this one
void nixev_json_grow(JsonRec *r, int64_t stack) { stack ? r->size(r->w[3], 2 * r->w[11]) : r->size(2 * r->w[3], r->w[11]); }
char *nixsa_room(SaRooms *c, uint64_t n) { c->rooms.append(composite::Text()); c->rooms.back().resize(n); return c->rooms.back().begin(); }
char *nixsa_out(SaRooms *c, int64_t k, uint64_t n) { c->out[k].resize(n); return c->out[k].begin(); }
int32_t nixstore_ts_sattrs(SaRooms *c, JsonRec *r, const void *outs, int64_t nout, const void *rws, int64_t nrw);
const char *nixstore_ts_rewrite(SaRooms *c, const char *p, int64_t n, const void *rws, int64_t nrw, int64_t *len);
}
// the outputs and the rewrites go over as their rows, read in place
static_assert(sizeof(SortedMap<composite::Text>::Row) == 32 && sizeof(composite::Text) == 16, "the rows nx_sa_row reads");

/// Produce (.attrs.json, .attrs.sh) for a structured-attrs derivation.
composite::Join<composite::Text, composite::Text> structuredAttrsFiles(std::string_view json,
                                                         const SortedMap<composite::Text> &outputs,
                                                         const SortedMap<composite::Text> &rewrites) {
  if (json.size() >= 0xFFFFFFFFull) throw Error("invalid structured attributes JSON"); // the spans are 32-bit
  JsonRec r;
  r.w[0] = uint64_t(json.data()), r.w[1] = json.size(), r.w[15] = 1; // 15: a NUL or an integer past 2^63 is a value here
  r.size(json.size() / 8 + 16, 16);
  SaRooms c;
  if (int32_t s = nixstore_ts_sattrs(&c, &r, outputs.rows.data(), int64_t(outputs.size()), rewrites.rows.data(), int64_t(rewrites.size())))
    throw Error(s == 1 ? "invalid structured attributes JSON" : "structured attributes must be a JSON object");
  return {composite::mv(c.out[0]), composite::mv(c.out[1])};
}

composite::Text rewritePlaceholders(std::string_view s, const SortedMap<composite::Text> &rewrites) {
  SaRooms c;
  int64_t n = 0;
  const char *p = nixstore_ts_rewrite(&c, s.data(), int64_t(s.size()), rewrites.rows.data(), int64_t(rewrites.size()), &n);
  return c.rooms.empty() ? composite::Text(p, size_t(n)) : composite::mv(c.rooms.back()); // the last room is the whole string
}

} // namespace nixstore
