# The JIT against the interpreter, 18 November 2026

The opt-in JIT (`MLNIX_JIT=1`: lib/Eval/ScalarJIT.cpp, LazyJIT.cpp) at 3b46257, on the two workloads of `scripts/bench.py`,
JIT off and on in turn, twice, five runs each. Host: the OrbStack machine mlnix-os on an M3 Pro (Debian trixie arm64),
built with clang-22 and LLVM 22 (Release). The answers are the same either way.

    round  JIT   nixos-toplevel                    nixpkgs-73
                 min     median  peak RSS          min     median  peak RSS
    1      off   1.16 s  1.20 s  1133 MB           0.86 s  0.89 s  1097 MB
    1      on    1.29 s  1.32 s  1217 MB           0.99 s  1.00 s  1144 MB
    2      off   1.15 s  1.19 s  1133 MB           0.87 s  0.89 s  1099 MB
    2      on    1.31 s  1.34 s  1217 MB           1.00 s  1.01 s  1142 MB

    result hashes: nixos-toplevel f1cfa7cd1464, nixpkgs-73 5e8fff662dff, in all eight passes

On, the JIT is 11-12% slower on both and holds 4-7% more memory. Its last measurement before this one (Kali, 28 October,
docs/bench/kali/list-returns-20261028/RESULTS.md) also found the whole JIT 4.0-6.5% slower in wall time. It was off by
default; nothing used it but its own check (scripts/check-jit.py) and the --jit arm of scripts/vs-nix.py. It lowered the
nix ops straight to arith, cf and LLVM, beside TrikeShed rather than through it, so it was removed with its control
setting (`mlnix.jit`). It is at 3b46257.

Command (from the staged source of 3b46257, `.cache` linked to the checkout's):

    python3 scripts/bench.py --mlnix BUILD/bin/mlnix --runs 5            # and with MLNIX_JIT=1
