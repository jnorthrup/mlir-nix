// Select / has_attr paths mix literal components (attributes) with computed
// ones (operands); the printed form round-trips and the verifier checks that
// computed components and operands agree.
// RUN: mlnix-opt %s | mlnix-opt | FileCheck %s

// CHECK-LABEL: nix.expr @paths
nix.expr @paths {
  %s = nix.attrs [](  )
  %k = nix.str "k"
  %d = nix.int 0
  // CHECK: nix.select %{{.*}}["a"]
  %0 = nix.select %s ["a"]
  // CHECK: nix.select %{{.*}}["a", %{{.*}}, "c"] or %{{.*}}
  %1 = nix.select %s ["a", %k, "c"] or %d
  // CHECK: nix.has_attr %{{.*}}[%{{.*}}, "b"]
  %2 = nix.has_attr %s [%k, "b"]
  nix.return %0
}
