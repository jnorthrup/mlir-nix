#!/bin/bash
# The proofs of the store's index (lowered/nixstore/StoreIndex.mlir), built against the objects of a build:
#   os      the system's words (StoreIndexDarwin.mlir.in, StoreIndexLinux.mlir) against the system's headers
#   pages   the sealed pages against a reference: every page byte for byte, read back, searched, damaged
#   index   the index against the directory it is derived from: entries written behind its back, the file damaged, cut
#           and removed, writers killed, processes at once; again where the directory's time cannot be set and where
#           there are no locks; and the index file removed under a process that holds it
#   store   every `mlnix store` command, an older mlnix against this build's, when OLD is given (store-index-diff.py)
# usage: scripts/store-index-check.sh WORK [SEEDS] [OLD_MLNIX]     (BUILD=<build dir>, default build; WORK: a new directory)
# One line a proof; the status is 0 when none failed.  WORK is left as it is.
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
[ $# -ge 1 ] || { sed -n 2,10p "$0"; exit 2; }
N=${2:-10}; OLD=${3:-}
B=${BUILD:-$R/build}; B=$(cd "$B" && pwd); L=$B/lib/lowered
mkdir -p "$1/os" "$1/stores"; W=$(cd "$1" && pwd)
CC=${CC:-cc}; [ "$(uname)" = Darwin ] && [ "$CC" = cc ] && CC="xcrun clang" # the system's compiler with the system's headers
O="$L/StoreIndex.o $L/StoreIndexOs.o $L/StoreGraph.o $L/HashParse.o $L/Decoders.o $L/PathOps.o $L/HashEq.o"
$CC -O2 -o "$W/os-check" "$R/scripts/store-index-os.c" "$L/StoreIndexOs.o" || exit 2
$CC -O2 -o "$W/pages" "$R/scripts/store-index-pages.c" $O || exit 2
$CC -O2 -g -o "$W/check" "$R/scripts/store-index-check.c" $O || exit 2
$CC -O2 -g -DNO_STAMP -o "$W/check-nostamp" "$R/scripts/store-index-check.c" $O || exit 2
$CC -O2 -g -DNO_LOCK -o "$W/check-nolock" "$R/scripts/store-index-check.c" $O || exit 2
bad=0
"$W/os-check" "$W/os" > "$W/os.log" 2>&1 || bad=1
echo "os:     $(tail -1 "$W/os.log")"
: > "$W/pages.log"
for s in $(seq 1 "$N"); do "$W/pages" "$s" 20000 >> "$W/pages.log" 2>&1 || bad=1; done
echo "pages:  $(grep -c ' 0 failures' "$W/pages.log") of $N seeds without a failure, $((N * 20000)) row sets"
runs() { # name binary seeds: the index check over the seeds, a line each in name.log
  : > "$W/$1.log"
  for s in $(seq 1 "$3"); do
    SIDX_TMP="$W/stores" "$W/$2" run "$s" 10 120 > "$W/one.log" 2>&1; rc=$?
    tail -8 "$W/one.log" >> "$W/$1.log"
    [ $rc -eq 0 ] || { bad=1; echo "seed $s: exit status $rc" >> "$W/$1.log"; }
  done
  echo "$1: $(grep -c '; 0 failures' "$W/$1.log") of $3 seeds without a failure, $(grep -c -E 'FAIL|FAULT|LEAK|exit status' "$W/$1.log") lines of trouble"
}
runs index check "$N"
runs index-nostamp check-nostamp $((N / 4 + 1))
runs index-nolock check-nolock $((N / 4 + 1))
SIDX_TMP="$W/stores" "$W/check" orphan > "$W/orphan.log" 2>&1 || bad=1
tail -1 "$W/orphan.log"
if [ -n "$OLD" ]; then
  python3 "$R/scripts/store-index-diff.py" "$OLD" "$B/bin/mlnix" "$W/diff" --seeds $((N / 5 + 1)) > "$W/store.log" 2>&1 || bad=1
  echo "store:  $(tail -1 "$W/store.log")"
fi
exit $bad
