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
<<<<<<< HEAD
    const PrimOp *prim = st.primFor(op);
    constexpr unsigned kMaxArity = 8;
    Value *args[kMaxArity];
    unsigned n = op->getNumOperands();
    assert(n <= kMaxArity && "primop arity above the evaluator's limit");
    for (unsigned i = 0; i < n; i++) args[i] = st.lookup(env, op->getOperand(i));
    st.callPrimOp(*prim, args, out, nd::posOfOp(op));
    if (getenv("MLNIX_CHECK_KINDS")) [[unlikely]] st.checkResultKind(op, out); // the slow path: no cached flag needed
||||||| 11b03dd
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
=======
    // One cached lookup per op class and evaluator (statics are zero-initialised,
    // so there is no guard on the fast path).
    static EvalState *cachedFor;
    static const PrimOp *prim;
    if (cachedFor != &st) {
      prim = st.primOpByKey(OpT::primKey);
      cachedFor = &st;
    }
    // Operands are left lazy here even though most primops force every one
    // of them immediately: a few (seq, deepSeq, tryEval) deliberately don't,
    // or need to control *when* an operand is forced (tryEval wraps forcing
    // in its own try/catch). Eagerly forcing in this shared template would
    // force those operands before the primop's own logic gets a say. Purity
    // (no memory effects) is not the same property as "forces every operand
    // unconditionally", so it can't be used to tell the two groups apart
    // here; doing this safely needs a per-op marker, not an effect check.
    Value *args[OpT::primArity > 0 ? OpT::primArity : 1];
    for (unsigned i = 0; i < OpT::primArity; i++) args[i] = st.lookup(env, op->getOperand(i));
    st.callPrimOp(*prim, args, out, op->getLoc().getAsOpaquePointer());
>>>>>>> 7e8a58de096581fe4a1b239d6a064025fd7390a4
  }
};

} // namespace

const PrimOp *EvalState::primFor(Operation *op) {
  const void *k = op->getName().getAsOpaquePointer();
  if (const PrimOp **found = primForOp.find(uint64_t(uintptr_t(k)))) return *found;
  const auto *info = ctx.getLoadedDialect<nd::NixDialect>()->primOf(op);
  const PrimOp *p = primOpByKey(info->key);
  if (!p)
    throw EvalError("primop '" + info->key.str() + "' is declared in the IRDL but has no implementation",
                    nd::posOfOp(op));
  primForOp.insert(uint64_t(uintptr_t(k)), p);
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
