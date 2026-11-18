# mini-luci as a NixOS service: the faceted navigator of this system's own options, evaluated by mlnix.  The programs come
# from the store's runtime (/mnt/wsl/mlnixos/runtime, built by the builder distro with Debian's LLVM 22): they run on their
# own loader and libraries, so they are not Nix packages and this module only points at them.
{ config, lib, pkgs, ... }:
let
  cfg = config.services.miniLuci;
  rt = cfg.runtime;
in
{
  options.services.miniLuci = {
    enable = lib.mkEnableOption "mini-luci, a faceted navigator of this system's options";
    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Port mini-luci listens on.";
    };
    runtime = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/wsl/mlnixos/runtime";
      description = "The store's runtime: bin/mini-luci, bin/mlnix and share/mini-luci.";
    };
    nixpkgs = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/wsl/mlnixos/src/nixpkgs";
      description = "The nixpkgs this system is evaluated with.";
    };
    configuration = lib.mkOption {
      type = lib.types.str;
      default = "/etc/nixos/configuration.nix";
      description = "The configuration whose options are the corpus.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.mini-luci = {
      description = "mini-luci: the options of this system, faceted, evaluated by mlnix";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      unitConfig.ConditionPathExists = "${rt}/bin/mini-luci";
      serviceConfig = {
        ExecStart = lib.escapeShellArgs [
          "${rt}/bin/mini-luci"
          "--corpus" "${rt}/share/mini-luci/nixos/eval.nix"
          "--arg" "nixpkgs" cfg.nixpkgs
          "--arg" "configuration" cfg.configuration
          "--page" "${rt}/share/mini-luci/www/index.html"
          "--mlnix" "${rt}/bin/mlnix"
          "--port" (toString cfg.port)
        ];
        Environment = [ "NIX_PATH=nixpkgs=${cfg.nixpkgs}" ];
        Restart = "on-failure";
        RestartSec = 10;
        DynamicUser = true;
        RuntimeDirectory = "mini-luci";
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };
    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
