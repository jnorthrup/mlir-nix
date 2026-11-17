// The chase's proofs as one Lean theorem: `mlnix-kif --chase --lean` (lib/Dialect/KifLean.cpp) writes lean4export's format,
// which the Lean toolchain's kernels read without elaborating.  The theorem has no axiom: the asserted facts, the rules and
// the ontology's subclass edges its proofs use are hypotheses, each derived fact a let of its proof, and its conclusion all of
// them.  scripts/kif-lean-check.py decodes what it states and compares that with the chase's dump: the same asserted facts,
// the same derived facts, each by the dump's rule from the dump's premises in order.
// RUN: d=%S/../kif; t=$(mktemp -d); mlnix-kif --chase --lean $t/c.ndjson --ontology $d/chase-onto.kif $d/certify-cases.kif && mlnix-kif --chase --dump --ontology $d/chase-onto.kif $d/certify-cases.kif > $t/c.dump && python3 %S/../../scripts/kif-lean-check.py $t/c.ndjson $t/c.dump --rules | FileCheck %s; s=$?; rm -rf $t; exit $s
//
// Negation as failure is the closed world of a stratum, not a proof from the facts: a fact derived by a (not ..) rule is an
// error, as is --lean without the chase.
// RUN: d=%S/../kif; not mlnix-kif --chase --lean /dev/null --ontology $d/chase-onto.kif $d/chase-cases.kif 2>&1 | FileCheck %s --check-prefix=NAF
// RUN: not mlnix-kif --lean /dev/null %S/../kif/certify-cases.kif 2>&1 | FileCheck %s --check-prefix=USAGE
//
// Where the kernels are on PATH (elan's Lean 4.36 toolchain: Kali), nanoda_bin, con-leche and con-ron each accept the theorem
// and reject three copies with one proof broken.
// RUN: [lean-checkers] d=%S/../kif; t=$(mktemp -d); mlnix-kif --chase --lean $t/c.ndjson --ontology $d/chase-onto.kif $d/certify-cases.kif && mlnix-kif --chase --dump --ontology $d/chase-onto.kif $d/certify-cases.kif > $t/c.dump && python3 %S/../../scripts/kif-lean-kernels.py $t/c.ndjson $t/c.dump --controls | FileCheck %s --check-prefix=KERNEL; s=$?; rm -rf $t; exit $s

// CHECK: c.ndjson: one theorem, no axiom, no constant; 107 hypotheses (52 atoms, 24 facts, 15 rules, 5 ontology edges); 39 lets
// CHECK-NEXT: r.1: forall ?x: (=> (instance ?x Animal) (animal ?x))
// CHECK-NEXT: r.2: forall ?x ?o: (=> (and (instance ?x Mammal) (owns ?o ?x)) (petOwner ?o))
// CHECK-NEXT: r.3: forall ?x ?y ?z: (=> (and (likes ?x ?y) (likes ?y ?z)) (fof ?x ?z))
// CHECK:      r.9: forall ?a ?b: (=> (and (pair ?a ?b) (equal ?a ?b)) (same ?a))
// CHECK-NEXT: r.10: forall ?y ?x: (=> (parent ?x ?y) (hasChild ?x))
// CHECK-NEXT: r.11: forall ?x: (=> (and (flag on) (person ?x)) (flagged ?x))
// CHECK-NEXT: r.12: forall ?r ?z: (=> (and (?r p1 ?z) (person ?z)) (touches ?r ?z))
// CHECK-NEXT: r.13: forall ?p: (=> (holds ?p) (believed ?p))
// CHECK-NEXT: r.14: forall ?x ?s: (=> (says ?x ?s) (said ?s ?x))
// CHECK-NEXT: r.15: forall ?x ?y: (=> (name ?x ?y) (named ?y))
// CHECK-NEXT: agrees with the dump: 24 asserted facts, 39 derived facts, each by the dump's rule from the dump's premises

// NAF: error: 'kif.derived' op is derived by rule allowed#{{[0-9]+}}, whose (not ..) premise is negation as failure
// USAGE: mlnix-kif: --lean writes the chase's proofs: give --chase too

// KERNEL: control premise: (petOwner ann): premise 2 is a proof of
// KERNEL: control binding: (animal rex): its rule's first variable is bound to
// KERNEL: control statement: the proof of (animal rex) claims
// KERNEL: nanoda_bin certificate accepted
// KERNEL: con-leche  certificate accepted
// KERNEL: con-ron    certificate accepted
// KERNEL: nanoda_bin premise     rejected
// KERNEL: con-leche  premise     rejected
// KERNEL: con-ron    premise     rejected
// KERNEL: nanoda_bin binding     rejected
// KERNEL: con-leche  binding     rejected
// KERNEL: con-ron    binding     rejected
// KERNEL: nanoda_bin statement   rejected
// KERNEL: con-leche  statement   rejected
// KERNEL: con-ron    statement   rejected
