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
#include "Nix/Pos.h"

#include "mlir/IR/Builders.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/StringMap.h"

#include <deque>
#include <sstream>

using namespace mlir;
namespace nd = mlir::nix;
namespace cp = composite;

namespace nixfe {
namespace {

struct Scope {
  Scope *parent = nullptr;
  bool isWith = false;
  Value withValue;
  llvm::DenseMap<llvm::StringRef, Value> vars; // the keys are names of the retained tree: viewed, not copied
};

/// Free names of lambdas (see FreeName / FreeMemo).  The binder discipline mirrors Gen: lambda
/// arguments and formals, `let` and `rec` groups bind; `inherit x;` reads outside the group it
/// defines; `with` binds nothing statically.  Over-approximating is free (an unused capture is one
/// operand); masking a name Gen would resolve outside the body would be a bug.
class FreeVars {
public:
  explicit FreeVars(FreeMemo &memo) : memo(memo) {}

  const std::vector<FreeName> &of(const ExprLambda *l) {
    auto it = memo.find(l);
    if (it != memo.end()) return it->second;
    Walk w(*this);
    if (!l->arg.isNull()) w.enter(l->arg.str());
    for (auto &f : l->formals) w.enter(f.name.str());
    for (auto &f : l->formals)
      if (f.def) w.walk(f.def);
    w.walk(l->body);
    return memo.emplace(l, std::move(w.out)).first->second;
  }

private:
  FreeMemo &memo;

  struct Walk {
    FreeVars &fv;
    struct Slot {
      int bound = 0; // binders of this name between here and the lambda
      int out = -1;  // index in `out`, once seen free
    };
    llvm::DenseMap<llvm::StringRef, Slot> slots; // keyed by names of the retained tree
    unsigned withs = 0; // `with` scopes between here and the lambda
    std::vector<FreeName> out;

    explicit Walk(FreeVars &fv) : fv(fv) {}
    void enter(llvm::StringRef n) { ++slots[n].bound; }
    void leave(llvm::StringRef n) { --slots[n].bound; }
    void ref(llvm::StringRef n, Pos pos, bool strict) {
      Slot &s = slots[n];
      if (s.bound > 0) return;
      if (s.out < 0) {
        s.out = static_cast<int>(out.size());
        out.push_back({n, pos, strict});
      } else if (strict && !out[s.out].strict) {
        out[s.out] = {n, pos, true};
      }
    }
    void walk(const Expr *e);
  };
};

void FreeVars::Walk::walk(const Expr *e) {
  switch (e->kind) {
  case ExprKind::Int: case ExprKind::Float: case ExprKind::String: case ExprKind::Path:
  case ExprKind::CurPos: case ExprKind::InheritFrom:
    return;
  case ExprKind::Var: {
    auto *v = static_cast<const ExprVar *>(e);
    ref(v->name.str(), v->pos, withs == 0);
    return;
  }
  case ExprKind::Lambda:
    for (const FreeName &f : fv.of(static_cast<const ExprLambda *>(e)))
      ref(f.name, f.pos, f.strict && withs == 0);
    return;
  case ExprKind::Let:
  case ExprKind::Attrs: {
    bool isLet = e->kind == ExprKind::Let;
    const ExprAttrs *a = isLet ? static_cast<const ExprLet *>(e)->attrs : static_cast<const ExprAttrs *>(e);
    bool binds = isLet || a->recursive;
    for (auto &[name, def] : a->entries()) // `inherit x;` reads outside the group it defines
      if (def.kind == ExprAttrs::DefKind::Inherited) walk(def.e);
    if (binds)
      for (auto &[name, def] : a->entries()) enter(name.str());
    for (auto *fe : a->inheritFromExprs) walk(fe);
    for (auto &[name, def] : a->entries())
      if (def.kind == ExprAttrs::DefKind::Plain) walk(def.e);
    for (auto &d : a->dynamicAttrs) {
      walk(d.nameExpr);
      walk(d.valueExpr);
    }
    if (isLet) walk(static_cast<const ExprLet *>(e)->body);
    if (binds)
      for (auto &[name, def] : a->entries()) leave(name.str());
    return;
  }
  case ExprKind::Select: {
    auto *x = static_cast<const ExprSelect *>(e);
    walk(x->e);
    for (auto &c : x->path)
      if (c.expr) walk(c.expr);
    if (x->def) walk(x->def);
    return;
  }
  case ExprKind::HasAttr: {
    auto *x = static_cast<const ExprHasAttr *>(e);
    walk(x->e);
    for (auto &c : x->path)
      if (c.expr) walk(c.expr);
    return;
  }
  case ExprKind::List:
    for (auto *x : static_cast<const ExprList *>(e)->elems) walk(x);
    return;
  case ExprKind::Call: {
    auto *c = static_cast<const ExprCall *>(e);
    walk(c->fun);
    for (auto *x : c->args) walk(x);
    return;
  }
  case ExprKind::With: {
    auto *x = static_cast<const ExprWith *>(e);
    walk(x->attrs);
    ++withs;
    walk(x->body);
    --withs;
    return;
  }
  case ExprKind::If: {
    auto *i = static_cast<const ExprIf *>(e);
    walk(i->cond);
    walk(i->then);
    walk(i->else_);
    return;
  }
  case ExprKind::Assert: {
    auto *x = static_cast<const ExprAssert *>(e);
    walk(x->cond);
    walk(x->body);
    return;
  }
  case ExprKind::Not:
    walk(static_cast<const ExprNot *>(e)->e);
    return;
  case ExprKind::Eq: case ExprKind::NEq: case ExprKind::And: case ExprKind::Or:
  case ExprKind::Impl: case ExprKind::Update: case ExprKind::ConcatLists: {
    auto *bn = static_cast<const ExprBin *>(e);
    walk(bn->e1);
    walk(bn->e2);
    return;
  }
  case ExprKind::ConcatStrings:
    for (auto &[p, x] : static_cast<const ExprConcatStrings *>(e)->es) walk(x);
    return;
  }
}

class Gen {
public:
  Gen(ModuleOp module, std::shared_ptr<Origin> origin, const GenOptions &opts)
      : module(module), ctx(module.getContext()), b(ctx), origin(std::move(origin)),
        opts(opts) {}

  nd::ExprOp run(const Expr *e, StringRef symName) {
    b.setInsertionPointToEnd(module.getBody());
    auto exprOp = nd::ExprOp::create(b, noLoc(), b.getStringAttr(symName),
                                     origin->path.empty() ? StringAttr() : b.getStringAttr(origin->path),
                                     b.getStringAttr(origin->baseDir));
    Block *blk = new Block();
    exprOp.getBody().push_back(blk);
    b.setInsertionPointToEnd(blk);
    topBlock = blk;
    Value result;
    if (opts.scoped) {
      // scope: <expr>, with the scope's names bound lexically.
      auto lam = nd::LambdaOp::create(b, noLoc(), valTy(), ArrayAttr(),
                                      DenseBoolArrayAttr(), false,
                                      b.getStringAttr("scope"), StringAttr(), DenseI64ArrayAttr(),
                                      ValueRange{}, IntegerAttr(), at(e->pos));
      Block *lb = new Block();
      lam.getBody().push_back(lb);
      Value arg = lb->addArgument(valTy(), noLoc());
      OpBuilder::InsertionGuard g(b);
      b.setInsertionPointToEnd(lb);
      Scope s;
      for (auto &n : opts.scopeNames) {
        s.vars[n] = selectLiteral(Pos{}, arg, n);
      }
      Value body = gen(e, &s);
      nd::ReturnOp::create(b, noLoc(), body);
      result = lam.getResult();
    } else {
      result = gen(e, nullptr);
    }
    b.setInsertionPointToEnd(blk);
    nd::ReturnOp::create(b, noLoc(), result);
    return exprOp;
  }

  /// The demand half of the mint (nixfe::mintBody): rebuild the lexical scope of the lambda from its
  /// pool row and generate the body, through the same path as at lowering time.
  void mint(nd::LambdaOp lam, const Row &r) {
    topBlock = &lam.getBody().front(); // anchored constants (builtins, true/false/null) head the body
    OperandRange caps = lam.getCaptures();
    Scope lex;
    for (size_t i = 0; i < r.names.size(); i++) lex.vars[r.names[i]] = caps[r.withs + i];
    // `with` never binds lexically and a lexical binding beats every `with`, so the flat map plus
    // the with-chain (outermost pushed first, so the walk meets the innermost first) is the same
    // scope extensionally.
    std::deque<Scope> frames; // stable addresses: the chain is walked by pointer
    Scope *cur = &lex;
    for (unsigned i = r.withs; i-- > 0;) {
      frames.emplace_back();
      frames.back().parent = cur;
      frames.back().isWith = true;
      frames.back().withValue = caps[i];
      cur = &frames.back();
    }
    genLambdaBody(lam, r.expr, cur);
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

  /// The position word of `p` (Nix/Pos.h): what an op carries in its `pos` property.  The FileLineColLoc
  /// it replaces was hashed, probed for and allocated by the context for every distinct position.
  int64_t at(Pos p) {
    if (!p.valid()) return 0;
    if (!origin->fileId) origin->fileId = FileTable::get().add(origin->name);
    return static_cast<int64_t>(PackedPos::pack(origin->fileId, p.line, p.col));
  }

  /// Every op is made with the same Location; the position is in the op, not in the context.
  Location noLoc() { return UnknownLoc::get(ctx); }

  /// A few consumers report errors at the position of an *operand* (a `with`
  /// scope, a computed attribute name, a part of an interpolation).  Give a
  /// literal operand its position back.
  Value positioned(Value v, Pos p) {
    if (Operation *d = v.getDefiningOp())
      if (isa<nd::StringOp, nd::IntOp, nd::FloatOp, nd::PathOp, nd::ListOp>(d) && nd::getPos(d) == 0)
        nd::setPos(d, static_cast<uint64_t>(at(p)));
    return v;
  }

  [[noreturn]] void error(const std::string &msg, Pos p) {
    throw ParseError(msg, p, origin);
  }

  Value placeholder(Pos p) {
    return UnrealizedConversionCastOp::create(b, noLoc(), TypeRange{valTy()}, ValueRange{})
        .getResult(0);
  }

  /// Replace the placeholders of a binding group by their final values.
  SmallVector<Value> finalizeGroup(ArrayRef<Value> phs, ArrayRef<Value> values,
                                   ArrayRef<Pos> poses,
                                   ArrayRef<SmallVectorImpl<Value> *> remap = {}) {
    SmallVector<Value> finals;
    for (auto [v, p] : cp::joins(values, poses))
      finals.push_back(v.getDefiningOp<UnrealizedConversionCastOp>()
                           ? Value(nd::ApplyOp::create(b, noLoc(), valTy(), v, ValueRange{}, at(p))) : v);
    // Other value lists that may hold placeholders must be remapped before the
    // placeholders are erased.
    for (auto *vec : remap)
      for (Value &v : *vec)
        for (size_t i = 0; i < phs.size(); i++)
          if (v == phs[i]) v = finals[i];
    for (auto [ph, fin] : cp::joins(phs, finals)) {
      ph.replaceAllUsesWith(fin);
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
    return nd::ApplyOp::create(b, noLoc(), valTy(), v, ValueRange{}, at(p));
  }

  Value builtin(StringRef name) {
    auto it = builtinCache.find(name);
    if (it != builtinCache.end()) return it->second;
    OpBuilder::InsertionGuard g(b);
    b.setInsertionPointToStart(topBlock);
    Value v = nd::BuiltinOp::create(b, UnknownLoc::get(ctx), valTy(), nixfe::Name::persist(name));
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

  Value str(StringRef s, Pos p = {}) { return str(nixfe::Name::persist(s)); } // text that may not live on
  Value str(const nixfe::Name &n) { return nd::StringOp::create(b, noLoc(), valTy(), n); }

  Value lookupVar(StringRef name, Pos p, Scope *s) { // `name` is a name of the retained tree, or a literal
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
    if (withs.empty()) error("undefined variable '" + name.str() + "'", p);
    return nd::WithVarOp::create(b, noLoc(), valTy(), nixfe::Name::of(name), withs, at(p));
  }

  /// A select/has_attr path: literal components become names, computed ones (`${e}`) the null name plus an
  /// operand (see nix.select).
  struct GenPath {
    SmallVector<nixfe::Name> comps;
    SmallVector<Value> dyn;
  };
  GenPath genPath(const AttrPath &path, Scope *s) {
    GenPath r;
    for (auto &a : path) {
      if (!a.computed()) {
        r.comps.push_back(a.symbol);
      } else {
        r.comps.push_back(nixfe::Name());
        r.dyn.push_back(gen(a.expr, s));
      }
    }
    return r;
  }

  /// `base.key` with a literal key and no default.
  Value selectLiteral(Pos p, Value base, StringRef key, Value def = Value()) {
    nixfe::Name path[1] = {nixfe::Name::persist(key)};
    return nd::SelectOp::create(b, noLoc(), valTy(), base, ValueRange{}, def, path, at(p));
  }

  /// Generate the bindings of an attrs node into `names/values`, resolving
  /// each def in the proper scope.
  void genBindings(const ExprAttrs *a, Scope *defScope, Scope *outerScope,
                   Scope *inheritFromScope, SmallVectorImpl<nixfe::Name> &names,
                   SmallVectorImpl<Value> &values, SmallVectorImpl<int64_t> &positions) {
    // Values of `inherit (e)` sources.
    SmallVector<Value> fromVals;
    for (auto *fe : a->inheritFromExprs) fromVals.push_back(gen(fe, inheritFromScope));
    for (auto &[name, def] : a->entries()) {
      Value v;
      switch (def.kind) {
      case ExprAttrs::DefKind::Plain: v = gen(def.e, defScope); break;
      case ExprAttrs::DefKind::Inherited: v = gen(def.e, outerScope); break;
      case ExprAttrs::DefKind::InheritedFrom: {
        auto *sel = static_cast<const ExprSelect *>(def.e);
        auto *from = static_cast<const ExprInheritFrom *>(sel->e);
        v = selectLiteral(def.pos, fromVals[from->displ], name.str());
        break;
      }
      }
      names.push_back(name);
      values.push_back(v);
      positions.push_back(at(def.pos));
    }
  }

  Value genAttrs(const ExprAttrs *a, Scope *s) {
    SmallVector<nixfe::Name> names;
    SmallVector<int64_t> positions;
    SmallVector<Value> values, dynNames, dynValues;
    if (!a->recursive) {
      genBindings(a, s, s, s, names, values, positions);
      for (auto &d : a->dynamicAttrs) {
        dynNames.push_back(positioned(gen(d.nameExpr, s), d.nameExpr->pos));
        dynValues.push_back(gen(d.valueExpr, s));
      }
    } else {
      Scope ns;
      ns.parent = s;
      llvm::DenseMap<StringRef, Value> phs;
      for (auto &[name, def] : a->entries()) {
        Value ph = placeholder(def.pos);
        phs[name.str()] = ph;
        ns.vars[name.str()] = ph;
      }
      genBindings(a, &ns, s, &ns, names, values, positions);
      for (auto &d : a->dynamicAttrs) {
        dynNames.push_back(positioned(gen(d.nameExpr, &ns), d.nameExpr->pos));
        dynValues.push_back(gen(d.valueExpr, &ns));
      }
      SmallVector<Value> phv;
      SmallVector<Pos> poses;
      int ovIdx = -1, idx = 0;
      for (auto &[name, def] : a->entries()) {
        phv.push_back(phs[name.str()]);
        poses.push_back(def.pos);
        if (name.str() == "__overrides") ovIdx = idx;
        idx++;
      }
      // Legacy `__overrides`: attributes of the overrides set replace both the
      // recursive bindings and the resulting attributes.
      if (ovIdx >= 0) {
        Value ov = values[ovIdx];
        idx = 0;
        for (auto &[name, def] : a->entries()) {
          if (idx != ovIdx)
            values[idx] = selectLiteral(def.pos, ov, name.str(), values[idx]);
          idx++;
        }
      }
      auto finals = finalizeGroup(phv, values, poses, {&dynNames, &dynValues});
      values.assign(finals.begin(), finals.end());
      if (ovIdx >= 0) {
        Value attrs = nd::AttrsOp::create(b, noLoc(), valTy(), names, values, dynNames, dynValues, positions,
                                          at(a->pos));
        return nd::UpdateOp::create(b, noLoc(), valTy(), attrs, values[ovIdx], at(a->pos));
      }
    }
    return nd::AttrsOp::create(b, noLoc(), valTy(), names, values, dynNames, dynValues, positions, at(a->pos));
  }

  Value genLet(const ExprLet *l, Scope *s) {
    Scope ns;
    ns.parent = s;
    llvm::DenseMap<StringRef, Value> phs;
    for (auto &[name, def] : l->attrs->entries()) {
      Value ph = placeholder(def.pos);
      phs[name.str()] = ph;
      ns.vars[name.str()] = ph;
    }
    SmallVector<nixfe::Name> names;
    SmallVector<int64_t> positions;
    SmallVector<Value> values;
    genBindings(l->attrs, &ns, s, &ns, names, values, positions);
    SmallVector<Value> phv;
    SmallVector<Pos> poses;
    for (auto &[name, def] : l->attrs->entries()) {
      phv.push_back(phs[name.str()]);
      poses.push_back(def.pos);
    }
    auto finals = finalizeGroup(phv, values, poses);
    size_t i = 0;
    for (auto &[name, def] : l->attrs->entries()) {
      (void)def;
      ns.vars[name.str()] = finals[i++];
    }
    return gen(l->body, &ns);
  }

  /// Where `name` resolves without a `with`: a lexical binding, else the base environment (an
  /// anchored constant at the head of the region).  Null when only a `with`, or nothing, can supply it.
  Value resolveStatic(StringRef name, Scope *s) {
    for (Scope *c = s; c; c = c->parent) {
      if (c->isWith) continue;
      auto it = c->vars.find(name);
      if (it != c->vars.end()) return it->second;
    }
    if (opts.isBaseName && opts.isBaseName(name)) return baseRef(name);
    return Value();
  }

  /// The defer half of the schedule.  The free names of the lambda resolve against the live scope NOW and
  /// become capture operands: real uses, so the placeholder RAUW of a let/rec group keeps them honest
  /// and the cleanup of unused builtins/selects cannot erase what a waiting body will read.  A name no
  /// scope supplies is a static error here, exactly when the eager schedule reports it, unless a `with`
  /// could supply it at run time.  Fills `caps` (the with-chain innermost first, then the resolved
  /// names) and returns the pool row.
  uint32_t defer(const ExprLambda *l, Scope *s, SmallVectorImpl<Value> &caps) {
    FreeVars fv(*opts.freeMemo);
    const std::vector<FreeName> &fs = fv.of(l);
    for (Scope *c = s; c; c = c->parent)
      if (c->isWith) caps.push_back(c->withValue); // lookupVar's order
    unsigned withs = caps.size();
    // α: each free name joined with where the live scope puts it; nothing resolves until its element is read.
    auto resolved = cp::series(fs.data(), fs.size()) |cp::α| [&](const FreeName &f) { return f |cp::j| resolveStatic(f.name, s); };
    SmallVector<StringRef> names;
    for (auto [f, v] : resolved) {
      if (v) {
        names.push_back(f.name);
        caps.push_back(v);
      } else if (f.strict && withs == 0) {
        error("undefined variable '" + f.name.str() + "'", f.pos);
      }
    }
    return opts.pool->defer(l, withs, names);
  }

  Value genLambda(const ExprLambda *l, Scope *s) {
    SmallVector<Attribute> formalNames;
    SmallVector<bool> hasDef;
    for (auto &f : l->formals) {
      formalNames.push_back(b.getStringAttr(f.name.str()));
      hasDef.push_back(f.def != nullptr);
    }
    bool deferred = opts.deferBodies && opts.pool && opts.freeMemo;
    SmallVector<Value> caps;
    IntegerAttr bodyIndex;
    uint32_t row = 0;
    if (deferred) {
      row = defer(l, s, caps);
      bodyIndex = b.getI64IntegerAttr(static_cast<int64_t>(BodyIndex(opts.pool->file, row).raw));
    }
    SmallVector<int64_t> formalLocs;
    for (auto &f : l->formals) formalLocs.push_back(at(f.pos));
    auto lam = nd::LambdaOp::create(
        b, noLoc(), valTy(),
        l->hasFormals ? b.getArrayAttr(formalNames) : ArrayAttr(),
        l->hasFormals ? b.getDenseBoolArrayAttr(hasDef) : DenseBoolArrayAttr(),
        l->ellipsis,
        l->arg.isNull() ? StringAttr() : b.getStringAttr(l->arg.str()),
        l->name.isNull() ? StringAttr() : b.getStringAttr(l->name.str()),
        l->hasFormals ? b.getDenseI64ArrayAttr(formalLocs) : DenseI64ArrayAttr(), caps, bodyIndex, at(l->pos));
    Block *blk = new Block();
    lam.getBody().push_back(blk);
    blk->addArgument(valTy(), noLoc());
    if (deferred) { // the node exists, its graph does not: the pool holds the rest
      opts.pool->attach(row, lam);
      return lam.getResult();
    }
    genLambdaBody(lam, l, s);
    return lam.getResult();
  }

  /// The body mint, shared by the eager schedule (at lowering time) and the demand schedule (first
  /// call): the same ops either way.
  void genLambdaBody(nd::LambdaOp lam, const ExprLambda *l, Scope *s) {
    OpBuilder::InsertionGuard g(b);
    b.setInsertionPointToEnd(&lam.getBody().front());
    Value arg = lam.getArgument();
    Scope ns;
    ns.parent = s;
    if (!l->arg.isNull()) ns.vars[l->arg.str()] = arg;
    if (l->hasFormals) {
      SmallVector<Value> phs;
      for (auto &f : l->formals) {
        Value ph = placeholder(f.pos);
        phs.push_back(ph);
        ns.vars[f.name.str()] = ph;
      }
      SmallVector<Value> defs;
      for (auto &f : l->formals) defs.push_back(f.def ? gen(f.def, &ns) : Value());
      // Create all formal ops before replacing any placeholder: defaults may
      // refer to other formals' placeholders.
      SmallVector<Value> fvs;
      for (auto [f, d] : cp::joins(l->formals, defs))
        fvs.push_back(nd::FormalOp::create(b, noLoc(), valTy(), arg, f.name, d, at(f.pos)));
      for (size_t i = 0; i < l->formals.size(); i++) {
        phs[i].replaceAllUsesWith(fvs[i]);
        phs[i].getDefiningOp()->erase();
        ns.vars[l->formals[i].name.str()] = fvs[i];
      }
    }
    Value body = gen(l->body, &ns);
    nd::ReturnOp::create(b, noLoc(), body);
  }

  Value gen(const Expr *e, Scope *s) {
    switch (e->kind) {
    case ExprKind::Int:
      return nd::IntOp::create(b, noLoc(), valTy(),
                               b.getI64IntegerAttr(static_cast<const ExprInt *>(e)->v));
    case ExprKind::Float:
      return nd::FloatOp::create(b, noLoc(), valTy(),
                                 b.getF64FloatAttr(static_cast<const ExprFloat *>(e)->v));
    case ExprKind::String:
      return str(static_cast<const ExprString *>(e)->v);
    case ExprKind::Path:
      return nd::PathOp::create(b, noLoc(), valTy(), static_cast<const ExprPath *>(e)->v);
    case ExprKind::Var: {
      auto *v = static_cast<const ExprVar *>(e);
      return lookupVar(v->name.str(), v->pos, s);
    }
    case ExprKind::CurPos: {
      if (origin->path.empty()) return lookupVar("null", e->pos, nullptr);
      SmallVector<nixfe::Name> names{nixfe::Name::persist("column"), nixfe::Name::persist("file"),
                                     nixfe::Name::persist("line")};
      SmallVector<Value> vals{
          nd::IntOp::create(b, noLoc(), valTy(), b.getI64IntegerAttr(e->pos.col)),
          str(origin->path, e->pos),
          nd::IntOp::create(b, noLoc(), valTy(), b.getI64IntegerAttr(e->pos.line))};
      return nd::AttrsOp::create(b, noLoc(), valTy(), names, vals, ValueRange{}, ValueRange{}, ArrayRef<int64_t>{},
                                 at(e->pos));
    }
    case ExprKind::InheritFrom:
      error("internal error: stray inherit-from", e->pos);
    case ExprKind::Select: {
      auto *sel = static_cast<const ExprSelect *>(e);
      Value base = gen(sel->e, s);
      GenPath path = genPath(sel->path, s);
      Value def = sel->def ? gen(sel->def, s) : Value();
      return nd::SelectOp::create(b, noLoc(), valTy(), base, path.dyn, def, path.comps, at(sel->pos));
    }
    case ExprKind::HasAttr: {
      auto *h = static_cast<const ExprHasAttr *>(e);
      Value base = gen(h->e, s);
      GenPath path = genPath(h->path, s);
      return nd::HasAttrOp::create(b, noLoc(), valTy(), base, path.dyn, path.comps, at(h->pos));
    }
    case ExprKind::Attrs:
      return genAttrs(static_cast<const ExprAttrs *>(e), s);
    case ExprKind::List: {
      SmallVector<Value> elems;
      for (auto *x : static_cast<const ExprList *>(e)->elems) elems.push_back(gen(x, s));
      return nd::ListOp::create(b, noLoc(), valTy(), elems);
    }
    case ExprKind::Lambda:
      return genLambda(static_cast<const ExprLambda *>(e), s);
    case ExprKind::Call: {
      auto *c = static_cast<const ExprCall *>(e);
      Value f = gen(c->fun, s);
      SmallVector<Value> args;
      for (auto *a : c->args) args.push_back(gen(a, s));
      return nd::ApplyOp::create(b, noLoc(), valTy(), f, args, at(c->pos));
    }
    case ExprKind::Let: {
      Value v = genLet(static_cast<const ExprLet *>(e), s);
      return isShared(e) ? identity(v, e->pos) : v;
    }
    case ExprKind::With: {
      auto *w = static_cast<const ExprWith *>(e);
      Value a = positioned(gen(w->attrs, s), w->attrs->pos);
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
      return nd::IfOp::create(b, noLoc(), valTy(), c, t, el, at(i->pos));
    }
    case ExprKind::Assert: {
      auto *a = static_cast<const ExprAssert *>(e);
      Value c = gen(a->cond, s), body = gen(a->body, s);
      std::ostringstream os;
      showExpr(os, a->cond);
      return nd::AssertOp::create(b, noLoc(), valTy(), c, body, b.getStringAttr(os.str()), at(a->pos));
    }
    case ExprKind::Not:
      return nd::NotOp::create(b, noLoc(), valTy(), gen(static_cast<const ExprNot *>(e)->e, s), at(e->pos));
    case ExprKind::Eq: case ExprKind::NEq: case ExprKind::And: case ExprKind::Or:
    case ExprKind::Impl: case ExprKind::Update: case ExprKind::ConcatLists: {
      auto *bn = static_cast<const ExprBin *>(e);
      Value l = gen(bn->e1, s), r = gen(bn->e2, s);
      int64_t w = at(e->pos);
      switch (e->kind) {
      case ExprKind::Eq: return nd::EqOp::create(b, noLoc(), valTy(), l, r, w);
      case ExprKind::NEq: return nd::NeqOp::create(b, noLoc(), valTy(), l, r, w);
      case ExprKind::And: return nd::AndOp::create(b, noLoc(), valTy(), l, r, w);
      case ExprKind::Or: return nd::OrOp::create(b, noLoc(), valTy(), l, r, w);
      case ExprKind::Impl: return nd::ImplOp::create(b, noLoc(), valTy(), l, r, w);
      case ExprKind::Update: return nd::UpdateOp::create(b, noLoc(), valTy(), l, r, w);
      default: return nd::ConcatListsOp::create(b, noLoc(), valTy(), l, r, w);
      }
    }
    case ExprKind::ConcatStrings: {
      auto *c = static_cast<const ExprConcatStrings *>(e);
      SmallVector<Value> parts;
      for (auto &[p, x] : c->es) parts.push_back(positioned(gen(x, s), x->pos));
      return nd::ConcatStringsOp::create(b, noLoc(), valTy(), parts, c->forceString, at(c->pos));
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

void mintBody(nd::LambdaOp lam, std::shared_ptr<Origin> origin, const Row &r, const GenOptions &opts) {
  Gen g(lam->getParentOfType<ModuleOp>(), std::move(origin), opts);
  g.mint(lam, r);
}

} // namespace nixfe
