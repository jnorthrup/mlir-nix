#!/bin/bash
# The optimizer ladder (docs/OPTIMIZER-LADDER.md): the loop heap against the transform heap, one compiler flag set at a time.
#
#   bash scripts/optimizer-ladder.sh OLD-INCLUDE-DIR      run from the repository root, on the benchmark host
#
# OLD-INCLUDE-DIR holds the loop version of include/Composite (git show <old>:include/Composite/{MinMaxHeap,Series,Pack}.h into
# <dir>/Composite/).  Each row builds scripts/inode-bench.cc both ways, runs each 5 times interleaved and prints the minimum
# cluster time.  Every row is one boot; hold the benchmark lock (/tmp/kb/gen.lock on kali) while it runs.
set -u
OLD=${1:?usage: optimizer-ladder.sh OLD-INCLUDE-DIR}
B=scripts/inode-bench.cc; O=${LADDER_OUT:-/tmp/ladder}; mkdir -p "$O"
row() { # compiler label flags...
  local cxx=$1 label=$2; shift 2
  local n; n=$(echo "$cxx $label" | tr -c 'A-Za-z0-9\n' '_')
  $cxx -std=c++20 "$@" -I "$OLD" $B -o "$O/old_$n" 2> "$O/eo_$n" || { echo "$label: loop version did not compile"; return; }
  $cxx -std=c++20 "$@" -I include $B -o "$O/new_$n" 2> "$O/en_$n" || { echo "$label: transform version did not compile"; return; }
  for r in 1 2 3 4 5; do for v in old new; do printf '%s ' $v; "$O/${v}_$n" 6 2>&1 | grep -E 'cluster +min'; done; done |
    awk -v n="$cxx $label" '{v=$1; if(!(v in m)||$4<m[v])m[v]=$4} END{printf "%-46s loops %.3f  transforms %.3f  (%+.1f%%)\n", n, m["old"], m["new"], 100*(m["new"]-m["old"])/m["old"]}'
}
for cxx in ${CLANG:-clang++-22}; do
  row $cxx "-O2" -O2
  row $cxx "-O3" -O3
  row $cxx "-O3 -flto=thin" -O3 -flto=thin
  row $cxx "-O3 -flto" -O3 -flto
  row $cxx "-O3 -flto -funroll-loops" -O3 -flto -funroll-loops
  row $cxx "-O3 -flto -inline-threshold=2000" -O3 -flto -mllvm -inline-threshold=2000
done
for cxx in ${GCC:-g++-16}; do
  row $cxx "-O2" -O2
  row $cxx "-O2 -fexpensive-optimizations" -O2 -fexpensive-optimizations
  row $cxx "-O3" -O3
  row $cxx "-O3 -fexpensive-optimizations" -O3 -fexpensive-optimizations
  row $cxx "-O3 -fexpensive-optimizations -funroll-loops -fpeel-loops" -O3 -fexpensive-optimizations -funroll-loops -fpeel-loops
  row $cxx "-O3 -fexpensive-optimizations -fipa-pta -fgcse-*" -O3 -fexpensive-optimizations -fipa-pta -fgcse-after-reload -fgcse-sm -fgcse-las
  row $cxx "-O3 -fexpensive-optimizations -march=native" -O3 -fexpensive-optimizations -march=native
  row $cxx "-O3 -fexpensive-optimizations -flto" -O3 -fexpensive-optimizations -flto
  row $cxx "-O3 (all of the above) -flto -march=native" -O3 -fexpensive-optimizations -funroll-loops -fpeel-loops -fipa-pta -fgcse-after-reload -march=native -flto
done
