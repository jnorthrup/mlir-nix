# Flakes, in Nix: builtins.fetchTree and builtins.getFlake over the fetchers mlnix already has
# (fetchTarball, fetchGit, path).  The host supplies the bytes; the flake algebra -- references,
# the lock file's graph of nodes, follows, `self`, the outputs fixed point -- lives here, the way
# flake-compat has it.  Embedded as <nix/flake.nix> by CMake (lib/Corepkgs/Embed.cmake).
let
  inherit (builtins)
    attrNames
    concatStringsSep
    elemAt
    fromJSON
    head
    isAttrs
    isList
    isString
    length
    mapAttrs
    pathExists
    readFile
    removeAttrs
    substring
    tail
    toString
    ;

  # The default flake registry, the part of it every flake leans on.
  registry = {
    nixpkgs = { type = "github"; owner = "NixOS"; repo = "nixpkgs"; };
    home-manager = { type = "github"; owner = "nix-community"; repo = "home-manager"; };
    flake-utils = { type = "github"; owner = "numtide"; repo = "flake-utils"; };
    flake-parts = { type = "github"; owner = "hercules-ci"; repo = "flake-parts"; };
    nix = { type = "github"; owner = "NixOS"; repo = "nix"; };
  };

  # A flake reference, string or attributes, as attributes with the registry applied.
  normalize = ref:
    let a = if isString ref then builtins.parseFlakeRef ref else ref; in
    if (a.type or "") == "indirect"
    then (registry.${a.id} or (throw "cannot find flake '${a.id}' in the flake registries")) // removeAttrs a [ "id" "type" ]
    else a;

  # Days since 1970-01-01 to civil date (Hinnant), for lastModifiedDate.
  pad = w: n: let s = toString n; in if builtins.stringLength s >= w then s else pad w "0${s}";
  civil = days:
    let
      z = days + 719468;
      era = (if z >= 0 then z else z - 146096) / 146097;
      doe = z - era * 146097;
      yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
      doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
      mp = (5 * doy + 2) / 153;
      d = doy - (153 * mp + 2) / 5 + 1;
      m = if mp < 10 then mp + 3 else mp - 9;
      y = yoe + era * 400 + (if m <= 2 then 1 else 0);
    in { inherit y m d; };
  dateOf = t:
    let
      days = t / 86400;
      s = t - days * 86400;
      c = civil days;
    in "${pad 4 c.y}${pad 2 c.m}${pad 2 c.d}${pad 2 (s / 3600)}${pad 2 (s / 60 - s / 3600 * 60)}${pad 2 (s - s / 60 * 60)}";

  archiveUrl = a:
    let r = a.rev or a.ref or "HEAD"; in
    if a.type == "github" then "https://${a.host or "github.com"}/${a.owner}/${a.repo}/archive/${r}.tar.gz"
    else if a.type == "gitlab" then "https://${a.host or "gitlab.com"}/api/v4/projects/${a.owner}%2F${a.repo}/repository/archive.tar.gz?sha=${r}"
    else "https://${a.host or "git.sr.ht"}/${a.owner}/${a.repo}/archive/${r}.tar.gz";

  withHash = a: if a ? narHash then { sha256 = a.narHash; } else { };
  opt = cond: set: if cond then set else { };

  # fetchTree: the source tree of a reference, with what is known of it (rev, narHash, dates).
  fetchTree = args:
    let
      a = normalize args;
      t = a.type or (throw "attribute 'type' is missing in call to 'fetchTree'");
      fetched =
        if t == "github" || t == "gitlab" || t == "sourcehut" then
          { outPath = builtins.fetchTarball ({ url = archiveUrl a; } // withHash a); }
        else if t == "tarball" then
          { outPath = builtins.fetchTarball ({ url = a.url; } // withHash a); }
        else if t == "git" then
          let g = builtins.fetchGit ({ url = a.url; }
            // opt (a ? ref) { inherit (a) ref; }
            // opt (a ? rev) { inherit (a) rev; }
            // opt (a ? submodules) { inherit (a) submodules; }); in
          g
        else if t == "path" then
          { outPath = builtins.path { path = a.path; name = "source"; }; }
        else throw "unsupported flake input type '${t}'";
      rev = fetched.rev or a.rev or null;
      lastModified = fetched.lastModified or a.lastModified or null;
    in
    fetched
    // opt (rev != null) { inherit rev; shortRev = substring 0 7 rev; }
    // opt (a ? narHash) { inherit (a) narHash; }
    // opt (lastModified != null) { inherit lastModified; lastModifiedDate = dateOf lastModified; }
    // opt (a ? revCount) { inherit (a) revCount; };

  # An input as written in a flake's `inputs` (url, or attributes), as a reference.
  inputRef = spec: if spec ? url then spec.url else removeAttrs spec [ "flake" "inputs" "follows" ];

  # A flake from a source tree: the lock file's graph when there is one, the declared inputs otherwise.
  callFlake = sourceInfo: subdir:
    let
      outPath = sourceInfo.outPath + (if subdir == "" then "" else "/${subdir}");
      lockPath = outPath + "/flake.lock";
      lockFile = fromJSON (readFile lockPath);
      flakeFile = outPath + "/flake.nix";
      flake = import flakeFile;

      allNodes = mapAttrs
        (key: node:
          let
            isRoot = key == lockFile.root;
            src = if isRoot then sourceInfo else fetchTree (removeAttrs node.locked [ "dir" ]);
            dir = if isRoot then subdir else node.locked.dir or "";
            nodeOut = src.outPath + (if dir == "" then "" else "/${dir}");
            nodeFlake = import (nodeOut + "/flake.nix");
            inputs = mapAttrs (_: spec: allNodes.${resolveInput spec}) (node.inputs or { });
            outputs = nodeFlake.outputs (inputs // { self = result; });
            result = outputs // src // { inherit inputs outputs; sourceInfo = src; _type = "flake"; };
          in
          if node.flake or true then assert builtins.isFunction nodeFlake.outputs; result else src)
        lockFile.nodes;

      resolveInput = spec: if isList spec then byPath lockFile.root spec else spec;
      byPath = nodeName: path:
        if path == [ ] then nodeName
        else byPath
          (let spec = lockFile.nodes.${nodeName}.inputs.${head path}; in if isList spec then byPath lockFile.root spec else spec)
          (tail path);
    in
    if pathExists lockPath then allNodes.${lockFile.root}
    else if pathExists flakeFile then lockless sourceInfo outPath
    else throw "path '${toString outPath}' does not contain a 'flake.nix', searching up";

  # No lock file: fetch each declared input at its reference, unpinned (what `nix` does with --no-write-lock-file).
  lockless = sourceInfo: outPath:
    let
      flake = import (outPath + "/flake.nix");
      inputs = mapAttrs
        (_: spec:
          let a = normalize (inputRef spec); src = fetchTree a; in
          if spec.flake or true then callFlake src (a.dir or "") else src)
        (flake.inputs or { });
      outputs = flake.outputs (inputs // { self = result; });
      result = outputs // sourceInfo // { inherit inputs outputs sourceInfo; _type = "flake"; };
    in
    result;

  getFlake = ref:
    let
      a = normalize ref;
      src = fetchTree (removeAttrs a [ "dir" ]);
    in
    callFlake src (a.dir or "");
in
{
  inherit fetchTree getFlake;
}
