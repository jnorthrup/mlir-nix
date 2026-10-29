#!/bin/bash
# The algebra is pure.  Every header of include/Composite (the dialect glue TrikeShed.h excepted) includes no standard header, names nothing
# from std:: in code, and compiles alone with no standard include path at all; the hot set (Hot.h: Core.h, Pack.h, Series.h) is also held to
# a line budget, because what every file pays for stays small.
#   bash scripts/hot-check.sh        CXX=<compiler>   BUDGET=<lines> (default 600)
set -euo pipefail
cd "$(dirname "$0")/.."
CXX=${CXX:-clang++}
HOT="include/Composite/Core.h include/Composite/Pack.h include/Composite/Series.h"
ALL=$(ls include/Composite/*.h | grep -v 'TrikeShed\.h$')
for f in $ALL; do
  if grep -n '^[[:space:]]*#[[:space:]]*include[[:space:]]*<' "$f"; then echo "FAIL: $f includes a standard header"; exit 1; fi
  if sed 's://.*$::' "$f" | grep -nE '(^|[^A-Za-z_])std::' | sed "s|^|$f:|"; then echo "FAIL: $f names std:: in code"; exit 1; fi
  $CXX -std=gnu++20 -fsyntax-only -nostdinc -nostdinc++ -ffreestanding -Iinclude -x c++ "$f"
done
lines=$(cat $HOT | wc -l)
budget=${BUDGET:-600}
if [ "$lines" -gt "$budget" ]; then echo "FAIL: the hot set is $lines lines, over its budget of $budget"; exit 1; fi
echo "algebra: $(echo $ALL | wc -w) headers pure, each compiles alone with no standard headers; hot set $lines lines of $budget"
