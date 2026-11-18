#!/bin/sh
# In mlnixos as root: a second mini-luci beside the live service, from a runtime laid out by `SWITCH=0 build.sh` (which
# leaves /mnt/wsl/mlnixos/runtime, the live service's, alone), as a transient unit with the live service's sandbox.  It
# does not survive a restart of the distro.
#   sh luci-beside.sh STAMP [PORT [PAGE]]      e.g. sh luci-beside.sh 20261117151247 8081 luci.html
P=/run/current-system/sw/bin
R=/mnt/wsl/mlnixos/runtimes/$1
PORT=${2:-8081}
PAGE=${3:-luci.html}
UNIT=mini-luci-$PORT
[ -x $R/bin/mini-luci ] || { echo "no runtime at $R"; exit 1; }
$P/systemctl stop $UNIT 2>/dev/null
$P/systemctl reset-failed $UNIT 2>/dev/null
$P/systemd-run --unit=$UNIT --description="mini-luci on :$PORT ($PAGE), beside the live service" \
  -p DynamicUser=yes -p RuntimeDirectory=$UNIT -p ProtectSystem=strict -p ProtectHome=yes \
  -p PrivateTmp=yes -p NoNewPrivileges=yes -p Restart=on-failure -p RestartSec=10 \
  --setenv=NIX_PATH=nixpkgs=/mnt/wsl/mlnixos/src/nixpkgs \
  $R/bin/mini-luci --corpus $R/share/mini-luci/nixos/eval.nix \
    --arg nixpkgs /mnt/wsl/mlnixos/src/nixpkgs --arg configuration /etc/nixos/configuration.nix \
    --page $R/share/mini-luci/www/$PAGE --mlnix $R/bin/mlnix --port $PORT
# ready when this invocation's journal says rows= (mlnix has evaluated the corpus)
id=$($P/systemctl show -p InvocationID --value $UNIT)
i=0
while [ $i -lt 60 ]; do
  $P/journalctl _SYSTEMD_INVOCATION_ID=$id --no-pager 2>/dev/null | $P/grep -q "rows=" && break
  $P/sleep 1; i=$((i + 1))
done
$P/systemctl is-active $UNIT
$P/journalctl _SYSTEMD_INVOCATION_ID=$id --no-pager | $P/tail -2
$P/cat $R/VERSION
