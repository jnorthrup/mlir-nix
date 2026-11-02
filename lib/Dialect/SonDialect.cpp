//===- SonDialect.cpp - The son dialect, nix-defer and son-mint ------------===//

#include "NixDialect/Son.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Transforms/RegionUtils.h"

#include "NixDialect/SonDialect.cpp.inc"

#define GET_OP_CLASSES
#include "NixDialect/Son.cpp.inc"

namespace mlir::son {

void SonDialect::initialize() {
  addOperations<
#define GET_OP_LIST
#include "NixDialect/Son.cpp.inc"
      >();
}

RegionKind BodyOp::getRegionKind(unsigned) { return RegionKind::Graph; }

LogicalResult BodyOp::verify() {
  Block &entry = getBody().front();
  if (entry.getNumArguments() != getCaptures() + 1)
    return emitOpError("takes its captures and then the lambda's argument: ") << getCaptures() + 1 << " block arguments";
  for (BlockArgument a : entry.getArguments())
    if (!isa<nix::ValueType>(a.getType()))
      return emitOpError("takes only !nix.value arguments");
  return success();
}

LogicalResult DeferOp::verifySymbolUses(SymbolTableCollection &symbols) {
  // From the module: a defer inside a body sits in the pool's own symbol table, and the reference starts at the pool.
  auto body = dyn_cast_or_null<BodyOp>(symbols.lookupSymbolIn((*this)->getParentOfType<ModuleOp>(), getRowAttr()));
  if (!body)
    return emitOpError("refers to ") << getRowAttr() << ", which is no son.body";
  if (body.getCaptures() != getCaptures().size())
    return emitOpError("binds ") << getCaptures().size() << " captures, the body takes " << body.getCaptures();
  return success();
}

namespace {
constexpr StringLiteral kPool = "bodies";

/// The module's pool, made at its end when there is none.
PoolOp poolOf(ModuleOp module) {
  if (auto pool = module.lookupSymbol<PoolOp>(kPool))
    return pool;
  OpBuilder b = OpBuilder::atBlockEnd(module.getBody());
  PoolOp pool = PoolOp::create(b, module.getLoc(), b.getStringAttr(kPool));
  pool.getRows().emplaceBlock();
  return pool;
}

struct NixDeferPass : PassWrapper<NixDeferPass, OperationPass<ModuleOp>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(NixDeferPass)
  StringRef getArgument() const override { return "nix-defer"; }
  StringRef getDescription() const override { return "Move each nix.lambda body to a son.pool row; the lambda becomes son.defer"; }
  void getDependentDialects(DialectRegistry &registry) const override { registry.insert<SonDialect>(); }

  void runOnOperation() override {
    ModuleOp module = getOperation();
    SmallVector<nix::LambdaOp> lambdas;
    module.walk([&](nix::LambdaOp l) { lambdas.push_back(l); }); // outer before inner: process in reverse
    if (lambdas.empty())
      return;
    PoolOp pool = poolOf(module);
    unsigned row = pool.getRows().front().getOperations().size();
    for (nix::LambdaOp lambda : llvm::reverse(lambdas)) {
      if (lambda.getBody().empty())
        continue; // a deferred shell of the evaluator: no body to move
      Region &body = lambda.getBody();
      SetVector<Value> captured;
      getUsedValuesDefinedAbove(body, captured);

      OpBuilder b = OpBuilder::atBlockEnd(&pool.getRows().front());
      Attribute props = lambda->getPropertiesAsAttribute();
      std::string name = ("row" + Twine(row++)).str();
      auto bodyOp = BodyOp::create(b, lambda.getLoc(), b.getStringAttr(name), captured.size(), props);
      Type value = nix::ValueType::get(&getContext());
      SmallVector<Type> types(captured.size() + 1, value);
      SmallVector<Location> locs(captured.size() + 1, lambda.getLoc());
      Block *entry = &bodyOp.getBody().emplaceBlock();
      entry->addArguments(types, locs);

      Block &old = body.front();
      old.getArgument(0).replaceAllUsesWith(entry->getArgument(captured.size()));
      for (auto [i, c] : llvm::enumerate(captured)) {
        Value capture = c;
        capture.replaceUsesWithIf(entry->getArgument(i), [&](OpOperand &use) { return body.isAncestor(use.getOwner()->getParentRegion()); });
      }
      entry->getOperations().splice(entry->end(), old.getOperations());

      OpBuilder at(lambda);
      auto ref = SymbolRefAttr::get(&getContext(), kPool, {FlatSymbolRefAttr::get(&getContext(), name)});
      auto defer = DeferOp::create(at, lambda.getLoc(), value, ref, captured.getArrayRef());
      lambda.getResult().replaceAllUsesWith(defer);
      lambda.erase();
    }
  }
};

struct SonMintPass : PassWrapper<SonMintPass, OperationPass<ModuleOp>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(SonMintPass)
  StringRef getArgument() const override { return "son-mint"; }
  StringRef getDescription() const override { return "Make every son.defer a nix.lambda with its body; drop the pool"; }

  void runOnOperation() override {
    ModuleOp module = getOperation();
    auto pool = module.lookupSymbol<PoolOp>(kPool);
    if (!pool)
      return;
    for (bool again = true; again;) { // a minted body can hold defers of its own
      again = false;
      SmallVector<DeferOp> defers;
      module.walk([&](DeferOp d) {
        if (!d->getParentOfType<PoolOp>())
          defers.push_back(d);
      });
      for (DeferOp defer : defers) {
        auto row = cast<BodyOp>(SymbolTable::lookupSymbolIn(module, defer.getRowAttr()));
        OpBuilder b(defer);
        OperationState state(defer.getLoc(), nix::LambdaOp::getOperationName());
        state.addTypes(defer.getType());
        state.addRegion();
        Operation *lambda = b.create(state);
        if (failed(lambda->setPropertiesFromAttribute(row.getLambda(), [&] { return row.emitOpError(); })))
          return signalPassFailure();
        IRMapping mapping;
        row.getBody().cloneInto(&lambda->getRegion(0), mapping);
        Block &entry = lambda->getRegion(0).front();
        for (auto [i, c] : llvm::enumerate(defer.getCaptures()))
          entry.getArgument(i).replaceAllUsesWith(c);
        entry.eraseArguments(0, row.getCaptures());
        defer.getResult().replaceAllUsesWith(lambda->getResult(0));
        defer.erase();
        again = true;
      }
    }
    pool.erase();
  }
};
} // namespace

void registerSonPasses() {
  static const bool registered = [] {
    PassRegistration<NixDeferPass>();
    PassRegistration<SonMintPass>();
    return true;
  }();
  (void)registered;
}

} // namespace mlir::son
