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
instead, with no tree, and applies the rewrites as each node is made; [FABRIC.md](FABRIC.md) sets its mechanisms against this tree one by one.

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
