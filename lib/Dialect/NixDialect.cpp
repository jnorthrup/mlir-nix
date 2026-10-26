//===- NixDialect.cpp - Nix dialect implementation ------------------------===//

#include "NixDialect/NixDialect.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/DialectImplementation.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassRegistry.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"
#include "llvm/ADT/SetVector.h"
#include "llvm/ADT/StringSet.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/TypeSwitch.h"

using namespace mlir;
using namespace mlir::nix;

#include "NixDialect/NixDialect.cpp.inc"

#define GET_TYPEDEF_CLASSES
#include "NixDialect/NixTypes.cpp.inc"

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

/// apply(builtin "__sub"|"__mul"|"__div", int, int) -> int
struct FoldBuiltinArith : OpRewritePattern<ApplyOp> {
  using OpRewritePattern::OpRewritePattern;
  LogicalResult matchAndRewrite(ApplyOp op, PatternRewriter &rw) const override {
    auto b = op.getCallee().getDefiningOp<BuiltinOp>();
    if (!b || op.getArgs().size() != 2)
      return failure();
    auto l = op.getArgs()[0].getDefiningOp<IntOp>();
    auto r = op.getArgs()[1].getDefiningOp<IntOp>();
    if (!l || !r)
      return failure();
    int64_t x = l.getValue(), y = r.getValue(), z;
    StringRef n = b.getName();
    if (n == "__sub") {
      if (__builtin_sub_overflow(x, y, &z)) return failure();
    } else if (n == "__mul") {
      if (__builtin_mul_overflow(x, y, &z)) return failure();
    } else if (n == "__div") {
      if (y == 0 || (x == INT64_MIN && y == -1)) return failure();
      z = x / y;
    } else {
      return failure();
    }
    rw.replaceOp(op, IntOp::create(rw, op.getLoc(), op.getType(), rw.getI64IntegerAttr(z)));
    return success();
  }
};

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
    if (op->getDialect() && isa<NixDialect>(op->getDialect()) &&
        !isa<ExprOp>(op) && !live.contains(op))
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

struct NixSimplifyPass
    : public PassWrapper<NixSimplifyPass, OperationPass<ModuleOp>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(NixSimplifyPass)
  StringRef getArgument() const override { return "nix-simplify"; }
  StringRef getDescription() const override {
    return "Fold constants/builtin arithmetic and remove dead (cyclic) bindings";
  }
  void runOnOperation() override {
    RewritePatternSet patterns(&getContext());
    patterns.add<FoldBuiltinArith>(&getContext());
    for (RegisteredOperationName op : getContext().getRegisteredOperations())
      if (op.getDialect().getNamespace() == "nix")
        op.getCanonicalizationPatterns(patterns, &getContext());
    GreedyRewriteConfig cfg;
    cfg.setRegionSimplificationLevel(GreedySimplifyRegionLevel::Disabled);
    if (failed(applyPatternsGreedily(getOperation(), std::move(patterns), cfg)))
      return signalPassFailure();
    eliminateDeadBindings(getOperation());
  }
};
} // namespace

std::unique_ptr<Pass> mlir::nix::createNixSimplifyPass() {
  return std::make_unique<NixSimplifyPass>();
}

void mlir::nix::registerNixPasses() { PassRegistration<NixSimplifyPass>(); }
