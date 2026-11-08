//===- SumoDialect.cpp - The SUMO dialect, and sumo-to-kif ------------------===//

#include "NixDialect/Sumo.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/DialectImplementation.h"
#include "mlir/Pass/Pass.h"
#include "llvm/ADT/SmallString.h"

#include "NixDialect/SumoDialect.cpp.inc"

#define GET_OP_CLASSES
#include "NixDialect/Sumo.cpp.inc"

namespace mlir::sumo {

void SumoDialect::initialize() {
  addOperations<
#define GET_OP_LIST
#include "NixDialect/Sumo.cpp.inc"
      >();
}

namespace {
/// `(word word ..)` as a fact, just before op.
void fact(Operation *op, ArrayRef<StringRef> words) {
  OpBuilder b(op);
  auto term = b.getType<kif::TermType>();
  SmallVector<Value> atoms;
  for (StringRef w : words)
    atoms.push_back(kif::AtomOp::create(b, op->getLoc(), term, b.getStringAttr(w)));
  kif::FactOp::create(b, op->getLoc(), kif::ListOp::create(b, op->getLoc(), term, atoms), IntegerAttr());
}

struct SumoToKifPass : PassWrapper<SumoToKifPass, OperationPass<ModuleOp>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(SumoToKifPass)
  StringRef getArgument() const override { return "sumo-to-kif"; }
  StringRef getDescription() const override { return "Lower sumo relations to kif facts"; }
  void getDependentDialects(DialectRegistry &registry) const override { registry.insert<kif::KifDialect>(); }

  void runOnOperation() override {
    SmallVector<Operation *> ops;
    getOperation().walk([&](Operation *op) {
      if (isa<SubclassOp, InstanceOp, DomainOp, RangeOp, HoldsOp>(op))
        ops.push_back(op);
    });
    for (Operation *op : ops) {
      SmallString<16> pos; // a position's decimal digits: the one word not already held by the context
      if (auto s = dyn_cast<SubclassOp>(op))
        fact(op, {"subclass", s.getChild(), s.getParent()});
      else if (auto i = dyn_cast<InstanceOp>(op))
        fact(op, {"instance", i.getThing(), i.getClassName()});
      else if (auto d = dyn_cast<DomainOp>(op))
        fact(op, {"domain", d.getRelation(), Twine(d.getPosition()).toStringRef(pos), d.getClassName()});
      else if (auto r = dyn_cast<RangeOp>(op))
        fact(op, {"range", r.getRelation(), Twine(r.getPosition()).toStringRef(pos), r.getClassName()});
      else {
        auto h = cast<HoldsOp>(op);
        SmallVector<StringRef> words{h.getRelation()}; // views on the context's uniqued attributes
        for (Attribute a : h.getArgs())
          words.push_back(cast<StringAttr>(a).getValue());
        fact(op, words);
      }
      op->erase();
    }
  }
};
} // namespace

void registerSumoPasses() {
  static const bool registered = [] {
    PassRegistration<SumoToKifPass>();
    return true;
  }();
  (void)registered;
}

} // namespace mlir::sumo
