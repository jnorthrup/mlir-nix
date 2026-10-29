#!/bin/bash
set -euo pipefail
exec 9>/tmp/kb/gen.lock
flock 9
cd "$HOME/work/mlir-nix-dense-selectors-20261028"
out=/tmp/kb/dense-selectors-20261028
unset MLNIX_JIT MLNIX_STATS MLNIX_DEFER
for w in nixos-toplevel nixpkgs-73; do
  args=(instantiate --readonly-mode --eval --strict test/nixos-toplevel.nix --arg nixpkgs ./.cache/nixpkgs)
  [ "$w" != nixpkgs-73 ] || args=(instantiate --readonly-mode --eval --strict --json test/nixpkgs-drvs.nix --argstr system x86_64-linux)
  for arm in original candidate; do
    binary=/tmp/kb/locality-20261028-final/mlnix
    [ "$arm" != candidate ] || binary="$out/mlnix"
    env MLNIX_STORE_ROOT=/tmp/mlnix-np-root MLNIX_STATE_DIR=/tmp/mlnix-np-state python3 scripts/hw-counters.py -- env MLNIX_DEFER=1 "$binary" "${args[@]}" > "$out/pmu-dense-$arm-$w.json"
    # If access is unavailable, retain the diagnostic once and stop this pair.
    python3 - "$out/pmu-dense-$arm-$w.json" <<'PY'
import json,sys
r=json.load(open(sys.argv[1]))
if all('unavailable' in event for event in r['events'].values()):
 print('PMU unavailable; no further samples')
 sys.exit(1)
PY
  done
done
