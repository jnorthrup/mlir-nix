#!/bin/bash
# LLVM 22.1.8 + MLIR built in mlnix-os (Linux aarch64) FOR arm64 macOS: static libraries and CMake package files that a
# cross build of mlir-nix links.  The tablegens and other build-time tools are Debian's llvm-22 (the same 22.1.8), so
# nothing built for macOS has to run here.  No zstd, z3, libxml2, libedit, libffi or curl: the only libraries the result
# can need are the SDK's (libSystem, libc++, libz), which every Mac has in /usr/lib.
#   llvm-darwin.sh WORK [JOBS]     (WORK holds src/, sdk/; installs WORK/llvm-darwin)
set -euo pipefail
W=$1; J=${2:-10}
D=$(cd "$(dirname "$0")" && pwd)
L=/usr/lib/llvm-22/bin
S=$W/src/llvm-project-22.1.8.src
B=$W/${LLVM_BUILD_DIR:-build-llvm}
P=$W/llvm-darwin
cmake -G Ninja -S $S/llvm -B $B \
  -DCMAKE_TOOLCHAIN_FILE=$D/darwin.cmake -DDARWIN_SDK=$W/sdk/MacOSX15.2.sdk \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$P \
  -DLLVM_ENABLE_PROJECTS=mlir -DLLVM_TARGETS_TO_BUILD=AArch64 \
  -DLLVM_HOST_TRIPLE=arm64-apple-darwin22.0.0 -DLLVM_DEFAULT_TARGET_TRIPLE=arm64-apple-darwin22.0.0 \
  -DLLVM_NATIVE_TOOL_DIR=$L \
  -DLLVM_TABLEGEN=$L/llvm-tblgen -DMLIR_TABLEGEN=$L/mlir-tblgen \
  -DMLIR_LINALG_ODS_YAML_GEN=$L/mlir-linalg-ods-yaml-gen -DMLIR_PDLL_TABLEGEN=$L/mlir-pdll \
  "-DCROSS_TOOLCHAIN_FLAGS_NATIVE=-DCMAKE_C_COMPILER=$L/clang;-DCMAKE_CXX_COMPILER=$L/clang++" \
  -DLLVM_ENABLE_RTTI=ON -DLLVM_ENABLE_ASSERTIONS=OFF \
  -DLLVM_ENABLE_ZLIB=ON -DLLVM_ENABLE_ZSTD=OFF -DLLVM_ENABLE_LIBXML2=OFF -DLLVM_ENABLE_LIBEDIT=OFF \
  -DLLVM_ENABLE_LIBPFM=OFF -DLLVM_ENABLE_Z3_SOLVER=OFF -DLLVM_ENABLE_FFI=OFF -DLLVM_ENABLE_CURL=OFF -DLLVM_ENABLE_HTTPLIB=OFF \
  -DLLVM_INCLUDE_TESTS=OFF -DLLVM_INCLUDE_EXAMPLES=OFF -DLLVM_INCLUDE_BENCHMARKS=OFF -DLLVM_INCLUDE_DOCS=OFF \
  -DMLIR_INCLUDE_TESTS=OFF -DMLIR_INCLUDE_INTEGRATION_TESTS=OFF -DMLIR_ENABLE_BINDINGS_PYTHON=OFF \
  -DLLVM_BUILD_TOOLS=OFF -DLLVM_INSTALL_UTILS=OFF -DLLVM_BUILD_UTILS=OFF -DMLIR_BUILD_MLIR_C_DYLIB=OFF \
  -DLLVM_PARALLEL_LINK_JOBS=2 -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=OFF \
  > $W/llvm-cmake.log 2>&1 || { echo "cmake failed"; tail -30 $W/llvm-cmake.log; exit 1; }
echo "configured: $(grep -c 'Performing Test' $W/llvm-cmake.log) checks"
s=$(date +%s)
ninja -C $B -j$J > $W/llvm-ninja.log 2>&1 || { echo "ninja failed after $(( $(date +%s) - s )) s"; grep -E '^FAILED|error:' $W/llvm-ninja.log | head -20; exit 1; }
echo "built in $(( $(date +%s) - s )) s"
ninja -C $B install > $W/llvm-install.log 2>&1 || { echo "install failed"; tail -20 $W/llvm-install.log; exit 1; }
echo "installed: $(ls $P/lib/*.a | wc -l) static libraries, $(du -sh $P | cut -f1) at $P"
$L/llvm-objdump --macho --private-headers $P/lib/libMLIRIR.a 2>/dev/null | grep -m2 -E 'cmd LC_BUILD_VERSION|platform' || true
