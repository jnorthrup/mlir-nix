# The optimizer ladder: transforms against loops

`include/Composite/MinMaxHeap.h` and `Funnel.h` contain no loop. Every walk is a transform over a `Series` (`fold`, `foldN`,
`vec<N>`, `argMin`, `firstWhere`, `iota`; [PRELOAD](../../TrikeShed/PRELOAD.md)'s "loops become projections"). The question this
page answers is what the C++ optimizers charge for that, and which flags make the charge go away.

## The chart

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

## What it says

- **Under clang, the compiler the project builds with, transforms win** once `-O3` is on, by 6 to 10%, and ThinLTO is best. At
  `-O2` they are 2.5% behind.
- **Under GCC, only link-time optimization closes the gap**, to parity. Every other expensive option (`-fexpensive-optimizations`
  is already on at `-O2` in GCC, so the row differs only by noise; unrolling, peeling, ipa-pta, gcse, PGO) leaves the transforms
  4 to 7% behind. `-march=native` is slower for both versions.
- **The cost is inlining, not work.** A fold step is a lambda; unless it is inlined into its caller each heap level pays a call
  and a by-value state copy. `Series.h` forces `fold`, `foldN`, `argMin`, `firstWhere` and `iota` inline, and the step lambdas in
  `MinMaxHeap.h` carry `always_inline`; LTO finishes the job across the benchmark's call sites.
- **Two structural thinnings did what no flag did.** Seeding `argMin` from element 1 removed one self-comparison per sift level
  (+9% to +5% at the time), and the peg "ring" turned out to be a bag (nothing ever moved its `head`), which removed an add and a
  mask from every peg probe (+9% to +2.5% at clang `-O2`).

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
