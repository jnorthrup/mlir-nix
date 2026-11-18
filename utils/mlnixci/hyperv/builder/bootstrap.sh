#!/bin/sh
# The builder distro (Debian trixie, WSL2) that builds mlnix and mlnixci into the store for the NixOS distro, mlnixos.
# Once, as root, from the store's checkout of mlir-nix:
#   wsl -d mlnix-builder -u root -- sh /mnt/wsl/mlnixos/src/mlir-nix/utils/mlnixci/hyperv/builder/bootstrap.sh
# The toolchain mlnix is built with (LLVM/MLIR 22 from apt.llvm.org), user jim (uid 1000, as on Kali and NixOS, so the
# store's files are his everywhere), systemd, and the unit that waits for the store.  Takes effect at the distro's next
# start.
set -eu
here=$(dirname "$0")
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq ca-certificates curl gpg >/dev/null
curl -fsSL https://apt.llvm.org/llvm-snapshot.gpg.key | gpg --dearmor --yes -o /usr/share/keyrings/apt.llvm.org.gpg
echo 'deb [signed-by=/usr/share/keyrings/apt.llvm.org.gpg] http://apt.llvm.org/trixie/ llvm-toolchain-trixie-22 main' \
  > /etc/apt/sources.list.d/llvm-22.list
apt-get update -qq
apt-get install -y -qq git sudo time python3 cmake ninja-build patchelf clang-22 llvm-22-dev llvm-22-tools libmlir-22-dev mlir-22-tools \
  libssl-dev liburing-dev zlib1g-dev libzstd-dev libedit-dev libxml2-dev libffi-dev libcurl4-openssl-dev >/dev/null
id jim >/dev/null 2>&1 || useradd -m -u 1000 -s /bin/bash -G sudo jim
echo 'jim ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/jim && chmod 440 /etc/sudoers.d/jim
install -m644 "$here/wsl.conf" /etc/wsl.conf
install -m644 "$here/mlnixos-store.service" /etc/systemd/system/mlnixos-store.service
mkdir -p /etc/systemd/system/multi-user.target.wants
ln -sf /etc/systemd/system/mlnixos-store.service /etc/systemd/system/multi-user.target.wants/mlnixos-store.service
/usr/lib/llvm-22/bin/mlir-opt --version | head -2
