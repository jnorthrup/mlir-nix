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

#include "Nix/AST.h"
#include "Nix/Store.h"
#include "NixDialect/NixDialect.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/OwningOpRef.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/StringMap.h"
#include "llvm/Support/Allocator.h"

#include <functional>
#include <map>
#include <memory>
#include <set>
#include <string>
#include <vector>

namespace nixev {

using Symbol = uint32_t;

class SymbolTable {
public:
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

private:
  llvm::StringMap<Symbol> map;
  std::vector<llvm::StringRef> names;
};

struct Value;
struct Frame;
struct RegionInfo;
class EvalState;

/// Opaque position: an mlir::Location's opaque pointer (or null).
using PosPtr = const void *;

struct Attr {
  Symbol name;
  Value *value;
  PosPtr pos;
};

struct Bindings {
  uint32_t size_ = 0;
  PosPtr pos = nullptr;
  Attr attrs[0];
  size_t size() const { return size_; }
  bool empty() const { return size_ == 0; }
  Attr *begin() { return attrs; }
  Attr *end() { return attrs + size_; }
  const Attr *begin() const { return attrs; }
  const Attr *end() const { return attrs + size_; }
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

struct Value {
  VType type = VType::Null;
  union {
    int64_t integer;
    double fpoint;
    bool boolean;
    struct {
      const char *s;
      size_t len;
      const StringContext *ctx;
    } str;
    struct {
      const char *s;
      size_t len;
    } path;
    Bindings *attrs;
    struct {
      Value **elems;
      size_t size;
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
  std::string_view sv() const { return {str.s, str.len}; }
  std::string_view pathView() const { return {path.s, path.len}; }
};

struct PrimOp {
  std::string name;
  unsigned arity;
  std::function<void(EvalState &, Value **args, Value &out, PosPtr pos)> fn;
};

struct RegionInfo {
  mlir::Region *region;
  unsigned numSlots;
  mlir::Value result;
};

struct Frame {
  Frame *up;
  RegionInfo *info;
  Value *slots[0];
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
  /// Comma-separated stages of the nix pipeline: devirt, fold, dce (or none).
  /// See mlir::nix::SimplifyOptions.  `fold` and `dce` cost more than they
  /// save on real workloads (measured), so only `devirt` is on by default.
  std::string passes = "devirt";
  unsigned maxCallDepth = 10000;
  bool dumpMLIR = false;
  nixfe::Lint lintAbsolutePaths = nixfe::Lint::Ignore, lintShortPaths = nixfe::Lint::Ignore,
              lintUrls = nixfe::Lint::Ignore;
};

//===----------------------------------------------------------------------===//
// EvalState
//===----------------------------------------------------------------------===//

class EvalState {
public:
  EvalState(EvalSettings settings, std::shared_ptr<nixstore::Store> store);
  ~EvalState();

  EvalSettings settings;
  std::shared_ptr<nixstore::Store> store;
  SymbolTable symbols;
  mlir::MLIRContext ctx;
  mlir::OwningOpRef<mlir::ModuleOp> module;
  llvm::BumpPtrAllocator alloc;

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
  Value *allocValue() { return new (alloc.Allocate<Value>()) Value(); }
  Bindings *allocBindings(size_t n);
  Value **allocList(size_t n);
  const char *copyString(std::string_view s);
  const StringContext *makeContext(const NixStringContext &c);

  // -- Value construction ------------------------------------------------
  void mkInt(Value &v, int64_t n) { v.type = VType::Int; v.integer = n; }
  void mkFloat(Value &v, double d) { v.type = VType::Float; v.fpoint = d; }
  void mkBool(Value &v, bool b) { v.type = VType::Bool; v.boolean = b; }
  void mkNull(Value &v) { v.type = VType::Null; }
  void mkString(Value &v, std::string_view s, const NixStringContext &ctx = {});
  void mkPath(Value &v, std::string_view p);
  void mkList(Value &v, size_t n);
  void mkAttrs(Value &v, Bindings *b) { v.type = VType::Attrs; v.attrs = b; }
  void mkApp(Value &v, Value *f, Value *x) { v.type = VType::App; v.app.left = f; v.app.right = x; }
  Value *mkAppValue(Value *f, Value *x) { Value *v = allocValue(); mkApp(*v, f, x); return v; }

  /// Builder for attribute sets.
  class BindingsBuilder {
  public:
    BindingsBuilder(EvalState &st) : st(st) {}
    void insert(Symbol s, Value *v, PosPtr pos = nullptr) { attrs.push_back({s, v, pos}); }
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
  private:
    EvalState &st;
    std::vector<Attr> attrs;
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
  void copyContext(const Value &v, NixStringContext &ctx);

  // -- Calls -----------------------------------------------------------------
  void callFunction(Value &fun, size_t nargs, Value **args, Value &out, PosPtr pos);
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
  /// Parse a source text with a fresh origin (kept alive by the state).
  nixfe::Expr *parseSource(const std::string &text, const std::string &name, const std::string &path,
                           const std::string &baseDir, std::shared_ptr<nixfe::Origin> *originOut = nullptr);
  nixfe::Expr *parseString(nixfe::ExprArena &arena, const std::string &text, const std::string &baseDir,
                           const std::string &originName);
  mlir::nix::ExprOp lowerToMLIR(nixfe::Expr *e, std::shared_ptr<nixfe::Origin> origin,
                                const std::vector<std::string> *scopeNames = nullptr);
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
  void addPrimOp(const std::string &name, unsigned arity,
                 std::function<void(EvalState &, Value **, Value &, PosPtr)> fn);
  void addConstant(const std::string &name, Value *v);
  void createBaseEnv();

  // Interpreter internals (public for builtins).
  /// Call a primop on already-collected arguments, adding the
  /// "while calling the 'X' builtin" trace like upstream.
  void callPrimOp(const PrimOp &op, Value **args, Value &out, PosPtr pos);
  const PrimOp *primOpByKey(llvm::StringRef key);
  /// MLNIX_STATS=1: op histogram of every module lowered, printed at exit.
  llvm::StringMap<size_t> opStats;
  bool statsEnabled = false;
  void printStats();
  /// Constant folding hook of the continent dialects: run primop `key` on
  /// scalar constants; null when it throws or yields a non-scalar.
  mlir::Attribute foldPrimOp(llvm::StringRef key, llvm::ArrayRef<mlir::Attribute> args);
  Value *lookup(Frame *f, mlir::Value v);
  void evalOp(mlir::Operation *op, Frame *env, Value &out);
  RegionInfo *regionInfo(mlir::Region *r);
  Frame *newFrame(RegionInfo *ri, Frame *up);

  unsigned callDepth = 0;
  unsigned tryLevel = 0;
  std::map<std::string, std::string> srcToStore;
  std::map<std::string, Value *> fileEvalCache;
  std::map<std::string, Value *> scopedImportCache;
  std::vector<nixfe::ExprArena *> arenas;
  std::vector<std::shared_ptr<nixfe::Origin>> origins;
  unsigned exprCounter = 0;
  std::function<void(const std::string &)> printTrace;

private:
  llvm::DenseMap<void *, std::pair<RegionInfo *, unsigned>> slotMap;
  llvm::DenseMap<mlir::Region *, RegionInfo *> regionInfos;
  llvm::DenseMap<mlir::Operation *, Value *> constCache;
  void indexRegion(mlir::Region &r);
  void evalConcatStrings(mlir::nix::ConcatStringsOp op, Frame *env, Value &out);
  void evalAttrs(mlir::nix::AttrsOp op, Frame *env, Value &out);
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
