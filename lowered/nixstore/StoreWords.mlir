// The words of the store's build and add path (lib/Store/LocalStore.cpp's realise, runBuilder, builtinFetchurl,
// addToStore, the walks and the derivation's hash; lib/Store/StorePaths.cpp's runProgram): every error they return
// with and every line they log, as data.  A message is a run of bytes in one constant text; its bytes 1 to 5 stand for
// what the caller gives (1, 2, 3 its three texts, 4 the system's words for an error number, 5 a number in decimal).
//
//   nixsb_say   one message composed and handed over: a combineAll over the message's bytes (a byte of its own, or the
//               text it stands for: one combine of six slices, all but one empty), drained once into a room of its
//               size.  `how` 0: the error the call returns with (nixstore::Error; the caller returns 1); 1: the same as
//               std::out_of_range (SortedMap::at's); 2: a line of the store's log; 3: the bytes to standard error (a
//               builder that could not be run says so itself).  Returns 1 for an error, 0 for a line.
//
// The globals are made by store-words.py (kept with the module's proofs, outside this repository): a message added
// there is a number added here.  The store keeps the error (nixsb_fail) and throws it once, where the call returns
// (LocalStore.cpp's Sb); nothing here is left allocated.
// Lowered by --trikeshed-lower-cursors and the stock buffer pipeline (lib/CMakeLists.txt mlnix_lower_trikeshed).
!s = !trikeshed.series<i8>
!s32 = !trikeshed.series<i32>
!tp = !trikeshed.twinpacked<i32>
!pieces = !trikeshed.series<!tp>
!m = memref<?xi8, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

// The words, by number (<a> <b> <c> the caller's three texts, <e> the system's words for its error number, <n> its
// number in decimal):
//    0  getting attributes of '<a>'
//    1  getting status of '<a>': <e>
//    2  creating directory '<a>': <e>
//    3  opening directory '<a>'
//    4  reading symlink '<a>'
//    5  creating symlink '<a>': <e>
//    6  file '<a>' has an unsupported type
//    7  hash mismatch importing path '<a>';\n  specified: <b>\n  got:       <c>
//    8  cycle in derivation graph at '<a>'
//    9  cannot build derivation '<a>': content-addressed/impure outputs are not supported
//   10  cannot build '<a>' in read-only mode
//   11  cannot build '<a>': the store directory '<b>' is not physically accessible (chroot store at '<c>'); use --store-dir with a writable directory to build
//   12  derivation '<a>' does not have output '<b>'
//   13  building '<a>'...
//   14  builder for '<a>' failed to produce output path for output '<b>' at '<c>'
//   15  hash mismatch in fixed-output derivation '<a>':\n         specified: <b>\n            got:    <c>
//   16  creating build directory: <e>
//   17  fork failed
//   18  builder for '<a>' failed with exit code <n>
//   19  builder for '<a>' was killed by signal <n>
//   20  note: keeping build directory '<a>'
//   21  error: executing '<a>': <e>\n
//   22  builtin:fetchurl: no URL specified
//   23  unable to download '<a>': curl exited with code <n>
//   24  pipe failed
//   25  content-addressed and impure derivations are not supported (derivation '<a>')
//   26  no hash for output '<a>' of derivation '<b>'
//   27  no entry '<a>'
memref.global "private" constant @sbs_text : memref<1122xi8> =
  dense<"0x67657474696e672061747472696275746573206f662027012767657474696e6720737461747573206f66202701273a20046372656174696e67206469726563746f7279202701273a20046f70656e696e67206469726563746f72792027012772656164696e672073796d6c696e6b202701276372656174696e672073796d6c696e6b202701273a200466696c65202701272068617320616e20756e737570706f72746564207479706568617368206d69736d6174636820696d706f7274696e672070617468202701273b0a20207370656369666965643a20020a2020676f743a20202020202020036379636c6520696e2064657269766174696f6e2067726170682061742027012763616e6e6f74206275696c642064657269766174696f6e202701273a20636f6e74656e742d6164647265737365642f696d70757265206f75747075747320617265206e6f7420737570706f7274656463616e6e6f74206275696c642027012720696e20726561642d6f6e6c79206d6f646563616e6e6f74206275696c64202701273a207468652073746f7265206469726563746f727920270227206973206e6f7420706879736963616c6c792061636365737369626c6520286368726f6f742073746f726520617420270327293b20757365202d2d73746f72652d64697220776974682061207772697461626c65206469726563746f727920746f206275696c6464657269766174696f6e2027012720646f6573206e6f742068617665206f7574707574202702276275696c64696e67202701272e2e2e6275696c64657220666f7220270127206661696c656420746f2070726f64756365206f7574707574207061746820666f72206f7574707574202702272061742027032768617368206d69736d6174636820696e2066697865642d6f75747075742064657269766174696f6e202701273a0a2020202020202020207370656369666965643a20020a202020202020202020202020676f743a20202020036372656174696e67206275696c64206469726563746f72793a2004666f726b206661696c65646275696c64657220666f7220270127206661696c65642077697468206578697420636f646520056275696c64657220666f722027012720776173206b696c6c6564206279207369676e616c20056e6f74653a206b656570696e67206275696c64206469726563746f7279202701276572726f723a20657865637574696e67202701273a20040a6275696c74696e3a666574636875726c3a206e6f2055524c20737065636966696564756e61626c6520746f20646f776e6c6f6164202701273a206375726c20657869746564207769746820636f6465200570697065206661696c6564636f6e74656e742d61646472657373656420616e6420696d707572652064657269766174696f6e7320617265206e6f7420737570706f72746564202864657269766174696f6e20270127296e6f206861736820666f72206f757470757420270127206f662064657269766174696f6e202702276e6f20656e74727920270127">
memref.global "private" constant @sbs_off : memref<28xi32> = dense<[0, 25, 49, 74, 95, 114, 137, 169, 232, 264, 343, 377, 521, 560, 575, 642, 731, 758, 769, 808, 846, 879, 903, 937, 984, 995, 1070, 1110]>
memref.global "private" constant @sbs_len : memref<28xi32> = dense<[25, 24, 25, 21, 19, 23, 32, 63, 32, 79, 34, 144, 39, 15, 67, 89, 27, 11, 39, 38, 33, 24, 34, 47, 11, 75, 40, 12]>

// the C library
func.func private @strerror(i32) -> !llvm.ptr
func.func private @strlen(!llvm.ptr) -> i64
func.func private @write(i32, !llvm.ptr, i64) -> i64
// the system's module (StoreBuildDarwin.mlir.in, StoreBuildLinux.mlir.in): the C library's realloc and free
func.func private @nixsb_os_grow(!llvm.ptr, i64) -> !llvm.ptr
func.func private @nixsb_os_free(!llvm.ptr)
// the store's (lib/Store/LocalStore.cpp): the error a call returns with (kind 0 nixstore::Error, 1 std::out_of_range),
// a line of its log
func.func private @nixsb_fail(!llvm.ptr, i64, !llvm.ptr, i64)
func.func private @nixsb_log(!llvm.ptr, !llvm.ptr, i64)

// the descriptor of n bytes at p
func.func private @sbs_d(%p: !llvm.ptr, %n: i64) -> !d {
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

func.func @nixsb_say(%c: !llvm.ptr, %how: i64, %id: i64, %ap: !llvm.ptr, %an: i64, %bp: !llvm.ptr, %bn: i64,
                     %dp: !llvm.ptr, %dn: i64, %e: i64, %num: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c10 = arith.constant 10 : i64
  %c48 = arith.constant 48 : i64
  %b1 = arith.constant 1 : i8
  %b2 = arith.constant 2 : i8
  %b3 = arith.constant 3 : i8
  %b4 = arith.constant 4 : i8
  %b5 = arith.constant 5 : i8
  %fd2 = arith.constant 2 : i32
  %z = arith.constant 0 : index
  %i1 = arith.constant 1 : index
  %c4096 = arith.constant 4096 : i64
  %short = llvm.alloca %c4096 x i8 : (i64) -> !llvm.ptr
  // the message: its run of the text
  %tg = memref.get_global @sbs_text : memref<1122xi8>
  %text = trikeshed.text %tg : memref<1122xi8> -> !s
  %og = memref.get_global @sbs_off : memref<28xi32>
  %offs = trikeshed.text %og : memref<28xi32> -> !s32
  %lg = memref.get_global @sbs_len : memref<28xi32>
  %lens = trikeshed.text %lg : memref<28xi32> -> !s32
  %idi = arith.index_cast %id : i64 to index
  %off32 = trikeshed.at %offs[%idi] : !s32, index -> i32
  %len32 = trikeshed.at %lens[%idi] : !s32, index -> i32
  %off = arith.index_castui %off32 : i32 to index
  %len = arith.index_castui %len32 : i32 to index
  %tpl = trikeshed.slice %text[%off, %len] : !s -> !s
  // what the caller gives: its three texts, the system's words for its error number (none below 0), its number's digits
  %a_d = func.call @sbs_d(%ap, %an) : (!llvm.ptr, i64) -> !d
  %a_m = builtin.unrealized_conversion_cast %a_d : !d to !m
  %a = builtin.unrealized_conversion_cast %a_m : !m to !s
  %b_d = func.call @sbs_d(%bp, %bn) : (!llvm.ptr, i64) -> !d
  %b_m = builtin.unrealized_conversion_cast %b_d : !d to !m
  %b = builtin.unrealized_conversion_cast %b_m : !m to !s
  %d_d = func.call @sbs_d(%dp, %dn) : (!llvm.ptr, i64) -> !d
  %d_m = builtin.unrealized_conversion_cast %d_d : !d to !m
  %d = builtin.unrealized_conversion_cast %d_m : !m to !s
  %hase = arith.cmpi sge, %e, %c0 : i64
  %ep, %en = scf.if %hase -> (!llvm.ptr, i64) {
    %e32 = arith.trunci %e : i64 to i32
    %sp = func.call @strerror(%e32) : (i32) -> !llvm.ptr
    %sn = func.call @strlen(%sp) : (!llvm.ptr) -> i64
    scf.yield %sp, %sn : !llvm.ptr, i64
  } else {
    scf.yield %ap, %c0 : !llvm.ptr, i64
  }
  %e_d = func.call @sbs_d(%ep, %en) : (!llvm.ptr, i64) -> !d
  %e_m = builtin.unrealized_conversion_cast %e_d : !d to !m
  %es = builtin.unrealized_conversion_cast %e_m : !m to !s
  %nd:2 = scf.while (%v = %num, %k0 = %i1) : (i64, index) -> (i64, index) {
    %more = arith.cmpi uge, %v, %c10 : i64
    scf.condition(%more) %v, %k0 : i64, index
  } do {
  ^bb0(%v1: i64, %k1: index):
    %q = arith.divui %v1, %c10 : i64
    %k2 = arith.addi %k1, %i1 : index
    scf.yield %q, %k2 : i64, index
  }
  %digits = trikeshed.series %nd#1 : !s {
  ^bb0(%k: index):
    %last = arith.subi %nd#1, %i1 : index
    %pw = arith.subi %last, %k : index
    %q = scf.for %j = %z to %pw step %i1 iter_args(%v = %num) -> (i64) {
      %v2 = arith.divui %v, %c10 : i64
      scf.yield %v2 : i64
    }
    %dig = arith.remui %q, %c10 : i64
    %ch = arith.addi %dig, %c48 : i64
    %ch8 = arith.trunci %ch : i64 to i8
    trikeshed.yield %ch8 : i8
  }
  %ani = arith.index_cast %an : i64 to index
  %bni = arith.index_cast %bn : i64 to index
  %dni = arith.index_cast %dn : i64 to index
  %eni = arith.index_cast %en : i64 to index
  // each byte of the message: itself, or the text it stands for
  %msg, %where = trikeshed.combineAll %len : !s, !pieces {
  ^bb0(%k: index):
    %ch = trikeshed.at %tpl[%k] : !s, index -> i8
    %isa = arith.cmpi eq, %ch, %b1 : i8
    %isb = arith.cmpi eq, %ch, %b2 : i8
    %isd = arith.cmpi eq, %ch, %b3 : i8
    %ise = arith.cmpi eq, %ch, %b4 : i8
    %isn = arith.cmpi eq, %ch, %b5 : i8
    %own = arith.cmpi ugt, %ch, %b5 : i8
    %ln = arith.select %own, %i1, %z : index
    %ak = arith.select %isa, %ani, %z : index
    %bk = arith.select %isb, %bni, %z : index
    %dk = arith.select %isd, %dni, %z : index
    %ek = arith.select %ise, %eni, %z : index
    %nk = arith.select %isn, %nd#1, %z : index
    %lit = trikeshed.slice %tpl[%k, %ln] : !s -> !s
    %pa = trikeshed.slice %a[%z, %ak] : !s -> !s
    %pb = trikeshed.slice %b[%z, %bk] : !s -> !s
    %pd = trikeshed.slice %d[%z, %dk] : !s -> !s
    %pe = trikeshed.slice %es[%z, %ek] : !s -> !s
    %pn = trikeshed.slice %digits[%z, %nk] : !s -> !s
    %piece = trikeshed.combine %lit, %pa, %pb, %pd, %pe, %pn : !s, !s, !s, !s, !s, !s -> !s
    trikeshed.yield %piece : !s
  }
  // its room: on the stack when it is short (a builder's child process allocates nothing for its one message)
  %size = trikeshed.size %msg : !s
  %size64 = arith.index_cast %size : index to i64
  %long = arith.cmpi ugt, %size64, %c4096 : i64
  %null = llvm.mlir.zero : !llvm.ptr
  %heap = scf.if %long -> (!llvm.ptr) {
    %hp = func.call @nixsb_os_grow(%null, %size64) : (!llvm.ptr, i64) -> !llvm.ptr
    scf.yield %hp : !llvm.ptr
  } else {
    scf.yield %null : !llvm.ptr
  }
  %room = scf.if %long -> (!llvm.ptr) {
    scf.yield %heap : !llvm.ptr
  } else {
    scf.yield %short : !llvm.ptr
  }
  %rd = func.call @sbs_d(%room, %size64) : (!llvm.ptr, i64) -> !d
  %rm = builtin.unrealized_conversion_cast %rd : !d to !m
  %end = trikeshed.drain %msg, %rm : !s, !m -> index
  %isline = arith.cmpi eq, %how, %c2 : i64
  %iserr = arith.cmpi eq, %how, %c3 : i64
  %res = scf.if %isline -> (i64) {
    func.call @nixsb_log(%c, %room, %size64) : (!llvm.ptr, !llvm.ptr, i64) -> ()
    scf.yield %c0 : i64
  } else {
    %r = scf.if %iserr -> (i64) {
      %w = func.call @write(%fd2, %room, %size64) : (i32, !llvm.ptr, i64) -> i64
      scf.yield %c0 : i64
    } else {
      func.call @nixsb_fail(%c, %how, %room, %size64) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
      scf.yield %c1 : i64
    }
    scf.yield %r : i64
  }
  func.call @nixsb_os_free(%heap) : (!llvm.ptr) -> ()
  return %res : i64
}
