# mini-luci's facets of an option, in Nix.  corpus.nix puts these on every row; answer.nix (the facets asked for on
# demand) shares `resolve` and the plain-data test.
#   widget    what the page edits the option with: toggle, select, knob (an int or float type with both bounds), number,
#             text, lines, list, records (a list of submodules), sections (an attrsOf submodule: entries made, edited
#             and removed), table (a freeform attribute set: keys and values), group (a submodule, whose options are
#             rows of their own), package, json; template and readonly rows are not edited
#   range     [lo hi] that its type allows (either null when unbounded), read off the type's description: ints.between,
#             ints.u8 ... s32, port, positive, unsigned, numbers.between; a list's range is its elements'
#   crud      what an edit may do: read, update, delete (drop the what-if); sections and tables also create entries, and
#             each entry says how it is removed (answer.nix: by the module, through its `enable`, or not at all)
{ lib }:
rec {
  # The option at a doc path, descending into submodules: a path through `attrsOf (submodule ...)` carries a placeholder
  # segment (`<name>`, `*`, or the type's own) that the sub-options are not keyed by.  An entry of a freeform set
  # resolves to the set's declared sub-options (not an option): callers test lib.isOption.
  resolve = options: loc:
    let
      n = builtins.length loc;
      go = node: i:
        if node == null then null
        else if i == n then node
        else if lib.isOption node then
          let subs = node.type.getSubOptions (lib.take i loc); seg = builtins.elemAt loc i; in
          if subs ? ${seg} then go subs i else go subs (i + 1)
        else let seg = builtins.elemAt loc i; in if node ? ${seg} then go node.${seg} (i + 1) else null;
    in go options 0;

  template = loc: lib.any (s: s == "*" || lib.hasPrefix "<" s) loc;

  # Types whose values are plain data, so a value is shown without building or forcing a package.  Not `path`: a package
  # is a path, and deepSeq of one walks its whole stdenv.
  plain = [ "bool" "int" "float" "str" "string" "lines" "separatedString" "enum" "intBetween" "positiveInt" "port"
            "unsignedInt" "unsignedInt8" "unsignedInt16" "unsignedInt32" "signedInt8" "signedInt16" "signedInt32" ];
  isPlain = t: builtins.elem t.name plain || lib.hasPrefix "strMatching" t.name
    || ((t.name == "nullOr" || t.name == "listOf") && isPlain t.nestedTypes.elemType);

  relative = root: d: let s = toString d; in lib.removePrefix (root + "/") s;

  # the type under any nullOr
  inner = t: if (t.name or "") == "nullOr" then inner t.nestedTypes.elemType else t;

  range = desc:
    let b = builtins.match ".*between (-?[0-9][0-9.]*) and (-?[0-9][0-9.]*) \\(both inclusive\\).*" desc; in
    if b != null then map builtins.fromJSON b
    else if builtins.match ".*meaning >0.*" desc != null then [ 1 null ]
    else if builtins.match ".*meaning >=0.*" desc != null then [ 0 null ]
    else null;

  bounded = [ "intBetween" "unsignedInt8" "unsignedInt16" "unsignedInt32" "signedInt8" "signedInt16" "signedInt32"
              "numberBetween" ];
  numbers = [ "int" "positiveInt" "unsignedInt" "float" "number" "numberPositive" "numberNonnegative" ];
  texts = [ "str" "string" "nonEmptyStr" "singleLineStr" "passwdEntry" "kernelParam" "path" ];
  # a string type by its name: passwdEntry wraps one ("passwdEntry str")
  textual = n: builtins.elem n texts || lib.hasPrefix "strMatching" n || lib.hasPrefix "passwdEntry" n;
  scalar = n: builtins.elem n ([ "bool" "enum" ] ++ bounded ++ numbers) || textual n;

  # t: the option's type (or { name = "?"; }); desc: its description
  widget = t: desc:
    let
      i = inner t;
      n = i.name or "?";
      e = inner (i.nestedTypes.elemType or { });
      en = e.name or "?";
    in
    if n == "bool" then "toggle"
    else if n == "enum" then "select"
    else if builtins.elem n bounded then "knob"
    else if builtins.elem n numbers then "number"
    else if n == "separatedString" then (if lib.hasInfix "\"\\n\"" desc then "lines" else "text")
    else if textual n then "text"
    else if n == "listOf" then (if en == "submodule" then "records" else if scalar en then "list" else "json")
    else if n == "attrsOf" || n == "lazyAttrsOf" then (if en == "submodule" then "sections" else "table")
    # a submodule that takes undeclared attributes (freeformType) is described as the attribute set it is
    else if n == "submodule" then (if lib.hasPrefix "attribute set of" desc || lib.hasPrefix "null or attribute set of" desc
                                   then "table" else "group")
    else if n == "package" || n == "shellPackage" then "package"
    else "json";

  crud = w:
    if builtins.elem w [ "template" "readonly" "group" "package" ] then [ "read" ]
    else if w == "sections" || w == "table" then [ "create" "read" "update" "delete" ]
    else [ "read" "update" "delete" ];
}
