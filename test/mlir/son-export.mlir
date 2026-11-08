// son-export writes the module as JSON for an executor in another runtime (the Graal arm: graal/, a Truffle interpreter).
// RUN: mlnix-opt %s --nix-defer --son-export -o /dev/null | FileCheck %s

// One op per object; a value is a number, given at its first sight; a primop names its builtin; source positions are dropped.
// CHECK: {"module":[{"op":"nix.expr","res":[],"ins":[],"types":[],"attrs":{"sym_name":"e"},"regions":[
// CHECK-SAME: [{"args":[],"ops":[
// CHECK-SAME: {"op":"nix.int","res":[0],"ins":[],"types":["!nix.value"],"attrs":{"value":2},"regions":[]}
// CHECK-SAME: {"op":"son.defer","res":[1],"ins":[0],"types":["(!nix.value) -> !nix.value"],"attrs":{"row":["bodies","row0"]},"regions":[]}
// CHECK-SAME: {"op":"nix.str","res":[2],"ins":[],"types":["!trikeshed.join<!trikeshed.series<i8>, !trikeshed.series<!trikeshed.series<i8>>>"],"attrs":{"value":"a\"b\n"},"regions":[]}
// CHECK-SAME: {"op":"nix.attrs","res":[3],"ins":[2],"types":["!trikeshed.series2<i32, !nix.value>"],"attrs":{"names":["k"],"operandSegmentSizes":[1, 0, 0]},"regions":[]}
// CHECK-SAME: {"op":"nixattr.attr_names","res":[4],"ins":[3],"types":["!trikeshed.series<!nix.value>"],"attrs":{"prim_key":"__attrNames"},"regions":[]}
// CHECK-SAME: {"op":"nix.select","res":[5],"ins":[3, 2],"types":["!nix.value"],"attrs":{"operandSegmentSizes":[1, 1, 0],"path":["k", null]
// CHECK-SAME: {"op":"nix.apply","res":[6],"ins":[1, 4],"types":["!nix.value"],"attrs":{},"regions":[]}
// CHECK-SAME: {"op":"nix.return","res":[],"ins":[6],"types":[],"attrs":{},"regions":[]}]}]]}
// The pool: a body's block takes its captures, then the argument; `lambda` keeps the lambda's properties.
// CHECK-SAME: {"op":"son.pool","res":[],"ins":[],"types":[],"attrs":{"sym_name":"bodies"},"regions":[
// CHECK-SAME: [{"args":[],"ops":[
// CHECK-SAME: {"op":"son.body","res":[],"ins":[],"types":[],"attrs":{"captures":1,"lambda":{"arg_name":"x"},"sym_name":"row0"},"regions":[
// CHECK-SAME: [{"args":[7, 8],"ops":[
// CHECK-SAME: {"op":"nix.concat_strings","res":[9],"ins":[7, 8]
nix.expr @e {
  %n = nix.int 2
  %f = nix.lambda (%n) attributes {arg_name = "x"} {
  ^bb0(%x: !nix.value):
    %s = nix.concat_strings %n, %x
    nix.return %s
  }
  %str = nix.str "a\"b\n"
  %set = nix.attrs ["k"](%str : !trikeshed.join<!trikeshed.series<i8>, !trikeshed.series<!trikeshed.series<i8>>>)
  %names = nixattr.attr_names(%set : !trikeshed.series2<i32, !nix.value>)
  %sel = nix.select %set : !trikeshed.series2<i32, !nix.value> ["k", %str : !trikeshed.join<!trikeshed.series<i8>, !trikeshed.series<!trikeshed.series<i8>>>]
  %r = nix.apply %f : (!nix.value) -> !nix.value(%names : !trikeshed.series<!nix.value>)
  nix.return %r
}
