//===- Eval.cpp - Lazy evaluator over the nix dialect ---------------------===//

#include <sys/resource.h>
#include "Composite/Folds.h"
#include "Composite/Mutable.h"
#include "Nix/Prefetch.h"
#include "Nix/Eval.h"
#include "Nix/Numbers.h"
#include "Nix/Os.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Pass/PassRegistry.h"
#include "mlir/Transforms/Passes.h"
#include "llvm/Support/Format.h"
#include "llvm/Support/MemoryBuffer.h"
#include "Nix/MLIRGen.h"
#include "NixDialect/Son.h"

#include "mlir/IR/Builders.h"
#include "mlir/Parser/Parser.h"
#include "mlir/Pass/PassManager.h"
#include "llvm/ADT/SmallString.h"
#include "llvm/ADT/TypeSwitch.h"
#include "llvm/Support/SourceMgr.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <exception>
#include <pthread.h>
#include <sys/stat.h>
#include <unistd.h>

using namespace mlir;
namespace nd = mlir::nix;

namespace nixev {

//===----------------------------------------------------------------------===//
// Bindings
//===----------------------------------------------------------------------===//

static const auto attrName = [](const Attr &a) { return a.name; };

const Attr *Bindings::get(Symbol s) const {
  const Attr *r = cp::findRow(attrs, size_, s, attrName);
  return r;
}

/// The union of two flat sorted sets, `y` winning on equal names, as a new flat set of exactly its size.
/// One pass: the set is allocated with room for both (a name in both is one row, so a few rows may stay unused) and written by unionInto.
static Bindings *mergeBindings(Arena &alloc, const Bindings *x, const Bindings *y) {
  // Counted first: the arena never takes back a tail, and an override over a large set shares most of its names (nixpkgs-73: 31 MB of
  // rows reserved and never written when the room was |x| + |y|).
  size_t room = cp::unionSize(x->attrs, x->size_, y->attrs, y->size_, attrName);
  void *mem = alloc.Allocate(sizeof(Bindings) + room * sizeof(Attr), alignof(Bindings));
  auto *r = new (mem) Bindings();
  r->size_ = uint32_t(cp::unionInto(x->attrs, x->size_, y->attrs, y->size_, r->attrs, attrName));
  Bindings::merged++;
  Bindings::mergedCells += r->size_;
  return r;
}

composite::Frozen<const Attr *> Bindings::lexicographicOrder(const SymbolTable &st) const {
  // Each name's first eight bytes are read once, into the rows sorted (on the stack up to 64 of them): a comparison reads the rows, not the
  // symbol table's prefix words, which a sort read n log n times at random (the table is larger than Kali's L2); the bytes only on a tie.
  struct Keyed { uint64_t prefix; const Attr *a; };
  size_t n = size();
  Keyed stackRows[64];
  composite::MutableSeries<Keyed> heapRows;
  if (n <= 64) {
    size_t k = 0;
    for (auto &a : *this) stackRows[k++] = {st.prefix[a.name], &a};
  } else {
    heapRows.reserve(n);
    for (auto &a : *this) heapRows.append({st.prefix[a.name], &a});
  }
  Keyed *rows = n <= 64 ? stackRows : heapRows.data();
  cp::sortRows(rows, n, [&](const Keyed &x, const Keyed &y) {
    return x.prefix != y.prefix ? x.prefix < y.prefix : composite::lessChars(st.chars(x.a->name), st.chars(y.a->name));
  });
  composite::MutableSeries<const Attr *> v;
  v.reserve(n);
  for (size_t i = 0; i < n; i++) v.append(rows[i].a);
  return std::move(v).freeze();  // sorted once, then only read: the handle's cells move into a const Series
}

/// `a // b`: the two merged into one flat set, as Nix does.  A set kept as a chain of layers over its base (a `//` that copied nothing)
/// was measured slower to read than to copy: every lookup walked the chain, a miss a level, and every `//` over a chain walked the base's
/// rows through it to build its selection (Mac, same outputs: toplevel -2.5%, nixpkgs-73 -7% merged flat; peak memory +5% and +13%).
Bindings *EvalState::updateAttrs(Bindings *a, Bindings *b) {
  // An empty side gives the other set itself, as Nix's `//` does: sets are not written after they are built, and the package set is
  // updated with nothing over a hundred times in a nixpkgs evaluation (each a copy of every row, never freed).
  if (b->size_ == 0) return a;
  if (a->size_ == 0) return b;
  if (statsEnabled) { nUpdMerged++; nUpdTop += a->size_ + b->size_; }
  return mergeBindings(alloc, a, b);
}

Bindings *EvalState::allocBindings(size_t n) {
  if (statsEnabled) nBindingBytes += sizeof(Bindings) + n * sizeof(Attr);
  void *mem = alloc.Allocate(sizeof(Bindings) + n * sizeof(Attr), alignof(Bindings));
  auto *b = new (mem) Bindings();
  b->size_ = 0;
  return b;
}

static size_t sortRowsFirstWins(Attr *rows, size_t n);
void EvalState::BindingsBuilder::overflow(Attr a) {
  if (cap) { // the first row past the room: the rows so far move to the series, and every later row goes there
    more.reserve(size_t(n) * 2 + 1);
    more.appendAll(rows, n);
    cap = 0;
  }
  more.append(a);
  n++;
}

Bindings *EvalState::BindingsBuilder::finish() {
  // A set of size 0 is the one constant: nothing is written to it after it is built, so every empty set is the same cell.
  if (n == 0) { if (st.statsEnabled) ++st.nEmptyShared; return st.vEmptyAttrs.attrs; }
  if (block && cap) { // written where it lives
    block->size_ = uint32_t(sortRowsFirstWins(block->attrs, n));
    return block;
  }
  Bindings *b = st.allocBindings(n);
  const Attr *src = cap ? rows : more.data();
  for (uint32_t i = 0; i < n; i++) b->attrs[i] = src[i];
  b->size_ = uint32_t(sortRowsFirstWins(b->attrs, n));
  return b;
}

Value **EvalState::allocList(size_t n) {
  if (!n) return nullptr;
  if (statsEnabled) nListBytes += n * sizeof(Value *);
  return static_cast<Value **>(alloc.Allocate(n * sizeof(Value *), alignof(Value *)));
}

const char *EvalState::copyString(std::string_view s) {
  if (statsEnabled) nStringBytes += s.size() + 1;
  char *p = static_cast<char *>(alloc.Allocate(s.size() + 1, 1));
  memcpy(p, s.data(), s.size());
  p[s.size()] = 0;
  return p;
}

void NixStringContext::settle() const {
  if (normal) return;
  cp::sortRows(rows.data(), rows.size(), lessBytes);
  uint32_t m = 0;
  for (uint32_t i = 0; i < rows.size(); i++)
    if (m == 0 || lessBytes(rows[m - 1], rows[i])) rows[m++] = rows[i]; // sorted: an element not after the last kept is a repeat
  while (rows.size() > m) rows.pop();
  normal = true;
}

/// The context `c` as a value's: its elements are already strings that outlive it, so the array holds them where they lie.
const StringContext *EvalState::makeContext(const NixStringContext &c) {
  if (c.empty()) return nullptr;
  uint32_t n = c.size();
  if (statsEnabled) nCtxBytes += sizeof(StringContext) + n * sizeof(const char *);
  void *mem = alloc.Allocate(sizeof(StringContext) + n * sizeof(const char *), alignof(StringContext));
  auto *ctx = new (mem) StringContext();
  ctx->n = n;
  const char *const *e = c.begin();
  for (uint32_t i = 0; i < n; i++) ctx->elems[i] = e[i];
  return ctx;
}

void EvalState::mkString(Value &v, std::string_view s, const NixStringContext &ctx) {
  if (s.size() > UINT32_MAX) throw EvalError("string of 4 GiB or more");
  v.type = VType::String;
  v.str.s = copyString(s);
  v.aux = static_cast<uint32_t>(s.size());
  v.str.ctx = makeContext(ctx);
}

void EvalState::mkStoreString(Value &v, std::string_view path) {
  if (path.size() > UINT32_MAX) throw EvalError("string of 4 GiB or more");
  const char *p = copyString(path);
  v.type = VType::String;
  v.str.s = p;
  v.aux = static_cast<uint32_t>(path.size());
  v.str.ctx = makeContext(NixStringContext{p});
}

// mkStringOf's pieces algebra is hollowed into lowered/nixeval/StringOps.mlir (trikeshed.combineAll / drain): at most one
// non-empty piece is shared as the string, else one arena buffer of the total drained once.
extern "C" void nixev_ts_concat(EvalState *st, const composite::Chars *pieces, int64_t np, Value *v, const StringContext *ctx);

void EvalState::mkPath(Value &v, std::string_view p) {
  if (p.size() > UINT32_MAX) throw EvalError("path of 4 GiB or more");
  v.type = VType::Path;
  v.path.s = copyString(p);
  v.aux = static_cast<uint32_t>(p.size());
}

void EvalState::mkList(Value &v, size_t n) {
  if (n > UINT32_MAX) throw EvalError("list of 4 Gi or more cells");
  v.type = VType::List;
  v.aux = static_cast<uint32_t>(n);
  v.list.elems = allocList(n);
  v.list.ext = nullptr;
}

void EvalState::concatLists(Value &l, Value &r, Value &out) {
  size_t nl = l.listSize(), nr = r.listSize(), n = nl + nr;
  if (n > UINT32_MAX) throw EvalError("list of 4 Gi or more cells");
  auto put = [&](Value **elems, ListExtent *e) {
    out.type = VType::List;
    out.aux = uint32_t(n);
    out.list.elems = elems;
    out.list.ext = e;
  };
  // l into the room below r: r starts at its buffer's claimed edge, and l fits
  if (ListExtent *e = r.list.ext; e && r.list.elems == e->lo && size_t(e->lo - e->begin) >= nl) {
    e->lo -= nl;
    memcpy(e->lo, l.list.elems, nl * sizeof(Value *));
    if (statsEnabled) nListExtended += nl;
    return put(e->lo, e);
  }
  // r into the room above l
  if (ListExtent *e = l.list.ext; e && l.list.elems + nl == e->hi && size_t(e->end - e->hi) >= nr) {
    memcpy(e->hi, r.list.elems, nr * sizeof(Value *));
    e->hi += nr;
    if (statsEnabled) nListExtended += nr;
    return put(l.list.elems, e);
  }
  if (n < 8) {
    mkList(out, l.items() + r.items());
    return;
  }
  // a new buffer with room for as many cells again, on the side the smaller operand came from (where a fold adds)
  size_t room = n;
  Value **buf = allocList(n + room);
  auto *e = static_cast<ListExtent *>(alloc.Allocate(sizeof(ListExtent), alignof(ListExtent)));
  e->begin = buf;
  e->lo = nl <= nr ? buf + room : buf;
  e->hi = e->lo + n;
  e->end = buf + n + room;
  memcpy(e->lo, l.list.elems, nl * sizeof(Value *));
  memcpy(e->lo + nl, r.list.elems, nr * sizeof(Value *));
  put(e->lo, e);
}

void PieceContexts::add(const StringContext *c, NixStringContext &spill) {
  if (!c || composite::anyOf(own, [&](const StringContext *o) { return o == c; })) return;
  if (own.size() < 8) { own.append(c); return; }
  for (size_t i = 0; i < c->n; i++) spill.insert(c->elems[i]);
}

const StringContext *PieceContexts::result(EvalState &st, NixStringContext &ctx) {
  if (ctx.empty() && own.size() <= 1) return own.empty() ? nullptr : own[0];
  for (const StringContext *c : own)
    for (size_t i = 0; i < c->n; i++) ctx.insert(c->elems[i]);
  return st.makeContext(ctx);
}

void EvalState::copyContext(const Value &v, NixStringContext &ctx) {
  if (v.type == VType::String && v.str.ctx)
    for (size_t i = 0; i < v.str.ctx->n; i++) ctx.insert(v.str.ctx->elems[i]);
}

//===----------------------------------------------------------------------===//
// Construction
//===----------------------------------------------------------------------===//

EvalState::EvalState(EvalSettings st, nixstore::Store *store) : settings(std::move(st)), store(store) {
  statsEnabled = getenv("MLNIX_STATS") != nullptr;
  composite::todoSink = [](const char *what) { llvm::errs() << "TODO: " << what << "\n"; };
  settings.deferBodies = getenv("MLNIX_DEFER") != nullptr; // sea-of-nodes schedule: mint bodies on first call
  // The evaluator is single-threaded.  With threading enabled every attribute
  // and location is uniqued through sharded, locked, thread-cached tables --
  // a quarter of the run time (measured) for no benefit.
  if (!getenv("MLNIX_MT") && !getenv("MLNIX_PRELOWER_LIST") && !getenv("MLNIX_PRELOWER")) ctx.disableMultithreading();
  nd::loadNixDialects(ctx);
  registerEvalModels(ctx);
  ctx.getLoadedDialect<nd::NixDialect>()->primFolder = [this](llvm::StringRef key,
                                                              llvm::ArrayRef<mlir::Attribute> args) {
    return foldPrimOp(key, args);
  };
  ctx.allowUnregisteredDialects(false);
  module = ModuleOp::create(UnknownLoc::get(&ctx));
#define SYM(field, str) s.field = symbols.create(str)
  SYM(outPath, "outPath"); SYM(drvPath, "drvPath"); SYM(type, "type"); SYM(name, "name");
  SYM(value, "value"); SYM(functor, "__functor"); SYM(toString, "__toString"); SYM(file, "file");
  SYM(line, "line"); SYM(column, "column"); SYM(outputs, "outputs"); SYM(outputName, "outputName");
  SYM(all, "all"); SYM(drvAttrs, "drvAttrs"); SYM(success, "success"); SYM(key, "key");
  SYM(operator_, "operator"); SYM(startSet, "startSet"); SYM(data, "data"); SYM(path, "path");
  SYM(prefix, "prefix"); SYM(body, "body"); SYM(ignoreNulls, "__ignoreNulls");
  SYM(structuredAttrs, "__structuredAttrs"); SYM(args, "args"); SYM(builder, "builder");
  SYM(system, "system"); SYM(outputHash, "outputHash"); SYM(outputHashAlgo, "outputHashAlgo");
  SYM(outputHashMode, "outputHashMode"); SYM(contentAddressed, "__contentAddressed");
  SYM(impure, "__impure"); SYM(allowedReferences, "allowedReferences");
  SYM(allowedRequisites, "allowedRequisites"); SYM(disallowedReferences, "disallowedReferences");
  SYM(disallowedRequisites, "disallowedRequisites"); SYM(maxSize, "maxSize");
  SYM(maxClosureSize, "maxClosureSize"); SYM(json, "__json"); SYM(right, "right"); SYM(wrong, "wrong");
  SYM(attrsSym, "attrs"); SYM(sha256, "sha256"); SYM(url, "url"); SYM(rev, "rev"); SYM(ref, "ref");
  SYM(submodules, "submodules"); SYM(shallow, "shallow"); SYM(allRefs, "allRefs");
  SYM(narHash, "narHash"); SYM(recursive, "recursive"); SYM(filter, "filter");
  SYM(lastModified, "lastModified"); SYM(revCount, "revCount"); SYM(shortRev, "shortRev");
  SYM(lastModifiedDate, "lastModifiedDate"); SYM(outPathSym, "outPath");
  SYM(exportIgnore, "exportIgnore"); SYM(executable, "executable"); SYM(unpack, "unpack");
#undef SYM
  mkBool(vTrue, true);
  mkBool(vFalse, false);
  mkNull(vNull);
  mkAttrs(vEmptyAttrs, allocBindings(0));
  mkList(vEmptyList, 0);
  printTrace = [](std::string_view m) { nixsys::lineToStderr(m.data(), m.size()); };
  createBaseEnv();
}

/// The entries of a map ranked by a count, largest first (ties keep the map's order): pointers to the entries where they lie, nothing copied.
template <class Map, class Count> static auto ranked(const Map &m, Count count) {
  using Entry = cp::bare_t<decltype(*m.begin())>;
  cp::MutableSeries<const Entry *> v;
  v.reserve(m.size());
  for (auto &e : m) v.append(&e);
  cp::sortRows(v.data(), v.size(), [&](const Entry *a, const Entry *b) { return count(*a) > count(*b); });
  return std::move(v).freeze();
}

void EvalState::printStats() {
  llvm::errs() << "attribute cells: bytes=" << sizeof(Attr)
               << " position_rows=" << attributePositions.size()
               << " position_bytes=" << attributePositions.capacity() * sizeof(PosPtr) << "\n";
  llvm::errs() << "frame allocations: count=" << nFrames << " bytes=" << nFrameBytes << " slots=" << nFrameSlots << '\n';
  if (nFrames) {
    auto mb = [](uint64_t b) { return b / 1048576.0; };
    struct rusage ru; getrusage(RUSAGE_SELF, &ru);
#ifdef __APPLE__
    double rss = mb(ru.ru_maxrss);
#else
    double rss = ru.ru_maxrss / 1024.0;
#endif
    uint64_t mergeBytes = Bindings::mergedCells * sizeof(Attr) + Bindings::merged * sizeof(Bindings);
    uint64_t values = nValues * sizeof(Value), named = values + nFrameBytes + nBindingBytes + nListBytes + nStringBytes + nMaskBytes + nLayerBytes + mergeBytes + nCtxBytes + nFormalBytes;
    uint64_t handed = alloc.getTotalMemory();  // the slabs, which is what the pages are
    llvm::errs() << llvm::format("== arena: %.0f MB of slabs; peak RSS %.0f MB. By use: values %.0f (%llu cells), frames %.0f, attribute rows %.0f, list cells %.0f, string bytes %.0f, other and slack %.0f MB\n",
                                 mb(handed), rss, mb(values), (unsigned long long)nValues, mb(nFrameBytes), mb(nBindingBytes), mb(nListBytes),
                                 mb(nStringBytes), mb(handed > named ? handed - named + nMaskBytes + nLayerBytes + mergeBytes + nCtxBytes + nFormalBytes : 0));
    llvm::errs() << llvm::format("   \"other\" named: frame stats words %.0f MB (a stats run only), `//` flat merges %.0f, layer headers %.0f, string contexts %.0f, formals %.0f; still unnamed (slab tails, alignment) %.0f MB\n",
                                 mb(nMaskBytes), mb(mergeBytes), mb(nLayerBytes), mb(nCtxBytes), mb(nFormalBytes), mb(handed > named ? handed - named : 0));
    llvm::errs() << llvm::format("   `++` wrote %llu cells into a buffer's room (ListExtent) instead of copying its other side\n",
                                 (unsigned long long)nListExtended);
  }
  llvm::errs() << "values evaluated at their first touch, never a thunk (the caller forces them next): " << nEager << "\n";
#ifdef __linux__
  if (nFrames) {
    // The peak is anonymous memory (heap, arena, IR) plus file-backed pages (the mapped source files, the binary): /proc says which.
    FILE *f = fopen("/proc/self/status", "r");
    char line[256];
    unsigned long anon = 0, file = 0, shmem = 0, hwm = 0, rss = 0;
    while (f && fgets(line, sizeof line, f)) {
      sscanf(line, "RssAnon: %lu kB", &anon); sscanf(line, "RssFile: %lu kB", &file); sscanf(line, "RssShmem: %lu kB", &shmem);
      sscanf(line, "VmHWM: %lu kB", &hwm); sscanf(line, "VmRSS: %lu kB", &rss);
    }
    if (f) fclose(f);
    llvm::errs() << llvm::format("== resident at exit: %.0f MB anonymous (arena %.0f + %.0f MB of heap, IR and the rest), %.0f MB file-backed (mapped sources and the binary); high-water mark %.0f MB\n",
                                 anon / 1024.0, alloc.getTotalMemory() / 1048576.0, anon / 1024.0 - alloc.getTotalMemory() / 1048576.0, file / 1024.0, hwm / 1024.0);
  }
  { // This thread (the evaluator's: the state is torn down where it ran): user and kernel time, what it waited for, the faults it took.
    struct rusage ru;
    if (getrusage(RUSAGE_THREAD, &ru) == 0)
      llvm::errs() << llvm::format("== evaluator thread: user %.2f s, system %.2f s; %ld voluntary context switches (it blocked), %ld involuntary; %ld minor faults, %ld major\n",
                                   ru.ru_utime.tv_sec + ru.ru_utime.tv_usec / 1e6, ru.ru_stime.tv_sec + ru.ru_stime.tv_usec / 1e6, ru.ru_nvcsw, ru.ru_nivcsw,
                                   ru.ru_minflt, ru.ru_majflt);
  }
#endif
  if (!pools.empty()) {
    // What the per-file pools keep for deferred bodies: the Confix band tables, the lambda rows and their names, outside the arena.
    uint64_t bandRows = 0, bandBytes = 0, ends = 0, openingEntries = 0, openingBytes = 0, poolRows = 0, poolRowBytes = 0, nameBytes = 0, freeBytes = 0, seenBytes = 0;
    for (auto &p : pools) {
      if (!p) continue;
      bandRows += p->bands.rows.size(); bandBytes += uint64_t(p->bands.rows.size()) * (sizeof(::join::TwInt) + 1 + sizeof(::join::TwInt));
      ends += p->bands.ends.size();
      openingEntries += p->bands.opening.size(); openingBytes += p->bands.opening.getMemorySize();
      poolRows += p->rows.size(); poolRowBytes += uint64_t(p->rows.size()) * (sizeof(uint32_t) + sizeof(nixfe::Pos) + sizeof(void *) + sizeof(uint32_t) + sizeof(::join::TwInt) + sizeof(void *));
      nameBytes += p->nameCol.size() * sizeof(llvm::StringRef);
      freeBytes += p->freeCol.capacity() * sizeof(nixfe::FreeName);
      seenBytes += p->seen.getMemorySize();
    }
    auto mb = [](uint64_t b) { return b / 1048576.0; };
    llvm::errs() << llvm::format("== per-file pools (%zu files): Confix bands %llu rows (%.1f MB) + %llu statement ends (%.1f MB) + opening index %llu entries (%.1f MB); lambda rows %llu (%.1f MB), names %.1f MB, free names %.1f MB, seen %.1f MB\n",
                                 pools.size(), (unsigned long long)bandRows, mb(bandBytes), (unsigned long long)ends, mb(ends * 4), (unsigned long long)openingEntries, mb(openingBytes),
                                 (unsigned long long)poolRows, mb(poolRowBytes), mb(nameBytes), mb(freeBytes), mb(seenBytes));
  }
  if (nReturns) llvm::errs() << llvm::format("== son's account of the frames at their return (MLNIX_STATS): %llu of %llu lambda bodies dead at return by son "
                                            "(no closure, every value a use takes lazily forced on every path that returns); of %llu returns (%.1f MB of "
                                            "frames), dead by the run (no closure, every thunk over them forced, projections too) %llu (%.1f%%, %.1f MB), dead "
                                            "by son %llu (%.1f%%, %.1f MB); son wrong (dead by son, not by the run): %llu\n",
                                            (unsigned long long)nSonDeadBodies, (unsigned long long)nBodies, (unsigned long long)nReturns, nReturnBytes / 1048576.0,
                                            (unsigned long long)nRunDead, 100.0 * nRunDead / nReturns, nRunDeadBytes / 1048576.0,
                                            (unsigned long long)nSonDead, 100.0 * nSonDead / nReturns, nSonDeadBytes / 1048576.0, (unsigned long long)nSonWrong);
  if (nReturns) llvm::errs() << llvm::format("   dead by the run, not by son, by why son keeps the frame: the body makes a closure %llu, a value forced on some "
                                            "path that returns only %llu, a value passed to a callee son does not see %llu, a value passed on unforced %llu\n",
                                            (unsigned long long)nSonGap[1], (unsigned long long)nSonGap[2], (unsigned long long)nSonGap[3],
                                            (unsigned long long)nSonGap[4]);
  if (nSonGap[2] + nSonGap[3] + nSonGap[4]) {
    auto g = ranked(sonGapByOp, [](auto &e) { return e.v.n[0] + e.v.n[1] + e.v.n[2]; });
    llvm::errs() << "   the op whose lazy use decides (path, callee, passed on):";
    for (size_t i = 0; i < g.size() && i < 10; ++i)
      llvm::errs() << llvm::format(" %.*s %llu/%llu/%llu", int(g[i]->v.name.size()), g[i]->v.name.data(), (unsigned long long)g[i]->v.n[0],
                                   (unsigned long long)g[i]->v.n[1], (unsigned long long)g[i]->v.n[2]);
    llvm::errs() << "\n";
  }
  llvm::errs() << "calls run on a stack frame (strict bodies over their one argument): " << nStackFrames << "\n";
  llvm::errs() << "selector calls with no frame (lib.optional, lib.optionalAttrs shapes): " << nSelectorCalls << "\n";
  llvm::errs() << "curried intermediates held by value: " << nStackCells << " (" << nStackCells * sizeof(Value) << " bytes of heap cells not allocated)\n";
  llvm::errs() << "empty attribute sets: " << nEmptyShared << " shared as one constant (" << nEmptyShared * (sizeof(Bindings)) << " bytes not allocated)\n";
  llvm::errs() << "value allocations: count=" << nValues << " bytes=" << nValues * sizeof(Value) << '\n';
  // How many ops of real programs live where: per tier of the dialect hierarchy
  // (scope > continent > dialect), read from the IRDL declaration.
  auto *core = ctx.getLoadedDialect<nd::NixDialect>();
  // By name: a dialect's is a prefix of its ops' names and a scope's or continent's is the dialect's declaration, bytes that live as long as
  // the context, so a row keeps them where they lie.
  cp::TextTable<uint64_t> perDialect, perScope, perContinent;
  auto add = [](cp::TextTable<uint64_t> &m, llvm::StringRef name, uint64_t n) { m.at(name.data(), uint32_t(name.size()), [&] { return name.data(); }) += n; };
  uint64_t total = 0;
  for (auto &e : opStats) {
    llvm::StringRef dialect = e.v.name.split('.').first;
    uint64_t n = e.v.n[0];
    add(perDialect, dialect, n);
    auto it = core->continents.find(dialect);
    add(perScope, it == core->continents.end() ? "core" : llvm::StringRef(it->second.scope), n);
    add(perContinent, it == core->continents.end() ? "core" : llvm::StringRef(it->second.continent), n);
    total += n;
  }
  auto section = [&](const char *title, cp::TextTable<uint64_t> &m) {
    llvm::errs() << "== " << title << " (" << m.size() << ")\n";
    for (auto *e : ranked(m, [](auto &e) { return e.v; }))
      llvm::errs() << "  " << llvm::format("%-9.*s", int(e->n), e->p) << llvm::format("%9llu", (unsigned long long)e->v) << "\n";
  };
  { // The sea of nodes against its schedule: the ops the index holds against the ops that ever ran,
    // file code against the bodies demand minted.  The thunk cells are finer grain's rows.
    cp::WordTable<char> minted; // a set, by the region's address
    for (auto &p : pools)
      if (p)
      for (nixev::RegionInfo *ri : p->rows.col<nixfe::PoolCol::Body>().view())
        if (ri) minted.insert(uint64_t(uintptr_t(ri)), 1);
    uint64_t fOps = 0, fRan = 0, fEvals = 0, fTh = 0, mOps = 0, mRan = 0, mEvals = 0, mTh = 0;
    unsigned fR = 0, mR = 0;
    for (auto &kv : regionInfos) {
      RegionInfo *ri = kv.v;
      uint64_t ran = 0;
      for (uint64_t w : ri->everRan) ran += __builtin_popcountll(w);
      if (minted.find(uint64_t(uintptr_t(ri)))) { mR++; mOps += ri->nOps; mRan += ran; mEvals += ri->nEvals; mTh += ri->nThunks; }
      else { fR++; fOps += ri->nOps; fRan += ran; fEvals += ri->nEvals; fTh += ri->nThunks; }
    }
    llvm::errs() << "== sea of nodes: " << fR << " file regions hold " << fOps << " ops ("
                 << llvm::format("%.1f", fOps ? 100.0 * fRan / fOps : 0.0) << "% ever ran, " << fEvals << " evals, "
                 << fTh << " thunk cells); " << mR << " minted bodies hold " << mOps << " ops ("
                 << llvm::format("%.1f", mOps ? 100.0 * mRan / mOps : 0.0) << "% ever ran, " << mEvals << " evals, "
                 << mTh << " thunk cells).  Finer grain mints a cell: the thunk cells are its rows against lambda grain's "
                 << mR << "\n";
  }
  if (pre) llvm::errs() << "== prelowering: " << pre->adopted << " files adopted (" << pre->waited << " of them waited for), " << pre->missed << " lowered by the evaluator\n";
  llvm::errs() << "== symbols: " << symbols.creates << " interning calls, " << symbols.size() << " symbols\n";
  { // the dynamic mix: what the run evaluated, by op kind
    uint64_t tot = 0;
    for (auto &e : evalsByKind) tot += e.v.n[0];
    auto ev = ranked(evalsByKind, [](auto &e) { return e.v.n[0]; });
    if (tot) llvm::errs() << "== evalOp calls by op kind (" << tot << " in all)\n";
    for (size_t i = 0; tot && i < ev.size() && i < 16; i++)
      llvm::errs() << "  " << llvm::format("%-26.*s", int(ev[i]->v.name.size()), ev[i]->v.name.data()) << llvm::format("%12llu", (unsigned long long)ev[i]->v.n[0]) << llvm::format("%7.1f%%", 100.0 * ev[i]->v.n[0] / tot) << '\n';
  }
  llvm::errs() << "== mlnix ops lowered: " << total << "\n";
  llvm::errs() << "== `//`: " << nUpdMerged << " merges, " << nUpdTop << " entries copied\n";
  llvm::errs() << "== lowering " << llvm::format("%.0f", nsLower / 1e6) << " ms (the analysis of deferred lambdas included), minted on demand "
               << llvm::format("%.0f", nsMint / 1e6) << " ms\n";
  if (!pools.empty()) {
    size_t names = 0, seen = 0, free = 0;
    for (auto &p : pools) {
      if (!p) continue;
      names += p->nameCol.size();
      seen += p->seen.size();
      free += p->freeCol.size();
    }
    llvm::errs() << "== read plan: " << names << " names pooled; " << seen << " lambdas skimmed and not yet reached (" << free
                 << " free names kept)\n";
  }
  if (!pools.empty()) {
    // The pools are Cursors: print them by their own column names.  A row is deferred when lowering
    // meets the lambda and drained when its first call mints the body; the rest is what never ran.
    size_t rows = 0, minted = 0;
    for (auto &p : pools) {
      if (!p) continue;
      rows += p->rows.size();
      for (nixev::RegionInfo *ri : p->rows.col<nixfe::PoolCol::Body>().view()) minted += ri != nullptr;
    }
    llvm::errs() << "== lambda pools: " << pools.size() << " files, (";
    for (size_t i = 0; i < pools[0]->rows.meta.size(); i++) llvm::errs() << (i ? ", " : "") << pools[0]->rows.meta[i];
    llvm::errs() << "), " << rows << " rows deferred, " << minted << " drained (body minted on a first call), "
                 << rows - minted << " never called\n";
  }
  section("scopes", perScope);
  section("continents", perContinent);
  section("dialects", perDialect);
  auto o = ranked(opStats, [](auto &e) { return e.v.n[0]; });
  llvm::errs() << "== top ops\n";
  for (size_t i = 0; i < o.size() && i < 14; i++)
    llvm::errs() << "  " << llvm::format("%-22.*s", int(o[i]->v.name.size()), o[i]->v.name.data()) << llvm::format("%9llu", (unsigned long long)o[i]->v.n[0]) << "\n";
}

EvalState::~EvalState() {
  if (pre) {
    { nixsys::Held g(pre->m); pre->stop = true; }
    pre->cv.notifyAll();
    for (auto &w : pre->workers) w.join();
  }
  if (statsEnabled) printStats();
}

bool EvalState::isBaseName(llvm::StringRef name) const { return baseEnv.find(name.data(), uint32_t(name.size())) != nullptr; }
/// GenOptions::isBaseName over the state: a plain function, the state its context.
static bool baseNameOf(const void *st, llvm::StringRef name) { return static_cast<const EvalState *>(st)->isBaseName(name); }

Value *EvalState::baseEnvValue(llvm::StringRef name) {
  Value **v = baseEnv.find(name.data(), uint32_t(name.size()));
  return v ? *v : nullptr;
}

static cp::Text primOpName(std::string_view name) { return cp::Text(name.starts_with("__") ? name.substr(2) : name); }

void EvalState::addPrimOp(std::string_view name, PrimFn fn) {
  const auto &declared = ctx.getLoadedDialect<nd::NixDialect>()->prims;
  auto it = declared.find(name);
  if (it == declared.end()) llvm::report_fatal_error(cp::cat("the primop '", name, "' is registered but not declared in NixPrims.irdl.mlir").c_str());
  registerPrimOp(name, new PrimOp{primOpName(name), it->second.arity, fn});
}

void EvalState::registerPrimOp(std::string_view name, PrimOp *p) {
  if (p->arity > kMaxPrimArity) llvm::report_fatal_error("a primop with more arguments than EvalState::kMaxPrimArity");
  Value *v = allocValue();
  if (p->arity == 0) {
    // A constant computed by calling fn immediately.
    p->call(*this, nullptr, *v, nullptr);
  } else {
    v->type = VType::PrimOp;
    v->primOp = p;
  }
  addConstant(name, v);
}

void EvalState::addConstant(std::string_view name, Value *v) {
  uint32_t n = uint32_t(name.size());
  baseEnv.set(name.data(), n, v, [&] { return baseEnvNames.copy(name.data(), n); });
}

//===----------------------------------------------------------------------===//
// Positions & errors
//===----------------------------------------------------------------------===//

cp::Text EvalState::showPos(PosPtr pos) const {
  auto f = nd::decodePos(pos);
  if (!f) return "«none»:0";
  return cp::cat(f->file, ':', f->line, ':', f->col);
}

void EvalState::throwError(std::string_view msg, PosPtr pos) { throw EvalError(msg, pos); }

void EvalState::warn(std::string_view msg) {
  cp::Text line = cp::cat("warning: ", msg);
  nixsys::lineToStderr(line.data(), line.size());
  if (settings.abortOnWarn) throw EvalError(msg);
}

// EvalState::showType is hollowed out to MLIR: lowered/nixeval/ShowType.mlir, built into NixEval by lib/CMakeLists.txt.

// EvalState::typeOf is hollowed out to MLIR: lowered/nixeval/TypeOps.mlir, built into NixEval by lib/CMakeLists.txt.

void EvalState::throwTypeError(const char *expected, Value &v, PosPtr pos, std::string_view ctx) {
  TypeError e(cp::cat("expected ", expected, " but found ", showType(v), ": ", printValueForTrace(v)), pos);
  if (!ctx.empty()) e.addTrace(pos, cp::Text(ctx));
  throw e;
}

//===----------------------------------------------------------------------===//
// Regions & frames
//===----------------------------------------------------------------------===//

static Node::How howOf(Operation *op);
static EvalFn evalFnOf(NodeKind k);
/// What evaluating `op` is, read once from the op: its kind, and what its operand segments say.
static void describe(Node *n, Operation *op, const nd::NixDialect *core) {
  n->how = howOf(op);
  n->kind = llvm::TypeSwitch<Operation *, NodeKind>(op)
      .Case<nd::ApplyOp>([](auto) { return NodeKind::Apply; })
      .Case<nd::SelectOp>([&](nd::SelectOp sel) {
        const auto &sz = sel.getProperties().operandSegmentSizes;
        n->nDyn = uint32_t(sz[1]);
        n->flags = sz[2] ? Node::kDefault : 0;
        return NodeKind::Select;
      })
      .Case<nd::IfOp>([](auto) { return NodeKind::If; })
      .Case<nd::AttrsOp>([&](nd::AttrsOp a) {
        const auto &sz = a.getProperties().operandSegmentSizes;
        n->nDyn = uint32_t(sz[0]);
        n->flags = sz[1] ? Node::kDynamic : 0;
        return NodeKind::Attrs;
      })
      .Case<nd::EqOp>([](auto) { return NodeKind::Eq; })
      .Case<nd::HasAttrOp>([&](nd::HasAttrOp h) { n->nDyn = h->getNumOperands() - 1; return NodeKind::HasAttr; })
      .Case<nd::ListOp>([](auto) { return NodeKind::List; })
      .Case<nd::StringOp>([](auto) { return NodeKind::String; })
      .Case<nd::AndOp>([](auto) { return NodeKind::And; })
      .Case<nd::OrOp>([](auto) { return NodeKind::Or; })
      .Case<nd::UpdateOp>([](auto) { return NodeKind::Update; })
      .Case<nd::NotOp>([](auto) { return NodeKind::Not; })
      .Case<nd::FormalOp>([](auto) { return NodeKind::Formal; })
      .Case<nd::NeqOp>([](auto) { return NodeKind::Neq; })
      .Case<nd::ConcatListsOp>([](auto) { return NodeKind::ConcatLists; })
      .Case<nd::ConcatStringsOp>([&](auto) { n->flags = 0; return NodeKind::ConcatStrings; })
      .Case<nd::InterpolateOp>([&](auto) { n->flags = Node::kForceString; return NodeKind::ConcatStrings; }) // one evaluation, every part coerced
      .Case<nd::WithVarOp>([](auto) { return NodeKind::WithVar; })
      .Case<nd::AssertOp>([](auto) { return NodeKind::Assert; })
      .Case<nd::ImplOp>([](auto) { return NodeKind::Impl; })
      .Case<nd::IntOp>([](auto) { return NodeKind::Int; })
      .Case<nd::BoolOp>([](auto) { return NodeKind::Bool; })
      .Case<nd::NullOp>([](auto) { return NodeKind::Null; })
      .Case<nd::FloatOp>([](auto) { return NodeKind::Float; })
      .Case<nd::PathOp>([](auto) { return NodeKind::Path; })
      .Case<nd::BuiltinOp>([](auto) { return NodeKind::Builtin; })
      .Case<nd::LambdaOp>([](auto) { return NodeKind::Lambda; })
      .Default([&](Operation *o) {
        if (!core->primOf(o)) return NodeKind::Other;
        n->flags = uint8_t(core->modesOf(o->getName()).first); // the operand the primop forces first, plus one (nix.first)
        return NodeKind::Prim;                                // the primop itself is found at its first evaluation
      });
}

void EvalState::unindexed() { throw EvalError("internal error: unindexed SSA value"); }

void EvalState::indexRegion(Region &r) { indexer.index(r); }

/// MLNIX_STATS: son's account of a frame of this lambda body (RegionInfo::sonDead): unreachable once its call returns, because the body makes
/// no closure (a closure keeps the frame it was made in) and every value of the body that a use passes on as a cell -- a thunk over the
/// frame, unless the value is a literal or a builtin, one cell for every frame -- is forced on every path on which the call returns
/// (son::forcedOnReturn), so each such thunk holds its value by then and not the frame.  The uses that pass a cell on are the evaluator's
/// (the functions below), the cells of son.release (frameReads): a list's elements (evalList), an attribute set's values (evalAttrsNode),
/// an application's arguments (evalApply forces the callee), a primop's operands (evalPrim; not the one it forces first, nor, applied to
/// all its arguments, a nix.strict one, forced before it returns).  The other ops of the core force what they read, or read it only to
/// force it (a select's default and computed names, a formal's default, the scopes of a with: lookupImpl(.., true), lookup then force), or
/// return it (an if's arms).  An op of any other dialect passes every operand on.
/// The result is 0 (dead at return) or why not, the worst use deciding: 1 the body makes a closure; 2 a value passed on is forced on some
/// path that returns, not all (a release per path would have it); 3 a value is passed to a callee son does not see (son-release states
/// each body's strictness, son.body's arg_forced, which the Graal arm reads at the call); 4 a value is passed on and nothing of the body
/// forces it (it escapes the call).  `at`: the use that decides, the worst, the first of its kind.
static uint8_t sonDiesAtReturn(mlir::Block &blk, nd::NixDialect *core, mlir::Operation *&at) {
  mlir::son::ForcedOnReturn must = mlir::son::forcedOnReturn(blk, core), may;
  if (must.never) return 0;
  bool mayDone = false;
  uint8_t why = 0;
  auto passedOn = [&](mlir::Operation &op, mlir::Value v, uint8_t kind) {
    auto res = dyn_cast<mlir::OpResult>(v);
    if (!res || res.getOwner()->getBlock() != &blk) return; // an argument or a value from outside: no thunk over this frame
    mlir::Operation *def = res.getOwner();
    if (def->hasTrait<mlir::OpTrait::ConstantLike>() || isa<nd::PathOp, nd::BuiltinOp>(def)) return; // fixed: one cell for all frames
    if (must.contains(v)) return;
    if (!mayDone) { may = mlir::son::forcedOnReturn(blk, core, /*may=*/true); mayDone = true; }
    uint8_t w = may.contains(v) ? 2 : kind;
    if (w > why) at = &op;
    why = std::max(why, w);
  };
  for (mlir::Operation &op : blk) {
    if (isa<nd::LambdaOp>(op)) { at = &op; return 1; }
    if (auto l = dyn_cast<nd::ListOp>(op)) { for (mlir::Value v : l.getElements()) passedOn(op, v, 4); continue; }
    if (auto a = dyn_cast<nd::AttrsOp>(op)) {
      for (mlir::Value v : a.getValues()) passedOn(op, v, 4);
      for (mlir::Value v : a.getDynValues()) passedOn(op, v, 4);
      continue;
    }
    if (auto ap = dyn_cast<nd::ApplyOp>(op)) { for (mlir::Value v : ap.getArgs()) passedOn(op, v, 3); continue; }
    if (isa<nd::ReturnOp, nd::IfOp, nd::AssertOp, nd::NotOp, nd::AndOp, nd::OrOp, nd::ImplOp, nd::EqOp, nd::NeqOp, nd::UpdateOp,
            nd::ConcatListsOp, nd::ConcatStringsOp, nd::InterpolateOp, nd::SelectOp, nd::HasAttrOp, nd::FormalOp, nd::WithVarOp>(op))
      continue;
    if (const auto *prim = core->primOf(&op)) {
      auto modes = core->modesOf(op.getName());
      bool full = op.getNumOperands() == prim->arity;
      for (unsigned i = 0; i < op.getNumOperands(); ++i) {
        if (modes.first && modes.first - 1 == i) continue;
        if (full && i < 32 && ((modes.strict >> i) & 1)) continue;
        passedOn(op, op.getOperand(i), 4);
      }
      continue;
    }
    for (mlir::Value v : op.getOperands()) passedOn(op, v, 4);
  }
  return why;
}

void EvalState::Indexer::index(Region &r) {
  auto *ri = new RegionInfo{&r, 0, {}};
  if (auto lam = dyn_cast_or_null<nd::LambdaOp>(r.getParentOp())) {
    if (auto formals = lam.getFormals()) {
      ri->hasFormals = 1;
      ri->nFormals = uint32_t(formals->size());
      ri->formalDefaults = lam.getFormalDefaults()->data();
    }
    ri->ellipsis = lam.getEllipsis();
  }
  Block &blk = r.front();
  unsigned slot = 0;
  auto *core = st.ctx.getLoadedDialect<nd::NixDialect>();
  bool stats = st.statsEnabled && !helper;
  auto newNode = [&] { return ::new (allocate(sizeof(Node), alignof(Node))) Node{}; };
  // A value is found in blockNodes by the ops of its block and of the bodies nested in it that are indexed with it, in this recursion.  A
  // body indexed later (a deferred lambda, minted at its first call) reads the values around it through its lambda's capture list, so the
  // captures are what goes into the map of every value (below, with the operands).  (An op evaluated through the interface model puts its
  // operands there itself: evalOther.)
  ++depth;
  auto publish = [&](mlir::Value v, Node *n) { blockNodes.at(uint64_t(uintptr_t(v.getAsOpaquePointer()))) = n; };
  for (BlockArgument a : blk.getArguments()) {
    Node *n = newNode();
    n->kind = NodeKind::Arg;
    n->how = Node::Unknown;
    n->promo = Promotion::Argument;
    n->idx = slot++;
    n->ri = ri;
    n->def = r.getParentOp(); // a block argument was made where its lambda is
    n->eval = evalFnOf(NodeKind::Arg);
    publish(a, n);
  }
  // Every value's record first: an op may read a value defined after it (a graph region) or from a body nested in it.
  for (Operation &op : blk) {
    if (auto ret = dyn_cast<nd::ReturnOp>(op)) {
      ri->result = ret.getValue();
      continue;
    }
    for (mlir::Value res : op.getResults()) {
      // What the dialect promotes the value to decides its cell: none when it is evaluated in place (one strict or tail use), made by its
      // one use (which runs once per frame: nothing to keep) or fixed (a literal or a builtin, one cell for every frame, kept in its Slot);
      // otherwise a cell in each frame of the region.
      Promotion p = core->promotionOf(res);
      // A cell that starts as a thunk is finer grain's row: an attribute value, a let binding, an argument, minted when it is forced
      // instead of when its body is.
      if (stats && (p == Promotion::Shared || p == Promotion::Distinct || p == Promotion::Once)) ++ri->nThunks;
      bool cell = p != Promotion::InPlace && p != Promotion::Fixed && p != Promotion::Once;
      Node *n = newNode();
      describe(n, &op, core);
      n->eval = evalFnOf(n->kind);
      n->promo = p;
      n->idx = cell ? slot++ : kNoSlot;
      n->ri = ri;
      n->def = &op;
      publish(res, n);
    }
  }
  ri->numSlots = slot;
  if (stats && isa_and_nonnull<nd::LambdaOp>(r.getParentOp())) {
    mlir::Operation *at = nullptr;
    uint8_t why = sonDiesAtReturn(blk, core, at);
    ri->sonDead = why == 0;
    ri->sonWhy = why;
    ri->sonWhyAt = at;
    ++st.nBodies; st.nSonDeadBodies += ri->sonDead;
  }
  // A deferred lambda's region is a shell until its first call; it is indexed when it is minted.
  for (Operation &op : blk) {
    auto lam = dyn_cast<nd::LambdaOp>(op);
    if (lam && lam.getBodyIndexAttr()) continue;
    for (Region &nested : op.getRegions())
      if (!nested.empty()) index(nested);
  }
  // Then each op's operands, as the records of the values they name (an operand not indexed stays null: its use is an internal error).
  // A helper indexes a whole file, which reads nothing from outside it: what is not in blockNodes is nowhere.
  auto recordOf = [&](mlir::Value v) -> Node * {
    void *key = v.getAsOpaquePointer();
    Node **found = blockNodes.find(uint64_t(uintptr_t(key)));
    return found ? *found : helper ? nullptr : st.nodeOf(key);
  };
  for (Operation &op : blk) {
    unsigned k = op.getNumOperands();
    if (op.getNumResults() == 0 || k == 0) continue;
    auto **ops = static_cast<Node **>(allocate(k * sizeof(Node *), alignof(Node *)));
    for (unsigned i = 0; i < k; i++) ops[i] = recordOf(op.getOperand(i));
    if (auto lam = dyn_cast<nd::LambdaOp>(op); lam && lam.getBodyIndexAttr())
      for (unsigned i = 0; i < k; i++)
        if (ops[i]) { // the captures of a body minted later
          void *key = op.getOperand(i).getAsOpaquePointer();
          if (helper) captures.append({key, ops[i]});
          else st.setNode(key, ops[i]);
        }
    for (mlir::Value res : op.getResults()) {
      Node *n = recordOf(res);
      n->operands = ops;
      n->nOperands = k;
    }
  }
  if (ri->result) ri->resultNode = recordOf(ri->result);
  if (--depth == 0) blockNodes.clear();
  if (stats) {
    ri->nOps = uint32_t(blk.getOperations().size());
    ri->everRan.assign((ri->nOps + 63) / 64, 0);
    uint32_t oi = 0;
    for (Operation &op : blk) ri->opIdx.at(uint64_t(uintptr_t(&op))) = oi++;
  }
  if (helper) regions.append({&r, ri});
  else st.regionInfos.at(uint64_t(uintptr_t(&r))) = ri;
}

RegionInfo *EvalState::regionInfo(Region *r) {
  if (RegionInfo **found = regionInfos.find(uint64_t(uintptr_t(r)))) return *found;
  indexRegion(*r);
  return regionInfos.at(uint64_t(uintptr_t(r)));
}

/// Can a call of this body run on a stack frame?  Yes when nothing in it can make a thunk, a closure, a list or a set over the frame that
/// outlives the call (a lazy operand is a thunk whose env is the frame, and the callee or the result may keep it) and it holds no cell but
/// its argument: only strict ops.  A core op reads its operands in place; a primop is given cells, forces each before it returns and keeps
/// none (nix.strict), so a cell made over the frame for one is forced, or unreachable, once the call returns.  Such a call puts no frame
/// in the never-freed arena.
bool EvalState::classifyStackFrame(RegionInfo *ri) {
  ri->stackable = 0;
  if (ri->numSlots > 1) return false;
  // The rule is the dialect's, not a list of names: an op whose every operand is strict or tail (its NixModes, or nix.strict on a continent
  // op) leaves no thunk over the frame once it returns; an op without operands may only be a constant.
  auto *core = ctx.getLoadedDialect<nd::NixDialect>();
  for (mlir::Operation &op : ri->region->front()) {
    bool ok;
    if (auto ap = dyn_cast<nd::ApplyOp>(op)) {
      // A call whose callee and arguments are this body's argument or values captured from outside: those are cells that already exist,
      // so no thunk is made over this frame, and the callee gets pointers to cells that outlive it.
      auto outsideOrArg = [&](mlir::Value v) { return v.getParentRegion() != ri->region || isa<mlir::BlockArgument>(v); };
      ok = outsideOrArg(ap.getCallee());
      for (mlir::Value a : ap.getArgs()) ok = ok && outsideOrArg(a);
    } else if (unsigned n = op.getNumOperands(); n == 0) {
      ok = op.getNumRegions() == 0 && op.hasTrait<mlir::OpTrait::ConstantLike>();
    } else {
      auto m = core->modesOf(op.getName());
      unsigned all = n >= 32 ? ~0u : (1u << n) - 1;
      ok = ((m.strict | m.tail) & all) == all;
    }
    if (!ok) return false;
  }
  ri->stackable = 1;
  return true;
}

/// MLNIX_STATS: the frame's two bookkeeping words, after its slots, for son's account of the frames at their return: pinned (a closure was
/// made over it), and the thunks made over it, projections too, that are not forced yet.
static inline uint64_t *frameWords(Frame *f) { return reinterpret_cast<uint64_t *>(f->slots + f->info->numSlots); }
/// A thunk (or, pinned, a closure) now refers to this frame.  A frame on the stack (a stackable body's) has no such words: the cells a
/// primop of the body is given over it are forced before the primop returns (nix.strict), so none outlives the call.
void EvalState::markCaptured(Frame *f) { if (f->info->stackable != 1) ++frameWords(f)[1]; }
void EvalState::markPinned(Frame *f) { frameWords(f)[0] = 1; }
/// A thunk over this frame has been forced: it holds its value now, not the frame.
void EvalState::statUnref(Frame *f) { if (uint64_t *w = frameWords(f); f->info->stackable != 1 && w[1]) --w[1]; }
/// A call has returned.
void EvalState::statReturn(Frame *f) {
  uint64_t *w = frameWords(f);
  uint64_t bytes = sizeof(Frame) + f->info->numSlots * sizeof(Value *);
  ++nReturns; nReturnBytes += bytes;
  bool runDead = !w[0] && !w[1];
  if (runDead) { ++nRunDead; nRunDeadBytes += bytes; }
  if (f->info->sonDead) { ++nSonDead; nSonDeadBytes += bytes; if (!runDead) ++nSonWrong; }
  if (runDead && !f->info->sonDead) {
    ++nSonGap[f->info->sonWhy & 7];
    if (f->info->sonWhyAt && f->info->sonWhy >= 2) ++countOf(sonGapByOp, f->info->sonWhyAt->getName()).n[f->info->sonWhy - 2];
  }
}

Frame *EvalState::newFrameSlow(RegionInfo *ri, Frame *up) {
  size_t sz = sizeof(Frame) + ri->numSlots * sizeof(Value *);
  size_t wordBytes = statsEnabled ? 2 * sizeof(uint64_t) : 0; // stats only: frameWords
  auto *f = static_cast<Frame *>(alloc.Allocate(sz + wordBytes, alignof(Frame)));
  if (statsEnabled) { ++nFrames; nFrameBytes += sz; nFrameSlots += ri->numSlots; nMaskBytes += wordBytes; }
  f->upBits = reinterpret_cast<uintptr_t>(up);
  f->info = ri;
  memset(f->slots, 0, ri->numSlots * sizeof(Value *) + wordBytes);
  return f;
}

static Node::How howOf(Operation *op) {
  if (isa<nd::IntOp, nd::FloatOp, nd::StringOp, nd::PathOp, nd::BoolOp, nd::NullOp>(op)) return Node::Const;
  if (isa<nd::BuiltinOp>(op)) return Node::Builtin;
  if (isa<nd::LambdaOp>(op)) return Node::Lambda;
  return Node::Thunk;
}

/// MLNIX_STATS: a cell lookup left over a frame (cold, out of line): a closure pins the frame, a thunk refers to it until it is forced.
void EvalState::statCell(Frame *f, Value *nv) {
  if (nv->type == VType::Lambda) markPinned(f);
  else markCaptured(f);
}

/// A literal's or a builtin's one cell, made at its first touch in any frame and kept in the node.
Value *EvalState::makeFixed(Node *s) {
  Operation *op = s->def;
  if (s->how == Node::Builtin) { // the base environment is complete before anything is evaluated
    auto b = cast<nd::BuiltinOp>(op);
    Value *bv = baseEnvValue(b.getName().str());
    if (!bv) throw EvalError(cp::cat("undefined variable '", b.getName().str(), "'"), nd::posOfOp(op));
    return s->fixed = bv;
  }
  Value *cv = allocValue();
  if (auto i = dyn_cast<nd::IntOp>(op)) mkInt(*cv, i.getValue());
  else if (auto fl = dyn_cast<nd::FloatOp>(op)) mkFloat(*cv, fl.getValue().convertToDouble());
  else if (auto str = dyn_cast<nd::StringOp>(op)) mkStringWindow(*cv, str.getValue().str());
  else if (auto bl = dyn_cast<nd::BoolOp>(op)) mkBool(*cv, bl.getValue());
  else if (isa<nd::NullOp>(op)) mkNull(*cv);
  else mkPath(*cv, cast<nd::PathOp>(op).getValue().str());
  return s->fixed = cv;
}

/// The caller forces this value as the very next thing, so it is evaluated now, into its cell: the same work in the same order as making a
/// thunk and forcing it, with no thunk, no frame captured.  The cell is in its slot first and a blackhole while it is evaluated, so a
/// reference back to it is infinite recursion, as before; if the evaluation throws, the cell keeps the error (or, for anything but an
/// evaluation error, becomes the thunk a later force retries).
Value *EvalState::evalNow(Frame *f, Node *s, Value *nv) {
  nv->type = VType::Blackhole;
  try {
    evalOp(s, f, *nv);
  } catch (EvalError &) {
    fail(*nv);
    throw;
  } catch (...) {
    nv->type = VType::Thunk;
    nv->thunk.node = s;
    nv->thunk.env = f;
    throw;
  }
  if (statsEnabled) ++nEager;
  return nv;
}

Value *EvalState::makeCell(Frame *f, Node *s, bool forced) {
  if (!s) unindexed();
  if (s->fixed) return s->fixed; // a literal or a builtin: no frame to find, no cell to fill
  RegionInfo *ri = s->ri;
  unsigned idx = s->idx;
  while (f && f->info != ri) f = f->up();
  if (!f) throw EvalError("internal error: SSA value used outside its scope");
  Value *noCell = nullptr; // a value made by its one use, or an in-place one reached through lookup(): the cell is not kept in the frame
  Value *&slot = idx == kNoSlot ? noCell : f->slots[idx];
  if (slot) return slot;
  if (s->kind == NodeKind::Arg) throw EvalError("internal error: unbound block argument");
  if (s->how == Node::Const || s->how == Node::Builtin) return slot = makeFixed(s);
  Value *nv = allocValue();
  bool eager = forced && s->how == Node::Thunk && (idx != kNoSlot || s->promo == Promotion::Once || s->promo == Promotion::InPlace);
  if (eager) {
    slot = nv;
    return evalNow(f, s, nv);
  }
  nv->type = s->how == Node::Lambda ? VType::Lambda : VType::Thunk;
  nv->thunk.node = s;
  nv->thunk.env = f;
  if (statsEnabled) [[unlikely]] statCell(f, nv);
  return slot = nv;
}

/// Evaluates the defining op of an in-place value straight into `dest`.  Lambdas are
/// closures, built where lookup() would build them.
void EvalState::evalDefinition(Node *def, Frame *f, Value &dest) {
  if (def->kind == NodeKind::Lambda) {
    dest.type = VType::Lambda;
    dest.thunk.node = def;
    dest.thunk.env = f;
    if (statsEnabled && f) [[unlikely]] markPinned(f);
  } else {
    evalOp(def, f, dest);
  }
}

Value &EvalState::operand(Frame *f, Node *v, Value &tmp) {
  if (v && v->inPlace() && f && f->info == v->ri) {
    evalDefinition(v, f, tmp);
    return tmp;
  }
  return *lookupImpl(f, v, true);  // every caller of operand() forces what it gets
}

void EvalState::evalTail(Frame *f, Node *v, Value &out, PosPtr pos) {
  if (v && v->inPlace() && f && f->info == v->ri) {
    evalDefinition(v, f, out);
    return;
  }
  Value *p = lookupImpl(f, v, true);
  forceValue(*p, pos);
  out = *p;
}

//===----------------------------------------------------------------------===//
// Forcing
//===----------------------------------------------------------------------===//

namespace {
struct DepthGuard {
  unsigned &d;
  DepthGuard(unsigned &d) : d(d) { ++d; }
  ~DepthGuard() { --d; }
};
} // namespace

void EvalState::evalOpCounted(Node *n, Frame *env, Value &out) {
  statEval(n, env);
  n->eval(*this, n, env, out);
}

void EvalState::forceCell(Value &v, PosPtr pos) {
  if (v.type == VType::Thunk) {
    Node *n = v.thunk.node;
    Frame *env = v.thunk.env;
    v.type = VType::Blackhole;
    try {
      evalOp(n, env, v);
      if (statsEnabled && env) [[unlikely]] {
        statUnref(env);
      }
    } catch (EvalError &) {
      fail(v);
      throw;
    } catch (...) {
      v.type = VType::Thunk;
      v.thunk.node = n;
      v.thunk.env = env;
      throw;
    }
  } else if (v.type == VType::App) {
    Value *l = v.app.left, *r = v.app.right;
    v.type = VType::Blackhole;
    try {
      callFunction(*l, 1, &r, v, pos);
    } catch (...) {
      v.type = VType::App;
      v.app.left = l;
      v.app.right = r;
      throw;
    }
  } else if (v.type == VType::AttrApp) {
    Value *f = v.app.left, *x = v.app.right;
    Symbol name = Symbol(v.aux);
    v.type = VType::Blackhole;
    try {
      Value *args[2] = {newStringWindow(symbols[name]), x}; // the name's own bytes, in the symbol table
      callFunction(*f, 2, args, v, pos);
    } catch (...) {
      v.type = VType::AttrApp;
      v.aux = name;
      v.app.left = f;
      v.app.right = x;
      throw;
    }
  } else if (v.type == VType::Failed) {
    rethrowFailed(v);
  } else if (v.type == VType::Blackhole) {
    throw InfiniteRecursionError("infinite recursion encountered", pos);
  }
}

void EvalState::fail(Value &v) {
  v.failed = new (alloc.Allocate(sizeof(std::exception_ptr), alignof(std::exception_ptr))) std::exception_ptr(std::current_exception());
  v.type = VType::Failed;
}

template <class E> [[noreturn]] static void throwCopy(const E &e) {
  E c(e.msg.clone(), e.pos);
  for (const Trace &t : e.traces) c.traces.append(Trace{t.pos, t.msg.clone()});
  throw c;
}

/// A copy of the kept error, of its own type: the traces this throw gathers on its way out are its own, not the kept one's.
void EvalState::rethrowFailed(const Value &v) {
  try {
    std::rethrow_exception(*v.failed);
  } catch (ThrownError &e) { throwCopy(e); }
  catch (AssertionError &e) { throwCopy(e); }
  catch (Abort &e) { throwCopy(e); }
  catch (TypeError &e) { throwCopy(e); }
  catch (InfiniteRecursionError &e) { throwCopy(e); }
  catch (StackOverflowError &e) { throwCopy(e); }
  catch (EvalError &e) { throwCopy(e); }
}

void EvalState::forceValueDeep(Value &v) {
  cp::WordTable<char> seen; // a set: the cells walked, by address
  auto rec = [&](auto &self, Value &v) -> void {
    if (callDepth >= settings.maxCallDepth) throw StackOverflowError("stack overflow; max-call-depth exceeded");
    DepthGuard g(callDepth);
    forceValue(v);
    if (!seen.insert(uint64_t(uintptr_t(&v)), 1)) return;
    if (v.type == VType::Attrs) {
      for (auto &a : *v.attrs) {
        try {
          self(self, *a.value);
        } catch (EvalError &e) {
          e.addTrace(positionOf(a), cp::cat("while evaluating the attribute '", symbols[a.name], "'"));
          throw;
        }
      }
    } else if (v.type == VType::List) {
      for (size_t i = 0; i < v.listSize(); i++) self(self, *v.list.elems[i]);
    }
  };
  rec(rec, v);
}

int64_t EvalState::forceInt(Value &v, PosPtr pos, std::string_view c) {
  forceValue(v, pos);
  if (v.type != VType::Int) throwTypeError("an integer", v, pos, c);
  return v.integer;
}

double EvalState::forceFloat(Value &v, PosPtr pos, std::string_view c) {
  forceValue(v, pos);
  if (v.type == VType::Int) return (double)v.integer;
  if (v.type != VType::Float) throwTypeError("a float", v, pos, c);
  return v.fpoint;
}

bool EvalState::forceBool(Value &v, PosPtr pos, std::string_view c) {
  forceValue(v, pos);
  if (v.type != VType::Bool) throwTypeError("a Boolean", v, pos, c);
  return v.boolean;
}

void EvalState::forceAttrs(Value &v, PosPtr pos, std::string_view c) {
  forceValue(v, pos);
  if (v.type != VType::Attrs) throwTypeError("a set", v, pos, c);
}

void EvalState::forceList(Value &v, PosPtr pos, std::string_view c) {
  forceValue(v, pos);
  if (v.type != VType::List) throwTypeError("a list", v, pos, c);
}

void EvalState::forceFunction(Value &v, PosPtr pos, std::string_view c) {
  forceValue(v, pos);
  if (!v.isFunction() && !(v.type == VType::Attrs && v.attrs->get(s.functor)))
    throwTypeError("a function", v, pos, c);
}

std::string_view EvalState::forceString(Value &v, PosPtr pos, std::string_view c) {
  forceValue(v, pos);
  if (v.type != VType::String) throwTypeError("a string", v, pos, c);
  return v.sv();
}

std::string_view EvalState::forceString(Value &v, NixStringContext &ctx, PosPtr pos, std::string_view c) {
  auto s = forceString(v, pos, c);
  copyContext(v, ctx);
  return s;
}

std::string_view EvalState::forceStringNoCtx(Value &v, PosPtr pos, std::string_view c) {
  auto s = forceString(v, pos, c);
  if (v.str.ctx) {
    std::string_view first = v.str.ctx->elems[0];
    char head = first.empty() ? '\0' : first[0]; // first[0] of a standard string was the NUL of an empty one
    std::string_view what = head == '=' ? first.substr(1) : head == '!' ? first.substr(first.find('!', 1) + 1) : first;
    throw EvalError(cp::cat("the string '", s, "' is not allowed to refer to a store path (such as '", nixstore::baseNameOf(what), "')"), pos);
  }
  return s;
}

//===----------------------------------------------------------------------===//
// Function calls
//===----------------------------------------------------------------------===//

/// The demand half of the sea-of-nodes schedule (MLNIX_DEFER).  Rows of a FilePool accumulate as
/// lowering defers lambdas; the first call of a lambda drains its row: the body is parsed again from where
/// the lambda starts, by the same path as at lowering time, optimized, and indexed, and the row keeps
/// only its anchor, the indexed region.  Every later call reads the anchor.
static cp::Own<mlir::PassManager> makeOptimizer(mlir::MLIRContext &,
                                                        const EvalSettings &);

/// The pass pipeline as text: MLNIX_PIPELINE over the setting.
static cp::Text pipelineText(const EvalSettings &settings) {
  const char *e = getenv("MLNIX_PIPELINE");
  return e ? cp::Text(e) : settings.pipeline.clone();
}

RegionInfo *EvalState::mintLambda(nixfe::FilePool &p, uint32_t row) {
  uint64_t t0 = statsEnabled ? nixsys::monotonicNs() : 0;
  auto lam = cast<nd::LambdaOp>(p.rows.col<nixfe::PoolCol::Op>()[row]);
  if (lam.getBody().front().empty()) { // not minted ahead by the helper that prelowered the file
    nixfe::GenOptions go;
    go.isBaseName = baseNameOf;
    go.baseNames = this;
    go.deferBodies = true; // lambdas nested in this body wait for their own first call
    go.pool = &p;
    nixfe::mintBody(lam, p, row, go);
    if (settings.optimize) mlir::nix::devirtualizePrims(lam);
  }
  nixprefetch::noteMint(p.origin->path.c_str(), row);
  if (statsEnabled) {
    lam.getBody().walk([&](mlir::Operation *o) { ++countOf(opStats, o->getName()).n[0]; });
    ++nDemandMinted;
    nsMint += nixsys::monotonicNs() - t0;
  }
  p.drain(row);
  return regionInfo(&lam.getBody());
}

RegionInfo *EvalState::bodyOf(nixfe::BodyIndex idx) {
  nixfe::FilePool &p = *pools[idx.first()]; // the index was issued by the generator: unchecked
  return composite::anchor(p.rows.col<nixfe::PoolCol::Body>(), idx.second(),
                           [&](uint32_t row) { return mintLambda(p, row); });
}

/// The region of a lambda's body: the one hash lookup of a call, made once and passed down.
RegionInfo *EvalState::infoOfSlow(nd::LambdaOp lam) {
  mlir::IntegerAttr deferred = lam.getBodyIndexAttr(); // null when the body is in the op
  return deferred ? bodyOf(nixfe::BodyIndex(uint64_t(deferred.getInt()))) : regionInfo(&lam.getBody());
}

//===----------------------------------------------------------------------===//
// Error paths: the messages are built here, in functions of their own, and the compiler decides what to inline.
//===----------------------------------------------------------------------===//

static cp::Text lambdaDesc(nd::LambdaOp lam) {
  if (auto n = lam.getName()) return cp::cat("function '", *n, "'");
  return "function 'anonymous lambda'";
}
[[noreturn]] static void throwMissingArg(nd::LambdaOp lam, llvm::StringRef formal, PosPtr pos) {
  throw EvalError(cp::cat(lambdaDesc(lam), " called without required argument '", formal, "'"), pos).addTrace(nd::posOfOp(lam), "from call site");
}
[[noreturn]] static void throwUnexpectedArg(nd::LambdaOp lam, llvm::StringRef name, PosPtr pos) {
  throw EvalError(cp::cat(lambdaDesc(lam), " called with unexpected argument '", name, "'"), pos).addTrace(nd::posOfOp(lam), "from call site");
}
[[noreturn]] static void throwUndefinedVariable(const nixfe::Name &n, PosPtr pos) { throw EvalError(cp::cat("undefined variable '", n.str(), "'"), pos); }
[[noreturn]] static void throwMissingFormal(const nixfe::Name &n, PosPtr pos) { throw EvalError(cp::cat("missing formal argument '", n.str(), "'"), pos); }
[[noreturn]] static void throwCannotEvaluate(mlir::Operation *o, PosPtr pos) {
  throw EvalError(cp::cat("internal error: cannot evaluate operation '", o->getName().getStringRef(), "'"), pos);
}
[[noreturn]] static void throwAssertFailed(nd::AssertOp a, PosPtr pos) {
  auto txt = a.getText();
  throw AssertionError(cp::cat("assertion '", txt ? *txt : llvm::StringRef("?"), "' failed"), pos);
}
[[noreturn]] static void throwIntOverflow(int64_t n, int64_t m, PosPtr pos) {
  throw EvalError(cp::cat("integer overflow in adding ", n, " + ", m), pos);
}
[[noreturn]] static void throwCannotAdd(const char *type, const char *to, PosPtr pos) {
  throw EvalError(cp::cat("cannot add ", type, " to ", to), pos);
}
[[noreturn]] static void throwAttrMissing(llvm::StringRef name, PosPtr pos) { throw EvalError(cp::cat("attribute '", name, "' missing"), pos); }

void EvalState::callLambdaIn(Value &fun, RegionInfo *ri, Value *arg, Value &out, PosPtr pos) {
  auto lam = cast<nd::LambdaOp>(fun.thunk.node->def);
  if (ri->hasFormals) { // what the formals are was read once, at indexing: the op's attributes are read here only at a first call and on errors
    try {
      forceAttrs(*arg, pos, "while evaluating the value passed for the lambda argument");
    } catch (EvalError &e) {
      e.addTrace(nd::posOfOp(lam), cp::cat("while calling ", lambdaDesc(lam)));
      throw;
    }
    if (ri->formalsOf != lam.getOperation()) {
      auto formals = *lam.getFormals();
      if (statsEnabled) nFormalBytes += formals.size() * sizeof(Symbol);
      auto *syms = static_cast<Symbol *>(alloc.Allocate(formals.size() * sizeof(Symbol), alignof(Symbol)));
      for (size_t i = 0; i < formals.size(); i++) syms[i] = symbols.create(cast<StringAttr>(formals[i]).getValue());
      ri->formalSyms = syms;
      ri->formalsOf = lam.getOperation();
    }
    const Symbol *formalSyms = ri->formalSyms;
    const bool *defs = ri->formalDefaults;
    size_t nFound = 0;
    for (uint32_t i = 0, n = ri->nFormals; i < n; i++) {
      if (arg->attrs->get(formalSyms[i])) nFound++;
      else if (!defs[i])
        throwMissingArg(lam, cast<StringAttr>((*lam.getFormals())[i]).getValue(), pos);
    }
    if (!ri->ellipsis && nFound != arg->attrs->size()) {
      auto formals = *lam.getFormals();
      for (auto &a : *arg->attrs) {
        bool known = false;
        for (Attribute fa : formals)
          if (cast<StringAttr>(fa).getValue() == symbols[a.name]) { known = true; break; }
        if (!known) throwUnexpectedArg(lam, symbols[a.name], pos);
      }
    }
  }
  if (callDepth >= settings.maxCallDepth)
    throw StackOverflowError("stack overflow; max-call-depth exceeded", pos);
  DepthGuard g(callDepth);
  auto interpret = [&] {
    if (stackFrameOK(ri)) {
      // a body of strict ops over its one argument: the frame is two words and the argument, on the stack
      alignas(Frame) char buf[sizeof(Frame) + sizeof(Value *)];
      Frame *sf = ::new (static_cast<void *>(buf)) Frame{reinterpret_cast<uintptr_t>(fun.thunk.env), ri, {}};
      sf->slots[0] = arg;
      if (statsEnabled) ++nStackFrames;
      evalTail(sf, ri->resultNode, out, pos);
      return;
    }
    Frame *f = newFrame(ri, fun.thunk.env);
    f->slots[0] = arg;
    evalTail(f, ri->resultNode, out, pos);
    if (statsEnabled) [[unlikely]] statReturn(f);
  };
  interpret();
}

/// MLNIX_CHECK_KINDS=1: an op whose type fixes a kind (a typed primop: NixPrims.irdl.mlir's `irdl.is`) made a value of that kind.  A
/// declaration that names a kind the primop does not always make is caught here, on the call that broke it.
static const bool checkKinds = getenv("MLNIX_CHECK_KINDS") != nullptr;
void EvalState::checkResultKind(mlir::Operation *op, const Value &out) {
  mlir::Type t = op->getResult(0).getType();
  if (mlir::isa<nd::ValueType>(t)) return;
  bool ok = nd::isFnType(t) ? (out.type == VType::Lambda || out.type == VType::PrimOp || out.type == VType::PrimOpApp)
          : nd::isStringType(t) ? out.type == VType::String
          : mlir::isa<composite::Series2Type>(t) ? out.type == VType::Attrs
          : mlir::isa<composite::SeriesType>(t) ? out.type == (mlir::cast<composite::SeriesType>(t).getElement().isInteger(8) ? VType::Path : VType::List)
          : false;
  if (!ok) {
    llvm::SmallString<96> ty;
    llvm::raw_svector_ostream(ty) << t;
    throw EvalError(composite::cat("internal error: ", op->getName().getStringRef(), " is declared to make ", llvm::StringRef(ty),
                                   " but made a value of tag ", composite::str(int(out.type))), nd::posOfOp(op));
  }
}

void EvalState::callPrimOp(const PrimOp &op, Value **args, Value &out, PosPtr pos) {
  try {
    op.call(*this, args, out, pos);
  } catch (EvalError &e) {
    tracePrimOp(op, e, pos);
    throw;
  }
}

void EvalState::tracePrimOp(const PrimOp &op, EvalError &e, PosPtr pos) {
  if (op.name != "throw" && op.name != "abort" && op.name != "addErrorContext") e.addTrace(pos, "while calling the '" + op.name + "' builtin");
}

const PrimOp *EvalState::primOpByKey(llvm::StringRef key) {
  Value *v = baseEnvValue(key);
  return v && v->type == VType::PrimOp ? v->primOp : nullptr;
}

mlir::Attribute EvalState::foldPrimOp(llvm::StringRef key, llvm::ArrayRef<mlir::Attribute> args) {
  const PrimOp *op = primOpByKey(key);
  if (!op || op->arity != args.size()) return {};
  llvm::SmallVector<Value *, 4> vals;
  for (mlir::Attribute a : args) {
    Value *v = allocValue();
    if (auto b = mlir::dyn_cast<mlir::BoolAttr>(a)) mkBool(*v, b.getValue());
    else if (auto i = mlir::dyn_cast<mlir::IntegerAttr>(a)) mkInt(*v, i.getInt());
    else if (auto f = mlir::dyn_cast<mlir::FloatAttr>(a)) mkFloat(*v, f.getValueAsDouble());
    else if (auto s = mlir::dyn_cast<mlir::StringAttr>(a)) mkString(*v, s.getValue());
    else if (mlir::isa<mlir::UnitAttr>(a)) mkNull(*v);
    else return {};
    vals.push_back(v);
  }
  Value out;
  try {
    op->call(*this, vals.data(), out, nullptr);
    forceValue(out, nullptr);
  } catch (std::exception &) {
    return {}; // stays a run-time error, with its original position and trace
  }
  mlir::Builder b(&ctx);
  switch (out.type) {
  case VType::Int: return b.getI64IntegerAttr(out.integer);
  case VType::Float: return b.getF64FloatAttr(out.fpoint);
  case VType::Bool: return b.getBoolAttr(out.boolean);
  case VType::Null: return b.getUnitAttr();
  case VType::String:
    if (out.str.ctx && out.str.ctx->n) return {}; // keep contexts out of constants
    return b.getStringAttr(out.sv());
  default: return {};
  }
}

/// Which selector, if any, a curried lambda is, by the structure of its IR and not by its name or file: `c: x: if c then [x] else []`
/// (shape 2, lib.optional) or `c: x: if c then x else {}` (shape 3, lib.optionalAttrs).  Both lambdas take one plain argument, the outer
/// body is only the inner lambda, and the inner body is the `if` on the outer argument.  Anything else is shape 1.
unsigned EvalState::selectorShape(nd::LambdaOp outerLam, RegionInfo *outer) {
  if (outer->selShape) return outer->selShape;
  outer->selShape = 1;
  if (outerLam.getFormals()) return 1;
  auto *innerOp = outer->result.getDefiningOp();
  auto inner = dyn_cast_or_null<nd::LambdaOp>(innerOp);
  if (!inner || inner.getFormals()) return 1;
  RegionInfo *ri = infoOfSlow(inner);
  if (outer->region->front().getNumArguments() != 1 || ri->region->front().getNumArguments() != 1) return 1;
  mlir::Value c = outer->region->front().getArgument(0), x = ri->region->front().getArgument(0);
  auto iff = dyn_cast_or_null<nd::IfOp>(ri->result.getDefiningOp());
  if (!iff || iff.getCond() != c) return 1;
  outer->selPos = nd::posOfOp(iff);
  mlir::Operation *no = iff.getElseValue().getDefiningOp();
  if (auto list = dyn_cast_or_null<nd::ListOp>(iff.getThenValue().getDefiningOp())) {
    auto none = dyn_cast_or_null<nd::ListOp>(no);
    if (none && none.getElements().empty() && list.getElements().size() == 1 && list.getElements()[0] == x) return outer->selShape = 2;
  } else if (iff.getThenValue() == x) {
    auto none = dyn_cast_or_null<nd::AttrsOp>(no);
    if (none && none.getNames().empty() && none.getDynNames().empty()) return outer->selShape = 3;
  }
  return 1;
}

/// `c: x: if c then [x] else []` / `if c then x else {}` called with both arguments: the same work as the two calls with the frames and the
/// closure between them gone.  Out of line, so the loop that calls it stays small.
void EvalState::applySelector(unsigned shape, RegionInfo *ri, Value **a, Value &dest, PosPtr pos) {
  if (forceBool(*a[0], ri->selPos, "while evaluating a branch condition")) {
    if (shape == 2) { mkList(dest, 1); dest.list.elems[0] = a[1]; }
    else { forceValue(*a[1], pos); dest = *a[1]; }
  } else {
    dest = shape == 2 ? vEmptyList : vEmptyAttrs;
  }
  if (statsEnabled) ++nSelectorCalls;
}

void EvalState::notAFunction(Value &cur, PosPtr pos) {
  throw EvalError(cp::cat("attempt to call something which is not a function but ", showType(cur), ": ", printValueForTrace(cur)), pos);
}

void EvalState::callFunction(Value &fun, size_t nargs, Value **args, Value &out, PosPtr pos) {
  Value *cur = &fun;
  size_t i = 0;
  Value tmp;
  // The intermediate of a curried chain is a closure: (op, env), two words that the next step reads and nobody keeps.  It is
  // held by value here, not in a heap cell.  Anything that is not a closure may be kept (a partial application links to
  // it, a functor's `self` goes into a frame), so it is moved to a heap cell, and the stack cell never escapes.
  Value stackCells[2];
  if (nargs == 0) {
    forceValue(fun, pos);
    out = fun;
    return;
  }
  while (true) {
    forceValue(*cur, pos);
    nd::LambdaOp curLam;
    RegionInfo *curRI = nullptr;
    if (cur->type == VType::Lambda) {
      curLam = cast<nd::LambdaOp>(cur->thunk.node->def);
      curRI = bodyOfNode(cur->thunk.node); // the selector check and the call below both use it
      if (nargs - i >= 2 && !curRI->hasFormals) {
        if (unsigned shape = curRI->selShape ? curRI->selShape : selectorShape(curLam, curRI); shape >= 2) {
          Value *dest = (i + 2 == nargs) ? &out : allocValue();
          applySelector(shape, curRI, args + i, *dest, pos);
          i += 2;
          if (i >= nargs) return;
          cur = dest;
          continue;
        }
      }
    }
    Value *res = (i + 1 == nargs) ? &out : cur == &stackCells[0] ? &stackCells[1] : &stackCells[0];
    if (cur->type == VType::Lambda) {
      callLambdaIn(*cur, curRI, args[i], *res, pos);
      i++;
    } else if (cur->type == VType::PrimOp || cur->type == VType::PrimOpApp) {
      // The arguments applied so far are a chain of PrimOpApp cells, the newest outermost: count it to find the primop, then fill a fixed array from
      // the back, and drain the arguments of this call in after them.
      size_t applied = 0;
      Value *p = cur;
      while (p->type == VType::PrimOpApp) { ++applied; p = p->app.left; }
      const PrimOp *op = p->primOp;
      size_t need = op->arity - applied;
      size_t avail = nargs - i;
      if (avail < need) {
        // Partial application.
        Value *acc = cur;
        for (; i < nargs; i++) {
          Value *app = (i + 1 == nargs) ? &out : allocValue();
          Value *l = acc;
          if (app == &out && l == &out) { l = allocValue(); *l = out; }
          app->type = VType::PrimOpApp;
          app->app.left = l;
          app->app.right = args[i];
          acc = app;
        }
        return;
      }
      // With no chain upstream, the cells of this call are the primop's arguments where they lie: the reification is nothing.  A chain is
      // joined in front of them, so then the two are scanned and drained into one array.
      Value **all = args + i;
      Value *joined[kMaxPrimArity];
      if (applied) {
        size_t k = applied;
        for (Value *q = cur; q->type == VType::PrimOpApp; q = q->app.left) joined[--k] = q->app.right;
        cp::drain(cp::series(args + i, uint32_t(need)), joined + applied);
        all = joined;
      }
      i += need;
      res = (i == nargs) ? &out : allocValue();
      callPrimOp(*op, all, *res, pos);
    } else if (cur->type == VType::Attrs && cur->attrs->get(s.functor)) {
      const Attr *f = cur->attrs->get(s.functor);
      Value *self = cur;
      if (self == &out) { self = allocValue(); *self = *cur; }
      Value *fargs[2] = {self, args[i]};
      try {
        callFunction(*f->value, 2, fargs, *res, pos);
      } catch (EvalError &e) {
        e.addTrace(pos, "while calling a functor (an attribute set with a '__functor' attribute)");
        throw;
      }
      i++;
    } else {
      notAFunction(*cur, pos);
    }
    if (i >= nargs) return;
    if (res == &stackCells[0] || res == &stackCells[1]) {
      if (res->type == VType::Lambda) { if (statsEnabled) ++nStackCells; }
      else { Value *h = allocValue(); *h = *res; res = h; }
    }
    cur = res;
  }
}

void EvalState::autoCallFunction(const AutoArgs &autoArgs, Value &fun, Value &out) {
  forceValue(fun);
  if (fun.type == VType::Attrs && fun.attrs->get(s.functor)) {
    Value *v = allocValue();
    callFunction(*fun.attrs->get(s.functor)->value, fun, *v, nullptr);
    autoCallFunction(autoArgs, *v, out);
    return;
  }
  if (fun.type != VType::Lambda) {
    out = fun;
    return;
  }
  auto lam = cast<nd::LambdaOp>(fun.thunk.node->def);
  if (!lam.getFormals()) {
    out = fun;
    return;
  }
  BindingsBuilder bb(*this, lam.getFormals()->size()); // a row a formal at most
  auto defs = *lam.getFormalDefaults();
  for (size_t i = 0; i < lam.getFormals()->size(); i++) {
    llvm::StringRef name = cast<StringAttr>((*lam.getFormals())[i]).getValue();
    if (Value *const *found = autoArgs.find(name.data(), uint32_t(name.size()))) bb.insert(name, *found);
    else if (!defs[i])
      throw EvalError(cp::cat("cannot evaluate a function that has an argument without a value ('", name,
                              "')\nNix attempted to evaluate a function as a top level expression; in this case it must have its arguments supplied either by default values, or passed explicitly with '--arg' or '--argstr'. See https://nix.dev/manual/nix/stable/language/syntax.html#functions."),
                      nd::posOfOp(lam));
  }
  if (lam.getEllipsis())
    autoArgs.each([&](const AutoArgs::Row &r) { bb.insert(llvm::StringRef(r.key, r.len), r.v); });
  Value *arg = allocValue();
  mkAttrs(*arg, bb.finish());
  callFunction(fun, *arg, out, nullptr);
}

//===----------------------------------------------------------------------===//
// Op semantics
//===----------------------------------------------------------------------===//

PosIdx EvalState::positionIndex(PosPtr pos) {
  if (!pos) return 0;
  if (PosIdx *found = dynamicPositions.find(uint64_t(uintptr_t(pos)))) return *found;
  if (attributePositions.size() >= PosIdx(~PosIdx(0)))
    throw EvalError("attribute position table exhausted");
  PosIdx index = attributePositions.append(pos);
  dynamicPositions.insert(uint64_t(uintptr_t(pos)), index);
  return index;
}

PosIdx EvalState::positionBase(nd::AttrsOp op) {
  auto positions = op.getPositions();
  size_t count = cp::min(positions.size(), op.getNames().size());
  if (!count) return 0;
  if (PosIdx *found = attrPositionBases.find(uint64_t(uintptr_t(op.getOperation())))) return *found;
  if (count > PosIdx(~PosIdx(0)) - attributePositions.size())
    throw EvalError("attribute position table exhausted");
  PosIdx base = attributePositions.size();
  for (size_t i = 0; i < count; ++i)
    attributePositions.append(nd::posOfWord(uint64_t(positions[i])));
  attrPositionBases.insert(uint64_t(uintptr_t(op.getOperation())), base);
  return base;
}

/// Rows by name, in place, the first of equal names kept (Composite/Rows.h): the rows left.
static size_t sortRowsFirstWins(Attr *rows, size_t n) {
  cp::sortRows(rows, n, [](const Attr &a, const Attr &b) { return a.name < b.name; });
  return cp::uniqueFirst(rows, n, attrName);
}

// An op's operands are its node's: a select's are (base, dynamic keys, default), an attribute set's (values, dynamic names, dynamic values),
// has_attr's, formal's and apply's one operand and then the rest; the segments were read once, when the body was indexed.

void EvalState::evalAttrs(Node *node, Frame *env, Value &out) {
  if (node->flags & Node::kDynamic) return evalAttrsDynamic(node, env, out);
  const AttrsShape *shape = node->attrsShape;
  if (!shape) shape = node->attrsShape = attrsShapeOf(cast<nd::AttrsOp>(node->def));
  uint32_t m = shape->m;
  // A set of size 0 is the one constant: every empty set is the same cell.
  if (m == 0) { if (statsEnabled) ++nEmptyShared; return mkAttrs(out, vEmptyAttrs.attrs); }
  // The set is allocated at its size and the rows are written where they stay, in name order: no builder, no vector, no sort.  The values
  // are lazy operands, so making their cells in that order changes nothing.
  Node **values = node->operands;
  Bindings *b = allocBindings(m);
  Attr *rows = b->attrs;
  for (uint32_t k = 0; k < m; k++) {
    const AttrsShape::Row &r = shape->rows[k];
    rows[k] = Attr{r.sym, r.pos, lookup(env, values[r.operand])};
  }
  b->size_ = m;
  mkAttrs(out, b);
}

const AttrsShape *EvalState::attrsShapeOf(nd::AttrsOp op) {
  auto names = op.getNames();
  auto positions = op.getPositions(); // one position word per name, or none
  PosIdx posBase = positionBase(op);
  uint32_t n = uint32_t(names.size());
  struct Row { Symbol s; uint32_t i; };
  Row stackRows[32];
  Row *rows = n <= 32 ? stackRows : static_cast<Row *>(alloc.Allocate(n * sizeof(Row), alignof(Row)));
  for (uint32_t i = 0; i < n; i++) rows[i] = {symbolOf(names[i]), i};
  cp::sortRows(rows, n, [](const Row &a, const Row &b) { return a.s < b.s; }); // stable: equal names keep their source order
  uint32_t m = uint32_t(cp::uniqueFirst(rows, n, [](const Row &r) { return r.s; }));
  auto *shape = static_cast<AttrsShape *>(alloc.Allocate(sizeof(AttrsShape) + m * sizeof(AttrsShape::Row), alignof(AttrsShape)));
  shape->m = m;
  for (uint32_t k = 0; k < m; k++) {
    uint32_t i = rows[k].i;
    shape->rows[k] = {i, rows[k].s, i < positions.size() ? posBase + PosIdx(i) : PosIdx(0)};
  }
  return shape;
}

/// Dynamic attributes are inserted one by one with duplicate checks: out of line, where the table of names lives.
void EvalState::evalAttrsDynamic(Node *node, Frame *env, Value &out) {
  auto op = cast<nd::AttrsOp>(node->def);
  auto names = op.getNames();
  Node **values = node->operands;
  size_t nDynNames = (node->nOperands - node->nDyn) / 2;     // the dynamic names, then their values
  Node **dynNames = node->operands + node->nDyn, **dynValues = dynNames + nDynNames;
  auto positions = op.getPositions();
  PosIdx posBase = positionBase(op);
  BindingsBuilder bb(*this, names.size() + nDynNames); // the static names and the dynamic ones (one that is null adds none)
  for (size_t i = 0; i < names.size(); i++) {
    PosIdx p = i < positions.size() ? posBase + i : 0;
    bb.insertIndexed(symbolOf(names[i]), lookup(env, values[i]), p);
  }
  // The names defined so far, by symbol (+1: the key 0 is no key): a dynamic name's position, a static name's null (the set's own is shown).
  cp::WordTable<PosPtr> seen;
  for (size_t i = 0; i < names.size(); i++)
    seen.insert(uint64_t(symbolOf(names[i])) + 1, nullptr);
  for (size_t j = 0; j < nDynNames; j++) {
    Value *nv = lookupForced(env, dynNames[j]); // forced next: a cell made here is made evaluated
    PosPtr p = dynNames[j]->pos();
    forceValue(*nv, p);
    if (nv->type == VType::Null) continue;
    auto name = forceStringNoCtx(*nv, p, "while evaluating the name of a dynamic attribute");
    Symbol sym = symbolOfString(name);
    if (PosPtr *defined = seen.find(uint64_t(sym) + 1))
      throw EvalError(cp::cat("dynamic attribute '", name, "' already defined at ", showPos(*defined ? *defined : nd::posOfOp(op))), p);
    seen.insert(uint64_t(sym) + 1, p);
    bb.insert(sym, lookup(env, dynValues[j]), p);
  }
  mkAttrs(out, bb.finish());
}

// evalConcatStrings' composition is hollowed into lowered/nixeval/ConcatOps.mlir (trikeshed.combineAll / drain and the
// scf.for accumulation), lowered by --trikeshed-lower-cursors into NixEval.  The per-part forcing (lookupForced /
// forceValue), coercion (coerceToWindow), context merging (own.add) and the error wording (throwCannotAdd /
// throwIntOverflow) stay C++ callbacks; the int add + overflow test, the int->float promotion, the float adds and the
// window collection (views[nv], total) are MLIR.  The PATH case's concat is a combineAll drained once into the Text;
// canonPath and mkPath stay here.  ConcatRec / ConcatResult layouts are the .mlir's record / result (asserted below).
struct ConcatCtx { EvalState *st; Frame *env; Node **parts; NixStringContext *context; cp::Text *scratch; PieceContexts *own; };
struct ConcatRec { uint8_t ft, kind; int64_t payload; composite::Chars w; };
struct ConcatResult { int64_t firstType, n; double nf; int64_t nv, total; };
static_assert(offsetof(ConcatRec, payload) == 8 && offsetof(ConcatRec, w) == 16 && sizeof(ConcatRec) == 32);
static_assert(offsetof(ConcatResult, nf) == 16 && offsetof(ConcatResult, nv) == 24 && offsetof(ConcatResult, total) == 32 && sizeof(ConcatResult) == 40);
extern "C" {
void nixev_ts_concat_parts(ConcatCtx *ctx, int64_t np, int64_t forceString, composite::Chars *views, ConcatResult *res);
int64_t nixev_ts_path_concat(const composite::Chars *pieces, int64_t np, char *into);
void nixev_cc_part(ConcatCtx *c, int64_t k, int64_t ft, int64_t isFirst, ConcatRec *rec) {
  Node *pv = c->parts[k]; PosPtr ppos = pv->pos();
  Value *v = c->st->lookupForced(c->env, pv); c->st->forceValue(*v, ppos);
  VType ftt = isFirst ? v->type : VType(ft); rec->ft = uint8_t(ftt);
  if (ftt == VType::Int || ftt == VType::Float) {
    if (v->type == VType::Int) { rec->kind = 1; rec->payload = v->integer; }
    else if (v->type == VType::Float) { rec->kind = 2; __builtin_memcpy(&rec->payload, &v->fpoint, 8); }
    else throwCannotAdd(EvalState::showType(*v), ftt == VType::Int ? "an integer" : "a float", ppos);
  } else {
    const StringContext *pc = nullptr;
    composite::Chars w = c->st->coerceToWindow(*v, *c->context, false, ftt == VType::String, ppos, "while evaluating a path segment", *c->scratch, !isFirst, &pc);
    c->own->add(pc, *c->context);
    if (w.size() && w.data() == c->scratch->data()) w = composite::chars(c->st->copyString(*c->scratch), w.size()); // text made here lives in the arena
    rec->kind = 0; rec->payload = w.size(); rec->w = w;
  }
}
[[noreturn]] void nixev_cc_overflow(ConcatCtx *c, int64_t k, int64_t n, int64_t x) { throwIntOverflow(n, x, c->parts[k]->pos()); }
}

void EvalState::evalConcatStrings(Node *node, Frame *env, Value &out) {
  // The result is the series of its parts.  A part that is already a string is a view of its arena bytes: no copy and no
  // heap string; only a part that must be coerced makes text, copied into the arena at once in the callback.  The total
  // is known before anything is written, so the result is one arena buffer, filled once.  Numbers and paths are as they were.
  auto parts = node->args();
  bool forceString = node->flags & Node::kForceString;
  NixStringContext context;
  size_t np = parts.size();
  composite::Chars stackViews[16];
  composite::Chars *views = np <= 16 ? stackViews : static_cast<composite::Chars *>(alloc.Allocate(np * sizeof(composite::Chars), alignof(composite::Chars)));
  cp::Text scratch;
  PieceContexts own; // the string pieces' own contexts: shared as the result's when there is one, merged only when there are several
  ConcatCtx ctx{this, env, node->operands, &context, &scratch, &own};
  ConcatResult r;
  nixev_ts_concat_parts(&ctx, int64_t(np), int64_t(forceString), views, &r);
  PosPtr pos = node->pos();
  if (r.firstType == int64_t(VType::Int)) return mkInt(out, r.n);
  if (r.firstType == int64_t(VType::Float)) return mkFloat(out, r.nf);
  if (r.firstType == int64_t(VType::Path)) {
    if (own.any(context))
      throw EvalError("a string that refers to a store path cannot be appended to a path", pos);
    cp::Text str;
    str.reserve(size_t(r.total)); str.resize(size_t(r.total));
    nixev_ts_path_concat(views, r.nv, str.begin());
    return mkPath(out, nixfe::canonPath(str));
  }
  nixev_ts_concat(this, views, r.nv, &out, own.result(*this, context));
}

Symbol EvalState::pathSymbol(const nixfe::Name &comp, Node *const *dyn, unsigned &nextDyn, Frame *env,
                             PosPtr pos) {
  if (!comp.isNull()) return symbolOf(comp);
  return symbolOfString(forceStringNoCtx(*lookupForced(env, dyn[nextDyn++]), pos, "while evaluating an attribute name"));
}

Value *EvalState::selectField(Value &base, Symbol key, PosPtr pos, uint32_t &guess) {
  forceValue(base, pos);
  if (base.type != VType::Attrs)
    throwTypeError("a set", base, pos, "while selecting an attribute");
  if (const Attr *attr = base.attrs->getGuess(key, guess)) return attr->value;
  throwAttrMissing(symbols[key], pos);
}

Value *EvalState::selectField(Value &base, Symbol key, PosPtr pos) {
  forceValue(base, pos);
  if (base.type != VType::Attrs)
    throwTypeError("a set", base, pos, "while selecting an attribute");
  if (const Attr *attr = base.attrs->get(key)) return attr->value;
  throwAttrMissing(symbols[key], pos);
}

void EvalState::statEval(Node *n, Frame *env) {
  Operation *op = n->def;
  ++countOf(evalsByKind, op->getName()).n[0];
  if (env) {
    ++env->info->nEvals;
    if (uint32_t *found = env->info->opIdx.find(uint64_t(uintptr_t(op)))) env->info->everRan[*found >> 6] |= 1ull << (*found & 63);
  }
}

// The evaluation of each kind of node, one function a kind (Node::eval).  An operand is read through its record (n->operands); the op's
// attributes (names, paths, literals) from the op (n->def).
namespace {
inline void copyFrom(EvalState &st, Value *v, Value &out, PosPtr pos) {
  st.forceValue(*v, pos);
  out = *v;
}

void evalApply(EvalState &st, Node *n, Frame *env, Value &out) {
  Node **x = n->operands;
  Value *f = st.lookupImpl(env, x[0], true); // callFunction forces the callee before anything else it does
  size_t na = n->nOperands - 1;
  auto cells = cp::series(x + 1, na) |cp::α| [&](Node *a) { return st.lookup(env, a); }; // the argument cells, drained into a stack array (arena past six)
  Value *buf[6];
  Value **args = na <= 6 ? buf : st.allocList(na);
  cp::drain(cells, args);
  st.callFunction(*f, na, args, out, n->pos());
}

void evalSelect(EvalState &st, Node *n, Frame *env, Value &out) {
  Node **x = n->operands;
  PosPtr pos = n->pos();
  Node *const *dyn = x + 1;
  Node *def = n->flags & Node::kDefault ? x[1 + n->nDyn] : nullptr;
  bool dynamic = n->nDyn != 0;
  Value tb;
  Value *cur = dynamic ? st.lookup(env, x[0]) : &st.operand(env, x[0], tb);
  unsigned nextDyn = 0;
  bool first = true; // the first name has the node's row guess
  for (const nixfe::Name &comp : cast<nd::SelectOp>(n->def).getPath()) {
    Symbol sym = st.pathSymbol(comp, dyn, nextDyn, env, pos);
    if (!def) {
      cur = first ? st.selectField(*cur, sym, pos, n->rowGuess) : st.selectField(*cur, sym, pos);
      first = false;
      continue;
    }
    st.forceValue(*cur, pos);
    if (cur->type != VType::Attrs) return copyFrom(st, st.lookupImpl(env, def, true), out, pos);
    const Attr *a = first ? cur->attrs->getGuess(sym, n->rowGuess) : cur->attrs->get(sym);
    first = false;
    if (!a) return copyFrom(st, st.lookupImpl(env, def, true), out, pos);
    cur = a->value;
  }
  copyFrom(st, cur, out, pos);
}

void evalIf(EvalState &st, Node *n, Frame *env, Value &out) {
  Value tc;
  PosPtr pos = n->pos();
  bool c = st.forceBool(st.operand(env, n->operands[0], tc), pos, "while evaluating a branch condition");
  st.evalTail(env, n->operands[c ? 1 : 2], out, pos);
}

void evalAttrsNode(EvalState &st, Node *n, Frame *env, Value &out) { st.evalAttrs(n, env, out); }

template <bool equal> void evalEq(EvalState &st, Node *n, Frame *env, Value &out) {
  Value ta, tb;
  PosPtr pos = n->pos();
  Value &ra = st.operand(env, n->operands[0], ta);
  st.forceValue(ra, pos);
  Value &rb = st.operand(env, n->operands[1], tb);
  st.forceValue(rb, pos);
  Value a = ra, b = rb;
  st.mkBool(out, st.eqValues(a, b, pos) == equal);
}

void evalHasAttr(EvalState &st, Node *n, Frame *env, Value &out) {
  Node **x = n->operands;
  PosPtr pos = n->pos();
  Node *const *dyn = x + 1;
  Value tb;
  Value *cur = n->nDyn ? st.lookup(env, x[0]) : &st.operand(env, x[0], tb);
  unsigned nextDyn = 0;
  bool first = true; // the first name has the node's row guess
  for (const nixfe::Name &comp : cast<nd::HasAttrOp>(n->def).getPath()) {
    st.forceValue(*cur, pos);
    Symbol sym = st.pathSymbol(comp, dyn, nextDyn, env, pos);
    if (cur->type != VType::Attrs) return st.mkBool(out, false);
    const Attr *a = first ? cur->attrs->getGuess(sym, n->rowGuess) : cur->attrs->get(sym);
    first = false;
    if (!a) return st.mkBool(out, false);
    cur = a->value;
  }
  st.mkBool(out, true);
}

void evalList(EvalState &st, Node *n, Frame *env, Value &out) { st.mkList(out, n->args() |cp::α| [&](Node *e) { return st.lookup(env, e); }); }
void evalString(EvalState &st, Node *n, Frame *, Value &out) { st.mkStringWindow(out, cast<nd::StringOp>(n->def).getValue().str()); }

void evalAnd(EvalState &st, Node *n, Frame *env, Value &out) {
  Value t1, t2;
  PosPtr pos = n->pos();
  if (!st.forceBool(st.operand(env, n->operands[0], t1), pos, "in the left operand of the AND (&&) operator")) return st.mkBool(out, false);
  st.mkBool(out, st.forceBool(st.operand(env, n->operands[1], t2), pos, "in the right operand of the AND (&&) operator"));
}
void evalOr(EvalState &st, Node *n, Frame *env, Value &out) {
  Value t1, t2;
  PosPtr pos = n->pos();
  if (st.forceBool(st.operand(env, n->operands[0], t1), pos, "in the left operand of the OR (||) operator")) return st.mkBool(out, true);
  st.mkBool(out, st.forceBool(st.operand(env, n->operands[1], t2), pos, "in the right operand of the OR (||) operator"));
}
void evalImpl(EvalState &st, Node *n, Frame *env, Value &out) {
  Value t1, t2;
  PosPtr pos = n->pos();
  if (!st.forceBool(st.operand(env, n->operands[0], t1), pos, "in the left operand of the IMPL (->) operator")) return st.mkBool(out, true);
  st.mkBool(out, st.forceBool(st.operand(env, n->operands[1], t2), pos, "in the right operand of the IMPL (->) operator"));
}
void evalNot(EvalState &st, Node *n, Frame *env, Value &out) {
  Value t;
  st.mkBool(out, !st.forceBool(st.operand(env, n->operands[0], t), n->pos(), "in the argument of the not operator"));
}

void evalUpdate(EvalState &st, Node *n, Frame *env, Value &out) {
  Value tl, tr;
  PosPtr pos = n->pos();
  Value *l = &st.operand(env, n->operands[0], tl);
  st.forceAttrs(*l, pos, "in the left operand of the update (//) operator");
  Value *r = &st.operand(env, n->operands[1], tr);
  st.forceAttrs(*r, pos, "in the right operand of the update (//) operator");
  if (l->attrs->empty()) { out = *r; return; }
  if (r->attrs->empty()) { out = *l; return; }
  st.mkAttrs(out, st.updateAttrs(l->attrs, r->attrs));
}

void evalConcatLists(EvalState &st, Node *n, Frame *env, Value &out) {
  Value tl, tr;
  PosPtr pos = n->pos();
  Value *l = &st.operand(env, n->operands[0], tl);
  st.forceList(*l, pos, "in the left operand of the list concatenation operator");
  Value *r = &st.operand(env, n->operands[1], tr);
  st.forceList(*r, pos, "in the right operand of the list concatenation operator");
  if (l->listSize() == 0) { out = *r; return; }
  if (r->listSize() == 0) { out = *l; return; }
  st.concatLists(*l, *r, out);
}

void evalConcatStringsNode(EvalState &st, Node *n, Frame *env, Value &out) { st.evalConcatStrings(n, env, out); }

void evalFormal(EvalState &st, Node *n, Frame *env, Value &out) {
  auto f = cast<nd::FormalOp>(n->def);
  PosPtr pos = n->pos();
  Value *arg = st.lookup(env, n->operands[0]);
  st.forceAttrs(*arg, pos);
  if (const Attr *a = arg->attrs->getGuess(st.symbolOf(f.getName()), n->rowGuess)) return copyFrom(st, a->value, out, pos);
  if (n->nOperands < 2) throwMissingFormal(f.getName(), pos);
  copyFrom(st, st.lookupImpl(env, n->operands[1], true), out, pos);
}

void evalWithVar(EvalState &st, Node *n, Frame *env, Value &out) {
  auto w = cast<nd::WithVarOp>(n->def);
  PosPtr pos = n->pos();
  Symbol sym = st.symbolOf(w.getName());
  for (Node *sc : n->args()) {
    Value *sv = st.lookup(env, sc);
    st.forceAttrs(*sv, sc->pos(), "while evaluating the first subexpression of a with expression");
    if (const Attr *a = sv->attrs->get(sym)) return copyFrom(st, a->value, out, pos);
  }
  throwUndefinedVariable(w.getName(), pos);
}

void evalAssert(EvalState &st, Node *n, Frame *env, Value &out) {
  Value tc;
  PosPtr pos = n->pos();
  bool c = st.forceBool(st.operand(env, n->operands[0], tc), pos, "in the condition of the assert statement");
  if (!c) throwAssertFailed(cast<nd::AssertOp>(n->def), pos);
  st.evalTail(env, n->operands[1], out, pos);
}

void evalPrim(EvalState &st, Node *n, Frame *env, Value &out) { // an op of a continent dialect: its primop, found once, on its operands' cells
  if (!n->prim) n->prim = st.primFor(n->def);
  Value *args[8];
  unsigned first = n->flags; // the operand the primop forces before anything else, plus one: its cell is made evaluated, not a thunk
  for (unsigned i = 0; i < n->nOperands; i++) {
    if (i + 1 != first) [[likely]] {
      args[i] = st.lookup(env, n->operands[i]);
      continue;
    }
    try {
      args[i] = st.lookupForced(env, n->operands[i]);
    } catch (EvalError &e) { // where the primop would have forced it: under the frame callPrimOp gives the primop's own errors
      st.tracePrimOp(*n->prim, e, n->pos());
      throw;
    }
  }
  st.callPrimOp(*n->prim, args, out, n->pos());
  if (checkKinds) [[unlikely]] st.checkResultKind(n->def, out);
}

void evalInt(EvalState &st, Node *n, Frame *, Value &out) { st.mkInt(out, cast<nd::IntOp>(n->def).getValue()); }
void evalBool(EvalState &st, Node *n, Frame *, Value &out) { st.mkBool(out, cast<nd::BoolOp>(n->def).getValue()); }
void evalNull(EvalState &st, Node *, Frame *, Value &out) { st.mkNull(out); }
void evalFloat(EvalState &st, Node *n, Frame *, Value &out) { st.mkFloat(out, cast<nd::FloatOp>(n->def).getValue().convertToDouble()); }
void evalPath(EvalState &st, Node *n, Frame *, Value &out) { st.mkPath(out, cast<nd::PathOp>(n->def).getValue().str()); }
void evalBuiltin(EvalState &st, Node *n, Frame *, Value &out) {
  copyFrom(st, st.baseEnvValue(cast<nd::BuiltinOp>(n->def).getName().str()), out, n->pos());
}

/// Anything else runs through the externally attached NixEvalOpInterface model, which reads its operands by their SSA values: their
/// records are put in the map of every value first.
void evalOther(EvalState &st, Node *n, Frame *env, Value &out) {
  Operation *op = n->def;
  for (unsigned i = 0; i < n->nOperands; i++)
    if (n->operands[i] && !st.nodeOf(op->getOperand(i).getAsOpaquePointer())) st.setNode(op->getOperand(i).getAsOpaquePointer(), n->operands[i]);
  if (auto e = dyn_cast<nd::NixEvalOpInterface>(op)) return e.eval(st, env, out);
  throwCannotEvaluate(op, n->pos());
}

constexpr EvalFn kEvalFns[] = {
    /* Arg */ evalOther, evalList, evalAttrsNode, evalSelect, evalHasAttr, evalApply, evalIf, evalAssert, evalNot, evalAnd, evalOr, evalImpl,
    evalEq<true>, evalEq<false>, evalUpdate, evalConcatLists, evalConcatStringsNode, evalWithVar, evalFormal, evalInt, evalBool, evalNull,
    evalFloat, evalString, evalPath, evalBuiltin, /* Lambda */ evalOther, evalPrim, evalOther};
static_assert(sizeof(kEvalFns) / sizeof(kEvalFns[0]) == unsigned(NodeKind::Other) + 1, "one evaluation function a node kind");
} // namespace

static EvalFn evalFnOf(NodeKind k) { return kEvalFns[unsigned(k)]; }

//===----------------------------------------------------------------------===//
// Coercion
//===----------------------------------------------------------------------===//

bool EvalState::isDerivation(Value &v) {
  if (v.type != VType::Attrs) return false;
  const Attr *t = v.attrs->get(s.type);
  if (!t) return false;
  forceValue(*t->value);
  return t->value->type == VType::String && t->value->sv() == "derivation";
}

cp::Maybe<cp::Text> EvalState::tryAttrsToString(Value &v, NixStringContext &ctx, bool coerceMore, bool copyToStore) {
  const Attr *f = v.attrs->get(s.toString);
  if (!f) return {};
  Value *r = allocValue();
  callFunction(*f->value, v, *r, nullptr);
  return coerceToString(*r, ctx, coerceMore, copyToStore, nullptr,
                        "while evaluating the result of the `__toString` attribute");
}

composite::Chars EvalState::coerceToWindow(Value &v, NixStringContext &ctx, bool coerceMore, bool copyToStore,
                                                 PosPtr pos, std::string_view errorCtx, cp::Text &scratch,
                                                 bool canonicalizePath, const StringContext **own) {
  forceValue(v, pos);
  if (v.type == VType::String) {
    if (own) *own = v.str.ctx;
    else copyContext(v, ctx);
    return v.window();
  }
  if (v.type == VType::Attrs) { // a set is the string its __toString returns or its outPath: a string value either way, so a window, not text made here
    if (const Attr *f = v.attrs->get(s.toString)) {
      Value *r = allocValue();
      callFunction(*f->value, v, *r, nullptr);
      return coerceToWindow(*r, ctx, coerceMore, copyToStore, nullptr, "while evaluating the result of the `__toString` attribute", scratch,
                            true, own);
    }
    if (const Attr *o = v.attrs->get(s.outPath))
      return coerceToWindow(*o->value, ctx, coerceMore, copyToStore, pos, "while evaluating the `outPath` attribute", scratch,
                            canonicalizePath, own);
  }
  scratch = coerceToString(v, ctx, coerceMore, copyToStore, pos, errorCtx, canonicalizePath);
  return composite::chars(std::string_view(scratch));
}

// coerceToString's, eqValues' and lessThan's algorithms are hollowed into lowered/nixeval/CoerceOps.mlir and
// CmpOps.mlir (trikeshed.at / compare over the cells and bytes, scf.while / scf.for walks, func.call recursion),
// lowered by --trikeshed-lower-cursors and linked into NixEval.  The methods below are thin bridges; the callbacks
// keep what only C++ can do: forcing (the inline forceValue check and the stats census), the error wording (the
// throws), the attribute lookups, copyPathToStore, the number text (cp::str / fixedFloat), the Text writes and the
// list element's recursive coercion under its try/catch addTrace.  errorCtx crosses as raw bytes, never a
// std::string_view (its ABI differs per platform).
extern "C" {
int64_t nixev_ts_eq(EvalState *st, Value *v1, Value *v2, PosPtr pos);
int64_t nixev_ts_lt(EvalState *st, Value *v1, Value *v2, PosPtr pos);
void nixev_ts_coerce(EvalState *st, Value *v, NixStringContext *ctx, int64_t coerceMore, int64_t copyToStore,
                     PosPtr pos, int64_t canonicalizePath, const char *errorCtx, int64_t errorCtxLen, cp::Text *out);
void nixev_cmp_force(EvalState *st, Value *v, PosPtr pos) { st->forceValue(*v, pos); }
[[noreturn]] void nixev_cmp_eq_throw(EvalState *st, Value *v1, Value *v2, PosPtr pos) {
  throw EvalError(cp::cat("cannot compare ", EvalState::showType(*v1), " with ", EvalState::showType(*v2)), pos);
}
[[noreturn]] void nixev_cmp_lt_inc(EvalState *st, Value *v1, Value *v2, PosPtr pos) {
  throw EvalError(cp::cat("cannot compare ", EvalState::showType(*v1), " with ", EvalState::showType(*v2),
                          "; values of that type are incomparable"), pos);
}
// the outPath attribute (which 0) or the __toString attribute (which 1) of a set
const Attr *nixev_attr_get(EvalState *st, Value *v, int64_t which) {
  return v->attrs->get(which == 0 ? st->s.outPath : st->s.toString);
}
[[noreturn]] void nixev_coerce_throw(EvalState *st, Value *v, PosPtr pos, const char *errorCtx, int64_t errorCtxLen) {
  TypeError e(cp::cat("cannot coerce ", EvalState::showType(*v), " to a string: ", st->printValueForTrace(*v)), pos);
  if (errorCtxLen) e.addTrace(pos, cp::Text(std::string_view(errorCtx, size_t(errorCtxLen))));
  throw e;
}
void nixev_text_set(cp::Text *out, const char *p, int64_t n) { *out = cp::Text(p, size_t(n)); }
void nixev_text_put(cp::Text *out, const char *p, int64_t n) { out->put(p, size_t(n)); }
void nixev_int_text(cp::Text *out, int64_t x) { *out = cp::str(x); }
void nixev_float_text(cp::Text *out, double d) { *out = nixfe::fixedFloat(d); }
void nixev_copy_path(EvalState *st, NixStringContext *ctx, const char *p, int64_t n, cp::Text *out) {
  *out = st->copyPathToStore(*ctx, std::string_view(p, size_t(n)));
}
// one list element: the recursion (canonicalizePath true, the default argument the C++ loop gave it), its piece
// appended to the result and freed here; the EvalError keeps its trace
void nixev_coerce_elem(EvalState *st, Value *e, NixStringContext *ctx, int64_t coerceMore, int64_t copyToStore,
                       PosPtr pos, const char *errorCtx, int64_t errorCtxLen, cp::Text *result) {
  try {
    cp::Text piece = st->coerceToString(*e, *ctx, coerceMore != 0, copyToStore != 0, pos,
                                        std::string_view(errorCtx, size_t(errorCtxLen)));
    result->put(piece.data(), piece.size());
  } catch (EvalError &err) {
    err.addTrace(pos, "while evaluating one element of the list");
    throw;
  }
}
}

cp::Text EvalState::coerceToString(Value &v, NixStringContext &ctx, bool coerceMore, bool copyToStore,
                                   PosPtr pos, std::string_view errorCtx, bool canonicalizePath) {
  cp::Text out;
  nixev_ts_coerce(this, &v, &ctx, int64_t(coerceMore), int64_t(copyToStore), pos, int64_t(canonicalizePath),
                  errorCtx.data(), int64_t(errorCtx.size()), &out);
  return out;
}

cp::Text EvalState::copyPathToStore(NixStringContext &ctx, std::string_view path) {
  cp::Text base = nixstore::baseNameOf(path);
  if (base.ends_with(".drv"))
    throw EvalError("file names are not allowed to end in '.drv'");
  const char *dst;
  if (const char **hit = srcToStore.find(path.data(), uint32_t(path.size()))) {
    dst = *hit;
  } else {
    cp::Text real(path);
    if (nixstore::isInStore(store->storeDir(), path)) real = store->toReal(path);
    if (!nixstore::pathExists(real)) throw EvalError(cp::cat("path '", path, "' does not exist"));
    try {
      dst = copyString(store->addToStore(base, real));
    } catch (nixstore::Error &e) {
      throw EvalError(e.what());
    }
    srcToStore.set(path.data(), uint32_t(path.size()), dst, [&] { return copyString(path); });
  }
  ctx.insert(dst);
  return dst;
}

cp::Text EvalState::coerceToPath(Value &v, NixStringContext &ctx, PosPtr pos, std::string_view errorCtx) {
  forceValue(v, pos);
  if (v.type == VType::Path) return cp::Text(v.pathView());
  cp::Text p = coerceToString(v, ctx, false, false, pos, errorCtx);
  if (p.empty() || p[0] != '/') {
    EvalError e(cp::cat("string '", p, "' doesn't represent an absolute path"), pos);
    if (!errorCtx.empty()) e.addTrace(pos, cp::Text(errorCtx));
    throw e;
  }
  return p;
}

//===----------------------------------------------------------------------===//
// Comparison
//===----------------------------------------------------------------------===//

bool EvalState::eqValues(Value &v1, Value &v2, PosPtr pos) { return nixev_ts_eq(this, &v1, &v2, pos) != 0; }

bool EvalState::lessThan(Value &v1, Value &v2, PosPtr pos) { return nixev_ts_lt(this, &v1, &v2, pos) != 0; }

//===----------------------------------------------------------------------===//
// Printing
//===----------------------------------------------------------------------===//

/// A cell or set met before, by its address (a set: the WordTable's values say nothing).
static bool firstTime(cp::WordTable<char> &seen, const void *p) { return seen.insert(uint64_t(uintptr_t(p)), 1); }

// The value printer's fixed bytes are hollowed into lowered/nixeval/PrintValueOps.mlir (trikeshed.slice / text / at /
// fold / series / combine / drain over a constant word table), lowered by --trikeshed-lower-cursors into NixEval.
// nixev_ts_pv(kind, a, b, into, cap) drains into room reserved here and returns how many it wrote: kind 0 the fixed
// word a (a PvWord), kind 1 the integer a in decimal, kind 2 the elision "«a unit elided»" (unit b: 0 byte, 1 attribute,
// 2 item; singular when a == 1).  The recursion / forcing / seen-table / depth guard and the name sorting stay here.
extern "C" size_t nixev_ts_pv(int32_t kind, int64_t a, int64_t b, char *into, size_t cap);
enum PvWord : int32_t { PV_true, PV_false, PV_null, PV_repeated, PV_setOpen, PV_eq, PV_semi, PV_setClose, PV_listOpen, PV_space, PV_listClose,
  PV_code, PV_infinite, PV_lambda, PV_primop, PV_primopApp, PV_error, PV_guilClose, PV_derivation, PV_setElide, PV_listElide, PV_lambdaTrace,
  PV_at, PV_primopTrace, PV_primopAppTrace, PV_thunk, PV_semiTrace, PV_guilOpen, PV_elidedTail, PV_question = 35, PV_setOpenTrace, PV_setCloseTrace, PV_listOpenTrace, PV_listCloseTrace };
static void tsPv(cp::Text &o, int32_t kind, int64_t a, int64_t b, size_t cap) { size_t at = o.size();
  o.resize(at + cap); o.truncate(at + nixev_ts_pv(kind, a, b, o.begin() + at, cap)); }

// The Attrs/List composition is hollowed into lowered/nixeval/PrintCompOps.mlir: a trikeshed.combineAll of the
// per-attr/element pieces with the separators and brackets, drained once into the Text.  The recursion into child
// values, the seen-table, the depth guard and the name sorting stay here; each piece is rendered once by the
// callback (the combineAll's region runs for its size and again for its drain, so the callback caches each piece).
extern "C" size_t nixev_ts_pv_comp(void *ctx, int32_t kind, int64_t n, char *into, size_t cap);
struct PvComp { EvalState *st; cp::WordTable<char> *seen; size_t depth; const composite::Frozen<const Attr *> *rows; Value *list; composite::MutableSeries<cp::Text> cache; };
extern "C" void nixev_pv_piece(void *p, int64_t j, void **pp, int64_t *nn) {
  PvComp &c = *static_cast<PvComp *>(p); cp::Text &t = c.cache[uint32_t(j)];
  if (t.empty()) { // a piece is never empty (a name >= 2 bytes, a value >= 1), so empty means not yet rendered
    if (c.list) c.st->printValue(t, *c.list->list.elems[j], c.seen, c.depth + 1);
    else if (j & 1) c.st->printValue(t, *(*c.rows)[uint32_t(j / 2)]->value, c.seen, c.depth + 1);
    else nixfe::printIdentifier(t, c.st->symbols[(*c.rows)[uint32_t(j / 2)]->name]); }
  *pp = (void *)t.data(); *nn = int64_t(t.size()); }
static void tsComp(cp::Text &o, PvComp &c, int32_t k, int64_t n) { size_t at = o.size(), need = nixev_ts_pv_comp(&c, k, n, nullptr, 0);
  o.resize(at + need); nixev_ts_pv_comp(&c, k, n, o.begin() + at, need); o.truncate(at + need); } // size pass renders, drain writes

void EvalState::printValue(cp::Text &out, Value &v, cp::WordTable<char> *seen, size_t depth) {
  if (depth > settings.maxCallDepth) throw StackOverflowError("stack overflow");
  switch (v.type) {
  case VType::Int: tsPv(out, 1, v.integer, 0, 21); break;
  case VType::Bool: tsPv(out, 0, v.boolean ? PV_true : PV_false, 0, 32); break;
  case VType::String: nixfe::printLiteralString(out, v.sv()); break;
  case VType::Path: out.put(cp::chars(v.pathView())); break;
  case VType::Null: tsPv(out, 0, PV_null, 0, 32); break;
  case VType::Attrs:
    if (seen && !v.attrs->empty() && !firstTime(*seen, v.attrs)) tsPv(out, 0, PV_repeated, 0, 32);
    else {
      auto rows = v.attrs->lexicographicOrder(symbols); PvComp c{this, seen, depth, &rows, nullptr, {}}; c.cache.resize(rows.size() * 2); tsComp(out, c, 0, rows.size());
    }
    break;
  case VType::List:
    if (seen && v.listSize() && !firstTime(*seen, &v)) tsPv(out, 0, PV_repeated, 0, 32);
    else {
      PvComp c{this, seen, depth, nullptr, &v, {}}; c.cache.resize(v.listSize()); tsComp(out, c, 1, v.listSize());
    }
    break;
  case VType::Thunk: case VType::App: case VType::AttrApp: case VType::Failed: tsPv(out, 0, PV_code, 0, 32); break;
  case VType::Blackhole: tsPv(out, 0, PV_infinite, 0, 32); break;
  case VType::Lambda: tsPv(out, 0, PV_lambda, 0, 32); break;
  case VType::PrimOp: tsPv(out, 0, PV_primop, 0, 32); break;
  case VType::PrimOpApp: tsPv(out, 0, PV_primopApp, 0, 32); break;
  case VType::Float: nixfe::printFloat(out, v.fpoint); break;
  }
}

namespace {
struct TracePrinter {
  EvalState &st;
  cp::Text &out;
  bool force;
  size_t maxDepth = 10, maxAttrs = 10, maxList = 10, maxStr = 1024;
  size_t attrsPrinted = 0, listPrinted = 0;
  cp::WordTable<char> seen;

  void put(std::string_view s) { out.put(cp::chars(s)); }
  void print(Value &v, size_t depth) {
    if (force) {
      try {
        st.forceValue(v);
      } catch (EvalError &e) {
        tsPv(out, 0, PV_error, 0, 32);
        put(e.msg);
        tsPv(out, 0, PV_guilClose, 0, 32);
        return;
      }
    }
    switch (v.type) {
    case VType::Int: tsPv(out, 1, v.integer, 0, 21); break;
    case VType::Float: nixfe::printFloat(out, v.fpoint); break;
    case VType::Bool: tsPv(out, 0, v.boolean ? PV_true : PV_false, 0, 32); break;
    case VType::Null: tsPv(out, 0, PV_null, 0, 32); break;
    case VType::Path: put(v.pathView()); break;
    case VType::String: {
      auto s = v.sv();
      if (s.size() > maxStr) {
        nixfe::printLiteralString(out, s.substr(0, maxStr));
        tsPv(out, 0, PV_space, 0, 32);
        tsPv(out, 2, int64_t(s.size() - maxStr), 0, 48);
      } else {
        nixfe::printLiteralString(out, s);
      }
      break;
    }
    case VType::Attrs: {
      if (!firstTime(seen, v.attrs)) { tsPv(out, 0, PV_repeated, 0, 32); break; }
      if (force && st.isDerivation(v)) {
        tsPv(out, 0, PV_derivation, 0, 32);
        if (const Attr *d = v.attrs->get(st.s.drvPath)) {
          try {
            st.forceValue(*d->value);
            if (d->value->type == VType::String) {
              tsPv(out, 0, PV_space, 0, 32);
              put(d->value->sv());
            }
          } catch (EvalError &) {
          }
        }
        tsPv(out, 0, PV_guilClose, 0, 32);
        break;
      }
      if (depth >= maxDepth) { tsPv(out, 0, PV_setElide, 0, 32); break; }
      tsPv(out, 0, PV_setOpenTrace, 0, 32);
      composite::MutableSeries<const Attr *> sorted;
      for (auto &a : *v.attrs) sorted.append(&a);
      cp::sortRows(sorted.data(), sorted.size(), [&](const Attr *a, const Attr *b) {
        auto an = st.symbols[a->name], bn = st.symbols[b->name];
        bool ai = an == "type" || an == "_type", bi = bn == "type" || bn == "_type";
        if (ai != bi) return ai;
        return st.symbols.less(a->name, b->name);
      });
      size_t cur = 0;
      for (auto *a : sorted) {
        tsPv(out, 0, PV_space, 0, 32);
        if (attrsPrinted >= maxAttrs) {
          tsPv(out, 2, int64_t(sorted.size() - cur), 1, 48);
          break;
        }
        auto n = st.symbols[a->name];
        if (nixfe::isValidIdentifier(n)) put(n);
        else nixfe::printLiteralString(out, n);
        tsPv(out, 0, PV_eq, 0, 32);
        print(*a->value, depth + 1);
        tsPv(out, 0, PV_semiTrace, 0, 32);
        attrsPrinted++;
        cur++;
      }
      tsPv(out, 0, PV_setCloseTrace, 0, 32);
      break;
    }
    case VType::List: {
      if (v.listSize() && !firstTime(seen, &v)) { tsPv(out, 0, PV_repeated, 0, 32); break; }
      if (depth >= maxDepth) { tsPv(out, 0, PV_listElide, 0, 32); break; }
      tsPv(out, 0, PV_listOpenTrace, 0, 32);
      size_t cur = 0;
      for (size_t i = 0; i < v.listSize(); i++) {
        tsPv(out, 0, PV_space, 0, 32);
        if (listPrinted >= maxList) {
          tsPv(out, 2, int64_t(v.listSize() - cur), 2, 48);
          break;
        }
        print(*v.list.elems[i], depth + 1);
        listPrinted++;
        cur++;
      }
      tsPv(out, 0, PV_listCloseTrace, 0, 32);
      break;
    }
    case VType::Lambda: {
      auto lam = cast<nd::LambdaOp>(v.thunk.node->def);
      tsPv(out, 0, PV_lambdaTrace, 0, 32);
      if (auto n = lam.getName()) {
        tsPv(out, 0, PV_space, 0, 32);
        put(*n);
      }
      tsPv(out, 0, PV_at, 0, 32);
      put(st.showPos(nd::posOfOp(lam)));
      tsPv(out, 0, PV_guilClose, 0, 32);
      break;
    }
    case VType::PrimOp: tsPv(out, 0, PV_primopTrace, 0, 32); put(v.primOp->name); tsPv(out, 0, PV_guilClose, 0, 32); break;
    case VType::PrimOpApp: {
      Value *p = &v;
      while (p->type == VType::PrimOpApp) p = p->app.left;
      tsPv(out, 0, PV_primopAppTrace, 0, 32);
      if (p->type == VType::PrimOp) put(p->primOp->name);
      else tsPv(out, 0, PV_question, 0, 32);
      tsPv(out, 0, PV_guilClose, 0, 32);
      break;
    }
    case VType::Thunk: case VType::App: case VType::AttrApp: case VType::Failed: tsPv(out, 0, PV_thunk, 0, 32); break;
    case VType::Blackhole: tsPv(out, 0, PV_infinite, 0, 32); break;
    }
  }
};
} // namespace

cp::Text EvalState::printValueForTrace(Value &v) {
  cp::Text t;
  TracePrinter p{*this, t, false};
  p.print(v, 0);
  return t;
}

//===----------------------------------------------------------------------===//
// Parsing, lowering, files
//===----------------------------------------------------------------------===//

nixfe::ParseOptions EvalState::parseOptions() {
  nixfe::ParseOptions po;
  po.pipeOperators = settings.pipeOperators;
  const char *home = getenv("HOME");
  po.home = home ? home : "/homeless-shelter";
  po.lintAbsolutePaths = settings.lintAbsolutePaths;
  po.lintShortPaths = settings.lintShortPaths;
  po.lintUrls = settings.lintUrls;
  po.onWarning = [](const nixfe::ParseError &e) {
    cp::Text line = formatParseError(e, "warning");
    nixsys::lineToStderr(line.data(), line.size());
  };
  return po;
}

/// The optimization pipeline is data: MLIR pass-pipeline text (EvalSettings::pipeline,
/// overridden by MLNIX_PIPELINE), so any registered pass can be composed by name.
static cp::Own<mlir::PassManager> makeOptimizer(mlir::MLIRContext &ctx, const EvalSettings &settings) {
  static const bool registered = [] { // the language runs a local static's initializer once, whichever thread comes first
    mlir::registerTransformsPasses();
    nd::registerNixPasses();
    return true;
  }();
  (void)registered;
  cp::Text text = pipelineText(settings);
  auto pm = cp::own<mlir::PassManager>(&ctx); // anchored on any op
  pm->enableVerifier(false);
  llvm::SmallString<256> err;
  llvm::raw_svector_ostream os(err);
  if (mlir::failed(mlir::parsePassPipeline(text, *pm, os)))
    throw EvalError(cp::cat("invalid pass pipeline '", text, "': ", err));
  return pm;
}

nd::ExprOp EvalState::lowerToMLIR(nixfe::Origin *origin, const composite::MutableSeries<composite::Text> *scopeNames) {
  nixfe::ParseOptions po = parseOptions();
  nixfe::GenOptions go;
  go.isBaseName = baseNameOf;
  go.baseNames = this;
  if (settings.deferBodies) {
    // A lambda body is not IsolatedFromAbove, so no PassManager can run on it when it is minted: the
    // demand schedule devirtualizes it directly, which is the whole default pipeline.  Any other
    // pipeline would be skipped silently on every minted body, so refuse it.
    if (settings.optimize && pipelineText(settings) != "nix-prims")
      throw EvalError(cp::cat("MLNIX_DEFER runs only the default pipeline 'nix-prims', not '", pipelineText(settings), "'"));
    auto pool = cp::own<nixfe::FilePool>(nextPoolId.fetch_add(1), origin, po);
    go.deferBodies = true;
    go.pool = pool.get();
    installPool(cp::mv(pool));
  }
  if (scopeNames) {
    go.scoped = true;
    for (const cp::Text &nm : *scopeNames) go.scopeNames.append(nm.clone());
  }
  cp::Text sym = cp::cat("expr", exprCounter++);
  uint64_t t0 = statsEnabled ? nixsys::monotonicNs() : 0;
  nd::ExprOp op = nixfe::genExpr(*module, origin, po, sym, go);
  // The expression is IsolatedFromAbove and not yet referenced by any frame,
  // so it can be rewritten freely before evaluation starts.
  if (settings.optimize) {
    if (!optimizer) optimizer = makeOptimizer(ctx, settings);
    if (mlir::failed(optimizer->run(op))) throw EvalError("the optimization pipeline failed");
  }
  if (statsEnabled) {
    op->walk([&](mlir::Operation *o) { ++countOf(opStats, o->getName()).n[0]; });
    nsLower += nixsys::monotonicNs() - t0;
  }
  return op;
}

void EvalState::installPool(cp::Own<nixfe::FilePool> p) {
  uint32_t id = p->file;
  if (pools.size() <= id) pools.resize(id + 1);
  pools[id] = cp::mv(p);
}

void EvalState::startPrelower() {
  const char *list = getenv("MLNIX_PRELOWER_LIST");
  bool replayed = getenv("MLNIX_PRELOWER") && !nixprefetch::replayFiles.empty(); // MLNIX_PREFETCH=auto|replay:FILE supplies the list
  if (pre || !settings.deferBodies || (!list && !replayed)) return;
  if (replayed) nixstore::startPrehash(); // the source trees the recorded run hashed, hashed again off this thread
  pre = cp::own<PrelowerState>();
  for (auto &e : baseEnv) pre->baseNames.set(e.p, e.n, 1, [&] { return e.p; }); // the names' bytes are baseEnvNames', which never move
  pre->po = parseOptions();
  pre->po.lintAbsolutePaths = pre->po.lintShortPaths = pre->po.lintUrls = nixfe::Lint::Ignore;
  pre->po.onWarning = nullptr;
  if (list) {
    cp::Text text; // one path a line, or a prefetch list (`F path`); no list, nothing to prelower
    nixsys::readInto(list, text);
    cp::eachLine(text.data(), text.size(), [&](const char *p, uint32_t n) {
      std::string_view line(p, n);
      if (line.size() > 2 && line[1] == ' ') {
        if (line[0] == 'F' && line.size() >= 6 && line.ends_with(".nix")) pre->queue.append(cp::Text(line.substr(2)));
      } else if (!line.empty()) {
        pre->queue.append(cp::Text(line));
      }
    });
  } else {
    for (const cp::Text &f : nixprefetch::replayFiles) pre->queue.append(f.clone());
  }
  unsigned n = 1;
  if (const char *t = getenv("MLNIX_PRELOWER_THREADS")) n = unsigned(cp::max<uint64_t>(1, cp::min<uint64_t>(8, nixsys::readUnsigned(t).value)));
  for (unsigned i = 0; i < n; i++) pre->workers.append(nixsys::Thread::start([this] { prelowerLoop(); }));
}

void EvalState::prelowerLoop() {
  for (;;) {
    cp::Text path;
    Prelowered *pl;
    {
      nixsys::Held lk(pre->m);
      pre->cv.waitFor(pre->m, [&] { return pre->stop || pre->head < pre->queue.size(); });
      if (pre->stop) return;
      path = pre->queue.drain(pre->head++);
      if (pre->byPath.find(path.data(), uint32_t(path.size()))) continue; // the evaluator took it first, or a duplicate
      pl = newPrelowered(path);
    }
    try {
      nixfe::Origin *origin = nixfe::newOrigin();
      origin->name = path.clone();
      origin->path = path.clone();
      origin->baseDir = nixstore::dirOf(path);
      origin->text = nixfe::Source::mapFile(path);
      if (origin->text) {
        nixfe::GenOptions go;
        go.isBaseName = [](const void *names, llvm::StringRef n) {
          return static_cast<const cp::TextTable<char> *>(names)->find(n.data(), uint32_t(n.size())) != nullptr;
        };
        go.baseNames = &pre->baseNames;
        go.deferBodies = true;
        pl->pool = cp::own<nixfe::FilePool>(nextPoolId.fetch_add(1), origin, pre->po);
        go.pool = pl->pool.get();
        pl->mod = ModuleOp::create(UnknownLoc::get(&ctx));
        pl->op = nixfe::genExpr(*pl->mod, origin, pre->po, "expr", go);
        // The bodies the recorded run minted in this file, minted here in its order (the rows of nested lambdas follow from it): the
        // evaluator only indexes them at their first call.  If one fails (the file changed since), the whole file is left to the evaluator.
        if (const auto *mints = nixprefetch::replayMints(path))
          for (uint32_t row : *mints) {
            if (row >= pl->pool->rows.size()) break;
            auto lam = dyn_cast_or_null<nd::LambdaOp>(pl->pool->rows.col<nixfe::PoolCol::Op>()[row]);
            if (!lam || !lam.getBody().front().empty()) continue;
            nixfe::mintBody(lam, *pl->pool, row, go);
          }
        // The default pipeline is devirtualization alone, which reads only the IR and the dialect's primop table: done here, off the
        // evaluator's thread.  Another pipeline runs at adoption, where the prim folder (the evaluator's) can be called.
        if (settings.optimize && pipelineText(settings) == "nix-prims") {
          nd::devirtualizePrims(pl->op);
          pl->optimized = true;
          // Indexed here too, while this thread's caches hold the IR it just built: a file reads nothing from outside it.  Not when the
          // census counts indexing: the evaluator indexes then.
          if (!statsEnabled) {
            pl->index = cp::own<Indexer>(*this, true);
            pl->index->index(pl->op.getBody());
          }
        }
        pl->origin = origin;
        pl->ok = true;
      }
    } catch (...) {
      pl->ok = false;
    }
    { nixsys::Held g(pre->m); pl->done = true; }
    pre->cv.notifyAll();
  }
}

/// A new lowering of `path`, owned by the prelowering state and found by the path (called under pre->m).
EvalState::Prelowered *EvalState::newPrelowered(std::string_view path) {
  Prelowered *pl = pre->lowered[pre->lowered.append(cp::own<Prelowered>())].get();
  pre->byPath.set(path.data(), uint32_t(path.size()), pl, [&] { return pre->pathBytes.copy(path.data(), uint32_t(path.size())); });
  return pl;
}

/// The finished lowering of `resolved`, adopted into the evaluator's module (and optimized there: the prim folder is the evaluator's), or a null op.
nd::ExprOp EvalState::takePrelowered(std::string_view resolved) {
  if (!pre) return {};
  Prelowered *pl;
  {
    nixsys::Held lk(pre->m);
    Prelowered **found = pre->byPath.find(resolved.data(), uint32_t(resolved.size()));
    if (!found) {
      // not started: take it off the queue so the helper does not lower it again, and lower it here
      newPrelowered(resolved);
      ++pre->missed;
      return {};
    }
    pl = *found;
    if (!pl->done) { ++pre->waited; pre->cv.waitFor(pre->m, [&] { return pl->done; }); }
  }
  if (!pl->ok) return {};
  ++pre->adopted;
  installPool(cp::mv(pl->pool));
  origins.append(pl->origin);
  nd::ExprOp op = pl->op;
  op->remove();
  op.setSymName(cp::cat("expr", exprCounter++));
  module->push_back(op);
  pl->mod = nullptr;
  if (settings.optimize && !pl->optimized) {
    if (!optimizer) optimizer = makeOptimizer(ctx, settings);
    if (mlir::failed(optimizer->run(op))) throw EvalError("the optimization pipeline failed");
  }
  if (pl->index) { // indexed by the helper: its regions and the captures of the bodies minted later become the evaluator's
    for (auto &[r, ri] : pl->index->regions) regionInfos.at(uint64_t(uintptr_t(r))) = ri;
    for (auto &[key, n] : pl->index->captures) setNode(key, n);
    helperIndexers.append(cp::mv(pl->index));
  }
  return op;
}

Value *EvalState::evalExprOp(nd::ExprOp op) {
  RegionInfo *ri = regionInfo(&op.getBody());
  Frame *f = newFrame(ri, nullptr);
  return lookup(f, ri->resultNode);
}

static const char *corepkgsFetchurl = R"NIX({
  system ? "", # obsolete
  url,
  hash ? "", # an SRI hash

  # Legacy hash specification
  md5 ? "",
  sha1 ? "",
  sha256 ? "",
  sha512 ? "",
  outputHash ?
    if hash != "" then
      hash
    else if sha512 != "" then
      sha512
    else if sha1 != "" then
      sha1
    else if md5 != "" then
      md5
    else
      sha256,
  outputHashAlgo ?
    if hash != "" then
      ""
    else if sha512 != "" then
      "sha512"
    else if sha1 != "" then
      "sha1"
    else if md5 != "" then
      "md5"
    else
      "sha256",

  executable ? false,
  unpack ? false,
  name ? baseNameOf (toString url),
  impure ? false,
}:

derivation (
  {
    builder = "builtin:fetchurl";

    # New-style output content requirements.
    outputHashMode = if unpack || executable then "recursive" else "flat";

    inherit
      name
      url
      executable
      unpack
      ;

    system = "builtin";

    # No need to double the amount of network traffic
    preferLocalBuild = true;

    # This attribute does nothing; it's here to avoid changing evaluation results.
    impureEnvVars = [
      "http_proxy"
      "https_proxy"
      "ftp_proxy"
      "all_proxy"
      "no_proxy"
    ];

    # To make "nix-prefetch-url" work.
    urls = [ url ];
  }
  // (if impure then { __impure = true; } else { inherit outputHashAlgo outputHash; })
)
)NIX";

// The Nix sources lib/Corepkgs/*.nix, embedded by lib/Corepkgs/Embed.cmake: <nix/flake.nix> and the like.
static const struct { const char *path, *text; } corepkgsTable[] = {
#include "Corepkgs.inc"
};

static cp::Text readSource(std::string_view path) {
  if (path == "/__corepkgs__/fetchurl.nix") return cp::Text(corepkgsFetchurl);
  for (auto &c : corepkgsTable)
    if (path == c.path) return cp::Text(c.text);
  try {
    return nixstore::readFile(path);
  } catch (nixstore::Error &e) {
    throw EvalError(e.what());
  }
}

cp::Text EvalState::resolveExprPath(std::string_view pathIn) {
  cp::Text path(pathIn);
  if (path.starts_with("/__corepkgs__/")) return path;
  // Follow symlinks (to the final target), then use default.nix for dirs.
  for (int i = 0; i < 1024; i++) {
    struct stat st;
    nixprefetch::note('L', path.c_str());
    if (lstat(path.c_str(), &st) != 0) throw EvalError(cp::cat("path '", path, "' does not exist"));
    if (!S_ISLNK(st.st_mode)) break;
    char buf[PATH_MAX + 1];
    ssize_t n = readlink(path.c_str(), buf, PATH_MAX);
    if (n < 0) break;
    cp::Text tgt(buf, size_t(n));
    if (tgt.empty() || tgt[0] != '/') tgt = cp::cat(nixstore::dirOf(path), '/', tgt); // (tgt[0] of an empty standard string was its NUL)
    path = nixfe::canonPath(tgt);
  }
  struct stat st;
  nixprefetch::note('S', path.c_str());
  if (stat(path.c_str(), &st) == 0 && S_ISDIR(st.st_mode)) path += "/default.nix";
  return path;
}

Value *EvalState::evalFile(std::string_view pathIn) {
  cp::Text path(pathIn);
  if (Value **hit = fileEvalCache.find(path.data(), uint32_t(path.size()))) return *hit;
  cp::Text real = realisePath(path, nullptr);
  cp::Text resolved = resolveExprPath(real);
  // Map back from the physical location when using a chroot store.
  cp::Text logical = resolved.clone();
  if (!store->config().realRoot.empty() && resolved.starts_with(store->config().realRoot))
    logical = cp::Text(resolved.substr(store->config().realRoot.size()));
  if (Value **hit = fileEvalCache.find(logical.data(), uint32_t(logical.size()))) {
    Value *same = *hit; // read before the set, which may move the rows
    fileEvalCache.set(path.data(), uint32_t(path.size()), same, [&] { return copyString(path); });
    return same;
  }

  Value *result;
  if (resolved.size() > 5 && resolved.ends_with(".mlir")) {
    result = evalMLIRFile(resolved, "");
  } else {
    nixfe::Origin *origin = nixfe::newOrigin();
    origin->name = logical.clone();
    origin->path = logical.clone();
    origin->baseDir = nixstore::dirOf(logical);
    nixprefetch::note('F', resolved.c_str());
    origin->text = nixfe::Source::mapFile(resolved); // mapped read-only (77de09c:docs/IO.md); read and copied when it cannot be
    if (!origin->text) origin->text = nixfe::Source::fromString(readSource(resolved));
    nd::ExprOp adopted;
    if (logical == resolved) {
      startPrelower();
      adopted = takePrelowered(resolved);
    }
    if (adopted) {
      result = evalExprOp(adopted);
    } else {
      origins.append(origin);
      result = evalExprOp(lowerToMLIR(origin));
    }
  }
  fileEvalCache.set(path.data(), uint32_t(path.size()), result, [&] { return copyString(path); });
  fileEvalCache.set(logical.data(), uint32_t(logical.size()), result, [&] { return copyString(logical); });
  return result;
}

Value *EvalState::evalString(std::string_view text, std::string_view baseDir, std::string_view originName) {
  nixfe::Origin *origin = nixfe::newOrigin();
  origin->name.assign(originName);
  origin->baseDir.assign(baseDir);
  origin->text = nixfe::Source::fromString(cp::Text(text));
  origins.append(origin);
  return evalExprOp(lowerToMLIR(origin));
}

Value *EvalState::evalMLIRFile(std::string_view path, std::string_view sym) {
  llvm::SourceMgr sm;
  OwningOpRef<ModuleOp> m = parseSourceFile<ModuleOp>(llvm::StringRef(path), sm, ParserConfig(&ctx));
  if (!m) throw EvalError(cp::cat("failed to parse MLIR file '", path, "'"));
  nd::ExprOp found;
  // Move all ops into our module (renaming symbols to avoid clashes).
  auto exprs = llvm::to_vector(m->getOps<nd::ExprOp>());
  for (auto e : exprs) {
    bool match = sym.empty() ? !found : e.getSymName() == llvm::StringRef(sym);
    e->remove();
    e.setSymName(cp::cat("mlir", exprCounter++));
    module->getBody()->push_back(e);
    if (match && !found) found = e;
  }
  if (!found) throw EvalError(cp::cat("no nix.expr found in '", path, "'"));
  return evalExprOp(found);
}

cp::Text EvalState::realisePath(std::string_view path, PosPtr pos) {
  // Store paths are realised through string context (realiseContext); here we
  // only map logical store paths to their physical location.
  const cp::Text &sd = store->storeDir();
  if (path == sd || path == sd + "/" || nixstore::isInStore(sd, path)) return store->toReal(path);
  return cp::Text(path);
}

void EvalState::realiseContext(const NixStringContext &ctx, PosPtr pos) {
  for (const char *c : ctx) {
    try {
      if (c[0] == '!') {
        const char *drv = c + 1;
        while (*drv && *drv != '!') ++drv;
        store->buildDerivation(*drv ? drv + 1 : drv);
      } else if (c[0] == '=') {
        store->buildDerivation(c + 1);
      } else if (!store->isValidPath(c)) {
        throw EvalError(cp::cat("path '", c, "' is not valid"), pos);
      }
    } catch (nixstore::Error &e) {
      throw EvalError(e.what(), pos);
    }
  }
}

cp::Text EvalState::findFile(Value &searchPath, std::string_view name, PosPtr pos) {
  forceList(searchPath, pos);
  for (Value &e : searchPath.values()) {
    forceAttrs(e, pos);
    cp::Text prefix;
    if (const Attr *a = e.attrs->get(s.prefix)) prefix = cp::Text(forceStringNoCtx(*a->value, pos));
    const Attr *pa = e.attrs->get(s.path);
    if (!pa) throw EvalError("attribute 'path' missing", pos);
    NixStringContext ctx;
    cp::Text p = coerceToString(*pa->value, ctx, false, false, pos);
    realiseContext(ctx, pos);
    cp::Text rest;
    if (!prefix.empty()) {
      if (name.substr(0, prefix.size()) != prefix) continue;
      if (name.size() > prefix.size() && name[prefix.size()] != '/') continue;
      rest = cp::Text(name.substr(prefix.size()));
    } else {
      rest = cp::cat("/", name);
    }
    if (p.find("://") != cp::npos) continue; // URL entries are not fetched implicitly
    cp::Text full = nixfe::canonPath(p + rest);
    if (nixstore::pathExists(realisePath(full, pos))) return full;
  }
  if (name.substr(0, 4) == "nix/") return cp::cat("/__corepkgs__", name.substr(3));
  if (settings.pureEval)
    throw ThrownError(cp::cat("cannot look up '<", name, ">' in pure evaluation mode (use '--impure' to override)"), pos);
  throw ThrownError(cp::cat("file '", name, "' was not found in the Nix search path (add it using $NIX_PATH or -I)"), pos);
}

//===----------------------------------------------------------------------===//
// Error formatting
//===----------------------------------------------------------------------===//

static cp::Text chomp(cp::Text s) {
  while (!s.empty() && (s.back() == ' ' || s.back() == '\t' || s.back() == '\n' || s.back() == '\r')) s.pop_back();
  return s;
}

static void appendCodeLines(cp::Text &out, std::string_view text, unsigned line, unsigned col,
                            unsigned indent = 7) {
  composite::MutableSeries<std::string_view> lines; // windows on `text`, which outlives them
  size_t start = 0;
  while (true) {
    size_t nl = text.find('\n', start);
    if (nl == std::string_view::npos) {
      lines.append(text.substr(start));
      break;
    }
    lines.append(text.substr(start, nl - start));
    start = nl + 1;
  }
  auto fmtLine = [&](unsigned n) {
    char buf[16];
    snprintf(buf, sizeof buf, "%5u", n);
    cp::Text l;
    l.put(indent + 1, ' ');
    l.put(buf).put("| ").put(lines[n - 1]);
    return chomp(cp::mv(l));
  };
  if (line >= 2 && line - 1 <= lines.size()) out.put('\n').put(fmtLine(line - 1));
  if (line >= 1 && line <= lines.size()) {
    out.put('\n').put(fmtLine(line));
    if (col > 0) {
      out.put('\n');
      out.put(indent, ' ');
      out.put("      |");
      out.put(col, ' ');
      out.put('^');
    }
  }
  if (line + 1 <= lines.size()) out.put('\n').put(fmtLine(line + 1));
}

static cp::Text sourceFor(EvalState *state, std::string_view file) {
  if (state)
    for (auto &o : state->origins)
      if (o->name == file && o->text) return cp::Text(o->text->view());
  if (!file.empty() && file[0] == '/' && nixstore::pathExists(file)) {
    try {
      return nixstore::readFile(file);
    } catch (...) {
    }
  }
  return "";
}

static void appendPos(cp::Text &out, EvalState *state, std::string_view file, unsigned line, unsigned col) {
  out.put("\n       at ").put(file).put(':').putUnsigned(line).put(':').putUnsigned(col).put(':');
  cp::Text text = sourceFor(state, file);
  if (!text.empty()) appendCodeLines(out, text, line, col);
}

cp::Text formatError(EvalState *state, const EvalError &e) {
  cp::Text out;
  // Traces are printed outermost first.
  if (state && state->settings.showTrace) {
    for (auto *it = e.traces.end(); it != e.traces.begin();) {
      --it;
      out.put("\n       … ").put(it->msg);
      if (auto f = nd::decodePos(it->pos)) {
        appendPos(out, state, f->file, f->line, f->col);
        out += "\n";
      } else {
        out += "\n";
      }
    }
  }
  const cp::Text &msg = e.msg;
  // Indent continuation lines of the message.
  cp::Text ind;
  for (size_t i = 0; i < msg.size(); i++) {
    ind += msg[i];
    if (msg[i] == '\n') ind += "       ";
  }
  cp::Text res = out.empty() ? cp::cat("error: ", ind) : cp::cat("error:", out, "\n       error: ", ind);
  if (auto f = nd::decodePos(e.pos)) appendPos(res, state, f->file, f->line, f->col);
  return res;
}

cp::Text formatParseError(const nixfe::ParseError &e, const char *kind) {
  unsigned indent = strlen(kind) + 2;
  cp::Text res = cp::cat(kind, ": ", e.what());
  if (e.pos.valid() && e.origin) {
    res.put('\n');
    res.put(indent, ' ');
    res.put("at ").put(e.origin->name).put(':').putUnsigned(e.pos.line).put(':').putUnsigned(e.pos.col).put(':');
    if (e.origin->text) appendCodeLines(res, e.origin->text->view(), e.pos.line, e.pos.col, indent);
  }
  return res;
}

int runWithLargeStack(cp::Fn<int()> fn) {
  struct Ctx {
    cp::Fn<int()> fn; // lent: the thread that calls it is joined before this returns
    int rc = 0;
    std::exception_ptr ex;
  } c{fn};
  pthread_attr_t attr;
  pthread_attr_init(&attr);
  pthread_attr_setstacksize(&attr, size_t(1) << 30); // 1 GiB (virtual)
  pthread_t th;
  auto tramp = [](void *p) -> void * {
    auto *c = static_cast<Ctx *>(p);
    try {
      c->rc = c->fn();
    } catch (...) {
      c->ex = std::current_exception();
    }
    return nullptr;
  };
  if (pthread_create(&th, &attr, tramp, &c) != 0) return c.fn();
  pthread_join(th, nullptr);
  if (c.ex) std::rethrow_exception(c.ex);
  return c.rc;
}

} // namespace nixev
