Lazy list-return IR example, 2026-10-28

Primary artifact: scalar-4.plan.txt with its .typed.mlir, .llvm.mlir and .ll.
It combines two root arguments, a two-argument inline hop and a unary inline
getter, then returns three ordered lazy handles through two native Leaves.
This README inspects saved artifacts; neither evaluator was rerun for it.

Recorded commands and environment
  Working directory: /Users/jim/work/mlir-nix
  Clear every inherited MLNIX_* variable. For both runs set:
    MLNIX_DEFER=1
    MLNIX_STORE_ROOT=/tmp/mlnix-np-root
    MLNIX_STATE_DIR=/tmp/mlnix-np-state

  Preserved Values V1 interpreter, with JIT unset:
    /tmp/mlnix-locality/mlnix-values-v1 instantiate --readonly-mode --eval --strict --json \
      /Users/jim/work/mlir-nix/docs/bench/local/list-returns-20261028/ir-v1/example.nix

  Candidate additionally sets:
    MLNIX_JIT=1
    MLNIX_JIT_THRESHOLD=1
    MLNIX_STATS=1
    MLNIX_JIT_DUMP=/Users/jim/work/mlir-nix/docs/bench/local/list-returns-20261028/ir-v1
  and runs:
    build/bin/mlnix instantiate --readonly-mode --eval --strict --json \
      /Users/jim/work/mlir-nix/docs/bench/local/list-returns-20261028/ir-v1/example.nix

LISTS, VALUES, CURRIED, INLINE and PROJECTION overrides were all absent (full
names MLNIX_JIT_*), retaining their enabled defaults inside the opt-in JIT.
No profile flag was set. The threshold was reduced from 1024 to 1. Candidate
stdout/stderr are output.json and stats.txt; the same-path interpreter oracle
is recorded in oracle-output.json and oracle-trace.txt.

Example behavior
  make creates two closures from the same getter LambdaOp and captured SSA
  definition, but with distinct label/closure environments. Four outer calls
  warm the first closure while leaving its captured trace unforced. Before the
  final call, seq realizes second as a closure without evaluating captured.
  This meets the existing reached-callee WHNF guard without demanding an item.
  Passing an unready closure would conservatively fall back instead.

  The final list is [captured, item, captured]. Its middle element throws if
  demanded, but length does not inspect it. head and elemAt 2 select the same
  captured cell, so its trace runs once when its answer field is requested.
  The output and oracle both contain [3,42,42], and both emit exactly:
    trace: selected capture once
  Neither the first capture's trace nor the middle-element error is observed.

Kernel roles
  scalar-0: ordinary unary getter; list recipe [capture, item, capture].
  scalar-1: ordinary final item stage of hop, with getter captured; one inline
            unary getter, then a list return.
  scalar-2: saturated two-argument hop; getter and item are root handles.
  scalar-3: ordinary final item stage of outer; captured hop/getter and two
            nested inline scopes.
  scalar-4: saturated two-argument outer, the primary combined example.
Ordinary and saturated oracle paths account for all five compiled kernels.

Reading scalar-4
  Leaf 0 is captured hop; leaf 1 is root argument 0 (getter); leaf 2 is root
  argument 1 (item). Leaf 3 is captured from the CURRENT getter environment in
  context 2. Node 2 calls hop with arity 2 in context 1; node 1 calls getter
  with arity 1 in context 2. Node 0 is list descriptor 0, result code 20,
  ordered leaves 3,2,3. Repeated leaf 3 preserves pointer aliasing and order.

  Entry continuation 11 enters hop; continuation 10 enters getter. ReturnList
  continuation 9 obtains handles and then follows Leave continuation 8 (context
  2) and Leave continuation 5 (context 1) to the separate status-6 terminal.
  Action numbers are 1=Enter, 2=Leave and 5=ReturnList here. Resume zero is
  initial entry; a resumed continuation uses its destination ID plus one.

  In scalar-4.typed.mlir, bb32/bb33 and bb24/bb25 guard the hop/getter Lambda
  tags and operation identities. bb38 and bb30 load each actual current closure
  environment before activation; the observed first environment is not baked
  into code. bb30 also clears context 2's cached capture handle.

  bb10 loads only cell POINTERS for leaves 3,2,3 and tests them against null.
  It reads no element tag or payload: Thunk, App and Blackhole are valid list
  elements. If a handle is missing, bb21 returns 74 = (9 << 3) | 2. The host
  services ReturnList continuation 9 in source element order while the owning
  contexts are still active. Existing slots are peeked first; only an absent
  real capture needs lookup. That lookup creates a persistent lazy cell without
  running its computation. Duplicate elements share the resolved pointer.
  This is a handle request, not a predicate, projection or forceValue request.

  The host resumes with 10. Once every pointer exists, bb22 stores code 20 in
  Runtime.resultLeaf. bb9/bb20 then leave context 2, and bb6/bb17 leave context
  1 and restore root depth. Only then does bb14 return status 6. All these Leave
  operations remain native; the result does not require a host Leave callback.

  The optimized scalar-4.ll retains the same distinction: block 41 checks the
  two distinct element pointers without dereferencing either. Block 70 stores
  code 20, .thread25 clears context 2, and block 63 clears context 1/restores
  root scope before common.ret returns 6. Callee tag/identity checks and current
  environment loads remain. scalar calls no evaluator helper. The LLVM-dialect
  file records the intermediate conversion. Layout offsets and embedded LambdaOp
  addresses are specific to this arm64 macOS process, not portable code-cache keys.

Host result and validation
  Codes 20+descriptor-id are separate from cell indices 0..15 and empty recipes
  17..19. At status 6 the host checks root scope, descriptor bounds/allowlist,
  length 1..4, Cell leaf indices and non-null pointers. It copies the ordered
  handles into RunResult's own bounded array, never exposing Runtime/plan storage.
  Trusted completion allocates a fresh arena list and copies those handles while
  activeRuns still pins the plan/code. No element is forced or copied by value.
  Its original persistent cell and environment determine later evaluation.

  The pure preflight observer and three native grace comparisons per entry use
  existing handles only: no lookup, element force or duplicate list allocation.
  Validation compares the oracle's List type, length and ordered element pointer
  identity. It does not compare the newly allocated list-array address or inspect
  element values. During grace the oracle's original list is returned.

  Current-local computations, virtual projections and kNoSlot captures remain
  excluded; those would require durable lazy computation storage rather than an
  already persistent handle. Strict Boolean contexts still deopt on constructors.

Saved counters and limits
  Five kernels complete 17 native executions, all list results; 15 are grace
  comparisons. There are 22 inline entries, 8 saturated-inline entries and 48
  native invocations. The run records one nonforcing capture lookup, zero actual
  demands, zero guard misses/deopts, zero mismatches and zero compiler failures.
  compile_ns=26756834 measures compiler elapsed wall time, not total JIT cost.

  These results, the explicit second-closure realization and the emitted guards
  support the intended current-environment path without interpreter deopt. The
  counters aggregate five kernels; they are not a per-invocation trace assigning
  the single lookup to a named native instruction. The IR separately shows where
  that lookup must be requested before either owning context is left.

  The primary plan uses 3/64 source nodes, 4/16 leaves and 39/256 emitted blocks;
  each list has at most 4 elements. Inline depth is capped at 4 and native
  invocations at 32 per run. Continuation/candidate/compiler caps also remain.
  Counter totals include grace and do not establish allocation savings. Exact
  output/trace, shallow handle checks and the broader regression gate provide
  evidence beyond compilation counts. No throughput, RSS or cache-miss claim
  follows from this small inspection example.
