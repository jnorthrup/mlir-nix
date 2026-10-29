#!/bin/bash
set -euo pipefail
# Prepared only: execute after root supplies the final frozen archive, SHA and gate count.
archive=${1:?supply the final frozen archive path}
archive_sha=${2:?supply the root-provided SHA256}
expected_jit_checks=${3:?supply the final focused gate count}
[[ "$archive_sha" =~ ^[0-9a-f]{64}$ ]] || exit 2
[[ "$expected_jit_checks" =~ ^[1-9][0-9]*$ ]] || exit 2
archive=$(realpath "$archive")
baseline=/tmp/kb/values-20261028-v1/mlnix
export GEN_OUT=/tmp/kb/list-returns-20261028-v1
# Never overwrite a preserved candidate or its raw evidence.
[ ! -e "$GEN_OUT" ] || { echo "Candidate path already exists: $GEN_OUT" >&2; exit 2; }
exec 9>/tmp/kb/gen.lock
flock -n 9
cd "$HOME/work/mlir-nix-dense-selectors-20261028"
python3 - "$archive" "$archive_sha" "$baseline" <<'HASH'
from pathlib import Path
import hashlib,sys
for path,expected in ((sys.argv[1],sys.argv[2]),(sys.argv[3],'dff41c359c62bbc2108cd75643c829a00c40e8949a59f31aafb17940ee8812e4')):
 actual=hashlib.sha256(Path(path).read_bytes()).hexdigest()
 assert actual==expected,(path,actual,expected)
 print('verified',path,actual)
HASH
mkdir "$GEN_OUT"
cp "$0" "$GEN_OUT/commands-v1.sh"
printf 'archive=%s\narchive_sha256=%s\nexpected_focused_checks=%s\nbaseline=%s\n' "$archive" "$archive_sha" "$expected_jit_checks" "$baseline" > "$GEN_OUT/launch-parameters.txt"
unset MLNIX_JIT MLNIX_JIT_INLINE MLNIX_JIT_CURRIED MLNIX_JIT_PROJECTION MLNIX_JIT_VALUES MLNIX_JIT_LISTS MLNIX_DEFER MLNIX_STATS MLNIX_PIPELINE MLNIX_PRIMS_IRDL MLNIX_JIT_THRESHOLD MLNIX_JIT_DUMP MLNIX_JIT_PROFILE
snapshot() {
 python3 - "$GEN_OUT/host-$1.txt" <<'HOST'
from pathlib import Path
import subprocess,sys,datetime
out=[datetime.datetime.now(datetime.timezone.utc).isoformat(), 'loadavg '+Path('/proc/loadavg').read_text().strip()]
out.append(subprocess.run(['free','-m'],text=True,capture_output=True,check=True).stdout.strip())
lines=subprocess.run(['ps','-eo','pid,ppid,comm,etime,pcpu,pmem'],capture_output=True,text=True,check=True).stdout.splitlines()
selected=[line for line in lines[1:] if len(line.split())>2 and line.split()[2] in ('java','mlnix','mlnix-opt','ninja','cmake','clang-22','clang++-22','cc1plus')]
out.extend(['Relevant processes; CPU is lifetime average, not an instantaneous utilization sample:',lines[0], '\n'.join(selected) if selected else 'No java/mlnix/build processes present'])
Path(sys.argv[1]).write_text('\n'.join(out)+'\n')
HOST
}
snapshot 00-before-build
sha256sum "$archive" "$baseline" > "$GEN_OUT/baseline-source.txt"
tar xzf "$archive"
python3 - "$GEN_OUT" "$archive" <<'VERIFY'
from pathlib import Path
import hashlib,sys,tarfile
root=Path.cwd();out=Path(sys.argv[1]);rows=[]
with tarfile.open(sys.argv[2]) as tar:
 for item in tar.getmembers():
  if not item.isfile(): continue
  actual=(root/item.name).read_bytes()
  assert actual==tar.extractfile(item).read(),item.name
  rows.append((item.name,hashlib.sha256(actual).hexdigest()))
(out/'verified-archive-files.sha256').write_text(''.join(f'{h}  {name}\n' for name,h in sorted(rows)))
(out/'cache-invalidation.txt').write_text(f'All {len(rows)} archived regular files match the extracted checkout byte for byte.\nThe entire isolated build directory is cleaned before compilation to prevent preserved archive mtimes from reusing stale objects.\nSource bytes and preserved Values V1 baseline are not changed.\n')
print(f'verified {len(rows)} archived files; cleaning isolated build tree')
VERIFY
cmake --build build --target clean > "$GEN_OUT/clean.log" 2>&1
bash scripts/kali-gen.sh build
cp build/bin/mlnix "$GEN_OUT/mlnix"
sha256sum "$archive" "$GEN_OUT/mlnix" test/nixos-toplevel.nix test/nixpkgs-drvs.nix > "$GEN_OUT/source.txt"
python3 -u scripts/check-jit.py --mlnix "$GEN_OUT/mlnix" > "$GEN_OUT/check-jit.txt" 2>&1
cat "$GEN_OUT/check-jit.txt"
python3 - "$GEN_OUT/check-jit.txt" "$expected_jit_checks" <<'GATE'
from pathlib import Path
import sys
assert f'JIT: {int(sys.argv[2])} exact comparisons passed' in Path(sys.argv[1]).read_text()
GATE
snapshot 01-before-profiles
for w in nixos-toplevel nixpkgs-73; do
 args=(instantiate --readonly-mode --eval --strict test/nixos-toplevel.nix --arg nixpkgs ./.cache/nixpkgs)
 [ "$w" != nixpkgs-73 ] || args=(instantiate --readonly-mode --eval --strict --json test/nixpkgs-drvs.nix --argstr system x86_64-linux)
 for arm in jit-off lists-off lists-on; do
  arm_env=()
  [ "$arm" = jit-off ] || arm_env+=(MLNIX_JIT=1)
  [ "$arm" != lists-off ] || arm_env+=(MLNIX_JIT_LISTS=0)
  env "${arm_env[@]}" MLNIX_DEFER=1 MLNIX_STATS=1 MLNIX_JIT_PROFILE=1 MLNIX_STORE_ROOT=/tmp/mlnix-np-root MLNIX_STATE_DIR=/tmp/mlnix-np-state "$GEN_OUT/mlnix" "${args[@]}" > "$GEN_OUT/profile-$arm-$w.out" 2> "$GEN_OUT/profile-$arm-$w.txt"
  sha256sum "$GEN_OUT/profile-$arm-$w.out" >> "$GEN_OUT/profile-hashes.txt"
  python3 - "$w" "$GEN_OUT/profile-$arm-$w.out" <<'CHECK'
import hashlib,sys
expected={'nixos-toplevel':'2057239a9017fb18a37976ec6c96ad31ee36847cfa2107f146d4fac427f0cd86','nixpkgs-73':'5e8fff662dffa4eab642b75e78028fb54204cd15ec1a9972c2cafe2306234959'}[sys.argv[1]]
digest=hashlib.sha256(open(sys.argv[2],'rb').read()).hexdigest()
assert digest==expected,(sys.argv[1],digest)
print('accepted profile',sys.argv[2],digest)
CHECK
 done
done
snapshot 02-before-lists-ablation
python3 -u scripts/ab.py --mlnix "$GEN_OUT/mlnix" --runs 5 'MLNIX_DEFER=1;MLNIX_JIT=1;MLNIX_JIT_LISTS=0' 'MLNIX_DEFER=1;MLNIX_JIT=1' > "$GEN_OUT/ab-lists-off-on-demand.txt" 2>&1
cat "$GEN_OUT/ab-lists-off-on-demand.txt"
snapshot 03-before-whole-jit-ablation
python3 -u scripts/ab.py --mlnix "$GEN_OUT/mlnix" --runs 5 MLNIX_DEFER=1 'MLNIX_DEFER=1;MLNIX_JIT=1' > "$GEN_OUT/ab-jit-off-on-demand.txt" 2>&1
cat "$GEN_OUT/ab-jit-off-on-demand.txt"
snapshot 04-before-values-v1-on-control
python3 -u scripts/ab.py --mlnix "$baseline" --mlnix-b "$GEN_OUT/mlnix" --runs 3 'MLNIX_DEFER=1;MLNIX_JIT=1' 'MLNIX_DEFER=1;MLNIX_JIT=1' > "$GEN_OUT/ab-values-v1-candidate-jit-on-demand.txt" 2>&1
cat "$GEN_OUT/ab-values-v1-candidate-jit-on-demand.txt"
snapshot 05-before-values-v1-off-control
python3 -u scripts/ab.py --mlnix "$baseline" --mlnix-b "$GEN_OUT/mlnix" --runs 3 MLNIX_DEFER=1 MLNIX_DEFER=1 > "$GEN_OUT/ab-values-v1-candidate-jit-off-demand.txt" 2>&1
cat "$GEN_OUT/ab-values-v1-candidate-jit-off-demand.txt"
snapshot 06-before-pmu
pmu_available=1
for w in nixos-toplevel nixpkgs-73; do
 [ "$pmu_available" = 1 ] || break
 args=(instantiate --readonly-mode --eval --strict test/nixos-toplevel.nix --arg nixpkgs ./.cache/nixpkgs)
 [ "$w" != nixpkgs-73 ] || args=(instantiate --readonly-mode --eval --strict --json test/nixpkgs-drvs.nix --argstr system x86_64-linux)
 for mode in off on; do
  mode_env=(-u MLNIX_JIT_LISTS)
  [ "$mode" != off ] || mode_env=(MLNIX_JIT_LISTS=0)
  env "${mode_env[@]}" MLNIX_JIT=1 MLNIX_STORE_ROOT=/tmp/mlnix-np-root MLNIX_STATE_DIR=/tmp/mlnix-np-state python3 scripts/hw-counters.py -- env MLNIX_DEFER=1 "$GEN_OUT/mlnix" "${args[@]}" > "$GEN_OUT/pmu-lists-$mode-$w.json"
  if ! python3 - "$GEN_OUT/pmu-lists-$mode-$w.json" <<'CHECK'
import json,sys
r=json.load(open(sys.argv[1]))
if all('unavailable' in event for event in r['events'].values()):
 print('PMU unavailable; no further samples')
 sys.exit(1)
CHECK
  then pmu_available=0; break; fi
 done
done
snapshot 07-complete
printf '%s\n' 'complete; no Nix/Lix references or old broad suites executed' > "$GEN_OUT/complete.txt"
