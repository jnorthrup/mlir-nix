#!/bin/bash
# The darwin bootstrap's seed fetched and checked on Linux, decompressed there (the chroot has no xz yet: the seed is
# what brings it), and laid out for mlnixos-darwin to import:
#   seed.sh NIXPKGS OUT        (OUT on /Users, e.g. ROOT/tmp/seed)
# bootstrap-tools.tar.xz is a flat fixed output (sha256 of the file); unpack is a recursive one (sha256 of its NAR), so
# its NAR is kept as unpack.nar.  Both hashes are nixpkgs' pins in pkgs/stdenv/darwin/bootstrap-files.
set -euo pipefail
NP=$1 O=$2
mkdir -p "$O"; cd "$O"
F=$NP/pkgs/stdenv/darwin/bootstrap-files/aarch64-apple-darwin.nix
url() { grep -o "http://tarballs.nixos.org/[^\"]*/$1" "$F"; }
sri() { python3 - "$1" <<'EOF'
import base64, hashlib, sys
print("sha256-" + base64.b64encode(hashlib.sha256(open(sys.argv[1], "rb").read()).digest()).decode())
EOF
}
want_tools=$(grep -A3 'bootstrapTools = ' "$F" | grep -o 'sha256-[^"]*')
want_unpack=$(grep -A4 'unpack = ' "$F" | grep -o 'sha256-[^"]*')
[ -f bootstrap-tools.tar.xz ] || curl -fsSL --retry 3 -o bootstrap-tools.tar.xz "$(url bootstrap-tools.tar.xz)"
[ -f unpack.nar.xz ] || curl -fsSL --retry 3 -o unpack.nar.xz "$(url unpack.nar.xz)"
xz -dc unpack.nar.xz > unpack.nar
got_tools=$(sri bootstrap-tools.tar.xz); got_unpack=$(sri unpack.nar)
echo "bootstrap-tools.tar.xz $(stat -c %s bootstrap-tools.tar.xz) bytes: $got_tools (nixpkgs $want_tools)"
echo "unpack.nar             $(stat -c %s unpack.nar) bytes: $got_unpack (nixpkgs $want_unpack)"
[ "$got_tools" = "$want_tools" ] && [ "$got_unpack" = "$want_unpack" ] && echo "seed matches nixpkgs' pins" || { echo "SEED DIFFERS"; exit 1; }
