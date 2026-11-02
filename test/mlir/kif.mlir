// The kif dialect (include/NixDialect/Kif.td) holds KIF terms as pure nodes of a graph region, and the sumo dialect
// (Sumo.td) stands for facts. sumo-to-kif and kif-to-nix take a theory down to the nix dialect, which mlnix evaluates.
// RUN: mlnix-opt %s | mlnix-opt | FileCheck %s
// RUN: mlnix-opt %s --cse | FileCheck %s --check-prefix=CSE
// RUN: mlnix-opt %s --sumo-to-kif | FileCheck %s --check-prefix=KIF
// RUN: mlnix-opt %s --sumo-to-kif --kif-to-nix | FileCheck %s --check-prefix=NIX
// RUN: t=$(mktemp -u).mlir; mlnix-opt %s --sumo-to-kif --kif-to-nix > $t && mlnix run-mlir $t --json | FileCheck %s --check-prefix=EVAL; rc=$?; rm -f $t; exit $rc

// CHECK-LABEL: kif.theory @t
// CHECK: sumo.subclass "Human" "Hominid"
// CHECK: sumo.domain "part" 1 "Object"
// CHECK: sumo.holds "dependsOn" ["a", "b"]
// CHECK: kif.rule %{{.*}} implies %{{.*}}
kif.theory @t {
  sumo.subclass "Human" "Hominid"
  sumo.domain "part" 1 "Object"
  sumo.holds "dependsOn" ["a", "b"]
  %p = kif.atom "p"
  %p2 = kif.atom "p"
  %v = kif.var "?v"
  %l = kif.list(%p, %v)
  %l2 = kif.list(%p2, %v)
  kif.fact %l
  kif.fact %l2
  kif.rule %l implies %l2
}

// Equal terms are one node after cse: one atom p, one list (p ?v), and the two facts read the same value.
// CSE-LABEL: kif.theory @t
// CSE-COUNT-1: kif.atom "p"
// CSE-NOT: kif.atom "p"
// CSE: %[[L:.*]] = kif.list(
// CSE: kif.fact %[[L]]
// CSE: kif.fact %[[L]]

// sumo-to-kif: a relation is a fact of a list of atoms.
// KIF: %{{.*}} = kif.atom "subclass"
// KIF: %{{.*}} = kif.atom "Human"
// KIF: %{{.*}} = kif.atom "domain"
// KIF: %{{.*}} = kif.atom "1"
// KIF-NOT: sumo.

// kif-to-nix: a nix.expr of { facts, rules } built from lists of strings.
// NIX: nix.expr @t
// NIX: nix.str "subclass"
// NIX: nix.str "=>"
// NIX: nix.attrs
// NIX-NOT: kif.

// The evaluator reads it back: the facts in the order of the theory, then the rule.
// EVAL: {"facts":
// EVAL-SAME: "subclass","Human","Hominid"
// EVAL-SAME: "domain","part","1","Object"
// EVAL-SAME: "dependsOn","a","b"
// EVAL-SAME: "p","?v"
// EVAL-SAME: "rules":
// EVAL-SAME: "=>"
