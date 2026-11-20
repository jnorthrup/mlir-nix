// Flake references and the UTF-8 check hollowed out of lib/Eval/Formats.cpp into the TrikeShed dialect:
// percentDecode, percentEncode (with its keep sets), parseQuery, isHexRev, putFlakeAttr's typing, parseFlakeRef,
// flakeRefToString and checkUTF8.  Lowered by --trikeshed-lower-cursors and the stock buffer pipeline
// (lib/CMakeLists.txt mlnix_lower_trikeshed) into NixEval.
//
// What stays C++ (Formats.cpp's bridges): forcing the argument and each attribute (Nix's error order), the throws with
// their exact wording, BindingsBuilder/mkString/mkInt/mkBool/mkAttrs (the evaluator's values), canonPath + getcwd for
// a relative path (a callback), and the room the entries write into.
//
//   nixev_ts_utf8_bad(p, n)                       the index toJSON reports as invalid UTF-8, or -1
//   nixev_ts_flake_parse(ctx, p, n, out, cap, recs) parseFlakeRef: records (name, value, kind) over bytes in out
//   nixev_ts_flake_unparse(ents, n, into, cap)    flakeRefToString: the reference's text drained into `into`
//
// The splits are trikeshed.parts (Series.div: the query at '&', github's owner/repo/rev at '/', and every "first
// '?' / '#' / ':' / '=' / '+' / '/'" as the length of the first part); words are slices of one constant blob compared
// unsigned (trikeshed.compare, Text ==); the parameters are a trikeshed.sorted series of row indices ordered by key
// (stable, so the SortedMap's last-assignment-wins is the last row of each run); isHexRev is a fold; the unparsed text
// is ONE trikeshed.combine of the head's pieces and a combineAll of the remaining attributes, each byte encoded as a
// slice of a 256 x 4 table (the byte itself, then "%XY") chosen by a keep-set bit, drained once.
//
// Word ids (fr_blob / fr_off / fr_len):
//   0 github  1 gitlab  2 sourcehut  3 path  4 git+  5 hg+  6 tarball+  7 file+
//   8 http  9 https  10 file  11 flake  12 mercurial  13 tarball  14 indirect  15 type
//   16 owner  17 repo  18 url  19 id  20 rev  21 ref  22 dir  23 narHash
//   24 revCount  25 lastModified  26 submodules  27 shallow  28 allRefs  29 exportIgnore  30 lfs  31 verifyCommit
//   32 true  33 1  34 .zip  35 .tar  36 .tgz  37 .tar.gz  38 .tar.xz  39 .tar.bz2
//   40 .tar.zst  41 hg  42 git  43 ?  44 &  45 =  46 :  47 /
//   48 +
//
// Helper names are module-unique (fr_*): convert-func-to-llvm exports a func.func private as a global symbol.
!s = !trikeshed.series<i8>
!s32 = !trikeshed.series<i32>
!s64 = !trikeshed.series<i64>
!tp = !trikeshed.twinpacked<i32>
!sp = !trikeshed.series<!tp>
!m = memref<?xi8, strided<[1], offset: ?>>
!m64 = memref<?xi64, strided<[1], offset: ?>>
!pm = memref<?xi64>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

memref.global "private" constant @fr_blob : memref<250xi8> = dense<"0x6769746875626769746C6162736F75726365687574706174686769742B68672B74617262616C6C2B66696C652B68747470687474707366696C65666C616B656D657263757269616C74617262616C6C696E646972656374747970656F776E65727265706F75726C69647265767265666469726E617248617368726576436F756E746C6173744D6F6469666965647375626D6F64756C65737368616C6C6F77616C6C526566736578706F727449676E6F72656C6673766572696679436F6D6D697474727565312E7A69702E7461722E74677A2E7461722E677A2E7461722E787A2E7461722E627A322E7461722E7A737468676769743F263D3A2F2B">
memref.global "private" constant @fr_off : memref<49xi32> = dense<[0, 6, 12, 21, 25, 29, 32, 40, 45, 49, 54, 58, 63, 72, 79, 87, 91, 96, 100, 103, 105, 108, 111, 114, 121, 129, 141, 151, 158, 165, 177, 180, 192, 196, 197, 201, 205, 209, 216, 223, 231, 239, 241, 244, 245, 246, 247, 248, 249]>
memref.global "private" constant @fr_len : memref<49xi32> = dense<[6, 6, 9, 4, 4, 3, 8, 5, 4, 5, 4, 5, 9, 7, 8, 4, 5, 4, 3, 2, 3, 3, 3, 7, 8, 12, 10, 7, 7, 12, 3, 12, 4, 1, 4, 4, 4, 7, 7, 8, 8, 2, 3, 1, 1, 1, 1, 1, 1]>
memref.global "private" constant @fr_enc : memref<1024xi8> = dense<"0x002530300125303102253032032530330425303405253035062530360725303708253038092530390A2530410B2530420C2530430D2530440E2530450F253046102531301125313112253132132531331425313415253135162531361725313718253138192531391A2531411B2531421C2531431D2531441E2531451F253146202532302125323122253232232532332425323425253235262532362725323728253238292532392A2532412B2532422C2532432D2532442E2532452F253246302533303125333132253332332533333425333435253335362533363725333738253338392533393A2533413B2533423C2533433D2533443E2533453F253346402534304125343142253432432534334425343445253435462534364725343748253438492534394A2534414B2534424C2534434D2534444E2534454F253446502535305125353152253532532535335425353455253535562535365725353758253538592535395A2535415B2535425C2535435D2535445E2535455F253546602536306125363162253632632536336425363465253635662536366725363768253638692536396A2536416B2536426C2536436D2536446E2536456F253646702537307125373172253732732537337425373475253735762537367725373778253738792537397A2537417B2537427C2537437D2537447E2537457F253746802538308125383182253832832538338425383485253835862538368725383788253838892538398A2538418B2538428C2538438D2538448E2538458F253846902539309125393192253932932539339425393495253935962539369725393798253938992539399A2539419B2539429C2539439D2539449E2539459F253946A0254130A1254131A2254132A3254133A4254134A5254135A6254136A7254137A8254138A9254139AA254141AB254142AC254143AD254144AE254145AF254146B0254230B1254231B2254232B3254233B4254234B5254235B6254236B7254237B8254238B9254239BA254241BB254242BC254243BD254244BE254245BF254246C0254330C1254331C2254332C3254333C4254334C5254335C6254336C7254337C8254338C9254339CA254341CB254342CC254343CD254344CE254345CF254346D0254430D1254431D2254432D3254433D4254434D5254435D6254436D7254437D8254438D9254439DA254441DB254442DC254443DD254444DE254445DF254446E0254530E1254531E2254532E3254533E4254534E5254535E6254536E7254537E8254538E9254539EA254541EB254542EC254543ED254544EE254545EF254546F0254630F1254631F2254632F3254633F4254634F5254635F6254636F7254637F8254638F9254639FA254641FB254642FC254643FD254644FE254645FF254646">
memref.global "private" constant @fr_keep : memref<256xi8> = dense<"0x07000000000000000000000000000000000000000000000000000000000000000001000001000001010101010107070507070707070707070707050100010000010707070707070707070707070707070707070707070707070707000000000700070707070707070707070707070707070707070707070707070700000007000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000">
memref.global "private" constant @fr_pow : memref<19xi64> = dense<[1, 10, 100, 1000, 10000, 100000, 1000000, 10000000, 100000000, 1000000000, 10000000000, 100000000000, 1000000000000, 10000000000000, 100000000000000, 1000000000000000, 10000000000000000, 100000000000000000, 1000000000000000000]>

// canonPath(cwd + '/' + the n bytes at p), kept by the bridge in ctx: its bytes, the count through the i64 slot
func.func private @nixev_flake_canon(!llvm.ptr, !llvm.ptr, i64, !llvm.ptr) -> !llvm.ptr

// the descriptor of n cells at p (i8 and i64 cells share the struct)
func.func private @fr_desc(%p: !llvm.ptr, %n: i64) -> !d {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %u = llvm.mlir.undef : !d
  %a = llvm.insertvalue %p, %u[0] : !d
  %b = llvm.insertvalue %p, %a[1] : !d
  %c = llvm.insertvalue %c0, %b[2] : !d
  %e = llvm.insertvalue %n, %c[3, 0] : !d
  %f = llvm.insertvalue %c1, %e[4, 0] : !d
  return %f : !d
}

//===----------------------------------------------------------------------===//
// checkUTF8
//===----------------------------------------------------------------------===//

// the index of the byte toJSON reports as invalid UTF-8 in the n bytes at p, or -1 when they are valid.  A lead byte's
// class gives the sequence length (0 for a stray continuation or 0xf8..0xff); the sequence is bad when it has no length,
// runs past the end, or a byte after the lead is not 10xxxxxx -- and then the bad byte is the first such byte that is
// there, else the lead.
func.func @nixev_ts_utf8_bad(%p: !llvm.ptr, %n: i64) -> i64 {
  %z = arith.constant 0 : index
  %one = arith.constant 1 : index
  %two = arith.constant 2 : index
  %three = arith.constant 3 : index
  %four = arith.constant 4 : index
  %m1 = arith.constant -1 : i64
  %z64 = arith.constant 0 : i64
  %x80 = arith.constant -128 : i8
  %k6 = arith.constant 6 : i8
  %k14 = arith.constant 14 : i8
  %k30 = arith.constant 30 : i8
  %k2 = arith.constant 2 : i8
  %k5 = arith.constant 5 : i8
  %k4 = arith.constant 4 : i8
  %k3 = arith.constant 3 : i8
  %true = arith.constant true
  %dd = func.call @fr_desc(%p, %n) : (!llvm.ptr, i64) -> !d
  %dm = builtin.unrealized_conversion_cast %dd : !d to !m
  %xs = builtin.unrealized_conversion_cast %dm : !m to !s
  %ni = arith.index_cast %n : i64 to index
  %r:2 = scf.while (%i = %z, %bad = %m1) : (index, i64) -> (index, i64) {
    %in = arith.cmpi ult, %i, %ni : index
    %none = arith.cmpi slt, %bad, %z64 : i64
    %go = arith.andi %in, %none : i1
    scf.condition(%go) %i, %bad : index, i64
  } do {
  ^bb0(%i: index, %bad: i64):
    %c = trikeshed.at %xs[%i] : !s, index -> i8
    %ascii = arith.cmpi ult, %c, %x80 : i8
    %h5 = arith.shrui %c, %k5 : i8
    %h4 = arith.shrui %c, %k4 : i8
    %h3 = arith.shrui %c, %k3 : i8
    %is2 = arith.cmpi eq, %h5, %k6 : i8
    %is3 = arith.cmpi eq, %h4, %k14 : i8
    %is4 = arith.cmpi eq, %h3, %k30 : i8
    %l4 = arith.select %is4, %four, %z : index
    %l3 = arith.select %is3, %three, %l4 : index
    %l2 = arith.select %is2, %two, %l3 : index
    %len = arith.select %ascii, %one, %l2 : index
    %end = arith.addi %i, %len : index
    %has = arith.cmpi ne, %len, %z : index
    %inside = arith.cmpi ule, %end, %ni : index
    %fits = arith.andi %has, %inside : i1
    %fb = scf.for %k = %one to %len step %one iter_args(%f = %z) -> (index) {
      %ik = arith.addi %i, %k : index
      %inr = arith.cmpi ult, %ik, %ni : index
      %cont = scf.if %inr -> (i1) {
        %b = trikeshed.at %xs[%ik] : !s, index -> i8
        %b6 = arith.shrui %b, %k6 : i8
        %iscont = arith.cmpi eq, %b6, %k2 : i8
        scf.yield %iscont : i1
      } else {
        scf.yield %true : i1
      }
      %notcont = arith.xori %cont, %true : i1
      %unset = arith.cmpi eq, %f, %z : index
      %h1 = arith.andi %unset, %notcont : i1
      %f2 = arith.select %h1, %k, %f : index
      scf.yield %f2 : index
    }
    %clean = arith.cmpi eq, %fb, %z : index
    %ok = arith.andi %fits, %clean : i1
    %multi = arith.cmpi ugt, %len, %one : index
    %found = arith.cmpi ne, %fb, %z : index
    %atk = arith.andi %multi, %found : i1
    %ifb = arith.addi %i, %fb : index
    %bpos = arith.select %atk, %ifb, %i : index
    %bpos64 = arith.index_cast %bpos : index to i64
    %bad2 = arith.select %ok, %m1, %bpos64 : i64
    scf.yield %end, %bad2 : index, i64
  }
  return %r#1 : i64
}

//===----------------------------------------------------------------------===//
// shared text helpers (module-unique fr_* names: convert-func-to-llvm exports them)
//===----------------------------------------------------------------------===//

// the first index in [from, to) holding byte c, else to: the length of the first part of Series.div at c
func.func private @fr_find(%xs: !s, %from: index, %to: index, %c: i8) -> index {
  %z = arith.constant 0 : index
  %len = arith.subi %to, %from : index
  %sl = trikeshed.slice %xs[%from, %len] : !s -> !s
  %ps = trikeshed.parts %sl, %c : !s, i8 -> !sp
  %p0 = trikeshed.at %ps[%z] : !sp, index -> !tp
  %l = trikeshed.second %p0 : !tp -> i32
  %li = arith.index_cast %l : i32 to index
  %r = arith.addi %from, %li : index
  return %r : index
}

// the (start, length) of word id in the blob
func.func private @fr_word(%id: index) -> (index, index) {
  %og = memref.get_global @fr_off : memref<49xi32>
  %offs = trikeshed.text %og : memref<49xi32> -> !s32
  %lg = memref.get_global @fr_len : memref<49xi32>
  %lens = trikeshed.text %lg : memref<49xi32> -> !s32
  %o = trikeshed.at %offs[%id] : !s32, index -> i32
  %l = trikeshed.at %lens[%id] : !s32, index -> i32
  %oi = arith.index_cast %o : i32 to index
  %li = arith.index_cast %l : i32 to index
  return %oi, %li : index, index
}

// whether the len bytes of xs at from are word id (compared unsigned, as Text ==)
func.func private @fr_is(%xs: !s, %from: index, %len: index, %id: index) -> i1 {
  %false = arith.constant false
  %w:2 = func.call @fr_word(%id) : (index) -> (index, index)
  %eqlen = arith.cmpi eq, %len, %w#1 : index
  %r = scf.if %eqlen -> (i1) {
    %g = memref.get_global @fr_blob : memref<250xi8>
    %b = trikeshed.text %g : memref<250xi8> -> !s
    %wd = trikeshed.slice %b[%w#0, %w#1] : !s -> !s
    %x = trikeshed.slice %xs[%from, %len] : !s -> !s
    %c = trikeshed.compare %x, %wd unsigned : !s, !s
    %z32 = arith.constant 0 : i32
    %e = arith.cmpi eq, %c, %z32 : i32
    scf.yield %e : i1
  } else {
    scf.yield %false : i1
  }
  return %r : i1
}

// whether the len bytes at from start with word id
func.func private @fr_prefix(%xs: !s, %from: index, %len: index, %id: index) -> i1 {
  %false = arith.constant false
  %w:2 = func.call @fr_word(%id) : (index) -> (index, index)
  %fits = arith.cmpi ule, %w#1, %len : index
  %r = scf.if %fits -> (i1) {
    %e = func.call @fr_is(%xs, %from, %w#1, %id) : (!s, index, index, index) -> i1
    scf.yield %e : i1
  } else {
    scf.yield %false : i1
  }
  return %r : i1
}

// whether the len bytes at from end with word id
func.func private @fr_suffix(%xs: !s, %from: index, %len: index, %id: index) -> i1 {
  %false = arith.constant false
  %w:2 = func.call @fr_word(%id) : (index) -> (index, index)
  %fits = arith.cmpi ule, %w#1, %len : index
  %r = scf.if %fits -> (i1) {
    %end = arith.addi %from, %len : index
    %at = arith.subi %end, %w#1 : index
    %e = func.call @fr_is(%xs, %at, %w#1, %id) : (!s, index, index, index) -> i1
    scf.yield %e : i1
  } else {
    scf.yield %false : i1
  }
  return %r : i1
}

// whether the len bytes at from are one of the words lo ..= hi
func.func private @fr_in(%xs: !s, %from: index, %len: index, %lo: index, %hi: index) -> i1 {
  %false = arith.constant false
  %one = arith.constant 1 : index
  %end = arith.addi %hi, %one : index
  %r = scf.for %id = %lo to %end step %one iter_args(%acc = %false) -> (i1) {
    %e = func.call @fr_is(%xs, %from, %len, %id) : (!s, index, index, index) -> i1
    %a2 = arith.ori %acc, %e : i1
    scf.yield %a2 : i1
  }
  return %r : i1
}

// isDigitIn(c, 16): 0-9, a-f, A-F (a byte past 0x7f is none)
func.func private @fr_hexd(%c: i8) -> i1 {
  %c0 = arith.constant 48 : i8
  %c9 = arith.constant 57 : i8
  %ca = arith.constant 97 : i8
  %cf = arith.constant 102 : i8
  %cA = arith.constant 65 : i8
  %cF = arith.constant 70 : i8
  %a1 = arith.cmpi uge, %c, %c0 : i8
  %a2 = arith.cmpi ule, %c, %c9 : i8
  %d = arith.andi %a1, %a2 : i1
  %b1 = arith.cmpi uge, %c, %ca : i8
  %b2 = arith.cmpi ule, %c, %cf : i8
  %l = arith.andi %b1, %b2 : i1
  %u1 = arith.cmpi uge, %c, %cA : i8
  %u2 = arith.cmpi ule, %c, %cF : i8
  %u = arith.andi %u1, %u2 : i1
  %dl = arith.ori %d, %l : i1
  %r = arith.ori %dl, %u : i1
  return %r : i1
}

// a hex digit's value (digitValue)
func.func private @fr_hexv(%c: i8) -> i8 {
  %c0 = arith.constant 48 : i8
  %c9 = arith.constant 57 : i8
  %ca = arith.constant 97 : i8
  %cA = arith.constant 65 : i8
  %ten = arith.constant 10 : i8
  %isd = arith.cmpi ule, %c, %c9 : i8
  %islow = arith.cmpi uge, %c, %ca : i8
  %vd = arith.subi %c, %c0 : i8
  %vl0 = arith.subi %c, %ca : i8
  %vl = arith.addi %vl0, %ten : i8
  %vu0 = arith.subi %c, %cA : i8
  %vu = arith.addi %vu0, %ten : i8
  %va = arith.select %islow, %vl, %vu : i8
  %r = arith.select %isd, %vd, %va : i8
  return %r : i8
}

// isHexRev: exactly 40 hex digits (a fold over the slice)
func.func private @fr_hexrev(%xs: !s, %from: index, %len: index) -> i1 {
  %false = arith.constant false
  %true = arith.constant true
  %forty = arith.constant 40 : index
  %is40 = arith.cmpi eq, %len, %forty : index
  %r = scf.if %is40 -> (i1) {
    %sl = trikeshed.slice %xs[%from, %len] : !s -> !s
    %all = trikeshed.fold %sl, %true : !s, i1 -> i1 {
    ^bb0(%acc: i1, %c: i8):
      %h = func.call @fr_hexd(%c) : (i8) -> i1
      %a2 = arith.andi %acc, %h : i1
      trikeshed.yield %a2 : i1
    }
    scf.yield %all : i1
  } else {
    scf.yield %false : i1
  }
  return %r : i1
}

// percentDecode of xs[from, to) written at `at` in out; returns the end.  "%XY" (two hex digits, both before `to`)
// is the byte 0xXY, anything else is itself.
func.func private @fr_decode(%xs: !s, %from: index, %to: index, %om: !m, %at: index) -> index {
  %one = arith.constant 1 : index
  %two = arith.constant 2 : index
  %three = arith.constant 3 : index
  %pc = arith.constant 37 : i8
  %sixteen = arith.constant 16 : i8
  %false = arith.constant false
  %r:2 = scf.while (%i = %from, %w = %at) : (index, index) -> (index, index) {
    %go = arith.cmpi ult, %i, %to : index
    scf.condition(%go) %i, %w : index, index
  } do {
  ^bb0(%i: index, %w: index):
    %ch = trikeshed.at %xs[%i] : !s, index -> i8
    %ispc = arith.cmpi eq, %ch, %pc : i8
    %i2 = arith.addi %i, %two : index
    %room = arith.cmpi ult, %i2, %to : index
    %cand = arith.andi %ispc, %room : i1
    %v:2 = scf.if %cand -> (i1, i8) {
      %i1 = arith.addi %i, %one : index
      %a = trikeshed.at %xs[%i1] : !s, index -> i8
      %b = trikeshed.at %xs[%i2] : !s, index -> i8
      %ha = func.call @fr_hexd(%a) : (i8) -> i1
      %hb = func.call @fr_hexd(%b) : (i8) -> i1
      %both = arith.andi %ha, %hb : i1
      %va = func.call @fr_hexv(%a) : (i8) -> i8
      %vb = func.call @fr_hexv(%b) : (i8) -> i8
      %hi = arith.muli %va, %sixteen : i8
      %byte = arith.addi %hi, %vb : i8
      scf.yield %both, %byte : i1, i8
    } else {
      scf.yield %false, %ch : i1, i8
    }
    %out = arith.select %v#0, %v#1, %ch : i8
    memref.store %out, %om[%w] : !m
    %adv = arith.select %v#0, %three, %one : index
    %in = arith.addi %i, %adv : index
    %w2 = arith.addi %w, %one : index
    scf.yield %in, %w2 : index, index
  }
  return %r#1 : index
}

// the len bytes of xs at from drained at `at` in out; returns the end
func.func private @fr_copy(%xs: !s, %from: index, %len: index, %om: !m, %at: index) -> index {
  %sl = trikeshed.slice %xs[%from, %len] : !s -> !s
  %cells = memref.subview %om[%at] [%len] [1] : !m to !m
  %e = trikeshed.drain %sl, %cells : !s, !m -> index
  %r = arith.addi %at, %len : index
  return %r : index
}

// word id drained at `at` in out; returns the end
func.func private @fr_putw(%id: index, %om: !m, %at: index) -> index {
  %g = memref.get_global @fr_blob : memref<250xi8>
  %b = trikeshed.text %g : memref<250xi8> -> !s
  %w:2 = func.call @fr_word(%id) : (index) -> (index, index)
  %r = func.call @fr_copy(%b, %w#0, %w#1, %om, %at) : (!s, index, index, !m, index) -> index
  return %r : index
}

// record k (6 words: name off, name len, value off, value len, kind 0 string / 1 int / 2 bool, the int or bool)
func.func private @fr_rec(%recs: !m64, %k: index, %no: index, %nl: index, %vo: index, %vl: index, %kind: i64, %iv: i64) -> index {
  %one = arith.constant 1 : index
  %six = arith.constant 6 : index
  %b = arith.muli %k, %six : index
  %no64 = arith.index_cast %no : index to i64
  %nl64 = arith.index_cast %nl : index to i64
  %vo64 = arith.index_cast %vo : index to i64
  %vl64 = arith.index_cast %vl : index to i64
  %b1 = arith.addi %b, %one : index
  %b2 = arith.addi %b1, %one : index
  %b3 = arith.addi %b2, %one : index
  %b4 = arith.addi %b3, %one : index
  %b5 = arith.addi %b4, %one : index
  memref.store %no64, %recs[%b] : !m64
  memref.store %nl64, %recs[%b1] : !m64
  memref.store %vo64, %recs[%b2] : !m64
  memref.store %vl64, %recs[%b3] : !m64
  memref.store %kind, %recs[%b4] : !m64
  memref.store %iv, %recs[%b5] : !m64
  %r = arith.addi %k, %one : index
  return %r : index
}

// readInteger<10, signed>: blanks skipped, one sign, the digits saturating at 2^63 - 1 (2^63 negative); 0 when none
func.func private @fr_int(%xs: !s, %from: index, %len: index) -> i64 {
  %one = arith.constant 1 : index
  %z64 = arith.constant 0 : i64
  %ten = arith.constant 10 : i64
  %max = arith.constant 9223372036854775807 : i64
  %min = arith.constant -9223372036854775808 : i64
  %sp = arith.constant 32 : i8
  %c9 = arith.constant 9 : i8
  %c13 = arith.constant 13 : i8
  %plus = arith.constant 43 : i8
  %minus = arith.constant 45 : i8
  %d0 = arith.constant 48 : i8
  %d9 = arith.constant 57 : i8
  %false = arith.constant false
  %true = arith.constant true
  %end = arith.addi %from, %len : index
  %ws = scf.while (%i = %from) : (index) -> (index) {
    %in = arith.cmpi ult, %i, %end : index
    %blank = scf.if %in -> (i1) {
      %c = trikeshed.at %xs[%i] : !s, index -> i8
      %isp = arith.cmpi eq, %c, %sp : i8
      %ge = arith.cmpi uge, %c, %c9 : i8
      %le = arith.cmpi ule, %c, %c13 : i8
      %ctl = arith.andi %ge, %le : i1
      %b = arith.ori %isp, %ctl : i1
      scf.yield %b : i1
    } else {
      scf.yield %false : i1
    }
    scf.condition(%blank) %i : index
  } do {
  ^bb0(%i: index):
    %i2 = arith.addi %i, %one : index
    scf.yield %i2 : index
  }
  %more = arith.cmpi ult, %ws, %end : index
  %sg:2 = scf.if %more -> (index, i1) {
    %c = trikeshed.at %xs[%ws] : !s, index -> i8
    %isp = arith.cmpi eq, %c, %plus : i8
    %ism = arith.cmpi eq, %c, %minus : i8
    %signed = arith.ori %isp, %ism : i1
    %next = arith.addi %ws, %one : index
    %at = arith.select %signed, %next, %ws : index
    scf.yield %at, %ism : index, i1
  } else {
    scf.yield %ws, %false : index, i1
  }
  %limit = arith.select %sg#1, %min, %max : i64
  %acc:4 = scf.while (%i = %sg#0, %v = %z64, %over = %false, %nd = %false) : (index, i64, i1, i1) -> (index, i64, i1, i1) {
    %in = arith.cmpi ult, %i, %end : index
    %dig = scf.if %in -> (i1) {
      %c = trikeshed.at %xs[%i] : !s, index -> i8
      %ge = arith.cmpi uge, %c, %d0 : i8
      %le = arith.cmpi ule, %c, %d9 : i8
      %isd = arith.andi %ge, %le : i1
      scf.yield %isd : i1
    } else {
      scf.yield %false : i1
    }
    scf.condition(%dig) %i, %v, %over, %nd : index, i64, i1, i1
  } do {
  ^bb0(%i: index, %v: i64, %over: i1, %nd: i1):
    %c = trikeshed.at %xs[%i] : !s, index -> i8
    %d8 = arith.subi %c, %d0 : i8
    %d = arith.extui %d8 : i8 to i64
    %room = arith.subi %limit, %d : i64
    %cut = arith.divui %room, %ten : i64
    %past = arith.cmpi ugt, %v, %cut : i64
    %o2 = arith.ori %over, %past : i1
    %m = arith.muli %v, %ten : i64
    %v1 = arith.addi %m, %d : i64
    %v2 = arith.select %o2, %limit, %v1 : i64
    %i2 = arith.addi %i, %one : index
    scf.yield %i2, %v2, %o2, %true : index, i64, i1, i1
  }
  %negv = arith.subi %z64, %acc#1 : i64
  %nonover = arith.xori %acc#2, %true : i1
  %negok = arith.andi %sg#1, %nonover : i1
  %neg2 = arith.select %sg#1, %min, %acc#1 : i64
  %val = arith.select %negok, %negv, %neg2 : i64
  %r = arith.select %acc#3, %val, %z64 : i64
  return %r : i64
}

// putFlakeAttr's typing: revCount / lastModified an int read from the value, the six flags a bool ("1" or "true"),
// any other name a string
func.func private @fr_attr(%os: !s, %recs: !m64, %k: index, %ko: index, %kl: index, %vo: index, %vl: index) -> index {
  %w24 = arith.constant 24 : index
  %w25 = arith.constant 25 : index
  %w26 = arith.constant 26 : index
  %w31 = arith.constant 31 : index
  %w32 = arith.constant 32 : index
  %w33 = arith.constant 33 : index
  %z64 = arith.constant 0 : i64
  %one64 = arith.constant 1 : i64
  %two64 = arith.constant 2 : i64
  %isint = func.call @fr_in(%os, %ko, %kl, %w24, %w25) : (!s, index, index, index, index) -> i1
  %isbool = func.call @fr_in(%os, %ko, %kl, %w26, %w31) : (!s, index, index, index, index) -> i1
  %iv = scf.if %isint -> (i64) {
    %x = func.call @fr_int(%os, %vo, %vl) : (!s, index, index) -> i64
    scf.yield %x : i64
  } else {
    %b = scf.if %isbool -> (i64) {
      %is1 = func.call @fr_is(%os, %vo, %vl, %w33) : (!s, index, index, index) -> i1
      %ist = func.call @fr_is(%os, %vo, %vl, %w32) : (!s, index, index, index) -> i1
      %t = arith.ori %is1, %ist : i1
      %t64 = arith.extui %t : i1 to i64
      scf.yield %t64 : i64
    } else {
      scf.yield %z64 : i64
    }
    scf.yield %b : i64
  }
  %kb = arith.select %isbool, %two64, %z64 : i64
  %kind = arith.select %isint, %one64, %kb : i64
  %r = func.call @fr_rec(%recs, %k, %ko, %kl, %vo, %vl, %kind, %iv) : (!m64, index, index, index, index, index, i64, i64) -> index
  return %r : index
}

// a query parameter (key off, len, value off, len in out) as row np of pm; returns np + 1
func.func private @fr_padd(%pm: !pm, %np: index, %ko: index, %kl: index, %vo: index, %vl: index) -> index {
  %one = arith.constant 1 : index
  %four = arith.constant 4 : index
  %b = arith.muli %np, %four : index
  %b1 = arith.addi %b, %one : index
  %b2 = arith.addi %b1, %one : index
  %b3 = arith.addi %b2, %one : index
  %ko64 = arith.index_cast %ko : index to i64
  %kl64 = arith.index_cast %kl : index to i64
  %vo64 = arith.index_cast %vo : index to i64
  %vl64 = arith.index_cast %vl : index to i64
  memref.store %ko64, %pm[%b] : !pm
  memref.store %kl64, %pm[%b1] : !pm
  memref.store %vo64, %pm[%b2] : !pm
  memref.store %vl64, %pm[%b3] : !pm
  %r = arith.addi %np, %one : index
  return %r : index
}

// parseQuery: the parts of xs[qs, qe) at '&' (Series.div); "k=v" (the first '=') decodes both sides, a non-empty part
// without '=' is k with an empty value, an empty part is skipped.  Rows go to pm in the order met, bytes to out at `at`.
func.func private @fr_query(%xs: !s, %qs: index, %qe: index, %om: !m, %pm: !pm, %at: index) -> (index, index) {
  %z = arith.constant 0 : index
  %one = arith.constant 1 : index
  %amp = arith.constant 38 : i8
  %eqc = arith.constant 61 : i8
  %qlen = arith.subi %qe, %qs : index
  %q = trikeshed.slice %xs[%qs, %qlen] : !s -> !s
  %ps = trikeshed.parts %q, %amp : !s, i8 -> !sp
  %cnt = trikeshed.size %ps : !sp
  %r:2 = scf.for %j = %z to %cnt step %one iter_args(%np = %z, %w = %at) -> (index, index) {
    %pc = trikeshed.at %ps[%j] : !sp, index -> !tp
    %st = trikeshed.first %pc : !tp -> i32
    %ln = trikeshed.second %pc : !tp -> i32
    %sti = arith.index_cast %st : i32 to index
    %lni = arith.index_cast %ln : i32 to index
    %kvs = arith.addi %qs, %sti : index
    %kve = arith.addi %kvs, %lni : index
    %eq = func.call @fr_find(%xs, %kvs, %kve, %eqc) : (!s, index, index, i8) -> index
    %has = arith.cmpi ult, %eq, %kve : index
    %nonempty = arith.cmpi ugt, %lni, %z : index
    %o:2 = scf.if %has -> (index, index) {
      %a1 = func.call @fr_decode(%xs, %kvs, %eq, %om, %w) : (!s, index, index, !m, index) -> index
      %kl = arith.subi %a1, %w : index
      %vs = arith.addi %eq, %one : index
      %a2 = func.call @fr_decode(%xs, %vs, %kve, %om, %a1) : (!s, index, index, !m, index) -> index
      %vl = arith.subi %a2, %a1 : index
      %np2 = func.call @fr_padd(%pm, %np, %w, %kl, %a1, %vl) : (!pm, index, index, index, index, index) -> index
      scf.yield %np2, %a2 : index, index
    } else {
      %o2:2 = scf.if %nonempty -> (index, index) {
        %b1 = func.call @fr_decode(%xs, %kvs, %kve, %om, %w) : (!s, index, index, !m, index) -> index
        %bl = arith.subi %b1, %w : index
        %np3 = func.call @fr_padd(%pm, %np, %w, %bl, %b1, %z) : (!pm, index, index, index, index, index) -> index
        scf.yield %np3, %b1 : index, index
      } else {
        scf.yield %np, %w : index, index
      }
      scf.yield %o2#0, %o2#1 : index, index
    }
    scf.yield %o#0, %o#1 : index, index
  }
  return %r#0, %r#1 : index, index
}

// the key (off, len) of parameter row e
func.func private @fr_pkey(%pm: !pm, %e: index) -> (index, index) {
  %one = arith.constant 1 : index
  %four = arith.constant 4 : index
  %b = arith.muli %e, %four : index
  %b1 = arith.addi %b, %one : index
  %o = memref.load %pm[%b] : !pm
  %l = memref.load %pm[%b1] : !pm
  %oi = arith.index_cast %o : i64 to index
  %li = arith.index_cast %l : i64 to index
  return %oi, %li : index, index
}

// the parameters as the SortedMap held them: sorted by key (stable), the last row of each key winning.  mode 0 makes
// each a putFlakeAttr record; mode 1 (git+ / hg+ / tarball+ / file+) records only the fetcher's attributes and
// appends the others to the url being written at `at` ("?k=v", then "&k=v").  Returns (records, end).
func.func private @fr_params(%os: !s, %om: !m, %recs: !m64, %pm: !pm, %np: index, %k: index, %at: index, %mode: i1) -> (index, index) {
  %z = arith.constant 0 : index
  %one = arith.constant 1 : index
  %two = arith.constant 2 : index
  %three = arith.constant 3 : index
  %four = arith.constant 4 : index
  %w20 = arith.constant 20 : index
  %w30 = arith.constant 30 : index
  %wq = arith.constant 43 : index
  %wa = arith.constant 44 : index
  %we = arith.constant 45 : index
  %z32 = arith.constant 0 : i32
  %true = arith.constant true
  %false = arith.constant false
  %idx = trikeshed.series %np : !s64 {
  ^bb0(%q: index):
    %q64 = arith.index_cast %q : index to i64
    trikeshed.yield %q64 : i64
  }
  %srt = trikeshed.sorted %idx : !s64 -> !s64 by {
  ^bb0(%a: i64, %b: i64):
    %ai = arith.index_cast %a : i64 to index
    %bi = arith.index_cast %b : i64 to index
    %ka:2 = func.call @fr_pkey(%pm, %ai) : (!pm, index) -> (index, index)
    %kb:2 = func.call @fr_pkey(%pm, %bi) : (!pm, index) -> (index, index)
    %xa = trikeshed.slice %os[%ka#0, %ka#1] : !s -> !s
    %xb = trikeshed.slice %os[%kb#0, %kb#1] : !s -> !s
    %c = trikeshed.compare %xa, %xb unsigned : !s, !s
    trikeshed.yield %c : i32
  }
  %r:3 = scf.for %j = %z to %np step %one iter_args(%kk = %k, %w = %at, %first = %true) -> (index, index, i1) {
    %e64 = trikeshed.at %srt[%j] : !s64, index -> i64
    %e = arith.index_cast %e64 : i64 to index
    %key:2 = func.call @fr_pkey(%pm, %e) : (!pm, index) -> (index, index)
    %eb = arith.muli %e, %four : index
    %eb2 = arith.addi %eb, %two : index
    %eb3 = arith.addi %eb, %three : index
    %vo64 = memref.load %pm[%eb2] : !pm
    %vl64 = memref.load %pm[%eb3] : !pm
    %vo = arith.index_cast %vo64 : i64 to index
    %vl = arith.index_cast %vl64 : i64 to index
    %j1 = arith.addi %j, %one : index
    %islast = arith.cmpi uge, %j1, %np : index
    %last = scf.if %islast -> (i1) {
      scf.yield %true : i1
    } else {
      %f64 = trikeshed.at %srt[%j1] : !s64, index -> i64
      %f = arith.index_cast %f64 : i64 to index
      %kf:2 = func.call @fr_pkey(%pm, %f) : (!pm, index) -> (index, index)
      %xe = trikeshed.slice %os[%key#0, %key#1] : !s -> !s
      %xf = trikeshed.slice %os[%kf#0, %kf#1] : !s -> !s
      %c = trikeshed.compare %xe, %xf unsigned : !s, !s
      %ne = arith.cmpi ne, %c, %z32 : i32
      scf.yield %ne : i1
    }
    %o:3 = scf.if %last -> (index, index, i1) {
      %isattr = func.call @fr_in(%os, %key#0, %key#1, %w20, %w30) : (!s, index, index, index, index) -> i1
      %notattr = arith.xori %isattr, %true : i1
      %tourl = arith.andi %mode, %notattr : i1
      %o2:3 = scf.if %tourl -> (index, index, i1) {
        %sep = arith.select %first, %wq, %wa : index
        %a1 = func.call @fr_putw(%sep, %om, %w) : (index, !m, index) -> index
        %a2 = func.call @fr_copy(%os, %key#0, %key#1, %om, %a1) : (!s, index, index, !m, index) -> index
        %a3 = func.call @fr_putw(%we, %om, %a2) : (index, !m, index) -> index
        %a4 = func.call @fr_copy(%os, %vo, %vl, %om, %a3) : (!s, index, index, !m, index) -> index
        scf.yield %kk, %a4, %false : index, index, i1
      } else {
        %k2 = func.call @fr_attr(%os, %recs, %kk, %key#0, %key#1, %vo, %vl) : (!s, !m64, index, index, index, index, index) -> index
        scf.yield %k2, %w, %first : index, index, i1
      }
      scf.yield %o2#0, %o2#1, %o2#2 : index, index, i1
    } else {
      scf.yield %kk, %w, %first : index, index, i1
    }
    scf.yield %o#0, %o#1, %o#2 : index, index, i1
  }
  return %r#0, %r#1 : index, index
}

//===----------------------------------------------------------------------===//
// parseFlakeRef: one function per reference type
//===----------------------------------------------------------------------===//

// github:/gitlab:/sourcehut:  owner/repo[/rev-or-ref], each part percent-decoded; 2 or 3 parts, else -1
func.func private @fr_gh(%xs: !s, %os: !s, %om: !m, %recs: !m64, %pm: !pm, %np: index, %at: index, %si: index, %colon: index, %slen: index) -> i64 {
  %z = arith.constant 0 : index
  %one = arith.constant 1 : index
  %two = arith.constant 2 : index
  %three = arith.constant 3 : index
  %wtype = arith.constant 15 : index
  %wowner = arith.constant 16 : index
  %wrepo = arith.constant 17 : index
  %wrev = arith.constant 20 : index
  %wref = arith.constant 21 : index
  %slash = arith.constant 47 : i8
  %z64 = arith.constant 0 : i64
  %m1 = arith.constant -1 : i64
  %false = arith.constant false
  %rs = arith.addi %colon, %one : index
  %rl = arith.subi %si, %rs : index
  %rest = trikeshed.slice %xs[%rs, %rl] : !s -> !s
  %ps = trikeshed.parts %rest, %slash : !s, i8 -> !sp
  %cnt = trikeshed.size %ps : !sp
  %few = arith.cmpi ult, %cnt, %two : index
  %many = arith.cmpi ugt, %cnt, %three : index
  %bad = arith.ori %few, %many : i1
  %r = scf.if %bad -> (i64) {
    scf.yield %m1 : i64
  } else {
    %a1 = func.call @fr_putw(%wtype, %om, %at) : (index, !m, index) -> index
    %a2 = func.call @fr_copy(%xs, %z, %slen, %om, %a1) : (!s, index, index, !m, index) -> index
    %n1 = arith.subi %a1, %at : index
    %k1 = func.call @fr_rec(%recs, %z, %at, %n1, %a1, %slen, %z64, %z64) : (!m64, index, index, index, index, index, i64, i64) -> index
    %p0 = trikeshed.at %ps[%z] : !sp, index -> !tp
    %s0 = trikeshed.first %p0 : !tp -> i32
    %l0 = trikeshed.second %p0 : !tp -> i32
    %s0i = arith.index_cast %s0 : i32 to index
    %l0i = arith.index_cast %l0 : i32 to index
    %f0 = arith.addi %rs, %s0i : index
    %t0 = arith.addi %f0, %l0i : index
    %a3 = func.call @fr_putw(%wowner, %om, %a2) : (index, !m, index) -> index
    %a4 = func.call @fr_decode(%xs, %f0, %t0, %om, %a3) : (!s, index, index, !m, index) -> index
    %n2 = arith.subi %a3, %a2 : index
    %v2 = arith.subi %a4, %a3 : index
    %k2 = func.call @fr_rec(%recs, %k1, %a2, %n2, %a3, %v2, %z64, %z64) : (!m64, index, index, index, index, index, i64, i64) -> index
    %p1 = trikeshed.at %ps[%one] : !sp, index -> !tp
    %s1 = trikeshed.first %p1 : !tp -> i32
    %l1 = trikeshed.second %p1 : !tp -> i32
    %s1i = arith.index_cast %s1 : i32 to index
    %l1i = arith.index_cast %l1 : i32 to index
    %f1 = arith.addi %rs, %s1i : index
    %t1 = arith.addi %f1, %l1i : index
    %a5 = func.call @fr_putw(%wrepo, %om, %a4) : (index, !m, index) -> index
    %a6 = func.call @fr_decode(%xs, %f1, %t1, %om, %a5) : (!s, index, index, !m, index) -> index
    %n3 = arith.subi %a5, %a4 : index
    %v3 = arith.subi %a6, %a5 : index
    %k3 = func.call @fr_rec(%recs, %k2, %a4, %n3, %a5, %v3, %z64, %z64) : (!m64, index, index, index, index, index, i64, i64) -> index
    %is3 = arith.cmpi eq, %cnt, %three : index
    %o:2 = scf.if %is3 -> (index, index) {
      %p2 = trikeshed.at %ps[%two] : !sp, index -> !tp
      %s2 = trikeshed.first %p2 : !tp -> i32
      %l2 = trikeshed.second %p2 : !tp -> i32
      %s2i = arith.index_cast %s2 : i32 to index
      %l2i = arith.index_cast %l2 : i32 to index
      %f2 = arith.addi %rs, %s2i : index
      %t2 = arith.addi %f2, %l2i : index
      %a7 = func.call @fr_decode(%xs, %f2, %t2, %om, %a6) : (!s, index, index, !m, index) -> index
      %v7 = arith.subi %a7, %a6 : index
      %hex = func.call @fr_hexrev(%os, %a6, %v7) : (!s, index, index) -> i1
      %kid = arith.select %hex, %wrev, %wref : index
      %a8 = func.call @fr_putw(%kid, %om, %a7) : (index, !m, index) -> index
      %n8 = arith.subi %a8, %a7 : index
      %np2 = func.call @fr_padd(%pm, %np, %a7, %n8, %a6, %v7) : (!pm, index, index, index, index, index) -> index
      scf.yield %np2, %a8 : index, index
    } else {
      scf.yield %np, %a6 : index, index
    }
    %fin:2 = func.call @fr_params(%os, %om, %recs, %pm, %o#0, %k3, %o#1, %false) : (!s, !m, !m64, !pm, index, index, index, i1) -> (index, index)
    %k64 = arith.index_cast %fin#0 : index to i64
    scf.yield %k64 : i64
  }
  return %r : i64
}

// path:  (or a bare reference starting with '/' or '.'): the path, made absolute against the working directory
// (canonPath, the bridge's callback) when it is not, then percent-decoded.  -(need) - 2 when out is too small for it.
func.func private @fr_path(%ctx: !llvm.ptr, %p: !llvm.ptr, %n: i64, %cap: i64, %xs: !s, %os: !s, %om: !m, %recs: !m64, %pm: !pm, %np: index, %at: index, %si: index, %colon: index, %slen: index) -> i64 {
  %z = arith.constant 0 : index
  %one = arith.constant 1 : index
  %wtype = arith.constant 15 : index
  %wpath = arith.constant 3 : index
  %slash = arith.constant 47 : i8
  %z64 = arith.constant 0 : i64
  %one64 = arith.constant 1 : i64
  %two64 = arith.constant 2 : i64
  %four64 = arith.constant 4 : i64
  %c128 = arith.constant 128 : i64
  %false = arith.constant false
  %bare = arith.cmpi eq, %slen, %z : index
  %after = arith.addi %colon, %one : index
  %pst = arith.select %bare, %z, %after : index
  %pl = arith.subi %si, %pst : index
  %a1 = func.call @fr_putw(%wtype, %om, %at) : (index, !m, index) -> index
  %a2 = func.call @fr_putw(%wpath, %om, %a1) : (index, !m, index) -> index
  %n1 = arith.subi %a1, %at : index
  %v1 = arith.subi %a2, %a1 : index
  %k1 = func.call @fr_rec(%recs, %z, %at, %n1, %a1, %v1, %z64, %z64) : (!m64, index, index, index, index, index, i64, i64) -> index
  %a3 = func.call @fr_putw(%wpath, %om, %a2) : (index, !m, index) -> index
  %nonempty = arith.cmpi ugt, %pl, %z : index
  %rel = scf.if %nonempty -> (i1) {
    %c = trikeshed.at %xs[%pst] : !s, index -> i8
    %ns = arith.cmpi ne, %c, %slash : i8
    scf.yield %ns : i1
  } else {
    scf.yield %false : i1
  }
  %dec:2 = scf.if %rel -> (i64, index) {
    %slot = llvm.alloca %one64 x i64 : (i64) -> !llvm.ptr
    %pst64 = arith.index_cast %pst : index to i64
    %pl64 = arith.index_cast %pl : index to i64
    %pp = llvm.getelementptr %p[%pst64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %cp = func.call @nixev_flake_canon(%ctx, %pp, %pl64, %slot) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr) -> !llvm.ptr
    %cl = llvm.load %slot : !llvm.ptr -> i64
    %n4 = arith.muli %n, %four64 : i64
    %n4b = arith.addi %n4, %c128 : i64
    %need = arith.addi %n4b, %cl : i64
    %short = arith.cmpi slt, %cap, %need : i64
    %res:2 = scf.if %short -> (i64, index) {
      %neg = arith.subi %z64, %need : i64
      %st = arith.subi %neg, %two64 : i64
      scf.yield %st, %a3 : i64, index
    } else {
      %cd = func.call @fr_desc(%cp, %cl) : (!llvm.ptr, i64) -> !d
      %cm = builtin.unrealized_conversion_cast %cd : !d to !m
      %cs = builtin.unrealized_conversion_cast %cm : !m to !s
      %cli = arith.index_cast %cl : i64 to index
      %a4 = func.call @fr_decode(%cs, %z, %cli, %om, %a3) : (!s, index, index, !m, index) -> index
      scf.yield %z64, %a4 : i64, index
    }
    scf.yield %res#0, %res#1 : i64, index
  } else {
    %a5 = func.call @fr_decode(%xs, %pst, %si, %om, %a3) : (!s, index, index, !m, index) -> index
    scf.yield %z64, %a5 : i64, index
  }
  %failed = arith.cmpi slt, %dec#0, %z64 : i64
  %r = scf.if %failed -> (i64) {
    scf.yield %dec#0 : i64
  } else {
    %n2 = arith.subi %a3, %a2 : index
    %v2 = arith.subi %dec#1, %a3 : index
    %k2 = func.call @fr_rec(%recs, %k1, %a2, %n2, %a3, %v2, %z64, %z64) : (!m64, index, index, index, index, index, i64, i64) -> index
    %fin:2 = func.call @fr_params(%os, %om, %recs, %pm, %np, %k2, %dec#1, %false) : (!s, !m, !m64, !pm, index, index, index, i1) -> (index, index)
    %k64 = arith.index_cast %fin#0 : index to i64
    scf.yield %k64 : i64
  }
  return %r : i64
}

// git+ / hg+ / tarball+ / file+:  the type before '+' (hg is mercurial), the fetcher's attributes from the query, the
// url after '+' with the other parameters put back ("?k=v&k=v", decoded, in key order).  The url record is last.
func.func private @fr_git(%xs: !s, %os: !s, %om: !m, %recs: !m64, %pm: !pm, %np: index, %at: index, %si: index, %slen: index) -> i64 {
  %z = arith.constant 0 : index
  %one = arith.constant 1 : index
  %wtype = arith.constant 15 : index
  %wmerc = arith.constant 12 : index
  %whg = arith.constant 41 : index
  %wurl = arith.constant 18 : index
  %plusc = arith.constant 43 : i8
  %z64 = arith.constant 0 : i64
  %true = arith.constant true
  %plus = func.call @fr_find(%xs, %z, %slen, %plusc) : (!s, index, index, i8) -> index
  %hg = func.call @fr_is(%xs, %z, %plus, %whg) : (!s, index, index, index) -> i1
  %a1 = func.call @fr_putw(%wtype, %om, %at) : (index, !m, index) -> index
  %a2 = scf.if %hg -> (index) {
    %b = func.call @fr_putw(%wmerc, %om, %a1) : (index, !m, index) -> index
    scf.yield %b : index
  } else {
    %c = func.call @fr_copy(%xs, %z, %plus, %om, %a1) : (!s, index, index, !m, index) -> index
    scf.yield %c : index
  }
  %n1 = arith.subi %a1, %at : index
  %v1 = arith.subi %a2, %a1 : index
  %k1 = func.call @fr_rec(%recs, %z, %at, %n1, %a1, %v1, %z64, %z64) : (!m64, index, index, index, index, index, i64, i64) -> index
  %a3 = func.call @fr_putw(%wurl, %om, %a2) : (index, !m, index) -> index
  %us = arith.addi %plus, %one : index
  %ul = arith.subi %si, %us : index
  %a4 = func.call @fr_copy(%xs, %us, %ul, %om, %a3) : (!s, index, index, !m, index) -> index
  %fin:2 = func.call @fr_params(%os, %om, %recs, %pm, %np, %k1, %a4, %true) : (!s, !m, !m64, !pm, index, index, index, i1) -> (index, index)
  %n3 = arith.subi %a3, %a2 : index
  %v3 = arith.subi %fin#1, %a3 : index
  %k3 = func.call @fr_rec(%recs, %fin#0, %a2, %n3, %a3, %v3, %z64, %z64) : (!m64, index, index, index, index, index, i64, i64) -> index
  %r = arith.index_cast %k3 : index to i64
  return %r : i64
}

// http: / https: / file:  tarball when the reference (before '?' and '#') ends in an archive suffix, else file; the
// url is that reference with the raw query put back
func.func private @fr_http(%xs: !s, %om: !m, %recs: !m64, %at: index, %si: index, %qs: index, %ni: index) -> i64 {
  %z = arith.constant 0 : index
  %one = arith.constant 1 : index
  %wtype = arith.constant 15 : index
  %wtar = arith.constant 13 : index
  %wfile = arith.constant 10 : index
  %wurl = arith.constant 18 : index
  %wq = arith.constant 43 : index
  %w34 = arith.constant 34 : index
  %w41 = arith.constant 41 : index
  %z64 = arith.constant 0 : i64
  %false = arith.constant false
  %tar = scf.for %id = %w34 to %w41 step %one iter_args(%acc = %false) -> (i1) {
    %e = func.call @fr_suffix(%xs, %z, %si, %id) : (!s, index, index, index) -> i1
    %a = arith.ori %acc, %e : i1
    scf.yield %a : i1
  }
  %tid = arith.select %tar, %wtar, %wfile : index
  %a1 = func.call @fr_putw(%wtype, %om, %at) : (index, !m, index) -> index
  %a2 = func.call @fr_putw(%tid, %om, %a1) : (index, !m, index) -> index
  %n1 = arith.subi %a1, %at : index
  %v1 = arith.subi %a2, %a1 : index
  %k1 = func.call @fr_rec(%recs, %z, %at, %n1, %a1, %v1, %z64, %z64) : (!m64, index, index, index, index, index, i64, i64) -> index
  %a3 = func.call @fr_putw(%wurl, %om, %a2) : (index, !m, index) -> index
  %a4 = func.call @fr_copy(%xs, %z, %si, %om, %a3) : (!s, index, index, !m, index) -> index
  %hasq = arith.cmpi ult, %qs, %ni : index
  %a5 = scf.if %hasq -> (index) {
    %b1 = func.call @fr_putw(%wq, %om, %a4) : (index, !m, index) -> index
    %ql = arith.subi %ni, %qs : index
    %b2 = func.call @fr_copy(%xs, %qs, %ql, %om, %b1) : (!s, index, index, !m, index) -> index
    scf.yield %b2 : index
  } else {
    scf.yield %a4 : index
  }
  %n3 = arith.subi %a3, %a2 : index
  %v3 = arith.subi %a5, %a3 : index
  %k2 = func.call @fr_rec(%recs, %k1, %a2, %n3, %a3, %v3, %z64, %z64) : (!m64, index, index, index, index, index, i64, i64) -> index
  %r = arith.index_cast %k2 : index to i64
  return %r : i64
}

// indirect:  [flake:]id[/ref-or-rev], raw (not decoded)
func.func private @fr_ind(%xs: !s, %os: !s, %om: !m, %recs: !m64, %pm: !pm, %np: index, %at: index, %si: index, %colon: index, %slen: index) -> i64 {
  %z = arith.constant 0 : index
  %one = arith.constant 1 : index
  %wtype = arith.constant 15 : index
  %wind = arith.constant 14 : index
  %wflake = arith.constant 11 : index
  %wid = arith.constant 19 : index
  %wrev = arith.constant 20 : index
  %wref = arith.constant 21 : index
  %slash = arith.constant 47 : i8
  %z64 = arith.constant 0 : i64
  %false = arith.constant false
  %isfl = func.call @fr_is(%xs, %z, %slen, %wflake) : (!s, index, index, index) -> i1
  %after = arith.addi %colon, %one : index
  %rs = arith.select %isfl, %after, %z : index
  %sl = func.call @fr_find(%xs, %rs, %si, %slash) : (!s, index, index, i8) -> index
  %a1 = func.call @fr_putw(%wtype, %om, %at) : (index, !m, index) -> index
  %a2 = func.call @fr_putw(%wind, %om, %a1) : (index, !m, index) -> index
  %n1 = arith.subi %a1, %at : index
  %v1 = arith.subi %a2, %a1 : index
  %k1 = func.call @fr_rec(%recs, %z, %at, %n1, %a1, %v1, %z64, %z64) : (!m64, index, index, index, index, index, i64, i64) -> index
  %a3 = func.call @fr_putw(%wid, %om, %a2) : (index, !m, index) -> index
  %il = arith.subi %sl, %rs : index
  %a4 = func.call @fr_copy(%xs, %rs, %il, %om, %a3) : (!s, index, index, !m, index) -> index
  %n2 = arith.subi %a3, %a2 : index
  %k2 = func.call @fr_rec(%recs, %k1, %a2, %n2, %a3, %il, %z64, %z64) : (!m64, index, index, index, index, index, i64, i64) -> index
  %has = arith.cmpi ult, %sl, %si : index
  %o:2 = scf.if %has -> (index, index) {
    %r0 = arith.addi %sl, %one : index
    %rl = arith.subi %si, %r0 : index
    %a5 = func.call @fr_copy(%xs, %r0, %rl, %om, %a4) : (!s, index, index, !m, index) -> index
    %hex = func.call @fr_hexrev(%xs, %r0, %rl) : (!s, index, index) -> i1
    %kid = arith.select %hex, %wrev, %wref : index
    %a6 = func.call @fr_putw(%kid, %om, %a5) : (index, !m, index) -> index
    %n6 = arith.subi %a6, %a5 : index
    %np2 = func.call @fr_padd(%pm, %np, %a5, %n6, %a4, %rl) : (!pm, index, index, index, index, index) -> index
    scf.yield %np2, %a6 : index, index
  } else {
    scf.yield %np, %a4 : index, index
  }
  %fin:2 = func.call @fr_params(%os, %om, %recs, %pm, %o#0, %k2, %o#1, %false) : (!s, !m, !m64, !pm, index, index, index, i1) -> (index, index)
  %r = arith.index_cast %fin#0 : index to i64
  return %r : i64
}

// the reference's frame: the query after the first '?', the reference before it and before the first '#', the
// parameters, the scheme before the first ':'; then the type's function.
func.func private @fr_parse(%ctx: !llvm.ptr, %p: !llvm.ptr, %n: i64, %out: !llvm.ptr, %cap: i64, %recs: !llvm.ptr) -> i64 {
  %z = arith.constant 0 : index
  %one = arith.constant 1 : index
  %two = arith.constant 2 : index
  %four = arith.constant 4 : index
  %qc = arith.constant 63 : i8
  %hc = arith.constant 35 : i8
  %cc = arith.constant 58 : i8
  %slashc = arith.constant 47 : i8
  %dotc = arith.constant 46 : i8
  %w0 = arith.constant 0 : index
  %w2 = arith.constant 2 : index
  %w3 = arith.constant 3 : index
  %w4 = arith.constant 4 : index
  %w7 = arith.constant 7 : index
  %w8 = arith.constant 8 : index
  %w10 = arith.constant 10 : index
  %false = arith.constant false
  %eight64 = arith.constant 8 : i64
  %six64 = arith.constant 6 : i64
  %xd = func.call @fr_desc(%p, %n) : (!llvm.ptr, i64) -> !d
  %xm = builtin.unrealized_conversion_cast %xd : !d to !m
  %xs = builtin.unrealized_conversion_cast %xm : !m to !s
  %od = func.call @fr_desc(%out, %cap) : (!llvm.ptr, i64) -> !d
  %om = builtin.unrealized_conversion_cast %od : !d to !m
  %os = builtin.unrealized_conversion_cast %om : !m to !s
  %nr0 = arith.addi %n, %eight64 : i64
  %nr = arith.muli %nr0, %six64 : i64
  %rd = func.call @fr_desc(%recs, %nr) : (!llvm.ptr, i64) -> !d
  %rm = builtin.unrealized_conversion_cast %rd : !d to !m64
  %ni = arith.index_cast %n : i64 to index
  %qi = func.call @fr_find(%xs, %z, %ni, %qc) : (!s, index, index, i8) -> index
  %hasq = arith.cmpi ult, %qi, %ni : index
  %qi1 = arith.addi %qi, %one : index
  %qs = arith.select %hasq, %qi1, %ni : index
  %si = func.call @fr_find(%xs, %z, %qi, %hc) : (!s, index, index, i8) -> index
  %ql = arith.subi %ni, %qs : index
  %ql2 = arith.addi %ql, %two : index
  %pms = arith.muli %ql2, %four : index
  %pm = memref.alloc(%pms) : !pm
  %q:2 = func.call @fr_query(%xs, %qs, %ni, %om, %pm, %z) : (!s, index, index, !m, !pm, index) -> (index, index)
  %colon = func.call @fr_find(%xs, %z, %si, %cc) : (!s, index, index, i8) -> index
  %hasc = arith.cmpi ult, %colon, %si : index
  %slen = arith.select %hasc, %colon, %z : index
  %g0 = func.call @fr_in(%xs, %z, %slen, %w0, %w2) : (!s, index, index, index, index) -> i1
  %r = scf.if %g0 -> (i64) {
    %x = func.call @fr_gh(%xs, %os, %om, %rm, %pm, %q#0, %q#1, %si, %colon, %slen) : (!s, !s, !m, !m64, !pm, index, index, index, index, index) -> i64
    scf.yield %x : i64
  } else {
    %ispath = func.call @fr_is(%xs, %z, %slen, %w3) : (!s, index, index, index) -> i1
    %noscheme = arith.cmpi eq, %slen, %z : index
    %some = arith.cmpi ugt, %si, %z : index
    %lead = arith.andi %noscheme, %some : i1
    %bare = scf.if %lead -> (i1) {
      %c0 = trikeshed.at %xs[%z] : !s, index -> i8
      %isl = arith.cmpi eq, %c0, %slashc : i8
      %isd = arith.cmpi eq, %c0, %dotc : i8
      %b = arith.ori %isl, %isd : i1
      scf.yield %b : i1
    } else {
      scf.yield %false : i1
    }
    %c2 = arith.ori %ispath, %bare : i1
    %r2 = scf.if %c2 -> (i64) {
      %x2 = func.call @fr_path(%ctx, %p, %n, %cap, %xs, %os, %om, %rm, %pm, %q#0, %q#1, %si, %colon, %slen) : (!llvm.ptr, !llvm.ptr, i64, i64, !s, !s, !m, !m64, !pm, index, index, index, index, index) -> i64
      scf.yield %x2 : i64
    } else {
      %c3 = scf.for %id = %w4 to %w8 step %one iter_args(%acc = %false) -> (i1) {
        %e = func.call @fr_prefix(%xs, %z, %slen, %id) : (!s, index, index, index) -> i1
        %a = arith.ori %acc, %e : i1
        scf.yield %a : i1
      }
      %r3 = scf.if %c3 -> (i64) {
        %x3 = func.call @fr_git(%xs, %os, %om, %rm, %pm, %q#0, %q#1, %si, %slen) : (!s, !s, !m, !m64, !pm, index, index, index, index) -> i64
        scf.yield %x3 : i64
      } else {
        %c4 = func.call @fr_in(%xs, %z, %slen, %w8, %w10) : (!s, index, index, index, index) -> i1
        %r4 = scf.if %c4 -> (i64) {
          %x4 = func.call @fr_http(%xs, %om, %rm, %q#1, %si, %qs, %ni) : (!s, !m, !m64, index, index, index, index) -> i64
          scf.yield %x4 : i64
        } else {
          %x5 = func.call @fr_ind(%xs, %os, %om, %rm, %pm, %q#0, %q#1, %si, %colon, %slen) : (!s, !s, !m, !m64, !pm, index, index, index, index, index) -> i64
          scf.yield %x5 : i64
        }
        scf.yield %r4 : i64
      }
      scf.yield %r3 : i64
    }
    scf.yield %r2 : i64
  }
  return %r : i64
}

// parseFlakeRef's whole text algebra.  The n bytes at p become records (6 i64 each at recs, room for n + 8) naming
// bytes written to out (cap bytes): returns the record count, -1 when a github-like reference has not 2 or 3 parts
// (the bridge throws "'REF' is not a valid URL"), or -(need) - 2 when out must hold `need` bytes (the bridge retries).
func.func @nixev_ts_flake_parse(%ctx: !llvm.ptr, %p: !llvm.ptr, %n: i64, %out: !llvm.ptr, %cap: i64, %recs: !llvm.ptr) -> i64 {
  %z64 = arith.constant 0 : i64
  %two64 = arith.constant 2 : i64
  %four64 = arith.constant 4 : i64
  %c128 = arith.constant 128 : i64
  %n4 = arith.muli %n, %four64 : i64
  %need = arith.addi %n4, %c128 : i64
  %short = arith.cmpi slt, %cap, %need : i64
  %r = scf.if %short -> (i64) {
    %neg = arith.subi %z64, %need : i64
    %st = arith.subi %neg, %two64 : i64
    scf.yield %st : i64
  } else {
    %x = func.call @fr_parse(%ctx, %p, %n, %out, %cap, %recs) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr) -> i64
    scf.yield %x : i64
  }
  return %r : i64
}

//===----------------------------------------------------------------------===//
// flakeRefToString
//===----------------------------------------------------------------------===//

// x >= 0 in decimal at dst (room for 20); returns the digit count.  A fold over the powers of ten counts the digits,
// a series makes them, one drain writes them (PrintOps.mlir's recipe).
func.func private @fr_digits(%x: i64, %dst: !llvm.ptr) -> i64 {
  %c1 = arith.constant 1 : index
  %c18 = arith.constant 18 : index
  %ten = arith.constant 10 : i64
  %d0 = arith.constant 48 : i8
  %pg = memref.get_global @fr_pow : memref<19xi64>
  %powers = trikeshed.text %pg : memref<19xi64> -> !s64
  %above = trikeshed.slice %powers[%c1, %c18] : !s64 -> !s64
  %count = trikeshed.fold %above, %c1 : !s64, index -> index {
  ^bb0(%acc: index, %pw: i64):
    %reach = arith.cmpi uge, %x, %pw : i64
    %more = arith.addi %acc, %c1 : index
    %r = arith.select %reach, %more, %acc : index
    trikeshed.yield %r : index
  }
  %digits = trikeshed.series %count : !s {
  ^bb0(%k: index):
    %last = arith.subi %count, %c1 : index
    %e = arith.subi %last, %k : index
    %pe = trikeshed.at %powers[%e] : !s64, index -> i64
    %q = arith.divui %x, %pe : i64
    %dg = arith.remui %q, %ten : i64
    %d8 = arith.trunci %dg : i64 to i8
    %c = arith.addi %d8, %d0 : i8
    trikeshed.yield %c : i8
  }
  %c64 = arith.index_cast %count : index to i64
  %dd = func.call @fr_desc(%dst, %c64) : (!llvm.ptr, i64) -> !d
  %dm = builtin.unrealized_conversion_cast %dd : !d to !m
  %end = trikeshed.drain %digits, %dm : !s, !m -> index
  return %c64 : i64
}

// the address of word id in the blob, and its length
func.func private @fr_wptr(%id: index) -> (i64, i64) {
  %g = memref.get_global @fr_blob : memref<250xi8>
  %base = memref.extract_aligned_pointer_as_index %g : memref<250xi8> -> index
  %w:2 = func.call @fr_word(%id) : (index) -> (index, index)
  %at = arith.addi %base, %w#0 : index
  %at64 = arith.index_cast %at : index to i64
  %l64 = arith.index_cast %w#1 : index to i64
  return %at64, %l64 : i64, i64
}

// entry e's key as (address, length)
func.func private @fr_ekey(%em: !m64, %e: index) -> (i64, i64) {
  %one = arith.constant 1 : index
  %five = arith.constant 5 : index
  %b = arith.muli %e, %five : index
  %b1 = arith.addi %b, %one : index
  %kp = memref.load %em[%b] : !m64
  %kl = memref.load %em[%b1] : !m64
  return %kp, %kl : i64, i64
}

// whether entry e's key is word id
func.func private @fr_ekeyis(%em: !m64, %e: index, %id: index) -> i1 {
  %z = arith.constant 0 : index
  %k:2 = func.call @fr_ekey(%em, %e) : (!m64, index) -> (i64, i64)
  %kp = llvm.inttoptr %k#0 : i64 to !llvm.ptr
  %kd = func.call @fr_desc(%kp, %k#1) : (!llvm.ptr, i64) -> !d
  %km = builtin.unrealized_conversion_cast %kd : !d to !m
  %ks = builtin.unrealized_conversion_cast %km : !m to !s
  %kli = arith.index_cast %k#1 : i64 to index
  %r = func.call @fr_is(%ks, %z, %kli, %id) : (!s, index, index, index) -> i1
  return %r : i1
}

// the entry whose key is word id (the map's find), or n
func.func private @fr_ekeyfind(%em: !m64, %n: index, %id: index) -> index {
  %z = arith.constant 0 : index
  %one = arith.constant 1 : index
  %r = scf.for %e = %z to %n step %one iter_args(%found = %n) -> (index) {
    %is = func.call @fr_ekeyis(%em, %e, %id) : (!m64, index, index) -> i1
    %unset = arith.cmpi eq, %found, %n : index
    %take = arith.andi %is, %unset : i1
    %f2 = arith.select %take, %e, %found : index
    scf.yield %f2 : index
  }
  return %r : index
}

// take(word id): the value window (address, length) of that entry, or an empty window at dflt
func.func private @fr_take(%em: !m64, %vw: !pm, %n: index, %id: index, %dflt: i64) -> (i64, i64) {
  %one = arith.constant 1 : index
  %two = arith.constant 2 : index
  %z64 = arith.constant 0 : i64
  %e = func.call @fr_ekeyfind(%em, %n, %id) : (!m64, index, index) -> index
  %has = arith.cmpi ult, %e, %n : index
  %r:2 = scf.if %has -> (i64, i64) {
    %b = arith.muli %e, %two : index
    %b1 = arith.addi %b, %one : index
    %vp = memref.load %vw[%b] : !pm
    %vl = memref.load %vw[%b1] : !pm
    scf.yield %vp, %vl : i64, i64
  } else {
    scf.yield %dflt, %z64 : i64, i64
  }
  return %r#0, %r#1 : i64, i64
}

// the reference's text, once the type is one of the five kinds (cls 1 github-like, 2 path, 3 git/mercurial/tarball/
// file, 4 indirect): one combine of the head's pieces (each 0 bytes when the kind has none) and the remaining
// attributes' query, drained once.  Encoding is per byte a slice of fr_enc (the byte itself, or "%XY"), chosen by the
// keep set's bit: 1 path/owner/repo/ref, 2 a query key, 4 a query value.
func.func private @fr_compose(%em: !m64, %vw: !pm, %n: index, %into: !llvm.ptr, %cap: i64, %tp: i64, %tl: i64, %cls: i64, %merc: i1) -> i64 {
  %z = arith.constant 0 : index
  %one = arith.constant 1 : index
  %two = arith.constant 2 : index
  %four = arith.constant 4 : index
  %five = arith.constant 5 : index
  %three = arith.constant 3 : index
  %z64 = arith.constant 0 : i64
  %one64 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %z8 = arith.constant 0 : i8
  %b1 = arith.constant 1 : i8
  %b2 = arith.constant 2 : i8
  %b4 = arith.constant 4 : i8
  %true = arith.constant true
  %wpath = arith.constant 3 : index
  %wflake = arith.constant 11 : index
  %whg = arith.constant 41 : index
  %wtype = arith.constant 15 : index
  %wowner = arith.constant 16 : index
  %wrepo = arith.constant 17 : index
  %wurl = arith.constant 18 : index
  %wid = arith.constant 19 : index
  %wrev = arith.constant 20 : index
  %wref = arith.constant 21 : index
  %wq = arith.constant 43 : index
  %wa = arith.constant 44 : index
  %we = arith.constant 45 : index
  %wc = arith.constant 46 : index
  %ws = arith.constant 47 : index
  %wp = arith.constant 48 : index
  %is1 = arith.cmpi eq, %cls, %one64 : i64
  %is2 = arith.cmpi eq, %cls, %c2 : i64
  %is3 = arith.cmpi eq, %cls, %c3 : i64
  %is4 = arith.cmpi eq, %cls, %c4 : i64
  %dflt = llvm.ptrtoint %into : !llvm.ptr to i64
  %owner:2 = func.call @fr_take(%em, %vw, %n, %wowner, %dflt) : (!m64, !pm, index, index, i64) -> (i64, i64)
  %repo:2 = func.call @fr_take(%em, %vw, %n, %wrepo, %dflt) : (!m64, !pm, index, index, i64) -> (i64, i64)
  %rev:2 = func.call @fr_take(%em, %vw, %n, %wrev, %dflt) : (!m64, !pm, index, index, i64) -> (i64, i64)
  %ref:2 = func.call @fr_take(%em, %vw, %n, %wref, %dflt) : (!m64, !pm, index, index, i64) -> (i64, i64)
  %path:2 = func.call @fr_take(%em, %vw, %n, %wpath, %dflt) : (!m64, !pm, index, index, i64) -> (i64, i64)
  %url:2 = func.call @fr_take(%em, %vw, %n, %wurl, %dflt) : (!m64, !pm, index, index, i64) -> (i64, i64)
  %id:2 = func.call @fr_take(%em, %vw, %n, %wid, %dflt) : (!m64, !pm, index, index, i64) -> (i64, i64)
  // which entries the kind takes (the map's erase), then the rest in key order and each one's rank among the rest
  %tk = memref.alloc(%n) : !pm
  scf.for %e = %z to %n step %one {
    %kt = func.call @fr_ekeyis(%em, %e, %wtype) : (!m64, index, index) -> i1
    %ko = func.call @fr_ekeyis(%em, %e, %wowner) : (!m64, index, index) -> i1
    %kr = func.call @fr_ekeyis(%em, %e, %wrepo) : (!m64, index, index) -> i1
    %kv = func.call @fr_ekeyis(%em, %e, %wrev) : (!m64, index, index) -> i1
    %kf = func.call @fr_ekeyis(%em, %e, %wref) : (!m64, index, index) -> i1
    %kp = func.call @fr_ekeyis(%em, %e, %wpath) : (!m64, index, index) -> i1
    %ku = func.call @fr_ekeyis(%em, %e, %wurl) : (!m64, index, index) -> i1
    %ki = func.call @fr_ekeyis(%em, %e, %wid) : (!m64, index, index) -> i1
    %or1 = arith.ori %ko, %kr : i1
    %vf = arith.ori %kv, %kf : i1
    %gh0 = arith.ori %or1, %vf : i1
    %gh = arith.andi %is1, %gh0 : i1
    %pt = arith.andi %is2, %kp : i1
    %gt = arith.andi %is3, %ku : i1
    %in0 = arith.ori %ki, %vf : i1
    %ind = arith.andi %is4, %in0 : i1
    %t1 = arith.ori %kt, %gh : i1
    %t2 = arith.ori %pt, %gt : i1
    %t3 = arith.ori %t1, %t2 : i1
    %t4 = arith.ori %t3, %ind : i1
    %t64 = arith.extui %t4 : i1 to i64
    memref.store %t64, %tk[%e] : !pm
  }
  %idx = trikeshed.series %n : !s64 {
  ^bb0(%q: index):
    %q64 = arith.index_cast %q : index to i64
    trikeshed.yield %q64 : i64
  }
  %srt = trikeshed.sorted %idx : !s64 -> !s64 by {
  ^bb0(%a: i64, %b: i64):
    %ai = arith.index_cast %a : i64 to index
    %bi = arith.index_cast %b : i64 to index
    %ka:2 = func.call @fr_ekey(%em, %ai) : (!m64, index) -> (i64, i64)
    %kb:2 = func.call @fr_ekey(%em, %bi) : (!m64, index) -> (i64, i64)
    %pa = llvm.inttoptr %ka#0 : i64 to !llvm.ptr
    %pb = llvm.inttoptr %kb#0 : i64 to !llvm.ptr
    %da = func.call @fr_desc(%pa, %ka#1) : (!llvm.ptr, i64) -> !d
    %db = func.call @fr_desc(%pb, %kb#1) : (!llvm.ptr, i64) -> !d
    %ma = builtin.unrealized_conversion_cast %da : !d to !m
    %mb = builtin.unrealized_conversion_cast %db : !d to !m
    %xa = builtin.unrealized_conversion_cast %ma : !m to !s
    %xb = builtin.unrealized_conversion_cast %mb : !m to !s
    %c = trikeshed.compare %xa, %xb unsigned : !s, !s
    trikeshed.yield %c : i32
  }
  %rk = memref.alloc(%n) : !pm
  %kept = scf.for %j = %z to %n step %one iter_args(%cnt = %z64) -> (i64) {
    %e64 = trikeshed.at %srt[%j] : !s64, index -> i64
    %e = arith.index_cast %e64 : i64 to index
    memref.store %cnt, %rk[%j] : !pm
    %t = memref.load %tk[%e] : !pm
    %free = arith.cmpi eq, %t, %z64 : i64
    %f64 = arith.extui %free : i1 to i64
    %cnt2 = arith.addi %cnt, %f64 : i64
    scf.yield %cnt2 : i64
  }
  // the tables
  %bg = memref.get_global @fr_blob : memref<250xi8>
  %blob = trikeshed.text %bg : memref<250xi8> -> !s
  %eg = memref.get_global @fr_enc : memref<1024xi8>
  %enc = trikeshed.text %eg : memref<1024xi8> -> !s
  %kg = memref.get_global @fr_keep : memref<256xi8>
  %keep = trikeshed.text %kg : memref<256xi8> -> !s
  // P1 the type word: the type itself (github-like; git/tarball/file), or "path", "hg", "flake"
  %w24 = arith.select %is4, %wflake, %whg : index
  %wid1 = arith.select %is2, %wpath, %w24 : index
  %merc3 = arith.andi %is3, %merc : i1
  %u24 = arith.ori %is2, %is4 : i1
  %useword = arith.ori %u24, %merc3 : i1
  %wd:2 = func.call @fr_wptr(%wid1) : (index) -> (i64, i64)
  %p1p = arith.select %useword, %wd#0, %tp : i64
  %p1l = arith.select %useword, %wd#1, %tl : i64
  %p1a = llvm.inttoptr %p1p : i64 to !llvm.ptr
  %p1d = func.call @fr_desc(%p1a, %p1l) : (!llvm.ptr, i64) -> !d
  %p1m = builtin.unrealized_conversion_cast %p1d : !d to !m
  %p1 = builtin.unrealized_conversion_cast %p1m : !m to !s
  // P2 ':' or '+'
  %sepw = arith.select %is3, %wp, %wc : index
  %sepb:2 = func.call @fr_word(%sepw) : (index) -> (index, index)
  %p2 = trikeshed.slice %blob[%sepb#0, %one] : !s -> !s
  // P3 owner (github-like) or path, encoded
  %a0p = arith.select %is2, %path#0, %dflt : i64
  %a0l = arith.select %is2, %path#1, %z64 : i64
  %ap = arith.select %is1, %owner#0, %a0p : i64
  %al = arith.select %is1, %owner#1, %a0l : i64
  %apa = llvm.inttoptr %ap : i64 to !llvm.ptr
  %ad = func.call @fr_desc(%apa, %al) : (!llvm.ptr, i64) -> !d
  %am = builtin.unrealized_conversion_cast %ad : !d to !m
  %as = builtin.unrealized_conversion_cast %am : !m to !s
  %ali = arith.index_cast %al : i64 to index
  %p3, %p3c = trikeshed.combineAll %ali : !s, !sp {
  ^bb0(%u3: index):
    %c3b = trikeshed.at %as[%u3] : !s, index -> i8
    %c3i = arith.index_castui %c3b : i8 to index
    %k3b = trikeshed.at %keep[%c3i] : !s, index -> i8
    %m3 = arith.andi %k3b, %b1 : i8
    %y3 = arith.cmpi ne, %m3, %z8 : i8
    %s3a = arith.muli %c3i, %four : index
    %s3b = arith.addi %s3a, %one : index
    %s3 = arith.select %y3, %s3a, %s3b : index
    %l3 = arith.select %y3, %one, %three : index
    %pc3 = trikeshed.slice %enc[%s3, %l3] : !s -> !s
    trikeshed.yield %pc3 : !s
  }
  // P4 url (git kinds) or id (indirect), raw
  %b0p = arith.select %is4, %id#0, %dflt : i64
  %b0l = arith.select %is4, %id#1, %z64 : i64
  %bp = arith.select %is3, %url#0, %b0p : i64
  %bl = arith.select %is3, %url#1, %b0l : i64
  %bpa = llvm.inttoptr %bp : i64 to !llvm.ptr
  %bd = func.call @fr_desc(%bpa, %bl) : (!llvm.ptr, i64) -> !d
  %bm = builtin.unrealized_conversion_cast %bd : !d to !m
  %p4 = builtin.unrealized_conversion_cast %bm : !m to !s
  // P5 '/' and P6 repo, encoded (github-like)
  %slb:2 = func.call @fr_word(%ws) : (index) -> (index, index)
  %l5 = arith.select %is1, %one, %z : index
  %p5 = trikeshed.slice %blob[%slb#0, %l5] : !s -> !s
  %rl6 = arith.select %is1, %repo#1, %z64 : i64
  %rpa = llvm.inttoptr %repo#0 : i64 to !llvm.ptr
  %rd6 = func.call @fr_desc(%rpa, %rl6) : (!llvm.ptr, i64) -> !d
  %rm6 = builtin.unrealized_conversion_cast %rd6 : !d to !m
  %rs6 = builtin.unrealized_conversion_cast %rm6 : !m to !s
  %rl6i = arith.index_cast %rl6 : i64 to index
  %p6, %p6c = trikeshed.combineAll %rl6i : !s, !sp {
  ^bb0(%u6: index):
    %c6b = trikeshed.at %rs6[%u6] : !s, index -> i8
    %c6i = arith.index_castui %c6b : i8 to index
    %k6b = trikeshed.at %keep[%c6i] : !s, index -> i8
    %m6 = arith.andi %k6b, %b1 : i8
    %y6 = arith.cmpi ne, %m6, %z8 : i8
    %s6a = arith.muli %c6i, %four : index
    %s6b = arith.addi %s6a, %one : index
    %s6 = arith.select %y6, %s6a, %s6b : index
    %l6 = arith.select %y6, %one, %three : index
    %pc6 = trikeshed.slice %enc[%s6, %l6] : !s -> !s
    trikeshed.yield %pc6 : !s
  }
  // P7 '/' before a rev or ref
  %hasrev = arith.cmpi ne, %rev#1, %z64 : i64
  %hasref = arith.cmpi ne, %ref#1, %z64 : i64
  %either = arith.ori %hasrev, %hasref : i1
  %g7 = arith.andi %is1, %either : i1
  %i7 = arith.andi %is4, %hasref : i1
  %s7 = arith.ori %g7, %i7 : i1
  %l7 = arith.select %s7, %one, %z : index
  %p7 = trikeshed.slice %blob[%slb#0, %l7] : !s -> !s
  // P8 ref encoded (github-like without a rev)
  %norev = arith.xori %hasrev, %true : i1
  %g8 = arith.andi %is1, %norev : i1
  %rl8 = arith.select %g8, %ref#1, %z64 : i64
  %fpa = llvm.inttoptr %ref#0 : i64 to !llvm.ptr
  %fd8 = func.call @fr_desc(%fpa, %rl8) : (!llvm.ptr, i64) -> !d
  %fm8 = builtin.unrealized_conversion_cast %fd8 : !d to !m
  %fs8 = builtin.unrealized_conversion_cast %fm8 : !m to !s
  %rl8i = arith.index_cast %rl8 : i64 to index
  %p8, %p8c = trikeshed.combineAll %rl8i : !s, !sp {
  ^bb0(%u8: index):
    %c8b = trikeshed.at %fs8[%u8] : !s, index -> i8
    %c8i = arith.index_castui %c8b : i8 to index
    %k8b = trikeshed.at %keep[%c8i] : !s, index -> i8
    %m8 = arith.andi %k8b, %b1 : i8
    %y8 = arith.cmpi ne, %m8, %z8 : i8
    %s8a = arith.muli %c8i, %four : index
    %s8b = arith.addi %s8a, %one : index
    %s8 = arith.select %y8, %s8a, %s8b : index
    %l8 = arith.select %y8, %one, %three : index
    %pc8 = trikeshed.slice %enc[%s8, %l8] : !s -> !s
    trikeshed.yield %pc8 : !s
  }
  // P9 ref raw (indirect), P10 '/' before an indirect rev, P11 rev raw
  %rl9 = arith.select %is4, %ref#1, %z64 : i64
  %rd9 = func.call @fr_desc(%fpa, %rl9) : (!llvm.ptr, i64) -> !d
  %rm9 = builtin.unrealized_conversion_cast %rd9 : !d to !m
  %p9 = builtin.unrealized_conversion_cast %rm9 : !m to !s
  %i10 = arith.andi %is4, %hasrev : i1
  %l10 = arith.select %i10, %one, %z : index
  %p10 = trikeshed.slice %blob[%slb#0, %l10] : !s -> !s
  %g11 = arith.ori %is1, %is4 : i1
  %rl11 = arith.select %g11, %rev#1, %z64 : i64
  %vpa = llvm.inttoptr %rev#0 : i64 to !llvm.ptr
  %vd11 = func.call @fr_desc(%vpa, %rl11) : (!llvm.ptr, i64) -> !d
  %vm11 = builtin.unrealized_conversion_cast %vd11 : !d to !m
  %p11 = builtin.unrealized_conversion_cast %vm11 : !m to !s
  // '?' and the rest: "k=v" joined by '&', keys and values encoded
  %qb:2 = func.call @fr_word(%wq) : (index) -> (index, index)
  %anyq = arith.cmpi ne, %kept, %z64 : i64
  %lq = arith.select %anyq, %one, %z : index
  %pq = trikeshed.slice %blob[%qb#0, %lq] : !s -> !s
  %ab:2 = func.call @fr_word(%wa) : (index) -> (index, index)
  %eb:2 = func.call @fr_word(%we) : (index) -> (index, index)
  %qa, %qac = trikeshed.combineAll %n : !s, !sp {
  ^bb0(%j: index):
    %ej64 = trikeshed.at %srt[%j] : !s64, index -> i64
    %ej = arith.index_cast %ej64 : i64 to index
    %tj = memref.load %tk[%ej] : !pm
    %fj = arith.cmpi eq, %tj, %z64 : i64
    %rj = memref.load %rk[%j] : !pm
    %later = arith.cmpi ne, %rj, %z64 : i64
    %sepj = arith.andi %fj, %later : i1
    %lsep = arith.select %sepj, %one, %z : index
    %psep = trikeshed.slice %blob[%ab#0, %lsep] : !s -> !s
    %keyj:2 = func.call @fr_ekey(%em, %ej) : (!m64, index) -> (i64, i64)
    %klj = arith.select %fj, %keyj#1, %z64 : i64
    %kpj = llvm.inttoptr %keyj#0 : i64 to !llvm.ptr
    %kdj = func.call @fr_desc(%kpj, %klj) : (!llvm.ptr, i64) -> !d
    %kmj = builtin.unrealized_conversion_cast %kdj : !d to !m
    %ksj = builtin.unrealized_conversion_cast %kmj : !m to !s
    %klji = arith.index_cast %klj : i64 to index
    %ek, %ekc = trikeshed.combineAll %klji : !s, !sp {
    ^bb0(%uk: index):
      %ckb = trikeshed.at %ksj[%uk] : !s, index -> i8
      %cki = arith.index_castui %ckb : i8 to index
      %kkb = trikeshed.at %keep[%cki] : !s, index -> i8
      %mk = arith.andi %kkb, %b2 : i8
      %yk = arith.cmpi ne, %mk, %z8 : i8
      %ska = arith.muli %cki, %four : index
      %skb = arith.addi %ska, %one : index
      %sk = arith.select %yk, %ska, %skb : index
      %lk = arith.select %yk, %one, %three : index
      %pck = trikeshed.slice %enc[%sk, %lk] : !s -> !s
      trikeshed.yield %pck : !s
    }
    %leq = arith.select %fj, %one, %z : index
    %peq = trikeshed.slice %blob[%eb#0, %leq] : !s -> !s
    %vb = arith.muli %ej, %two : index
    %vb1 = arith.addi %vb, %one : index
    %vpj = memref.load %vw[%vb] : !pm
    %vlj0 = memref.load %vw[%vb1] : !pm
    %vlj = arith.select %fj, %vlj0, %z64 : i64
    %vpja = llvm.inttoptr %vpj : i64 to !llvm.ptr
    %vdj = func.call @fr_desc(%vpja, %vlj) : (!llvm.ptr, i64) -> !d
    %vmj = builtin.unrealized_conversion_cast %vdj : !d to !m
    %vsj = builtin.unrealized_conversion_cast %vmj : !m to !s
    %vlji = arith.index_cast %vlj : i64 to index
    %ev, %evc = trikeshed.combineAll %vlji : !s, !sp {
    ^bb0(%uv: index):
      %cvb = trikeshed.at %vsj[%uv] : !s, index -> i8
      %cvi = arith.index_castui %cvb : i8 to index
      %kvb = trikeshed.at %keep[%cvi] : !s, index -> i8
      %mv = arith.andi %kvb, %b4 : i8
      %yv = arith.cmpi ne, %mv, %z8 : i8
      %sva = arith.muli %cvi, %four : index
      %svb = arith.addi %sva, %one : index
      %sv = arith.select %yv, %sva, %svb : index
      %lv = arith.select %yv, %one, %three : index
      %pcv = trikeshed.slice %enc[%sv, %lv] : !s -> !s
      trikeshed.yield %pcv : !s
    }
    %piece = trikeshed.combine %psep, %ek, %peq, %ev : !s, !s, !s, !s -> !s
    trikeshed.yield %piece : !s
  }
  %all = trikeshed.combine %p1, %p2, %p3, %p4, %p5, %p6, %p7, %p8, %p9, %p10, %p11, %pq, %qa : !s, !s, !s, !s, !s, !s, !s, !s, !s, !s, !s, !s, !s -> !s
  %od = func.call @fr_desc(%into, %cap) : (!llvm.ptr, i64) -> !d
  %om = builtin.unrealized_conversion_cast %od : !d to !m
  %end = trikeshed.drain %all, %om : !s, !m -> index
  %r = arith.index_cast %end : index to i64
  return %r : i64
}

// flakeRefToString's whole text algebra over the forced attributes: n entries of 5 i64 at ents (key address, key
// length, value address, value length or the int/bool, kind 0 string / 1 int >= 0 / 2 bool).  The bridge sized
// `into` (cap bytes) so that its last 21 n bytes hold the ints' digits.  Returns the bytes written, -1 when the type
// is missing or empty, or -(L) - 2 for an unsupported type whose text (L bytes) is at into.
func.func @nixev_ts_flake_unparse(%ents: !llvm.ptr, %n: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %z = arith.constant 0 : index
  %one = arith.constant 1 : index
  %two = arith.constant 2 : index
  %three = arith.constant 3 : index
  %four = arith.constant 4 : index
  %five = arith.constant 5 : index
  %twentyone = arith.constant 21 : index
  %z64 = arith.constant 0 : i64
  %one64 = arith.constant 1 : i64
  %two64 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %five64 = arith.constant 5 : i64
  %m1 = arith.constant -1 : i64
  %c21 = arith.constant 21 : i64
  %w0 = arith.constant 0 : index
  %w2 = arith.constant 2 : index
  %wpath = arith.constant 3 : index
  %wfile = arith.constant 10 : index
  %wmerc = arith.constant 12 : index
  %wtar = arith.constant 13 : index
  %wind = arith.constant 14 : index
  %wtype = arith.constant 15 : index
  %wgit = arith.constant 42 : index
  %ni = arith.index_cast %n : i64 to index
  %n5 = arith.muli %n, %five64 : i64
  %ed = func.call @fr_desc(%ents, %n5) : (!llvm.ptr, i64) -> !d
  %em = builtin.unrealized_conversion_cast %ed : !d to !m64
  %n21 = arith.muli %n, %c21 : i64
  %base = arith.subi %cap, %n21 : i64
  %n2 = arith.muli %ni, %two : index
  %vw = memref.alloc(%n2) : !pm
  // each value as a window: a string's own bytes, an int's or bool's digits in the scratch tail
  scf.for %e = %z to %ni step %one {
    %eb = arith.muli %e, %five : index
    %eb2 = arith.addi %eb, %two : index
    %eb3 = arith.addi %eb, %three : index
    %eb4 = arith.addi %eb, %four : index
    %kind = memref.load %em[%eb4] : !m64
    %vp = memref.load %em[%eb2] : !m64
    %vx = memref.load %em[%eb3] : !m64
    %isstr = arith.cmpi eq, %kind, %z64 : i64
    %w:2 = scf.if %isstr -> (i64, i64) {
      scf.yield %vp, %vx : i64, i64
    } else {
      %e64 = arith.index_cast %e : index to i64
      %eo = arith.muli %e64, %c21 : i64
      %off = arith.addi %base, %eo : i64
      %dp = llvm.getelementptr %into[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %dl = func.call @fr_digits(%vx, %dp) : (i64, !llvm.ptr) -> i64
      %dpi = llvm.ptrtoint %dp : !llvm.ptr to i64
      scf.yield %dpi, %dl : i64, i64
    }
    %vb = arith.muli %e, %two : index
    %vb1 = arith.addi %vb, %one : index
    memref.store %w#0, %vw[%vb] : !pm
    memref.store %w#1, %vw[%vb1] : !pm
  }
  %t = func.call @fr_ekeyfind(%em, %ni, %wtype) : (!m64, index, index) -> index
  %has = arith.cmpi ult, %t, %ni : index
  %r = scf.if %has -> (i64) {
    %tb = arith.muli %t, %two : index
    %tb1 = arith.addi %tb, %one : index
    %tp = memref.load %vw[%tb] : !pm
    %tl = memref.load %vw[%tb1] : !pm
    %empty = arith.cmpi eq, %tl, %z64 : i64
    %r2 = scf.if %empty -> (i64) {
      scf.yield %m1 : i64
    } else {
      %tpa = llvm.inttoptr %tp : i64 to !llvm.ptr
      %td = func.call @fr_desc(%tpa, %tl) : (!llvm.ptr, i64) -> !d
      %tm = builtin.unrealized_conversion_cast %td : !d to !m
      %ts = builtin.unrealized_conversion_cast %tm : !m to !s
      %tli = arith.index_cast %tl : i64 to index
      %k1 = func.call @fr_in(%ts, %z, %tli, %w0, %w2) : (!s, index, index, index, index) -> i1
      %k2 = func.call @fr_is(%ts, %z, %tli, %wpath) : (!s, index, index, index) -> i1
      %kg = func.call @fr_is(%ts, %z, %tli, %wgit) : (!s, index, index, index) -> i1
      %km = func.call @fr_is(%ts, %z, %tli, %wmerc) : (!s, index, index, index) -> i1
      %kt = func.call @fr_is(%ts, %z, %tli, %wtar) : (!s, index, index, index) -> i1
      %kf = func.call @fr_is(%ts, %z, %tli, %wfile) : (!s, index, index, index) -> i1
      %k4 = func.call @fr_is(%ts, %z, %tli, %wind) : (!s, index, index, index) -> i1
      %gm = arith.ori %kg, %km : i1
      %tf = arith.ori %kt, %kf : i1
      %k3 = arith.ori %gm, %tf : i1
      %c34 = arith.select %k3, %c3, %c4 : i64
      %c234 = arith.select %k2, %two64, %c34 : i64
      %cls = arith.select %k1, %one64, %c234 : i64
      %a12 = arith.ori %k1, %k2 : i1
      %a34 = arith.ori %k3, %k4 : i1
      %known = arith.ori %a12, %a34 : i1
      %r3 = scf.if %known -> (i64) {
        %x = func.call @fr_compose(%em, %vw, %ni, %into, %cap, %tp, %tl, %cls, %km) : (!m64, !pm, index, !llvm.ptr, i64, i64, i64, i64, i1) -> i64
        scf.yield %x : i64
      } else {
        %od = func.call @fr_desc(%into, %tl) : (!llvm.ptr, i64) -> !d
        %om = builtin.unrealized_conversion_cast %od : !d to !m
        %e = trikeshed.drain %ts, %om : !s, !m -> index
        %neg = arith.subi %z64, %tl : i64
        %st = arith.subi %neg, %two64 : i64
        scf.yield %st : i64
      }
      scf.yield %r3 : i64
    }
    scf.yield %r2 : i64
  } else {
    scf.yield %m1 : i64
  }
  return %r : i64
}
