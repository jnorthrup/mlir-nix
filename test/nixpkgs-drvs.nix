# Evaluate drvPaths of many nixpkgs attributes; used by scripts/nixpkgs-difftest.sh
{ nixpkgs ? ../.cache/nixpkgs, system ? "x86_64-linux" }:
let
  pkgs = import nixpkgs { inherit system; config = { allowUnfree = false; }; overlays = [ ]; };
  lib = pkgs.lib;
  names = [
    "hello" "curl" "git" "python3" "gcc" "openssl" "zlib" "bash" "coreutils" "perl" "nodejs"
    "rustc" "cargo" "go" "jq" "ripgrep" "fd" "bat" "neovim" "vim" "emacs" "tmux" "zsh" "fish"
    "llvmPackages.clang" "llvmPackages.llvm" "cmake" "ninja" "meson" "pkg-config" "autoconf" "automake"
    "libtool" "gnumake" "binutils" "glibc" "musl" "busybox" "systemd" "nix" "openssh" "wget"
    "sqlite" "postgresql" "redis" "nginx" "haskellPackages.aeson" "python3Packages.numpy"
    "python3Packages.requests" "ffmpeg" "imagemagick" "gtk3" "qt5.qtbase" "firefox-unwrapped"
    "linuxPackages.kernel" "docker" "kubectl" "terraform" "ocaml" "erlang" "elixir" "ruby"
    "php" "lua" "luajit" "julia" "R" "texlive.combined.scheme-small" "stdenv" "stdenvNoCC"
    "pkgsStatic.hello" "pkgsCross.aarch64-multiplatform.hello" "pkgsMusl.hello"
  ];
  get = n:
    let r = builtins.tryEval (lib.getAttrFromPath (lib.splitString "." n) pkgs).drvPath;
    in if r.success then r.value else "EVAL-FAILED";
in
map (n: "${n} ${get n}") names
