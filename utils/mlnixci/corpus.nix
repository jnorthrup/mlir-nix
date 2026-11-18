# The option corpus of an evaluated module system: one row per visible option.  Shared by the profiles (os/, nixos/).
#   evaluated   the result of lib.evalModules (or NixOS's eval-config)
#   root        declarations are shown relative to it (the nixpkgs or profile directory, as a string)
#   etc         name -> text of the files the configuration renders
# Each row carries its facets for the page (facets.nix): what it is edited with (widget), the range its type allows,
# what an edit may do (crud), and whether the running system has a counterpart (runtime, runtime.nix).  The facets the
# page asks for on demand are answer.nix's.
{ lib, evaluated, root, etc }:
let
  inherit (evaluated) config options;
  F = import ./facets.nix { inherit lib; };
  R = import ./runtime.nix { inherit lib; };
  inherit (F) isPlain template;
  resolve = F.resolve options;

  # A value is evaluated only where a module defines the option (priority above mkOptionDefault's 1500).  An option left at
  # its default shows the declared default text instead: NixOS never forces those, and some cannot be forced (a default
  # reading a package that is off), with an error tryEval does not catch.
  state = opt: let p = opt.highestPrio or 9999; in if p < 1500 then "set" else if p == 1500 then "default" else "none";
  shown = opt: loc: t:
    let r = builtins.tryEval (let v = lib.attrByPath loc null config; in builtins.deepSeq v v); in
    if isPlain t && state opt == "set" && r.success then { valueShown = true; value = r.value; }
    else { valueShown = false; value = null; };

  relative = F.relative root;

  docs = lib.filter (o: o.visible && !o.internal && lib.head o.loc != "_module") (lib.optionAttrSetToDocList options);
  row = o:
    let
      opt = resolve o.loc;
      t = if opt != null && opt ? type then opt.type else { name = "?"; };
      tmpl = template o.loc;
      v = if t.name != "?" && !tmpl then shown opt o.loc t else { valueShown = false; value = null; };
      readOnly = o.readOnly or false;
      widget = if tmpl then "template" else if readOnly then "readonly" else F.widget t (o.type or "");
    in {
      path = o.loc;
      kind = t.name or "?";
      type = o.type or "";
      choices = if (t.name or "") == "enum" then t.functor.payload.values else null;
      description = o.description or "";
      default = (o.default or { }).text or null;
      example = (o.example or { }).text or null;
      declarations = map relative (o.declarations or [ ]);
      inherit readOnly widget;
      template = tmpl;
      state = if tmpl || opt == null then "template" else state opt;
      inherit (v) value valueShown;
      range = F.range (o.type or "");
      nullable = (t.name or "") == "nullOr";
      crud = F.crud widget;
      runtime = !tmpl && R.maps o.loc;
    };
in
{
  options = map row docs;
  inherit etc;
}
