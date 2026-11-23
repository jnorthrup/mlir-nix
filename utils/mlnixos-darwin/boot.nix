# The darwin stdenv bootstrap as buildable attributes, oldest first:
#   bootstrapTools  stage0  stage1  xclang  stage2  stage3  stage4  stdenv  hello
# (each stageN is that stage's stdenv; stage0's coreutils is the bootstrapTools derivation, unpacked from the seed).
#   nix-build boot.nix --arg nixpkgs PATH -A bootstrapTools
{ nixpkgs, system ? "aarch64-darwin" }:
let
  pkgs = import nixpkgs { inherit system; };
  inherit (pkgs) lib;
  chain = p: n:
    [ p ] ++ (if lib.hasPrefix "bootstrap-stage0" p.stdenv.name || n >= 12 then [ ] else chain p.stdenv.__bootPackages (n + 1));
  sets = chain pkgs 0;
  named = prefix: lib.findFirst (p: lib.hasPrefix prefix p.stdenv.name) (throw "no stage ${prefix}") sets;
  stage0 = named "bootstrap-stage0";
in
{
  bootstrapTools = stage0.coreutils;
  stage0 = stage0.stdenv;
  stage1 = (named "bootstrap-stage1").stdenv;
  xclang = (named "bootstrap-stage-xclang").stdenv;
  stage2 = (named "bootstrap-stage2").stdenv;
  stage3 = (named "bootstrap-stage3").stdenv;
  stage4 = (named "bootstrap-stage4").stdenv;
  stdenv = pkgs.stdenv;
  hello = pkgs.hello;
}
