// confix.bands: the Nix delimiter scan (the frontend's Bands, Nix/Confix.h), the body of the op in
// lowered/nixfrontend/ConfixScan.mlir (compiled at build time, linked into MLIRNix as confix.ll's scanner).  The record
// is Confix.td's: src, n, start, rooted, span, kind, stmts, ends, rows, nends, rowCap, endCap; the status 0 balanced,
// 1 not, 2 room.  The cases below are what the C++ Scanner gave for these texts (span open << 32 | close, stmts
// first << 32 | count into ends):
//   { a=1; b="x"; }  rows 2: the brace 0..14 with ends [5, 12], the string 9..11 with none
//   the same from offset 9, rooted: the string band alone
//   {  alone: not balanced, its one band left open (close 0)
//
// RUN: mlnix-opt %s | mlnix-opt | FileCheck %s --check-prefix=ROUND
// RUN: mlnix-opt %s --confix-to-llvm | FileCheck %s --check-prefix=LLVM
// RUN: d=$(mktemp -d) && clang++ -S -emit-llvm -O1 -std=c++17 -I include %S/inputs/confix-bands-match.cpp -o $d/match.ll && mlnix-opt %s --confix-to-llvm | mlir-translate --mlir-to-llvmir | llvm-link - build/lib/lowered/ConfixScan.ll $d/match.ll -S | lli

// ROUND: confix.bands %{{.*}} : !llvm.ptr
// LLVM-DAG: llvm.func @confix_scan_nix(!llvm.ptr) -> i32
// LLVM: llvm.call @confix_scan_nix(%{{.*}}) : (!llvm.ptr) -> i32

!rec = !llvm.struct<(ptr, i64, i64, i64, ptr, ptr, ptr, ptr, i64, i64, i64, i64)>

llvm.mlir.global internal constant @text1("{ a=1; b=\22x\22; }") {addr_space = 0 : i32}
llvm.mlir.global internal constant @text2("{") {addr_space = 0 : i32}

llvm.func private @ne64(%a: i64, %b: i64) -> i32 {
  %c = llvm.icmp "ne" %a, %b : i64
  %r = llvm.zext %c : i1 to i32
  llvm.return %r : i32
}
llvm.func private @ne32(%a: i32, %b: i32) -> i32 {
  %c = llvm.icmp "ne" %a, %b : i32
  %r = llvm.zext %c : i1 to i32
  llvm.return %r : i32
}

// the record of a scan of %src (%n bytes) from %start, rooted %rooted, into fresh arrays; the status
llvm.func private @scan(%src: !llvm.ptr, %n: i64, %start: i64, %rooted: i64, %rec: !llvm.ptr) -> i32 {
  %one = llvm.mlir.constant(1 : i64) : i64
  %z = llvm.mlir.constant(0 : i64) : i64
  %span = llvm.alloca %one x !llvm.array<16 x i64> : (i64) -> !llvm.ptr
  %kind = llvm.alloca %one x !llvm.array<16 x i8> : (i64) -> !llvm.ptr
  %stmts = llvm.alloca %one x !llvm.array<16 x i64> : (i64) -> !llvm.ptr
  %ends = llvm.alloca %one x !llvm.array<64 x i32> : (i64) -> !llvm.ptr
  %f0 = llvm.getelementptr %rec[0, 0] : (!llvm.ptr) -> !llvm.ptr, !rec
  llvm.store %src, %f0 : !llvm.ptr, !llvm.ptr
  %f1 = llvm.getelementptr %rec[0, 1] : (!llvm.ptr) -> !llvm.ptr, !rec
  llvm.store %n, %f1 : i64, !llvm.ptr
  %f2 = llvm.getelementptr %rec[0, 2] : (!llvm.ptr) -> !llvm.ptr, !rec
  llvm.store %start, %f2 : i64, !llvm.ptr
  %f3 = llvm.getelementptr %rec[0, 3] : (!llvm.ptr) -> !llvm.ptr, !rec
  llvm.store %rooted, %f3 : i64, !llvm.ptr
  %sp = llvm.getelementptr %span[0, 0] : (!llvm.ptr) -> !llvm.ptr, !llvm.array<16 x i64>
  %f4 = llvm.getelementptr %rec[0, 4] : (!llvm.ptr) -> !llvm.ptr, !rec
  llvm.store %sp, %f4 : !llvm.ptr, !llvm.ptr
  %kp = llvm.getelementptr %kind[0, 0] : (!llvm.ptr) -> !llvm.ptr, !llvm.array<16 x i8>
  %f5 = llvm.getelementptr %rec[0, 5] : (!llvm.ptr) -> !llvm.ptr, !rec
  llvm.store %kp, %f5 : !llvm.ptr, !llvm.ptr
  %tp = llvm.getelementptr %stmts[0, 0] : (!llvm.ptr) -> !llvm.ptr, !llvm.array<16 x i64>
  %f6 = llvm.getelementptr %rec[0, 6] : (!llvm.ptr) -> !llvm.ptr, !rec
  llvm.store %tp, %f6 : !llvm.ptr, !llvm.ptr
  %ep = llvm.getelementptr %ends[0, 0] : (!llvm.ptr) -> !llvm.ptr, !llvm.array<64 x i32>
  %f7 = llvm.getelementptr %rec[0, 7] : (!llvm.ptr) -> !llvm.ptr, !rec
  llvm.store %ep, %f7 : !llvm.ptr, !llvm.ptr
  %f8 = llvm.getelementptr %rec[0, 8] : (!llvm.ptr) -> !llvm.ptr, !rec
  llvm.store %z, %f8 : i64, !llvm.ptr
  %f9 = llvm.getelementptr %rec[0, 9] : (!llvm.ptr) -> !llvm.ptr, !rec
  llvm.store %z, %f9 : i64, !llvm.ptr
  %c16 = llvm.mlir.constant(16 : i64) : i64
  %f10 = llvm.getelementptr %rec[0, 10] : (!llvm.ptr) -> !llvm.ptr, !rec
  llvm.store %c16, %f10 : i64, !llvm.ptr
  %c64 = llvm.mlir.constant(64 : i64) : i64
  %f11 = llvm.getelementptr %rec[0, 11] : (!llvm.ptr) -> !llvm.ptr, !rec
  llvm.store %c64, %f11 : i64, !llvm.ptr
  %status = confix.bands %rec : !llvm.ptr
  llvm.return %status : i32
}

llvm.func private @field(%rec: !llvm.ptr, %k: i64) -> i64 {
  %p = llvm.getelementptr %rec[%k] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %v = llvm.load %p : !llvm.ptr -> i64
  llvm.return %v : i64
}
llvm.func private @col64(%rec: !llvm.ptr, %k: i64, %i: i64) -> i64 {
  %p = llvm.getelementptr %rec[%k] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %a = llvm.load %p : !llvm.ptr -> !llvm.ptr
  %q = llvm.getelementptr %a[%i] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %v = llvm.load %q : !llvm.ptr -> i64
  llvm.return %v : i64
}
llvm.func private @col8(%rec: !llvm.ptr, %k: i64, %i: i64) -> i64 {
  %p = llvm.getelementptr %rec[%k] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %a = llvm.load %p : !llvm.ptr -> !llvm.ptr
  %q = llvm.getelementptr %a[%i] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %v = llvm.load %q : !llvm.ptr -> i8
  %w = llvm.zext %v : i8 to i64
  llvm.return %w : i64
}
llvm.func private @col32(%rec: !llvm.ptr, %k: i64, %i: i64) -> i64 {
  %p = llvm.getelementptr %rec[%k] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %a = llvm.load %p : !llvm.ptr -> !llvm.ptr
  %q = llvm.getelementptr %a[%i] : (!llvm.ptr, i64) -> !llvm.ptr, i32
  %v = llvm.load %q : !llvm.ptr -> i32
  %w = llvm.zext %v : i32 to i64
  llvm.return %w : i64
}

// { a=1; b="x"; }: the brace 0..14 (kind 123) with ends [5, 12], the string 9..11 (kind 34) with none
llvm.func @case_whole() -> i32 {
  %one = llvm.mlir.constant(1 : i64) : i64
  %one8 = llvm.mlir.constant(8 : i64) : i64
  %one9 = llvm.mlir.constant(9 : i64) : i64
  %rec = llvm.alloca %one x !rec : (i64) -> !llvm.ptr
  %src = llvm.mlir.addressof @text1 : !llvm.ptr
  %n = llvm.mlir.constant(15 : i64) : i64
  %z = llvm.mlir.constant(0 : i64) : i64
  %status = llvm.call @scan(%src, %n, %z, %z, %rec) : (!llvm.ptr, i64, i64, i64, !llvm.ptr) -> i32
  %z32 = llvm.mlir.constant(0 : i32) : i32
  %r0 = llvm.call @ne32(%status, %z32) : (i32, i32) -> i32
  %rows = llvm.call @field(%rec, %one8) : (!llvm.ptr, i64) -> i64
  %two = llvm.mlir.constant(2 : i64) : i64
  %r1 = llvm.call @ne64(%rows, %two) : (i64, i64) -> i32
  %nends = llvm.call @field(%rec, %one9) : (!llvm.ptr, i64) -> i64
  %r2 = llvm.call @ne64(%nends, %two) : (i64, i64) -> i32
  %k4 = llvm.mlir.constant(4 : i64) : i64
  %k5 = llvm.mlir.constant(5 : i64) : i64
  %k6 = llvm.mlir.constant(6 : i64) : i64
  %k7 = llvm.mlir.constant(7 : i64) : i64
  %span0 = llvm.call @col64(%rec, %k4, %z) : (!llvm.ptr, i64, i64) -> i64
  %w14 = llvm.mlir.constant(14 : i64) : i64
  %r3 = llvm.call @ne64(%span0, %w14) : (i64, i64) -> i32
  %kind0 = llvm.call @col8(%rec, %k5, %z) : (!llvm.ptr, i64, i64) -> i64
  %w123 = llvm.mlir.constant(123 : i64) : i64
  %r4 = llvm.call @ne64(%kind0, %w123) : (i64, i64) -> i32
  %stmts0 = llvm.call @col64(%rec, %k6, %z) : (!llvm.ptr, i64, i64) -> i64
  %r5 = llvm.call @ne64(%stmts0, %two) : (i64, i64) -> i32
  %span1 = llvm.call @col64(%rec, %k4, %one) : (!llvm.ptr, i64, i64) -> i64
  %w911 = llvm.mlir.constant(38654705675 : i64) : i64
  %r6 = llvm.call @ne64(%span1, %w911) : (i64, i64) -> i32
  %kind1 = llvm.call @col8(%rec, %k5, %one) : (!llvm.ptr, i64, i64) -> i64
  %w34 = llvm.mlir.constant(34 : i64) : i64
  %r7 = llvm.call @ne64(%kind1, %w34) : (i64, i64) -> i32
  %stmts1 = llvm.call @col64(%rec, %k6, %one) : (!llvm.ptr, i64, i64) -> i64
  %r8 = llvm.call @ne64(%stmts1, %z) : (i64, i64) -> i32
  %end0 = llvm.call @col32(%rec, %k7, %z) : (!llvm.ptr, i64, i64) -> i64
  %w5 = llvm.mlir.constant(5 : i64) : i64
  %r9 = llvm.call @ne64(%end0, %w5) : (i64, i64) -> i32
  %end1 = llvm.call @col32(%rec, %k7, %one) : (!llvm.ptr, i64, i64) -> i64
  %w12 = llvm.mlir.constant(12 : i64) : i64
  %r10 = llvm.call @ne64(%end1, %w12) : (i64, i64) -> i32
  %s1 = llvm.add %r0, %r1 : i32
  %s2 = llvm.add %s1, %r2 : i32
  %s3 = llvm.add %s2, %r3 : i32
  %s4 = llvm.add %s3, %r4 : i32
  %s5 = llvm.add %s4, %r5 : i32
  %s6 = llvm.add %s5, %r6 : i32
  %s7 = llvm.add %s6, %r7 : i32
  %s8 = llvm.add %s7, %r8 : i32
  %s9 = llvm.add %s8, %r9 : i32
  %s10 = llvm.add %s9, %r10 : i32
  llvm.return %s10 : i32
}

// the same text from offset 9, rooted: the string band alone, 9..11
llvm.func @case_rooted() -> i32 {
  %one = llvm.mlir.constant(1 : i64) : i64
  %one8 = llvm.mlir.constant(8 : i64) : i64
  %rec = llvm.alloca %one x !rec : (i64) -> !llvm.ptr
  %src = llvm.mlir.addressof @text1 : !llvm.ptr
  %n = llvm.mlir.constant(15 : i64) : i64
  %nine = llvm.mlir.constant(9 : i64) : i64
  %status = llvm.call @scan(%src, %n, %nine, %one, %rec) : (!llvm.ptr, i64, i64, i64, !llvm.ptr) -> i32
  %z32 = llvm.mlir.constant(0 : i32) : i32
  %r0 = llvm.call @ne32(%status, %z32) : (i32, i32) -> i32
  %rows = llvm.call @field(%rec, %one8) : (!llvm.ptr, i64) -> i64
  %r1 = llvm.call @ne64(%rows, %one) : (i64, i64) -> i32
  %k4 = llvm.mlir.constant(4 : i64) : i64
  %z = llvm.mlir.constant(0 : i64) : i64
  %span0 = llvm.call @col64(%rec, %k4, %z) : (!llvm.ptr, i64, i64) -> i64
  %w911 = llvm.mlir.constant(38654705675 : i64) : i64
  %r2 = llvm.call @ne64(%span0, %w911) : (i64, i64) -> i32
  %s1 = llvm.add %r0, %r1 : i32
  %s2 = llvm.add %s1, %r2 : i32
  llvm.return %s2 : i32
}

// { alone: not balanced (status 1), its one band left open (close 0)
llvm.func @case_bad() -> i32 {
  %one = llvm.mlir.constant(1 : i64) : i64
  %one8 = llvm.mlir.constant(8 : i64) : i64
  %rec = llvm.alloca %one x !rec : (i64) -> !llvm.ptr
  %src = llvm.mlir.addressof @text2 : !llvm.ptr
  %z = llvm.mlir.constant(0 : i64) : i64
  %status = llvm.call @scan(%src, %one, %z, %z, %rec) : (!llvm.ptr, i64, i64, i64, !llvm.ptr) -> i32
  %o32 = llvm.mlir.constant(1 : i32) : i32
  %r0 = llvm.call @ne32(%status, %o32) : (i32, i32) -> i32
  %rows = llvm.call @field(%rec, %one8) : (!llvm.ptr, i64) -> i64
  %r1 = llvm.call @ne64(%rows, %one) : (i64, i64) -> i32
  %k4 = llvm.mlir.constant(4 : i64) : i64
  %span0 = llvm.call @col64(%rec, %k4, %z) : (!llvm.ptr, i64, i64) -> i64
  %r2 = llvm.call @ne64(%span0, %z) : (i64, i64) -> i32
  %s1 = llvm.add %r0, %r1 : i32
  %s2 = llvm.add %s1, %r2 : i32
  llvm.return %s2 : i32
}

llvm.func @main() -> i32 {
  %a = llvm.call @case_whole() : () -> i32
  %b = llvm.call @case_rooted() : () -> i32
  %c = llvm.call @case_bad() : () -> i32
  %s1 = llvm.add %a, %b : i32
  %s2 = llvm.add %s1, %c : i32
  llvm.return %s2 : i32
}
