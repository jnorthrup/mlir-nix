//===- EvalModels.cpp - Evaluation semantics as an external interface model ===//
//
// The dialects define *what* an op is (operands, effects, folds); how the lazy
// evaluator *runs* it is attached from outside as a NixEvalOpInterface model.
// The 105 primop ops of the 11 continent dialects (defined at run time from
// IRDL, so they have no C++ classes) are all evaluated by this one model, which
// finds the primop through the core dialect's table.
//
//===----------------------------------------------------------------------===//

#include "Nix/Eval.h"
#include "NixDialect/NixDialect.h"

using namespace mlir;
namespace nd = mlir::nix;

namespace nixev {
namespace {

struct PrimEvalModel : public nd::NixEvalOpInterface::FallbackModel<PrimEvalModel> {
  void eval(Operation *op, EvalState &st, Frame *env, Value &out) const {
    const PrimOp *prim = st.primFor(op);
    constexpr unsigned kMaxArity = 8;
    Value *args[kMaxArity];
    unsigned n = op->getNumOperands();
    assert(n <= kMaxArity && "primop arity above the evaluator's limit");
    for (unsigned i = 0; i < n; i++) args[i] = st.lookup(env, op->getOperand(i));
    st.callPrimOp(*prim, args, out, op->getLoc().getAsOpaquePointer());
  }
};

} // namespace

const PrimOp *EvalState::primFor(Operation *op) {
  const void *k = op->getName().getAsOpaquePointer();
  auto it = primForOp.find(k);
  if (it != primForOp.end()) return it->second;
  const auto *info = ctx.getLoadedDialect<nd::NixDialect>()->primOf(op);
  const PrimOp *p = primOpByKey(info->key);
  if (!p)
    throw EvalError("primop '" + info->key.str() + "' is declared in the IRDL but has no implementation",
                    op->getLoc().getAsOpaquePointer());
  primForOp[k] = p;
  return p;
}

void registerEvalModels(MLIRContext &ctx) {
  auto *core = ctx.getLoadedDialect<nd::NixDialect>();
  for (auto &entry : core->prims) {
    OperationName name = entry.second.name;
    if (!name.hasInterface<nd::NixEvalOpInterface>()) name.attachInterface<PrimEvalModel>();
  }
}

} // namespace nixev
