# Where the frame bytes are

`MLNIX_STATS=1` (demand schedule, counts independent of the machine) accounts for the call frames. Frames are never freed, so their
storage is part of the peak: about 300 MB of mlnix's 1.2 GB on both workloads (Nix peaks at 0.6 GB). Frame time is not the issue:
removing 5.4% and 11.5% of the frames (the selector recognition) changed no wall time.

## What the frames are

- 5.1M frames on nixos-toplevel, 3.3M on nixpkgs-drvs (after the selector recognition); 28.4M slots, of which 32% are ever read.
- `MLNIX_STATS_SHAPES=n` groups lambdas by a name-free canonical form of their IR. The largest group is the unique module-system
  bodies (22% of frames in 3,532 lambdas); next come `x: x` (4.3%), `x: x.a` (2.5%), `lib.warnIf` (4.6%, a three-lambda chain),
  `lib.isFunction` (1.9%), `!(pred x)` (1.7%), `imap1`, `hasPrefix`, `filterAttrs`, and curried selections.

## Non-escaping frames are not the lever

A frame can live on the C++ stack only if no op of its body can make a thunk, closure, list or set over it. With a conservative
whitelist of strict ops, that is **9.3%** of nixos-toplevel's frames (5.9% on nixpkgs-drvs) and 10.9 MB of 294 MB of frame storage
(4.5 MB of 260 MB). Not worth building: it saves under 1% of peak memory.

## Big frames are the lever

nixos-toplevel, frame storage by slots per frame (the 1-slot row's "read" share is an artifact: the argument cell is filled at call
time, so it counts as unread; every row's read share is understated by about one slot per frame):

| slots | frames | frame storage | slot words | read | dead |
|---|---:|---:|---:|---:|---:|
| 1 | 49.4% | 57.6 MB (19.6%) | 19.2 MB | n/a | n/a |
| 2-3 | 28.0% | 48.7 MB (16.6%) | 27.0 MB | 45.4% | 14.7 MB |
| 4-8 | 8.7% | 24.9 MB (8.5%) | 18.1 MB | 48.6% | 9.3 MB |
| 9-16 | 8.0% | 42.1 MB (14.3%) | 35.8 MB | 34.1% | 23.6 MB |
| 17-64 | 5.1% | 71.5 MB (24.3%) | 67.6 MB | 25.1% | 50.6 MB |
| 65+ | 0.9% | 49.3 MB (16.8%) | 48.6 MB | 39.6% | 29.3 MB |

On nixpkgs-drvs the 17-64 row reads **7.5%** of its slots and holds 88.6 MB of dead slot words (100.3 MB of 260 MB frame storage).
Frames of 9 or more slots are 14% of frames and 55% of frame storage; their dead slot words are 104 MB on nixos-toplevel and 132 MB
on nixpkgs-drvs, 8 to 11% of peak memory as an upper bound.

## Sparse frames do not pay

The idea: allocate a big frame's slots as they are first read. It works only if the slots a call reads are clustered, so
`MLNIX_STATS=1` keeps a mask of the slots read in each frame and, at the end of the run, prices a frame made of a table of chunks
(a chunk made on its first read; the table costs a pointer a chunk, the header one pointer more) against the flat frame, for every
frame of 9 or more slots:

| chunk | nixos-toplevel (712,892 frames, 35.5% of slots read) | nixpkgs-drvs (528,132 frames, 25.1% read) |
|---|---|---|
| 8 slots | 70.9% touched, saves -0.3 MB | 60.7% touched, saves 30.5 MB (17.0%) |
| 4 slots | 58.3% touched, saves 10.5 MB (6.4%) | 46.6% touched, saves 38.7 MB (21.6%) |
| 2 slots | 44.7% touched, saves -0.3 MB | 33.8% touched, saves 22.6 MB (12.6%) |
| 1 slot | 35.5% touched, saves -59.4 MB (-36.4%) | 25.1% touched, saves -47.0 MB (-26.2%) |

The reads are scattered: a quarter to a third of the slots are read but half to three quarters of the 8-slot chunks are touched.
The best chunking (4 slots) saves 10.5 MB of nixos-toplevel's 1.2 GB peak (0.9%) and 38.7 MB of nixpkgs-drvs (about 3%), and every
read of a slot would pay the table indirection. It is not worth building.

The table above is the record: the pricing code that produced it has been taken out of `MLNIX_STATS` (the mask stays, it counts the
slots ever read).

## What the peak is made of

`MLNIX_STATS=1` now prints the arena against the process's peak RSS. Everything the evaluator builds is in one never-freed bump arena
(`include/Nix/Arena.h`). nixos-toplevel, demand schedule (a stats run: the per-frame masks of the census above add to the arena and the
RSS, so the percentages are against 1,363 MB, not the 1,203 MB of an ordinary run):

| | MB | of the arena | of peak RSS |
|---|---:|---:|---:|
| Value cells (12.2M of 24 bytes) | 280 | 33% | 21% |
| frames | 294 | 34% | 22% |
| attribute rows | 92 | 11% | 7% |
| string bytes | 38 | 4% | 3% |
| list cells | 14 | 2% | 1% |
| other, slab slack and the census masks | 143 | 17% | 10% |
| **arena (slabs)** | **861** | | **63%** |
| outside the arena: lowered IR, parsed sources, the MLIR context | about 500 | | 37% |

nixpkgs-drvs: 820 MB of slabs against 1,205 MB (68%), values 235, frames 260, attribute rows 79, strings 47, lists 12.

Values and frames are two thirds of the arena and about half of all memory. Neither stack frames (under 1% of peak) nor sparse frames
(1 to 3%) take much of the frames; the cells that would fall to a strictness analysis (27 to 32% of real thunks are never forced) are
the value half, and the frames that fall to a `lib` continent are the other. The IR and the parsed sources are the 37% outside the
arena and have not been accounted by use.

## Recycling frames, and what projections would add

A frame that returns with no thunk or closure made over it can never be reached again. `Frame` carries a captured bit in the low bit of
its `up` pointer, set at the only two places a frame pointer enters a value (a thunk or closure cell in `lookup`, a closure in
`evalDefinition`); such a frame is pushed on a per-slot-count free stack when its call returns normally, and `newFrame` reuses it.
It is opt-in, `MLNIX_RECYCLE=1`, because on Kali it trades time for memory. Same boot, three interleaved rounds, demand, minimum of 5,
against live Nix:

| | nixos-toplevel | peak RSS | nixpkgs-73 | peak RSS |
|---|---|---|---|---|
| recycling on | 3.84, 3.67, 3.71 s | 1,141 MB | 3.32, 3.37, 3.34 s | 1,090 MB |
| recycling off | 3.64, 3.64, 3.62 s | 1,177 to 1,180 MB | 3.38, 3.30, 3.36 s | 1,112 to 1,113 MB |

The memory saving is exact and what the simulation below predicted (-36 to -39 MB, -22 MB). The time is not: on nixos-toplevel every round
with recycling is slower, by 1 to 6%; on nixpkgs-73 there is no difference. The arena's prefault thread already makes fresh memory cheap,
so reusing an L1-hot frame saves no bandwidth, and the captured-bit store on every thunk and the free-list pop cost a little. With it off,
the captured bit is not even written. Output is identical with it on and off.

`MLNIX_STATS=1` simulates allocators that would go further. Each keeps a free list per slot count and records how many bytes were
allocated between a frame's release and its reuse:

| what may release a frame | nixos-toplevel: new frames reusing storage, MB | nixpkgs-drvs |
|---|---|---|
| it returned with nothing made over it (built) | 17.7%, 38.2 MB | 21.0%, 22.2 MB |
| ... or every thunk over it has been forced, no closure pins it | 32.2%, 70.7 MB | 36.6%, 41.8 MB |
| ... and projections of an argument or captured value hold no frame | 35.3%, 75.0 MB | 37.6%, 42.9 MB |
| ... and calls, selects, formals hold their operand cells instead | 39.3%, 90.5 MB | 39.1%, 49.3 MB |
| ... and lists, sets, ifs and string concatenation too | 44.6%, 131.8 MB | 51.4%, 146.4 MB |
| every thunk self-contained (flat closures) | 46.5%, 167.8 MB | 53.0%, 181.3 MB |

97 to 98.5% of the simulated reuses land within 32 KiB of allocation, Kali's L1d: a recycled frame is hot. Of the thunks that need their
frame, calls are 31% (26% on nixpkgs-drvs), non-argument selects 14%, lists 7%, sets 7%, formals 6 to 9%, string concatenation 5 to 6%,
conditionals 5 to 7% (`MLNIX_STATS_DOWNGRADE=` names the families the simulation treats as frame-free). The rest of the frames are pinned
by closures, which nothing collects. The two lines past "every thunk over it has been forced" need reference counting that a copied
unforced thunk would break, and the last two need thunks that carry their operand cells, which creates those cells eagerly; the simulation
prices neither, so they are ceilings, not plans.
