#!/bin/bash
set -euo pipefail
exec 9>/tmp/kb/gen.lock
flock 9
cd "$HOME/work/mlir-nix-dense-selectors-20261028"
tar xzf /tmp/mlir-nix-lazy-boolean-20261028.tar.gz
export GEN_OUT=/tmp/kb/lazy-boolean-20261028-v1
mkdir -p "$GEN_OUT"
unset MLNIX_JIT MLNIX_DEFER MLNIX_STATS MLNIX_PIPELINE MLNIX_PRIMS_IRDL MLNIX_JIT_THRESHOLD MLNIX_JIT_DUMP MLNIX_JIT_PROFILE
baseline=/tmp/kb/dense-selectors-v2-20261028/mlnix
{
 date -u
 uptime
 free -m
 sha256sum /tmp/mlir-nix-lazy-boolean-20261028.tar.gz "$baseline"
} > "$GEN_OUT/metadata-start.txt"
bash scripts/kali-gen.sh build
cp build/bin/mlnix "$GEN_OUT/mlnix"
sha256sum /tmp/mlir-nix-lazy-boolean-20261028.tar.gz build/bin/mlnix > "$GEN_OUT/source.txt"
python3 scripts/check-jit.py > "$GEN_OUT/check-jit.txt" 2>&1
cat "$GEN_OUT/check-jit.txt"
for w in nixos-toplevel nixpkgs-73; do
 args=(instantiate --readonly-mode --eval --strict test/nixos-toplevel.nix --arg nixpkgs ./.cache/nixpkgs)
 [ "$w" != nixpkgs-73 ] || args=(instantiate --readonly-mode --eval --strict --json test/nixpkgs-drvs.nix --argstr system x86_64-linux)
 env MLNIX_JIT=1 MLNIX_DEFER=1 MLNIX_STATS=1 MLNIX_JIT_PROFILE=1 MLNIX_STORE_ROOT=/tmp/mlnix-np-root MLNIX_STATE_DIR=/tmp/mlnix-np-state "$GEN_OUT/mlnix" "${args[@]}" > "$GEN_OUT/profile-$w.out" 2> "$GEN_OUT/profile-$w.txt"
 sha256sum "$GEN_OUT/profile-$w.out" >> "$GEN_OUT/profile-hashes.txt"
 grep -E '^jit:|^jit-boolean|^jit-bool|^jit-demand' "$GEN_OUT/profile-$w.txt" || true
done
python3 scripts/ab.py --mlnix "$baseline" --mlnix-b "$GEN_OUT/mlnix" --runs 3 'MLNIX_DEFER=1;MLNIX_JIT=1' 'MLNIX_DEFER=1;MLNIX_JIT=1' > "$GEN_OUT/ab-selector-v2-on-boolean-v1-on-demand.txt" 2>&1
cat "$GEN_OUT/ab-selector-v2-on-boolean-v1-on-demand.txt"
{ date -u; uptime; free -m; } > "$GEN_OUT/metadata-end.txt"
printf '%s\n' 'complete; no reference execution' > "$GEN_OUT/complete.txt"
