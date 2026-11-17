# The `nix` command, flakes and binary caches

mlnix invoked as `nix` (a symlink: `ln -s mlnix ~/.local/bin/nix`) is a `nix` command over the evaluator.

    nix build|eval|run REF#ATTR      nix profile add|list|remove REF#ATTR      nix derivation|hash|store ...

## Where each part lives

| part | written in | file |
|---|---|---|
| flake references, the lock file's graph of nodes, `follows`, `self`, the outputs fixed point; `builtins.fetchTree`, `builtins.getFlake` | Nix | lib/Corepkgs/flake.nix |
| an installable `REF#ATTR` to a derivation (`packages.<system>.ATTR`, `legacyPackages`, the default package) | Nix | lib/Corepkgs/installable.nix |
| the two primops that enter the Nix above, declared in the `nixstore` dialect (`fetch_tree`, `get_flake`) | IRDL + C++ | include/NixDialect/NixPrims.irdl.mlir, lib/Eval/StoreBuiltins.cpp |
| binary cache substitution: narinfo, fingerprint, signature policy, the references first, `ensure` over a derivation's closure | Nix | lib/Corepkgs/substitute.nix |
| the NAR restore with its hash check and registration (`storeImportNar`), `storeValid`, `storeDerivation`, the Ed25519 check (`cryptoVerify`) | IRDL + C++ | lib/Eval/StoreBuiltins.cpp, lib/Store/Ed25519.cpp |
| the command: arguments, `build`/`eval`/`run`, profile generations (links + manifest.json) | Nix | lib/Corepkgs/cli.nix |
| the boundary cli.nix stands on: `fsMkdir`, `fsSymlink`, `fsRename`, `fsWrite`, `fsReadLink`, `fsUnlink`, `storeReal`, `procSelf`, `procRun`, `procExec`, declared in the `nixstore` dialect | IRDL + C++ | include/NixDialect/NixPrims.irdl.mlir, lib/Eval/StoreBuiltins.cpp |
| `nix` as a program name: its argument vector becomes a Nix list handed to cli.nix | C++ | tools/mlnix.cpp |

The Nix files are embedded by lib/Corepkgs/Embed.cmake and found as `<nix/flake.nix>`, `<nix/installable.nix>`.
The host supplies only bytes and processes: `curl`, `git`, `tar`, `xz`/`zstd`/`bzip2`.

## Flakes

`builtins.getFlake REF` fetches the source (`fetchTarball` for github/gitlab/sourcehut/tarball with the lock's `narHash`,
`fetchGit` for git, a store copy for path), reads `flake.lock`, fetches each locked node and calls `outputs`.
Without a lock file the declared inputs are fetched unpinned. Not done: writing a lock file, `rev` and dates for an
unpinned github ref (they come from the lock), the flake registry beyond five built-in names, `nix flake ...` subcommands.

## Binary caches

`nix build`, `nix run` and `nix profile add` first call `ensure` (substitute.nix) on the installable's derivation: where a
cache holds its outputs they are fetched, else its input derivations' are, so that building builds only what no cache has.
`MLNIX_SUBSTITUTERS` (space-separated URLs; default https://cache.nixos.org; `none`), `MLNIX_TRUSTED_KEYS` (`name:base64`;
default cache.nixos.org-1), `--no-substitute`. A narinfo without a signature by a trusted key is refused. `mlnix build` and
`nix-build` do not substitute: the policy lives in the `nix` command. A failed signature walks every input derivation's
narinfo, which is slow.

## What running a substituted program needs

Cache outputs have `/nix/store/...` paths inside them. mlnix falls back to a chroot store (`~/.local/share/mlnix/root`)
when `/nix` is not writable: paths can be fetched and unpacked there, **and building is refused there**, but programs from
it do not run, because their own references point at `/nix/store`. Installing and running needs a real `/nix/store`.
On macOS that is an APFS volume (`/etc/synthetic.conf` line `nix`, a reboot, `diskutil apfs addVolume ... -mountpoint /nix`),
and a derivation absent from every cache (pi, for one) is then built by `runBuilder`. Checked on this Mac in a writable
`--store-dir`: a two-step `/bin/sh` derivation chain builds and the second reads the first. Not checked: a stdenv build.

## Checks

    python3 scripts/run-mlir-tests.py substitute   # test/mlir/substitute.mlir, offline: a signed file:// cache; fetched with its key, refused with another's
    python3 scripts/run-mlir-tests.py flake     # test/mlir/flake.mlir, offline: path flakes, lock graph with follows, dir, installables, the nix command
