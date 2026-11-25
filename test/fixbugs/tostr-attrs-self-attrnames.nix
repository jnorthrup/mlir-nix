builtins.toString [ { __toString = self: builtins.concatStringsSep "," (builtins.attrNames self); x = "a"; } ]
