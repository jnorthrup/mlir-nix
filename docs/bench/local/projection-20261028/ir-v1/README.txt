Lazy projection IR example, 2026-10-28

Primary artifact: scalar-3.plan.txt and its .typed.mlir, .llvm.mlir and .ll files.
This is the combined default-tier execution, not a curried-off ablation.

Effective recorded invocation, from /Users/jim/work/mlir-nix:
  Clear every inherited MLNIX_* variable, then set:
    MLNIX_DEFER=1
    MLNIX_JIT=1
    MLNIX_JIT_THRESHOLD=1
    MLNIX_STATS=1
    MLNIX_JIT_DUMP=/Users/jim/work/mlir-nix/docs/bench/local/projection-20261028/ir-v1
    MLNIX_STORE_ROOT=/tmp/mlnix-np-root
    MLNIX_STATE_DIR=/tmp/mlnix-np-state
  build/bin/mlnix instantiate --readonly-mode --eval --strict --json \
    /Users/jim/work/mlir-nix/docs/bench/local/projection-20261028/ir-v1/example.nix

MLNIX_JIT_CURRIED, MLNIX_JIT_INLINE and MLNIX_JIT_PROJECTION were absent: all
three use their enabled defaults within the opt-in JIT. The hot threshold was
explicitly reduced from 1024 to 1. stdout is output.json; stderr is stats.txt.
This README reviews the saved artifacts without rerunning the command.

Kernel roles
  scalar-0: ordinary unary value stage of the predicate; enabled is captured.
  scalar-1: saturated two-argument name/value predicate; name stays unused.
  scalar-2: ordinary final set stage of apply, capturing pred and name; contains
            a two-argument inline predicate and dynamic projection.
  scalar-3: saturated three-argument apply; the primary combined example.
The oracle reaches ordinary and saturated paths, so four kernels are expected.

Reading scalar-3
  chain-count=3 maps root leaves 0/1/2 to pred/name/set. Leaf 3 is the recipe
  projection(base=2, dynamic-key=1); its components are not eagerly resolved.
  Call node 4 guards leaf 0, enters context 1 with arity=2, and compiles the
  predicate's final Boolean graph. Context-1 leaves 4 and 5 are captures.
  Continuation 8 enters the call. Continuation 7 tests the current enabled
  capture, routing true to projection-consuming predicate continuation 5 and
  false to continuation 6. Leave continuations 3/4 implement the outer NOT.

  In scalar-3.typed.mlir, bb25/bb26 check the outer callee's Lambda tag and
  operation identity. bb31 loads that closure's current environment, activates
  context 1, clears its capture cells and enters bb8. The environment is loaded
  from the current closure; enabled is not baked into code. bb23 selects bb6
  for enabled=true or bb7 for enabled=false. The false path never visits the
  projected leaf, so the throwing key and base in example.nix stay untouched.

  bb6/bb13 request an unresolved projection using status 42 = (5 << 3) | 2.
  The host services continuation 5 and resumes with 6 (= destination + 1).
  It forces the dynamic key first, then uses selectField to force/check the
  base and find the stable field, then forces that field at the Select position.
  The entire sequence retains the consuming isBool builtin's error wrapper.
  This helper work is a host boundary, not a native attribute-search loop.
  After resumption, native code performs the Boolean tag test and continuation.

  The LLVM-dialect file preserves this control flow after func/arith/cf lowering.
  scalar-3.ll retains the callee identity guard, current-environment store,
  captured-condition branch, demand statuses and native Enter/Leave bookkeeping.
  Its scalar function calls no evaluator helper; LLVM folds capture-slot clearing
  into a memset intrinsic. Numeric offsets and the embedded operation pointer
  are from this arm64 macOS process, not portable cached-code identifiers.

Observed result and limits
  output.json is [false,true,false]. The first three lines of stats.txt are:
    trace: projection key
    trace: projection base
    trace: projection field
  Each occurs once, in order. Two closures sharing the predicate's LambdaOp use
  different enabled captures; the disabled one ignores both throwing inputs.

  Saved counters report four kernels, 16 native executions, 12 grace comparisons,
  two projection kernels, two saturated-inline kernels, nine projection requests,
  five projection component forces, and ten saturated-inline entries. There are
  zero mismatches or compilation failures. These counts establish which paths
  ran; grace and counters alone are not a semantic proof. The plan/IR inspection,
  ordered output/trace oracle and broader exact tests provide separate evidence.
  This small diagnostic is not a throughput or RSS measurement.
