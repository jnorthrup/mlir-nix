#!/bin/bash
# The darwin bootstrap inside the mlnixos chroot (mlnixos-chroot installed setuid root; ROOT made by mkroot.sh):
#   chroot-boot2.sh ROOT ORACLE [ATTR...]      (ATTR defaults to "bootstrapTools stage1"; see boot.nix)
# 1. mlnix and the seed's sh run in the chroot; 2. the stages' derivations against Nix 2.28.4's on mlnixos (ORACLE:
# oracle-mlnixos.sh's output with store /nix/store); 3. the seed and rescued sources go into the store; 4. each ATTR is
# built; 5. every path it built is compared with Hydra's: same store path, so cache.nixos.org's narinfo has its NAR hash.
set -uo pipefail
R=$1 ORACLE=$2; shift 2
ATTRS=${*:-bootstrapTools stage1}
D=$(cd "$(dirname "$0")" && pwd)
X=${CHROOT:-/usr/local/sbin/mlnixos-chroot}
L=$R/tmp/logs; mkdir -p "$L"
in() { "$X" "$R" "$@"; }
echo "== in the chroot: $(in /bin/mlnix --version 2>&1)"
echo "== the stages, mlnix vs Nix 2.28.4 (nixpkgs 3ff0e34 unpatched, /nix/store)"
in /bin/nix-instantiate --readonly-mode --eval --strict --json /src/stages.nix --arg nixpkgs /src/nixpkgs > $L/stages.json 2> $L/stages.err
echo "   rc=$?"; head -3 $L/stages.err
python3 "$D/same-json.py" $L/stages.json "$ORACLE"
echo "== seed"
[ -d $R/tmp/seed/unpack ] || in /bin/mlnix store --restore /tmp/seed/unpack < $R/tmp/seed/unpack.nar
echo "   $(in /bin/mlnix store --add /tmp/seed/unpack 2>&1)"
echo "   $(in /bin/mlnix store --add-fixed sha256 /tmp/seed/bootstrap-tools.tar.xz 2>&1)"
for f in $R/tmp/fod/*; do [ -f "$f" ] && echo "   $(in /bin/mlnix store --add-fixed sha256 /tmp/fod/${f##*/} 2>&1)"; done
echo "   /bin/sh: $(in /bin/sh -c 'echo "$BASH_VERSION"' 2>&1)"
for a in $ATTRS; do
  echo "== build $a"
  s=$(date +%s)
  in /bin/nix-build /src/boot.nix --arg nixpkgs /src/nixpkgs -A $a -o /tmp/result-$a > $L/chroot-$a.log 2>&1
  rc=$?
  echo "   rc=$rc in $(( $(date +%s) - s )) s, $(grep -c '^building' $L/chroot-$a.log) builds; $(tail -1 $L/chroot-$a.log | cut -c1-200)"
  [ $rc = 0 ] || { grep -E '^error' $L/chroot-$a.log | tail -3; break; }
done
echo "== every built output against Hydra's (cache.nixos.org narinfo NarHash)"
python3 "$D/vs-hydra.py" "$X" "$R" $L/chroot-*.log
