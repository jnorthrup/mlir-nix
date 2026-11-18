#!/bin/sh
# On Kali, as root: install the store's tmpfiles entry and mount units, and mount it.  This is all mlnixos needs of Kali.
set -eu
here=$(dirname "$0")
install -m644 "$here/mlnixos-store.conf" /etc/tmpfiles.d/mlnixos-store.conf
install -m644 "$here/srv-mlnixos-nixpkgs.mount" "$here/mnt-wsl-mlnixos.mount" /etc/systemd/system/
systemd-tmpfiles --create /etc/tmpfiles.d/mlnixos-store.conf
systemctl daemon-reload
systemctl enable --now srv-mlnixos-nixpkgs.mount mnt-wsl-mlnixos.mount
findmnt -o TARGET,SOURCE,OPTIONS,PROPAGATION /srv/mlnixos/nixpkgs /mnt/wsl/mlnixos
