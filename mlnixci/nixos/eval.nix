# NixOS as a corpus for mini-luci: every visible option of nixpkgs' NixOS modules (corpus.nix), evaluated for one
# configuration, with an optional what-if `overlay` (JSON) merged in as one more module at mkForce's priority.  Given a
# `request` (JSON: the facets a page asks for on demand), the same evaluation answers it instead (answer.nix).
#   configuration   a NixOS configuration (a path or a module): the live system's, as mlnixos runs it
#   settings        otherwise: a container configuration's values as JSON
{ nixpkgs, configuration ? null, settings ? ./settings.json, overlay ? null, request ? null,
  system ? builtins.currentSystem, ... }:
let
  json = f: { _file = toString f; config = builtins.fromJSON (builtins.readFile f); };
  force = v: if builtins.isAttrs v then builtins.mapAttrs (_: force) v else { _type = "override"; priority = 50; content = v; };
  # named, so that an option's adhesion (answer.nix) says which values the what-if gives
  forced = f: { _file = "mini-luci what-if"; config = force (builtins.fromJSON (builtins.readFile f)); };
  base =
    if configuration != null then [ configuration ]
    else [
      {
        boot.isContainer = true; # no bootloader, kernel or filesystems: the machine supplies them
        system.stateVersion = "25.05";
      }
      (json settings)
    ];
  nixos = import (nixpkgs + "/nixos/lib/eval-config.nix") {
    inherit system;
    modules = base ++ (if overlay == null then [ ] else [ (forced overlay) ]);
  };
  lib = import (nixpkgs + "/lib");
  # /etc entries that are text the configuration gives (not files built from packages).
  etc = lib.filterAttrs (_: x: x != null) (lib.mapAttrs (name: e:
    let r = builtins.tryEval (if e.enable && e.text != null then builtins.unsafeDiscardStringContext e.text else null); in
    if r.success then r.value else null) nixos.config.environment.etc);
in
if request == null then import ../corpus.nix { inherit lib etc; evaluated = nixos; root = toString nixpkgs; }
else import ../answer.nix {
  inherit lib overlay request;
  evaluated = nixos;
  root = toString nixpkgs;
  target = if configuration != null then toString configuration else null;
}
