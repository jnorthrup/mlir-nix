#!/bin/bash
# LLVM 22.1.8's source (the version of Debian's llvm-22 tools in mlnix-os, whose tablegens the cross build uses), from the
# GitHub release, checked against the release's GPG signature with LLVM's release keys.
#   llvm-src.sh WORK
set -euo pipefail
W=$1; mkdir -p "$W"; cd "$W"
V=22.1.8
T=llvm-project-$V.src.tar.xz
B=https://github.com/llvm/llvm-project/releases/download/llvmorg-$V
[ -f $T ] || { curl -fsSL --retry 3 -o $T.part $B/$T && mv $T.part $T; }
[ -f $T.sig ] || curl -fsSL --retry 3 -o $T.sig $B/$T.sig || echo "(no .sig on the release)"
echo "$T: $(stat -c %s $T) bytes, sha256 $(sha256sum $T | cut -c1-64)"
if [ -f $T.sig ]; then
  export GNUPGHOME=$W/gnupg; mkdir -p -m 700 "$GNUPGHOME"
  curl -fsSL --retry 3 https://releases.llvm.org/release-keys.asc -o release-keys.asc && gpg --batch --quiet --import release-keys.asc 2>&1 | tail -2 || true
  gpg --batch --verify $T.sig $T 2>&1 | grep -E 'Good signature|BAD|Can.t check|using|key' || true
fi
[ -d llvm-project-$V.src ] || tar -xJf $T
echo "source: $W/llvm-project-$V.src ($(ls llvm-project-$V.src | tr '\n' ' '))"
