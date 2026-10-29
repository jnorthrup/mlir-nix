//===- ScalarJIT.cpp - Nix sea of nodes -> typed MLIR -> LLVM -> native -------===//
#include "Composite/Mutable.h"
#include "Nix/ScalarJIT.h"
#include "Nix/Eval.h"
#include "Nix/LazyJIT.h"

#include "mlir/Conversion/ArithToLLVM/ArithToLLVM.h"
#include "mlir/Conversion/ControlFlowToLLVM/ControlFlowToLLVM.h"
#include "mlir/Conversion/Passes.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/ExecutionEngine/ExecutionEngine.h"
#include "mlir/ExecutionEngine/OptUtils.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/Verifier.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Transforms/Passes.h"
#include "mlir/Target/LLVMIR/Dialect/Builtin/BuiltinToLLVMIRTranslation.h"
#include "mlir/Target/LLVMIR/Dialect/LLVMIR/LLVMToLLVMIRTranslation.h"
#include "llvm/IR/Module.h"
#include "llvm/ADT/ScopeExit.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/Support/TargetSelect.h"

#include <algorithm>
#include <array>
#include <charconv>
#include <chrono>
#include <cstring>
#include <cstdlib>
#include <filesystem>
#include <mutex>

namespace nixev {
namespace nd = mlir::nix;
namespace {
constexpr unsigned kMaxNodes = 64, kMaxCandidates = 256, kMaxCompiles = 16, kGrace = 3;
constexpr unsigned kMaxBooleanDeopts = 64;
enum class Kind { Arg, Int, Add, Sub, Mul };
struct Node { Kind kind; unsigned lhs = 0, rhs = 0; int64_t literal = 0; };

enum class PointerKind { None, Argument, Capture, EmptyAttrs, EmptyList, EmptyString };
struct PointerPlan {
  PointerKind kind = PointerKind::None;
  mlir::Value capture; // identity's result, or a conditional's Boolean; resolved in the current closure on EVERY call
  PosPtr pos = nullptr;
  bool inverted = false;
};

/// These small shapes account for the hot library identities and optionalAttrs/optionals/optionalString. Recognize
/// their graph, not their source name. In particular, a conditional never demands its argument on the empty arm.
PointerPlan pointerPlan(nd::LambdaOp lam, mlir::Value result) {
  auto &region = lam.getBody();
  if (lam.getFormals() || !llvm::hasSingleElement(region) || region.front().getNumArguments() != 1) return {};
  auto arg = region.front().getArgument(0);
  if (result == arg) return {PointerKind::Argument};
  if (result.getParentRegion() != &region) return {PointerKind::Capture, result};
  auto branch = result.getDefiningOp<nd::IfOp>();
  if (!branch || branch.getCond().getParentRegion() == &region) return {};
  bool inverted = branch.getElseValue() == arg;
  if (!inverted && branch.getThenValue() != arg) return {};
  auto *empty = (inverted ? branch.getThenValue() : branch.getElseValue()).getDefiningOp();
  if (!empty || empty->getParentRegion() != &region || empty->getNumOperands()) return {};
  PointerKind kind = PointerKind::None;
  if (mlir::isa<nd::AttrsOp>(empty)) kind = PointerKind::EmptyAttrs;
  else if (mlir::isa<nd::ListOp>(empty)) kind = PointerKind::EmptyList;
  else if (auto str = mlir::dyn_cast<nd::StringOp>(empty); str && str.getValue().str().empty()) kind = PointerKind::EmptyString;
  if (kind == PointerKind::None) return {};
  return {kind, branch.getCond(), nd::posOfOp(branch), inverted};
}

/// Grace validation compares WHNF payload identity, never recursively evaluates a list, set or function.
bool sameValue(const Value &a, const Value &b) {
  if (a.type != b.type) return false;
  switch (a.type) {
  case VType::Int: return a.integer == b.integer;
  case VType::Float: return memcmp(&a.fpoint, &b.fpoint, sizeof(double)) == 0;
  case VType::Bool: return a.boolean == b.boolean;
  case VType::Null: return true;
  case VType::String: return a.str.s == b.str.s && a.str.ctx == b.str.ctx && a.aux == b.aux;
  case VType::Path: return a.path.s == b.path.s && a.aux == b.aux;
  case VType::Attrs: return a.attrs == b.attrs;
  case VType::List: return a.list.elems == b.list.elems && a.aux == b.aux;
  case VType::Lambda: return a.thunk.op == b.thunk.op && a.thunk.env == b.thunk.env;
  case VType::PrimOp: return a.primOp == b.primOp;
  case VType::PrimOpApp: return a.app.left == b.app.left && a.app.right == b.app.right;
  default: return false;
  }
}

bool sameEmpty(const Value &v, PointerKind kind) {
  return (kind == PointerKind::EmptyAttrs && v.type == VType::Attrs && v.attrs->empty()) ||
         (kind == PointerKind::EmptyList && v.type == VType::List && v.listSize() == 0) ||
         (kind == PointerKind::EmptyString && v.type == VType::String && v.sv().empty() && !v.str.ctx);
}

using LazyEmpty = LazyJITPlan::RunResult::Empty;
PointerKind emptyKind(LazyEmpty recipe) {
  switch (recipe) {
  case LazyEmpty::Attrs: return PointerKind::EmptyAttrs;
  case LazyEmpty::List: return PointerKind::EmptyList;
  case LazyEmpty::String: return PointerKind::EmptyString;
  case LazyEmpty::None: return PointerKind::None;
  }
  return PointerKind::None;
}

bool sameLazyResult(const Value &oracle, const LazyJITPlan::RunResult &result) {
  if (result.listSize) {
    if (result.cell || result.empty != LazyEmpty::None || result.listSize > result.listElements.size() ||
        oracle.type != VType::List || oracle.listSize() != result.listSize) return false;
    // A recipe describes a fresh list array. Only its ordered element handles
    // must match; inspecting their tags or values would violate lazy grace.
    for (unsigned i = 0; i < result.listSize; ++i)
      if (!result.listElements[i] || oracle.list.elems[i] != result.listElements[i]) return false;
    return true;
  }
  if (result.empty != LazyEmpty::None)
    return !result.cell && sameEmpty(oracle, emptyKind(result.empty));
  return result.cell ? sameValue(oracle, *result.cell)
                     : oracle.type == VType::Bool && oracle.boolean == result.value;
}

/// Walk only the result's reachable graph. Unused nodes stay lazy; captures and cycles are refused.
struct Plan {
  explicit Plan(mlir::Region &region) : region(region) {}
  mlir::Region &region;
  llvm::DenseMap<mlir::Value, unsigned> visited;
  llvm::SmallVector<Node, 16> nodes;
  bool visit(mlir::Value v, unsigned &index, unsigned depth = 0) {
    if (depth >= kMaxNodes) return false;
    if (auto it = visited.find(v); it != visited.end()) {
      if (!it->second) return false; // active DFS edge: recursive graph
      index = it->second - 1;
      return true;
    }
    if (visited.size() >= kMaxNodes) return false;
    visited[v] = 0;
    Node n{Kind::Arg};
    if (v != region.front().getArgument(0)) {
      auto *op = v.getDefiningOp();
      if (!op || op->getParentRegion() != &region || op->getNumResults() != 1) return false;
      if (auto c = mlir::dyn_cast<nd::IntOp>(op)) {
        n.kind = Kind::Int;
        n.literal = c.getValue();
      } else {
        auto name = op->getName().getStringRef();
        if (name == "nixnum.add") n.kind = Kind::Add;
        else if (name == "nixnum.sub") n.kind = Kind::Sub;
        else if (name == "nixnum.mul") n.kind = Kind::Mul;
        else if (auto c = mlir::dyn_cast<nd::ConcatStringsOp>(op); c && !c.getForceString()) n.kind = Kind::Add;
        else return false;
        if (op->getNumOperands() != 2 || !visit(op->getOperand(0), n.lhs, depth + 1) ||
            !visit(op->getOperand(1), n.rhs, depth + 1)) return false;
      }
    }
    index = nodes.size();
    nodes.push_back(n);
    visited[v] = index + 1;
    return true;
  }
};

unsigned threshold() {
  unsigned n = 1024;
  if (const char *s = getenv("MLNIX_JIT_THRESHOLD")) {
    unsigned parsed;
    auto result = std::from_chars(s, s + strlen(s), parsed);
    if (result.ec == std::errc() && *result.ptr == '\0' && parsed >= 1 && parsed <= 1000000) n = parsed;
  }
  return n;
}
} // namespace

struct ScalarJIT::Impl {
  using Fn = uint64_t (*)(int64_t, int64_t *);
  using PointerFn = Value *(*)(uint64_t, Value *, Value *);
  struct Entry {
    unsigned calls = 0, grace = 0, booleanMisses = 0, preflightMisses = 0, activeRuns = 0;
    bool rejected = false, retirePending = false;
    Fn fn = nullptr;
    PointerFn pointerFn = nullptr;
    PointerPlan pointer;
    std::unique_ptr<Plan> scalarPlan;
    std::unique_ptr<LazyJITPlan> lazyPlan;
    LazyJITPlan::Fn lazyFn = nullptr;
    unsigned scalarResult = 0, curriedArity = 0;
    uint64_t curriedCalls = 0, curriedCompletions = 0, curriedDeopts = 0;
    uint64_t projectionRequests = 0, projectionForces = 0, saturatedInlineCalls = 0, valueCompletions = 0,
             listCompletions = 0, stringComparisons = 0;
    std::string curriedLocation;
    // ExecutionEngine accepts a function_ref; keep its callable alive until after the engine is destroyed.
    std::function<llvm::Error(llvm::Module *)> transformer;
    std::unique_ptr<mlir::ExecutionEngine> engine;
    void releaseLazyCode() {
      engine.reset();
      transformer = {};
      lazyFn = nullptr;
      lazyPlan.reset();
      retirePending = false;
    }
  };
  composite::MutableSeries<std::unique_ptr<Entry>> entries;
  composite::MutableSeries<std::unique_ptr<CurriedCache>> curriedCaches;
  composite::MutableSeries<std::unique_ptr<Entry>> curriedEntries;
  const bool curriedEnabled = [] {
    const char *setting = getenv("MLNIX_JIT_CURRIED");
    return !setting || std::string_view(setting) != "0";
  }();
  Entry refused;
  Impl() { refused.rejected = true; }
  Entry sharedPointer; // one generated selector, reused across argument/capture/conditional leaf shapes
  struct Profile {
    uint64_t calls = 0, ready = 0, integers = 0;
    std::string shape, location;
    uint64_t booleanCompletions = 0, booleanDemands = 0, booleanDeopts = 0, inlineCalls = 0;
    uint64_t projectionRequests = 0, projectionForces = 0, saturatedInlineCalls = 0, valueCompletions = 0,
             listCompletions = 0, stringComparisons = 0;
  };
  const bool profiling = getenv("MLNIX_JIT_PROFILE") != nullptr;
  llvm::DenseMap<mlir::Operation *, Profile> profiles;
  uint64_t profileDropped = 0;
  std::unique_ptr<mlir::MLIRContext> ctx;
  const unsigned hot = threshold();
  unsigned attempts = 0;
  uint64_t compileNs = 0; // elapsed compilation wall time, including failed attempts and first context setup
  uint64_t compiled = 0, executions = 0, grace = 0, rejected = 0, typeMisses = 0,
           overflows = 0, mismatches = 0, compileFailures = 0;
  uint64_t pointerCompiled = 0, identityExecutions = 0, captureExecutions = 0,
           selectorExecutions = 0, pointerGrace = 0, pointerMismatches = 0;
  // Retain these historical counter names for the whole demand/continuation
  // tier. lazy_value_* separately identifies persistent-value results.
  uint64_t booleanCompiled = 0, booleanExecutions = 0, booleanCompletions = 0,
           booleanDemands = 0, booleanResumes = 0, booleanDeopts = 0, booleanGrace = 0,
           booleanMismatches = 0, booleanRetired = 0;
  uint64_t booleanPreflightAttempts = 0, booleanPreflightDeopts = 0, booleanPreflightRejections = 0;
  uint64_t booleanInlineCompiled = 0, booleanInlineCalls = 0, booleanGuardMisses = 0,
           booleanDepthEntries = 0, booleanSpecializations = 0, booleanSpecializationDeopts = 0;
  uint64_t booleanProjectionCompiled = 0, booleanProjectionRequests = 0, booleanProjectionForces = 0,
           booleanProjectionDeopts = 0, booleanProjectionFlat = 0, booleanProjectionLayered = 0,
           booleanProjectionCachedFlat = 0, booleanSaturatedInlineCompiled = 0, booleanSaturatedInlineCalls = 0;
  uint64_t lazyValueCompiled = 0, lazyValueCompletions = 0, lazyValueGrace = 0, lazyValueMismatches = 0,
           lazyEmptyCompletions = 0;
  uint64_t lazyListCompiled = 0, lazyListCompletions = 0, lazyListHandleLookups = 0;
  uint64_t stringCompiled = 0, stringComparisons = 0, stringGuardDeopts = 0,
           pathProjectionCompiled = 0, pathProjectionRequests = 0;

  uint64_t curriedCompiled = 0, curriedExecutions = 0, curriedCompletions = 0,
           curriedGrace = 0, curriedDeopts = 0, curriedRejected = 0,
           curriedFramesSaved = 0, curriedValuesSaved = 0;
  std::array<uint64_t, 3> curriedCalls{};

  bool compile(Entry &entry, const Plan *plan, unsigned result = 0) {
    using namespace mlir;
    auto started = std::chrono::steady_clock::now();
    auto recordTime = llvm::make_scope_exit([&] {
      compileNs += std::chrono::duration_cast<std::chrono::nanoseconds>(
          std::chrono::steady_clock::now() - started).count();
    });
    const unsigned serial = attempts++;
    static std::once_flag native;
    static bool nativeFailed = false;
    std::call_once(native, [] {
      nativeFailed = llvm::InitializeNativeTarget() || llvm::InitializeNativeTargetAsmPrinter();
    });
    if (nativeFailed) return false;
    if (!ctx) {
      ctx = std::make_unique<MLIRContext>();
      ctx->disableMultithreading();
      ctx->loadDialect<arith::ArithDialect, cf::ControlFlowDialect, func::FuncDialect, LLVM::LLVMDialect>();
      registerBuiltinDialectTranslation(*ctx);
      registerLLVMDialectTranslation(*ctx);
    }
    ScopedDiagnosticHandler diagnostics(ctx.get(), [](Diagnostic &d) {
      if (getenv("MLNIX_JIT_DEBUG")) { d.print(llvm::errs()); llvm::errs() << '\n'; }
      return success();
    });
    OpBuilder b(ctx.get());
    auto loc = b.getUnknownLoc();
    OwningOpRef<ModuleOp> module(ModuleOp::create(loc));
    if (entry.lazyPlan) {
      if (!entry.lazyPlan->emit(*module)) return false;
    } else {
      b.setInsertionPointToEnd(module->getBody());
      auto i64 = b.getI64Type(), i128 = b.getIntegerType(128);
      auto pointerType = LLVM::LLVMPointerType::get(ctx.get());
      auto type = plan ? b.getFunctionType({i64, pointerType}, {i64})
                       : b.getFunctionType({i64, pointerType, pointerType}, {pointerType});
      auto fn = func::FuncOp::create(b, loc, "scalar", type);
      auto *block = fn.addEntryBlock();
      b.setInsertionPointToEnd(block);
      if (!plan) {
        auto zero = arith::ConstantIntOp::create(b, loc, 0, 64);
        auto condition = arith::CmpIOp::create(b, loc, arith::CmpIPredicate::ne, block->getArgument(0), zero);
        auto chosen = LLVM::SelectOp::create(b, loc, condition, block->getArgument(1), block->getArgument(2));
        func::ReturnOp::create(b, loc, chosen.getResult());
      } else {
        llvm::SmallVector<mlir::Value, 16> values;
        mlir::Value overflow = arith::ConstantIntOp::create(b, loc, 0, 1);
        for (const auto &n : plan->nodes) {
          if (n.kind == Kind::Arg) { values.push_back(block->getArgument(0)); continue; }
          if (n.kind == Kind::Int) { values.push_back(arith::ConstantIntOp::create(b, loc, n.literal, 64)); continue; }
          auto lhs = arith::ExtSIOp::create(b, loc, i128, values[n.lhs]);
          auto rhs = arith::ExtSIOp::create(b, loc, i128, values[n.rhs]);
          mlir::Value wide;
          if (n.kind == Kind::Add) wide = arith::AddIOp::create(b, loc, lhs, rhs);
          else if (n.kind == Kind::Sub) wide = arith::SubIOp::create(b, loc, lhs, rhs);
          else wide = arith::MulIOp::create(b, loc, lhs, rhs);
          // Each operand is signed i64, so its exact product fits signed i128. Truncate at EVERY node, checking the
          // discarded bits, rather than checking only the final expression (overflow may cancel later).
          auto narrow = arith::TruncIOp::create(b, loc, i64, wide);
          auto restored = arith::ExtSIOp::create(b, loc, i128, narrow);
          auto bad = arith::CmpIOp::create(b, loc, arith::CmpIPredicate::ne, wide, restored);
          overflow = arith::OrIOp::create(b, loc, overflow, bad);
          values.push_back(narrow);
        }
        LLVM::StoreOp::create(b, loc, values[result], block->getArgument(1));
        auto status = arith::ExtUIOp::create(b, loc, i64, overflow);
        func::ReturnOp::create(b, loc, status.getResult());
      }
    }
    if (failed(verify(*module))) return false;

    std::string prefix;
    if (const char *dir = getenv("MLNIX_JIT_DUMP")) {
      std::error_code ec;
      std::filesystem::create_directories(dir, ec);
      if (!ec) prefix = std::string(dir) + "/scalar-" + std::to_string(serial);
    }
    auto dump = [&](llvm::StringRef suffix) {
      if (prefix.empty()) return;
      std::error_code ec;
      llvm::raw_fd_ostream os(prefix + suffix.str(), ec);
      if (!ec) { module->print(os); os << '\n'; }
    };
    if (entry.lazyPlan && !prefix.empty()) {
      std::error_code ec;
      llvm::raw_fd_ostream os(prefix + ".plan.txt", ec);
      if (!ec) entry.lazyPlan->print(os);
    }
    dump(".typed.mlir");
    auto tPh0 = std::chrono::steady_clock::now();
    PassManager pm(ctx.get());
    // Typed-level cleanup: shared graph nodes dedupe here, before LLVM sees them (opt-in MLNIX_JIT_CLEAN=1: measured no gain on small kernels).
    if (const char *clean = getenv("MLNIX_JIT_CLEAN"); clean && std::string_view(clean) == "1") {
      OpPassManager &fn = pm.nest<func::FuncOp>();
      fn.addPass(createCanonicalizerPass());
      fn.addPass(createCSEPass());
      fn.addPass(createControlFlowSinkPass());
    }
    pm.addPass(createArithToLLVMConversionPass());
    pm.addPass(createConvertControlFlowToLLVMPass());
    pm.addPass(createConvertFuncToLLVMPass());
    pm.addPass(createReconcileUnrealizedCastsPass());
    if (failed(pm.run(*module))) return false;
    dump(".llvm.mlir");
    unsigned optLevel = 0; // measured: engine 0.45 ms at 0 vs 1.85 ms at 2, same steady-state speed (host forcing dominates)
    if (const char *o = getenv("MLNIX_JIT_OPT")) optLevel = std::min(3, atoi(o));
    auto optimize = makeOptimizingTransformer(optLevel, 0, nullptr);
    entry.transformer = [optimize = std::move(optimize), prefix](llvm::Module *m) -> llvm::Error {
      if (auto error = optimize(m)) return error;
      if (!prefix.empty()) {
        std::error_code ec;
        llvm::raw_fd_ostream os(prefix + ".ll", ec);
        if (!ec) m->print(os, nullptr);
      }
      return llvm::Error::success();
    };
    ExecutionEngineOptions options;
    options.jitCodeGenOptLevel = optLevel == 0 ? llvm::CodeGenOptLevel::None
                               : optLevel == 1 ? llvm::CodeGenOptLevel::Less : llvm::CodeGenOptLevel::Default;
    options.transformer = entry.transformer;
    options.enableGDBNotificationListener = false;
    options.enablePerfNotificationListener = false;
    auto tPh1 = std::chrono::steady_clock::now();
    auto engine = ExecutionEngine::create(*module, options);
    if (getenv("MLNIX_JIT_PHASE")) { auto us=[](auto a,auto b){return std::chrono::duration_cast<std::chrono::microseconds>(b-a).count();}; auto tPh2=std::chrono::steady_clock::now(); llvm::errs()<<"phase lower_us="<<us(tPh0,tPh1)<<" engine_us="<<us(tPh1,tPh2)<<" pre_us="<<us(started,tPh0)<<"\n"; }
    if (!engine) { llvm::consumeError(engine.takeError()); return false; }
    auto address = (*engine)->lookup("scalar");
    if (!address) { llvm::consumeError(address.takeError()); return false; }
    if (entry.lazyPlan) {
      entry.lazyFn = reinterpret_cast<LazyJITPlan::Fn>(*address);
      ++booleanCompiled;
      curriedCompiled += entry.curriedArity != 0;
      booleanInlineCompiled += entry.lazyPlan->inlineCallCount() != 0;
      booleanProjectionCompiled += entry.lazyPlan->projectionCount() != 0;
      booleanSaturatedInlineCompiled += entry.lazyPlan->saturatedInlineCallCount() != 0;
      lazyValueCompiled += entry.lazyPlan->valueReturnCount() != 0;
      lazyListCompiled += entry.lazyPlan->listReturnCount() != 0;
      stringCompiled += entry.lazyPlan->comparisonCount() != 0;
      pathProjectionCompiled += entry.lazyPlan->pathProjectionCount() != 0;
    }
    else if (plan) entry.fn = reinterpret_cast<Fn>(*address);
    else { entry.pointerFn = reinterpret_cast<PointerFn>(*address); ++pointerCompiled; }
    entry.engine = std::move(*engine);
    ++compiled;
    return true;
  }
  void evaluateLazy(EvalState &st, Entry &e, mlir::Operation *lambda, Frame *closureEnv,
                    llvm::ArrayRef<Value *> args, Value &out, PosPtr callPos, void *&cache,
                    llvm::function_ref<void()> interpret) {
    auto &p = *this;
    // The oracle must not overwrite an input that observation will read. A
    // particular aliased invocation does not invalidate this entry's plan.
    for (Value *arg : args) if (arg == &out) { interpret(); return; }
    // Curried stages are sequential calls at the same depth. The oracle runs at
    // the original caller depth; only observation/native execution enters one
    // logical stage. Host demands and nested inlined calls inherit that depth.
    auto atCallDepth = [&](auto action) {
      const unsigned depth = st.callDepth;
      if (e.curriedArity) {
        if (depth >= st.settings.maxCallDepth)
          throw StackOverflowError("stack overflow; max-call-depth exceeded", callPos);
        ++st.callDepth;
      }
      auto restore = llvm::make_scope_exit([&] { st.callDepth = depth; });
      return action();
    };
    bool oracleRan = false;
    if (!e.lazyFn) {
      if (++e.calls < p.hot) { interpret(); return; }
      if (p.attempts >= kMaxCompiles) {
        e.rejected = true; ++p.rejected; interpret(); return;
      }
      // A hot but unsupported path should not pay for an LLVM engine. The oracle
      // runs once; the pure observer then reads only its already-memoized cells.
      interpret();
      oracleRan = true;
      if (e.rejected) return;
      // The oracle can recursively compile, validate or refuse this same entry.
      // Re-read its state instead of retaining a plan pointer across interpretation.
      if (!e.lazyFn) {
        auto refuse = [&] {
          e.rejected = true;
          cache = &p.refused;
          ++p.rejected; ++p.booleanPreflightRejections;
          p.curriedRejected += e.curriedArity != 0;
          e.lazyPlan.reset(); // no native run exists before this entry's first compilation
        };
        if (!e.lazyPlan && e.curriedArity) {
          e.lazyPlan = LazyJITPlan::createSaturated(st, lambda, e.curriedArity);
          if (!e.lazyPlan) { refuse(); return; }
        }
        if (e.lazyPlan->needsSpecialization()) {
          ++p.booleanSpecializations;
          if (!e.lazyPlan->specialize(st, closureEnv, args)) {
            ++p.booleanSpecializationDeopts;
            if (++e.preflightMisses >= kMaxBooleanDeopts) refuse();
            return; // the oracle already produced the answer; unresolved calls stay lazy
          }
        }
        ++p.booleanPreflightAttempts;
        auto observed = atCallDepth([&] { return e.lazyPlan->observe(st, closureEnv, args); });
        if (observed.outcome == LazyJITPlan::Outcome::Deopt) {
          ++p.booleanPreflightDeopts;
          if (++e.preflightMisses >= kMaxBooleanDeopts) refuse();
          return;
        }
        if (observed.outcome != LazyJITPlan::Outcome::Done) { refuse(); return; }
        if (!sameLazyResult(out, observed)) {
          ++p.mismatches; ++p.booleanMismatches;
          p.lazyValueMismatches += observed.cell != nullptr || observed.empty != LazyEmpty::None || observed.listSize != 0;
          refuse();
          return;
        }
        e.preflightMisses = 0;
        if (p.attempts >= kMaxCompiles) { refuse(); return; }
        if (!p.compile(e, nullptr)) {
          if (getenv("MLNIX_JIT_DEBUG"))
            llvm::errs() << "jit: lazy graph compilation failed at " << st.showPos(nd::posOfOp(lambda)) << '\n';
          e.rejected = true; ++p.compileFailures;
          return; // preserve the oracle answer, without repeating its effects
        }
      }
    }
    const bool validating = e.grace < kGrace;
    if (oracleRan && !validating) return; // recursive calls already completed the three native checks
    if (validating && !oracleRan) {
      // The interpreter is the only executor of effects during grace. The native observer
      // may inspect persistent memoized cells, but may not demand an additional value.
      interpret();
      if (e.rejected) return; // a recursive oracle call may have disabled this entry
      if (e.grace >= kGrace) return;
    }
    ++p.executions; ++p.booleanExecutions;
    p.curriedExecutions += e.curriedArity != 0;
    // A host demand may recursively invoke this same lambda. Retirement can stop
    // new entries immediately, but suspended native runs still own this plan and code.
    ++e.activeRuns;
    auto activeRun = llvm::make_scope_exit([&] {
      if (--e.activeRuns == 0 && e.retirePending) e.releaseLazyCode();
    });
    auto result = atCallDepth([&] { return e.lazyPlan->run(st, closureEnv, args, e.lazyFn, validating, callPos); });
    p.booleanDemands += result.demands;
    p.booleanResumes += result.resumes;
    p.booleanInlineCalls += result.inlineCalls;
    p.booleanGuardMisses += result.guardMisses;
    p.booleanDepthEntries += result.depthEntries;
    p.booleanProjectionRequests += result.projectionRequests;
    p.booleanProjectionForces += result.projectionForces;
    p.booleanProjectionDeopts += result.projectionDeopts;
    p.booleanProjectionFlat += result.projectionFlat;
    p.booleanProjectionLayered += result.projectionLayered;
    p.booleanProjectionCachedFlat += result.projectionCachedFlat;
    p.booleanSaturatedInlineCalls += result.saturatedInlineCalls;
    p.lazyListHandleLookups += result.listHandleLookups;
    p.stringComparisons += result.stringComparisons;
    p.stringGuardDeopts += result.stringGuardDeopts;
    p.pathProjectionRequests += result.pathProjectionRequests;
    if (e.curriedArity) {
      e.projectionRequests += result.projectionRequests;
      e.projectionForces += result.projectionForces;
      e.saturatedInlineCalls += result.saturatedInlineCalls;
      e.stringComparisons += result.stringComparisons;
    }
    Impl::Profile *profile = nullptr;
    if (p.profiling && !e.curriedArity) {
      auto it = p.profiles.find(lambda);
      if (it != p.profiles.end()) {
        profile = &it->second;
        profile->booleanDemands += result.demands;
        profile->inlineCalls += result.inlineCalls;
        profile->projectionRequests += result.projectionRequests;
        profile->projectionForces += result.projectionForces;
        profile->saturatedInlineCalls += result.saturatedInlineCalls;
        profile->stringComparisons += result.stringComparisons;
      }
    }
    if (e.rejected && !e.retirePending) {
      // A recursive demand detected a validation failure in the shared entry.
      if (!validating) interpret();
      return;
    }
    if (result.outcome == LazyJITPlan::Outcome::Invalid) {
      e.rejected = true; ++p.mismatches; ++p.booleanMismatches;
      if (!validating) interpret();
      return;
    }
    if (result.outcome == LazyJITPlan::Outcome::Deopt) {
      ++p.booleanDeopts;
      p.curriedDeopts += e.curriedArity != 0;
      if (e.curriedArity) ++e.curriedDeopts;
      if (profile) ++profile->booleanDeopts;
      if (++e.booleanMisses >= kMaxBooleanDeopts && !e.rejected) {
        // A graph may have a native path that this workload never takes. Stop paying
        // its dispatch and release its private machine code after a bounded miss streak.
        // Successfully forced inputs remain memoized; retirement changes no Nix value.
        e.rejected = true;
        cache = &p.refused;
        ++p.rejected; ++p.booleanRetired;
        p.curriedRejected += e.curriedArity != 0;
        e.retirePending = true;
      }
      if (!validating) interpret();
      return;
    }
    e.booleanMisses = 0;
    ++p.booleanCompletions;
    p.curriedCompletions += e.curriedArity != 0;
    if (e.curriedArity) ++e.curriedCompletions;
    if (profile) ++profile->booleanCompletions;
    const bool valueResult = result.cell || result.empty != LazyEmpty::None || result.listSize != 0;
    if (valueResult) {
      ++p.lazyValueCompletions;
      p.lazyEmptyCompletions += result.empty != LazyEmpty::None;
      if (e.curriedArity) ++e.valueCompletions;
      if (profile) ++profile->valueCompletions;
    }
    if (result.listSize) {
      ++p.lazyListCompletions;
      if (e.curriedArity) ++e.listCompletions;
      if (profile) ++profile->listCompletions;
    }
    if (validating) {
      if (e.grace < kGrace) ++e.grace;
      ++p.grace; ++p.booleanGrace;
      p.curriedGrace += e.curriedArity != 0;
      p.lazyValueGrace += valueResult;
      if (!sameLazyResult(out, result)) {
        e.rejected = true; ++p.mismatches; ++p.booleanMismatches;
        p.lazyValueMismatches += valueResult;
      }
      return;
    }
    if (e.curriedArity) {
      // Semantic chain storage avoided, not an incremental allocation delta
      // against the existing unary JIT. Use allocValue/newFrame for that delta.
      p.curriedFramesSaved += e.curriedArity;
      p.curriedValuesSaved += e.curriedArity - 1;
    }
    if (result.cell) out = *result.cell;
    else if (result.listSize) {
      st.mkList(out, size_t(result.listSize));
      std::copy_n(result.listElements.begin(), result.listSize, out.list.elems);
    }
    else if (result.empty == LazyEmpty::Attrs) st.mkAttrs(out, st.allocBindings(0));
    else if (result.empty == LazyEmpty::List) st.mkList(out, size_t(0));
    else if (result.empty == LazyEmpty::String) st.mkString(out, "");
    else st.mkBool(out, result.value);
    return;
  }
};

ScalarJIT::ScalarJIT() : impl(std::make_unique<Impl>()), refused(&impl->refused), profiling(impl->profiling), curried(impl->curriedEnabled) {}
ScalarJIT::~ScalarJIT() = default;
std::unique_ptr<ScalarJIT> ScalarJIT::create() {
  const char *enabled = getenv("MLNIX_JIT");
  // A replacement primop declaration can change the semantics behind an operation name.
  if (!enabled || std::string_view(enabled) != "1" || getenv("MLNIX_PRIMS_IRDL")) return nullptr;
  return std::unique_ptr<ScalarJIT>(new ScalarJIT());
}

bool ScalarJIT::evaluateSaturated(EvalState &st, mlir::Operation *lambda, mlir::Value result,
                                   Frame *closureEnv, llvm::ArrayRef<Value *> args, Value &out,
                                   PosPtr callPos, void *&cache, llvm::function_ref<void()> interpret) {
  auto &p = *impl;
  if (!curried || args.size() < 2 || args.size() > 4 || cache == refused) return false;
  // The oracle may overwrite out. An aliased input would no longer represent
  // the original invocation during observe-only validation; leave it ordinary.
  for (Value *arg : args) if (arg == &out) return false;
  ++p.curriedCalls[args.size() - 2];
  if (!cache) {
    auto outer = mlir::cast<nd::LambdaOp>(lambda);
    auto next = result.getDefiningOp<nd::LambdaOp>();
    // This cheap structural gate also makes permanently ineligible regions
    // bypass dispatch. No nested body is minted or argument inspected here.
    if (outer.getFormals() || !next || next->getParentRegion() != &outer.getBody() ||
        p.curriedCaches.size() >= kMaxCandidates) {
      cache = &p.refused; ++p.curriedRejected; return false;
    }
    auto slots = std::make_unique<CurriedCache>();
    cache = slots.get();
    p.curriedCaches.append(std::move(slots));
  }
  void *&slot = static_cast<CurriedCache *>(cache)->byArity[args.size() - 2];
  if (slot == refused) return false;
  if (!slot) {
    if (p.curriedEntries.size() >= kMaxCandidates) {
      slot = &p.refused; ++p.curriedRejected; return false;
    }
    auto entry = std::make_unique<Impl::Entry>();
    entry->curriedArity = args.size();
    if (p.profiling) entry->curriedLocation = st.showPos(nd::posOfOp(lambda));
    slot = entry.get();
    p.curriedEntries.append(std::move(entry));
  }
  auto &e = *static_cast<Impl::Entry *>(slot);
  if (e.rejected) return false;
  ++e.curriedCalls;
  p.evaluateLazy(st, e, lambda, closureEnv, args, out, callPos, slot, interpret);
  // Every refusal becomes visible to the inline arity gate. Entry/code lifetime
  // still belongs to the JIT and activeRuns, including suspended recursive runs.
  if (e.rejected) slot = &p.refused;
  return true;
}

void ScalarJIT::evaluate(EvalState &st, mlir::Operation *lambda, mlir::Value result, Frame *closureEnv,
                         Value &arg, Value &out, const void *callPos, void *&cache,
                         llvm::function_ref<void()> interpret) {
  auto &p = *impl;
  if (p.profiling) {
    auto it = p.profiles.find(lambda);
    if (it == p.profiles.end() && p.profiles.size() < 4096) {
      auto lam = mlir::cast<nd::LambdaOp>(lambda);
      auto shape = [&](mlir::Value v) {
        if (v == lam.getBody().front().getArgument(0)) return std::string("argument");
        auto *op = v.getDefiningOp();
        if (!op || op->getParentRegion() != &lam.getBody()) return std::string("capture");
        return op->getName().getStringRef().str();
      };
      std::string desc = shape(result);
      if (auto *op = result.getDefiningOp()) {
        if (auto select = mlir::dyn_cast<nd::SelectOp>(op)) {
          desc += "(" + shape(select.getBase()) + ":";
          for (const auto &name : select.getPath()) desc += name.toString() + ".";
          desc += ")";
        } else if (auto branch = mlir::dyn_cast<nd::IfOp>(op)) {
          desc += "(" + shape(branch.getCond()) + "," + shape(branch.getThenValue()) + "," + shape(branch.getElseValue()) + ")";
        }
      }
      it = p.profiles.try_emplace(lambda, Impl::Profile{0, 0, 0, std::move(desc), st.showPos(nd::posOfOp(lambda))}).first;
    }
    if (it != p.profiles.end()) {
      ++it->second.calls;
      it->second.ready += !arg.isThunk();
      it->second.integers += arg.type == VType::Int;
    } else ++p.profileDropped;
  }
  // RegionInfo holds this stable pointer: warm calls do not hash the LambdaOp or reclassify its graph.
  if (!cache) {
    if (p.entries.size() >= kMaxCandidates) { cache = &p.refused; interpret(); return; }
    auto lam = mlir::cast<nd::LambdaOp>(lambda);
    auto entry = std::make_unique<Impl::Entry>();
    entry->pointer = pointerPlan(lam, result);
    if (entry->pointer.capture) {
      uint32_t slot = st.slotOf(entry->pointer.capture.getAsOpaquePointer());
      if (slot == EvalState::kNoHandle || st.slotStore[slot].idx == kNoSlot) {
        // lookup() of an in-place value makes a temporary cell. It cannot be forced and then replayed safely.
        cache = &p.refused; ++p.rejected; interpret(); return;
      }
    }
    if (entry->pointer.kind == PointerKind::None) {
      if (lam.getFormals() || !llvm::hasSingleElement(lam.getBody()) ||
          lam.getBody().front().getNumArguments() != 1) {
        cache = &p.refused; ++p.rejected; interpret(); return;
      }
      entry->scalarPlan = std::make_unique<Plan>(lam.getBody());
      if (!entry->scalarPlan->visit(result, entry->scalarResult)) {
        entry->scalarPlan.reset();
        entry->lazyPlan = LazyJITPlan::create(st, lambda, result);
        if (!entry->lazyPlan) { cache = &p.refused; ++p.rejected; interpret(); return; }
      }
    }
    cache = entry.get();
    p.entries.append(std::move(entry));
  }
  auto &e = *static_cast<Impl::Entry *>(cache);
  if (e.rejected) { interpret(); return; }
  if (e.pointer.kind != PointerKind::None) {
    if (!e.pointerFn) {
      if (++e.calls < p.hot) { interpret(); return; }
      if (!p.sharedPointer.pointerFn) {
        if (p.sharedPointer.rejected || p.attempts >= kMaxCompiles) {
          e.rejected = true; ++p.rejected; interpret(); return;
        }
        if (!p.compile(p.sharedPointer, nullptr)) {
          p.sharedPointer.rejected = e.rejected = true;
          ++p.compileFailures; interpret(); return;
        }
      }
      e.pointerFn = p.sharedPointer.pointerFn;
    }
    Value *input = &arg;
    bool take = true;
    PosPtr tailPos = callPos;
    if (e.pointer.kind == PointerKind::Capture) {
      input = st.lookup(closureEnv, e.pointer.capture);
    } else if (e.pointer.kind != PointerKind::Argument) {
      // The IfOp always demands this persistent capture before either arm. If forcing throws, propagate that
      // exception directly: retrying the interpreter would repeat effects because a failing thunk is reset.
      Value *condition = st.lookup(closureEnv, e.pointer.capture);
      st.forceValue(*condition, e.pointer.pos);
      if (condition->type != VType::Bool) { ++p.typeMisses; interpret(); return; }
      take = condition->boolean != e.pointer.inverted;
      tailPos = e.pointer.pos;
    }
    Value *chosen = e.pointerFn(take, input, nullptr);
    ++p.executions;
    if (e.pointer.kind == PointerKind::Argument) ++p.identityExecutions;
    else if (e.pointer.kind == PointerKind::Capture) ++p.captureExecutions;
    else ++p.selectorExecutions;
    // Check the pointer recipe on EVERY call before any selected value is forced. A miscompiled selector must
    // never turn an unused throwing/tracing arm into an observed effect, even after the grace period.
    if (chosen != (take ? input : nullptr)) {
      e.rejected = true; ++p.mismatches; ++p.pointerMismatches; interpret(); return;
    }
    if (e.grace < kGrace) {
      // Run the oracle first. Its persistent result cell is now WHNF; compare payload identity without forcing
      // anything additional. Empty containers are compared by their empty recipe, preserving fresh allocations.
      interpret();
      ++e.grace; ++p.grace; ++p.pointerGrace;
      if (!(chosen ? sameValue(out, *chosen) : sameEmpty(out, e.pointer.kind))) {
        e.rejected = true; ++p.mismatches; ++p.pointerMismatches;
      }
      return;
    }
    if (chosen) {
      st.forceValue(*chosen, tailPos);
      out = *chosen;
    } else if (e.pointer.kind == PointerKind::EmptyAttrs) st.mkAttrs(out, st.allocBindings(0));
    else if (e.pointer.kind == PointerKind::EmptyList) st.mkList(out, size_t(0));
    else st.mkString(out, "");
    return;
  }
  if (e.lazyPlan) {
    Value *args[]{&arg};
    p.evaluateLazy(st, e, lambda, closureEnv, args, out, callPos, cache, interpret);
    return;
  }
  // Arithmetic keeps its original guard: it never forces an argument merely to obtain an integer specialization.
  if (arg.type != VType::Int) { ++p.typeMisses; interpret(); return; }
  if (!e.fn) {
    if (++e.calls < p.hot) { interpret(); return; }
    if (p.attempts >= kMaxCompiles) {
      e.rejected = true; ++p.rejected; interpret(); return;
    }
    bool compiled = p.compile(e, e.scalarPlan.get(), e.scalarResult);
    e.scalarPlan.reset();
    if (!compiled) {
      e.rejected = true; ++p.compileFailures; interpret(); return;
    }
  }
  int64_t nativeResult = 0;
  ++p.executions;
  if (e.fn(arg.integer, &nativeResult)) { ++p.overflows; interpret(); return; }
  if (e.grace < kGrace) {
    try { interpret(); }
    catch (...) { e.rejected = true; ++p.mismatches; throw; }
    ++e.grace; ++p.grace;
    if (out.type != VType::Int || out.integer != nativeResult) {
      e.rejected = true; ++p.mismatches;
    }
    return;
  }
  st.mkInt(out, nativeResult);
}

void ScalarJIT::printStats() const {
  const auto &p = *impl;
  llvm::errs() << "jit: compiled=" << p.compiled << " executions=" << p.executions << " grace=" << p.grace
               << " rejected=" << p.rejected << " type_misses=" << p.typeMisses << " overflows=" << p.overflows
               << " mismatches=" << p.mismatches << " compile_failures=" << p.compileFailures
               << " compile_ns=" << p.compileNs
               << " candidates=" << p.entries.size() << " pointer_compiled=" << p.pointerCompiled
               << " identity_executions=" << p.identityExecutions << " capture_executions=" << p.captureExecutions
               << " selector_executions=" << p.selectorExecutions << " pointer_grace=" << p.pointerGrace
               << " pointer_mismatches=" << p.pointerMismatches
               << " boolean_compiled=" << p.booleanCompiled << " boolean_executions=" << p.booleanExecutions
               << " boolean_completions=" << p.booleanCompletions << " boolean_demands=" << p.booleanDemands
               << " boolean_resumes=" << p.booleanResumes << " boolean_deopts=" << p.booleanDeopts
               << " boolean_grace=" << p.booleanGrace << " boolean_mismatches=" << p.booleanMismatches
               << " boolean_retired=" << p.booleanRetired
               << " boolean_preflight_attempts=" << p.booleanPreflightAttempts
               << " boolean_preflight_deopts=" << p.booleanPreflightDeopts
               << " boolean_preflight_rejections=" << p.booleanPreflightRejections
               << " boolean_inline_compiled=" << p.booleanInlineCompiled
               << " boolean_inline_calls=" << p.booleanInlineCalls
               << " boolean_guard_misses=" << p.booleanGuardMisses
               << " boolean_depth_entries=" << p.booleanDepthEntries
               << " boolean_specializations=" << p.booleanSpecializations
               << " boolean_specialization_deopts=" << p.booleanSpecializationDeopts
               << " boolean_projection_compiled=" << p.booleanProjectionCompiled
               << " boolean_projection_requests=" << p.booleanProjectionRequests
               << " boolean_projection_forces=" << p.booleanProjectionForces
               << " boolean_projection_deopts=" << p.booleanProjectionDeopts
               << " boolean_projection_flat=" << p.booleanProjectionFlat
               << " boolean_projection_layered=" << p.booleanProjectionLayered
               << " boolean_projection_cached_flat=" << p.booleanProjectionCachedFlat
               << " boolean_saturated_inline_compiled=" << p.booleanSaturatedInlineCompiled
               << " boolean_saturated_inline_calls=" << p.booleanSaturatedInlineCalls
               << " lazy_value_compiled=" << p.lazyValueCompiled
               << " lazy_value_completions=" << p.lazyValueCompletions
               << " lazy_value_grace=" << p.lazyValueGrace
               << " lazy_value_mismatches=" << p.lazyValueMismatches
               << " lazy_empty_completions=" << p.lazyEmptyCompletions
               << " lazy_list_compiled=" << p.lazyListCompiled
               << " lazy_list_completions=" << p.lazyListCompletions
               << " lazy_list_handle_lookups=" << p.lazyListHandleLookups
               << " string_compiled=" << p.stringCompiled
               << " string_comparisons=" << p.stringComparisons
               << " string_guard_deopts=" << p.stringGuardDeopts
               << " path_projection_compiled=" << p.pathProjectionCompiled
               << " path_projection_requests=" << p.pathProjectionRequests
               << " curried_candidates=" << p.curriedEntries.size()
               << " curried_compiled=" << p.curriedCompiled
               << " curried_executions=" << p.curriedExecutions
               << " curried_completions=" << p.curriedCompletions
               << " curried_grace=" << p.curriedGrace << " curried_deopts=" << p.curriedDeopts
               << " curried_rejected=" << p.curriedRejected
               << " curried_frames_saved=" << p.curriedFramesSaved
               << " curried_values_saved=" << p.curriedValuesSaved
               << " curried_arity2=" << p.curriedCalls[0] << " curried_arity3=" << p.curriedCalls[1]
               << " curried_arity4=" << p.curriedCalls[2] << '\n';
  if (p.profiling) {
    composite::MutableSeries<const Impl::Profile *> ranked;
    for (const auto &entry : p.profiles) ranked.append(&entry.second);
    composite::sortRows(ranked.data(), ranked.size(), [](const auto *a, const auto *b) { return a->calls > b->calls; });
    llvm::errs() << "jit-profile: kernels=" << ranked.size() << " dropped_calls=" << p.profileDropped << '\n';
    for (size_t i = 0; i < std::min<size_t>(ranked.size(), 60); ++i) {
      const auto &r = *ranked[i];
      llvm::errs() << "jit-shape: calls=" << r.calls << " ready=" << r.ready << " integers=" << r.integers
                   << " root=" << r.shape << " boolean_completions=" << r.booleanCompletions
                   << " boolean_demands=" << r.booleanDemands << " boolean_deopts=" << r.booleanDeopts
                   << " boolean_inline_calls=" << r.inlineCalls
                   << " projection_requests=" << r.projectionRequests << " projection_forces=" << r.projectionForces
                   << " saturated_inline_calls=" << r.saturatedInlineCalls
                   << " value_completions=" << r.valueCompletions
                   << " list_completions=" << r.listCompletions
                   << " string_comparisons=" << r.stringComparisons
                   << " at=" << r.location << '\n';
    }
    composite::MutableSeries<const Impl::Entry *> saturated;
    for (const auto &entry : p.curriedEntries) saturated.append(entry.get());
    composite::sortRows(saturated.data(), saturated.size(), [](const auto *a, const auto *b) {
      return a->curriedCalls > b->curriedCalls;
    });
    for (size_t i = 0; i < std::min<size_t>(saturated.size(), 60); ++i) {
      const auto &entry = *saturated[i];
      llvm::errs() << "jit-curried: arity=" << entry.curriedArity << " calls=" << entry.curriedCalls
                   << " completions=" << entry.curriedCompletions << " grace=" << entry.grace
                   << " deopts=" << entry.curriedDeopts << " projection_requests=" << entry.projectionRequests
                   << " projection_forces=" << entry.projectionForces
                   << " saturated_inline_calls=" << entry.saturatedInlineCalls
                   << " value_completions=" << entry.valueCompletions
                   << " list_completions=" << entry.listCompletions
                   << " string_comparisons=" << entry.stringComparisons
                   << " at=" << entry.curriedLocation << '\n';
    }
    // A low-call kernel can still account for many fallbacks. Reuse the bounded
    // recorded rows to expose that cost without adding hot-path bookkeeping.
    uint64_t recordedUnaryDeopts = 0, recordedCurriedDeopts = 0;
    for (const auto *r : ranked) recordedUnaryDeopts += r->booleanDeopts;
    for (const auto *e : saturated) recordedCurriedDeopts += e->curriedDeopts;
    llvm::errs() << "jit-deopt-profile: aggregate=" << p.booleanDeopts
                 << " recorded_unary=" << recordedUnaryDeopts
                 << " recorded_curried=" << recordedCurriedDeopts << '\n';
    composite::sortRows(ranked.data(), ranked.size(), [](const auto *a, const auto *b) {
      if (a->booleanDeopts != b->booleanDeopts) return a->booleanDeopts > b->booleanDeopts;
      return composite::lessChars(composite::chars(a->location), composite::chars(b->location));
    });
    for (size_t i = 0; i < std::min<size_t>(ranked.size(), 20) && ranked[i]->booleanDeopts; ++i) {
      const auto &r = *ranked[i];
      llvm::errs() << "jit-deopt-shape: calls=" << r.calls << " completions=" << r.booleanCompletions
                   << " demands=" << r.booleanDemands << " deopts=" << r.booleanDeopts
                   << " root=" << r.shape << " at=" << r.location << '\n';
    }
    composite::sortRows(saturated.data(), saturated.size(), [](const auto *a, const auto *b) {
      if (a->curriedDeopts != b->curriedDeopts) return a->curriedDeopts > b->curriedDeopts;
      return composite::lessChars(composite::chars(a->curriedLocation), composite::chars(b->curriedLocation));
    });
    for (size_t i = 0; i < std::min<size_t>(saturated.size(), 20) && saturated[i]->curriedDeopts; ++i) {
      const auto &e = *saturated[i];
      llvm::errs() << "jit-deopt-curried: arity=" << e.curriedArity << " calls=" << e.curriedCalls
                   << " completions=" << e.curriedCompletions << " deopts=" << e.curriedDeopts
                   << " at=" << e.curriedLocation << '\n';
    }
  }
}
} // namespace nixev
