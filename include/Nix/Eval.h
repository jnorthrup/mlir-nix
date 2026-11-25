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

#include "Composite/Patricia.h"
#include "Composite/Table.h"
#include "Composite/Text.h"
#include "Composite/Vocab.h"
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

#include "Nix/StdBind.h"
#include "Nix/Arena.h"
#include "Nix/Os.h"

namespace nixev {
namespace cp = ::composite;

using Symbol = uint32_t;

struct SymbolTable {
  Symbol create(llvm::StringRef s) {
    ++creates; // (counted always: one add; MLNIX_STATS prints it)
    if (Symbol *found = map.find(s.data(), uint32_t(s.size()))) return *found;
    Symbol id = names.size();
    const char *bytes = text.copy(s.data(), uint32_t(s.size())); // the name's bytes, where they never move
    map.set(bytes, uint32_t(s.size()), id, [bytes] { return bytes; });
    names.append(llvm::StringRef(bytes, s.size()));
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

  composite::TextTable<Symbol> map; // a name's symbol (Composite/Table.h): its bytes' hash, one probe, one compare
  composite::Bump text;             // the names' bytes
  composite::MutableSeries<llvm::StringRef> names;
  composite::MutableSeries<uint64_t> prefix; // per symbol: its first eight bytes as one word (less)
  uint64_t creates = 0;
};

struct Value;
struct Frame;
/// A list buffer with room on a side, made by `++` (EvalState::concatLists).  [lo, hi) is claimed: every list that reads the buffer
/// sees cells inside it, and only those cells are ever written.  A `++` whose larger side is a list that starts at lo (or ends at
/// hi) writes the smaller side into the room below lo (above hi) and widens the claim: `[ x ] ++ acc` and `acc ++ [ x ]` in a fold
/// cost the new cells, not a copy of acc.  An older list that touched the edge is still a view of cells that never change.
struct ListExtent {
  Value **begin, **lo, **hi, **end;
};
struct RegionInfo;
struct Node;
struct EvalState;

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
  uint32_t size_ = 0;
  PosPtr pos = nullptr;
  Attr attrs[0];

  static inline uint64_t merged = 0, mergedCells = 0; // MLNIX_STATS: flat sets made by mergeBindings, and their cells

  /// The rows, in name order: the array itself.  (A `//` merges into one such array: EvalState::updateAttrs.)
  auto rows() const { return cp::series(attrs, size_); }
  const Attr *begin() const { return attrs; }
  const Attr *end() const { return attrs + size_; }
  size_t size() const { return size_; }
  bool empty() const { return size_ == 0; }
  const Attr *get(Symbol s) const;
  /// get(), with a guess of the row: the row the asker found the name at last time, in a set of the same layout (62% of the selects of
  /// a NixOS evaluation hit the layout their site saw last).  A right guess is one row read instead of a search; a wrong one costs a
  /// compare, and the search's answer becomes the next guess.
  const Attr *getGuess(Symbol s, uint32_t &guess) const {
    if (guess < size_ && attrs[guess].name == s) return &attrs[guess];
    const Attr *r = get(s);
    if (r) guess = uint32_t(r - attrs);
    return r;
  }
  /// Attributes sorted by name (string order).
  composite::Frozen<const Attr *> lexicographicOrder(const SymbolTable &st) const;
};

/// String context: the set of encoded elements
///   "/nix/store/..."          opaque path
///   "=/nix/store/x.drv"       derivation with all outputs (drvDeep)
///   "!out!/nix/store/x.drv"   built output
/// as a string being made gathers them: C strings that outlive the set (a string's own context's elements, arena copies made with
/// copyString, literals), held where they lie and appended as they come, with no node and no copy per element.  Read, it is a set: sorted
/// by bytes, each element once, as the first read after an append leaves it (Rows' sortRows, then the repeats dropped).
struct NixStringContext {
  NixStringContext() = default;
  explicit NixStringContext(const char *e) { insert(e); }
  void insert(const char *e) {
    normal = rows.empty() || (normal && lessBytes(rows.back(), e));
    rows.append(e);
  }
  template <class It> void insert(It b, It e) {
    for (; b != e; ++b) insert(*b);
  }
  bool empty() const { return rows.empty(); }
  uint32_t size() const { settle(); return rows.size(); }
  const char *const *begin() const { settle(); return rows.data(); }
  const char *const *end() const { settle(); return rows.data() + rows.size(); }
  static bool lessBytes(const char *a, const char *b) {
    while (*a && *a == *b) ++a, ++b;
    return (unsigned char)*a < (unsigned char)*b;
  }
  void settle() const;
  mutable composite::MutableSeries<const char *> rows;
  mutable bool normal = true; // sorted, each element once
};
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

/// JSON being written: one growing run of bytes (a MutableSeries), strings escaped into it a run at a time, no stream and no string a value.
struct JsonOut {
  composite::MutableSeries<char> bytes;
  void put(std::string_view s) { bytes.appendAll(s.data(), uint32_t(s.size())); }
  void put(char c) { bytes.append(c); }
  void putInt(int64_t x);
  /// `s` as a JSON string: quoted, and escaped as Nix escapes (\" \\ \b \f \n \r \t, \u00xx for the other control bytes).
  void putString(std::string_view s);
  std::string_view view() const { return {bytes.data(), bytes.size()}; }
};


/// Failed: a thunk whose evaluation threw an evaluation error.  Forcing it again throws a fresh copy of that error as it stands then (the
/// first throw may still be gathering traces on its way out), not the evaluation again: Nix 2.34's memoised errors.  The tags up to
/// Blackhole are the cells that are not values yet (isThunk).
/// AttrApp: `f name value` as mapAttrs and zipAttrsWith make it for each attribute, one cell holding f (app.left), the value (app.right) and
/// the name's symbol (aux).  The name's string and the application of f to it are made when the cell is forced, not for every attribute
/// (three cells an attribute were made before, most of them never read).
enum class VType : uint8_t {
  Thunk, App, AttrApp, Failed, Blackhole, Int, Float, Bool, Null, String, Path, Attrs, List,
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
      ListExtent *ext; // the buffer's room, when `++` made it with some (null otherwise): see ListExtent
    } list;
    struct {
      Node *node; // Thunk: the record of the op it evaluates; Lambda: the record of the lambda op (which keeps its body, once called)
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


/// A primop is a function pointer: a lambda without captures.  A registering loop (type predicates, arithmetic, bit operations, rounding)
/// makes one per constant, the constant a template parameter (K in Builtins.cpp), not a capture: there is no closure to call through.
using PrimFn = void (*)(EvalState &, Value **args, Value &out, PosPtr pos);
struct PrimOp {
  composite::Text name;
  unsigned arity;
  PrimFn fn;
  void call(EvalState &st, Value **args, Value &out, PosPtr pos) const { fn(st, args, out, pos); }
};

struct RegionInfo {
  mlir::Region *region;
  unsigned numSlots;
  mlir::Value result;
  Node *resultNode = nullptr; // the record of `result`
  /// For a lambda body: the symbols of the lambda's formals (made at its first call, by EvalState::callLambdaIn) and the op
  /// they were made from.
  const Symbol *formalSyms = nullptr;
  mlir::Operation *formalsOf = nullptr;
  /// The lambda's formals as its op states them, read once when the body is indexed (a call reads these, not the op's attributes): whether
  /// it has any, how many, which have defaults (the attribute's own uniqued storage), and whether `...` accepts the rest.
  uint8_t hasFormals = 0, ellipsis = 0;
  uint32_t nFormals = 0;
  const bool *formalDefaults = nullptr;
  uint8_t stackable = 2; // 1 when no op of the body can make a thunk or closure over the frame, so a call runs on a stack frame; 2 unclassified
  PosPtr selPos = nullptr; // where the recognized selector's `if` is: the position a non-Boolean condition is reported at
  uint8_t selShape = 0; // 0 unclassified, 1 none, 2 `c: x: if c then [x] else []`, 3 `c: x: if c then x else {}` (EvalState::selectorShape)
  /// MLNIX_STATS: 1 when son says a frame of this lambda body is unreachable once its call returns: the body makes no closure, and
  /// every value of it a lazy use makes a thunk over the frame of is forced on every path that returns (son::forcedOnReturn).
  uint8_t sonDead = 0;
  uint8_t sonWhy = 0;        // MLNIX_STATS: why son keeps the frame (sonDiesAtReturn): 0 it does not, 1 closure, 2 path, 3 callee, 4 escape
  mlir::Operation *sonWhyAt = nullptr; // MLNIX_STATS: the op whose use decides it
  /// MLNIX_STATS: what this region's sea of nodes holds.  nOps its body's ops; nThunks its cells that start as
  /// thunks (finer-grain deferral would mint those, so they are its rows); nEvals its ops' evals (a region called
  /// N times counts N times); everRan the distinct ops that ran, one bit an op, opIdx the op -> bit.
  uint32_t nOps = 0, nThunks = 0;
  uint64_t nEvals = 0;
  composite::WordTable<uint32_t> opIdx; // by the op's address
  composite::MutableSeries<uint64_t> everRan{};
};

struct Frame {
  /// The enclosing frame.  When a frame dies is son's to say (son.release, sonDead), not the frame's: the run-time capture bit and the recycler
  /// it fed (MLNIX_RECYCLE: -2 to -3% peak memory, +1 to +4% time on Kali, 77de09c:docs/FRAME-BYTES.md) are gone.
  uintptr_t upBits;
  RegionInfo *info;
  Value *slots[0];
  Frame *up() const { return reinterpret_cast<Frame *>(upBits); }
};

/// What the dialect promotes a value to (NixDialect::promotionOf): which cell it gets, if any, and what may read it back.
using Promotion = mlir::nix::NixDialect::Promotion;

inline constexpr unsigned kNoSlot = ~0u;
/// A set literal as its evaluation writes it, worked out at its first evaluation and kept in its node: its rows in name order (the first
/// of equal names wins), each the operand that holds its value, its symbol and its position.  A literal's names, their symbols and its
/// positions never change, so no later evaluation sorts, interns or reads the op's properties.
struct AttrsShape {
  uint32_t m;
  struct Row { uint32_t operand; Symbol sym; uint32_t pos; } rows[0];
};
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
  uint8_t flags = 0;        // Select: kDefault; Attrs: kDynamic; ConcatStrings: kForceString (made by nix.interpolate)
  unsigned idx;             // kNoSlot: the value has no frame cell (it is evaluated in place, made by its one use, or fixed)
  uint32_t nOperands = 0;
  uint32_t nDyn = 0;        // Select and HasAttr: the dynamic keys after the base; Attrs: the static values, first
  RegionInfo *ri;
  Value *fixed = nullptr;   // a literal or a builtin: its one cell, the same in every frame, made at its first touch
  Node **operands = nullptr; // the op's operands, in order
  mlir::Operation *def;     // the op that defines the value; a block argument's lambda (kind Arg)
  union {
    const PrimOp *prim = nullptr;  // Prim: what the op runs
    uint32_t rowGuess;             // Select, HasAttr, Formal: the row its (first) name was found at last (Bindings::getGuess)
    const AttrsShape *attrsShape;  // Attrs: its rows, once worked out (EvalState::attrsShapeOf)
    RegionInfo *body;              // Lambda: its body's region, once called (EvalState::bodyOfNode)
  };
  EvalFn eval = nullptr;    // what evaluating the op is
  static constexpr uint8_t kDefault = 1, kDynamic = 1, kForceString = 1;
  bool inPlace() const { return promo == Promotion::InPlace; }
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
  composite::Text msg;
};

struct EvalError : std::exception {
  composite::Text msg;
  PosPtr pos = nullptr;
  composite::MutableSeries<Trace> traces;
  EvalError(composite::Text m, PosPtr p = nullptr) : msg(std::move(m)), pos(p) {}
  /// A message that is a view of bytes: copied.
  template <class V> requires(composite::ByteView<V> && !composite::same<V, composite::Text>) EvalError(const V &m, PosPtr p = nullptr) : msg(m), pos(p) {}
  const char *what() const noexcept override { return msg.c_str(); }
  EvalError &addTrace(PosPtr p, composite::Text m) & {
    traces.append({p, std::move(m)});
    return *this;
  }
  EvalError &&addTrace(PosPtr p, composite::Text m) && { // `throw EvalError(...).addTrace(...)`: the temporary is moved into the exception
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
  composite::Text prefix, path;
};

struct EvalSettings {
  composite::MutableSeries<SearchPathElem> nixPath;
  composite::Text currentSystem;
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
  composite::Text pipeline = "nix-prims";
  /// Sea-of-nodes schedule (MLNIX_DEFER): mint no lambda body at lowering
  /// time; the op carries a pool row and the body is generated on first call.
  bool deferBodies = false;
  unsigned maxCallDepth = 10000;
  nixfe::Lint lintAbsolutePaths = nixfe::Lint::Ignore, lintShortPaths = nixfe::Lint::Ignore,
              lintUrls = nixfe::Lint::Ignore;
};

//===----------------------------------------------------------------------===//
// EvalState
//===----------------------------------------------------------------------===//

/// The arguments the command line gives the function it calls (--arg, --argstr), by name in byte order; the names are the state's arena copies.
using AutoArgs = composite::Patricia<Value *>;

struct EvalState {
  EvalState(EvalSettings settings, nixstore::Store *store); // the store is lent: it outlives the state
  ~EvalState();

  EvalSettings settings;
  nixstore::Store *store;
  SymbolTable symbols;
  mlir::MLIRContext ctx;
  mlir::OwningOpRef<mlir::ModuleOp> module;
  /// The optimization pipeline (text: settings.pipeline / MLNIX_PIPELINE), built on first use.
  composite::Own<mlir::PassManager> optimizer;
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
  composite::TextTable<Value *> baseEnv; // by name (Composite/Table.h), the names copied into baseEnvNames
  composite::Bump baseEnvNames;
  Bindings *builtinsAttrs = nullptr;

  // -- Allocation --------------------------------------------------------
  Value *allocValue() {
    if (statsEnabled) ++nValues;
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
  const AttrsShape *attrsShapeOf(mlir::nix::AttrsOp op);
  cp::MutableSeries<PosPtr> attributePositions{nullptr};
  composite::WordTable<PosIdx> dynamicPositions; // by the position word's address (Composite/Table.h)
  composite::WordTable<PosIdx> attrPositionBases; // by the op's address

  // -- Value construction ------------------------------------------------
  void mkInt(Value &v, int64_t n) { v.type = VType::Int; v.integer = n; }
  void mkFloat(Value &v, double d) { v.type = VType::Float; v.fpoint = d; }
  void mkBool(Value &v, bool b) { v.type = VType::Bool; v.boolean = b; }
  void mkNull(Value &v) { v.type = VType::Null; }
  void mkString(Value &v, std::string_view s, const NixStringContext &ctx = {});
  /// A store path that is its own context (a copied source, a fixed output, a store path read back): one arena copy is both the string's
  /// bytes and its context's element.
  void mkStoreString(Value &v, std::string_view path);
  /// A string literal: a window on the bytes the lowered op already holds (a Name: a slice of a mapped input or a never-freed arena), no copy.
  void mkStringWindow(Value &v, llvm::StringRef r) {
    std::string_view s(r.data(), r.size());
    if (s.size() > UINT32_MAX) throw EvalError("string of 4 GiB or more");
    v.type = VType::String; v.str.s = s.data(); v.aux = static_cast<uint32_t>(s.size()); v.str.ctx = nullptr;
  }
  /// A string made of pieces: the algebra is hollowed into lowered/nixeval/StringOps.mlir (nixev_ts_concat, declared in Eval.cpp).
  void mkPath(Value &v, std::string_view p);
  void mkList(Value &v, size_t n);
  /// `l ++ r` into out: into the room of r's or l's buffer when the other side fits there (ListExtent), else a new buffer, with
  /// room on the smaller side when the result has 8 or more cells.
  void concatLists(Value &l, Value &r, Value &out);
  /// A list drained from a series of Value * (a Series, a vector): the one fill loop, the α of the caller inlined.
  template <class S> requires requires(const S &s, Value **o) { s.size(); cp::drain(s, o); }
  void mkList(Value &v, const S &s) {
    mkList(v, size_t(s.size()));
    cp::drain(s, v.list.elems);
  }
  void mkAttrs(Value &v, Bindings *b) { v.type = VType::Attrs; v.attrs = b; }
  void mkApp(Value &v, Value *f, Value *x) { v.type = VType::App; v.app.left = f; v.app.right = x; }
  Value *mkAppValue(Value *f, Value *x) { Value *v = allocValue(); mkApp(*v, f, x); return v; }
  /// `f name x`, applied when forced (VType::AttrApp).
  Value *mkAttrAppValue(Value *f, Symbol name, Value *x) {
    Value *v = allocValue();
    v->type = VType::AttrApp;
    v->aux = name;
    v->app.left = f;
    v->app.right = x;
    return v;
  }
  Value *newString(std::string_view s, const NixStringContext &ctx = {}) { Value *v = allocValue(); mkString(*v, s, ctx); return v; }
  /// A string on bytes that stay where they are (a name in the symbol table, a piece of an arena string): a window, nothing copied.
  Value *newStringWindow(llvm::StringRef r) { Value *v = allocValue(); mkStringWindow(*v, r); return v; }
  /// A cell shared by every value that needs it, never written: null, and the strings of no or one byte without context (what
  /// `split` and `match` make for each piece between tokens and each group that took no part: 20% of the cells of sumo.full's
  /// kif.nix).  Neither has an identity Nix can see: a string and null print and compare by content (a list and a function do not:
  /// they keep their own cells).
  Value *sharedNull() { return &sharedNullCell; }
  Value *sharedShortString(std::string_view s) {
    if (s.size() > 1) return nullptr;
    unsigned i = s.empty() ? 0 : 1 + (unsigned char)s[0];
    Value &v = sharedShortCells[i];
    if (i) shortBytes[2 * i] = char(i - 1);
    if (v.type != VType::String) mkStringWindow(v, llvm::StringRef(&shortBytes[2 * i], s.size()));
    return &v;
  }

  /// Builder for attribute sets.
  /// A set being built: its rows go where the set will live.  Given the most rows it can get (`room`), the builder writes them into an
  /// arena block of that size, and finish() sorts them there: no heap and no copy.  Without one, up to twelve rows stay in the builder and
  /// are copied once into a block of their size; more go to a MutableSeries and are copied at finish.
  struct BindingsBuilder {
    explicit BindingsBuilder(EvalState &st, size_t room = 0) : st(st) {
      if (room > kInline) {
        block = st.allocBindings(room);
        rows = block->attrs;
        cap = uint32_t(room);
      }
    }
    BindingsBuilder(const BindingsBuilder &) = delete; // `rows` may point into the builder itself
    BindingsBuilder &operator=(const BindingsBuilder &) = delete;
    void insertIndexed(Symbol s, Value *v, PosIdx pos) {
      if (n < cap) [[likely]] {
        rows[n++] = {s, pos, v};
        return;
      }
      overflow({s, pos, v});
    }
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
    Bindings *finish(); // sorts in name order; of rows with one name, the first inserted stays
    size_t size() const { return n; }
    static constexpr uint32_t kInline = 12;
    EvalState &st;
    Attr inl[kInline];
    Attr *rows = inl;       // where the next row goes while there is room: `inl`, or the arena block `room` asked for
    uint32_t n = 0, cap = kInline;
    Bindings *block = nullptr;
    composite::MutableSeries<Attr> more; // the rows, once more came than there was room for
    void overflow(Attr a);
  };

  // -- Forcing -------------------------------------------------------------
  /// A value is already one: the common case is a test, here; a cell that is not a value yet (or any cell, in an MLNIX_STATS run) is
  /// forced out of line, where the exception handling and the census live.
  void forceValue(Value &v, PosPtr pos = nullptr) {
    if (v.isThunk() || statsEnabled) forceCell(v, pos);
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
  void callFunction(Value &fun, size_t nargs, Value **args, Value &out, PosPtr pos);
  void callFunction(Value &fun, Value &arg, Value &out, PosPtr pos) {
    Value *a = &arg;
    callFunction(fun, 1, &a, out, pos);
  }
  void autoCallFunction(const AutoArgs &autoArgs, Value &fun, Value &out);

  // -- Coercions -------------------------------------------------------------
  composite::Text coerceToString(Value &v, NixStringContext &ctx, bool coerceMore, bool copyToStore,
                             PosPtr pos = nullptr, std::string_view errorCtx = "",
                             bool canonicalizePath = true);
  // The same coercion as a window: a string, and a set's __toString result or outPath, is its own bytes (nothing copied); anything else is made
  // in `scratch`, which the window views.
  // With `own`, a string (and a set's __toString result or outPath) hands its own context back through it instead of copying it into ctx.
  composite::Chars coerceToWindow(Value &v, NixStringContext &ctx, bool coerceMore, bool copyToStore, PosPtr pos,
                                       std::string_view errorCtx, composite::Text &scratch, bool canonicalizePath = true,
                                       const StringContext **own = nullptr);
  composite::Text coerceToPath(Value &v, NixStringContext &ctx, PosPtr pos, std::string_view errorCtx = "");
  composite::Text copyPathToStore(NixStringContext &ctx, std::string_view path);
  bool isDerivation(Value &v);
  composite::Maybe<composite::Text> tryAttrsToString(Value &v, NixStringContext &ctx, bool coerceMore, bool copyToStore);

  // -- Comparison ------------------------------------------------------------
  bool eqValues(Value &a, Value &b, PosPtr pos);
  bool lessThan(Value &a, Value &b, PosPtr pos);

  // -- Types ----------------------------------------------------------------
  static const char *showType(const Value &v);
  static const char *typeOf(const Value &v);

  // -- Errors -----------------------------------------------------------------
  [[noreturn]] void throwTypeError(const char *expected, Value &v, PosPtr pos, std::string_view ctx = "");
  void warn(std::string_view msg);
  composite::Text showPos(PosPtr pos) const;

  // -- Printing ---------------------------------------------------------------
  void printValue(composite::Text &out, Value &v, composite::WordTable<char> *seen, size_t depth = 0); // seen: a set by address
  composite::Text printValueForTrace(Value &v);
  void printValueAsJSON(JsonOut &out, Value &v, bool strict, NixStringContext &ctx,
                        bool copyToStore = true, PosPtr pos = nullptr);
  void printValueAsXML(composite::Text &out, Value &v, bool strict, bool location, NixStringContext &ctx);

  // -- Parsing / evaluation entry points ---------------------------------------
  /// Parse+lower+evaluate a file (cached).  Result is a lazy value.
  Value *evalFile(std::string_view path);
  /// Parse+lower a string; returns the expression value (lazy).
  Value *evalString(std::string_view text, std::string_view baseDir,
                    std::string_view originName = "«string»");
  /// Parse only.
  nixfe::ParseOptions parseOptions();
  /// Parse a source into the module (kept alive by the state, as its origin is).
  mlir::nix::ExprOp lowerToMLIR(nixfe::Origin *origin, const composite::MutableSeries<composite::Text> *scopeNames = nullptr);
  Value *evalExprOp(mlir::nix::ExprOp op);
  /// Load all nix.expr ops of an MLIR module (from mlnix compile) and
  /// evaluate the one named `sym` (or the first).
  Value *evalMLIRFile(std::string_view path, std::string_view sym);

  composite::Text resolveExprPath(std::string_view path);
  composite::Text findFile(Value &searchPath, std::string_view name, PosPtr pos);
  composite::Text realisePath(std::string_view path, PosPtr pos);
  /// Ensure the store paths in `ctx` are realised (import-from-derivation).
  void realiseContext(const NixStringContext &ctx, PosPtr pos);

  // -- Builtins -----------------------------------------------------------------
  /// The arguments of a primop call are gathered in a fixed array of this many cells (checked once, when a primop is registered).
  static constexpr unsigned kMaxPrimArity = 8;
  /// A primop under its base-environment key.  Its arity is the one NixPrims.irdl.mlir declares for the key; a primop not declared there is fatal.
  void addPrimOp(std::string_view name, PrimFn fn);
  /// For a primop that captures (a registering loop's parameter).
  void addConstant(std::string_view name, Value *v);
  void registerPrimOp(std::string_view name, PrimOp *p);
  void createBaseEnv();

  // Interpreter internals (public for builtins).
  /// Call a primop on already-collected arguments, adding the
  /// "while calling the 'X' builtin" trace like upstream.
  void callPrimOp(const PrimOp &op, Value **args, Value &out, PosPtr pos);
  /// MLNIX_CHECK_KINDS=1: `out`, made by `op`, has the kind op's result type fixes (an internal error otherwise).
  void checkResultKind(mlir::Operation *op, const Value &out);
  /// The frame a primop's error gets: "while calling the 'name' builtin" (not for throw, abort and addErrorContext).
  void tracePrimOp(const PrimOp &op, EvalError &e, PosPtr pos);
  const PrimOp *primOpByKey(llvm::StringRef key);
  /// The primop an IRDL-defined continent op stands for (cached per op name).
  const PrimOp *primFor(mlir::Operation *op);
  composite::WordTable<const PrimOp *> primForOp; // by the op name's address
  /// MLNIX_STATS: a count by op kind, keyed by the kind's OperationName (one per name in a context, so a word, and no name is hashed).
  struct OpCount {
    llvm::StringRef name;
    uint64_t n[3]; // the third: sonGapByOp's
  };
  using OpCounts = composite::WordTable<OpCount>;
  static OpCount &countOf(OpCounts &t, mlir::OperationName kind) {
    OpCount &c = t.at(uint64_t(uintptr_t(kind.getAsOpaquePointer())));
    c.name = kind.getStringRef();
    return c;
  }
  /// MLNIX_STATS=1: op histogram of every module lowered, printed at exit.
  OpCounts opStats;
  bool statsEnabled = false;

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
    uint64_t k = uint64_t(uintptr_t(a.getAsOpaquePointer()));
    if (Symbol *s = attrSymbols.find(k)) return *s;
    Symbol s = symbols.create(a.getValue());
    attrSymbols.insert(k, s);
    return s;
  }
  composite::WordTable<Symbol> attrSymbols; // by the attribute's address
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
  /// The same for a consumer that forces the cell next: one it makes is evaluated now, not a thunk (a cell already there is as it is).
  Value *lookupForced(Frame *f, Node *v) { return lookupImpl(f, v, true); }
  /// The same from the SSA value: one hash probe to find its record (the primop model, the cold paths).
  Value *lookup(Frame *f, mlir::Value v) { return lookupImpl(f, nodeOfValue(v), false); }
  Node *nodeOfValue(mlir::Value v) {
    Node *n = nodeOf(v.getAsOpaquePointer());
    if (!n) unindexed();
    return n;
  }
  [[noreturn]] static void unindexed();
  void evalOp(Node *n, Frame *env, Value &out) {
    if (statsEnabled) [[unlikely]] return evalOpCounted(n, env, out);
    n->eval(*this, n, env, out);
  }
  void statEval(Node *n, Frame *env);
  /// MLNIX_STATS: evalOp with the census.
  void evalOpCounted(Node *n, Frame *env, Value &out);
  RegionInfo *regionInfo(mlir::Region *r);
  /// A frame of `ri`'s body: its slots empty.  The ordinary case (no census) is a bump of the arena, here; the census's out of line.
  Frame *newFrame(RegionInfo *ri, Frame *up) {
    if (statsEnabled) [[unlikely]] return newFrameSlow(ri, up);
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
  // By path, in crit-bit tries (Composite/Patricia.h): the keys share long prefixes, and are copied into the arena once, when new.
  composite::Patricia<const char *> srcToStore; // a source path's store path, an arena string: the context element of every copy
  composite::Patricia<Value *> fileEvalCache;
  composite::Patricia<Value *> scopedImportCache; // by the file's path and the scope's names
  composite::MutableSeries<nixfe::Origin *> origins; // the files and strings lowered (an origin is kept for the run: nixfe::newOrigin)
  /// MLNIX_DEFER: one pool of deferred lambdas per lowered file.  The `body_index` of a nix.lambda is a
  /// nixfe::BodyIndex (`file j row`) into these.
  composite::MutableSeries<composite::Own<nixfe::FilePool>> pools; // indexed by FilePool::file; a slot is empty while its file is only prelowered
  composite::Atomic<uint32_t> nextPoolId{0}; // the helpers number their files' pools too
  void installPool(composite::Own<nixfe::FilePool> p);
  unsigned exprCounter = 0;

  /// MLNIX_PRELOWER=1 with MLNIX_PREFETCH=auto (the files a previous run of this invocation evaluated; the first run records them), or MLNIX_PRELOWER_LIST=file (such a list): a helper thread lexes, parses
  /// and builds the IR of those files ahead of the evaluator, which adopts each finished file when evalFile asks for it.  The helper does
  /// no evaluation and no optimization (the prim folder calls back into the evaluator), only genExpr into a module of its own.
  struct Indexer;
  struct Prelowered {
    nixfe::Origin *origin = nullptr;
    mlir::OwningOpRef<mlir::ModuleOp> mod;
    mlir::nix::ExprOp op;
    composite::Own<nixfe::FilePool> pool;
    bool done = false, ok = false;
    bool optimized = false; // devirtualized by the helper (the demand schedule's whole pipeline): adoption runs no pass
    composite::Own<Indexer> index; // the file's body indexed by the helper: adoption installs its regions and captures
  };
  struct PrelowerState {
    nixsys::Lock m;
    nixsys::Signal cv; // a path queued (a helper waits for one), a file lowered (the evaluator waits for it), or the stop
    composite::Patricia<Prelowered *> byPath; // the file's lowering, by path (the paths' bytes in pathBytes)
    composite::Bump pathBytes;
    composite::MutableSeries<composite::Own<Prelowered>> lowered; // every Prelowered, owned here until the state goes
    composite::MutableSeries<composite::Text> queue; // paths, appended; the helpers drain them from `head` (a cell leaves, an empty one stays)
    uint32_t head = 0;
    composite::TextTable<char> baseNames; // a set: the base environment's names when the helpers started (they read it, nothing writes it)
    nixfe::ParseOptions po;
    composite::MutableSeries<nixsys::Thread> workers;
    bool stop = false;
    uint64_t adopted = 0, waited = 0, missed = 0;
  };
  composite::Own<PrelowerState> pre;
  void startPrelower();
  void prelowerLoop();
  mlir::nix::ExprOp takePrelowered(std::string_view resolved);
  Prelowered *newPrelowered(std::string_view path);
  void (*printTrace)(std::string_view) = nullptr; // builtins.trace's line

  // The record of each SSA value, by the value's address: the evaluator reads the records an op's record points at and never asks; the
  // primop model and the cold paths ask here, through a direct-mapped cache in front of the hash map.  A value's address indexed again
  // (an op erased by a pass and its storage reused) gets a new record, and the map and the cache are rewritten, so neither holds a stale one.
  composite::WordTable<Node *> nodeMap; // by the value's address
  struct NodeCacheEntry { void *key = nullptr; Node *node = nullptr; };
  static constexpr size_t kNodeCache = 8192;
  NodeCacheEntry nodeCache[kNodeCache];
  Node *nodeOf(void *key) {
    NodeCacheEntry &e = nodeCache[(reinterpret_cast<uintptr_t>(key) >> 4) & (kNodeCache - 1)];
    if (e.key == key) return e.node;
    Node **found = nodeMap.find(uint64_t(uintptr_t(key)));
    if (!found) return nullptr;
    e = {key, *found};
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
    composite::WordTable<Node *> blockNodes; // by the value's address: the values of the blocks being indexed
    unsigned depth = 0;
    composite::MutableSeries<composite::Join<void *, Node *>> captures;         // a helper's: for the evaluator's map of every value
    composite::MutableSeries<composite::Join<mlir::Region *, RegionInfo *>> regions; // a helper's: for regionInfos
    Indexer(EvalState &st, bool helper) : st(st), helper(helper) {}
    void *allocate(size_t n, size_t a) { return helper ? arena.Allocate(n, llvm::Align(a)) : st.alloc.Allocate(n, a); }
    void index(mlir::Region &r);
  };
  Indexer indexer{*this, false};
  composite::MutableSeries<composite::Own<Indexer>> helperIndexers; // adopted with their files: their arenas hold those files' nodes
  void setNode(void *key, Node *n) {
    nodeMap.at(uint64_t(uintptr_t(key))) = n;
    NodeCacheEntry &e = nodeCache[(reinterpret_cast<uintptr_t>(key) >> 4) & (kNodeCache - 1)];
    if (e.key == key) e.node = n;
  }
  uint64_t nUpdLayered = 0, nUpdMerged = 0, nUpdBase = 0, nUpdTop = 0; // MLNIX_STATS: `//` as a layer / a flat merge, entries not copied / copied
  uint64_t nDemandMinted = 0; // MLNIX_STATS: lambda bodies minted on first call
  uint64_t nValues = 0; // MLNIX_STATS: Value cells allocated
  uint64_t nFrames = 0, nFrameBytes = 0, nFrameSlots = 0; // requested frame storage, excluding arena overhead
  uint64_t nMaskBytes = 0, nLayerBytes = 0, nMergeBytes = 0, nCtxBytes = 0, nFormalBytes = 0; // MLNIX_STATS: arena bytes the by-use line did not name before
  OpCounts evalsByKind; // MLNIX_STATS: evalOp calls by op kind
  uint64_t nListExtended = 0; // MLNIX_STATS: cells `++` wrote into a buffer's room (ListExtent) instead of a copy
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
  void statCell(Frame *f, Value *nv);
  uint64_t nEager = 0;   // MLNIX_STATS
  Value sharedNullCell;            // type Null from construction (Value())
  Value sharedShortCells[257];     // "" and each byte, made on first use
  char shortBytes[2 * 257] = {};   // their bytes: one, then a NUL
  void markCaptured(Frame *f);
  void markPinned(Frame *f);
  void statUnref(Frame *f);
  void statReturn(Frame *f);
  /// The region of a lambda's body, from a direct-mapped cache keyed by the op's address: a hit is a load and a compare, where the lookup
  /// was a read of the op's deferred-body attribute and a hash probe on every call (3.7% of the CPU of a NixOS evaluation on Kali;
  /// 77de09c:docs/SELECT-AND-LOOKUP.md has the A/B against a build without it).  Sound because an entry is made only for a lambda that is
  /// being called, and nothing erases a called op (the passes that erase run on a body when it is lowered or minted, before any call of it).
  RegionInfo *infoOf(mlir::nix::LambdaOp lam) {
    const void *k = lam.getOperation();
    InfoSlot &e = infoCache[(reinterpret_cast<uintptr_t>(k) >> 4) & (kInfoCache - 1)];
    if (e.op == k) return e.ri;
    RegionInfo *ri = infoOfSlow(lam);
    e = {k, ri};
    return ri;
  }
  RegionInfo *infoOfSlow(mlir::nix::LambdaOp lam);
  /// The body of the lambda whose node a closure holds: found once (infoOf: the body is minted at the first call of a deferred lambda) and
  /// kept in the node, so a call reads one word where it probed a cache keyed by the op.
  RegionInfo *bodyOfNode(Node *lambda) {
    if (RegionInfo *ri = lambda->body) return ri;
    return lambda->body = infoOf(mlir::cast<mlir::nix::LambdaOp>(lambda->def));
  }
  static constexpr size_t kInfoCache = 4096;
  struct InfoSlot { const void *op = nullptr; RegionInfo *ri = nullptr; };
  InfoSlot infoCache[kInfoCache];
  void callLambdaIn(Value &fun, RegionInfo *ri, Value *arg, Value &out, PosPtr pos);
  void applySelector(unsigned shape, RegionInfo *ri, Value **a, Value &dest, PosPtr pos);
  composite::TextTable<Value> matchMemo; // builtins.match's answers, keyed by the pattern's length and bytes, then the input's
  composite::Text matchKey;              // the key of the call at hand, built here so a lookup allocates nothing
  composite::Bump keyText;               // the keys of matchMemo
  // MLNIX_STATS: frames at their call's return -- by son's account dead (RegionInfo::sonDead), by the run's dead (no closure over
  // them and every thunk over them, projections too, forced), and son's account wrong (dead by son, not by the run: must be 0)
  uint64_t nSonDead = 0, nSonDeadBytes = 0, nRunDead = 0, nRunDeadBytes = 0, nSonWrong = 0, nReturns = 0, nReturnBytes = 0;
  uint64_t nSonDeadBodies = 0, nBodies = 0; // lambda bodies indexed, and those son calls dead at return
  uint64_t nSonGap[8] = {};                  // returns dead by the run and not by son, by RegionInfo::sonWhy
  OpCounts sonGapByOp;                       // the same, by the op whose lazy use decides (n[0] path, n[1] callee, n[2] passed on)
  uint64_t nSelectorCalls = 0; // MLNIX_STATS: saturated calls of a recognized selector, made with no frame and no closure
  unsigned selectorShape(mlir::nix::LambdaOp outerLam, RegionInfo *outer);
  uint64_t nStackCells = 0; // MLNIX_STATS: curried-call intermediates held by value instead of in a heap cell
  uint64_t nEmptyShared = 0; // MLNIX_STATS: empty attribute sets that were the shared constant instead of a fresh 16-byte cell
  uint64_t nsLower = 0, nsMint = 0; // MLNIX_STATS: time lowering files (analysis of deferred lambdas included) / minting bodies on demand
  composite::WordTable<RegionInfo *> regionInfos; // by the region's address
  void indexRegion(mlir::Region &r);
  void evalConcatStrings(Node *n, Frame *env, Value &out);
  void evalAttrsDynamic(Node *n, Frame *env, Value &out);
  [[noreturn]] void notAFunction(Value &cur, PosPtr pos); // cold: builds the message
  void evalAttrs(Node *n, Frame *env, Value &out);
  RegionInfo *mintLambda(nixfe::FilePool &p, uint32_t row);
  RegionInfo *bodyOf(nixfe::BodyIndex idx);
};

/// Render an error the way Nix does ("error: ..." with source excerpt).
composite::Text formatError(EvalState *state, const EvalError &e);
composite::Text formatParseError(const nixfe::ParseError &e, const char *kind = "error");

/// Register all builtins (Builtins.cpp).
void registerBuiltins(EvalState &state);
/// Parse JSON into a value (FromJSON in Builtins.cpp).
void parseJSON(EvalState &state, std::string_view json, Value &v);

/// Run `fn` on a thread with a large stack (deep recursion in the evaluator); the thread is joined before this returns.
int runWithLargeStack(composite::Fn<int()> fn);

/// Attach the evaluator's external `NixEvalOpInterface` models to the ops of
/// the Nix dialect family in `ctx` (EvalModels.cpp).
void registerEvalModels(mlir::MLIRContext &ctx);

} // namespace nixev

#endif
