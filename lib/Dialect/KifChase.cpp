//===- KifChase.cpp - forward chaining over a kif.theory, with proofs -------===//
//
// `kif-chase`: the solver of sumo-nix/datalog.nix as a pass.  The rules of a theory are chained forward from its facts to a
// fixpoint, and every fact a rule gives becomes a `kif.derived` that names the rule and the facts its premises matched.
//
// The same answers as datalog.nix, proofs included, which fixes the order of everything that picks a proof:
//   - a round derives from the facts of the rounds before it (a fact found in round k feeds round k+1);
//   - within a round the rules are taken in order, and each rule's solutions in the order its premises find them;
//   - a premise reads the facts in the order of their printed form (Nix's attribute order: datalog.nix keys facts by `show`),
//     from the narrowest index: the fact itself when the premise is ground, else by relation and first argument, else by
//     relation, else all of them;
//   - of the solutions that give one new fact in a round, the first is kept (listToAttrs keeps the first of equal names).
// A premise may be `(and ..)`, `(exists vars p)`, `(not p)` (negation as failure), `(equal a b)`, `(instance X Class)` (with an
// ontology theory: X is an instance of any class whose ancestors include Class) or a pattern.  A rule whose consequent keeps a
// variable is an error, as it is a throw in datalog.nix.
//
// Terms are interned ids here, not ops: a list is a row of ids, so a solution's substitutions and the indexes cost words, and
// ops are made only for the derived facts at the end.
//
//===----------------------------------------------------------------------===//

#include "NixDialect/Kif.h"
#include "NixDialect/Sumo.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/Pass.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallString.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringMap.h"
#include "llvm/Support/Allocator.h"
#include "llvm/Support/raw_ostream.h"

namespace mlir::kif {
namespace {

constexpr uint32_t kNone = ~0u;

/// Every term of a theory, and the ones a chase makes, by id.
struct Terms {
  enum Kind : uint8_t { Atom, Var, List };
  struct T {
    Kind kind;
    StringRef text;          // an atom's or a variable's
    uint32_t kids = 0, n = 0; // a list's elements: kids[kids .. kids+n)
    Value value;              // its op, when it has one
  };
  SmallVector<T, 0> terms;
  SmallVector<uint32_t, 0> kids;
  llvm::StringMap<uint32_t> atoms;
  llvm::DenseMap<ArrayRef<uint32_t>, uint32_t> lists;
  llvm::DenseMap<Value, uint32_t> byValue;
  llvm::BumpPtrAllocator mem;
  SmallVector<StringRef, 0> shown; // show(id), made on first use
  SmallVector<int8_t, 0> groundMemo;

  ArrayRef<uint32_t> elems(uint32_t id) const { return ArrayRef<uint32_t>(kids).slice(terms[id].kids, terms[id].n); }
  bool isList(uint32_t id) const { return terms[id].kind == List; }
  bool isVar(uint32_t id) const { return terms[id].kind == Var; }
  bool isString(uint32_t id) const { return terms[id].kind != List; } // datalog.nix: an atom or a variable is a string

  uint32_t atom(StringRef text, Value v = {}) {
    auto [it, fresh] = atoms.try_emplace(text, uint32_t(terms.size()));
    if (fresh) terms.push_back({text.size() >= 2 && text[0] == '?' ? Var : Atom, it->first(), 0, 0, v});
    else if (v && !terms[it->second].value) terms[it->second].value = v;
    return it->second;
  }
  uint32_t lookupAtom(StringRef text) const {
    auto it = atoms.find(text);
    return it == atoms.end() ? kNone : it->second;
  }
  uint32_t list(ArrayRef<uint32_t> es, Value v = {}) {
    if (auto it = lists.find(es); it != lists.end()) {
      if (v && !terms[it->second].value) terms[it->second].value = v;
      return it->second;
    }
    uint32_t id = uint32_t(terms.size());
    uint32_t at = uint32_t(kids.size());
    kids.append(es.begin(), es.end());
    terms.push_back({List, StringRef(), at, uint32_t(es.size()), v});
    uint32_t *key = mem.Allocate<uint32_t>(es.size());
    llvm::copy(es, key);
    lists.try_emplace(ArrayRef<uint32_t>(key, es.size()), id);
    return id;
  }
  /// The id of a term of the theory: a graph region may use a term before it is defined, so a list's elements come first.
  uint32_t of(Value v) {
    if (auto it = byValue.find(v); it != byValue.end()) return it->second;
    Operation *d = v.getDefiningOp();
    uint32_t id;
    if (auto a = dyn_cast<AtomOp>(d)) id = atom(a.getName(), v);
    else if (auto x = dyn_cast<VarOp>(d)) id = atom(x.getName(), v);
    else {
      SmallVector<uint32_t, 8> es;
      for (Value e : cast<ListOp>(d).getElements()) es.push_back(of(e));
      id = list(es, v);
    }
    byValue[v] = id;
    return id;
  }

  /// datalog.nix's show: an atom as it is, a list as (a b c).
  StringRef show(uint32_t id) {
    if (shown.size() <= id) shown.resize(terms.size());
    if (!shown[id].empty() || (!isList(id) && terms[id].text.empty())) return isList(id) ? shown[id] : terms[id].text;
    if (!isList(id)) return shown[id] = terms[id].text;
    llvm::SmallString<64> s("(");
    auto es = elems(id);
    for (size_t i = 0; i < es.size(); i++) {
      if (i) s += ' ';
      s += show(es[i]);
    }
    s += ')';
    char *p = mem.Allocate<char>(s.size());
    memcpy(p, s.data(), s.size());
    if (shown.size() <= id) shown.resize(terms.size());
    return shown[id] = StringRef(p, s.size());
  }

  bool ground(uint32_t id) {
    if (groundMemo.size() <= id) groundMemo.resize(terms.size(), -1);
    if (groundMemo[id] >= 0) return groundMemo[id];
    bool g = !isVar(id);
    if (g && isList(id))
      for (uint32_t e : elems(id))
        if (!ground(e)) { g = false; break; }
    if (groundMemo.size() <= id) groundMemo.resize(terms.size(), -1);
    return groundMemo[id] = g;
  }

  uint32_t head(uint32_t id) const { return isList(id) && terms[id].n ? kids[terms[id].kids] : kNone; } // headOf; kNone is ""
  uint32_t at(uint32_t id, unsigned i) const { return kids[terms[id].kids + i]; }
  unsigned size(uint32_t id) const { return terms[id].n; }
};

struct Bind {
  SmallVector<std::pair<uint32_t, uint32_t>, 8> v; // variable -> term
  uint32_t get(uint32_t var) const {
    for (auto &[k, x] : v)
      if (k == var) return x;
    return kNone;
  }
};
struct State {
  Bind b;
  SmallVector<uint32_t, 4> used; // the facts the premises matched, in order
};

struct Entry {
  uint32_t fact;
  int32_t rule = -1; // -1: asserted
  uint32_t round = 0;
  SmallVector<uint32_t, 4> from;
};

struct Chase {
  Terms &T;
  // the ontology: Child -> its parents, by the classes' names; ancestors made on demand
  llvm::StringMap<SmallVector<StringRef, 2>> parents;
  llvm::StringMap<llvm::DenseSet<StringRef>> ancestorsMemo;
  bool hasOntology = false;
  struct Rule { uint32_t antecedent, consequent; llvm::SmallString<32> id; };
  SmallVector<Rule, 0> rules;
  SmallVector<Entry, 0> entries;                 // asserted, then derived in the order found
  llvm::DenseMap<uint32_t, uint32_t> idx;        // fact -> its entry
  uint32_t aAnd, aExists, aNot, aEqual, aInstance;

  // the index of a round (datalog.nix's `index`): entries in show order, by relation, by relation and first argument
  SmallVector<uint32_t, 0> sorted;
  llvm::DenseMap<uint32_t, SmallVector<uint32_t, 4>> byHead;
  llvm::DenseMap<std::pair<uint32_t, uint32_t>, SmallVector<uint32_t, 2>> byFirst;

  explicit Chase(Terms &t) : T(t) {
    aAnd = T.lookupAtom("and"), aExists = T.lookupAtom("exists"), aNot = T.lookupAtom("not");
    aEqual = T.lookupAtom("equal"), aInstance = T.lookupAtom("instance");
  }

  const llvm::DenseSet<StringRef> &ancestors(StringRef c) {
    if (auto it = ancestorsMemo.find(c); it != ancestorsMemo.end()) return it->second;
    llvm::DenseSet<StringRef> out;
    SmallVector<StringRef, 16> work;
    if (auto it = parents.find(c); it != parents.end()) work.append(it->second.begin(), it->second.end());
    while (!work.empty()) {
      StringRef p = work.pop_back_val();
      if (!out.insert(p).second) continue;
      if (auto it = parents.find(p); it != parents.end()) work.append(it->second.begin(), it->second.end());
    }
    return ancestorsMemo[c] = std::move(out);
  }
  bool isSubclass(uint32_t c, uint32_t a) {
    if (c == a) return true;
    if (!T.isString(c) || !T.isString(a)) return false;
    return ancestors(T.terms[c].text).contains(T.terms[a].text);
  }

  void reindex() {
    sorted.clear();
    for (uint32_t i = 0; i < entries.size(); i++) sorted.push_back(i);
    llvm::sort(sorted, [&](uint32_t x, uint32_t y) { return T.show(entries[x].fact) < T.show(entries[y].fact); });
    byHead.clear();
    byFirst.clear();
    for (uint32_t e : sorted) {
      uint32_t f = entries[e].fact;
      byHead[T.head(f)].push_back(e);
      if (T.isList(f) && T.size(f) > 1 && T.isString(T.at(f, 1))) byFirst[{T.head(f), T.at(f, 1)}].push_back(e);
    }
  }

  uint32_t subst(const Bind &b, uint32_t s) {
    if (!T.isList(s)) {
      if (!T.isVar(s)) return s;
      uint32_t x = b.get(s);
      return x == kNone ? s : x;
    }
    if (T.ground(s)) return s;
    SmallVector<uint32_t, 8> es;
    for (uint32_t e : T.elems(s)) es.push_back(subst(b, e));
    return T.list(es);
  }

  bool unify(Bind &b, uint32_t p, uint32_t f) {
    if (T.isString(p)) {
      if (T.isVar(p)) {
        uint32_t x = b.get(p);
        if (x != kNone) return x == f;
        b.v.push_back({p, f});
        return true;
      }
      return p == f;
    }
    if (!T.isList(f) || T.size(p) != T.size(f)) return false;
    for (unsigned i = 0; i < T.size(p); i++)
      if (!unify(b, T.at(p, i), T.at(f, i))) return false;
    return true;
  }

  ArrayRef<uint32_t> candidates(const Bind &b, uint32_t p, SmallVectorImpl<uint32_t> &one) {
    uint32_t q = subst(b, p);
    uint32_t h = T.head(q);
    if (T.ground(q)) {
      if (auto it = idx.find(q); it != idx.end()) one.push_back(it->second);
      return one;
    }
    if (h != kNone && T.isString(h) && !T.isVar(h)) {
      if (T.size(q) > 1 && T.isString(T.at(q, 1)) && !T.isVar(T.at(q, 1))) {
        auto it = byFirst.find({h, T.at(q, 1)});
        return it == byFirst.end() ? ArrayRef<uint32_t>() : ArrayRef<uint32_t>(it->second);
      }
      auto it = byHead.find(h);
      return it == byHead.end() ? ArrayRef<uint32_t>() : ArrayRef<uint32_t>(it->second);
    }
    return sorted;
  }

  void step(const State &s, uint32_t p, SmallVectorImpl<State> &out) {
    uint32_t h = T.head(p);
    if (h != kNone && h == aAnd) {
      SmallVector<State, 4> sols{s};
      for (unsigned i = 1; i < T.size(p); i++) {
        SmallVector<State, 4> next;
        for (const State &t : sols) step(t, T.at(p, i), next);
        sols = std::move(next);
        if (sols.empty()) break;
      }
      out.append(std::make_move_iterator(sols.begin()), std::make_move_iterator(sols.end()));
      return;
    }
    if (h != kNone && h == aExists) return step(s, T.at(p, 2), out);
    if (h != kNone && h == aNot) {
      SmallVector<State, 2> sub;
      step(s, T.at(p, 1), sub);
      if (sub.empty()) out.push_back(s);
      return;
    }
    if (h != kNone && h == aEqual) {
      if (subst(s.b, T.at(p, 1)) == subst(s.b, T.at(p, 2))) out.push_back(s);
      return;
    }
    if (h != kNone && h == aInstance && hasOntology && T.size(p) == 3) {
      uint32_t c = subst(s.b, T.at(p, 2));
      if (!T.isVar(c)) {
        auto it = byHead.find(aInstance);
        if (it == byHead.end()) return;
        for (uint32_t e : it->second) {
          uint32_t f = entries[e].fact;
          if (T.size(f) != 3 || !isSubclass(T.at(f, 2), c)) continue;
          State t = s;
          if (!unify(t.b, T.at(p, 1), T.at(f, 1))) continue;
          t.used.push_back(f);
          out.push_back(std::move(t));
        }
        return;
      }
    }
    SmallVector<uint32_t, 1> one;
    for (uint32_t e : candidates(s.b, p, one)) {
      State t = s;
      if (!unify(t.b, p, entries[e].fact)) continue;
      t.used.push_back(entries[e].fact);
      out.push_back(std::move(t));
    }
  }

  LogicalResult run(Location loc) {
    for (uint32_t round = 1;; round++) {
      reindex();
      SmallVector<Entry, 0> fresh;
      llvm::DenseMap<uint32_t, uint32_t> freshIdx;
      for (uint32_t r = 0; r < rules.size(); r++) {
        SmallVector<State, 8> sols;
        step(State(), rules[r].antecedent, sols);
        for (State &s : sols) {
          uint32_t f = subst(s.b, rules[r].consequent);
          if (!T.ground(f))
            return emitError(loc) << "rule " << rules[r].id << ": the consequent keeps a variable (" << T.show(f) << ")";
          if (idx.count(f) || freshIdx.count(f)) continue;
          freshIdx[f] = uint32_t(fresh.size());
          fresh.push_back({f, int32_t(r), round, s.used});
        }
      }
      if (fresh.empty()) return success();
      for (Entry &e : fresh) {
        idx[e.fact] = uint32_t(entries.size());
        entries.push_back(std::move(e));
      }
    }
  }
};

/// The ontology a theory names: its `(subclass Child Parent)` facts of two atoms, and its sumo.subclass ops.
void readOntology(Chase &c, TheoryOp onto) {
  c.hasOntology = true;
  for (Operation &op : onto.getBody().front()) {
    if (auto s = dyn_cast<sumo::SubclassOp>(op)) {
      c.parents[s.getChild()].push_back(s.getParent());
      continue;
    }
    auto f = dyn_cast<FactOp>(op);
    if (!f) continue;
    auto l = f.getTerm().getDefiningOp<ListOp>();
    if (!l || l.getElements().size() != 3) continue;
    auto h = l.getElements()[0].getDefiningOp<AtomOp>();
    if (!h || h.getName() != "subclass") continue;
    // datalog.nix reads the ontology through sumo.nix: both sides are strings (a variable is a string too); a list is skipped
    auto text = [](Value v) -> StringRef {
      if (auto x = v.getDefiningOp<AtomOp>()) return x.getName();
      if (auto x = v.getDefiningOp<VarOp>()) return x.getName();
      return StringRef();
    };
    StringRef child = text(l.getElements()[1]), parent = text(l.getElements()[2]);
    if (!child.empty() && !parent.empty()) c.parents[child].push_back(parent);
  }
}

/// An op for term `id` in the theory: the theory's own, or one made at the end of its block.
Value valueOf(Terms &T, OpBuilder &b, Location loc, uint32_t id) {
  if (T.terms[id].value) return T.terms[id].value;
  Value v;
  if (T.terms[id].kind == Terms::Atom) v = AtomOp::create(b, loc, TermType::get(b.getContext()), T.terms[id].text);
  else if (T.terms[id].kind == Terms::Var) v = VarOp::create(b, loc, TermType::get(b.getContext()), T.terms[id].text);
  else {
    SmallVector<Value, 8> es;
    for (uint32_t e : T.elems(id)) es.push_back(valueOf(T, b, loc, e));
    v = ListOp::create(b, loc, TermType::get(b.getContext()), es);
  }
  return T.terms[id].value = v;
}

LogicalResult chaseTheory(TheoryOp theory) {
  Block &body = theory.getBody().front();
  for (Operation &op : llvm::make_early_inc_range(body)) // a second chase starts from the asserted facts again
    if (isa<DerivedOp>(op)) op.erase();
  Terms T;
  SmallVector<uint32_t, 0> facts;
  SmallVector<RuleOp, 0> ruleOps;
  for (Operation &op : body) {
    if (auto f = dyn_cast<FactOp>(op)) facts.push_back(T.of(f.getTerm()));
    else if (auto r = dyn_cast<RuleOp>(op)) ruleOps.push_back(r);
  }
  if (ruleOps.empty()) return success();
  Chase c(T);
  for (auto [i, r] : llvm::enumerate(ruleOps)) {
    Chase::Rule rule{T.of(r.getAntecedent()), T.of(r.getConsequent()), {}};
    uint32_t h = T.head(rule.consequent);
    rule.id = h == kNone ? StringRef() : T.show(h);
    rule.id += '#';
    llvm::raw_svector_ostream(rule.id) << (i + 1);
    c.rules.push_back(std::move(rule));
  }
  // atoms the rules test by name, interned after the theory's terms: a theory without `and` has no and-premise
  c.aAnd = T.lookupAtom("and"), c.aExists = T.lookupAtom("exists"), c.aNot = T.lookupAtom("not");
  c.aEqual = T.lookupAtom("equal"), c.aInstance = T.lookupAtom("instance");
  if (auto ref = theory.getOntologyAttr()) {
    auto onto = SymbolTable::lookupNearestSymbolFrom<TheoryOp>(theory, ref);
    if (!onto) return theory.emitOpError("names an ontology that is not a kif.theory: ") << ref;
    readOntology(c, onto);
  }
  for (uint32_t f : facts)
    if (!c.idx.count(f)) {
      c.idx[f] = uint32_t(c.entries.size());
      c.entries.push_back({f, -1, 0, {}});
    }
  if (failed(c.run(theory.getLoc()))) return failure();
  OpBuilder b(theory.getContext());
  b.setInsertionPointToEnd(&body);
  Location loc = theory.getLoc();
  for (Entry &e : c.entries) {
    if (e.rule < 0) continue;
    Value term = valueOf(T, b, loc, e.fact);
    SmallVector<Value, 4> from;
    for (uint32_t f : e.from) from.push_back(valueOf(T, b, loc, f));
    DerivedOp::create(b, loc, term, c.rules[e.rule].id, int32_t(e.round), from);
  }
  return success();
}

struct KifChasePass : PassWrapper<KifChasePass, OperationPass<ModuleOp>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(KifChasePass)
  StringRef getArgument() const override { return "kif-chase"; }
  StringRef getDescription() const override {
    return "Chain each theory's rules forward to a fixpoint: a kif.derived, with its rule and premises, per fact they give";
  }
  void runOnOperation() override {
    // a theory another one names as its ontology gives classes, not facts to chase (datalog.nix reads it only through sumo.nix)
    SmallVector<TheoryOp> theories;
    llvm::DenseSet<StringRef> ontologies;
    getOperation().walk([&](TheoryOp t) {
      theories.push_back(t);
      if (auto o = t.getOntologyAttr()) ontologies.insert(o.getValue());
    });
    for (TheoryOp t : theories)
      if (!ontologies.contains(t.getSymName()) && failed(chaseTheory(t))) return signalPassFailure();
  }
};

} // namespace

void registerKifChasePass() { PassRegistration<KifChasePass>(); }

void dumpClosure(TheoryOp theory, raw_ostream &os) {
  Terms T;
  struct Line { StringRef fact; llvm::SmallString<64> rest; };
  SmallVector<Line, 0> lines;
  llvm::DenseSet<uint32_t> seen;
  for (Operation &op : theory.getBody().front()) {
    if (auto f = dyn_cast<FactOp>(op)) {
      uint32_t id = T.of(f.getTerm());
      if (seen.insert(id).second) lines.push_back({T.show(id), llvm::SmallString<64>("-")});
    } else if (auto d = dyn_cast<DerivedOp>(op)) {
      uint32_t id = T.of(d.getTerm());
      if (!seen.insert(id).second) continue;
      Line l{T.show(id), llvm::SmallString<64>(d.getRule())};
      for (Value v : d.getFrom()) {
        l.rest += '\t';
        l.rest += T.show(T.of(v));
      }
      lines.push_back(std::move(l));
    }
  }
  llvm::sort(lines, [](const Line &a, const Line &b) { return a.fact < b.fact; });
  for (const Line &l : lines) os << l.fact << '\t' << l.rest << '\n';
}

} // namespace mlir::kif
