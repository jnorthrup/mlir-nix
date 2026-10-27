[
  .5
  (builtins.typeOf .git/config)
  (builtins.baseNameOf .git/config)
  (builtins.typeOf ..foo/bar)
  (let a = { b = 1; }; in a.b)
  (let a = { b = 1; }; in a.b + 1)
  (let a = { b = 1; }; in a ? b)
]
