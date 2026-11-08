// The kinds a value's maker fixes are TrikeShed types (docs/PRELOAD-DIALECTS.md, step 1): a list is Series<!nix.value>, an attribute
// set Series2<i32, !nix.value>, a string Join<Series<i8>, Series<Series<i8>>>, a function (!nix.value) -> !nix.value.  A typed result prints no type; a typed operand prints
// its type at the use.  A path is a CharSeries (Series<i8>) with no context.  A constant folded from an op that fixes no kind (`+`) keeps !nix.value; an interpolation folds to a string.
// RUN: mlnix-opt %s | FileCheck %s
// RUN: mlnix-opt %s | mlnix-opt | FileCheck %s
// RUN: mlnix-opt %s -canonicalize | FileCheck %s --check-prefix=FOLD
// RUN: mlnix-opt %s --nix-defer | mlnix-opt | FileCheck %s --check-prefix=DEFER
// RUN: mlnix-opt %s --nix-prims | mlnix-opt | FileCheck %s --check-prefix=PRIM
// A primop whose declaration fixes its result's kind (NixPrims.irdl.mlir, `irdl.is`) makes that type, also when nix-prims makes
// it from a call: __attrNames makes a list.

// CHECK-DAG: !char_series = !trikeshed.series<i8>
// CHECK-DAG: !nix_attrs = !trikeshed.series2<i32, !nix.value>
// CHECK-DAG: !nix_fn = (!nix.value) -> !nix.value
// CHECK-DAG: !nix_list = !trikeshed.series<!nix.value>
// CHECK-DAG: !nix_string = !trikeshed.join<!char_series, !trikeshed.series<!char_series>>
nix.expr @kinds {
  // CHECK: %[[A:.*]] = nix.str "a"{{$}}
  %a = nix.str "a"
  %b = nix.str "b"
  // CHECK: %[[I:.*]] = nix.interpolate %[[A]] : !nix_string, %{{.*}} : !nix_string{{$}}
  %i = nix.interpolate %a : !trikeshed.join<!trikeshed.series<i8>, !trikeshed.series<!trikeshed.series<i8>>>, %b : !trikeshed.join<!trikeshed.series<i8>, !trikeshed.series<!trikeshed.series<i8>>>
  // CHECK: %[[P:.*]] = nix.concat_strings %[[A]] : !nix_string, %{{.*}} : !nix_string{{$}}
  %p = nix.concat_strings %a : !trikeshed.join<!trikeshed.series<i8>, !trikeshed.series<!trikeshed.series<i8>>>, %b : !trikeshed.join<!trikeshed.series<i8>, !trikeshed.series<!trikeshed.series<i8>>>
  // CHECK: %[[PATH:.*]] = nix.path "/tmp/kinds"{{$}}
  %path = nix.path "/tmp/kinds"
  // CHECK: %[[L:.*]] = nix.list[%[[I]] : !nix_string, %[[P]], %[[PATH]] : !char_series]
  %l = nix.list [%i : !trikeshed.join<!trikeshed.series<i8>, !trikeshed.series<!trikeshed.series<i8>>>, %p, %path : !trikeshed.series<i8>]
  // CHECK: %[[L2:.*]] = nix.concat_lists %[[L]] : !nix_list, %[[L]] : !nix_list
  %l2 = nix.concat_lists %l : !trikeshed.series<!nix.value>, %l : !trikeshed.series<!nix.value>
  // CHECK: %[[S:.*]] = nix.attrs ["l"](%[[L2]] : !nix_list)
  %s = nix.attrs ["l"](%l2 : !trikeshed.series<!nix.value>)
  // CHECK: %[[U:.*]] = nix.update %[[S]] : !nix_attrs, %[[S]] : !nix_attrs
  %u = nix.update %s : !trikeshed.series2<i32, !nix.value>, %s : !trikeshed.series2<i32, !nix.value>
  // A lambda body reads the typed set through its capture: nix-defer makes the capture a !nix.value block argument.
  %f = nix.lambda attributes {arg_name = "x"} {
  ^bb0(%x: !nix.value):
    %v = nix.select %u : !trikeshed.series2<i32, !nix.value> ["l"]
    nix.return %v
  }
  // CHECK: %[[N:.*]] = nixattr.attr_names(%[[U]] : !nix_attrs)
  %names = nixattr.attr_names(%u : !trikeshed.series2<i32, !nix.value>)
  // CHECK: nixlist.head(%[[N]] : !nix_list)
  %h = nixlist.head(%names : !trikeshed.series<!nix.value>)
  %an = nix.builtin "__attrNames"
  %call = nix.apply %an(%u : !trikeshed.series2<i32, !nix.value>)
  %len = nixlist.length(%call)
  // CHECK: %[[R:.*]] = nix.apply %{{.*}} : !nix_fn(%[[U]] : !nix_attrs)
  %r = nix.apply %f : (!nix.value) -> !nix.value(%u : !trikeshed.series2<i32, !nix.value>)
  // CHECK: nix.return %[[U]] : !nix_attrs
  nix.return %u : !trikeshed.series2<i32, !nix.value>
}

// FOLD-DAG: nix.str "ab"{{$}}
// FOLD-DAG: nix.str "ab" : !nix.value{{$}}
// FOLD-NOT: nix.interpolate
// FOLD-NOT: nix.concat_strings

// PRIM: nixattr.attr_names(
// PRIM: %[[C:.*]] = nixattr.attr_names(%{{.*}} : !nix_attrs)
// PRIM-NEXT: nixlist.length(%[[C]] : !nix_list)

// DEFER: %[[D:.*]] = son.defer @bodies::@row0(%{{.*}} : !nix_attrs)
// DEFER: nix.apply %[[D]] : !nix_fn(
// DEFER: son.body @row0 captures 1
// DEFER: ^bb0(%[[C:.*]]: !nix.value, %{{.*}}: !nix.value):
// DEFER: nix.select %[[C]] ["l"]
