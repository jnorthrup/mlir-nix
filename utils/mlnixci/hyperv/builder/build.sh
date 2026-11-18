#!/bin/bash
# In the builder distro, as jim: build mlnix and mlnixci from the store's mlir-nix repository (mlnixci is its
# utils/mlnixci), run mlnixci's checks, and lay out a runtime the NixOS distro runs them from: runtimes/<stamp> with the
# programs, patched to load Debian's libraries from the runtime's lib/ with the runtime's own dynamic loader, so they need
# nothing of NixOS but the kernel.
#   bash /mnt/wsl/mlnixos/src/mlir-nix/utils/mlnixci/hyperv/builder/build.sh [mlir-nix-branch]   (default master)
# It prints STAMP=<stamp>; nixos/beside.sh STAMP [PORT [PAGE]] runs that runtime beside the system's service.
#   SWITCH=1 bash ...   also point /mnt/wsl/mlnixos/runtime (the system's service's and mlnixos-rebuild's) at it.  Refused
#                       while that runtime is mini-luci's (bin/mini-luci): the system's service would not find its program.
# The body is one function, read whole before it runs: the checkout below may rewrite this file, so a change to it takes
# effect only from the run after the checkout that brings it.
set -euo pipefail

main() {
  local ST=/mnt/wsl/mlnixos BRANCH=${1:-master} LLVM=/usr/lib/llvm-22 SWITCH=${SWITCH:-0}
  export PATH=$LLVM/bin:$PATH
  local S=$ST/src/mlir-nix B=$ST/build/mlir-nix L=$ST/build/mlnixci
  local M=$S/utils/mlnixci
  if [ "$SWITCH" = 1 ] && [ -e $ST/runtime/bin/mini-luci ]; then
    echo "SWITCH=1 refused: $ST/runtime is mini-luci's, and the system's service runs its bin/mini-luci" >&2; exit 1
  fi

  # the source: the store's clone of mlir-nix, at the branch asked for
  if [ -d $S/.git ]; then git -C $S fetch -q origin && git -C $S checkout -q -B "$BRANCH" "origin/$BRANCH"
  else git clone -q -b "$BRANCH" $ST/git/mlir-nix.git $S; fi
  echo "source: $(git -C $S log --oneline -1 | cut -c1-110)"

  # mlnix and mlnix-opt
  local t0=$SECONDS
  [ -f $B/build.ninja ] || cmake -S $S -B $B -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=clang-22 \
    -DCMAKE_CXX_COMPILER=clang++-22 -DLLVM_DIR=$LLVM/lib/cmake/llvm -DMLIR_DIR=$LLVM/lib/cmake/mlir \
    -DMLIR_TABLEGEN_EXE=$LLVM/bin/mlir-tblgen > $ST/build/mlir-nix.configure.log
  cmake --build $B --target mlnix mlnix-opt > $ST/build/mlir-nix.build.log 2>&1 \
    || { grep -m20 'error:' $ST/build/mlir-nix.build.log; exit 1; }
  echo "mlnix, mlnix-opt: built in $((SECONDS - t0)) s"

  # mlnixci (src/*.mlir and query.mlir through mlnix-opt; libc and liburing-ffi, no C++), its compiled query and text
  # checks, and e2e against a server on os/ (port 8097: the distros share one network, and the services hold 8080-8082)
  t0=$SECONDS
  make -C $M MLNIX_BIN=$B/bin BUILD=$L LLVM_BIN=$LLVM/bin NIXPKGS_LIB=$ST/src/nixpkgs/lib CHECK_PORT=8097 check \
    > $ST/build/mlnixci.build.log 2>&1 || { tail -30 $ST/build/mlnixci.build.log; exit 1; }
  echo "mlnixci: built and checked in $((SECONDS - t0)) s: e2e PASS $(grep -c '^PASS' $ST/build/mlnixci.build.log)," \
    "FAIL $(grep -c '^FAIL' $ST/build/mlnixci.build.log)"
  if ldd $L/mlnixci | grep -E 'libstdc\+\+|libc\+\+|libgcc_s'; then echo "mlnixci links a C++ library" >&2; exit 1; fi

  # the runtime: the programs and the Debian libraries they load, the loader among them, in a new directory, so a
  # running server keeps the files it started with
  local stamp R interp p
  stamp=$(date +%Y%m%d%H%M%S)
  R=$ST/runtimes/$stamp
  mkdir -p $R/bin $R/lib $R/share/mlnixci
  for p in $B/bin/mlnix $B/bin/mlnix-opt $L/mlnixci; do
    install -m755 "$p" $R/bin/
    ldd "$p" | awk '/=> \//{print $3} /^\t\/lib/{print $1}' | while read -r so; do cp -Ln "$so" $R/lib/ 2>/dev/null || true; done
  done
  interp=$(basename "$(patchelf --print-interpreter $B/bin/mlnix)")
  # The runtime's own loader: the libc beside it is the one it was copied with.  Every object looks beside itself: a
  # program's search path serves only its own NEEDED once a library on the way has a RUNPATH of its own (libLLVM does),
  # and libLLVM's libedit needs libtinfo.
  for p in $R/bin/*; do patchelf --set-interpreter $R/lib/$interp --set-rpath '$ORIGIN/../lib' "$p"; done
  for p in $R/lib/*.so*; do case $(basename "$p") in ld-linux*) ;; *) patchelf --set-rpath '$ORIGIN' "$p" ;; esac; done
  cp -r $M/www $M/corpus.nix $M/facets.nix $M/answer.nix $M/runtime.nix $M/os $M/nixos $R/share/mlnixci/
  { echo "mlnixci: mlir-nix utils/mlnixci"; git -C $S log --oneline -1; } > $R/VERSION
  # what the runtime loads: nothing outside it
  if LD_DEBUG=libs $R/bin/mlnix instantiate --eval -E '"mlnix runs from the runtime"' 2>&1 | grep -E 'calling init: /' \
       | grep -v -e "calling init: $R"; then
    echo "runtime: a library loaded from outside the runtime" >&2; exit 1
  fi
  $R/bin/mlnix instantiate --eval -E '"mlnix runs from the runtime"'
  if [ "$SWITCH" = 1 ]; then
    ln -sfn runtimes/$stamp $ST/runtime.new && mv -T $ST/runtime.new $ST/runtime
    echo "runtime: $ST/runtime -> runtimes/$stamp ($(du -sh $R | cut -f1))"
  else
    echo "runtime: $R, beside $ST/runtime -> $(readlink $ST/runtime) ($(du -sh $R | cut -f1))"
  fi
  echo "STAMP=$stamp"
}

main "$@"
exit
