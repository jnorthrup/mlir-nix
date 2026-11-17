// A kif theory as a TPTP problem: `mlnix-kif --tptp` (lib/Dialect/KifTptp.cpp) writes @kb as SigmaKEE's translation does
// (trans/SUMOKBtoTPTPKB, FormulaPreprocessor, parsing/ExprToTPTP, PredVarInst, RowVar), so that Vampire's problem comes
// from the kif dialect.  On Merge.kif it writes what SigmaKEE's SUMO.tptp holds, formula for formula
// (scripts/kif-tptp-compare.py; docs/REASONING-SPLIT.md).  Each formula follows a `% f:` line with its form.
// RUN: mlnix-kif --tptp - %S/../kif/tptp-cases.kif | FileCheck %s
//
// Where Vampire is on PATH (Kali), the problem's conjecture is a theorem.
// RUN: [vampire] t=$(mktemp -d); mlnix-kif --tptp $t/c.p %S/../kif/tptp-cases.kif && vampire --mode casc -t 20 $t/c.p | FileCheck %s --check-prefix=VAMPIRE; s=$?; rm -rf $t; exit $s

// What SigmaKEE leaves out is a comment: the excluded predicates (domain, documentation, ..).
// CHECK:      % f: (domain part 1 Object)
// CHECK-NEXT: % not written: excluded
// CHECK:      % f: (subrelation member part)
// CHECK-NEXT: fof(kb_{{[0-9]+}},axiom,(s__subrelation(s__member__m,s__part__m))).
// CHECK:      % f: (documentation part EnglishLanguage "A part.")
// CHECK-NEXT: % not written: excluded
// CHECK:      % f: (domainSubclass KindFn 1 Object)
// CHECK-NEXT: fof(kb_{{[0-9]+}},axiom,(s__domainSubclass(s__KindFn__m,n__1,s__Object))).
//
// A variable-arity relation takes the number of its arguments.
// CHECK:      % f: (partition Animal Human Object)
// CHECK-NEXT: fof(kb_{{[0-9]+}},axiom,(s__partition__3(s__Animal,s__Human,s__Object))).
//
// The variables are typed by the relations' domains: guards for the free ones, a forall's in its body, an exists' among
// its conjuncts.  A rule's antecedent (instance ?X Human) is ?X's type, so ?X has no guard; a function's range types
// what equals its value; a domainSubclass makes a (subclass ?X C) guard.
// CHECK:      % f: (=> (part ?X ?Y) (exists (?Z) (part ?Z ?X)))
// CHECK-NEXT: fof(kb_{{[0-9]+}},axiom,(( ! [V__X,V__Y] : (((s__instance(V__X,s__Object) & s__instance(V__Y,s__Object)) => (s__part(V__X,V__Y) => (? [V__Z] : ((s__instance(V__Z,s__Object) & s__part(V__Z,V__X)))))) ) ))).
// CHECK-NEXT: % f: (=> (and (instance ?X Human) (part ?X ?Y)) (touches ?X ?Y))
// CHECK-NEXT: fof(kb_{{[0-9]+}},axiom,(( ! [V__Y,V__X] : ((s__instance(V__Y,s__Object) => ((s__instance(V__X,s__Human) & s__part(V__X,V__Y)) => s__touches(V__X,V__Y))) ) ))).
// CHECK-NEXT: % f: (=> (equal ?H (HeightFn ?X)) (instance ?H Number))
// CHECK-NEXT: fof(kb_{{[0-9]+}},axiom,(( ! [V__H,V__X] : (((s__instance(V__H,s__RealNumber) & s__instance(V__X,s__Object)) => ((V__H = s__HeightFn(V__X)) => s__instance(V__H,s__Number))) ) ))).
// CHECK-NEXT: % f: (=> (subclass ?C (KindFn ?X)) (instance ?X Object))
// CHECK-NEXT: fof(kb_{{[0-9]+}},axiom,(( ! [V__C,V__X] : (((s__instance(V__C,s__Class) & s__subclass(V__X,s__Object)) => (s__subclass(V__C,s__KindFn(V__X)) => s__instance(V__X,s__Object))) ) ))).
//
// A formula as an argument (holdsDuring's second is a Formula) is higher order: not FOF.
// CHECK-NEXT: % f: (=> (holdsDuring ?T (part ?X ?Y)) (part ?X ?Y))
// CHECK-NEXT: % not written: higher order
//
// A row variable: as many variables as its relation leaves, or one formula for each of 1..7 where it is of variable
// arity, the relations renamed.
// CHECK:      % f: (=> (touches @ROW) (part @ROW))
// CHECK-NEXT: fof(kb_{{[0-9]+}},axiom,(( ! [V__ROW1,V__ROW2] : (((s__instance(V__ROW1,s__Object) & s__instance(V__ROW2,s__Object)) => (s__touches(V__ROW1,V__ROW2) => s__part(V__ROW1,V__ROW2))) ) ))).
// CHECK-NEXT: % f: (=> (partition @ROW) (inList Bob (ListFn @ROW)))
// CHECK-NEXT: fof(kb_{{[0-9]+}},axiom,(( ! [V__ROW1] : ((s__instance(V__ROW1,s__Class) => (s__partition__1(V__ROW1) => s__inList(s__Bob,s__ListFn__1Fn(V__ROW1)))) ) ))).
// CHECK-NEXT: fof(kb_{{[0-9]+}},axiom,(( ! [V__ROW1,V__ROW2] : (((s__instance(V__ROW1,s__Class) & s__instance(V__ROW2,s__Class)) => (s__partition__2(V__ROW1,V__ROW2) => s__inList(s__Bob,s__ListFn__2Fn(V__ROW1,V__ROW2)))) ) ))).
// CHECK:      fof(kb_{{[0-9]+}},axiom,(( ! [V__ROW1,V__ROW2,V__ROW3,V__ROW4,V__ROW5,V__ROW6,V__ROW7] : (((s__instance(V__ROW1,s__Class) & {{.*}} => (s__partition__7(V__ROW1,V__ROW2,V__ROW3,V__ROW4,V__ROW5,V__ROW6,V__ROW7) => s__inList(s__Bob,s__ListFn__7Fn(V__ROW1,V__ROW2,V__ROW3,V__ROW4,V__ROW5,V__ROW6,V__ROW7)))) ) ))).
//
// A predicate variable: each relation that is an instance of its types (member is one of TransitiveRelation through
// part, which it is a subrelation of), in order.
// CHECK-NEXT: % f: (=> (instance ?REL TransitiveRelation) (forall (?A ?B ?C) (=> (and (?REL ?A ?B) (?REL ?B ?C)) (?REL ?A ?C))))
// CHECK-NEXT: fof(kb_{{[0-9]+}},axiom,((s__instance(s__member__m,s__TransitiveRelation) => (! [V__A,V__B,V__C] : (((s__instance(V__A,s__Animal) & s__instance(V__B,s__Animal) & s__instance(V__C,s__Object)) => ((s__member(V__A,V__B) & s__member(V__B,V__C)) => s__member(V__A,V__C)))))))).
// CHECK-NEXT: fof(kb_{{[0-9]+}},axiom,((s__instance(s__part__m,s__TransitiveRelation) => {{.*}}s__part(V__A,V__C)))))))).
// CHECK-NEXT: fof(kb_{{[0-9]+}},axiom,((s__instance(s__properPart__m,s__TransitiveRelation) => {{.*}}s__properPart(V__A,V__C)))))))).
// CHECK-NEXT: fof(kb_{{[0-9]+}},axiom,((s__instance(s__subclass__m,s__TransitiveRelation) => {{.*}}s__subclass(V__A,V__C)))))))).
// CHECK-NEXT: fof(kb_{{[0-9]+}},axiom,((s__instance(s__subrelation__m,s__TransitiveRelation) => {{.*}}s__subrelation(V__A,V__C)))))))).
//
// Two predicate variables: the two axioms SigmaKEE instantiates pair by pair (with its tautology for a relation of a
// disjointRelation that has subrelations), and none else.
// CHECK-NEXT: % f: (=> (and (instance ?REL1 Predicate) (instance ?REL2 Predicate) (disjointRelation ?REL1 ?REL2) (?REL1 @ROW2)) (not (?REL2 @ROW2)))
// CHECK-NEXT: fof(kb_{{[0-9]+}},axiom,(( ! [V__ROW1,V__ROW2] : (((s__instance(V__ROW1,s__Animal) & s__instance(V__ROW2,s__Object)) => (s__member(V__ROW1,V__ROW2) => ~(s__touches(V__ROW1,V__ROW2)))) ) ))).
// CHECK-NEXT: % f: (=> (and (subrelation ?REL1 ?REL2) (instance ?REL1 Predicate) (instance ?REL2 Predicate) (?REL1 @ROW)) (?REL2 @ROW))
// CHECK-NEXT: fof(kb_{{[0-9]+}},axiom,(( ! [V__ROW1,V__ROW2] : (((s__instance(V__ROW1,s__Animal) & s__instance(V__ROW2,s__Object)) => (s__member(V__ROW1,V__ROW2) => s__member(V__ROW1,V__ROW2))) ) ))).
// CHECK-NEXT: fof(kb_{{[0-9]+}},axiom,(( ! [V__ROW1,V__ROW2] : (((s__instance(V__ROW1,s__Animal) & s__instance(V__ROW2,s__Object)) => (s__member(V__ROW1,V__ROW2) => s__part(V__ROW1,V__ROW2))) ) ))).
// CHECK-NEXT: fof(kb_{{[0-9]+}},axiom,(( ! [V__ROW1,V__ROW2] : (((s__instance(V__ROW1,s__Object) & s__instance(V__ROW2,s__Object)) => (s__properPart(V__ROW1,V__ROW2) => s__part(V__ROW1,V__ROW2))) ) ))).
// CHECK-NEXT: % f: (=> (inverse ?REL1 ?REL2) (forall (?A ?B) (<=> (?REL1 ?A ?B) (?REL2 ?B ?A))))
// CHECK-NEXT: % not written: more than one predicate variable
//
// A test's query is the conjecture, its free variables existential.
// CHECK-NEXT: % f: (query (part ?P Bob))
// CHECK-NEXT: fof(query_0,conjecture,(( ? [V__P] : (s__part(V__P,s__Bob) ) ))).
//
// SigmaKEE's cache: the instances of the classes above, the relations' through subrelation, less what is stated.
// CHECK:      fof(kb_{{[0-9]+}},axiom,(s__subclass(s__Human,s__Entity))).
// CHECK:      fof(kb_{{[0-9]+}},axiom,(s__instance(s__Bob,s__Animal))).
// CHECK:      fof(kb_{{[0-9]+}},axiom,(s__instance(s__member__m,s__TransitiveRelation))).
//
// And what SUMOKBtoTPTPKB writes after the KB: ListFn's and partition's axioms.
// CHECK:      % f: (the ListFn and partition axioms SUMOKBtoTPTPKB writes)
// CHECK-NEXT: fof(kb_{{[0-9]+}},axiom,(! [V__X1] : s__instance(s__ListFn__1Fn(V__X1),s__List))).
// CHECK:      fof(kb_{{[0-9]+}},axiom,(! [V__OBJ,V__C,V__C1,V__C2,V__C3,V__C4,V__C5,V__C6,V__C7] : ((s__partition__8(V__C,V__C1,V__C2,V__C3,V__C4,V__C5,V__C6,V__C7) & s__instance(V__OBJ,V__C)) => (s__instance(V__OBJ,V__C1) | s__instance(V__OBJ,V__C2) | s__instance(V__OBJ,V__C3) | s__instance(V__OBJ,V__C4) | s__instance(V__OBJ,V__C5) | s__instance(V__OBJ,V__C6) | s__instance(V__OBJ,V__C7))))).
// CHECK-NEXT: % 242 axioms, 1 conjectures; not written: 17 excluded; 1 higher order; 1 more than one predicate variable;

// VAMPIRE: SZS status Theorem
