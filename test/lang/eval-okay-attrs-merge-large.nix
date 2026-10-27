# Attribute paths that extend a set which is far into a large literal: right after the index was first built,
# and after it had to grow.
let
  s = {
    a1 = 1; a2 = 2; a3 = 3; a4 = 4; a5 = 5; a6 = 6; a7 = 7; a8 = 8; a9 = 9; a10 = 10;
    k.x = 1;
    k.y = 2;
    a11 = 11; a12 = 12; a13 = 13; a14 = 14; a15 = 15; a16 = 16; a17 = 17; a18 = 18; a19 = 19; a20 = 20; a21 = 21; a22 = 22; a23 = 23; a24 = 24; a25 = 25; a26 = 26; a27 = 27; a28 = 28; a29 = 29; a30 = 30; a31 = 31; a32 = 32; a33 = 33; a34 = 34; a35 = 35; a36 = 36; a37 = 37; a38 = 38; a39 = 39; a40 = 40; a41 = 41; a42 = 42; a43 = 43; a44 = 44; a45 = 45;
    m.p = 1;
    k.z = 3;
    m.q = 2;
    n.deep.er = 3;
    n.deep.est = 4;
  };
in [ s.k s.m s.n s.a10 s.a45 (builtins.length (builtins.attrNames s)) ]
