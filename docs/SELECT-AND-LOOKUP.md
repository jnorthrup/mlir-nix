# Selects, lookups and where the CPU goes

Two measurements decided what not to build: the census of attribute selects (`MLNIX_STATS=1`) and the sampling profile on Kali
(`scripts/kali-gen.sh prof`, 3 runs of nixos-toplevel on the demand schedule, 2 ms samples, 2,915 samples).

## The profile (Kali)

By phase: evaluation 59.5% (the evaluator 30.8, operand lookup 13.4), parsing 23.5%, derivations and the store 14.4%, lowering 1.7%,
demand minting 0.9%.

By self time, the head of the list: libc 12.2%, `EvalState::lookup` 8.9%, `evalOp` 7.3%, `Lexer::nextToken` 4.9%, `operand` 4.5%,
sha256 3.5%, `evalTail` 3.2%, **`Bindings::get` 2.8%**, `forceValue` 2.7%, `callFunction` 2.2%, **`LambdaOp::getBodyIndex` 1.9%**,
**`infoOf` 1.8%**, `malloc` 1.6%, `updateAttrs` 1.2%.

## Selects

nixos-toplevel: 2.92M selects (nixpkgs-drvs: 1.45M); 86.5% (88.9%) are found, 11.1% (32.4%) run on a layered set, 5.4% (17.0%) have a
dynamic key. The search looks at 4.5 (6.4) probes on average. Most sets are small: 47% have 2 or 3 rows on nixos-toplevel; the large
tail (2^9 rows and up) is 6% there and 14% on nixpkgs-drvs.

Per site, by how many distinct set layouts it sees (a layout signature is the size and three sampled names):

| | nixos-toplevel | nixpkgs-drvs |
|---|---:|---:|
| monomorphic sites, share of selects | 45.5% | 45.5% |
| 2 to 4 layouts | 11.1% | 16.6% |
| 5 layouts | 0.4% | 0.7% |
| 6+ layouts (megamorphic), sites | 177 | 164 |
| 6+ layouts, share of selects | 43.0% | 37.1% |
| a one-entry cache per site would hit | 61.9% | 69.9% |

**Decision: no select cache.** The whole attribute search, `Bindings::get`, is 2.8% of the CPU. A cache that hits two thirds of selects
could save one to two percent at best, and would need a layout id in every attribute set (the sets carry none; the `pos` field is
never set by the builders). A few hundred megamorphic sites carry about 40% of the selects and would miss.

## Lambda dispatch: 3.7% found, and cached

`getBodyIndex` (reading the deferred-body attribute off the lambda op) and `infoOf` (the hash lookup of its `RegionInfo`) were 3.7% of
the CPU together: every call of a lambda paid both. `EvalState::infoOf` now answers from a direct-mapped, 4,096-entry cache keyed by the
op's address, a load and a compare on a hit. Sound because an entry is made only for a lambda being called, and nothing erases a called
op. On the Mac, relative only, demand schedule, minimum of 7 interleaved runs against the build without it: nixos-toplevel 1.603 s to
1.556 s (-2.9%), nixpkgs-drvs 1.367 s to 1.334 s (-2.4%).

## The 12.2% in libc

`libc.so.6` is stripped, so the report shows it as one line. Resolving the evaluating thread's libc samples (17.9% of its samples) by
exported symbol is unreliable, because libc's internal routines sit under whichever public name precedes them. Reading the
instructions at the hottest addresses instead: the hottest 64-byte windows are each 1 to 2% of the thread, and they are an errno-return
path (2%), `fstatat` (1.3%, the import stats), and the `malloc` and `free` windows (about 3 to 4% together). None is an AVX copy loop or a
`rep movs`. So libc's share is mostly the allocator and syscalls, which serve the lowered IR and the parsed sources outside the arena,
not a bulk copy or fill in the evaluator's own data.

## The lookup caches

`slotOf` is a second direct-mapped cache, in front of the hash map from an SSA value to its frame slot. `lookup`, `operand` and `evalTail`
(16.6% of the CPU between them) each began with a hash probe. The slots now live in a deque (the map grows as the demand schedule adds
values, which would move them) and a value's slot is rewritten in place when its address is indexed again. Both caches can be compiled out
with `-DMLNIX_NO_LOOKUP_CACHES` for the A/B below. The cached build is slightly bigger (`lookup` 2,220 to 2,332
bytes, `callFunction` 2,644 to 2,760).

## The hot functions grew, then were cut back

The hot loop is `callFunction` and what it calls. Measured by symbol size on the Mac build against the commit before the session
(46182e5): `callFunction` 2,160 bytes then, 3,812 at its largest, 2,644 now; `callLambda` and `callLambdaIn` together 2,736 then, 2,728
now; `lookup` 2,176, 2,404, 2,220; `evalOp` unchanged at 7.6 KB. The growth came from fast paths added in line; they are now out of line
(`applySelector`, `jitChain`, `statTouch`), and one region lookup per call is shared by the selector check, the JIT check and the call.

## The caches on Kali

Same boot, the cached build and a `-DMLNIX_NO_LOOKUP_CACHES` build of the same sources, three interleaved rounds, each run of
`vs-nix.py` timing live Nix 2.35.4 and Lix 2.91.3 beside mlnix (demand schedule, minimum of 5). The two binaries print the same
output; the cached build passes every gate (language 486/486 on both schedules, difftest 72/72 against Nix and 71/72 against Lix).

| workload | caches on: min (ratio to Nix in the same run) | caches off |
|---|---|---|
| nixos-toplevel | 3.62, 3.58, 3.56 s (x0.87, x0.91, x0.90) | 3.96, 3.81, 3.81 s (x1.01, x0.99, x0.97) |
| nixpkgs-73 | 3.30, 3.28, 3.28 s (x0.91, x0.86, x0.88) | 3.54, 3.44, 3.40 s (x0.96, x0.99, x0.97) |

The caches are 6 to 9% faster on nixos-toplevel and 4 to 7% on nixpkgs-73, in every one of the six pairs. Where the hash probes were,
not where the allocations are, was the time.

An AddressSanitizer build of the evaluator could not check the caches: it fails inside MLIR's own `BuiltinDialect::initialize`
(use-after-poison in an `llvm::SmallVector`), the known clash of an instrumented build with the prebuilt, uninstrumented LLVM libraries,
before any evaluator code runs.
