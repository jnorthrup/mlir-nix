# The sea of nodes, demand-minted

Cliff Click's IR is a graph of nodes with explicit use-def edges and no fixed order, plus a schedule
that decides when a node exists and where it runs. The `nix` dialect already has the first half: its
regions are graph regions of mostly pure ops, forced on demand. It lacked the second. Every op of a
file was created when the file was lowered, and 89-90% of them are never evaluated (nixos-toplevel:
121,687 of 1,095,819; nixpkgs-73: 76,949 of 798,177). This change moves one decision: a lambda body is
minted on its first call, not when its file is lowered. It is opt-in (`MLNIX_DEFER=1`); the eager
default stays the oracle. Value numbering is not part of it: stock `cse` costs +7.1% / +5.4% on the
same workloads, because a file is lowered once and evaluated once (F17 in COMBINATORS.md).

The graph is built from a syntax tree here. Sam H. Smith's [talk](https://www.youtube.com/watch?v=NxiKlnUtyio) builds it while parsing
instead, with no tree, and applies the rewrites as each node is made; [FABRIC.md](https://github.com/jnorthrup/mlir-nix/blob/77de09c/docs/FABRIC.md) sets its mechanisms against this tree one by one.

## What was built, in PRELOAD's terms

`include/Composite/Series.h` is the kernel algebra of `../TrikeShed/PRELOAD.md` in C++. Header-only, no
MLIR, no LLVM. Every name in it has a caller outside the header, except the `Series` alias (it names
what `series`, `α` and `view` return) and the gap marked below.

    a j b          Join, the base binary composition. `Gen::defer` joins each free name of a lambda to
                   where the live scope puts it (`f j resolve(f)`), and `series`, `α` and `view` build
                   their Series with it. The `body_index` of a `nix.lambda` is `file j row`: the
                   existing `join::TwInt` of Pack.h, named `nixfe::BodyIndex`.
    Series<F>      `Join<uint32_t, F>`, as PRELOAD aliases it: size j index-function. Indexing is not
                   bounds-checked, because every index is issued by the builder (a pool row, a position
                   in a free-name list), never by the user. Callers: the range-for in `Gen::defer` and
                   the MLNIX_STATS loop over the pool.
    xs α f         Lazy projection, `size j { i -> f(xs[i]) }`; α of α reads as α of the composition (a
                   `static_assert`). Caller: `Gen::defer`, over the free names of a lambda, so nothing
                   resolves until its element is read.
    MutableSeries  A list that is mutated says so in its type. Rows accumulate (`append`) as lowering
                   defers lambdas and drain (`drain`) as evaluation mints them. A drain leaves a default
                   cell: a removal would renumber the rows, and every `body_index` holds one. `view()`
                   is the Series over the cells and holds no pointer into them, so an append that moves
                   the cells leaves it valid. Callers: the columns of `FilePool`.
    anchor         ↺, the constant anchor: the first force of a cell mints it, every read after is the
                   constant it produced. The cell is addressed by index again after the mint, because a
                   mint appends to the very pool it anchors in (a lambda nested in the body defers a
                   row) and an append moves the cells. Caller: `EvalState::bodyOf`.
    Cursor<T...>   The instance pool of one type: a MutableSeries per column and the column names.
                   Caller: `nixfe::FilePool` (expr, op, withs, names, body); MLNIX_STATS prints the pool
                   by those names.

Gaps, said so rather than stubbed:

- PRELOAD's Cursor is `Series<RowVec>`, the row-shaped face of the same columns. Nothing reads a pool row
  as a RowVec (`FilePool::read` names its cells), so that face is not built.
- TrikeShed's MutableSeries also has `set`, `insert`, `removeAt`, `remove`, `clear`, `snapshot` and COW,
  chunked, ring, journal and guard backends. Only the accumulate half and `drain` exist here, and a ring
  or a `removeAt` would renumber the pool.
- `⋈` and the literals, `get(range)`, `snapshot()`.
- Confix is not used as a scanner. Its idea is: index first, reify later. `FilePool` is the index (the
  expression, the waiting op, a span of names); minting is the reify; the `Body` anchor is the
  `rowCache` of its `tree()`.

## How it works

- Lowering a lambda in `MLNIX_DEFER` mode creates the `nix.lambda` with an empty body block, its
  **captures** as operands (the `with` chain innermost first, then the free names that resolve in the
  live scope, base-environment names included), and `body_index`. It appends one row to the pool of its
  file: `(expr, op, withs, names, body)`. The shell exists only in memory: the dialect verifier refuses
  an empty block, nothing verifies in process, and `mlnix emit-mlir` lowers eagerly.
- Captures are real operands. The cleanup after devirtualization erases an unused `nix.builtin`,
  `nix.select` or `nix.str`; a value that only a waiting body will read must already have a use. The
  placeholder RAUW of a `let`/`rec` group also keeps them honest.
- The free names come from one memoized walk (`FreeVars`): a body is walked once however deep the
  lambdas nest. A name that no scope can supply is an error at lowering time, exactly when the eager
  schedule reports it, unless a `with` could supply it (`x: y` must fail without being called).
- The first call drains the row (`EvalState::mintLambda`): the scope is rebuilt from the captures (a
  flat lexical map, then the `with` chain: a lexical binding beats every `with`, so this is the same
  scope), the body is generated by the same function as in the eager schedule, devirtualized, and
  indexed. The row keeps its anchor, the indexed region; every later call reads it.
- A lambda is not `IsolatedFromAbove`, so no `PassManager` can run on it. The demand schedule runs
  devirtualization directly with its pattern set frozen once, and refuses any `MLNIX_PIPELINE` other
  than `nix-prims`.

## The A/B

`scripts/son-ab.py`, modeled on TrikeShed's shape benches (`src/commonBench/kotlin/borg`): the same work
down two paths, the whole path priced, parameters swept, the answer checked inside the run (a run that
fails or answers differently stops the table). Acceptance was stated in the script before the numbers:
demand beats eager in wall time on both real workloads, with identical result hashes and a lower peak
footprint.

    arms interleaved, 7 runs each, medians, macOS arm64, Release build

    workload         wall eager   wall demand            peak footprint eager   demand            hashes
    nixos-toplevel     2.902 s      2.585 s  -10.9%       1902 MB   1768 MB   -7.1%           identical
    nixpkgs-73         2.399 s      2.089 s  -12.9%       1810 MB   1655 MB   -8.6%           identical

The acceptance holds. Three runs of the command (two on the build before its last two small changes, a
removed verifier guard and `emit-mlir`, neither on a measured path): toplevel wall -8.8%, -10.5%, -10.9%
and footprint -7.2%, -6.8%, -7.1%; nixpkgs-73 wall -14.7%, -12.8%, -12.9% and footprint -8.7%, -8.0%,
-8.6%. A browser, a chat client and sysmond each used 20-27% of a core during the last run, so the
absolute times are not a quiet machine's; the arms alternate, so the load lands on both.

PERFORMANCE.md estimated ~12-17% and 300+ MB. Time landed inside that range for nixpkgs-73 and under it
for toplevel; the footprint landed at about half (130-160 MB). Why, from `MLNIX_STATS` on the same binary:

    nixos-toplevel            eager        demand
    ops lowered             1,095,819      619,842   (-43.4%)
    ops ever evaluated        121,687      121,680   (11.1% -> 19.6% of those lowered)
    lowering                    899 ms        77 ms
    minted on demand               -        544 ms
    lambdas deferred / called      -     29,744 / 5,394   (82% never called)

    nixpkgs-73                eager        demand
    ops lowered               798,177      384,645   (-51.8%)
    ops ever evaluated         76,949       76,944   (9.6% -> 20.0%)
    lowering                    655 ms       110 ms
    minted on demand               -        307 ms
    lambdas deferred / called      -     23,376 / 3,537   (85% never called)

Lowering and minting explain 278 of the 317 ms saved on toplevel (899 - (77 + 544)) and 238 of the 310 ms
on nixpkgs-73 (655 - (110 + 307)); the rest I did not isolate. Most lambdas are never called, but a
called lambda mints its whole body, and most of a called body's ops are still never evaluated. Lambda
grain removes 43-52% of the ops while 89-90% of the eager schedule's ops are dead.

The plan costs 77 ms of lowering on toplevel (110 ms on nixpkgs-73): the analysis of every lambda in
every file read, the shells, the captures, and the code that is not a lambda. Its payload is about 5 MB:
94,805 analyzed free names at 32 bytes, 56,135 pooled names at 16, and 29,744 pool rows at 36 (sizes
from the compiler; the memo's hash nodes are not counted).

### Shapes: where it stops paying

Generated files of 20,000 pattern lambdas with 12-entry bodies (TrikeShed's LCG picks which are called),
5 interleaved runs per row, the command run three times. Hashes are identical on every row. Wall and
footprint are from the last run; the deltas are all three.

    called                 wall eager   wall demand    wall delta, three runs     footprint
    0%                       0.853 s      0.309 s     -66.0 / -64.2 / -63.8 %     474 ->  179 MB  -62.2%
    1%                       0.841 s      0.324 s     -62.2 / -62.0 / -61.5 %     478 ->  179 MB  -62.5%
    10%                      0.846 s      0.366 s     -56.0 / -56.3 / -56.7 %     472 ->  208 MB  -56.0%
    50%                      0.865 s      0.604 s     -29.6 / -27.4 / -30.2 %     483 ->  314 MB  -35.0%
    100%                     0.873 s      0.958 s      +8.5 /  +7.5 /  +9.8 %     481 ->  427 MB  -11.1%
    50 lambdas x 50k calls   1.166 s      1.149 s      +0.2 /  -0.9 /  -1.5 %    1785 -> 1785 MB   0.0%

Wall time breaks even near 88-89% of lambdas called (interpolated between the 50% and 100% rows in each
run; not measured there). At 100% called the plan is pure cost: +7.5% to +9.8% wall. The real workloads
call 18% (toplevel: 5,394 of 29,744) and 15% (nixpkgs-73: 3,537 of 23,376) of the lambdas they defer.
The last row is the call path of a minted lambda: parity (-1.5% to +0.2%), so calling a minted lambda
does not regress.

## Gates

    scripts/run-lang-tests.py                 467/467 semantic, 209/467 exact  (466 upstream + eval-okay-demand-scope)
    MLNIX_DEFER=1 scripts/run-lang-tests.py   467/467 semantic, 209/467 exact
    scripts/difftest.py (file as at b4c0cf7)  72/72 identical to Nix 2.35.4, both schedules
    scripts/run-mlir-tests.py                 14/14  (deferred-emit and deferred-invalid are new)
    scripts/check-prims.py                    105 registered, 105 declared

### Mutations

A gate that cannot fail proves nothing. Each mutation breaks one rule of the free-name analysis in
`lib/Frontend/MLIRGen.cpp`, rebuilds, and runs the lang suite under `MLNIX_DEFER=1`:

    M1 no static undefined-variable check                1 failing: parse-fail-undef-var
    M2 `inherit x;` read inside its own group            1 failing: eval-okay-demand-scope
    M3 the `with` chain is not captured                 20 failing, the probe among them
    M4 a let's body walked after its names leave       157 failing, the probe among them
    M5 a nested lambda's free names are not the outer's 12 failing, the probe among them
    M6 formal defaults are not walked                    2 failing: eval-okay-autoargs, the probe
    M7 a name under an inner `with` is strict            2 failing: eval-okay-delayed-with, the probe
    M8 a rec set binds nothing                           1 failing: the probe

The first pass, over the upstream suite alone, left M2 alive (466/466), and M3 did not build (its mutation
text swallowed the next declaration, so it tested nothing). `test/lang/eval-okay-demand-scope.nix` closes
both: 15 probes, one rule each, with the expected output taken from Nix 2.35.4. It kills seven of the
eight itself; M1 is killed by the upstream `parse-fail-undef-var`. The harness edits a tracked source
file in place and restores it, so it is not kept in the repo.

## Failures and corrections

- The first `MLNIX_DEFER` lang run failed 50 of 466: `PassManager::run` refuses a root that is not
  `IsolatedFromAbove`, and a lambda reads its captures from outside. Devirtualization now runs directly
  on the minted body.
- The estimate was high on memory by half and, for toplevel, on time; see above.
- `mlnix emit-mlir` under `MLNIX_DEFER=1` exited 0 and printed lambdas with empty bodies. It now lowers
  eagerly (`test/mlir/deferred-emit.mlir`, red before the fix).
- A verifier special case for the shell (a terminator required only without `body_index`) never ran: the
  `SingleBlock` trait refuses an empty block first, so the dialect never admitted the shell. It is removed,
  and `test/mlir/deferred-invalid.mlir` records that the shell is refused with or without `body_index`.
- No A/B of the pool's shape (columnar `Cursor` against a struct per row) was run: 29,744 rows of 36 bytes
  are 1 MB, three orders below the effect being measured. The columnar form is there because it is the
  algebra's pool, and it costs nothing measurable.

## The frame's release: the Graal arm's lifetime, in son

The Graal arm (`graal/`, nix-truffle) runs son form: a call of a `son.body` is a frame of slots, and its one lifecycle
rule is `BodyRoot.release`: when the call returns, the frame keeps what its unforced cells can read and lets go of the
rest. `son.release` states that rule in this dialect, not in a new one. `son-release` puts one before each frame's
return, naming what a cell passed on without forcing can read (the operands nix-truffle reads with `lazy`, and their
closure over operands); its verifier refuses a release that lets go of such a value; `son-mint` drops it. It frees
nothing: the slots stay the collector's, and it says only when the frame stops reaching them.

The release has two halves. What escapes: the cells passed on unforced (a list's elements, an attribute's value, an
argument, a capture). What the schedule forces before the return: the must-force set (`MustForce`, SonDialect.cpp) --
the return value, what a forced op always forces (an if's condition and what both arms force, the left of `&&`, both
sides of `==` and `//`, a select's base, a primop's `nix.strict` operands), a callee's argument where the callee is a
lambda of the frame that takes a pattern or forces it on every path; a throw returns on no path. A cell in the
must-force set is a value by the return and reads nothing, so the frame keeps only the cells outside it and what they
read. `son.forcedOnReturn` exposes the set to the evaluator.

Checked against the arm itself (`NIXTRUFFLE_SON_PASSES=--son-release NIXTRUFFLE_CHECK_RELEASE=1`, both runs by
`scripts/truffle-release-check.py`): at each return, the
slots the arm keeps are compared with the frame's `son.release`.

    eval-okay, 147 files    frames with a cell     slots holding    kept by    named by       kept outside
                            unforced at return     a value          the arm    son.release    son.release
    escapes only            930                    11,252           3,268      5,787          0
    with the must-force set 930                    11,252           3,268      5,234          0

The outputs are byte-identical with and without it (147/147; 123/147 identical to `.exp` both ways). The must-force set
takes 553 of the 2,519 slots son.release named and the arm let go (22%); the rest are cells forced before the return on
the path the run took, not on every path, or by a callee son does not see. The evaluator registers son, so it carries
the op and the pass (+64 KB stripped, +0.29%) and never runs them: `emit-mlir` and `son-export` are byte-identical.

The native evaluator keeps son's account beside the run's (MLNIX_STATS, `son's account of the frames at their
return`). A lambda body is dead at return by son when it makes no closure and every value of it passed on as a cell is
in its must-force set -- the cells are the evaluator's, as son.release's are the arm's: a list's elements, an attribute's
value, an application's arguments, a primop's operands (not the one it forces first, nor a `nix.strict` one); the other
core ops force what they read or read it only to force it. A frame is dead at return by the run when it pinned no
closure and every thunk made over it, projections too, was forced by then. Son wrong counts frames dead by son and not
by the run: it must be 0.

    MLNIX_DEFER=1           returns      dead by the run    dead by son    without must-force    son wrong
    nixpkgs-73              2,880,133    1,003,419 34.8%    364,152 12.6%  358,749 12.5%         0
    toplevel                4,568,831    1,364,094 29.9%    591,099 12.9%  583,038 12.8%         0

Outputs unchanged (5e8fff66..., f1cfa7cd...). On the native side the must-force set adds little: its cells are attribute
values and arguments, which a body passes on rather than forces. (That column was an ablation; MLNIX_STATS dropped it once
it was measured, as it did the callee breakdown below. Both are in the code at 0253d57.) Why son keeps the frames the run found dead, by the
worst cell of the body:

                            a closure    forced on some path only    a callee son does not see    passed on unforced
    nixpkgs-73              58,004       23,396                      516,728                      41,139
    toplevel                89,203       58,527                      452,477                      172,788

Passed on unforced is mostly attribute values, then primops whose table entry says less than they force (`__seq`'s
second operand, `elemAt`'s index, `lessThan`, a throw's message): `nix.strict` there is precision for son and for the
evaluator's promotion alike. A strict schedule -- make the value, not the thunk, where the body forces it on every
path anyway -- would remove 27,959 of 3,778,193 thunks over a frame on nixpkgs-73 (0.7%) and 117,089 of 5,327,906 on
toplevel (2.2%): too few to trade Nix's order of errors for. A release per path takes at most the second column.

The callee column is a cell given to a function son does not see. Where that function comes from decides what could
close it (MLNIX_STATS at 0253d57, the deciding call of each frame):

    callee gap                                   nixpkgs-73          toplevel
    the call itself is not on every path         303,583  58.8%      270,756  59.8%
    an argument of the body (higher order)       169,408  32.8%       71,723  15.9%
    a set's attribute (lib.f, pkgs.f, with)       36,468   7.1%       81,852  18.1%
    a call's result (a curried function)           4,197   0.8%       23,701   5.2%
    a lambda of the file, lazy in it               1,494   0.3%          948   0.2%
    a lambda of the file not minted yet            1,313   0.3%        3,297   0.7%
    other                                            265                 200

A summary of each body's strictness in its argument, resolved statically across files, closes at most the attribute,
curried and in-file rows: 8% of the gap on nixpkgs-73, 24% on toplevel. The rest is the run's: which arm a call is on,
and which function arrives as a value. So the next step is the arm's (profile and speculate, son.release the check of
the guess), and its precondition is a frame the compiler can keep virtual -- the section below.

## Escape on the Graal arm: what kept every frame allocated

A call of a son.body allocates a Frame and its slots array (BodyRoot.execute). Graal's partial escape analysis can
keep both virtual -- no allocation, the slots as values -- on every path on which the frame does not escape. At
f1a7119 it escaped on every call, whatever son proves, through four doors: the release at the return (`release(f)`, a
`@TruffleBoundary`); the ops that are boundaries and took the frame (`+`, select, attrs, `//`, interpolation); every
op reached through `f.ops[s]`, an array read from the frame object, which the partial evaluator cannot fold, so
`exec(f)` was a virtual call the frame went into; and slot indices that were not constants (the loops of apply,
primop, defer and list over arrays not marked CompilationFinal; an if's `strict(f, if (c) t else e)`).

Closed in graal/ (Nodes.kt): an op reads its operands itself, with constant slot indices (CompilationFinal arrays,
exploded loops, two reads in an if), and hands boundaries values, not the frame (past 32 operands an op keeps its
boundary over the frame, for code size); `strict` and `lazy` take the body's ops from the node (`OpNode.rootOps`, set
by BodyRoot), a constant when compiled; a literal is its own value, never a cell (son's fixed promotion); and the
release takes its boundary only when a cell of the frame is still unforced at the return (an inline scan), and not at
all when son.release keeps nothing -- the schedule's half of the lifecycle, used as a fact, not checked again.

    eval-okay, 147 files        f1a7119      now
    outputs                     123/147      123/147 identical to .exp; 147/147 byte-identical to f1a7119's
    returns                                  26,111
      with a cell unforced      930 frames   738 (literals make no cell)  -> the boundary
      son.release empty                      18,138 -> no release at all; a cell unforced in 0 of them
    kept outside son.release    0            0

The microbenchmarks (graal/bench/, `scripts/truffle-bench.py WT INSTALL --runs 20 --launches 5 [--son]`: the median of the
last ten runs, five JVMs; allocation
is the thread's bytes per run, deterministic; Oracle GraalVM 25.4 on an M3 Pro):

                                   f1a7119             now                 now, son.release exported
    leaf    foldl' of a strict leaf  40.0 ms 188.8 MB    30.6 ms 124.7 MB    24.8 ms 124.7 MB
    attrs   a set made, selected     50.8 ms 185.4 MB    40.0 ms 170.1 MB    38.2 ms 170.1 MB
    fib 24  lazy arguments           18.2 ms  33.2 MB    19.7 ms  26.3 MB    33.8 ms  26.3 MB (19.3 to 39.4)
    slots1  a leaf of one slot       29.6 ms 156.8 MB    31.4 ms 111.0 MB    34.1 ms 111.0 MB
    slots9  the leaf with nine       45.1 ms 168.2 MB    33.1 ms 111.0 MB    34.4 ms 111.0 MB

slots9 against slots1 is the proof that the frame is virtual: eight more slots in the leaf cost 38 B a call at f1a7119
(the slots array grows) and nothing now (111.0 MB both). Frames still materialize where a cell over them escapes --
fib's `fib (n - 1)` passes a LocalThunk of the frame to the call -- which is the case speculation on the callee's
strictness would take next: a strict callee's argument computed before the call makes no cell, and son.release checks
the guess. Allocation falls on every one (-8% to -34%) and does not depend on the export: a frame whose son.release is
empty makes no cell, so the inline scan folds away when compiled; son's fact saves the scan where the frame is too big
to scan inline (more than 64 slots), where the boundary would be taken. Time falls on leaf, attrs and slots9 (the
slowest of five JVMs now beats the fastest before); on fib and slots1 it is within the spread between JVMs, which
reaches 2x (fib with the export: 19.3 ms in one launch, 39.4 ms in another). The allocation does not vary.

## The callee's half: arg_forced, and the argument computed first

The must-force set already reaches into a callee when the callee is a lambda of the same frame: `calleeForcesArg` asks
whether that body forces its argument. A function that arrives as a value -- an argument, `lib.f`, a call's result -- is
a callee son does not see, and the native table above puts most of the frames son keeps there. `son-release` now states
that half on the body itself: `son.body ... arg_forced` when the body forces its argument on every path on which it
returns and returns on some path, or binds a pattern (a call checks the set before the body runs). It is derived, like
`son.release`, and `son-mint` drops it with the pool. test/mlir/son-release.mlir checks it both ways: `g = y: y + "!"`
has it, a body that returns a set does not.

The Graal arm reads it at the call (Nodes.kt, ApplyNode). The guess is the closure that arrives: when its body is
`arg_forced`, the first argument is computed before the call and passed as a value when it is an op of the caller's body,
so no cell over the caller's frame is made for it. An argument of the caller's own body (its parameter, a capture) is
passed on as it came: it is not a cell of this frame, so computing it first saves nothing (it made slots9 10-20% slower).
Otherwise the call makes its cells as before. Each way is compiled only once a call has gone it
(CompilationFinal flags, invalidated on first use), so a call site that has met only such callees has no cell path at
all, and its frame can stay virtual. son.release stays the static bound and the check: the arm keeps no slot outside it.

The order. The value is the same: the callee would have forced the argument on every path on which it returns. An error
is the same: an argument whose computation throws is passed as the error (`Failed`), which the callee throws where it
would have forced the cell, so a callee that throws first still throws its own, and `tryEval` catches what it caught.
What moves: a `builtins.trace` inside the argument prints before the callee's own traces that run before it forces it,
and on a path on which the callee throws without forcing the argument, the argument was computed for nothing.

    eval-okay, 147 files                     0253d57              now
    outputs                                  123/147 match .exp   123/147; 147/147 byte-identical to 0253d57's, plain and with son
    kept outside son.release                 0                    0
    frames with a cell unforced at return    738                  738
    calls                                                         11,539: to a body arg_forced 5,194; the argument
                                                                  computed first (an op of the caller) in 3,628, of which 3 threw

The release counts cannot move: a cell given to a callee that forces it is forced by the time the caller returns. What
the call saves is the cell, and with it the frame's escape. The microbenchmarks, now the median of the last 30 of 60
runs over five JVMs (at 20 runs a body can still be interpreted at run 10: the control below first showed fib 13%
heavier on the new arm, which was its compilation finishing a few runs later):

                    son exported                               no son (the control)
                    0253d57              now                   0253d57              now
    fib 24          12.7 ms   26.3 MB    2.2 ms    3.4 MB      12.9 ms   26.3 MB    13.9 ms   26.3 MB
    attrs           33.2 ms  170.1 MB   30.2 ms  147.2 MB      34.8 ms  170.1 MB    34.9 ms  170.1 MB
    leaf            21.7 ms  124.7 MB   22.4 ms  117.9 MB      24.7 ms  124.7 MB    24.5 ms  124.7 MB
    slots1          21.0 ms  111.0 MB   21.9 ms  104.1 MB      25.1 ms  111.0 MB    24.0 ms  111.0 MB
    slots9          24.1 ms  111.0 MB   23.7 ms  104.1 MB      33.5 ms  111.0 MB    33.5 ms  111.0 MB

fib's frames stay virtual: 26.3 MB a run becomes 3.4 MB (under 25 bytes a call are left) and the run is 5.8x faster.
Allocation falls on every file with the export, by 5.5% to 87%, and is unchanged on every file without it. Time falls
with it on fib and attrs (9%); on leaf, slots1 and slots9 it stays within the spread between JVMs. Without the export
fib takes 13.9 ms against 12.9 (the ranges over five JVMs just touch): the test at each call, when no callee carries
the flag.

Left on the arm: the second and later arguments of a curried call (`f a b`: the function that takes `b` is known only
after the first call returns); a primop's operands (PrimNode makes a cell of each; its `nix.strict` ones could be
computed first, as the native evaluator does); and list elements, attribute values and captures, which escape by
design. The native evaluator reads neither son.release nor arg_forced.

## Not built, with the number that gates it

Type pools for every node (the whole AST as `Cursor`s of typed instances, Confix mapping a tree to rows)
have a consumer only if deferral goes finer than the lambda: an attribute value, a `let` binding, an
argument, minted when it is forced. The measurement this section demanded is now made: the MLNIX_STATS
"sea of nodes" line counts, per region, the ops the index holds, the distinct ops that ever ran (one bit
an op), and the thunk cells finer grain would mint -- file code against the bodies demand minted.

    toplevel, demand      ops held    ever ran     evals        thunk cells
    5,811 file regions    562,915     17.4%        258,116      358,550
    2,476 minted bodies    53,038     44.2%        15.16M       27,826

    nixpkgs-73, demand
    2,395 file regions    315,435     14.2%        395,916      178,084
    2,315 minted bodies    67,797     47.3%        10.41M       37,099

The naive cell-grain ceiling is ~304 ms on toplevel (544 ms of minting times the 55.8% of a minted body's
ops that never run), not the 440 ms the estimate above assumed -- minted bodies run at 44-47%, not 20%. The
rows grow from lambda grain's 2,476 to 27,826 (bodies alone) or 386,376 (with file code), against a plan
that cost 77 ms of lowering at 29,744 rows; and the frame-per-deferred-thunk risk is priced: 15.16M evals
a run (toplevel) would each pay the mint check. The file code's dead ops cost almost nothing where finer
grain would collect -- all of demand lowering is 77 ms -- they cost IR memory and slot-map indexing, which
minting per force does not save. Finer grain in this form is closed by the numbers; this is the
measurement, and now it is a conclusion.

The default stays eager. Flipping it is a separate decision: it would make any `MLNIX_PIPELINE` other
than `nix-prims` an error (the stock passes cannot run on a body that does not exist yet), and it costs
+7.5% to +9.8% on a file whose lambdas are all called.
