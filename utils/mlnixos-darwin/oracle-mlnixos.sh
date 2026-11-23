#!/bin/sh
# Real Nix (mlnixos, Nix 2.28.4) as the oracle for the darwin bootstrap's derivations: nixpkgs 3ff0e34 (the store's
# checkout), aarch64-darwin, read-only (computes paths, writes nothing).  STORE_DIR picks the logical store directory.
#   oracle-mlnixos.sh [STORE_DIR]
PATH=/run/current-system/sw/bin:$PATH
T=/mnt/wsl/mlnixos/state/tmp
[ -n "$1" ] && export NIX_STORE_DIR=$1
nix --version
echo "store dir: ${NIX_STORE_DIR:-/nix/store}"
s=$(date +%s)
nix-instantiate --readonly-mode --eval --strict --json $T/stages.nix --arg nixpkgs /mnt/wsl/mlnixos/src/nixpkgs > $T/oracle.out 2> $T/oracle.err
echo "rc=$?"
head -c 4000 $T/oracle.out; echo
head -40 $T/oracle.err
echo "evaluated in $(( $(date +%s) - s )) s"
