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

#include "Composite/Folds.h"
#include "Composite/Table.h"
#include "Composite/Text.h"
#include "Composite/Vocab.h"
#include "llvm/Support/raw_ostream.h"

using namespace mlir;
using namespace mlir::kif;
using composite::anyOf;
using composite::cat;
using composite::Chars;
using composite::chars;
using composite::Join;
using composite::mv;
using composite::MutableSeries;
using composite::Text;

namespace {

/// Bytes to the stream.  (A Text or a window given to `<<` is tried against each of raw_ostream's overloads, some incomplete here.)
raw_ostream &out(raw_ostream &os, Chars c) { return os.write(c.data(), c.size()); }

/// A name is its place in `names`: equal names are one symbol, and symbol 0 is "", no name.
using Sym = uint32_t;
using Syms = MutableSeries<Sym>;
struct Names {
  composite::TextTable<uint32_t> rows;
  composite::Bump bytes;
  Names() { (*this)(chars("", 0)); }
  Sym operator()(Chars s) {
    if (const uint32_t *v = rows.find(s.data(), s.size())) return *v;
    return *rows.set(s.data(), s.size(), rows.size(), [&] { return bytes.copy(s.data(), s.size()); });
  }
  Sym find(Chars s) const { const uint32_t *v = rows.find(s.data(), s.size()); return v ? *v : 0; } // 0: not a name yet
} names;
Chars nm(Sym s) { return chars(names.rows.row(s).p, names.rows.row(s).n); }
Sym sym(Chars s) { return names(s); }
Sym sym(const char *s) { return names(chars(s, uint32_t(__builtin_strlen(s)))); }
bool varName(Sym s) { return composite::startsWith(nm(s), chars("?", 1)); }
bool plusType(Sym s) { return composite::endsWith(nm(s), chars("+", 1)); } // "C+": the subclasses of C
template <uint32_t N> bool among(Chars s, const char *const (&xs)[N]) {
  return anyOf(composite::series(xs, N), [&](const char *x) { return s == x; });
}
bool contains(const Syms &xs, Sym s) { return anyOf(xs, [&](Sym x) { return x == s; }); }
Syms copy(const Syms &xs) { Syms o; for (Sym s : xs) o.append(s); return o; }
uint64_t pairKey(Sym a, Sym b) { return (uint64_t(a) + 1) << 32 | b; } // never 0, a WordTable's empty key
/// The byte order of two names (std::string's: unsigned bytes, then the shorter first).
bool before(Sym a, Sym b) { return a != b && composite::lessChars(nm(a), nm(b)); }

/// The cells in order, stably (std::stable_sort's): a bottom-up merge that takes the right run's cell only when it is strictly less.
template <class T, class Less> void stableSort(MutableSeries<T> &xs, Less less) {
  uint32_t n = xs.size();
  MutableSeries<T> tmp;
  tmp.resize(n);
  for (uint32_t w = 1; w < n; w *= 2) {
    for (uint32_t lo = 0; lo < n; lo += 2 * w) {
      uint32_t mid = composite::min(lo + w, n), hi = composite::min(lo + 2 * w, n), a = lo, b = mid, k = lo;
      while (a < mid || b < hi) tmp[k++] = b == hi || (a < mid && !less(xs[b], xs[a])) ? xs[a++] : xs[b++];
    }
    for (uint32_t i = 0; i < n; i++) xs[i] = tmp[i];
  }
}

/// Rows kept in the byte order of their names (what a std::set or std::map by std::string was): one sorted series.
template <class Row> struct Sorted {
  MutableSeries<Row> rows;
  static Sym key(const Row &r) {
    if constexpr (composite::same<Row, Sym>) return r;
    else return r.k;
  }
  uint32_t place(Sym s) const { // the first row not before s
    uint32_t lo = 0;
    for (uint32_t hi = rows.size(); lo < hi;) {
      uint32_t mid = (lo + hi) / 2;
      if (before(key(rows[mid]), s)) lo = mid + 1;
      else hi = mid;
    }
    return lo;
  }
  bool at(uint32_t i, Sym s) const { return i < rows.size() && key(rows[i]) == s; }
  bool count(Sym s) const { return at(place(s), s); }
  Row &settle(uint32_t i, Row r) { // r in at i, the rows from i moved up one
    rows.append(mv(r));
    for (uint32_t k = rows.size() - 1; k > i; k--) { Row t = mv(rows[k - 1]); rows[k - 1] = mv(rows[k]), rows[k] = mv(t); }
    return rows[i];
  }
  const Row *begin() const { return rows.begin(); }
  const Row *end() const { return rows.end(); }
  uint32_t size() const { return rows.size(); }
  bool empty() const { return rows.empty(); }
};
struct SymSet : Sorted<Sym> {
  /// The names of xs, each once.
  static SymSet of(Syms xs) {
    stableSort(xs, before);
    SymSet s;
    for (uint32_t i = 0; i < xs.size(); i++) if (!i || xs[i] != xs[i - 1]) s.rows.append(xs[i]);
    return s;
  }
  bool insert(Sym s) { uint32_t i = place(s); return !at(i, s) && (settle(i, s), true); }
  template <class S> void insertAll(const S &xs) { for (Sym s : xs) insert(s); }
  void erase(Sym s) {
    uint32_t i = place(s);
    if (!at(i, s)) return;
    for (; i + 1 < rows.size(); i++) rows[i] = rows[i + 1];
    rows.pop();
  }
  SymSet clone() const { return SymSet{{copy(rows)}}; }
};
template <class V> struct Keyed {
  Sym k;
  V v;
};
template <class V> struct SymMap : Sorted<Keyed<V>> {
  V *find(Sym s) { uint32_t i = this->place(s); return this->at(i, s) ? &this->rows[i].v : nullptr; }
  const V *find(Sym s) const { return const_cast<SymMap *>(this)->find(s); }
  V &operator[](Sym s) { uint32_t i = this->place(s); return (this->at(i, s) ? this->rows[i] : this->settle(i, {s, V()})).v; }
};
using TypeMap = SymMap<SymSet>;

/// A form as SigmaKEE's Expr sees it: an atom, a variable (?X), a row variable (@ROW), a number, a string, or a list.
struct Node;
using Kids = MutableSeries<const Node *>;
struct Node {
  enum Kind : uint8_t { Atom, Var, Row, Num, Str, List } kind;
  Sym name;  // the text of all but a list
  Kids kids; // a list's elements, its head first
};

/// What the cache knows of a name: KBcache's maps, by symbol.
struct Info {
  Syms subclassParents, subclassChildren, subrelationParents, subrelationChildren, instanceClasses, instancesOf;
  Syms sig;     // the signature: arg 0 the range, arg i the domain (0 none)
  Syms binKeys; // as a relation: the a of each (rel a b) of atoms, the first seen first
  composite::Maybe<SymSet> supers, inst; // memos
  Sym range = 0, rangeSub = 0;
  int valence = 0;
  bool hasSig = false, hasValence = false, hasClasses = false;
};

bool isNumeric(Chars s) { // -?[0-9]+(.[0-9]+)?
  auto digits = [&](uint32_t &i) { uint32_t d = i; while (i < s.size() && s[i] >= '0' && s[i] <= '9') i++; return i > d; };
  uint32_t i = s.size() && s[0] == '-';
  if (!digits(i)) return false;
  if (i < s.size() && s[i] == '.' && !digits(++i)) return false;
  return i == s.size();
}
bool lower(char c) { return c >= 'a' && c <= 'z'; }
bool isLogOp(Chars h) {
  return h == "forall" || h == "exists" || h == "and" || h == "or" || h == "xor" || h == "not" || h == "=>" || h == "<=>";
}
bool isQuantifier(Chars h) { return h == "forall" || h == "exists"; }
bool isInequality(Chars h) {
  return h == "greaterThan" || h == "greaterThanOrEqualTo" || h == "lessThan" || h == "lessThanOrEqualTo";
}
const char *const climbs[] = {"subrelation", "subAttribute"}; // what instanceOf climbs to the classes above
const char *const doubleAxiom = // PredVarInst.DOUBLE_PREDICATE_AXIOM
    "(=> (and (instance ?REL1 Predicate) (instance ?REL2 Predicate) (disjointRelation ?REL1 ?REL2) (?REL1 @ROW2)) "
    "(not (?REL2 @ROW2)))";
const char *const subrelationAxiom = // PredVarInst.handleDouble2's
    "(=> (and (subrelation ?REL1 ?REL2) (instance ?REL1 Predicate) (instance ?REL2 Predicate) (?REL1 @ROW)) (?REL2 @ROW))";

struct Tptp {
  explicit Tptp(TheoryOp theory) : theory(theory) {}
  TheoryOp theory;
  MutableSeries<Node, composite::Chunked<Node>> pool; // cells that never move
  composite::WordTable<const Node *> seen;            // by the Value's address

  // ---- the cache
  MutableSeries<Info, composite::Chunked<Info>> infos; // by symbol
  composite::WordTable<uint32_t> edgeAt, reachAt;      // (rel, a) -> its row of edgeLists, of reachSets
  MutableSeries<Syms, composite::Chunked<Syms>> edgeLists;     // [b] for each (rel a b) of atoms
  MutableSeries<SymSet, composite::Chunked<SymSet>> reachSets; // what (rel a _) reaches
  composite::WordTable<char> instAsserted, domainClass;        // (instance a b) as stated; (domain R _ C): R, C
  SymSet transRels, relations, functions, predicates, subrelated; // subrelated: what is a subrelation of something
  SymSet fresh; // instances() before the cache is built
  bool cacheBuilt = false, sigsKnown = false;

  Info &info(Sym s) {
    if (s >= infos.size()) infos.resize(s + 1);
    return infos[s];
  }
  Syms &edges(Sym rel, Sym a) {
    if (const uint32_t *i = edgeAt.find(pairKey(rel, a))) return edgeLists[*i];
    edgeAt.insert(pairKey(rel, a), edgeLists.size()), info(rel).binKeys.append(a);
    return edgeLists[edgeLists.append(Syms())];
  }
  const Syms *edgesOf(Sym rel, Sym a) {
    const uint32_t *i = edgeAt.find(pairKey(rel, a));
    return i ? &edgeLists[*i] : nullptr;
  }

  const Node *mk(Node::Kind k, Sym name, Kids kids = {}) { return &pool[pool.append(Node{k, name, mv(kids)})]; }
  const Node *atom(Sym s) { return mk(Node::Atom, s); }
  const Node *atom(const char *s) { return mk(Node::Atom, sym(s)); }
  const Node *list(Kids kids) { return mk(Node::List, 0, mv(kids)); }

  const Node *node(Value v) {
    uint64_t key = uint64_t(uintptr_t(v.getAsOpaquePointer()));
    if (const Node **n = seen.find(key)) return *n;
    const Node *n;
    if (auto a = v.getDefiningOp<AtomOp>()) {
      Chars s = chars(a.getName().data(), uint32_t(a.getName().size()));
      Node::Kind k = s.size() > 1 && s[0] == '@'  ? Node::Row
                     : s.size() && s[0] == '"' ? Node::Str
                     : isNumeric(s)            ? Node::Num
                                               : Node::Atom;
      Text t;
      for (char c : s) { // SigmaKEE's reader makes each run of white space in a string one space
        bool white = k == Node::Str && (c == ' ' || c == '\n' || c == '\t' || c == '\r' || c == '\f');
        if (!white) t += c;
        else if (t.empty() || t.back() != ' ') t += ' ';
      }
      n = mk(k, sym(t));
    } else if (auto var = v.getDefiningOp<VarOp>()) {
      n = mk(Node::Var, sym(chars(var.getName().data(), uint32_t(var.getName().size()))));
    } else {
      Kids kids;
      for (Value e : v.getDefiningOp<ListOp>().getElements()) kids.append(node(e));
      n = list(mv(kids));
    }
    seen.insert(key, n);
    return n;
  }

  // ---- the cache ----------------------------------------------------------------------------------------------------

  void buildCache(const Kids &forms) {
    composite::WordTable<uint32_t> domainAt; // a relation (+1) -> its row: domain at 1..20, domainSubclass at 22..41
    MutableSeries<composite::Arr<Sym, 42>> domainRows;
    auto isAtom = [](const Node *n) { return n->kind == Node::Atom; };
    for (const Node *f : forms) {
      Sym hs = head(f);
      Chars h = nm(hs);
      if (!hs) continue;
      if (nargs(f) == 2 && isAtom(arg(f, 0)) && isAtom(arg(f, 1))) {
        Sym a = arg(f, 0)->name, b = arg(f, 1)->name;
        edges(hs, a).append(b);
        if (h == "subclass") info(a).subclassParents.append(b), info(b).subclassChildren.append(a);
        else if (h == "subrelation") info(a).subrelationParents.append(b), info(b).subrelationChildren.append(a), subrelated.insert(a);
        else if (h == "instance")
          info(a).instanceClasses.append(b), info(a).hasClasses = true, info(b).instancesOf.append(a), instAsserted.insert(pairKey(a, b), 1);
        else if (h == "range") info(a).range = b;
        else if (h == "rangeSubclass") info(a).rangeSub = b;
      }
      if (nargs(f) == 3 && isAtom(arg(f, 0)) && arg(f, 1)->kind == Node::Num && isAtom(arg(f, 2)) &&
          (h == "domain" || h == "domainSubclass")) {
        int n = 0;
        Chars place = nm(arg(f, 1)->name);
        if (llvm::StringRef(place.data(), place.size()).getAsInteger(10, n) || n < 1 || n > 20) continue;
        Sym rel = arg(f, 0)->name;
        if (!domainAt.find(rel + 1)) domainAt.insert(rel + 1, domainRows.append(composite::Arr<Sym, 42>{}));
        domainRows[*domainAt.find(rel + 1)][(h == "domain" ? 0 : 21) + n] = arg(f, 2)->name;
        if (h == "domain") domainClass.insert(pairKey(rel, arg(f, 2)->name), 1);
      }
    }
    // KBcache.buildRelationsSet: from Relation down subclass, instance and subrelation
    SymSet frontier, visited, rels, done;
    frontier.insert(sym("Relation")), rels.insert(sym("TransitiveRelation"));
    while (!frontier.empty()) {
      SymSet next;
      for (Sym r : frontier) {
        if (!visited.insert(r)) continue;
        next.insertAll(info(r).subclassChildren);
        for (Sym i : info(r).instancesOf) relations.insert(i), next.insert(i);
        for (Sym s : info(r).subrelationChildren) relations.insert(s), next.insert(s);
      }
      frontier = mv(next);
    }
    // KBcache.buildTransitiveRelationsSet: from TransitiveRelation down subclass; its instances and subrelations
    while (!rels.empty()) {
      SymSet next;
      for (Sym r : rels) {
        if (!done.insert(r)) continue;
        next.insertAll(info(r).subclassChildren);
        transRels.insertAll(info(r).instancesOf), transRels.insertAll(info(r).subrelationChildren);
      }
      rels = mv(next);
    }
    // KBcache.collectDomains
    Sym entity = sym("Entity");
    for (Sym rel : relations) {
      Sym a[21] = {};
      int maxIndex = 0;
      if (const uint32_t *at = domainAt.find(rel + 1))
        for (int k = 0; k < 42; k++) // the domains, then the domainSubclasses
          if (Sym c = domainRows[*at][k]) a[k % 21] = k < 21 ? c : sym(nm(c) + "+"), maxIndex = composite::max(maxIndex, k % 21);
      Info &ri = info(rel);
      if (ri.range) a[0] = ri.range;
      if (ri.rangeSub) a[0] = sym(nm(ri.rangeSub) + "+");
      for (int i = 1; i < maxIndex; i++) // fillArray: up to, not including, maxIndex
        if (!a[i]) a[i] = entity;
      ri.sig.clear();
      for (int i = 0; i <= maxIndex; i++) ri.sig.append(a[i]);
      ri.hasSig = ri.hasValence = sigsKnown = true, ri.valence = maxIndex;
    }
    // KBcache.inheritDomains: from each root of subrelation (an arg 2 that is no arg 1), children first in, first visited
    SymSet roots;
    for (Sym c : subrelated) roots.insertAll(info(c).subrelationParents);
    for (Sym root : roots) {
      if (subrelated.count(root)) continue;
      Syms q; // a stack: SigmaKEE's push and pop at the front
      q.append(root);
      SymSet v;
      v.insert(root);
      while (!q.empty()) {
        Sym t = q.back();
        q.pop();
        for (Sym child : SymSet::of(copy(info(t).subrelationChildren))) {
          Info &ci = info(child), &ti = info(t);
          if (!ti.hasValence || !ci.hasSig || !ti.hasSig) continue;
          Syms &cd = ci.sig;
          if (!ci.hasValence || ci.valence < ti.valence) {
            for (int i = ci.hasValence ? ci.valence + 1 : 0; i < ti.valence + 1; i++) // fillArrayList appends
              if (i > int(cd.size()) - 1 || !cd[i]) cd.append(entity);
            ci.valence = ti.valence, ci.hasValence = true;
          }
          for (int i = 1; i <= ti.valence && i < int(cd.size()) && i < int(ti.sig.size()); i++)
            if (!domainClass.find(pairKey(child, cd[i]))) cd[i] = ti.sig[i];
          if (v.insert(child)) q.append(child);
        }
      }
    }
    // KBcache.buildTransInstOf, correctValences, buildFunctionsSet: once the signatures are known
    for (Sym r : relations) (isInstanceOf(r, sym("Function")) ? functions : predicates).insert(r);
    cacheBuilt = true;
  }

  const SymSet &supers(Sym c) {
    Info &ci = info(c);
    if (ci.supers) return *ci.supers;
    ci.supers = SymSet(); // a cycle reads what is there so far
    for (Syms todo = copy(ci.subclassParents); !todo.empty();) {
      Sym p = todo.back();
      todo.pop();
      if (p == c || !ci.supers->insert(p)) continue;
      for (Sym g : info(p).subclassParents) todo.append(g);
    }
    return *ci.supers;
  }

  const SymSet &reach(Sym rel, Sym a) {
    if (const uint32_t *i = reachAt.find(pairKey(rel, a))) return reachSets[*i];
    uint32_t at = reachSets.append(SymSet());
    reachAt.insert(pairKey(rel, a), at);
    SymSet &out = reachSets[at];
    const Syms *e = edgesOf(rel, a);
    for (Syms todo = e ? copy(*e) : Syms(); !todo.empty();) {
      Sym b = todo.back();
      todo.pop();
      if (b == a || !out.insert(b)) continue;
      if (const Syms *f = edgesOf(rel, b)) for (Sym x : *f) todo.append(x);
    }
    return out;
  }

  bool instTransRel(Sym rel) { // KBcache.buildInstTransRels: no argument is a class
    Sym cls = sym("Class");
    return transRels.count(rel) && info(rel).hasSig && !anyOf(info(rel).sig, [&](Sym t) { return plusType(t) || t == cls; });
  }

  const SymSet &instances(Sym i) { // KBcache.buildTransInstOf: what i is an instance of
    if (cacheBuilt && info(i).inst) return *info(i).inst;
    SymSet out;
    auto add = [&](Sym c) { out.insert(c), out.insertAll(supers(c)); };
    for (Sym c : info(i).instanceClasses) add(c);
    if (sigsKnown) // once the signatures are known: up subrelation and subAttribute, to what is above
      for (const char *rel : climbs)
        if (instTransRel(sym(rel)))
          for (Sym p : reach(sym(rel), i))
            for (Sym c : info(p).instanceClasses) add(c);
    if (!cacheBuilt) return fresh = mv(out);
    return *(info(i).inst = mv(out));
  }
  bool isInstanceOf(Sym i, Sym c) { return instances(i).count(c); }
  bool isSubclass(Sym c, Sym p) { return c == p || supers(c).count(p); }
  bool isFunction(Sym f) { return functions.count(f); }

  int valence(Sym rel) { // KBcache.getArity after correctValences: -1 for a variable arity
    if (isInstanceOf(rel, sym("VariableArityRelation"))) return -1;
    return info(rel).hasValence ? info(rel).valence : 0;
  }

  void copyNewPred(Sym renamed, Sym old, int arity) { // copyNewPredFromVariableArity
    Info &ri = info(renamed), &oi = info(old);
    if (ri.hasSig) return;
    Syms sig;
    Sym last = sym("Entity");
    if (!oi.hasSig || oi.sig.empty()) sig.append(isFunction(old) ? sym("Entity") : 0);
    else if (sig = copy(oi.sig), sig.back()) last = sig.back();
    while (int(sig.size()) <= arity) sig.append(last);
    ri.sig = mv(sig), ri.hasSig = ri.hasValence = sigsKnown = true, ri.valence = arity;
    (isFunction(old) ? functions : predicates).insert(renamed);
    ri.instanceClasses = copy(oi.instanceClasses), ri.hasClasses = oi.hasClasses = true, ri.inst = nullptr;
  }

  SymSet subrelationsBelow(Sym r) { // KBcache.getChildRelations: transitive
    SymSet out;
    for (Sym c : subrelated)
      if (c != r && reach(sym("subrelation"), c).count(r)) out.insert(c);
    return out;
  }

  Sym findType(int arg, Sym pred) { return !info(pred).hasSig || arg >= int(info(pred).sig.size()) ? 0 : info(pred).sig[arg]; }
  Sym getRange(Sym f) { return !isFunction(f) || !info(f).hasSig || info(f).sig.empty() ? 0 : info(f).sig[0]; }

  // ---- preprocessing ------------------------------------------------------------------------------------------------

  static Sym head(const Node *n) {
    if (n->kind != Node::List || n->kids.empty()) return 0;
    const Node *h = n->kids[0];
    return (h->kind == Node::Atom || h->kind == Node::Var) ? h->name : 0;
  }
  static uint32_t nargs(const Node *n) { return n->kids.empty() ? 0 : n->kids.size() - 1; }
  static const Node *arg(const Node *n, uint32_t i) { return n->kids[i + 1]; }

  bool higherOrder(const Node *e) { // Formula.isHigherOrderExpr
    Sym h = head(e), formula = sym("Formula");
    if (!h) return false;
    if (!varName(h) && info(h).hasSig && contains(info(h).sig, formula)) return true;
    bool logop = isLogOp(nm(h));
    for (uint32_t i = 0; i < nargs(e); i++) {
      const Node *a = arg(e, i);
      if (a->kind != Node::List) continue;
      Sym ah = head(a);
      if (ah && !isFunction(ah)) {
        if (!logop) return true;
        if (higherOrder(a)) return true;
      } else if (higherOrder(a)) {
        return true;
      }
    }
    return false;
  }

  static bool hasPredVar(const Node *e) {
    if (e->kind != Node::List) return false;
    if (isQuantifier(nm(head(e))) && nargs(e) == 2) return hasPredVar(arg(e, 1)); // its variable list is no application
    if (!e->kids.empty() && e->kids[0]->kind == Node::Var) return true;
    return anyOf(e->kids, hasPredVar);
  }

  static bool hasRowVar(const Node *e) { return e->kind == Node::Row || (e->kind == Node::List && anyOf(e->kids, hasRowVar)); }

  // ---- predicate variables (com.articulate.sigma.PredVarInst) -------------------------------------------------------

  bool simpleClause(const Node *e, uint32_t start) { // Formula.isSimpleClause of the list e->kids[start..]
    if (e->kind != Node::List || start >= e->kids.size() || e->kids[start]->kind == Node::List) return false;
    for (uint32_t i = start + 1; i < e->kids.size(); i++) {
      const Node *a = e->kids[i];
      if (a->kind != Node::List) continue;
      Sym h = head(a);
      if (!h || !isFunction(h)) return false;
    }
    return true;
  }

  // PredVarInst.gatherPredVarRecurse: car and cdr, as SigmaKEE walks the formula's text
  void gatherPredVars(const Node *e, uint32_t start, SymSet &vars, SymMap<int> &arity) {
    if (e->kind != Node::List || start >= e->kids.size()) return;
    if (simpleClause(e, start)) {
      const Node *h = e->kids[start];
      if (h->kind == Node::Var && e->kids.size() - start > 1) {
        vars.insert(h->name);
        bool row = false;
        for (uint32_t i = start + 1; i < e->kids.size(); i++) row |= e->kids[i]->kind == Node::Row;
        arity[h->name] = row ? 0 : int(e->kids.size() - start - 1); // 0: any arity
      }
      return;
    }
    const Node *car = e->kids[start];
    if (car->kind == Node::Atom && isQuantifier(nm(car->name))) return gatherPredVars(e, start + 2, vars, arity); // cddr
    gatherPredVars(car, 0, vars, arity);
    gatherPredVars(e, start + 1, vars, arity);
  }

  TypeMap allTypeRestrictions(const Node *e) { // FormulaPreprocessor.findAllTypeRestrictions
    TypeMap out = variableTypes(e), types, classes;
    explicitTypes(antecedent(e), false, types, classes);
    for (auto &[v, ts] : types) out[v].insertAll(ts);
    return out;
  }
  static const Node *antecedent(const Node *e) { // A of (=> A B) or (<=> A B), else the whole
    Chars h = nm(head(e));
    return (h == "=>" || h == "<=>") && nargs(e) >= 2 ? arg(e, 0) : e;
  }

  const Node *substitute(const Node *e, Sym var, const Node *by) { // parsing.PredVarInst.substituteVar
    if (e->kind == Node::Var) return e->name == var ? by : e;
    if (e->kind != Node::List) return e;
    Kids kids;
    bool changed = false;
    for (const Node *k : e->kids) {
      kids.append(substitute(k, var, by));
      changed |= kids.back() != k;
    }
    return changed ? list(mv(kids)) : e;
  }

  // PredVarInst.handleDouble1 (disjoint) and handleDouble2: the two axioms with two predicate variables SigmaKEE
  // instantiates, pair by pair of relations of one arity.  (SigmaKEE writes both sets under whichever double axiom a
  // thread meets first; here each set is written under its own axiom.)
  Kids handleDouble(bool disjoint) {
    MutableSeries<Join<Sym, Sym>> pairs; // then in byte order, each once (a std::set of pairs)
    Sym dr = sym("disjointRelation");
    if (disjoint) { // KBcache.buildDisjointRelationsMap
      for (Sym a : info(dr).binKeys)
        for (Sym b : *edgesOf(dr, a)) {
          SymSet c1 = subrelationsBelow(a), c2 = subrelationsBelow(b);
          c1.insert(a), c2.insert(b);
          for (Sym x : c1)
            for (Sym y : c2)
              if (x != y) pairs.append({x, y});
        }
    } else {
      // KBcache.buildDisjointRelationsMap adds each relation of a (disjointRelation a b) to its own stored set of
      // subrelations (getChildRelations returns the cache's set, and it adds a to it), so for each that has one -- that is
      // in a (subrelation _ _) -- SigmaKEE writes the tautology (=> (a ..) (a ..)) too.  So does this.
      SymSet inSubrelation, selfBelow;
      for (Sym c : subrelated) inSubrelation.insert(c), inSubrelation.insertAll(info(c).subrelationParents);
      for (Sym a : info(dr).binKeys) {
        for (Sym x : *edgesOf(dr, a))
          if (inSubrelation.count(x)) selfBelow.insert(x);
        if (inSubrelation.count(a)) selfBelow.insert(a);
      }
      for (Sym r1 : relations) {
        if (isFunction(r1)) continue;
        for (Sym r2 : subrelationsBelow(r1)) pairs.append({r2, r1});
        if (selfBelow.count(r1)) pairs.append({r1, r1});
      }
    }
    stableSort(pairs, [](const Join<Sym, Sym> &p, const Join<Sym, Sym> &q) { return p.a != q.a ? before(p.a, q.a) : before(p.b, q.b); });
    Kids out;
    for (uint32_t k = 0; k < pairs.size(); k++) {
      Sym x = pairs[k].a, y = pairs[k].b;
      if (k && x == pairs[k - 1].a && y == pairs[k - 1].b) continue;
      int ax = valence(x);
      if (ax != valence(y)) continue;
      Kids l{atom(x)}, r{atom(y)};
      for (int i = 1; i <= ax; i++) {
        const Node *v = mk(Node::Var, sym(cat("?ROW", i)));
        l.append(v), r.append(v);
      }
      const Node *rhs = list(mv(r));
      if (disjoint) rhs = list({atom("not"), rhs});
      out.append(list({atom("=>"), list(mv(l)), rhs}));
    }
    return out;
  }

  // PredVarInst.instantiatePredVars: each relation of the variable's arity that is an instance of each of its types, in
  // its place.  Nothing: dropped (more than one predicate variable); empty: no instance.
  composite::Maybe<Kids> instantiatePredVars(const Node *f, const Text &key) {
    SymSet vars;
    SymMap<int> arity;
    gatherPredVars(f, 0, vars, arity);
    if (vars.size() > 1) {
      if (key == doubleAxiom) return handleDouble(true);
      if (key == subrelationAxiom) return handleDouble(false);
      return nullptr;
    }
    TypeMap all = allTypeRestrictions(f), varTypes;
    for (Sym v : vars)
      if (const SymSet *ts = all.find(v)) varTypes[v] = ts->clone();
    // addExplicitTypes: a rule's antecedent's (instance ?V C) and (subclass ?V C), the latter replacing the former
    const Node *rule = f;
    while (isQuantifier(nm(head(rule))) && nargs(rule) == 2 && arg(rule, 1)->kind == Node::List) rule = arg(rule, 1);
    Chars rh = nm(head(rule));
    if ((rh == "=>" || rh == "<=>") && nargs(f) >= 1) {
      TypeMap types, classes;
      explicitTypes(arg(f, 0), false, types, classes);
      for (auto &[v, c] : classes) types[v] = c.clone();
      if (!types.empty()) {
        TypeMap result;
        for (auto &[v, ts] : types)
          if (const SymSet *had = varTypes.find(v)) (result[v] = had->clone()).insertAll(ts);
        varTypes = mv(result);
      }
    }
    static const char *const skip[] = {"equal", "greaterThan", "greaterThanOrEqualTo", "lessThan", "lessThanOrEqualTo",
                                       "AdditionFn", "SubtractionFn", "MultiplicationFn", "DivisionFn", "FloorFn",
                                       "RoundFn", "CeilingFn", "RemainderFn"};
    Kids out;
    for (auto &[v, ts] : varTypes) {
      int a = arity.count(v) ? *arity.find(v) : 0;
      for (Sym rel : ts.count(sym("Function")) ? functions : predicates) {
        Chars rn = nm(rel);
        if (among(rn, skip) || isLogOp(rn) || composite::find(rn, chars("__", 2)) != composite::npos) continue;
        if (valence(rel) != a && a != 0) continue;
        if (!anyOf(ts.rows, [&](Sym t) { return !isInstanceOf(rel, t); })) out.append(substitute(f, v, atom(rel)));
      }
    }
    return out;
  }

  // ---- row variables (parsing.RowVar.expandRowVarExpr) --------------------------------------------------------------

  // Formula.initCachesFromExpr's RowStructs: for each row variable, the relation of each literal it is an argument of and
  // the literal's number of arguments.  A quantifier's variable list has no head, so none.
  void rowStructs(const Node *e, bool varList, SymMap<MutableSeries<Join<Sym, int>>> &out) {
    if (e->kind != Node::List || varList) return;
    Sym h = head(e);
    for (uint32_t i = 0; i < nargs(e); i++)
      if (arg(e, i)->kind == Node::Row && h) out[arg(e, i)->name].append({h, int(nargs(e))});
    bool q = isQuantifier(nm(h)) && nargs(e) == 2;
    for (uint32_t i = 0; i < nargs(e); i++) rowStructs(arg(e, i), q && i == 0, out);
  }

  SymMap<int> findArities(const Node *f) { // RowVar.findArities: -1 variable, 0 a conflict
    SymMap<MutableSeries<Join<Sym, int>>> rs;
    rowStructs(f, false, rs);
    SymMap<int> arities;
    for (auto &[rv, structs] : rs) {
      MutableSeries<Join<Sym, int>> sorted;
      for (const Join<Sym, int> &s : structs) sorted.append(s);
      stableSort(sorted, [](const Join<Sym, int> &x, const Join<Sym, int> &y) { return before(x.a, y.a); });
      for (auto &[pred, n] : sorted) {
        if (varName(pred)) continue; // a variable predicate
        int predArity = valence(pred);
        int rva = predArity;
        if (n > 1) rva -= n - 1;
        if (predArity == -1) rva = -1;
        int *had = arities.find(rv);
        if (!had || predArity != -1) {
          if (had && *had > 0 && rva > 0 && *had != rva) arities[rv] = 0;
          else if (!had || *had != 0) arities[rv] = rva;
        }
      }
    }
    for (auto &[rv, a] : arities.rows) { // a numeric and a non-numeric type at one position: a conflict
      if (a <= 0) continue;
      MutableSeries<uint8_t> kinds; // by position: 1 a numeric type there, 2 a non-numeric one
      for (auto &[pred, n] : *rs.find(rv)) {
        Info &pi = info(pred);
        if (!pi.hasSig) continue;
        int pArity = valence(pred);
        if (pArity <= 0) continue;
        for (int abs = n; abs <= pArity && abs < int(pi.sig.size()); abs++)
          if (Sym t = pi.sig[abs]) {
            uint32_t pos = uint32_t(abs - (n - 1));
            if (kinds.size() <= pos) kinds.resize(pos + 1);
            kinds[pos] |= isSubclass(t, sym("RealNumber")) ? 1 : 2;
          }
      }
      if (anyOf(kinds, [](uint8_t k) { return k == 3; })) a = 0;
    }
    return arities;
  }

  const Node *splice(const Node *e, Sym row, const Kids &vars, bool varList) {
    if (e->kind != Node::List) return e;
    Kids kids;
    uint32_t first = varList ? 0 : 1; // a variable list has no head
    if (!varList && !e->kids.empty()) kids.append(e->kids[0]);
    bool q = !varList && isQuantifier(nm(head(e))) && nargs(e) == 2, spliced = false;
    for (uint32_t i = first; i < e->kids.size(); i++) {
      const Node *a = e->kids[i];
      if (a->kind == Node::Row && a->name == row) {
        for (const Node *v : vars) kids.append(v);
        spliced = true;
      } else {
        kids.append(splice(a, row, vars, q && i == 1));
      }
    }
    if (spliced && !varList && !kids.empty() && kids[0]->kind == Node::Atom && valence(kids[0]->name) == -1) {
      Sym pred = kids[0]->name;
      int total = int(kids.size()) - 1;
      Sym renamed = sym(cat(nm(pred), "__", total, composite::endsWith(nm(pred), chars("Fn", 2)) ? "Fn" : ""));
      copyNewPred(renamed, pred, total);
      kids[0] = atom(renamed);
    }
    return list(mv(kids));
  }

  Kids expandRowVars(const Node *f) { // empty: f as it is
    Kids working{f};
    for (auto &[rv, a] : findArities(f)) {
      if (a == 0) return {};
      Kids next;
      for (int n = a == -1 ? 1 : a; n <= (a == -1 ? 7 : a); n++) {
        Kids vs;
        for (int i = 1; i <= n; i++) vs.append(mk(Node::Var, sym(cat("?", composite::substr(nm(rv), 1), i))));
        for (const Node *e : working) next.append(splice(e, rv, vs, false));
      }
      if (a < -1) // a literal with more arguments than its relation: the row variable goes
        for (const Node *e : working) next.append(splice(e, rv, Kids(), false));
      working = mv(next);
    }
    return working;
  }

  const Node *renameVariableArity(const Node *e) { // FormulaPreprocessor.renameVariableArityInExpr
    if (e->kind != Node::List) return e;
    Kids kids;
    for (uint32_t i = 0; i < e->kids.size(); i++) kids.append(i ? renameVariableArity(e->kids[i]) : e->kids[i]);
    const Node *h = kids.empty() ? nullptr : kids[0];
    if (h && h->kind == Node::Atom && instances(h->name).count(sym("VariableArityRelation"))) {
      int arity = int(kids.size()) - 1;
      Text suffix = cat("__", arity, instances(h->name).count(sym("Function")) ? "Fn" : "");
      if (!composite::endsWith(nm(h->name), suffix)) {
        Sym renamed = sym(nm(h->name) + suffix);
        copyNewPred(renamed, h->name, arity);
        kids[0] = atom(renamed);
      }
    }
    return list(mv(kids));
  }

  void merge(TypeMap &into, const TypeMap &from) { // KButilities.mergeToMap: the union, less the supertypes
    for (auto &[var, types] : from) {
      SymSet &v = into[var], drop;
      v.insertAll(types);
      for (Sym a : v)
        for (Sym b : v)
          if (a != b && isSubclass(a, b)) drop.insert(b);
      for (Sym d : drop) v.erase(d);
    }
  }

  TypeMap variableTypes(const Node *e) { // FormulaPreprocessor.computeVariableTypesRecurseExpr
    TypeMap result;
    Sym pred = head(e);
    Chars h = nm(pred);
    if (!pred) return result;
    if (isLogOp(h)) {
      for (uint32_t i = isQuantifier(h) ? 1 : 0; i < nargs(e); i++) merge(result, variableTypes(arg(e, i)));
      return result;
    }
    if (varName(pred)) return result;
    for (uint32_t k = 0; k < 2 && h == "equal" && nargs(e) >= 2; k++) {
      const Node *v = arg(e, k), *f = arg(e, 1 - k);
      if (v->kind == Node::Var && f->kind == Node::List && head(f) && isFunction(head(f)))
        result[v->name].insert(getRange(head(f)) ? getRange(head(f)) : sym("Entity"));
    }
    for (uint32_t i = 0; i < nargs(e); i++) {
      const Node *a = arg(e, i);
      if (a->kind == Node::Var) {
        if (Sym cl = findType(int(i) + 1, pred)) result[a->name].insert(cl);
      } else if (a->kind == Node::List) {
        Sym ah = head(a);
        if (ah && !varName(ah) && isFunction(ah)) merge(result, variableTypes(a));
      }
    }
    return result;
  }

  void explicitTypes(const Node *e, bool negative, TypeMap &types, TypeMap &classes) {
    Sym hs = head(e);
    Chars h = nm(hs);
    if (!hs) return;
    if (isLogOp(h)) {
      if (isQuantifier(h)) {
        if (nargs(e) == 2) explicitTypes(arg(e, 1), false, types, classes);
      } else {
        for (uint32_t i = 0; i < nargs(e); i++) explicitTypes(arg(e, i), h == "not", types, classes);
      }
      return;
    }
    if (negative) return;
    if ((h == "instance" || h == "subclass") && nargs(e) == 2 && arg(e, 0)->kind == Node::Var && arg(e, 1)->kind == Node::Atom) {
      if (h == "instance") types[arg(e, 0)->name].insert(arg(e, 1)->name);
      else classes[arg(e, 0)->name].insert(sym(nm(arg(e, 1)->name) + "+"));
      return;
    }
    for (uint32_t i = 0; i < nargs(e); i++) explicitTypes(arg(e, i), false, types, classes);
  }

  TypeMap typeRestrictions(const Node *e) { // FormulaPreprocessor.findTypeRestrictionsExpr
    // the explicit types of the antecedent of (=> A B) or (<=> A B), else of the whole: instance types only
    // (findExplicitTypesClassesInAntecedentExpr returns the instance map, not the subclass one)
    TypeMap domain = variableTypes(e), types, classes, out;
    explicitTypes(antecedent(e), false, types, classes);
    for (auto &[var, ts] : domain) {
      const SymSet *given = types.find(var);
      if (!given) {
        out[var] = ts.clone();
        continue;
      }
      SymSet &keep = out[var];
      for (Sym t : ts)
        if (plusType(t)) keep.insert(t);
      for (Sym t : *given)
        if (plusType(t)) keep.insert(t);
    }
    return out;
  }

  const Node *guard(Sym var, Sym type) {
    Chars t = nm(type), c = composite::substr(t, 0, t.size() ? t.size() - 1 : 0);
    if (!type || (plusType(type) ? c == "Entity" : t == "Entity" || t == "World" || t == "ObjectiveNorm")) return nullptr;
    if (plusType(type)) return list({atom("subclass"), mk(Node::Var, var), atom(sym(c))});
    return list({atom("instance"), mk(Node::Var, var), atom(type)});
  }
  const Node *wrapAnd(Kids gs) {
    if (gs.size() == 1) return gs[0];
    Kids k{atom("and")};
    for (const Node *g : gs) k.append(g);
    return list(mv(k));
  }

  const Node *restrictRecurse(const Node *e) { // FormulaPreprocessor.addTypeRestrictionsRecurseExpr
    Sym hs = head(e);
    Chars h = nm(hs);
    if (!hs || (!isLogOp(h) && h != "equal")) return e;
    if (isQuantifier(h)) {
      if (nargs(e) != 2) return e;
      const Node *vars = arg(e, 0), *body = arg(e, 1);
      TypeMap sub = typeRestrictions(e);
      Kids guards;
      if (vars->kind == Node::List)
        for (const Node *v : vars->kids)
          if (const SymSet *ts = v->kind == Node::Var || v->kind == Node::Row ? sub.find(v->name) : nullptr)
            for (Sym t : *ts)
              if (const Node *g = guard(v->name, t)) guards.append(g);
      const Node *nb = restrictRecurse(body);
      if (guards.empty()) return nb == body ? e : list({e->kids[0], vars, nb});
      if (h == "exists") return guards.append(nb), list({e->kids[0], vars, wrapAnd(mv(guards))});
      return list({e->kids[0], vars, list({atom("=>"), wrapAnd(mv(guards)), nb})});
    }
    bool changed = false;
    Kids kids{e->kids[0]};
    for (uint32_t i = 0; i < nargs(e); i++) {
      const Node *n = restrictRecurse(arg(e, i));
      changed |= n != arg(e, i);
      kids.append(n);
    }
    return changed ? list(mv(kids)) : e;
  }

  const Node *restrict(const Node *e, const TypeMap &varmap) { // FormulaPreprocessor.addTypeRestrictionsExpr
    Syms bound, free;
    freeVars(e, bound, free);
    Kids guards;
    for (Sym v : SymSet::of(mv(free)))
      if (const SymSet *ts = varmap.find(v))
        for (Sym t : *ts)
          if (const Node *g = guard(v, t)) guards.append(g);
    const Node *body = restrictRecurse(e);
    if (guards.empty()) return body;
    return list({atom("=>"), wrapAnd(mv(guards)), body});
  }

  static void freeVars(const Node *e, Syms &bound, Syms &free) {
    if (e->kind == Node::Var || e->kind == Node::Row) {
      if (!contains(bound, e->name) && !contains(free, e->name)) free.append(e->name);
      return;
    }
    if (e->kind != Node::List) return;
    if (isQuantifier(nm(head(e))) && nargs(e) == 2) {
      Syms inner = copy(bound);
      if (arg(e, 0)->kind == Node::List)
        for (const Node *v : arg(e, 0)->kids)
          if (v->kind == Node::Var || v->kind == Node::Row) inner.append(v->name);
      freeVars(arg(e, 1), inner, free);
      return;
    }
    for (const Node *k : e->kids) freeVars(k, bound, free);
  }

  // ---- rendering ----------------------------------------------------------------------------------------------------

  static Text variable(Sym v) {
    Text s("V__");
    for (char c : composite::substr(nm(v), 1)) s += c == '-' ? '_' : c;
    return s;
  }

  Text word(const Node *e, bool isHead) { // ExprToTPTP.translateExpr for all but a list
    Chars name = nm(e->name);
    auto underscore = [](Chars s) {
      Text t;
      for (char c : s) t += c == '.' || c == '-' ? '_' : c;
      return t;
    };
    switch (e->kind) {
    case Node::Var:
    case Node::Row:
      return variable(e->name);
    case Node::Num:
      return "n__" + underscore(name);
    case Node::Str: {
      Text s;
      for (char c : name) {
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
    if (isInequality(name) && !isHead) return "s__" + name + "__m";
    if (name == "True") return isHead ? "$true" : "'$true__m'";
    if (name == "False") return isHead ? "$false" : "'$false__m'";
    Text term = underscore(name);
    if (!isHead && !term.ends_with("__m") &&
        (term.ends_with("Fn") || (term.size() && lower(term[0])) || relations.count(names.find(term))))
      term += "__m";
    return "s__" + mv(term);
  }

  Text render(const Node *e) { // ExprToTPTP.translateSExpr
    if (e->kind != Node::List) return word(e, false);
    Chars h = nm(head(e));
    auto join = [&](const char *sep) {
      Text s;
      for (uint32_t i = 0; i < nargs(e); i++) s += (i ? sep : "") + render(arg(e, i));
      return s;
    };
    if (h == "not" && nargs(e) == 1) return "~(" + render(arg(e, 0)) + ")";
    if ((h == "and" || h == "or" || h == "xor") && nargs(e) >= 2)
      return "(" + join(h == "and" ? " & " : h == "or" ? " | " : " <~> ") + ")";
    if (h == "=>" && nargs(e) == 2) return "(" + render(arg(e, 0)) + " => " + render(arg(e, 1)) + ")";
    if (h == "<=>" && nargs(e) == 2) {
      Text l = render(arg(e, 0)), r = render(arg(e, 1));
      return "((" + l + " => " + r + ") & (" + r + " => " + l + "))";
    }
    if (h == "equal" && nargs(e) == 2) return "(" + render(arg(e, 0)) + " = " + render(arg(e, 1)) + ")";
    if (isQuantifier(h) && nargs(e) == 2) {
      Text vars;
      if (arg(e, 0)->kind == Node::List)
        for (const Node *v : arg(e, 0)->kids)
          if (v->kind == Node::Var || v->kind == Node::Row) vars += (vars.empty() ? "" : ",") + word(v, false);
      if (vars.empty()) return render(arg(e, 1));
      return (h == "forall" ? "(! [" : "(? [") + vars + "] : (" + render(arg(e, 1)) + "))";
    }
    if (e->kids.empty()) return "()";
    Text s = word(e->kids[0], true) + "(";
    for (uint32_t i = 0; i < nargs(e); i++) s += (i ? "," : "") + word(arg(e, i), false);
    return s + ")";
  }

  Text translate(const Node *e, bool query) { // ExprToTPTP.translate
    Text body = render(e);
    Syms bound, free;
    freeVars(e, bound, free);
    if (free.empty()) return body;
    Text vars;
    for (Sym v : free) vars += (vars.empty() ? "" : ",") + variable(v);
    return (query ? "( ? [" : "( ! [") + vars + "] : (" + body + " ) )";
  }

  static void print(const Node *e, Text &out) {
    if (e->kind != Node::List) {
      out += nm(e->name);
      return;
    }
    out += '(';
    for (uint32_t i = 0; i < e->kids.size(); i++) {
      if (i) out += ' ';
      print(e->kids[i], out);
    }
    out += ')';
  }

  static bool quotedCall(Chars t) { // SUMOKBtoTPTPKB.QUOTED_CALL_PATTERN: .*'[a-z][a-zA-Z0-9_]*\(.*
    auto alnum = [](char c) { return lower(c) || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_'; };
    for (uint32_t i = 0; i + 1 < t.size(); i++) {
      if (t[i] != '\'' || !lower(t[i + 1])) continue;
      uint32_t j = i + 2;
      while (j < t.size() && alnum(t[j])) j++;
      if (j < t.size() && t[j] == '(') return true;
    }
    return false;
  }

  LogicalResult write(raw_ostream &os) {
    Kids forms;
    for (Operation &op : theory.getBody().front()) {
      if (auto f = dyn_cast<FactOp>(op)) forms.append(node(f.getTerm()));
      else if (auto r = dyn_cast<RuleOp>(op)) forms.append(list({atom("=>"), node(r.getAntecedent()), node(r.getConsequent())}));
    }
    buildCache(forms);
    static const char *const excluded[] = {"documentation", "domain", "format", "termFormat", "externalImage",
                                           "relatedExternalConcept", "relatedInternalConcept", "formerName",
                                           "abbreviation", "conventionalShortName", "conventionalLongName"};
    static const char *const testForms[] = {"note", "category", "time", "answer"};
    os << "% the theory " << theory.getSymName() << " as TPTP FOF, as SigmaKEE translates it (mlnix-kif --tptp)\n";
    unsigned n = 0, queries = 0;
    SymMap<unsigned> skipped;
    // FormulaPreprocessor.preProcessExpr: the predicate variables instantiated, then the row variables expanded, then
    // each variable-arity relation renamed and the variables' types made guards
    composite::TextSet written; // SUMOKBtoTPTPKB.alreadyWrittenTPTPs
    auto axiom = [&](const Node *f) {
      const Node *renamed = renameVariableArity(f);
      Text tptp = translate(restrict(renamed, typeRestrictions(renamed)), false);
      if (quotedCall(tptp)) out(os << "% number: ", tptp) << "\n"; // filterAxiom: removeNum
      else if (!written.insert(tptp.data(), tptp.size())) out(os << "% empty, already written or filtered formula, skipping : ", tptp) << "\n";
      else out(os << "fof(kb_" << ++n << ",axiom,(", tptp) << ")).\n";
    };
    auto emit = [&](Chars key, const Node *f, bool query) {
      out(os << "% f: ", key) << "\n";
      if (query) out(os << "fof(query_" << queries++ << ",conjecture,(", translate(renameVariableArity(f), true)) << ")).\n";
      else axiom(f);
    };
    for (const Node *f : forms) {
      Text key;
      print(f, key);
      Chars h = nm(head(f));
      const char *why = nullptr;
      if (among(h, testForms)) continue;
      bool query = h == "query" && nargs(f) == 1;
      const Node *g = query ? arg(f, 0) : f; // a query asks its formula
      if (among(h, excluded)) why = "excluded";
      else if (higherOrder(g)) why = "higher order";
      else if (query && (hasPredVar(g) || hasRowVar(g))) why = "a query with a predicate or row variable";
      Kids stage{f};
      if (!why && !query && hasPredVar(f)) {
        composite::Maybe<Kids> inst = instantiatePredVars(f, key);
        if (!inst) why = "more than one predicate variable";
        else if (inst->empty()) why = "no instance of its predicate variable";
        else stage = mv(*inst);
      }
      if (query && !why) {
        emit(key, g, true);
        continue;
      }
      if (why) {
        out(os << "% f: ", key) << "\n% not written: " << why << "\n";
        skipped[sym(why)]++;
        continue;
      }
      MutableSeries<Text> texts; // by text, as SigmaKEE's TreeSet by toKifString: each text once, in byte order
      Kids made;
      MutableSeries<uint32_t> order;
      for (const Node *x : stage) {
        Kids e;
        if (hasRowVar(x)) e = expandRowVars(x);
        if (e.empty()) e.append(x);
        for (const Node *y : e) order.append(texts.append(Text())), print(y, texts.back()), made.append(y);
      }
      stableSort(order, [&](uint32_t a, uint32_t b) { return composite::lessChars(texts[a], texts[b]); });
      out(os << "% f: ", key) << "\n";
      for (uint32_t k = 0; k < order.size(); k++)
        if (!k || texts[order[k]] != texts[order[k - 1]]) axiom(made[order[k]]);
    }

    // SUMO_Cache.kif: each transitive relation's closure, less what is asserted
    for (Sym rel : transRels) {
      if (among(nm(rel), excluded)) continue;
      for (Sym c : SymSet::of(copy(info(rel).binKeys)))
        for (Sym p : reach(rel, c)) {
          if (contains(*edgesOf(rel, c), p)) continue;
          Node a{Node::Atom, rel, {}}, x{Node::Atom, c, {}}, y{Node::Atom, p, {}}, l{Node::List, 0, {&a, &x, &y}};
          emit(cat("(", nm(rel), " ", nm(c), " ", nm(p), ")"), &l, false);
        }
    }
    Syms held; // what has classes: an instance, or what is below one by subrelation or subAttribute
    for (Sym s = 0; s < infos.size(); s++)
      if (infos[s].hasClasses) held.append(s);
    for (const char *rel : climbs)
      for (Sym a : info(sym(rel)).binKeys) held.append(a);
    for (Sym i : SymSet::of(mv(held))) {
      if (composite::find(nm(i), chars("__", 2)) != composite::npos) continue; // a renamed variable-arity relation
      for (Sym c : instances(i).clone()) {
        if (instAsserted.find(pairKey(i, c))) continue;
        Node a{Node::Atom, sym("instance"), {}}, x{Node::Atom, i, {}}, y{Node::Atom, c, {}}, l{Node::List, 0, {&a, &x, &y}};
        emit(cat("(instance ", nm(i), " ", nm(c), ")"), &l, false);
      }
    }
    // SUMOKBtoTPTPKB.printListFnSemanticAxioms and printPartitionSemanticAxioms: what SigmaKEE writes after the KB, in FOF
    os << "% f: (the ListFn and partition axioms SUMOKBtoTPTPKB writes)\n";
    auto vars = [](const char *v, int k) {
      Text s;
      for (int i = 1; i <= k; i++) s += cat(i > 1 ? "," : "", v, i);
      return s;
    };
    auto extra = [&](const Text &body) { out(os << "fof(kb_" << ++n << ",axiom,(", body) << ")).\n"; };
    for (int k = 1; k <= 7; k++) {
      Text xs = vars("V__X", k), fn = cat("s__ListFn__", k, "Fn(", xs, ")");
      extra(cat("! [", xs, "] : s__instance(", fn, ",s__List)"));
      extra(cat("! [", xs, "] : (s__ListLengthFn(", fn, ") = n__", k, ")"));
      for (int i = 1; i <= k; i++) {
        extra(cat("! [", xs, "] : (s__ListOrderFn(", fn, ",n__", i, ") = V__X", i, ")"));
        extra(cat("! [", xs, "] : s__inList(V__X", i, ",", fn, ")"));
      }
    }
    for (int k = 2; k <= 7; k++) {
      Text cs = vars("V__C", k), all = cat("V__C,", cs), part = cat("s__partition__", k + 1, "(V__C,", cs, ")"), disj;
      for (int i = 1; i <= k; i++) disj += cat(i > 1 ? " | " : "", "s__instance(V__OBJ,V__C", i, ")");
      extra(cat("! [", all, "] : (", part, " => (s__ChildrenOfFn(V__C) = s__ListFn__", k, "Fn(", cs, ")))"));
      extra(cat("! [V__OBJ,", all, "] : ((", part, " & s__instance(V__OBJ,V__C)) => (", disj, "))"));
    }
    os << "% " << n << " axioms, " << queries << " conjectures; not written:";
    for (auto &[why, k] : skipped) out(os << " " << k << " ", nm(why)) << ";";
    os << "\n";
    return success();
  }
};

} // namespace

LogicalResult mlir::kif::exportTptp(TheoryOp theory, raw_ostream &os) { return Tptp(theory).write(os); }
