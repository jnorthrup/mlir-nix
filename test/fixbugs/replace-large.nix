builtins.stringLength (builtins.replaceStrings [ "a" ] [ "b" ] (builtins.concatStringsSep "" (builtins.genList (_: "a") 1000000)))
