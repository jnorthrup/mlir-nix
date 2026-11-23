#!/bin/bash
# The mlnixos chroot's root, made and attached as the user (no root needed):  mkroot.sh ROOT [LINUX_BIN] [SEED_DIR]
# ROOT is the mount point of a sparse APFS disk image, ROOT.sparsebundle.  The user attaches it, so macOS mounts it
# nosuid and nodev, which mlnixos-chroot requires.  It holds the minimum macOS needs to run a program, and the
# bootstrap's inputs; nothing else of macOS:
#   /usr/lib/dyld        Apple's dyld (a copy): the kernel loads /usr/lib/dyld from the chroot for every program, and
#                        refuses static arm64 executables, so nothing runs without it
#   /System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e*
#                        the arm64e dyld shared cache, 82 files (libSystem, libc++ and the frameworks exist only in it),
#                        kept compressed; dyld maps it into each process (DYLD_SHARED_REGION=private, mlnixos-chroot)
#   /dev                 devfs, mounted by mlnixos-chroot
#   /bin/sh              the seed's bash, in /nix/store (nixpkgs' darwin stdenv expects /bin/sh; dangling until the
#                        seed is imported).  Apple's sh is no use here: dyld ignores DYLD_SHARED_REGION for platform
#                        binaries, so in the chroot they cannot load libSystem
#   /bin/mlnix ...       mlnix built on Linux (it links only libSystem, libc++ and libz, all in the cache)
#   /etc/ssl/cert.pem    the CA bundle, for fetches over https
#   /src/nixpkgs         nixpkgs 3ff0e34 as mlnixos evaluates it, unpatched; /src/{stages,boot}.nix
#   /tmp/seed /tmp/fod   the seed (seed.sh, checked against nixpkgs' pins) and rotted sources (fod-rescue.sh)
#   /nix/store /nix/var/mlnix /home/USER
# Re-run after a macOS update: dyld and the cache change with it.
set -euo pipefail
R=$1
BIN=${2:-/Users/jim/mlnixos-darwin/bin}
SEED=${3:-/Users/jim/mlnixos-darwin/tmp/seed}
IMG=${IMG:-$R.sparsebundle}
NP_REV=${NP_REV:-3ff0e34b1383648053bba8ed03f201d3466f90c9}
D=$(cd "$(dirname "$0")" && pwd)
C=System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld

if ! mount | grep -q " on $R ("; then
  [ -d "$IMG" ] || hdiutil create -quiet -type SPARSEBUNDLE -fs APFS -volname mlnixos -size 300g "$IMG"
  mkdir -p "$R"
  hdiutil attach -quiet -nobrowse -owners on -mountpoint "$R" "$IMG"
fi
flags=$(mount | grep " on $R (" | sed 's/.*(\(.*\))/\1/')
case "$flags" in *nosuid*) ;; *) echo "$R is mounted without nosuid ($flags): mlnixos-chroot would refuse it"; exit 1;; esac

mkdir -p "$R"/{bin,usr/lib,dev,etc/ssl,src,nix/store,nix/var/mlnix,"$C",System/Cryptexes,tmp/seed,tmp/fod} "$R/home/$(id -un)"
chmod 755 "$R"; chmod 1777 "$R/tmp"
# dyld and the cache family (not .map or .atlas, which only tools read), copied when size or date differ.  The originals
# are flagged restricted (SIP), which no copy may carry, so ditto (which copies flags) gets a plain cp of each first;
# ditto then stores it compressed, as the originals are (2.4 GB rather than 6.7).
same() { [ -e "$2" ] && [ "$(stat -f %z.%m "$1")" = "$(stat -f %z.%m "$2")" ]; }
put() { cp "$1" "$R/tmp/.put" && touch -r "$1" "$R/tmp/.put" && ditto --hfsCompression "$R/tmp/.put" "$2" && rm "$R/tmp/.put"; }
same /usr/lib/dyld "$R/usr/lib/dyld" || put /usr/lib/dyld "$R/usr/lib/dyld"
n=0
for f in "/$C"/dyld_shared_cache_arm64e*; do
  case "$f" in *.map|*.atlas) continue;; esac
  same "$f" "$R/$C/${f##*/}" || put "$f" "$R/$C/${f##*/}"
  n=$((n + 1))
done
ln -sfn ../../System/Volumes/Preboot/Cryptexes/OS "$R/System/Cryptexes/OS"
cp /etc/ssl/cert.pem "$R/etc/ssl/cert.pem"
for f in mlnix mlnix-opt mlnix-kif mlnix-parse; do cp -p "$BIN/$f" "$R/bin/$f"; done
for x in nix-build nix-instantiate nix-store nix-hash; do ln -sfn mlnix "$R/bin/$x"; done
if [ ! -f "$R/src/nixpkgs/.version" ]; then
  mkdir -p "$R/src/nixpkgs"
  ssh -o ConnectTimeout=10 kali "git -C /srv/mlnixos/src/nixpkgs archive $NP_REV" | tar -x -C "$R/src/nixpkgs"
  echo "$NP_REV" > "$R/src/nixpkgs/.git-revision"
fi
cp "$D/stages.nix" "$D/boot.nix" "$R/src/"
cp -p "$SEED/bootstrap-tools.tar.xz" "$SEED/unpack.nar" "$R/tmp/seed/"
# /bin/sh -> the seed's bash at the store path nixpkgs gives the unpack seed (computed, nothing written).
unpack=$(NIX_STORE_DIR=/nix/store NIX_REMOTE=dummy:// "$R/bin/mlnix" eval --raw -E \
  "(import $R/src/nixpkgs/pkgs/stdenv/darwin/bootstrap-files/aarch64-apple-darwin.nix).unpack.outPath")
ln -sfn "$unpack/bin/bash" "$R/bin/sh"
echo "root: $R ($flags); dyld + $n cache files, $(du -sh "$R/System" | cut -f1) on disk; /bin/sh -> $unpack/bin/bash"
echo "      nixpkgs $(cut -c1-12 "$R/src/nixpkgs/.git-revision"); image $(du -sh "$IMG" | cut -f1)"
