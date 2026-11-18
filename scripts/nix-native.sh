#!/bin/sh
# nix-native.sh F.nix OUT: F through the LLVM arm's first cut (docs/PRELOAD-DIALECTS.md step 3), to the native program OUT,
# which prints F's value as `mlnix instantiate --eval --strict` does.  Kept beside OUT: OUT.mlir (nix-truffle
# --emit-trikeshed: the son-form module in TrikeShed's ops), OUT.lowered.mlir (mlnix-opt --trikeshed-lower-cursors) and
# OUT.ll.  The lowering after mlnix-opt is mlnixci's (utils/mlnixci/Makefile LOWER_BUFFERS).  Exit 2: the emitter refused F
# (it says what it met).
#   BIN       mlnix and mlnix-opt              (default build/bin)
#   LLVM_BIN  mlir-opt, mlir-translate, clang  (default /usr/lib/llvm-22/bin; on the Mac /opt/homebrew/opt/llvm/bin)
#   TRUFFLE   nix-truffle                      (default graal/build/install/nix-truffle/bin/nix-truffle)
set -eu
F=$1; OUT=$2
BIN=${BIN:-build/bin}; LLVM_BIN=${LLVM_BIN:-/usr/lib/llvm-22/bin}
TRUFFLE=${TRUFFLE:-graal/build/install/nix-truffle/bin/nix-truffle}
mkdir -p "$(dirname "$OUT")"
"$TRUFFLE" --bin "$BIN" --emit-trikeshed "$F" > "$OUT.mlir" || exit $?
"$BIN/mlnix-opt" "$OUT.mlir" --trikeshed-lower-cursors > "$OUT.lowered.mlir"
if grep -q 'trikeshed\.' "$OUT.lowered.mlir"; then echo "nix-native: trikeshed ops left after lowering" >&2; exit 1; fi
"$LLVM_BIN/mlir-opt" "$OUT.lowered.mlir" --ownership-based-buffer-deallocation --canonicalize --buffer-deallocation-simplification \
  --bufferization-lower-deallocations --convert-scf-to-cf --expand-strided-metadata --lower-affine --finalize-memref-to-llvm \
  --convert-scf-to-cf --convert-arith-to-llvm --convert-index-to-llvm --convert-cf-to-llvm --convert-func-to-llvm \
  --reconcile-unrealized-casts | "$LLVM_BIN/mlir-translate" --mlir-to-llvmir -o "$OUT.ll"
case $(uname) in Darwin) SDKROOT=${SDKROOT:-$(xcrun --show-sdk-path)}; export SDKROOT ;; esac
"$LLVM_BIN/clang" -O2 -Wno-override-module "$OUT.ll" -o "$OUT"
