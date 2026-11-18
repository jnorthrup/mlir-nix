#!/bin/sh
# In mlnixos as root: mlnixci from a runtime laid out by hyperv/builder/build.sh, as a transient unit mlnixci-PORT with
# the live service's sandbox, beside the system's own service (whose unit and `runtime` link it leaves alone).  It does
# not survive a restart of the distro: run it again.
#   sh /mnt/wsl/mlnixos/src/mlir-nix/utils/mlnixci/hyperv/nixos/beside.sh STAMP [PORT [PAGE]]
#   e.g. ... beside.sh 20261118084318 8082 luci.html
P=/run/current-system/sw/bin
R=/mnt/wsl/mlnixos/runtimes/$1
PORT=${2:-8082}
PAGE=${3:-luci.html}
UNIT=mlnixci-$PORT
[ -x $R/bin/mlnixci ] || { echo "no mlnixci runtime at $R"; exit 1; }
$P/systemctl stop $UNIT 2>/dev/null
$P/systemctl reset-failed $UNIT 2>/dev/null
$P/systemd-run --unit=$UNIT --description="mlnixci on :$PORT ($PAGE), beside the system's service" \
  -p DynamicUser=yes -p RuntimeDirectory=$UNIT -p ProtectSystem=strict -p ProtectHome=yes \
  -p PrivateTmp=yes -p NoNewPrivileges=yes -p Restart=on-failure -p RestartSec=10 \
  --setenv=NIX_PATH=nixpkgs=/mnt/wsl/mlnixos/src/nixpkgs \
  $R/bin/mlnixci --corpus $R/share/mlnixci/nixos/eval.nix \
    --arg nixpkgs /mnt/wsl/mlnixos/src/nixpkgs --arg configuration /etc/nixos/configuration.nix \
    --page $R/share/mlnixci/www/$PAGE --mlnix $R/bin/mlnix --port $PORT
# ready when this invocation's journal says rows= (mlnix has evaluated the corpus: about 5 s for NixOS)
id=$($P/systemctl show -p InvocationID --value $UNIT)
i=0
while [ $i -lt 90 ]; do
  $P/journalctl _SYSTEMD_INVOCATION_ID=$id --no-pager 2>/dev/null | $P/grep -q "rows=" && break
  $P/sleep 1; i=$((i + 1))
done
$P/systemctl is-active $UNIT
$P/journalctl _SYSTEMD_INVOCATION_ID=$id --no-pager | $P/tail -2
$P/systemctl show -p MemoryCurrent -p MemoryPeak $UNIT
$P/cat $R/VERSION
