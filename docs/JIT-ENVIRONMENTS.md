# Durable environments for general lazy native evaluation

This is a design for the next architectural stage, not implemented local-value support. The current native
tier can retain persistent arguments, captures and selected fields, return existing values and bounded
container recipes, and execute guarded control flow. General local computations and escaping closures
still require interpreter-compatible state. Adding more leaf recipes alone does not complete that conversion.

## Evidence and current boundary

The [List Returns profiles](bench/local/list-returns-20261028/v1/profile-analysis.txt) show only 2,091 native
fallbacks on the package workload, but many frequently called graphs remain uncompiled. Its printed
`splice.nix:40` row has 229,306 calls producing lazy records with local value computations. NixOS has 53,347
calls at `modules.nix:723`, also producing records with local fields. These counts overlap callers and are
not time measurements or independent savings. Compiler/candidate budgets and truncated profiles also limit
what can be inferred about admission.

The relevant existing ownership rules are in [Eval.h](../include/Nix/Eval.h) and [Eval.cpp](../lib/Eval/Eval.cpp):

- A `Frame` holds its real parent, `RegionInfo` and stable `Value *` slots in evaluator arena storage.
- `lookup` locates the owning frame. It creates a constant, builtin, closure or thunk cell when an indexed
  slot is empty. A thunk or closure retains the original operation and its actual frame.
- `operand` and `evalTail` evaluate eligible single-use locals directly into temporary/output Values.
  Such `kNoSlot` values have no persistent memo cell, and both paths consult shared `Slot.inPlace` metadata.
- `callLambda` currently gives the JIT an interpreter callback that creates a new frame on every invocation.
  The saturated callback restarts the remaining ordinary applications through `callFunction`.

Restarting is safe for the current tier because all native-demanded effects occur in preexisting persistent
cells. A native local effect followed by the present fresh-frame callback could run twice. A returned local
closure cannot retain a Runtime stack address or a JIT-plan pointer. Both restrictions must be solved before
general local execution or collection fusion.

## Invocation state, allocated only when needed

Introduce a per-call activation whose lifetime is independent of the cached plan. The activation records
the actual closure environment, explicit argument handles and lazily materialized real frames. It can live
on the C++ stack as an ownership handle, but any frame or cell referenced by an escaping Nix value must be
arena-owned. Reentrant calls always get separate activations, even when they use the same compiled entry.

The persistent-only fast path should materialize no interpreter frame. A reached local demand, escape or
fallback may request a frame. Materialization uses the existing `RegionInfo`, real parent relationship and
formal-slot layout, then binds original argument pointers. It must not create temporary Value copies for
formals whose cells may escape.

For saturated chains, each eliminated lexical stage can need its own real frame if a later closure captures
an earlier local. Sequential source calls still have one logical call depth at a time. Lexical parent links
and dynamic call depth are separate properties; reconstructing a frame chain must not add artificial stack
depth. The reached outer closure's current environment remains the root, including when the same operation
appears in a separately instantiated closure.

## Fallback must reuse the activation

Start with invocation-aware unary fallback before changing saturated or inline local execution. The
interpreter callback should obtain the activation's frame once and evaluate the original body from that
same frame. A native local demand must publish into the precise cell that callback will subsequently read.
The oracle can expose its completed invocation frame through the activation instead of destroying that
identity at the JIT boundary.

Merely allocating a Frame is insufficient. All completed effectful locals that a restart can revisit must
be memoized there, or fallback must use an explicit interpreter continuation after the completed operation.
No successful local result may exist only in LLVM SSA when fallback could recompute its effectful producer.

Initially admit only locals with real indexed slots. Use ordinary `lookup` and `forceValue` so recursive
blackholes, successful memoization and exception restoration retain one implementation. A thrown local
evaluation must propagate once with its source position; it is not a silent deopt that retries the effect.
Calls, projections, comparisons and builtin coercions keep their original demand order and error wrappers.

`kNoSlot` is a separate requirement. Creating a side cell does not help if `operand` and `evalTail` ignore it.
Do not mutate global `Slot.inPlace` during an invocation: recursive calls share that metadata. Options are
an activation-local memo override consulted by both interpreter paths, or precise deoptimization
continuations that never revisit the completed effect. Pure nonescaping native intermediates can be
recomputed without a memo cell, but purity needs an operation-level proof and guarded operand contract.

## Escaping values and speculation

After frame reuse and local memoization work, a lazy record or closure recipe can reference original
operations and durable cells/frames. It must never embed a native program counter, plan allocation, Runtime
array or borrowed LLVM temporary. Native code retirement can then free code while returned values remain
valid through the ordinary evaluator representation.

Preflight and grace need the actual oracle activation. They inspect its realized local cells and identities
without forcing a new branch or allocating an independent copy of the environment. A recipe for a record
compares names, positions and ordered field-cell identities; a closure compares its operation and durable
capture environment. Deep equality is not a safe speculative validator for lazy results.

Hold `activeRuns` through host local demand, activation-based fallback and result publication. Recheck entry
state after recursive oracle execution. Retirement refuses new entries immediately but cannot destroy a
suspended plan or engine. Exceptions restore logical depth and activation ownership without unwinding through
generated native code.

Deferred bodies remain minted under ordinary demand. Cold planning must not resolve an unobserved body,
force captures, intern names merely for observation, or install speculative local effects. These rules extend
the existing separation between bounded native control and host demand, rather than weakening it.

## Implementation and acceptance sequence

| Stage | Required behavior | Evidence before proceeding |
|---|---|---|
| Unary activation | Oracle and fallback can share the actual frame; fast persistent path allocates none | Exact diagnostics/traces, recursion, measured frame counts |
| Local indexed demands | Successful local results occupy interpreter-visible memo cells | Exactly-once effects across deopt; blackhole and throw recovery |
| Saturated/inline activations | Correct lexical parents and original sequential call depth | Changed captures, nested fallback, depth errors, recursive retirement |
| Lazy records and closures | Returned values retain only durable evaluator state | Force after return/retirement; pointer-based nonforcing grace |
| In-place locals | `kNoSlot` effects cannot replay on fallback | Both operand and tail consumers; recursion-safe metadata |
| Collection fusion | Proven producer/consumer ownership permits avoiding intermediate collections | Order, duplicate precedence, lazy fields, escaping producer controls |

Every stage needs the existing eager/demand language gates, focused native-execution proofs, preserved
interpreter outputs and Kali allocation/timing controls. Count newly materialized frames and cells alongside
avoided allocations. More native coverage can increase memory if it eagerly restores frames that the current
tier omits. A compact environment layout can follow once its interpreter adapter is explicit; it must not
silently change `Frame.up` or slot lookup semantics.

The intended collection path includes `listToAttrs(map callback(attrNames set))`, but generic fusion must
preserve lexical callback order, duplicate-name precedence, lazy value cells, attribute positions and fresh
observable identities. An escaping producer still needs materialization. Single-use analysis must cover all
consumers and cannot be inferred from one benchmark trace.
