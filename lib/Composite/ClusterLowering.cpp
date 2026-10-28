#include "Composite/TrikeShed.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassRegistry.h"

using namespace mlir;
namespace composite {
namespace {
struct LowerClusters : PassWrapper<LowerClusters, OperationPass<ModuleOp>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(LowerClusters)
  StringRef getArgument() const final { return "trikeshed-lower-clusters"; }
  StringRef getDescription() const final { return "Run bounded cluster ordering through its native kernel"; }
  void getDependentDialects(DialectRegistry &r) const final { r.insert<func::FuncDialect, memref::MemRefDialect>(); }
  void runOnOperation() final {
    auto module = getOperation();
    SmallVector<ClusterOrderOp> ops;
    module.walk([&](ClusterOrderOp op) { ops.push_back(op); });
    if (ops.empty()) return;
    OpBuilder b(&getContext());
    auto dynamic = ShapedType::kDynamic;
    auto buffer = MemRefType::get({dynamic}, b.getI64Type(), StridedLayoutAttr::get(&getContext(), dynamic, {dynamic}));
    auto type = b.getFunctionType({buffer, buffer}, {b.getI1Type()});
    constexpr StringLiteral name = "trikeshed_cluster_order";
    auto symbol = module.lookupSymbol(name);
    auto fn = dyn_cast_or_null<func::FuncOp>(symbol);
    if (symbol && (!fn || fn.getFunctionType() != type || !fn.isExternal())) {
      symbol->emitError("conflicts with the cluster runtime declaration");
      signalPassFailure();
      return;
    }
    if (!fn) {
      b.setInsertionPointToStart(module.getBody());
      fn = func::FuncOp::create(b, module.getLoc(), name, type);
      fn.setPrivate();
    }
    fn->setAttr("llvm.emit_c_interface", b.getUnitAttr());
    for (auto op : ops) {
      b.setInsertionPoint(op);
      SmallVector<Value> args;
      for (auto v : op->getOperands())
        args.push_back(v.getType() == buffer ? v : memref::CastOp::create(b, op.getLoc(), buffer, v).getResult());
      auto call = func::CallOp::create(b, op.getLoc(), fn, args);
      op.getAccepted().replaceAllUsesWith(call.getResult(0));
      op.erase();
    }
  }
};
} // namespace
void registerTrikeShedPasses() { PassRegistration<LowerClusters>(); }
} // namespace composite
