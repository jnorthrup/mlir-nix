# hasAttr with a known name: present, and absent
[ (builtins.hasAttr "a" { a = 1; }) (builtins.hasAttr "z" { a = 1; }) ]
