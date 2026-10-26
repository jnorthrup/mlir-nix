// Calls of known primops become ops of their continent dialect; everything
// the rewrite does not understand is left alone.
// RUN: mlnix-opt %s --nix-prims | FileCheck %s

// A global alias, the `__`-prefixed operator form and builtins.<name> all
// resolve to the same primop.
// CHECK-LABEL: nix.expr @spellings
nix.expr @spellings {
  %b = nix.builtin "builtins"
  %sel = nix.select %b ["add"]
  %add = nix.builtin "__add"
  %one = nix.int 1
  %two = nix.int 2
  %x = nix.apply %sel(%one, %two)
  %y = nix.apply %add(%one, %two)
  %t = nix.builtin "toString"
  %z = nix.apply %t(%one)
  %r = nix.list [%x, %y, %z]
  nix.return %r
}
// CHECK-NOT: nix.apply
// CHECK-NOT: nix.builtin "builtins"
// CHECK: nixnum.add(
// CHECK: nixnum.add(
// CHECK: nixstr.to_string(

// A partial application is a value, not a call.
// CHECK-LABEL: nix.expr @partial
nix.expr @partial {
  %add = nix.builtin "__add"
  %one = nix.int 1
  %p = nix.apply %add(%one)
  nix.return %p
}
// CHECK: nix.apply
// CHECK-NOT: nixnum.add

// Surplus arguments are applied to the result of the saturated call.
// CHECK-LABEL: nix.expr @oversaturated
nix.expr @oversaturated {
  %h = nix.builtin "__head"
  %one = nix.int 1
  %l = nix.list [%one]
  %f = nix.int 7
  %r = nix.apply %h(%l, %f)
  nix.return %r
}
// CHECK: [[H:%.*]] = nixlist.head(
// CHECK: nix.apply [[H]](

// `builtins` shadowed by a user binding, a default (`or`), and a computed key
// are not the primop and must not be rewritten.
// CHECK-LABEL: nix.expr @not_builtins
nix.expr @not_builtins {
  %user = nix.attrs ["add"](%f)
  %f = nix.builtin "map"
  %sel = nix.select %user ["add"]
  %one = nix.int 1
  %two = nix.int 2
  %r = nix.apply %sel(%one, %two)
  nix.return %r
}
// CHECK-NOT: nixnum.add
// CHECK: nix.apply

// A computed component or a default keeps the select a select.
// CHECK-LABEL: nix.expr @dynamic_key
nix.expr @dynamic_key {
  %b = nix.builtin "builtins"
  %k = nix.str "add"
  %sel = nix.select %b [%k]
  %one = nix.int 1
  %two = nix.int 2
  %r = nix.apply %sel(%one, %two)
  nix.return %r
}
// CHECK-NOT: nixnum.add
// CHECK: nix.select
