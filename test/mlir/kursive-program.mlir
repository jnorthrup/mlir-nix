// kursive-to-program: each kursive.regex becomes the Step program of Kursive.h's compiler as constant globals:
// @X_steps (4 i32 words a step: op, x, y, z; ops Char 0, Alt 1, Rep 2, Jmp 3, Save 4, Bol 5, Eol 6, Match 7),
// @X_sets (4 i64 words a set) and @X_counts (steps, sets, groups, loops, error 0 None / 1 Invalid / 2 Space).
// RUN: mlnix-opt %s --re2mlir --kursive-to-program | FileCheck %s
// RUN: mlnix-opt %s --re2mlir --kursive-to-program=step-cap=11 | FileCheck %s --check-prefix=ROOM

// (a|b)*c: save 0; rep (body 2, out 9, loop 0); save 2; alt 4 6; char a; jmp 7; char b; save 3; jmp 1; char c; save 1;
// match.
// CHECK: memref.global "private" constant @alt_steps : memref<48xi32> = dense<[4, 0, 0, 0, 2, 2, 9, 0, 4, 2, 0, 0, 1, 4, 6, 0, 0, 0, 0, 0, 3, 7, 0, 0, 0, 1, 0, 0, 4, 3, 0, 0, 3, 1, 0, 0, 0, 2, 0, 0, 4, 1, 0, 0, 7, 0, 0, 0]>
// CHECK: memref.global "private" constant @alt_sets : memref<12xi64> = dense<[0, 8589934592, 0, 0, 0, 17179869184, 0, 0, 0, 34359738368, 0, 0]>
// CHECK: memref.global "private" constant @alt_counts : memref<5xi32> = dense<[12, 3, 1, 1, 0]>
kursive.pattern @alt "(a|b)*c"

// x{1,3}: one copy, then two optional copies, each a repeat state of its own (loop slots 0 and 1).
// CHECK: memref.global "private" constant @bounded_steps : memref<32xi32> = dense<[4, 0, 0, 0, 0, 0, 0, 0, 2, 3, 4, 0, 0, 0, 0, 0, 2, 5, 6, 1, 0, 0, 0, 0, 4, 1, 0, 0, 7, 0, 0, 0]>
// CHECK: memref.global "private" constant @bounded_counts : memref<5xi32> = dense<[8, 1, 0, 2, 0]>
kursive.pattern @bounded "x{1,3}"

// A rejected pattern has only its counts, with the reason.
// CHECK: memref.global "private" constant @bad_counts : memref<5xi32> = dense<[0, 0, 0, 0, 1]>
// CHECK-NOT: kursive.
kursive.pattern @bad "a{2,1}"

// With room for 11 steps, (a|b)*c (12 steps) is out of room; x{1,3} (8) fits.
// ROOM: @alt_counts : memref<5xi32> = dense<[0, 0, 0, 0, 2]>
// ROOM: @bounded_counts : memref<5xi32> = dense<[8, 1, 0, 2, 0]>
