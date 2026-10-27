# The library is the workload

The continents (the primop dialects, `include/NixDialect/NixPrims.irdl.mlir`) are 5,324 of the 619,842 ops lowered for the NixOS
toplevel, 0.9%. The border they sit on is crossed from nixpkgs' `lib`, which is Nix code: `lib.foldl'` is a lambda that calls
`builtins.foldl'`. This file is the map of that border: where the lambda calls of a real evaluation are made, what they are made of, what
moving a library function across the border would be worth, and what is and is not proposed. Everything measured is from `MLNIX_STATS=1`
on the Mac, demand schedule (`MLNIX_DEFER=1`), on the two workloads of the head-to-head, over the same nixpkgs (the `nixos-25.05` tarball
whose sha256 is in the [README](../README.md)). Nothing here is built except the instrument.

    MLNIX_STATS=1 MLNIX_STATS_LAMBDAS=700 MLNIX_DEFER=1 build/bin/mlnix instantiate ... 2> stats.txt
    python3 scripts/lambda-functions.py stats.txt --top 40

## Where the calls are

A call is a call of a `nix.lambda`; a curried function is one lambda per argument, so `optionalAttrs cond as` is two calls.
5,387,038 calls on the NixOS toplevel, 3,762,175 on nixpkgs-73.

| area of the tree | nixos-toplevel | nixpkgs-73 |
|---|---:|---:|
| `lib/` | **91.4%** | **76.8%** |
| `pkgs/stdenv` | 4.2% | 11.2% |
| `pkgs/top-level` | 1.1% | 6.4% |
| `pkgs/development` | 1.7% | 2.8% |
| `nixos/modules` | 0.7% | 0.1% |
| everything else | 0.9% | 2.7% |

Inside `lib/`, by file (the same two columns): `modules.nix` 47.4% | 9.4%, `trivial.nix` 11.2% | 13.8%, `lists.nix` 10.5% | 14.1%,
`attrsets.nix` 8.3% | 16.4%, `strings.nix` 4.4% | 6.8%, `types.nix` 3.1% | 0.6%, `systems/default.nix` 2.4% | 8.8%, `options.nix` 1.6% | 0.2%,
`meta.nix` 0.9% | 2.9%. In `pkgs/stdenv`: `generic/make-derivation.nix` 3.0% | 8.0%, `generic/check-meta.nix` 1.2% | 3.1%; `pkgs/top-level/splice.nix`
1.0% | 6.2%.

## What the calls are made of

Small functions. Share of all calls that are in functions of at most N ops (all the lambdas of a curried function together):

| N | 4 | 8 | 16 | 32 |
|---|---:|---:|---:|---:|
| nixos-toplevel | 8.3% | 34.6% | 58.7% | 77.9% |
| nixpkgs-73 | 6.1% | 34.0% | 58.7% | 80.5% |

The functions that lead, with their share of all calls (a curried function counts once per argument):

| function | where | toplevel | nixpkgs-73 |
|---|---|---:|---:|
| `warnIf` | `trivial.nix:825` | 6.6% | 6.5% |
| `imap1` | `lists.nix:345` | 3.6% | 5.3% |
| `optionalAttrs` | `attrsets.nix:1353` | 3.1% | 7.8% |
| `hasPrefix` | `strings.nix:769` | 2.8% | 4.0% |
| `removeFunctions` | `systems/default.nix:46` | 2.4% | 8.7% |
| `optional` | `lists.nix:777` | 2.3% | 3.7% |
| `foldl'` | `lists.nix:277` | 2.0% | 0.5% |
| `isFunction` | `trivial.nix:1023` | 1.8% | 4.6% |
| `filterAttrs` | `attrsets.nix:657` | 1.4% | 4.7% |
| `min` | `trivial.nix:524` | 1.3% | 0.3% |
| `optionals` | `lists.nix:811` | 1.2% | 3.0% |
| `platformMatch` | `meta.nix:241` | 0.7% | 2.5% |
| `optionalString`, `assertMsg`, `id`, `isDerivation`, `subtractLists`, `nameValuePair` | | 2.0% | 5.7% |
| those 18 | | **31.2%** | **57.4%** |

(The first sixteen of them, without `foldl'` and `platformMatch`, are 28.4% | 54.4%, the figures in the commit that added the instrument; the
ranking showed two more once the lines were read, so the set is a floor.) `hasPrefix` calls `warnIf`, which is why `warnIf` leads.

The calls are in the leaf functions, but the work is not: weighting each call by the ops in its body, the module system (`modules`, `types`,
`options`) is 68% | 14% of the work, the rest of `lib` 16% | 26%, `pkgs/stdenv` and `pkgs/top-level` 13% | 54%. The big bodies are `loadModule` (180 ops),
`collectModules` (132), `unifyModuleSyntax` (282), `evalOptionValue` (201), `mergeDefinitions` (207) on a NixOS evaluation, and splice's `merge`
(83) and `checkDependencyList'` in `make-derivation.nix` (93) on a package set. Ops in the body is a proxy: it counts the ops of a body, not the
ones a call executes.

## What moving a leaf function across the border is worth

A bound from one measurement, not a result. Three million iterations of `foldl'`, each calling `f true acc` through a variable, in the
three forms below (Mac, best of five runs, seconds; the first eager run of the first form was 0.15):

| `f` is | eager | demand |
|---|---:|---:|
| not called (`acc`) | 0.11 | 0.10 |
| `builtins.seq`, a two-argument primop | 0.16 | 0.17 |
| `optionalAttrs`, interpreted | 0.27 | 0.24 |

That is 17-23 ns for the primop call and 47-53 ns for the interpreted one, so **about 30 ns saved per call** of a function of 8 ops. The 18
functions are 0.88 M (toplevel) and 1.27 M (nixpkgs-73) calls of the whole function (not of each lambda). At 30 to 60 ns each, the upper end
for larger bodies, that is 26-53 ms of a 1.58 s run (1.7-3.3%) and 38-76 ms of 1.30 s (2.9-5.9%). That is the size of one good change of this
project, not a different order, and it holds only to the extent that a native function costs what a primop costs.

## What it would take (nothing of this is built)

- **Recognition by structure.** At lowering, a lambda whose syntax tree has the same structural hash (positions and binder names ignored, free
  variables by name) as the reference definition of a registered function is marked native. The registry is data: the reference text and the
  native function, next to `NixPrims.irdl.mlir`, as the continents are. A definition that nixpkgs changes hashes differently and is
  interpreted, so the library can move without making the evaluator wrong.
- **Free variables are checked, not assumed.** `hasPrefix` calls `warnIf`, `imap1` calls `genList`, `elemAt` and `length`, which `lists.nix`
  gets from `builtins` by `inherit`. The native function runs only if the captured values are the primops (or registered natives) the reference
  expects, checked at the first call; otherwise the lambda is interpreted.
- **The value stays a lambda.** Only the call changes, so `typeOf`, `functionArgs`, `isFunction`, printing as `<LAMBDA>` and equality are unchanged.
- **The interpreted definition is the oracle.** Each entry gets a differential test of the result and of what was forced, in which order, on
  generated inputs that include throwing ones, run native against `MLNIX_NATIVE=0`; and `scripts/difftest.py` against Nix as before.
- **What a user can see change.** An error raised inside a subsumed function loses the library frame in its trace
  (`while calling anonymous lambda at .../lists.nix:777`), and `MLNIX_STATS` counts the call as a primop.

## What is not proposed

Rewriting the module system or `mkDerivation` natively. That is where the work is, and also the largest semantic surface, tied to one
nixpkgs and to its error messages. The cheaper first question is which of their functions the time goes to, by inclusive time and not by
calls, and how much of it is in the primops they call (`mapAttrs`, `zipAttrsWith`, `attrNames`, `filter`, `concatMap`, `foldl'`), where a
faster continent helps every caller. Neither is measured yet.
