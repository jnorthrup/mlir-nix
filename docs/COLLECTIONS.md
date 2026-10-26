# Collections: what was measured, what was built, what failed

Claim tested: "Krapivin trees are optimal" for Nix attribute sets. (Krapivin's result is
a family of open-addressing hash tables, not trees: elastic and funnel hashing,
Farach-Colton, Krapivin, Kuszmaul, arXiv:2501.02305. That is what was implemented.)

Short answer. The claim is true in the paper's regime and that regime is not ours:

* The tables beat linear probing only above about 94-97% load (measured at 10^6 slots).
  Nix attribute sets are immutable, mostly under 64 entries, and we choose the load.
* On the real lookup traces of the NixOS and nixpkgs evaluations, elastic hashing is
  worse than binary search when hot and mixed when cold, and funnel hashing saves 0-30 ms
  of lookup time for a 71 ms build; in every size class that gets an index (8+ entries)
  both lose to plain linear probing.
* The best structure in the replay (linear probing, 50% load) won the replay and gave
  nothing end to end (-0.0% / -0.3%, 15 interleaved runs). It was reverted.
* The measurement found a real bug instead: `builtins.intersectAttrs` made 90-96% of all
  attribute lookups, all of them misses. Fixed: -1.4% (NixOS) / -6.7% (nixpkgs-73).

## 1. Where the lookups came from

Counting `Bindings::get` per call site (`experiments/attrs/trace.patch`):

                         NixOS toplevel                  nixpkgs-73
    lookups              49,314,433                      92,963,859
    hit rate             7.4%                            2.8%
    one call site        44.2M (89.6%), 0.0% hit         89.1M (95.8%), 0.0% hit

That site was `__intersectAttrs`, which walked the second argument and binary-searched
the first. `callPackage` calls it as `intersectAttrs (functionArgs f) allPackages`: ten
formals against forty thousand packages, so each call did 40,000 failing probes and a
1 MB scan to find about ten hits. Upstream Nix walks the smaller side. Now so do we
(`lib/Eval/Builtins.cpp`); results are identical (the entries always come from the
second set).

                         before            after
    NixOS lookups        49.3M             5.16M
    nixpkgs-73 lookups   93.0M             3.93M
    NixOS toplevel       3.460 s           3.412 s   (-1.4%, 5 interleaved runs)
    nixpkgs-73           3.018 s           2.816 s   (-6.7%)

Seven differential cases against Nix 2.35.4 were added (`scripts/difftest.py`, 60/60);
mutating the fix to take values from the wrong set fails two of them.

What the remaining lookups are (after the fix): `select` 57% / 37% (NixOS / nixpkgs-73,
86-89% hits, mean set size 76 / 232), formals matching 18% / 19%, `has_attr` 12% / 11%,
formal-argument lookup 6% / 12%.

## 2. The tables

`experiments/attrs/krapivin.h` implements both from the paper's text (not ported: the one
C++ port found says its elastic tests "always fail", and LLVM issue #129384 notes that
most ports are not the real algorithm). Funnel hashing: alpha = 4 log(1/delta)+10 levels
shrinking by 3/4, buckets of 2 log(1/delta) slots, a special array of uniform probing
plus two-choice buckets. Elastic hashing: arrays halving in size, batched insertion, the
three cases with f(eps) = c min(log^2(1/eps), log(1/delta)).

`experiments/attrs/test_krapivin.cpp`: every inserted key is found with its value and no
absent key is found (0 incorrect results over all cases). Slots examined per lookup,
10^6 slots, filled to 1 - delta:

    delta   fill     linear probing      funnel            elastic
                     hit      miss       hit     miss      hit     miss
    1/8     87.5%    4.5      32         17.4    57        8.0     130
    1/16    93.8%    8.4      122        25.3    95        11.1    142
    1/32    96.9%    15.8     470        33.2    144       14.7    178
    1/64    98.4%    30.4     1728       40.9    202       17.9    198
    1/128   99.2%    64.4     11019      48.4    269       21.5    253
    1/256   99.6%    131.9    23926      55.8    347       24.7    298

So the paper holds: funnel wins on misses from about 94% fill, elastic wins on hits from
about 97%, and at 99.6% the gap is 5x on hits and 70-80x on misses. Below that, plain
linear probing is better, which is where every table here would run.

Nix-sized tables (m keys in the paper's n = capacityFor(m, 1/8) slots, mean of 400 trials):

    m      slots    linear hit/miss    funnel hit/miss    elastic hit/miss
    16     18       2.3 / 7.5          8.4 / 17.7         4.5 / 14.4
    64     73       3.3 / 14.6         22.8 / 53.0        6.0 / 27.3
    256    292      4.0 / 23.6         22.0 / 83.0        7.1 / 40.9
    1024   1170     4.3 / 29.7         18.0 / 65.6        7.5 / 51.4

Funnel overflowed in 2.8% of trials at m = 4 (the asymptotics need n >> 1000).

## 3. The replay

`experiments/attrs/replay.cpp` replays the recorded sequence of define / `//` / lookup
events (70 MB and 56 MB traces) against each structure. Builds happen before timing, so
a structure is judged on its best case: if it cannot win with free builds it cannot win.

Method corrections that mattered:

* A throughput loop (independent lookups) measured binary search as free: the CPU
  overlaps lookups. The evaluator's lookups are on the critical path, so the replay times
  a dependent chain (the next index depends on this result).
* "Hot" is the original order, "cold" a fixed shuffle (no temporal locality); the
  evaluator is in between. The cold column is noisy: the same code path (sets under 8
  entries, never indexed) measured 27 vs 18 ns between strategies, so only large cold
  differences are trusted. Repeated binary-search baselines: 66.6 / 67.1 / 62.6 ms hot.

ns per lookup (dependent chain), hot / cold, by set size. NixOS toplevel, 5.16M lookups
(63% in sets under 8, 21% in 8-31, 11% in 32-127, 4% in 128+):

                          <8         8-31       32-127     >=128      total hot / cold
    binary search         7.5 / 33   19 / 47    27 / 36    27 / 40    67 / 189 ms
    32-bit key mask       6.4 / 30   14 / 38    25 / 36    29 / 43    56 / 169
    linear probing, 50%   8.6 / 21   11 / 26    14 / 17    8 / 12     50 / 108
    funnel 1/8            10 / 25    15 / 47    23 / 37    16 / 24    67 / 159
    elastic 1/8           8 / 20     22 / 66    24 / 40    20 / 31    70 / 168

nixpkgs-73, 3.93M lookups (40% / 29% / 25% / 7%):

    binary search         6.9 / 27   17 / 44    28 / 44    32 / 49    66 / 148 ms
    32-bit key mask       5.0 / 24   10 / 31    28 / 47    35 / 52    56 / 132
    linear probing, 50%   7.3 / 18   7 / 22     13 / 21    9 / 13     35 / 77
    funnel 1/8            10 / 20    15 / 42    24 / 42    19 / 28    62 / 128
    elastic 1/8           7 / 19     30 / 67    23 / 46    28 / 37    74 / 161

Build cost for an index on every set with >= 8 entries and >= 4 lookups (NixOS): linear
24 ms (+62 MB at 16 B/slot), funnel 71 ms, elastic 58 ms; a mask costs 7-9 ms and no
memory. In the size classes that have an index (8+ entries) funnel and elastic are
behind linear probing in every cell of both tables. Against binary search, funnel
totals 67 vs 67 ms hot and 159 vs 189 cold on NixOS (62 vs 66 hot, 128 vs 148 cold on
nixpkgs-73), so it saves 0-30 ms of lookups and costs 71 ms to build. Elastic is slower
than binary search when hot on both (70 vs 67, 74 vs 66 ms) and mixed when cold (168 vs
189 on NixOS, 161 vs 148 on nixpkgs-73), against a 58 ms build.

## 4. End to end

The replay's best candidate, built into the evaluator (lazy index after 4 lookups on sets
of 8+ entries, 4-byte slots at 50% load from the evaluator's arena), 15 interleaved runs,
same binary with the index switched off for A, identical result hashes:

    NixOS toplevel   3.449 s -> 3.448 s   (-0.0%)
    nixpkgs-73       2.839 s -> 2.831 s   (-0.3%)

Gates were green (466/466; difftest 53/53, the count at the time). A first 7-run A/B had shown -0.8% on both; that was
noise, and is the reason for 15. Not kept: the replay's 17-81 ms of possible savings are
gone once builds, cache pressure and the rest of the evaluator are in the picture. The
32-bit mask (the cheapest candidate, 10 ms hot) was not built: it is below what the
benchmark can resolve.

## 5. Failures and limits

C1. "Optimal" is a statement about a regime (open addressing, no reordering, fixed
    capacity, load -> 1). Immutable sets with a free load factor are outside it.
C2. Elastic hashing has no cheap negative lookup. The paper bounds only successful
    searches for the non-greedy scheme; an absent key needs each array's maximum probe
    depth, which grows with n (45 -> 130 probes at 10^6 slots, 50% -> 87.5% fill). 97% of
    Nix lookups are negative.
C3. Both tables are asymptotic. At Nix sizes funnel has fewer levels than the paper's 22,
    overflows at m = 4, and needs 2-5x the probes of linear probing at the same slots.
C4. No usable third-party C++ code (one port, failing tests). Written from the paper.
C5. A throughput replay hides latency; a cold replay is layout-noisy. Both caveats are
    in the numbers above, not removed from them.
C6. A structure that wins its replay (-26% hot / -43% cold of lookup time) can win
    nothing end to end. The replay is an upper bound, not a forecast.
C7. My first estimate was wrong: "lookups are 5.9% of the profile, so the ceiling is
    6%" came from a profile dominated by one builtin's tight, predictable loop (4 ns per
    lookup). After the fix the remaining 5M lookups cost 13-48 ns each (70-250 ms).
    A profile says where time goes, not why: attribute operations to call sites first.

## 6. Where a tree could still pay: `//`

`//` copies both operands into a fresh sorted array, and the arena never frees:

                                  NixOS toplevel     nixpkgs-73
    `//` calls                    369,945            316,797 (134k trivial)
    entries copied                11.0M (264 MB)     21.4M (514 MB, a fifth of RSS)
    calls with left >= 256        374                773
    entries copied by those       6.1M (56%)         14.4M (67%)

The kernel charges 10% of the NixOS run (0.36 s of 3.46 s, 151,567 page reclaims) for
touching a 2.4 GB footprint. A persistent or layered attribute set (`big // small`
shares `big`, lookup checks the small layer first, iteration flattens once) would turn
those copies into O(small) work. That is where a tree-like structure is the right tool;
the estimate is 1-3% (page-fault share of the copied bytes plus the merge loops) and a
smaller footprint, at the cost of touching every direct reader of `Bindings` (about 40
sites: 14 `attrs[i]` accesses, 14 range-for loops, 14 `size()/empty()` uses). Not built.

## 7. Reproduce

    c++ -std=c++20 -O2 -isysroot $(xcrun --show-sdk-path) -o /tmp/test_krapivin experiments/attrs/test_krapivin.cpp && /tmp/test_krapivin
    git apply experiments/attrs/trace.patch      # counters + MLNIX_ATTRTRACE=file + MLNIX_ATTRSTATS=1
    MLNIX_ATTRSTATS=1 MLNIX_ATTRTRACE=/tmp/t.trace build/bin/mlnix instantiate --readonly-mode --eval --strict test/nixos-toplevel.nix --arg nixpkgs ./.cache/nixpkgs
    c++ -std=c++20 -O2 -isysroot $(xcrun --show-sdk-path) -o /tmp/replay experiments/attrs/replay.cpp && /tmp/replay /tmp/t.trace

The patch is against the tree before the experiment (`git checkout` the two files after).
