# a list from map, held in a set and printed
{ l = builtins.map (x: x + 1) [ 1 2 ]; }
