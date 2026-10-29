#!/bin/bash
set -euo pipefail
exec 9>/tmp/kb/gen.lock
flock -n 9
cd "$HOME/work/mlir-nix-dense-selectors-20261028"
sha256sum /tmp/mlir-nix-curried-dispatch-v2-20261028.tar.gz | grep -q '^77d0788b1a5355acd3d7d9511c69c150c030b5b18446e7b6d6817415b56dec71 '
tar xzf /tmp/mlir-nix-curried-dispatch-v2-20261028.tar.gz
export GEN_OUT=/tmp/kb/curried-20261028-dispatch-v2
mkdir -p "$GEN_OUT"
unset MLNIX_JIT MLNIX_JIT_INLINE MLNIX_JIT_CURRIED MLNIX_DEFER MLNIX_STATS MLNIX_PIPELINE MLNIX_PRIMS_IRDL MLNIX_JIT_THRESHOLD MLNIX_JIT_DUMP MLNIX_JIT_PROFILE
baseline=/tmp/kb/curried-20261028-v1/mlnix
{ date -u; uptime; free -m; sha256sum /tmp/mlir-nix-curried-dispatch-v2-20261028.tar.gz "$baseline"; } > "$GEN_OUT/metadata-start.txt"
bash scripts/kali-gen.sh build
cp build/bin/mlnix "$GEN_OUT/mlnix"
sha256sum /tmp/mlir-nix-curried-dispatch-v2-20261028.tar.gz "$GEN_OUT/mlnix" > "$GEN_OUT/source.txt"
python3 -u scripts/check-jit.py --mlnix "$GEN_OUT/mlnix" > "$GEN_OUT/check-jit.txt" 2>&1
cat "$GEN_OUT/check-jit.txt"
for w in nixos-toplevel nixpkgs-73; do
 args=(instantiate --readonly-mode --eval --strict test/nixos-toplevel.nix --arg nixpkgs ./.cache/nixpkgs)
 [ "$w" != nixpkgs-73 ] || args=(instantiate --readonly-mode --eval --strict --json test/nixpkgs-drvs.nix --argstr system x86_64-linux)
 env MLNIX_JIT=1 MLNIX_DEFER=1 MLNIX_STATS=1 MLNIX_JIT_PROFILE=1 MLNIX_STORE_ROOT=/tmp/mlnix-np-root MLNIX_STATE_DIR=/tmp/mlnix-np-state "$GEN_OUT/mlnix" "${args[@]}" > "$GEN_OUT/profile-jit-on-$w.out" 2> "$GEN_OUT/profile-jit-on-$w.txt"
 sha256sum "$GEN_OUT/profile-jit-on-$w.out" >> "$GEN_OUT/profile-hashes.txt"
 python3 - "$w" "$GEN_OUT/profile-jit-on-$w.out" <<'CHECK'
import hashlib,sys
expected={'nixos-toplevel':'2057239a9017fb18a37976ec6c96ad31ee36847cfa2107f146d4fac427f0cd86','nixpkgs-73':'5e8fff662dffa4eab642b75e78028fb54204cd15ec1a9972c2cafe2306234959'}[sys.argv[1]]
digest=hashlib.sha256(open(sys.argv[2],'rb').read()).hexdigest()
assert digest==expected,(sys.argv[1],digest)
CHECK
 grep -E '^jit:|^frame allocations:|^value allocations:' "$GEN_OUT/profile-jit-on-$w.txt"
done
python3 -u scripts/ab.py --mlnix "$baseline" --mlnix-b "$GEN_OUT/mlnix" --runs 5 'MLNIX_DEFER=1;MLNIX_JIT=1' 'MLNIX_DEFER=1;MLNIX_JIT=1' > "$GEN_OUT/ab-v1-v2-jit-on-demand.txt" 2>&1
cat "$GEN_OUT/ab-v1-v2-jit-on-demand.txt"
python3 -u scripts/ab.py --mlnix "$baseline" --mlnix-b "$GEN_OUT/mlnix" --runs 3 MLNIX_DEFER=1 MLNIX_DEFER=1 > "$GEN_OUT/ab-v1-v2-jit-off-demand.txt" 2>&1
cat "$GEN_OUT/ab-v1-v2-jit-off-demand.txt"
pmu_available=1
for w in nixos-toplevel nixpkgs-73; do
 [ "$pmu_available" = 1 ] || break
 args=(instantiate --readonly-mode --eval --strict test/nixos-toplevel.nix --arg nixpkgs ./.cache/nixpkgs)
 [ "$w" != nixpkgs-73 ] || args=(instantiate --readonly-mode --eval --strict --json test/nixpkgs-drvs.nix --argstr system x86_64-linux)
 for arm in v1 v2; do
  binary="$baseline"
  [ "$arm" != v2 ] || binary="$GEN_OUT/mlnix"
  env MLNIX_JIT=1 MLNIX_STORE_ROOT=/tmp/mlnix-np-root MLNIX_STATE_DIR=/tmp/mlnix-np-state python3 scripts/hw-counters.py -- env MLNIX_DEFER=1 "$binary" "${args[@]}" > "$GEN_OUT/pmu-$arm-jit-on-$w.json"
  if ! python3 - "$GEN_OUT/pmu-$arm-jit-on-$w.json" <<'CHECK'
import json,sys
r=json.load(open(sys.argv[1]))
if all('unavailable' in event for event in r['events'].values()):
 print('PMU unavailable; no further samples')
 sys.exit(1)
CHECK
  then pmu_available=0; break; fi
 done
done
{ date -u; uptime; free -m; } > "$GEN_OUT/metadata-end.txt"
printf '%s\n' 'complete; no Nix/Lix references or old broad suites executed' > "$GEN_OUT/complete.txt"
