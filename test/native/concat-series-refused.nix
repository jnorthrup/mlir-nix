# refused: is a list computed at run time
# (a series' cells cannot be written in place; the ++ of one is refused)
(builtins.genList (i: i) 2) ++ [ 1 ]
