#!/bin/bash
set -euo pipefail
exec 9>/tmp/kb/gen.lock
flock -n 9
cd "$HOME/work/mlir-nix-dense-selectors-20261028"
sha256sum /tmp/mlir-nix-projection-v1-20261028.tar.gz | grep -q '^7b3187487ba5658fc24cbc1ed8e7ed73bed30f5da3b0af401f8948f57a9663db '
tar xzf /tmp/mlir-nix-projection-v1-20261028.tar.gz
export GEN_OUT=/tmp/kb/projection-20261028-v1
mkdir -p "$GEN_OUT"
unset MLNIX_JIT MLNIX_JIT_INLINE MLNIX_JIT_CURRIED MLNIX_JIT_PROJECTION MLNIX_DEFER MLNIX_STATS MLNIX_PIPELINE MLNIX_PRIMS_IRDL MLNIX_JIT_THRESHOLD MLNIX_JIT_DUMP MLNIX_JIT_PROFILE
baseline=/tmp/kb/curried-20261028-dispatch-v2/mlnix
{ date -u; uptime; free -m; sha256sum /tmp/mlir-nix-projection-v1-20261028.tar.gz "$baseline"; } > "$GEN_OUT/metadata-start.txt"
python3 - "$GEN_OUT" <<'VERIFY'
from pathlib import Path
import hashlib,sys,tarfile
root=Path.cwd()
out=Path(sys.argv[1])
rows=[]
with tarfile.open('/tmp/mlir-nix-projection-v1-20261028.tar.gz') as tar:
 for item in tar.getmembers():
  if not item.isfile(): continue
  archived=tar.extractfile(item).read()
  actual=(root/item.name).read_bytes()
  assert actual==archived,item.name
  rows.append((item.name,hashlib.sha256(actual).hexdigest()))
(out/'verified-archive-files.sha256').write_text(''.join(f'{h}  {name}\n' for name,h in sorted(rows)))
(out/'cache-invalidation.txt').write_text(f'All {len(rows)} archived regular files match the extracted checkout byte for byte.\nInitial incremental link failed because Eval.cpp.o lacked selectField despite the frozen source definition; preserved archive mtimes predated that object.\nThe isolated build directory is cleaned in full before retry, without modifying source bytes or preserved baseline binaries.\n')
print(f'verified {len(rows)} archived files; cleaning isolated build tree')
VERIFY
cmake --build build --target clean > "$GEN_OUT/clean.log" 2>&1
bash scripts/kali-gen.sh build
cp build/bin/mlnix "$GEN_OUT/mlnix"
sha256sum /tmp/mlir-nix-projection-v1-20261028.tar.gz "$GEN_OUT/mlnix" test/nixos-toplevel.nix test/nixpkgs-drvs.nix > "$GEN_OUT/source.txt"
python3 -u scripts/check-jit.py --mlnix "$GEN_OUT/mlnix" > "$GEN_OUT/check-jit.txt" 2>&1
cat "$GEN_OUT/check-jit.txt"
for w in nixos-toplevel nixpkgs-73; do
 args=(instantiate --readonly-mode --eval --strict test/nixos-toplevel.nix --arg nixpkgs ./.cache/nixpkgs)
 [ "$w" != nixpkgs-73 ] || args=(instantiate --readonly-mode --eval --strict --json test/nixpkgs-drvs.nix --argstr system x86_64-linux)
 for mode in off on; do
  mode_env=()
  [ "$mode" != off ] || mode_env+=(MLNIX_JIT_PROJECTION=0)
  env "${mode_env[@]}" MLNIX_JIT=1 MLNIX_DEFER=1 MLNIX_STATS=1 MLNIX_JIT_PROFILE=1 MLNIX_STORE_ROOT=/tmp/mlnix-np-root MLNIX_STATE_DIR=/tmp/mlnix-np-state "$GEN_OUT/mlnix" "${args[@]}" > "$GEN_OUT/profile-projection-$mode-$w.out" 2> "$GEN_OUT/profile-projection-$mode-$w.txt"
  sha256sum "$GEN_OUT/profile-projection-$mode-$w.out" >> "$GEN_OUT/profile-hashes.txt"
  python3 - "$w" "$GEN_OUT/profile-projection-$mode-$w.out" <<'CHECK'
import hashlib,sys
expected={'nixos-toplevel':'2057239a9017fb18a37976ec6c96ad31ee36847cfa2107f146d4fac427f0cd86','nixpkgs-73':'5e8fff662dffa4eab642b75e78028fb54204cd15ec1a9972c2cafe2306234959'}[sys.argv[1]]
digest=hashlib.sha256(open(sys.argv[2],'rb').read()).hexdigest()
assert digest==expected,(sys.argv[1],digest)
CHECK
  grep -E '^jit:|^frame allocations:|^value allocations:' "$GEN_OUT/profile-projection-$mode-$w.txt"
 done
done
python3 -u scripts/ab.py --mlnix "$GEN_OUT/mlnix" --runs 5 'MLNIX_DEFER=1;MLNIX_JIT=1;MLNIX_JIT_PROJECTION=0' 'MLNIX_DEFER=1;MLNIX_JIT=1' > "$GEN_OUT/ab-projection-off-on-demand.txt" 2>&1
cat "$GEN_OUT/ab-projection-off-on-demand.txt"
python3 -u scripts/ab.py --mlnix "$GEN_OUT/mlnix" --runs 5 MLNIX_DEFER=1 'MLNIX_DEFER=1;MLNIX_JIT=1' > "$GEN_OUT/ab-jit-off-on-demand.txt" 2>&1
cat "$GEN_OUT/ab-jit-off-on-demand.txt"
python3 -u scripts/ab.py --mlnix "$baseline" --mlnix-b "$GEN_OUT/mlnix" --runs 3 'MLNIX_DEFER=1;MLNIX_JIT=1' 'MLNIX_DEFER=1;MLNIX_JIT=1' > "$GEN_OUT/ab-dispatch-v2-candidate-jit-on-demand.txt" 2>&1
cat "$GEN_OUT/ab-dispatch-v2-candidate-jit-on-demand.txt"
python3 -u scripts/ab.py --mlnix "$baseline" --mlnix-b "$GEN_OUT/mlnix" --runs 3 MLNIX_DEFER=1 MLNIX_DEFER=1 > "$GEN_OUT/ab-dispatch-v2-candidate-jit-off-demand.txt" 2>&1
cat "$GEN_OUT/ab-dispatch-v2-candidate-jit-off-demand.txt"
pmu_available=1
for w in nixos-toplevel nixpkgs-73; do
 [ "$pmu_available" = 1 ] || break
 args=(instantiate --readonly-mode --eval --strict test/nixos-toplevel.nix --arg nixpkgs ./.cache/nixpkgs)
 [ "$w" != nixpkgs-73 ] || args=(instantiate --readonly-mode --eval --strict --json test/nixpkgs-drvs.nix --argstr system x86_64-linux)
 for mode in off on; do
  mode_env=(-u MLNIX_JIT_PROJECTION)
  [ "$mode" != off ] || mode_env=(MLNIX_JIT_PROJECTION=0)
  env "${mode_env[@]}" MLNIX_JIT=1 MLNIX_STORE_ROOT=/tmp/mlnix-np-root MLNIX_STATE_DIR=/tmp/mlnix-np-state python3 scripts/hw-counters.py -- env MLNIX_DEFER=1 "$GEN_OUT/mlnix" "${args[@]}" > "$GEN_OUT/pmu-projection-$mode-$w.json"
  if ! python3 - "$GEN_OUT/pmu-projection-$mode-$w.json" <<'CHECK'
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
