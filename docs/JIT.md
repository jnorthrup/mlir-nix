# Guarded native compilation

`MLNIX_JIT=1` enables experimental native compilation for hot integer lambdas, lazy value selectors and graphs with explicit demand
continuations, Boolean control flow, guarded string equality, persistent value returns and bounded container recipes, including guarded calls and saturated unary-lambda chains. The default evaluator remains interpreted. Unsupported
computation returns to the interpreter.

```text
TrikeShed source spans / Series / deferred-body Cursor
    -> nix graph regions (lazy sea of nodes)
    -> cached arithmetic plan, pointer recipe or lazy demand/CPS IR
    -> typed func / arith / cf / LLVM pointer MLIR
    -> LLVM dialect
    -> LLVM IR + ORC native code
```

The arithmetic plan contains the lambda argument, integer constants, and checked integer addition, subtraction and multiplication.
It recognizes the default numeric primops and the numeric use of Nix's `+`. Its native entry requires an argument already tagged `Int`;
it never forces an argument to discover an arithmetic specialization. Arithmetic captures, branches and function calls stay interpreted.
Unreachable definitions are never walked or forced.

The pointer tier recognizes graph structure, independently of source names: `x: x`, `x: capturedValue`, and a captured-Boolean `if`
choosing between `x` and an empty attribute set, list or string. Either branch direction is supported. All these shapes reuse one native
pointer-selection kernel. It receives values from the current call; no captured pointer or Boolean is baked into code cached by lambda.
The host resolves each capture through the current closure environment and refuses captures without a persistent frame cell.

Demand stays with the host. A conditional first forces its captured condition at the original `nix.if` position. Only the selected
argument is then forced, at that same position; an identity forces its result at the original call-site position. The empty arm constructs
a fresh empty set or list, or an empty string, without touching the argument. Failed forcing propagates directly rather than retrying a
thunk whose effects might repeat. A successfully forced condition with the wrong type returns to the interpreter for its original error
context. Generated code performs no forcing and cannot unwind Nix exceptions.

Each unary region caches a stable plan pointer or a shared rejection marker, so warm calls do not reanalyze the graph or hash its lambda.
Calls with a cached rejection bypass JIT dispatch entirely. Diagnostic profiling disables that unary refusal bypass, retaining observations
of rejected unary calls.
The existing call-depth check still applies. Completed native calls after validation bypass the called lambda's frame allocation and
intermediate thunk cells; forcing a required input still uses the evaluator.

## Lazy demand and continuation IR

The graph compiler accepts direct single-argument lambdas and exactly saturated chains of two to four unary lambdas. Its graph
vocabulary includes Boolean literals, argument handles and persistent captures, all nine `nixty.is_*` predicates, `!`, `&&`, `||`, `->`,
`if`, single-component static `has_attr`, lazy projections, guarded string `==`/`!=`, and guarded calls supplying one to four arguments. Atomic Boolean
consumers may demand a persistent cell or a supported projected leaf; a tail expression can return that cell's arbitrary WHNF value
or an empty attribute-set, list or string recipe.
Captures resolve through the current closure on each call. The arithmetic tier still requires an already evaluated integer; the graph
tier can demand a lazy input when the original graph requires it.

Control flow is compiled in continuation-passing style: each Boolean node receives true and false destinations. Negation swaps them;
AND, OR and implication route to their right operand only when required. An `if` routes to its selected arm. Shared graph nodes can have
different continuation instances, so both source graph size and emitted control flow are bounded. No SSA intermediate is assumed to
survive a return from the native kernel.

The call tier's V2 native entry is `uint64_t scalar(uint32_t resume, Runtime *runtime)`, still `(i32, ptr) -> i64` in MLIR. Resume zero enters the
graph; other resume values are the destination ID plus one. Results encode false, true, demand, deopt or invalid in the low three bits
(`0` through `4`), depth overflow (`5`), value completion (`6`) or callee-guard miss (`7`). Requests carry their continuation ID in the remaining bits.
A forcing demand identifies a persistent or projected leaf and its original consuming operation. The host resolves that leaf, forces it if needed, then
resumes the consumer. The same request transport also supports reached callee peeks and batched nonforcing list-handle resolution.
The stack-local Runtime contains 16 cell pointers, 64 closure-environment pointers and active flags, the
initial/maximum/relative call depths, current context, inline-call counts and a `resultLeaf` cell/recipe code initialized invalid. Only live cells and active flags are initialized, along
with the root environment; each child environment is written before activation and read only while active. Native code never calls
the evaluator.

Host forcing preserves the original operation's position. Persistent type-predicate demands use `callPrimOp`, retaining the builtin's error-trace wrapper.
Other demands use `forceValue`. A non-Boolean leaf in a strict Boolean context returns to the interpreter for its original type diagnostic.
A tail leaf can instead return that value natively: `x: if true then x else false` can return an integer argument without a Boolean guard.
Static `has_attr` forces the base, tests its tag, and binary-searches flat attribute rows using their interned symbols. A non-set or a
missing name produces false. The final attribute value is never read or forced. Layered sets return to the interpreter to preserve
shadowing behavior.

An unsupported local node becomes a deopt destination without traversing or forcing its operands. A graph needs at least one path that
can complete natively; supported cycles and plans exceeding a bound are refused. For example, the usual `lib.isFunction` graph can
complete its function-tag and missing-`__functor` paths while leaving the recursive functor application to the interpreter. This is a
general graph rule, independent of library names. After a successful demand, whole-lambda fallback is safe because the persistent cell
is memoized. A failed force propagates immediately; it is never caught and retried. Native execution never forces a local in-place
temporary before falling back, and never unwinds a C++ exception through generated code.

Guarded calls require a persistent callee and one to four persistent or projected arguments. After a hot interpreter call,
specialization reads only already-WHNF lambda targets and already-indexed bodies; it neither forces a callee nor mints an unvisited body.
For a saturated inline chain, each nonfinal body must directly return the next unary lambda. Each call context maps all chain formals to
the caller's leaf handles and excludes unmapped locals owned by eliminated stages. At every reached apply, generated code guards the
outer callee tag and lambda-operation identity before entering the final graph. Other captures resolve through that outer closure's
current environment, independently of any equal SSA identities in the caller. Missing, lazy or changed callees fall back without
demanding an argument. Sequential curried stages share one relative-depth increment; calls nested inside the final graph still add depth.

The callee graph itself is lowered into MLIR/LLVM. Ordinary Enter/Leave bookkeeping now stays in generated control flow: native code
checks scope and depth, installs the current closure environment, clears that context's capture cells, updates relative depth and
branches directly into or out of the callee. Depth overflow alone returns status `5`, and the host raises the original error at the
apply position; observe-only validation does not raise a new depth error.

During actual host forcing, scoped cleanup temporarily installs `initialDepth + runtime.depth` as evaluator `callDepth`, then restores
the base depth on success or exception before resuming native code. This uses the active call scope even when a callee's formal is a
substituted root-argument cell. After native Leave, later caller demands use the caller's depth. Identity-callee tail demands retain the apply position, while a
non-Boolean result in a strict Boolean context falls back for the enclosing operator's diagnostic. Formals/defaults and arbitrary local temporary arguments remain
unsupported. [JIT-CALLS.md](JIT-CALLS.md) records the implementation and remaining work.

## Guarded string comparisons

An `Eq` or `Neq` node can compare persistent argument/capture cells, supported projections and literal string bytes. Its CPS sequence
demands the left operand and then the right operand to WHNF before checking either string tag. This preserves general equality's
effect and error order even when the left value is not a string. Other operand types deopt to ordinary equality after those successful
demands, retaining numeric coercion, deep container comparison and function behavior. A failed demand propagates once.

The native comparison checks lengths and then bytes, including the zero-length case. It does not inspect or mutate string contexts.
Literal bytes live in immutable plan-owned storage pinned by `activeRuns`; dynamic data and lengths are loaded again after the final
host demand. No native payload pointer is carried across a force or recursive code retirement. The observer follows the same
continuations using only already-realized cells. An unselected comparison does not request either operand.

Literal operands and cell/projection leaves share 16 operand slots. Literal definitions also count against the 64-node budget, with
at most 4,096 aggregate literal bytes. The comparison and its separate operand-demand continuations share the existing block,
continuation and 32-native-invocation bounds. Two unavailable operands can require two host resumptions; the implementation does not
assume that new native coverage removes demand overhead. General local computed strings remain outside this persistent-cell tier.

## Tail values and empty-result recipes

Root argument/capture leaves and supported projections can return any existing WHNF value, including strings with their context,
paths, shallow lists/sets and existing closures or primitive functions. Tail `if` arms and guarded inline calls propagate these results.
Zero-operand local attribute-set/list constructors and an empty string literal can instead return an empty-result recipe. These recipes
have no fields, captures or lazy child computations; arbitrary local constructors remain unsupported.
The compiler adds a value continuation alongside the Boolean true/false destinations. An `if` passes it only to its arms; `!`, `&&`,
`||`, implication, predicates and `if` conditions retain strict Boolean evaluation. Computed Boolean operations still return statuses
`0` or `1`; returning an existing Boolean cell uses the value path like any other WHNF cell.

A native ReturnValue continuation first demands WHNF, then stores its known leaf index in Runtime and branches through every required
native Leave. A separate terminal returns status `6`; it has no resume-switch entry. Boolean terminal IDs/statuses `0` and `1` stay fixed;
ordinary continuation IDs are assigned per plan and can shift when the graph changes.
The host accepts a cell result only with relative depth zero, root context active, a bounded return-enabled leaf index, and a nonnull WHNF cell.
It then copies that cell into `out`. The cell belongs to an existing argument, closure environment or selected field, not a temporary
frame or compiler allocation. Leaving an inline context does not invalidate its persistent cells. `activeRuns` keeps the plan/code
alive through host forcing and result copy, including recursive retirement and exceptions.

ReturnEmpty takes the same value-continuation and native Leave route without demanding a cell. It writes code `17` for empty attrs,
`18` for an empty list, or `19` for an empty string. These codes are disjoint from cell indices `0..15` and the invalid initial code.
After the complete context unwind, status `6` is accepted only if the recipe code is in range and enabled by the plan's separate recipe
allowlist. The host constructs a fresh empty set/list, or a context-free empty string, only on trusted completion. It does not reuse a
cached container. Empty constructors in a strict Boolean context deopt for the interpreter's original type/context error.

A tail list with one to four persistent element handles can return a nonempty recipe. Native code checks handle availability without
reading element tags: thunks, applications and blackholes are valid lazy elements. Missing captured handles are resolved together by
the host using nonforcing `lookup` in the current closure environment, before native Leave clears that context. This does not perform
a predicate, projection or value force. Root argument handles need no lookup. After complete scope unwind, the host validates the
plan's list descriptor and copies the ordered pointers into `RunResult`; it allocates a fresh list array only on trusted completion.
The result never refers to temporary Runtime or plan storage. Duplicate elements keep their original shared cell.

List recipes accept existing arguments and captures, including substituted inline formals. Every element must qualify before a
recipe is built. A current-local computation, virtual projection, eliminated-frame local or uncached `kNoSlot` capture keeps the
constructor on the interpreter path. In particular, `[x.field]` cannot use a projection recipe: constructing that list must not force
the set or selected field. Larger lists and local thunk/closure construction still need further lowering.

Bare root tails force at the original call-site position, `if` tails at the If position, and inline tails at the Apply position.
Projections always retain their own Select position and component ordering. Only WHNF is demanded: list elements and attribute values
remain lazy, and returned closures retain their actual environments. Apart from empty and bounded persistent-element list recipes, the compiler does not generate
local allocating constructors or make an escaping closure that depends on an eliminated frame. Such computations keep the interpreter path; an already existing value
of the same type can be returned safely.

Preflight and native grace follow the same Return/Leave paths without forcing another cell. Missing or still-lazy return cells deopt.
`sameValue` compares the oracle with the returned WHNF payload shallowly: scalar payloads, string/path storage, container storage and
closure operation/environment identity. Empty recipes use `sameEmpty`, checking the empty type/shape and absence of string context;
the observer and native grace create no extra container or string. Nonempty list recipes compare only list length and ordered element
pointer identities, allowing elements to remain unevaluated. Missing handles deopt; the observer never calls `lookup` to create one.
Grace returns the already computed oracle value. None of these comparisons
performs deep equality or forces a container member. An invocation whose input cell
aliases `out` bypasses the shared graph helper before admission or oracle execution, without rejecting its cached plan.

## Lazy one-key projections

A one-key `Select` with no default can be a virtual leaf rather than an allocated argument thunk. Its base must be an actual persistent
cell; the key is either static or another actual persistent cell. Formal substitution does not relax this requirement: a virtual
projection cannot itself serve as another projection's base or key. Projected callees, defaults and multi-component paths remain opaque.
Merely passing a projected argument does not resolve its key, base or field. If the selected callee ignores that argument, all three remain
untouched. These recipes support generic graphs such as `name: !(pred name set.${name})`, without identifying a library function by name.

On a reached demand, the host first uses `forceStringNoCtx` for a dynamic key, with the original attribute-name context and Select position,
then interns the key. The shared `EvalState::selectField` helper forces and checks the base, preserves missing-attribute/type diagnostics,
and returns the stable, unforced field cell. The host forces that field at the Select position before resuming the atomic consumer.
If the consumer is a type predicate, the whole key/base/field sequence retains its original builtin error-trace wrapper. Select itself
adds no extra attribute trace. Failed forcing propagates immediately; successful component forces remain memoized before any later fallback.

The projection observer only peeks existing WHNF cells. Dynamic symbols use `symbols.map.find`, with no interning; wrong or unavailable
keys, bases or fields conservatively deopt. `Bindings::get` supports flat and layered sets, including an existing cached flat view,
without flattening or allocating; top-layer shadowing is preserved. This differs from the separate native `has_attr` search, which still
deopts on layered sets. Projection forcing runs in the active logical call scope, and native code never unwinds a host exception.

## Saturated unary-lambda chains

An additional hook in `callFunction` runs after the reached function is forced and before intermediate results or frames are allocated.
It accepts two to four remaining arguments when each nonfinal body directly returns the next unary lambda and the final body has a
supported Boolean, persistent-value or bounded-recipe path. The hook can accept an eligible suffix after an ordinary application prefix. Partial applications, oversaturated
candidates, formals/defaults and local returned-lambda constructors keep the ordinary path. Existing captured or argument closures can
be returned through a value leaf. Descendant bodies are inspected only after the ordinary
oracle has indexed them; admission performs no additional minting, lookup or forcing.

Each chain formal maps to its existing `args[index]` cell. Other captures resolve from the original outer closure's environment. A local
definition owned by an eliminated stage becomes an opaque deopt unless it is an explicitly mapped formal. Substitution applies only to
the root context: an inlined callee still reads its own current environment, even when it captures the same SSA formal from a different
invocation. No temporary interpreter frames are placed on the stack. Unsupported descendants and escaping closures retain the ordinary
representation and durable environments.

Curried stages are sequential calls at the same depth relative to the caller. The shared lazy execution helper adds one logical call
scope around observation or native execution, restoring it before fallback. The oracle runs at the original caller depth and executes
the original remaining call once with that saturated hook disabled; nested calls remain eligible normally. Existing native inlined-call
depth checks, host-demand scopes and diagnostic positions still apply. An input cell that aliases `out` bypasses this tier without
rejecting its cache entry, because the oracle would overwrite that input before validation.

Each outer region has independent cache slots for arities two, three and four, with separate hotness, admission and grace state. A failed
arity does not reject another arity. These entries reuse graph specialization, post-oracle preflight, three successful native grace
comparisons, bounded deopt retirement and `activeRuns` lifetime protection.

## Speculation and grace

Memory effects and totality are separate MLIR contracts. Only the six literal kinds retain `Pure` (which includes unconditional
speculation). Fallible or forcing core operations declare `NoMemoryEffect` without unconditional speculation. Stock loop motion
tests in `test/mlir/speculation.mlir` keep those operations inside a potentially empty loop while moving total literals out.
The identity/effects/CSE tests continue to apply.

Each compiled arithmetic node sign-extends its signed 64-bit operands to 128 bits, calculates there, truncates, and checks that
sign-extension reconstructs the exact intermediate. Two signed 64-bit factors fit in signed 128 bits. Every intermediate is checked:
`(x + 1) - 1` must still fail when the first addition overflows. No signed-overflow assumption or poison is used to hide that error.
Any overflow returns to the interpreter, which produces the original error and trace in the original evaluation order.

Every pointer-kernel call checks the returned pointer against the structural recipe before forcing any selected value, including after
the grace period. A bad selector therefore cannot make an unused throwing or tracing argument observable. During the first three
successful calls of each pointer entry, the interpreter runs first; validation then compares shallow WHNF payload identity or the empty
constructor recipe. It never recursively compares containers or forces another value. Arithmetic entries likewise compare their first
three successful native results with the interpreter. The interpreter's answer is returned during grace. A mismatch disables that
lambda's native entry. These checks supplement structural proofs and guards; three matching inputs alone are not a correctness proof.

Before a hot graph entry's first compilation, the interpreter runs once as the oracle. Plans containing eligible opaque calls are
retained cold, then specialized from that observation before preflight. A pure C++ observer then walks the same expanded CPS
plan, reading only existing persistent cells. It reads capture slots directly: it does not call `lookup`, allocate cells, force
thunks, or execute an unsupported branch. Compilation is admitted only after a completed Boolean, shallow cell or bounded recipe observation matches
the oracle. An absent handle or a still-lazy cell whose WHNF is required is never forced by admission; list elements need only a handle.

An observed deopt delays compilation while returning the oracle result. A later eligible input can still admit the entry before the
limit of 64 combined specialization/preflight deopts; reaching that limit installs the shared refusal marker and discards the plan
without creating an engine or spending a compiler attempt. This admission check does not replace native grace. Its oracle result is reused for the first native
comparison, so the triggering call's effects are not repeated. Because the oracle can recursively compile, validate, refuse or retire
the same entry, the caller rechecks entry state after it returns instead of retaining a plan pointer across interpretation.

Graph entries use the interpreter as the oracle before their first three successful native completions. The subsequent native run is
observe-only: it may resolve captures and inspect cells already demanded by the interpreter, but it cannot force another thunk. A request
for an additional force cannot be executed during grace. Invalid protocol results disable the entry; unavailable value-return or
projection observations deopt. Completed results must match the oracle, using shallow `sameValue` for cells, `sameEmpty` for empty recipes,
and ordered element-pointer comparison for nonempty list recipes; a deopt returns
the already computed interpreter result without running it again and does not advance grace. After grace, demanded host effects run once,
in graph order, and an unsupported reached branch resumes interpretation with successfully forced cells memoized.

Entries reach the compilation threshold after 1,024 eligible calls by default; graph entries must also pass the post-oracle preflight.
`MLNIX_JIT_THRESHOLD=1` makes the path testable on small examples.
There are at most 256 unary candidate records and, separately, 256 saturated outer-region caches and 256 saturated candidate records
across their three arities. All tiers share 16 compiler attempts. Arithmetic plans permit 64 reachable nodes. The pointer shapes use
constant-size recipes and one shared compilation. Rejected plans use a shared marker stored in the region; they do not allocate a record
per repeated call. Each lambda retains its own hotness and grace counts even when its generated kernel is shared.

Graph plans permit at most 64 expanded source nodes including projection recipes, 16 total cell/recipe leaves, 256 continuation specializations and 256 emitted blocks
including helpers, with inline depth capped at four. Value-return blocks, extra Leave continuations and the value terminal count against
the same budgets. These bounds apply across callees. Recursive inline edges remain opaque fallback
branches. A run permits at most 32 native invocations, including initial entry and demand/callee-resolution resumes; exceeding this limit disables
the entry and falls back.

A compiled graph entry retires after 64 successive native deopt results without a native completion. This releases code that was
already compiled. Retirement installs the shared refusal marker immediately, so later calls bypass its native dispatch.
An `activeRuns` guard retains its expanded plan and machine code while any suspended host demand can still resume it, including a
demand from an inlined callee. Destruction is deferred until the last active run exits, including exception unwinding. Retirement does not
replenish the candidate or compilation-attempt budget.

No JIT context is created while the feature is disabled. An explicit `MLNIX_PRIMS_IRDL` replacement disables this tier because a
replacement declaration may change the meaning of an operation name. Compilation failures fall back to interpretation.

## Inspect and test

```sh
cmake --build build --target mlnix mlnix-opt
MLNIX_DEFER=1 MLNIX_JIT=1 MLNIX_JIT_THRESHOLD=1 MLNIX_STATS=1 \
  MLNIX_JIT_DUMP=/tmp/mlnix-jit-ir build/bin/mlnix instantiate --eval --strict -E \
  "builtins.foldl' builtins.add 0 (builtins.genList (x: ((x * 3) - 1) + 7) 12)"
python3 scripts/check-jit.py
python3 scripts/run-mlir-tests.py
MLNIX_JIT=1 MLNIX_JIT_THRESHOLD=1 python3 scripts/run-lang-tests.py
MLNIX_DEFER=1 MLNIX_JIT=1 MLNIX_JIT_THRESHOLD=1 python3 scripts/run-lang-tests.py
```

`MLNIX_JIT_DUMP` saves `scalar-N.typed.mlir`, `scalar-N.llvm.mlir` and optimized `scalar-N.ll` as compilation reaches each stage.
Graph compilations also save `scalar-N.plan.txt`: source node kinds, leaf indices, continuation edges and consumers, symbols and bounds.
Expanded plans include call contexts, callee handles and native Enter/Leave edges. Saturated plans also show `chain-count` and each
root leaf's explicit argument index.
Projection recipes show their base leaf and static symbol or dynamic-key leaf; expanded call nodes show their argument arity. These
recipes remain visible in the plan dump while MLIR/LLVM contains the consuming control flow and demand continuations.
Value plans show `value-returns`, ReturnValue/ReturnEmpty/ReturnList actions, recipe names/codes, ordered list leaves, the separate value-terminal sentinel and
the third Leave route where required.
The emitted terminal returns status `6` after those native Leaves.
Set `MLNIX_JIT_DEBUG=1` to print MLIR compilation diagnostics; they are quiet by default.
For a small Boolean example, use the same environment above with `-E 'let f = x: builtins.isFunction x || x ? __functor; in f {}'`.
`MLNIX_JIT_INLINE=0` disables call acceptance during cold plan construction, preserving the other JIT tiers for a same-binary ablation.
Inlining is enabled by default within the opt-in JIT; this switch adds no hot-path environment reads.
`MLNIX_JIT_CURRIED=0` disables the saturated-chain hook while preserving unary compilation, including guarded inlining. Saturated
compilation is enabled by default within the opt-in JIT; its setting is read once when the evaluator's JIT is created.
`MLNIX_JIT_PROJECTION=0` disables virtual Select-leaf acceptance at cold plan construction. Saturated inline expansion remains enabled
for persistent arguments; `MLNIX_JIT_INLINE=0` still disables all inline Apply expansion. Neither flag adds per-call environment reads.
`MLNIX_JIT_VALUES=0` restores Boolean-only CPS construction, disabling cell returns and all result recipes while retaining projection support. It adds no value continuation, terminal
or extra Leave route; the independent pointer tier still supports its existing identity/selector recipes. The setting is read during
cold plan construction, with no per-call environment lookup.
`MLNIX_JIT_LISTS=0` independently disables nonempty list recipes, preserving persistent-cell and empty returns. It is also read during
cold plan construction and is subordinate to `MLNIX_JIT_VALUES`. Lists share existing source/leaf/continuation budgets and the 32-resume limit.
`MLNIX_JIT_STRINGS=0` disables guarded string equality during cold plan construction, independently of `MLNIX_JIT_VALUES`.

`MLNIX_STATS` reports compilations, native executions, grace comparisons, rejected candidates, type misses, overflows, mismatches
and compiler failures. Pointer counters distinguish argument identities, captured-value identities and conditional selectors.
`compile_ns` is elapsed wall time inside compiler attempts, including failed attempts, initial LLVM/MLIR setup and any enabled IR dumps.
It excludes interpreter-oracle work, plan analysis and specialization, and is not CPU time or the full cost of the JIT.
The legacy `boolean_*` names now aggregate the whole graph tier, including cell, empty and nonempty-list recipe completions. Counters are
`boolean_compiled`, `boolean_executions`, `boolean_completions`, `boolean_demands`, `boolean_resumes`,
`boolean_deopts`, `boolean_grace`, `boolean_mismatches` and `boolean_retired`. Demands count actual host forcing actions, not capture
resolution; resumes count native invocations including initial entry. Demands and resumes are aggregated only when a run returns, so
both omit work from a run whose host demand throws. An execution may therefore have no recorded completion, deopt or demand.
One projected demand can force its key, base and selected field, so `boolean_demands` can increase by three for one projection request.
Demand counts across versions therefore describe actual component forces, not one uniform count per selected argument.

`lazy_value_compiled` counts engines with value-return continuations, `lazy_value_completions` counts completed cell, empty or list-recipe results,
`lazy_value_grace` counts their completed observe-only comparisons, and `lazy_value_mismatches` counts their oracle disagreements.
A returned cell can itself contain a Boolean; these counters distinguish the return protocol, not just non-Boolean payloads. Profile
rows include `value_completions`. `lazy_empty_completions` is the subset returning empty recipes, including grace comparisons where no
extra object is constructed. Return counts therefore do not directly measure allocations, deep evaluation or an allocation saving.
`lazy_list_compiled` counts engines with nonempty list-return continuations. `lazy_list_completions` and per-location `list_completions`
are subsets of the value counts, including grace. `lazy_list_handle_lookups` counts trusted host `lookup` calls needed for missing
captured element cells; it excludes already-existing handles and observer peeks, and does not count element forcing. As with other
run counters, throwing runs are omitted.

`string_compiled` counts engines containing guarded comparisons; `string_comparisons` counts reached comparisons whose two operands
pass the string guards, including native grace. `string_guard_deopts` counts native type-guard failures after both WHNF demands.
Per-location rows include successful string comparisons. Separate unary kernels compiled during a saturated call's interpreter oracle
also contribute to aggregate counts; these totals must not be added to the curried subset. None of these counters measures string
bytes read or establishes a throughput improvement.

Preflight has separate counters: `boolean_preflight_attempts` counts observer passes, `boolean_preflight_deopts` counts their deopt
results, and `boolean_preflight_rejections` counts entries refused during preflight. Refusal includes the 64-deopt limit, an unavailable
or invalid observation, an oracle disagreement, or an exhausted compiler budget after recursive interpretation. These are not native
executions or `boolean_retired` events, and successful preflight does not increment the three native grace checks.

Call counters are `boolean_inline_compiled` (engines containing an inline call), `boolean_inline_calls` (entered inline scopes),
`boolean_guard_misses` (callee guards that returned fallback), and `boolean_depth_entries` (logical depth increments).
`boolean_specializations` counts cold graph rebuild attempts; `boolean_specialization_deopts` counts attempts that could not produce
a completable expanded plan. Their misses share the 64-miss admission limit with observer deopts. Runtime call counters, like demands
and resumes, are aggregated only after a run returns and omit all work in a run whose host demand throws. The separate
`frame allocations: count=... bytes=... slots=...` line measures actual `newFrame` allocations; Value tag writes are not allocation counts.

Saturated counters are `curried_candidates`, `curried_compiled`, `curried_executions`, `curried_completions`, `curried_grace`,
`curried_deopts`, `curried_rejected` and the dispatch counts `curried_arity2/3/4`. Their executions also contribute to the shared
Boolean counters. After a trusted completion, `curried_frames_saved` adds the chain arity and `curried_values_saved` adds arity minus one.
These are semantic chain-storage estimates, not measured allocation deltas against the existing unary JIT, which may already avoid a
final-stage frame. Compare actual `newFrame` and `allocValue` counts to establish incremental savings.

Projection counters are `boolean_projection_compiled`, `boolean_projection_requests`, `boolean_projection_forces`,
`boolean_projection_deopts`, `boolean_projection_flat`, `boolean_projection_layered` and `boolean_projection_cached_flat`.
Compiled counts engines containing recipes, requests count reached recipe resolution/peek attempts, and forces count actual component
forcing actions, also included in `boolean_demands`. Deopts count unavailable observe-only projections. Lookup counts distinguish flat
and layered sets; cached-flat is a subset of layered. Observe-only runs perform zero forces. These runtime counters are aggregated only
when a native run returns, omitting throwing runs and the separate C++ preflight observer. `boolean_saturated_inline_compiled` counts
engines with multi-argument inline chains; `boolean_saturated_inline_calls` counts their reached boundaries, each also included in
`boolean_inline_calls`. It counts one boundary per Apply, not one entry for each sequential stage.

`MLNIX_JIT_PROFILE=1` additionally records a bounded diagnostic table of called graph shapes and argument readiness; it never forces
an input to collect those observations. Its per-shape rows include Boolean completion, demand, deopt and inline-call counts. Separate
`jit-curried` rows report outer location, arity, calls, completions, grace and deopts; saturated completions are not added to unary rows
whose call count excludes trusted saturated execution. Both profile kinds also report projection requests/forces and saturated-inline calls. The acceptance script
compares status, stdout and stderr with the interpreter on both schedules and separately requires counters proving that native execution,
grace checks and guard fallbacks actually ran. It also checks compilation limits,
the hotness threshold, custom-declaration opt-out, post-grace lazy demands, conservative branch fallback, delayed preflight admission,
recursive oracle state changes, and retirement during recursive demands and exception unwinding.
Call tests additionally cover current closure environments, reached target guards, logical depth and inlined suspension during retirement.
Saturated tests cover two to four sequential stages, current captures, partial and escaping closures, eliminated-region locals, distinct
arity caches, nested native depth, recursive admission and retirement, and the curried-off ablation.

## Measurement

```sh
python3 scripts/jit-bench.py --runs 5 --demand
python3 scripts/ab.py --runs 5 MLNIX_DEFER=1 'MLNIX_DEFER=1;MLNIX_JIT=1'
python3 scripts/ab.py --runs 5 'MLNIX_DEFER=1;MLNIX_JIT=1;MLNIX_JIT_INLINE=0' 'MLNIX_DEFER=1;MLNIX_JIT=1'
python3 scripts/ab.py --runs 5 'MLNIX_DEFER=1;MLNIX_JIT=1;MLNIX_JIT_CURRIED=0' 'MLNIX_DEFER=1;MLNIX_JIT=1'
MLNIX_JIT=1 python3 scripts/vs-nix.py --native --demand --reuse-refs \
  --ref "Nix 2.35.4=$NIX_BIN" --ref "Lix 2.91.3=$LIX_BIN"
```

The generated arithmetic sweep includes compilation, grace and process startup. Its three sizes expose compilation cost and payback;
every output must match an independently computed arithmetic sum. It cannot establish a nixpkgs speedup. The ordinary A/B harness
compares the two real repository workloads and rejects nonzero exits or any changing/differing result hash. Kali reference comparisons
use `vs-nix.py --reuse-refs`: accepted same-host Nix/Lix records and their output hash are reused without invoking those reference
binaries, including startup and RSS probes. Missing or incompatible records stop the run rather than trigger new reference timings.
Cached rows are labeled explicitly; their ratios are historical comparisons, not simultaneous measurements of host load. PMU counters,
when available, are sampled separately by `hw-counters.py`.

The [28 October Kali measurements](bench/kali/locality-20261028/RESULTS.md) put one million supported scalar calls at 0.574 s
interpreted versus 0.205 s with the tier, including compilation; peak RSS was 290 MB versus 196 MB (decimal). Neither real workload
compiled a kernel with this first eligibility rule. Their extra guards did not establish a useful improvement, and unrelated Java
load made wall timings unstable. The tier therefore remains opt-in; the scalar result is not evidence of a general nixpkgs speedup.

The selector extension now has real workload coverage: one demand nixpkgs-73 run executed 367,815 native calls through one shared
kernel with 29 candidate records, 30 grace checks and zero mismatches or compiler failures. Of those calls, 122,890 were argument
identities, 11,799 captured-value identities and 233,126 conditional selectors. Its output hash stayed `5e8fff662dff`. These counters
establish execution coverage, not a speedup; the [dense-attribute and selector Kali report](bench/kali/dense-selectors-20261028/RESULTS.md)
compares the candidate with the existing evaluator and accepted Nix/Lix baselines.
After bypassing dispatch for cached refusals, five paired demand rounds measured JIT off/on wall time at +3.1% on NixOS and -1.4%
on nixpkgs-73, with RSS +0.6% / +0.7%. The native tier remains opt-in; the retained default memory improvement comes from dense
attribute cells. These measurements do not establish a general JIT speedup.

The Boolean extension completes 111,101 / 201,795 evaluations in the final v2 demand profiles, with 103,749 / 186,782 host demands.
Retirement cuts deopts from 74,532 / 97,191 to 845 / 2,051. Its five-pair JIT off/on measurement still loses: wall +8.1% / +2.0%,
RSS about +0.7% on both workloads. The [Boolean Kali report](bench/kali/lazy-boolean-20261028/RESULTS.md) preserves the v1/v2
ablations, cached Nix/Lix comparisons and generated-IR evidence. The same allocValue counts as the selector baseline rule out claiming
heap savings merely from fewer Boolean tag writes. Compilation avoidance and broader useful graph coverage are still needed.

V3's admission check avoids four / three unused Boolean engines on NixOS / nixpkgs without losing native completions or demands.
It passes 186 exact native/interpreter comparisons on both hosts and preserves all saved output files in the 478-case full suites.
The final five-pair JIT off/on medians still rise 5.4% / 2.1%, with RSS about +0.7%. The same
[report](bench/kali/lazy-boolean-20261028/RESULTS.md) records the causal v2/v3 comparison and reused Nix/Lix references.

Guarded-call V1, with host Enter/Leave round trips, passed [local validation](bench/local/calls-20261028/v1/validation-summary.txt): 236 focused exact
comparisons, 479/479 semantic language cases and 221 stored exact expectations in each schedule, with all 1,434 prior saved files unchanged
per schedule. An untimed same-binary nixpkgs-73 inline-off/on profile records 161,997 entered inline calls and unchanged golden output.
Frame allocations fall from 3,193,780 to 3,031,786, and requested frame bytes from 266,271,360 to 262,383,504: 3,887,856 fewer bytes.
Both runs allocate 11,769,738 Value rows. These are diagnostic allocation counts, not peak RSS or a speed result. The
[V1 Kali comparison](bench/kali/calls-20261028/RESULTS-V1.md) measured inline-off/on wall time at +1.1% / +3.1% on NixOS / nixpkgs-73.

V2 keeps ordinary call bookkeeping native and passes [240 exact comparisons](bench/local/calls-20261028/v2/check-jit.txt), including
depth during a nested host demand, restoration after Leave, and recursive retirement with throwing cleanup. Its
[local profile](bench/local/calls-20261028/v2/profile-inline-on-nixpkgs.txt) retains 161,997 inline calls with zero mismatches or compiler
failures; native invocations fall from V1's 885,230 to 561,236. This confirms fewer host round trips, not an end-to-end speedup.
The [V2 Kali comparison](bench/kali/calls-20261028/RESULTS.md) records +1.5% / +0.8% wall time for inline-off/on and +2.2% / +3.9%
for whole-JIT-off/on. Both full language schedules pass 479/479 semantic cases with every saved output/error/status file unchanged.

Saturated-chain V1 passes [300 focused exact comparisons](bench/local/curried-20261028/v1/check-jit.txt) and
[480/480 semantic cases per schedule](bench/local/curried-20261028/v1/validation-summary.txt), including 222 stored exact expectations;
all 1,437 prior saved files remain unchanged per schedule. Its untimed same-binary demand nixpkgs-73
[curried-off](bench/local/curried-20261028/v1/profile-curried-off-nixpkgs.txt) /
[curried-on](bench/local/curried-20261028/v1/profile-curried-on-nixpkgs.txt) profiles retain the golden output and record three saturated
kernels, 188,515 completions and nine grace checks, with zero mismatches or compiler failures. Actual frame and Value allocation counts
each fall by 188,506, saving 9,048,288 requested bytes combined. The [Kali report](bench/kali/curried-20261028/RESULTS.md) confirms
77,354 / 188,506 fewer actual frames and Value rows on NixOS / nixpkgs-73. Curried-off/on median wall time rises 0.5% / 2.8%;
whole-JIT-off/on rises 2.8% / 3.6%. The default-path control is mixed, and native execution stays opt-in.

Projection V1 passes [370 exact comparisons](bench/local/projection-20261028/v1/check-jit.txt), including 33 new projection/inline cases,
and [481/481 semantic cases per schedule](bench/local/projection-20261028/v1/validation-summary.txt), with 223 stored exact expectations.
All 1,440 prior output/error/status files per schedule remain byte-identical. Checks cover ignored projected arguments, ordered
key/base/field forces, current captures, layered and cached-flat lookups, predicate and ordinary consumer errors, depth limits,
fallback after successful demands, recursive retirement, and independent projection/inline controls. The
[saved IR example](bench/local/projection-20261028/ir-v1/README.txt) maps three root arguments and a two-argument inline callee through
the plan, typed MLIR and LLVM, preserving current captures and exactly-once traces. The
[projection Kali report](bench/kali/projection-20261028/RESULTS.md) records 17,253 / 28,701 fewer frames and 8,430 / 21,368 fewer Value
allocations on NixOS / nixpkgs-73, saving 985,712 / 1,786,864 requested bytes. Projection-off/on wall time changes −1.0% / +2.5%;
whole-JIT-off/on changes +1.2% / +2.0%. At that stage, coverage also brought more fallbacks and compiler cost, including bare non-Boolean
Select results entering the Boolean-only tier. These historical measurements precede cell/empty-recipe returns. Native execution remains
opt-in; the report reuses historical Nix/Lix reference results.

Persistent-value and empty-recipe V1 passes [472 exact comparisons](bench/local/values-20261028/v1/check-jit.txt) on both hosts and
[482/482 semantic cases per local schedule](bench/local/values-20261028/v1/validation-summary.txt), with 224 stored exact expectations.
All 1,443 prior output/error/status files remain byte-identical. The 46 new cases cover returned cells, lazy payloads, current captures,
strict Boolean contexts, fresh empty recipes, nested Leave/depth restoration, reentrant retirement and independent ablations. The
[IR example](bench/local/values-20261028/ir-v1/README.txt) maps selected-cell and empty-list returns through two native Leave scopes.
The [Kali report](bench/kali/values-20261028/RESULTS.md) records 160,781 / 333,549 fewer frames and 33,443 / 283,512 fewer Value
allocations on NixOS / nixpkgs-73 against VALUES=0, saving 5,467,992 / 14,800,312 requested bytes. Peak RSS falls 0.3% / 1.2%, while
wall time changes +0.2% / +1.7%. Whole-JIT-off/on wall time rises 5.9% / 6.2%; native execution stays opt-in. General fallbacks fall
8,882 → 7,460 for NixOS but rise 7,692 → 19,293 for nixpkgs, mainly at a partially covered singleton-list constructor. Native invocations
also rise. These measurements support memory savings, not a throughput or cache-locality improvement.

List Returns V1 passes [536 exact comparisons](bench/local/list-returns-20261028/v1/check-jit.txt) on both hosts and
[483 semantic cases per local schedule](bench/local/list-returns-20261028/v1/validation-summary.txt), with 225 stored exact expectations.
All 1,446 prior saved output/error/status files remain byte-identical. Its 29 new cases exercise lazy and cyclic elements, duplicate
handles, delayed errors, current captures, nonforcing capture lookup, nested/curried Leaves, depth and resource limits, exclusions,
reentrant retirement and three ablations. The [IR guide](bench/local/list-returns-20261028/ir-v1/README.txt) shows an ordered three-element
recipe with a skipped throwing element and exactly-once capture trace. The [Kali report](bench/kali/list-returns-20261028/RESULTS.md)
records 120,304 / 34,274 fewer frames and 60,152 / 17,137 fewer Value allocations against LISTS=0, saving 4,330,944 / 1,233,864
requested bytes. `optional`'s curried fallbacks disappear. NixOS native invocations rise as that formerly retired plan stays active.
LISTS-off/on wall time changes +1.2% / −7.6%, with substantial variability and nearly unchanged minima; peak RSS does not fall.
Whole-JIT-off/on wall time rises 6.5% / 4.0%. Allocation reductions therefore do not establish a robust throughput gain.
Four balanced PMU pairs also fail to establish a repeatable cache-miss reduction: both workload ranges cross zero, and package
cache-miss signs follow run order. The report retains the original pair and all three confirmation pairs without selective replacement.

General closure conversion, arbitrary local value-producing computations, constructors beyond the bounded list recipes, multi-component/defaulted projection paths, nested virtual
projection bases or keys, projected callees, collection kernels and persistent machine-code caching remain outside this tier. The guarded plans preserve lazy Nix
graph semantics and use the existing TrikeShed source and region representation.

[The call compiler and its next stages](JIT-CALLS.md) describe guarded calls, saturated chains, lazy projections and future closure/collection work.
[The durable-environment design](JIT-ENVIRONMENTS.md) defines frame reuse and local memoization needed before general local execution,
escaping closures and collection fusion. Those capabilities are not implemented by the current persistent-cell tier.

## Compile cost (2026-10-28)

A warm kernel compile is about 2.7 ms: graph to typed MLIR 0.66 ms, conversion to the LLVM dialect 0.37 ms, and the
ExecutionEngine 1.7 ms. The engine cost is LLVM optimization. `MLNIX_JIT_OPT` selects the LLVM level (default `0`): the engine
takes 0.45 ms at level 0 against 1.85 ms at level 2, and 2M-call loops run at the same speed at every level (0.143 s at 0,
0.153 s at 2, interpreter 0.251 s), because host forcing dominates the kernels. `check-jit.py` passes all 652 comparisons at
level 0. `MLNIX_JIT_CLEAN=1` runs `canonicalize,cse,control-flow-sink` on the typed functions before lowering; it is opt-in
because it measured no gain on these small kernels (4.5 to 4.8 ms before the optimization-level change, within noise or slightly slower).
`MLNIX_JIT_PHASE=1` prints the three phase times per compile.
