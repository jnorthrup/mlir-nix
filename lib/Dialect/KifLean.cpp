//===- KifLean.cpp - a chased theory's proofs as one Lean theorem -----------===//
//
// `mlnix-kif --chase --lean OUT`: the facts kif-chase derived in a theory, with the proofs it recorded, as one theorem in
// lean4export's format (NDJSON, format 3.1.0).  The Lean toolchain's kernels read that format without elaborating anything:
// nanoda_bin, con-leche and con-ron (whose --verified mode comes with a proof that what it accepts proves no False).
//
// The theorem uses no axiom and no constant: everything the theory assumes is a hypothesis of its statement,
//
//   ∀ (Term : Type) (Holds : Term → Prop) (nil : Term) (cons : Term → Term → Term)
//     (a.X : Term)...                   each atom X; a list (t1 .. tn) is cons t1 (.. (cons tn nil))
//     (Same : Term → Term → Prop) (same : ∀ t, Same t t)                                    when a rule has (equal a b)
//     (Sub : Term → Term → Prop) (sub_trans : ∀ a b c, Sub a b → Sub b c → Sub a c)
//     (inst_up : ∀ x c d, Holds (instance x c) → Sub c d → Holds (instance x d))
//     (o.j : Sub C P)...                when a proof reads (instance X Class) through the ontology (sumo.nix's isSubclass):
//                                       the (subclass C P) edges its proofs use
//     (f.i : Holds fact)...             each asserted fact
//     (r.k : ∀ vars, H p1 → .. → H pn → Holds consequent)...    each rule: H p is Holds p, or Same a b for (equal a b)
//     (Done : Prop) (done : Done),
//   Done
//
// proved by `fun .. => let d.1 : Holds d1 := r.k terms proofs; ..; let d.n : Holds dn := ..; done`: each derived fact a let,
// its rule applied to the bindings and to the proofs of the facts its premises matched (`from`: asserted facts, or lets before
// it).  The lets are the claims: a kernel checks every let's value against its type, used or not, so the theorem type-checks
// only if each derived fact follows from the hypotheses.  The conclusion is the trivial Done, not the derived facts' conjunction:
// a body that names every let (pack d.1 .. d.n, or a tree of And) made nanoda_bin, con-leche and con-ron superlinear in the
// lets (6,000 lets: 10-23 s, against 0.4 s for a body that names one), while the lets alone check in linear time.
//
// The bindings are not recorded in a kif.derived: they are found again by matching the rule's premises against `from` in
// order, as the chase matched them.  A rule with a (not ..) premise is negation as failure, the closed world of a stratum,
// not a proof from the facts: a derived fact that needs one is an error.
//
//===----------------------------------------------------------------------===//

#include "NixDialect/Kif.h"
#include "NixDialect/Sumo.h"

#include "mlir/IR/SymbolTable.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallString.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringMap.h"
#include "llvm/Support/Allocator.h"
#include "llvm/Support/Format.h"
#include "llvm/Support/JSON.h"
#include "llvm/Support/StringSaver.h"
#include "llvm/Support/raw_ostream.h"

#include <cassert>
#include <string>
#include <tuple>

namespace mlir::kif {
namespace {

constexpr uint32_t kNone = ~0u;

/// The theory's terms by structure, as kif-chase interns them (KifChase.cpp's Terms): equal terms are one id.
struct Terms {
  enum Kind : uint8_t { Atom, Var, List };
  struct T {
    Kind kind;
    StringRef text;
    uint32_t at = 0, n = 0; // a list's elements: kids[at .. at+n)
  };
  SmallVector<T, 0> terms;
  SmallVector<uint32_t, 0> kids;
  llvm::StringMap<uint32_t> atoms;
  llvm::DenseMap<ArrayRef<uint32_t>, uint32_t> lists;
  llvm::DenseMap<Value, uint32_t> byValue;
  llvm::BumpPtrAllocator mem;
  SmallVector<int8_t, 0> groundMemo;

  uint32_t atom(StringRef text) {
    auto [it, fresh] = atoms.try_emplace(text, uint32_t(terms.size()));
    if (fresh) terms.push_back({text.size() >= 2 && text[0] == '?' ? Var : Atom, it->first(), 0, 0});
    return it->second;
  }
  uint32_t lookupAtom(StringRef text) const {
    auto it = atoms.find(text);
    return it == atoms.end() ? kNone : it->second;
  }
  uint32_t list(ArrayRef<uint32_t> es) {
    if (auto it = lists.find(es); it != lists.end()) return it->second;
    uint32_t id = uint32_t(terms.size());
    uint32_t at = uint32_t(kids.size());
    kids.append(es.begin(), es.end());
    terms.push_back({List, StringRef(), at, uint32_t(es.size())});
    uint32_t *key = mem.Allocate<uint32_t>(es.size());
    llvm::copy(es, key);
    lists.try_emplace(ArrayRef<uint32_t>(key, es.size()), id);
    return id;
  }
  uint32_t of(Value v) {
    if (auto it = byValue.find(v); it != byValue.end()) return it->second;
    Operation *d = v.getDefiningOp();
    uint32_t id;
    if (auto a = dyn_cast<AtomOp>(d)) id = atom(a.getName());
    else if (auto x = dyn_cast<VarOp>(d)) id = atom(x.getName());
    else {
      SmallVector<uint32_t, 8> es;
      for (Value e : cast<ListOp>(d).getElements()) es.push_back(of(e));
      id = list(es);
    }
    byValue[v] = id;
    return id;
  }
  ArrayRef<uint32_t> elems(uint32_t id) const { return ArrayRef<uint32_t>(kids).slice(terms[id].at, terms[id].n); }
  bool isList(uint32_t id) const { return terms[id].kind == List; }
  bool isVar(uint32_t id) const { return terms[id].kind == Var; }
  bool isString(uint32_t id) const { return terms[id].kind != List; }
  uint32_t head(uint32_t id) const { return isList(id) && terms[id].n ? kids[terms[id].at] : kNone; }
  uint32_t at(uint32_t id, unsigned i) const { return kids[terms[id].at + i]; }
  unsigned size(uint32_t id) const { return terms[id].n; }
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
  void show(uint32_t id, std::string &s) const {
    if (!isList(id)) { s += terms[id].text.str(); return; }
    s += '(';
    for (auto [i, e] : llvm::enumerate(elems(id))) {
      if (i) s += ' ';
      show(e, s);
    }
    s += ')';
  }
  std::string show(uint32_t id) const {
    std::string s;
    show(id, s);
    return s;
  }
};

using Bind = SmallVector<std::pair<uint32_t, uint32_t>, 8>; // variable -> term

uint32_t lookup(const Bind &b, uint32_t var) {
  for (auto &[k, x] : b)
    if (k == var) return x;
  return kNone;
}

/// The chase's matching (KifChase.cpp's unify and subst): a variable of the premise takes the fact's term, or must equal what
/// it took; an atom must be the fact's; a list matches a list of its length element by element.
bool unify(Terms &T, Bind &b, uint32_t p, uint32_t f) {
  if (T.isString(p)) {
    if (T.isVar(p)) {
      uint32_t x = lookup(b, p);
      if (x != kNone) return x == f;
      b.push_back({p, f});
      return true;
    }
    return p == f;
  }
  if (!T.isList(f) || T.size(p) != T.size(f)) return false;
  for (unsigned i = 0; i < T.size(p); i++)
    if (!unify(T, b, T.at(p, i), T.at(f, i))) return false;
  return true;
}
uint32_t subst(Terms &T, const Bind &b, uint32_t s) {
  if (!T.isList(s)) {
    if (!T.isVar(s)) return s;
    uint32_t x = lookup(b, s);
    return x == kNone ? s : x;
  }
  if (T.ground(s)) return s;
  SmallVector<uint32_t, 8> es;
  for (uint32_t e : T.elems(s)) es.push_back(subst(T, b, e));
  return T.list(es);
}

/// A premise of a rule, flattened out of (and ..) and (exists vars ..) in the chase's order.
struct Form {
  enum Kind { Pattern, Equal, Instance } kind;
  uint32_t p = kNone, a = kNone, b = kNone; // Pattern, Instance: p; Equal: a, b
};
struct Rule {
  std::string id;              // datalog.nix's name: the consequent's relation, '#', the rule's place
  uint32_t consequent = kNone;
  SmallVector<uint32_t, 8> vars; // in the order they first occur: the antecedent, then the consequent
  SmallVector<Form, 4> forms;
  bool negation = false;       // a (not ..) premise somewhere
};
/// How one premise of a derived fact is proved.
struct Premise {
  enum Kind { Fact, Same, Up } kind;
  uint32_t fact = kNone;          // Fact, Up: the fact the premise matched
  uint32_t term = kNone;          // Same: the term both sides are; Up: the instance
  uint32_t from = kNone, to = kNone; // Up: the fact's class and the premise's
  SmallVector<uint32_t, 4> path;  // Up: the ontology edges from `from` up to `to`
};
struct Proof {
  uint32_t fact;
  unsigned rule;                  // index into Rules
  SmallVector<uint32_t, 8> inst;  // a term for each of the rule's vars (kNone: never bound, any term will do: nil)
  SmallVector<Premise, 4> premises;
};

/// lean4export's records (format 3.1.0), written as they are made: names, then expressions, each once (equal ones share an
/// index), children before parents; the declaration last.
struct Writer {
  raw_ostream &os;
  llvm::BumpPtrAllocator mem;
  llvm::UniqueStringSaver saver{mem};
  llvm::DenseMap<std::pair<uint32_t, StringRef>, uint32_t> names;
  llvm::DenseMap<std::pair<uint32_t, uint64_t>, uint32_t> numNames;
  llvm::DenseMap<std::tuple<uint8_t, uint32_t, uint32_t, uint32_t, uint32_t>, uint32_t> exprs;
  uint32_t nNames = 1, nExprs = 0; // name 0 is the anonymous one
  enum Kind : uint8_t { Sort, BVar, App, Pi, Lam, Let };

  explicit Writer(raw_ostream &os) : os(os) {
    // nanoda_bin requires the `lean` field; no Lean environment is exported here (the theorem needs no prelude), so it is empty
    os << R"({"meta":{"exporter":{"name":"mlnix-kif","version":"1"},"format":{"version":"3.1.0"},)"
       << R"("lean":{"githash":"","version":""}}})" << '\n';
    os << R"({"il":1,"succ":0})" << '\n'; // level 1; level 0 is zero
  }
  void string(StringRef s) {
    std::string fixed;
    if (!llvm::json::isUTF8(s)) s = fixed = llvm::json::fixUTF8(s);
    os << '"';
    for (unsigned char c : s) {
      if (c == '"' || c == '\\') os << '\\' << char(c);
      else if (c < 0x20) os << llvm::format("\\u%04x", c);
      else os << char(c);
    }
    os << '"';
  }
  uint32_t name(StringRef s, uint32_t pre = 0) {
    s = saver.save(s);
    auto [it, fresh] = names.try_emplace({pre, s}, nNames);
    if (!fresh) return it->second;
    os << R"({"in":)" << nNames << R"(,"str":{"pre":)" << pre << R"(,"str":)";
    string(s);
    os << "}}\n";
    return nNames++;
  }
  uint32_t numName(StringRef family, uint64_t i) {
    uint32_t pre = name(family);
    auto [it, fresh] = numNames.try_emplace({pre, i}, nNames);
    if (!fresh) return it->second;
    os << R"({"in":)" << nNames << R"(,"num":{"i":)" << i << R"(,"pre":)" << pre << "}}\n";
    return nNames++;
  }
  /// The index of an expression, written the first time it is made.
  template <typename F>
  uint32_t expr(Kind k, uint32_t a, uint32_t b, uint32_t c, uint32_t d, F write) {
    auto [it, fresh] = exprs.try_emplace({k, a, b, c, d}, nExprs);
    if (!fresh) return it->second;
    write(nExprs);
    return nExprs++;
  }
  uint32_t sort(uint32_t level) {
    return expr(Sort, level, 0, 0, 0, [&](uint32_t i) { os << R"({"ie":)" << i << R"(,"sort":)" << level << "}\n"; });
  }
  uint32_t bvar(uint32_t n) {
    return expr(BVar, n, 0, 0, 0, [&](uint32_t i) { os << R"({"bvar":)" << n << R"(,"ie":)" << i << "}\n"; });
  }
  uint32_t app(uint32_t f, uint32_t a) {
    return expr(App, f, a, 0, 0,
                [&](uint32_t i) { os << R"({"app":{"arg":)" << a << R"(,"fn":)" << f << R"(},"ie":)" << i << "}\n"; });
  }
  uint32_t binder(Kind k, uint32_t n, uint32_t type, uint32_t body) {
    return expr(k, n, type, body, 0, [&](uint32_t i) {
      os << (k == Pi ? R"({"forallE":)" : R"({"lam":)") << R"({"binderInfo":"default","body":)" << body << R"(,"name":)" << n
         << R"(,"type":)" << type << R"(},"ie":)" << i << "}\n";
    });
  }
  uint32_t pi(uint32_t n, uint32_t type, uint32_t body) { return binder(Pi, n, type, body); }
  uint32_t lam(uint32_t n, uint32_t type, uint32_t body) { return binder(Lam, n, type, body); }
  uint32_t let(uint32_t n, uint32_t type, uint32_t value, uint32_t body) {
    return expr(Let, n, type, value, body, [&](uint32_t i) {
      os << R"({"ie":)" << i << R"(,"letE":{"body":)" << body << R"(,"name":)" << n << R"(,"nondep":false,"type":)" << type
         << R"(,"value":)" << value << "}}\n";
    });
  }
  void theorem(uint32_t n, uint32_t type, uint32_t value) {
    os << R"({"thm":{"all":[)" << n << R"(],"levelParams":[],"name":)" << n << R"(,"type":)" << type << R"(,"value":)"
       << value << "}}\n";
  }
};

struct Certificate {
  Terms T;
  TheoryOp theory;
  // the ontology: (child, parent) edges by class name, as kif-chase reads them (readOntology)
  bool hasOntology = false;
  SmallVector<std::pair<StringRef, StringRef>, 0> edges;
  llvm::StringMap<SmallVector<uint32_t, 2>> up; // a class -> its edges to its parents
  uint32_t aAnd = kNone, aExists = kNone, aNot = kNone, aEqual = kNone, aInstance = kNone;

  SmallVector<uint32_t, 0> asserted;   // each asserted fact once, in the theory's order
  llvm::DenseMap<uint32_t, uint32_t> assertedAt;
  SmallVector<Rule, 0> rules;
  SmallVector<Proof, 0> proofs;        // the kif.derived ops, in the order the chase found them
  llvm::DenseMap<uint32_t, uint32_t> derivedAt;
  bool usesSame = false, usesUp = false;
  SmallVector<uint32_t, 0> usedEdges;  // the ontology edges a proof uses, first use first
  llvm::DenseMap<uint32_t, uint32_t> edgeAt;

  explicit Certificate(TheoryOp t) : theory(t) {}

  void readOntology(TheoryOp onto) {
    hasOntology = true;
    auto edge = [&](StringRef c, StringRef p) {
      up[c].push_back(uint32_t(edges.size()));
      edges.push_back({c, p});
    };
    for (Operation &op : onto.getBody().front()) {
      if (auto s = dyn_cast<sumo::SubclassOp>(op)) {
        edge(s.getChild(), s.getParent());
        continue;
      }
      auto f = dyn_cast<FactOp>(op);
      if (!f) continue;
      auto l = f.getTerm().getDefiningOp<ListOp>();
      if (!l || l.getElements().size() != 3) continue;
      auto h = l.getElements()[0].getDefiningOp<AtomOp>();
      if (!h || h.getName() != "subclass") continue;
      auto text = [](Value v) -> StringRef {
        if (auto x = v.getDefiningOp<AtomOp>()) return x.getName();
        if (auto x = v.getDefiningOp<VarOp>()) return x.getName();
        return StringRef();
      };
      StringRef child = text(l.getElements()[1]), parent = text(l.getElements()[2]);
      if (!child.empty() && !parent.empty()) edge(child, parent);
    }
  }

  /// The edges from class `c` up to class `a` (a shortest path), or false when `a` is not among c's ancestors.
  bool path(StringRef c, StringRef a, SmallVectorImpl<uint32_t> &out) {
    llvm::StringMap<uint32_t> via; // a class reached -> the edge that reached it
    SmallVector<StringRef, 16> queue{c};
    via[c] = kNone;
    for (size_t q = 0; q < queue.size(); q++) {
      StringRef x = queue[q];
      if (x == a && q) break;
      auto it = up.find(x);
      if (it == up.end()) continue;
      for (uint32_t e : it->second)
        if (via.try_emplace(edges[e].second, e).second) queue.push_back(edges[e].second);
    }
    auto it = via.find(a);
    if (a == c || it == via.end()) return false;
    for (StringRef x = a; x != c;) {
      uint32_t e = via[x];
      out.push_back(e);
      x = edges[e].first;
    }
    std::reverse(out.begin(), out.end());
    return true;
  }

  void vars(uint32_t t, SmallVectorImpl<uint32_t> &out) {
    if (T.isVar(t)) {
      if (!llvm::is_contained(out, t)) out.push_back(t);
    } else if (T.isList(t)) {
      for (uint32_t e : T.elems(t)) vars(e, out);
    }
  }
  void flatten(Rule &r, uint32_t p) {
    uint32_t h = T.head(p);
    if (h != kNone && h == aAnd) {
      for (unsigned i = 1; i < T.size(p); i++) flatten(r, T.at(p, i));
    } else if (h != kNone && h == aExists) {
      flatten(r, T.at(p, 2));
    } else if (h != kNone && h == aNot) {
      r.negation = true;
    } else if (h != kNone && h == aEqual) {
      r.forms.push_back({Form::Equal, kNone, T.at(p, 1), T.at(p, 2)});
    } else if (h != kNone && h == aInstance && hasOntology && T.size(p) == 3) {
      r.forms.push_back({Form::Instance, p});
    } else {
      r.forms.push_back({Form::Pattern, p});
    }
  }

  LogicalResult read() {
    Block &body = theory.getBody().front();
    SmallVector<RuleOp, 0> ruleOps;
    SmallVector<DerivedOp, 0> derived;
    for (Operation &op : body) {
      if (auto f = dyn_cast<FactOp>(op)) {
        uint32_t id = T.of(f.getTerm());
        if (assertedAt.try_emplace(id, uint32_t(asserted.size())).second) asserted.push_back(id);
      } else if (auto r = dyn_cast<RuleOp>(op)) {
        ruleOps.push_back(r);
      } else if (auto d = dyn_cast<DerivedOp>(op)) {
        derived.push_back(d);
      }
    }
    // the atoms the rules test by name, looked up once every term of the rules is interned (as kif-chase does)
    SmallVector<std::pair<uint32_t, uint32_t>, 0> ruleTerms;
    for (RuleOp r : ruleOps) ruleTerms.push_back({T.of(r.getAntecedent()), T.of(r.getConsequent())});
    aAnd = T.lookupAtom("and"), aExists = T.lookupAtom("exists"), aNot = T.lookupAtom("not");
    aEqual = T.lookupAtom("equal"), aInstance = T.lookupAtom("instance");
    if (auto ref = theory.getOntologyAttr()) {
      auto onto = SymbolTable::lookupNearestSymbolFrom<TheoryOp>(theory, ref);
      if (!onto) return theory.emitOpError("names an ontology that is not a kif.theory: ") << ref;
      readOntology(onto);
    }
    llvm::StringMap<unsigned> byId;
    for (auto [i, r] : llvm::enumerate(ruleTerms)) {
      Rule rule;
      uint32_t antecedent = r.first;
      rule.consequent = r.second;
      uint32_t h = T.head(rule.consequent);
      rule.id = (h == kNone ? std::string() : T.show(h)) + "#" + std::to_string(i + 1);
      vars(antecedent, rule.vars);
      vars(rule.consequent, rule.vars);
      flatten(rule, antecedent);
      byId[rule.id] = unsigned(rules.size());
      rules.push_back(std::move(rule));
    }
    for (DerivedOp d : derived) {
      Proof p;
      p.fact = T.of(d.getTerm());
      auto it = byId.find(d.getRule());
      if (it == byId.end()) return d.emitOpError("names a rule the theory does not have: ") << d.getRule();
      p.rule = it->second;
      Rule &r = rules[p.rule];
      if (r.negation)
        return d.emitOpError("is derived by rule ")
               << r.id << ", whose (not ..) premise is negation as failure: the closed world of a stratum, not a proof "
               << "from the facts, so no Lean certificate is given for " << T.show(p.fact);
      SmallVector<uint32_t, 4> from;
      for (Value v : d.getFrom()) from.push_back(T.of(v));
      if (failed(replay(d, r, from, p))) return failure();
      derivedAt[p.fact] = uint32_t(proofs.size());
      proofs.push_back(std::move(p));
    }
    return success();
  }

  /// The proof of one derived fact: its rule's premises matched against `from` again, in the chase's order.
  LogicalResult replay(DerivedOp d, Rule &r, ArrayRef<uint32_t> from, Proof &p) {
    Bind b;
    size_t next = 0;
    auto proved = [&](uint32_t f) { return assertedAt.count(f) || derivedAt.count(f); };
    auto take = [&](uint32_t &f) -> LogicalResult {
      if (next >= from.size()) return d.emitOpError("has fewer premises than rule ") << r.id << " matches";
      f = from[next++];
      if (!proved(f)) return d.emitOpError("rests on ") << T.show(f) << ", which is neither asserted nor derived before it";
      return success();
    };
    for (const Form &form : r.forms) {
      if (form.kind == Form::Equal) {
        uint32_t x = subst(T, b, form.a), y = subst(T, b, form.b);
        if (x != y) return d.emitOpError("rule ") << r.id << ": (equal " << T.show(x) << " " << T.show(y) << ") does not hold";
        p.premises.push_back({Premise::Same, kNone, x});
        usesSame = true;
        continue;
      }
      if (form.kind == Form::Instance) {
        uint32_t c = subst(T, b, T.at(form.p, 2));
        if (!T.isVar(c)) {
          uint32_t f;
          if (failed(take(f))) return failure();
          if (!T.isList(f) || T.size(f) != 3 || T.head(f) != aInstance || !unify(T, b, T.at(form.p, 1), T.at(f, 1)))
            return d.emitOpError("rule ") << r.id << ": " << T.show(f) << " does not match " << T.show(form.p);
          uint32_t fc = T.at(f, 2);
          if (fc == c) {
            p.premises.push_back({Premise::Fact, f});
            continue;
          }
          Premise up{Premise::Up, f, T.at(f, 1), fc, c};
          if (!T.isString(fc) || !T.isString(c) || !path(T.terms[fc].text, T.terms[c].text, up.path))
            return d.emitOpError("rule ") << r.id << ": " << T.show(fc) << " is not a subclass of " << T.show(c);
          for (uint32_t e : up.path)
            if (edgeAt.try_emplace(e, uint32_t(usedEdges.size())).second) usedEdges.push_back(e);
          p.premises.push_back(std::move(up));
          usesUp = true;
          continue;
        }
      }
      uint32_t f;
      if (failed(take(f))) return failure();
      if (!unify(T, b, form.p, f))
        return d.emitOpError("rule ") << r.id << ": " << T.show(f) << " does not match " << T.show(form.p);
      p.premises.push_back({Premise::Fact, f});
    }
    if (next != from.size()) return d.emitOpError("has more premises than rule ") << r.id << " matches";
    if (subst(T, b, r.consequent) != p.fact)
      return d.emitOpError("rule ") << r.id << " gives " << T.show(subst(T, b, r.consequent)) << ", not " << T.show(p.fact);
    for (uint32_t v : r.vars) p.inst.push_back(lookup(b, v));
    return success();
  }

  // ---- the theorem

  // a binder's place in the telescope (0: Term, outermost); a reference from depth d to place q is bvar(d - 1 - q)
  uint32_t qTerm = 0, qHolds = 1, qNil = 2, qCons = 3, qSame = kNone, qSameRefl = kNone, qSub = kNone, qSubTrans = kNone,
           qInstUp = kNone, qDone = kNone, qDoneIntro = kNone, nBinders = 0;
  llvm::DenseMap<uint32_t, uint32_t> qAtom, qFact; // an atom's place; an asserted fact's
  SmallVector<uint32_t, 0> qEdge, qRule;          // the place of each used edge (usedEdges' order); of each rule
  SmallVector<uint32_t, 0> atomOrder;

  void atomsOf(uint32_t t, bool rule) {
    if (T.isList(t)) {
      for (uint32_t e : T.elems(t)) atomsOf(e, rule);
      return;
    }
    if (rule && T.isVar(t)) return; // a rule's variable is bound by the rule
    if (qAtom.try_emplace(t, kNone).second) atomOrder.push_back(t);
  }

  void place() {
    for (uint32_t f : asserted) atomsOf(f, false);
    for (Rule &r : rules)
      if (!r.negation) {
        for (const Form &form : r.forms) {
          if (form.kind == Form::Equal) atomsOf(form.a, true), atomsOf(form.b, true);
          else atomsOf(form.p, true);
        }
        atomsOf(r.consequent, true);
      }
    for (Proof &p : proofs) atomsOf(p.fact, false);
    if (usesUp) {
      atomsOf(aInstance, false);
      for (uint32_t e : usedEdges) atomsOf(T.atom(edges[e].first), false), atomsOf(T.atom(edges[e].second), false);
    }
    uint32_t q = 4;
    for (uint32_t a : atomOrder) qAtom[a] = q++;
    if (usesSame) qSame = q++, qSameRefl = q++;
    if (usesUp) qSub = q++, qSubTrans = q++, qInstUp = q++;
    for (size_t i = 0; i < usedEdges.size(); i++) qEdge.push_back(q++);
    for (uint32_t f : asserted) qFact[f] = q++;
    for (Rule &r : rules) qRule.push_back(r.negation ? kNone : q++);
    qDone = q++, qDoneIntro = q++;
    nBinders = q;
  }

  Writer *w = nullptr;
  llvm::DenseMap<std::pair<uint32_t, uint32_t>, uint32_t> groundAt; // (term, depth) -> expression

  uint32_t ref(uint32_t depth, uint32_t q) { return w->bvar(depth - 1 - q); }
  /// A term at `depth`; a rule's variable is the binder at its place in `vars` (`varQ`: the place of the first).
  uint32_t term(uint32_t t, uint32_t depth, ArrayRef<uint32_t> vars = {}, uint32_t varQ = 0) {
    bool closed = vars.empty();
    if (closed)
      if (auto it = groundAt.find({t, depth}); it != groundAt.end()) return it->second;
    uint32_t e;
    if (T.isList(t)) {
      e = ref(depth, qNil);
      auto es = T.elems(t);
      for (size_t i = es.size(); i-- > 0;) e = w->app(w->app(ref(depth, qCons), term(es[i], depth, vars, varQ)), e);
    } else if (!closed && T.isVar(t)) {
      auto at = llvm::find(vars, t);
      e = ref(depth, varQ + uint32_t(at - vars.begin()));
    } else {
      e = ref(depth, qAtom.lookup(t));
    }
    if (closed) groundAt[{t, depth}] = e;
    return e;
  }
  uint32_t holds(uint32_t t, uint32_t depth, ArrayRef<uint32_t> vars = {}, uint32_t varQ = 0) {
    return w->app(ref(depth, qHolds), term(t, depth, vars, varQ));
  }
  uint32_t arrow(uint32_t a, uint32_t b) { return w->pi(w->name("h"), a, b); }

  /// The types of the fixed binders, each made at its own place's depth.
  uint32_t fixedType(uint32_t q) {
    if (q == qTerm) return w->sort(1);
    uint32_t termTy = ref(q, qTerm), prop = w->sort(0);
    auto termAt = [&](uint32_t d) { return ref(d, qTerm); };
    if (q == qHolds) return w->pi(w->name("t"), termTy, prop);
    if (q == qNil) return termTy;
    if (q == qCons) return w->pi(w->name("x"), termTy, w->pi(w->name("xs"), termAt(q + 1), termAt(q + 2)));
    if (q == qSame || q == qSub) return w->pi(w->name("a"), termTy, w->pi(w->name("b"), termAt(q + 1), prop));
    if (q == qSameRefl) // ∀ t, Same t t
      return w->pi(w->name("t"), termTy, w->app(w->app(ref(q + 1, qSame), w->bvar(0)), w->bvar(0)));
    if (q == qSubTrans) { // ∀ a b c, Sub a b → Sub b c → Sub a c
      auto sub = [&](uint32_t d, uint32_t x, uint32_t y) { return w->app(w->app(ref(d, qSub), ref(d, x)), ref(d, y)); };
      uint32_t a = q, b = q + 1, c = q + 2;
      uint32_t body = sub(q + 5, a, c);
      body = arrow(sub(q + 4, b, c), body);
      body = arrow(sub(q + 3, a, b), body);
      return w->pi(w->name("a"), termTy, w->pi(w->name("b"), termAt(q + 1), w->pi(w->name("c"), termAt(q + 2), body)));
    }
    if (q == qInstUp) { // ∀ x c d, Holds (instance x c) → Sub c d → Holds (instance x d)
      uint32_t x = q, c = q + 1, dd = q + 2;
      auto inst = [&](uint32_t depth, uint32_t cls) {
        uint32_t e = ref(depth, qNil);
        e = w->app(w->app(ref(depth, qCons), ref(depth, cls)), e);
        e = w->app(w->app(ref(depth, qCons), ref(depth, x)), e);
        e = w->app(w->app(ref(depth, qCons), ref(depth, qAtom.lookup(aInstance))), e);
        return w->app(ref(depth, qHolds), e);
      };
      uint32_t body = inst(q + 5, dd);
      body = arrow(w->app(w->app(ref(q + 4, qSub), ref(q + 4, c)), ref(q + 4, dd)), body);
      body = arrow(inst(q + 3, c), body);
      return w->pi(w->name("x"), termTy, w->pi(w->name("c"), termAt(q + 1), w->pi(w->name("d"), termAt(q + 2), body)));
    }
    if (q == qDone) return prop;
    assert(q == qDoneIntro && "not a fixed binder");
    return ref(q, qDone);
  }

  /// ∀ vars, H p1 → .. → H pn → Holds consequent, made at depth q.
  uint32_t ruleType(const Rule &r, uint32_t q) {
    uint32_t m = uint32_t(r.vars.size()), n = uint32_t(r.forms.size());
    uint32_t body = holds(r.consequent, q + m + n, r.vars, q);
    for (uint32_t i = n; i-- > 0;) {
      uint32_t d = q + m + i;
      const Form &form = r.forms[i];
      uint32_t h = form.kind == Form::Equal
                       ? w->app(w->app(ref(d, qSame), term(form.a, d, r.vars, q)), term(form.b, d, r.vars, q))
                       : holds(form.p, d, r.vars, q);
      body = arrow(h, body);
    }
    for (uint32_t j = m; j-- > 0;) body = w->pi(w->name(T.terms[r.vars[j]].text), ref(q + j, qTerm), body);
    return body;
  }

  /// The proof of a fact (asserted, or the let of a derived one before the i-th) at depth `depth` (= nBinders + i).
  uint32_t factProof(uint32_t f, uint32_t depth) {
    if (auto it = assertedAt.find(f); it != assertedAt.end()) return ref(depth, qFact.lookup(f));
    return ref(depth, nBinders + derivedAt.lookup(f));
  }
  uint32_t subProof(ArrayRef<uint32_t> path, uint32_t depth) { // Sub (path's first child) (path's last parent)
    uint32_t e0 = path.front();
    uint32_t edge = ref(depth, qEdge[edgeAt.lookup(e0)]);
    if (path.size() == 1) return edge;
    uint32_t top = T.atom(edges[path.back()].second);
    uint32_t e = ref(depth, qSubTrans);
    e = w->app(e, term(T.atom(edges[e0].first), depth));
    e = w->app(e, term(T.atom(edges[e0].second), depth));
    e = w->app(e, term(top, depth));
    e = w->app(e, edge);
    return w->app(e, subProof(path.drop_front(), depth));
  }
  uint32_t proofValue(const Proof &p, uint32_t depth) {
    uint32_t e = ref(depth, qRule[p.rule]);
    for (uint32_t t : p.inst) e = w->app(e, t == kNone ? ref(depth, qNil) : term(t, depth));
    for (const Premise &pr : p.premises) {
      uint32_t x;
      if (pr.kind == Premise::Fact) x = factProof(pr.fact, depth);
      else if (pr.kind == Premise::Same) x = w->app(ref(depth, qSameRefl), term(pr.term, depth));
      else {
        x = ref(depth, qInstUp);
        x = w->app(x, term(pr.term, depth));
        x = w->app(x, term(pr.from, depth));
        x = w->app(x, term(pr.to, depth));
        x = w->app(x, factProof(pr.fact, depth));
        x = w->app(x, subProof(pr.path, depth));
      }
      e = w->app(e, x);
    }
    return e;
  }

  void write(raw_ostream &os) {
    place();
    Writer writer(os);
    w = &writer;
    SmallVector<uint32_t, 0> names(nBinders, kNone), types(nBinders, kNone);
    auto fixed = [&](uint32_t q, StringRef name) {
      if (q == kNone) return;
      names[q] = w->name(name);
      types[q] = fixedType(q);
    };
    fixed(qTerm, "Term"), fixed(qHolds, "Holds"), fixed(qNil, "nil"), fixed(qCons, "cons");
    uint32_t a = w->name("a");
    for (uint32_t t : atomOrder) {
      uint32_t q = qAtom[t];
      names[q] = w->name(T.terms[t].text, a);
      types[q] = ref(q, qTerm);
    }
    fixed(qSame, "Same"), fixed(qSameRefl, "same"), fixed(qSub, "Sub"), fixed(qSubTrans, "sub_trans");
    fixed(qInstUp, "inst_up");
    for (auto [i, e] : llvm::enumerate(usedEdges)) {
      uint32_t q = qEdge[i];
      names[q] = w->numName("o", i);
      types[q] = w->app(w->app(ref(q, qSub), term(T.atom(edges[e].first), q)), term(T.atom(edges[e].second), q));
    }
    for (auto [i, f] : llvm::enumerate(asserted)) {
      uint32_t q = qFact[f];
      names[q] = w->numName("f", i);
      types[q] = holds(f, q);
    }
    for (auto [k, r] : llvm::enumerate(rules)) {
      uint32_t q = qRule[k];
      if (q == kNone) continue;
      names[q] = w->numName("r", k + 1);
      types[q] = ruleType(r, q);
    }
    fixed(qDone, "Done"), fixed(qDoneIntro, "done");
    uint32_t n = uint32_t(proofs.size());
    // the statement: ∀ binders, Done
    uint32_t type = ref(nBinders, qDone);
    for (uint32_t q = nBinders; q-- > 0;) type = w->pi(names[q], types[q], type);
    // the proof: fun binders => let d.1 := ..; ..; let d.n := ..; done
    uint32_t body = ref(nBinders + n, qDoneIntro);
    for (uint32_t i = n; i-- > 0;) {
      uint32_t depth = nBinders + i;
      body = w->let(w->numName("d", i), holds(proofs[i].fact, depth), proofValue(proofs[i], depth), body);
    }
    for (uint32_t q = nBinders; q-- > 0;) body = w->lam(names[q], types[q], body);
    w->theorem(w->name("closure"), type, body);
    w = nullptr;
  }
};

} // namespace

LogicalResult exportLean(TheoryOp theory, raw_ostream &os) {
  Certificate c(theory);
  if (failed(c.read())) return failure();
  c.write(os);
  return success();
}

} // namespace mlir::kif
