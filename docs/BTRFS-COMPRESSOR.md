# The btrfs inode block compressor

Register math is cheap.  Memory is a chasm of time.  Every decision below follows
from that: the ordering work happens in blocks small enough that registers and
cache lines stay on tap, keys pack into words so ordering is arithmetic, and the
hash table is a client the sea of nodes calls on only when a dense bucket cannot
serve.

## The shape

The parser reads leaf items and the builder writes compressed blocks; between
them the records populate and agglomerate in clusters:

- A cluster is a min-max heap of a small block count (15 rows of 16 B = 240 B,
  under two 128 B lines on the Mac, four 64 B lines on kali).  The min and the
  max sit at the edges of the heap; swaps settle at the edges and never walk the
  whole heap.  Both extremes are O(1) register reads.
- A slop cache of spare pegs absorbs what an edge swap displaces.  A full
  cluster that takes a new row swaps its max edge out to a peg; a row beyond the
  edge parks on a peg without touching the heap.  Pegs are a fixed ring, filled
  and drained; nothing allocates, nothing leaves L1.
- The 96-bit index.  A btrfs disk key is objectid(64) + type(8) + offset(64),
  17 B on disk, ordered (objectid, type, offset).  Inside one block window the
  objectid tail is small, so the index a cluster orders is 96 bits: objectid
  tail (24) + type (8) + offset (64), packed into one 32-bit word and one
  64-bit word.  Compare is register math: two loads, two compares, no memory.
- Krapivin tiny address space, dense buckets.  The window's key universe is
  tiny, so the bucket array is addressed by arithmetic on the 96-bit index, not
  hashed: a record's cell is computed, never probed.  Buckets fill by append
  and drain in key order -- the fill and drain pair that docs/FILL-DRAIN.md
  maps across the evaluator, doing the dense sort here, locally dispatched per
  bucket, with no comparison in the fill and no search in the drain.
- The sea of nodes between the network nodes of type resolution as the hash
  bucket client.  The parser's stream resolves by type into clusters; the sea
  of nodes is the client of the buckets: while the window's address space stays
  tiny the dense bucket serves every record, and only when a block's key spread
  exceeds the dense window does the sea of nodes call the O(1) hash table --
  sparing use, an elastic Krapivin-style open-address table for the sparse
  tail, while the code keeps its cache-conscious min-max heaps.
- Ordered keys are the compression.  A drained block is sorted, so the emit
  writes deltas: the objectid tail steps small, the type repeats, the offset
  steps small, and the delta stream feeds the zstd trie the CAS already seals
  (16 KiB pages of fixed-width sorted rows).

## The real material it stands on

- The leaf format: `BtrfsHeader.leaf` (TrikeShed, `borg.trikeshed.btrfs`) --
  a leaf is item headers of 25 B (key 17, offset 4, size 4), keys sorted,
  data packed at the block end.  A 16 KiB leaf holds at most 655 items.
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
| `composite::Idx96` -- the 96-bit block index, packed key | built, `include/Composite/MinMaxHeap.h` |
| `composite::MinMaxHeap` -- 15 rows, edges settled by swaps, law as static_asserts | built, same header |
| `composite::Pegs` -- the slop ring of spare rows that settles edge swaps | built, same header |
| dense bucket over the window's tiny address space, fill + drain sort | built, `scripts/inode-bench.cc` |
| the sea-of-nodes client: dense bucket vs sparing O(1) hash, decided per window | declared, not built (the bench reroutes a spill to the next cluster, the declared cheap path) |
| the btrfs leaf adapter (25 B headers -> records) and the delta emit into the zstd trie envelope | not started |

## The first measurement (2026-10-27)

The bench feeds 4,096 block windows of 128 objectid tails each -- inode items,
refs, dir indexes, 5% xattr floods that fill the pegs, 1% overflows that spill
-- 2,195,456 rows, arrival shuffled.  Path A is the stdlib shape: a
`std::vector` filled and `std::sort`'d a block.  Path B is the cluster shape:
a dense bucket of 15-row clusters addressed by the objectid tail (arithmetic,
no hash), pegs settling the edges, spill rerouted to the block's overflow
cluster, drain in cell order.  3 interleaved runs, min wall:

| host | vector | cluster | gain | gate |
|---|---|---|---|---|
| Mac (M3 Pro, 128 KiB L1d, 128 B line) | 0.062 s, 35.4 M rows/s | 0.045 s, 48.8 M rows/s | 27% | byte-identical |
| kali (WSL2, 32 KiB L1d, 64 B line) | 0.098 s, 22.4 M rows/s | 0.073 s, 30.1 M rows/s | 26% | byte-identical |

The ordering is the compression: the drained stream's keys delta-encode to
23.1% of the raw 17 B a row (37.3 MB -> 8.6 MB of varints) before any zstd,
and the same stream through both paths is the gate.  The compile-time law
earned its keep before the first run: it caught an inverted push branch (the
Atkinson swap condition) and a max edge that picked the smaller child -- both
would have ordered wrongly under load, and neither survived `static_assert`.

The law, in the header: a cluster filled out of order and drained emits the
same stream a sort of the same rows emits, and the edges never move more than
one row.  Numbers land here when the bench runs: 3 interleaved runs, min and
mean wall, identical output bytes as the correctness gate.
