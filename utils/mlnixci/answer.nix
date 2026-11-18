# mlnixci's facets asked for on demand.  The page asks about the options it shows; the server writes the request to a
# file and evaluates the corpus's eval.nix with `--arg request FILE` (and the what-if overlay), which answers here.  The
# request is {"ask": [{"iface": I, "path": [...]}, ...]}; the answer is {"answers": [...]} in the same order, each
# {"iface", "path", ...}, or {"iface", "path", "error"} when that one does not evaluate.
#   adhesion  where the option is declared (file, line, column) and which .nix files define its value: the files the
#             page's projection of it adheres to
#   entries   the entries of an attrsOf submodule (sections) or the keys of a freeform set (table): each one's value or
#             the sub-options a module set, the files defining it, how it is removed, and its runtime counterpart
#   live      the running system's value (runtime.nix) beside the configured one
#   module    the what-if overlay as the .nix module it would adhere as, and the file that would import it
{ lib, evaluated, root, overlay ? null, request, target ? null }:
let
  F = import ./facets.nix { inherit lib; };
  R = import ./runtime.nix { inherit lib; };
  inherit (evaluated) config options;
  req = builtins.fromJSON (builtins.readFile request);
  ov = if overlay == null then { } else builtins.fromJSON (builtins.readFile overlay);
  file = F.relative root;
  forced = v: builtins.tryEval (builtins.deepSeq v v);
  # data the page can show as it is: no function, no derivation (a store path's string is fine)
  isData = v: builtins.isString v || builtins.isInt v || builtins.isBool v || builtins.isFloat v || v == null
    || (builtins.isList v && lib.all isData v);
  shown = v: let r = forced v; in if r.success && isData r.value then r.value else null;
  configured = loc: lib.attrByPath loc null config;
  # an option's value only when its type is plain data: deepSeq of anything else may walk a package's whole closure
  shownAs = o: v: if lib.isOption o && !(F.isPlain o.type) then null else shown v;
  text = d: if builtins.isString d then d else if builtins.isAttrs d then d.text or null else null;
  defaultOf = s:
    let r = builtins.tryEval (if s ? defaultText then text s.defaultText
                              else if s ? default then lib.generators.toPretty { multiline = false; } s.default else null);
    in if r.success && (r.value == null || builtins.isString r.value) then r.value else null;

  # how an entry of a set is removed, where its module says so: a sysctl key set to null is not written
  removeBy = { "boot.kernel.sysctl" = "null"; };

  adhesion = loc:
    let o = F.resolve options loc; in
    if !(lib.isOption o) then { error = "no option at this path"; } else {
      declared = map (p: { file = file p.file; inherit (p) line column; })
        (o.declarationPositions or (map (f: { file = f; line = null; column = null; }) (o.declarations or [ ])));
      defined = map file (o.files or [ ]);
      priority = o.highestPrio or null;
      inherit target;
    };

  entries = loc:
    let
      o = F.resolve options loc;
      t = F.inner o.type;
      elem = F.inner (t.nestedTypes.elemType or { });
      sections = (elem.name or "") == "submodule";
      p = lib.concatStringsSep "." loc;
      value = let r = builtins.tryEval (configured loc); in if r.success && builtins.isAttrs r.value then r.value else { };
      subs = if sections then elem.getSubOptions (loc ++ [ "<name>" ]) else { };
      canDisable = subs ? enable;
      defs = o.definitionsWithLocations or [ ];
      definedIn = name: lib.unique (map (d: file d.file) (lib.filter (d: builtins.isAttrs d.value && d.value ? ${name}) defs));
      inOverlay = name: (lib.attrByPath loc { } ov) ? ${name};
      # the plain sub-options of an entry whose value is not the template's default: what its row shows (not texts of
      # many lines: an /etc file's text may force half the system's packages)
      plainSubs = lib.filterAttrs (k: s: k != "_module" && lib.isOption s
        && (F.isPlain s.type || F.textual (F.inner s.type).name) && (F.inner s.type).name != "separatedString") subs;
      summary = name:
        let
          v = value.${name};
          differs = k: s:
            let x = forced (v.${k} or null); d = forced (s.default or null); in
            x.success && isData x.value && x.value != null && x.value != "" && x.value != [ ]
            && !(d.success && d.value == x.value);
        in lib.mapAttrs (k: _: shown v.${k}) (lib.filterAttrs differs plainSubs);
      entry = name:
        let files = definedIn name; in {
          inherit name;
          definedIn = files;
          overlay = inOverlay name;
          remove =
            if inOverlay name && builtins.length files <= 1 then "reset"
            else if removeBy ? ${p} then removeBy.${p}
            else if sections && canDisable then "disable"
            else "none";
          enabled = if canDisable then shown (value.${name}.enable or true) else null;
          value = if sections then summary name else shown value.${name};
          live = let l = R.entry loc name; in if l == null then null else builtins.removeAttrs l [ "agree" ];
          agrees = let l = R.entry loc name; in if l == null || sections then null else agrees l value.${name};
        };
    in
    if !(lib.isOption o) then { error = "no option at this path"; } else {
      kind = if sections then "sections" else "table";
      inherit canDisable;
      # the sub-options a new entry is made with: name, type and default, as the form for it
      form = lib.mapAttrsToList (k: s: { name = k; kind = s.type.name; type = s.type.description;
        widget = F.widget s.type s.type.description; range = F.range s.type.description;
        choices = if (F.inner s.type).name == "enum" then (F.inner s.type).functor.payload.values or null else null;
        default = defaultOf s; description = text (s.description or "") ; })
        (lib.filterAttrs (k: s: !(s.internal or false) && (s.visible or true) != false) plainSubs);
      entries = map entry (builtins.attrNames value);
    };

  # whether the running system agrees with the configured value, as the mapping means it (runtime.nix agree)
  agrees = r: c: if !(r ? agree) then null else let x = forced (r.agree c); in if x.success then x.value else null;
  live = loc:
    let r = R.rule loc; o = F.resolve options loc; c = configured loc; in
    if r == null then { error = "no runtime mapping"; } else
    builtins.removeAttrs r [ "agree" ] // {
      configured = if r.perEntry or false then null else shownAs o c;
      agrees = if r.perEntry or false then null else agrees r c;
    };

  leaves = p: v: if builtins.isAttrs v then lib.concatLists (lib.mapAttrsToList (k: leaves (p ++ [ k ])) v)
    else [ { path = p; value = v; } ];
  module = _:
    let ls = leaves [ ] ov; in {
      inherit target;
      count = builtins.length ls;
      text = "# mlnixci's what-if as a module, each value at mkForce as it was evaluated; it adheres where "
        + (if target == null then "the configuration" else target) + " imports it (imports = [ ./luci.nix ];)\n"
        + "{ lib, ... }:\n{\n"
        + lib.concatMapStrings (l: "  ${lib.showAttrPath l.path} = lib.mkForce ${lib.generators.toPretty { multiline = false; } l.value};\n") ls
        + "}\n";
    };

  ifaces = { inherit adhesion entries live module; };
  one = a:
    let
      iface = if builtins.isAttrs a then a.iface or null else null;
      path = if builtins.isAttrs a then a.path or [ ] else [ ];
      ok = builtins.isString iface && builtins.isList path && lib.all builtins.isString path;
      f = if ok then ifaces.${iface} or null else null;
      v = f path;
      r = forced v;
    in
    { iface = if ok then iface else null; path = if ok then path else [ ]; }
    // (if !ok then { error = "an ask is {\"iface\": string, \"path\": [string, ...]}"; }
        else if f == null then { error = "no facet " + iface; }
        else if r.success then r.value
        else { error = "this facet does not evaluate here"; });
in
{ answers = map one (if builtins.isList (req.ask or null) then req.ask else [ ]); }
