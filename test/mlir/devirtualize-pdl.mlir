// The PDL formulation of primop devirtualization (MLNIX_DEVIRT=pdl, and the
// variant that only runs the matcher on nix.apply, pdl-apply) must produce
// exactly the IR of the C++ pattern, locations included.
// RUN: diff <(mlnix-opt %s --nix-prims --mlir-print-debuginfo --mlir-print-local-scope) <(MLNIX_DEVIRT=pdl mlnix-opt %s --nix-prims --mlir-print-debuginfo --mlir-print-local-scope)
// RUN: diff <(mlnix-opt %s --nix-prims --mlir-print-debuginfo --mlir-print-local-scope) <(MLNIX_DEVIRT=pdl-apply mlnix-opt %s --nix-prims --mlir-print-debuginfo --mlir-print-local-scope)
// RUN: MLNIX_DEVIRT=pdl mlnix-opt %s --nix-prims --mlir-print-debuginfo --mlir-print-local-scope | FileCheck %s

// Every spelling of the callee, a callee shared by two calls (the evaluator
// shares one `nix.builtin` per name), and the location of the created ops.
// CHECK-LABEL: nix.expr @spellings
nix.expr @spellings {
  %b = nix.builtin "builtins"
  %sel = nix.select %b ["add"]
  %dunder = nix.select %b ["__add"] loc("t.nix":3:7)
  %add = nix.builtin "__add"
  %one = nix.int 1
  %two = nix.int 2
  %x = nix.apply %sel(%one, %two) loc("t.nix":1:1)
  %y = nix.apply %add(%one, %two) loc("t.nix":2:1)
  %y2 = nix.apply %add(%two, %one) loc("t.nix":2:9)
  %z = nix.apply %dunder(%one, %two) loc("t.nix":3:1)
  %t = nix.builtin "toString"
  %w = nix.apply %t(%one)
  %ts = nix.select %b ["toString"]
  %w2 = nix.apply %ts(%two)
  %r = nix.list [%x, %y, %y2, %z, %w, %w2]
  nix.return %r
}
// CHECK-NOT: nix.apply
// CHECK-NOT: nix.builtin
// CHECK-NOT: nix.select
// CHECK: nixnum.add({{.*}}) loc("t.nix":1:1)
// CHECK: nixnum.add({{.*}}) loc("t.nix":2:1)
// CHECK: nixnum.add({{.*}}) loc("t.nix":2:9)
// CHECK: nixnum.add({{.*}}) loc("t.nix":3:1)
// CHECK: nixstr.to_string(
// CHECK: nixstr.to_string(

// A partial application is a value, not a call (also: no arguments at all).
// CHECK-LABEL: nix.expr @partial
nix.expr @partial {
  %add = nix.builtin "__add"
  %one = nix.int 1
  %p = nix.apply %add(%one)
  %q = nix.apply %add()
  %r = nix.list [%p, %q]
  nix.return %r
}
// CHECK: nix.apply
// CHECK: nix.apply
// CHECK-NOT: nixnum.add

// Surplus arguments are applied to the result of the saturated call: one, and
// two (the `rest` range of the pattern is empty, resp. not).
// CHECK-LABEL: nix.expr @oversaturated
nix.expr @oversaturated {
  %h = nix.builtin "__head"
  %one = nix.int 1
  %l = nix.list [%one]
  %f = nix.int 7
  %g = nix.int 8
  %r1 = nix.apply %h(%l, %f)
  %r2 = nix.apply %h(%l, %f, %g)
  %r = nix.list [%r1, %r2]
  nix.return %r
}
// CHECK: [[H1:%.*]] = nixlist.head(
// CHECK: nix.apply [[H1]](
// CHECK: [[H2:%.*]] = nixlist.head(
// CHECK: nix.apply [[H2]](

// `builtins` shadowed by a user binding, a default (`or`), a computed key, a
// two-component path, an unknown name and a callee that is a parameter are not
// the primop and must not be rewritten.
// CHECK-LABEL: nix.expr @not_primops
nix.expr @not_primops {
  %user = nix.attrs ["add"](%f)
  %f = nix.builtin "map"
  %sel = nix.select %user ["add"]
  %b = nix.builtin "builtins"
  %dflt = nix.int 0
  %withdef = nix.select %b ["add"] or %dflt
  %k = nix.str "add"
  %dyn = nix.select %b [%k]
  %two = nix.select %b ["lib", "add"]
  %nope = nix.select %b ["nope"]
  %nope2 = nix.builtin "nope"
  %one = nix.int 1
  %a1 = nix.apply %sel(%one, %one)
  %a2 = nix.apply %withdef(%one, %one)
  %a3 = nix.apply %dyn(%one, %one)
  %a4 = nix.apply %two(%one, %one)
  %a5 = nix.apply %nope(%one, %one)
  %a6 = nix.apply %nope2(%one, %one)
  %lam = nix.lambda {
  ^bb0(%arg0: !nix.value):
    %a7 = nix.apply %arg0(%one, %one)
    nix.return %a7
  }
  %r = nix.list [%a1, %a2, %a3, %a4, %a5, %a6, %lam]
  nix.return %r
}
// CHECK-NOT: nixnum.add
// CHECK-COUNT-6: nix.apply
// CHECK: nix.apply %arg0
