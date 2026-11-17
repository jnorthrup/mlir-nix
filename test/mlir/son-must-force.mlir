// son.release with the schedule's must-force set (lib/Dialect/SonDialect.cpp, MustForce): a value forced on every path on
// which the call returns is computed by then, so a cell of it reads nothing and the closure of the cells over operands stops
// at it.  The input is `mlnix emit-mlir` of
//   let k = x: x + 1;
//       f = x: let a = x.p; b = a + 1; in
//              if a == null then throw "no" else { inherit b; l = [ a ]; n = k b; };
//   in f { p = 1; }
// Worked by hand.  In f, the if forces its condition a == null, so a and, through the select, x; its arms are a throw (no path
// through it returns) and the set, which forces nothing.  So a is a value by the return: [ a ] and b = a + 1 keep a as it is
// and not x, which is released (without the must-force set son.release kept x).  b, [ a ] and k b are attribute values
// passed on unforced: kept, with their operands 1 and k; "no" is the throw's operand.  In the expression, f forces its
// argument on every path (f's own must-force set holds x), so the call f { p = 1; } forces the set: it is released, and only
// its value 1, an attribute passed on, is kept (without the must-force set the set was kept too).
// RUN: mlnix-opt %s --nix-defer --son-release | FileCheck %s
// RUN: mlnix-opt %s --nix-defer --son-release | mlnix-opt | FileCheck %s

nix.expr @expr1 {
  %0 = nix.null
  %1 = nix.lambda attributes {arg_name = "x", name = "k"} {
  ^bb0(%arg0: !nix.value):
    %6 = nix.int 1
    %7 = nix.concat_strings %arg0, %6
    nix.return %7
  }
  %2 = nix.lambda attributes {arg_name = "x", name = "f"} {
  ^bb0(%arg0: !nix.value):
    %6 = nix.select %arg0 ["p"]
    %7 = nix.int 1
    %8 = nix.concat_strings %6, %7
    %9 = nix.eq %6, %0
    %10 = nix.str "no"
    %11 = nixerr.throw(%10 : !trikeshed.join<!trikeshed.series<i8>, !trikeshed.series<!trikeshed.series<i8>>>)
    %12 = nix.list[%6]
    %13 = nix.apply %1 : (!nix.value) -> !nix.value(%8)
    %14 = nix.attrs ["b", "l", "n"](%8, %12 : !trikeshed.series<!nix.value>, %13)
    %15 = nix.if %9 then %11 else %14 : !trikeshed.series2<i32, !nix.value>
    nix.return %15
  }
  %3 = nix.int 1
  %4 = nix.attrs ["p"](%3)
  %5 = nix.apply %2 : (!nix.value) -> !nix.value(%4 : !trikeshed.series2<i32, !nix.value>)
  nix.return %5
}

// CHECK-LABEL: nix.expr @expr1
// CHECK-NEXT:    %[[NULL:.*]] = nix.null
// CHECK-NEXT:    %[[K:.*]] = son.defer @bodies::@row1()
// CHECK-NEXT:    %[[F:.*]] = son.defer @bodies::@row0(%[[NULL]], %[[K]] : !nix_fn)
// CHECK-NEXT:    %[[ONE:.*]] = nix.int 1
// CHECK-NEXT:    %[[SET:.*]] = nix.attrs ["p"](%[[ONE]])
// CHECK-NEXT:    %[[CALL:.*]] = nix.apply %[[F]] : !nix_fn(%[[SET]] : !nix_attrs)
// CHECK-NEXT:    son.release(%[[NULL]], %[[K]] : !nix_fn, %[[ONE]])
// CHECK-NEXT:    nix.return %[[CALL]]

// CHECK:       son.body @row0 captures 2 lambda {arg_name = "x", name = "f"
// CHECK-NEXT:  ^bb0(%[[CNULL:.*]]: !nix.value, %[[CK:.*]]: !nix.value, %[[X:.*]]: !nix.value):
// CHECK-NEXT:    %[[A:.*]] = nix.select %[[X]] ["p"]
// CHECK-NEXT:    %[[I1:.*]] = nix.int 1
// CHECK-NEXT:    %[[B:.*]] = nix.concat_strings %[[A]], %[[I1]]
// CHECK-NEXT:    %[[TEST:.*]] = nix.eq %[[A]], %[[CNULL]]
// CHECK-NEXT:    %[[NO:.*]] = nix.str "no"
// CHECK-NEXT:    %[[THROW:.*]] = nixerr.throw(%[[NO]] : !nix_string)
// CHECK-NEXT:    %[[L:.*]] = nix.list[%[[A]]]
// CHECK-NEXT:    %[[N:.*]] = nix.apply %[[CK]](%[[B]])
// CHECK-NEXT:    %[[S:.*]] = nix.attrs ["b", "l", "n"](%[[B]], %[[L]] : !nix_list, %[[N]])
// CHECK-NEXT:    %[[R:.*]] = nix.if %[[TEST]] then %[[THROW]] else %[[S]] : !nix_attrs
// CHECK-NEXT:    son.release(%[[CK]], %[[A]], %[[I1]], %[[B]], %[[NO]] : !nix_string, %[[L]] : !nix_list, %[[N]])
// CHECK-NEXT:    nix.return %[[R]]

// CHECK:       son.body @row1 captures 0 lambda {arg_name = "x", name = "k"
// CHECK:         son.release()
