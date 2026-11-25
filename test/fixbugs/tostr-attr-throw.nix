builtins.toString [ { __toString = self: throw "bad ${self.x}"; x = "a"; } ]
