//===- NixDialect.cpp - Nix dialect implementation ------------------------===//

#include "NixDialect/NixDialect.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/DialectImplementation.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Pass/PassRegistry.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"
#include "mlir/Transforms/WalkPatternRewriteDriver.h"
#include "llvm/ADT/SetVector.h"
#include "llvm/ADT/SmallString.h"
#include "llvm/ADT/StringSet.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/TypeSwitch.h"
#include <mutex>

using namespace mlir;
using namespace mlir::nix;

#include "NixDialect/NixDialect.cpp.inc"
#include "NixDialect/NixInterfaces.cpp.inc"

#define GET_TYPEDEF_CLASSES
#include "NixDialect/NixTypes.cpp.inc"

namespace mlir::nix {
/// `[ "a", %k, "b" ]`: literal components are string attributes, computed ones
/// are operands (recorded as unit attributes in `path`).
static ParseResult parseAttrPath(OpAsmParser &p, ArrayAttr &path,
                                 SmallVectorImpl<OpAsmParser::UnresolvedOperand> &dyn) {
  Builder b(p.getContext());
  SmallVector<Attribute> comps;
  if (p.parseLSquare())
    return failure();
  do {
    std::string lit;
    OpAsmParser::UnresolvedOperand operand;
    if (succeeded(p.parseOptionalString(&lit))) {
      comps.push_back(b.getStringAttr(lit));
    } else {
      OptionalParseResult r = p.parseOptionalOperand(operand);
      if (!r.has_value())
        return p.emitError(p.getCurrentLocation(), "expected a string or an operand");
      if (failed(*r))
        return failure();
      dyn.push_back(operand);
      comps.push_back(b.getUnitAttr());
    }
  } while (succeeded(p.parseOptionalComma()));
  if (p.parseRSquare())
    return failure();
  path = b.getArrayAttr(comps);
  return success();
}

static void printAttrPath(OpAsmPrinter &p, Operation *, ArrayAttr path, OperandRange dyn) {
  p << "[";
  unsigned next = 0;
  llvm::interleaveComma(path, p, [&](Attribute a) {
    if (isa<StringAttr>(a))
      p.printAttribute(a);
    else
      p.printOperand(dyn[next++]);
  });
  p << "]";
}

static LogicalResult verifyAttrPath(Operation *op, ArrayAttr path, unsigned numDyn) {
  if (path.empty())
    return op->emitOpError("path must have at least one component");
  unsigned units = 0;
  for (Attribute a : path) {
    if (isa<UnitAttr>(a))
      ++units;
    else if (!isa<StringAttr>(a))
      return op->emitOpError("path components must be strings or units");
  }
  if (units != numDyn)
    return op->emitOpError("has ") << units << " computed path component(s) but " << numDyn << " operand(s)";
  return success();
}
} // namespace mlir::nix

#define GET_OP_CLASSES
#include "NixDialect/NixOps.cpp.inc"

void NixDialect::initialize() {
  addTypes<
#define GET_TYPEDEF_LIST
#include "NixDialect/NixTypes.cpp.inc"
      >();
  addOperations<
#define GET_OP_LIST
#include "NixDialect/NixOps.cpp.inc"
      >();
}

Operation *NixDialect::materializeConstant(OpBuilder &b, Attribute value,
                                           Type type, Location loc) {
  if (auto bl = dyn_cast<BoolAttr>(value)) // before IntegerAttr: i1 integers
    return BoolOp::create(b, loc, type, bl);
  if (isa<UnitAttr>(value))
    return NullOp::create(b, loc, type);
  if (auto i = dyn_cast<IntegerAttr>(value))
    return IntOp::create(b, loc, type, i);
  if (auto f = dyn_cast<FloatAttr>(value))
    return FloatOp::create(b, loc, type, f);
  if (auto s = dyn_cast<StringAttr>(value))
    return StringOp::create(b, loc, type, s);
  return nullptr;
}

//===----------------------------------------------------------------------===//
// Region kinds: bodies are graph regions (recursive bindings = cyclic SSA).
//===----------------------------------------------------------------------===//

RegionKind ExprOp::getRegionKind(unsigned) { return RegionKind::Graph; }
RegionKind LambdaOp::getRegionKind(unsigned) { return RegionKind::Graph; }

//===----------------------------------------------------------------------===//
// Verifiers
//===----------------------------------------------------------------------===//

LogicalResult LambdaOp::verify() {
  Block &b = getBody().front();
  if (b.getNumArguments() != 1)
    return emitOpError("body must have exactly one block argument");
  if (!isa<ReturnOp>(b.back()))
    return emitOpError("body must end in nix.return");
  if (getFormals()) {
    if (!getFormalDefaults() ||
        getFormalDefaults()->size() != (int64_t)getFormals()->size())
      return emitOpError("formal_defaults must parallel formals");
  } else if (getEllipsis()) {
    return emitOpError("ellipsis requires formals");
  }
  return success();
}

LogicalResult SelectOp::verify() { return verifyAttrPath(*this, getPath(), getDynKeys().size()); }
LogicalResult HasAttrOp::verify() { return verifyAttrPath(*this, getPath(), getDynKeys().size()); }

LogicalResult AttrsOp::verify() {
  if (getNames().size() != getValues().size())
    return emitOpError("names and values must have equal length");
  if (getDynNames().size() != getDynValues().size())
    return emitOpError("dyn_names and dyn_values must have equal length");
  llvm::StringSet<llvm::MallocAllocator> seen;
  for (Attribute a : getNames())
    if (!seen.insert(cast<StringAttr>(a).getValue()).second)
      return emitOpError("duplicate attribute '")
             << cast<StringAttr>(a).getValue() << "'";
  return success();
}

//===----------------------------------------------------------------------===//
// Folders
//===----------------------------------------------------------------------===//

OpFoldResult IntOp::fold(FoldAdaptor) { return getValueAttr(); }
OpFoldResult FloatOp::fold(FoldAdaptor) { return getValueAttr(); }
OpFoldResult StringOp::fold(FoldAdaptor) { return getValueAttr(); }
OpFoldResult BoolOp::fold(FoldAdaptor) { return getValueAttr(); }
OpFoldResult NullOp::fold(FoldAdaptor) { return UnitAttr::get(getContext()); }

OpFoldResult ConcatStringsOp::fold(FoldAdaptor adaptor) {
  auto ops = adaptor.getParts();
  if (ops.empty())
    return {};
  for (Attribute a : ops)
    if (!a)
      return {};
  // `"a" + "b"`, `"${"a"}"`: all string literals.
  if (llvm::all_of(ops, [](Attribute a) { return isa<StringAttr>(a); })) {
    std::string s;
    for (Attribute a : ops)
      s += cast<StringAttr>(a).getValue();
    return StringAttr::get(getContext(), s);
  }
  if (getForceString())
    return {};
  // Integer addition with overflow check (overflow is a runtime error).
  if (llvm::all_of(ops, [](Attribute a) { return isa<IntegerAttr>(a); })) {
    int64_t acc = 0;
    for (Attribute a : ops)
      if (__builtin_add_overflow(acc, cast<IntegerAttr>(a).getInt(), &acc))
        return {};
    return IntegerAttr::get(IntegerType::get(getContext(), 64), acc);
  }
  return {};
}

//===----------------------------------------------------------------------===//
// nix-simplify: folding, builtin arithmetic folding, dead binding elimination
//===----------------------------------------------------------------------===//

namespace {

/// `nix.apply (builtin "__add"|builtins.add|...) a b` -> `nixnum.add(a, b)`:
/// the call of a known primop becomes an op of its continent dialect, whose
/// arity, effects and foldability are declared in NixPrims.irdl.mlir.  Calls with too
/// few arguments stay partial applications; extra arguments are applied to the
/// result.
struct DevirtualizePrimCall : OpRewritePattern<ApplyOp> {
  using OpRewritePattern::OpRewritePattern;
  LogicalResult matchAndRewrite(ApplyOp op, PatternRewriter &rw) const override {
    if (op.getArgs().empty())
      return failure();
    auto *core = getContext()->getLoadedDialect<NixDialect>();
    const NixDialect::PrimInfo *info = nullptr;
    Value callee = op.getCallee();
    if (auto b = callee.getDefiningOp<BuiltinOp>()) {
      auto it = core->prims.find(b.getName());
      if (it != core->prims.end())
        info = &it->second;
    } else if (auto sel = callee.getDefiningOp<SelectOp>()) {
      // builtins.<name>
      if (sel.getDefaultValue() || sel.getPath().size() != 1)
        return failure();
      auto base = sel.getBase().getDefiningOp<BuiltinOp>();
      auto key = dyn_cast<StringAttr>(sel.getPath()[0]);
      if (!base || base.getName() != "builtins" || !key)
        return failure();
      llvm::SmallString<48> internal("__");
      internal += key.getValue();
      auto it = core->prims.find(internal);
      if (it == core->prims.end())
        it = core->prims.find(key.getValue());
      if (it != core->prims.end())
        info = &it->second;
    }
    if (!info || op.getArgs().size() < info->arity)
      return failure();
    OperationState st(op.getLoc(), info->name);
    st.addOperands(op.getArgs().take_front(info->arity));
    st.addTypes(op.getType());
    Value res = rw.create(st)->getResult(0);
    if (op.getArgs().size() > info->arity)
      res = ApplyOp::create(rw, op.getLoc(), op.getType(), res, op.getArgs().drop_front(info->arity));
    rw.replaceOp(op, res);
    return success();
  }
};

/// `nix.apply %v()` (application to zero arguments) is the identity; it only
/// exists to give a binding its own value identity.  When nothing else uses
/// %v that identity is unobservable, so forward %v directly.
struct ForwardUnobservableIdentity : OpRewritePattern<ApplyOp> {
  using OpRewritePattern::OpRewritePattern;
  LogicalResult matchAndRewrite(ApplyOp op, PatternRewriter &rw) const override {
    if (!op.getArgs().empty()) return failure();
    Value callee = op.getCallee();
    if (callee == op.getResult() || !callee.hasOneUse()) return failure();
    // Placeholders/cycles: only forward values defined by real nix ops or
    // block arguments.
    if (Operation *d = callee.getDefiningOp())
      if (!isa<NixDialect>(d->getDialect())) return failure();
    rw.replaceOp(op, callee);
    return success();
  }
};

/// Core dialect or one of the continent dialects (nixnum, nixstr, ...).
bool isNixFamily(Operation *op) {
  return op->getDialect() && op->getDialect()->getNamespace().starts_with("nix");
}

/// Graph regions can hold dead *cycles* (unused recursive bindings) that the
/// generic dead-code elimination never removes. Mark from each terminator.
void eliminateDeadBindings(Operation *root) {
  llvm::DenseSet<Operation *> live;
  llvm::SmallVector<Operation *> work;
  root->walk([&](ExprOp e) {
    if (!e.getBody().empty())
      work.push_back(&e.getBody().front().back());
  });
  auto markValue = [&](Value v) {
    if (Operation *d = v.getDefiningOp())
      if (live.insert(d).second)
        work.push_back(d);
  };
  while (!work.empty()) {
    Operation *op = work.pop_back_val();
    live.insert(op);
    for (Value v : op->getOperands())
      markValue(v);
    if (auto lam = dyn_cast<LambdaOp>(op)) {
      Operation *ret = &lam.getBody().front().back();
      if (live.insert(ret).second)
        work.push_back(ret);
    }
    // The parent lambda of a live op is necessarily live already.
  }
  llvm::SmallVector<Operation *> dead;
  root->walk([&](Operation *op) {
    if (isNixFamily(op) && !isa<ExprOp>(op) && !live.contains(op))
      dead.push_back(op);
  });
  // Drop all uses first (cycles), then erase outermost-first is unsafe; erase
  // after dropping references.
  for (Operation *op : dead)
    op->dropAllReferences();
  for (Operation *op : dead) {
    // Nested ops of a dead lambda are erased with it.
    Operation *p = op->getParentOp();
    bool nestedInDead = false;
    while (p) {
      if (llvm::is_contained(dead, p)) { nestedInDead = true; break; }
      p = p->getParentOp();
    }
    if (!nestedInDead)
      op->erase();
  }
}

} // namespace

void mlir::nix::devirtualizePrims(Operation *root) {
  MLIRContext *ctx = root->getContext();
  RewritePatternSet patterns(ctx);
  patterns.add<DevirtualizePrimCall>(ctx);
  walkAndApplyPatterns(root, FrozenRewritePatternSet(std::move(patterns)));
  // The callee computations of rewritten calls are now unreferenced; erase
  // them, and whatever only they kept alive.
  llvm::SmallVector<Operation *> work;
  root->walk([&](Operation *op) {
    if (isa<BuiltinOp, SelectOp, StringOp>(op) && op->use_empty())
      work.push_back(op);
  });
  while (!work.empty()) {
    Operation *op = work.pop_back_val();
    llvm::SmallVector<Operation *, 4> producers;
    for (Value v : op->getOperands())
      if (Operation *d = v.getDefiningOp())
        producers.push_back(d);
    op->erase();
    for (Operation *d : producers)
      if (isa<BuiltinOp, SelectOp, StringOp>(d) && d->use_empty())
        work.push_back(d);
  }
}

namespace {

// The passes run on any op, so the same ones serve the evaluator (a `nix.expr`)
// and mlnix-opt (a module).  The continent dialects are defined when the core
// dialect loads, so a pass that creates or matches their ops makes sure it is.

struct NixPrimsPass : public PassWrapper<NixPrimsPass, OperationPass<>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(NixPrimsPass)
  StringRef getArgument() const override { return "nix-prims"; }
  StringRef getDescription() const override {
    return "Rewrite calls of known primops into continent-dialect ops";
  }
  void getDependentDialects(DialectRegistry &registry) const override { registerNixDialects(registry); }
  void runOnOperation() override { devirtualizePrims(getOperation()); }
};

struct NixFoldPass : public PassWrapper<NixFoldPass, OperationPass<>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(NixFoldPass)
  StringRef getArgument() const override { return "nix-fold"; }
  StringRef getDescription() const override {
    return "Canonicalize and constant-fold Nix IR (every foldable primop, generically)";
  }
  void getDependentDialects(DialectRegistry &registry) const override { registerNixDialects(registry); }
  LogicalResult initialize(MLIRContext *ctx) override {
    RewritePatternSet patterns(ctx);
    patterns.add<ForwardUnobservableIdentity>(ctx);
    for (RegisteredOperationName op : ctx->getRegisteredOperations())
      if (op.getDialect().getNamespace().starts_with("nix"))
        op.getCanonicalizationPatterns(patterns, ctx);
    frozen = FrozenRewritePatternSet(std::move(patterns));
    return success();
  }
  void runOnOperation() override {
    GreedyRewriteConfig cfg;
    cfg.setRegionSimplificationLevel(GreedySimplifyRegionLevel::Disabled);
    cfg.enableConstantCSE(false);
    (void)applyPatternsGreedily(getOperation(), frozen, cfg);
  }
  FrozenRewritePatternSet frozen;
};

struct NixDcePass : public PassWrapper<NixDcePass, OperationPass<>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(NixDcePass)
  StringRef getArgument() const override { return "nix-dce"; }
  StringRef getDescription() const override {
    return "Remove unreferenced bindings, including dead recursive cycles";
  }
  void runOnOperation() override { eliminateDeadBindings(getOperation()); }
};
} // namespace

void mlir::nix::registerNixPasses() {
  static std::once_flag once;
  std::call_once(once, [] {
    PassRegistration<NixPrimsPass>();
    PassRegistration<NixFoldPass>();
    PassRegistration<NixDcePass>();
    PassPipelineRegistration<>("nix-simplify",
                               "Devirtualize primops, fold constants, remove dead (cyclic) bindings",
                               [](OpPassManager &pm) {
                                 pm.addPass(std::make_unique<NixPrimsPass>());
                                 pm.addPass(std::make_unique<NixFoldPass>());
                                 pm.addPass(std::make_unique<NixDcePass>());
                               });
  });
}
