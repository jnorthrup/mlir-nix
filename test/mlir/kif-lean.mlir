// The chase's proofs as one Lean theorem: `mlnix-kif --chase --lean` (lib/Dialect/KifLean.cpp) writes lean4export's format,
// which the Lean toolchain's kernels read without elaborating.  The theorem has no axiom: the asserted facts, the rules and
// the ontology's subclass edges its proofs use are hypotheses, and each derived fact is a let of its proof, which a kernel
// checks against the fact.  scripts/kif-lean-check.py decodes what it claims and compares that with the chase's dump: the
// same asserted facts, the same derived facts, each by the dump's rule from the dump's premises in order.
// RUN: d=%S/../kif; t=$(mktemp -d); mlnix-kif --chase --lean $t/c.ndjson --ontology $d/chase-onto.kif $d/certify-cases.kif && mlnix-kif --chase --dump --ontology $d/chase-onto.kif $d/certify-cases.kif > $t/c.dump && python3 %S/../../scripts/kif-lean-check.py $t/c.ndjson $t/c.dump --rules | FileCheck %s; s=$?; rm -rf $t; exit $s
//
// In pieces (--lean-piece 5: theorems of at most 5 lets, each with the hypotheses its lets use), the same claims: the lets
// d.0 .. d.38 through the pieces in order, and each fact a piece takes from an earlier one (an import) what that piece's let
// claims.
// RUN: d=%S/../kif; t=$(mktemp -d); mlnix-kif --chase --lean $t/c5.ndjson --lean-piece 5 --ontology $d/chase-onto.kif $d/certify-cases.kif && mlnix-kif --chase --dump --ontology $d/chase-onto.kif $d/certify-cases.kif > $t/c.dump && python3 %S/../../scripts/kif-lean-check.py $t/c5.ndjson $t/c.dump | FileCheck %s --check-prefix=PIECES; s=$?; rm -rf $t; exit $s
//
// Negation as failure is the closed world of a stratum, not a proof from the facts: a fact derived by a (not ..) rule is an
// error, as is --lean without the chase.
// RUN: d=%S/../kif; not mlnix-kif --chase --lean /dev/null --ontology $d/chase-onto.kif $d/chase-cases.kif 2>&1 | FileCheck %s --check-prefix=NAF
// RUN: not mlnix-kif --lean /dev/null %S/../kif/certify-cases.kif 2>&1 | FileCheck %s --check-prefix=USAGE
// RUN: not mlnix-kif --chase --lean-piece 5 %S/../kif/certify-cases.kif 2>&1 | FileCheck %s --check-prefix=USAGE-PIECE
//
// Where the kernels are on PATH (elan's Lean 4.36 toolchain: Kali), nanoda_bin, con-leche and con-ron each accept the theorem
// and reject three copies with one proof broken; so do they the pieces.
// RUN: [lean-checkers] d=%S/../kif; t=$(mktemp -d); mlnix-kif --chase --lean $t/c.ndjson --ontology $d/chase-onto.kif $d/certify-cases.kif && mlnix-kif --chase --dump --ontology $d/chase-onto.kif $d/certify-cases.kif > $t/c.dump && python3 %S/../../scripts/kif-lean-kernels.py $t/c.ndjson $t/c.dump --controls | FileCheck %s --check-prefix=KERNEL; s=$?; rm -rf $t; exit $s
// RUN: [lean-checkers] d=%S/../kif; t=$(mktemp -d); mlnix-kif --chase --lean $t/c5.ndjson --lean-piece 5 --ontology $d/chase-onto.kif $d/certify-cases.kif && mlnix-kif --chase --dump --ontology $d/chase-onto.kif $d/certify-cases.kif > $t/c.dump && python3 %S/../../scripts/kif-lean-kernels.py $t/c5.ndjson $t/c.dump --controls | FileCheck %s --check-prefix=KERNEL; s=$?; rm -rf $t; exit $s

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

// PIECES: c5.ndjson: 8 theorems, no axiom, no constant; 204 hypotheses in all (87 atoms, 38 facts, 19 rules, 5 ontology edges, 2 imports); 39 lets; the deepest theorem 40 binders and lets
// PIECES-NEXT: agrees with the dump: 22 asserted facts used, 39 derived facts, each by the dump's rule from the dump's premises, each import what an earlier piece's let proves

// NAF: error: 'kif.derived' op is derived by rule allowed#{{[0-9]+}}, whose (not ..) premise is negation as failure
// USAGE: mlnix-kif: --lean writes the chase's proofs: give --chase too
// USAGE-PIECE: mlnix-kif: --lean-piece divides what --lean writes: give --lean too

// KERNEL: control premise: {{.*}}: premise {{[0-9]+}} is a proof of
// KERNEL: control binding: {{.*}}: its rule's first variable is bound to
// KERNEL: control statement: the proof of {{.*}}, the last let, claims
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
