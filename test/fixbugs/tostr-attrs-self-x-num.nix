builtins.toString [ { __toString = self: builtins.toString self.n; n = 42; } ]
