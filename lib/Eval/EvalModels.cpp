//===- EvalModels.cpp - Evaluation semantics as external interface models --===//
//
// The dialects define *what* an op is (operands, effects, folds); how the lazy
// evaluator *runs* it is attached from outside as a NixEvalOpInterface model.
// A primop op of any continent is evaluated by one template, which replaces
// both the `builtin` + `select` + `apply` chain of the generic encoding and
// the chain of dyn_casts the interpreter would need to tell 105 ops apart.
//
//===----------------------------------------------------------------------===//

#include "Nix/Eval.h"
#include "NixDialect/NixPrims.h"

using namespace mlir;
namespace nd = mlir::nix;

namespace nixev {
namespace {

template <class OpT>
struct PrimEvalModel : public nd::NixEvalOpInterface::ExternalModel<PrimEvalModel<OpT>, OpT> {
  void eval(Operation *op, EvalState &st, Frame *env, Value &out) const {
    // One cached lookup per op class and evaluator (statics are zero-initialised,
    // so there is no guard on the fast path).
    static EvalState *cachedFor;
    static const PrimOp *prim;
    if (cachedFor != &st) {
      prim = st.primOpByKey(OpT::primKey);
      cachedFor = &st;
    }
    Value *args[OpT::primArity > 0 ? OpT::primArity : 1];
    for (unsigned i = 0; i < OpT::primArity; i++) args[i] = st.lookup(env, op->getOperand(i));
    st.callPrimOp(*prim, args, out, op->getLoc().getAsOpaquePointer());
  }
};

template <class... Ops>
void attachPrimModels(MLIRContext &ctx) {
  (Ops::template attachInterface<PrimEvalModel<Ops>>(ctx), ...);
}

} // namespace

void registerEvalModels(MLIRContext &ctx) {
  attachPrimModels<
#define GET_OP_LIST
#include "NixDialect/NixnumOps.cpp.inc"
      >(ctx);
  attachPrimModels<
#define GET_OP_LIST
#include "NixDialect/NixtyOps.cpp.inc"
      >(ctx);
  attachPrimModels<
#define GET_OP_LIST
#include "NixDialect/NixstrOps.cpp.inc"
      >(ctx);
  attachPrimModels<
#define GET_OP_LIST
#include "NixDialect/NixctxOps.cpp.inc"
      >(ctx);
  attachPrimModels<
#define GET_OP_LIST
#include "NixDialect/NixlistOps.cpp.inc"
      >(ctx);
  attachPrimModels<
#define GET_OP_LIST
#include "NixDialect/NixattrOps.cpp.inc"
      >(ctx);
  attachPrimModels<
#define GET_OP_LIST
#include "NixDialect/NixpathOps.cpp.inc"
      >(ctx);
  attachPrimModels<
#define GET_OP_LIST
#include "NixDialect/NixstoreOps.cpp.inc"
      >(ctx);
  attachPrimModels<
#define GET_OP_LIST
#include "NixDialect/NixhashOps.cpp.inc"
      >(ctx);
  attachPrimModels<
#define GET_OP_LIST
#include "NixDialect/NixfmtOps.cpp.inc"
      >(ctx);
  attachPrimModels<
#define GET_OP_LIST
#include "NixDialect/NixctlOps.cpp.inc"
      >(ctx);
}

} // namespace nixev
