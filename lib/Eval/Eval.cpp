//===- Eval.cpp - Lazy evaluator over the nix dialect ---------------------===//

#include <sys/resource.h>
#include <map>
#include "Composite/Folds.h"
#include "Composite/Mutable.h"
#include "Nix/Prefetch.h"
#include <bit>
#include <fstream>
#include "Nix/Eval.h"
#include "Nix/ScalarJIT.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Pass/PassRegistry.h"
#include "mlir/Transforms/Passes.h"
#include <mutex>
#include "llvm/Support/Format.h"
#include "llvm/Support/MemoryBuffer.h"
#include "Nix/MLIRGen.h"

#include "mlir/IR/Builders.h"
#include "mlir/Parser/Parser.h"
#include "mlir/Pass/PassManager.h"
#include "llvm/ADT/TypeSwitch.h"
#include "llvm/Support/SourceMgr.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>
#include <exception>
#include <iostream>
#include <limits>
#include <pthread.h>
#include <sstream>
#include <sys/stat.h>
#include <unistd.h>

using namespace mlir;
namespace nd = mlir::nix;

namespace nixev {

//===----------------------------------------------------------------------===//
// Bindings
//===----------------------------------------------------------------------===//

void EvalState::statSelect(const void *site, const Bindings *b, Symbol key, bool dynamic) {
  ++nSelects;
  if (dynamic) ++nSelectDyn;
  if (b->layered()) { ++nSelectLayered; }
  size_t n = b->size();
  unsigned lg = n ? 64 - __builtin_clzll(n) : 0;
  ++nSelectSizeLog[lg < 17 ? lg : 17];
  nSelectProbes += lg + 1;                 // a binary search over n rows looks at about log2(n)+1 of them
  bool hit = b->get(key) != nullptr;
  nSelectHits += hit;
  uint64_t sig = 0x9E3779B97F4A7C15ull * (n + 1);
  if (!b->layered() && n) {
    sig ^= uint64_t(b->attrs[0].name) * 0xBF58476D1CE4E5B9ull;
    sig ^= uint64_t(b->attrs[n / 2].name) * 0x94D049BB133111EBull;
    sig ^= uint64_t(b->attrs[n - 1].name) * 0xD6E8FEB86659FD93ull;
  } else if (b->layered()) sig = 0x1;     // all layered sets are one class here
  SelSite &s = selSites[site];
  ++s.calls; s.hits += hit; s.dynamic |= dynamic;
  if (s.calls > 1 && s.last == sig) ++s.sameAsLast;
  s.last = sig;
  if (!cp::anyOf(s.seen, [&](uint64_t x) { return x == sig; })) { if (s.seen.size() < 6) s.seen.append(sig); else s.seen[5] = sig ^ 1; }
}

static const auto attrName = [](const Attr &a) { return a.name; };

const Attr *Bindings::get(Symbol s) const {
  if (layered()) {
    if (countGets) ++getLayered;
    const Layer &L = layer();
    if (L.flat) return L.flat->get(s);
    if (const Attr *a = L.top->get(s)) return a; // top shadows base
    return L.base->get(s);                       // and base may be a layer itself: the chain is walked, not flattened
  }
  const Attr *r = cp::findRow(attrs, size_, s, attrName);
  if (countGets) { unsigned b = size_ ? std::min(15, 63 - std::countl_zero(uint64_t(size_))) : 0; ++getCalls[b]; getSteps[b] += b; getMiss[b] += r == nullptr; }
  return r;
}

/// The union of two flat sorted sets, `y` winning on equal names, as a new flat set of exactly its size.
static Bindings *mergeBindings(Arena &alloc, const Bindings *x, const Bindings *y) {
  size_t n = cp::unionSize(x->attrs, x->size_, y->attrs, y->size_, attrName);
  Bindings::merged++;
  Bindings::mergedCells += n;
  void *mem = alloc.Allocate(sizeof(Bindings) + n * sizeof(Attr), alignof(Bindings));
  auto *r = new (mem) Bindings();
  r->size_ = uint32_t(cp::unionRows(x->attrs, x->size_, y->attrs, y->size_, r->attrs, attrName));
  return r;
}

Bindings *Bindings::flat() const {
  if (!layered()) return const_cast<Bindings *>(this);
  Layer &L = layer();
  if (!L.flat) {
    // The rows of the chain ARE the set, so materialising it is a copy of rows() -- no merge, no shadowing left to do.
    size_t n = size();
    void *mem = L.alloc->Allocate(sizeof(Bindings) + n * sizeof(Attr), alignof(Bindings));
    auto *r = new (mem) Bindings();
    auto rs = rows();
    for (size_t i = 0; i < n; i++) r->attrs[i] = rs[uint32_t(i)];
    r->size_ = uint32_t(n);
    L.flat = r;
    flattened++;
  }
  return L.flat;
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

/// `a // b`: the two merged into one flat set, as Nix does.  A set that is a chain of layers over its base (a `//` that copied nothing) was
/// measured slower to read than it was to copy: every lookup walked the chain, a miss a level, and every `//` over it walked the base's
/// rows through the chain to build its selection (Mac, same outputs: toplevel -2.5%, nixpkgs-73 -7% when merged flat; peak memory +5% and
/// +13%).  A set made a layer before this is still read as one, and merged here as one.
Bindings *EvalState::updateAttrs(Bindings *a, Bindings *b) {
  b = b->flat();
  if (a->layered() && a->layer().flat) a = a->layer().flat;
  if (statsEnabled) { nUpdMerged++; nUpdTop += a->size() + b->size_; }
  return mergeBindings(alloc, a->flat(), b);
}

Bindings *EvalState::allocBindings(size_t n) {
  if (statsEnabled) nBindingBytes += sizeof(Bindings) + n * sizeof(Attr);
  void *mem = alloc.Allocate(sizeof(Bindings) + n * sizeof(Attr), alignof(Bindings));
  auto *b = new (mem) Bindings();
  b->size_ = 0;
  return b;
}

static size_t sortRowsFirstWins(Attr *rows, size_t n);
Bindings *EvalState::BindingsBuilder::finish() {
  if (st.statsEnabled) { ++st.nBuilders; st.nBuilderRows += attrs.size(); if (attrs.size() > 12) { ++st.nBuildersBig; st.nBuilderBigRows += attrs.size(); } }
  // A set of size 0 is the one constant: nothing is written to it after it is built, so every empty set is the same cell.
  if (attrs.empty()) { if (st.statsEnabled) ++st.nEmptyShared; return st.vEmptyAttrs.attrs; }
  Bindings *b = st.allocBindings(attrs.size());
  std::copy(attrs.begin(), attrs.end(), b->attrs);
  b->size_ = sortRowsFirstWins(b->attrs, attrs.size());
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

const StringContext *EvalState::makeContext(const NixStringContext &c) {
  if (c.empty()) return nullptr;
  if (statsEnabled) nCtxBytes += sizeof(StringContext) + c.size() * sizeof(const char *);
  void *mem = alloc.Allocate(sizeof(StringContext) + c.size() * sizeof(const char *), alignof(StringContext));
  auto *ctx = new (mem) StringContext();
  ctx->n = c.size();
  size_t i = 0;
  for (auto &e : c) ctx->elems[i++] = copyString(e);
  return ctx;
}

void EvalState::mkString(Value &v, std::string_view s, const NixStringContext &ctx) {
  if (s.size() > UINT32_MAX) throw EvalError("string of 4 GiB or more");
  v.type = VType::String; if (statsEnabled) ++nVT[unsigned(VType::String)];
  v.str.s = copyString(s);
  v.aux = static_cast<uint32_t>(s.size());
  v.str.ctx = makeContext(ctx);
}

void EvalState::mkStringOf(Value &v, llvm::ArrayRef<composite::Chars> pieces, const StringContext *ctx) {
  struct Sum { size_t total; uint32_t full; composite::Chars one; };
  Sum sum = composite::fold(composite::series(pieces.data(), uint32_t(pieces.size())), Sum{0, 0, composite::chars("", 0)},
                            [](Sum s, const composite::Chars &p) {
                              if (p.size()) { s.full++; s.one = p; }
                              s.total += p.size();
                              return s;
                            });
  size_t total = sum.total;
  if (total > UINT32_MAX) throw EvalError("string of 4 GiB or more");
  if (sum.full <= 1) { // nothing is joined to the one piece (or there is none): it is the string, its bytes shared, as a string is never written
    v.type = VType::String; if (statsEnabled) ++nVT[unsigned(VType::String)];
    v.str.s = sum.one.data();
    v.aux = sum.one.size();
    v.str.ctx = ctx;
    return;
  }
  char *buf = static_cast<char *>(alloc.Allocate(total + 1, 1));
  if (statsEnabled) nStringBytes += total + 1;
  char *at = composite::fold(composite::series(pieces.data(), uint32_t(pieces.size())), buf,
                             [](char *to, const composite::Chars &p) { return std::copy(p.data(), p.data() + p.size(), to); });
  *at = 0;
  v.type = VType::String; if (statsEnabled) ++nVT[unsigned(VType::String)];
  v.str.s = buf;
  v.aux = static_cast<uint32_t>(total);
  v.str.ctx = ctx;
}

void EvalState::mkPath(Value &v, std::string_view p) {
  if (p.size() > UINT32_MAX) throw EvalError("path of 4 GiB or more");
  v.type = VType::Path; if (statsEnabled) ++nVT[unsigned(VType::Path)];
  v.path.s = copyString(p);
  v.aux = static_cast<uint32_t>(p.size());
}

void EvalState::mkList(Value &v, size_t n) {
  if (n > UINT32_MAX) throw EvalError("list of 4 Gi or more cells");
  v.type = VType::List; if (statsEnabled) ++nVT[unsigned(VType::List)];
  v.aux = static_cast<uint32_t>(n);
  v.list.elems = allocList(n);
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

EvalState::EvalState(EvalSettings st, std::shared_ptr<nixstore::Store> store)
    : settings(std::move(st)), store(std::move(store)) {
  statsEnabled = getenv("MLNIX_STATS") != nullptr;
  recordEdges = statsEnabled && getenv("MLNIX_STATS_EDGES");
  instrumented = statsEnabled || recordEdges;
  if (getenv("MLNIX_STATS_IMPORTS")) nixfe::pathLiterals = new std::unordered_set<std::string>();
  Bindings::countGets = statsEnabled;
  scalarJIT = ScalarJIT::create();
  settings.mapSources = !getenv("MLNIX_NOMMAP"); // ablation switch: read and copy every file, as before
  composite::todoSink = [](const char *what) { llvm::errs() << "TODO: " << what << "\n"; };
  recycleOn = getenv("MLNIX_RECYCLE") != nullptr; // opt-in: -2 to -3% peak memory, +1 to +4% time on Kali (docs/FRAME-BYTES.md)
  selectorsOn = !getenv("MLNIX_NOSELECTORS"); // ablation switch: every curried selector runs as two calls, as before
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
  printTrace = [](const std::string &m) { std::cerr << m << std::endl; };
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
  if (scalarJIT) scalarJIT->printStats();
  llvm::errs() << "attribute cells: bytes=" << sizeof(Attr)
               << " position_rows=" << attributePositions.size()
               << " position_bytes=" << attributePositions.capacity() * sizeof(PosPtr) << "\n";
  llvm::errs() << "frame allocations: count=" << nFrames << " bytes=" << nFrameBytes
               << " slots=" << nFrameSlots << " touched=" << nSlotsTouched
               << llvm::format(" (%.1f%% of the slots a frame carries are ever read)", nFrameSlots ? 100.0 * nSlotsTouched / nFrameSlots : 0.0) << '\n';
  if (nFrames) {
    llvm::errs() << "== frames by slot count / first touches by slot index (index 16: 16 or more):\n";
    for (unsigned i = 0; i <= 16; ++i)
      llvm::errs() << llvm::format("   %2u%s  frames %9llu (%5.1f%%)   touches %9llu (%5.1f%%)\n", i, i == 16 ? "+" : " ",
                                   (unsigned long long)nFramesBySize[i], 100.0 * nFramesBySize[i] / nFrames,
                                   (unsigned long long)nTouchAt[i], nSlotsTouched ? 100.0 * nTouchAt[i] / nSlotsTouched : 0.0);
  }
  if (nFrames) {
    static const char *names[kSrcClasses] = {"?", "nixpkgs/lib", "nixos/modules", "nixpkgs/pkgs", "other"};
    llvm::errs() << "== frames by the file that defines the lambda:\n";
    for (unsigned c = 1; c < kSrcClasses; ++c)
      llvm::errs() << llvm::format("   %-14s frames %9llu (%5.1f%%)  slots %10llu (%5.1f%%)  touched %5.1f%% of its slots\n", names[c],
                                   (unsigned long long)nClsFrames[c], 100.0 * nClsFrames[c] / nFrames,
                                   (unsigned long long)nClsSlots[c], 100.0 * nClsSlots[c] / nFrameSlots,
                                   nClsSlots[c] ? 100.0 * nClsTouched[c] / nClsSlots[c] : 0.0);
  }
  if (nFrames)
    llvm::errs() << llvm::format("== curried chains: %llu frames (%.1f%%, %.1f%% of slots) are the outer half of `a: b: ...`: they exist to capture an argument for an inner lambda\n",
                                 (unsigned long long)nChainOuter, 100.0 * nChainOuter / nFrames, 100.0 * nChainOuterSlots / nFrameSlots);
  if (nFrames) {
    composite::MutableSeries<RegionInfo *> top;
    for (auto &kv : regionInfos) if (kv.second->calls) top.append(kv.second);
    cp::sortRows(top.data(), top.size(), [](RegionInfo *a, RegionInfo *b) { return a->calls > b->calls; });
    size_t keep = 40;
    if (const char *t = getenv("MLNIX_STATS_TOP")) keep = std::max<size_t>(1, strtoul(t, nullptr, 10));
    llvm::errs() << "== the " << keep << " lambdas that make the most frames (calls, slots, where):\n";
    uint64_t cum = 0;
    for (size_t i = 0; i < top.size() && i < keep; ++i) {
      cum += top[i]->calls;
      llvm::errs() << llvm::format("   %9llu %2u slots  cum %5.1f%%  ", (unsigned long long)top[i]->calls, top[i]->numSlots, 100.0 * cum / nFrames)
                   << showPos(nd::posOfOp(top[i]->region->getParentOp())) << "\n";
    }
  }
  if (nFrames && getenv("MLNIX_STATS_SHAPES")) {
    struct Group { uint64_t frames = 0, lambdas = 0; std::string example, shape; };
    std::map<std::string, Group> byShape;
    for (auto &kv : regionInfos) {
      RegionInfo *ri = kv.second;
      if (!ri->calls || !ri->region->getParentOp()) continue;
      if (!isa<nd::LambdaOp>(ri->region->getParentOp())) continue;
      std::string sh = shapeOf(ri);
      if (sh.size() > 400) sh = "(large)";
      Group &g = byShape[sh];
      if (g.frames == 0 || ri->calls > g.frames) {}
      if (g.example.empty()) g.example = showPos(nd::posOfOp(ri->region->getParentOp()));
      g.frames += ri->calls; ++g.lambdas; g.shape = sh;
    }
    auto gs = ranked(byShape, [](auto &e) { return e.second.frames; });
    size_t keep = 30;
    if (const char *t = getenv("MLNIX_STATS_SHAPES")) keep = std::max<size_t>(1, strtoul(t, nullptr, 10));
    llvm::errs() << "== lambda shapes by the frames they make (" << gs.size() << " shapes, " << nFrames << " frames):\n";
    uint64_t cum = 0;
    for (size_t i = 0; i < gs.size() && i < keep; ++i) {
      const Group &g = gs[i]->second;
      cum += g.frames;
      llvm::errs() << llvm::format("   %9llu frames in %5llu lambdas  cum %5.1f%%  ", (unsigned long long)g.frames, (unsigned long long)g.lambdas, 100.0 * cum / nFrames)
                   << g.shape << "   e.g. " << g.example << "\n";
    }
  }
  if (nFrames) llvm::errs() << llvm::format("== frames that cannot leak (strict ops only, nothing built over the frame): %llu = %.1f%% of frames, %.1f MB of %.1f MB of frame storage\n",
                                          (unsigned long long)nStackable, 100.0 * nStackable / nFrames, nStackableBytes / 1048576.0, nFrameBytes / 1048576.0);
  if (nFrames) {
    uint64_t bytes[6] = {}, frames[6] = {}, slotsBy[6] = {};   // 1, 2-3, 4-8, 9-16, 17-64, 65+ slots
    for (auto &kv : regionInfos) {
      RegionInfo *ri = kv.second;
      unsigned b = ri->numSlots <= 1 ? 0 : ri->numSlots <= 3 ? 1 : ri->numSlots <= 8 ? 2 : ri->numSlots <= 16 ? 3 : ri->numSlots <= 64 ? 4 : 5;
      frames[b] += ri->calls; bytes[b] += ri->calls * (sizeof(Frame) + ri->numSlots * sizeof(Value *)); slotsBy[b] += ri->calls * ri->numSlots;
    }
    static const char *names[6] = {"1 slot", "2-3 slots", "4-8 slots", "9-16 slots", "17-64 slots", "65+ slots"};
    llvm::errs() << "== frame storage by slots per frame (bytes of frame headers + slot words):\n";
    for (unsigned b = 0; b < 6; ++b)
      llvm::errs() << llvm::format("   %-12s frames %9llu (%5.1f%%)   %7.1f MB (%5.1f%% of frame storage)   slot words %6.1f MB   read %5.1f%%   dead %6.1f MB\n", names[b], (unsigned long long)frames[b],
                                   100.0 * frames[b] / nFrames, bytes[b] / 1048576.0, 100.0 * bytes[b] / nFrameBytes, slotsBy[b] * 8 / 1048576.0,
                                   slotsBy[b] ? 100.0 * nTouchedBy[b] / slotsBy[b] : 0.0, (slotsBy[b] - nTouchedBy[b]) * 8 / 1048576.0);
  }
  if (nFrames) {
    auto mb = [](uint64_t b) { return b / 1048576.0; };
    struct rusage ru; getrusage(RUSAGE_SELF, &ru);
#ifdef __APPLE__
    double rss = mb(ru.ru_maxrss);
#else
    double rss = ru.ru_maxrss / 1024.0;
#endif
    uint64_t mergeBytes = Bindings::mergedCells * sizeof(Attr) + Bindings::merged * sizeof(Bindings);
    uint64_t values = nVT[kAllocated] * sizeof(Value), named = values + nFrameBytes + nBindingBytes + nListBytes + nStringBytes + nMaskBytes + nLayerBytes + mergeBytes + nCtxBytes + nFormalBytes;
    uint64_t handed = alloc.getTotalMemory();  // the slabs, which is what the pages are
    llvm::errs() << llvm::format("== arena: %.0f MB of slabs; peak RSS %.0f MB. By use: values %.0f (%llu cells), frames %.0f, attribute rows %.0f, list cells %.0f, string bytes %.0f, other and slack %.0f MB\n",
                                 mb(handed), rss, mb(values), (unsigned long long)nVT[kAllocated], mb(nFrameBytes), mb(nBindingBytes), mb(nListBytes),
                                 mb(nStringBytes), mb(handed > named ? handed - named + nMaskBytes + nLayerBytes + mergeBytes + nCtxBytes + nFormalBytes : 0));
    llvm::errs() << llvm::format("   \"other\" named: stats census masks %.0f MB (a stats run only), `//` flat merges %.0f, layer headers %.0f, string contexts %.0f, formals %.0f; still unnamed (slab tails, alignment) %.0f MB\n",
                                 mb(nMaskBytes), mb(mergeBytes), mb(nLayerBytes), mb(nCtxBytes), mb(nFormalBytes), mb(handed > named ? handed - named : 0));
  }
  if (nFrames) llvm::errs() << "   of which only the argument slot (no cells at all): " << nStackableOneSlot << " = " << llvm::format("%.1f%%", 100.0 * nStackableOneSlot / nFrames) << " of frames\n";
  if (nSelects) {
    uint64_t sites[4] = {}, siteCalls[4] = {}, sameLast = 0, dynSites = 0;
    for (auto &kv : selSites) {
      const SelSite &x = kv.second;
      unsigned k = x.seen.size() <= 1 ? 0 : x.seen.size() <= 4 ? 1 : x.seen.size() <= 5 ? 2 : 3;   // 1, 2-4, 5, 6+ layouts
      ++sites[k]; siteCalls[k] += x.calls; sameLast += x.sameAsLast; dynSites += x.dynamic;
    }
    llvm::errs() << llvm::format("== selects: %llu (%.1f%% found, %.1f%% on a layered set, %.1f%% with a dynamic key); mean search %.1f probes\n", (unsigned long long)nSelects,
                                 100.0 * nSelectHits / nSelects, 100.0 * nSelectLayered / nSelects, 100.0 * nSelectDyn / nSelects, double(nSelectProbes) / nSelects);
    llvm::errs() << "   set size at the select (log2 buckets):";
    for (unsigned i = 0; i < 18; ++i) if (nSelectSizeLog[i]) llvm::errs() << llvm::format(" <2^%u:%.1f%%", i, 100.0 * nSelectSizeLog[i] / nSelects);
    llvm::errs() << "\n";
    static const char *nm[4] = {"monomorphic (1 layout)", "2-4 layouts", "5 layouts", "6+ layouts (megamorphic)"};
    for (unsigned k = 0; k < 4; ++k)
      llvm::errs() << llvm::format("   %-26s %6llu sites, %5.1f%% of selects\n", nm[k], (unsigned long long)sites[k], 100.0 * siteCalls[k] / nSelects);
    llvm::errs() << llvm::format("   a one-entry cache per site (same layout as the site's last select) would hit %.1f%% of selects\n", 100.0 * sameLast / nSelects);
  }
  if (!thunksByOp.empty()) {
    auto v = ranked(thunksByOp, [](auto &e) { return e.getValue().first; });
    llvm::errs() << "== thunks that need the frame, by operation (share of those; mean operands, of which defined in the same body):\n";
    uint64_t cum = 0;
    for (size_t i = 0; i < v.size() && i < 14; ++i) {
      cum += v[i]->getValue().first;
      uint64_t n = v[i]->getValue().first, packed = v[i]->getValue().second, ops = 0, inside = 0;
      ops = packed / 8; inside = 0;   // the in-body count is accumulated separately below
      (void)inside;
      llvm::errs() << llvm::format("   %-22s %9llu  %5.1f%%  cum %5.1f%%   %.1f operands\n", v[i]->getKey().str().c_str(), (unsigned long long)n, 100.0 * n / nHardThunks, 100.0 * cum / nHardThunks, double(ops) / n);
    }
  }
  llvm::errs() << "values evaluated at their first touch, never a thunk (the caller forces them next): " << nEager << "\n";
  if (nHardThunks) {
    llvm::errs() << llvm::format("== of the thunks that need their frame, %llu (%.1f%%) are forced as the very next thing after they are made: eager evaluation would keep the order and never capture the frame\n",
                                 (unsigned long long)nImmediate, 100.0 * nImmediate / nHardThunks);
    auto v = ranked(immediateByOp, [](auto &e) { return e.getValue(); });
    llvm::errs() << "   by operation:";
    for (size_t i = 0; i < v.size() && i < 8; ++i) llvm::errs() << llvm::format(" %s %.1f%%", v[i]->getKey().str().c_str(), 100.0 * v[i]->getValue() / nImmediate);
    llvm::errs() << "\n";
  }
  if (nProjThunks + nHardThunks) llvm::errs() << llvm::format("== thunks made over a frame: %llu, of which %llu (%.1f%%) are projections of the body's argument or a captured value (the rest %llu need the frame)\n",
                                                              (unsigned long long)(nProjThunks + nHardThunks), (unsigned long long)nProjThunks, 100.0 * nProjThunks / (nProjThunks + nHardThunks), (unsigned long long)nHardThunks);
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
  if (nFrames) llvm::errs() << llvm::format("== a recycling allocator for frames (simulated, projection thunks holding no frame): %llu calls returned with their frame captured (kept), %llu uncaptured (%.1f MB released); %llu of %llu new frames (%.1f%%) would reuse released storage, %.1f MB of the %.1f MB of frame storage\n",
                                          (unsigned long long)nSimCaptured, (unsigned long long)nSimReleased, nSimReleasedBytes / 1048576.0, (unsigned long long)nSimHit, (unsigned long long)nFrames,
                                          100.0 * nSimHit / nFrames, nSimHitBytes / 1048576.0, nFrameBytes / 1048576.0);
  if (nSimHit) {
    llvm::errs() << "   reuse distance (bytes allocated between a frame's release and its reuse):";
    static const char *nm[5] = {"< 32 KiB (Kali L1d)", "< 256 KiB (L2)", "< 2 MiB", "< 32 MiB (L3)", "farther"};
    for (unsigned i = 0; i < 5; ++i) llvm::errs() << llvm::format("  %s %.1f%%", nm[i], 100.0 * nSimReuseDist[i] / nSimHit);
    llvm::errs() << "\n";
  }
  if (nBuilders) llvm::errs() << llvm::format("== attribute-set builders: %llu, %.1f rows each on average; %llu (%.2f%%) outgrow the 12 inline rows and use malloc, holding %.1f%% of all rows built (%.1f MB of rows through a std heap vector and then copied)\n",
                                              (unsigned long long)nBuilders, double(nBuilderRows) / nBuilders, (unsigned long long)nBuildersBig, 100.0 * nBuildersBig / nBuilders,
                                              100.0 * nBuilderBigRows / nBuilderRows, nBuilderBigRows * sizeof(Attr) / 1048576.0);
  llvm::errs() << "calls run on a stack frame (strict bodies over their one argument): " << nStackFrames << "\n";
  llvm::errs() << "selector calls with no frame (lib.optional, lib.optionalAttrs shapes): " << nSelectorCalls << "\n";
  llvm::errs() << "curried intermediates held by value: " << nStackCells << " (" << nStackCells * sizeof(Value) << " bytes of heap cells not allocated)\n";
  llvm::errs() << "empty attribute sets: " << nEmptyShared << " shared as one constant (" << nEmptyShared * (sizeof(Bindings)) << " bytes not allocated)\n";
  llvm::errs() << "value allocations: count=" << nVT[kAllocated] << " bytes=" << nVT[kAllocated] * sizeof(Value) << '\n';
  // How many ops of real programs live where: per tier of the dialect hierarchy
  // (scope > continent > dialect), read from the IRDL declaration.
  auto *core = ctx.getLoadedDialect<nd::NixDialect>();
  llvm::StringMap<size_t> perDialect, perScope, perContinent;
  size_t total = 0;
  for (auto &e : opStats) {
    llvm::StringRef dialect = e.getKey().split('.').first;
    perDialect[dialect] += e.getValue();
    auto it = core->continents.find(dialect);
    perScope[it == core->continents.end() ? "core" : llvm::StringRef(it->second.scope)] += e.getValue();
    perContinent[it == core->continents.end() ? "core" : llvm::StringRef(it->second.continent)] += e.getValue();
    total += e.getValue();
  }
  auto section = [&](const char *title, llvm::StringMap<size_t> &m) {
    llvm::errs() << "== " << title << " (" << m.size() << ")\n";
    for (auto *e : ranked(m, [](auto &e) { return e.getValue(); })) llvm::errs() << "  " << llvm::format("%-9s", e->getKey().str().c_str()) << llvm::format("%9zu", e->getValue()) << "\n";
  };
  // These writes include stack temporaries and repeated mutations of a cell. They
  // describe evaluator work, not a live-heap census or a per-facet allocation count.
  {
    static const char *nm[kAllocated] = {"thunk", "app", "failed", "blackhole", "int", "float", "bool", "null", "string", "path",
                                         "attrs", "list", "lambda", "primop", "primopapp"};
    llvm::errs() << "== instrumented value-tag writes (including stack temporaries; not live heap rows)\n";
    for (unsigned i = 0; i < kAllocated; i++)
      if (nVT[i]) {
        llvm::errs() << "  " << llvm::format("%-11s", nm[i]) << llvm::format("%10llu", (unsigned long long)nVT[i]) << '\n';
      }
  }
  { // The sea of nodes against its schedule: the ops the index holds against the ops that ever ran,
    // file code against the bodies demand minted.  The thunk cells are finer grain's rows.
    llvm::DenseSet<RegionInfo *> minted;
    for (auto &p : pools)
      if (p)
      for (nixev::RegionInfo *ri : p->rows.col<nixfe::PoolCol::Body>().view())
        if (ri) minted.insert(ri);
    uint64_t fOps = 0, fRan = 0, fEvals = 0, fTh = 0, mOps = 0, mRan = 0, mEvals = 0, mTh = 0;
    unsigned fR = 0, mR = 0;
    for (auto &kv : regionInfos) {
      RegionInfo *ri = kv.second;
      uint64_t ran = 0;
      for (uint64_t w : ri->everRan) ran += std::popcount(w);
      if (minted.count(ri)) { mR++; mOps += ri->nOps; mRan += ran; mEvals += ri->nEvals; mTh += ri->nThunks; }
      else { fR++; fOps += ri->nOps; fRan += ran; fEvals += ri->nEvals; fTh += ri->nThunks; }
    }
    llvm::errs() << "== sea of nodes: " << fR << " file regions hold " << fOps << " ops ("
                 << llvm::format("%.1f", fOps ? 100.0 * fRan / fOps : 0.0) << "% ever ran, " << fEvals << " evals, "
                 << fTh << " thunk cells); " << mR << " minted bodies hold " << mOps << " ops ("
                 << llvm::format("%.1f", mOps ? 100.0 * mRan / mOps : 0.0) << "% ever ran, " << mEvals << " evals, "
                 << mTh << " thunk cells).  Finer grain mints a cell: the thunk cells are its rows against lambda grain's "
                 << mR << "\n";
  }
  { uint64_t tc = 0, ts = 0; for (int i = 0; i < 16; i++) { tc += Bindings::getCalls[i]; ts += Bindings::getSteps[i]; }
    if (tc) {
      llvm::errs() << "== Bindings::get on flat sets: " << tc << " calls (+" << Bindings::getLayered << " entered through a layer), " << ts << " binary-search steps; by set size:\n";
      for (int i = 0; i < 16; i++)
        if (Bindings::getCalls[i])
          llvm::errs() << "  size " << llvm::format("%6u", 1u << i) << "+  calls " << llvm::format("%10llu", (unsigned long long)Bindings::getCalls[i]) << llvm::format("  %5.1f%%", 100.0 * Bindings::getCalls[i] / tc)
                       << "  steps " << llvm::format("%11llu", (unsigned long long)Bindings::getSteps[i]) << llvm::format("  (%4.1f a call)", double(Bindings::getSteps[i]) / Bindings::getCalls[i])
                       << "  misses " << llvm::format("%5.1f%%", 100.0 * Bindings::getMiss[i] / Bindings::getCalls[i]) << '\n';
    } }
  if (pre) llvm::errs() << "== prelowering: " << pre->adopted << " files adopted (" << pre->waited << " of them waited for), " << pre->missed << " lowered by the evaluator\n";
  if (nixfe::pathLiterals) { // how predictable is the next file: a file is predicted if a literal naming it (or its directory) was lowered before it was evaluated
    size_t pred = 0, firstSeen = 0, nix = 0;
    std::unordered_set<std::string> hit;
    for (auto &ef : evaluatedFiles) {
      std::string dir = nixstore::dirOf(ef.first);
      bool p = nixfe::pathLiterals->count(ef.first) || nixfe::pathLiterals->count(dir) || nixfe::pathLiterals->count(dir + "/");
      pred += p; if (p) { hit.insert(ef.first); hit.insert(dir); hit.insert(dir + "/"); }
    }
    for (auto &l : *nixfe::pathLiterals) nix += l.size() > 4 && l.compare(l.size() - 4, 4, ".nix") == 0;
    size_t litHit = 0; for (auto &l : *nixfe::pathLiterals) litHit += hit.count(l);
    llvm::errs() << "== import prediction: " << evaluatedFiles.size() << " files evaluated, " << pred << " named by a path literal lowered earlier (recall "
                 << llvm::format("%.1f", evaluatedFiles.empty() ? 0.0 : 100.0 * pred / evaluatedFiles.size()) << "%); " << nixfe::pathLiterals->size() << " distinct path literals ("
                 << nix << " end in .nix), " << litHit << " of them led to an evaluated file (precision "
                 << llvm::format("%.1f", 100.0 * litHit / std::max<size_t>(1, nixfe::pathLiterals->size())) << "%, of the .nix ones' neighbours not separated)\n";
  }
  if (recordEdges && epochEvals.size() > 1) { // the epochs' work and which later epoch needed what an earlier one forced, for a schedule simulation
    if (FILE *f = fopen(getenv("MLNIX_STATS_EDGES"), "w")) {
      for (uint32_t i = 0; i < epochEvals.size(); i++) fprintf(f, "w %u %llu\n", i, (unsigned long long)epochEvals[i]);
      for (uint64_t e : epochEdges) fprintf(f, "e %u %u\n", uint32_t(e >> 32), uint32_t(e));
      fclose(f);
    }
  }
  if (epochEvals.size() > 1) { // how the work divides among the attributes the driver visited: a serial prefix or a flat spread
    uint64_t tot = 0, mx = 0;
    for (uint64_t e : epochEvals) { tot += e; mx = std::max(mx, e); }
    composite::MutableSeries<uint64_t> sorted(epochEvals.size()); // the epochs are only read: the sort's first pass is the drain
    cp::sortRows(epochEvals.data(), sorted.data(), epochEvals.size(), [](uint64_t a, uint64_t b) { return a < b; });
    auto share = [&](size_t n) { uint64_t c = 0; for (size_t i = 0; i < n && i < epochEvals.size(); i++) c += epochEvals[i]; return 100.0 * c / tot; };
    llvm::errs() << "== epochs (attributes visited): " << epochEvals.size() << ", " << tot << " evalOp calls; median " << sorted[sorted.size() / 2] << ", p90 " << sorted[sorted.size() * 9 / 10]
                 << ", max " << mx << " (" << llvm::format("%.1f", 100.0 * mx / tot) << "%); share of the work in the first 1 / 10 / 100 / 10% of the epochs: "
                 << llvm::format("%.1f", share(1)) << "% / " << llvm::format("%.1f", share(10)) << "% / " << llvm::format("%.1f", share(100)) << "% / "
                 << llvm::format("%.1f", share(epochEvals.size() / 10)) << "%\n";
  }
  llvm::errs() << "== symbols: " << symbols.creates << " interning calls, " << symbols.size() << " symbols\n";
  llvm::errs() << "== nodeOf: " << nSlotMisses << " answered by the hash map (" << nodeMap.size() << " values indexed), not its cache\n";
  if (nLookups) {
    llvm::errs() << "== lookupImpl: " << nLookups << " calls, " << nLookupHits << " answered by a filled slot ("
                 << llvm::format("%.1f", 100.0 * nLookupHits / nLookups) << "%); frame hops to the defining region: ";
    for (unsigned i = 0; i < 6; i++) llvm::errs() << (i == 5 ? "5+" : std::to_string(i)) << " " << llvm::format("%.1f", 100.0 * nHopHist[i] / nLookups) << "%  ";
    llvm::errs() << '\n';
    uint64_t tot = 0;
    for (auto &e : evalsByKind) tot += e.second.second;
    auto ev = ranked(evalsByKind, [](auto &e) { return e.second.second; });
    { uint64_t ct = 0;
      for (auto &e : cellsByKind) ct += e.second.second[0] + e.second.second[1];
      auto cv = ranked(cellsByKind, [](auto &e) { return e.second.second[0] + e.second.second[1]; });
      llvm::errs() << "== cells made by lookup, by defining op (" << ct << " in all): evaluated at once (forced), left as a thunk\n";
      for (size_t i = 0; i < cv.size() && i < 14; i++)
        llvm::errs() << "  " << llvm::format("%-26s", cv[i]->second.first.str().c_str()) << llvm::format("%12llu", (unsigned long long)cv[i]->second.second[0]) << llvm::format("%12llu", (unsigned long long)cv[i]->second.second[1]) << '\n'; }
    llvm::errs() << "== evalOp calls by op kind (" << tot << " in all)\n";
    for (size_t i = 0; i < ev.size() && i < 16; i++)
      llvm::errs() << "  " << llvm::format("%-26s", ev[i]->second.first.str().c_str()) << llvm::format("%12llu", (unsigned long long)ev[i]->second.second) << llvm::format("%7.1f%%", 100.0 * ev[i]->second.second / tot) << '\n';
  }
  if (nMatchCalls) { // builtins.match: how often the same (regex, input) comes back, which a memo would answer without matching
    uint64_t repeats = 0, regexes = 0;
    llvm::StringMap<char> res;
    for (auto &e : matchPairs) { repeats += e.getValue() - 1; res[e.getKey().split('\0').first] = 1; }
    llvm::errs() << llvm::format("== builtins.match: %llu calls, %u distinct (regex, input) pairs over %u regexes; %llu calls (%.1f%%) repeat a pair already matched\n",
                                 (unsigned long long)nMatchCalls, matchPairs.size(), res.size(), (unsigned long long)repeats, 100.0 * repeats / nMatchCalls);
    if (getenv("MLNIX_STATS_REGEX")) { // every pattern, with its calls
      llvm::StringMap<uint64_t> byRe;
      for (auto &e : matchPairs) byRe[e.getKey().split('\0').first] += e.getValue();
      for (auto &e : byRe) llvm::errs() << llvm::format("   regex %8llu  ", (unsigned long long)e.getValue()) << e.getKey() << "\n";
    }
  }
  { // The IR the evaluator reads: ops evaluated, and how many bytes of MLIR operations hold the hottest of them (what a compact form would shrink).
    struct Hot { uint32_t evals; uint32_t bytes; };
    cp::MutableSeries<Hot> hot;
    uint64_t evals = 0, irBytes = 0;
    for (auto &kv : regionInfos)
      for (auto &o : kv.second->opIdx) {
        uint32_t e = o.second < kv.second->opEvals.size() ? kv.second->opEvals[o.second] : 0;
        mlir::Operation *op = o.first;
        // an Operation's header, its operands, results and properties: what a read of the op may touch
        uint32_t b = uint32_t(sizeof(mlir::Operation) + op->getNumOperands() * sizeof(mlir::OpOperand) + op->getNumResults() * 16 +
                              op->getPropertiesStorageSize());
        irBytes += b;
        if (e) { hot.append({e, b}); evals += e; }
      }
    cp::sortRows(hot.data(), hot.size(), [](const Hot &a, const Hot &b) { return a.evals > b.evals; });
    uint64_t cum = 0, bytes = 0;
    double marks[] = {0.5, 0.9, 0.99};
    unsigned m = 0;
    llvm::errs() << llvm::format("== IR read: %u indexed ops ran (of %.1f MB of indexed operations), %llu evaluations; the ops of the hottest",
                                 hot.size(), irBytes / 1048576.0, (unsigned long long)evals);
    for (const Hot &h : hot) {
      cum += h.evals; bytes += h.bytes;
      while (m < 3 && cum >= marks[m] * evals) { llvm::errs() << llvm::format(" %.0f%%: %.2f MB", marks[m] * 100, bytes / 1048576.0); ++m; }
    }
    llvm::errs() << llvm::format(" (all that ran: %.1f MB)\n", bytes / 1048576.0);
  }
  if (getenv("MLNIX_STATS_USES")) { // single-use census: per op kind, how many results have no use, one use, several (who could move, who must copy)
    struct U { uint64_t ops = 0, zero = 0, one = 0, many = 0, ranOne = 0; };
    llvm::StringMap<U> byKind;
    for (auto &kv : regionInfos) {
      RegionInfo *ri = kv.second;
      for (auto &o : ri->opIdx) {
        mlir::Operation *op = o.first;
        if (op->getNumResults() != 1) continue;
        U &u = byKind[op->getName().getStringRef()];
        u.ops++;
        unsigned n = std::distance(op->getResult(0).use_begin(), op->getResult(0).use_end());
        (n == 0 ? u.zero : n == 1 ? u.one : u.many)++;
        if (n == 1 && (ri->everRan[o.second >> 6] >> (o.second & 63) & 1)) u.ranOne++;
      }
    }
    { // who reads a single-use string, attrs or concatenation: the consumer's kind, and whether it sits in another region (read once per call of that region, not once)
      llvm::StringMap<std::array<uint64_t, 3>> by; // [same region, nested region, producer evals]
      for (auto &kv : regionInfos)
        for (auto &o : kv.second->opIdx) {
          mlir::Operation *op = o.first;
          if (op->getNumResults() != 1 || !op->hasOneUse()) continue;
          mlir::Operation *c = *op->getUsers().begin();
          { auto &row = by[(op->getName().getStringRef() + " -> " + c->getName().getStringRef()).str()]; row[c->getParentRegion() == op->getParentRegion() ? 0 : 1]++; row[2] += kv.second->opEvals[o.second]; }
        }
      auto r2 = ranked(by, [](auto &e) { return e.getValue()[2]; });
      llvm::errs() << "== single-use string/attrs/concat producers -> consumer: same region, nested region, producer evals (ranked by evals)\n";
      for (size_t i = 0; i < r2.size() && i < 30; i++)
        llvm::errs() << "  " << llvm::format("%-44s", r2[i]->getKey().str().c_str()) << llvm::format("%9llu", (unsigned long long)r2[i]->getValue()[0]) << llvm::format("%9llu", (unsigned long long)r2[i]->getValue()[1]) << llvm::format("%11llu", (unsigned long long)r2[i]->getValue()[2]) << '\n';
    }
    auto rows = ranked(byKind, [](auto &e) { return e.getValue().ops; });
    llvm::errs() << "== single-use census (one-result ops): kind, ops, no use, one use, several, one-use that ran\n";
    for (size_t i = 0; i < rows.size() && i < 40; i++)
      llvm::errs() << "  " << llvm::format("%-26s", rows[i]->getKey().str().c_str()) << llvm::format("%9llu", (unsigned long long)rows[i]->getValue().ops)
                   << llvm::format("%9llu", (unsigned long long)rows[i]->getValue().zero) << llvm::format("%9llu", (unsigned long long)rows[i]->getValue().one)
                   << llvm::format("%9llu", (unsigned long long)rows[i]->getValue().many) << llvm::format("%9llu", (unsigned long long)rows[i]->getValue().ranOne) << '\n';
  }
  if (nSlotsAssigned)
    llvm::errs() << "== frame cells: " << nSlotsAssigned << " assigned, " << nSlotsNoRead
                 << " to a value with no use at all (" << llvm::format("%.1f", 100.0 * nSlotsNoRead / nSlotsAssigned)
                 << "%) -- a value no one reads still costs a cell in every frame of its region\n";
  llvm::errs() << "== mlnix ops lowered: " << total << "\n";
  llvm::errs() << "== `//`: " << nUpdLayered << " layered (" << nUpdBase << " entries not copied, " << nUpdTop << " top entries incl. merges), " << nUpdMerged << " flat merges, " << Bindings::flattened << " layers flattened later\n";
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
  auto o = ranked(opStats, [](auto &e) { return e.getValue(); });
  llvm::errs() << "== top ops\n";
  for (size_t i = 0; i < o.size() && i < 14; i++)
    llvm::errs() << "  " << llvm::format("%-22s", o[i]->getKey().str().c_str()) << llvm::format("%9zu", o[i]->getValue()) << "\n";
}

EvalState::~EvalState() {
  if (pre) {
    { std::lock_guard<std::mutex> g(pre->m); pre->stop = true; }
    pre->cv.notify_all();
    for (auto &w : pre->workers) w.join();
  }
  if (statsEnabled) printStats();
}

bool EvalState::isBaseName(llvm::StringRef name) const { return baseEnv.count(name); }

Value *EvalState::baseEnvValue(llvm::StringRef name) {
  auto it = baseEnv.find(name);
  return it == baseEnv.end() ? nullptr : it->second;
}

static std::string primOpName(const std::string &name) { return name.rfind("__", 0) == 0 ? name.substr(2) : name; }

void EvalState::addPrimOp(const std::string &name, unsigned arity, PrimFn fn) {
  registerPrimOp(name, new PrimOp{primOpName(name), arity, fn, nullptr});
}

void EvalState::addPrimOpClosure(const std::string &name, unsigned arity,
                                 std::function<void(EvalState &, Value **, Value &, PosPtr)> fn) {
  registerPrimOp(name, new PrimOp{primOpName(name), arity, nullptr, std::move(fn)});
}

void EvalState::registerPrimOp(const std::string &name, PrimOp *p) {
  if (p->arity > kMaxPrimArity) llvm::report_fatal_error("a primop with more arguments than EvalState::kMaxPrimArity");
  Value *v = allocValue();
  if (p->arity == 0) {
    // A constant computed by calling fn immediately.
    p->call(*this, nullptr, *v, nullptr);
  } else {
    v->type = VType::PrimOp; if (statsEnabled) ++nVT[unsigned(VType::PrimOp)];
    v->primOp = p;
  }
  addConstant(name, v);
}

void EvalState::addConstant(const std::string &name, Value *v) {
  baseEnv[name] = v;
  std::string bare = name.rfind("__", 0) == 0 ? name.substr(2) : name;
  (void)bare;
}

//===----------------------------------------------------------------------===//
// Positions & errors
//===----------------------------------------------------------------------===//

std::string EvalState::showPos(PosPtr pos) const {
  auto f = nd::decodePos(pos);
  if (!f) return "«none»:0";
  return f->file + ":" + std::to_string(f->line) + ":" + std::to_string(f->col);
}

void EvalState::throwError(const std::string &msg, PosPtr pos) { throw EvalError(msg, pos); }

void EvalState::warn(const std::string &msg) {
  std::cerr << "warning: " << msg << std::endl;
  if (settings.abortOnWarn) throw EvalError(msg);
}

const char *EvalState::showType(const Value &v) {
  switch (v.type) {
  case VType::Int: return "an integer";
  case VType::Bool: return "a Boolean";
  case VType::String: return v.str.ctx ? "a string with context" : "a string";
  case VType::Path: return "a path";
  case VType::Null: return "null";
  case VType::Attrs: return "a set";
  case VType::List: return "a list";
  case VType::Lambda: return "a function";
  case VType::PrimOp: return "a built-in function";
  case VType::PrimOpApp: return "a partially applied built-in function";
  case VType::Float: return "a float";
  case VType::Thunk: case VType::App: case VType::Failed: return "a thunk";
  case VType::Blackhole: return "a thunk";
  }
  return "?";
}

const char *EvalState::typeOf(const Value &v) {
  switch (v.type) {
  case VType::Int: return "int";
  case VType::Bool: return "bool";
  case VType::String: return "string";
  case VType::Path: return "path";
  case VType::Null: return "null";
  case VType::Attrs: return "set";
  case VType::List: return "list";
  case VType::Lambda: case VType::PrimOp: case VType::PrimOpApp: return "lambda";
  case VType::Float: return "float";
  default: return "thunk";
  }
}

void EvalState::throwTypeError(const char *expected, Value &v, PosPtr pos, std::string_view ctx) {
  TypeError e(std::string("expected ") + expected + " but found " + showType(v) + ": " +
                  printValueForTrace(v),
              pos);
  if (!ctx.empty()) e.addTrace(pos, std::string(ctx));
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
      .Case<nd::ConcatStringsOp>([&](nd::ConcatStringsOp c) { n->flags = c.getForceString() ? Node::kForceString : 0; return NodeKind::ConcatStrings; })
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
      .Default([&](Operation *o) { return core->primOf(o) ? NodeKind::Prim : NodeKind::Other; }); // a primop is found at its first evaluation
}

void EvalState::unindexed() { throw EvalError("internal error: unindexed SSA value"); }

void EvalState::indexRegion(Region &r) { indexer.index(r); }

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
  // captures are what goes into the map of every value (below, with the operands); and every value does when a JIT, which reads any value
  // by its address, is on.  (An op evaluated through the interface model puts its operands there itself: evalOther.)
  ++depth;
  bool everyValue = st.scalarJIT != nullptr;
  auto publish = [&](mlir::Value v, Node *n) {
    void *key = v.getAsOpaquePointer();
    blockNodes[key] = n;
    if (everyValue) st.setNode(key, n);
  };
  for (BlockArgument a : blk.getArguments()) {
    if (stats) { ++st.nSlotsAssigned; if (a.use_empty()) ++st.nSlotsNoRead; }
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
      if (stats) {
        ++st.nSlotsAssigned;
        if (res.use_empty()) ++st.nSlotsNoRead;
        // A cell that starts as a thunk is finer grain's row: an attribute value, a let binding, an argument,
        // minted when it is forced instead of when its body is.
        if (p == Promotion::Shared || p == Promotion::Distinct || p == Promotion::Once) ++ri->nThunks;
      }
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
  // A deferred lambda's region is a shell until its first call; it is indexed when it is minted.
  for (Operation &op : blk) {
    auto lam = dyn_cast<nd::LambdaOp>(op);
    if (lam && lam.getBodyIndex()) continue;
    for (Region &nested : op.getRegions())
      if (!nested.empty()) index(nested);
  }
  // Then each op's operands, as the records of the values they name (an operand not indexed stays null: its use is an internal error).
  // A helper indexes a whole file, which reads nothing from outside it: what is not in blockNodes is nowhere.
  auto recordOf = [&](mlir::Value v) -> Node * {
    void *key = v.getAsOpaquePointer();
    auto it = blockNodes.find(key);
    return it != blockNodes.end() ? it->second : helper ? nullptr : st.nodeOf(key);
  };
  for (Operation &op : blk) {
    unsigned k = op.getNumOperands();
    if (op.getNumResults() == 0 || k == 0) continue;
    auto **ops = static_cast<Node **>(allocate(k * sizeof(Node *), alignof(Node *)));
    for (unsigned i = 0; i < k; i++) ops[i] = recordOf(op.getOperand(i));
    if (auto lam = dyn_cast<nd::LambdaOp>(op); lam && lam.getBodyIndex() && !everyValue)
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
    ri->opEvals.assign(ri->nOps, 0);
    uint32_t oi = 0;
    for (Operation &op : blk) ri->opIdx[&op] = oi++;
  }
  if (helper) regions.append({&r, ri});
  else st.regionInfos[&r] = ri;
}

RegionInfo *EvalState::regionInfo(Region *r) {
  auto it = regionInfos.find(r);
  if (it != regionInfos.end()) return it->second;
  indexRegion(*r);
  return regionInfos[r];
}

unsigned EvalState::srcClassOf(RegionInfo *ri) {
  if (ri->srcClass) return ri->srcClass;
  unsigned c = 4;
  if (auto f = nd::decodePos(nd::posOfOp(ri->region->getParentOp()))) {
    const std::string &p = f->file;
    c = p.find("nixpkgs/lib/") != std::string::npos ? 1 : p.find("nixos/modules/") != std::string::npos ? 2
        : p.find("nixpkgs/pkgs/") != std::string::npos ? 3 : 4;
  }
  return ri->srcClass = uint8_t(c);
}

/// Can a call of this body run on a stack frame?  Yes when nothing in it can make a thunk, a closure, a list or a set over the frame (a
/// lazy operand is a thunk whose env is the frame, and the callee or the result may keep it) and it holds no cell but its argument: only
/// strict ops, whose operands are read in place.  Such a call allocates nothing in the never-freed arena.
bool EvalState::classifyStackFrame(RegionInfo *ri) {
  ri->stackable = 0;
  if (ri->numSlots > 1) return false;
  // The rule is the dialect's, not a list of names: an op whose every operand is strict or tail (its NixModes, or nix.strict on a continent
  // op) reads its operands in place and makes no thunk over the frame; an op without operands may only be a constant.
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

/// MLNIX_STATS: would this thunk need its frame?  Not if it is a projection: a select with static keys and no default, or a has_attr, of this body's
/// argument or of a value captured from outside.  Its inputs are cells that already exist, so it could be a thunk of (base cell, path).
static const char *downgradeSet() { static const char *e = getenv("MLNIX_STATS_DOWNGRADE"); return e; }
static bool isProjection(mlir::Operation *op) {
  if (const char *d = downgradeSet()) {            // the experiment: these families would hold their operand cells, not the frame
    std::string name = op->getName().getStringRef().str();
    if (std::string(d) == "all") return true;
    for (const char *p = d; *p;) {
      const char *q = strchr(p, ',');
      std::string tok = q ? std::string(p, q) : std::string(p);
      if (name.find(tok) != std::string::npos) return true;
      if (!q) break;
      p = q + 1;
    }
  }
  mlir::Value base;
  if (auto sel = dyn_cast<nd::SelectOp>(op)) { if (!sel.getDynKeys().empty() || sel.getDefaultValue()) return false; base = sel.getBase(); }
  else if (auto h = dyn_cast<nd::HasAttrOp>(op)) { base = h.getOperand(0); }
  else return false;
  return isa<mlir::BlockArgument>(base) || base.getParentRegion() != op->getParentRegion();
}

/// MLNIX_STATS: the frame's bookkeeping words, after its slots and read-mask: pinned, unforced thunks over it, state (1 = a call is running in it, 2 = released).
static inline uint64_t *frameWords(Frame *f) { unsigned n = f->info->numSlots; return reinterpret_cast<uint64_t *>(f->slots + n) + (n + 63) / 64; }
/// A frame is released to the simulated free list when no call runs in it, nothing pins it (a closure) and every thunk over it has been forced.
static void trySimRelease(EvalState &st, Frame *f) {
  uint64_t *w = frameWords(f);
  if (w[0] || w[1] || (w[2] & 3) != 0) return;   // pinned, thunks left, still running, or already released
  w[2] |= 2;
  unsigned n = f->info->numSlots;
  if (n >= st.simFree.size()) st.simFree.resize(n + 1);
  st.simFree[n].append(st.allocClock()); ++st.nSimReleased; st.nSimReleasedBytes += sizeof(Frame) + n * sizeof(Value *);
}
/// A thunk (or, pinned, a closure) now refers to this frame.
void EvalState::markCaptured(Frame *f) { ++frameWords(f)[1]; }
void EvalState::markPinned(Frame *f) { frameWords(f)[0] = 1; }
/// A thunk over this frame has been forced: it holds its value now, not the frame.
void EvalState::statUnref(Frame *f) { uint64_t *w = frameWords(f); if (w[1]) --w[1]; trySimRelease(*this, f); }
/// A call has returned.
void EvalState::statReturn(Frame *f) {
  uint64_t *w = frameWords(f);
  w[2] &= ~uint64_t(1);
  if (w[0] || w[1]) ++nSimCaptured;
  trySimRelease(*this, f);
}

Frame *EvalState::newFrameSlow(RegionInfo *ri, Frame *up) {
  if (unsigned n = ri->numSlots; n < kRecycleMax && freeFrames[n] && !statsEnabled) {
    Frame *f = freeFrames[n];
    freeFrames[n] = reinterpret_cast<Frame *>(f->upBits);
    f->upBits = reinterpret_cast<uintptr_t>(up);
    f->info = ri;
    memset(f->slots, 0, n * sizeof(Value *));
    return f;
  }
  size_t sz = sizeof(Frame) + ri->numSlots * sizeof(Value *);
  size_t maskBytes = statsEnabled ? (((ri->numSlots + 63) / 64) + 3) * sizeof(uint64_t) : 0; // stats only: the mask of slots ever read, after the slots
  if (statsEnabled) nMaskBytes += maskBytes;
  auto *f = static_cast<Frame *>(alloc.Allocate(sz + maskBytes, alignof(Frame)));
  if (statsEnabled) { ++nFrames; nFrameBytes += sz; nFrameSlots += ri->numSlots; ++nFramesBySize[ri->numSlots < 16 ? ri->numSlots : 16];
    ++ri->calls;
    if (ri->chainOuter == 2) ri->chainOuter = isa_and_nonnull<nd::LambdaOp>(ri->result.getDefiningOp());
    if (ri->chainOuter == 1) { ++nChainOuter; nChainOuterSlots += ri->numSlots; }
    stackFrameOK(ri);
    if (ri->stackable == 1) { ++nStackable; nStackableBytes += sizeof(Frame) + ri->numSlots * sizeof(Value *); if (ri->numSlots <= 1) ++nStackableOneSlot; }
    unsigned c = srcClassOf(ri); ++nClsFrames[c]; nClsSlots[c] += ri->numSlots; }
  f->upBits = reinterpret_cast<uintptr_t>(up);
  f->info = ri;
  memset(f->slots, 0, ri->numSlots * sizeof(Value *) + maskBytes);
  if (statsEnabled) {
    // a recycled frame, if one of this size was released (the simulation: nothing is reused, only counted)
    if (ri->numSlots >= simFree.size()) simFree.resize(ri->numSlots + 1);
    if (!simFree[ri->numSlots].empty()) {
      uint64_t dist = allocClock() - simFree[ri->numSlots].back();
      simFree[ri->numSlots].pop(); ++nSimHit; nSimHitBytes += sz;
      ++nSimReuseDist[dist < (32u << 10) ? 0 : dist < (256u << 10) ? 1 : dist < (2u << 20) ? 2 : dist < (32u << 20) ? 3 : 4];
    }
  }
  if (statsEnabled) { frameWords(f)[2] = 1; if (ri->numSlots) reinterpret_cast<uint64_t *>(f->slots + ri->numSlots)[0] |= 1; } // slot 0 is the argument
  return f;
}

static Node::How howOf(Operation *op) {
  if (isa<nd::IntOp, nd::FloatOp, nd::StringOp, nd::PathOp, nd::BoolOp, nd::NullOp>(op)) return Node::Const;
  if (isa<nd::BuiltinOp>(op)) return Node::Builtin;
  if (isa<nd::LambdaOp>(op)) return Node::Lambda;
  return Node::Thunk;
}

/// MLNIX_STATS: the first read of a frame slot.  Cold and out of line, so lookup() carries one test and one call, not the census.
void EvalState::statTouch(Frame *f, RegionInfo *ri, unsigned idx) {
  ++nSlotsTouched; ++nTouchAt[idx < 16 ? idx : 16]; ++nClsTouched[srcClassOf(ri)];
  reinterpret_cast<uint64_t *>(f->slots + ri->numSlots)[idx / 64] |= uint64_t(1) << (idx % 64);
  ++nTouchedBy[ri->numSlots <= 1 ? 0 : ri->numSlots <= 3 ? 1 : ri->numSlots <= 8 ? 2 : ri->numSlots <= 16 ? 3 : ri->numSlots <= 64 ? 4 : 5];
}

void EvalState::statHops(Frame *f, RegionInfo *ri, bool hit) {
  unsigned h = 0;
  while (f && f->info != ri) { f = f->up(); ++h; }
  ++nLookups; nLookupHits += hit; ++nHopHist[h < 5 ? h : 5];
}

/// MLNIX_STATS: the census of a cell lookup makes (cold, out of line).
void EvalState::statCell(Frame *f, Node *s, Value *nv, bool eager) {
  Operation *op = s->def;
  auto &c = cellsByKind[op->getName().getAsOpaquePointer()]; c.first = op->getName().getStringRef(); ++c.second[eager ? 0 : 1];
  if (eager || !f) return;
  if (nv->type == VType::Lambda) markPinned(f);
  else if (isProjection(op)) ++nProjThunks;          // in the simulated world this thunk holds (base cell, path), not the frame
  else {
    ++nHardThunks; markCaptured(f); lastThunk = nv;
    auto &e = thunksByOp[op->getName().getStringRef()];
    ++e.first;
    unsigned inside = 0;                                // operands defined in this very body: cells the thunk would have to create first
    for (mlir::Value o : op->getOperands()) inside += !isa<mlir::BlockArgument>(o) && o.getParentRegion() == op->getParentRegion();
    e.second += op->getNumOperands() * 8u + inside;     // packed: total operands in the high part, in-body operands in the low byte below
  }
}

/// A literal's or a builtin's one cell, made at its first touch in any frame and kept in the node.
Value *EvalState::makeFixed(Node *s) {
  Operation *op = s->def;
  if (s->how == Node::Builtin) { // the base environment is complete before anything is evaluated
    auto b = cast<nd::BuiltinOp>(op);
    Value *bv = baseEnvValue(b.getName().str());
    if (!bv) throw EvalError("undefined variable '" + b.getName().toString() + "'", nd::posOfOp(op));
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
    if (recycleOn) f->capture();
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
  if (statsEnabled) [[unlikely]] { Frame *g = f; while (g && g->info != ri) g = g->up(); statHops(f, ri, g && idx != kNoSlot && g->slots[idx]); }
  while (f && f->info != ri) f = f->up();
  if (!f) throw EvalError("internal error: SSA value used outside its scope");
  Value *noCell = nullptr; // a value made by its one use, or an in-place one reached through lookup(): the cell is not kept in the frame
  Value *&slot = idx == kNoSlot ? noCell : f->slots[idx];
  if (slot) return slot;
  if (statsEnabled && idx != kNoSlot) [[unlikely]] statTouch(f, ri, idx);
  if (s->kind == NodeKind::Arg) throw EvalError("internal error: unbound block argument");
  if (s->how == Node::Const || s->how == Node::Builtin) return slot = makeFixed(s);
  Value *nv = allocValue();
  bool eager = forced && s->how == Node::Thunk && (idx != kNoSlot || s->promo == Promotion::Once);
  if (eager) {
    slot = nv;
    if (statsEnabled) [[unlikely]] statCell(f, s, nv, true);
    return evalNow(f, s, nv);
  }
  nv->type = s->how == Node::Lambda ? VType::Lambda : VType::Thunk;
  nv->thunk.node = s;
  nv->thunk.env = f;
  if (recycleOn) f->capture();
  if (statsEnabled) [[unlikely]] statCell(f, s, nv, false);
  return slot = nv;
}

/// Evaluates the defining op of an in-place value straight into `dest`.  Lambdas are
/// closures, built where lookup() would build them.
void EvalState::evalDefinition(Node *def, Frame *f, Value &dest) {
  if (def->kind == NodeKind::Lambda) {
    dest.type = VType::Lambda; if (statsEnabled) ++nVT[unsigned(VType::Lambda)];
    dest.thunk.node = def;
    dest.thunk.env = f;
    if (recycleOn && f) f->capture();
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

void EvalState::epochTouch(const Value &v) {
  uint32_t cur = epochEvals.size() - 1;
  if (v.type == VType::Thunk || v.type == VType::App) { forcedBy[&v] = cur; return; } // about to be forced here
  auto it = forcedBy.find(&v);
  if (it != forcedBy.end() && it->second != cur) epochEdges.insert(uint64_t(it->second) << 32 | cur);
}

void EvalState::forceCell(Value &v, PosPtr pos) {
  if (recordEdges && !epochEvals.empty()) [[unlikely]] epochTouch(v);
  if (statsEnabled && lastThunk) [[unlikely]] {
    if (&v == lastThunk && v.type == VType::Thunk) { ++nImmediate; ++immediateByOp[v.thunk.node->def->getName().getStringRef()]; }
    lastThunk = nullptr;
  }
  if (v.type == VType::Thunk) {
    Node *n = v.thunk.node;
    Frame *env = v.thunk.env;
    v.type = VType::Blackhole; if (statsEnabled) ++nVT[unsigned(VType::Blackhole)];
    try {
      evalOp(n, env, v);
      if (statsEnabled && env && !isProjection(n->def)) [[unlikely]] statUnref(env);
    } catch (EvalError &) {
      fail(v);
      throw;
    } catch (...) {
      v.type = VType::Thunk; if (statsEnabled) ++nVT[unsigned(VType::Thunk)];
      v.thunk.node = n;
      v.thunk.env = env;
      throw;
    }
  } else if (v.type == VType::App) {
    Value *l = v.app.left, *r = v.app.right;
    v.type = VType::Blackhole; if (statsEnabled) ++nVT[unsigned(VType::Blackhole)];
    try {
      callFunction(*l, 1, &r, v, pos);
    } catch (...) {
      v.type = VType::App; if (statsEnabled) ++nVT[unsigned(VType::App)];
      v.app.left = l;
      v.app.right = r;
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
  v.type = VType::Failed; if (statsEnabled) ++nVT[unsigned(VType::Failed)];
}

template <class E> [[noreturn]] static void throwCopy(const E &e) {
  E c(e.msg, e.pos);
  for (const Trace &t : e.traces) c.traces.append(t);
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
  std::set<const void *> seen;
  std::function<void(Value &)> rec = [&](Value &v) {
    if (callDepth >= settings.maxCallDepth) throw StackOverflowError("stack overflow; max-call-depth exceeded");
    DepthGuard g(callDepth);
    forceValue(v);
    if (!seen.insert(&v).second) return;
    if (v.type == VType::Attrs) {
      for (auto &a : *v.attrs) {
        try {
          rec(*a.value);
        } catch (EvalError &e) {
          e.addTrace(positionOf(a), "while evaluating the attribute '" + symbols[a.name].str() + "'");
          throw;
        }
      }
    } else if (v.type == VType::List) {
      for (size_t i = 0; i < v.listSize(); i++) rec(*v.list.elems[i]);
    }
  };
  rec(v);
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
    std::string first = v.str.ctx->elems[0];
    std::string what = first[0] == '=' ? first.substr(1) : first[0] == '!' ? first.substr(first.find('!', 1) + 1) : first;
    throw EvalError("the string '" + std::string(s) + "' is not allowed to refer to a store path (such as '" +
                        nixstore::baseNameOf(what) + "')",
                    pos);
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
static std::unique_ptr<mlir::PassManager> makeOptimizer(mlir::MLIRContext &,
                                                        const EvalSettings &);

/// The pass pipeline as text: MLNIX_PIPELINE over the setting.
static std::string pipelineText(const EvalSettings &settings) {
  const char *e = getenv("MLNIX_PIPELINE");
  return e ? e : settings.pipeline;
}

RegionInfo *EvalState::mintLambda(nixfe::FilePool &p, uint32_t row) {
  auto t0 = std::chrono::steady_clock::now();
  auto lam = cast<nd::LambdaOp>(p.rows.col<nixfe::PoolCol::Op>()[row]);
  if (lam.getBody().front().empty()) { // not minted ahead by the helper that prelowered the file
    nixfe::GenOptions go;
    go.isBaseName = [this](llvm::StringRef n) { return isBaseName(n); };
    go.deferBodies = true; // lambdas nested in this body wait for their own first call
    go.pool = &p;
    nixfe::mintBody(lam, p, row, go);
    if (settings.optimize) mlir::nix::devirtualizePrims(lam);
  }
  nixprefetch::noteMint(p.origin->path.c_str(), row);
  if (statsEnabled) {
    lam.getBody().walk([&](mlir::Operation *o) { ++opStats[o->getName().getStringRef()]; });
    ++nDemandMinted;
    nsMint += std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now() - t0).count();
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
  std::optional<uint64_t> deferred = lam.getBodyIndex();
  return deferred ? bodyOf(nixfe::BodyIndex(*deferred)) : regionInfo(&lam.getBody());
}

void EvalState::callLambda(Value &fun, Value *arg, Value &out, PosPtr pos) {
  callLambdaIn(fun, bodyOfNode(fun.thunk.node), arg, out, pos);
}

//===----------------------------------------------------------------------===//
// Error paths: the messages are built here, in functions of their own, and the compiler decides what to inline.
//===----------------------------------------------------------------------===//

static std::string lambdaDesc(nd::LambdaOp lam) {
  if (auto n = lam.getName()) return "function '" + n->str() + "'";
  return "function 'anonymous lambda'";
}
[[noreturn]] static void throwMissingArg(nd::LambdaOp lam, llvm::StringRef formal, PosPtr pos) {
  throw EvalError(lambdaDesc(lam) + " called without required argument '" + formal.str() + "'", pos).addTrace(nd::posOfOp(lam), "from call site");
}
[[noreturn]] static void throwUnexpectedArg(nd::LambdaOp lam, llvm::StringRef name, PosPtr pos) {
  throw EvalError(lambdaDesc(lam) + " called with unexpected argument '" + name.str() + "'", pos).addTrace(nd::posOfOp(lam), "from call site");
}
[[noreturn]] static void throwUndefinedVariable(const nixfe::Name &n, PosPtr pos) { throw EvalError("undefined variable '" + n.toString() + "'", pos); }
[[noreturn]] static void throwMissingFormal(const nixfe::Name &n, PosPtr pos) { throw EvalError("missing formal argument '" + n.toString() + "'", pos); }
[[noreturn]] static void throwCannotEvaluate(mlir::Operation *o, PosPtr pos) {
  throw EvalError("internal error: cannot evaluate operation '" + o->getName().getStringRef().str() + "'", pos);
}
[[noreturn]] static void throwAssertFailed(nd::AssertOp a, PosPtr pos) {
  std::string txt = a.getText() ? a.getText()->str() : "?";
  throw AssertionError("assertion '" + txt + "' failed", pos);
}
[[noreturn]] static void throwIntOverflow(int64_t n, int64_t m, PosPtr pos) {
  throw EvalError("integer overflow in adding " + std::to_string(n) + " + " + std::to_string(m), pos);
}
[[noreturn]] static void throwCannotAdd(const char *type, const char *to, PosPtr pos) {
  throw EvalError(std::string("cannot add ") + type + " to " + to, pos);
}
[[noreturn]] static void throwAttrMissing(llvm::StringRef name, PosPtr pos) { throw EvalError("attribute '" + name.str() + "' missing", pos); }

void EvalState::callLambdaIn(Value &fun, RegionInfo *ri, Value *arg, Value &out, PosPtr pos) {
  auto lam = cast<nd::LambdaOp>(fun.thunk.node->def);
  if (ri->hasFormals) { // what the formals are was read once, at indexing: the op's attributes are read here only at a first call and on errors
    try {
      forceAttrs(*arg, pos, "while evaluating the value passed for the lambda argument");
    } catch (EvalError &e) {
      e.addTrace(nd::posOfOp(lam), "while calling " + lambdaDesc(lam));
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
    else if (!f->captured() && recycleOn) recycleFrame(f);  // returned with nothing made over it: nothing can reach it again
  };
  if (scalarJIT && scalarJIT->accepts(ri->jitEntry))
    scalarJIT->evaluate(*this, lam, ri->result, fun.thunk.env, *arg, out, pos, ri->jitEntry, interpret);
  else interpret();
}

void EvalState::callPrimOp(const PrimOp &op, Value **args, Value &out, PosPtr pos) {
  try {
    op.call(*this, args, out, pos);
  } catch (EvalError &e) {
    if (op.name != "throw" && op.name != "abort" && op.name != "addErrorContext")
      e.addTrace(pos, "while calling the '" + op.name + "' builtin");
    throw;
  }
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
  std::optional<uint64_t> deferred = inner.getBodyIndex();
  RegionInfo *ri = deferred ? bodyOf(nixfe::BodyIndex(*deferred)) : regionInfo(&inner.getBody());
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

/// The shape of a lambda: its ops in order with the names, positions and file taken out, so two lambdas that compute the same thing
/// the same way have the same string.  Operands are `aN` (the Nth argument of this body), `rN` (the Nth op of this body), `cK` (a
/// value captured from outside, by distance K), and a returned lambda's body is written inline.  Constants keep their value.
std::string EvalState::shapeOf(RegionInfo *ri, unsigned depth) {
  if (depth == 0 && !ri->shape.empty()) return ri->shape;
  std::string out;
  llvm::DenseMap<const void *, std::string> ids;
  mlir::Block &blk = ri->region->front();
  for (unsigned i = 0; i < blk.getNumArguments(); ++i) ids[blk.getArgument(i).getAsOpaquePointer()] = "a" + std::to_string(i) + (depth ? "'" : "");
  unsigned n = 0;
  auto ref = [&](mlir::Value v) { auto it = ids.find(v.getAsOpaquePointer()); return it == ids.end() ? std::string("c") : it->second; };
  for (mlir::Operation &op : blk) {
    std::string id = "r" + std::to_string(n++) + (depth ? "'" : "");
    out += op.getName().getStringRef().str();
    if (auto iv = dyn_cast<nd::IntOp>(op)) out += "=" + std::to_string(iv.getValue());
    else if (auto bv = dyn_cast<nd::BoolOp>(op)) out += bv.getValue() ? "=true" : "=false";
    else if (auto sv = dyn_cast<nd::StringOp>(op)) { out += "=\""; out += sv.getValue().str().substr(0, 12); out += "\""; }
    out += "(";
    if (auto lam = dyn_cast<nd::LambdaOp>(op)) {
      if (depth < 4) {
        std::optional<uint64_t> deferred = lam.getBodyIndex();
        RegionInfo *inner = deferred ? bodyOf(nixfe::BodyIndex(*deferred)) : regionInfo(&lam.getBody());
        out += (lam.getFormals() ? "formals" : "arg") + std::string(": ") + shapeOf(inner, depth + 1);
      }
    } else {
      bool first = true;
      for (mlir::Value v : op.getOperands()) { out += (first ? "" : ",") + ref(v); first = false; }
    }
    out += ") ";
    for (mlir::Value r : op.getResults()) ids[r.getAsOpaquePointer()] = id;
  }
  if (depth == 0) ri->shape = out;
  return out;
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

/// The opt-in JIT's saturated chain of 2 to 4 unary lambdas: true when native code ran the whole call.  Out of line: the loop that
/// asks is the evaluator's hottest, and a run without MLNIX_JIT never gets here.
bool EvalState::jitChain(nd::LambdaOp lambda, RegionInfo *ri, Value &cur, size_t n, Value **args, Value &out, PosPtr pos) {
  if (!scalarJIT->acceptsSaturated(nullptr) || !scalarJIT->acceptsSaturated(ri->curriedEntry, unsigned(n))) return false;
  // This outer body is reached by the ordinary call as well. Descendant bodies are only inspected after the interpreter oracle has run them.
  auto interpret = [&] { callFunction(cur, n, args, out, pos, false); };
  return scalarJIT->evaluateSaturated(*this, lambda, ri->result, cur.thunk.env, llvm::ArrayRef<Value *>(args, n), out, pos, ri->curriedEntry, interpret);
}

void EvalState::notAFunction(Value &cur, PosPtr pos) {
  throw EvalError(std::string("attempt to call something which is not a function but ") + showType(cur) + ": " + printValueForTrace(cur), pos);
}

void EvalState::callFunction(Value &fun, size_t nargs, Value **args, Value &out, PosPtr pos, bool allowCurried) {
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
      curRI = bodyOfNode(cur->thunk.node); // the selector check, the JIT check and the call below all use it
      if (selectorsOn && nargs - i >= 2 && !curRI->hasFormals) {
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
    if (allowCurried && scalarJIT && nargs - i >= 2 && nargs - i <= 4 && curRI && !curRI->hasFormals &&
        jitChain(curLam, curRI, *cur, nargs - i, args + i, out, pos))
      return;
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
          app->type = VType::PrimOpApp; if (statsEnabled) ++nVT[unsigned(VType::PrimOpApp)];
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

void EvalState::autoCallFunction(const std::map<std::string, Value *> &autoArgs, Value &fun, Value &out) {
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
  BindingsBuilder bb(*this);
  auto defs = *lam.getFormalDefaults();
  for (size_t i = 0; i < lam.getFormals()->size(); i++) {
    std::string name = cast<StringAttr>((*lam.getFormals())[i]).getValue().str();
    auto it = autoArgs.find(name);
    if (it != autoArgs.end()) bb.insert(name, it->second);
    else if (!defs[i])
      throw EvalError("cannot evaluate a function that has an argument without a value ('" + name +
                          "')\nNix attempted to evaluate a function as a top level expression; in this case it must have its arguments supplied either by default values, or passed explicitly with '--arg' or '--argstr'. See https://nix.dev/manual/nix/stable/language/syntax.html#functions.",
                      nd::posOfOp(lam));
  }
  if (lam.getEllipsis())
    for (auto &[k, v] : autoArgs) bb.insert(k, v);
  Value *arg = allocValue();
  mkAttrs(*arg, bb.finish());
  callFunction(fun, *arg, out, nullptr);
}

//===----------------------------------------------------------------------===//
// Op semantics
//===----------------------------------------------------------------------===//

PosIdx EvalState::positionIndex(PosPtr pos) {
  if (!pos) return 0;
  auto it = dynamicPositions.find(pos);
  if (it != dynamicPositions.end()) return it->second;
  if (attributePositions.size() >= std::numeric_limits<PosIdx>::max())
    throw EvalError("attribute position table exhausted");
  PosIdx index = attributePositions.append(pos);
  dynamicPositions.emplace(pos, index);
  return index;
}

PosIdx EvalState::positionBase(nd::AttrsOp op) {
  auto positions = op.getPositions();
  size_t count = std::min(positions.size(), op.getNames().size());
  if (!count) return 0;
  auto it = attrPositionBases.find(op.getOperation());
  if (it != attrPositionBases.end()) return it->second;
  if (count > std::numeric_limits<PosIdx>::max() - attributePositions.size())
    throw EvalError("attribute position table exhausted");
  PosIdx base = attributePositions.size();
  for (size_t i = 0; i < count; ++i)
    attributePositions.append(nd::posOfWord(uint64_t(positions[i])));
  attrPositionBases.try_emplace(op.getOperation(), base);
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
  if (statsEnabled) [[unlikely]] { ++nBuilders; nBuilderRows += m; if (m > 12) { ++nBuildersBig; nBuilderBigRows += m; } }
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

/// Dynamic attributes are inserted one by one with duplicate checks: out of line, where the std::map lives.
void EvalState::evalAttrsDynamic(Node *node, Frame *env, Value &out) {
  auto op = cast<nd::AttrsOp>(node->def);
  auto names = op.getNames();
  Node **values = node->operands;
  size_t nDynNames = (node->nOperands - node->nDyn) / 2;     // the dynamic names, then their values
  Node **dynNames = node->operands + node->nDyn, **dynValues = dynNames + nDynNames;
  auto positions = op.getPositions();
  PosIdx posBase = positionBase(op);
  BindingsBuilder bb(*this);
  for (size_t i = 0; i < names.size(); i++) {
    PosIdx p = i < positions.size() ? posBase + i : 0;
    bb.insertIndexed(symbolOf(names[i]), lookup(env, values[i]), p);
  }
  std::map<Symbol, PosPtr> seen;
  for (size_t i = 0; i < names.size(); i++)
    seen[symbolOf(names[i])] = nullptr;
  for (size_t j = 0; j < nDynNames; j++) {
    Value *nv = lookup(env, dynNames[j]);
    PosPtr p = dynNames[j]->pos();
    forceValue(*nv, p);
    if (nv->type == VType::Null) continue;
    auto name = forceStringNoCtx(*nv, p, "while evaluating the name of a dynamic attribute");
    Symbol sym = symbolOfString(name);
    if (seen.count(sym))
      throw EvalError("dynamic attribute '" + std::string(name) + "' already defined at " +
                          showPos(seen[sym] ? seen[sym] : nd::posOfOp(op)),
                      p);
    seen[sym] = p;
    bb.insert(sym, lookup(env, dynValues[j]), p);
  }
  mkAttrs(out, bb.finish());
}

void EvalState::evalConcatStrings(Node *node, Frame *env, Value &out) {
  // The result is the series of its parts.  A part that is already a string is a view of its arena bytes: no copy and no heap string; only a
  // part that must be coerced (a number, a path, a set with __toString or outPath) makes text, kept in `owned` where it does not move.  The
  // total is known before anything is written, so the result is one arena buffer, filled once.  Numbers and paths are as they were.
  auto parts = node->args();
  bool forceString = node->flags & Node::kForceString;
  NixStringContext context;
  // The windows of the parts: a stack array (the arena past sixteen parts).  A part that must be coerced (a number, a path, a set with __toString)
  // makes text in `scratch`, which is copied into the arena at once, so no part owns anything and nothing is a heap list.
  size_t np = parts.size(), nv = 0;
  composite::Chars stackViews[16];
  composite::Chars *views = np <= 16 ? stackViews : static_cast<composite::Chars *>(alloc.Allocate(np * sizeof(composite::Chars), alignof(composite::Chars)));
  std::string scratch;
  PieceContexts own; // the string pieces' own contexts: shared as the result's when there is one, merged only when there are several
  size_t total = 0;
  int64_t n = 0;
  double nf = 0;
  bool first = !forceString;
  VType firstType = VType::String;
  for (Node *pv : parts) {
    PosPtr ppos = pv->pos();
    Value *v = lookup(env, pv);
    forceValue(*v, ppos);
    if (first) firstType = v->type;
    if (firstType == VType::Int) {
      if (v->type == VType::Int) {
        if (__builtin_add_overflow(n, v->integer, &n)) throwIntOverflow(n, v->integer, ppos);
      } else if (v->type == VType::Float) {
        firstType = VType::Float;
        nf = (double)n;
        nf += v->fpoint;
      } else {
        throwCannotAdd(showType(*v), "an integer", ppos);
      }
    } else if (firstType == VType::Float) {
      if (v->type == VType::Int) nf += (double)v->integer;
      else if (v->type == VType::Float) nf += v->fpoint;
      else throwCannotAdd(showType(*v), "a float", ppos);
    } else {
      const StringContext *pc = nullptr;
      composite::Chars w = coerceToWindow(*v, context, false, firstType == VType::String, ppos, "while evaluating a path segment", scratch, !first, &pc);
      own.add(pc, context);
      if (w.size() && w.data() == scratch.data()) { w = composite::chars(copyString(scratch), w.size()); } // text made here lives in the arena
      views[nv++] = w;
      total += w.size();
    }
    first = false;
  }
  PosPtr pos = node->pos();
  if (firstType == VType::Int) return mkInt(out, n);
  if (firstType == VType::Float) return mkFloat(out, nf);
  if (firstType == VType::Path) {
    if (own.any(context))
      throw EvalError("a string that refers to a store path cannot be appended to a path", pos);
    std::string str;
    str.reserve(total);
    for (size_t k = 0; k < nv; k++) str += composite::view(views[k]);
    return mkPath(out, nixfe::canonPath(str));
  }
  mkStringOf(out, llvm::ArrayRef<composite::Chars>(views, nv), own.result(*this, context));
}

Symbol EvalState::pathSymbol(const nixfe::Name &comp, Node *const *dyn, unsigned &nextDyn, Frame *env,
                             PosPtr pos) {
  if (!comp.isNull()) return symbolOf(comp);
  return symbolOfString(forceStringNoCtx(*lookup(env, dyn[nextDyn++]), pos, "while evaluating an attribute name"));
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
  auto &e = evalsByKind[op->getName().getAsOpaquePointer()]; e.first = op->getName().getStringRef(); ++e.second;
  if (env) {
    ++env->info->nEvals;
    if (!epochEvals.empty()) ++epochEvals.back();
    auto it = env->info->opIdx.find(op);
    if (it != env->info->opIdx.end()) { env->info->everRan[it->second >> 6] |= 1ull << (it->second & 63); ++env->info->opEvals[it->second]; }
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
      Value *baseV = cur;
      cur = first ? st.selectField(*cur, sym, pos, n->rowGuess) : st.selectField(*cur, sym, pos);
      first = false;
      if (st.statsEnabled) st.statSelect(n->def, baseV->attrs, sym, dynamic);
      continue;
    }
    st.forceValue(*cur, pos);
    if (cur->type != VType::Attrs) return copyFrom(st, st.lookupImpl(env, def, true), out, pos);
    if (st.statsEnabled) st.statSelect(n->def, cur->attrs, sym, dynamic);
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
  st.mkList(out, l->items() + r->items());
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
  for (unsigned i = 0; i < n->nOperands; i++) args[i] = st.lookup(env, n->operands[i]);
  st.callPrimOp(*n->prim, args, out, n->pos());
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

std::optional<std::string> EvalState::tryAttrsToString(Value &v, NixStringContext &ctx, bool coerceMore,
                                                       bool copyToStore) {
  const Attr *f = v.attrs->get(s.toString);
  if (!f) return std::nullopt;
  Value *r = allocValue();
  callFunction(*f->value, v, *r, nullptr);
  return coerceToString(*r, ctx, coerceMore, copyToStore, nullptr,
                        "while evaluating the result of the `__toString` attribute");
}

composite::Chars EvalState::coerceToWindow(Value &v, NixStringContext &ctx, bool coerceMore, bool copyToStore,
                                                 PosPtr pos, std::string_view errorCtx, std::string &scratch,
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

std::string EvalState::coerceToString(Value &v, NixStringContext &ctx, bool coerceMore, bool copyToStore,
                                      PosPtr pos, std::string_view errorCtx, bool canonicalizePath) {
  forceValue(v, pos);
  switch (v.type) {
  case VType::String:
    copyContext(v, ctx);
    return std::string(v.sv());
  case VType::Path: {
    std::string p(v.pathView());
    if (copyToStore) return copyPathToStore(ctx, p);
    return p;
  }
  case VType::Attrs: {
    if (auto s2 = tryAttrsToString(v, ctx, coerceMore, copyToStore)) return *s2;
    const Attr *o = v.attrs->get(s.outPath);
    if (!o) {
      TypeError e(std::string("cannot coerce ") + showType(v) + " to a string: " + printValueForTrace(v), pos);
      if (!errorCtx.empty()) e.addTrace(pos, std::string(errorCtx));
      throw e;
    }
    return coerceToString(*o->value, ctx, coerceMore, copyToStore, pos,
                          "while evaluating the `outPath` attribute", canonicalizePath);
  }
  default:
    break;
  }
  if (coerceMore) {
    if (v.type == VType::Bool) return v.boolean ? "1" : "";
    if (v.type == VType::Int) return std::to_string(v.integer);
    if (v.type == VType::Float) return std::to_string(v.fpoint);
    if (v.type == VType::Null) return "";
    if (v.type == VType::List) {
      std::string result;
      for (size_t n = 0; n < v.listSize(); n++) {
        Value *e = v.list.elems[n];
        try {
          result += coerceToString(*e, ctx, coerceMore, copyToStore, pos, errorCtx);
        } catch (EvalError &err) {
          err.addTrace(pos, "while evaluating one element of the list");
          throw;
        }
        if (n < v.listSize() - 1 && (e->type != VType::List || e->listSize() != 0)) result += " ";
      }
      return result;
    }
  }
  TypeError e(std::string("cannot coerce ") + showType(v) + " to a string: " + printValueForTrace(v), pos);
  if (!errorCtx.empty()) e.addTrace(pos, std::string(errorCtx));
  throw e;
}

std::string EvalState::copyPathToStore(NixStringContext &ctx, const std::string &path) {
  std::string base = nixstore::baseNameOf(path);
  if (base.size() >= 4 && base.substr(base.size() - 4) == ".drv")
    throw EvalError("file names are not allowed to end in '.drv'");
  auto it = srcToStore.find(path);
  std::string dst;
  if (it != srcToStore.end()) {
    dst = it->second;
  } else {
    std::string real = path;
    if (nixstore::isInStore(store->storeDir(), path)) real = store->toReal(path);
    if (!nixstore::pathExists(real)) throw EvalError("path '" + path + "' does not exist");
    try {
      dst = store->addToStore(base, real);
    } catch (nixstore::Error &e) {
      throw EvalError(e.what());
    }
    srcToStore[path] = dst;
  }
  ctx.insert(dst);
  return dst;
}

std::string EvalState::coerceToPath(Value &v, NixStringContext &ctx, PosPtr pos, std::string_view errorCtx) {
  forceValue(v, pos);
  if (v.type == VType::Path) return std::string(v.pathView());
  std::string p = coerceToString(v, ctx, false, false, pos, errorCtx);
  if (p.empty() || p[0] != '/') {
    EvalError e("string '" + p + "' doesn't represent an absolute path", pos);
    if (!errorCtx.empty()) e.addTrace(pos, std::string(errorCtx));
    throw e;
  }
  return p;
}

std::string EvalState::coerceToStorePath(Value &v, NixStringContext &ctx, PosPtr pos, std::string_view errorCtx) {
  std::string p = coerceToString(v, ctx, false, false, pos, errorCtx);
  if (nixstore::isInStore(store->storeDir(), p)) return nixstore::toStorePath(store->storeDir(), p);
  EvalError e("path '" + p + "' is not in the Nix store", pos);
  if (!errorCtx.empty()) e.addTrace(pos, std::string(errorCtx));
  throw e;
}

//===----------------------------------------------------------------------===//
// Comparison
//===----------------------------------------------------------------------===//

bool EvalState::eqValues(Value &v1, Value &v2, PosPtr pos) {
  forceValue(v1, pos);
  forceValue(v2, pos);
  if (v1.type == VType::Int && v2.type == VType::Float) return (double)v1.integer == v2.fpoint;
  if (v1.type == VType::Float && v2.type == VType::Int) return v1.fpoint == (double)v2.integer;
  auto norm = [](VType t) { return t == VType::PrimOp || t == VType::PrimOpApp ? VType::Lambda : t; };
  if (norm(v1.type) != norm(v2.type)) return false;
  switch (v1.type) {
  case VType::Int: return v1.integer == v2.integer;
  case VType::Float: return v1.fpoint == v2.fpoint;
  case VType::Bool: return v1.boolean == v2.boolean;
  case VType::Null: return true;
  case VType::String: return v1.sv() == v2.sv();
  case VType::Path: return v1.pathView() == v2.pathView();
  case VType::List:
    if (v1.listSize() != v2.listSize()) return false;
    for (auto [a, b] : cp::joins(v1.items(), v2.items()))
      if (a != b && !eqValues(*a, *b, pos)) return false; // a == b: one value, equal without a look
    return true;
  case VType::Attrs: {
    if (v1.attrs == v2.attrs) return true;
    if (isDerivation(v1) && isDerivation(v2)) {
      const Attr *i = v1.attrs->get(s.outPath), *j = v2.attrs->get(s.outPath);
      if (i && j) {
        if (i->value == j->value) return true;
        return eqValues(*i->value, *j->value, pos);
      }
    }
    if (v1.attrs->size() != v2.attrs->size()) return false;
    auto ra = v1.attrs->rows(), rb = v2.attrs->rows(); // the rows as Series: a layer reads through its selection
    for (size_t k = 0; k < v1.attrs->size(); k++) {
      const Attr &a = ra[uint32_t(k)], &b = rb[uint32_t(k)];
      if (a.name != b.name) return false;
      if (a.value == b.value) continue;
      if (!eqValues(*a.value, *b.value, pos)) return false;
    }
    return true;
  }
  case VType::Lambda: case VType::PrimOp: case VType::PrimOpApp:
    return false;
  default:
    throw EvalError(std::string("cannot compare ") + showType(v1) + " with " + showType(v2), pos);
  }
}

bool EvalState::lessThan(Value &v1, Value &v2, PosPtr pos) {
  forceValue(v1, pos);
  forceValue(v2, pos);
  if (v1.type == VType::Float && v2.type == VType::Int) return v1.fpoint < (double)v2.integer;
  if (v1.type == VType::Int && v2.type == VType::Float) return (double)v1.integer < v2.fpoint;
  if (v1.type != v2.type)
    throw EvalError(std::string("cannot compare ") + showType(v1) + " with " + showType(v2), pos);
  switch (v1.type) {
  case VType::Int: return v1.integer < v2.integer;
  case VType::Float: return v1.fpoint < v2.fpoint;
  case VType::String: return v1.sv() < v2.sv();
  case VType::Path: return v1.pathView() < v2.pathView();
  case VType::List:
    for (size_t i = 0;; i++) {
      if (i == v2.listSize()) return false;
      if (i == v1.listSize()) return true;
      if (!eqValues(*v1.list.elems[i], *v2.list.elems[i], pos))
        return lessThan(*v1.list.elems[i], *v2.list.elems[i], pos);
    }
  default:
    throw EvalError(std::string("cannot compare ") + showType(v1) + " with " + showType(v2) +
                        "; values of that type are incomparable",
                    pos);
  }
}

//===----------------------------------------------------------------------===//
// Printing
//===----------------------------------------------------------------------===//

static std::string fmtFloat(double d) {
  std::ostringstream os;
  os << d;
  return os.str();
}

void EvalState::printValue(std::ostream &str, Value &v, std::set<const void *> *seen, size_t depth) {
  if (depth > settings.maxCallDepth) throw StackOverflowError("stack overflow");
  switch (v.type) {
  case VType::Int: str << v.integer; break;
  case VType::Bool: str << (v.boolean ? "true" : "false"); break;
  case VType::String: nixfe::printLiteralString(str, v.sv()); break;
  case VType::Path: str << v.pathView(); break;
  case VType::Null: str << "null"; break;
  case VType::Attrs:
    if (seen && !v.attrs->empty() && !seen->insert(v.attrs).second) str << "«repeated»";
    else {
      str << "{ ";
      for (auto *a : v.attrs->lexicographicOrder(symbols)) {
        nixfe::printIdentifier(str, symbols[a->name]);
        str << " = ";
        printValue(str, *a->value, seen, depth + 1);
        str << "; ";
      }
      str << "}";
    }
    break;
  case VType::List:
    if (seen && v.listSize() && !seen->insert(&v).second) str << "«repeated»";
    else {
      str << "[ ";
      for (size_t i = 0; i < v.listSize(); i++) {
        printValue(str, *v.list.elems[i], seen, depth + 1);
        str << " ";
      }
      str << "]";
    }
    break;
  case VType::Thunk: case VType::App: case VType::Failed: str << "<CODE>"; break;
  case VType::Blackhole: str << "«potential infinite recursion»"; break;
  case VType::Lambda: str << "<LAMBDA>"; break;
  case VType::PrimOp: str << "<PRIMOP>"; break;
  case VType::PrimOpApp: str << "<PRIMOP-APP>"; break;
  case VType::Float: str << fmtFloat(v.fpoint); break;
  }
}

namespace {
struct TracePrinter {
  EvalState &st;
  std::ostream &out;
  bool force;
  size_t maxDepth = 10, maxAttrs = 10, maxList = 10, maxStr = 1024;
  size_t attrsPrinted = 0, listPrinted = 0;
  std::set<const void *> seen;

  void elided(size_t n, const char *one, const char *many) {
    out << "«" << n << " " << (n == 1 ? one : many) << " elided»";
  }
  void print(Value &v, size_t depth) {
    if (force) {
      try {
        st.forceValue(v);
      } catch (EvalError &e) {
        out << "«error: " << e.msg << "»";
        return;
      }
    }
    switch (v.type) {
    case VType::Int: out << v.integer; break;
    case VType::Float: out << fmtFloat(v.fpoint); break;
    case VType::Bool: out << (v.boolean ? "true" : "false"); break;
    case VType::Null: out << "null"; break;
    case VType::Path: out << v.pathView(); break;
    case VType::String: {
      auto s = v.sv();
      if (s.size() > maxStr) {
        nixfe::printLiteralString(out, s.substr(0, maxStr));
        out << " ";
        elided(s.size() - maxStr, "byte", "bytes");
      } else {
        nixfe::printLiteralString(out, s);
      }
      break;
    }
    case VType::Attrs: {
      if (!seen.insert(v.attrs).second) { out << "«repeated»"; break; }
      if (force && st.isDerivation(v)) {
        out << "«derivation";
        if (const Attr *d = v.attrs->get(st.s.drvPath)) {
          try {
            st.forceValue(*d->value);
            if (d->value->type == VType::String) out << " " << d->value->sv();
          } catch (EvalError &) {
          }
        }
        out << "»";
        break;
      }
      if (depth >= maxDepth) { out << "{ ... }"; break; }
      out << "{";
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
        out << " ";
        if (attrsPrinted >= maxAttrs) {
          elided(sorted.size() - cur, "attribute", "attributes");
          break;
        }
        auto n = st.symbols[a->name];
        if (nixfe::isValidIdentifier(n)) out << n.str();
        else nixfe::printLiteralString(out, n);
        out << " = ";
        print(*a->value, depth + 1);
        out << ";";
        attrsPrinted++;
        cur++;
      }
      out << " }";
      break;
    }
    case VType::List: {
      if (v.listSize() && !seen.insert(&v).second) { out << "«repeated»"; break; }
      if (depth >= maxDepth) { out << "[ ... ]"; break; }
      out << "[";
      size_t cur = 0;
      for (size_t i = 0; i < v.listSize(); i++) {
        out << " ";
        if (listPrinted >= maxList) {
          elided(v.listSize() - cur, "item", "items");
          break;
        }
        print(*v.list.elems[i], depth + 1);
        listPrinted++;
        cur++;
      }
      out << " ]";
      break;
    }
    case VType::Lambda: {
      auto lam = cast<nd::LambdaOp>(v.thunk.node->def);
      out << "«lambda";
      if (auto n = lam.getName()) out << " " << n->str();
      out << " @ " << st.showPos(nd::posOfOp(lam)) << "»";
      break;
    }
    case VType::PrimOp: out << "«primop " << v.primOp->name << "»"; break;
    case VType::PrimOpApp: {
      Value *p = &v;
      while (p->type == VType::PrimOpApp) p = p->app.left;
      out << "«partially applied primop " << (p->type == VType::PrimOp ? p->primOp->name : "?") << "»";
      break;
    }
    case VType::Thunk: case VType::App: case VType::Failed: out << "«thunk»"; break;
    case VType::Blackhole: out << "«potential infinite recursion»"; break;
    }
  }
};
} // namespace

std::string EvalState::printValueForTrace(Value &v) {
  std::ostringstream os;
  TracePrinter p{*this, os, false};
  p.print(v, 0);
  return os.str();
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
  po.onWarning = [](const nixfe::ParseError &e) { std::cerr << formatParseError(e, "warning") << std::endl; };
  return po;
}

/// The optimization pipeline is data: MLIR pass-pipeline text (EvalSettings::pipeline,
/// overridden by MLNIX_PIPELINE), so any registered pass can be composed by name.
static std::unique_ptr<mlir::PassManager> makeOptimizer(mlir::MLIRContext &ctx, const EvalSettings &settings) {
  static std::once_flag once;
  std::call_once(once, [] {
    mlir::registerTransformsPasses();
    nd::registerNixPasses();
  });
  std::string text = pipelineText(settings);
  auto pm = std::make_unique<mlir::PassManager>(&ctx); // anchored on any op
  pm->enableVerifier(false);
  std::string err;
  llvm::raw_string_ostream os(err);
  if (mlir::failed(mlir::parsePassPipeline(text, *pm, os)))
    throw EvalError("invalid pass pipeline '" + text + "': " + err);
  return pm;
}

nd::ExprOp EvalState::lowerToMLIR(std::shared_ptr<nixfe::Origin> origin, const composite::MutableSeries<std::string> *scopeNames) {
  nixfe::ParseOptions po = parseOptions();
  nixfe::GenOptions go;
  go.isBaseName = [this](llvm::StringRef n) { return isBaseName(n); };
  if (settings.deferBodies) {
    // A lambda body is not IsolatedFromAbove, so no PassManager can run on it when it is minted: the
    // demand schedule devirtualizes it directly, which is the whole default pipeline.  Any other
    // pipeline would be skipped silently on every minted body, so refuse it.
    if (settings.optimize && pipelineText(settings) != "nix-prims")
      throw EvalError("MLNIX_DEFER runs only the default pipeline 'nix-prims', not '" + pipelineText(settings) + "'");
    auto pool = std::make_unique<nixfe::FilePool>(nextPoolId.fetch_add(1), origin, po);
    go.deferBodies = true;
    go.pool = pool.get();
    installPool(std::move(pool));
  }
  if (scopeNames) {
    go.scoped = true;
    for (const std::string &nm : *scopeNames) go.scopeNames.append(nm);
  }
  std::string sym = "expr" + std::to_string(exprCounter++);
  auto t0 = std::chrono::steady_clock::now();
  nd::ExprOp op = nixfe::genExpr(*module, std::move(origin), po, sym, go);
  // The expression is IsolatedFromAbove and not yet referenced by any frame,
  // so it can be rewritten freely before evaluation starts.
  if (settings.optimize) {
    if (!optimizer) optimizer = makeOptimizer(ctx, settings);
    if (mlir::failed(optimizer->run(op))) throw EvalError("the optimization pipeline failed");
  }
  if (statsEnabled) {
    op->walk([&](mlir::Operation *o) { ++opStats[o->getName().getStringRef()]; });
    nsLower += std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now() - t0).count();
  }
  return op;
}

void EvalState::installPool(std::unique_ptr<nixfe::FilePool> p) {
  uint32_t id = p->file;
  if (pools.size() <= id) pools.resize(id + 1);
  pools[id] = std::move(p);
}

void EvalState::startPrelower() {
  const char *list = getenv("MLNIX_PRELOWER_LIST");
  bool replayed = getenv("MLNIX_PRELOWER") && !nixprefetch::replayFiles.empty(); // MLNIX_PREFETCH=auto|replay:FILE supplies the list
  if (pre || !settings.deferBodies || (!list && !replayed)) return;
  pre = std::make_unique<PrelowerState>();
  for (auto &e : baseEnv) pre->baseNames.insert(e.getKey().str());
  pre->po = parseOptions();
  pre->po.lintAbsolutePaths = pre->po.lintShortPaths = pre->po.lintUrls = nixfe::Lint::Ignore;
  pre->po.onWarning = nullptr;
  if (list) {
    std::ifstream in(list); // one path a line, or a prefetch list (`F path`)
    for (std::string line; std::getline(in, line);) {
      if (line.size() > 2 && line[1] == ' ') {
        if (line[0] == 'F' && line.compare(line.size() - 4, 4, ".nix") == 0) pre->queue.append(line.substr(2));
      } else if (!line.empty()) {
        pre->queue.append(line);
      }
    }
  } else {
    for (const std::string &f : nixprefetch::replayFiles) pre->queue.append(f);
  }
  unsigned n = 1;
  if (const char *t = getenv("MLNIX_PRELOWER_THREADS")) n = std::max(1ul, std::min(8ul, strtoul(t, nullptr, 10)));
  for (unsigned i = 0; i < n; i++) pre->workers.emplace([this] { prelowerLoop(); });
}

void EvalState::prelowerLoop() {
  for (;;) {
    std::string path;
    std::shared_ptr<Prelowered> pl;
    {
      std::unique_lock<std::mutex> lk(pre->m);
      pre->cv.wait(lk, [&] { return pre->stop || pre->head < pre->queue.size(); });
      if (pre->stop) return;
      path = pre->queue.drain(pre->head++);
      if (pre->byPath.count(path)) continue; // the evaluator took it first, or a duplicate
      pl = pre->byPath[path] = std::make_shared<Prelowered>();
    }
    try {
      auto origin = std::make_shared<nixfe::Origin>();
      origin->name = path;
      origin->path = path;
      origin->baseDir = nixstore::dirOf(path);
      origin->text = nixfe::Source::mapFile(path);
      if (origin->text) {
        nixfe::GenOptions go;
        go.isBaseName = [this](llvm::StringRef n) { return pre->baseNames.count(n.str()) != 0; };
        go.deferBodies = true;
        pl->pool = std::make_unique<nixfe::FilePool>(nextPoolId.fetch_add(1), origin, pre->po);
        go.pool = pl->pool.get();
        pl->mod = ModuleOp::create(UnknownLoc::get(&ctx));
        pl->op = nixfe::genExpr(*pl->mod, origin, pre->po, "expr", go);
        // The bodies the recorded run minted in this file, minted here in its order (the rows of nested lambdas follow from it): the
        // evaluator only indexes them at their first call.  If one fails (the file changed since), the whole file is left to the evaluator.
        if (auto mints = nixprefetch::replayMints.find(path); mints != nixprefetch::replayMints.end())
          for (uint32_t row : mints->second) {
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
          // census counts indexing or a JIT reads every value by its address: the evaluator indexes then.
          if (!statsEnabled && !scalarJIT) {
            pl->index = std::make_unique<Indexer>(*this, true);
            pl->index->index(pl->op.getBody());
          }
        }
        pl->origin = origin;
        pl->ok = true;
      }
    } catch (...) {
      pl->ok = false;
    }
    { std::lock_guard<std::mutex> g(pre->m); pl->done = true; }
    pre->cv.notify_all();
  }
}

/// The finished lowering of `resolved`, adopted into the evaluator's module (and optimized there: the prim folder is the evaluator's), or a null op.
nd::ExprOp EvalState::takePrelowered(const std::string &resolved) {
  if (!pre) return {};
  std::shared_ptr<Prelowered> pl;
  {
    std::unique_lock<std::mutex> lk(pre->m);
    auto it = pre->byPath.find(resolved);
    if (it == pre->byPath.end()) {
      // not started: take it off the queue so the helper does not lower it again, and lower it here
      pre->byPath[resolved] = std::make_shared<Prelowered>();
      ++pre->missed;
      return {};
    }
    pl = it->second;
    if (!pl->done) { ++pre->waited; pre->cv.wait(lk, [&] { return pl->done; }); }
  }
  if (!pl->ok) return {};
  ++pre->adopted;
  installPool(std::move(pl->pool));
  origins.append(pl->origin);
  nd::ExprOp op = pl->op;
  op->remove();
  op.setSymName("expr" + std::to_string(exprCounter++));
  module->push_back(op);
  pl->mod = nullptr;
  if (settings.optimize && !pl->optimized) {
    if (!optimizer) optimizer = makeOptimizer(ctx, settings);
    if (mlir::failed(optimizer->run(op))) throw EvalError("the optimization pipeline failed");
  }
  if (pl->index) { // indexed by the helper: its regions and the captures of the bodies minted later become the evaluator's
    for (auto &[r, ri] : pl->index->regions) regionInfos[r] = ri;
    for (auto &[key, n] : pl->index->captures) setNode(key, n);
    helperIndexers.append(std::move(pl->index));
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

static std::string readSource(const std::string &path) {
  if (path == "/__corepkgs__/fetchurl.nix") return corepkgsFetchurl;
  try {
    return nixstore::readFile(path);
  } catch (nixstore::Error &e) {
    throw EvalError(e.what());
  }
}

std::string EvalState::resolveExprPath(std::string path) {
  if (path.rfind("/__corepkgs__/", 0) == 0) return path;
  // Follow symlinks (to the final target), then use default.nix for dirs.
  for (int i = 0; i < 1024; i++) {
    struct stat st;
    nixprefetch::note('L', path.c_str());
    if (lstat(path.c_str(), &st) != 0) throw EvalError("path '" + path + "' does not exist");
    if (!S_ISLNK(st.st_mode)) break;
    char buf[PATH_MAX + 1];
    ssize_t n = readlink(path.c_str(), buf, PATH_MAX);
    if (n < 0) break;
    std::string tgt(buf, n);
    if (tgt[0] != '/') tgt = nixstore::dirOf(path) + "/" + tgt;
    path = nixfe::canonPath(tgt);
  }
  struct stat st;
  nixprefetch::note('S', path.c_str());
  if (stat(path.c_str(), &st) == 0 && S_ISDIR(st.st_mode)) path += "/default.nix";
  return path;
}

Value *EvalState::evalFile(const std::string &pathIn) {
  std::string path = pathIn;
  auto it = fileEvalCache.find(path);
  if (it != fileEvalCache.end()) return it->second;
  std::string real = realisePath(path, nullptr);
  std::string resolved = resolveExprPath(real);
  // Map back from the physical location when using a chroot store.
  std::string logical = resolved;
  if (!store->config().realRoot.empty() && resolved.rfind(store->config().realRoot, 0) == 0)
    logical = resolved.substr(store->config().realRoot.size());
  auto it2 = fileEvalCache.find(logical);
  if (it2 != fileEvalCache.end()) return fileEvalCache[path] = it2->second;

  Value *result;
  if (resolved.size() > 5 && resolved.substr(resolved.size() - 5) == ".mlir") {
    result = evalMLIRFile(resolved, "");
  } else {
    auto origin = std::make_shared<nixfe::Origin>();
    origin->name = logical;
    origin->path = logical;
    origin->baseDir = nixstore::dirOf(logical);
    nixprefetch::note('F', resolved.c_str());
    if (nixfe::pathLiterals) evaluatedFiles.append({logical, nixfe::pathLiterals->size()});
    origin->text = settings.mapSources ? nixfe::Source::mapFile(resolved) : nullptr;
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
  fileEvalCache[path] = result;
  fileEvalCache[logical] = result;
  return result;
}

Value *EvalState::evalString(const std::string &text, const std::string &baseDir, const std::string &originName) {
  auto origin = std::make_shared<nixfe::Origin>();
  origin->name = originName;
  origin->baseDir = baseDir;
  origin->text = nixfe::Source::fromString(text);
  origins.append(origin);
  return evalExprOp(lowerToMLIR(origin));
}

Value *EvalState::evalMLIRFile(const std::string &path, const std::string &sym) {
  llvm::SourceMgr sm;
  OwningOpRef<ModuleOp> m = parseSourceFile<ModuleOp>(path, sm, ParserConfig(&ctx));
  if (!m) throw EvalError("failed to parse MLIR file '" + path + "'");
  nd::ExprOp found;
  // Move all ops into our module (renaming symbols to avoid clashes).
  auto exprs = llvm::to_vector(m->getOps<nd::ExprOp>());
  for (auto e : exprs) {
    bool match = sym.empty() ? !found : e.getSymName() == sym;
    e->remove();
    e.setSymName("mlir" + std::to_string(exprCounter++));
    module->getBody()->push_back(e);
    if (match && !found) found = e;
  }
  if (!found) throw EvalError("no nix.expr found in '" + path + "'");
  return evalExprOp(found);
}

std::string EvalState::realisePath(const std::string &path, PosPtr pos) {
  // Store paths are realised through string context (realiseContext); here we
  // only map logical store paths to their physical location.
  const std::string &sd = store->storeDir();
  if (path == sd || path == sd + "/" || nixstore::isInStore(sd, path)) return store->toReal(path);
  return path;
}

void EvalState::realiseContext(const NixStringContext &ctx, PosPtr pos) {
  for (auto &c : ctx) {
    try {
      if (c[0] == '!') {
        auto p = c.find('!', 1);
        std::string drv = c.substr(p + 1);
        store->buildDerivation(drv);
      } else if (c[0] == '=') {
        store->buildDerivation(c.substr(1));
      } else if (!store->isValidPath(c)) {
        throw EvalError("path '" + c + "' is not valid", pos);
      }
    } catch (nixstore::Error &e) {
      throw EvalError(e.what(), pos);
    }
  }
}

std::string EvalState::findFile(Value &searchPath, std::string_view name, PosPtr pos) {
  forceList(searchPath, pos);
  for (Value &e : searchPath.values()) {
    forceAttrs(e, pos);
    std::string prefix;
    if (const Attr *a = e.attrs->get(s.prefix)) prefix = std::string(forceStringNoCtx(*a->value, pos));
    const Attr *pa = e.attrs->get(s.path);
    if (!pa) throw EvalError("attribute 'path' missing", pos);
    NixStringContext ctx;
    std::string p = coerceToString(*pa->value, ctx, false, false, pos);
    realiseContext(ctx, pos);
    std::string rest;
    if (!prefix.empty()) {
      if (name.substr(0, prefix.size()) != prefix) continue;
      if (name.size() > prefix.size() && name[prefix.size()] != '/') continue;
      rest = std::string(name.substr(prefix.size()));
    } else {
      rest = "/" + std::string(name);
    }
    if (p.find("://") != std::string::npos) continue; // URL entries are not fetched implicitly
    std::string full = nixfe::canonPath(p + rest);
    if (nixstore::pathExists(realisePath(full, pos))) return full;
  }
  if (name.substr(0, 4) == "nix/") return "/__corepkgs__" + std::string(name.substr(3));
  if (settings.pureEval)
    throw ThrownError("cannot look up '<" + std::string(name) + ">' in pure evaluation mode (use '--impure' to override)", pos);
  throw ThrownError("file '" + std::string(name) +
                        "' was not found in the Nix search path (add it using $NIX_PATH or -I)",
                    pos);
}

//===----------------------------------------------------------------------===//
// Error formatting
//===----------------------------------------------------------------------===//

static std::string chomp(std::string s) {
  while (!s.empty() && (s.back() == ' ' || s.back() == '\t' || s.back() == '\n' || s.back() == '\r')) s.pop_back();
  return s;
}

static void appendCodeLines(std::string &out, std::string_view text, unsigned line, unsigned col,
                            unsigned indent = 7) {
  composite::MutableSeries<std::string> lines;
  size_t start = 0;
  while (true) {
    size_t nl = text.find('\n', start);
    if (nl == std::string_view::npos) {
      lines.append(std::string(text.substr(start)));
      break;
    }
    lines.append(std::string(text.substr(start, nl - start)));
    start = nl + 1;
  }
  auto fmtLine = [&](unsigned n) {
    char buf[16];
    snprintf(buf, sizeof buf, "%5u", n);
    return chomp(std::string(indent + 1, ' ') + buf + "| " + lines[n - 1]);
  };
  if (line >= 2 && line - 1 <= lines.size()) out += "\n" + fmtLine(line - 1);
  if (line >= 1 && line <= lines.size()) {
    out += "\n" + fmtLine(line);
    if (col > 0) out += "\n" + std::string(indent, ' ') + "      |" + std::string(col, ' ') + "^";
  }
  if (line + 1 <= lines.size()) out += "\n" + fmtLine(line + 1);
}

static std::string sourceFor(EvalState *state, const std::string &file) {
  if (state)
    for (auto &o : state->origins)
      if (o->name == file && o->text) return std::string(o->text->view());
  if (!file.empty() && file[0] == '/' && nixstore::pathExists(file)) {
    try {
      return nixstore::readFile(file);
    } catch (...) {
    }
  }
  return "";
}

static void appendPos(std::string &out, EvalState *state, const std::string &file, unsigned line, unsigned col) {
  out += "\n       at " + file + ":" + std::to_string(line) + ":" + std::to_string(col) + ":";
  std::string text = sourceFor(state, file);
  if (!text.empty()) appendCodeLines(out, text, line, col);
}

std::string formatError(EvalState *state, const EvalError &e) {
  std::string out;
  // Traces are printed outermost first.
  if (state && state->settings.showTrace) {
    for (auto *it = e.traces.end(); it != e.traces.begin();) {
      --it;
      out += "\n       … " + it->msg;
      if (auto f = nd::decodePos(it->pos)) {
        appendPos(out, state, f->file, f->line, f->col);
        out += "\n";
      } else {
        out += "\n";
      }
    }
  }
  std::string msg = e.msg;
  // Indent continuation lines of the message.
  std::string ind;
  for (size_t i = 0; i < msg.size(); i++) {
    ind += msg[i];
    if (msg[i] == '\n') ind += "       ";
  }
  std::string res = out.empty() ? "error: " + ind : "error:" + out + "\n       error: " + ind;
  if (auto f = nd::decodePos(e.pos)) appendPos(res, state, f->file, f->line, f->col);
  return res;
}

std::string formatParseError(const nixfe::ParseError &e, const char *kind) {
  unsigned indent = strlen(kind) + 2;
  std::string res = std::string(kind) + ": " + std::string(e.what());
  if (e.pos.valid() && e.origin) {
    res += "\n" + std::string(indent, ' ') + "at " + e.origin->name + ":" + std::to_string(e.pos.line) + ":" +
           std::to_string(e.pos.col) + ":";
    if (e.origin->text) appendCodeLines(res, e.origin->text->view(), e.pos.line, e.pos.col, indent);
  }
  return res;
}

int runWithLargeStack(std::function<int()> fn) {
  struct Ctx {
    std::function<int()> fn;
    int rc = 0;
    std::exception_ptr ex;
  } c{std::move(fn)};
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
