//===- MLIRGen.cpp - Lower the Nix AST to the nix dialect -----------------===//
//
// All lexical scoping is resolved here.  Recursive binding groups (let, rec,
// lambda formals) are emitted into the enclosing graph region: we first create
// placeholder values for the group, generate each binding, then RAUW the
// placeholders.  A binding that is merely an alias of another member of a
// group (`let a = b; b = a;`) is given an identity node (`nix.apply %x()`,
// application to zero arguments) so that cycles become real SSA cycles.
//
//===----------------------------------------------------------------------===//

#include "Nix/MLIRGen.h"

#include "mlir/IR/Builders.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/StringMap.h"

#include <sstream>

using namespace mlir;
namespace nd = mlir::nix;

namespace nixfe {
namespace {

struct Scope {
  Scope *parent = nullptr;
  bool isWith = false;
  Value withValue;
  llvm::StringMap<Value> vars;
};

class Gen {
public:
  Gen(ModuleOp module, std::shared_ptr<Origin> origin, const GenOptions &opts)
      : module(module), ctx(module.getContext()), b(ctx), origin(std::move(origin)),
        opts(opts) {}

  nd::ExprOp run(const Expr *e, StringRef symName) {
    b.setInsertionPointToEnd(module.getBody());
    auto exprOp = nd::ExprOp::create(b, loc(Pos{}), b.getStringAttr(symName),
                                     origin->path.empty() ? StringAttr() : b.getStringAttr(origin->path),
                                     b.getStringAttr(origin->baseDir));
    Block *blk = new Block();
    exprOp.getBody().push_back(blk);
    b.setInsertionPointToEnd(blk);
    topBlock = blk;
    Value result;
    if (opts.scoped) {
      // scope: <expr>, with the scope's names bound lexically.
      auto lam = nd::LambdaOp::create(b, loc(e->pos), valTy(), ArrayAttr(),
                                      DenseBoolArrayAttr(), false,
                                      b.getStringAttr("scope"), StringAttr(), ArrayAttr());
      Block *lb = new Block();
      lam.getBody().push_back(lb);
      Value arg = lb->addArgument(valTy(), loc(e->pos));
      OpBuilder::InsertionGuard g(b);
      b.setInsertionPointToEnd(lb);
      Scope s;
      for (auto &n : opts.scopeNames) {
        Value key = nd::StringOp::create(b, loc(Pos{}), valTy(), b.getStringAttr(n));
        s.vars[n] = nd::SelectOp::create(b, loc(Pos{}), valTy(), arg, ValueRange{key}, Value());
      }
      Value body = gen(e, &s);
      nd::ReturnOp::create(b, loc(e->pos), body);
      result = lam.getResult();
    } else {
      result = gen(e, nullptr);
    }
    b.setInsertionPointToEnd(blk);
    nd::ReturnOp::create(b, loc(e->pos), result);
    return exprOp;
  }

private:
  ModuleOp module;
  MLIRContext *ctx;
  OpBuilder b;
  std::shared_ptr<Origin> origin;
  const GenOptions &opts;
  Block *topBlock = nullptr;
  llvm::StringMap<Value> builtinCache;
  llvm::DenseMap<const Expr *, Value> inheritFromVals;

  Type valTy() { return nd::ValueType::get(ctx); }

  Location loc(Pos p) {
    if (!p.valid()) return UnknownLoc::get(ctx);
    return FileLineColLoc::get(ctx, origin->name, p.line, p.col);
  }

  [[noreturn]] void error(const std::string &msg, Pos p) {
    throw ParseError(msg, p, origin);
  }

  Value placeholder(Pos p) {
    return UnrealizedConversionCastOp::create(b, loc(p), TypeRange{valTy()}, ValueRange{})
        .getResult(0);
  }

  /// Replace the placeholders of a binding group by their final values.
  SmallVector<Value> finalizeGroup(ArrayRef<Value> phs, ArrayRef<Value> values,
                                   ArrayRef<Pos> poses,
                                   ArrayRef<SmallVectorImpl<Value> *> remap = {}) {
    SmallVector<Value> finals;
    for (size_t i = 0; i < values.size(); i++) {
      Value v = values[i];
      if (v.getDefiningOp<UnrealizedConversionCastOp>())
        v = nd::ApplyOp::create(b, loc(poses[i]), valTy(), v, ValueRange{});
      finals.push_back(v);
    }
    // Other value lists that may hold placeholders must be remapped before the
    // placeholders are erased.
    for (auto *vec : remap)
      for (Value &v : *vec)
        for (size_t i = 0; i < phs.size(); i++)
          if (v == phs[i]) v = finals[i];
    for (size_t i = 0; i < phs.size(); i++) {
      Value ph = phs[i];
      ph.replaceAllUsesWith(finals[i]);
      ph.getDefiningOp()->erase();
    }
    return finals;
  }

  /// Upstream evaluates `let`/`with` into a fresh value (copying the body's
  /// value) whereas variable references share the bound value.  Mirror that
  /// so that value identity (observable via `==` on functions and via
  /// «repeated» when printing) matches.
  static bool isShared(const Expr *e) {
    switch (e->kind) {
    case ExprKind::Var: return true;
    case ExprKind::Let: return isShared(static_cast<const ExprLet *>(e)->body);
    case ExprKind::With: return isShared(static_cast<const ExprWith *>(e)->body);
    default: return false;
    }
  }
  Value identity(Value v, Pos p) {
    return nd::ApplyOp::create(b, loc(p), valTy(), v, ValueRange{});
  }

  Value builtin(StringRef name) {
    auto it = builtinCache.find(name);
    if (it != builtinCache.end()) return it->second;
    OpBuilder::InsertionGuard g(b);
    b.setInsertionPointToStart(topBlock);
    Value v = nd::BuiltinOp::create(b, UnknownLoc::get(ctx), valTy(), b.getStringAttr(name));
    builtinCache[name] = v;
    return v;
  }

  /// A reference to a base-environment entry.  The literals `true`, `false`
  /// and `null` become real constants (ConstantLike, so they fold and can be
  /// operands of folded primops); everything else stays a `nix.builtin`.
  Value baseRef(StringRef name) {
    if (name != "true" && name != "false" && name != "null") return builtin(name);
    auto it = builtinCache.find(name);
    if (it != builtinCache.end()) return it->second;
    OpBuilder::InsertionGuard g(b);
    b.setInsertionPointToStart(topBlock);
    Location l = UnknownLoc::get(ctx);
    Value v = name == "null" ? nd::NullOp::create(b, l, valTy()).getResult()
                             : nd::BoolOp::create(b, l, valTy(), b.getBoolAttr(name == "true")).getResult();
    builtinCache[name] = v;
    return v;
  }

  Value str(StringRef s, Pos p = {}) {
    return nd::StringOp::create(b, loc(p), valTy(), b.getStringAttr(s));
  }

  Value lookupVar(const std::string &name, Pos p, Scope *s) {
    SmallVector<Value> withs;
    for (Scope *c = s; c; c = c->parent) {
      if (c->isWith) {
        withs.push_back(c->withValue);
        continue;
      }
      auto it = c->vars.find(name);
      if (it != c->vars.end()) return it->second;
    }
    if (opts.isBaseName && opts.isBaseName(name)) return baseRef(name);
    if (withs.empty()) error("undefined variable '" + name + "'", p);
    return nd::WithVarOp::create(b, loc(p), valTy(), b.getStringAttr(name), withs);
  }

  SmallVector<Value> genKeys(const AttrPath &path, Scope *s, Pos p) {
    SmallVector<Value> keys;
    for (auto &a : path) {
      if (a.symbol) keys.push_back(str(*a.symbol, p));
      else keys.push_back(gen(a.expr, s));
    }
    return keys;
  }

  /// Generate the bindings of an attrs node into `names/values`, resolving
  /// each def in the proper scope.
  void genBindings(const ExprAttrs *a, Scope *defScope, Scope *outerScope,
                   Scope *inheritFromScope, SmallVectorImpl<Attribute> &names,
                   SmallVectorImpl<Value> &values, SmallVectorImpl<Attribute> &positions) {
    // Values of `inherit (e)` sources.
    SmallVector<Value> fromVals;
    for (auto *fe : a->inheritFromExprs) fromVals.push_back(gen(fe, inheritFromScope));
    for (auto &[name, def] : a->attrs) {
      Value v;
      switch (def.kind) {
      case ExprAttrs::DefKind::Plain: v = gen(def.e, defScope); break;
      case ExprAttrs::DefKind::Inherited: v = gen(def.e, outerScope); break;
      case ExprAttrs::DefKind::InheritedFrom: {
        auto *sel = static_cast<const ExprSelect *>(def.e);
        auto *from = static_cast<const ExprInheritFrom *>(sel->e);
        Value key = str(name, def.pos);
        v = nd::SelectOp::create(b, loc(def.pos), valTy(), fromVals[from->displ],
                                 ValueRange{key}, Value());
        break;
      }
      }
      names.push_back(b.getStringAttr(name));
      values.push_back(v);
      positions.push_back(loc(def.pos));
    }
  }

  Value genAttrs(const ExprAttrs *a, Scope *s) {
    SmallVector<Attribute> names, positions;
    SmallVector<Value> values, dynNames, dynValues;
    if (!a->recursive) {
      genBindings(a, s, s, s, names, values, positions);
      for (auto &d : a->dynamicAttrs) {
        dynNames.push_back(gen(d.nameExpr, s));
        dynValues.push_back(gen(d.valueExpr, s));
      }
    } else {
      Scope ns;
      ns.parent = s;
      llvm::StringMap<Value> phs;
      for (auto &[name, def] : a->attrs) {
        Value ph = placeholder(def.pos);
        phs[name] = ph;
        ns.vars[name] = ph;
      }
      genBindings(a, &ns, s, &ns, names, values, positions);
      for (auto &d : a->dynamicAttrs) {
        dynNames.push_back(gen(d.nameExpr, &ns));
        dynValues.push_back(gen(d.valueExpr, &ns));
      }
      SmallVector<Value> phv;
      SmallVector<Pos> poses;
      int ovIdx = -1, idx = 0;
      for (auto &[name, def] : a->attrs) {
        phv.push_back(phs[name]);
        poses.push_back(def.pos);
        if (name == "__overrides") ovIdx = idx;
        idx++;
      }
      // Legacy `__overrides`: attributes of the overrides set replace both the
      // recursive bindings and the resulting attributes.
      if (ovIdx >= 0) {
        Value ov = values[ovIdx];
        idx = 0;
        for (auto &[name, def] : a->attrs) {
          if (idx != ovIdx)
            values[idx] = nd::SelectOp::create(b, loc(def.pos), valTy(), ov, ValueRange{str(name, def.pos)},
                                               values[idx]);
          idx++;
        }
      }
      auto finals = finalizeGroup(phv, values, poses, {&dynNames, &dynValues});
      values.assign(finals.begin(), finals.end());
      if (ovIdx >= 0) {
        Value attrs = nd::AttrsOp::create(b, loc(a->pos), valTy(), b.getArrayAttr(names), values, dynNames,
                                          dynValues, b.getArrayAttr(positions));
        return nd::UpdateOp::create(b, loc(a->pos), valTy(), attrs, values[ovIdx]);
      }
    }
    return nd::AttrsOp::create(b, loc(a->pos), valTy(), b.getArrayAttr(names), values,
                               dynNames, dynValues, b.getArrayAttr(positions));
  }

  Value genLet(const ExprLet *l, Scope *s) {
    Scope ns;
    ns.parent = s;
    llvm::StringMap<Value> phs;
    for (auto &[name, def] : l->attrs->attrs) {
      Value ph = placeholder(def.pos);
      phs[name] = ph;
      ns.vars[name] = ph;
    }
    SmallVector<Attribute> names, positions;
    SmallVector<Value> values;
    genBindings(l->attrs, &ns, s, &ns, names, values, positions);
    SmallVector<Value> phv;
    SmallVector<Pos> poses;
    for (auto &[name, def] : l->attrs->attrs) {
      phv.push_back(phs[name]);
      poses.push_back(def.pos);
    }
    auto finals = finalizeGroup(phv, values, poses);
    size_t i = 0;
    for (auto &[name, def] : l->attrs->attrs) {
      (void)def;
      ns.vars[name] = finals[i++];
    }
    return gen(l->body, &ns);
  }

  Value genLambda(const ExprLambda *l, Scope *s) {
    SmallVector<Attribute> formalNames;
    SmallVector<bool> hasDef;
    for (auto &f : l->formals) {
      formalNames.push_back(b.getStringAttr(f.name));
      hasDef.push_back(f.def != nullptr);
    }
    auto lam = nd::LambdaOp::create(
        b, loc(l->pos), valTy(),
        l->hasFormals ? b.getArrayAttr(formalNames) : ArrayAttr(),
        l->hasFormals ? b.getDenseBoolArrayAttr(hasDef) : DenseBoolArrayAttr(),
        l->ellipsis,
        l->arg.empty() ? StringAttr() : b.getStringAttr(l->arg),
        l->name.empty() ? StringAttr() : b.getStringAttr(l->name), ArrayAttr());
    if (l->hasFormals) {
      SmallVector<Attribute> locs;
      for (auto &f : l->formals) locs.push_back(loc(f.pos));
      lam.setFormalLocsAttr(b.getArrayAttr(locs));
    }
    Block *blk = new Block();
    lam.getBody().push_back(blk);
    Value arg = blk->addArgument(valTy(), loc(l->pos));
    OpBuilder::InsertionGuard g(b);
    b.setInsertionPointToEnd(blk);
    Scope ns;
    ns.parent = s;
    if (!l->arg.empty()) ns.vars[l->arg] = arg;
    if (l->hasFormals) {
      SmallVector<Value> phs;
      for (auto &f : l->formals) {
        Value ph = placeholder(f.pos);
        phs.push_back(ph);
        ns.vars[f.name] = ph;
      }
      SmallVector<Value> defs;
      for (auto &f : l->formals) defs.push_back(f.def ? gen(f.def, &ns) : Value());
      // Create all formal ops before replacing any placeholder: defaults may
      // refer to other formals' placeholders.
      SmallVector<Value> fvs;
      for (size_t i = 0; i < l->formals.size(); i++) {
        auto &f = l->formals[i];
        fvs.push_back(nd::FormalOp::create(b, loc(f.pos), valTy(), arg,
                                           b.getStringAttr(f.name), defs[i]));
      }
      for (size_t i = 0; i < l->formals.size(); i++) {
        phs[i].replaceAllUsesWith(fvs[i]);
        phs[i].getDefiningOp()->erase();
        ns.vars[l->formals[i].name] = fvs[i];
      }
    }
    Value body = gen(l->body, &ns);
    nd::ReturnOp::create(b, loc(l->body->pos), body);
    return lam.getResult();
  }

  Value gen(const Expr *e, Scope *s) {
    switch (e->kind) {
    case ExprKind::Int:
      return nd::IntOp::create(b, loc(e->pos), valTy(),
                               b.getI64IntegerAttr(static_cast<const ExprInt *>(e)->v));
    case ExprKind::Float:
      return nd::FloatOp::create(b, loc(e->pos), valTy(),
                                 b.getF64FloatAttr(static_cast<const ExprFloat *>(e)->v));
    case ExprKind::String:
      return str(static_cast<const ExprString *>(e)->v, e->pos);
    case ExprKind::Path:
      return nd::PathOp::create(b, loc(e->pos), valTy(),
                                b.getStringAttr(static_cast<const ExprPath *>(e)->v));
    case ExprKind::Var: {
      auto *v = static_cast<const ExprVar *>(e);
      return lookupVar(v->name, v->pos, s);
    }
    case ExprKind::CurPos: {
      if (origin->path.empty()) return lookupVar("null", e->pos, nullptr);
      SmallVector<Attribute> names{b.getStringAttr("column"), b.getStringAttr("file"),
                                   b.getStringAttr("line")};
      SmallVector<Value> vals{
          nd::IntOp::create(b, loc(e->pos), valTy(), b.getI64IntegerAttr(e->pos.col)),
          str(origin->path, e->pos),
          nd::IntOp::create(b, loc(e->pos), valTy(), b.getI64IntegerAttr(e->pos.line))};
      return nd::AttrsOp::create(b, loc(e->pos), valTy(), b.getArrayAttr(names), vals,
                                 ValueRange{}, ValueRange{}, ArrayAttr());
    }
    case ExprKind::InheritFrom:
      error("internal error: stray inherit-from", e->pos);
    case ExprKind::Select: {
      auto *sel = static_cast<const ExprSelect *>(e);
      Value base = gen(sel->e, s);
      auto keys = genKeys(sel->path, s, sel->pos);
      Value def = sel->def ? gen(sel->def, s) : Value();
      return nd::SelectOp::create(b, loc(sel->pos), valTy(), base, keys, def);
    }
    case ExprKind::HasAttr: {
      auto *h = static_cast<const ExprHasAttr *>(e);
      Value base = gen(h->e, s);
      auto keys = genKeys(h->path, s, h->pos);
      return nd::HasAttrOp::create(b, loc(h->pos), valTy(), base, keys);
    }
    case ExprKind::Attrs:
      return genAttrs(static_cast<const ExprAttrs *>(e), s);
    case ExprKind::List: {
      SmallVector<Value> elems;
      for (auto *x : static_cast<const ExprList *>(e)->elems) elems.push_back(gen(x, s));
      return nd::ListOp::create(b, loc(e->pos), valTy(), elems);
    }
    case ExprKind::Lambda:
      return genLambda(static_cast<const ExprLambda *>(e), s);
    case ExprKind::Call: {
      auto *c = static_cast<const ExprCall *>(e);
      Value f = gen(c->fun, s);
      SmallVector<Value> args;
      for (auto *a : c->args) args.push_back(gen(a, s));
      return nd::ApplyOp::create(b, loc(c->pos), valTy(), f, args);
    }
    case ExprKind::Let: {
      Value v = genLet(static_cast<const ExprLet *>(e), s);
      return isShared(e) ? identity(v, e->pos) : v;
    }
    case ExprKind::With: {
      auto *w = static_cast<const ExprWith *>(e);
      Value a = gen(w->attrs, s);
      Scope ns;
      ns.parent = s;
      ns.isWith = true;
      ns.withValue = a;
      Value v = gen(w->body, &ns);
      return isShared(e) ? identity(v, e->pos) : v;
    }
    case ExprKind::If: {
      auto *i = static_cast<const ExprIf *>(e);
      Value c = gen(i->cond, s), t = gen(i->then, s), el = gen(i->else_, s);
      return nd::IfOp::create(b, loc(i->pos), valTy(), c, t, el);
    }
    case ExprKind::Assert: {
      auto *a = static_cast<const ExprAssert *>(e);
      Value c = gen(a->cond, s), body = gen(a->body, s);
      std::ostringstream os;
      showExpr(os, a->cond);
      return nd::AssertOp::create(b, loc(a->pos), valTy(), c, body, b.getStringAttr(os.str()));
    }
    case ExprKind::Not:
      return nd::NotOp::create(b, loc(e->pos), valTy(), gen(static_cast<const ExprNot *>(e)->e, s));
    case ExprKind::Eq: case ExprKind::NEq: case ExprKind::And: case ExprKind::Or:
    case ExprKind::Impl: case ExprKind::Update: case ExprKind::ConcatLists: {
      auto *bn = static_cast<const ExprBin *>(e);
      Value l = gen(bn->e1, s), r = gen(bn->e2, s);
      Location lc = loc(e->pos);
      switch (e->kind) {
      case ExprKind::Eq: return nd::EqOp::create(b, lc, valTy(), l, r);
      case ExprKind::NEq: return nd::NeqOp::create(b, lc, valTy(), l, r);
      case ExprKind::And: return nd::AndOp::create(b, lc, valTy(), l, r);
      case ExprKind::Or: return nd::OrOp::create(b, lc, valTy(), l, r);
      case ExprKind::Impl: return nd::ImplOp::create(b, lc, valTy(), l, r);
      case ExprKind::Update: return nd::UpdateOp::create(b, lc, valTy(), l, r);
      default: return nd::ConcatListsOp::create(b, lc, valTy(), l, r);
      }
    }
    case ExprKind::ConcatStrings: {
      auto *c = static_cast<const ExprConcatStrings *>(e);
      SmallVector<Value> parts;
      for (auto &[p, x] : c->es) parts.push_back(gen(x, s));
      return nd::ConcatStringsOp::create(b, loc(c->pos), valTy(), parts, c->forceString);
    }
    }
    error("internal error: unknown expression kind", e->pos);
  }
};

} // namespace

nd::ExprOp genExpr(ModuleOp module, const Expr *e, std::shared_ptr<Origin> origin,
                   StringRef symName, const GenOptions &opts) {
  Gen g(module, std::move(origin), opts);
  return g.run(e, symName);
}

} // namespace nixfe
