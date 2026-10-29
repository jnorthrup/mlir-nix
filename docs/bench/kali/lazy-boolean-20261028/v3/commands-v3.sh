#!/bin/bash
set -euo pipefail
exec 9>/tmp/kb/gen.lock
flock 9
cd "$HOME/work/mlir-nix-dense-selectors-20261028"
tar xzf /tmp/mlir-nix-lazy-boolean-v3-20261028.tar.gz
export GEN_OUT=/tmp/kb/lazy-boolean-20261028-v3
mkdir -p "$GEN_OUT"
unset MLNIX_JIT MLNIX_DEFER MLNIX_STATS MLNIX_PIPELINE MLNIX_PRIMS_IRDL MLNIX_JIT_THRESHOLD MLNIX_JIT_DUMP MLNIX_JIT_PROFILE
v2=/tmp/kb/lazy-boolean-20261028-v2/mlnix
{
 date -u
 uptime
 free -m
 sha256sum /tmp/mlir-nix-lazy-boolean-v3-20261028.tar.gz "$v2"
} > "$GEN_OUT/metadata-start.txt"
bash scripts/kali-gen.sh build
cp build/bin/mlnix "$GEN_OUT/mlnix"
sha256sum /tmp/mlir-nix-lazy-boolean-v3-20261028.tar.gz build/bin/mlnix > "$GEN_OUT/source.txt"
python3 scripts/check-jit.py > "$GEN_OUT/check-jit.txt" 2>&1
cat "$GEN_OUT/check-jit.txt"
for w in nixos-toplevel nixpkgs-73; do
 args=(instantiate --readonly-mode --eval --strict test/nixos-toplevel.nix --arg nixpkgs ./.cache/nixpkgs)
 [ "$w" != nixpkgs-73 ] || args=(instantiate --readonly-mode --eval --strict --json test/nixpkgs-drvs.nix --argstr system x86_64-linux)
 env MLNIX_JIT=1 MLNIX_DEFER=1 MLNIX_STATS=1 MLNIX_JIT_PROFILE=1 MLNIX_STORE_ROOT=/tmp/mlnix-np-root MLNIX_STATE_DIR=/tmp/mlnix-np-state "$GEN_OUT/mlnix" "${args[@]}" > "$GEN_OUT/profile-$w.out" 2> "$GEN_OUT/profile-$w.txt"
 sha256sum "$GEN_OUT/profile-$w.out" >> "$GEN_OUT/profile-hashes.txt"
 python3 - "$w" "$GEN_OUT/profile-$w.out" <<'PY'
import hashlib,sys
expected={'nixos-toplevel':'2057239a9017','nixpkgs-73':'5e8fff662dff'}[sys.argv[1]]
digest=hashlib.sha256(open(sys.argv[2],'rb').read()).hexdigest()
assert digest.startswith(expected),(sys.argv[1],digest)
PY
 grep '^jit:' "$GEN_OUT/profile-$w.txt"
done
python3 scripts/ab.py --mlnix "$v2" --mlnix-b "$GEN_OUT/mlnix" --runs 3 'MLNIX_DEFER=1;MLNIX_JIT=1' 'MLNIX_DEFER=1;MLNIX_JIT=1' > "$GEN_OUT/ab-boolean-v2-on-v3-on-demand.txt" 2>&1
cat "$GEN_OUT/ab-boolean-v2-on-v3-on-demand.txt"
python3 scripts/ab.py --mlnix "$GEN_OUT/mlnix" --runs 5 MLNIX_DEFER=1 'MLNIX_DEFER=1;MLNIX_JIT=1' > "$GEN_OUT/ab-boolean-v3-off-on-demand.txt" 2>&1
cat "$GEN_OUT/ab-boolean-v3-off-on-demand.txt"
for w in nixos-toplevel nixpkgs-73; do
 args=(instantiate --readonly-mode --eval --strict test/nixos-toplevel.nix --arg nixpkgs ./.cache/nixpkgs)
 [ "$w" != nixpkgs-73 ] || args=(instantiate --readonly-mode --eval --strict --json test/nixpkgs-drvs.nix --argstr system x86_64-linux)
 for mode in off on; do
  mode_env=(-u MLNIX_JIT)
  [ "$mode" = on ] && mode_env=(MLNIX_JIT=1)
  env "${mode_env[@]}" MLNIX_STORE_ROOT=/tmp/mlnix-np-root MLNIX_STATE_DIR=/tmp/mlnix-np-state python3 scripts/hw-counters.py -- env MLNIX_DEFER=1 "$GEN_OUT/mlnix" "${args[@]}" > "$GEN_OUT/pmu-v3-$mode-$w.json"
  python3 - "$GEN_OUT/pmu-v3-$mode-$w.json" <<'PY'
import json,sys
r=json.load(open(sys.argv[1]))
if all('unavailable' in event for event in r['events'].values()):
 print('PMU unavailable; no further samples')
 sys.exit(1)
PY
 done
done
{ date -u; uptime; free -m; } > "$GEN_OUT/metadata-end.txt"
printf '%s\n' 'complete; no references or old broad suites executed' > "$GEN_OUT/complete.txt"
