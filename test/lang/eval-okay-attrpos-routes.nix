# The position (file, line, column) that unsafeGetAttrPos reports for an attribute that reached its set by each route that makes or
# copies an attribute cell.  The lang suite compares it with the output of reference Nix (2.35.4).
# The file is shown by its base name, because the checkout is at a different path in the reference container.
let
  at = name: set:
    let p = builtins.unsafeGetAttrPos name set;
    in if p == null then null else { file = baseNameOf p.file; inherit (p) line column; };
  x = 1;
  src = { z = 9; };
in
{
  plain = at "b" {
    a = 1;
    b = 2;
  };
  path = at "d" { c.d = 1; };
  inheritOne = at "x" { inherit x; };
  inheritFrom = at "z" { inherit (src) z; };
  rec_ = at "b" (rec { a = 1; b = a; });
  dynamic = at "k" { ${"k"} = 1; };
  dynamicAfterStatic = at "k2" {
    a = 1;
    ${"k2"} = 2;
  };
  updateRight = at "b" ({ a = 1; } // {
    b = 2;
  });
  updateLeft = at "a" ({
    a = 1;
  } // { b = 2; });
  updateShadow = at "a" ({ a = 1; } // {
    a = 2;
  });
  listToAttrs = at "k" (builtins.listToAttrs [
    {
      name = "k";
      value = 1;
    }
  ]);
  removeAttrs = at "b" (removeAttrs {
    a = 1;
    b = 2;
  } [ "a" ]);
  intersect = at "a" (builtins.intersectAttrs { a = 1; } {
    a = 2;
    b = 3;
  });
  functionArgs = at "q" (builtins.functionArgs ({ p, q ? 1 }: p));
  functionArgsCalled = at "p" (builtins.functionArgs (
    { p, ... }: p));
  missing = at "nope" { a = 1; };
  genericAttrs = at "a" (builtins.listToAttrs (map (n: { name = n; value = 1; }) [ "a" "b" ]));
}
