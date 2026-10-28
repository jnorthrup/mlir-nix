//===- EvalModels.cpp - Evaluation semantics as an external interface model ===//
//
// The dialects define *what* an op is (operands, effects, folds); how the lazy
// evaluator *runs* it is attached from outside as a NixEvalOpInterface model.
// Core operations and the IRDL-defined continent operations use the same
// interface. The evaluator needs no central switch over their classes.
//
//===----------------------------------------------------------------------===//

#include "Nix/Eval.h"
#include "NixDialect/NixDialect.h"

using namespace mlir;
namespace nd = mlir::nix;

namespace nixev {
namespace {

struct CoreEval {
  EvalState &st;
  Frame *env;
  Value &out;
  PosPtr pos;
  void copyFrom(Value *v) { st.forceValue(*v, pos); out = *v; }
  void operator()(nd::ListOp l) { st.mkList(out, l.getElements() |cp::α| [&](mlir::Value x) { return st.lookup(env, x); }); }
  void operator()(nd::AttrsOp a) { st.evalAttrs(a, env, out); }
  void operator()(nd::SelectOp sel) {
    mlir::OperandRange dyn = sel.getDynKeys();
    Value tb;
    Value *cur = dyn.empty() ? &st.operand(env, sel.getBase(), tb) : st.lookup(env, sel.getBase());
    mlir::Value def = sel.getDefaultValue();
    unsigned nextDyn = 0;
    for (const nixfe::Name &comp : sel.getPath()) {
      Symbol sym = st.pathSymbol(comp, dyn, nextDyn, env, pos);
      st.forceValue(*cur, pos);
      if (def) {
        if (cur->type != VType::Attrs) return copyFrom(st.lookup(env, def));
      } else if (cur->type != VType::Attrs) {
        st.throwTypeError("a set", *cur, pos, "while selecting an attribute");
      }
      const Attr *a = cur->attrs->get(sym);
      if (!a) {
        if (def) return copyFrom(st.lookup(env, def));
        throw EvalError("attribute '" + std::string(st.symbols[sym].str()) + "' missing", pos);
      }
      cur = a->value;
    }
    copyFrom(cur);
  }
  void operator()(nd::HasAttrOp h) {
    mlir::OperandRange dyn = h.getDynKeys();
    Value tb;
    Value *cur = dyn.empty() ? &st.operand(env, h.getBase(), tb) : st.lookup(env, h.getBase());
    unsigned nextDyn = 0;
    for (const nixfe::Name &comp : h.getPath()) {
      st.forceValue(*cur, pos);
      Symbol sym = st.pathSymbol(comp, dyn, nextDyn, env, pos);
      if (cur->type != VType::Attrs) return st.mkBool(out, false);
      const Attr *a = cur->attrs->get(sym);
      if (!a) return st.mkBool(out, false);
      cur = a->value;
    }
    st.mkBool(out, true);
  }
  void operator()(nd::ApplyOp ap) {
    Value *f = st.lookup(env, ap.getCallee());
    auto args = llvm::to_vector<4>(llvm::map_range(ap.getArgs(), [&](mlir::Value a) { return st.lookup(env, a); }));
    st.callFunction(*f, args.size(), args.data(), out, pos);
  }
  void operator()(nd::IfOp i) {
    Value tc;
    bool c = st.forceBool(st.operand(env, i.getCond(), tc), pos, "while evaluating a branch condition");
    st.evalTail(env, c ? i.getThenValue() : i.getElseValue(), out, pos);
  }
  void operator()(nd::AssertOp a) {
    Value tc;
    bool c = st.forceBool(st.operand(env, a.getCond(), tc), pos, "in the condition of the assert statement");
    if (!c) {
      std::string txt = a.getText() ? a.getText()->str() : "?";
      throw AssertionError("assertion '" + txt + "' failed", pos);
    }
    st.evalTail(env, a.getBody(), out, pos);
  }
  void operator()(nd::NotOp n) {
    Value t;
    st.mkBool(out, !st.forceBool(st.operand(env, n.getOperand(), t), pos, "in the argument of the not operator"));
  }
  template <class Op> void logical(Op o, bool stop, bool answer, const char *left, const char *right) {
    Value t1, t2;
    if (st.forceBool(st.operand(env, o.getLhs(), t1), pos, left) == stop) return st.mkBool(out, answer);
    st.mkBool(out, st.forceBool(st.operand(env, o.getRhs(), t2), pos, right));
  }
  void operator()(nd::AndOp o) {
    logical(o, false, false, "in the left operand of the AND (&&) operator", "in the right operand of the AND (&&) operator");
  }
  void operator()(nd::OrOp o) {
    logical(o, true, true, "in the left operand of the OR (||) operator", "in the right operand of the OR (||) operator");
  }
  void operator()(nd::ImplOp o) {
    logical(o, false, true, "in the left operand of the IMPL (->) operator", "in the right operand of the IMPL (->) operator");
  }
  template <class Op> void compare(Op e, bool negate) {
    Value ta, tb;
    Value &ra = st.operand(env, e.getLhs(), ta);
    st.forceValue(ra, pos);
    Value &rb = st.operand(env, e.getRhs(), tb);
    st.forceValue(rb, pos);
    Value a = ra, b = rb;
    st.mkBool(out, negate != st.eqValues(a, b, pos));
  }
  void operator()(nd::EqOp e) { compare(e, false); }
  void operator()(nd::NeqOp e) { compare(e, true); }
  void operator()(nd::UpdateOp u) {
    Value tl, tr;
    Value *l = &st.operand(env, u.getLhs(), tl);
    st.forceAttrs(*l, pos, "in the left operand of the update (//) operator");
    Value *r = &st.operand(env, u.getRhs(), tr);
    st.forceAttrs(*r, pos, "in the right operand of the update (//) operator");
    if (l->attrs->empty()) { out = *r; return; }
    if (r->attrs->empty()) { out = *l; return; }
    st.mkAttrs(out, st.updateAttrs(l->attrs, r->attrs));
  }
  void operator()(nd::ConcatListsOp c) {
    Value tl, tr;
    Value *l = &st.operand(env, c.getLhs(), tl);
    st.forceList(*l, pos, "in the left operand of the list concatenation operator");
    Value *r = &st.operand(env, c.getRhs(), tr);
    st.forceList(*r, pos, "in the right operand of the list concatenation operator");
    if (l->listSize() == 0) { out = *r; return; }
    if (r->listSize() == 0) { out = *l; return; }
    st.mkList(out, l->items() + r->items());
  }
  void operator()(nd::ConcatStringsOp c) { st.evalConcatStrings(c, env, out); }
  void operator()(nd::WithVarOp w) {
    Symbol sym = st.symbolOf(w.getName());
    for (mlir::Value sc : w.getScopes()) {
      Value *sv = st.lookup(env, sc);
      st.forceAttrs(*sv, nd::posOfValue(sc), "while evaluating the first subexpression of a with expression");
      if (const Attr *a = sv->attrs->get(sym)) return copyFrom(a->value);
    }
    throw EvalError("undefined variable '" + w.getName().toString() + "'", pos);
  }
  void operator()(nd::FormalOp f) {
    Value *arg = st.lookup(env, f.getArg());
    st.forceAttrs(*arg, pos);
    if (const Attr *a = arg->attrs->get(st.symbolOf(f.getName()))) return copyFrom(a->value);
    if (!f.getDefaultValue()) throw EvalError("missing formal argument '" + f.getName().toString() + "'", pos);
    copyFrom(st.lookup(env, f.getDefaultValue()));
  }
  void operator()(nd::IntOp i) { st.mkInt(out, i.getValue()); }
  void operator()(nd::BoolOp b) { st.mkBool(out, b.getValue()); }
  void operator()(nd::NullOp) { st.mkNull(out); }
  void operator()(nd::FloatOp f) { st.mkFloat(out, f.getValue().convertToDouble()); }
  void operator()(nd::StringOp s) { st.mkString(out, s.getValue().str()); }
  void operator()(nd::PathOp p) { st.mkPath(out, p.getValue().str()); }
  void operator()(nd::BuiltinOp b) { copyFrom(st.baseEnvValue(b.getName().str())); }
};

template <class Op> struct CoreEvalModel : nd::NixEvalOpInterface::ExternalModel<CoreEvalModel<Op>, Op> {
  void eval(Operation *op, EvalState &st, Frame *env, Value &out) const {
    CoreEval{st, env, out, nd::posOfOp(op)}(cast<Op>(op));
  }
};
template <class Op> void attachCore(MLIRContext &ctx) {
  if constexpr (requires(CoreEval run, Op op) { run(op); })
    Op::template attachInterface<CoreEvalModel<Op>>(ctx);
}

struct PrimEvalModel : public nd::NixEvalOpInterface::FallbackModel<PrimEvalModel> {
  void eval(Operation *op, EvalState &st, Frame *env, Value &out) const {
    const PrimOp *prim = st.primFor(op);
    constexpr unsigned kMaxArity = 8;
    Value *args[kMaxArity];
    unsigned n = op->getNumOperands();
    assert(n <= kMaxArity && "primop arity above the evaluator's limit");
    for (unsigned i = 0; i < n; i++) args[i] = st.lookup(env, op->getOperand(i));
    st.callPrimOp(*prim, args, out, nd::posOfOp(op));
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
                    nd::posOfOp(op));
  primForOp[k] = p;
  return p;
}

void registerEvalModels(MLIRContext &ctx) {
  [&]<class... Ops>() { (attachCore<Ops>(ctx), ...); }.template operator()<
#define GET_OP_LIST
#include "NixDialect/NixOps.cpp.inc"
  >();
  auto *core = ctx.getLoadedDialect<nd::NixDialect>();
  for (auto &entry : core->prims) {
    OperationName name = entry.second.name;
    if (!name.hasInterface<nd::NixEvalOpInterface>()) name.attachInterface<PrimEvalModel>();
  }
}

} // namespace nixev
