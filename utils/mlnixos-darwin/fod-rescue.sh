#!/bin/bash
# A fixed-output source whose upstream URL has rotted, fetched from tarballs.nixos.org into the chroot's /tmp/fod, from
# where chroot-boot2.sh adds it to the store (--add-fixed: the path the derivation names, by its name and hash):
#   fod-rescue.sh ROOT NAME SRI
# nixpkgs' fetchurl falls back to hashed mirrors only for its legacy sha256/sha512 attributes; with an SRI `hash` the
# mirror URL comes out malformed (tarballs.nixos.org//sha256-...: 404).  Real Nix never notices, because
# cache.nixos.org substitutes the output; this store substitutes nothing.  tarballs.nixos.org/sha256/<hex> has the bytes.
# First seen: mailcap-2.1.54 (releases.pagure.org: 404, 2026-11-22).
set -euo pipefail
R=$1 NAME=$2 SRI=$3
algo=${SRI%%-*}; b64=${SRI#*-}
[ "$algo" = sha256 ] || { echo "only sha256 (got $algo)"; exit 1; }
hex=$(printf '%s' "$b64" | base64 -d | od -An -tx1 | tr -d ' \n')
mkdir -p "$R/tmp/fod"
curl -fsSL --retry 3 -o "$R/tmp/fod/$NAME.part" "https://tarballs.nixos.org/sha256/$hex"
got=$(shasum -a 256 "$R/tmp/fod/$NAME.part" | cut -d' ' -f1)
[ "$got" = "$hex" ] || { echo "hash mismatch: $got"; rm -f "$R/tmp/fod/$NAME.part"; exit 1; }
mv "$R/tmp/fod/$NAME.part" "$R/tmp/fod/$NAME"
echo "$R/tmp/fod/$NAME ($SRI)"
