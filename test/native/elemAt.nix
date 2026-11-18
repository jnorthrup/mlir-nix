# elemAt of a list whose elements cannot fail (no checked arithmetic in them)
builtins.elemAt (builtins.genList (i: if i < 5 then i else 7) 10) 6
