#!/bin/bash
# The mlnixos chroot's root, made and attached as the user (no root needed):  mkroot.sh ROOT [LINUX_BIN] [SEED_DIR]
# ROOT is the mount point of a sparse APFS disk image, ROOT.sparsebundle.  The user attaches it, so macOS mounts it
# nosuid and nodev, which mlnixos-chroot requires.  Of macOS it holds only dyld, as the kernel needs it:
#   /usr/lib/dyld        Apple's dyld (a copy, 4 MB): the kernel loads /usr/lib/dyld from the chroot for every program,
#                        and refuses static arm64 executables, so nothing runs without it
#   /usr/libexec/mlnixos-chroot
#                        a plain copy of the helper: run first in the chroot with the REAL cache directory as /dev/fd/N,
#                        so that its dyld maps the real (SIP-protected) cache into the chroot's shared region, where
#                        every later process finds it.  No copy of the cache is needed for that
#   /dev                 devfs, mounted by mlnixos-chroot
#   /bin/sh              the seed's bash, in /nix/store (nixpkgs' darwin stdenv expects /bin/sh; dangling until the
#                        seed is imported).  Apple's programs cannot run from a copy (launch constraints)
#   /bin/mlnix ...       mlnix built on Linux (it links only libSystem, libc++ and libz, all in the cache)
#   /etc/ssl/cert.pem    the CA bundle, for fetches over https; /etc/hosts, for localhost
#                        (host names are resolved outside, by mlnixos-chroot's proxy)
#   /src/nixpkgs         nixpkgs 3ff0e34 as mlnixos evaluates it, unpatched; /src/{stages,boot}.nix
#   /tmp/seed /tmp/fod   the seed (seed.sh, checked against nixpkgs' pins) and rotted sources (fod-rescue.sh)
#   /nix/store /nix/var/mlnix /home/USER
# CACHE_COPY=1 also copies the arm64e cache (82 files, 6.7 GB) to /System/Library/dyld, for the helper's fallback
# (DYLD_SHARED_REGION=private: each process maps the copy itself) should the real cache not map into the chroot.
# Re-run after a macOS update: dyld and the cache change with it.
set -euo pipefail
R=$1
BIN=${2:-$HOME/.local/share/mlnixos-darwin/bin}
SEED=${3:-$HOME/.local/share/mlnixos-darwin/seed}
HELPER=${HELPER:-$HOME/.local/share/mlnixos-darwin/mlnixos-chroot}
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

mkdir -p "$R"/{bin,usr/lib,usr/libexec,dev,etc/ssl,src,nix/store,nix/var/mlnix,tmp/seed,tmp/fod} "$R/home/$(id -un)"
chmod 755 "$R"; chmod 1777 "$R/tmp"
# Copies are plain cp: the originals are flagged restricted (SIP), which `cp -p` and ditto fail to copy.
same() { [ -e "$2" ] && [ "$(stat -f %z.%m "$1")" = "$(stat -f %z.%m "$2")" ]; }
put() { cp "$1" "$2" && touch -r "$1" "$2"; }
same /usr/lib/dyld "$R/usr/lib/dyld" || put /usr/lib/dyld "$R/usr/lib/dyld"
cp "$HELPER" "$R/usr/libexec/mlnixos-chroot"; chmod 755 "$R/usr/libexec/mlnixos-chroot"
n=0
if [ "${CACHE_COPY:-0}" = 1 ]; then
  mkdir -p "$R/$C" "$R/System/Cryptexes" "$R/System/Library"
  for f in "/$C"/dyld_shared_cache_arm64e*; do
    case "$f" in *.map|*.atlas) continue;; esac
    same "$f" "$R/$C/${f##*/}" || put "$f" "$R/$C/${f##*/}"
    n=$((n + 1))
  done
  ln -sfn ../../System/Volumes/Preboot/Cryptexes/OS "$R/System/Cryptexes/OS"
  ln -sfn ../Volumes/Preboot/Cryptexes/OS/System/Library/dyld "$R/System/Library/dyld"
fi
cp /etc/ssl/cert.pem "$R/etc/ssl/cert.pem"; cp /etc/hosts "$R/etc/hosts"
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
echo "root: $R ($flags); dyld, $n cache files copied; /bin/sh -> $unpack/bin/bash"
echo "      nixpkgs $(cut -c1-12 "$R/src/nixpkgs/.git-revision"); image $(du -sh "$IMG" | cut -f1)"
