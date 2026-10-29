#!/bin/bash
# A profile-guided build of mlnix: instrument, train on the real workloads, rebuild with the profile.
#
#   bash scripts/pgo-build.sh [OUT_DIR]        default OUT_DIR=build-pgo (build-pgo/gen, build-pgo/use, build-pgo/prof)
#
# Environment: LLVM_DIR and MLIR_DIR (cmake dirs, as for the ordinary build), CXX/CC (default: the compiler of ./build), PROFDATA (default:
# `xcrun llvm-profdata` on macOS, llvm-profdata on PATH elsewhere).  Linux needs the profile runtime of the compiler (clang: libclang-rt-<N>-dev),
# which -fprofile-instr-generate links.  Training is the two workloads of scripts/vs-nix.py (nixos-toplevel, nixpkgs-73) on the demand schedule,
# so the profile is of the evaluator that benchmark measures; a different workload may do better or worse.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:-build-pgo}
cache() { grep "^$1:" build/CMakeCache.txt | head -1 | cut -d= -f2; }
LLVM_DIR=${LLVM_DIR:-$(cache LLVM_DIR)}; MLIR_DIR=${MLIR_DIR:-$(cache MLIR_DIR)}
CXX=${CXX:-$(cache CMAKE_CXX_COMPILER)}; CC=${CC:-$(cache CMAKE_C_COMPILER)}
if [ -z "${PROFDATA:-}" ]; then
  if [ "$(uname)" = Darwin ]; then PROFDATA="xcrun llvm-profdata"; else PROFDATA=llvm-profdata; fi
fi
mkdir -p "$OUT/prof"; rm -f "$OUT"/prof/*.profraw
cfg() { cmake -S . -B "$OUT/$1" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
        -DLLVM_DIR="$LLVM_DIR" -DMLIR_DIR="$MLIR_DIR" "${@:2}" > "$OUT/cfg-$1.log" 2>&1; }
cfg gen -DCMAKE_CXX_FLAGS="-fprofile-instr-generate" -DCMAKE_EXE_LINKER_FLAGS="-fprofile-instr-generate"
cmake --build "$OUT/gen" --target mlnix > "$OUT/build-gen.log" 2>&1
export MLNIX_DEFER=1 LLVM_PROFILE_FILE="$PWD/$OUT/prof/%p.profraw"
"$OUT/gen/bin/mlnix" instantiate --readonly-mode --eval --strict test/nixos-toplevel.nix --arg nixpkgs ./.cache/nixpkgs > /dev/null 2>&1
"$OUT/gen/bin/mlnix" instantiate --readonly-mode --eval --strict --json test/nixpkgs-drvs.nix --argstr system x86_64-linux > /dev/null 2>&1
unset LLVM_PROFILE_FILE
$PROFDATA merge -o "$OUT/merged.profdata" "$OUT"/prof/*.profraw
cfg use -DCMAKE_CXX_FLAGS="-fprofile-instr-use=$PWD/$OUT/merged.profdata -Wno-profile-instr-unprofiled -Wno-profile-instr-out-of-date -Wno-backend-plugin"
cmake --build "$OUT/use" --target mlnix > "$OUT/build-use.log" 2>&1
echo "profile-guided mlnix: $OUT/use/bin/mlnix"
