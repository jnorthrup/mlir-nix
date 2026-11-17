{ outputs = { self }: let s = builtins.currentSystem; in {
  packages.${s} = { default = { name = "dflt-1"; }; tool = { name = "tool-2"; }; };
  legacyPackages.${s}.legacy = { name = "legacy-3"; sub.deep = { name = "deep-4"; }; };
}; }
