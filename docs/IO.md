# I/O: what the evaluator waits for, and what io_uring does about it

Earlier notes here called file I/O a small, fixed cost. That came from a profile with a warm
page cache, and it was wrong for the case that matters: the first evaluation after a boot, a
checkout, or a cache drop. Measured on Linux (Kali on WSL2, kernel 6.18, x86_64, 8 cores, ext4 on
a virtual disk), NixOS toplevel, `scripts/iocost.py`:

    cold 10.63 s    hot 7.51 s    ->  3.12 s (29% of the cold run) waiting for the disk
    nixpkgs-73:  cold 8.44 s, hot 6.60 s  ->  1.84 s

It is serialized latency, not bandwidth: 4,906 files, 21 MB. One evaluation makes 31k `newfstatat`,
7.4k `openat`, 3.5k `read`, 2k `getdents64`, each waiting for the previous one.

## What the storage can do (prefetch-bench.cpp, cut from the tree: `git show dd55950:experiments/uring/prefetch-bench.cpp`)

The 4,906 files the toplevel evaluation opens, page cache dropped before every run:

    sequential (what the evaluator does)     0.92 - 1.07 s
    16 threads                               0.18 s
    io_uring, 16 in flight                   0.22 s
    io_uring, 64 in flight                   0.152 - 0.160 s     <- 6.5x sequential, one thread
    io_uring, 256 in flight                  0.19 s

Each file is a linked chain `openat(direct) -> read -> close(direct)`; 64 chains in flight.

## What it does for the evaluator (scripts/prefetch-ab.py, 4 interleaved cold rounds)

An evaluation touches the same files in the same order every time. `MLNIX_PREFETCH=record:FILE`
writes that list (`F` file read or mapped, `L` lstat, `S` stat, `D` directory listed; first use
order, one `K path` per line). `MLNIX_PREFETCH=replay:FILE` feeds it to one io_uring from a helper
thread at startup. `MLNIX_PREFETCH=auto` keys the list by working directory and arguments under
the state directory: the first run records, later runs replay.

                      cold as is    cold + replay       hot
    nixos-toplevel     9.89 s       7.96 s  (-19.5%)    7.81 s
    nixpkgs-73         8.31 s       6.91 s  (-16.8%)    6.63 s

Result hashes identical on every run (`2057239a9017`, `5e8fff662dff`, the same as on macOS). The
replay of ~12k entries takes 0.13 s and finishes long before the evaluator needs most of it: running
it to completion first (`replay-wait`) is no faster than running it concurrently. Under `strace -T`
a cold replayed run has 25 syscalls over 1 ms, 0.05 s in total.

## What did not work, or did not matter

- `O_CLOEXEC` on `openat` with a direct descriptor is `-EINVAL`; the first ring benchmark silently
  read nothing and reported 0.016 s. It printed `0.0 MB`; that is how it was caught.
- A "hot" row measured right after dropping the cache is cold. The warm-up read has to come first.
- `builtins.readDir` called `lstat` on every entry although `readdir` returns the type: 19k stat
  calls on the toplevel evaluation. It uses `d_type` now (upstream does too), `lstat` only for
  `DT_UNKNOWN`. Worth 0.1-0.2 s cold; the evaluation result is unchanged (60/60 difftest).
- Recording only `readFile`/`import`/`pathExists`/`readDir` left the files copied into the store
  (path coercion) out: 859 cold opens. Recording the store dump walk too took the toplevel result
  from -14.2% to -19.5%.
- Warming only the executable and shared libraries changes nothing (cold data: 9.7-10.0 s); loading
  the executable cold costs about 115 ms.

## Limits

- The first run has no list and is unchanged. A stale list warms files nothing needs; it never
  changes a result.
- Replay is Linux with liburing (found by CMake); elsewhere `record` works and `replay` does nothing.
  macOS has no io_uring; `F_RDADVISE` would be the analogue.
- "Cold" is `drop_caches` inside the VM. On WSL2 the host may still hold the data; a bare-metal
  or network file system will differ, and a slower disk makes the gain larger.
- Imported files are mapped read-only (`nixfe::Source`, `MLNIX_NOMMAP=1` reads and copies). A file
  truncated by another process while it is mapped raises SIGBUS. Store paths do not change.
- The ring reads the first 128 KiB of each file; the rest of a larger file is faulted in on demand.

## Linux build notes (LLVM/MLIR 22 from the distribution)

The project targets LLVM 23. It builds and runs against 22.1.8 with clang-22 and libstdc++ after two
changes (`SideEffects::Resource::getName` is `const` only from 23; `LLVM_DEFINITIONS` must be split
before `add_definitions`), and passes the 466 upstream lang tests (semantic 466/466, exact 208/466,
the same as macOS). Three of twelve FileCheck tests fail on 22 (`declaration`, `effects`,
`identity`): stock CSE does not unify two identical IRDL-defined ops there, while an unused pure
one is still removed and static ops unify. Cause not pinned down beyond that. `mlnix-query` does
not build there (MLIR 22's query headers use `std::vector` of an incomplete type, which libstdc++
rejects).
