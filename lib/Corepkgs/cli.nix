# The `nix` command, as Nix: mlnix invoked as `nix` evaluates this on its argument vector and prints the string it
# answers.  Installables are lib/Corepkgs/installable.nix (flakes: lib/Corepkgs/flake.nix); building and
# evaluating are mlnix's own commands, reached with procExec / procRun; a profile is directories of links to
# store paths (fsMkdir, fsSymlink, fsWrite, fsRename) with a manifest.json in Nix's format.  Embedded as <nix/cli.nix>.
#
#   nix build|eval|run REF#ATTR    nix profile add|list|remove REF#ATTR    nix derivation|hash|store ...
{ args }:
let
  inherit (builtins)
    attrNames attrValues concatMap concatStringsSep deepSeq elem elemAt filter foldl' fromJSON genList getEnv
    hasAttr head isNull length mapAttrs match pathExists readDir readFile removeAttrs replaceStrings seq split
    substring tail toJSON toString;
  inherit (builtins) fsMkdir fsRename fsReadLink fsSymlink fsWrite procExec procRun procSelf storeReal;

  self = procSelf null;
  seqAll = xs: foldl' (acc: x: seq acc (seq x null)) null xs;
  hasPrefix = p: s: substring 0 (builtins.stringLength p) s == p;
  mapAttrsToList = f: set: map (n: f n set.${n}) (attrNames set);
  quote = s: replaceStrings [ "\${" ] [ "\\\${" ] (toJSON s); # a Nix string literal: JSON, with ${ not left to interpolate

  # -- the argument vector ----------------------------------------------------------------------------------------
  ignored = [ "--print-out-paths" "--impure" "--refresh" "--no-write-lock-file" "--accept-flake-config" "--quiet" "-L" "--print-build-logs" ];
  kept0 = [ "--raw" "--json" "--strict" "--show-trace" ];
  kept1 = [ "-o" "--out-link" "-I" "--store" "--system" ];
  kept2 = [ "--arg" "--argstr" ];

  parse = cmd: acc: xs:
    if xs == [ ] then acc
    else
      let a = head xs; r = tail xs; in
      if acc.dashes then parse cmd (acc // { after = acc.after ++ [ a ]; }) r
      else if a == "--" then parse cmd (acc // { dashes = true; }) r
      else if a == "--no-substitute" then parse cmd (acc // { noSubstitute = true; kept = acc.kept ++ [ a ]; }) r
      else if a == "--no-link" then parse cmd (acc // { kept = acc.kept ++ [ "--no-out-link" ]; }) r
      else if elem a ignored then parse cmd acc r
      else if elem a kept0 then parse cmd (acc // { kept = acc.kept ++ [ a ]; }) r
      else if elem a kept1 then
        (if r == [ ] then throw "${a} requires an argument" else parse cmd (acc // { kept = acc.kept ++ [ a (head r) ]; }) (tail r))
      else if elem a kept2 then
        (if length r < 2 then throw "${a} requires two arguments" else parse cmd (acc // { kept = acc.kept ++ [ a (head r) (elemAt r 1) ]; }) (tail (tail r)))
      else if a == "--expr" then
        (if r == [ ] then throw "--expr requires an argument" else parse cmd (acc // { expr = head r; }) (tail r))
      else if a == "--profile" then
        (if r == [ ] then throw "--profile requires an argument" else parse cmd (acc // { profile = head r; }) (tail r))
      else if hasPrefix "-" a && a != "-" then throw "unsupported option '${a}' for 'nix ${cmd}'"
      else parse cmd (acc // { positional = acc.positional ++ [ a ]; }) r;
  parsed = cmd: xs: parse cmd { dashes = false; after = [ ]; kept = [ ]; expr = null; profile = null; noSubstitute = false; positional = [ ]; } xs;

  # -- installables -----------------------------------------------------------------------------------------------
  installable = s: let m = match "([^#]*)#?(.*)" s; in { ref = if head m == "" then "." else head m; attr = elemAt m 1; original = s; };
  drvOf = i: (import <nix/installable.nix>) ({ inherit (i) ref; } // (if i.attr == "" then { } else { inherit (i) attr; }));
  exprOf = i: "((import <nix/installable.nix>) { ref = ${quote i.ref}; ${if i.attr == "" then "" else "attr = ${quote i.attr};"} })";
  installablesOf = p: if p.positional == [ ] then [ (installable ".") ] else map installable p.positional;
  exprArgs = p: if !isNull p.expr then [ "-E" p.expr ] else concatMap (i: [ "-E" (exprOf i) ]) (installablesOf p);

  # the substituter: caches are used unless --no-substitute; ensure fetches what a cache holds of a derivation's closure
  substituter = noSubstitute: import <nix/substitute.nix> (if noSubstitute then { caches = [ ]; } else { });

  runSelf = a:
    let r = procRun { prog = self; args = a; }; in
    if r.status == 0 then r.stdout else throw "mlnix ${head a} failed (status ${toString r.status})";
  # fetch from the caches what they hold of installable i, before it is built
  fetched = p: i: (substituter p.noSubstitute).ensure (builtins.unsafeDiscardStringContext (drvOf i).drvPath);
  lines = s: filter (l: l != "" && !builtins.isList l) (split "\n" s);

  # -- profiles ---------------------------------------------------------------------------------------------------
  home = getEnv "HOME";
  stateHome = let x = getEnv "XDG_STATE_HOME"; in if x != "" then x else "${home}/.local/state";

  profileOf = p:
    let
      dir = if isNull p.profile then "${stateHome}/nix/profiles" else builtins.dirOf p.profile;
      name = if isNull p.profile then "profile" else baseNameOf p.profile;
      current = "${dir}/${name}";
      manifest = "${current}/manifest.json";
      generations = concatMap (n: let m = match "${name}-([0-9]+)-link" n; in if isNull m then [ ] else [ (fromJSON (head m)) ])
        (if pathExists dir then attrNames (readDir dir) else [ ]);
    in
    {
      inherit dir name current;
      elements = if pathExists manifest then (fromJSON (readFile manifest)).elements else { };
      next = 1 + foldl' (a: b: if b > a then b else a) 0 generations;
    };

  mkdirs = path:
    let parts = filter (x: x != "" && !builtins.isList x) (split "/" path);
    in seqAll (genList (i: fsMkdir "/${concatStringsSep "/" (genList (j: elemAt parts j) (i + 1))}") (length parts));

  # the files below a store path as a tree of directories and links; a link to a directory is a directory
  treeOf = path:
    mapAttrs (n: t: if t == "directory" || (t == "symlink" && pathExists "${path}/${n}/.") then { dir = treeOf "${path}/${n}"; } else { link = "${path}/${n}"; })
      (readDir path);
  mergeTrees = owner: a: b:
    a // mapAttrs
      (n: nb:
        if !(a ? ${n}) then nb
        else if a.${n} ? dir && nb ? dir then { dir = mergeTrees owner a.${n}.dir nb.dir; }
        else if a.${n} ? link && nb ? link && a.${n}.link == nb.link then a.${n}
        else throw "packages conflict at '${n}' (while installing '${owner}')")
      b;
  emit = dst: tree:
    seqAll ([ (fsMkdir dst) ] ++ mapAttrsToList
      (n: node: if node ? dir then emit "${dst}/${n}" node.dir else fsSymlink { target = storeReal node.link; link = "${dst}/${n}"; })
      tree);

  # generation N+1 from the elements; the profile link is switched last, by a rename
  commit = pr: els:
    let
      gen = "${pr.dir}/${pr.name}-${toString pr.next}-link";
      tree = foldl' (acc: n: foldl' (t: p: mergeTrees n t (treeOf p)) acc els.${n}.storePaths) { } (attrNames els);
      user = "${home}/.nix-profile";
    in
    deepSeq els (seqAll [
      (mkdirs pr.dir)
      (emit gen tree)
      (fsWrite { path = "${gen}/manifest.json"; text = toJSON { version = 3; elements = els; }; })
      (fsSymlink { target = baseNameOf gen; link = "${pr.current}.${toString pr.next}.tmp"; })
      (fsRename { from = "${pr.current}.${toString pr.next}.tmp"; to = pr.current; })
      (if pr.name == "profile" && isNull (fsReadLink user) && !pathExists user then fsSymlink { target = pr.current; link = user; } else null)
    ]);

  profile = op: rest:
    let
      p = parsed "profile ${op}" rest;
      pr = profileOf p;
      elementOf = s:
        let
          i = installable s;
          d = drvOf i;
          name = d.pname or (builtins.parseDrvName d.name).name;
          built = seq (fetched p i) (lines (runSelf [ "build" "--no-out-link" "-E" (exprOf i) ]));
        in
        { inherit name; value = { active = true; attrPath = i.attr; originalUrl = s; outputs = null; priority = 5; storePaths = built; url = s; }; };
    in
    if op == "list" then
      concatStringsSep "" (mapAttrsToList
        (n: e: "Name:               ${n}\nFlake attribute:    ${e.attrPath}\nOriginal flake URL: ${e.originalUrl}\nStore paths:        ${concatStringsSep " " e.storePaths}\n\n")
        pr.elements)
    else if op == "add" || op == "install" then
      (if p.positional == [ ] then throw "'nix profile add' needs at least one installable"
      else
        let
          added = map elementOf p.positional;
          els = foldl' (acc: e: if acc ? ${e.name} then throw "package '${e.name}' is already installed; remove it first ('nix profile remove ${e.name}')" else acc // { ${e.name} = e.value; }) pr.elements added;
        in
        seq (commit pr els) "")
    else if op == "remove" || op == "uninstall" then
      (if p.positional == [ ] then throw "'nix profile remove' needs the name of an element"
      else
        let
          matches = t: n: n == t || pr.elements.${n}.originalUrl == t;
          unknown = filter (t: !(builtins.any (matches t) (attrNames pr.elements))) p.positional;
          keep = filter (n: !(builtins.any (t: matches t n) p.positional)) (attrNames pr.elements);
        in
        if unknown != [ ] then throw "no profile element matches '${head unknown}'"
        else seq (commit pr (builtins.listToAttrs (map (n: { name = n; value = pr.elements.${n}; }) keep))) "")
    else throw "'nix profile ${op}' is not supported (add, list, remove)";

  # -- the commands -----------------------------------------------------------------------------------------------
  command = cmd: rest:
    if cmd == "--version" then "nix (mlnix) 2.35.4\n"
    else if cmd == "build" then
      let p = parsed cmd rest; in seq (builtins.all (fetched p) (if isNull p.expr then installablesOf p else [ ])) (procExec { prog = self; args = [ "build" ] ++ p.kept ++ exprArgs p; })
    else if cmd == "eval" then
      let p = parsed cmd rest; in procExec { prog = self; args = [ "eval" "--read-write-mode" ] ++ p.kept ++ exprArgs p; }
    else if cmd == "run" then
      let
        p = parsed cmd rest;
        i = head (installablesOf p);
        d = drvOf i;
        out = seq (fetched p i) (head (lines (runSelf [ "build" "--no-out-link" "-E" (exprOf i) ])));
      in
      procExec { prog = "${storeReal out}/bin/${d.meta.mainProgram or d.pname or (builtins.parseDrvName d.name).name}"; args = p.after; }
    else if cmd == "profile" then
      (if rest == [ ] then throw "a subcommand of 'nix profile' is required: add, list, remove" else profile (head rest) (tail rest))
    else if cmd == "derivation" || cmd == "hash" || cmd == "store" then procExec { prog = self; args = [ cmd ] ++ rest; }
    else throw "'nix ${cmd}' is not supported by mlnix (build, eval, run, profile, derivation, hash, store)";
in
if args == [ ] then throw "a subcommand is required: build, eval, run, profile, derivation, hash, store, --version"
else command (head args) (tail args)
