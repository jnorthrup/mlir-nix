# mlnixos: NixOS-WSL 2505.7.0 on nixpkgs 3ff0e34 (git checkouts in the store on Kali's disk), its configuration
# evaluated by mlnix (mlnixos-rebuild).  /etc/nixos/configuration.nix imports this file from the store's mini-luci checkout.
{ config, lib, pkgs, ... }:
{
  imports = [
    /mnt/wsl/mlnixos/src/NixOS-WSL/modules
    ./mini-luci.nix
  ];

  wsl.enable = true;
  wsl.defaultUser = "nixos";
  wsl.wslConf.network.hostname = "mlnixos";

  services.miniLuci.enable = true;
  environment.systemPackages = [ (pkgs.writeShellScriptBin "mlnixos-rebuild" (builtins.readFile ./mlnixos-rebuild.sh)) pkgs.git ];

  # WSL generates wsl-mnt-guard.service so that this distro's shutdown does not unmount /mnt/wsl in the others (the store
  # is mounted there).  It runs /bin/true and /bin/mount, which NixOS does not have: the unit failed and its guard never
  # ran.  The same commands, from the system's packages.
  systemd.services.wsl-mnt-guard = {
    overrideStrategy = "asDropin";
    serviceConfig.ExecStart = [ "" "${pkgs.coreutils}/bin/true" ];
    serviceConfig.ExecStop = [ "" "-${pkgs.util-linux}/bin/mount --make-rslave /mnt/wsl" ];
  };

  system.stateVersion = "25.05";
}
