// Regular expressions as kursive combinators, run: --re2mlir, --kursive-to-program, then each Program walked by
// mlnix_kursive_walk (lowered/nixeval/KursiveOps.mlir) over a text by inputs/kursive-run-main.mlir, as builtins.match walks it
// (the whole text).  Each line printed is [result, the groups' marks]: result 1 a match, 0 none; a mark -1 is a
// group that took no part.
// RUN: { cat lowered/nixeval/KursiveOps.mlir; mlnix-opt %s --re2mlir --kursive-to-program | sed '/^module {$/d;/^}$/d'; cat %S/inputs/kursive-run-main.mlir; } | mlir-opt --ownership-based-buffer-deallocation --canonicalize --buffer-deallocation-simplification --bufferization-lower-deallocations --convert-scf-to-cf --expand-strided-metadata --lower-affine --finalize-memref-to-llvm --convert-arith-to-llvm --convert-index-to-llvm --convert-cf-to-llvm --convert-func-to-llvm --reconcile-unrealized-casts | mlir-runner -e main -entry-point-result=i32 -shared-libs=$(ls $(dirname $(which mlir-runner))/../lib/libmlir_runner_utils.* | head -1) | FileCheck %s

// (a|b)*c on "abac": a match, group 1 the last iteration, "a" at [2, 3).
// CHECK: [1, 0, 4, 2, 3]
// ([a-z]+)-([0-9]+) on "foo-123": groups [0, 3) and [4, 7).
// CHECK: [1, 0, 7, 0, 3, 4, 7]
// x{2,3} on "xxxx": no match (the marks are only an answer's).
// CHECK: [0, {{.*}}]
// (a|ab)(c|bcd)(d*) on "abcd": POSIX alternation is libstdc++'s (the first way that reaches the end): a, bcd, "".
// CHECK: [1, 0, 4, 0, 1, 1, 4, 4, 4]
// ^(x)?y$ on "y": group 1 took no part.
// CHECK: [1, 0, 1, -1, -1]
// CHECK: 0

kursive.pattern @p1 "(a|b)*c"
kursive.pattern @p2 "([a-z]+)-([0-9]+)"
kursive.pattern @p3 "x{2,3}"
kursive.pattern @p4 "(a|ab)(c|bcd)(d*)"
kursive.pattern @p5 "^(x)?y$"
