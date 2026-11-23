# The darwin stdenv bootstrap's stages, newest first: each stage's stdenv (name, drvPath), and stage0's bootstrap tools
# (its coreutils is the bootstrapTools derivation).  Evaluated by mlnix in mlnixos-darwin and by real Nix on mlnixos.
#   nix-instantiate --eval --strict --json stages.nix --arg nixpkgs PATH
# The walk stops at the stage whose stdenv is named bootstrap-stage0-*: the stage before it is the raw seed, whose
# package set cannot be evaluated (booter.nix reads its missing stdenv).
{ nixpkgs, system ? "aarch64-darwin" }:
let
  pkgs = import nixpkgs { inherit system; };
  inherit (pkgs) lib;
  walk = p: n:
    let stage0 = lib.hasPrefix "bootstrap-stage0" p.stdenv.name;
    in
    [ ({ inherit n; stdenv = p.stdenv.name; drv = p.stdenv.drvPath; }
       // lib.optionalAttrs stage0 { bootstrapTools = p.coreutils.drvPath; bootstrapToolsOut = p.coreutils.outPath; }) ]
    ++ (if stage0 || n >= 12 then [ ] else walk p.stdenv.__bootPackages (n + 1));
in
walk pkgs 0
