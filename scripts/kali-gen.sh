#!/bin/bash
# One generation on the Linux benchmark host: build it, gate it, measure it against Nix and Lix.
#
#   bash scripts/kali-gen.sh [stage ...]       stages: build gates bench prof (default: build gates bench)
#
# Run from the checkout of the generation (a launcher there takes the lock and checks the commit
# out).  Environment:
#   GEN_OUT   directory for logs and results             (default /tmp/gen-out)
#   NIX_BIN   reference nix-instantiate, the oracle      (required for gates, bench)
#   LIX_BIN   second reference nix-instantiate           (optional)
#   BENCH_OVER  fraction past a pinned record at which an mlnix run is stopped (default 0.2; raise it when the host drifts)
#
# Each benchmark job stays under 180 s of wall time; results land in $GEN_OUT/summary.txt.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
OUT=${GEN_OUT:-/tmp/gen-out}
mkdir -p "$OUT"
stages=${*:-build gates bench}
LLVM_PREFIX=${LLVM_PREFIX:-/usr/lib/llvm-22}
say() { echo "$(date +%T) $*" | tee -a "$OUT/summary.txt"; }
refs=(--ref "Nix 2.35.4=${NIX_BIN:-}")
[ -n "${LIX_BIN:-}" ] && refs+=(--ref "Lix 2.91.3=$LIX_BIN")
[ -e .cache ] || ln -s "$HOME/work/mlir-nix/.cache" .cache

# BUILD_DIR and CMAKE_EXTRA (for instance BUILD_DIR=build23 CMAKE_EXTRA=-DCMAKE_CXX_STANDARD=23) build another configuration
# beside the default one; the gates and the benchmarks still run the binaries of ./build.
stage_build() {
  local b=${BUILD_DIR:-build}
  if [ ! -f $b/build.ninja ]; then
    cmake -S . -B $b -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=clang-22 -DCMAKE_CXX_COMPILER=clang++-22 \
      -DLLVM_DIR=$LLVM_PREFIX/lib/cmake/llvm -DMLIR_DIR=$LLVM_PREFIX/lib/cmake/mlir ${CMAKE_EXTRA:-} > "$OUT/configure.log" 2>&1 \
      || { say "configure failed"; tail -20 "$OUT/configure.log"; return 1; }
  fi
  cmake --build $b --target mlnix mlnix-opt -j8 ${BUILD_KEEP_GOING:+-- -k 0} > "$OUT/build.log" 2>&1
  local rc=$?
  say "build rc=$rc, error lines: $(grep -c 'error:' "$OUT/build.log")"
  [ $rc -eq 0 ] || { grep -m10 'error:' "$OUT/build.log" | cut -c1-260; return 1; }
}

# Keep each complete log and propagate the producer's status: a successful grep or
# summary line must never turn a failed correctness gate into a benchmark result.
check_refs() {
  [ -n "${NIX_BIN:-}" ] && [ -x "$NIX_BIN" ] || { say "NIX_BIN must name an executable reference"; return 1; }
  [ -z "${LIX_BIN:-}" ] || [ -x "$LIX_BIN" ] || { say "LIX_BIN must name an executable reference"; return 1; }
}

stage_gates() {
  check_refs || return 1
  local sched rc failed=0
  for sched in eager demand; do
    local schedule_env=(-u MLNIX_DEFER)
    [ "$sched" = demand ] && schedule_env=(MLNIX_DEFER=1)
    env "${schedule_env[@]}" python3 scripts/run-lang-tests.py > "$OUT/lang-$sched.txt" 2>&1
    rc=$?
    say "lang $sched (rc=$rc): $(grep -E '^TOTAL' "$OUT/lang-$sched.txt")"
    [ $rc -eq 0 ] || failed=1
  done
  LLVM_BIN=$LLVM_PREFIX/bin python3 scripts/run-mlir-tests.py > "$OUT/mlir-tests.txt" 2>&1
  rc=$?
  say "mlir tests (rc=$rc): $(tail -1 "$OUT/mlir-tests.txt")"
  [ $rc -eq 0 ] || failed=1
  python3 scripts/check-prims.py > "$OUT/primops.txt" 2>&1
  rc=$?
  say "primops (rc=$rc): $(tail -1 "$OUT/primops.txt")"
  [ $rc -eq 0 ] || failed=1
  for sched in eager demand; do
    local schedule_env=(-u MLNIX_DEFER)
    [ "$sched" = demand ] && schedule_env=(MLNIX_DEFER=1)
    env "${schedule_env[@]}" python3 scripts/difftest.py --native "${refs[@]}" > "$OUT/difftest-$sched.txt" 2>&1
    rc=$?
    say "difftest $sched (rc=$rc): $(grep -E '^[0-9]+/[0-9]+ identical' "$OUT/difftest-$sched.txt" | tr '\n' ';')"
    [ $rc -eq 0 ] || failed=1
  done
  return $failed
}

stage_bench() {
  check_refs || return 1
  local w rc failed=0
  for w in nixos-toplevel nixpkgs-73; do
    say "bench $w"
    # Reuse accepted same-host Nix/Lix timings without invoking those binaries. Missing records fail the comparison.
    # An mlnix run past 1.2x a pinned record is stopped, its state kept
    # on disk: a core is the size of the run (3 GB), and /tmp is RAM on kali, where two of them slowed the rounds after them
    timeout 180 python3 scripts/vs-nix.py --native --demand --budget 165 --reuse-refs --auto-pin --cap --over "${BENCH_OVER:-0.2}" --diag "$HOME/kb-diag/$(basename "$OUT")" \
      --workload $w "${refs[@]}" \
      > "$OUT/$w.txt" 2>&1
    rc=$?
    say "$w rc=$rc"
    [ $rc -eq 0 ] || failed=1
  done
  return $failed
}

stage_prof() {
  cc -O1 -g -shared -fPIC -o "$OUT/libsigprof.so" scripts/linux-prof/sigprof.c -ldl -lpthread -lrt || { say "sigprof did not compile"; return 1; }
  local i
  for i in 1 2 3; do
    env SIGPROF_OUT="$OUT/toplevel-$i.prof" LD_PRELOAD="$OUT/libsigprof.so" ${PROF_ENV:-} MLNIX_DEFER=1 \
      MLNIX_STORE_ROOT=/tmp/mlnix-np-root MLNIX_STATE_DIR=/tmp/mlnix-np-state \
      build/bin/mlnix instantiate --readonly-mode --eval --strict test/nixos-toplevel.nix --arg nixpkgs ./.cache/nixpkgs > /dev/null 2>&1
  done
  python3 scripts/linux-prof/report.py "$OUT"/toplevel-?.prof --top 40 > "$OUT/profile.txt" 2>&1
  say "profile: $(head -1 "$OUT/profile.txt")"
}

for s in $stages; do
  "stage_$s" || { say "stage $s failed"; exit 1; }
done
say "done"
