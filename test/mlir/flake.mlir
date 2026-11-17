// builtins.getFlake, builtins.fetchTree and <nix/installable.nix> (lib/Corepkgs): path flakes, a lock file's graph
// with `follows`, `dir`, non-flake inputs and the installables of `nix build REF#ATTR`.  The fixtures are copied
// to a scratch directory, where @DIR@ in them names that directory; nothing here uses the network.
//
// RUN: d=$(mktemp -d); cp -R %S/inputs/flake $d/f; find $d/f -type f | while read f; do sed -i.bak "s|@DIR@|$d/f|g" $f; done; env -u NIX_REMOTE MLNIX_STORE_ROOT=$d/root mlnix eval --read-write-mode -E 'let f = builtins.getFlake "path:'$d'/f/top"; in [ f.answer f.rawText f.inputNames f.type ]' | FileCheck %s --check-prefix=UNLOCKED
// UNLOCKED: [ 42 "raw\n" [ "dep" "raw" ] "flake" ]
//
// RUN: d=$(mktemp -d); cp -R %S/inputs/flake $d/f; find $d/f -type f | while read f; do sed -i.bak "s|@DIR@|$d/f|g" $f; done; env -u NIX_REMOTE MLNIX_STORE_ROOT=$d/root mlnix eval --read-write-mode -E '(builtins.getFlake "path:'$d'/f/locked").viaInner' | FileCheck %s --check-prefix=LOCKED
// LOCKED: "dep"
//
// RUN: d=$(mktemp -d); cp -R %S/inputs/flake $d/f; env -u NIX_REMOTE MLNIX_STORE_ROOT=$d/root mlnix eval --read-write-mode -E '(builtins.getFlake "path:'$d'/f/mono?dir=sub").where' | FileCheck %s --check-prefix=DIR
// DIR: "sub"
//
// RUN: d=$(mktemp -d); cp -R %S/inputs/flake $d/f; env -u NIX_REMOTE MLNIX_STORE_ROOT=$d/root mlnix eval --read-write-mode -E 'let i = a: (import <nix/installable.nix>) ({ ref = "path:'$d'/f/pk"; } // a); in map (a: (i a).name) [ { } { attr = "tool"; } { attr = "legacy"; } { attr = "legacy.sub.deep"; } ]' | FileCheck %s --check-prefix=INSTALLABLE
// INSTALLABLE: [ "dflt-1" "tool-2" "legacy-3" "deep-4" ]
//
// The `nix` command is lib/Corepkgs/cli.nix: mlnix run under the name nix evaluates an installable.
// RUN: d=$(mktemp -d); cp -R %S/inputs/flake $d/f; ln -s $(command -v mlnix) $d/nix; env -u NIX_REMOTE MLNIX_STORE_ROOT=$d/root $d/nix eval --raw 'path:'$d'/f/pk#legacy.sub.deep.name' | FileCheck %s --check-prefix=NIX
// NIX: deep-4
//
// RUN: d=$(mktemp -d); ln -s $(command -v mlnix) $d/nix; env -u NIX_REMOTE MLNIX_STORE_ROOT=$d/root $d/nix --version | FileCheck %s --check-prefix=NIXVERSION
// NIXVERSION: nix (mlnix)
