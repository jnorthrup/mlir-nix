//===- KifTptp.cpp - a kif.theory as TPTP FOF, the way SigmaKEE translates it ===//
//
// `mlnix-kif --tptp OUT`: the theory @kb as a TPTP problem in FOF, for Vampire.  The translation is SigmaKEE's (d3cc7b4:
// trans/SUMOKBtoTPTPKB, FormulaPreprocessor, parsing/ExprToTPTP, KBcache), ported, so that the problem comes from the kif
// dialect and can be compared formula by formula with the one SigmaKEE writes (scripts/kif-tptp-compare.py):
//
//   the cache    KBcache's: instanceOf (an instance's classes, up the subclass closure), the relations (from Relation down
//                subclass, instance and subrelation), the functions (the relations that are instances of Function), and a
//                relation's signature: arg 0 its range (rangeSubclass: "C+"), arg i its domain (domainSubclass: "C+"),
//                Entity where none is given, inherited down subrelation where the child states no domain of that class.
//                instanceOf also climbs subrelation and subAttribute (KBcache.buildTransInstOf: an attribute is an instance
//                of what the attributes above it are instances of).  The closure is written as SigmaKEE's SUMO_Cache.kif
//                is: for each transitive relation (an instance of TransitiveRelation or of a subclass, or a subrelation
//                of one) each (rel A B) of its transitive closure, and each (instance X C) of instanceOf, not asserted.
//   not written  a form whose predicate is excluded (documentation, domain, format, termFormat, externalImage,
//                relatedExternalConcept, relatedInternalConcept, formerName, abbreviation, conventionalShortName,
//                conventionalLongName) or that is a test's note, category, time or answer; a higher-order form
//                (Formula.isHigherOrderExpr: a predicate with an argument of type Formula, or with a compound argument that
//                is no function term); one with two predicate variables but the two SigmaKEE instantiates pair by pair
//                (PredVarInst.handleDoubles); one whose predicate variable has no instance.  Each is a comment with the
//                reason.
//   predicate    PredVarInst's: a variable in predicate position is each relation in turn (predicates, or functions where
//   variables    the variable's types include Function) that has the arity of its literals (any, with a row variable) and
//                is an instance of each of its types (from its argument places, and a rule's (instance ?REL C)); not
//                equal, a comparison, an arithmetic function or a relation SigmaKEE made (a name with __).
//   row          RowVar.expandRowVarExpr: @ROW becomes ?ROW1 .. ?ROWn, n the arity its relations leave it, or each of 1..7
//   variables    where one is of variable arity (and the relation becomes R__k); two arities that disagree, or numeric
//                and non-numeric types at one place, leave it as it is.
//   preprocess   a variable-arity relation takes its arity as a suffix (partition__3, ListFn__3Fn); then a variable gets
//                the types its argument places give (the signature of the relation or function it is an argument of, a
//                function's range when it is equal to the function's value), the supertypes dropped where two places
//                meet, unless the antecedent types it already with (instance ?X C): a guard (instance ?X C), or
//                (subclass ?X C) for "C+", none for Entity, World or ObjectiveNorm.  A free variable's guards are the
//                antecedent of the whole formula, a forall's the antecedent of its body, an exists' conjuncts of its body.
//   rendering    ExprToTPTP's: s__ before a symbol (its - and . made _), __m after one in argument position that is a
//                relation, starts lower case or ends in Fn; V__ before a variable; n__ before a number; (<=> a b) as
//                ((a => b) & (b => a)); the free variables universal: fof(kb_N,axiom,(( ! [V__..] : (..) ))).
//   the query    a test's (query F) is the conjecture, as SigmaKEE asks it: not type-restricted, its free variables
//                existential.
//
// Each formula is preceded by `% f: ` and the form, one line, as SigmaKEE prints it: the key the comparison uses.
//
//===----------------------------------------------------------------------===//

#include "NixDialect/Kif.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/Support/raw_ostream.h"

#include <algorithm>
#include <deque>
#include <map>
#include <optional>
#include <set>
#include <string>
#include <vector>

using namespace mlir;
using namespace mlir::kif;

namespace {

/// A form as SigmaKEE's Expr sees it: an atom, a variable (?X), a row variable (@ROW), a number, a string, or a list.
struct Node {
  enum Kind : uint8_t { Atom, Var, Row, Num, Str, List } kind;
  std::string name;                 // the text of all but a list
  std::vector<const Node *> kids;   // a list's elements, its head first
};

using TypeMap = std::map<std::string, std::set<std::string>>;

bool isNumeric(llvm::StringRef s) { // -?[0-9]+(.[0-9]+)?
  size_t i = 0;
  if (i < s.size() && s[i] == '-') i++;
  size_t d = i;
  while (i < s.size() && isdigit((unsigned char)s[i])) i++;
  if (i == d) return false;
  if (i < s.size() && s[i] == '.') {
    size_t f = ++i;
    while (i < s.size() && isdigit((unsigned char)s[i])) i++;
    if (i == f) return false;
  }
  return i == s.size();
}

bool isLogOp(llvm::StringRef h) {
  return h == "forall" || h == "exists" || h == "and" || h == "or" || h == "xor" || h == "not" || h == "=>" || h == "<=>";
}
bool isQuantifier(llvm::StringRef h) { return h == "forall" || h == "exists"; }
bool isInequality(llvm::StringRef h) {
  return h == "greaterThan" || h == "greaterThanOrEqualTo" || h == "lessThan" || h == "lessThanOrEqualTo";
}

class Tptp {
public:
  explicit Tptp(TheoryOp theory) : theory(theory) {}
  LogicalResult write(raw_ostream &os);

private:
  TheoryOp theory;
  std::deque<Node> pool;
  llvm::DenseMap<Value, const Node *> seen;

  // ---- the cache
  std::map<std::string, std::vector<std::string>> subclassParents, subclassChildren, subrelationParents, subrelationChildren,
      instanceClasses, instancesOf;
  std::set<std::pair<std::string, std::string>> asserted[3]; // (subclass), (subrelation), (instance) facts as stated
  std::map<std::string, std::map<std::string, std::vector<std::string>>> binary; // rel -> a -> [b] for each (rel a b) of atoms
  std::map<std::string, std::map<std::string, std::set<std::string>>> closureMemo; // rel -> a -> what (rel a _) reaches
  std::set<std::string> transRels;
  std::set<std::pair<std::string, std::string>> domainClass; // (domain R _ C): R, C
  std::map<std::string, std::set<std::string>> supersMemo;
  std::set<std::string> relations, functions, predicates;
  std::map<std::string, std::vector<std::string>> sigs;
  std::map<std::string, int> valences;
  bool cacheBuilt = false;
  std::map<std::string, std::set<std::string>> instMemo;
  std::set<std::string> doublesWritten; // the double-predicate-variable axioms whose instances are written

  const Node *mk(Node::Kind k, std::string name, std::vector<const Node *> kids = {}) {
    pool.push_back(Node{k, std::move(name), std::move(kids)});
    return &pool.back();
  }
  const Node *atom(llvm::StringRef s) { return mk(Node::Atom, s.str()); }
  const Node *list(std::vector<const Node *> kids) { return mk(Node::List, "", std::move(kids)); }

  const Node *node(Value v);
  void buildCache(llvm::ArrayRef<const Node *> forms);
  const std::set<std::string> &supers(const std::string &c);
  const std::set<std::string> &reach(const std::string &rel, const std::string &a);
  bool instTransRel(const std::string &rel);
  std::set<std::string> instanceOf(const std::string &i);
  bool isInstanceOf(const std::string &i, const std::string &c) { return instanceOf(i).count(c); }
  bool isSubclass(const std::string &c, const std::string &p) { return c == p || supers(c).count(p); }
  bool isFunction(const std::string &f) { return functions.count(f); }
  int valence(const std::string &rel);
  void copyNewPred(const std::string &renamed, const std::string &old, int arity);
  std::set<std::string> subrelationsBelow(const std::string &r);
  std::string findType(int arg, const std::string &pred);
  std::string getRange(const std::string &f);

  // ---- preprocessing
  static llvm::StringRef head(const Node *n) {
    if (n->kind != Node::List || n->kids.empty()) return {};
    const Node *h = n->kids[0];
    return (h->kind == Node::Atom || h->kind == Node::Var) ? llvm::StringRef(h->name) : llvm::StringRef();
  }
  static size_t nargs(const Node *n) { return n->kids.empty() ? 0 : n->kids.size() - 1; }
  static const Node *arg(const Node *n, size_t i) { return n->kids[i + 1]; }
  bool higherOrder(const Node *e);
  static bool hasPredVar(const Node *e);
  static bool hasRowVar(const Node *e);
  const Node *renameVariableArity(const Node *e);
  bool simpleClause(const Node *e, size_t start);
  void gatherPredVars(const Node *e, size_t start, std::set<std::string> &vars, std::map<std::string, int> &arity);
  TypeMap allTypeRestrictions(const Node *e);
  const Node *substitute(const Node *e, const std::string &var, const Node *by);
  std::optional<std::vector<const Node *>> instantiatePredVars(const Node *f, const std::string &key);
  std::vector<const Node *> handleDouble(bool disjoint);
  void rowStructs(const Node *e, bool varList, std::map<std::string, std::vector<std::pair<std::string, int>>> &out);
  std::map<std::string, int> findArities(const Node *f);
  const Node *splice(const Node *e, const std::string &row, const std::vector<const Node *> &vars, bool varList);
  std::vector<const Node *> expandRowVars(const Node *f);
  void merge(TypeMap &into, const TypeMap &from);
  TypeMap variableTypes(const Node *e);
  void explicitTypes(const Node *e, bool negative, TypeMap &types, TypeMap &classes);
  TypeMap typeRestrictions(const Node *e);
  const Node *guard(const std::string &var, const std::string &type);
  const Node *wrapAnd(std::vector<const Node *> gs) {
    if (gs.size() == 1) return gs[0];
    gs.insert(gs.begin(), atom("and"));
    return list(std::move(gs));
  }
  const Node *restrictRecurse(const Node *e);
  const Node *restrict(const Node *e, const TypeMap &varmap);
  static void freeVars(const Node *e, std::vector<std::string> &bound, std::vector<std::string> &free);

  // ---- rendering
  std::string word(const Node *e, bool isHead);
  std::string render(const Node *e);
  std::string translate(const Node *e, bool query);
  static void print(const Node *e, std::string &out);
};

const Node *Tptp::node(Value v) {
  if (auto it = seen.find(v); it != seen.end()) return it->second;
  const Node *n;
  if (auto a = v.getDefiningOp<AtomOp>()) {
    llvm::StringRef s = a.getName();
    Node::Kind k = s.starts_with("@") && s.size() > 1 ? Node::Row
                   : s.starts_with("\"")               ? Node::Str
                   : isNumeric(s)                      ? Node::Num
                                                       : Node::Atom;
    std::string text = s.str();
    if (k == Node::Str) { // SigmaKEE's reader makes each run of white space in a string one space
      std::string t;
      for (char c : text) {
        bool white = c == ' ' || c == '\n' || c == '\t' || c == '\r' || c == '\f';
        if (!white) t += c;
        else if (t.empty() || t.back() != ' ') t += ' ';
      }
      text = t;
    }
    n = mk(k, text);
  } else if (auto var = v.getDefiningOp<VarOp>()) {
    n = mk(Node::Var, var.getName().str());
  } else {
    auto l = v.getDefiningOp<ListOp>();
    std::vector<const Node *> kids;
    for (Value e : l.getElements()) kids.push_back(node(e));
    n = list(std::move(kids));
  }
  return seen[v] = n;
}

// ---- the cache ------------------------------------------------------------------------------------------------------

void Tptp::buildCache(llvm::ArrayRef<const Node *> forms) {
  std::map<std::string, std::map<int, std::string>> domains, domainSubs;
  std::map<std::string, std::string> ranges, rangeSubs;
  auto isAtom = [](const Node *n) { return n->kind == Node::Atom; };
  for (const Node *f : forms) {
    llvm::StringRef h = head(f);
    if (h.empty()) continue;
    if (nargs(f) == 2 && isAtom(arg(f, 0)) && isAtom(arg(f, 1))) {
      const std::string &a = arg(f, 0)->name, &b = arg(f, 1)->name;
      binary[h.str()][a].push_back(b);
      if (h == "subclass") subclassParents[a].push_back(b), subclassChildren[b].push_back(a), asserted[0].insert({a, b});
      else if (h == "subrelation") subrelationParents[a].push_back(b), subrelationChildren[b].push_back(a), asserted[1].insert({a, b});
      else if (h == "instance") instanceClasses[a].push_back(b), instancesOf[b].push_back(a), asserted[2].insert({a, b});
      else if (h == "range") ranges[a] = b;
      else if (h == "rangeSubclass") rangeSubs[a] = b;
    }
    if (nargs(f) == 3 && isAtom(arg(f, 0)) && arg(f, 1)->kind == Node::Num && isAtom(arg(f, 2)) &&
        (h == "domain" || h == "domainSubclass")) {
      int n = 0;
      if (llvm::StringRef(arg(f, 1)->name).getAsInteger(10, n) || n < 1 || n > 20) continue;
      (h == "domain" ? domains : domainSubs)[arg(f, 0)->name][n] = arg(f, 2)->name;
      if (h == "domain") domainClass.insert({arg(f, 0)->name, arg(f, 2)->name});
    }
  }
  // KBcache.buildRelationsSet: from Relation down subclass, instance and subrelation
  std::set<std::string> frontier{"Relation"}, visited;
  while (!frontier.empty()) {
    std::set<std::string> next;
    for (const std::string &r : frontier) {
      if (!visited.insert(r).second) continue;
      for (const std::string &c : subclassChildren[r]) next.insert(c);
      for (const std::string &i : instancesOf[r]) relations.insert(i), next.insert(i);
      for (const std::string &s : subrelationChildren[r]) relations.insert(s), next.insert(s);
    }
    frontier.swap(next);
  }
  // KBcache.buildTransitiveRelationsSet: from TransitiveRelation down subclass; its instances and subrelations
  for (std::set<std::string> rels{"TransitiveRelation"}, done; !rels.empty();) {
    std::set<std::string> next;
    for (const std::string &r : rels) {
      if (!done.insert(r).second) continue;
      for (const std::string &c : subclassChildren[r]) next.insert(c);
      for (const std::string &i : instancesOf[r]) transRels.insert(i);
      for (const std::string &s : subrelationChildren[r]) transRels.insert(s);
    }
    rels.swap(next);
  }
  // KBcache.collectDomains
  for (const std::string &rel : relations) {
    std::vector<std::string> a(21);
    int maxIndex = 0;
    for (auto &[n, c] : domains[rel]) a[n] = c, maxIndex = std::max(maxIndex, n);
    for (auto &[n, c] : domainSubs[rel]) a[n] = c + "+", maxIndex = std::max(maxIndex, n);
    if (ranges.count(rel)) a[0] = ranges[rel];
    if (rangeSubs.count(rel)) a[0] = rangeSubs[rel] + "+";
    for (int i = 1; i < maxIndex; i++) // fillArray: up to, not including, maxIndex
      if (a[i].empty()) a[i] = "Entity";
    a.resize(maxIndex + 1);
    sigs[rel] = a;
    valences[rel] = maxIndex;
  }
  // KBcache.inheritDomains: from each root of subrelation (an arg 2 that is no arg 1), children first in, first visited
  std::set<std::string> arg1s, arg2s;
  for (auto &[c, ps] : subrelationParents) {
    arg1s.insert(c);
    for (auto &p : ps) arg2s.insert(p);
  }
  for (const std::string &root : arg2s) {
    if (arg1s.count(root)) continue;
    std::deque<std::string> q{root};
    std::set<std::string> v{root};
    while (!q.empty()) {
      std::string t = q.front();
      q.pop_front();
      std::set<std::string> kids(subrelationChildren[t].begin(), subrelationChildren[t].end());
      for (const std::string &child : kids) {
        if (!valences.count(t) || !sigs.count(child) || !sigs.count(t)) continue;
        std::vector<std::string> &cd = sigs[child];
        const std::vector<std::string> &td = sigs[t];
        if (!valences.count(child) || valences[child] < valences[t]) {
          for (int i = valences.count(child) ? valences[child] + 1 : 0; i < valences[t] + 1; i++) // fillArrayList appends
            if (i > int(cd.size()) - 1 || cd[i].empty()) cd.push_back("Entity");
          valences[child] = valences[t];
        }
        for (int i = 1; i <= valences[t]; i++) {
          if (i >= int(cd.size()) || i >= int(td.size())) break;
          if (!domainClass.count({child, cd[i]})) cd[i] = td[i];
        }
        if (v.insert(child).second) q.push_front(child);
      }
    }
  }
  // KBcache.buildTransInstOf, correctValences, buildFunctionsSet: once the signatures are known
  for (const std::string &r : relations)
    (isInstanceOf(r, "Function") ? functions : predicates).insert(r);
  cacheBuilt = true;
}

const std::set<std::string> &Tptp::supers(const std::string &c) {
  if (auto it = supersMemo.find(c); it != supersMemo.end()) return it->second;
  std::set<std::string> &out = supersMemo[c]; // a cycle reads what is there so far
  std::vector<std::string> todo(subclassParents[c].begin(), subclassParents[c].end());
  while (!todo.empty()) {
    std::string p = todo.back();
    todo.pop_back();
    if (p == c || !out.insert(p).second) continue;
    for (const std::string &g : subclassParents[p]) todo.push_back(g);
  }
  return out;
}

const std::set<std::string> &Tptp::reach(const std::string &rel, const std::string &a) {
  auto &memo = closureMemo[rel];
  if (auto it = memo.find(a); it != memo.end()) return it->second;
  std::set<std::string> &out = memo[a];
  auto &edges = binary[rel];
  std::vector<std::string> todo;
  if (auto it = edges.find(a); it != edges.end()) todo.assign(it->second.begin(), it->second.end());
  while (!todo.empty()) {
    std::string b = todo.back();
    todo.pop_back();
    if (b == a || !out.insert(b).second) continue;
    if (auto it = edges.find(b); it != edges.end()) todo.insert(todo.end(), it->second.begin(), it->second.end());
  }
  return out;
}

bool Tptp::instTransRel(const std::string &rel) { // KBcache.buildInstTransRels: no argument is a class
  if (!transRels.count(rel)) return false;
  auto it = sigs.find(rel);
  if (it == sigs.end()) return false;
  return llvm::none_of(it->second, [](const std::string &t) { return llvm::StringRef(t).ends_with("+") || t == "Class"; });
}

std::set<std::string> Tptp::instanceOf(const std::string &i) { // KBcache.buildTransInstOf
  if (cacheBuilt)
    if (auto it = instMemo.find(i); it != instMemo.end()) return it->second;
  std::set<std::string> out;
  auto add = [&](const std::string &c) {
    out.insert(c);
    const std::set<std::string> &s = supers(c);
    out.insert(s.begin(), s.end());
  };
  if (auto it = instanceClasses.find(i); it != instanceClasses.end())
    for (const std::string &c : it->second) add(c);
  if (!sigs.empty()) // once the signatures are known: up subrelation and subAttribute, to what is above
    for (const char *rel : {"subrelation", "subAttribute"})
      if (instTransRel(rel))
        for (const std::string &p : reach(rel, i))
          if (auto it = instanceClasses.find(p); it != instanceClasses.end())
            for (const std::string &c : it->second) add(c);
  if (cacheBuilt) instMemo[i] = out;
  return out;
}

int Tptp::valence(const std::string &rel) { // KBcache.getArity after correctValences: -1 for a variable arity
  if (isInstanceOf(rel, "VariableArityRelation")) return -1;
  auto it = valences.find(rel);
  return it == valences.end() ? 0 : it->second;
}

void Tptp::copyNewPred(const std::string &renamed, const std::string &old, int arity) { // copyNewPredFromVariableArity
  if (sigs.count(renamed)) return;
  auto it = sigs.find(old);
  std::vector<std::string> sig;
  std::string last = "Entity";
  if (it == sigs.end() || it->second.empty()) {
    sig.push_back(isFunction(old) ? "Entity" : "");
  } else {
    sig = it->second;
    last = sig.back().empty() ? "Entity" : sig.back();
  }
  while (int(sig.size()) <= arity) sig.push_back(last);
  sigs[renamed] = sig;
  valences[renamed] = arity;
  (isFunction(old) ? functions : predicates).insert(renamed);
  instanceClasses[renamed] = instanceClasses[old];
  instMemo.erase(renamed);
}

std::set<std::string> Tptp::subrelationsBelow(const std::string &r) { // KBcache.getChildRelations: transitive
  std::set<std::string> out;
  for (auto &[c, ps] : subrelationParents) {
    (void)ps;
    if (c != r && reach("subrelation", c).count(r)) out.insert(c);
  }
  return out;
}

std::string Tptp::findType(int arg, const std::string &pred) {
  auto it = sigs.find(pred);
  if (it == sigs.end() || arg >= int(it->second.size())) return "";
  return it->second[arg];
}

std::string Tptp::getRange(const std::string &f) {
  if (!isFunction(f)) return "";
  auto it = sigs.find(f);
  return it == sigs.end() || it->second.empty() ? "" : it->second[0];
}

// ---- preprocessing --------------------------------------------------------------------------------------------------

bool Tptp::higherOrder(const Node *e) { // Formula.isHigherOrderExpr
  llvm::StringRef h = head(e);
  if (h.empty()) return false;
  if (!h.starts_with("?")) {
    auto it = sigs.find(h.str());
    if (it != sigs.end() && llvm::is_contained(it->second, "Formula")) return true;
  }
  bool logop = isLogOp(h);
  for (size_t i = 0; i < nargs(e); i++) {
    const Node *a = arg(e, i);
    if (a->kind != Node::List) continue;
    llvm::StringRef ah = head(a);
    if (!ah.empty() && !isFunction(ah.str())) {
      if (!logop) return true;
      if (higherOrder(a)) return true;
    } else if (higherOrder(a)) {
      return true;
    }
  }
  return false;
}

bool Tptp::hasPredVar(const Node *e) {
  if (e->kind != Node::List) return false;
  if (isQuantifier(head(e)) && nargs(e) == 2) return hasPredVar(arg(e, 1)); // its variable list is no application
  if (!e->kids.empty() && e->kids[0]->kind == Node::Var) return true;
  return llvm::any_of(e->kids, hasPredVar);
}

bool Tptp::hasRowVar(const Node *e) {
  if (e->kind == Node::Row) return true;
  return e->kind == Node::List && llvm::any_of(e->kids, hasRowVar);
}

// ---- predicate variables (com.articulate.sigma.PredVarInst) ---------------------------------------------------------

bool Tptp::simpleClause(const Node *e, size_t start) { // Formula.isSimpleClause of the list e->kids[start..]
  if (e->kind != Node::List || start >= e->kids.size() || e->kids[start]->kind == Node::List) return false;
  for (size_t i = start + 1; i < e->kids.size(); i++) {
    const Node *a = e->kids[i];
    if (a->kind != Node::List) continue;
    llvm::StringRef h = head(a);
    if (h.empty() || !isFunction(h.str())) return false;
  }
  return true;
}

// PredVarInst.gatherPredVarRecurse: car and cdr, as SigmaKEE walks the formula's text
void Tptp::gatherPredVars(const Node *e, size_t start, std::set<std::string> &vars, std::map<std::string, int> &arity) {
  if (e->kind != Node::List || start >= e->kids.size()) return;
  if (simpleClause(e, start)) {
    const Node *h = e->kids[start];
    if (h->kind == Node::Var && e->kids.size() - start > 1) {
      vars.insert(h->name);
      bool row = std::any_of(e->kids.begin() + start + 1, e->kids.end(), [](const Node *k) { return k->kind == Node::Row; });
      arity[h->name] = row ? 0 : int(e->kids.size() - start - 1); // 0: any arity
    }
    return;
  }
  const Node *car = e->kids[start];
  if (car->kind == Node::Atom && isQuantifier(car->name)) return gatherPredVars(e, start + 2, vars, arity); // cddr
  gatherPredVars(car, 0, vars, arity);
  gatherPredVars(e, start + 1, vars, arity);
}

TypeMap Tptp::allTypeRestrictions(const Node *e) { // FormulaPreprocessor.findAllTypeRestrictions
  TypeMap out = variableTypes(e);
  const Node *ante = e;
  llvm::StringRef h = head(e);
  if ((h == "=>" || h == "<=>") && nargs(e) >= 2) ante = arg(e, 0);
  TypeMap types, classes;
  explicitTypes(ante, false, types, classes);
  for (auto &[v, ts] : types) out[v].insert(ts.begin(), ts.end());
  return out;
}

const Node *Tptp::substitute(const Node *e, const std::string &var, const Node *by) { // parsing.PredVarInst.substituteVar
  if (e->kind == Node::Var) return e->name == var ? by : e;
  if (e->kind != Node::List) return e;
  std::vector<const Node *> kids;
  bool changed = false;
  for (const Node *k : e->kids) {
    kids.push_back(substitute(k, var, by));
    changed |= kids.back() != k;
  }
  return changed ? list(std::move(kids)) : e;
}

static const char *doubleAxiom = // PredVarInst.DOUBLE_PREDICATE_AXIOM
    "(=> (and (instance ?REL1 Predicate) (instance ?REL2 Predicate) (disjointRelation ?REL1 ?REL2) (?REL1 @ROW2)) "
    "(not (?REL2 @ROW2)))";
static const char *subrelationAxiom = // PredVarInst.handleDouble2's
    "(=> (and (subrelation ?REL1 ?REL2) (instance ?REL1 Predicate) (instance ?REL2 Predicate) (?REL1 @ROW)) (?REL2 @ROW))";

// PredVarInst.handleDouble1 (disjoint) and handleDouble2: the two axioms with two predicate variables SigmaKEE
// instantiates, pair by pair of relations of one arity.  (SigmaKEE writes both sets under whichever double axiom a
// thread meets first; here each set is written under its own axiom.)
std::vector<const Node *> Tptp::handleDouble(bool disjoint) {
  std::set<std::pair<std::string, std::string>> pairs;
  if (disjoint) { // KBcache.buildDisjointRelationsMap
    for (auto &[a, bs] : binary["disjointRelation"])
      for (const std::string &b : bs) {
        std::set<std::string> c1 = subrelationsBelow(a), c2 = subrelationsBelow(b);
        c1.insert(a), c2.insert(b);
        for (const std::string &x : c1)
          for (const std::string &y : c2)
            if (x != y) pairs.insert({x, y});
      }
  } else {
    for (const std::string &r1 : relations) {
      if (isFunction(r1)) continue;
      for (const std::string &r2 : subrelationsBelow(r1)) pairs.insert({r2, r1});
    }
  }
  std::vector<const Node *> out;
  for (auto &[x, y] : pairs) {
    int ax = valence(x), ay = valence(y);
    if (ax != ay) continue;
    std::vector<const Node *> vars;
    for (int i = 1; i <= ax; i++) vars.push_back(mk(Node::Var, "?ROW" + std::to_string(i)));
    std::vector<const Node *> l{atom(x)}, r{atom(y)};
    l.insert(l.end(), vars.begin(), vars.end());
    r.insert(r.end(), vars.begin(), vars.end());
    const Node *rhs = list(std::move(r));
    if (disjoint) rhs = list({atom("not"), rhs});
    out.push_back(list({atom("=>"), list(std::move(l)), rhs}));
  }
  return out;
}

// PredVarInst.instantiatePredVars: each relation of the variable's arity that is an instance of each of its types, in
// its place.  nullopt: dropped (more than one predicate variable); empty: no instance.
std::optional<std::vector<const Node *>> Tptp::instantiatePredVars(const Node *f, const std::string &key) {
  std::set<std::string> vars;
  std::map<std::string, int> arity;
  gatherPredVars(f, 0, vars, arity);
  if (vars.size() > 1) {
    if (key == doubleAxiom) return handleDouble(true);
    if (key == subrelationAxiom) return handleDouble(false);
    return std::nullopt;
  }
  TypeMap all = allTypeRestrictions(f), varTypes;
  for (const std::string &v : vars)
    if (auto it = all.find(v); it != all.end()) varTypes[v] = it->second;
  // addExplicitTypes: a rule's antecedent's (instance ?V C) and (subclass ?V C), the latter replacing the former
  llvm::StringRef h = head(f);
  const Node *rule = f;
  while (isQuantifier(head(rule)) && nargs(rule) == 2 && arg(rule, 1)->kind == Node::List) rule = arg(rule, 1);
  llvm::StringRef rh = head(rule);
  if ((rh == "=>" || rh == "<=>") && nargs(f) >= 1) {
    TypeMap types, classes;
    explicitTypes(arg(f, 0), false, types, classes);
    for (auto &[v, c] : classes) types[v] = c;
    if (!types.empty()) {
      TypeMap result;
      for (auto &[v, ts] : types)
        if (auto it = varTypes.find(v); it != varTypes.end()) {
          std::set<std::string> hs = it->second;
          hs.insert(ts.begin(), ts.end());
          result[v] = hs;
        }
      varTypes = result;
    }
  }
  (void)h;
  static const std::set<std::string> skip{"equal", "greaterThan", "greaterThanOrEqualTo", "lessThan", "lessThanOrEqualTo",
                                          "AdditionFn", "SubtractionFn", "MultiplicationFn", "DivisionFn", "FloorFn",
                                          "RoundFn", "CeilingFn", "RemainderFn"};
  std::vector<const Node *> out;
  for (auto &[v, ts] : varTypes) {
    int a = arity.count(v) ? arity[v] : 0;
    std::set<std::string> rels = ts.count("Function") ? functions : predicates;
    for (const std::string &rel : rels) {
      if (skip.count(rel) || isLogOp(rel) || rel.find("__") != std::string::npos) continue;
      if (valence(rel) != a && a != 0) continue;
      if (llvm::all_of(ts, [&](const std::string &t) { return isInstanceOf(rel, t); }))
        out.push_back(substitute(f, v, atom(rel)));
    }
  }
  return out;
}

// ---- row variables (parsing.RowVar.expandRowVarExpr) ----------------------------------------------------------------

// Formula.initCachesFromExpr's RowStructs: for each row variable, the relation of each literal it is an argument of and
// the literal's number of arguments.  A quantifier's variable list has no head, so none.
void Tptp::rowStructs(const Node *e, bool varList, std::map<std::string, std::vector<std::pair<std::string, int>>> &out) {
  if (e->kind != Node::List || varList) return;
  llvm::StringRef h = head(e);
  for (size_t i = 0; i < nargs(e); i++)
    if (arg(e, i)->kind == Node::Row && !h.empty()) out[arg(e, i)->name].push_back({h.str(), int(nargs(e))});
  bool q = isQuantifier(h) && nargs(e) == 2;
  for (size_t i = 0; i < nargs(e); i++) rowStructs(arg(e, i), q && i == 0, out);
}

std::map<std::string, int> Tptp::findArities(const Node *f) { // RowVar.findArities: -1 variable, 0 a conflict
  std::map<std::string, std::vector<std::pair<std::string, int>>> rs;
  rowStructs(f, false, rs);
  std::map<std::string, int> arities;
  for (auto &[rv, structs] : rs) {
    std::vector<std::pair<std::string, int>> sorted = structs;
    std::stable_sort(sorted.begin(), sorted.end(), [](auto &a, auto &b) { return a.first < b.first; });
    for (auto &[pred, n] : sorted) {
      if (llvm::StringRef(pred).starts_with("?")) continue; // a variable predicate
      int predArity = valence(pred);
      int rva = predArity;
      if (n > 1) rva -= n - 1;
      if (predArity == -1) rva = -1;
      auto it = arities.find(rv);
      if (it == arities.end() || predArity != -1) {
        if (it != arities.end() && it->second > 0 && rva > 0 && it->second != rva) arities[rv] = 0;
        else if (it == arities.end() || it->second != 0) arities[rv] = rva;
      }
    }
  }
  for (auto &[rv, a] : arities) { // a numeric and a non-numeric type at one position: a conflict
    if (a <= 0) continue;
    std::map<int, std::set<std::string>> posTypes;
    for (auto &[pred, n] : rs[rv]) {
      auto sit = sigs.find(pred);
      if (sit == sigs.end()) continue;
      int pArity = valence(pred);
      if (pArity <= 0) continue;
      for (int abs = n; abs <= pArity; abs++)
        if (abs < int(sit->second.size()) && !sit->second[abs].empty()) posTypes[abs - (n - 1)].insert(sit->second[abs]);
    }
    for (auto &[pos, ts] : posTypes) {
      (void)pos;
      bool num = false, non = false;
      for (const std::string &t : ts) (isSubclass(t, "RealNumber") ? num : non) = true;
      if (num && non) {
        a = 0;
        break;
      }
    }
  }
  return arities;
}

const Node *Tptp::splice(const Node *e, const std::string &row, const std::vector<const Node *> &vars, bool varList) {
  if (e->kind != Node::List) return e;
  std::vector<const Node *> kids;
  size_t first = varList ? 0 : 1; // a variable list has no head
  if (!varList && !e->kids.empty()) kids.push_back(e->kids[0]);
  bool q = !varList && isQuantifier(head(e)) && nargs(e) == 2, spliced = false;
  for (size_t i = first; i < e->kids.size(); i++) {
    const Node *a = e->kids[i];
    if (a->kind == Node::Row && a->name == row) {
      kids.insert(kids.end(), vars.begin(), vars.end());
      spliced = true;
    } else {
      kids.push_back(splice(a, row, vars, q && i == 1));
    }
  }
  if (spliced && !varList && !kids.empty() && kids[0]->kind == Node::Atom && valence(kids[0]->name) == -1) {
    const std::string &pred = kids[0]->name;
    int total = int(kids.size()) - 1;
    std::string renamed = pred + "__" + std::to_string(total) + (llvm::StringRef(pred).ends_with("Fn") ? "Fn" : "");
    copyNewPred(renamed, pred, total);
    kids[0] = atom(renamed);
  }
  return list(std::move(kids));
}

std::vector<const Node *> Tptp::expandRowVars(const Node *f) { // empty: f as it is
  std::vector<const Node *> working{f};
  for (auto &[rv, a] : findArities(f)) {
    if (a == 0) return {};
    std::string base = rv.substr(1);
    auto vars = [&](int n) {
      std::vector<const Node *> v;
      for (int i = 1; i <= n; i++) v.push_back(mk(Node::Var, "?" + base + std::to_string(i)));
      return v;
    };
    std::vector<const Node *> next;
    for (int n = a == -1 ? 1 : a; n <= (a == -1 ? 7 : a); n++) {
      std::vector<const Node *> vs = vars(n);
      for (const Node *e : working) next.push_back(splice(e, rv, vs, false));
    }
    if (a < -1) // a literal with more arguments than its relation: the row variable goes
      for (const Node *e : working) next.push_back(splice(e, rv, {}, false));
    working = next;
  }
  return working;
}

const Node *Tptp::renameVariableArity(const Node *e) { // FormulaPreprocessor.renameVariableArityInExpr
  if (e->kind != Node::List) return e;
  std::vector<const Node *> kids;
  for (size_t i = 0; i < e->kids.size(); i++) kids.push_back(i ? renameVariableArity(e->kids[i]) : e->kids[i]);
  const Node *h = kids.empty() ? nullptr : kids[0];
  if (h && h->kind == Node::Atom) {
    std::set<std::string> io = instanceOf(h->name);
    if (io.count("VariableArityRelation")) {
      int arity = int(kids.size()) - 1;
      std::string suffix = "__" + std::to_string(arity) + (io.count("Function") ? "Fn" : "");
      if (!llvm::StringRef(h->name).ends_with(suffix)) {
        std::string renamed = h->name + suffix;
        copyNewPred(renamed, h->name, arity);
        kids[0] = atom(renamed);
      }
    }
  }
  return list(std::move(kids));
}

void Tptp::merge(TypeMap &into, const TypeMap &from) { // KButilities.mergeToMap: the union, less the supertypes
  for (auto &[var, types] : from) {
    std::set<std::string> &v = into[var];
    v.insert(types.begin(), types.end());
    std::set<std::string> drop;
    for (const std::string &a : v)
      for (const std::string &b : v)
        if (a != b && isSubclass(a, b)) drop.insert(b);
    for (const std::string &d : drop) v.erase(d);
  }
}

TypeMap Tptp::variableTypes(const Node *e) { // FormulaPreprocessor.computeVariableTypesRecurseExpr
  TypeMap result;
  llvm::StringRef h = head(e);
  if (h.empty()) return result;
  if (isLogOp(h)) {
    for (size_t i = isQuantifier(h) ? 1 : 0; i < nargs(e); i++) merge(result, variableTypes(arg(e, i)));
    return result;
  }
  if (h.starts_with("?")) return result;
  std::string pred = h.str();
  if (pred == "equal" && nargs(e) >= 2) {
    for (int k = 0; k < 2; k++) {
      const Node *v = arg(e, k), *f = arg(e, 1 - k);
      if (v->kind == Node::Var && f->kind == Node::List) {
        llvm::StringRef fh = head(f);
        if (!fh.empty() && isFunction(fh.str())) {
          std::string t = getRange(fh.str());
          result[v->name].insert(t.empty() ? "Entity" : t);
        }
      }
    }
  }
  for (size_t i = 0; i < nargs(e); i++) {
    const Node *a = arg(e, i);
    if (a->kind == Node::Var) {
      std::string cl = findType(int(i) + 1, pred);
      if (!cl.empty()) result[a->name].insert(cl);
    } else if (a->kind == Node::List) {
      llvm::StringRef ah = head(a);
      if (!ah.empty() && !ah.starts_with("?") && isFunction(ah.str())) merge(result, variableTypes(a));
    }
  }
  return result;
}

void Tptp::explicitTypes(const Node *e, bool negative, TypeMap &types, TypeMap &classes) {
  llvm::StringRef h = head(e);
  if (h.empty()) return;
  if (isLogOp(h)) {
    if (isQuantifier(h)) {
      if (nargs(e) == 2) explicitTypes(arg(e, 1), false, types, classes);
    } else {
      for (size_t i = 0; i < nargs(e); i++) explicitTypes(arg(e, i), h == "not", types, classes);
    }
    return;
  }
  if (negative) return;
  if ((h == "instance" || h == "subclass") && nargs(e) == 2 && arg(e, 0)->kind == Node::Var && arg(e, 1)->kind == Node::Atom) {
    if (h == "instance") types[arg(e, 0)->name].insert(arg(e, 1)->name);
    else classes[arg(e, 0)->name].insert(arg(e, 1)->name + "+");
    return;
  }
  for (size_t i = 0; i < nargs(e); i++) explicitTypes(arg(e, i), false, types, classes);
}

TypeMap Tptp::typeRestrictions(const Node *e) { // FormulaPreprocessor.findTypeRestrictionsExpr
  TypeMap domain = variableTypes(e);
  // the explicit types of the antecedent of (=> A B) or (<=> A B), else of the whole: instance types only
  // (findExplicitTypesClassesInAntecedentExpr returns the instance map, not the subclass one)
  const Node *ante = e;
  llvm::StringRef h = head(e);
  if ((h == "=>" || h == "<=>") && nargs(e) >= 2) ante = arg(e, 0);
  TypeMap types, classes;
  explicitTypes(ante, false, types, classes);
  TypeMap out;
  for (auto &[var, ts] : domain) {
    if (!types.count(var)) {
      out[var] = ts;
      continue;
    }
    std::set<std::string> keep;
    for (const std::string &t : ts)
      if (llvm::StringRef(t).ends_with("+")) keep.insert(t);
    for (const std::string &t : types[var])
      if (llvm::StringRef(t).ends_with("+")) keep.insert(t);
    out[var] = keep;
  }
  return out;
}

const Node *Tptp::guard(const std::string &var, const std::string &type) {
  if (type.empty()) return nullptr;
  if (llvm::StringRef(type).ends_with("+")) {
    std::string t = type.substr(0, type.size() - 1);
    if (t == "Entity") return nullptr;
    return list({atom("subclass"), mk(Node::Var, var), atom(t)});
  }
  if (type == "Entity" || type == "World" || type == "ObjectiveNorm") return nullptr;
  return list({atom("instance"), mk(Node::Var, var), atom(type)});
}

const Node *Tptp::restrictRecurse(const Node *e) { // FormulaPreprocessor.addTypeRestrictionsRecurseExpr
  llvm::StringRef h = head(e);
  if (h.empty() || (!isLogOp(h) && h != "equal")) return e;
  if (isQuantifier(h)) {
    if (nargs(e) != 2) return e;
    const Node *vars = arg(e, 0), *body = arg(e, 1);
    TypeMap sub = typeRestrictions(e);
    std::vector<const Node *> guards;
    if (vars->kind == Node::List)
      for (const Node *v : vars->kids) {
        if (v->kind != Node::Var && v->kind != Node::Row) continue;
        auto it = sub.find(v->name);
        if (it == sub.end()) continue;
        for (const std::string &t : it->second)
          if (const Node *g = guard(v->name, t)) guards.push_back(g);
      }
    const Node *nb = restrictRecurse(body);
    if (guards.empty()) return nb == body ? e : list({e->kids[0], vars, nb});
    const Node *gb;
    if (h == "exists") {
      guards.push_back(nb);
      gb = wrapAnd(guards);
    } else {
      gb = list({atom("=>"), wrapAnd(guards), nb});
    }
    return list({e->kids[0], vars, gb});
  }
  bool changed = false;
  std::vector<const Node *> kids{e->kids[0]};
  for (size_t i = 0; i < nargs(e); i++) {
    const Node *n = restrictRecurse(arg(e, i));
    changed |= n != arg(e, i);
    kids.push_back(n);
  }
  return changed ? list(std::move(kids)) : e;
}

const Node *Tptp::restrict(const Node *e, const TypeMap &varmap) { // FormulaPreprocessor.addTypeRestrictionsExpr
  std::vector<std::string> bound, free;
  freeVars(e, bound, free);
  std::set<std::string> sorted(free.begin(), free.end());
  std::vector<const Node *> guards;
  for (const std::string &v : sorted) {
    auto it = varmap.find(v);
    if (it == varmap.end()) continue;
    for (const std::string &t : it->second)
      if (const Node *g = guard(v, t)) guards.push_back(g);
  }
  const Node *body = restrictRecurse(e);
  if (guards.empty()) return body;
  return list({atom("=>"), wrapAnd(guards), body});
}

void Tptp::freeVars(const Node *e, std::vector<std::string> &bound, std::vector<std::string> &free) {
  if (e->kind == Node::Var || e->kind == Node::Row) {
    if (!llvm::is_contained(bound, e->name) && !llvm::is_contained(free, e->name)) free.push_back(e->name);
    return;
  }
  if (e->kind != Node::List) return;
  llvm::StringRef h = head(e);
  if (isQuantifier(h) && nargs(e) == 2) {
    std::vector<std::string> inner = bound;
    if (arg(e, 0)->kind == Node::List)
      for (const Node *v : arg(e, 0)->kids)
        if (v->kind == Node::Var || v->kind == Node::Row) inner.push_back(v->name);
    freeVars(arg(e, 1), inner, free);
    return;
  }
  for (const Node *k : e->kids) freeVars(k, bound, free);
}

// ---- rendering ------------------------------------------------------------------------------------------------------

std::string Tptp::word(const Node *e, bool isHead) { // ExprToTPTP.translateExpr for all but a list
  auto underscore = [](std::string s) {
    for (char &c : s)
      if (c == '.' || c == '-') c = '_';
    return s;
  };
  switch (e->kind) {
  case Node::Var:
  case Node::Row: {
    std::string s = e->name.substr(1);
    for (char &c : s)
      if (c == '-') c = '_';
    return "V__" + s;
  }
  case Node::Num:
    return "n__" + underscore(e->name);
  case Node::Str: {
    std::string s;
    for (char c : e->name) {
      if (c == '\n' || c == '\t' || c == '\r' || c == '\f') s += ' ';
      else if (c != '\'') s += c;
    }
    return s;
  }
  case Node::Atom:
    break;
  case Node::List:
    return render(e);
  }
  const std::string &name = e->name;
  if (isInequality(name) && !isHead) return "s__" + name + "__m";
  if (name == "True") return isHead ? "$true" : "'$true__m'";
  if (name == "False") return isHead ? "$false" : "'$false__m'";
  std::string term = underscore(name);
  if (!isHead) {
    llvm::StringRef t(term);
    bool mention = !t.ends_with("__m") &&
                   (t.ends_with("Fn") || (!t.empty() && islower((unsigned char)t[0])) || relations.count(term));
    if (mention) term += "__m";
  }
  return "s__" + term;
}

std::string Tptp::render(const Node *e) { // ExprToTPTP.translateSExpr
  if (e->kind != Node::List) return word(e, false);
  llvm::StringRef h = head(e);
  auto join = [&](llvm::StringRef sep) {
    std::string s;
    for (size_t i = 0; i < nargs(e); i++) s += (i ? sep.str() : "") + render(arg(e, i));
    return s;
  };
  if (h == "not" && nargs(e) == 1) return "~(" + render(arg(e, 0)) + ")";
  if ((h == "and" || h == "or" || h == "xor") && nargs(e) >= 2)
    return "(" + join(h == "and" ? " & " : h == "or" ? " | " : " <~> ") + ")";
  if (h == "=>" && nargs(e) == 2) return "(" + render(arg(e, 0)) + " => " + render(arg(e, 1)) + ")";
  if (h == "<=>" && nargs(e) == 2) {
    std::string l = render(arg(e, 0)), r = render(arg(e, 1));
    return "((" + l + " => " + r + ") & (" + r + " => " + l + "))";
  }
  if (h == "equal" && nargs(e) == 2) return "(" + render(arg(e, 0)) + " = " + render(arg(e, 1)) + ")";
  if (isQuantifier(h) && nargs(e) == 2) {
    std::string vars;
    if (arg(e, 0)->kind == Node::List)
      for (const Node *v : arg(e, 0)->kids)
        if (v->kind == Node::Var || v->kind == Node::Row) vars += (vars.empty() ? "" : ",") + word(v, false);
    if (vars.empty()) return render(arg(e, 1));
    return std::string("(") + (h == "forall" ? "! " : "? ") + "[" + vars + "] : (" + render(arg(e, 1)) + "))";
  }
  if (e->kids.empty()) return "()";
  std::string s = word(e->kids[0], true);
  if (nargs(e) == 0) return s + "()";
  s += "(";
  for (size_t i = 0; i < nargs(e); i++) s += (i ? "," : "") + word(arg(e, i), false);
  return s + ")";
}

std::string Tptp::translate(const Node *e, bool query) { // ExprToTPTP.translate
  std::string body = render(e);
  std::vector<std::string> bound, free;
  freeVars(e, bound, free);
  if (free.empty()) return body;
  std::string vars;
  for (const std::string &v : free) {
    Node n{Node::Var, v, {}};
    vars += (vars.empty() ? "" : ",") + word(&n, false);
  }
  return std::string("( ") + (query ? "? [" : "! [") + vars + "] : (" + body + " ) )";
}

void Tptp::print(const Node *e, std::string &out) {
  if (e->kind != Node::List) {
    out += e->name;
    return;
  }
  out += '(';
  for (size_t i = 0; i < e->kids.size(); i++) {
    if (i) out += ' ';
    print(e->kids[i], out);
  }
  out += ')';
}

LogicalResult Tptp::write(raw_ostream &os) {
  std::vector<const Node *> forms;
  for (Operation &op : theory.getBody().front()) {
    if (auto f = dyn_cast<FactOp>(op)) forms.push_back(node(f.getTerm()));
    else if (auto r = dyn_cast<RuleOp>(op))
      forms.push_back(list({atom("=>"), node(r.getAntecedent()), node(r.getConsequent())}));
  }
  buildCache(forms);
  static const std::set<std::string> excluded{"documentation", "domain", "format", "termFormat", "externalImage",
                                              "relatedExternalConcept", "relatedInternalConcept", "formerName",
                                              "abbreviation", "conventionalShortName", "conventionalLongName"};
  static const std::set<std::string> testForms{"note", "category", "time", "answer"};
  os << "% the theory " << theory.getSymName() << " as TPTP FOF, as SigmaKEE translates it (mlnix-kif --tptp)\n";
  unsigned n = 0, queries = 0;
  std::map<std::string, unsigned> skipped;
  // FormulaPreprocessor.preProcessExpr: the predicate variables instantiated, then the row variables expanded, then
  // each variable-arity relation renamed and the variables' types made guards
  auto axiom = [&](const Node *f) {
    const Node *renamed = renameVariableArity(f);
    const Node *typed = restrict(renamed, typeRestrictions(renamed));
    os << "fof(kb_" << ++n << ",axiom,(" << translate(typed, false) << ")).\n";
  };
  auto emit = [&](const std::string &key, const Node *f, bool query) {
    os << "% f: " << key << "\n";
    if (query) {
      os << "fof(query_" << queries++ << ",conjecture,(" << translate(renameVariableArity(f), true) << ")).\n";
      return;
    }
    axiom(f);
  };
  for (const Node *f : forms) {
    std::string key;
    print(f, key);
    llvm::StringRef h = head(f);
    std::string why;
    if (testForms.count(h.str())) continue;
    bool query = h == "query" && nargs(f) == 1;
    const Node *g = query ? arg(f, 0) : f; // a query asks its formula
    if (excluded.count(h.str())) why = "excluded";
    else if (higherOrder(g)) why = "higher order";
    else if (query && (hasPredVar(g) || hasRowVar(g))) why = "a query with a predicate or row variable";
    std::vector<const Node *> stage{f};
    if (why.empty() && !query && hasPredVar(f)) {
      std::optional<std::vector<const Node *>> inst = instantiatePredVars(f, key);
      if (!inst) why = "more than one predicate variable";
      else if (inst->empty()) why = "no instance of its predicate variable";
      else stage = *inst;
    }
    if (query && why.empty()) {
      emit(key, g, true);
      continue;
    }
    if (!why.empty()) {
      os << "% f: " << key << "\n% not written: " << why << "\n";
      skipped[why]++;
      continue;
    }
    std::map<std::string, const Node *> expanded; // by text, as SigmaKEE's TreeSet by toKifString
    for (const Node *x : stage) {
      std::vector<const Node *> e;
      if (hasRowVar(x)) e = expandRowVars(x);
      if (e.empty()) e.push_back(x);
      for (const Node *y : e) {
        std::string t;
        print(y, t);
        expanded.emplace(t, y);
      }
    }
    os << "% f: " << key << "\n";
    for (auto &[t, y] : expanded) {
      (void)t;
      axiom(y);
    }
  }

  // SUMO_Cache.kif: each transitive relation's closure, less what is asserted
  for (const std::string &rel : transRels) {
    if (excluded.count(rel)) continue;
    auto bit = binary.find(rel);
    if (bit == binary.end()) continue;
    std::set<std::pair<std::string, std::string>> stated;
    for (auto &[a, bs] : bit->second)
      for (const std::string &b : bs) stated.insert({a, b});
    std::vector<std::string> from;
    for (auto &[a, bs] : bit->second) from.push_back(a);
    for (const std::string &c : from)
      for (const std::string &p : reach(rel, c)) {
        if (stated.count({c, p})) continue;
        Node a{Node::Atom, rel, {}}, x{Node::Atom, c, {}}, y{Node::Atom, p, {}};
        Node l{Node::List, "", {&a, &x, &y}};
        emit("(" + rel + " " + c + " " + p + ")", &l, false);
      }
  }
  std::set<std::string> insts; // what has classes: an instance, or what is below one by subrelation or subAttribute
  for (auto &[i, cs] : instanceClasses) insts.insert(i);
  for (const char *rel : {"subrelation", "subAttribute"})
    for (auto &[a, bs] : binary[rel]) insts.insert(a);
  for (const std::string &i : insts) {
    if (llvm::StringRef(i).contains("__")) continue; // a renamed variable-arity relation
    for (const std::string &c : instanceOf(i)) {
      if (asserted[2].count({i, c})) continue;
      Node a{Node::Atom, "instance", {}}, x{Node::Atom, i, {}}, y{Node::Atom, c, {}};
      Node l{Node::List, "", {&a, &x, &y}};
      emit("(instance " + i + " " + c + ")", &l, false);
    }
  }
  os << "% " << n << " axioms, " << queries << " conjectures; not written:";
  for (auto &[why, k] : skipped) os << " " << k << " " << why << ";";
  os << "\n";
  return success();
}

} // namespace

LogicalResult mlir::kif::exportTptp(TheoryOp theory, raw_ostream &os) { return Tptp(theory).write(os); }
