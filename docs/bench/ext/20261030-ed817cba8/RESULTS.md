# asnix and ll against Nix, Lix and mlnix (Kali, 2026-10-30)

Harness: `scripts/vs-nix.py --native --demand --runs 7 --budget 200 --asnix PATH --ll PATH --ref Nix --ref Lix`, real reference runs (no `--reuse-refs`), interleaved rounds with a rotating start order, one workload per call. The raw tables are `ffmpeg.txt`, `nixos-toplevel.txt`, `nixpkgs-73.txt`; the run is `summary.txt`.

Under test: mlir-nix `ed817cba8` (`build/bin/mlnix`), Nix 2.35.4, Lix 2.91.3, asnix `4c6d833` (2026-10-30), ll `a64b79e` (2026-10-29), built with `make` (asnix with cc, ll with `CC=clang-22`). x86_64, 8 threads, i7-6820HK, a WSL2 VM.

An evaluator's answer is checked against the first reference's (Nix) before it is timed; one that differs or fails gets no ratio.

## ffmpeg (identical output from all six, sha256 e3a4fafd5224)

| evaluator    | min s | median s | peak RSS MB | median / Nix | median / Lix |
|--------------|------:|---------:|------------:|-------------:|-------------:|
| Nix 2.35.4   |  2.00 |     2.04 |         356 |              |              |
| Lix 2.91.3   |  2.16 |     2.37 |         431 |              |              |
| mlnix        |  1.70 |     1.78 |         574 |         0.87 |         0.75 |
| mlnix demand |  1.36 |     1.44 |         470 |         0.70 |         0.61 |
| asnix        |  1.23 |     1.25 |         512 |         0.61 |         0.53 |
| ll           |  1.15 |     1.30 |         483 |         0.63 |         0.55 |

This is the closure asnix measures itself on (`test/nixpkgs-ffmpeg.nix`), and both of its evaluators are faster than mlnix on it.

## nixos-toplevel (sha256 2057239a9017 from Nix, Lix and mlnix)

| evaluator    | min s | median s | peak RSS MB | answer                                   |
|--------------|------:|---------:|------------:|------------------------------------------|
| Nix 2.35.4   |  4.15 |     4.46 |         628 | reference                                |
| Lix 2.91.3   |  4.72 |     4.83 |         755 | identical                                |
| mlnix        |  2.91 |     2.94 |        1132 | identical (0.66 of Nix, 0.61 of Lix)     |
| mlnix demand |  2.54 |     2.81 |        1025 | identical (0.63 of Nix, 0.58 of Lix)     |
| asnix        |  2.77 |     3.01 |        1174 | differs: ca0018c161a5, not a comparison  |
| ll           |  3.09 |     3.26 |        1103 | differs: ca0018c161a5, not a comparison  |

The difference is the toplevel derivation's hash: Nix prints `/nix/store/0sa095my...-nixos-system-nixos-25.05pre-git.drv`, asnix and ll print `/nix/store/3gk10vqm...-nixos-system-nixos-25.05pre-git.drv` (same name, 82 bytes each, asnix and ll agree with each other). Which derivation in the closure first differs was not looked for.

## nixpkgs-73 (sha256 5e8fff662dff)

| evaluator    | min s | median s | peak RSS MB | answer                                          |
|--------------|------:|---------:|------------:|-------------------------------------------------|
| Nix 2.35.4   |  3.67 |     4.03 |         593 | reference                                       |
| Lix 2.91.3   |  4.47 |     4.66 |         757 | identical                                       |
| mlnix        |  2.52 |     2.56 |        1113 | identical (0.64 of Nix, 0.55 of Lix)            |
| mlnix demand |  2.20 |     2.37 |        1011 | identical (0.59 of Nix, 0.51 of Lix)            |
| asnix        |       |          |             | fails rc=1: `derivation: too many outputs (max 16)` |
| ll           |       |          |             | fails rc=1: `derivation: too many outputs (max 16)` |

## Conditions

The host had been restarted 40 minutes earlier and was busy (Defender and desktop programs, about 20% of its CPU), so absolute times are about 10% above a quiet host's (cached Nix timings of the same workload were 3.81 s at 08:51). The ratios inside one table come from interleaved rounds and are the figures to compare; these tables are not a release-grade generation.

## numtide/nix-conformance (corpus 466c61d, `lang/`)

Adapters of tomberek/asnix and tomberek/ll, `make test-nix-conformance`:

|                   | passed | failed | known | skipped |
|-------------------|-------:|-------:|------:|--------:|
| adapters as found |    653 |      0 |     3 |     208 |
| with the PRs      |    763 |      0 |    21 |      80 |

The PRs: https://github.com/tomberek/asnix/pull/1 and https://github.com/tomberek/ll/pull/1.
