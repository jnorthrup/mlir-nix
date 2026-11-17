# The ordering cluster at differing scales

`include/Composite/MinMaxHeap.h` orders rows in clusters: an Atkinson min-max heap of N rows and a bag of P spare pegs
(15 + 8 = 23 rows in 384 B), one cluster per cell of a block's tiny address space, filled and then drained in key order
([BTRFS-COMPRESSOR.md](BTRFS-COMPRESSOR.md)). This page measures that design at three scales -- the cluster's own shape,
the flood a cell meets, the block window -- and the same structure at the IR op's scale (`trikeshed.cluster_order`, at most
23 keys). Every way of ordering is gated on the same output, byte for byte.

Host: Apple M3 Pro (128 KiB L1d and 128 B lines on a performance core, 16 MiB L2), Apple clang 17, `-O3`, the pedantic
(transform) kernels. Kali (x86_64, 32 KiB L1d, 64 B lines) was unreachable on 2026-11-17, so its column is still to take.

## The block: three scales

`scripts/cluster-scales.cc` builds inode-bench's workload at a chosen window (objectids, so cells, per block) and flood (the
xattr rows every 20th objectid adds: a cell holds 3 rows, or 3 + flood), about two million rows, and orders each block:

- vector: the block copied and `std::sort`ed (inode-bench's A);
- counting: the dense bucket without a heap -- count the rows of each cell (the cell is arithmetic, `hi >> 8`), scatter
  them into their segments, insertion-sort each segment where it lies;
- heap N+P: a `Cluster<InodeRow, N, P>` per cell; a full cluster spills to overflow runs of clusters, whose heads merge with
  the cells' drain (inode-bench's B, its run pool sized to the block); "sorted" drains the pegs as one sorted run instead
  of an argMin over the bag at each pop.

Nanoseconds per row, the minimum of five interleaved rounds (all 90 cells of the sweep identical to the vector's output):

    window  cell rows   vector  counting   7+4    15+8   15+8s   31+16  31+16s   63+32  63+32s   spilled by 15+8
      32      3 / 23     18.0     7.1      20.9   19.8   18.1    17.0   17.4    17.2   17.4        0%
      32      3 / 47     19.1    10.0      30.0   32.9   31.4    34.7   26.0    24.3   24.3       26%
      32      3 / 95     22.0    15.8      39.7   43.4   42.2    54.4   49.5    73.8   36.4       51%
     128      3 / 23     23.8     6.7      22.1   19.0   17.3    16.4   16.9    16.7   16.9        0%
     128      3 / 47     24.8     9.2      33.6   34.0   32.7    33.3   25.0    23.6   23.5       24%
     128      3 / 95     26.3    14.7      46.7   48.9   48.1    56.4   52.2    67.1   35.9       49%
     512      3 / 23     29.3     6.9      24.2   19.2   17.5    17.3   17.9    18.5   18.9        0%
     512      3 / 47     30.4     9.3      37.8   37.6   36.4    34.1   26.1    25.1   25.2       23%
     512      3 / 95     32.0    14.7      53.7   55.6   54.9    62.5   58.0    67.4   37.1       48%

What the scales say:

- The counting dense bucket is the fastest at every scale: 2.3x to 2.7x faster than the best cluster shape for the same
  cells, and 1.4x (small blocks, large floods) to 4.3x (large blocks, small floods) faster than the vector. It has no
  capacity, so nothing spills and nothing is pegged: the count sizes each cell exactly.
- The vector's cost grows with the block (n log n: 18, 24 and 29 ns a row at floods of 20); the cluster's and the
  counting bucket's do not -- their work is local to a cell. That is the island property, and it holds.
- A cluster that holds its cells without spilling beats the vector by a margin that grows with the block: at floods of
  20, 17 against 18 ns a row at window 32 and 17 against 29 at window 512. Large floods turn it round: at floods of 95
  the vector wins at every window, even against the 63+32 that holds the flood (36 to 37 against 22 to 32 ns a row).
- Spill is the cliff. A sixth of the rows spilled (7+4 at floods of 20) still beats the vector at windows 128 and 512; a
  quarter or more (15+8 at floods of 47, the design point one flood up) loses at every window. That generalizes
  inode-bench's "heavy overflow loses to the vector sort".
- A shape bigger than its load costs nothing measurable: a 63+32 cluster (1,536 B; 786 KB of cells at window 512, six
  times L1) orders 3-row cells as fast as a 15+8. A 3-row cell touches its first line and its counts.
- The pegs are a bag drained by argMin, so draining P full pegs costs about P squared comparisons. At 8 pegs that is the
  register-scale cost the header assumes (a sorted drain gains 1% to 9%); at 16 pegs the argMin costs a quarter of the
  time (33 to 35 ns a row, 25 to 26 sorted), and at 32 pegs half (67 to 74, 36 to 37 sorted). Past 8 pegs, sort the bag
  once at drain time.

## The op: at most 23 keys

`trikeshed.cluster_order` lowers to `composite::clusterOrder`: a stable permutation of at most 23 keys through one 15+8
cluster. `scripts/cluster-order-scales.cc` orders 400,000 runs of n keys three ways (the same permutation each time), in
nanoseconds a run, the minimum of five rounds:

    n     keys        cluster   insertion   std::stable_sort
     4    4 values      30.3       15.1        17.8
     4    distinct      32.6       15.9        18.9
     8    distinct      86.1       45.1        48.4
    12    distinct     151.8       76.4        78.9
    16    distinct     241.8      111.2       110.1
    23    4 values     522.0      164.3       160.3
    23    distinct     534.3      177.1       175.2

The cluster is 2x to 3x slower than a plain insertion sort of the indices at every size the op admits.

## What follows

- For fill-then-drain ordering -- the compressor's block, and the dense side of the sea-of-nodes client
  (BTRFS-COMPRESSOR.md, "the sea routes the crossings") -- the island is the counting bucket: count, scatter, sort each cell
  in place. It needs no capacity, so the client's routing question shrinks to dense (the window's key spread fits the cell
  array) or sparse (the funnel), and the vector sort is never the best route at these scales.
- The min-max heap keeps the roles where both of its edges are read online: the run heads of a merge (the spill merge
  uses one), a bounded buffer that must give up its largest row, and the funnel's buckets, where `find` uses the edges to
  skip a scan. Those roles are not timed here.
- Pegs past register scale need a sorted drain; at 8 they do not.
- `clusterOrder` (and so `trikeshed.cluster_order`) could be an insertion sort of the indices with the same contract: at
  most 23 keys, stable, input and output may alias. Not changed here: the op's documentation names the cluster, and that is
  the design's choice to make.

## To repeat

```sh
clang++ -std=c++20 -O3 -I include scripts/cluster-scales.cc -o build/cluster-scales && build/cluster-scales
build/cluster-scales 128 20 512 92     # chosen (window, flood) pairs
clang++ -std=c++20 -O3 -I include scripts/cluster-order-scales.cc -o build/cluster-order-scales && build/cluster-order-scales
```

On macOS use `xcrun clang++` (Homebrew's clang does not find the SDK's headers without SDKROOT).
