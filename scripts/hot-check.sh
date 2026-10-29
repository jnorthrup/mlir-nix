#!/bin/bash
# The hot set (include/Composite/Hot.h) is pure: it compiles with no standard include path, names nothing from std::, and stays small.
#   bash scripts/hot-check.sh        BUDGET=<lines> overrides the line budget (default 600 for Core.h + Pack.h + Series.h together)
set -euo pipefail
cd "$(dirname "$0")/.."
CXX=${CXX:-clang++}
HOT="include/Composite/Core.h include/Composite/Pack.h include/Composite/Series.h"
if grep -n '^[[:space:]]*#[[:space:]]*include[[:space:]]*<' $HOT; then echo "FAIL: a hot header includes a standard header"; exit 1; fi
for f in $HOT; do
  if sed 's://.*$::' "$f" | grep -nE '(^|[^A-Za-z_])std::' | sed "s|^|$f:|"; then echo "FAIL: a hot header names std:: in code"; exit 1; fi
done
$CXX -std=gnu++20 -fsyntax-only -nostdinc -nostdinc++ -ffreestanding -Iinclude -x c++ include/Composite/Hot.h
lines=$(cat $HOT | wc -l)
budget=${BUDGET:-600}
if [ "$lines" -gt "$budget" ]; then echo "FAIL: the hot set is $lines lines, over its budget of $budget"; exit 1; fi
echo "hot set: pure ($lines lines of $budget), compiles with no standard headers"
