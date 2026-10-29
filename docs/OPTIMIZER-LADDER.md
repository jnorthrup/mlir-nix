# The optimizer ladder: transforms against loops

`include/Composite/MinMaxHeap.h` and `Funnel.h` contain no loop. Every walk is a transform over a `Series` (`fold`, `foldN`,
`vec<N>`, `argMin`, `firstWhere`, `iota`; [PRELOAD](../../TrikeShed/PRELOAD.md)'s "loops become projections"). The question this
page answers is what the C++ optimizers charge for that, and which flags make the charge go away.

## The chart (the header before the premark)

Cluster time of `scripts/inode-bench.cc` (default spill 6, 2,195,456 rows), in seconds. Minimum of five runs, loop version and
transform version interleaved, on Kali (Intel i7-6820HK under WSL2), one boot (`ca6157df`), the working tree on ext4. A negative
change means the transforms are faster. The two versions do the same work: 65,651,101 comparisons over 200,000 batches and
byte-identical output (`scripts/minmax-check.cc`, `funnel-check.cc` and `frozen-check.cc` pass under ASan and UBSan with both
compilers).

| compiler | flags | loops | transforms | change |
|---|---|---:|---:|---:|
| clang 22 | `-O2` | 0.081 | 0.083 | +2.5% |
| clang 22 | `-O3` | 0.080 | 0.075 | **-6.3%** |
| clang 22 | `-O3 -flto=thin` | 0.077 | 0.069 | **-10.4%** |
| clang 22 | `-O3 -flto` | 0.077 | 0.071 | **-7.8%** |
| clang 22 | `-O3 -flto -funroll-loops` | 0.077 | 0.071 | -7.8% |
| clang 22 | `-O3 -flto -mllvm -inline-threshold=2000` | 0.076 | 0.074 | -2.6% |
| g++ 16 | `-O2` | 0.075 | 0.081 | +8.0% |
| g++ 16 | `-O2 -fexpensive-optimizations` | 0.075 | 0.080 | +6.7% |
| g++ 16 | `-O3` | 0.075 | 0.078 | +4.0% |
| g++ 16 | `-O3 -fexpensive-optimizations` | 0.074 | 0.078 | +5.4% |
| g++ 16 | `-O3 -fexpensive-optimizations -funroll-loops -fpeel-loops` | 0.074 | 0.078 | +5.4% |
| g++ 16 | `-O3 -fexpensive-optimizations -fipa-pta -fgcse-after-reload -fgcse-sm -fgcse-las` | 0.073 | 0.078 | +6.8% |
| g++ 16 | `-O3 -fexpensive-optimizations -march=native` | 0.082 | 0.089 | +8.5% |
| g++ 16 | `-O3 -fexpensive-optimizations -fprofile-use` (PGO, trained on this workload) | 0.073 | 0.077 | +5.5% |
| g++ 16 | `-O3 -fexpensive-optimizations -flto` | 0.074 | 0.074 | **+0.0%** |
| g++ 16 | `-O3` with every option above, `-flto -march=native` | 0.084 | 0.081 | -3.6% |

## The same ladder after the premark (`Marks`) went in

`fold` now dispatches on a compile-time premark (`Join<Size<N>, F>` is a constant-size Series; `Marks` says so and `fold` takes
the straight-line path). Re-running `scripts/optimizer-ladder.sh` on the same host and boot with that header, minimum of five:

| compiler | flags | loops | transforms | change |
|---|---|---:|---:|---:|
| clang 22 | `-O2` | 0.081 | 0.084 | +3.7% |
| clang 22 | `-O3` | 0.080 | 0.076 | -5.0% |
| clang 22 | `-O3 -flto=thin` | 0.077 | 0.069 | -10.4% |
| clang 22 | `-O3 -flto` | 0.077 | 0.072 | -6.5% |
| clang 22 | `-O3 -flto -mllvm -inline-threshold=2000` | 0.076 | 0.074 | -2.6% |
| g++ 16 | `-O2` | 0.076 | 0.080 | +5.3% |
| g++ 16 | `-O3` | 0.074 | 0.078 | +5.4% |
| g++ 16 | `-O3 -fexpensive-optimizations` | 0.075 | 0.078 | +4.0% |
| g++ 16 | `-O3 -fexpensive-optimizations -flto` | 0.075 | 0.079 | **+5.3%** |
| g++ 16 | `-O3` with every option above, `-flto -march=native` | 0.085 | 0.079 | -7.1% |

Clang agrees with the first chart. **GCC does not reproduce the earlier parity**: `-O3 -fexpensive-optimizations -flto` was 0.074 against
0.074 with the previous header and is 0.075 against 0.079 now. Either that earlier row was inside the run-to-run spread, or the
dispatching `fold` costs GCC a few percent; one boot and five runs cannot tell them apart. The only GCC row where the transforms win
is the largest combination (unroll, peel, ipa-pta, gcse, native, LTO), where both versions are slower than their `-O3` rows. So the
supported statements are: **clang 22 at `-O3` or better runs the transforms 5 to 10% faster than the loops; GCC 16 runs them 4 to 7%
slower except with the full combination.**

## Pedantic and pragmatic: `COMPOSITE_PEDANTIC`

`MinMaxHeap.h` has two spellings of the same kernels, selected by `-DCOMPOSITE_PEDANTIC=1|0` (default 1). Pedantic is the transform
form (`foldN`, `argMin`, `fold`; no loop written). Pragmatic is the plain loop each transform replaces. They make the same 65,651,101
comparisons with identical output, and both pass `minmax-check` and `funnel-check`. The heap and the pegs now sit on `Inline` bodies of
`MutableSeries`, and `TODO()` is cold and out of line. Kali, one boot, minimum of five (`scripts/optimizer-ladder.sh`), loops =
`cd60c69`:

| compiler | flags | loops | pedantic | pragmatic |
|---|---|---:|---:|---:|
| clang 22 | `-O2` | 0.081 | 0.083 (+2.5%) | 0.083 (+2.5%) |
| clang 22 | `-O3` | 0.080 | 0.076 (**-5.0%**) | 0.077 (-3.8%) |
| clang 22 | `-O3 -flto=thin` | 0.077 | 0.076 (-1.3%) | 0.071 (**-7.8%**) |
| clang 22 | `-O3 -flto` | 0.077 | 0.072 (**-6.5%**) | 0.077 (+0.0%) |
| clang 22 | `-O3 -flto -inline-threshold=2000` | 0.076 | 0.072 (-5.3%) | 0.073 (-3.9%) |
| g++ 16 | `-O2` | 0.076 | 0.081 (+6.6%) | 0.078 (+2.6%) |
| g++ 16 | `-O3` | 0.075 | 0.079 (+5.3%) | 0.082 (+9.3%) |
| g++ 16 | `-O3 -fexpensive-optimizations -flto` | 0.075 | 0.080 (+6.7%) | 0.081 (+8.0%) |
| g++ 16 | `-O3 -fexpensive-optimizations -march=native` | 0.082 | 0.090 (+9.8%) | 0.093 (+13.4%) |
| g++ 16 | everything, `-flto -march=native` | 0.085 | 0.084 (-1.2%) | 0.093 (+9.4%) |

What this supports: neither mode wins everywhere. Under clang at `-O3` or with full LTO the transforms win (pedantic); under ThinLTO
the loop spelling wins by a wide margin (-7.8% against -1.3%); under GCC at `-O3` the pedantic form is the closer of the two but
both are 5 to 9% behind the loops. The default is pedantic because the project builds with clang `-O3`. Two earlier rows should be
read as noise or as superseded: the GCC parity under `-flto` (0.074 against 0.074) did not reproduce, and ThinLTO's -10.4% was for the
heap on a `std::array` and a count, before `Inline` bodies. With 3 to 4 points of run-to-run spread, differences under about 3% are
not distinguishable from noise.

## What it says

- **Under clang, the compiler the project builds with, transforms win** once `-O3` is on, and ThinLTO is best. At `-O2` they are
  2.5 to 3.7% behind.
- **Under GCC, no single flag closes the gap.** `-fexpensive-optimizations` is already on at `-O2`; unrolling, peeling, ipa-pta, gcse,
  PGO and LTO each leave the transforms 4 to 7% behind; `-march=native` is slower for both versions.
- **The cost is inlining, not work.** A fold step is a lambda; unless it is inlined into its caller each heap level pays a call
  and a by-value state copy. `Series.h` forces `fold`, `argMin`, `firstWhere` and `iota` inline, and the step lambdas in
  `MinMaxHeap.h` carry `always_inline`.
- **Two structural thinnings did what no flag did.** Seeding `argMin` from element 1 removed one self-comparison per sift level, and
  the peg "ring" turned out to be a bag (nothing ever moved its `head`), which removed an add and a mask from every peg probe.

## What it does not say

- It is a micro-benchmark of one header-only path. It does not carry over to the evaluator (next section).
- One host, one boot, five runs per cell. Differences under about 2% are inside the run-to-run spread; the +0.0% and +2.5% rows
  should be read as "level".
- PGO was trained on this single workload.

## The whole binary: ThinLTO does not move the evaluator

`mlnix` built with clang 22 `-flto=thin` (GNU ld with clang's plugin; Kali has no gold or lld) beside the ordinary build, same
boot, both timed live against Nix 2.35.4 and Lix 2.91.3, seven interleaved runs, demand schedule, state on ext4. The two
binaries print byte-identical output for every case of the language suite on both schedules (484/484 semantic).

| workload | ordinary: min / vs Nix | ThinLTO: min / vs Nix |
|---|---:|---:|
| nixos-toplevel, demand | 3.79 s / x0.97 | 3.68 s / x0.96 |
| nixpkgs-73, demand | 3.33 s / x0.87 | 3.37 s / x0.88 |

Peak RSS is identical (1203 and 1131 MB for demand). The binary is 1% smaller (32,457,640 against 32,778,064 bytes). The
differences are inside the run-to-run spread (Nix's own minimum moved 3.94 to 3.72 s between the two arms of one session), so
whole-program optimization buys the evaluator nothing measurable. The evaluator is bound by forcing, allocation and cache
misses, not by call overhead the optimizer can remove; the heap micro-benchmark is a different regime.

## Reproduce

On the benchmark host, from the repository root, with the loop version of the headers in `<old>/Composite/`:

```sh
mkdir -p /tmp/old/Composite
for f in MinMaxHeap.h Series.h Pack.h; do git show cd60c69:include/Composite/$f > /tmp/old/Composite/$f; done
bash scripts/optimizer-ladder.sh /tmp/old
```

`cd60c69` is the last commit with the loop heap (the transform rewrite is `d2fbbe2`; the earlier `46182e5` lacks `Cluster::min`, which
the benchmark uses). `CLANG=` and `GCC=` select the compilers.
