#!/bin/bash
set -euo pipefail
exec 9>/tmp/kb/gen.lock
flock 9
cd "$HOME/work/mlir-nix-dense-selectors-20261028"
tar xzf /tmp/mlir-nix-dense-selectors-v2-20261028.tar.gz
export GEN_OUT=/tmp/kb/dense-selectors-v2-20261028
mkdir -p "$GEN_OUT"
unset MLNIX_JIT MLNIX_DEFER MLNIX_STATS MLNIX_PIPELINE MLNIX_PRIMS_IRDL MLNIX_JIT_THRESHOLD MLNIX_JIT_DUMP
v1=/tmp/kb/dense-selectors-20261028/mlnix
{ date -u; uptime; free -m; sha256sum /tmp/mlir-nix-dense-selectors-v2-20261028.tar.gz "$v1"; } > "$GEN_OUT/metadata-start.txt"
bash scripts/kali-gen.sh build
cp build/bin/mlnix "$GEN_OUT/mlnix"
sha256sum /tmp/mlir-nix-dense-selectors-v2-20261028.tar.gz build/bin/mlnix > "$GEN_OUT/source.txt"
python3 scripts/check-jit.py > "$GEN_OUT/check-jit.txt" 2>&1
cat "$GEN_OUT/check-jit.txt"
python3 scripts/ab.py --mlnix "$GEN_OUT/mlnix" --runs 5 MLNIX_DEFER=1 'MLNIX_DEFER=1;MLNIX_JIT=1' > "$GEN_OUT/ab-v2-off-on-demand.txt" 2>&1
cat "$GEN_OUT/ab-v2-off-on-demand.txt"
python3 scripts/ab.py --mlnix "$v1" --mlnix-b "$GEN_OUT/mlnix" --runs 3 'MLNIX_DEFER=1;MLNIX_JIT=1' 'MLNIX_DEFER=1;MLNIX_JIT=1' > "$GEN_OUT/ab-v1-on-v2-on-demand.txt" 2>&1
cat "$GEN_OUT/ab-v1-on-v2-on-demand.txt"
for w in nixos-toplevel nixpkgs-73; do
  args=(instantiate --readonly-mode --eval --strict test/nixos-toplevel.nix --arg nixpkgs ./.cache/nixpkgs)
  [ "$w" != nixpkgs-73 ] || args=(instantiate --readonly-mode --eval --strict --json test/nixpkgs-drvs.nix --argstr system x86_64-linux)
  for arm in v1 v2; do
    binary="$v1"
    [ "$arm" != v2 ] || binary="$GEN_OUT/mlnix"
    env MLNIX_JIT=1 MLNIX_STORE_ROOT=/tmp/mlnix-np-root MLNIX_STATE_DIR=/tmp/mlnix-np-state python3 scripts/hw-counters.py -- env MLNIX_DEFER=1 "$binary" "${args[@]}" > "$GEN_OUT/pmu-$arm-on-$w.json"
    python3 - "$GEN_OUT/pmu-$arm-on-$w.json" <<'PY'
import json,sys
r=json.load(open(sys.argv[1]))
if all('unavailable' in event for event in r['events'].values()):
 print('PMU unavailable; no further samples')
 sys.exit(1)
PY
  done
done
{ date -u; uptime; free -m; } > "$GEN_OUT/metadata-end.txt"
printf '%s\n' 'complete; no Nix/Lix execution or unchanged broad gates' > "$GEN_OUT/complete.txt"
