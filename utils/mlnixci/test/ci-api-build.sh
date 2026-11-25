#!/bin/bash
# ci-api: builds the differential executable, ci-api-walks (no Python ctypes: the Python side only generates cases and
# reads results).  The old api.mlir is BASE's (default 3465fbc: master before the walks), renamed old_* by ci-api-rename.py;
# the new one is this checkout's.  Both are linked with the checkout's modules (mlnix-opt from MLNIX_BIN, LLVM from
# LLVM_BIN; on the Mac: /opt/homebrew/opt/llvm/bin) into one executable with glue (ci-api-glue.mlir).  Mach-O: the
# dealloc_helper localization is done here (llvm-objcopy misses _dealloc_helper on Mach-O).
#   ci-api-build.sh OUTDIR [BASE]
#   OUTDIR/ci-api-walks CASES      (CASES from ci-api-gen.py N_EDIT N_FAIL N_404 N_CORPUS N_QUERY SEED)
set -eu
T=$(cd "$(dirname "$0")" && pwd)
WT=$(cd "$T/../../.." && pwd)
OUT=$1
BASE=${2:-3465fbc}
LLVM=${LLVM_BIN:-/opt/homebrew/opt/llvm/bin}
MLNIX_BIN=${MLNIX_BIN:-$WT/build/bin}
LOW="--convert-scf-to-cf --convert-arith-to-llvm --convert-index-to-llvm --convert-cf-to-llvm --convert-func-to-llvm --reconcile-unrealized-casts"
MODS="series confix corpus eval index columns load reads text query request kursive-walk confix-scan api"
mkdir -p "$OUT"
git -C "$WT" show "$BASE:utils/mlnixci/src/api.mlir" > "$OUT/api_base.mlir"
python3 "$T/ci-api-rename.py" "$OUT/api_base.mlir" "$OUT/old_api.mlir" > /dev/null
cp "$T/ci-api-glue.mlir" "$OUT/glue.mlir"
for f in old_api glue; do
  "$LLVM/mlir-opt" "$OUT/$f.mlir" $LOW | "$LLVM/mlir-translate" --mlir-to-llvmir | "$LLVM/clang" -c -O2 -Wno-override-module -x ir - -o "$OUT/$f.o"
done
OBJS=$(for m in $MODS; do echo -n "$OUT/mods/$m.o "; done)
make -C "$WT/utils/mlnixci" BUILD="$OUT/mods" MLNIX_BIN="$MLNIX_BIN" LLVM_BIN="$LLVM" $OBJS > "$OUT/build-mods.log" 2>&1
for f in $OBJS "$OUT/old_api.o" "$OUT/glue.o"; do "$LLVM/llvm-objcopy" --localize-symbol=_dealloc_helper "$f"; done
"$LLVM/clang" -O1 -o "$OUT/ci-api-walks" "$T/ci-api-walks.c" "$OUT/old_api.o" "$OUT/glue.o" $OBJS
echo "built $OUT/ci-api-walks"
