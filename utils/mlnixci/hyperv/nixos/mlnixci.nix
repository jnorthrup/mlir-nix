# mlnixci as a NixOS service: the faceted navigator of this system's own options, evaluated by mlnix.  The programs come
# from a runtime in the store (laid out by hyperv/builder/build.sh in the builder distro, with Debian's LLVM 22): they run
# on their own loader and libraries, so they are not Nix packages and this module only points at them.
{ config, lib, pkgs, ... }:
let
  cfg = config.services.mlnixci;
  rt = cfg.runtime;
in
{
  options.services.mlnixci = {
    enable = lib.mkEnableOption "mlnixci, a faceted navigator of this system's options";
    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Port mlnixci listens on.";
    };
    runtime = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/wsl/mlnixos/runtime";
      description = "A runtime in the store (runtimes/<stamp>, or the `runtime` link to one): bin/mlnixci, bin/mlnix and share/mlnixci.";
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
    systemd.services.mlnixci = {
      description = "mlnixci: the options of this system, faceted, evaluated by mlnix";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      unitConfig.ConditionPathExists = "${rt}/bin/mlnixci";
      serviceConfig = {
        ExecStart = lib.escapeShellArgs [
          "${rt}/bin/mlnixci"
          "--corpus" "${rt}/share/mlnixci/nixos/eval.nix"
          "--arg" "nixpkgs" cfg.nixpkgs
          "--arg" "configuration" cfg.configuration
          "--page" "${rt}/share/mlnixci/www/index.html"
          "--mlnix" "${rt}/bin/mlnix"
          "--port" (toString cfg.port)
        ];
        Environment = [ "NIX_PATH=nixpkgs=${cfg.nixpkgs}" ];
        Restart = "on-failure";
        RestartSec = 10;
        DynamicUser = true;
        RuntimeDirectory = "mlnixci";
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };
    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
