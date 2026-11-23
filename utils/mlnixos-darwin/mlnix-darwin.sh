#!/bin/bash
# mlir-nix built in mlnix-os FOR arm64 macOS, against llvm-darwin.sh's LLVM/MLIR.  What runs at build time runs here:
# Debian's mlir-tblgen, opt, mlir-opt and mlir-translate, a Linux mlnix-opt of the same source for
# --trikeshed-lower-cursors, and llc/clang wrapped to emit arm64 macOS objects.  The result links only what every Mac has
# in /usr/lib (libSystem, libc++, libz): no Homebrew.
#   mlnix-darwin.sh WORK SRC HOST_BIN OUT [JOBS]
#     SRC: a git archive of mlir-nix; HOST_BIN: a Linux build of the same commit (its mlnix-opt); OUT: where bin/ goes
set -euo pipefail
W=$1 S=$2 H=$3 O=$4 J=${5:-10}
D=$(cd "$(dirname "$0")" && pwd)
L=/usr/lib/llvm-22/bin
P=$W/llvm-darwin
SDK=$W/sdk/MacOSX15.2.sdk
B=$W/build-$(basename "$S")
mkdir -p "$W/bin-cross"
printf '#!/bin/sh\nexec %s/llc -mtriple=arm64-apple-macosx13.0 "$@"\n' $L > "$W/bin-cross/llc"
printf '#!/bin/sh\nexec %s/clang --target=arm64-apple-macos13.0 -isysroot %s "$@"\n' $L "$SDK" > "$W/bin-cross/clang"
chmod +x "$W/bin-cross/llc" "$W/bin-cross/clang"
export PATH=$L:$PATH
cmake -G Ninja -S "$S" -B "$B" \
  -DCMAKE_TOOLCHAIN_FILE=$D/darwin.cmake -DDARWIN_SDK=$SDK -DCMAKE_BUILD_TYPE=Release \
  -DMLIR_DIR=$P/lib/cmake/mlir -DLLVM_DIR=$P/lib/cmake/llvm \
  -DMLNIX_HOST_OPT=$H/mlnix-opt -DMLNIX_OPT=$L/opt -DMLNIX_LLC=$W/bin-cross/llc \
  -DMLNIX_MLIR_OPT=$L/mlir-opt -DMLNIX_MLIR_TRANSLATE=$L/mlir-translate -DMLNIX_LOWER_CLANG=$W/bin-cross/clang \
  -DURING_INCLUDE_DIR=URING_INCLUDE_DIR-NOTFOUND -DURING_LIBRARY=URING_LIBRARY-NOTFOUND \
  > "$B.cmake.log" 2>&1 || { echo "cmake failed"; grep -E 'Error|error' -A4 "$B.cmake.log" | head -30; exit 1; }
grep -E 'MLIRConfig|TABLEGEN' "$B.cmake.log" | head -3 || true
s=$(date +%s)
ninja -C "$B" -j$J > "$B.ninja.log" 2>&1 || { echo "ninja failed after $(( $(date +%s) - s )) s"; grep -E '^FAILED|error:' "$B.ninja.log" | head -30; exit 1; }
echo "built in $(( $(date +%s) - s )) s, $(grep -c 'warning:' "$B.ninja.log") warnings"
mkdir -p "$O/bin" "$O/lib"
for f in "$B"/bin/*; do cp "$f" "$O/bin/"; done
cp "$B"/lib/*.dylib "$O/lib/" 2>/dev/null || true
for f in "$O"/bin/*; do echo "$(basename "$f"): $(stat -c %s "$f") bytes; $($L/llvm-otool -L "$f" | sed 1d | awk '{print $1}' | tr '\n' ' ')"; done
