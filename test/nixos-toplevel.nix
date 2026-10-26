{ nixpkgs ? ../.cache/nixpkgs }:
(import (nixpkgs + "/nixos") {
  system = "x86_64-linux";
  configuration = {
    boot.loader.grub.device = "nodev";
    fileSystems."/".device = "/dev/sda1";
    system.stateVersion = "25.05";
    services.openssh.enable = true;
    users.users.alice = { isNormalUser = true; extraGroups = [ "wheel" ]; };
  };
}).config.system.build.toplevel.drvPath
