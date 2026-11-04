// The confix dialect (include/NixDialect/Confix.td): TrikeShed's Confix scanner, over the LLVM IR of lib/Confix/confix.ll.  The three cases below
// are what TrikeShed's own Syntax.scan0, Syntax.scanCbor0 and Syntax.scanYaml0 give for these three texts; the last two RUN lines check 626 and 762 more
// (inputs/confix-golden.ll, inputs/confix-golden-yaml.ll).
// RUN: mlnix-opt %s | mlnix-opt | FileCheck %s
// RUN: mlnix-opt %s --confix-to-llvm | FileCheck %s --check-prefix=LLVM
// RUN: mlnix-opt %s --confix-to-llvm | mlir-translate --mlir-to-llvmir | llvm-link - lib/Confix/confix.ll -S | lli
// RUN: llvm-link lib/Confix/confix.ll %S/inputs/confix-check.ll %S/inputs/confix-golden.ll -S | lli
// RUN: llvm-link lib/Confix/confix.ll %S/inputs/confix-check.ll %S/inputs/confix-golden-yaml.ll -S | lli

// The lowering declares the entry points of the IR scanner, at the head of the module.
// LLVM-DAG: llvm.func @confix_scan_json(!llvm.ptr, !llvm.ptr) -> i32
// LLVM-DAG: llvm.func @confix_scan_cbor(!llvm.ptr, !llvm.ptr) -> i32
// LLVM-DAG: llvm.func @confix_scan_yaml(!llvm.ptr, !llvm.ptr) -> i32

// CHECK-LABEL: llvm.func @row_is
// CHECK: confix.row %{{.*}}[%{{.*}}] : !llvm.ptr
// LLVM-LABEL: llvm.func @row_is
// LLVM-NOT: confix.
// LLVM: llvm.getelementptr
// LLVM: llvm.load
llvm.func @row_is(%flat: !llvm.ptr, %k: i32, %open: i32, %close: i32, %tag: i32, %depth: i32, %first: i32, %count: i32) -> i32 {
  %o, %c, %t, %d, %f, %n = confix.row %flat[%k] : !llvm.ptr
  %a = llvm.icmp "ne" %o, %open : i32
  %b = llvm.icmp "ne" %c, %close : i32
  %e = llvm.icmp "ne" %t, %tag : i32
  %g = llvm.icmp "ne" %d, %depth : i32
  %h = llvm.icmp "ne" %f, %first : i32
  %i = llvm.icmp "ne" %n, %count : i32
  %ab = llvm.or %a, %b : i1
  %eg = llvm.or %e, %g : i1
  %hi = llvm.or %h, %i : i1
  %abeg = llvm.or %ab, %eg : i1
  %all = llvm.or %abeg, %hi : i1
  %r = llvm.zext %all : i1 to i32
  llvm.return %r : i32
}

// CHECK-LABEL: llvm.func @kid_is
// CHECK: confix.kid %{{.*}}[%{{.*}}] : !llvm.ptr
llvm.func @kid_is(%flat: !llvm.ptr, %at: i32, %want: i32) -> i32 {
  %row = confix.kid %flat[%at] : !llvm.ptr
  %a = llvm.icmp "ne" %row, %want : i32
  %r = llvm.zext %a : i1 to i32
  llvm.return %r : i32
}

llvm.mlir.global internal constant @json_text("{\22a\22:[true,null],\22b\22:-1.5}") {addr_space = 0 : i32}
llvm.mlir.global internal constant @yaml_text("- a: 1\0A\0A- b: 2") {addr_space = 0 : i32}
llvm.mlir.global internal constant @cbor_bytes(dense<[-95, 97, 97, -126, -11, -10]> : tensor<6xi8>) {addr_space = 0 : i32} : !llvm.array<6 x i8>

// CHECK-LABEL: llvm.func @json_case
// CHECK: confix.scan json %{{.*}} into %{{.*}} : !llvm.ptr, !llvm.ptr
// CHECK: confix.size %{{.*}} : !llvm.ptr
// LLVM-LABEL: llvm.func @json_case
// LLVM: llvm.call @confix_scan_json(%{{.*}}, %{{.*}}) : (!llvm.ptr, !llvm.ptr) -> i32
llvm.func @json_case() -> i32 {
  %one = llvm.mlir.constant(1 : i32) : i32
  %n = llvm.mlir.constant(26 : i32) : i32
  %n2 = llvm.mlir.constant(52 : i32) : i32
  %n1 = llvm.mlir.constant(27 : i32) : i32
  %n3 = llvm.mlir.constant(78 : i32) : i32
  %text = llvm.mlir.addressof @json_text : !llvm.ptr
  %cs = llvm.alloca %one x !llvm.struct<(i32, ptr, i32, i32, i32)> : (i32) -> !llvm.ptr
  %cs0 = llvm.getelementptr %cs[0, 0] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(i32, ptr, i32, i32, i32)>
  llvm.store %n, %cs0 : i32, !llvm.ptr
  %cs1 = llvm.getelementptr %cs[0, 1] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(i32, ptr, i32, i32, i32)>
  llvm.store %text, %cs1 : !llvm.ptr, !llvm.ptr
  %flat = llvm.alloca %one x !llvm.struct<(i32, i32, i32, i32, ptr, ptr, ptr, ptr, ptr, ptr)> : (i32) -> !llvm.ptr
  %span = llvm.alloca %n2 x i32 : (i32) -> !llvm.ptr
  %tag = llvm.alloca %n x i8 : (i32) -> !llvm.ptr
  %depth = llvm.alloca %n x i32 : (i32) -> !llvm.ptr
  %start = llvm.alloca %n1 x i32 : (i32) -> !llvm.ptr
  %kid = llvm.alloca %n x i32 : (i32) -> !llvm.ptr
  %work = llvm.alloca %n3 x i32 : (i32) -> !llvm.ptr
  %f3 = llvm.getelementptr %flat[0, 3] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(i32, i32, i32, i32, ptr, ptr, ptr, ptr, ptr, ptr)>
  llvm.store %n, %f3 : i32, !llvm.ptr
  %f4 = llvm.getelementptr %flat[0, 4] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(i32, i32, i32, i32, ptr, ptr, ptr, ptr, ptr, ptr)>
  llvm.store %span, %f4 : !llvm.ptr, !llvm.ptr
  %f5 = llvm.getelementptr %flat[0, 5] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(i32, i32, i32, i32, ptr, ptr, ptr, ptr, ptr, ptr)>
  llvm.store %tag, %f5 : !llvm.ptr, !llvm.ptr
  %f6 = llvm.getelementptr %flat[0, 6] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(i32, i32, i32, i32, ptr, ptr, ptr, ptr, ptr, ptr)>
  llvm.store %depth, %f6 : !llvm.ptr, !llvm.ptr
  %f7 = llvm.getelementptr %flat[0, 7] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(i32, i32, i32, i32, ptr, ptr, ptr, ptr, ptr, ptr)>
  llvm.store %start, %f7 : !llvm.ptr, !llvm.ptr
  %f8 = llvm.getelementptr %flat[0, 8] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(i32, i32, i32, i32, ptr, ptr, ptr, ptr, ptr, ptr)>
  llvm.store %kid, %f8 : !llvm.ptr, !llvm.ptr
  %f9 = llvm.getelementptr %flat[0, 9] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(i32, i32, i32, i32, ptr, ptr, ptr, ptr, ptr, ptr)>
  llvm.store %work, %f9 : !llvm.ptr, !llvm.ptr

  %fault, %at = confix.scan json %cs into %flat : !llvm.ptr, !llvm.ptr
  %total = confix.size %flat : !llvm.ptr
  %zero = llvm.mlir.constant(0 : i32) : i32
  %seven = llvm.mlir.constant(7 : i32) : i32
  %bad_fault = llvm.icmp "ne" %fault, %zero : i32
  %bad_total = llvm.icmp "ne" %total, %seven : i32
  %bad0 = llvm.or %bad_fault, %bad_total : i1
  %acc0 = llvm.zext %bad0 : i1 to i32

  // open close tag depth first count            { "a" [ true null ] "b" -1.5 }
  %k0 = llvm.mlir.constant(0 : i32) : i32
  %k1 = llvm.mlir.constant(1 : i32) : i32
  %k2 = llvm.mlir.constant(2 : i32) : i32
  %k3 = llvm.mlir.constant(3 : i32) : i32
  %k4 = llvm.mlir.constant(4 : i32) : i32
  %k5 = llvm.mlir.constant(5 : i32) : i32
  %k6 = llvm.mlir.constant(6 : i32) : i32
  %c25 = llvm.mlir.constant(25 : i32) : i32
  %c15 = llvm.mlir.constant(15 : i32) : i32
  %c9 = llvm.mlir.constant(9 : i32) : i32
  %c11 = llvm.mlir.constant(11 : i32) : i32
  %c14 = llvm.mlir.constant(14 : i32) : i32
  %c17 = llvm.mlir.constant(17 : i32) : i32
  %c19 = llvm.mlir.constant(19 : i32) : i32
  %c21 = llvm.mlir.constant(21 : i32) : i32
  %c24 = llvm.mlir.constant(24 : i32) : i32
  %r0 = llvm.call @row_is(%flat, %k0, %k0, %c25, %k5, %k0, %k0, %k4) : (!llvm.ptr, i32, i32, i32, i32, i32, i32, i32) -> i32
  %r1 = llvm.call @row_is(%flat, %k1, %k1, %k3, %k4, %k1, %k4, %k0) : (!llvm.ptr, i32, i32, i32, i32, i32, i32, i32) -> i32
  %r2 = llvm.call @row_is(%flat, %k2, %k5, %c15, %k6, %k1, %k4, %k2) : (!llvm.ptr, i32, i32, i32, i32, i32, i32, i32) -> i32
  %r3 = llvm.call @row_is(%flat, %k3, %k6, %c9, %k1, %k2, %k6, %k0) : (!llvm.ptr, i32, i32, i32, i32, i32, i32, i32) -> i32
  %r4 = llvm.call @row_is(%flat, %k4, %c11, %c14, %k0, %k2, %k6, %k0) : (!llvm.ptr, i32, i32, i32, i32, i32, i32, i32) -> i32
  %r5 = llvm.call @row_is(%flat, %k5, %c17, %c19, %k4, %k1, %k6, %k0) : (!llvm.ptr, i32, i32, i32, i32, i32, i32, i32) -> i32
  %r6 = llvm.call @row_is(%flat, %k6, %c21, %c24, %k3, %k1, %k6, %k0) : (!llvm.ptr, i32, i32, i32, i32, i32, i32, i32) -> i32
  // the kid array: 1 2 5 6 | 3 4
  %q0 = llvm.call @kid_is(%flat, %k0, %k1) : (!llvm.ptr, i32, i32) -> i32
  %q1 = llvm.call @kid_is(%flat, %k1, %k2) : (!llvm.ptr, i32, i32) -> i32
  %q2 = llvm.call @kid_is(%flat, %k2, %k5) : (!llvm.ptr, i32, i32) -> i32
  %q3 = llvm.call @kid_is(%flat, %k3, %k6) : (!llvm.ptr, i32, i32) -> i32
  %q4 = llvm.call @kid_is(%flat, %k4, %k3) : (!llvm.ptr, i32, i32) -> i32
  %q5 = llvm.call @kid_is(%flat, %k5, %k4) : (!llvm.ptr, i32, i32) -> i32
  %s1 = llvm.add %acc0, %r0 : i32
  %s2 = llvm.add %s1, %r1 : i32
  %s3 = llvm.add %s2, %r2 : i32
  %s4 = llvm.add %s3, %r3 : i32
  %s5 = llvm.add %s4, %r4 : i32
  %s6 = llvm.add %s5, %r5 : i32
  %s7 = llvm.add %s6, %r6 : i32
  %s8 = llvm.add %s7, %q0 : i32
  %s9 = llvm.add %s8, %q1 : i32
  %s10 = llvm.add %s9, %q2 : i32
  %s11 = llvm.add %s10, %q3 : i32
  %s12 = llvm.add %s11, %q4 : i32
  %s13 = llvm.add %s12, %q5 : i32
  llvm.return %s13 : i32
}

// CHECK-LABEL: llvm.func @cbor_case
// CHECK: confix.scan cbor %{{.*}} into %{{.*}} : !llvm.ptr, !llvm.ptr
// LLVM-LABEL: llvm.func @cbor_case
// LLVM: llvm.call @confix_scan_cbor(%{{.*}}, %{{.*}}) : (!llvm.ptr, !llvm.ptr) -> i32
llvm.func @cbor_case() -> i32 {
  %one = llvm.mlir.constant(1 : i32) : i32
  %n = llvm.mlir.constant(6 : i32) : i32
  %n2 = llvm.mlir.constant(12 : i32) : i32
  %n1 = llvm.mlir.constant(7 : i32) : i32
  %n3 = llvm.mlir.constant(18 : i32) : i32
  %text = llvm.mlir.addressof @cbor_bytes : !llvm.ptr
  %cs = llvm.alloca %one x !llvm.struct<(i32, ptr, i32, i32, i32)> : (i32) -> !llvm.ptr
  %cs0 = llvm.getelementptr %cs[0, 0] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(i32, ptr, i32, i32, i32)>
  llvm.store %n, %cs0 : i32, !llvm.ptr
  %cs1 = llvm.getelementptr %cs[0, 1] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(i32, ptr, i32, i32, i32)>
  llvm.store %text, %cs1 : !llvm.ptr, !llvm.ptr
  %flat = llvm.alloca %one x !llvm.struct<(i32, i32, i32, i32, ptr, ptr, ptr, ptr, ptr, ptr)> : (i32) -> !llvm.ptr
  %span = llvm.alloca %n2 x i32 : (i32) -> !llvm.ptr
  %tag = llvm.alloca %n x i8 : (i32) -> !llvm.ptr
  %depth = llvm.alloca %n x i32 : (i32) -> !llvm.ptr
  %start = llvm.alloca %n1 x i32 : (i32) -> !llvm.ptr
  %kid = llvm.alloca %n x i32 : (i32) -> !llvm.ptr
  %work = llvm.alloca %n3 x i32 : (i32) -> !llvm.ptr
  %f3 = llvm.getelementptr %flat[0, 3] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(i32, i32, i32, i32, ptr, ptr, ptr, ptr, ptr, ptr)>
  llvm.store %n, %f3 : i32, !llvm.ptr
  %f4 = llvm.getelementptr %flat[0, 4] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(i32, i32, i32, i32, ptr, ptr, ptr, ptr, ptr, ptr)>
  llvm.store %span, %f4 : !llvm.ptr, !llvm.ptr
  %f5 = llvm.getelementptr %flat[0, 5] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(i32, i32, i32, i32, ptr, ptr, ptr, ptr, ptr, ptr)>
  llvm.store %tag, %f5 : !llvm.ptr, !llvm.ptr
  %f6 = llvm.getelementptr %flat[0, 6] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(i32, i32, i32, i32, ptr, ptr, ptr, ptr, ptr, ptr)>
  llvm.store %depth, %f6 : !llvm.ptr, !llvm.ptr
  %f7 = llvm.getelementptr %flat[0, 7] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(i32, i32, i32, i32, ptr, ptr, ptr, ptr, ptr, ptr)>
  llvm.store %start, %f7 : !llvm.ptr, !llvm.ptr
  %f8 = llvm.getelementptr %flat[0, 8] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(i32, i32, i32, i32, ptr, ptr, ptr, ptr, ptr, ptr)>
  llvm.store %kid, %f8 : !llvm.ptr, !llvm.ptr
  %f9 = llvm.getelementptr %flat[0, 9] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(i32, i32, i32, i32, ptr, ptr, ptr, ptr, ptr, ptr)>
  llvm.store %work, %f9 : !llvm.ptr, !llvm.ptr

  %fault, %at = confix.scan cbor %cs into %flat : !llvm.ptr, !llvm.ptr
  %total = confix.size %flat : !llvm.ptr
  %zero = llvm.mlir.constant(0 : i32) : i32
  %five = llvm.mlir.constant(5 : i32) : i32
  %bad_fault = llvm.icmp "ne" %fault, %zero : i32
  %bad_total = llvm.icmp "ne" %total, %five : i32
  %bad0 = llvm.or %bad_fault, %bad_total : i1
  %acc0 = llvm.zext %bad0 : i1 to i32

  // open close tag depth first count            a1 61 61 82 f5 f6 : { "a": [ true, null ] }
  %k0 = llvm.mlir.constant(0 : i32) : i32
  %k1 = llvm.mlir.constant(1 : i32) : i32
  %k2 = llvm.mlir.constant(2 : i32) : i32
  %k3 = llvm.mlir.constant(3 : i32) : i32
  %k4 = llvm.mlir.constant(4 : i32) : i32
  %k5 = llvm.mlir.constant(5 : i32) : i32
  %k6 = llvm.mlir.constant(6 : i32) : i32
  %r0 = llvm.call @row_is(%flat, %k0, %k0, %k5, %k5, %k0, %k0, %k2) : (!llvm.ptr, i32, i32, i32, i32, i32, i32, i32) -> i32
  %r1 = llvm.call @row_is(%flat, %k1, %k1, %k2, %k4, %k1, %k2, %k0) : (!llvm.ptr, i32, i32, i32, i32, i32, i32, i32) -> i32
  %r2 = llvm.call @row_is(%flat, %k2, %k3, %k5, %k6, %k1, %k2, %k2) : (!llvm.ptr, i32, i32, i32, i32, i32, i32, i32) -> i32
  %r3 = llvm.call @row_is(%flat, %k3, %k4, %k4, %k1, %k2, %k4, %k0) : (!llvm.ptr, i32, i32, i32, i32, i32, i32, i32) -> i32
  %r4 = llvm.call @row_is(%flat, %k4, %k5, %k5, %k0, %k2, %k4, %k0) : (!llvm.ptr, i32, i32, i32, i32, i32, i32, i32) -> i32
  // the kid array: 1 2 | 3 4
  %q0 = llvm.call @kid_is(%flat, %k0, %k1) : (!llvm.ptr, i32, i32) -> i32
  %q1 = llvm.call @kid_is(%flat, %k1, %k2) : (!llvm.ptr, i32, i32) -> i32
  %q2 = llvm.call @kid_is(%flat, %k2, %k3) : (!llvm.ptr, i32, i32) -> i32
  %q3 = llvm.call @kid_is(%flat, %k3, %k4) : (!llvm.ptr, i32, i32) -> i32
  %s1 = llvm.add %acc0, %r0 : i32
  %s2 = llvm.add %s1, %r1 : i32
  %s3 = llvm.add %s2, %r2 : i32
  %s4 = llvm.add %s3, %r3 : i32
  %s5 = llvm.add %s4, %r4 : i32
  %s6 = llvm.add %s5, %q0 : i32
  %s7 = llvm.add %s6, %q1 : i32
  %s8 = llvm.add %s7, %q2 : i32
  %s9 = llvm.add %s8, %q3 : i32
  llvm.return %s9 : i32
}

// CHECK-LABEL: llvm.func @yaml_case
// CHECK: confix.scan yaml %{{.*}} into %{{.*}} : !llvm.ptr, !llvm.ptr
// LLVM-LABEL: llvm.func @yaml_case
// LLVM: llvm.call @confix_scan_yaml(%{{.*}}, %{{.*}}) : (!llvm.ptr, !llvm.ptr) -> i32
llvm.func @yaml_case() -> i32 {
  %one = llvm.mlir.constant(1 : i32) : i32
  %n = llvm.mlir.constant(14 : i32) : i32
  %room = llvm.mlir.constant(43 : i32) : i32
  %room2 = llvm.mlir.constant(86 : i32) : i32
  %room1 = llvm.mlir.constant(44 : i32) : i32
  %work = llvm.mlir.constant(135 : i32) : i32
  %text = llvm.mlir.addressof @yaml_text : !llvm.ptr
  %cs = llvm.alloca %one x !llvm.struct<(i32, ptr, i32, i32, i32)> : (i32) -> !llvm.ptr
  %cs0 = llvm.getelementptr %cs[0, 0] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(i32, ptr, i32, i32, i32)>
  llvm.store %n, %cs0 : i32, !llvm.ptr
  %cs1 = llvm.getelementptr %cs[0, 1] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(i32, ptr, i32, i32, i32)>
  llvm.store %text, %cs1 : !llvm.ptr, !llvm.ptr
  %flat = llvm.alloca %one x !llvm.struct<(i32, i32, i32, i32, ptr, ptr, ptr, ptr, ptr, ptr)> : (i32) -> !llvm.ptr
  %span = llvm.alloca %room2 x i32 : (i32) -> !llvm.ptr
  %tag = llvm.alloca %room x i8 : (i32) -> !llvm.ptr
  %depth = llvm.alloca %room x i32 : (i32) -> !llvm.ptr
  %start = llvm.alloca %room1 x i32 : (i32) -> !llvm.ptr
  %kid = llvm.alloca %room x i32 : (i32) -> !llvm.ptr
  %workb = llvm.alloca %work x i32 : (i32) -> !llvm.ptr
  %f3 = llvm.getelementptr %flat[0, 3] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(i32, i32, i32, i32, ptr, ptr, ptr, ptr, ptr, ptr)>
  llvm.store %room, %f3 : i32, !llvm.ptr
  %f4 = llvm.getelementptr %flat[0, 4] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(i32, i32, i32, i32, ptr, ptr, ptr, ptr, ptr, ptr)>
  llvm.store %span, %f4 : !llvm.ptr, !llvm.ptr
  %f5 = llvm.getelementptr %flat[0, 5] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(i32, i32, i32, i32, ptr, ptr, ptr, ptr, ptr, ptr)>
  llvm.store %tag, %f5 : !llvm.ptr, !llvm.ptr
  %f6 = llvm.getelementptr %flat[0, 6] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(i32, i32, i32, i32, ptr, ptr, ptr, ptr, ptr, ptr)>
  llvm.store %depth, %f6 : !llvm.ptr, !llvm.ptr
  %f7 = llvm.getelementptr %flat[0, 7] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(i32, i32, i32, i32, ptr, ptr, ptr, ptr, ptr, ptr)>
  llvm.store %start, %f7 : !llvm.ptr, !llvm.ptr
  %f8 = llvm.getelementptr %flat[0, 8] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(i32, i32, i32, i32, ptr, ptr, ptr, ptr, ptr, ptr)>
  llvm.store %kid, %f8 : !llvm.ptr, !llvm.ptr
  %f9 = llvm.getelementptr %flat[0, 9] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(i32, i32, i32, i32, ptr, ptr, ptr, ptr, ptr, ptr)>
  llvm.store %workb, %f9 : !llvm.ptr, !llvm.ptr

  %fault, %at = confix.scan yaml %cs into %flat : !llvm.ptr, !llvm.ptr
  %total = confix.size %flat : !llvm.ptr
  %zero = llvm.mlir.constant(0 : i32) : i32
  %want = llvm.mlir.constant(10 : i32) : i32
  %bad_fault = llvm.icmp "ne" %fault, %zero : i32
  %bad_total = llvm.icmp "ne" %total, %want : i32
  %bad0 = llvm.or %bad_fault, %bad_total : i1
  %acc0 = llvm.zext %bad0 : i1 to i32

  // open close tag depth first count            '- a: 1', an empty line, '- b: 2'  (Kotlin's own result: a value's row opens at the start of its line)
  %k0 = llvm.mlir.constant(0 : i32) : i32
  %k1 = llvm.mlir.constant(1 : i32) : i32
  %k2 = llvm.mlir.constant(2 : i32) : i32
  %k3 = llvm.mlir.constant(3 : i32) : i32
  %k4 = llvm.mlir.constant(4 : i32) : i32
  %k5 = llvm.mlir.constant(5 : i32) : i32
  %k6 = llvm.mlir.constant(6 : i32) : i32
  %k7 = llvm.mlir.constant(7 : i32) : i32
  %k8 = llvm.mlir.constant(8 : i32) : i32
  %k9 = llvm.mlir.constant(9 : i32) : i32
  %k10 = llvm.mlir.constant(10 : i32) : i32
  %k13 = llvm.mlir.constant(13 : i32) : i32
  %r0 = llvm.call @row_is(%flat, %k0, %k0, %k13, %k6, %k0, %k0, %k3) : (!llvm.ptr, i32, i32, i32, i32, i32, i32, i32) -> i32
  %r1 = llvm.call @row_is(%flat, %k1, %k0, %k6, %k5, %k1, %k3, %k2) : (!llvm.ptr, i32, i32, i32, i32, i32, i32, i32) -> i32
  %r2 = llvm.call @row_is(%flat, %k2, %k0, %k0, %k4, %k2, %k5, %k0) : (!llvm.ptr, i32, i32, i32, i32, i32, i32, i32) -> i32
  %r3 = llvm.call @row_is(%flat, %k3, %k0, %k5, %k3, %k2, %k5, %k0) : (!llvm.ptr, i32, i32, i32, i32, i32, i32, i32) -> i32
  %r4 = llvm.call @row_is(%flat, %k4, %k7, %k7, %k5, %k1, %k5, %k1) : (!llvm.ptr, i32, i32, i32, i32, i32, i32, i32) -> i32
  %r5 = llvm.call @row_is(%flat, %k5, %k7, %k7, %k4, %k2, %k6, %k1) : (!llvm.ptr, i32, i32, i32, i32, i32, i32, i32) -> i32
  %r6 = llvm.call @row_is(%flat, %k6, %k7, %k6, %k3, %k3, %k7, %k0) : (!llvm.ptr, i32, i32, i32, i32, i32, i32, i32) -> i32
  %r7 = llvm.call @row_is(%flat, %k7, %k8, %k13, %k5, %k1, %k7, %k2) : (!llvm.ptr, i32, i32, i32, i32, i32, i32, i32) -> i32
  %r8 = llvm.call @row_is(%flat, %k8, %k8, %k8, %k4, %k2, %k9, %k0) : (!llvm.ptr, i32, i32, i32, i32, i32, i32, i32) -> i32
  %r9 = llvm.call @row_is(%flat, %k9, %k8, %k13, %k3, %k2, %k9, %k0) : (!llvm.ptr, i32, i32, i32, i32, i32, i32, i32) -> i32
  // the kid array: 1 4 7 2 3 5 6 8 9
  %q0 = llvm.call @kid_is(%flat, %k0, %k1) : (!llvm.ptr, i32, i32) -> i32
  %q1 = llvm.call @kid_is(%flat, %k1, %k4) : (!llvm.ptr, i32, i32) -> i32
  %q2 = llvm.call @kid_is(%flat, %k2, %k7) : (!llvm.ptr, i32, i32) -> i32
  %q3 = llvm.call @kid_is(%flat, %k3, %k2) : (!llvm.ptr, i32, i32) -> i32
  %q4 = llvm.call @kid_is(%flat, %k4, %k3) : (!llvm.ptr, i32, i32) -> i32
  %q5 = llvm.call @kid_is(%flat, %k5, %k5) : (!llvm.ptr, i32, i32) -> i32
  %q6 = llvm.call @kid_is(%flat, %k6, %k6) : (!llvm.ptr, i32, i32) -> i32
  %q7 = llvm.call @kid_is(%flat, %k7, %k8) : (!llvm.ptr, i32, i32) -> i32
  %q8 = llvm.call @kid_is(%flat, %k8, %k9) : (!llvm.ptr, i32, i32) -> i32
  %s1 = llvm.add %acc0, %r0 : i32
  %s2 = llvm.add %s1, %r1 : i32
  %s3 = llvm.add %s2, %r2 : i32
  %s4 = llvm.add %s3, %r3 : i32
  %s5 = llvm.add %s4, %r4 : i32
  %s6 = llvm.add %s5, %r5 : i32
  %s7 = llvm.add %s6, %r6 : i32
  %s8 = llvm.add %s7, %r7 : i32
  %s9 = llvm.add %s8, %r8 : i32
  %s10 = llvm.add %s9, %r9 : i32
  %s11 = llvm.add %s10, %q0 : i32
  %s12 = llvm.add %s11, %q1 : i32
  %s13 = llvm.add %s12, %q2 : i32
  %s14 = llvm.add %s13, %q3 : i32
  %s15 = llvm.add %s14, %q4 : i32
  %s16 = llvm.add %s15, %q5 : i32
  %s17 = llvm.add %s16, %q6 : i32
  %s18 = llvm.add %s17, %q7 : i32
  %s19 = llvm.add %s18, %q8 : i32
  llvm.return %s19 : i32
}

llvm.func @main() -> i32 {
  %j = llvm.call @json_case() : () -> i32
  %c = llvm.call @cbor_case() : () -> i32
  %y = llvm.call @yaml_case() : () -> i32
  %jc = llvm.add %j, %c : i32
  %r = llvm.add %jc, %y : i32
  llvm.return %r : i32
}
