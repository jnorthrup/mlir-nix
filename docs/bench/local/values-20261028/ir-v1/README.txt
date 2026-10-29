Value-return IR example, 2026-10-28

Primary artifact: scalar-4.plan.txt and its .typed.mlir, .llvm.mlir and .ll files.
This records combined default-tier execution with persistent cell and empty-list
returns through two nested inline call scopes. It is not a timing experiment.

Effective recorded invocation, from /Users/jim/work/mlir-nix:
  Clear every inherited MLNIX_* variable, then set:
    MLNIX_DEFER=1
    MLNIX_JIT=1
    MLNIX_JIT_THRESHOLD=1
    MLNIX_STATS=1
    MLNIX_JIT_DUMP=/Users/jim/work/mlir-nix/docs/bench/local/values-20261028/ir-v1
    MLNIX_STORE_ROOT=/tmp/mlnix-np-root
    MLNIX_STATE_DIR=/tmp/mlnix-np-state
  build/bin/mlnix instantiate --readonly-mode --eval --strict --json \
    /Users/jim/work/mlir-nix/docs/bench/local/values-20261028/ir-v1/example.nix

MLNIX_JIT_CURRIED, MLNIX_JIT_INLINE, MLNIX_JIT_PROJECTION and MLNIX_JIT_VALUES
were absent, retaining their enabled defaults within the opt-in JIT. The hot
threshold was reduced from 1024 to 1. stdout is output.json; stderr is stats.txt.
The preserved projection-V1 interpreter evaluated this same absolute example
path: oracle-output.json and oracle-trace.txt record its answer. This README
reviews saved files only; it did not rerun either evaluator.

Kernel roles
  scalar-0: ordinary unary getter, capturing enabled and returning item.value
            or the empty-list recipe.
  scalar-1: ordinary final item stage of hop, with getter captured; one inline
            unary getter and a static projection.
  scalar-2: saturated two-argument hop; getter/item are root arguments.
  scalar-3: ordinary final item stage of outer, with hop/getter captured;
            two inline scopes, including a saturated two-argument hop.
  scalar-4: saturated two-argument outer; the primary combined example.
  scalar-5: checked integer x + 1 in the returned closure, invoked afterward.
The arithmetic kernel has no demand/CPS plan file. The ordinary and saturated
oracle paths account for the five lazy kernels, rather than five different
source algorithms.

Reading scalar-4
  chain-count=2 maps leaf 1 to root getter and leaf 2 to root item. Leaf 0 is
  the captured hop. Node 5 guards that callee and inlines its two-argument chain
  in context 1. Node 4 guards getter and enters its unary body in context 2.
  Leaf 3 is enabled from the current getter environment. Leaf 4 is the virtual
  static projection(base=2, symbol=4), corresponding to item.value.

  The entry is continuation 13 (Enter hop), followed by continuation 12
  (Enter getter). Continuation 11 tests the captured enabled Boolean. Its true
  path reaches continuation 9, ReturnValue of projected leaf 4; its false path
  reaches continuation 10, ReturnEmpty with list recipe code 18. Both then use
  continuation 8 (Leave context 2) and continuation 5 (Leave context 1) before
  the separate value terminal. Action numbers are 0=atomic, 1=Enter, 2=Leave,
  3=ReturnValue and 4=ReturnEmpty. Resume zero selects entry; other resumes are
  continuation ID plus one. The value terminal has no resume-switch entry.

  In scalar-4.typed.mlir, bb39/bb40 and bb31/bb32 guard the Lambda tags and
  operation identities of hop and getter. bb45 and bb37 load their CURRENT
  closure environments before activating contexts. The getter's enabled value
  is not embedded in generated code. bb29 branches to bb10 for a selected field
  or bb11 for the empty result. The false path never resolves item or its field,
  so getterOff can receive the throwing item unchanged.

  bb10/bb23 request an unresolved projection with status 74 = (9 << 3) | 2.
  The host resolves continuation 9 and resumes with 10. This example has a
  static key: selectField forces/checks the persistent base and returns its
  stable field cell; the host then forces that field at the Select position.
  Only WHNF is required. The trace on chosenList therefore occurs once, while
  its second element and both ignored fields remain lazy.

  Once ready, bb25 stores leaf index 4 in Runtime.resultLeaf. bb11 instead stores
  recipe code 18, without a demand or allocation. Both route through bb9/bb22
  and bb6/bb19, clearing contexts 2 and 1 and restoring depth to zero; bb16 then
  returns status 6. These are ordinary native branches, not host Leave requests.

  scalar-4.ll preserves this protocol after optimization: .sink.split contains
  a phi choosing 18 or 4 and stores it at Runtime offset 728. .thread32 and
  block 64 clear the two active contexts and restore root scope. common.ret
  returns 6 on that path. The getter's captured Boolean branch remains in
  block 79, and its current environment is loaded in .thread33. No evaluator
  helper is called by scalar; LLVM folds capture-cell clearing into memset.
  The LLVM-dialect file exposes the intermediate lowering. Numeric offsets and
  embedded operation addresses belong to this arm64 macOS process and are not
  portable identifiers for cached machine code.

Host result contract
  Status 6 alone is insufficient: the host checks root context, zero relative
  depth and active root, then either a bounded allowlisted WHNF cell or an
  allowlisted empty-recipe code. Codes 17/18/19 identify attrs/list/string and
  are disjoint from leaf indices 0..15 and the invalid initial result code.
  A cell result is copied shallowly from durable argument/environment/field
  storage. A trusted code-18 result constructs a fresh empty list after the
  native scopes have unwound. It never publishes a Runtime pointer or reuses
  a cached empty container. Active-run protection spans forcing and result copy.

  Admission and the first three native completions per entry use the interpreter
  oracle. Observe-only validation performs no extra force or result allocation:
  sameValue compares shallow payload/storage/closure identity, and sameEmpty
  validates the empty recipe. Grace returns the oracle's existing answer.
  Strict Boolean consumers still reject a non-Boolean cell or empty constructor;
  this example exercises tail values, not relaxed Boolean typing.

Observed result and limits
  output.json and oracle-output.json both contain [42,7,2,0]. stats.txt contains
  exactly the same single trace as oracle-trace.txt:
    trace: selected persistent list
  The returned closure is subsequently applied to 41; the selected list is
  reused by head and length. Its throwing second element is never forced.
  getterOn/getterOff share one LambdaOp but have different enabled captures.
  After four warm calls, the false capture returns the fresh empty-list recipe
  without forcing the throwing item. The final zero is that list's length.

  Saved counters: 6 compiled kernels, 20 executions and 16 grace comparisons.
  Five lazy kernels record 19 value completions, 15 value grace comparisons and
  1 empty-recipe completion. There are 26 inline entries, 10 saturated-inline
  entries, 18 projection requests, 4 projection forces and 72 native invocations
  in the lazy tier. Deopts, guard misses, mismatches and compiler failures are
  zero. compile_ns=31546625 is compiler elapsed wall time, not end-to-end timing.
  The primary plan uses 7/64 source-node budget units, 5/16 leaves and 46/256
  emitted blocks; inline depth is capped at 4 and native invocations at 32 per
  run. Source/CPS/call/candidate limits remain in force.

  Counters aggregate these kernels and include validation, so they do not alone
  prove which value an individual invocation returned or how many allocations
  were saved. The plan/IR mapping, exact result/trace oracle, laziness checks and
  broader regression gate provide separate evidence. This record makes no
  throughput, RSS or cache-miss claim.
