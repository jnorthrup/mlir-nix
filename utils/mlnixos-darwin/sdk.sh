#!/bin/bash
# The macOS SDK for cross compiling on Linux, fetched and unpacked the way nixpkgs' apple-sdk does it
# (pkgs/by-name/ap/apple-sdk/common/fetch-sdk.nix): Apple's CLTools_macOSNMOS_SDK.pkg from swcdn.apple.com, its Payload
# (pbzx) as a cpio archive, the SDK directory minus usr/bin, usr/share and System/Library/Perl.  The result is checked
# against nixpkgs' pinned hash, which is the NAR hash (recursiveHash) of that directory.
#   sdk.sh WORK            (in mlnix-os; WORK on the VM's disk)
set -euo pipefail
W=$1; mkdir -p "$W"; cd "$W"
HERE=$(cd "$(dirname "$0")" && pwd)
VER=15.2
URLS="https://swcdn.apple.com/content/downloads/36/33/072-44426-A_G1AII30AST/ddbss9h6gse6a32rg6luosbrm6vgniu033/CLTools_macOSNMOS_SDK.pkg
https://web.archive.org/web/20250210234739/https://swcdn.apple.com/content/downloads/36/33/072-44426-A_G1AII30AST/ddbss9h6gse6a32rg6luosbrm6vgniu033/CLTools_macOSNMOS_SDK.pkg"
WANT=sha256-OP5Ah/JnSZ6sD42BD5vGDmikgFzjsfFBmz1hvQD1dOI=     # nixpkgs 25.05 apple-sdk metadata/versions.json "15"
MLNIX=${MLNIX:-$HOME/mlnix-d3m-src-038009d/bin/mlnix}
# nixpkgs' urls in order, as fetchurl tries them (swcdn answered 403 for both pinned SDKs on 2026-11-22; archive.org had them).
for URL in $URLS; do
  [ -f sdk.pkg ] && break
  curl -fsSL --retry 3 -o sdk.pkg.part "$URL" && mv sdk.pkg.part sdk.pkg && echo "fetched $URL"
done
[ -f sdk.pkg ] || { echo "no URL answered"; exit 1; }
echo "pkg: $(stat -c %s sdk.pkg) bytes, sha256 $(sha256sum sdk.pkg | cut -c1-64)"
rm -rf x && mkdir x && cd x
bsdtar -xf ../sdk.pkg
ls
python3 "$HERE/pbzx.py" Payload payload.cpio
cpio -idm --quiet < payload.cpio
src=Library/Developer/CommandLineTools/SDKs/MacOSX$VER.sdk
rm -rf $src/usr/bin $src/usr/share $src/System/Library/Perl
cd ..
rm -rf MacOSX$VER.sdk && mv x/$src MacOSX$VER.sdk && rm -rf x
ln -sfn MacOSX$VER.sdk MacOSX.sdk
echo "sdk: $(du -sh MacOSX$VER.sdk | cut -f1) at $W/MacOSX$VER.sdk"
# The NAR hash, through mlnix's nix-hash (argv[0] picks the personality).
ln -sfn "$MLNIX" "$W/nix-hash"
got=$("$W/nix-hash" --type sha256 --sri "$W/MacOSX$VER.sdk")
echo "NAR hash: $got"
echo "nixpkgs:  $WANT"
[ "$got" = "$WANT" ] && echo "SDK matches nixpkgs' pin" || { echo "SDK DIFFERS from nixpkgs' pin"; exit 1; }
