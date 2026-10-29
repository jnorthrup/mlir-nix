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

#include <functional>
#include <map>
#include <memory>
#include <set>
#include <string>
#include <unordered_map>
#include <vector>

#include "Nix/Arena.h"

namespace nixev {
namespace cp = ::composite;

using Symbol = uint32_t;

struct SymbolTable {
  Symbol create(llvm::StringRef s) {
    auto it = map.find(s);
    if (it != map.end()) return it->second;
    Symbol id = names.size();
    auto r = map.try_emplace(s, id);
    names.push_back(r.first->getKey());
    return id;
  }
  llvm::StringRef operator[](Symbol s) const { return names[s]; }
  size_t size() const { return names.size(); }

  llvm::StringMap<Symbol> map;
  std::vector<llvm::StringRef> names;
};

struct Value;
struct Frame;
struct RegionInfo;
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
  /// Attributes sorted by name (string order).
  std::vector<const Attr *> lexicographicOrder(const SymbolTable &st) const;
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

struct PrimOp;

enum class VType : uint8_t {
  Thunk, App, Blackhole, Int, Float, Bool, Null, String, Path, Attrs, List,
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
      mlir::Operation *op;
      Frame *env;
    } thunk; // Thunk and Lambda
    struct {
      Value *left, *right;
    } app; // App thunk and PrimOpApp
    const PrimOp *primOp;
  };

  Value() : integer(0) {}

  bool isThunk() const { return type == VType::Thunk || type == VType::App || type == VType::Blackhole; }
  bool isFunction() const { return type == VType::Lambda || type == VType::PrimOp || type == VType::PrimOpApp; }
  std::string_view sv() const { return {str.s, aux}; }
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
  /// For a lambda body: the symbols of the lambda's formals (made at its first call, by EvalState::callLambda) and the op
  /// they were made from.
  const Symbol *formalSyms = nullptr;
  mlir::Operation *formalsOf = nullptr;
  /// Stable entry owned by this evaluator's optional JIT; closure values are resolved at each call.
  void *jitEntry = nullptr;
  /// Optional arity-indexed JIT cache, owned by ScalarJIT and never an environment.
  void *curriedEntry = nullptr;
  uint64_t calls = 0; // MLNIX_STATS: frames made for this region
  uint8_t srcClass = 0; // MLNIX_STATS: where the region's code is defined, once classified (EvalState::srcClassOf); 0 unclassified
  /// MLNIX_STATS: what this region's sea of nodes holds.  nOps its body's ops; nThunks its cells that start as
  /// thunks (finer-grain deferral would mint those, so they are its rows); nEvals its ops' evals (a region called
  /// N times counts N times); everRan the distinct ops that ran, one bit an op, opIdx the op -> bit.
  uint32_t nOps = 0, nThunks = 0;
  uint64_t nEvals = 0;
  llvm::DenseMap<mlir::Operation *, uint32_t> opIdx{};
  std::vector<uint64_t> everRan{};
};

struct Frame {
  Frame *up;
  RegionInfo *info;
  Value *slots[0];
};

/// Where an SSA value lives: its region, its frame slot, and whether its single
/// strict/tail consumer evaluates it in place (NixDialect::evaluatesInPlace).
inline constexpr unsigned kNoSlot = ~0u;
struct Slot {
  /// What the first touch of a value's cell makes; worked out from the defining op once, at the first touch of the value in any
  /// frame, and kept here.
  enum How : uint8_t { Unknown, Thunk, Lambda, Const, Builtin };
  RegionInfo *ri;
  mlir::Operation *def; // the op that defines the value, null for a block argument (Value::getDefiningOp() is a call into MLIR)
  unsigned idx;         // kNoSlot: the value is evaluated in place and has no cell
  How how;
  bool inPlace;
};

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
  std::vector<Trace> traces;
  EvalError(std::string m, PosPtr p = nullptr) : msg(std::move(m)), pos(p) {}
  const char *what() const noexcept override { return msg.c_str(); }
  EvalError &addTrace(PosPtr p, std::string m) {
    traces.push_back({p, std::move(m)});
    return *this;
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
  std::vector<SearchPathElem> nixPath;
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
    if (statsEnabled) ++nVT[14];
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
  cp::MutableSeries<PosPtr> attributePositions{{nullptr}};
  std::unordered_map<PosPtr, PosIdx> dynamicPositions;
  llvm::DenseMap<mlir::Operation *, PosIdx> attrPositionBases;

  // -- Value construction ------------------------------------------------
  void mkInt(Value &v, int64_t n) { if (statsEnabled) ++nVT[unsigned(VType::Int)];  v.type = VType::Int; v.integer = n; }
  void mkFloat(Value &v, double d) { if (statsEnabled) ++nVT[unsigned(VType::Float)];  v.type = VType::Float; v.fpoint = d; }
  void mkBool(Value &v, bool b) { if (statsEnabled) ++nVT[unsigned(VType::Bool)];  v.type = VType::Bool; v.boolean = b; }
  void mkNull(Value &v) { if (statsEnabled) ++nVT[unsigned(VType::Null)];  v.type = VType::Null; }
  void mkString(Value &v, std::string_view s, const NixStringContext &ctx = {});
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
  void forceValue(Value &v, PosPtr pos = nullptr);
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
  mlir::nix::ExprOp lowerToMLIR(std::shared_ptr<nixfe::Origin> origin, const std::vector<std::string> *scopeNames = nullptr);
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
  bool inPlaceEnabled = true;

  /// The operand `v` of the op being evaluated in frame `f`, for a consumer that forces it
  /// right away and does not keep the Value (a `strict` operand, see NixModes).  When the
  /// value is evaluated in place the result is `tmp`, already in WHNF; otherwise it is the
  /// frame's (possibly still unevaluated) thunk, exactly like lookup().
  Value &operand(Frame *f, mlir::Value v, Value &tmp);
  /// Evaluates `v` to WHNF into `out` (a `tail` operand: the op's result is its value).
  void evalTail(Frame *f, mlir::Value v, Value &out, PosPtr pos);

  void evalDefinition(mlir::Operation *def, Frame *f, Value &dest);
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
  /// Symbol of one select/has_attr path component: literal (a name) or the
  /// next computed key (operand), forced to a string.
  Symbol pathSymbol(const nixfe::Name &comp, mlir::OperandRange dyn, unsigned &nextDyn, Frame *env, PosPtr pos);
  Value *lookup(Frame *f, mlir::Value v);
  void evalOp(mlir::Operation *op, Frame *env, Value &out);
  RegionInfo *regionInfo(mlir::Region *r);
  Frame *newFrame(RegionInfo *ri, Frame *up);

  unsigned callDepth = 0;
  unsigned tryLevel = 0;
  std::map<std::string, std::string> srcToStore;
  std::map<std::string, Value *> fileEvalCache;
  std::map<std::string, Value *> scopedImportCache;
  std::vector<std::shared_ptr<nixfe::Origin>> origins;
  /// MLNIX_DEFER: one pool of deferred lambdas per lowered file.  The `body_index` of a nix.lambda is a
  /// nixfe::BodyIndex (`file j row`) into these.
  std::vector<std::unique_ptr<nixfe::FilePool>> pools;
  unsigned exprCounter = 0;
  std::function<void(const std::string &)> printTrace;

  llvm::DenseMap<void *, Slot> slotMap;
  uint64_t nUpdLayered = 0, nUpdMerged = 0, nUpdBase = 0, nUpdTop = 0; // MLNIX_STATS: `//` as a layer / a flat merge, entries not copied / copied
  uint64_t nDemandMinted = 0; // MLNIX_STATS: lambda bodies minted on first call
  uint64_t nVT[15] = {}; // MLNIX_STATS: instrumented tag writes, including stack values and repeated retyping;
                         // [14] alone counts allocated Value rows, not tag writes
  uint64_t nFrames = 0, nFrameBytes = 0, nFrameSlots = 0; // requested frame storage, excluding arena overhead
  uint64_t nTouchAt[17] = {}, nFramesBySize[17] = {}; // MLNIX_STATS: first touches by slot index (16 = 16 or more), frames by slot count
  static constexpr unsigned kSrcClasses = 5; // 1 nixpkgs lib, 2 nixos modules, 3 pkgs, 4 other
  uint64_t nClsFrames[kSrcClasses] = {}, nClsSlots[kSrcClasses] = {}, nClsTouched[kSrcClasses] = {};
  unsigned srcClassOf(RegionInfo *ri);
  uint64_t nSlotsTouched = 0; // MLNIX_STATS: frame slots that were ever read (a cell made on first touch), of nFrameSlots allocated
  uint64_t nSlotsAssigned = 0, nSlotsNoRead = 0; // MLNIX_STATS: frame cells assigned, and those given to a value with no use at all
  uint64_t nsLower = 0, nsMint = 0; // MLNIX_STATS: time lowering files (analysis of deferred lambdas included) / minting bodies on demand
  llvm::DenseMap<mlir::Region *, RegionInfo *> regionInfos;
  llvm::DenseMap<mlir::Operation *, Value *> constCache;
  void indexRegion(mlir::Region &r);
  void evalConcatStrings(mlir::nix::ConcatStringsOp op, Frame *env, Value &out);
  void evalAttrs(mlir::nix::AttrsOp op, Frame *env, Value &out);
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
