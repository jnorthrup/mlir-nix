//===- Eval.h - Lazy evaluator over the nix dialect -----------*- C++ -*-===//
//
// Execution model
// ---------------
// A `Frame` is one activation of a graph region (a nix.expr body or a call of
// a nix.lambda).  Each SSA value of the region owns a slot in the frame; the
// slot is filled on first reference with a thunk (op, frame), so evaluation is
// call-by-need and recursive bindings (cyclic SSA) are just thunks that refer
// to each other's slots.  Forcing a thunk runs the op's semantics, which force
// operands only as needed.
//
//===----------------------------------------------------------------------===//
#ifndef NIX_EVAL_H
#define NIX_EVAL_H

#include "Composite/Pool.h"
#include "Composite/Rows.h"
#include "Composite/Views.h"
#include "Nix/MLIRGen.h"
#include "Nix/Store.h"
#include "NixDialect/NixDialect.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/OwningOpRef.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/StringMap.h"
#include "llvm/Support/Allocator.h"

namespace mlir { class PassManager; }

#include <atomic>
#include <condition_variable>
#include <deque>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <set>
#include <string>
#include <thread>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include "Nix/StdBind.h"
#include "Nix/Arena.h"

namespace nixev {
namespace cp = ::composite;

using Symbol = uint32_t;

struct SymbolTable {
  Symbol create(llvm::StringRef s) {
    ++creates; // (counted always: one add; MLNIX_STATS prints it)
    auto it = map.find(s);
    if (it != map.end()) return it->second;
    Symbol id = names.size();
    auto r = map.try_emplace(s, id);
    names.append(r.first->getKey());
    uint64_t p = 0; // the first eight bytes, big-endian, zero-padded: comparing two of these orders the names as their bytes do
    for (size_t i = 0; i < 8; i++) p = p << 8 | (i < s.size() ? uint8_t(s[i]) : 0);
    prefix.append(p);
    return id;
  }
  llvm::StringRef operator[](Symbol s) const { return names[s]; }
  /// The name's bytes as the hot Series<char>: what an ordering by name reads.
  auto chars(Symbol s) const { llvm::StringRef r = names[s]; return composite::series(r.data(), uint32_t(r.size())); }
  /// The order of two names as their bytes: one compare of the prefix words, the bytes only when the first eight agree.
  bool less(Symbol a, Symbol b) const {
    uint64_t pa = prefix[a], pb = prefix[b];
    return pa != pb ? pa < pb : composite::lessChars(chars(a), chars(b));
  }
  size_t size() const { return names.size(); }

  llvm::StringMap<Symbol> map;
  composite::MutableSeries<llvm::StringRef> names;
  composite::MutableSeries<uint64_t> prefix; // per symbol: its first eight bytes as one word (less)
  uint64_t creates = 0;
};

struct Value;
struct Frame;
struct RegionInfo;
struct Node;
struct EvalState;
class ScalarJIT;

/// Opaque position: a packed source word, an mlir::Location pointer, or null.
using PosPtr = const void *;
using PosIdx = uint32_t;

struct Attr {
  Symbol name;
  PosIdx pos; // index into the owning EvalState's cold position series; zero means absent
  Value *value;
};
static_assert(sizeof(Attr) == 16, "four attribute cells per 64-byte cache line");

struct Bindings {
  /// `size_` of a layered set (below).
  static constexpr uint32_t kLayered = 0xFFFFFFFFu;
  uint32_t size_ = 0;
  PosPtr pos = nullptr;
  Attr attrs[0];

  /// `base // top`: the rows of both in name order, `top` shadowing `base`.  A Series, not a copy: `sel` holds one word a
  /// row — `(row << 1) | side`, side 1 for `top` — and a row is read where it lies (4 bytes a row of selection, against a
  /// row apiece for a copy).  `base` may itself be a layer: a `//` of a `//` DEPENDS on the layer before it instead of
  /// merging into its top, so a chain of layers stays a chain and nothing is copied (`depth` bounds the walk; past it the
  /// chain is materialised by flat()).
  struct Layer {
    Bindings *top, *base, *flat;
    Arena *alloc; // where flat() allocates
    cp::Sel sel;                        // `row j side` packed in 32 bits: 4 bytes a row, one load to read
    uint32_t depth = 1;                 // how many layers the walk from here can pass through
  };
  static inline uint64_t flattened = 0; // MLNIX_STATS
  static inline bool countGets = false; // MLNIX_STATS: get() calls and binary-search steps by set size (1, 2-3, 4-7, ... 2^k)
  static inline uint64_t getCalls[16] = {}, getSteps[16] = {}, getMiss[16] = {}, getLayered = 0;
  static inline uint64_t merged = 0, mergedCells = 0; // MLNIX_STATS: flat sets made by mergeBindings, and their cells
  bool layered() const { return size_ == kLayered; }
  Layer &layer() const { return *reinterpret_cast<Layer *>(const_cast<Attr *>(attrs)); }
  /// The set as one sorted array: itself, or the union of its layers, built once.
  Bindings *flat() const;

  /// The rows of the set, flat or layered, as a Series: size j index.  A layered set indexes through its selection and
  /// copies nothing; a side that is itself layered is read the same way, so a layer of a layer is still a view.
  struct Rows {
    const Bindings *b;
    const Attr &operator()(uint32_t i) const {
      const Bindings *s = b;
      if (s->layered()) {
        const Layer &L = s->layer();
        join::TwInt w = L.sel.at(i); // `row j side` (Pack.h): the row, and which set it is read from
        s = w.second() ? L.top : L.base;
        i = w.first();
        if (s->layered()) return (*s).rows()[i];
      }
      return s->attrs[i];
    }
  };
  cp::Series<Rows> rows() const { return {uint32_t(size()), Rows{this}}; }

  /// A walk over the rows.  The iterator carries the index function itself (eight bytes: the set), not a pointer to a
  /// Series that a caller made on the way in — a range-for over a set has no Series of its own to keep alive.
  struct iterator {
    Rows r;
    uint32_t i = 0;
    const Attr &operator*() const { return r(i); }
    iterator &operator++() {
      ++i;
      return *this;
    }
    bool operator==(const iterator &o) const { return i == o.i; }
  };

  size_t size() const { return layered() ? layer().sel.size() : size_; }
  bool empty() const { return !layered() && size_ == 0; }
  iterator begin() const { return {Rows{this}, 0}; }
  iterator end() const { return {Rows{this}, uint32_t(size())}; }
  const Attr *get(Symbol s) const;
  /// get(), with a guess of the row: the row the asker found the name at last time, in a set of the same layout (62% of the selects of
  /// a NixOS evaluation hit the layout their site saw last).  A right guess is one row read instead of a search; a wrong one costs a
  /// compare, and the search's answer becomes the next guess.
  const Attr *getGuess(Symbol s, uint32_t &guess) const {
    if (!layered() && guess < size_ && attrs[guess].name == s) return &attrs[guess];
    const Attr *r = get(s);
    if (r && !layered()) guess = uint32_t(r - attrs);
    return r;
  }
  /// Attributes sorted by name (string order).
  composite::Frozen<const Attr *> lexicographicOrder(const SymbolTable &st) const;
};

/// String context: sorted set of encoded elements
///   "/nix/store/..."          opaque path
///   "=/nix/store/x.drv"       derivation with all outputs (drvDeep)
///   "!out!/nix/store/x.drv"   built output
using NixStringContext = std::set<std::string>;
struct StringContext {
  size_t n;
  const char *elems[0];
};
struct EvalState;
/// The contexts of the pieces of a string being built.  A piece that is a string brings its own context, already made: each is kept once,
/// in an inline series, and the set is touched only to merge.  With at most one and nothing else added, that one is the result's context
/// as it stands: nothing is joined, so nothing is made.
struct PieceContexts {
  composite::MutableSeries<const StringContext *, composite::Inline<const StringContext *, 8>> own;
  /// Keep c once; past eight distinct ones its elements go to `spill`.
  void add(const StringContext *c, NixStringContext &spill);
  bool any(const NixStringContext &ctx) const { return !ctx.empty() || own.size(); }
  const StringContext *result(EvalState &st, NixStringContext &ctx);
};

struct PrimOp;

/// Failed: a thunk whose evaluation threw an evaluation error.  Forcing it again throws a fresh copy of that error as it stands then (the
/// first throw may still be gathering traces on its way out), not the evaluation again: Nix 2.34's memoised errors.  The tags up to
/// Blackhole are the cells that are not values yet (isThunk; the JITs test `tag <= Blackhole`).
enum class VType : uint8_t {
  Thunk, App, Failed, Blackhole, Int, Float, Bool, Null, String, Path, Attrs, List,
  Lambda, PrimOp, PrimOpApp
};

/// 24 bytes: a tag and a 32-bit count, then two words.  The count is the byte length of a string or path and the length of
/// a list (a string of 4 GiB or a list of 4 Gi cells does not fit in the memory of the machines this runs on; mkString and
/// mkPath refuse the first, and a list of that many cells would be 32 GB of pointers).
struct Value {
  VType type = VType::Null;
  uint32_t aux = 0; // length of a string or path, size of a list: see listSize(), sv(), pathView()
  union {
    int64_t integer;
    double fpoint;
    bool boolean;
    struct {
      const char *s;
      const StringContext *ctx;
    } str;
    struct {
      const char *s;
    } path;
    Bindings *attrs;
    struct {
      Value **elems;
    } list;
    struct {
      union {
        Node *node;          // Thunk: the record of the op it evaluates
        mlir::Operation *op; // Lambda: the lambda op
      };
      Frame *env;
    } thunk; // Thunk and Lambda
    struct {
      Value *left, *right;
    } app; // App thunk and PrimOpApp
    const PrimOp *primOp;
    const std::exception_ptr *failed; // Failed: the error its evaluation threw
  };

  Value() : integer(0) {}

  bool isThunk() const { return type <= VType::Blackhole; }
  bool isFunction() const { return type == VType::Lambda || type == VType::PrimOp || type == VType::PrimOpApp; }
  std::string_view sv() const { return {str.s, aux}; }
  /// The string's characters as a window over its arena bytes (Series<char>, no cursor), never a copy: the weight of a string_view.
  composite::Chars window() const { return composite::chars(str.s, aux); }
  std::string_view pathView() const { return {path.s, aux}; }
  size_t listSize() const { return aux; }
  auto items() const { return cp::series(list.elems, aux); }                               // the cells of a list, a Series
  auto values() const { return items() |cp::α| [](Value *p) -> Value & { return *p; }; } // and what they point at
};
static_assert(sizeof(Value) == 24, "a Value is a tag, a count and two words");


/// A primop is a function pointer: most are lambdas without captures, and a call through a std::function costs two indirect calls
/// (the line profile put 1.6% of a run on them).  The few made by a registering loop that captures (type predicates, arithmetic,
/// bit operations, rounding) keep a closure.
using PrimFn = void (*)(EvalState &, Value **args, Value &out, PosPtr pos);
struct PrimOp {
  std::string name;
  unsigned arity;
  PrimFn fn; // null for a closure
  std::function<void(EvalState &, Value **args, Value &out, PosPtr pos)> closure;
  void call(EvalState &st, Value **args, Value &out, PosPtr pos) const {
    if (fn) fn(st, args, out, pos);
    else closure(st, args, out, pos);
  }
};

struct RegionInfo {
  mlir::Region *region;
  unsigned numSlots;
  mlir::Value result;
  Node *resultNode = nullptr; // the record of `result`
  /// For a lambda body: the symbols of the lambda's formals (made at its first call, by EvalState::callLambda) and the op
  /// they were made from.
  const Symbol *formalSyms = nullptr;
  mlir::Operation *formalsOf = nullptr;
  /// The lambda's formals as its op states them, read once when the body is indexed (a call reads these, not the op's attributes): whether
  /// it has any, how many, which have defaults (the attribute's own uniqued storage), and whether `...` accepts the rest.
  uint8_t hasFormals = 0, ellipsis = 0;
  uint32_t nFormals = 0;
  const bool *formalDefaults = nullptr;
  /// Stable entry owned by this evaluator's optional JIT; closure values are resolved at each call.
  void *jitEntry = nullptr;
  /// Optional arity-indexed JIT cache, owned by ScalarJIT and never an environment.
  void *curriedEntry = nullptr;
  uint64_t calls = 0; // MLNIX_STATS: frames made for this region
  uint8_t stackable = 2; // MLNIX_STATS: 1 when no op of the body can make a thunk or closure over the frame, so it could live on the C++ stack; 2 unclassified
  std::string shape = {}; // MLNIX_STATS_SHAPES: the name-free canonical form of this lambda and the lambdas it returns (EvalState::shapeOf)
  PosPtr selPos = nullptr; // where the recognized selector's `if` is: the position a non-Boolean condition is reported at
  uint8_t selShape = 0; // 0 unclassified, 1 none, 2 `c: x: if c then [x] else []`, 3 `c: x: if c then x else {}` (EvalState::selectorShape)
  uint8_t chainOuter = 2; // MLNIX_STATS: 1 when the body's result is itself a lambda (a curried chain's outer half), 2 unclassified
  uint8_t srcClass = 0; // MLNIX_STATS: where the region's code is defined, once classified (EvalState::srcClassOf); 0 unclassified
  /// MLNIX_STATS: what this region's sea of nodes holds.  nOps its body's ops; nThunks its cells that start as
  /// thunks (finer-grain deferral would mint those, so they are its rows); nEvals its ops' evals (a region called
  /// N times counts N times); everRan the distinct ops that ran, one bit an op, opIdx the op -> bit.
  uint32_t nOps = 0, nThunks = 0;
  uint64_t nEvals = 0;
  llvm::DenseMap<mlir::Operation *, uint32_t> opIdx{};
  composite::MutableSeries<uint64_t> everRan{};
  composite::MutableSeries<uint32_t> opEvals{}; // MLNIX_STATS_USES: evalOp calls per op (indexed like everRan's bits)
};

struct Frame {
  /// The enclosing frame, with bit 0 set once a thunk or a closure has been made over this frame.  A frame that returns with the bit clear can
  /// never be reached again, and its storage is recycled (EvalState::newFrame / recycleFrame).
  uintptr_t upBits;
  RegionInfo *info;
  Value *slots[0];
  Frame *up() const { return reinterpret_cast<Frame *>(upBits & ~uintptr_t(1)); }
  bool captured() const { return upBits & 1; }
  void capture() { upBits |= 1; }
};

/// What the dialect promotes a value to (NixDialect::promotionOf): which cell it gets, if any, and what may read it back.
using Promotion = mlir::nix::NixDialect::Promotion;

inline constexpr unsigned kNoSlot = ~0u;
/// How a node is evaluated: one function a kind, which the node holds, so evaluating it is one indirect call into a function that saves
/// what that kind needs and no more (a single switch saved, at every entry, the registers of its biggest case).
using EvalFn = void (*)(EvalState &, Node *, Frame *, Value &);
/// What evaluating an op does, as a function: not a chain of TypeID compares.  Prim is an op of the continent dialects (a primop), Other
/// anything the evaluator reaches through NixEvalOpInterface.
enum class NodeKind : uint8_t {
  Arg, List, Attrs, Select, HasAttr, Apply, If, Assert, Not, And, Or, Impl, Eq, Neq, Update, ConcatLists, ConcatStrings, WithVar, Formal,
  Int, Bool, Null, Float, String, Path, Builtin, Lambda, Prim, Other
};
/// An SSA value of an indexed body as the evaluator reads it: one record, made when the body is indexed, at an address that stays put.  Where
/// the value lives (its region, its frame slot, what the dialect promoted it to) and, for an op's result, what evaluating the op reads: its
/// kind, its operands as the records of the values they name, its position.  A thunk holds the record of its op, so forcing it and reading
/// the operands touches no MLIR structure: no TypeID chain, no operand list, no hash probe per operand.  The op's attributes (names, paths,
/// literals) are still read from the op.
struct Node {
  /// What the first touch of a value's cell makes, from the defining op (Unknown for a block argument).
  enum How : uint8_t { Unknown, Thunk, Lambda, Const, Builtin };
  NodeKind kind;
  How how;
  Promotion promo;
  uint8_t flags = 0;        // Select: kDefault; Attrs: kDynamic; ConcatStrings: kForceString
  unsigned idx;             // kNoSlot: the value has no frame cell (it is evaluated in place, made by its one use, or fixed)
  uint32_t nOperands = 0;
  uint32_t nDyn = 0;        // Select and HasAttr: the dynamic keys after the base; Attrs: the static values, first
  RegionInfo *ri;
  Value *fixed = nullptr;   // a literal or a builtin: its one cell, the same in every frame, made at its first touch
  Node **operands = nullptr; // the op's operands, in order
  mlir::Operation *def;     // the op that defines the value; a block argument's lambda (kind Arg)
  union {
    const PrimOp *prim = nullptr; // Prim: what the op runs
    uint32_t rowGuess;            // Select, HasAttr, Formal: the row its (first) name was found at last (Bindings::getGuess)
  };
  EvalFn eval = nullptr;    // what evaluating the op is
  static constexpr uint8_t kDefault = 1, kDynamic = 1, kForceString = 1;
  bool inPlace() const { return promo == Promotion::InPlace; }
  /// A value with a cell to read back: its frame cell, or its fixed one.  Not one evaluated in place, whose lookup makes a temporary, nor
  /// one made by its one use, whose cell the frame does not keep.
  bool persists() const { return promo != Promotion::InPlace && promo != Promotion::Once; }
  auto args() const { return cp::series(operands, nOperands); }
  /// The op's position; a block argument's is its lambda's (where it was made).
  PosPtr pos() const { return mlir::nix::posOfOp(def); }
};
static_assert(sizeof(Node) == 64, "a node is one cache line");

//===----------------------------------------------------------------------===//
// Errors
//===----------------------------------------------------------------------===//

struct Trace {
  PosPtr pos;
  std::string msg;
};

struct EvalError : std::exception {
  std::string msg;
  PosPtr pos = nullptr;
  composite::MutableSeries<Trace> traces;
  EvalError(std::string m, PosPtr p = nullptr) : msg(std::move(m)), pos(p) {}
  const char *what() const noexcept override { return msg.c_str(); }
  EvalError &addTrace(PosPtr p, std::string m) & {
    traces.append({p, std::move(m)});
    return *this;
  }
  EvalError &&addTrace(PosPtr p, std::string m) && { // `throw EvalError(...).addTrace(...)`: the temporary is moved into the exception
    traces.append({p, std::move(m)});
    return std::move(*this);
  }
};
struct AssertionError : EvalError { using EvalError::EvalError; };
struct ThrownError : AssertionError { using AssertionError::AssertionError; };
struct Abort : EvalError { using EvalError::EvalError; };
struct TypeError : EvalError { using EvalError::EvalError; };
struct InfiniteRecursionError : EvalError { using EvalError::EvalError; };
struct StackOverflowError : EvalError { using EvalError::EvalError; };

//===----------------------------------------------------------------------===//
// Settings
//===----------------------------------------------------------------------===//

struct SearchPathElem {
  std::string prefix, path;
};

struct EvalSettings {
  composite::MutableSeries<SearchPathElem> nixPath;
  std::string currentSystem;
  bool pureEval = false;
  bool restrictEval = false;
  bool traceVerbose = false;
  bool abortOnWarn = false;
  bool showTrace = false;
  bool pipeOperators = false;
  bool optimize = true;
  /// MLIR pass pipeline (text, a comma-separated list: no `op(...)` wrapper, which
  /// would nest it under child ops) run on every lowered expression; any
  /// registered pass can be named (nix-prims, nix-fold, nix-dce, nix-simplify,
  /// cse, canonicalize, sccp, ...).  MLNIX_PIPELINE overrides it.  `nix-fold` and
  /// `nix-dce` cost more than they save on real workloads (measured), so only
  /// devirtualization is on by default.
  std::string pipeline = "nix-prims";
  /// Sea-of-nodes schedule (MLNIX_DEFER): mint no lambda body at lowering
  /// time; the op carries a pool row and the body is generated on first call.
  bool deferBodies = false;
  /// Imported files are mapped read-only (nixfe::Source::mapFile) instead of read and copied.
  bool mapSources = true;
  unsigned maxCallDepth = 10000;
  bool dumpMLIR = false;
  nixfe::Lint lintAbsolutePaths = nixfe::Lint::Ignore, lintShortPaths = nixfe::Lint::Ignore,
              lintUrls = nixfe::Lint::Ignore;
};

//===----------------------------------------------------------------------===//
// EvalState
//===----------------------------------------------------------------------===//

struct EvalState {
  EvalState(EvalSettings settings, std::shared_ptr<nixstore::Store> store);
  ~EvalState();

  EvalSettings settings;
  std::shared_ptr<nixstore::Store> store;
  SymbolTable symbols;
  mlir::MLIRContext ctx;
  mlir::OwningOpRef<mlir::ModuleOp> module;
  /// The optimization pipeline (text: settings.pipeline / MLNIX_PIPELINE), built on first use.
  std::unique_ptr<mlir::PassManager> optimizer;
  /// The demand schedule's optimizer: devirtualization (the default pipeline's one stage) with its
  /// pattern set frozen once.  A lambda body is not IsolatedFromAbove, so no PassManager runs on it.
  std::unique_ptr<mlir::FrozenRewritePatternSet> devirt;
  std::unique_ptr<ScalarJIT> scalarJIT; // opt-in, guarded native tier; initialized without an MLIR/LLVM context
  Arena alloc;

  // Frequently used symbols.
  struct {
    Symbol outPath, drvPath, type, name, value, functor, toString, file, line, column,
        outputs, outputName, all, drvAttrs, success, key, operator_, startSet, data,
        path, prefix, body, ignoreNulls, structuredAttrs, args, builder, system,
        outputHash, outputHashAlgo, outputHashMode, contentAddressed, impure,
        allowedReferences, allowedRequisites, disallowedReferences, disallowedRequisites,
        maxSize, maxClosureSize, json, right, wrong, attrsSym, sha256, url, rev, ref,
        submodules, shallow, allRefs, narHash, recursive, filter, lastModified,
        revCount, shortRev, lastModifiedDate, outPathSym, exportIgnore, executable, unpack;
  } s;

  // Shared constants.
  Value vTrue, vFalse, vNull, vEmptyAttrs, vEmptyList;
  Value *baseEnvValue(llvm::StringRef name);
  bool isBaseName(llvm::StringRef name) const;
  llvm::StringMap<Value *> baseEnv;
  Bindings *builtinsAttrs = nullptr;

  // -- Allocation --------------------------------------------------------
  Value *allocValue() {
    if (statsEnabled) ++nVT[kAllocated];
    return new (alloc.Allocate<Value>()) Value();
  }
  Bindings *allocBindings(size_t n);
  /// `a // b` (see Bindings::Layer).
  Bindings *updateAttrs(Bindings *a, Bindings *b);
  Value **allocList(size_t n);
  const char *copyString(std::string_view s);
  const StringContext *makeContext(const NixStringContext &c);

  /// Attribute positions are cold metadata. Repeated evaluation of a source attrset reuses
  /// one range of indices; copying an Attr copies its index without copying or interning a position.
  /// The MLIR positions property is unchanged by this runtime layout; table indices never enter the IR.
  PosPtr positionOf(const Attr &a) const { return attributePositions[a.pos]; }
  PosIdx positionIndex(PosPtr pos);
  PosIdx positionBase(mlir::nix::AttrsOp op);
  /// A set literal's rows in name order, worked out at its first evaluation and kept: `m` then the source index of each row (the first of
  /// equal names wins).  A literal's names and their symbols never change, so no evaluation after the first sorts anything.
  const uint32_t *attrsOrderOf(mlir::nix::AttrsOp op);
  struct AttrsOrderEntry { void *op = nullptr; const uint32_t *order = nullptr; };
  AttrsOrderEntry attrsOrderCache[1024];                        // 16 KB, direct-mapped by the op's address
  llvm::DenseMap<void *, const uint32_t *> attrsOrders;
  cp::MutableSeries<PosPtr> attributePositions{nullptr};
  std::unordered_map<PosPtr, PosIdx> dynamicPositions;
  llvm::DenseMap<mlir::Operation *, PosIdx> attrPositionBases;

  // -- Value construction ------------------------------------------------
  void mkInt(Value &v, int64_t n) { if (statsEnabled) ++nVT[unsigned(VType::Int)];  v.type = VType::Int; v.integer = n; }
  void mkFloat(Value &v, double d) { if (statsEnabled) ++nVT[unsigned(VType::Float)];  v.type = VType::Float; v.fpoint = d; }
  void mkBool(Value &v, bool b) { if (statsEnabled) ++nVT[unsigned(VType::Bool)];  v.type = VType::Bool; v.boolean = b; }
  void mkNull(Value &v) { if (statsEnabled) ++nVT[unsigned(VType::Null)];  v.type = VType::Null; }
  void mkString(Value &v, std::string_view s, const NixStringContext &ctx = {});
  /// A string literal: a window on the bytes the lowered op already holds (a Name: a slice of a mapped input or a never-freed arena), no copy.
  void mkStringWindow(Value &v, llvm::StringRef r) {
    std::string_view s(r.data(), r.size());
    if (s.size() > UINT32_MAX) throw EvalError("string of 4 GiB or more");
    v.type = VType::String; if (statsEnabled) ++nVT[unsigned(VType::String)];
    v.str.s = s.data(); v.aux = static_cast<uint32_t>(s.size()); v.str.ctx = nullptr;
  }
  /// A string made of pieces (windows over existing bytes), written once into one arena buffer.
  void mkStringOf(Value &v, llvm::ArrayRef<composite::Chars> pieces, const StringContext *ctx);
  void mkPath(Value &v, std::string_view p);
  void mkList(Value &v, size_t n);
  /// A list drained from a series of Value * (a Series, a vector, a combine): the one fill loop, the α of the caller inlined.
  template <class S> requires requires(const S &s, Value **o) { s.size(); cp::drain(s, o); }
  void mkList(Value &v, const S &s) {
    mkList(v, size_t(s.size()));
    cp::drain(s, v.list.elems);
  }
  void mkAttrs(Value &v, Bindings *b) { if (statsEnabled) ++nVT[unsigned(VType::Attrs)];  v.type = VType::Attrs; v.attrs = b; }
  void mkApp(Value &v, Value *f, Value *x) { if (statsEnabled) ++nVT[unsigned(VType::App)];  v.type = VType::App; v.app.left = f; v.app.right = x; }
  Value *mkAppValue(Value *f, Value *x) { Value *v = allocValue(); mkApp(*v, f, x); return v; }
  Value *newString(std::string_view s, const NixStringContext &ctx = {}) { Value *v = allocValue(); mkString(*v, s, ctx); return v; }
  /// A string on bytes that stay where they are (a name in the symbol table, a piece of an arena string): a window, nothing copied.
  Value *newStringWindow(llvm::StringRef r) { Value *v = allocValue(); mkStringWindow(*v, r); return v; }

  /// Builder for attribute sets.
  struct BindingsBuilder {
    BindingsBuilder(EvalState &st) : st(st) {}
    void insertIndexed(Symbol s, Value *v, PosIdx pos) { attrs.push_back({s, pos, v}); }
    void insert(Symbol s, Value *v, PosPtr pos = nullptr) { insertIndexed(s, v, st.positionIndex(pos)); }
    void insert(llvm::StringRef name, Value *v, PosPtr pos = nullptr) { insert(st.symbols.create(name), v, pos); }
    Value &alloc(llvm::StringRef name, PosPtr pos = nullptr) {
      Value *v = st.allocValue();
      insert(name, v, pos);
      return *v;
    }
    Value &alloc(Symbol s, PosPtr pos = nullptr) {
      Value *v = st.allocValue();
      insert(s, v, pos);
      return *v;
    }
    Bindings *finish(); // sorts; later inserts of the same name win? (no: first)
    size_t size() const { return attrs.size(); }
    EvalState &st;
    llvm::SmallVector<Attr, 12> attrs; // accumulated here, then drained into the arena by finish()
  };

  // -- Forcing -------------------------------------------------------------
  /// A value is already one: the common case is a test, here; a cell that is not a value yet (or any cell, in an instrumented run) is
  /// forced out of line, where the exception handling and the census live.
  void forceValue(Value &v, PosPtr pos = nullptr) {
    if (v.isThunk() || instrumented) forceCell(v, pos);
  }
  void forceCell(Value &v, PosPtr pos);
  /// The cell's evaluation threw this evaluation error, now in flight: the cell keeps it (VType::Failed).
  void fail(Value &v);
  [[noreturn]] void rethrowFailed(const Value &v);
  void forceValueDeep(Value &v);
  int64_t forceInt(Value &v, PosPtr pos, std::string_view errorCtx = "");
  double forceFloat(Value &v, PosPtr pos, std::string_view errorCtx = "");
  bool forceBool(Value &v, PosPtr pos, std::string_view errorCtx = "");
  void forceAttrs(Value &v, PosPtr pos, std::string_view errorCtx = "");
  void forceList(Value &v, PosPtr pos, std::string_view errorCtx = "");
  void forceFunction(Value &v, PosPtr pos, std::string_view errorCtx = "");
  std::string_view forceString(Value &v, PosPtr pos = nullptr, std::string_view errorCtx = "");
  std::string_view forceString(Value &v, NixStringContext &ctx, PosPtr pos = nullptr,
                               std::string_view errorCtx = "");
  std::string_view forceStringNoCtx(Value &v, PosPtr pos = nullptr, std::string_view errorCtx = "");
  /// Force/check a selection base and return its existing, unforced field cell.
  /// Dynamic-key validation precedes this operation; the caller forces the result.
  Value *selectField(Value &base, Symbol key, PosPtr pos);
  Value *selectField(Value &base, Symbol key, PosPtr pos, uint32_t &guess); // with the row guess of the select (Bindings::getGuess)
  void copyContext(const Value &v, NixStringContext &ctx);

  // -- Calls -----------------------------------------------------------------
  void callFunction(Value &fun, size_t nargs, Value **args, Value &out, PosPtr pos, bool allowCurried = true);
  void callFunction(Value &fun, Value &arg, Value &out, PosPtr pos) {
    Value *a = &arg;
    callFunction(fun, 1, &a, out, pos);
  }
  void autoCallFunction(const std::map<std::string, Value *> &autoArgs, Value &fun, Value &out);

  // -- Coercions -------------------------------------------------------------
  std::string coerceToString(Value &v, NixStringContext &ctx, bool coerceMore, bool copyToStore,
                             PosPtr pos = nullptr, std::string_view errorCtx = "",
                             bool canonicalizePath = true);
  // The same coercion as a window: a string, and a set's __toString result or outPath, is its own bytes (nothing copied); anything else is made
  // in `scratch`, which the window views.
  // With `own`, a string (and a set's __toString result or outPath) hands its own context back through it instead of copying it into ctx.
  composite::Chars coerceToWindow(Value &v, NixStringContext &ctx, bool coerceMore, bool copyToStore, PosPtr pos,
                                       std::string_view errorCtx, std::string &scratch, bool canonicalizePath = true,
                                       const StringContext **own = nullptr);
  std::string coerceToPath(Value &v, NixStringContext &ctx, PosPtr pos, std::string_view errorCtx = "");
  std::string coerceToStorePath(Value &v, NixStringContext &ctx, PosPtr pos, std::string_view errorCtx = "");
  std::string copyPathToStore(NixStringContext &ctx, const std::string &path);
  bool isDerivation(Value &v);
  std::optional<std::string> tryAttrsToString(Value &v, NixStringContext &ctx, bool coerceMore,
                                              bool copyToStore);

  // -- Comparison ------------------------------------------------------------
  bool eqValues(Value &a, Value &b, PosPtr pos);
  bool lessThan(Value &a, Value &b, PosPtr pos);

  // -- Types ----------------------------------------------------------------
  static const char *showType(const Value &v);
  static const char *typeOf(const Value &v);

  // -- Errors -----------------------------------------------------------------
  [[noreturn]] void throwTypeError(const char *expected, Value &v, PosPtr pos, std::string_view ctx = "");
  [[noreturn]] void throwError(const std::string &msg, PosPtr pos = nullptr);
  void warn(const std::string &msg);
  std::string showPos(PosPtr pos) const;

  // -- Printing ---------------------------------------------------------------
  void printValue(std::ostream &os, Value &v, std::set<const void *> *seen, size_t depth = 0);
  std::string printValueForTrace(Value &v);
  void printValueAsJSON(std::ostream &os, Value &v, bool strict, NixStringContext &ctx,
                        bool copyToStore = true, PosPtr pos = nullptr);
  void printValueAsXML(std::ostream &os, Value &v, bool strict, bool location, NixStringContext &ctx);

  // -- Parsing / evaluation entry points ---------------------------------------
  /// Parse+lower+evaluate a file (cached).  Result is a lazy value.
  Value *evalFile(const std::string &path);
  /// Parse+lower a string; returns the expression value (lazy).
  Value *evalString(const std::string &text, const std::string &baseDir,
                    const std::string &originName = "«string»");
  /// Parse only.
  nixfe::ParseOptions parseOptions();
  /// Parse a source into the module (kept alive by the state, as its origin is).
  mlir::nix::ExprOp lowerToMLIR(std::shared_ptr<nixfe::Origin> origin, const composite::MutableSeries<std::string> *scopeNames = nullptr);
  Value *evalExprOp(mlir::nix::ExprOp op);
  /// Load all nix.expr ops of an MLIR module (from mlnix compile) and
  /// evaluate the one named `sym` (or the first).
  Value *evalMLIRFile(const std::string &path, const std::string &sym);

  std::string resolveExprPath(std::string path);
  std::string findFile(Value &searchPath, std::string_view name, PosPtr pos);
  std::string realisePath(const std::string &path, PosPtr pos);
  /// Ensure the store paths in `ctx` are realised (import-from-derivation).
  void realiseContext(const NixStringContext &ctx, PosPtr pos);

  // -- Builtins -----------------------------------------------------------------
  /// The arguments of a primop call are gathered in a fixed array of this many cells (checked once, when a primop is registered).
  static constexpr unsigned kMaxPrimArity = 8;
  void addPrimOp(const std::string &name, unsigned arity, PrimFn fn);
  /// For a primop that captures (a registering loop's parameter).
  void addPrimOpClosure(const std::string &name, unsigned arity, std::function<void(EvalState &, Value **, Value &, PosPtr)> fn);
  void addConstant(const std::string &name, Value *v);
  void registerPrimOp(const std::string &name, PrimOp *p);
  void createBaseEnv();

  // Interpreter internals (public for builtins).
  /// Call a primop on already-collected arguments, adding the
  /// "while calling the 'X' builtin" trace like upstream.
  void callPrimOp(const PrimOp &op, Value **args, Value &out, PosPtr pos);
  const PrimOp *primOpByKey(llvm::StringRef key);
  /// The primop an IRDL-defined continent op stands for (cached per op name).
  const PrimOp *primFor(mlir::Operation *op);
  llvm::DenseMap<const void *, const PrimOp *> primForOp;
  /// MLNIX_STATS=1: op histogram of every module lowered, printed at exit.
  llvm::StringMap<size_t> opStats;
  bool statsEnabled = false;
  bool instrumented = false; // statsEnabled or recordEdges: forceValue always takes the out-of-line path

  /// The operand `v` of the op being evaluated in frame `f`, for a consumer that forces it
  /// right away and does not keep the Value (a `strict` operand, see NixModes).  When the
  /// value is evaluated in place the result is `tmp`, already in WHNF; otherwise it is the
  /// frame's (possibly still unevaluated) thunk, exactly like lookup().
  Value &operand(Frame *f, Node *v, Value &tmp);
  /// Evaluates `v` to WHNF into `out` (a `tail` operand: the op's result is its value).
  void evalTail(Frame *f, Node *v, Value &out, PosPtr pos);

  void evalDefinition(Node *def, Frame *f, Value &dest);
  void printStats();
  /// Constant folding hook of the continent dialects: run primop `key` on
  /// scalar constants; null when it throws or yields a non-scalar.
  mlir::Attribute foldPrimOp(llvm::StringRef key, llvm::ArrayRef<mlir::Attribute> args);
  /// The evaluator Symbol of a Name held by an op: hashed by the first evaluation that asks and kept in the Name
  /// (in the op), so a name is hashed at most once per op, and never when its code is never run.  Pass the
  /// property in place (`op.getName()` and `getPath()` return references into the op), not a copy of it.
  Symbol symbolOf(const nixfe::Name &n) {
    if (n.symbol) return n.symbol - 1;
    Symbol s = symbols.create(n.str());
    n.symbol = s + 1;
    return s;
  }
  /// The same for a name MLIR has interned as a StringAttr (the formals and names of lambdas).  Keyed by the
  /// attribute's address, so no string is hashed or compared (the uniquer did that once, at lowering).
  Symbol symbolOf(mlir::StringAttr a) {
    auto [it, inserted] = attrSymbols.try_emplace(a.getAsOpaquePointer(), Symbol());
    if (inserted) it->second = symbols.create(a.getValue());
    return it->second;
  }
  llvm::DenseMap<const void *, Symbol> attrSymbols;
  /// The symbol of a string value's bytes.  A string value's bytes never change and never move (an arena, a mapped source, an op's
  /// property, the symbol table's own entries), so their address and length name them for the whole run: a string met before (the literal
  /// list of a removeAttrs called a hundred thousand times, a name attrNames handed out) is answered by its address, not hashed and probed.
  /// Only for the bytes of a string value: a temporary's address would name other bytes later.
  Symbol symbolOfString(std::string_view s) {
    StrSymEntry &e = strSymCache[((reinterpret_cast<uintptr_t>(s.data()) >> 3) ^ (s.size() * 0x9E3779B1u)) & (kStrSymCache - 1)];
    if (e.p == s.data() && e.n == s.size()) return e.sym;
    Symbol sym = symbols.create(s);
    e = {s.data(), uint32_t(s.size()), sym};
    return sym;
  }
  struct StrSymEntry { const char *p = nullptr; uint32_t n = 0; Symbol sym = 0; };
  static constexpr size_t kStrSymCache = 4096; // 64 KB
  StrSymEntry strSymCache[kStrSymCache];
  /// Symbol of one select/has_attr path component: literal (a name) or the
  /// next computed key (operand), forced to a string.
  Symbol pathSymbol(const nixfe::Name &comp, Node *const *dyn, unsigned &nextDyn, Frame *env, PosPtr pos);
  Value *lookup(Frame *f, Node *v) { return lookupImpl(f, v, false); }
  /// The same from the SSA value: one hash probe to find its record (the JITs, the primop model, the cold paths).
  Value *lookup(Frame *f, mlir::Value v) { return lookupImpl(f, nodeOfValue(v), false); }
  Node *nodeOfValue(mlir::Value v) {
    Node *n = nodeOf(v.getAsOpaquePointer());
    if (!n) unindexed();
    return n;
  }
  [[noreturn]] static void unindexed();
  void evalOp(Node *n, Frame *env, Value &out) {
    if (statsEnabled) [[unlikely]] statEval(n, env);
    n->eval(*this, n, env, out);
  }
  void statEval(Node *n, Frame *env);
  RegionInfo *regionInfo(mlir::Region *r);
  /// A frame of `ri`'s body: its slots empty.  The ordinary case (no census, no recycling) is a bump of the arena, here; the rest out of line.
  Frame *newFrame(RegionInfo *ri, Frame *up) {
    if (statsEnabled || recycleOn) [[unlikely]] return newFrameSlow(ri, up);
    unsigned n = ri->numSlots;
    auto *f = static_cast<Frame *>(alloc.Allocate(sizeof(Frame) + n * sizeof(Value *), alignof(Frame)));
    f->upBits = reinterpret_cast<uintptr_t>(up);
    f->info = ri;
    memset(f->slots, 0, n * sizeof(Value *));
    return f;
  }
  Frame *newFrameSlow(RegionInfo *ri, Frame *up);

  unsigned callDepth = 0;
  unsigned tryLevel = 0;
  std::map<std::string, std::string> srcToStore;
  std::map<std::string, Value *> fileEvalCache;
  std::map<std::string, Value *> scopedImportCache;
  composite::MutableSeries<std::shared_ptr<nixfe::Origin>> origins;
  /// MLNIX_DEFER: one pool of deferred lambdas per lowered file.  The `body_index` of a nix.lambda is a
  /// nixfe::BodyIndex (`file j row`) into these.
  composite::MutableSeries<std::unique_ptr<nixfe::FilePool>> pools; // indexed by FilePool::file; a slot is empty while its file is only prelowered
  std::atomic<uint32_t> nextPoolId{0};
  void installPool(std::unique_ptr<nixfe::FilePool> p);
  unsigned exprCounter = 0;

  /// MLNIX_PRELOWER=1 with MLNIX_PREFETCH=auto (the files a previous run of this invocation evaluated; the first run records them), or MLNIX_PRELOWER_LIST=file (such a list): a helper thread lexes, parses
  /// and builds the IR of those files ahead of the evaluator, which adopts each finished file when evalFile asks for it.  The helper does
  /// no evaluation and no optimization (the prim folder calls back into the evaluator), only genExpr into a module of its own.
  struct Indexer;
  struct Prelowered {
    std::shared_ptr<nixfe::Origin> origin;
    mlir::OwningOpRef<mlir::ModuleOp> mod;
    mlir::nix::ExprOp op;
    std::unique_ptr<nixfe::FilePool> pool;
    bool done = false, ok = false;
    bool optimized = false; // devirtualized by the helper (the demand schedule's whole pipeline): adoption runs no pass
    std::unique_ptr<Indexer> index; // the file's body indexed by the helper: adoption installs its regions and captures
  };
  struct PrelowerState {
    std::mutex m;
    std::condition_variable cv;
    std::unordered_map<std::string, std::shared_ptr<Prelowered>> byPath;
    composite::MutableSeries<std::string> queue; // paths, appended; the helpers drain them from `head` (a cell leaves, an empty one stays)
    uint32_t head = 0;
    std::unordered_set<std::string> baseNames;
    nixfe::ParseOptions po;
    composite::MutableSeries<std::thread> workers;
    bool stop = false;
    uint64_t adopted = 0, waited = 0, missed = 0;
  };
  std::unique_ptr<PrelowerState> pre;
  void startPrelower();
  void prelowerLoop();
  mlir::nix::ExprOp takePrelowered(const std::string &resolved);
  std::function<void(const std::string &)> printTrace;

  // The record of each SSA value, by the value's address: the evaluator reads the records an op's record points at and never asks; the JITs,
  // the primop model and the cold paths ask here, through a direct-mapped cache in front of the hash map.  A value's address indexed again
  // (an op erased by a pass and its storage reused) gets a new record, and the map and the cache are rewritten, so neither holds a stale one.
  llvm::DenseMap<void *, Node *> nodeMap;
  struct NodeCacheEntry { void *key = nullptr; Node *node = nullptr; };
  static constexpr size_t kNodeCache = 8192;
  NodeCacheEntry nodeCache[kNodeCache];
  Node *nodeOf(void *key) {
    NodeCacheEntry &e = nodeCache[(reinterpret_cast<uintptr_t>(key) >> 4) & (kNodeCache - 1)];
    if (e.key == key) return e.node;
    if (statsEnabled) [[unlikely]] ++nSlotMisses;
    auto it = nodeMap.find(key);
    if (it == nodeMap.end()) return nullptr;
    e = {key, it->second};
    return e.node;
  }
  /// Indexing a body: its RegionInfo and a node for each of its values.  The evaluator's indexer allocates in the evaluator's arena and
  /// writes its maps; a prelowering helper's allocates in an arena of its own and lists what the evaluator takes over with the file (the
  /// regions it indexed, the captures of the deferred bodies in it), so a file arrives indexed, by the thread whose caches hold its IR.
  struct Indexer {
    EvalState &st;
    bool helper;
    llvm::BumpPtrAllocator arena;                 // a helper's: the nodes live as long as the evaluator keeps this indexer
    /// The records of the values of the blocks being indexed: an operand in its own block (or in a block around it, indexed in the same
    /// recursion) is found here, in a map the size of those blocks; emptied when the outermost body is done.
    llvm::DenseMap<void *, Node *> blockNodes;
    unsigned depth = 0;
    composite::MutableSeries<std::pair<void *, Node *>> captures;           // a helper's: for the evaluator's map of every value
    composite::MutableSeries<std::pair<mlir::Region *, RegionInfo *>> regions; // a helper's: for regionInfos
    Indexer(EvalState &st, bool helper) : st(st), helper(helper) {}
    void *allocate(size_t n, size_t a) { return helper ? arena.Allocate(n, llvm::Align(a)) : st.alloc.Allocate(n, a); }
    void index(mlir::Region &r);
  };
  Indexer indexer{*this, false};
  composite::MutableSeries<std::unique_ptr<Indexer>> helperIndexers; // adopted with their files: their arenas hold those files' nodes
  void setNode(void *key, Node *n) {
    nodeMap[key] = n;
    NodeCacheEntry &e = nodeCache[(reinterpret_cast<uintptr_t>(key) >> 4) & (kNodeCache - 1)];
    if (e.key == key) e.node = n;
  }
  uint64_t nUpdLayered = 0, nUpdMerged = 0, nUpdBase = 0, nUpdTop = 0; // MLNIX_STATS: `//` as a layer / a flat merge, entries not copied / copied
  uint64_t nDemandMinted = 0; // MLNIX_STATS: lambda bodies minted on first call
  uint64_t nSlotMisses = 0;   // MLNIX_STATS: nodeOf answered by the hash map, not its cache
  static constexpr unsigned kAllocated = unsigned(VType::PrimOpApp) + 1; // nVT's last row: cells allocated
  uint64_t nVT[kAllocated + 1] = {}; // MLNIX_STATS: instrumented tag writes, including stack values and repeated retyping;
                         // [14] alone counts allocated Value rows, not tag writes
  uint64_t nFrames = 0, nFrameBytes = 0, nFrameSlots = 0; // requested frame storage, excluding arena overhead
  composite::MutableSeries<std::pair<std::string, size_t>> evaluatedFiles; // MLNIX_STATS_IMPORTS: files evalFile'd, with how many path literals had been lowered by then
  composite::MutableSeries<uint64_t> epochEvals; // MLNIX_STATS: evalOp calls per epoch (one epoch a derivation attribute the driver visits)
  void beginEpoch() { if (statsEnabled) epochEvals.append(0); }
  llvm::DenseMap<const Value *, uint32_t> forcedBy; // MLNIX_STATS_EDGES: the epoch that first forced a cell
  llvm::DenseSet<uint64_t> epochEdges;              // MLNIX_STATS_EDGES: (earlier epoch << 32 | later epoch) when the later one touched a cell the earlier one forced
  bool recordEdges = false;
  void epochTouch(const Value &v);
  uint64_t nMaskBytes = 0, nLayerBytes = 0, nMergeBytes = 0, nCtxBytes = 0, nFormalBytes = 0; // MLNIX_STATS: arena bytes the by-use line did not name before
  uint64_t nLookups = 0, nLookupHits = 0, nHopHist[6] = {}; // MLNIX_STATS: lookupImpl calls, those answered by a filled slot, and the frame hops to the defining region (0, 1, 2, 3, 4, 5 or more)
  llvm::DenseMap<const void *, std::pair<llvm::StringRef, std::array<uint64_t, 2>>> cellsByKind; // MLNIX_STATS: cells lookup made, by defining op: [evaluated at once, left a thunk]
  llvm::DenseMap<const void *, std::pair<llvm::StringRef, uint64_t>> evalsByKind; // MLNIX_STATS: evalOp calls by op kind
  uint64_t nTouchAt[17] = {}, nFramesBySize[17] = {}; // MLNIX_STATS: first touches by slot index (16 = 16 or more), frames by slot count
  static constexpr unsigned kSrcClasses = 5; // 1 nixpkgs lib, 2 nixos modules, 3 pkgs, 4 other
  uint64_t nClsFrames[kSrcClasses] = {}, nClsSlots[kSrcClasses] = {}, nClsTouched[kSrcClasses] = {};
  unsigned srcClassOf(RegionInfo *ri);
  uint64_t nChainOuter = 0, nChainOuterSlots = 0; // MLNIX_STATS: frames (and their slots) that exist only to capture an argument for an inner lambda
  uint64_t nStackable = 0, nStackableBytes = 0, nStackableOneSlot = 0; // MLNIX_STATS: frames (and their bytes) of bodies that cannot leak their frame
  uint64_t nTouchedBy[6] = {}; // MLNIX_STATS: slots ever read, by the slot count of their frame (1, 2-3, 4-8, 9-16, 17-64, 65+)
  uint64_t nBindingBytes = 0, nListBytes = 0, nStringBytes = 0; // MLNIX_STATS: arena bytes by use (values and frames are counted above)
  uint64_t nStackFrames = 0; // MLNIX_STATS: calls run on a stack frame, nothing allocated in the arena
  /// Can a call of this body run on a stack frame?  Decided at its first call (classifyStackFrame) and kept in the region.
  bool stackFrameOK(RegionInfo *ri) { return ri->stackable == 2 ? classifyStackFrame(ri) : ri->stackable == 1; }
  bool classifyStackFrame(RegionInfo *ri);
  /// The cell of `v` in frame `f` (or the enclosing frame of its region): a fixed one, or one its frame already holds, is found here; one to
  /// make (a thunk, a value evaluated now, a closure, a literal) is made out of line.
  Value *lookupImpl(Frame *f, Node *v, bool forced) {
    if (v && !statsEnabled) {
      if (v->fixed) return v->fixed;
      if (v->idx != kNoSlot) {
        Frame *g = f;
        while (g && g->info != v->ri) g = g->up();
        if (g && g->slots[v->idx]) return g->slots[v->idx];
      }
    }
    return makeCell(f, v, forced);
  }
  Value *makeCell(Frame *f, Node *v, bool forced);
  Value *makeFixed(Node *s);
  Value *evalNow(Frame *f, Node *s, Value *nv);
  void statCell(Frame *f, Node *s, Value *nv, bool eager);
  uint64_t nEager = 0;   // MLNIX_STATS
  // Frames that returned uncaptured, by slot count: a stack per size, linked through the frame's own first word.  The newest is reused first, so
  // a recycled frame is almost always still in L1 (docs/FRAME-BYTES.md: 97 to 98% of reuses are within 32 KiB of allocation).
  static constexpr unsigned kRecycleMax = 64;
  Frame *freeFrames[kRecycleMax] = {};
  bool recycleOn = false;  // MLNIX_RECYCLE=1 turns it on: it trades a little time for memory (docs/FRAME-BYTES.md)
  void recycleFrame(Frame *f) {
    unsigned n = f->info->numSlots;
    if (n >= kRecycleMax) return;
    f->info = nullptr;  // a stale use of a recycled frame fails at once
    f->upBits = reinterpret_cast<uintptr_t>(freeFrames[n]);
    freeFrames[n] = f;
  }
  void markCaptured(Frame *f);
  void markPinned(Frame *f);
  void statUnref(Frame *f);
  void statReturn(Frame *f);
  /// The region of a lambda's body, from a direct-mapped cache keyed by the op's address.  Sound because an entry is made only for a lambda that
  /// is being called, and nothing erases a called op (the passes that erase run on a body when it is lowered or minted, before any call of it).
  /// The region of a lambda's body, from a direct-mapped cache keyed by the op: a hit is a load and a compare, where the lookup was a read
  /// of the op's deferred-body attribute and a hash probe on every call (3.7% of the CPU of a NixOS evaluation on Kali).
#ifdef MLNIX_NO_LOOKUP_CACHES  // ablation build (docs/SELECT-AND-LOOKUP.md): the lookups without the caches in front
  RegionInfo *infoOf(mlir::nix::LambdaOp lam) { return infoOfSlow(lam); }
#else
  RegionInfo *infoOf(mlir::nix::LambdaOp lam) {
    const void *k = lam.getOperation();
    InfoSlot &e = infoCache[(reinterpret_cast<uintptr_t>(k) >> 4) & (kInfoCache - 1)];
    if (e.op == k) return e.ri;
    RegionInfo *ri = infoOfSlow(lam);
    e = {k, ri};
    return ri;
  }
#endif
  RegionInfo *infoOfSlow(mlir::nix::LambdaOp lam);
  static constexpr size_t kInfoCache = 4096;
  struct InfoSlot { const void *op = nullptr; RegionInfo *ri = nullptr; };
  InfoSlot infoCache[kInfoCache];
  bool jitChain(mlir::nix::LambdaOp lambda, RegionInfo *ri, Value &cur, size_t n, Value **args, Value &out, PosPtr pos);
  void callLambdaIn(Value &fun, RegionInfo *ri, Value *arg, Value &out, PosPtr pos);
  void applySelector(unsigned shape, RegionInfo *ri, Value **a, Value &dest, PosPtr pos);
  void statTouch(Frame *f, RegionInfo *ri, unsigned idx);
  void statHops(Frame *f, RegionInfo *ri, bool hit);
  // MLNIX_STATS: the select census.  A layout signature is the set's size and three sampled names; a site is mono-, few- or megamorphic
  // by how many distinct signatures it has seen.
  struct SelSite { uint64_t calls = 0, hits = 0, sameAsLast = 0, last = 0; cp::MutableSeries<uint64_t, cp::Inline<uint64_t, 6>> seen; bool dynamic = false; };
  llvm::DenseMap<const void *, SelSite> selSites;
  uint64_t nMatchCalls = 0; llvm::StringMap<uint64_t> matchPairs; // MLNIX_STATS: builtins.match calls, by (regex, input)
  llvm::StringMap<Value> matchMemo; // builtins.match's answers, keyed by the pattern's length and bytes, then the input's
  std::string matchKey;             // the key of the call at hand, built here so a lookup allocates nothing
  uint64_t nSelects = 0, nSelectHits = 0, nSelectDyn = 0, nSelectLayered = 0, nSelectProbes = 0, nSelectSizeLog[18] = {};
  void statSelect(const void *site, const Bindings *b, Symbol key, bool dynamic);
  // MLNIX_STATS: a recycling allocator for frames, simulated.  A frame that returns with nothing made over it (no thunk, no closure) can never be
  // reached again, so its storage could serve the next frame of the same slot count; simFree counts those, per slot count.
  composite::MutableSeries<composite::MutableSeries<uint64_t>> simFree;   // per slot count: the allocation clock at each release (a stack: the newest is reused first)
  uint64_t allocClock() const { return nFrameBytes + nVT[kAllocated] * sizeof(Value) + nBindingBytes + nListBytes + nStringBytes; }
  uint64_t nSimReuseDist[5] = {};               // reuse distance in bytes allocated since the release: < 32 KiB, < 256 KiB, < 2 MiB, < 32 MiB, more
  uint64_t nSimHit = 0, nSimHitBytes = 0, nSimReleased = 0, nSimReleasedBytes = 0, nSimCaptured = 0;
  uint64_t nBuilders = 0, nBuilderRows = 0, nBuildersBig = 0, nBuilderBigRows = 0; // MLNIX_STATS: attribute-set builders, and those past the 12 inline rows (a malloc)
  llvm::StringMap<std::pair<uint64_t, uint64_t>> thunksByOp; // MLNIX_STATS: frame-needing thunks by operation: count, packed operand counts
  uint64_t nProjThunks = 0, nHardThunks = 0, nImmediate = 0, nImmediateLater = 0; // MLNIX_STATS: frame-needing thunks forced as the very next thing
  const Value *lastThunk = nullptr;
  llvm::StringMap<uint64_t> immediateByOp; // MLNIX_STATS: thunks made over a frame, projections and the rest
  uint64_t nSelectorCalls = 0; // MLNIX_STATS: saturated calls of a recognized selector, made with no frame and no closure
  bool selectorsOn = true;     // MLNIX_NOSELECTORS turns the recognition off
  unsigned selectorShape(mlir::nix::LambdaOp outerLam, RegionInfo *outer);
  std::string shapeOf(RegionInfo *ri, unsigned depth = 0); // MLNIX_STATS_SHAPES
  uint64_t nStackCells = 0; // MLNIX_STATS: curried-call intermediates held by value instead of in a heap cell
  uint64_t nEmptyShared = 0; // MLNIX_STATS: empty attribute sets that were the shared constant instead of a fresh 16-byte cell
  uint64_t nSlotsTouched = 0; // MLNIX_STATS: frame slots that were ever read (a cell made on first touch), of nFrameSlots allocated
  uint64_t nSlotsAssigned = 0, nSlotsNoRead = 0; // MLNIX_STATS: frame cells assigned, and those given to a value with no use at all
  uint64_t nsLower = 0, nsMint = 0; // MLNIX_STATS: time lowering files (analysis of deferred lambdas included) / minting bodies on demand
  llvm::DenseMap<mlir::Region *, RegionInfo *> regionInfos;
  void indexRegion(mlir::Region &r);
  void evalConcatStrings(Node *n, Frame *env, Value &out);
  void evalAttrsDynamic(Node *n, Frame *env, Value &out);
  [[noreturn]] void notAFunction(Value &cur, PosPtr pos); // cold: builds the message
  void evalAttrs(Node *n, Frame *env, Value &out);
  RegionInfo *mintLambda(nixfe::FilePool &p, uint32_t row);
  RegionInfo *bodyOf(nixfe::BodyIndex idx);
  void callLambda(Value &fun, Value *arg, Value &out, PosPtr pos);
};

/// Render an error the way Nix does ("error: ..." with source excerpt).
std::string formatError(EvalState *state, const EvalError &e);
std::string formatParseError(const nixfe::ParseError &e, const char *kind = "error");

/// Register all builtins (Builtins.cpp).
void registerBuiltins(EvalState &state);
/// Parse JSON into a value (FromJSON in Builtins.cpp).
void parseJSON(EvalState &state, std::string_view json, Value &v);
void parseTOML(EvalState &state, std::string_view toml, Value &v);

/// Run `fn` on a thread with a large stack (deep recursion in the evaluator).
int runWithLargeStack(std::function<int()> fn);

/// Attach the evaluator's external `NixEvalOpInterface` models to the ops of
/// the Nix dialect family in `ctx` (EvalModels.cpp).
void registerEvalModels(mlir::MLIRContext &ctx);

} // namespace nixev

#endif
