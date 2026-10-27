//===- EvalModels.cpp - Evaluation semantics as external interface models ===//
//
// The dialects define *what* an op is (operands, effects, folds); how the lazy
// evaluator *runs* it is attached from outside as a NixEvalOpInterface model.
// The evaluator has no op switch: EvalState::evalOp asks the op for its model.
//
//   core ops    one model per op of the `nix` dialect, CoreEval<Op>; the op's
//               semantics is its evalCore<Op> below
//   primops     the 105 ops of the continent dialects (defined at run time from
//               IRDL, so they have no C++ classes) share one fallback model,
//               which finds the primop through the core dialect's table
//
// The dialects know nothing about this file.  A JIT or a symbolic executor
// attaches its own models the same way.
//
//===----------------------------------------------------------------------===//

#include "Nix/Eval.h"
#include "NixDialect/NixDialect.h"

using namespace mlir;
namespace nd = mlir::nix;

namespace nixev {
namespace {

//===----------------------------------------------------------------------===//
// Core ops: one model per op, its semantics in one evalCore specialization
//===----------------------------------------------------------------------===//

/// The evaluation of core op `op` in activation `env`, into `out`; `pos` is the op's location.
template <class OpT> void evalCore(OpT op, EvalState &st, Frame *env, Value &out, PosPtr pos);

template <class OpT> struct CoreEval : nd::NixEvalOpInterface::ExternalModel<CoreEval<OpT>, OpT> {
  void eval(Operation *op, EvalState &st, Frame *env, Value &out) const {
    evalCore(cast<OpT>(op), st, env, out, op->getLoc().getAsOpaquePointer());
  }
};

/// The result is the value `v` stands for, forced.
void copyFrom(EvalState &st, Value *v, Value &out, PosPtr pos) {
  st.forceValue(*v, pos);
  out = *v;
}

// -- Constants and the base environment ---------------------------------------

template <> void evalCore(nd::IntOp i, EvalState &st, Frame *, Value &out, PosPtr) { st.mkInt(out, i.getValue()); }
template <> void evalCore(nd::BoolOp b, EvalState &st, Frame *, Value &out, PosPtr) { st.mkBool(out, b.getValue()); }
template <> void evalCore(nd::NullOp, EvalState &st, Frame *, Value &out, PosPtr) { st.mkNull(out); }
template <> void evalCore(nd::FloatOp fl, EvalState &st, Frame *, Value &out, PosPtr) {
  st.mkFloat(out, fl.getValue().convertToDouble());
}
template <> void evalCore(nd::StringOp s, EvalState &st, Frame *, Value &out, PosPtr) { st.mkString(out, s.getValue()); }
template <> void evalCore(nd::PathOp p, EvalState &st, Frame *, Value &out, PosPtr) { st.mkPath(out, p.getValue()); }
template <> void evalCore(nd::BuiltinOp b, EvalState &st, Frame *, Value &out, PosPtr pos) {
  copyFrom(st, st.baseEnvValue(b.getName()), out, pos);
}

// -- Lists and attribute sets -------------------------------------------------

template <> void evalCore(nd::ListOp l, EvalState &st, Frame *env, Value &out, PosPtr) {
  auto elems = l.getElements();
  st.mkList(out, elems.size());
  for (size_t i = 0; i < elems.size(); i++) out.list.elems[i] = st.lookup(env, elems[i]);
}

template <> void evalCore(nd::AttrsOp op, EvalState &st, Frame *env, Value &out, PosPtr) {
  auto names = op.getNames();
  auto values = op.getValues();
  auto dynNames = op.getDynNames();
  std::optional<ArrayAttr> positions = op.getPositions();
  EvalState::BindingsBuilder bb(st);
  for (size_t i = 0; i < names.size(); i++) {
    PosPtr p = positions && i < positions->size()
                   ? cast<LocationAttr>((*positions)[i]).getAsOpaquePointer() : nullptr;
    bb.insert(st.symbolOf(cast<StringAttr>(names[i])), st.lookup(env, values[i]), p);
  }
  if (dynNames.empty()) {
    st.mkAttrs(out, bb.finish());
    return;
  }
  // Dynamic attributes are inserted one by one with duplicate checks.
  std::map<Symbol, PosPtr> seen;
  for (size_t i = 0; i < names.size(); i++)
    seen[st.symbolOf(cast<StringAttr>(names[i]))] = nullptr;
  auto dynValues = op.getDynValues();
  for (size_t j = 0; j < dynNames.size(); j++) {
    Value *nv = st.lookup(env, dynNames[j]);
    PosPtr p = dynNames[j].getLoc().getAsOpaquePointer();
    st.forceValue(*nv, p);
    if (nv->type == VType::Null) continue;
    auto name = st.forceStringNoCtx(*nv, p, "while evaluating the name of a dynamic attribute");
    Symbol sym = st.symbols.create(name);
    if (seen.count(sym))
      throw EvalError("dynamic attribute '" + std::string(name) + "' already defined at " +
                          st.showPos(seen[sym] ? seen[sym] : op->getLoc().getAsOpaquePointer()),
                      p);
    seen[sym] = p;
    bb.insert(sym, st.lookup(env, dynValues[j]), p);
  }
  st.mkAttrs(out, bb.finish());
}

template <> void evalCore(nd::SelectOp sel, EvalState &st, Frame *env, Value &out, PosPtr pos) {
  mlir::OperandRange dyn = sel.getDynKeys();
  Value tb;
  Value *cur = dyn.empty() ? &st.operand(env, sel.getBase(), tb) : st.lookup(env, sel.getBase());
  mlir::Value def = sel.getDefaultValue();
  unsigned nextDyn = 0;
  for (mlir::Attribute comp : sel.getPath()) {
    Symbol sym = st.pathSymbol(comp, dyn, nextDyn, env, pos);
    st.forceValue(*cur, pos);
    if (def) {
      if (cur->type != VType::Attrs) return copyFrom(st, st.lookup(env, def), out, pos);
    } else if (cur->type != VType::Attrs) {
      st.throwTypeError("a set", *cur, pos, "while selecting an attribute");
    }
    const Attr *a = cur->attrs->get(sym);
    if (!a) {
      if (def) return copyFrom(st, st.lookup(env, def), out, pos);
      throw EvalError("attribute '" + std::string(st.symbols[sym].str()) + "' missing", pos);
    }
    cur = a->value;
  }
  copyFrom(st, cur, out, pos);
}

template <> void evalCore(nd::HasAttrOp h, EvalState &st, Frame *env, Value &out, PosPtr pos) {
  mlir::OperandRange dyn = h.getDynKeys();
  Value tb;
  Value *cur = dyn.empty() ? &st.operand(env, h.getBase(), tb) : st.lookup(env, h.getBase());
  unsigned nextDyn = 0;
  for (mlir::Attribute comp : h.getPath()) {
    st.forceValue(*cur, pos);
    Symbol sym = st.pathSymbol(comp, dyn, nextDyn, env, pos);
    if (cur->type != VType::Attrs) return st.mkBool(out, false);
    const Attr *a = cur->attrs->get(sym);
    if (!a) return st.mkBool(out, false);
    cur = a->value;
  }
  st.mkBool(out, true);
}

template <> void evalCore(nd::UpdateOp u, EvalState &st, Frame *env, Value &out, PosPtr pos) {
  Value tl, tr;
  Value *l = &st.operand(env, u.getLhs(), tl);
  st.forceAttrs(*l, pos, "in the left operand of the update (//) operator");
  Value *r = &st.operand(env, u.getRhs(), tr);
  st.forceAttrs(*r, pos, "in the right operand of the update (//) operator");
  if (l->attrs->empty()) { out = *r; return; }
  if (r->attrs->empty()) { out = *l; return; }
  st.mkAttrs(out, st.updateAttrs(l->attrs, r->attrs));
}

template <> void evalCore(nd::ConcatListsOp c, EvalState &st, Frame *env, Value &out, PosPtr pos) {
  Value tl, tr;
  Value *l = &st.operand(env, c.getLhs(), tl);
  st.forceList(*l, pos, "in the left operand of the list concatenation operator");
  Value *r = &st.operand(env, c.getRhs(), tr);
  st.forceList(*r, pos, "in the right operand of the list concatenation operator");
  if (l->list.size == 0) { out = *r; return; }
  if (r->list.size == 0) { out = *l; return; }
  size_t n1 = l->list.size, n2 = r->list.size;
  Value **e1 = l->list.elems, **e2 = r->list.elems;
  st.mkList(out, n1 + n2);
  memcpy(out.list.elems, e1, n1 * sizeof(Value *));
  memcpy(out.list.elems + n1, e2, n2 * sizeof(Value *));
}

// -- Scopes and calls -----------------------------------------------------------

template <> void evalCore(nd::WithVarOp w, EvalState &st, Frame *env, Value &out, PosPtr pos) {
  Symbol sym = st.symbolOf(w.getNameAttr());
  for (mlir::Value sc : w.getScopes()) {
    Value *sv = st.lookup(env, sc);
    st.forceAttrs(*sv, sc.getLoc().getAsOpaquePointer(), "while evaluating the first subexpression of a with expression");
    if (const Attr *a = sv->attrs->get(sym)) return copyFrom(st, a->value, out, pos);
  }
  throw EvalError("undefined variable '" + w.getName().str() + "'", pos);
}

template <> void evalCore(nd::FormalOp f, EvalState &st, Frame *env, Value &out, PosPtr pos) {
  Value *arg = st.lookup(env, f.getArg());
  st.forceAttrs(*arg, pos);
  if (const Attr *a = arg->attrs->get(st.symbolOf(f.getNameAttr()))) return copyFrom(st, a->value, out, pos);
  if (!f.getDefaultValue()) throw EvalError("missing formal argument '" + f.getName().str() + "'", pos);
  copyFrom(st, st.lookup(env, f.getDefaultValue()), out, pos);
}

template <> void evalCore(nd::ApplyOp ap, EvalState &st, Frame *env, Value &out, PosPtr pos) {
  Value *f = st.lookup(env, ap.getCallee());
  auto as = ap.getArgs();
  llvm::SmallVector<Value *, 4> args;
  for (mlir::Value a : as) args.push_back(st.lookup(env, a));
  st.callFunction(*f, args.size(), args.data(), out, pos);
}

// -- Control and logic ------------------------------------------------------------

template <> void evalCore(nd::IfOp i, EvalState &st, Frame *env, Value &out, PosPtr pos) {
  Value tc;
  bool c = st.forceBool(st.operand(env, i.getCond(), tc), pos, "while evaluating a branch condition");
  st.evalTail(env, c ? i.getThenValue() : i.getElseValue(), out, pos);
}

template <> void evalCore(nd::AssertOp a, EvalState &st, Frame *env, Value &out, PosPtr pos) {
  Value tc;
  bool c = st.forceBool(st.operand(env, a.getCond(), tc), pos, "in the condition of the assert statement");
  if (!c) {
    std::string txt = a.getText() ? a.getText()->str() : "?";
    throw AssertionError("assertion '" + txt + "' failed", pos);
  }
  st.evalTail(env, a.getBody(), out, pos);
}

template <> void evalCore(nd::NotOp n, EvalState &st, Frame *env, Value &out, PosPtr pos) {
  Value t;
  st.mkBool(out, !st.forceBool(st.operand(env, n.getOperand(), t), pos, "in the argument of the not operator"));
}

template <> void evalCore(nd::AndOp a, EvalState &st, Frame *env, Value &out, PosPtr pos) {
  Value t1, t2;
  if (!st.forceBool(st.operand(env, a.getLhs(), t1), pos, "in the left operand of the AND (&&) operator"))
    return st.mkBool(out, false);
  st.mkBool(out, st.forceBool(st.operand(env, a.getRhs(), t2), pos, "in the right operand of the AND (&&) operator"));
}

template <> void evalCore(nd::OrOp o, EvalState &st, Frame *env, Value &out, PosPtr pos) {
  Value t1, t2;
  if (st.forceBool(st.operand(env, o.getLhs(), t1), pos, "in the left operand of the OR (||) operator"))
    return st.mkBool(out, true);
  st.mkBool(out, st.forceBool(st.operand(env, o.getRhs(), t2), pos, "in the right operand of the OR (||) operator"));
}

template <> void evalCore(nd::ImplOp o, EvalState &st, Frame *env, Value &out, PosPtr pos) {
  Value t1, t2;
  if (!st.forceBool(st.operand(env, o.getLhs(), t1), pos, "in the left operand of the IMPL (->) operator"))
    return st.mkBool(out, true);
  st.mkBool(out, st.forceBool(st.operand(env, o.getRhs(), t2), pos, "in the right operand of the IMPL (->) operator"));
}

/// `==` and `!=`: both operands forced, left first, then compared by value.
bool equalOperands(EvalState &st, Frame *env, mlir::Value lhs, mlir::Value rhs, PosPtr pos) {
  Value ta, tb;
  Value &ra = st.operand(env, lhs, ta);
  st.forceValue(ra, pos);
  Value &rb = st.operand(env, rhs, tb);
  st.forceValue(rb, pos);
  Value a = ra, b = rb;
  return st.eqValues(a, b, pos);
}
template <> void evalCore(nd::EqOp e, EvalState &st, Frame *env, Value &out, PosPtr pos) {
  st.mkBool(out, equalOperands(st, env, e.getLhs(), e.getRhs(), pos));
}
template <> void evalCore(nd::NeqOp e, EvalState &st, Frame *env, Value &out, PosPtr pos) {
  st.mkBool(out, !equalOperands(st, env, e.getLhs(), e.getRhs(), pos));
}

// -- Strings ----------------------------------------------------------------------

/// String interpolation and `+`: the first part decides whether this is integer, float, path or
/// string addition.
template <> void evalCore(nd::ConcatStringsOp op, EvalState &st, Frame *env, Value &out, PosPtr pos) {
  auto parts = op.getParts();
  bool forceString = op.getForceString();
  NixStringContext context;
  std::string str;
  int64_t n = 0;
  double nf = 0;
  bool first = !forceString;
  VType firstType = VType::String;
  for (mlir::Value pv : parts) {
    PosPtr ppos = pv.getLoc().getAsOpaquePointer();
    Value *v = st.lookup(env, pv);
    st.forceValue(*v, ppos);
    if (first) firstType = v->type;
    if (firstType == VType::Int) {
      if (v->type == VType::Int) {
        if (__builtin_add_overflow(n, v->integer, &n))
          throw EvalError("integer overflow in adding " + std::to_string(n) + " + " + std::to_string(v->integer), ppos);
      } else if (v->type == VType::Float) {
        firstType = VType::Float;
        nf = (double)n;
        nf += v->fpoint;
      } else {
        throw EvalError(std::string("cannot add ") + EvalState::showType(*v) + " to an integer", ppos);
      }
    } else if (firstType == VType::Float) {
      if (v->type == VType::Int) nf += (double)v->integer;
      else if (v->type == VType::Float) nf += v->fpoint;
      else throw EvalError(std::string("cannot add ") + EvalState::showType(*v) + " to a float", ppos);
    } else {
      str += st.coerceToString(*v, context, false, firstType == VType::String, ppos,
                               "while evaluating a path segment", !first);
    }
    first = false;
  }
  if (firstType == VType::Int) st.mkInt(out, n);
  else if (firstType == VType::Float) st.mkFloat(out, nf);
  else if (firstType == VType::Path) {
    if (!context.empty())
      throw EvalError("a string that refers to a store path cannot be appended to a path", pos);
    st.mkPath(out, nixfe::canonPath(str));
  } else {
    st.mkString(out, str, context);
  }
}

/// Every core op the evaluator runs (nix.expr, nix.return and nix.lambda are structure: a
/// lambda is a closure that lookup() builds, not an op that is run).
template <class... Ops> void attachCore(MLIRContext &ctx) { (Ops::template attachInterface<CoreEval<Ops>>(ctx), ...); }

//===----------------------------------------------------------------------===//
// Primops: one fallback model for the continent dialects
//===----------------------------------------------------------------------===//

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
  attachCore<nd::IntOp, nd::BoolOp, nd::NullOp, nd::FloatOp, nd::StringOp, nd::PathOp, nd::BuiltinOp,
             nd::ListOp, nd::AttrsOp, nd::SelectOp, nd::HasAttrOp, nd::UpdateOp, nd::ConcatListsOp,
             nd::WithVarOp, nd::FormalOp, nd::ApplyOp,
             nd::IfOp, nd::AssertOp, nd::NotOp, nd::AndOp, nd::OrOp, nd::ImplOp, nd::EqOp, nd::NeqOp,
             nd::ConcatStringsOp>(ctx);
  auto *core = ctx.getLoadedDialect<nd::NixDialect>();
  for (auto &entry : core->prims) {
    OperationName name = entry.second.name;
    if (!name.hasInterface<nd::NixEvalOpInterface>()) name.attachInterface<PrimEvalModel>();
  }
}

} // namespace nixev
