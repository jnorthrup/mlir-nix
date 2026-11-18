#!/bin/bash
# In the builder distro, as jim: build mlnix and mini-luci from the store's git repositories into the store, and lay out
# the runtime the NixOS distro runs them from (/mnt/wsl/mlnixos/runtime: the programs, patched to load Debian's libraries
# from runtime/lib with runtime/lib's dynamic loader, so they need nothing of NixOS but the kernel).
#   bash /mnt/wsl/mlnixos/src/mini-luci/hyperv/builder/build.sh [mlir-nix-branch] [mini-luci-branch]
#   SWITCH=0 bash ...   lay the runtime out beside the live one (runtimes/<stamp>) and leave `runtime` where it is: for a
#                       second instance on a spare port
# The body is one function, read whole before it runs: the checkout below may rewrite this file, so a change to it takes
# effect only from the run after the checkout that brings it (check the branch out first).
set -euo pipefail

main() {
  local ST=/mnt/wsl/mlnixos MLIR_BRANCH=${1:-trikeshed-cursor-lowering} LUCI_BRANCH=${2:-mlnixos} LLVM=/usr/lib/llvm-22
  local SWITCH=${SWITCH:-1}
  export PATH=$LLVM/bin:$PATH

  # sources: clones of the store's repositories, at the branches asked for
  checkout() { # repo branch dir
    if [ -d "$3/.git" ]; then git -C "$3" fetch -q origin && git -C "$3" checkout -q -B "$2" "origin/$2"
    else git clone -q -b "$2" "$ST/git/$1.git" "$3"; fi
    git -C "$3" log --oneline -1
  }
  checkout mlir-nix "$MLIR_BRANCH" $ST/src/mlir-nix
  checkout mini-luci "$LUCI_BRANCH" $ST/src/mini-luci

  # mlnix
  local B=$ST/build/mlir-nix
  [ -f $B/build.ninja ] || cmake -S $ST/src/mlir-nix -B $B -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=clang-22 \
    -DCMAKE_CXX_COMPILER=clang++-22 -DLLVM_DIR=$LLVM/lib/cmake/llvm -DMLIR_DIR=$LLVM/lib/cmake/mlir \
    -DMLIR_TABLEGEN_EXE=$LLVM/bin/mlir-tblgen > $ST/build/mlir-nix.configure.log
  cmake --build $B --target mlnix mlnix-opt > $ST/build/mlir-nix.build.log 2>&1 || { grep -m20 'error:' $ST/build/mlir-nix.build.log; exit 1; }
  tail -1 $ST/build/mlir-nix.build.log

  # mini-luci (src/*.mlir, and query.mlir through mlnix-opt; libc and liburing-ffi, no C++) and its checks that need no
  # corpus
  local L=$ST/build/mini-luci
  make -C $ST/src/mini-luci MLIR_NIX=$ST/src/mlir-nix MLNIX_BIN=$B/bin BUILD=$L $L/mini-luci $L/query.so > $ST/build/mini-luci.build.log 2>&1 \
    || { tail -20 $ST/build/mini-luci.build.log; exit 1; }
  python3 $ST/src/mini-luci/test/facet_check.py $L/query.so

  # the runtime: programs and the Debian libraries they load, the loader among them; a new directory each time, then
  # `runtime` is switched to it, so a running server keeps the files it started with
  local stamp R interp p
  stamp=$(date +%Y%m%d%H%M%S)
  R=$ST/runtimes/$stamp
  mkdir -p $R/bin $R/lib $R/share/mini-luci
  for p in $B/bin/mlnix $B/bin/mlnix-opt $L/mini-luci; do
    install -m755 "$p" $R/bin/
    ldd "$p" | awk '/=> \//{print $3} /^\t\/lib/{print $1}' | while read -r so; do cp -Ln "$so" $R/lib/ 2>/dev/null || true; done
  done
  interp=$(basename "$(patchelf --print-interpreter $B/bin/mlnix)")
  # Every object looks beside itself: a program's search path serves only its own NEEDED once a library on the way has
  # a RUNPATH of its own (libLLVM does), and libLLVM's libedit needs libtinfo.
  for p in $R/bin/*; do patchelf --set-interpreter $ST/runtime/lib/$interp --set-rpath '$ORIGIN/../lib' "$p"; done
  for p in $R/lib/*.so*; do case $(basename "$p") in ld-linux*) ;; *) patchelf --set-rpath '$ORIGIN' "$p" ;; esac; done
  local m=$ST/src/mini-luci
  cp -r $m/www $m/corpus.nix $m/facets.nix $m/answer.nix $m/runtime.nix $m/os $m/nixos $R/share/mini-luci/
  { git -C $ST/src/mlir-nix log --oneline -1; git -C $ST/src/mini-luci log --oneline -1; } > $R/VERSION
  if [ "$SWITCH" = 1 ]; then
    ln -sfn runtimes/$stamp $ST/runtime.new && mv -T $ST/runtime.new $ST/runtime
    echo "runtime: $ST/runtime -> runtimes/$stamp ($(du -sh $R | cut -f1))"
  else
    echo "runtime: $R, beside $ST/runtime -> $(readlink $ST/runtime) ($(du -sh $R | cut -f1))"
  fi
  # what the runtime loads: nothing outside it (its programs name the loader of runtime/lib, the same Debian ld.so)
  if LD_DEBUG=libs $R/bin/mlnix instantiate --eval -E '"mlnix runs from the runtime"' 2>&1 | grep -E 'calling init: /' \
       | grep -v -e "calling init: $R" -e "calling init: $ST/runtime"; then
    echo "runtime: a library loaded from outside the runtime" >&2; exit 1
  fi
  $R/bin/mlnix instantiate --eval -E '"mlnix runs from the runtime"'
}

main "$@"
exit
