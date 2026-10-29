#!/bin/bash
set -euo pipefail
exec 9>/tmp/kb/gen.lock
flock 9
candidate="$HOME/work/mlir-nix-dense-selectors-20261028"
mkdir -p "$candidate"
cd "$candidate"
tar xzf /tmp/mlir-nix-dense-selectors-20261028.tar.gz
[ -e .cache ] || ln -s "$HOME/work/mlir-nix/.cache" .cache
export GEN_OUT=/tmp/kb/dense-selectors-20261028
mkdir -p "$GEN_OUT"
unset MLNIX_JIT MLNIX_DEFER MLNIX_STATS MLNIX_PIPELINE MLNIX_PRIMS_IRDL MLNIX_JIT_THRESHOLD MLNIX_JIT_DUMP
baseline=/tmp/kb/locality-20261028-final/mlnix
{
  date -u
  uptime
  free -m
  ps -eo pid,comm,pcpu,pmem --sort=-pcpu | head -10
  sha256sum /tmp/mlir-nix-dense-selectors-20261028.tar.gz "$baseline"
  clang++-22 --version
} > "$GEN_OUT/metadata-start.txt"
bash scripts/kali-gen.sh build
cp build/bin/mlnix "$GEN_OUT/mlnix"
cp build/bin/mlnix-opt "$GEN_OUT/mlnix-opt"
sha256sum /tmp/mlir-nix-dense-selectors-20261028.tar.gz build/bin/mlnix > "$GEN_OUT/source.txt"
python3 scripts/check-jit.py > "$GEN_OUT/check-jit.txt" 2>&1
cat "$GEN_OUT/check-jit.txt"
for mode in off on; do
  for schedule in eager demand; do
    mode_env=(-u MLNIX_JIT)
    [ "$mode" = on ] && mode_env=(MLNIX_JIT=1)
    schedule_env=(-u MLNIX_DEFER)
    [ "$schedule" = demand ] && schedule_env=(MLNIX_DEFER=1)
    env "${mode_env[@]}" env "${schedule_env[@]}" python3 scripts/run-lang-tests.py > "$GEN_OUT/lang-$mode-$schedule.txt" 2>&1
    printf '%s %s: ' "$mode" "$schedule"
    tail -1 "$GEN_OUT/lang-$mode-$schedule.txt"
  done
done
LLVM_BIN=/usr/lib/llvm-22/bin python3 scripts/run-mlir-tests.py > "$GEN_OUT/mlir-tests.txt" 2>&1
python3 scripts/check-prims.py > "$GEN_OUT/primops.txt" 2>&1
tail -1 "$GEN_OUT/mlir-tests.txt"
cat "$GEN_OUT/primops.txt"
printf '%s\n' 'All correctness gates passed; Nix/Lix were not invoked.' | tee "$GEN_OUT/gates.txt"
python3 scripts/ab.py --mlnix "$baseline" --mlnix-b "$GEN_OUT/mlnix" --runs 5 MLNIX_DEFER=1 MLNIX_DEFER=1 > "$GEN_OUT/ab-old-off-candidate-off-demand.txt" 2>&1
cat "$GEN_OUT/ab-old-off-candidate-off-demand.txt"
python3 scripts/ab.py --mlnix "$GEN_OUT/mlnix" --runs 5 MLNIX_DEFER=1 'MLNIX_DEFER=1;MLNIX_JIT=1' > "$GEN_OUT/ab-candidate-off-on-demand.txt" 2>&1
cat "$GEN_OUT/ab-candidate-off-on-demand.txt"
python3 scripts/ab.py --mlnix "$baseline" --mlnix-b "$GEN_OUT/mlnix" --runs 3 -- - - > "$GEN_OUT/ab-old-off-candidate-off-eager.txt" 2>&1
cat "$GEN_OUT/ab-old-off-candidate-off-eager.txt"
python3 scripts/ab.py --mlnix "$GEN_OUT/mlnix" --runs 3 -- - MLNIX_JIT=1 > "$GEN_OUT/ab-candidate-off-on-eager.txt" 2>&1
cat "$GEN_OUT/ab-candidate-off-on-eager.txt"
# Stable tools are represented by existing accepted records. --reuse-refs must
# not execute any reference binary; these intentionally invalid paths prove it.
MLNIX_JIT=1 python3 scripts/vs-nix.py --native --demand --reuse-refs --runs 3 --ref 'Nix 2.35.4=/no-reference-execution/nix' --ref 'Lix 2.91.3=/no-reference-execution/lix' > "$GEN_OUT/cached-references.txt" 2>&1
cat "$GEN_OUT/cached-references.txt"
for w in nixos-toplevel nixpkgs-73; do
  args=(instantiate --readonly-mode --eval --strict test/nixos-toplevel.nix --arg nixpkgs ./.cache/nixpkgs)
  [ "$w" != nixpkgs-73 ] || args=(instantiate --readonly-mode --eval --strict --json test/nixpkgs-drvs.nix --argstr system x86_64-linux)
  env MLNIX_JIT=1 MLNIX_DEFER=1 MLNIX_STATS=1 MLNIX_STORE_ROOT=/tmp/mlnix-np-root MLNIX_STATE_DIR=/tmp/mlnix-np-state "$GEN_OUT/mlnix" "${args[@]}" > /dev/null 2> "$GEN_OUT/stats-$w.txt"
  grep -E '^jit:|^== attr|^== binding|^== value' "$GEN_OUT/stats-$w.txt" || true
  for mode in off on; do
    mode_env=(-u MLNIX_JIT)
    [ "$mode" = on ] && mode_env=(MLNIX_JIT=1)
    env "${mode_env[@]}" MLNIX_STORE_ROOT=/tmp/mlnix-np-root MLNIX_STATE_DIR=/tmp/mlnix-np-state python3 scripts/hw-counters.py -- env MLNIX_DEFER=1 "$GEN_OUT/mlnix" "${args[@]}" > "$GEN_OUT/pmu-$mode-$w.json"
  done
done
{ date -u; uptime; free -m; ps -eo pid,comm,pcpu,pmem --sort=-pcpu | head -10; } > "$GEN_OUT/metadata-end.txt"
printf '%s\n' 'complete' > "$GEN_OUT/complete.txt"
