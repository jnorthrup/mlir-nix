# The btrfs inode block compressor

Register math is cheap.  Memory is a chasm of time.  Every decision below follows
from that: the ordering work happens in blocks small enough that registers and
cache lines stay on tap, keys pack into words so ordering is arithmetic, and the
hash table is a client the sea of nodes calls on only when a dense bucket cannot
serve.

## Scope: the layer, not the filesystem

Btrfs is the worked example, not the boundary. The problem is any B+tree: a small insert rewrites a whole page, so write
traffic amplifies until something absorbs the inserts. This layer is that something. Clusters buffer and order rows in
registers and a few cache lines; the funnel table answers point lookups in a bounded number of bucket probes; a
drained block is sorted, so it emits as deltas into a sealed, compressed page. Nothing in `MinMaxHeap.h` or `Funnel.h`
is btrfs-specific: a bucket holds any row with `<` and `==`, and the hash is a template parameter. `InodeRow` is one
row type, the btrfs one. Anything keyed by a sorted fixed-width tuple (an LSM run, a Nix store index, a CAS page) takes
the same layer.

## Islands and the sea

The dense structures are islands: a cluster, a dense bucket array over a tiny key window, a funnel level. Inside an
island rows are addressed by arithmetic and ordered by edge swaps, with no pointer chasing and no allocation. The sea of
nodes is the graph between the islands. An island only reports (`insert` returns 0, 1 or 2; a lookup returns a row or
null); it never calls another island. The sea routes the crossings: which island takes a row, and where a full or
foreign row goes next. The funnel's step to the next level is such a crossing. The evaluator has the same split: a native
kernel ([JIT.md](JIT.md)) is an island, and its demand, deopt and depth-overflow results are the crossing messages the
host's forcing loop, the sea, answers.

## The shape

The planned parser reads leaf items and the builder writes compressed blocks.
The current code orders synthetic records between those boundaries:

- A cluster is a min-max heap of a small block count (15 rows of 16 B = 240 B,
  under two 128 B lines on the Mac, four 64 B lines on kali).  The min and the
  max sit at the edges of the heap. A repair follows one heap path.
  Both extremes need a fixed number of row reads.
- A slop cache of spare pegs absorbs what an edge swap displaces.  A full
  cluster that takes a new row swaps its max edge out to a peg; a row beyond the
  edge parks on a peg without touching the heap.  Pegs are a fixed ring, filled
  and drained. A cluster is 384 B on both tested hosts, including counts.
  No cluster operation allocates. This does not guarantee cache residency:
  the benchmark's 128-cluster array is 49,152 B, larger than Kali's 32 KiB L1d.
- The 96-bit index.  A btrfs disk key is objectid(64) + type(8) + offset(64),
  17 B on disk, ordered (objectid, type, offset).  Inside one block window the
  objectid tail is small, so the index a cluster orders is 96 bits: objectid
  tail (24) + type (8) + offset (64), packed into one 32-bit word and one
  64-bit word. The caller must check the window before packing: objectid must
  be at least the base, with a tail below 2^24. Packing is not a lossless
  replacement for every disk key. Comparison needs no pointer lookup.
- Tiny address space, dense buckets. The window's key universe is
  tiny, so the bucket array is addressed by arithmetic on the 96-bit index, not
  hashed: a record's cell is computed, never probed.  Buckets fill by append
  and drain in key order -- the fill and drain pair that docs/FILL-DRAIN.md
  maps across the evaluator, doing the dense sort here, locally dispatched per
  bucket. The heap compares keys during fill and drain. Direct bucket
  addressing avoids a hash probe; it does not remove those comparisons.
- The sea of nodes between the network nodes of type resolution as the hash
  bucket client.  The parser's stream resolves by type into clusters; the sea
  of nodes is the client of the buckets: while the window's address space stays
  tiny the dense bucket serves every record, and only when a block's key spread
  exceeds the dense window does the sea of nodes call the O(1) hash table --
  sparing use, while the code keeps its cache-conscious min-max heaps.
  This client and a Krapivin table are not implemented in this benchmark.
- Ordered keys are the compression.  A drained block is sorted, so the emit
  writes deltas: the objectid tail steps small, the type repeats, the offset
  steps small, and the delta stream feeds the zstd trie the CAS already seals
  (16 KiB pages of fixed-width sorted rows).

## The real material it stands on

- The leaf format: `BtrfsHeader.leaf` (TrikeShed, `borg.trikeshed.btrfs`) --
  a leaf has item headers of 25 B (key 17, offset 4, size 4), sorted keys,
  and data packed at the block end.
- The metadata envelope: `BtrfsMetadataCompression` -- RAW/ZSTD/LZ4, checked,
  payload kept raw when incompressible.  The compressor's envelope is this one.
- The dense CAS: `CursorTrie.kt` -- `HashTrie` (fold-keyed, sealed 16 KiB pages
  sorted by tail, depth up to 3) and `LaneTrie` (16 KiB segments of fixed-width
  rows, one appender, lock-free readers).  The compressor's output pages are
  the same geometry: sealed pages of sorted fixed-width rows.
- The fill/drain vocabulary and the cache geometry of both hosts:
  docs/FILL-DRAIN.md sections 1 and 7.  A fill buffer lives inside L1; the
  sizes are read once and kept; the Mac's performance cores have 128 KiB L1d
  and 128 B lines, kali 32 KiB and 64 B.

## Built / not built

| piece | status |
|---|---|
| `composite::InodeRow` -- a window-relative 96-bit key plus payload handle | built, `include/Composite/MinMaxHeap.h` |
| `composite::MinMaxHeap` -- 15 rows, edges settled by swaps, law as static_asserts | built, same header |
| `composite::Pegs` -- the slop ring of spare rows that settles edge swaps | built, same header |
| dense bucket over the window's tiny address space, fill + drain sort | built, `scripts/inode-bench.cc` |
| ordered overflow drain | built in the benchmark: bounded cluster runs, merged by a small heap of run heads |
| `trikeshed.cluster_order` -- stable row indices from one bounded cluster | kernel and native lowering; coroutine execution checked on Mac and Kali |
| `composite::Funnel` -- a table whose buckets are clusters; a full bucket reroutes one level down | built, `include/Composite/Funnel.h`, checked by `scripts/funnel-check.cc` (Mac only so far) |
| the sea-of-nodes client: dense bucket vs sparse hash, decided per window | not built; the Nix evaluator does not use this heap |
| the btrfs leaf adapter (25 B headers -> records) and the delta emit into the zstd trie envelope | not started |

## Native cluster path

The operation now has a consumer. `trikeshed-lower-clusters` replaces it with
a call to the shared kernel in `lib/Composite/ClusterRuntime.cpp`. That kernel
reads keys through a Series view and calls `composite::clusterOrder`. The
cluster holds signed keys and original row indices. Equal keys keep their
input order. The kernel fills before it drains, so input and output may alias.

The call accepts zero through 23 rows. It rejects unequal lengths, non-unit
strides, and larger runs before reading keys or writing output. The verifier
requires rank-one, strided i64 buffers in host memory. The operation records
its input reads and output writes, so CSE must retain the work.

The existing FileCheck case now includes native execution through the stock
MLIR runner. Two coroutine tasks order separate runs. A third task waits for
both results, checks their order, and frees their output buffers. The same
case checks aliasing and rejection. It uses the standard async runtime, not
a separate scheduler or test framework. A delegate checked native execution
on Mac with LLVM 23.1.1 and Kali with LLVM 22. Both RUN lines passed on both
hosts, with no skips. The LLVM pipeline expands strided metadata before
conversion, so the rejection case also lowers its `memref.subview`.

This is not a Nix evaluator integration or a measured Nix speedup. The parser,
window routing, and btrfs/CAS adapters remain separate work. This case needs
no new Nix or Lix reference run.

## Recovered checks and corrections

The recovered checks exposed faults that the first benchmark missed:

- After swapping with a child, downward repair must stop. The child is on
  the opposite heap level. Continuing broke alternating min/max removal
  with duplicate keys. Both repair paths now stop there.
- Raw `malloc` did not construct the bucket counters. The benchmark now
  constructs its fixed arrays once, before timing.
- The original dataset generated no spills. Extra rows now reach buckets
  that already contain a flood. Each run prints the actual route counts.
- Appending an overflow cluster after later buckets broke global order.
  Ignoring its capacity result also lost rows. Spills now fill bounded
  cluster runs. A heap of run heads merges them with the dense drain.
- The byte comparison now checks every A/B pair, not just the final pair.

`scripts/minmax-check.cc` preserves the recovered checks. It covers binary
keys through full heap capacity under three removal orders, mixed push/pop
work, duplicate keys, signed limits, and reused/full clusters. A failure
returns a nonzero status. The minimal duplicate-key case is also a compile-time
law in the header.

The earlier 23.1% size estimate is withdrawn. It omitted window bases,
framing and absolute initial offsets, and had no decoder. Ordering alone is
not a measured compressor. The leaf adapter and codec remain unbuilt.

## Corrected ordering measurements

Each row below uses three interleaved A/B pairs from the same release binary.
Both paths emit identical full rows, including payload handles, in every pair.
Times are seconds, shown as minimum / mean. These are synthetic ordering
measurements, not Nix execution gains. The earlier no-spill timings do not
measure the intended overflow path.

| host | extra rows per selected flood | vector min / mean | cluster min / mean |
|---|---:|---:|---:|
| Mac | 0 | 0.060 / 0.064 | 0.044 / 0.046 |
| Kali | 0 | 0.094 / 0.101 | 0.074 / 0.080 |
| Mac | 6 (default) | 0.060 / 0.062 | 0.047 / 0.049 |
| Kali | 6 (default) | 0.096 / 0.103 | 0.082 / 0.089 |
| Mac | 48 | 0.072 / 0.073 | 0.074 / 0.077 |
| Kali | 48 | 0.113 / 0.122 | 0.137 / 0.144 |
| Mac | 94 | 0.085 / 0.089 | 0.111 / 0.113 |
| Kali | 94 | 0.133 / 0.143 | 0.196 / 0.205 |

The default case orders 2,195,456 rows, with 49,152 actual spills. Heavy
overflow loses to the vector sort on both hosts. The future graph client
must account for that cost; this benchmark does not implement that policy.

Heap checks and the six spill settings (0, 1, 6, 24, 48, 94) pass address and
undefined-behavior sanitizers on Mac and Kali. Kali also runs with allocator
perturbation. Sanitizer timings are not included in the table.

To repeat on Kali, from the repository root:

```sh
g++-16 -std=c++20 -O2 -g -fsanitize=address,undefined -I include scripts/minmax-check.cc -o build/minmax-check
MALLOC_PERTURB_=165 build/minmax-check
clang++-22 -std=c++20 -O2 -I include scripts/inode-bench.cc -o build/inode-bench
build/inode-bench 6
build/inode-bench 48
```

## The funnel table: loose pegs as the collision cure

`include/Composite/Funnel.h` is the table the sea-of-nodes client would call when a window outgrows its dense buckets.
Each bucket is a cluster (23 rows, 384 B). A bucket that is full says so (`insert` returns 2) and the row reroutes to
its salted bucket one level down, where the bucket count halves, as in Krapivin's funnel. The pegs absorb a burst
past the heap, so a collision costs one more row in the same bucket, not a probe sequence. Levels are `Series` views
over storage the caller owns; nothing allocates. `Cluster::find` uses the heap's min and max edges to skip the heap scan
for a key outside them, then scans the eight pegs.

With no deletes a full bucket stays full, so a lookup that reaches a bucket with room and does not find the key there
has proved the key absent. That bounds the probes by the level count (here 6).

`scripts/funnel-check.cc` (1024 buckets at level 0, 6 levels, 46,000 row slots, random window keys) checks every stored
key against a reference set and counts probes. Buckets touched per lookup, Mac, ASan and UBSan clean:

| load | hit avg / max | miss avg / max |
|---:|---:|---:|
| 0.50 | 1.07 / 2 | 1.48 / 2 |
| 0.80 | 1.42 / 3 | 2.77 / 3 |
| 0.90 | 1.61 / 4 | 3.68 / 4 |
| 0.95 | 1.73 / 5 | 4.43 / 5 |
| 0.99 | 1.86 / 6 | 5.84 / 6 |

No insert was refused, even at 0.99 load. These are probe counts, not times: each probe scans up to 23 rows, and no
timing against a conventional table has been taken. The build has not been run on Kali.

```sh
clang++ -std=c++20 -O2 -g -fsanitize=address,undefined -I include scripts/funnel-check.cc -o build/funnel-check
build/funnel-check
```
