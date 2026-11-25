builtins.toString [ { __toString = self: self.x; x = "a"; } { __toString = self: "[" + self.y + "]"; y = "b"; } ]
