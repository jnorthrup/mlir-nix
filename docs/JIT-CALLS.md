# Guarded calls and value returns

**Guarded calls, saturated unary-lambda chains, lazy one-key projections, persistent value returns and empty-result recipes are implemented and remain opt-in with the JIT.** Ordinary
call bookkeeping stays native. Top-level saturated entries accept two to four remaining arguments; inline Apply expansion accepts one
to four arguments, including supported projected leaves. They compile bounded lazy graphs through the demand/continuation IR,
independently of library names. General closure/collection fusion and broader projection paths remain future work.
[JIT.md](JIT.md) describes the other tiers, flags and counters.

## Evidence and first scope

The saved [profile before call compilation](bench/local/lazy-boolean-20261028/stats-retirement.txt) identified:

| graph and source context | calls | coverage at that stage |
|---|---:|---|
| `not(apply capturedCallee argument)` in the `removeFunctions` predicate | 163,020 | interpreted wrapper |
| its outer lambda, which returns the predicate lambda | 163,020 | interpreted currying |
| `lib.isFunction`'s OR / type predicate / attribute-existence graph | 174,774 | 173,751 native completions |
| `filterAttrs`' `not(apply ...)` callback | 168,382 | requires a lazy dynamic attribute projection as an argument |
| splice's lazy `{ name; value; }` producer | 229,306 | escaping lazy result; outside this first scope |

These counts overlap along call chains and must not be summed as independent work. The first implemented target was the first row: a Boolean
wrapper compiled together with a bounded supported callee graph. The existing `isFunction` graph supplies a real example whose function
tag and missing-`__functor` paths complete, while its recursive functor application remains an opaque interpreter fallback.
Saturated-chain compilation now also covers the outer lambda in the second row; its separate allocation evidence appears below.

The [earlier call-site profile](MLIR.md) found 85.6% of nixpkgs lambda calls at sites whose callee never changed, with a 98.9% hit rate for
a one-entry callee cache. This supports testing guarded calls; it does not prove that any particular captured function is constant.
The additional 168,382 dynamic-projection callbacks were **not** first-stage coverage. The current projection and saturated-inline
extension supports that generic graph shape; this historical count is not a measurement of the new implementation's coverage.

## Representation and runtime boundary

The plan records each inline-call boundary, guarded lambda identity, formal-to-operand binding and capture-handle context. A callee's
formal substitutes a persistent-cell or projected-leaf handle. Free SSA values resolve through that invocation's actual closure
environment. Code caches the lambda operation and graph metadata; observed environment pointers are cleared before the specialized plan
is retained.

Cold analysis retains bounded graph plans containing eligible `Apply(persistentCallee, arguments...)` nodes, even when those
opaque calls currently prevent completion. After the hot interpreter oracle returns, specialization rebuilds from already-WHNF lambda
targets and already-indexed bodies. It performs no lookup, forcing or body minting. An unresolved plan can retry on later inputs within
the shared 64-miss admission bound. The post-oracle observer must then complete and agree before compilation.

Inline expansion accepts one to four supplied arguments and a supported Boolean, persistent-value or bounded-recipe result. For multiple arguments, every nonfinal body
must directly return the next unary lambda, and each body must already be indexed. Each call context records all formal-to-leaf
bindings and eliminated regions. At each **reached** apply, generated code checks the actual outer callee's tag and lambda-operation
identity. A missing capture cell is resolved by peeking at its existing slot; a lazy or changed callee falls back before demanding an
argument. Other captures use that outer closure's current environment; an equal SSA identity in another invocation does not cause
root-formal substitution. Nonformal locals owned by eliminated stages stay opaque. Guards and demands remain inside the selected
control path. The final callee graph is emitted into MLIR/LLVM; the host does not execute its body as a replacement for compilation.

Formals/defaults, arbitrary local temporary arguments, constructors beyond the bounded tail recipes and unsupported local computations are excluded.
Existing persistent closures and containers may return shallowly; no closure retaining an eliminated frame is constructed. Unsupported reached calls
remain deopt destinations without traversing their operands. Executing an arbitrary host call, obtaining a local result, then restarting
the enclosing lambda could repeat effects. General local evaluation would need a lazily allocated shared
deopt frame, with completed results installed in cells used by the interpreter. It could also add allocations where `evalTail` currently
evaluates in place, so it is a separate design.

The **expanded** graph shares limits of 64 source nodes including projection recipes, 16 total cell/recipe leaves, 256 continuation specializations and 256 emitted blocks. Inline depth
is capped at four, and a run permits 32 native invocations including initial entry and demand/callee-resolution resumes. Active call-graph cycles are detected before
descending; recursive edges stay opaque fallbacks when another path can complete. Context-qualified captures count against the shared
leaf budget. `MLNIX_JIT_INLINE=0` disables Apply acceptance only during cold plan construction, leaving the other tiers enabled.

## Lazy projected arguments

The generic callback `name: !(pred name set.${name})` combines a saturated inline Apply with a projected second argument. Its Select
becomes a lazy recipe containing a base leaf, a static symbol or dynamic-key leaf, and the original operation/position. No argument
thunk or temporary interpreter frame is created for that recipe. The callee may use the name, ignore the value, or demand the projection
under a conditional; only a reached atomic consumer resolves the recipe.

Initial scope is one key with no default. Base and dynamic key must resolve to actual persistent-cell handles, including after formal
substitution. Nested virtual bases/keys and projected callees remain opaque; ordinary persistent captures can still contain already
existing computations. Broader local evaluation or escaping recipes would require durable memo cells shared with fallback.

Trusted resolution preserves Select's order: dynamic key first, base second, selected field last. The key uses `forceStringNoCtx` at
the Select position with the attribute-name context, then normal symbol interning. The shared `EvalState::selectField` helper forces
and checks the base, reports the original missing/type errors, and returns an unforced stable field cell. The host forces it at the
Select position and caches that pointer for the rest of this invocation. A predicate consumer wraps the entire sequence, including key
and base failures, in the same builtin trace as `callPrimOp`; Select itself adds no synthetic attribute trace. A failed force propagates
once. Successful component forces are memoized, so a later native deopt can repeat pure lookup without repeating effects.

Preflight and native grace only peek existing WHNF cells. A dynamic key uses `symbols.map.find`, never interning; missing, wrong-type
or unready components conservatively deopt. Read-only `Bindings::get` handles flat sets, layered top-over-base shadowing, and an already
cached flat view without materializing a layer. This does not change the separate native `has_attr` rule, which still deopts on layered
sets. Host forcing installs the active logical depth for every key/base/field action, including when the projection was passed through
several inline formal bindings.

`MLNIX_JIT_PROJECTION=0` disables virtual Select acceptance during cold plan construction while leaving multi-argument inline expansion
enabled for persistent arguments. `MLNIX_JIT_INLINE=0` disables all Apply expansion. The flags add no per-call environment reads.
Plan dumps identify projection base/key leaves and static symbols, call arities, context-qualified captures and demand consumers;
the accompanying typed MLIR, LLVM-dialect MLIR and LLVM IR expose the consuming control flow and continuations.

## Values and container recipes in tail position

A persistent argument, capture or selected-field leaf can be a value result at the root, in an `if` arm or in the tail of an inlined
call. It may contain any WHNF type, including an existing closure or a list/set with lazy members. Zero-operand local attribute-set/list
constructors and an empty string literal can return an empty-result recipe. Lists of one to four persistent handles can return a lazy list recipe. General local constructors, unevaluated local computations
and temporary frame adapters remain unsupported.

The CPS cache distinguishes an optional value continuation from the existing true/false continuations. Tail `if` arms inherit it;
conditions and strict Boolean operators do not. Calls whose tail can produce a cell or container recipe add a third native Leave route. A ReturnValue
action demands its leaf to WHNF, stores the known leaf index in Runtime.resultLeaf, and branches through all enclosing native Leaves.
Only then does a separate terminal return status `6`. It is not exposed in the resume switch. Boolean terminal IDs/statuses `0`/`1`
stay fixed; ordinary continuation IDs are assigned per plan and may shift as the graph changes.

For a cell result, the host checks root context, zero relative depth, an active root, a bounded return-enabled leaf index and a nonnull WHNF cell before
accepting status `6`. The pointer identifies an existing caller argument, environment cell or stable attribute field; it never points
into the plan or a temporary result slot. Child context deactivation cannot destroy that underlying cell. The host copies its shallow
payload to `out` while `activeRuns` still protects any suspended plan/code, including during reentrant retirement.

ReturnEmpty stores a recipe code in the same Runtime field and follows the same native Leave chain. Codes `17`, `18` and `19` mean
empty attrs, list and string; they cannot overlap cell indices `0..15` or the invalid initial code. After validating the complete scope
unwind, the host checks the recipe range and separate plan allowlist. Only trusted completion materializes a fresh empty container or
a context-free empty string. Native control flow and the observer do not allocate these results; strict Boolean consumers deopt on
constructors rather than accepting an empty result as a Boolean.

ReturnList uses codes `20 + recipe-id`, disjoint from cells and empty recipes. Each bounded descriptor records one to four ordered
persistent Cell leaves and is allowlisted only by a tail return continuation. Native code tests pointers for null without reading
element tags. A missing handle requests one batch of host resolution in the still-active owning contexts: existing slots first,
then nonforcing `lookup` for absent captures. Thunk, App and Blackhole cells are valid elements. The request does not force a value
or enter the predicate/projection machinery. Once handles are present, the same native Leave chain reaches status `6`.
After complete unwind, the host validates the descriptor and copies pointers into the result's own bounded array. Trusted completion
allocates a fresh arena list and fills it while the plan/code pin is still held. Neither runtime stack storage nor plan storage escapes.

Eligibility requires every element to have a persistent Cell handle. Virtual projections, current-local computations, eliminated-frame
locals and `kNoSlot` captures cannot be list elements in this tier. The whole unsupported constructor deopts without traversing or
forcing those operands. The list observer only peeks existing handles. Grace compares list length and ordered element pointers without
reading their payloads or allocating a duplicate list; the original interpreter list remains the returned answer.

Forcing keeps the original tail position: root call-site, If operation, or inlined Apply operation. A projected tail keeps its own
Select position and ordered component demands. Returning a list or set does not force its members; returning a closure keeps its
actual environment. A non-Boolean value used by `!`, another Boolean operator or an `if` condition still deopts for the original type
diagnostic. Tail-context propagation never makes those consumers permissive.

Both the post-oracle observer and native grace follow the Return/Leave protocol without additional forces. A missing or unready return
cell deopts conservatively. `sameValue` validates scalar payloads and shallow storage/closure identities rather than calling deep Nix
equality. `sameEmpty` validates the empty type/shape and context-free string contract without constructing another result. The interpreter
answer is reused during grace, preserving its fresh allocation. Input/output cell aliases bypass the shared graph helper before its oracle,
without invalidating the entry. No input is forced merely to obtain a native value-return specialization.

`MLNIX_JIT_VALUES=0` uses the previous Boolean-only CPS construction, disabling cell and all recipe returns while retaining projections
and the independent pointer tier. `MLNIX_JIT_LISTS=0` independently disables only nonempty list recipes. Both settings are read during
cold plan construction. No value terminal or third Leave route is emitted with VALUES disabled. Value continuations, ReturnValue/ReturnEmpty/ReturnList blocks and extra Leaves share the existing
256-continuation/block bounds; the source, leaf, inline-depth and resume limits remain unchanged. Dumps show `value-returns`, return
actions, empty recipe names/codes and the separate terminal sentinel so the native Leave chain can be inspected alongside status `6` in MLIR/LLVM.

## Call depth, errors and grace

For the unary entry, the caller's `DepthGuard` remains active; saturated execution installs the equivalent one-stage scope described below.
V2's generated Enter code checks the current scope and whether initial plus relative depth
has reached the limit, before any callee-body demand. It then stores the current closure environment, activates the context, clears
its capture handles, increments relative depth and the inline counter, and branches directly into the emitted callee graph. Leave
deactivates that context, restores its parent and relative depth, and branches to the selected Boolean or value continuation. Neither ordinary operation
returns to the host.
An inline saturated chain shares one such depth increment: its stages execute sequentially at the same depth. A call nested inside its
final graph adds another scope. The guard still precedes every argument demand.

The V2 kernel ABI is `uint64_t(uint32_t resume, Runtime *runtime)`, retaining the native `(i32, ptr) -> i64` signature. Resume zero selects
entry; other resumes are destination ID plus one. Runtime stores 16 cell pointers, 64 environment pointers and active flags, initial/maximum/relative
depth, current context, inline/saturated-inline call counters and an initially invalid resultLeaf cell/recipe code. Only live cells, live active flags and the root environment are initialized; generated
code writes a child environment before activating it, and active-state checks protect environment reads.

Status `2` requests a leaf demand, reached callee-cell peek or batched nonforcing list-handle resolution; `5` reports depth overflow at the original apply, and `7` reports a callee
guard miss. Their continuation IDs occupy the upper bits. Status `6` completes a validated cell or bounded-recipe return after unwinding;
it has no encoded continuation. Normal Enter/Leave is not a return status. The host throws the original depth
error only outside observe-only validation; validation treats an unexpected overflow as invalid instead of raising a new error.

While actually forcing a requested value, the host temporarily sets evaluator `callDepth` to `initialDepth + runtime.depth` under scoped
cleanup. The active call depth applies even when an inlined formal refers to the root argument cell. Recursive evaluator calls therefore
start at the correct logical depth. Success and exceptions both restore the base before resuming or leaving the run; demands after
native Leave run at the caller's depth. A top-level restoration guard remains in place. C++ exceptions never unwind through generated code.

Each original consumer operation and position stays in the expanded graph. Persistent predicate demands continue through `callPrimOp`;
projection resolution preserves its equivalent builtin trace around the entire Select. Other forces preserve their original positions and error order. A failed force propagates once. Successful
forces of persistent cells may precede whole-caller fallback because those cells remain memoized. Identity-callee tail forces use the
original apply position; a non-Boolean result in a strict Boolean context deopts for the enclosing operator's type diagnostic. Existing returned lambdas retain their
representation, printing, `functionArgs` and equality behavior.

Specialization and preflight reuse the one interpreter-oracle result. The entry is rechecked after recursive interpretation, which may
have compiled, refused or retired it. The first three completed native runs remain observe-only comparisons against the oracle; they
cannot force another branch. Target guards remain active afterward, including when two closures share a lambda operation but have
different captures. Retirement after 64 consecutive native deopts rejects new entries immediately; `activeRuns` defers plan/code
destruction while an inlined demand is suspended. Tests exercise recursive retirement on both successful and throwing demand paths.

## Saturated unary-lambda chains

The original hook inside `callLambda` sees one argument. Saturated-chain V1 adds an arity-aware hook in `callFunction`, after the reached
function is forced and before intermediate result Values or frames are allocated. It accepts exactly two to four remaining arguments
for an unconditional chain whose nonfinal bodies directly return the next unary lambda and whose final body has a supported Boolean, persistent-value or bounded-recipe
path. Ordinary application prefixes may expose an eligible suffix, including in a call that originally supplied more than four arguments.
Partial applications, oversaturated candidates, formals/defaults and local returned-lambda constructors continue ordinarily. Existing
argument/capture closures can return through value leaves. Independent arity cache
slots prevent an unsuitable arity from rejecting a later suitable one.

The initial structural check examines only the reached outer body. After the hot ordinary oracle has run, `createSaturated` discovers the
chain using already-indexed bodies, without lookup, forcing or further minting. Each formal maps to an explicit `args[index]` leaf;
other root captures resolve through the original outer closure's environment. Nonformal local SSA definitions owned by an eliminated
stage remain opaque deopt branches and are never looked up through nonexistent frames. Root argument indices apply only in the root
context; each inlined context has its own chain-formal bindings. An unrelated callee capture still resolves through its actual current
environment, even when its SSA identity equals a chain formal from another invocation. Supported calls in the final graph use the same
guarded specialization as unary plans.

No temporary stack frames are passed through generic `lookup` or `evalTail`; either could publish a thunk or closure retaining that
frame. The compiler does not evaluate unsupported local closure/container constructors or inspect their operands. A deferred shell's
empty body is never treated as evidence of no captures. Cases such as `a: b: (c: a)` and `a: b: { f = c: a; }` retain ordinary durable
environments. General local memo cells or new local closure publication remain future work and would need materialization shared with deoptimization.

Curried stages are sequential logical calls. Each runs at caller depth plus one; combining their graphs does not make them nested calls.
The shared `Impl::evaluateLazy` helper installs one checked logical scope around observation or native execution and restores caller depth
before fallback. Its oracle executes the original remaining call once at caller depth with the saturated hook disabled for that call;
nested calls use their normal eligibility. Inlined calls inside the final graph still enter deeper scopes, including during host demands.
Errors keep the original Apply and consumer positions. If any input pointer aliases `out`, the tier is bypassed without rejecting its
cache entry: an oracle write would otherwise destroy the original input before observation.

Each outer region has separate arity-two/three/four entries. There are at most 256 outer-region caches and 256 saturated candidate
records, separately from the 256 unary candidates; all tiers share the 16 compiler-attempt limit. The graph, leaf, block,
continuation, inline-depth and resume limits are unchanged. Each entry keeps its own hotness, bounded specialization/preflight state and
three successful native grace comparisons. Recursive oracle state is rechecked; native deopt retirement and deferred destruction use
the same `activeRuns` guard as unary plans. Dumps include `chain-count` and explicit root-argument indices.

`MLNIX_JIT_CURRIED=0` disables this hook while preserving unary compilation and guarded inlining. It is enabled by default within
`MLNIX_JIT=1`; the flag is cached at JIT construction and performs no per-call environment read.

## Validation, counters and cost

The historical [V1 local validation record](bench/local/calls-20261028/v1/validation-summary.txt) contains 236 focused exact comparisons across eager
and demand schedules. Each full schedule passes 479/479 semantic cases and 221 stored exact expectations; all 1,434 prior saved output,
error and status files are byte-identical per schedule. The focused tests cover:

- Direct Boolean wrappers and nested short circuits, with counters proving execution beyond grace.
- The same lambda operation under different closure environments, and a changed or unready callee after warmup.
- Unused throwing/tracing arguments, callee errors, predicate errors, and exactly-once traces before fallback.
- Original max-call-depth failures, recursion, cleanup after exceptions, and expanded node/leaf/inline budgets.
- Reentrant retirement while an inlined demand is suspended, including throwing cleanup, and the inline-off ablation.

The historical call-tier V2 passes [240 exact comparisons](bench/local/calls-20261028/v2/check-jit.txt), retaining those cases and adding explicit checks that a
host demand inside the callee sees its logical depth, and a later demand after native Leave sees the caller's restored depth.
Both V2 full schedules also pass 479/479 semantic cases and 221 stored exact expectations; all 1,437 saved output/error/status files
per schedule match V1 byte for byte ([validation record](bench/local/calls-20261028/v2/validation-summary.txt)).

Saturated-chain V1 passes [300 focused exact comparisons](bench/local/curried-20261028/v1/check-jit.txt), including 29 curried cases,
and [480/480 semantic language cases per schedule](bench/local/curried-20261028/v1/validation-summary.txt) with 222 stored exact expectations.
All 1,437 prior saved output/error/status files remain unchanged per schedule. Added coverage includes unused earlier arguments,
sequential depth for arities two through four, partial and escaping closures, formals/defaults and eliminated-region locals, wrong arity
followed by the right arity, same-SSA captures from different environments with proven native inlining, recursive admission and retirement
on successful and throwing paths, and the curried-off ablation.

The historical V1 same-binary [inline-off](bench/local/calls-20261028/v1/profile-inline-off-nixpkgs.txt) and
[inline-on](bench/local/calls-20261028/v1/profile-inline-on-nixpkgs.txt) diagnostic profiles retain the golden nixpkgs-73 output. The call
tier records 161,997 entered inline calls. `newFrame` allocations change from 3,193,780 / 266,271,360 bytes to 3,031,786 / 262,383,504 bytes:
161,994 fewer frames and 3,887,856 fewer requested frame bytes. Both runs allocate 11,769,738 Value rows. Native invocations rise from
399,236 to 885,230, exposing the additional guard/Enter/Leave round trips. These counts establish coverage and frame allocation changes;
they do not establish RSS savings or faster evaluation. The [V1 Kali report](bench/kali/calls-20261028/RESULTS-V1.md) measured
inline-off/on wall regressions of 1.1% / 3.1% on NixOS / nixpkgs-73, motivating the removal of ordinary Enter/Leave round trips.

The [V2 local profile](bench/local/calls-20261028/v2/profile-inline-on-nixpkgs.txt) retains 161,997 inline calls and has zero mismatches
or compiler failures. Native invocations are 561,236, versus V1's 885,230. This measures the protocol change; it does not establish an
end-to-end speedup. The [V2 Kali report](bench/kali/calls-20261028/RESULTS.md) records five paired inline-off/on wall changes of
+1.5% / +0.8% and whole-JIT-off/on changes of +2.2% / +3.9% on NixOS / nixpkgs-73. Frame and Value allocation evidence remains
distinct from timing and RSS; the native tier stays opt-in.

The saturated V1 same-binary demand nixpkgs-73 [curried-off](bench/local/curried-20261028/v1/profile-curried-off-nixpkgs.txt) and
[curried-on](bench/local/curried-20261028/v1/profile-curried-on-nixpkgs.txt) profiles retain output hash `5e8fff662dff`, with zero mismatches
or compiler failures. Three saturated kernels complete 188,515 calls, including nine grace comparisons. Actual frame allocations and
Value allocations each fall by 188,506, a combined reduction of 9,048,288 requested bytes. The [Kali report](bench/kali/curried-20261028/RESULTS.md)
confirms 77,354 / 188,506 fewer frames and Value rows on NixOS / nixpkgs-73, but curried-off/on wall time rises 0.5% / 2.8%.
Whole-JIT-off/on rises 2.8% / 3.6%, and the default-path control is mixed. The allocation savings do not establish a throughput or
cache-locality improvement; native execution remains opt-in.

Projection V1 passes [370 exact comparisons](bench/local/projection-20261028/v1/check-jit.txt) and
[481/481 semantic cases per schedule](bench/local/projection-20261028/v1/validation-summary.txt), with 223 stored exact expectations
and all 1,440 prior saved files unchanged per schedule. Its 33 new cases exercise saturated inline arities, unused projected arguments,
key/base/field order, changed captures and callees, layered and cached-flat lookup, predicate and ordinary consumer diagnostics,
logical depth, memoized fallback and recursive retirement. The [inspectable example](bench/local/projection-20261028/ir-v1/README.txt)
shows the three-root-argument/two-inline-argument plan and generated code, with exactly-once traces and skipped throwing inputs.
The [projection Kali report](bench/kali/projection-20261028/RESULTS.md) measures 17,253 / 28,701 fewer frames and 8,430 / 21,368 fewer
Value allocations on NixOS / nixpkgs-73. Projection-off/on wall time changes −1.0% / +2.5%; whole-JIT-off/on changes +1.2% / +2.0%.
New callback inlining partly replaced existing curried execution, so their counters were not independent savings. At that Boolean-only
stage, bare non-Boolean projection results and unsupported reached branches created frequent fallback, motivating the subsequent
persistent-value return extension. Those historical measurements do not measure that extension.

Values V1 passes [472 exact comparisons](bench/local/values-20261028/v1/check-jit.txt) on macOS and Kali, with
[482 semantic cases and 224 stored exact expectations per local schedule](bench/local/values-20261028/v1/validation-summary.txt).
All 1,443 prior saved output/error/status files remain unchanged. The 46 new cases exercise persistent cell returns, empty recipes,
strict Boolean errors, unforced payloads, current captures, nested value Leave paths, reentrant lifetime and ablations. The
[value-return IR guide](bench/local/values-20261028/ir-v1/README.txt) follows both cell and empty-list paths through two nested scopes.
The [Values Kali report](bench/kali/values-20261028/RESULTS.md) measures 160,781 / 333,549 fewer frame allocations and 33,443 / 283,512
fewer Value allocations on NixOS / nixpkgs-73 against VALUES=0. Paired RSS falls 0.3% / 1.2%, while wall time changes +0.2% / +1.7%.
Whole-JIT-off/on wall time rises 5.9% / 6.2%. Curried fallbacks fall 2,110 → 139 on NixOS but rise 1,482 → 17,137 on nixpkgs;
the latter mostly comes from the unsupported nonempty arm of `optional`. Fewer allocations have not yet produced a throughput win.

List Returns V1 passes [536 exact comparisons](bench/local/list-returns-20261028/v1/check-jit.txt) on macOS and Kali and
[483 semantic cases per local schedule](bench/local/list-returns-20261028/v1/validation-summary.txt), with 225 stored exact expectations.
All 1,446 prior saved files remain unchanged. Its 29 new cases prove lazy/cyclic elements, current handles, nonforcing capture lookup,
nested Leave/depth behavior, retirement lifetime, exclusions and ablations. The [list IR guide](bench/local/list-returns-20261028/ir-v1/README.txt)
maps a three-element recipe through two call scopes. The [Kali report](bench/kali/list-returns-20261028/RESULTS.md) records zero curried
`optional` fallbacks and 120,304 / 34,274 fewer frames plus 60,152 / 17,137 fewer Value allocations on NixOS / nixpkgs-73.
LISTS-off/on wall time changes +1.2% / −7.6%, with nearly unchanged minima and no peak-RSS reduction; whole-JIT-off/on rises
6.5% / 4.0%. The noisy timing series does not establish a robust speedup from these allocation savings.
Four balanced hardware-counter pairs show cache-miss ranges crossing zero, with package signs following run order; the report does
not claim a repeatable locality improvement.

`MLNIX_STATS` reports actual `newFrame` count/bytes/slots separately from Value writes and allocations. The `boolean_inline_compiled`
counter counts engines containing inline calls; `boolean_inline_calls`, `boolean_guard_misses` and `boolean_depth_entries` count runtime
scope entries, failed callee guards and logical depth increments. V2 copies entry/depth counts from Runtime after native returns.
`boolean_specializations` and `boolean_specialization_deopts` count
graph rebuild attempts and unsuccessful rebuilds, separately from the observer's preflight counters. Runtime counts are aggregated only
after a run returns; a throwing run's demands, resumes and call counters are omitted. `compile_ns` measures elapsed wall time within
compiler attempts, including failures and initial setup, but excludes oracle execution and specialization. It is not compiler CPU time
or total JIT cost.

Saturated counters report candidate records, compiled kernels, executions, completions, grace, deopts, rejections and dispatches by
arity as `curried_*`. Saturated executions also contribute to the shared Boolean counters. After each trusted completion,
`curried_frames_saved` adds the semantic chain arity and `curried_values_saved` adds arity minus one. These are chain-storage estimates:
the existing unary JIT can already omit a final-stage frame, so they are not incremental savings against curried-off. Actual `newFrame`
and `allocValue` deltas are decisive. In the local profile the estimated frame counter is 377,012 while the measured reduction is 188,506.
Separate `jit-curried` profile rows give each outer location/arity's calls, completions, grace and deopts; they do not contaminate unary
rows whose call counts omit trusted saturated executions.

`boolean_projection_compiled` counts engines containing virtual Select recipes. Runtime `boolean_projection_requests` counts reached
resolution/peek attempts, `boolean_projection_forces` counts key/base/field force actions and `boolean_projection_deopts` counts
unavailable observe-only projections. `boolean_projection_flat` and `boolean_projection_layered` count their lookup representations;
`boolean_projection_cached_flat` is a subset of layered. Observer-only runs have zero forces. Each component force also contributes to
`boolean_demands`, so one projection request can now add up to three demands. These counts omit throwing runs and the separate C++
preflight observer, following the existing aggregation boundary. `boolean_saturated_inline_compiled` counts engines with multi-argument
inline chains, and `boolean_saturated_inline_calls` counts reached Apply boundaries, not their individual sequential stages. Those calls
also contribute to `boolean_inline_calls`; profile rows include projection request/force and saturated-inline counts.

The legacy `boolean_*` names now aggregate the whole lazy graph tier, including cell and recipe completions. `lazy_value_compiled` counts
engines with value-return continuations, `lazy_value_completions` counts completed cell, empty or list-recipe results, `lazy_value_grace` counts their completed
observe-only comparisons, and `lazy_value_mismatches` counts oracle disagreements on that path. Profile rows add `value_completions`.
A returned Boolean cell is still a value-path result; these counters distinguish protocols rather than only non-Boolean types.
`lazy_empty_completions` is the subset completing an empty recipe, including grace where the observer constructs nothing additional.
`lazy_list_compiled` counts engines with nonempty list returns; `lazy_list_completions` and profile `list_completions` count that subset
of value returns, including grace. `lazy_list_handle_lookups` counts trusted missing-capture `lookup` calls, with no element force;
existing-handle peeks are excluded and throwing runs are omitted, as with other runtime counters.
Validation is shallow, and these counters alone establish neither allocation counts, deep evaluation nor an allocation or throughput improvement.

With 163,020 calls and a 1,024-call threshold, each additional millisecond of compilation needs roughly 6.2 ns saved per remaining call
to repay itself, before guard overhead. Measure the actual compiler cost; do not reuse an assumed per-body cost. Require unchanged output
hashes and useful execution coverage, then an interleaved same-host A/B including compilation and startup. Keep the tier opt-in if wall,
CPU or allocation results do not justify it. Reuse accepted Nix/Lix reference records rather than rerunning them for this experiment.

The larger follow-on is generic fusion of a single-use list/record producer into its consumer, such as
`listToAttrs (map callback (attrNames set))`. That could remove intermediate containers, but must preserve lexical callback order,
duplicate-name precedence, builtin diagnostic contexts, fresh observable identities, and escaping lazy value thunks. It needs explicit
closure and escape handling first and is not claimed by this call-inlining plan.

[The durable-environment design](JIT-ENVIRONMENTS.md) specifies that prerequisite: invocation-owned interpreter frames,
memoized local demands shared with fallback, nonforcing grace over the actual oracle activation, and escaping values that retain no
native-plan storage. It separates indexed locals from `kNoSlot` computations, which need an interpreter-visible memo override or precise
deoptimization continuation before effectful local execution can be safe. This is an implementation plan, not current compiler coverage.
