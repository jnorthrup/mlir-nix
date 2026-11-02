//===- KifDialect.cpp - The KIF dialect, and kif-to-nix ---------------------===//

#include "NixDialect/Kif.h"
#include "NixDialect/NixDialect.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/DialectImplementation.h"
#include "mlir/Pass/Pass.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/TypeSwitch.h"

#include "NixDialect/KifDialect.cpp.inc"

#define GET_TYPEDEF_CLASSES
#include "NixDialect/KifTypes.cpp.inc"

#define GET_OP_CLASSES
#include "NixDialect/Kif.cpp.inc"

namespace mlir::kif {

void KifDialect::initialize() {
  addTypes<
#define GET_TYPEDEF_LIST
#include "NixDialect/KifTypes.cpp.inc"
      >();
  addOperations<
#define GET_OP_LIST
#include "NixDialect/Kif.cpp.inc"
      >();
}

RegionKind TheoryOp::getRegionKind(unsigned) { return RegionKind::Graph; }

LogicalResult VarOp::verify() {
  if (!getName().starts_with("?") || getName().size() < 2)
    return emitOpError("a variable's name starts with ? and has a name after it");
  return success();
}

namespace {
/// Terms are nodes of a graph region, so a term can use one defined after it: lowering follows the definitions.
struct Lowering {
  OpBuilder &b;
  Location loc;
  Type value;
  DenseMap<Value, Value> done{};

  Value str(StringRef s) { return nix::StringOp::create(b, loc, value, nixfe::Name::persist(s)); }
  Value list(ValueRange xs) { return nix::ListOp::create(b, loc, value, xs); }

  Value term(Value t) {
    if (auto it = done.find(t); it != done.end())
      return it->second;
    Operation *def = t.getDefiningOp();
    Value out;
    if (auto atom = dyn_cast<AtomOp>(def))
      out = str(atom.getName());
    else if (auto var = dyn_cast<VarOp>(def))
      out = str(var.getName());
    else {
      SmallVector<Value> elements;
      for (Value e : cast<ListOp>(def).getElements())
        elements.push_back(term(e));
      out = list(elements);
    }
    return done[t] = out;
  }
};

struct KifToNixPass : PassWrapper<KifToNixPass, OperationPass<ModuleOp>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(KifToNixPass)
  StringRef getArgument() const override { return "kif-to-nix"; }
  StringRef getDescription() const override { return "Lower a kif.theory to a nix.expr of its facts and rules"; }
  void getDependentDialects(DialectRegistry &registry) const override { registry.insert<nix::NixDialect>(); }

  void runOnOperation() override {
    SmallVector<TheoryOp> theories;
    getOperation().walk([&](TheoryOp t) { theories.push_back(t); });
    for (TheoryOp theory : theories) {
      for (Operation &op : theory.getBody().front())
        if (!isa<AtomOp, VarOp, ListOp, FactOp, RuleOp>(op)) {
          op.emitOpError("is not KIF: lower it with sumo-to-kif first");
          return signalPassFailure();
        }
      OpBuilder b(theory);
      Location loc = theory.getLoc();
      auto expr = nix::ExprOp::create(b, loc, theory.getSymNameAttr(), StringAttr(), StringAttr());
      b.setInsertionPointToStart(&expr.getBody().emplaceBlock());
      Lowering lower{b, loc, nix::ValueType::get(b.getContext())};
      SmallVector<Value> facts, rules;
      for (Operation &op : theory.getBody().front()) {
        if (auto fact = dyn_cast<FactOp>(op))
          facts.push_back(lower.term(fact.getTerm()));
        else if (auto rule = dyn_cast<RuleOp>(op))
          rules.push_back(lower.list({lower.str("=>"), lower.term(rule.getAntecedent()), lower.term(rule.getConsequent())}));
      }
      Value members[] = {lower.list(facts), lower.list(rules)};
      Value result = nix::AttrsOp::create(b, loc, lower.value, {nixfe::Name::persist("facts"), nixfe::Name::persist("rules")},
                                          members, ValueRange(), ValueRange(), {0, 0});
      nix::ReturnOp::create(b, loc, result);
      theory.erase();
    }
  }
};
} // namespace

void registerKifPasses() {
  static const bool registered = [] {
    PassRegistration<KifToNixPass>();
    return true;
  }();
  (void)registered;
}

} // namespace mlir::kif
