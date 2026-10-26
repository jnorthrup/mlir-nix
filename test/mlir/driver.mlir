// The evaluator does not know which optimizations it runs: it hands every
// freshly lowered file to a pipeline that is data -- a textual pass pipeline
// (MLNIX_PIPELINE), a Transform-dialect script (MLNIX_TRANSFORM) or, deprecated,
// MLNIX_PASSES=devirt,fold,dce|all. The default is builtin.module(nix-prims).
//
// RUN: mlnix emit-mlir -E 'let n = 1; in [ (builtins.add n 2) ]' | FileCheck %s --check-prefix=DEFAULT
// RUN: mlnix emit-mlir --no-opt -E 'let n = 1; in [ (builtins.add n 2) ]' | FileCheck %s --check-prefix=NOOPT
// RUN: MLNIX_PIPELINE='builtin.module()' mlnix emit-mlir -E 'let n = 1; in [ (builtins.add n 2) ]' | FileCheck %s --check-prefix=NOOPT
// RUN: MLNIX_PIPELINE='builtin.module(nix-prims,nix-fold,nix-dce)' mlnix emit-mlir -E 'let n = 1; in [ (builtins.add n 2) ]' | FileCheck %s --check-prefix=FOLD
// RUN: MLNIX_PIPELINE='builtin.module(nix.expr(nix-prims),nix-fold)' mlnix emit-mlir -E 'let n = 1; in [ (builtins.add n 2) ]' | FileCheck %s --check-prefix=FOLD
// RUN: MLNIX_PASSES=devirt mlnix emit-mlir -E 'let n = 1; in [ (builtins.add n 2) ]' | FileCheck %s --check-prefix=DEFAULT
// RUN: MLNIX_PASSES=dce,fold,devirt mlnix emit-mlir -E 'let n = 1; in [ (builtins.add n 2) ]' | FileCheck %s --check-prefix=FOLD
// RUN: MLNIX_PASSES=all mlnix emit-mlir -E 'let n = 1; in [ (builtins.add n 2) ]' | FileCheck %s --check-prefix=FOLD
// RUN: MLNIX_PASSES=none mlnix emit-mlir -E 'let n = 1; in [ (builtins.add n 2) ]' | FileCheck %s --check-prefix=NOOPT
// RUN: MLNIX_TRANSFORM=embedded mlnix emit-mlir -E 'let n = 1; in [ (builtins.add n 2) ]' | FileCheck %s --check-prefix=DEFAULT
// RUN: MLNIX_TRANSFORM=pipelines/default.transform.mlir mlnix emit-mlir -E 'let n = 1; in [ (builtins.add n 2) ]' | FileCheck %s --check-prefix=DEFAULT
// RUN: MLNIX_TRANSFORM=pipelines/full.transform.mlir mlnix emit-mlir -E 'let n = 1; in [ (builtins.add n 2) ]' | FileCheck %s --check-prefix=FOLD
//
// A bad pipeline is an error of the evaluator, not a silent fallback.
// RUN: not env MLNIX_PIPELINE='builtin.module(no-such-pass)' mlnix emit-mlir -E 1 2>&1 | FileCheck %s --check-prefix=BADPASS
// RUN: not env MLNIX_PIPELINE='nix-prims' mlnix emit-mlir -E 1 2>&1 | FileCheck %s --check-prefix=BADANCHOR
// RUN: not env MLNIX_TRANSFORM=/no/such/script.mlir mlnix emit-mlir -E 1 2>&1 | FileCheck %s --check-prefix=BADFILE

// DEFAULT: nix.int 1
// DEFAULT: nix.int 2
// DEFAULT: nixnum.add(
// DEFAULT-NOT: nix.apply

// NOOPT: nix.builtin
// NOOPT: nix.apply
// NOOPT-NOT: nixnum.add

// FOLD: nix.int 3
// FOLD-NOT: nixnum.add
// FOLD-NOT: nix.apply

// BADPASS: error: invalid pass pipeline 'builtin.module(no-such-pass)'
// BADPASS: 'no-such-pass' does not refer to a registered pass or pass pipeline
// BADANCHOR: expected pass pipeline to be wrapped with the anchor operation type
// BADFILE: error: cannot read MLNIX_TRANSFORM script '/no/such/script.mlir'
