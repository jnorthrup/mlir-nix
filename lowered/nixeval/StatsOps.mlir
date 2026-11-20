// The MLNIX_STATS report (EvalState::printStats) hollowed out of lib/Eval/Eval.cpp: every line's composition is
// ONE variadic trikeshed.combine of pieces (constant label slices, unsigned decimal drains of the counters, the
// float/name windows the bridge formats, padded fields), drained once into the caller's room.  The ranked lists
// (scopes/continents/dialects, top ops, evalOp kinds, the son-gap ops) and the lambda-pool meta-name join are nested
// combineAll over the rows/windows.  The C++ bridge reads the counters, formats the floats (snprintf), ranks the
// tables (cp::sortRows) and keeps the conditionals and the llvm::errs() write; the pieces are pure reads, so the
// combineAll's two region passes (size then drain) need no cache.  One entry
//   nixev_ts_stats(kind, vals, wins, rows, nrows, into, cap) -> the line's byte count (drains only when cap >= it)
// vals: i64[8] counters; wins: {ptr,len}[8] windows; rows: 64-byte records {namePtr,nameLen,a,b,c,fptr,flen,pad}.
!text = !trikeshed.series<i8>
!s32 = !trikeshed.series<i32>
!s64 = !trikeshed.series<i64>
!m8 = memref<?xi8, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>
!coords = !trikeshed.series<!trikeshed.twinpacked<i32>>

memref.global "private" constant @st_blob : memref<2642xi8> = dense<"0x6174747269627574652063656c6c733a2062797465733d20706f736974696f6e5f726f77733d20706f736974696f6e5f62797465733d0a6672616d6520616c6c6f636174696f6e733a20636f756e743d2062797465733d20736c6f74733d3d3d206172656e613a20204d42206f6620736c6162733b207065616b2052535320204d422e204279207573653a2076616c7565732020282063656c6c73292c206672616d6573202c2061747472696275746520726f7773202c206c6973742063656c6c73202c20737472696e67206279746573202c206f7468657220616e6420736c61636b20204d420a202020226f7468657222206e616d65643a206672616d6520737461747320776f72647320204d422028612073746174732072756e206f6e6c79292c20602f2f6020666c6174206d6572676573202c206c617965722068656164657273202c20737472696e6720636f6e7465787473202c20666f726d616c73203b207374696c6c20756e6e616d65642028736c6162207461696c732c20616c69676e6d656e742920202020602b2b602077726f7465202063656c6c7320696e746f206120627566666572277320726f6f6d20284c697374457874656e742920696e7374656164206f6620636f7079696e6720697473206f7468657220736964650a76616c756573206576616c756174656420617420746865697220666972737420746f7563682c206e657665722061207468756e6b20287468652063616c6c657220666f72636573207468656d206e657874293a203d3d207265736964656e7420617420657869743a20204d4220616e6f6e796d6f757320286172656e6120202b20204d42206f6620686561702c20495220616e64207468652072657374292c20204d422066696c652d6261636b656420286d617070656420736f757263657320616e64207468652062696e617279293b20686967682d7761746572206d61726b203d3d206576616c7561746f72207468726561643a20757365722020732c2073797374656d2020733b2020766f6c756e7461727920636f6e746578742073776974636865732028697420626c6f636b6564292c2020696e766f6c756e746172793b20206d696e6f72206661756c74732c20206d616a6f720a3d3d207065722d66696c6520706f6f6c7320282066696c6573293a20436f6e6669782062616e64732020726f77732028204d4229202b202073746174656d656e7420656e64732028204d4229202b206f70656e696e6720696e6465782020656e74726965732028204d42293b206c616d62646120726f777320204d42292c206e616d657320204d422c2066726565206e616d657320204d422c207365656e203d3d20736f6e2773206163636f756e74206f6620746865206672616d65732061742074686569722072657475726e20284d4c4e49585f5354415453293a20206f6620206c616d62646120626f6469657320646561642061742072657475726e20627920736f6e20286e6f20636c6f737572652c2065766572792076616c75652061207573652074616b6573206c617a696c7920666f72636564206f6e206576657279207061746820746861742072657475726e73293b206f66202072657475726e732028204d42206f66206672616d6573292c2064656164206279207468652072756e20286e6f20636c6f737572652c206576657279207468756e6b206f766572207468656d20666f726365642c2070726f6a656374696f6e7320746f6f2920252c20204d42292c206465616420627920736f6e20204d42293b20736f6e2077726f6e6720286465616420627920736f6e2c206e6f74206279207468652072756e293a2020202064656164206279207468652072756e2c206e6f7420627920736f6e2c2062792077687920736f6e206b6565707320746865206672616d653a2074686520626f6479206d616b6573206120636c6f73757265202c20612076616c756520666f72636564206f6e20736f6d65207061746820746861742072657475726e73206f6e6c79202c20612076616c75652070617373656420746f20612063616c6c656520736f6e20646f6573206e6f7420736565202c20612076616c756520706173736564206f6e20756e666f7263656420202020746865206f702077686f7365206c617a792075736520646563696465732028706174682c2063616c6c65652c20706173736564206f6e293a63616c6c732072756e206f6e206120737461636b206672616d65202873747269637420626f64696573206f766572207468656972206f6e6520617267756d656e74293a2073656c6563746f722063616c6c732077697468206e6f206672616d6520286c69622e6f7074696f6e616c2c206c69622e6f7074696f6e616c417474727320736861706573293a206375727269656420696e7465726d656469617465732068656c642062792076616c75653a20206279746573206f6620686561702063656c6c73206e6f7420616c6c6f6361746564290a656d7074792061747472696275746520736574733a2020736861726564206173206f6e6520636f6e7374616e742028206279746573206e6f7420616c6c6f6361746564290a76616c756520616c6c6f636174696f6e733a20636f756e743d3d3d20736561206f66206e6f6465733a202066696c6520726567696f6e7320686f6c6420206f707320282520657665722072616e2c20206576616c732c20207468756e6b2063656c6c73293b20206d696e74656420626f6469657320686f6c6420207468756e6b2063656c6c73292e202046696e657220677261696e206d696e747320612063656c6c3a20746865207468756e6b2063656c6c73206172652069747320726f777320616761696e7374206c616d62646120677261696e2773203d3d207072656c6f776572696e673a202066696c65732061646f707465642028206f66207468656d2077616974656420666f72292c20206c6f776572656420627920746865206576616c7561746f720a3d3d2073796d626f6c733a2020696e7465726e696e672063616c6c732c202073796d626f6c730a3d3d206576616c4f702063616c6c73206279206f70206b696e64202820696e20616c6c290a3d3d206d6c6e6978206f7073206c6f77657265643a203d3d20602f2f603a20206d65726765732c2020656e747269657320636f706965640a3d3d206c6f776572696e6720206d73202874686520616e616c79736973206f66206465666572726564206c616d6264617320696e636c75646564292c206d696e746564206f6e2064656d616e6420206d730a3d3d207265616420706c616e3a20206e616d657320706f6f6c65643b20206c616d6264617320736b696d6d656420616e64206e6f7420796574207265616368656420282066726565206e616d6573206b657074290a3d3d206c616d62646120706f6f6c733a202066696c65732c20282c20292c2020726f77732064656665727265642c2020647261696e65642028626f6479206d696e746564206f6e20612066697273742063616c6c292c20206e657665722063616c6c65640a3d3d2073636f7065732028290a3d3d20636f6e74696e656e747320283d3d206469616c6563747320283d3d20746f70206f70730a2020202f25">
memref.global "private" constant @st_off : memref<114xi32> = dense<[0, 23, 38, 54, 55, 80, 87, 94, 104, 127, 147, 149, 165, 182, 195, 210, 228, 232, 268, 309, 325, 343, 353, 393, 407, 482, 566, 587, 608, 611, 642, 707, 733, 744, 748, 790, 804, 819, 826, 845, 867, 874, 881, 898, 919, 929, 947, 959, 975, 985, 1047, 1051, 1171, 1181, 1273, 1276, 1294, 1341, 1426, 1474, 1520, 1549, 1608, 1676, 1747, 1784, 1820, 1842, 1867, 1889, 1914, 1931, 1950, 1956, 1968, 1976, 1991, 2011, 2105, 2121, 2137, 2159, 2185, 2197, 2215, 2224, 2252, 2261, 2283, 2292, 2301, 2317, 2329, 2395, 2399, 2413, 2428, 2466, 2484, 2501, 2510, 2512, 2515, 2531, 2571, 2585, 2596, 2598, 2613, 2626, 2637, 2639, 2640, 2641]>
memref.global "private" constant @st_len : memref<114xi32> = dense<[23, 15, 16, 1, 25, 7, 7, 10, 23, 20, 2, 16, 17, 13, 15, 18, 4, 36, 41, 16, 18, 10, 40, 14, 75, 84, 21, 21, 3, 31, 65, 26, 11, 4, 42, 14, 15, 7, 19, 22, 7, 7, 17, 21, 10, 18, 12, 16, 10, 62, 4, 120, 10, 92, 3, 18, 47, 85, 48, 46, 29, 59, 68, 71, 37, 36, 22, 25, 22, 25, 17, 19, 6, 12, 8, 15, 20, 94, 16, 16, 22, 26, 12, 18, 9, 28, 9, 22, 9, 9, 16, 12, 66, 4, 14, 15, 38, 18, 17, 9, 2, 3, 16, 40, 14, 11, 2, 15, 13, 11, 2, 1, 1, 1]>
memref.global "private" constant @st_pow : memref<20xi64> = dense<[1, 10, 100, 1000, 10000, 100000, 1000000, 10000000, 100000000, 1000000000, 10000000000, 100000000000, 1000000000000, 10000000000000, 100000000000000, 1000000000000000, 10000000000000000, 100000000000000000, 1000000000000000000, -8446744073709551616]>
memref.global "private" constant @st_sp : memref<32xi8> = dense<32>

func.func private @st_desc8(%p: !llvm.ptr, %n: i64) -> !d {
  %c1 = arith.constant 0 : i64
  %c2 = arith.constant 1 : i64
  %u3 = llvm.mlir.undef : !d
  %a4 = llvm.insertvalue %p, %u3[0] : !d
  %b5 = llvm.insertvalue %p, %a4[1] : !d
  %c6 = llvm.insertvalue %c1, %b5[2] : !d
  %e7 = llvm.insertvalue %n, %c6[3, 0] : !d
  %g8 = llvm.insertvalue %c2, %e7[4, 0] : !d
  return %g8 : !d
}

func.func private @st_word(%wid: index) -> (index, index) {
  %og1 = memref.get_global @st_off : memref<114xi32>
  %offs2 = trikeshed.text %og1 : memref<114xi32> -> !s32
  %lg3 = memref.get_global @st_len : memref<114xi32>
  %lens4 = trikeshed.text %lg3 : memref<114xi32> -> !s32
  %o5 = trikeshed.at %offs2[%wid] : !s32, index -> i32
  %l6 = trikeshed.at %lens4[%wid] : !s32, index -> i32
  %oi7 = arith.index_cast %o5 : i32 to index
  %li8 = arith.index_cast %l6 : i32 to index
  return %oi7, %li8 : index, index
}

func.func private @st_dcount(%mag: i64) -> index {
  %c1 = arith.constant 1 : index
  %c4 = arith.constant 19 : index
  %pg2 = memref.get_global @st_pow : memref<20xi64>
  %powers3 = trikeshed.text %pg2 : memref<20xi64> -> !s64
  %above5 = trikeshed.slice %powers3[%c1, %c4] : !s64 -> !s64
  %cnt6 = trikeshed.fold %above5, %c1 : !s64, index -> index {
  ^bb0(%acc: index, %p: i64):
    %reach7 = arith.cmpi uge, %mag, %p : i64
    %more8 = arith.addi %acc, %c1 : index
    %rr9 = arith.select %reach7, %more8, %acc : index
    trikeshed.yield %rr9 : index
  }
  return %cnt6 : index
}

func.func private @st_l_0(%vals: !llvm.ptr, %wins: !llvm.ptr, %rows: !llvm.ptr, %nrows: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %c3 = arith.constant 0 : index
  %c5 = arith.constant 0 : i64
  %c12 = arith.constant 1 : index
  %c17 = arith.constant 10 : i64
  %c20 = arith.constant 48 : i8
  %c25 = arith.constant 1 : i64
  %c41 = arith.constant 2 : index
  %c43 = arith.constant 2 : i64
  %c59 = arith.constant 3 : index
  %di = func.call @st_desc8(%into, %cap) : (!llvm.ptr, i64) -> !d
  %mi = builtin.unrealized_conversion_cast %di : !d to !m8
  %bg = memref.get_global @st_blob : memref<2642xi8>
  %blob = trikeshed.text %bg : memref<2642xi8> -> !text
  %spg = memref.get_global @st_sp : memref<32xi8>
  %sp = trikeshed.text %spg : memref<32xi8> -> !text
  %ws1, %wl2 = func.call @st_word(%c3) : (index) -> (index, index)
  %w4 = trikeshed.slice %blob[%ws1, %wl2] : !text -> !text
  %vp6 = llvm.getelementptr %vals[%c5] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv7 = llvm.load %vp6 : !llvm.ptr -> i64
  %dc8 = func.call @st_dcount(%vv7) : (i64) -> index
  %pg9 = memref.get_global @st_pow : memref<20xi64>
  %powers10 = trikeshed.text %pg9 : memref<20xi64> -> !s64
  %digits11 = trikeshed.series %dc8 : !text {
  ^bb0(%k: index):
    %last13 = arith.subi %dc8, %c12 : index
    %e14 = arith.subi %last13, %k : index
    %p15 = trikeshed.at %powers10[%e14] : !s64, index -> i64
    %q16 = arith.divui %vv7, %p15 : i64
    %dd18 = arith.remui %q16, %c17 : i64
    %d819 = arith.trunci %dd18 : i64 to i8
    %ch21 = arith.addi %d819, %c20 : i8
    trikeshed.yield %ch21 : i8
  }
  %ws22, %wl23 = func.call @st_word(%c12) : (index) -> (index, index)
  %w24 = trikeshed.slice %blob[%ws22, %wl23] : !text -> !text
  %vp26 = llvm.getelementptr %vals[%c25] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv27 = llvm.load %vp26 : !llvm.ptr -> i64
  %dc28 = func.call @st_dcount(%vv27) : (i64) -> index
  %pg29 = memref.get_global @st_pow : memref<20xi64>
  %powers30 = trikeshed.text %pg29 : memref<20xi64> -> !s64
  %digits31 = trikeshed.series %dc28 : !text {
  ^bb0(%k: index):
    %last32 = arith.subi %dc28, %c12 : index
    %e33 = arith.subi %last32, %k : index
    %p34 = trikeshed.at %powers30[%e33] : !s64, index -> i64
    %q35 = arith.divui %vv27, %p34 : i64
    %dd36 = arith.remui %q35, %c17 : i64
    %d837 = arith.trunci %dd36 : i64 to i8
    %ch38 = arith.addi %d837, %c20 : i8
    trikeshed.yield %ch38 : i8
  }
  %ws39, %wl40 = func.call @st_word(%c41) : (index) -> (index, index)
  %w42 = trikeshed.slice %blob[%ws39, %wl40] : !text -> !text
  %vp44 = llvm.getelementptr %vals[%c43] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv45 = llvm.load %vp44 : !llvm.ptr -> i64
  %dc46 = func.call @st_dcount(%vv45) : (i64) -> index
  %pg47 = memref.get_global @st_pow : memref<20xi64>
  %powers48 = trikeshed.text %pg47 : memref<20xi64> -> !s64
  %digits49 = trikeshed.series %dc46 : !text {
  ^bb0(%k: index):
    %last50 = arith.subi %dc46, %c12 : index
    %e51 = arith.subi %last50, %k : index
    %p52 = trikeshed.at %powers48[%e51] : !s64, index -> i64
    %q53 = arith.divui %vv45, %p52 : i64
    %dd54 = arith.remui %q53, %c17 : i64
    %d855 = arith.trunci %dd54 : i64 to i8
    %ch56 = arith.addi %d855, %c20 : i8
    trikeshed.yield %ch56 : i8
  }
  %ws57, %wl58 = func.call @st_word(%c59) : (index) -> (index, index)
  %w60 = trikeshed.slice %blob[%ws57, %wl58] : !text -> !text
  %whole61 = trikeshed.combine %w4, %digits11, %w24, %digits31, %w42, %digits49, %w60 : !text, !text, !text, !text, !text, !text, !text -> !text
  %sz = trikeshed.size %whole61 : !text
  %szi = arith.index_cast %sz : index to i64
  %capi = arith.index_cast %cap : i64 to index
  %fits = arith.cmpi ule, %sz, %capi : index
  scf.if %fits {
    %end = trikeshed.drain %whole61, %mi : !text, !m8 -> index
  }
  return %szi : i64
}

func.func private @st_l_1(%vals: !llvm.ptr, %wins: !llvm.ptr, %rows: !llvm.ptr, %nrows: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %c3 = arith.constant 4 : index
  %c5 = arith.constant 0 : i64
  %c12 = arith.constant 1 : index
  %c17 = arith.constant 10 : i64
  %c20 = arith.constant 48 : i8
  %c24 = arith.constant 5 : index
  %c26 = arith.constant 1 : i64
  %c42 = arith.constant 6 : index
  %c44 = arith.constant 2 : i64
  %c60 = arith.constant 3 : index
  %di = func.call @st_desc8(%into, %cap) : (!llvm.ptr, i64) -> !d
  %mi = builtin.unrealized_conversion_cast %di : !d to !m8
  %bg = memref.get_global @st_blob : memref<2642xi8>
  %blob = trikeshed.text %bg : memref<2642xi8> -> !text
  %spg = memref.get_global @st_sp : memref<32xi8>
  %sp = trikeshed.text %spg : memref<32xi8> -> !text
  %ws1, %wl2 = func.call @st_word(%c3) : (index) -> (index, index)
  %w4 = trikeshed.slice %blob[%ws1, %wl2] : !text -> !text
  %vp6 = llvm.getelementptr %vals[%c5] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv7 = llvm.load %vp6 : !llvm.ptr -> i64
  %dc8 = func.call @st_dcount(%vv7) : (i64) -> index
  %pg9 = memref.get_global @st_pow : memref<20xi64>
  %powers10 = trikeshed.text %pg9 : memref<20xi64> -> !s64
  %digits11 = trikeshed.series %dc8 : !text {
  ^bb0(%k: index):
    %last13 = arith.subi %dc8, %c12 : index
    %e14 = arith.subi %last13, %k : index
    %p15 = trikeshed.at %powers10[%e14] : !s64, index -> i64
    %q16 = arith.divui %vv7, %p15 : i64
    %dd18 = arith.remui %q16, %c17 : i64
    %d819 = arith.trunci %dd18 : i64 to i8
    %ch21 = arith.addi %d819, %c20 : i8
    trikeshed.yield %ch21 : i8
  }
  %ws22, %wl23 = func.call @st_word(%c24) : (index) -> (index, index)
  %w25 = trikeshed.slice %blob[%ws22, %wl23] : !text -> !text
  %vp27 = llvm.getelementptr %vals[%c26] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv28 = llvm.load %vp27 : !llvm.ptr -> i64
  %dc29 = func.call @st_dcount(%vv28) : (i64) -> index
  %pg30 = memref.get_global @st_pow : memref<20xi64>
  %powers31 = trikeshed.text %pg30 : memref<20xi64> -> !s64
  %digits32 = trikeshed.series %dc29 : !text {
  ^bb0(%k: index):
    %last33 = arith.subi %dc29, %c12 : index
    %e34 = arith.subi %last33, %k : index
    %p35 = trikeshed.at %powers31[%e34] : !s64, index -> i64
    %q36 = arith.divui %vv28, %p35 : i64
    %dd37 = arith.remui %q36, %c17 : i64
    %d838 = arith.trunci %dd37 : i64 to i8
    %ch39 = arith.addi %d838, %c20 : i8
    trikeshed.yield %ch39 : i8
  }
  %ws40, %wl41 = func.call @st_word(%c42) : (index) -> (index, index)
  %w43 = trikeshed.slice %blob[%ws40, %wl41] : !text -> !text
  %vp45 = llvm.getelementptr %vals[%c44] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv46 = llvm.load %vp45 : !llvm.ptr -> i64
  %dc47 = func.call @st_dcount(%vv46) : (i64) -> index
  %pg48 = memref.get_global @st_pow : memref<20xi64>
  %powers49 = trikeshed.text %pg48 : memref<20xi64> -> !s64
  %digits50 = trikeshed.series %dc47 : !text {
  ^bb0(%k: index):
    %last51 = arith.subi %dc47, %c12 : index
    %e52 = arith.subi %last51, %k : index
    %p53 = trikeshed.at %powers49[%e52] : !s64, index -> i64
    %q54 = arith.divui %vv46, %p53 : i64
    %dd55 = arith.remui %q54, %c17 : i64
    %d856 = arith.trunci %dd55 : i64 to i8
    %ch57 = arith.addi %d856, %c20 : i8
    trikeshed.yield %ch57 : i8
  }
  %ws58, %wl59 = func.call @st_word(%c60) : (index) -> (index, index)
  %w61 = trikeshed.slice %blob[%ws58, %wl59] : !text -> !text
  %whole62 = trikeshed.combine %w4, %digits11, %w25, %digits32, %w43, %digits50, %w61 : !text, !text, !text, !text, !text, !text, !text -> !text
  %sz = trikeshed.size %whole62 : !text
  %szi = arith.index_cast %sz : index to i64
  %capi = arith.index_cast %cap : i64 to index
  %fits = arith.cmpi ule, %sz, %capi : index
  scf.if %fits {
    %end = trikeshed.drain %whole62, %mi : !text, !m8 -> index
  }
  return %szi : i64
}

func.func private @st_l_2(%vals: !llvm.ptr, %wins: !llvm.ptr, %rows: !llvm.ptr, %nrows: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %c3 = arith.constant 7 : index
  %c5 = arith.constant 0 : i64
  %c8 = arith.constant 8 : i64
  %c16 = arith.constant 8 : index
  %c18 = arith.constant 16 : i64
  %c28 = arith.constant 9 : index
  %c30 = arith.constant 32 : i64
  %c40 = arith.constant 10 : index
  %c48 = arith.constant 1 : index
  %c53 = arith.constant 10 : i64
  %c56 = arith.constant 48 : i8
  %c60 = arith.constant 11 : index
  %c62 = arith.constant 48 : i64
  %c72 = arith.constant 12 : index
  %c74 = arith.constant 64 : i64
  %c84 = arith.constant 13 : index
  %c86 = arith.constant 80 : i64
  %c96 = arith.constant 14 : index
  %c98 = arith.constant 96 : i64
  %c108 = arith.constant 15 : index
  %c110 = arith.constant 112 : i64
  %c120 = arith.constant 16 : index
  %di = func.call @st_desc8(%into, %cap) : (!llvm.ptr, i64) -> !d
  %mi = builtin.unrealized_conversion_cast %di : !d to !m8
  %bg = memref.get_global @st_blob : memref<2642xi8>
  %blob = trikeshed.text %bg : memref<2642xi8> -> !text
  %spg = memref.get_global @st_sp : memref<32xi8>
  %sp = trikeshed.text %spg : memref<32xi8> -> !text
  %ws1, %wl2 = func.call @st_word(%c3) : (index) -> (index, index)
  %w4 = trikeshed.slice %blob[%ws1, %wl2] : !text -> !text
  %wb6 = llvm.getelementptr %wins[%c5] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wp7 = llvm.load %wb6 : !llvm.ptr -> !llvm.ptr
  %wl9 = llvm.getelementptr %wb6[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wn10 = llvm.load %wl9 : !llvm.ptr -> i64
  %d11 = func.call @st_desc8(%wp7, %wn10) : (!llvm.ptr, i64) -> !d
  %m12 = builtin.unrealized_conversion_cast %d11 : !d to !m8
  %s13 = builtin.unrealized_conversion_cast %m12 : !m8 to !text
  %ws14, %wl15 = func.call @st_word(%c16) : (index) -> (index, index)
  %w17 = trikeshed.slice %blob[%ws14, %wl15] : !text -> !text
  %wb19 = llvm.getelementptr %wins[%c18] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wp20 = llvm.load %wb19 : !llvm.ptr -> !llvm.ptr
  %wl21 = llvm.getelementptr %wb19[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wn22 = llvm.load %wl21 : !llvm.ptr -> i64
  %d23 = func.call @st_desc8(%wp20, %wn22) : (!llvm.ptr, i64) -> !d
  %m24 = builtin.unrealized_conversion_cast %d23 : !d to !m8
  %s25 = builtin.unrealized_conversion_cast %m24 : !m8 to !text
  %ws26, %wl27 = func.call @st_word(%c28) : (index) -> (index, index)
  %w29 = trikeshed.slice %blob[%ws26, %wl27] : !text -> !text
  %wb31 = llvm.getelementptr %wins[%c30] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wp32 = llvm.load %wb31 : !llvm.ptr -> !llvm.ptr
  %wl33 = llvm.getelementptr %wb31[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wn34 = llvm.load %wl33 : !llvm.ptr -> i64
  %d35 = func.call @st_desc8(%wp32, %wn34) : (!llvm.ptr, i64) -> !d
  %m36 = builtin.unrealized_conversion_cast %d35 : !d to !m8
  %s37 = builtin.unrealized_conversion_cast %m36 : !m8 to !text
  %ws38, %wl39 = func.call @st_word(%c40) : (index) -> (index, index)
  %w41 = trikeshed.slice %blob[%ws38, %wl39] : !text -> !text
  %vp42 = llvm.getelementptr %vals[%c5] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv43 = llvm.load %vp42 : !llvm.ptr -> i64
  %dc44 = func.call @st_dcount(%vv43) : (i64) -> index
  %pg45 = memref.get_global @st_pow : memref<20xi64>
  %powers46 = trikeshed.text %pg45 : memref<20xi64> -> !s64
  %digits47 = trikeshed.series %dc44 : !text {
  ^bb0(%k: index):
    %last49 = arith.subi %dc44, %c48 : index
    %e50 = arith.subi %last49, %k : index
    %p51 = trikeshed.at %powers46[%e50] : !s64, index -> i64
    %q52 = arith.divui %vv43, %p51 : i64
    %dd54 = arith.remui %q52, %c53 : i64
    %d855 = arith.trunci %dd54 : i64 to i8
    %ch57 = arith.addi %d855, %c56 : i8
    trikeshed.yield %ch57 : i8
  }
  %ws58, %wl59 = func.call @st_word(%c60) : (index) -> (index, index)
  %w61 = trikeshed.slice %blob[%ws58, %wl59] : !text -> !text
  %wb63 = llvm.getelementptr %wins[%c62] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wp64 = llvm.load %wb63 : !llvm.ptr -> !llvm.ptr
  %wl65 = llvm.getelementptr %wb63[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wn66 = llvm.load %wl65 : !llvm.ptr -> i64
  %d67 = func.call @st_desc8(%wp64, %wn66) : (!llvm.ptr, i64) -> !d
  %m68 = builtin.unrealized_conversion_cast %d67 : !d to !m8
  %s69 = builtin.unrealized_conversion_cast %m68 : !m8 to !text
  %ws70, %wl71 = func.call @st_word(%c72) : (index) -> (index, index)
  %w73 = trikeshed.slice %blob[%ws70, %wl71] : !text -> !text
  %wb75 = llvm.getelementptr %wins[%c74] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wp76 = llvm.load %wb75 : !llvm.ptr -> !llvm.ptr
  %wl77 = llvm.getelementptr %wb75[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wn78 = llvm.load %wl77 : !llvm.ptr -> i64
  %d79 = func.call @st_desc8(%wp76, %wn78) : (!llvm.ptr, i64) -> !d
  %m80 = builtin.unrealized_conversion_cast %d79 : !d to !m8
  %s81 = builtin.unrealized_conversion_cast %m80 : !m8 to !text
  %ws82, %wl83 = func.call @st_word(%c84) : (index) -> (index, index)
  %w85 = trikeshed.slice %blob[%ws82, %wl83] : !text -> !text
  %wb87 = llvm.getelementptr %wins[%c86] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wp88 = llvm.load %wb87 : !llvm.ptr -> !llvm.ptr
  %wl89 = llvm.getelementptr %wb87[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wn90 = llvm.load %wl89 : !llvm.ptr -> i64
  %d91 = func.call @st_desc8(%wp88, %wn90) : (!llvm.ptr, i64) -> !d
  %m92 = builtin.unrealized_conversion_cast %d91 : !d to !m8
  %s93 = builtin.unrealized_conversion_cast %m92 : !m8 to !text
  %ws94, %wl95 = func.call @st_word(%c96) : (index) -> (index, index)
  %w97 = trikeshed.slice %blob[%ws94, %wl95] : !text -> !text
  %wb99 = llvm.getelementptr %wins[%c98] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wp100 = llvm.load %wb99 : !llvm.ptr -> !llvm.ptr
  %wl101 = llvm.getelementptr %wb99[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wn102 = llvm.load %wl101 : !llvm.ptr -> i64
  %d103 = func.call @st_desc8(%wp100, %wn102) : (!llvm.ptr, i64) -> !d
  %m104 = builtin.unrealized_conversion_cast %d103 : !d to !m8
  %s105 = builtin.unrealized_conversion_cast %m104 : !m8 to !text
  %ws106, %wl107 = func.call @st_word(%c108) : (index) -> (index, index)
  %w109 = trikeshed.slice %blob[%ws106, %wl107] : !text -> !text
  %wb111 = llvm.getelementptr %wins[%c110] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wp112 = llvm.load %wb111 : !llvm.ptr -> !llvm.ptr
  %wl113 = llvm.getelementptr %wb111[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wn114 = llvm.load %wl113 : !llvm.ptr -> i64
  %d115 = func.call @st_desc8(%wp112, %wn114) : (!llvm.ptr, i64) -> !d
  %m116 = builtin.unrealized_conversion_cast %d115 : !d to !m8
  %s117 = builtin.unrealized_conversion_cast %m116 : !m8 to !text
  %ws118, %wl119 = func.call @st_word(%c120) : (index) -> (index, index)
  %w121 = trikeshed.slice %blob[%ws118, %wl119] : !text -> !text
  %whole122 = trikeshed.combine %w4, %s13, %w17, %s25, %w29, %s37, %w41, %digits47, %w61, %s69, %w73, %s81, %w85, %s93, %w97, %s105, %w109, %s117, %w121 : !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text -> !text
  %sz = trikeshed.size %whole122 : !text
  %szi = arith.index_cast %sz : index to i64
  %capi = arith.index_cast %cap : i64 to index
  %fits = arith.cmpi ule, %sz, %capi : index
  scf.if %fits {
    %end = trikeshed.drain %whole122, %mi : !text, !m8 -> index
  }
  return %szi : i64
}

func.func private @st_l_3(%vals: !llvm.ptr, %wins: !llvm.ptr, %rows: !llvm.ptr, %nrows: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %c3 = arith.constant 17 : index
  %c5 = arith.constant 0 : i64
  %c8 = arith.constant 8 : i64
  %c16 = arith.constant 18 : index
  %c18 = arith.constant 16 : i64
  %c28 = arith.constant 19 : index
  %c30 = arith.constant 32 : i64
  %c40 = arith.constant 20 : index
  %c42 = arith.constant 48 : i64
  %c52 = arith.constant 21 : index
  %c54 = arith.constant 64 : i64
  %c64 = arith.constant 22 : index
  %c66 = arith.constant 80 : i64
  %c76 = arith.constant 16 : index
  %di = func.call @st_desc8(%into, %cap) : (!llvm.ptr, i64) -> !d
  %mi = builtin.unrealized_conversion_cast %di : !d to !m8
  %bg = memref.get_global @st_blob : memref<2642xi8>
  %blob = trikeshed.text %bg : memref<2642xi8> -> !text
  %spg = memref.get_global @st_sp : memref<32xi8>
  %sp = trikeshed.text %spg : memref<32xi8> -> !text
  %ws1, %wl2 = func.call @st_word(%c3) : (index) -> (index, index)
  %w4 = trikeshed.slice %blob[%ws1, %wl2] : !text -> !text
  %wb6 = llvm.getelementptr %wins[%c5] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wp7 = llvm.load %wb6 : !llvm.ptr -> !llvm.ptr
  %wl9 = llvm.getelementptr %wb6[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wn10 = llvm.load %wl9 : !llvm.ptr -> i64
  %d11 = func.call @st_desc8(%wp7, %wn10) : (!llvm.ptr, i64) -> !d
  %m12 = builtin.unrealized_conversion_cast %d11 : !d to !m8
  %s13 = builtin.unrealized_conversion_cast %m12 : !m8 to !text
  %ws14, %wl15 = func.call @st_word(%c16) : (index) -> (index, index)
  %w17 = trikeshed.slice %blob[%ws14, %wl15] : !text -> !text
  %wb19 = llvm.getelementptr %wins[%c18] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wp20 = llvm.load %wb19 : !llvm.ptr -> !llvm.ptr
  %wl21 = llvm.getelementptr %wb19[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wn22 = llvm.load %wl21 : !llvm.ptr -> i64
  %d23 = func.call @st_desc8(%wp20, %wn22) : (!llvm.ptr, i64) -> !d
  %m24 = builtin.unrealized_conversion_cast %d23 : !d to !m8
  %s25 = builtin.unrealized_conversion_cast %m24 : !m8 to !text
  %ws26, %wl27 = func.call @st_word(%c28) : (index) -> (index, index)
  %w29 = trikeshed.slice %blob[%ws26, %wl27] : !text -> !text
  %wb31 = llvm.getelementptr %wins[%c30] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wp32 = llvm.load %wb31 : !llvm.ptr -> !llvm.ptr
  %wl33 = llvm.getelementptr %wb31[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wn34 = llvm.load %wl33 : !llvm.ptr -> i64
  %d35 = func.call @st_desc8(%wp32, %wn34) : (!llvm.ptr, i64) -> !d
  %m36 = builtin.unrealized_conversion_cast %d35 : !d to !m8
  %s37 = builtin.unrealized_conversion_cast %m36 : !m8 to !text
  %ws38, %wl39 = func.call @st_word(%c40) : (index) -> (index, index)
  %w41 = trikeshed.slice %blob[%ws38, %wl39] : !text -> !text
  %wb43 = llvm.getelementptr %wins[%c42] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wp44 = llvm.load %wb43 : !llvm.ptr -> !llvm.ptr
  %wl45 = llvm.getelementptr %wb43[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wn46 = llvm.load %wl45 : !llvm.ptr -> i64
  %d47 = func.call @st_desc8(%wp44, %wn46) : (!llvm.ptr, i64) -> !d
  %m48 = builtin.unrealized_conversion_cast %d47 : !d to !m8
  %s49 = builtin.unrealized_conversion_cast %m48 : !m8 to !text
  %ws50, %wl51 = func.call @st_word(%c52) : (index) -> (index, index)
  %w53 = trikeshed.slice %blob[%ws50, %wl51] : !text -> !text
  %wb55 = llvm.getelementptr %wins[%c54] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wp56 = llvm.load %wb55 : !llvm.ptr -> !llvm.ptr
  %wl57 = llvm.getelementptr %wb55[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wn58 = llvm.load %wl57 : !llvm.ptr -> i64
  %d59 = func.call @st_desc8(%wp56, %wn58) : (!llvm.ptr, i64) -> !d
  %m60 = builtin.unrealized_conversion_cast %d59 : !d to !m8
  %s61 = builtin.unrealized_conversion_cast %m60 : !m8 to !text
  %ws62, %wl63 = func.call @st_word(%c64) : (index) -> (index, index)
  %w65 = trikeshed.slice %blob[%ws62, %wl63] : !text -> !text
  %wb67 = llvm.getelementptr %wins[%c66] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wp68 = llvm.load %wb67 : !llvm.ptr -> !llvm.ptr
  %wl69 = llvm.getelementptr %wb67[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wn70 = llvm.load %wl69 : !llvm.ptr -> i64
  %d71 = func.call @st_desc8(%wp68, %wn70) : (!llvm.ptr, i64) -> !d
  %m72 = builtin.unrealized_conversion_cast %d71 : !d to !m8
  %s73 = builtin.unrealized_conversion_cast %m72 : !m8 to !text
  %ws74, %wl75 = func.call @st_word(%c76) : (index) -> (index, index)
  %w77 = trikeshed.slice %blob[%ws74, %wl75] : !text -> !text
  %whole78 = trikeshed.combine %w4, %s13, %w17, %s25, %w29, %s37, %w41, %s49, %w53, %s61, %w65, %s73, %w77 : !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text -> !text
  %sz = trikeshed.size %whole78 : !text
  %szi = arith.index_cast %sz : index to i64
  %capi = arith.index_cast %cap : i64 to index
  %fits = arith.cmpi ule, %sz, %capi : index
  scf.if %fits {
    %end = trikeshed.drain %whole78, %mi : !text, !m8 -> index
  }
  return %szi : i64
}

func.func private @st_l_4(%vals: !llvm.ptr, %wins: !llvm.ptr, %rows: !llvm.ptr, %nrows: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %c3 = arith.constant 23 : index
  %c5 = arith.constant 0 : i64
  %c12 = arith.constant 1 : index
  %c17 = arith.constant 10 : i64
  %c20 = arith.constant 48 : i8
  %c24 = arith.constant 24 : index
  %di = func.call @st_desc8(%into, %cap) : (!llvm.ptr, i64) -> !d
  %mi = builtin.unrealized_conversion_cast %di : !d to !m8
  %bg = memref.get_global @st_blob : memref<2642xi8>
  %blob = trikeshed.text %bg : memref<2642xi8> -> !text
  %spg = memref.get_global @st_sp : memref<32xi8>
  %sp = trikeshed.text %spg : memref<32xi8> -> !text
  %ws1, %wl2 = func.call @st_word(%c3) : (index) -> (index, index)
  %w4 = trikeshed.slice %blob[%ws1, %wl2] : !text -> !text
  %vp6 = llvm.getelementptr %vals[%c5] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv7 = llvm.load %vp6 : !llvm.ptr -> i64
  %dc8 = func.call @st_dcount(%vv7) : (i64) -> index
  %pg9 = memref.get_global @st_pow : memref<20xi64>
  %powers10 = trikeshed.text %pg9 : memref<20xi64> -> !s64
  %digits11 = trikeshed.series %dc8 : !text {
  ^bb0(%k: index):
    %last13 = arith.subi %dc8, %c12 : index
    %e14 = arith.subi %last13, %k : index
    %p15 = trikeshed.at %powers10[%e14] : !s64, index -> i64
    %q16 = arith.divui %vv7, %p15 : i64
    %dd18 = arith.remui %q16, %c17 : i64
    %d819 = arith.trunci %dd18 : i64 to i8
    %ch21 = arith.addi %d819, %c20 : i8
    trikeshed.yield %ch21 : i8
  }
  %ws22, %wl23 = func.call @st_word(%c24) : (index) -> (index, index)
  %w25 = trikeshed.slice %blob[%ws22, %wl23] : !text -> !text
  %whole26 = trikeshed.combine %w4, %digits11, %w25 : !text, !text, !text -> !text
  %sz = trikeshed.size %whole26 : !text
  %szi = arith.index_cast %sz : index to i64
  %capi = arith.index_cast %cap : i64 to index
  %fits = arith.cmpi ule, %sz, %capi : index
  scf.if %fits {
    %end = trikeshed.drain %whole26, %mi : !text, !m8 -> index
  }
  return %szi : i64
}

func.func private @st_l_5(%vals: !llvm.ptr, %wins: !llvm.ptr, %rows: !llvm.ptr, %nrows: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %c3 = arith.constant 25 : index
  %c5 = arith.constant 0 : i64
  %c12 = arith.constant 1 : index
  %c17 = arith.constant 10 : i64
  %c20 = arith.constant 48 : i8
  %c24 = arith.constant 3 : index
  %di = func.call @st_desc8(%into, %cap) : (!llvm.ptr, i64) -> !d
  %mi = builtin.unrealized_conversion_cast %di : !d to !m8
  %bg = memref.get_global @st_blob : memref<2642xi8>
  %blob = trikeshed.text %bg : memref<2642xi8> -> !text
  %spg = memref.get_global @st_sp : memref<32xi8>
  %sp = trikeshed.text %spg : memref<32xi8> -> !text
  %ws1, %wl2 = func.call @st_word(%c3) : (index) -> (index, index)
  %w4 = trikeshed.slice %blob[%ws1, %wl2] : !text -> !text
  %vp6 = llvm.getelementptr %vals[%c5] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv7 = llvm.load %vp6 : !llvm.ptr -> i64
  %dc8 = func.call @st_dcount(%vv7) : (i64) -> index
  %pg9 = memref.get_global @st_pow : memref<20xi64>
  %powers10 = trikeshed.text %pg9 : memref<20xi64> -> !s64
  %digits11 = trikeshed.series %dc8 : !text {
  ^bb0(%k: index):
    %last13 = arith.subi %dc8, %c12 : index
    %e14 = arith.subi %last13, %k : index
    %p15 = trikeshed.at %powers10[%e14] : !s64, index -> i64
    %q16 = arith.divui %vv7, %p15 : i64
    %dd18 = arith.remui %q16, %c17 : i64
    %d819 = arith.trunci %dd18 : i64 to i8
    %ch21 = arith.addi %d819, %c20 : i8
    trikeshed.yield %ch21 : i8
  }
  %ws22, %wl23 = func.call @st_word(%c24) : (index) -> (index, index)
  %w25 = trikeshed.slice %blob[%ws22, %wl23] : !text -> !text
  %whole26 = trikeshed.combine %w4, %digits11, %w25 : !text, !text, !text -> !text
  %sz = trikeshed.size %whole26 : !text
  %szi = arith.index_cast %sz : index to i64
  %capi = arith.index_cast %cap : i64 to index
  %fits = arith.cmpi ule, %sz, %capi : index
  scf.if %fits {
    %end = trikeshed.drain %whole26, %mi : !text, !m8 -> index
  }
  return %szi : i64
}

func.func private @st_l_6(%vals: !llvm.ptr, %wins: !llvm.ptr, %rows: !llvm.ptr, %nrows: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %c3 = arith.constant 26 : index
  %c5 = arith.constant 0 : i64
  %c8 = arith.constant 8 : i64
  %c16 = arith.constant 27 : index
  %c18 = arith.constant 16 : i64
  %c28 = arith.constant 28 : index
  %c30 = arith.constant 32 : i64
  %c40 = arith.constant 29 : index
  %c42 = arith.constant 48 : i64
  %c52 = arith.constant 30 : index
  %c54 = arith.constant 64 : i64
  %c64 = arith.constant 16 : index
  %di = func.call @st_desc8(%into, %cap) : (!llvm.ptr, i64) -> !d
  %mi = builtin.unrealized_conversion_cast %di : !d to !m8
  %bg = memref.get_global @st_blob : memref<2642xi8>
  %blob = trikeshed.text %bg : memref<2642xi8> -> !text
  %spg = memref.get_global @st_sp : memref<32xi8>
  %sp = trikeshed.text %spg : memref<32xi8> -> !text
  %ws1, %wl2 = func.call @st_word(%c3) : (index) -> (index, index)
  %w4 = trikeshed.slice %blob[%ws1, %wl2] : !text -> !text
  %wb6 = llvm.getelementptr %wins[%c5] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wp7 = llvm.load %wb6 : !llvm.ptr -> !llvm.ptr
  %wl9 = llvm.getelementptr %wb6[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wn10 = llvm.load %wl9 : !llvm.ptr -> i64
  %d11 = func.call @st_desc8(%wp7, %wn10) : (!llvm.ptr, i64) -> !d
  %m12 = builtin.unrealized_conversion_cast %d11 : !d to !m8
  %s13 = builtin.unrealized_conversion_cast %m12 : !m8 to !text
  %ws14, %wl15 = func.call @st_word(%c16) : (index) -> (index, index)
  %w17 = trikeshed.slice %blob[%ws14, %wl15] : !text -> !text
  %wb19 = llvm.getelementptr %wins[%c18] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wp20 = llvm.load %wb19 : !llvm.ptr -> !llvm.ptr
  %wl21 = llvm.getelementptr %wb19[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wn22 = llvm.load %wl21 : !llvm.ptr -> i64
  %d23 = func.call @st_desc8(%wp20, %wn22) : (!llvm.ptr, i64) -> !d
  %m24 = builtin.unrealized_conversion_cast %d23 : !d to !m8
  %s25 = builtin.unrealized_conversion_cast %m24 : !m8 to !text
  %ws26, %wl27 = func.call @st_word(%c28) : (index) -> (index, index)
  %w29 = trikeshed.slice %blob[%ws26, %wl27] : !text -> !text
  %wb31 = llvm.getelementptr %wins[%c30] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wp32 = llvm.load %wb31 : !llvm.ptr -> !llvm.ptr
  %wl33 = llvm.getelementptr %wb31[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wn34 = llvm.load %wl33 : !llvm.ptr -> i64
  %d35 = func.call @st_desc8(%wp32, %wn34) : (!llvm.ptr, i64) -> !d
  %m36 = builtin.unrealized_conversion_cast %d35 : !d to !m8
  %s37 = builtin.unrealized_conversion_cast %m36 : !m8 to !text
  %ws38, %wl39 = func.call @st_word(%c40) : (index) -> (index, index)
  %w41 = trikeshed.slice %blob[%ws38, %wl39] : !text -> !text
  %wb43 = llvm.getelementptr %wins[%c42] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wp44 = llvm.load %wb43 : !llvm.ptr -> !llvm.ptr
  %wl45 = llvm.getelementptr %wb43[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wn46 = llvm.load %wl45 : !llvm.ptr -> i64
  %d47 = func.call @st_desc8(%wp44, %wn46) : (!llvm.ptr, i64) -> !d
  %m48 = builtin.unrealized_conversion_cast %d47 : !d to !m8
  %s49 = builtin.unrealized_conversion_cast %m48 : !m8 to !text
  %ws50, %wl51 = func.call @st_word(%c52) : (index) -> (index, index)
  %w53 = trikeshed.slice %blob[%ws50, %wl51] : !text -> !text
  %wb55 = llvm.getelementptr %wins[%c54] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wp56 = llvm.load %wb55 : !llvm.ptr -> !llvm.ptr
  %wl57 = llvm.getelementptr %wb55[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wn58 = llvm.load %wl57 : !llvm.ptr -> i64
  %d59 = func.call @st_desc8(%wp56, %wn58) : (!llvm.ptr, i64) -> !d
  %m60 = builtin.unrealized_conversion_cast %d59 : !d to !m8
  %s61 = builtin.unrealized_conversion_cast %m60 : !m8 to !text
  %ws62, %wl63 = func.call @st_word(%c64) : (index) -> (index, index)
  %w65 = trikeshed.slice %blob[%ws62, %wl63] : !text -> !text
  %whole66 = trikeshed.combine %w4, %s13, %w17, %s25, %w29, %s37, %w41, %s49, %w53, %s61, %w65 : !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text -> !text
  %sz = trikeshed.size %whole66 : !text
  %szi = arith.index_cast %sz : index to i64
  %capi = arith.index_cast %cap : i64 to index
  %fits = arith.cmpi ule, %sz, %capi : index
  scf.if %fits {
    %end = trikeshed.drain %whole66, %mi : !text, !m8 -> index
  }
  return %szi : i64
}

func.func private @st_l_7(%vals: !llvm.ptr, %wins: !llvm.ptr, %rows: !llvm.ptr, %nrows: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %c3 = arith.constant 31 : index
  %c5 = arith.constant 0 : i64
  %c8 = arith.constant 8 : i64
  %c16 = arith.constant 32 : index
  %c18 = arith.constant 16 : i64
  %c28 = arith.constant 33 : index
  %c36 = arith.constant 1 : index
  %c41 = arith.constant 10 : i64
  %c44 = arith.constant 48 : i8
  %c48 = arith.constant 34 : index
  %c50 = arith.constant 1 : i64
  %c66 = arith.constant 35 : index
  %c68 = arith.constant 2 : i64
  %c84 = arith.constant 36 : index
  %c86 = arith.constant 3 : i64
  %c102 = arith.constant 37 : index
  %di = func.call @st_desc8(%into, %cap) : (!llvm.ptr, i64) -> !d
  %mi = builtin.unrealized_conversion_cast %di : !d to !m8
  %bg = memref.get_global @st_blob : memref<2642xi8>
  %blob = trikeshed.text %bg : memref<2642xi8> -> !text
  %spg = memref.get_global @st_sp : memref<32xi8>
  %sp = trikeshed.text %spg : memref<32xi8> -> !text
  %ws1, %wl2 = func.call @st_word(%c3) : (index) -> (index, index)
  %w4 = trikeshed.slice %blob[%ws1, %wl2] : !text -> !text
  %wb6 = llvm.getelementptr %wins[%c5] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wp7 = llvm.load %wb6 : !llvm.ptr -> !llvm.ptr
  %wl9 = llvm.getelementptr %wb6[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wn10 = llvm.load %wl9 : !llvm.ptr -> i64
  %d11 = func.call @st_desc8(%wp7, %wn10) : (!llvm.ptr, i64) -> !d
  %m12 = builtin.unrealized_conversion_cast %d11 : !d to !m8
  %s13 = builtin.unrealized_conversion_cast %m12 : !m8 to !text
  %ws14, %wl15 = func.call @st_word(%c16) : (index) -> (index, index)
  %w17 = trikeshed.slice %blob[%ws14, %wl15] : !text -> !text
  %wb19 = llvm.getelementptr %wins[%c18] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wp20 = llvm.load %wb19 : !llvm.ptr -> !llvm.ptr
  %wl21 = llvm.getelementptr %wb19[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wn22 = llvm.load %wl21 : !llvm.ptr -> i64
  %d23 = func.call @st_desc8(%wp20, %wn22) : (!llvm.ptr, i64) -> !d
  %m24 = builtin.unrealized_conversion_cast %d23 : !d to !m8
  %s25 = builtin.unrealized_conversion_cast %m24 : !m8 to !text
  %ws26, %wl27 = func.call @st_word(%c28) : (index) -> (index, index)
  %w29 = trikeshed.slice %blob[%ws26, %wl27] : !text -> !text
  %vp30 = llvm.getelementptr %vals[%c5] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv31 = llvm.load %vp30 : !llvm.ptr -> i64
  %dc32 = func.call @st_dcount(%vv31) : (i64) -> index
  %pg33 = memref.get_global @st_pow : memref<20xi64>
  %powers34 = trikeshed.text %pg33 : memref<20xi64> -> !s64
  %digits35 = trikeshed.series %dc32 : !text {
  ^bb0(%k: index):
    %last37 = arith.subi %dc32, %c36 : index
    %e38 = arith.subi %last37, %k : index
    %p39 = trikeshed.at %powers34[%e38] : !s64, index -> i64
    %q40 = arith.divui %vv31, %p39 : i64
    %dd42 = arith.remui %q40, %c41 : i64
    %d843 = arith.trunci %dd42 : i64 to i8
    %ch45 = arith.addi %d843, %c44 : i8
    trikeshed.yield %ch45 : i8
  }
  %ws46, %wl47 = func.call @st_word(%c48) : (index) -> (index, index)
  %w49 = trikeshed.slice %blob[%ws46, %wl47] : !text -> !text
  %vp51 = llvm.getelementptr %vals[%c50] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv52 = llvm.load %vp51 : !llvm.ptr -> i64
  %dc53 = func.call @st_dcount(%vv52) : (i64) -> index
  %pg54 = memref.get_global @st_pow : memref<20xi64>
  %powers55 = trikeshed.text %pg54 : memref<20xi64> -> !s64
  %digits56 = trikeshed.series %dc53 : !text {
  ^bb0(%k: index):
    %last57 = arith.subi %dc53, %c36 : index
    %e58 = arith.subi %last57, %k : index
    %p59 = trikeshed.at %powers55[%e58] : !s64, index -> i64
    %q60 = arith.divui %vv52, %p59 : i64
    %dd61 = arith.remui %q60, %c41 : i64
    %d862 = arith.trunci %dd61 : i64 to i8
    %ch63 = arith.addi %d862, %c44 : i8
    trikeshed.yield %ch63 : i8
  }
  %ws64, %wl65 = func.call @st_word(%c66) : (index) -> (index, index)
  %w67 = trikeshed.slice %blob[%ws64, %wl65] : !text -> !text
  %vp69 = llvm.getelementptr %vals[%c68] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv70 = llvm.load %vp69 : !llvm.ptr -> i64
  %dc71 = func.call @st_dcount(%vv70) : (i64) -> index
  %pg72 = memref.get_global @st_pow : memref<20xi64>
  %powers73 = trikeshed.text %pg72 : memref<20xi64> -> !s64
  %digits74 = trikeshed.series %dc71 : !text {
  ^bb0(%k: index):
    %last75 = arith.subi %dc71, %c36 : index
    %e76 = arith.subi %last75, %k : index
    %p77 = trikeshed.at %powers73[%e76] : !s64, index -> i64
    %q78 = arith.divui %vv70, %p77 : i64
    %dd79 = arith.remui %q78, %c41 : i64
    %d880 = arith.trunci %dd79 : i64 to i8
    %ch81 = arith.addi %d880, %c44 : i8
    trikeshed.yield %ch81 : i8
  }
  %ws82, %wl83 = func.call @st_word(%c84) : (index) -> (index, index)
  %w85 = trikeshed.slice %blob[%ws82, %wl83] : !text -> !text
  %vp87 = llvm.getelementptr %vals[%c86] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv88 = llvm.load %vp87 : !llvm.ptr -> i64
  %dc89 = func.call @st_dcount(%vv88) : (i64) -> index
  %pg90 = memref.get_global @st_pow : memref<20xi64>
  %powers91 = trikeshed.text %pg90 : memref<20xi64> -> !s64
  %digits92 = trikeshed.series %dc89 : !text {
  ^bb0(%k: index):
    %last93 = arith.subi %dc89, %c36 : index
    %e94 = arith.subi %last93, %k : index
    %p95 = trikeshed.at %powers91[%e94] : !s64, index -> i64
    %q96 = arith.divui %vv88, %p95 : i64
    %dd97 = arith.remui %q96, %c41 : i64
    %d898 = arith.trunci %dd97 : i64 to i8
    %ch99 = arith.addi %d898, %c44 : i8
    trikeshed.yield %ch99 : i8
  }
  %ws100, %wl101 = func.call @st_word(%c102) : (index) -> (index, index)
  %w103 = trikeshed.slice %blob[%ws100, %wl101] : !text -> !text
  %whole104 = trikeshed.combine %w4, %s13, %w17, %s25, %w29, %digits35, %w49, %digits56, %w67, %digits74, %w85, %digits92, %w103 : !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text -> !text
  %sz = trikeshed.size %whole104 : !text
  %szi = arith.index_cast %sz : index to i64
  %capi = arith.index_cast %cap : i64 to index
  %fits = arith.cmpi ule, %sz, %capi : index
  scf.if %fits {
    %end = trikeshed.drain %whole104, %mi : !text, !m8 -> index
  }
  return %szi : i64
}

func.func private @st_l_8(%vals: !llvm.ptr, %wins: !llvm.ptr, %rows: !llvm.ptr, %nrows: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %c3 = arith.constant 38 : index
  %c5 = arith.constant 0 : i64
  %c12 = arith.constant 1 : index
  %c17 = arith.constant 10 : i64
  %c20 = arith.constant 48 : i8
  %c24 = arith.constant 39 : index
  %c26 = arith.constant 1 : i64
  %c42 = arith.constant 40 : index
  %c46 = arith.constant 8 : i64
  %c54 = arith.constant 41 : index
  %c56 = arith.constant 2 : i64
  %c72 = arith.constant 42 : index
  %c74 = arith.constant 16 : i64
  %c84 = arith.constant 43 : index
  %c86 = arith.constant 3 : i64
  %c102 = arith.constant 44 : index
  %c104 = arith.constant 32 : i64
  %c114 = arith.constant 45 : index
  %c116 = arith.constant 4 : i64
  %c132 = arith.constant 10 : index
  %c134 = arith.constant 48 : i64
  %c144 = arith.constant 46 : index
  %c146 = arith.constant 64 : i64
  %c156 = arith.constant 47 : index
  %c158 = arith.constant 80 : i64
  %c168 = arith.constant 48 : index
  %c170 = arith.constant 96 : i64
  %c180 = arith.constant 16 : index
  %di = func.call @st_desc8(%into, %cap) : (!llvm.ptr, i64) -> !d
  %mi = builtin.unrealized_conversion_cast %di : !d to !m8
  %bg = memref.get_global @st_blob : memref<2642xi8>
  %blob = trikeshed.text %bg : memref<2642xi8> -> !text
  %spg = memref.get_global @st_sp : memref<32xi8>
  %sp = trikeshed.text %spg : memref<32xi8> -> !text
  %ws1, %wl2 = func.call @st_word(%c3) : (index) -> (index, index)
  %w4 = trikeshed.slice %blob[%ws1, %wl2] : !text -> !text
  %vp6 = llvm.getelementptr %vals[%c5] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv7 = llvm.load %vp6 : !llvm.ptr -> i64
  %dc8 = func.call @st_dcount(%vv7) : (i64) -> index
  %pg9 = memref.get_global @st_pow : memref<20xi64>
  %powers10 = trikeshed.text %pg9 : memref<20xi64> -> !s64
  %digits11 = trikeshed.series %dc8 : !text {
  ^bb0(%k: index):
    %last13 = arith.subi %dc8, %c12 : index
    %e14 = arith.subi %last13, %k : index
    %p15 = trikeshed.at %powers10[%e14] : !s64, index -> i64
    %q16 = arith.divui %vv7, %p15 : i64
    %dd18 = arith.remui %q16, %c17 : i64
    %d819 = arith.trunci %dd18 : i64 to i8
    %ch21 = arith.addi %d819, %c20 : i8
    trikeshed.yield %ch21 : i8
  }
  %ws22, %wl23 = func.call @st_word(%c24) : (index) -> (index, index)
  %w25 = trikeshed.slice %blob[%ws22, %wl23] : !text -> !text
  %vp27 = llvm.getelementptr %vals[%c26] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv28 = llvm.load %vp27 : !llvm.ptr -> i64
  %dc29 = func.call @st_dcount(%vv28) : (i64) -> index
  %pg30 = memref.get_global @st_pow : memref<20xi64>
  %powers31 = trikeshed.text %pg30 : memref<20xi64> -> !s64
  %digits32 = trikeshed.series %dc29 : !text {
  ^bb0(%k: index):
    %last33 = arith.subi %dc29, %c12 : index
    %e34 = arith.subi %last33, %k : index
    %p35 = trikeshed.at %powers31[%e34] : !s64, index -> i64
    %q36 = arith.divui %vv28, %p35 : i64
    %dd37 = arith.remui %q36, %c17 : i64
    %d838 = arith.trunci %dd37 : i64 to i8
    %ch39 = arith.addi %d838, %c20 : i8
    trikeshed.yield %ch39 : i8
  }
  %ws40, %wl41 = func.call @st_word(%c42) : (index) -> (index, index)
  %w43 = trikeshed.slice %blob[%ws40, %wl41] : !text -> !text
  %wb44 = llvm.getelementptr %wins[%c5] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wp45 = llvm.load %wb44 : !llvm.ptr -> !llvm.ptr
  %wl47 = llvm.getelementptr %wb44[%c46] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wn48 = llvm.load %wl47 : !llvm.ptr -> i64
  %d49 = func.call @st_desc8(%wp45, %wn48) : (!llvm.ptr, i64) -> !d
  %m50 = builtin.unrealized_conversion_cast %d49 : !d to !m8
  %s51 = builtin.unrealized_conversion_cast %m50 : !m8 to !text
  %ws52, %wl53 = func.call @st_word(%c54) : (index) -> (index, index)
  %w55 = trikeshed.slice %blob[%ws52, %wl53] : !text -> !text
  %vp57 = llvm.getelementptr %vals[%c56] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv58 = llvm.load %vp57 : !llvm.ptr -> i64
  %dc59 = func.call @st_dcount(%vv58) : (i64) -> index
  %pg60 = memref.get_global @st_pow : memref<20xi64>
  %powers61 = trikeshed.text %pg60 : memref<20xi64> -> !s64
  %digits62 = trikeshed.series %dc59 : !text {
  ^bb0(%k: index):
    %last63 = arith.subi %dc59, %c12 : index
    %e64 = arith.subi %last63, %k : index
    %p65 = trikeshed.at %powers61[%e64] : !s64, index -> i64
    %q66 = arith.divui %vv58, %p65 : i64
    %dd67 = arith.remui %q66, %c17 : i64
    %d868 = arith.trunci %dd67 : i64 to i8
    %ch69 = arith.addi %d868, %c20 : i8
    trikeshed.yield %ch69 : i8
  }
  %ws70, %wl71 = func.call @st_word(%c72) : (index) -> (index, index)
  %w73 = trikeshed.slice %blob[%ws70, %wl71] : !text -> !text
  %wb75 = llvm.getelementptr %wins[%c74] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wp76 = llvm.load %wb75 : !llvm.ptr -> !llvm.ptr
  %wl77 = llvm.getelementptr %wb75[%c46] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wn78 = llvm.load %wl77 : !llvm.ptr -> i64
  %d79 = func.call @st_desc8(%wp76, %wn78) : (!llvm.ptr, i64) -> !d
  %m80 = builtin.unrealized_conversion_cast %d79 : !d to !m8
  %s81 = builtin.unrealized_conversion_cast %m80 : !m8 to !text
  %ws82, %wl83 = func.call @st_word(%c84) : (index) -> (index, index)
  %w85 = trikeshed.slice %blob[%ws82, %wl83] : !text -> !text
  %vp87 = llvm.getelementptr %vals[%c86] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv88 = llvm.load %vp87 : !llvm.ptr -> i64
  %dc89 = func.call @st_dcount(%vv88) : (i64) -> index
  %pg90 = memref.get_global @st_pow : memref<20xi64>
  %powers91 = trikeshed.text %pg90 : memref<20xi64> -> !s64
  %digits92 = trikeshed.series %dc89 : !text {
  ^bb0(%k: index):
    %last93 = arith.subi %dc89, %c12 : index
    %e94 = arith.subi %last93, %k : index
    %p95 = trikeshed.at %powers91[%e94] : !s64, index -> i64
    %q96 = arith.divui %vv88, %p95 : i64
    %dd97 = arith.remui %q96, %c17 : i64
    %d898 = arith.trunci %dd97 : i64 to i8
    %ch99 = arith.addi %d898, %c20 : i8
    trikeshed.yield %ch99 : i8
  }
  %ws100, %wl101 = func.call @st_word(%c102) : (index) -> (index, index)
  %w103 = trikeshed.slice %blob[%ws100, %wl101] : !text -> !text
  %wb105 = llvm.getelementptr %wins[%c104] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wp106 = llvm.load %wb105 : !llvm.ptr -> !llvm.ptr
  %wl107 = llvm.getelementptr %wb105[%c46] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wn108 = llvm.load %wl107 : !llvm.ptr -> i64
  %d109 = func.call @st_desc8(%wp106, %wn108) : (!llvm.ptr, i64) -> !d
  %m110 = builtin.unrealized_conversion_cast %d109 : !d to !m8
  %s111 = builtin.unrealized_conversion_cast %m110 : !m8 to !text
  %ws112, %wl113 = func.call @st_word(%c114) : (index) -> (index, index)
  %w115 = trikeshed.slice %blob[%ws112, %wl113] : !text -> !text
  %vp117 = llvm.getelementptr %vals[%c116] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv118 = llvm.load %vp117 : !llvm.ptr -> i64
  %dc119 = func.call @st_dcount(%vv118) : (i64) -> index
  %pg120 = memref.get_global @st_pow : memref<20xi64>
  %powers121 = trikeshed.text %pg120 : memref<20xi64> -> !s64
  %digits122 = trikeshed.series %dc119 : !text {
  ^bb0(%k: index):
    %last123 = arith.subi %dc119, %c12 : index
    %e124 = arith.subi %last123, %k : index
    %p125 = trikeshed.at %powers121[%e124] : !s64, index -> i64
    %q126 = arith.divui %vv118, %p125 : i64
    %dd127 = arith.remui %q126, %c17 : i64
    %d8128 = arith.trunci %dd127 : i64 to i8
    %ch129 = arith.addi %d8128, %c20 : i8
    trikeshed.yield %ch129 : i8
  }
  %ws130, %wl131 = func.call @st_word(%c132) : (index) -> (index, index)
  %w133 = trikeshed.slice %blob[%ws130, %wl131] : !text -> !text
  %wb135 = llvm.getelementptr %wins[%c134] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wp136 = llvm.load %wb135 : !llvm.ptr -> !llvm.ptr
  %wl137 = llvm.getelementptr %wb135[%c46] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wn138 = llvm.load %wl137 : !llvm.ptr -> i64
  %d139 = func.call @st_desc8(%wp136, %wn138) : (!llvm.ptr, i64) -> !d
  %m140 = builtin.unrealized_conversion_cast %d139 : !d to !m8
  %s141 = builtin.unrealized_conversion_cast %m140 : !m8 to !text
  %ws142, %wl143 = func.call @st_word(%c144) : (index) -> (index, index)
  %w145 = trikeshed.slice %blob[%ws142, %wl143] : !text -> !text
  %wb147 = llvm.getelementptr %wins[%c146] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wp148 = llvm.load %wb147 : !llvm.ptr -> !llvm.ptr
  %wl149 = llvm.getelementptr %wb147[%c46] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wn150 = llvm.load %wl149 : !llvm.ptr -> i64
  %d151 = func.call @st_desc8(%wp148, %wn150) : (!llvm.ptr, i64) -> !d
  %m152 = builtin.unrealized_conversion_cast %d151 : !d to !m8
  %s153 = builtin.unrealized_conversion_cast %m152 : !m8 to !text
  %ws154, %wl155 = func.call @st_word(%c156) : (index) -> (index, index)
  %w157 = trikeshed.slice %blob[%ws154, %wl155] : !text -> !text
  %wb159 = llvm.getelementptr %wins[%c158] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wp160 = llvm.load %wb159 : !llvm.ptr -> !llvm.ptr
  %wl161 = llvm.getelementptr %wb159[%c46] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wn162 = llvm.load %wl161 : !llvm.ptr -> i64
  %d163 = func.call @st_desc8(%wp160, %wn162) : (!llvm.ptr, i64) -> !d
  %m164 = builtin.unrealized_conversion_cast %d163 : !d to !m8
  %s165 = builtin.unrealized_conversion_cast %m164 : !m8 to !text
  %ws166, %wl167 = func.call @st_word(%c168) : (index) -> (index, index)
  %w169 = trikeshed.slice %blob[%ws166, %wl167] : !text -> !text
  %wb171 = llvm.getelementptr %wins[%c170] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wp172 = llvm.load %wb171 : !llvm.ptr -> !llvm.ptr
  %wl173 = llvm.getelementptr %wb171[%c46] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wn174 = llvm.load %wl173 : !llvm.ptr -> i64
  %d175 = func.call @st_desc8(%wp172, %wn174) : (!llvm.ptr, i64) -> !d
  %m176 = builtin.unrealized_conversion_cast %d175 : !d to !m8
  %s177 = builtin.unrealized_conversion_cast %m176 : !m8 to !text
  %ws178, %wl179 = func.call @st_word(%c180) : (index) -> (index, index)
  %w181 = trikeshed.slice %blob[%ws178, %wl179] : !text -> !text
  %whole182 = trikeshed.combine %w4, %digits11, %w25, %digits32, %w43, %s51, %w55, %digits62, %w73, %s81, %w85, %digits92, %w103, %s111, %w115, %digits122, %w133, %s141, %w145, %s153, %w157, %s165, %w169, %s177, %w181 : !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text -> !text
  %sz = trikeshed.size %whole182 : !text
  %szi = arith.index_cast %sz : index to i64
  %capi = arith.index_cast %cap : i64 to index
  %fits = arith.cmpi ule, %sz, %capi : index
  scf.if %fits {
    %end = trikeshed.drain %whole182, %mi : !text, !m8 -> index
  }
  return %szi : i64
}

func.func private @st_l_9(%vals: !llvm.ptr, %wins: !llvm.ptr, %rows: !llvm.ptr, %nrows: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %c3 = arith.constant 49 : index
  %c5 = arith.constant 0 : i64
  %c12 = arith.constant 1 : index
  %c17 = arith.constant 10 : i64
  %c20 = arith.constant 48 : i8
  %c24 = arith.constant 50 : index
  %c26 = arith.constant 1 : i64
  %c42 = arith.constant 51 : index
  %c44 = arith.constant 2 : i64
  %c60 = arith.constant 52 : index
  %c64 = arith.constant 8 : i64
  %c72 = arith.constant 53 : index
  %c74 = arith.constant 3 : i64
  %c90 = arith.constant 10 : index
  %c92 = arith.constant 16 : i64
  %c102 = arith.constant 54 : index
  %c104 = arith.constant 32 : i64
  %c114 = arith.constant 55 : index
  %c116 = arith.constant 4 : i64
  %c133 = arith.constant 48 : i64
  %c144 = arith.constant 64 : i64
  %c154 = arith.constant 56 : index
  %c156 = arith.constant 5 : i64
  %c172 = arith.constant 3 : index
  %di = func.call @st_desc8(%into, %cap) : (!llvm.ptr, i64) -> !d
  %mi = builtin.unrealized_conversion_cast %di : !d to !m8
  %bg = memref.get_global @st_blob : memref<2642xi8>
  %blob = trikeshed.text %bg : memref<2642xi8> -> !text
  %spg = memref.get_global @st_sp : memref<32xi8>
  %sp = trikeshed.text %spg : memref<32xi8> -> !text
  %ws1, %wl2 = func.call @st_word(%c3) : (index) -> (index, index)
  %w4 = trikeshed.slice %blob[%ws1, %wl2] : !text -> !text
  %vp6 = llvm.getelementptr %vals[%c5] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv7 = llvm.load %vp6 : !llvm.ptr -> i64
  %dc8 = func.call @st_dcount(%vv7) : (i64) -> index
  %pg9 = memref.get_global @st_pow : memref<20xi64>
  %powers10 = trikeshed.text %pg9 : memref<20xi64> -> !s64
  %digits11 = trikeshed.series %dc8 : !text {
  ^bb0(%k: index):
    %last13 = arith.subi %dc8, %c12 : index
    %e14 = arith.subi %last13, %k : index
    %p15 = trikeshed.at %powers10[%e14] : !s64, index -> i64
    %q16 = arith.divui %vv7, %p15 : i64
    %dd18 = arith.remui %q16, %c17 : i64
    %d819 = arith.trunci %dd18 : i64 to i8
    %ch21 = arith.addi %d819, %c20 : i8
    trikeshed.yield %ch21 : i8
  }
  %ws22, %wl23 = func.call @st_word(%c24) : (index) -> (index, index)
  %w25 = trikeshed.slice %blob[%ws22, %wl23] : !text -> !text
  %vp27 = llvm.getelementptr %vals[%c26] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv28 = llvm.load %vp27 : !llvm.ptr -> i64
  %dc29 = func.call @st_dcount(%vv28) : (i64) -> index
  %pg30 = memref.get_global @st_pow : memref<20xi64>
  %powers31 = trikeshed.text %pg30 : memref<20xi64> -> !s64
  %digits32 = trikeshed.series %dc29 : !text {
  ^bb0(%k: index):
    %last33 = arith.subi %dc29, %c12 : index
    %e34 = arith.subi %last33, %k : index
    %p35 = trikeshed.at %powers31[%e34] : !s64, index -> i64
    %q36 = arith.divui %vv28, %p35 : i64
    %dd37 = arith.remui %q36, %c17 : i64
    %d838 = arith.trunci %dd37 : i64 to i8
    %ch39 = arith.addi %d838, %c20 : i8
    trikeshed.yield %ch39 : i8
  }
  %ws40, %wl41 = func.call @st_word(%c42) : (index) -> (index, index)
  %w43 = trikeshed.slice %blob[%ws40, %wl41] : !text -> !text
  %vp45 = llvm.getelementptr %vals[%c44] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv46 = llvm.load %vp45 : !llvm.ptr -> i64
  %dc47 = func.call @st_dcount(%vv46) : (i64) -> index
  %pg48 = memref.get_global @st_pow : memref<20xi64>
  %powers49 = trikeshed.text %pg48 : memref<20xi64> -> !s64
  %digits50 = trikeshed.series %dc47 : !text {
  ^bb0(%k: index):
    %last51 = arith.subi %dc47, %c12 : index
    %e52 = arith.subi %last51, %k : index
    %p53 = trikeshed.at %powers49[%e52] : !s64, index -> i64
    %q54 = arith.divui %vv46, %p53 : i64
    %dd55 = arith.remui %q54, %c17 : i64
    %d856 = arith.trunci %dd55 : i64 to i8
    %ch57 = arith.addi %d856, %c20 : i8
    trikeshed.yield %ch57 : i8
  }
  %ws58, %wl59 = func.call @st_word(%c60) : (index) -> (index, index)
  %w61 = trikeshed.slice %blob[%ws58, %wl59] : !text -> !text
  %wb62 = llvm.getelementptr %wins[%c5] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wp63 = llvm.load %wb62 : !llvm.ptr -> !llvm.ptr
  %wl65 = llvm.getelementptr %wb62[%c64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wn66 = llvm.load %wl65 : !llvm.ptr -> i64
  %d67 = func.call @st_desc8(%wp63, %wn66) : (!llvm.ptr, i64) -> !d
  %m68 = builtin.unrealized_conversion_cast %d67 : !d to !m8
  %s69 = builtin.unrealized_conversion_cast %m68 : !m8 to !text
  %ws70, %wl71 = func.call @st_word(%c72) : (index) -> (index, index)
  %w73 = trikeshed.slice %blob[%ws70, %wl71] : !text -> !text
  %vp75 = llvm.getelementptr %vals[%c74] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv76 = llvm.load %vp75 : !llvm.ptr -> i64
  %dc77 = func.call @st_dcount(%vv76) : (i64) -> index
  %pg78 = memref.get_global @st_pow : memref<20xi64>
  %powers79 = trikeshed.text %pg78 : memref<20xi64> -> !s64
  %digits80 = trikeshed.series %dc77 : !text {
  ^bb0(%k: index):
    %last81 = arith.subi %dc77, %c12 : index
    %e82 = arith.subi %last81, %k : index
    %p83 = trikeshed.at %powers79[%e82] : !s64, index -> i64
    %q84 = arith.divui %vv76, %p83 : i64
    %dd85 = arith.remui %q84, %c17 : i64
    %d886 = arith.trunci %dd85 : i64 to i8
    %ch87 = arith.addi %d886, %c20 : i8
    trikeshed.yield %ch87 : i8
  }
  %ws88, %wl89 = func.call @st_word(%c90) : (index) -> (index, index)
  %w91 = trikeshed.slice %blob[%ws88, %wl89] : !text -> !text
  %wb93 = llvm.getelementptr %wins[%c92] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wp94 = llvm.load %wb93 : !llvm.ptr -> !llvm.ptr
  %wl95 = llvm.getelementptr %wb93[%c64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wn96 = llvm.load %wl95 : !llvm.ptr -> i64
  %d97 = func.call @st_desc8(%wp94, %wn96) : (!llvm.ptr, i64) -> !d
  %m98 = builtin.unrealized_conversion_cast %d97 : !d to !m8
  %s99 = builtin.unrealized_conversion_cast %m98 : !m8 to !text
  %ws100, %wl101 = func.call @st_word(%c102) : (index) -> (index, index)
  %w103 = trikeshed.slice %blob[%ws100, %wl101] : !text -> !text
  %wb105 = llvm.getelementptr %wins[%c104] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wp106 = llvm.load %wb105 : !llvm.ptr -> !llvm.ptr
  %wl107 = llvm.getelementptr %wb105[%c64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wn108 = llvm.load %wl107 : !llvm.ptr -> i64
  %d109 = func.call @st_desc8(%wp106, %wn108) : (!llvm.ptr, i64) -> !d
  %m110 = builtin.unrealized_conversion_cast %d109 : !d to !m8
  %s111 = builtin.unrealized_conversion_cast %m110 : !m8 to !text
  %ws112, %wl113 = func.call @st_word(%c114) : (index) -> (index, index)
  %w115 = trikeshed.slice %blob[%ws112, %wl113] : !text -> !text
  %vp117 = llvm.getelementptr %vals[%c116] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv118 = llvm.load %vp117 : !llvm.ptr -> i64
  %dc119 = func.call @st_dcount(%vv118) : (i64) -> index
  %pg120 = memref.get_global @st_pow : memref<20xi64>
  %powers121 = trikeshed.text %pg120 : memref<20xi64> -> !s64
  %digits122 = trikeshed.series %dc119 : !text {
  ^bb0(%k: index):
    %last123 = arith.subi %dc119, %c12 : index
    %e124 = arith.subi %last123, %k : index
    %p125 = trikeshed.at %powers121[%e124] : !s64, index -> i64
    %q126 = arith.divui %vv118, %p125 : i64
    %dd127 = arith.remui %q126, %c17 : i64
    %d8128 = arith.trunci %dd127 : i64 to i8
    %ch129 = arith.addi %d8128, %c20 : i8
    trikeshed.yield %ch129 : i8
  }
  %ws130, %wl131 = func.call @st_word(%c90) : (index) -> (index, index)
  %w132 = trikeshed.slice %blob[%ws130, %wl131] : !text -> !text
  %wb134 = llvm.getelementptr %wins[%c133] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wp135 = llvm.load %wb134 : !llvm.ptr -> !llvm.ptr
  %wl136 = llvm.getelementptr %wb134[%c64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wn137 = llvm.load %wl136 : !llvm.ptr -> i64
  %d138 = func.call @st_desc8(%wp135, %wn137) : (!llvm.ptr, i64) -> !d
  %m139 = builtin.unrealized_conversion_cast %d138 : !d to !m8
  %s140 = builtin.unrealized_conversion_cast %m139 : !m8 to !text
  %ws141, %wl142 = func.call @st_word(%c102) : (index) -> (index, index)
  %w143 = trikeshed.slice %blob[%ws141, %wl142] : !text -> !text
  %wb145 = llvm.getelementptr %wins[%c144] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wp146 = llvm.load %wb145 : !llvm.ptr -> !llvm.ptr
  %wl147 = llvm.getelementptr %wb145[%c64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wn148 = llvm.load %wl147 : !llvm.ptr -> i64
  %d149 = func.call @st_desc8(%wp146, %wn148) : (!llvm.ptr, i64) -> !d
  %m150 = builtin.unrealized_conversion_cast %d149 : !d to !m8
  %s151 = builtin.unrealized_conversion_cast %m150 : !m8 to !text
  %ws152, %wl153 = func.call @st_word(%c154) : (index) -> (index, index)
  %w155 = trikeshed.slice %blob[%ws152, %wl153] : !text -> !text
  %vp157 = llvm.getelementptr %vals[%c156] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv158 = llvm.load %vp157 : !llvm.ptr -> i64
  %dc159 = func.call @st_dcount(%vv158) : (i64) -> index
  %pg160 = memref.get_global @st_pow : memref<20xi64>
  %powers161 = trikeshed.text %pg160 : memref<20xi64> -> !s64
  %digits162 = trikeshed.series %dc159 : !text {
  ^bb0(%k: index):
    %last163 = arith.subi %dc159, %c12 : index
    %e164 = arith.subi %last163, %k : index
    %p165 = trikeshed.at %powers161[%e164] : !s64, index -> i64
    %q166 = arith.divui %vv158, %p165 : i64
    %dd167 = arith.remui %q166, %c17 : i64
    %d8168 = arith.trunci %dd167 : i64 to i8
    %ch169 = arith.addi %d8168, %c20 : i8
    trikeshed.yield %ch169 : i8
  }
  %ws170, %wl171 = func.call @st_word(%c172) : (index) -> (index, index)
  %w173 = trikeshed.slice %blob[%ws170, %wl171] : !text -> !text
  %whole174 = trikeshed.combine %w4, %digits11, %w25, %digits32, %w43, %digits50, %w61, %s69, %w73, %digits80, %w91, %s99, %w103, %s111, %w115, %digits122, %w132, %s140, %w143, %s151, %w155, %digits162, %w173 : !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text -> !text
  %sz = trikeshed.size %whole174 : !text
  %szi = arith.index_cast %sz : index to i64
  %capi = arith.index_cast %cap : i64 to index
  %fits = arith.cmpi ule, %sz, %capi : index
  scf.if %fits {
    %end = trikeshed.drain %whole174, %mi : !text, !m8 -> index
  }
  return %szi : i64
}

func.func private @st_l_10(%vals: !llvm.ptr, %wins: !llvm.ptr, %rows: !llvm.ptr, %nrows: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %c3 = arith.constant 57 : index
  %c5 = arith.constant 0 : i64
  %c12 = arith.constant 1 : index
  %c17 = arith.constant 10 : i64
  %c20 = arith.constant 48 : i8
  %c24 = arith.constant 58 : index
  %c26 = arith.constant 1 : i64
  %c42 = arith.constant 59 : index
  %c44 = arith.constant 2 : i64
  %c60 = arith.constant 60 : index
  %c62 = arith.constant 3 : i64
  %c78 = arith.constant 3 : index
  %di = func.call @st_desc8(%into, %cap) : (!llvm.ptr, i64) -> !d
  %mi = builtin.unrealized_conversion_cast %di : !d to !m8
  %bg = memref.get_global @st_blob : memref<2642xi8>
  %blob = trikeshed.text %bg : memref<2642xi8> -> !text
  %spg = memref.get_global @st_sp : memref<32xi8>
  %sp = trikeshed.text %spg : memref<32xi8> -> !text
  %ws1, %wl2 = func.call @st_word(%c3) : (index) -> (index, index)
  %w4 = trikeshed.slice %blob[%ws1, %wl2] : !text -> !text
  %vp6 = llvm.getelementptr %vals[%c5] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv7 = llvm.load %vp6 : !llvm.ptr -> i64
  %dc8 = func.call @st_dcount(%vv7) : (i64) -> index
  %pg9 = memref.get_global @st_pow : memref<20xi64>
  %powers10 = trikeshed.text %pg9 : memref<20xi64> -> !s64
  %digits11 = trikeshed.series %dc8 : !text {
  ^bb0(%k: index):
    %last13 = arith.subi %dc8, %c12 : index
    %e14 = arith.subi %last13, %k : index
    %p15 = trikeshed.at %powers10[%e14] : !s64, index -> i64
    %q16 = arith.divui %vv7, %p15 : i64
    %dd18 = arith.remui %q16, %c17 : i64
    %d819 = arith.trunci %dd18 : i64 to i8
    %ch21 = arith.addi %d819, %c20 : i8
    trikeshed.yield %ch21 : i8
  }
  %ws22, %wl23 = func.call @st_word(%c24) : (index) -> (index, index)
  %w25 = trikeshed.slice %blob[%ws22, %wl23] : !text -> !text
  %vp27 = llvm.getelementptr %vals[%c26] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv28 = llvm.load %vp27 : !llvm.ptr -> i64
  %dc29 = func.call @st_dcount(%vv28) : (i64) -> index
  %pg30 = memref.get_global @st_pow : memref<20xi64>
  %powers31 = trikeshed.text %pg30 : memref<20xi64> -> !s64
  %digits32 = trikeshed.series %dc29 : !text {
  ^bb0(%k: index):
    %last33 = arith.subi %dc29, %c12 : index
    %e34 = arith.subi %last33, %k : index
    %p35 = trikeshed.at %powers31[%e34] : !s64, index -> i64
    %q36 = arith.divui %vv28, %p35 : i64
    %dd37 = arith.remui %q36, %c17 : i64
    %d838 = arith.trunci %dd37 : i64 to i8
    %ch39 = arith.addi %d838, %c20 : i8
    trikeshed.yield %ch39 : i8
  }
  %ws40, %wl41 = func.call @st_word(%c42) : (index) -> (index, index)
  %w43 = trikeshed.slice %blob[%ws40, %wl41] : !text -> !text
  %vp45 = llvm.getelementptr %vals[%c44] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv46 = llvm.load %vp45 : !llvm.ptr -> i64
  %dc47 = func.call @st_dcount(%vv46) : (i64) -> index
  %pg48 = memref.get_global @st_pow : memref<20xi64>
  %powers49 = trikeshed.text %pg48 : memref<20xi64> -> !s64
  %digits50 = trikeshed.series %dc47 : !text {
  ^bb0(%k: index):
    %last51 = arith.subi %dc47, %c12 : index
    %e52 = arith.subi %last51, %k : index
    %p53 = trikeshed.at %powers49[%e52] : !s64, index -> i64
    %q54 = arith.divui %vv46, %p53 : i64
    %dd55 = arith.remui %q54, %c17 : i64
    %d856 = arith.trunci %dd55 : i64 to i8
    %ch57 = arith.addi %d856, %c20 : i8
    trikeshed.yield %ch57 : i8
  }
  %ws58, %wl59 = func.call @st_word(%c60) : (index) -> (index, index)
  %w61 = trikeshed.slice %blob[%ws58, %wl59] : !text -> !text
  %vp63 = llvm.getelementptr %vals[%c62] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv64 = llvm.load %vp63 : !llvm.ptr -> i64
  %dc65 = func.call @st_dcount(%vv64) : (i64) -> index
  %pg66 = memref.get_global @st_pow : memref<20xi64>
  %powers67 = trikeshed.text %pg66 : memref<20xi64> -> !s64
  %digits68 = trikeshed.series %dc65 : !text {
  ^bb0(%k: index):
    %last69 = arith.subi %dc65, %c12 : index
    %e70 = arith.subi %last69, %k : index
    %p71 = trikeshed.at %powers67[%e70] : !s64, index -> i64
    %q72 = arith.divui %vv64, %p71 : i64
    %dd73 = arith.remui %q72, %c17 : i64
    %d874 = arith.trunci %dd73 : i64 to i8
    %ch75 = arith.addi %d874, %c20 : i8
    trikeshed.yield %ch75 : i8
  }
  %ws76, %wl77 = func.call @st_word(%c78) : (index) -> (index, index)
  %w79 = trikeshed.slice %blob[%ws76, %wl77] : !text -> !text
  %whole80 = trikeshed.combine %w4, %digits11, %w25, %digits32, %w43, %digits50, %w61, %digits68, %w79 : !text, !text, !text, !text, !text, !text, !text, !text, !text -> !text
  %sz = trikeshed.size %whole80 : !text
  %szi = arith.index_cast %sz : index to i64
  %capi = arith.index_cast %cap : i64 to index
  %fits = arith.cmpi ule, %sz, %capi : index
  scf.if %fits {
    %end = trikeshed.drain %whole80, %mi : !text, !m8 -> index
  }
  return %szi : i64
}

func.func private @st_l_11(%vals: !llvm.ptr, %wins: !llvm.ptr, %rows: !llvm.ptr, %nrows: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %c3 = arith.constant 61 : index
  %c8 = arith.constant 64 : i64
  %c12 = arith.constant 0 : i64
  %c15 = arith.constant 8 : i64
  %c18 = arith.constant 16 : i64
  %c21 = arith.constant 24 : i64
  %c24 = arith.constant 32 : i64
  %c27 = arith.constant 40 : i64
  %c30 = arith.constant 48 : i64
  %c35 = arith.constant 111 : index
  %c47 = arith.constant 1 : index
  %c52 = arith.constant 10 : i64
  %c55 = arith.constant 48 : i8
  %c59 = arith.constant 112 : index
  %c89 = arith.constant 3 : index
  %di = func.call @st_desc8(%into, %cap) : (!llvm.ptr, i64) -> !d
  %mi = builtin.unrealized_conversion_cast %di : !d to !m8
  %bg = memref.get_global @st_blob : memref<2642xi8>
  %blob = trikeshed.text %bg : memref<2642xi8> -> !text
  %spg = memref.get_global @st_sp : memref<32xi8>
  %sp = trikeshed.text %spg : memref<32xi8> -> !text
  %ws1, %wl2 = func.call @st_word(%c3) : (index) -> (index, index)
  %w4 = trikeshed.slice %blob[%ws1, %wl2] : !text -> !text
  %ni5 = arith.index_cast %nrows : i64 to index
  %rows6, %rco7 = trikeshed.combineAll %ni5 : !text, !coords {
  ^bb0(%j: index):
  %j649 = arith.index_cast %j : index to i64
  %ro10 = arith.muli %j649, %c8 : i64
  %rb11 = llvm.getelementptr %rows[%ro10] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fp13 = llvm.getelementptr %rb11[%c12] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fv14 = llvm.load %fp13 : !llvm.ptr -> !llvm.ptr
  %fp16 = llvm.getelementptr %rb11[%c15] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fv17 = llvm.load %fp16 : !llvm.ptr -> i64
  %fp19 = llvm.getelementptr %rb11[%c18] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fv20 = llvm.load %fp19 : !llvm.ptr -> i64
  %fp22 = llvm.getelementptr %rb11[%c21] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fv23 = llvm.load %fp22 : !llvm.ptr -> i64
  %fp25 = llvm.getelementptr %rb11[%c24] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fv26 = llvm.load %fp25 : !llvm.ptr -> i64
  %fp28 = llvm.getelementptr %rb11[%c27] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fv29 = llvm.load %fp28 : !llvm.ptr -> !llvm.ptr
  %fp31 = llvm.getelementptr %rb11[%c30] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fv32 = llvm.load %fp31 : !llvm.ptr -> i64
  %ws33, %wl34 = func.call @st_word(%c35) : (index) -> (index, index)
  %w36 = trikeshed.slice %blob[%ws33, %wl34] : !text -> !text
  %d37 = func.call @st_desc8(%fv14, %fv17) : (!llvm.ptr, i64) -> !d
  %m38 = builtin.unrealized_conversion_cast %d37 : !d to !m8
  %s39 = builtin.unrealized_conversion_cast %m38 : !m8 to !text
  %ws40, %wl41 = func.call @st_word(%c35) : (index) -> (index, index)
  %w42 = trikeshed.slice %blob[%ws40, %wl41] : !text -> !text
  %dc43 = func.call @st_dcount(%fv20) : (i64) -> index
  %pg44 = memref.get_global @st_pow : memref<20xi64>
  %powers45 = trikeshed.text %pg44 : memref<20xi64> -> !s64
  %digits46 = trikeshed.series %dc43 : !text {
  ^bb0(%k: index):
    %last48 = arith.subi %dc43, %c47 : index
    %e49 = arith.subi %last48, %k : index
    %p50 = trikeshed.at %powers45[%e49] : !s64, index -> i64
    %q51 = arith.divui %fv20, %p50 : i64
    %dd53 = arith.remui %q51, %c52 : i64
    %d854 = arith.trunci %dd53 : i64 to i8
    %ch56 = arith.addi %d854, %c55 : i8
    trikeshed.yield %ch56 : i8
  }
  %ws57, %wl58 = func.call @st_word(%c59) : (index) -> (index, index)
  %w60 = trikeshed.slice %blob[%ws57, %wl58] : !text -> !text
  %dc61 = func.call @st_dcount(%fv23) : (i64) -> index
  %pg62 = memref.get_global @st_pow : memref<20xi64>
  %powers63 = trikeshed.text %pg62 : memref<20xi64> -> !s64
  %digits64 = trikeshed.series %dc61 : !text {
  ^bb0(%k: index):
    %last65 = arith.subi %dc61, %c47 : index
    %e66 = arith.subi %last65, %k : index
    %p67 = trikeshed.at %powers63[%e66] : !s64, index -> i64
    %q68 = arith.divui %fv23, %p67 : i64
    %dd69 = arith.remui %q68, %c52 : i64
    %d870 = arith.trunci %dd69 : i64 to i8
    %ch71 = arith.addi %d870, %c55 : i8
    trikeshed.yield %ch71 : i8
  }
  %ws72, %wl73 = func.call @st_word(%c59) : (index) -> (index, index)
  %w74 = trikeshed.slice %blob[%ws72, %wl73] : !text -> !text
  %dc75 = func.call @st_dcount(%fv26) : (i64) -> index
  %pg76 = memref.get_global @st_pow : memref<20xi64>
  %powers77 = trikeshed.text %pg76 : memref<20xi64> -> !s64
  %digits78 = trikeshed.series %dc75 : !text {
  ^bb0(%k: index):
    %last79 = arith.subi %dc75, %c47 : index
    %e80 = arith.subi %last79, %k : index
    %p81 = trikeshed.at %powers77[%e80] : !s64, index -> i64
    %q82 = arith.divui %fv26, %p81 : i64
    %dd83 = arith.remui %q82, %c52 : i64
    %d884 = arith.trunci %dd83 : i64 to i8
    %ch85 = arith.addi %d884, %c55 : i8
    trikeshed.yield %ch85 : i8
  }
  %row86 = trikeshed.combine %w36, %s39, %w42, %digits46, %w60, %digits64, %w74, %digits78 : !text, !text, !text, !text, !text, !text, !text, !text -> !text
    trikeshed.yield %row86 : !text
  }
  %ws87, %wl88 = func.call @st_word(%c89) : (index) -> (index, index)
  %w90 = trikeshed.slice %blob[%ws87, %wl88] : !text -> !text
  %whole91 = trikeshed.combine %w4, %rows6, %w90 : !text, !text, !text -> !text
  %sz = trikeshed.size %whole91 : !text
  %szi = arith.index_cast %sz : index to i64
  %capi = arith.index_cast %cap : i64 to index
  %fits = arith.cmpi ule, %sz, %capi : index
  scf.if %fits {
    %end = trikeshed.drain %whole91, %mi : !text, !m8 -> index
  }
  return %szi : i64
}

func.func private @st_l_12(%vals: !llvm.ptr, %wins: !llvm.ptr, %rows: !llvm.ptr, %nrows: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %c3 = arith.constant 62 : index
  %c5 = arith.constant 0 : i64
  %c12 = arith.constant 1 : index
  %c17 = arith.constant 10 : i64
  %c20 = arith.constant 48 : i8
  %c24 = arith.constant 3 : index
  %di = func.call @st_desc8(%into, %cap) : (!llvm.ptr, i64) -> !d
  %mi = builtin.unrealized_conversion_cast %di : !d to !m8
  %bg = memref.get_global @st_blob : memref<2642xi8>
  %blob = trikeshed.text %bg : memref<2642xi8> -> !text
  %spg = memref.get_global @st_sp : memref<32xi8>
  %sp = trikeshed.text %spg : memref<32xi8> -> !text
  %ws1, %wl2 = func.call @st_word(%c3) : (index) -> (index, index)
  %w4 = trikeshed.slice %blob[%ws1, %wl2] : !text -> !text
  %vp6 = llvm.getelementptr %vals[%c5] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv7 = llvm.load %vp6 : !llvm.ptr -> i64
  %dc8 = func.call @st_dcount(%vv7) : (i64) -> index
  %pg9 = memref.get_global @st_pow : memref<20xi64>
  %powers10 = trikeshed.text %pg9 : memref<20xi64> -> !s64
  %digits11 = trikeshed.series %dc8 : !text {
  ^bb0(%k: index):
    %last13 = arith.subi %dc8, %c12 : index
    %e14 = arith.subi %last13, %k : index
    %p15 = trikeshed.at %powers10[%e14] : !s64, index -> i64
    %q16 = arith.divui %vv7, %p15 : i64
    %dd18 = arith.remui %q16, %c17 : i64
    %d819 = arith.trunci %dd18 : i64 to i8
    %ch21 = arith.addi %d819, %c20 : i8
    trikeshed.yield %ch21 : i8
  }
  %ws22, %wl23 = func.call @st_word(%c24) : (index) -> (index, index)
  %w25 = trikeshed.slice %blob[%ws22, %wl23] : !text -> !text
  %whole26 = trikeshed.combine %w4, %digits11, %w25 : !text, !text, !text -> !text
  %sz = trikeshed.size %whole26 : !text
  %szi = arith.index_cast %sz : index to i64
  %capi = arith.index_cast %cap : i64 to index
  %fits = arith.cmpi ule, %sz, %capi : index
  scf.if %fits {
    %end = trikeshed.drain %whole26, %mi : !text, !m8 -> index
  }
  return %szi : i64
}

func.func private @st_l_13(%vals: !llvm.ptr, %wins: !llvm.ptr, %rows: !llvm.ptr, %nrows: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %c3 = arith.constant 63 : index
  %c5 = arith.constant 0 : i64
  %c12 = arith.constant 1 : index
  %c17 = arith.constant 10 : i64
  %c20 = arith.constant 48 : i8
  %c24 = arith.constant 3 : index
  %di = func.call @st_desc8(%into, %cap) : (!llvm.ptr, i64) -> !d
  %mi = builtin.unrealized_conversion_cast %di : !d to !m8
  %bg = memref.get_global @st_blob : memref<2642xi8>
  %blob = trikeshed.text %bg : memref<2642xi8> -> !text
  %spg = memref.get_global @st_sp : memref<32xi8>
  %sp = trikeshed.text %spg : memref<32xi8> -> !text
  %ws1, %wl2 = func.call @st_word(%c3) : (index) -> (index, index)
  %w4 = trikeshed.slice %blob[%ws1, %wl2] : !text -> !text
  %vp6 = llvm.getelementptr %vals[%c5] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv7 = llvm.load %vp6 : !llvm.ptr -> i64
  %dc8 = func.call @st_dcount(%vv7) : (i64) -> index
  %pg9 = memref.get_global @st_pow : memref<20xi64>
  %powers10 = trikeshed.text %pg9 : memref<20xi64> -> !s64
  %digits11 = trikeshed.series %dc8 : !text {
  ^bb0(%k: index):
    %last13 = arith.subi %dc8, %c12 : index
    %e14 = arith.subi %last13, %k : index
    %p15 = trikeshed.at %powers10[%e14] : !s64, index -> i64
    %q16 = arith.divui %vv7, %p15 : i64
    %dd18 = arith.remui %q16, %c17 : i64
    %d819 = arith.trunci %dd18 : i64 to i8
    %ch21 = arith.addi %d819, %c20 : i8
    trikeshed.yield %ch21 : i8
  }
  %ws22, %wl23 = func.call @st_word(%c24) : (index) -> (index, index)
  %w25 = trikeshed.slice %blob[%ws22, %wl23] : !text -> !text
  %whole26 = trikeshed.combine %w4, %digits11, %w25 : !text, !text, !text -> !text
  %sz = trikeshed.size %whole26 : !text
  %szi = arith.index_cast %sz : index to i64
  %capi = arith.index_cast %cap : i64 to index
  %fits = arith.cmpi ule, %sz, %capi : index
  scf.if %fits {
    %end = trikeshed.drain %whole26, %mi : !text, !m8 -> index
  }
  return %szi : i64
}

func.func private @st_l_14(%vals: !llvm.ptr, %wins: !llvm.ptr, %rows: !llvm.ptr, %nrows: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %c3 = arith.constant 64 : index
  %c5 = arith.constant 0 : i64
  %c12 = arith.constant 1 : index
  %c17 = arith.constant 10 : i64
  %c20 = arith.constant 48 : i8
  %c24 = arith.constant 10 : index
  %c26 = arith.constant 1 : i64
  %c42 = arith.constant 65 : index
  %di = func.call @st_desc8(%into, %cap) : (!llvm.ptr, i64) -> !d
  %mi = builtin.unrealized_conversion_cast %di : !d to !m8
  %bg = memref.get_global @st_blob : memref<2642xi8>
  %blob = trikeshed.text %bg : memref<2642xi8> -> !text
  %spg = memref.get_global @st_sp : memref<32xi8>
  %sp = trikeshed.text %spg : memref<32xi8> -> !text
  %ws1, %wl2 = func.call @st_word(%c3) : (index) -> (index, index)
  %w4 = trikeshed.slice %blob[%ws1, %wl2] : !text -> !text
  %vp6 = llvm.getelementptr %vals[%c5] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv7 = llvm.load %vp6 : !llvm.ptr -> i64
  %dc8 = func.call @st_dcount(%vv7) : (i64) -> index
  %pg9 = memref.get_global @st_pow : memref<20xi64>
  %powers10 = trikeshed.text %pg9 : memref<20xi64> -> !s64
  %digits11 = trikeshed.series %dc8 : !text {
  ^bb0(%k: index):
    %last13 = arith.subi %dc8, %c12 : index
    %e14 = arith.subi %last13, %k : index
    %p15 = trikeshed.at %powers10[%e14] : !s64, index -> i64
    %q16 = arith.divui %vv7, %p15 : i64
    %dd18 = arith.remui %q16, %c17 : i64
    %d819 = arith.trunci %dd18 : i64 to i8
    %ch21 = arith.addi %d819, %c20 : i8
    trikeshed.yield %ch21 : i8
  }
  %ws22, %wl23 = func.call @st_word(%c24) : (index) -> (index, index)
  %w25 = trikeshed.slice %blob[%ws22, %wl23] : !text -> !text
  %vp27 = llvm.getelementptr %vals[%c26] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv28 = llvm.load %vp27 : !llvm.ptr -> i64
  %dc29 = func.call @st_dcount(%vv28) : (i64) -> index
  %pg30 = memref.get_global @st_pow : memref<20xi64>
  %powers31 = trikeshed.text %pg30 : memref<20xi64> -> !s64
  %digits32 = trikeshed.series %dc29 : !text {
  ^bb0(%k: index):
    %last33 = arith.subi %dc29, %c12 : index
    %e34 = arith.subi %last33, %k : index
    %p35 = trikeshed.at %powers31[%e34] : !s64, index -> i64
    %q36 = arith.divui %vv28, %p35 : i64
    %dd37 = arith.remui %q36, %c17 : i64
    %d838 = arith.trunci %dd37 : i64 to i8
    %ch39 = arith.addi %d838, %c20 : i8
    trikeshed.yield %ch39 : i8
  }
  %ws40, %wl41 = func.call @st_word(%c42) : (index) -> (index, index)
  %w43 = trikeshed.slice %blob[%ws40, %wl41] : !text -> !text
  %whole44 = trikeshed.combine %w4, %digits11, %w25, %digits32, %w43 : !text, !text, !text, !text, !text -> !text
  %sz = trikeshed.size %whole44 : !text
  %szi = arith.index_cast %sz : index to i64
  %capi = arith.index_cast %cap : i64 to index
  %fits = arith.cmpi ule, %sz, %capi : index
  scf.if %fits {
    %end = trikeshed.drain %whole44, %mi : !text, !m8 -> index
  }
  return %szi : i64
}

func.func private @st_l_15(%vals: !llvm.ptr, %wins: !llvm.ptr, %rows: !llvm.ptr, %nrows: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %c3 = arith.constant 66 : index
  %c5 = arith.constant 0 : i64
  %c12 = arith.constant 1 : index
  %c17 = arith.constant 10 : i64
  %c20 = arith.constant 48 : i8
  %c24 = arith.constant 67 : index
  %c26 = arith.constant 1 : i64
  %c42 = arith.constant 68 : index
  %di = func.call @st_desc8(%into, %cap) : (!llvm.ptr, i64) -> !d
  %mi = builtin.unrealized_conversion_cast %di : !d to !m8
  %bg = memref.get_global @st_blob : memref<2642xi8>
  %blob = trikeshed.text %bg : memref<2642xi8> -> !text
  %spg = memref.get_global @st_sp : memref<32xi8>
  %sp = trikeshed.text %spg : memref<32xi8> -> !text
  %ws1, %wl2 = func.call @st_word(%c3) : (index) -> (index, index)
  %w4 = trikeshed.slice %blob[%ws1, %wl2] : !text -> !text
  %vp6 = llvm.getelementptr %vals[%c5] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv7 = llvm.load %vp6 : !llvm.ptr -> i64
  %dc8 = func.call @st_dcount(%vv7) : (i64) -> index
  %pg9 = memref.get_global @st_pow : memref<20xi64>
  %powers10 = trikeshed.text %pg9 : memref<20xi64> -> !s64
  %digits11 = trikeshed.series %dc8 : !text {
  ^bb0(%k: index):
    %last13 = arith.subi %dc8, %c12 : index
    %e14 = arith.subi %last13, %k : index
    %p15 = trikeshed.at %powers10[%e14] : !s64, index -> i64
    %q16 = arith.divui %vv7, %p15 : i64
    %dd18 = arith.remui %q16, %c17 : i64
    %d819 = arith.trunci %dd18 : i64 to i8
    %ch21 = arith.addi %d819, %c20 : i8
    trikeshed.yield %ch21 : i8
  }
  %ws22, %wl23 = func.call @st_word(%c24) : (index) -> (index, index)
  %w25 = trikeshed.slice %blob[%ws22, %wl23] : !text -> !text
  %vp27 = llvm.getelementptr %vals[%c26] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv28 = llvm.load %vp27 : !llvm.ptr -> i64
  %dc29 = func.call @st_dcount(%vv28) : (i64) -> index
  %pg30 = memref.get_global @st_pow : memref<20xi64>
  %powers31 = trikeshed.text %pg30 : memref<20xi64> -> !s64
  %digits32 = trikeshed.series %dc29 : !text {
  ^bb0(%k: index):
    %last33 = arith.subi %dc29, %c12 : index
    %e34 = arith.subi %last33, %k : index
    %p35 = trikeshed.at %powers31[%e34] : !s64, index -> i64
    %q36 = arith.divui %vv28, %p35 : i64
    %dd37 = arith.remui %q36, %c17 : i64
    %d838 = arith.trunci %dd37 : i64 to i8
    %ch39 = arith.addi %d838, %c20 : i8
    trikeshed.yield %ch39 : i8
  }
  %ws40, %wl41 = func.call @st_word(%c42) : (index) -> (index, index)
  %w43 = trikeshed.slice %blob[%ws40, %wl41] : !text -> !text
  %whole44 = trikeshed.combine %w4, %digits11, %w25, %digits32, %w43 : !text, !text, !text, !text, !text -> !text
  %sz = trikeshed.size %whole44 : !text
  %szi = arith.index_cast %sz : index to i64
  %capi = arith.index_cast %cap : i64 to index
  %fits = arith.cmpi ule, %sz, %capi : index
  scf.if %fits {
    %end = trikeshed.drain %whole44, %mi : !text, !m8 -> index
  }
  return %szi : i64
}

func.func private @st_l_16(%vals: !llvm.ptr, %wins: !llvm.ptr, %rows: !llvm.ptr, %nrows: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %c3 = arith.constant 69 : index
  %c5 = arith.constant 0 : i64
  %c12 = arith.constant 1 : index
  %c17 = arith.constant 10 : i64
  %c20 = arith.constant 48 : i8
  %c24 = arith.constant 5 : index
  %c26 = arith.constant 1 : i64
  %c42 = arith.constant 3 : index
  %di = func.call @st_desc8(%into, %cap) : (!llvm.ptr, i64) -> !d
  %mi = builtin.unrealized_conversion_cast %di : !d to !m8
  %bg = memref.get_global @st_blob : memref<2642xi8>
  %blob = trikeshed.text %bg : memref<2642xi8> -> !text
  %spg = memref.get_global @st_sp : memref<32xi8>
  %sp = trikeshed.text %spg : memref<32xi8> -> !text
  %ws1, %wl2 = func.call @st_word(%c3) : (index) -> (index, index)
  %w4 = trikeshed.slice %blob[%ws1, %wl2] : !text -> !text
  %vp6 = llvm.getelementptr %vals[%c5] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv7 = llvm.load %vp6 : !llvm.ptr -> i64
  %dc8 = func.call @st_dcount(%vv7) : (i64) -> index
  %pg9 = memref.get_global @st_pow : memref<20xi64>
  %powers10 = trikeshed.text %pg9 : memref<20xi64> -> !s64
  %digits11 = trikeshed.series %dc8 : !text {
  ^bb0(%k: index):
    %last13 = arith.subi %dc8, %c12 : index
    %e14 = arith.subi %last13, %k : index
    %p15 = trikeshed.at %powers10[%e14] : !s64, index -> i64
    %q16 = arith.divui %vv7, %p15 : i64
    %dd18 = arith.remui %q16, %c17 : i64
    %d819 = arith.trunci %dd18 : i64 to i8
    %ch21 = arith.addi %d819, %c20 : i8
    trikeshed.yield %ch21 : i8
  }
  %ws22, %wl23 = func.call @st_word(%c24) : (index) -> (index, index)
  %w25 = trikeshed.slice %blob[%ws22, %wl23] : !text -> !text
  %vp27 = llvm.getelementptr %vals[%c26] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv28 = llvm.load %vp27 : !llvm.ptr -> i64
  %dc29 = func.call @st_dcount(%vv28) : (i64) -> index
  %pg30 = memref.get_global @st_pow : memref<20xi64>
  %powers31 = trikeshed.text %pg30 : memref<20xi64> -> !s64
  %digits32 = trikeshed.series %dc29 : !text {
  ^bb0(%k: index):
    %last33 = arith.subi %dc29, %c12 : index
    %e34 = arith.subi %last33, %k : index
    %p35 = trikeshed.at %powers31[%e34] : !s64, index -> i64
    %q36 = arith.divui %vv28, %p35 : i64
    %dd37 = arith.remui %q36, %c17 : i64
    %d838 = arith.trunci %dd37 : i64 to i8
    %ch39 = arith.addi %d838, %c20 : i8
    trikeshed.yield %ch39 : i8
  }
  %ws40, %wl41 = func.call @st_word(%c42) : (index) -> (index, index)
  %w43 = trikeshed.slice %blob[%ws40, %wl41] : !text -> !text
  %whole44 = trikeshed.combine %w4, %digits11, %w25, %digits32, %w43 : !text, !text, !text, !text, !text -> !text
  %sz = trikeshed.size %whole44 : !text
  %szi = arith.index_cast %sz : index to i64
  %capi = arith.index_cast %cap : i64 to index
  %fits = arith.cmpi ule, %sz, %capi : index
  scf.if %fits {
    %end = trikeshed.drain %whole44, %mi : !text, !m8 -> index
  }
  return %szi : i64
}

func.func private @st_l_17(%vals: !llvm.ptr, %wins: !llvm.ptr, %rows: !llvm.ptr, %nrows: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %c3 = arith.constant 70 : index
  %c5 = arith.constant 0 : i64
  %c12 = arith.constant 1 : index
  %c17 = arith.constant 10 : i64
  %c20 = arith.constant 48 : i8
  %c24 = arith.constant 71 : index
  %c26 = arith.constant 1 : i64
  %c42 = arith.constant 72 : index
  %c46 = arith.constant 8 : i64
  %c54 = arith.constant 73 : index
  %c56 = arith.constant 2 : i64
  %c72 = arith.constant 74 : index
  %c74 = arith.constant 3 : i64
  %c90 = arith.constant 75 : index
  %c92 = arith.constant 4 : i64
  %c108 = arith.constant 76 : index
  %c110 = arith.constant 5 : i64
  %c127 = arith.constant 16 : i64
  %c138 = arith.constant 6 : i64
  %c155 = arith.constant 7 : i64
  %c171 = arith.constant 77 : index
  %c188 = arith.constant 3 : index
  %di = func.call @st_desc8(%into, %cap) : (!llvm.ptr, i64) -> !d
  %mi = builtin.unrealized_conversion_cast %di : !d to !m8
  %bg = memref.get_global @st_blob : memref<2642xi8>
  %blob = trikeshed.text %bg : memref<2642xi8> -> !text
  %spg = memref.get_global @st_sp : memref<32xi8>
  %sp = trikeshed.text %spg : memref<32xi8> -> !text
  %ws1, %wl2 = func.call @st_word(%c3) : (index) -> (index, index)
  %w4 = trikeshed.slice %blob[%ws1, %wl2] : !text -> !text
  %vp6 = llvm.getelementptr %vals[%c5] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv7 = llvm.load %vp6 : !llvm.ptr -> i64
  %dc8 = func.call @st_dcount(%vv7) : (i64) -> index
  %pg9 = memref.get_global @st_pow : memref<20xi64>
  %powers10 = trikeshed.text %pg9 : memref<20xi64> -> !s64
  %digits11 = trikeshed.series %dc8 : !text {
  ^bb0(%k: index):
    %last13 = arith.subi %dc8, %c12 : index
    %e14 = arith.subi %last13, %k : index
    %p15 = trikeshed.at %powers10[%e14] : !s64, index -> i64
    %q16 = arith.divui %vv7, %p15 : i64
    %dd18 = arith.remui %q16, %c17 : i64
    %d819 = arith.trunci %dd18 : i64 to i8
    %ch21 = arith.addi %d819, %c20 : i8
    trikeshed.yield %ch21 : i8
  }
  %ws22, %wl23 = func.call @st_word(%c24) : (index) -> (index, index)
  %w25 = trikeshed.slice %blob[%ws22, %wl23] : !text -> !text
  %vp27 = llvm.getelementptr %vals[%c26] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv28 = llvm.load %vp27 : !llvm.ptr -> i64
  %dc29 = func.call @st_dcount(%vv28) : (i64) -> index
  %pg30 = memref.get_global @st_pow : memref<20xi64>
  %powers31 = trikeshed.text %pg30 : memref<20xi64> -> !s64
  %digits32 = trikeshed.series %dc29 : !text {
  ^bb0(%k: index):
    %last33 = arith.subi %dc29, %c12 : index
    %e34 = arith.subi %last33, %k : index
    %p35 = trikeshed.at %powers31[%e34] : !s64, index -> i64
    %q36 = arith.divui %vv28, %p35 : i64
    %dd37 = arith.remui %q36, %c17 : i64
    %d838 = arith.trunci %dd37 : i64 to i8
    %ch39 = arith.addi %d838, %c20 : i8
    trikeshed.yield %ch39 : i8
  }
  %ws40, %wl41 = func.call @st_word(%c42) : (index) -> (index, index)
  %w43 = trikeshed.slice %blob[%ws40, %wl41] : !text -> !text
  %wb44 = llvm.getelementptr %wins[%c5] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wp45 = llvm.load %wb44 : !llvm.ptr -> !llvm.ptr
  %wl47 = llvm.getelementptr %wb44[%c46] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wn48 = llvm.load %wl47 : !llvm.ptr -> i64
  %d49 = func.call @st_desc8(%wp45, %wn48) : (!llvm.ptr, i64) -> !d
  %m50 = builtin.unrealized_conversion_cast %d49 : !d to !m8
  %s51 = builtin.unrealized_conversion_cast %m50 : !m8 to !text
  %ws52, %wl53 = func.call @st_word(%c54) : (index) -> (index, index)
  %w55 = trikeshed.slice %blob[%ws52, %wl53] : !text -> !text
  %vp57 = llvm.getelementptr %vals[%c56] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv58 = llvm.load %vp57 : !llvm.ptr -> i64
  %dc59 = func.call @st_dcount(%vv58) : (i64) -> index
  %pg60 = memref.get_global @st_pow : memref<20xi64>
  %powers61 = trikeshed.text %pg60 : memref<20xi64> -> !s64
  %digits62 = trikeshed.series %dc59 : !text {
  ^bb0(%k: index):
    %last63 = arith.subi %dc59, %c12 : index
    %e64 = arith.subi %last63, %k : index
    %p65 = trikeshed.at %powers61[%e64] : !s64, index -> i64
    %q66 = arith.divui %vv58, %p65 : i64
    %dd67 = arith.remui %q66, %c17 : i64
    %d868 = arith.trunci %dd67 : i64 to i8
    %ch69 = arith.addi %d868, %c20 : i8
    trikeshed.yield %ch69 : i8
  }
  %ws70, %wl71 = func.call @st_word(%c72) : (index) -> (index, index)
  %w73 = trikeshed.slice %blob[%ws70, %wl71] : !text -> !text
  %vp75 = llvm.getelementptr %vals[%c74] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv76 = llvm.load %vp75 : !llvm.ptr -> i64
  %dc77 = func.call @st_dcount(%vv76) : (i64) -> index
  %pg78 = memref.get_global @st_pow : memref<20xi64>
  %powers79 = trikeshed.text %pg78 : memref<20xi64> -> !s64
  %digits80 = trikeshed.series %dc77 : !text {
  ^bb0(%k: index):
    %last81 = arith.subi %dc77, %c12 : index
    %e82 = arith.subi %last81, %k : index
    %p83 = trikeshed.at %powers79[%e82] : !s64, index -> i64
    %q84 = arith.divui %vv76, %p83 : i64
    %dd85 = arith.remui %q84, %c17 : i64
    %d886 = arith.trunci %dd85 : i64 to i8
    %ch87 = arith.addi %d886, %c20 : i8
    trikeshed.yield %ch87 : i8
  }
  %ws88, %wl89 = func.call @st_word(%c90) : (index) -> (index, index)
  %w91 = trikeshed.slice %blob[%ws88, %wl89] : !text -> !text
  %vp93 = llvm.getelementptr %vals[%c92] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv94 = llvm.load %vp93 : !llvm.ptr -> i64
  %dc95 = func.call @st_dcount(%vv94) : (i64) -> index
  %pg96 = memref.get_global @st_pow : memref<20xi64>
  %powers97 = trikeshed.text %pg96 : memref<20xi64> -> !s64
  %digits98 = trikeshed.series %dc95 : !text {
  ^bb0(%k: index):
    %last99 = arith.subi %dc95, %c12 : index
    %e100 = arith.subi %last99, %k : index
    %p101 = trikeshed.at %powers97[%e100] : !s64, index -> i64
    %q102 = arith.divui %vv94, %p101 : i64
    %dd103 = arith.remui %q102, %c17 : i64
    %d8104 = arith.trunci %dd103 : i64 to i8
    %ch105 = arith.addi %d8104, %c20 : i8
    trikeshed.yield %ch105 : i8
  }
  %ws106, %wl107 = func.call @st_word(%c108) : (index) -> (index, index)
  %w109 = trikeshed.slice %blob[%ws106, %wl107] : !text -> !text
  %vp111 = llvm.getelementptr %vals[%c110] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv112 = llvm.load %vp111 : !llvm.ptr -> i64
  %dc113 = func.call @st_dcount(%vv112) : (i64) -> index
  %pg114 = memref.get_global @st_pow : memref<20xi64>
  %powers115 = trikeshed.text %pg114 : memref<20xi64> -> !s64
  %digits116 = trikeshed.series %dc113 : !text {
  ^bb0(%k: index):
    %last117 = arith.subi %dc113, %c12 : index
    %e118 = arith.subi %last117, %k : index
    %p119 = trikeshed.at %powers115[%e118] : !s64, index -> i64
    %q120 = arith.divui %vv112, %p119 : i64
    %dd121 = arith.remui %q120, %c17 : i64
    %d8122 = arith.trunci %dd121 : i64 to i8
    %ch123 = arith.addi %d8122, %c20 : i8
    trikeshed.yield %ch123 : i8
  }
  %ws124, %wl125 = func.call @st_word(%c42) : (index) -> (index, index)
  %w126 = trikeshed.slice %blob[%ws124, %wl125] : !text -> !text
  %wb128 = llvm.getelementptr %wins[%c127] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wp129 = llvm.load %wb128 : !llvm.ptr -> !llvm.ptr
  %wl130 = llvm.getelementptr %wb128[%c46] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wn131 = llvm.load %wl130 : !llvm.ptr -> i64
  %d132 = func.call @st_desc8(%wp129, %wn131) : (!llvm.ptr, i64) -> !d
  %m133 = builtin.unrealized_conversion_cast %d132 : !d to !m8
  %s134 = builtin.unrealized_conversion_cast %m133 : !m8 to !text
  %ws135, %wl136 = func.call @st_word(%c54) : (index) -> (index, index)
  %w137 = trikeshed.slice %blob[%ws135, %wl136] : !text -> !text
  %vp139 = llvm.getelementptr %vals[%c138] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv140 = llvm.load %vp139 : !llvm.ptr -> i64
  %dc141 = func.call @st_dcount(%vv140) : (i64) -> index
  %pg142 = memref.get_global @st_pow : memref<20xi64>
  %powers143 = trikeshed.text %pg142 : memref<20xi64> -> !s64
  %digits144 = trikeshed.series %dc141 : !text {
  ^bb0(%k: index):
    %last145 = arith.subi %dc141, %c12 : index
    %e146 = arith.subi %last145, %k : index
    %p147 = trikeshed.at %powers143[%e146] : !s64, index -> i64
    %q148 = arith.divui %vv140, %p147 : i64
    %dd149 = arith.remui %q148, %c17 : i64
    %d8150 = arith.trunci %dd149 : i64 to i8
    %ch151 = arith.addi %d8150, %c20 : i8
    trikeshed.yield %ch151 : i8
  }
  %ws152, %wl153 = func.call @st_word(%c72) : (index) -> (index, index)
  %w154 = trikeshed.slice %blob[%ws152, %wl153] : !text -> !text
  %vp156 = llvm.getelementptr %vals[%c155] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv157 = llvm.load %vp156 : !llvm.ptr -> i64
  %dc158 = func.call @st_dcount(%vv157) : (i64) -> index
  %pg159 = memref.get_global @st_pow : memref<20xi64>
  %powers160 = trikeshed.text %pg159 : memref<20xi64> -> !s64
  %digits161 = trikeshed.series %dc158 : !text {
  ^bb0(%k: index):
    %last162 = arith.subi %dc158, %c12 : index
    %e163 = arith.subi %last162, %k : index
    %p164 = trikeshed.at %powers160[%e163] : !s64, index -> i64
    %q165 = arith.divui %vv157, %p164 : i64
    %dd166 = arith.remui %q165, %c17 : i64
    %d8167 = arith.trunci %dd166 : i64 to i8
    %ch168 = arith.addi %d8167, %c20 : i8
    trikeshed.yield %ch168 : i8
  }
  %ws169, %wl170 = func.call @st_word(%c171) : (index) -> (index, index)
  %w172 = trikeshed.slice %blob[%ws169, %wl170] : !text -> !text
  %vp173 = llvm.getelementptr %vals[%c92] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv174 = llvm.load %vp173 : !llvm.ptr -> i64
  %dc175 = func.call @st_dcount(%vv174) : (i64) -> index
  %pg176 = memref.get_global @st_pow : memref<20xi64>
  %powers177 = trikeshed.text %pg176 : memref<20xi64> -> !s64
  %digits178 = trikeshed.series %dc175 : !text {
  ^bb0(%k: index):
    %last179 = arith.subi %dc175, %c12 : index
    %e180 = arith.subi %last179, %k : index
    %p181 = trikeshed.at %powers177[%e180] : !s64, index -> i64
    %q182 = arith.divui %vv174, %p181 : i64
    %dd183 = arith.remui %q182, %c17 : i64
    %d8184 = arith.trunci %dd183 : i64 to i8
    %ch185 = arith.addi %d8184, %c20 : i8
    trikeshed.yield %ch185 : i8
  }
  %ws186, %wl187 = func.call @st_word(%c188) : (index) -> (index, index)
  %w189 = trikeshed.slice %blob[%ws186, %wl187] : !text -> !text
  %whole190 = trikeshed.combine %w4, %digits11, %w25, %digits32, %w43, %s51, %w55, %digits62, %w73, %digits80, %w91, %digits98, %w109, %digits116, %w126, %s134, %w137, %digits144, %w154, %digits161, %w172, %digits178, %w189 : !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text -> !text
  %sz = trikeshed.size %whole190 : !text
  %szi = arith.index_cast %sz : index to i64
  %capi = arith.index_cast %cap : i64 to index
  %fits = arith.cmpi ule, %sz, %capi : index
  scf.if %fits {
    %end = trikeshed.drain %whole190, %mi : !text, !m8 -> index
  }
  return %szi : i64
}

func.func private @st_l_18(%vals: !llvm.ptr, %wins: !llvm.ptr, %rows: !llvm.ptr, %nrows: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %c3 = arith.constant 78 : index
  %c5 = arith.constant 0 : i64
  %c12 = arith.constant 1 : index
  %c17 = arith.constant 10 : i64
  %c20 = arith.constant 48 : i8
  %c24 = arith.constant 79 : index
  %c26 = arith.constant 1 : i64
  %c42 = arith.constant 80 : index
  %c44 = arith.constant 2 : i64
  %c60 = arith.constant 81 : index
  %di = func.call @st_desc8(%into, %cap) : (!llvm.ptr, i64) -> !d
  %mi = builtin.unrealized_conversion_cast %di : !d to !m8
  %bg = memref.get_global @st_blob : memref<2642xi8>
  %blob = trikeshed.text %bg : memref<2642xi8> -> !text
  %spg = memref.get_global @st_sp : memref<32xi8>
  %sp = trikeshed.text %spg : memref<32xi8> -> !text
  %ws1, %wl2 = func.call @st_word(%c3) : (index) -> (index, index)
  %w4 = trikeshed.slice %blob[%ws1, %wl2] : !text -> !text
  %vp6 = llvm.getelementptr %vals[%c5] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv7 = llvm.load %vp6 : !llvm.ptr -> i64
  %dc8 = func.call @st_dcount(%vv7) : (i64) -> index
  %pg9 = memref.get_global @st_pow : memref<20xi64>
  %powers10 = trikeshed.text %pg9 : memref<20xi64> -> !s64
  %digits11 = trikeshed.series %dc8 : !text {
  ^bb0(%k: index):
    %last13 = arith.subi %dc8, %c12 : index
    %e14 = arith.subi %last13, %k : index
    %p15 = trikeshed.at %powers10[%e14] : !s64, index -> i64
    %q16 = arith.divui %vv7, %p15 : i64
    %dd18 = arith.remui %q16, %c17 : i64
    %d819 = arith.trunci %dd18 : i64 to i8
    %ch21 = arith.addi %d819, %c20 : i8
    trikeshed.yield %ch21 : i8
  }
  %ws22, %wl23 = func.call @st_word(%c24) : (index) -> (index, index)
  %w25 = trikeshed.slice %blob[%ws22, %wl23] : !text -> !text
  %vp27 = llvm.getelementptr %vals[%c26] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv28 = llvm.load %vp27 : !llvm.ptr -> i64
  %dc29 = func.call @st_dcount(%vv28) : (i64) -> index
  %pg30 = memref.get_global @st_pow : memref<20xi64>
  %powers31 = trikeshed.text %pg30 : memref<20xi64> -> !s64
  %digits32 = trikeshed.series %dc29 : !text {
  ^bb0(%k: index):
    %last33 = arith.subi %dc29, %c12 : index
    %e34 = arith.subi %last33, %k : index
    %p35 = trikeshed.at %powers31[%e34] : !s64, index -> i64
    %q36 = arith.divui %vv28, %p35 : i64
    %dd37 = arith.remui %q36, %c17 : i64
    %d838 = arith.trunci %dd37 : i64 to i8
    %ch39 = arith.addi %d838, %c20 : i8
    trikeshed.yield %ch39 : i8
  }
  %ws40, %wl41 = func.call @st_word(%c42) : (index) -> (index, index)
  %w43 = trikeshed.slice %blob[%ws40, %wl41] : !text -> !text
  %vp45 = llvm.getelementptr %vals[%c44] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv46 = llvm.load %vp45 : !llvm.ptr -> i64
  %dc47 = func.call @st_dcount(%vv46) : (i64) -> index
  %pg48 = memref.get_global @st_pow : memref<20xi64>
  %powers49 = trikeshed.text %pg48 : memref<20xi64> -> !s64
  %digits50 = trikeshed.series %dc47 : !text {
  ^bb0(%k: index):
    %last51 = arith.subi %dc47, %c12 : index
    %e52 = arith.subi %last51, %k : index
    %p53 = trikeshed.at %powers49[%e52] : !s64, index -> i64
    %q54 = arith.divui %vv46, %p53 : i64
    %dd55 = arith.remui %q54, %c17 : i64
    %d856 = arith.trunci %dd55 : i64 to i8
    %ch57 = arith.addi %d856, %c20 : i8
    trikeshed.yield %ch57 : i8
  }
  %ws58, %wl59 = func.call @st_word(%c60) : (index) -> (index, index)
  %w61 = trikeshed.slice %blob[%ws58, %wl59] : !text -> !text
  %whole62 = trikeshed.combine %w4, %digits11, %w25, %digits32, %w43, %digits50, %w61 : !text, !text, !text, !text, !text, !text, !text -> !text
  %sz = trikeshed.size %whole62 : !text
  %szi = arith.index_cast %sz : index to i64
  %capi = arith.index_cast %cap : i64 to index
  %fits = arith.cmpi ule, %sz, %capi : index
  scf.if %fits {
    %end = trikeshed.drain %whole62, %mi : !text, !m8 -> index
  }
  return %szi : i64
}

func.func private @st_l_19(%vals: !llvm.ptr, %wins: !llvm.ptr, %rows: !llvm.ptr, %nrows: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %c3 = arith.constant 82 : index
  %c5 = arith.constant 0 : i64
  %c12 = arith.constant 1 : index
  %c17 = arith.constant 10 : i64
  %c20 = arith.constant 48 : i8
  %c24 = arith.constant 83 : index
  %c26 = arith.constant 1 : i64
  %c42 = arith.constant 84 : index
  %di = func.call @st_desc8(%into, %cap) : (!llvm.ptr, i64) -> !d
  %mi = builtin.unrealized_conversion_cast %di : !d to !m8
  %bg = memref.get_global @st_blob : memref<2642xi8>
  %blob = trikeshed.text %bg : memref<2642xi8> -> !text
  %spg = memref.get_global @st_sp : memref<32xi8>
  %sp = trikeshed.text %spg : memref<32xi8> -> !text
  %ws1, %wl2 = func.call @st_word(%c3) : (index) -> (index, index)
  %w4 = trikeshed.slice %blob[%ws1, %wl2] : !text -> !text
  %vp6 = llvm.getelementptr %vals[%c5] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv7 = llvm.load %vp6 : !llvm.ptr -> i64
  %dc8 = func.call @st_dcount(%vv7) : (i64) -> index
  %pg9 = memref.get_global @st_pow : memref<20xi64>
  %powers10 = trikeshed.text %pg9 : memref<20xi64> -> !s64
  %digits11 = trikeshed.series %dc8 : !text {
  ^bb0(%k: index):
    %last13 = arith.subi %dc8, %c12 : index
    %e14 = arith.subi %last13, %k : index
    %p15 = trikeshed.at %powers10[%e14] : !s64, index -> i64
    %q16 = arith.divui %vv7, %p15 : i64
    %dd18 = arith.remui %q16, %c17 : i64
    %d819 = arith.trunci %dd18 : i64 to i8
    %ch21 = arith.addi %d819, %c20 : i8
    trikeshed.yield %ch21 : i8
  }
  %ws22, %wl23 = func.call @st_word(%c24) : (index) -> (index, index)
  %w25 = trikeshed.slice %blob[%ws22, %wl23] : !text -> !text
  %vp27 = llvm.getelementptr %vals[%c26] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv28 = llvm.load %vp27 : !llvm.ptr -> i64
  %dc29 = func.call @st_dcount(%vv28) : (i64) -> index
  %pg30 = memref.get_global @st_pow : memref<20xi64>
  %powers31 = trikeshed.text %pg30 : memref<20xi64> -> !s64
  %digits32 = trikeshed.series %dc29 : !text {
  ^bb0(%k: index):
    %last33 = arith.subi %dc29, %c12 : index
    %e34 = arith.subi %last33, %k : index
    %p35 = trikeshed.at %powers31[%e34] : !s64, index -> i64
    %q36 = arith.divui %vv28, %p35 : i64
    %dd37 = arith.remui %q36, %c17 : i64
    %d838 = arith.trunci %dd37 : i64 to i8
    %ch39 = arith.addi %d838, %c20 : i8
    trikeshed.yield %ch39 : i8
  }
  %ws40, %wl41 = func.call @st_word(%c42) : (index) -> (index, index)
  %w43 = trikeshed.slice %blob[%ws40, %wl41] : !text -> !text
  %whole44 = trikeshed.combine %w4, %digits11, %w25, %digits32, %w43 : !text, !text, !text, !text, !text -> !text
  %sz = trikeshed.size %whole44 : !text
  %szi = arith.index_cast %sz : index to i64
  %capi = arith.index_cast %cap : i64 to index
  %fits = arith.cmpi ule, %sz, %capi : index
  scf.if %fits {
    %end = trikeshed.drain %whole44, %mi : !text, !m8 -> index
  }
  return %szi : i64
}

func.func private @st_l_20(%vals: !llvm.ptr, %wins: !llvm.ptr, %rows: !llvm.ptr, %nrows: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %c3 = arith.constant 85 : index
  %c5 = arith.constant 0 : i64
  %c12 = arith.constant 1 : index
  %c17 = arith.constant 10 : i64
  %c20 = arith.constant 48 : i8
  %c24 = arith.constant 86 : index
  %c29 = arith.constant 64 : i64
  %c35 = arith.constant 8 : i64
  %c38 = arith.constant 16 : i64
  %c41 = arith.constant 24 : i64
  %c44 = arith.constant 32 : i64
  %c47 = arith.constant 40 : i64
  %c50 = arith.constant 48 : i64
  %c55 = arith.constant 110 : index
  %c60 = arith.constant 26 : index
  %c63 = arith.constant 0 : index
  %c79 = arith.constant 12 : index
  %c88 = arith.constant 7 : index
  %c97 = arith.constant 113 : index
  %c101 = arith.constant 3 : index
  %di = func.call @st_desc8(%into, %cap) : (!llvm.ptr, i64) -> !d
  %mi = builtin.unrealized_conversion_cast %di : !d to !m8
  %bg = memref.get_global @st_blob : memref<2642xi8>
  %blob = trikeshed.text %bg : memref<2642xi8> -> !text
  %spg = memref.get_global @st_sp : memref<32xi8>
  %sp = trikeshed.text %spg : memref<32xi8> -> !text
  %ws1, %wl2 = func.call @st_word(%c3) : (index) -> (index, index)
  %w4 = trikeshed.slice %blob[%ws1, %wl2] : !text -> !text
  %vp6 = llvm.getelementptr %vals[%c5] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv7 = llvm.load %vp6 : !llvm.ptr -> i64
  %dc8 = func.call @st_dcount(%vv7) : (i64) -> index
  %pg9 = memref.get_global @st_pow : memref<20xi64>
  %powers10 = trikeshed.text %pg9 : memref<20xi64> -> !s64
  %digits11 = trikeshed.series %dc8 : !text {
  ^bb0(%k: index):
    %last13 = arith.subi %dc8, %c12 : index
    %e14 = arith.subi %last13, %k : index
    %p15 = trikeshed.at %powers10[%e14] : !s64, index -> i64
    %q16 = arith.divui %vv7, %p15 : i64
    %dd18 = arith.remui %q16, %c17 : i64
    %d819 = arith.trunci %dd18 : i64 to i8
    %ch21 = arith.addi %d819, %c20 : i8
    trikeshed.yield %ch21 : i8
  }
  %ws22, %wl23 = func.call @st_word(%c24) : (index) -> (index, index)
  %w25 = trikeshed.slice %blob[%ws22, %wl23] : !text -> !text
  %ni26 = arith.index_cast %nrows : i64 to index
  %rows27, %rco28 = trikeshed.combineAll %ni26 : !text, !coords {
  ^bb0(%j: index):
  %j6430 = arith.index_cast %j : index to i64
  %ro31 = arith.muli %j6430, %c29 : i64
  %rb32 = llvm.getelementptr %rows[%ro31] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fp33 = llvm.getelementptr %rb32[%c5] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fv34 = llvm.load %fp33 : !llvm.ptr -> !llvm.ptr
  %fp36 = llvm.getelementptr %rb32[%c35] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fv37 = llvm.load %fp36 : !llvm.ptr -> i64
  %fp39 = llvm.getelementptr %rb32[%c38] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fv40 = llvm.load %fp39 : !llvm.ptr -> i64
  %fp42 = llvm.getelementptr %rb32[%c41] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fv43 = llvm.load %fp42 : !llvm.ptr -> i64
  %fp45 = llvm.getelementptr %rb32[%c44] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fv46 = llvm.load %fp45 : !llvm.ptr -> i64
  %fp48 = llvm.getelementptr %rb32[%c47] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fv49 = llvm.load %fp48 : !llvm.ptr -> !llvm.ptr
  %fp51 = llvm.getelementptr %rb32[%c50] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fv52 = llvm.load %fp51 : !llvm.ptr -> i64
  %ws53, %wl54 = func.call @st_word(%c55) : (index) -> (index, index)
  %w56 = trikeshed.slice %blob[%ws53, %wl54] : !text -> !text
  %d57 = func.call @st_desc8(%fv34, %fv37) : (!llvm.ptr, i64) -> !d
  %m58 = builtin.unrealized_conversion_cast %d57 : !d to !m8
  %s59 = builtin.unrealized_conversion_cast %m58 : !m8 to !text
  %li61 = arith.index_cast %fv37 : i64 to index
  %sub62 = arith.subi %c60, %li61 : index
  %ge64 = arith.cmpi sge, %sub62, %c63 : index
  %n65 = arith.select %ge64, %sub62, %c63 : index
  %sp66 = trikeshed.slice %sp[%c63, %n65] : !text -> !text
  %pl67 = trikeshed.combine %s59, %sp66 : !text, !text -> !text
  %dc68 = func.call @st_dcount(%fv40) : (i64) -> index
  %pg69 = memref.get_global @st_pow : memref<20xi64>
  %powers70 = trikeshed.text %pg69 : memref<20xi64> -> !s64
  %digits71 = trikeshed.series %dc68 : !text {
  ^bb0(%k: index):
    %last72 = arith.subi %dc68, %c12 : index
    %e73 = arith.subi %last72, %k : index
    %p74 = trikeshed.at %powers70[%e73] : !s64, index -> i64
    %q75 = arith.divui %fv40, %p74 : i64
    %dd76 = arith.remui %q75, %c17 : i64
    %d877 = arith.trunci %dd76 : i64 to i8
    %ch78 = arith.addi %d877, %c20 : i8
    trikeshed.yield %ch78 : i8
  }
  %sub80 = arith.subi %c79, %dc68 : index
  %ge81 = arith.cmpi sge, %sub80, %c63 : index
  %n82 = arith.select %ge81, %sub80, %c63 : index
  %sp83 = trikeshed.slice %sp[%c63, %n82] : !text -> !text
  %pr84 = trikeshed.combine %sp83, %digits71 : !text, !text -> !text
  %d85 = func.call @st_desc8(%fv49, %fv52) : (!llvm.ptr, i64) -> !d
  %m86 = builtin.unrealized_conversion_cast %d85 : !d to !m8
  %s87 = builtin.unrealized_conversion_cast %m86 : !m8 to !text
  %li89 = arith.index_cast %fv52 : i64 to index
  %sub90 = arith.subi %c88, %li89 : index
  %ge91 = arith.cmpi sge, %sub90, %c63 : index
  %n92 = arith.select %ge91, %sub90, %c63 : index
  %sp93 = trikeshed.slice %sp[%c63, %n92] : !text -> !text
  %pr94 = trikeshed.combine %sp93, %s87 : !text, !text -> !text
  %ws95, %wl96 = func.call @st_word(%c97) : (index) -> (index, index)
  %w98 = trikeshed.slice %blob[%ws95, %wl96] : !text -> !text
  %ws99, %wl100 = func.call @st_word(%c101) : (index) -> (index, index)
  %w102 = trikeshed.slice %blob[%ws99, %wl100] : !text -> !text
  %row103 = trikeshed.combine %w56, %pl67, %pr84, %pr94, %w98, %w102 : !text, !text, !text, !text, !text, !text -> !text
    trikeshed.yield %row103 : !text
  }
  %whole104 = trikeshed.combine %w4, %digits11, %w25, %rows27 : !text, !text, !text, !text -> !text
  %sz = trikeshed.size %whole104 : !text
  %szi = arith.index_cast %sz : index to i64
  %capi = arith.index_cast %cap : i64 to index
  %fits = arith.cmpi ule, %sz, %capi : index
  scf.if %fits {
    %end = trikeshed.drain %whole104, %mi : !text, !m8 -> index
  }
  return %szi : i64
}

func.func private @st_l_21(%vals: !llvm.ptr, %wins: !llvm.ptr, %rows: !llvm.ptr, %nrows: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %c3 = arith.constant 87 : index
  %c5 = arith.constant 0 : i64
  %c12 = arith.constant 1 : index
  %c17 = arith.constant 10 : i64
  %c20 = arith.constant 48 : i8
  %c24 = arith.constant 3 : index
  %di = func.call @st_desc8(%into, %cap) : (!llvm.ptr, i64) -> !d
  %mi = builtin.unrealized_conversion_cast %di : !d to !m8
  %bg = memref.get_global @st_blob : memref<2642xi8>
  %blob = trikeshed.text %bg : memref<2642xi8> -> !text
  %spg = memref.get_global @st_sp : memref<32xi8>
  %sp = trikeshed.text %spg : memref<32xi8> -> !text
  %ws1, %wl2 = func.call @st_word(%c3) : (index) -> (index, index)
  %w4 = trikeshed.slice %blob[%ws1, %wl2] : !text -> !text
  %vp6 = llvm.getelementptr %vals[%c5] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv7 = llvm.load %vp6 : !llvm.ptr -> i64
  %dc8 = func.call @st_dcount(%vv7) : (i64) -> index
  %pg9 = memref.get_global @st_pow : memref<20xi64>
  %powers10 = trikeshed.text %pg9 : memref<20xi64> -> !s64
  %digits11 = trikeshed.series %dc8 : !text {
  ^bb0(%k: index):
    %last13 = arith.subi %dc8, %c12 : index
    %e14 = arith.subi %last13, %k : index
    %p15 = trikeshed.at %powers10[%e14] : !s64, index -> i64
    %q16 = arith.divui %vv7, %p15 : i64
    %dd18 = arith.remui %q16, %c17 : i64
    %d819 = arith.trunci %dd18 : i64 to i8
    %ch21 = arith.addi %d819, %c20 : i8
    trikeshed.yield %ch21 : i8
  }
  %ws22, %wl23 = func.call @st_word(%c24) : (index) -> (index, index)
  %w25 = trikeshed.slice %blob[%ws22, %wl23] : !text -> !text
  %whole26 = trikeshed.combine %w4, %digits11, %w25 : !text, !text, !text -> !text
  %sz = trikeshed.size %whole26 : !text
  %szi = arith.index_cast %sz : index to i64
  %capi = arith.index_cast %cap : i64 to index
  %fits = arith.cmpi ule, %sz, %capi : index
  scf.if %fits {
    %end = trikeshed.drain %whole26, %mi : !text, !m8 -> index
  }
  return %szi : i64
}

func.func private @st_l_22(%vals: !llvm.ptr, %wins: !llvm.ptr, %rows: !llvm.ptr, %nrows: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %c3 = arith.constant 88 : index
  %c5 = arith.constant 0 : i64
  %c12 = arith.constant 1 : index
  %c17 = arith.constant 10 : i64
  %c20 = arith.constant 48 : i8
  %c24 = arith.constant 89 : index
  %c26 = arith.constant 1 : i64
  %c42 = arith.constant 90 : index
  %di = func.call @st_desc8(%into, %cap) : (!llvm.ptr, i64) -> !d
  %mi = builtin.unrealized_conversion_cast %di : !d to !m8
  %bg = memref.get_global @st_blob : memref<2642xi8>
  %blob = trikeshed.text %bg : memref<2642xi8> -> !text
  %spg = memref.get_global @st_sp : memref<32xi8>
  %sp = trikeshed.text %spg : memref<32xi8> -> !text
  %ws1, %wl2 = func.call @st_word(%c3) : (index) -> (index, index)
  %w4 = trikeshed.slice %blob[%ws1, %wl2] : !text -> !text
  %vp6 = llvm.getelementptr %vals[%c5] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv7 = llvm.load %vp6 : !llvm.ptr -> i64
  %dc8 = func.call @st_dcount(%vv7) : (i64) -> index
  %pg9 = memref.get_global @st_pow : memref<20xi64>
  %powers10 = trikeshed.text %pg9 : memref<20xi64> -> !s64
  %digits11 = trikeshed.series %dc8 : !text {
  ^bb0(%k: index):
    %last13 = arith.subi %dc8, %c12 : index
    %e14 = arith.subi %last13, %k : index
    %p15 = trikeshed.at %powers10[%e14] : !s64, index -> i64
    %q16 = arith.divui %vv7, %p15 : i64
    %dd18 = arith.remui %q16, %c17 : i64
    %d819 = arith.trunci %dd18 : i64 to i8
    %ch21 = arith.addi %d819, %c20 : i8
    trikeshed.yield %ch21 : i8
  }
  %ws22, %wl23 = func.call @st_word(%c24) : (index) -> (index, index)
  %w25 = trikeshed.slice %blob[%ws22, %wl23] : !text -> !text
  %vp27 = llvm.getelementptr %vals[%c26] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv28 = llvm.load %vp27 : !llvm.ptr -> i64
  %dc29 = func.call @st_dcount(%vv28) : (i64) -> index
  %pg30 = memref.get_global @st_pow : memref<20xi64>
  %powers31 = trikeshed.text %pg30 : memref<20xi64> -> !s64
  %digits32 = trikeshed.series %dc29 : !text {
  ^bb0(%k: index):
    %last33 = arith.subi %dc29, %c12 : index
    %e34 = arith.subi %last33, %k : index
    %p35 = trikeshed.at %powers31[%e34] : !s64, index -> i64
    %q36 = arith.divui %vv28, %p35 : i64
    %dd37 = arith.remui %q36, %c17 : i64
    %d838 = arith.trunci %dd37 : i64 to i8
    %ch39 = arith.addi %d838, %c20 : i8
    trikeshed.yield %ch39 : i8
  }
  %ws40, %wl41 = func.call @st_word(%c42) : (index) -> (index, index)
  %w43 = trikeshed.slice %blob[%ws40, %wl41] : !text -> !text
  %whole44 = trikeshed.combine %w4, %digits11, %w25, %digits32, %w43 : !text, !text, !text, !text, !text -> !text
  %sz = trikeshed.size %whole44 : !text
  %szi = arith.index_cast %sz : index to i64
  %capi = arith.index_cast %cap : i64 to index
  %fits = arith.cmpi ule, %sz, %capi : index
  scf.if %fits {
    %end = trikeshed.drain %whole44, %mi : !text, !m8 -> index
  }
  return %szi : i64
}

func.func private @st_l_23(%vals: !llvm.ptr, %wins: !llvm.ptr, %rows: !llvm.ptr, %nrows: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %c3 = arith.constant 91 : index
  %c5 = arith.constant 0 : i64
  %c8 = arith.constant 8 : i64
  %c16 = arith.constant 92 : index
  %c18 = arith.constant 16 : i64
  %c28 = arith.constant 93 : index
  %di = func.call @st_desc8(%into, %cap) : (!llvm.ptr, i64) -> !d
  %mi = builtin.unrealized_conversion_cast %di : !d to !m8
  %bg = memref.get_global @st_blob : memref<2642xi8>
  %blob = trikeshed.text %bg : memref<2642xi8> -> !text
  %spg = memref.get_global @st_sp : memref<32xi8>
  %sp = trikeshed.text %spg : memref<32xi8> -> !text
  %ws1, %wl2 = func.call @st_word(%c3) : (index) -> (index, index)
  %w4 = trikeshed.slice %blob[%ws1, %wl2] : !text -> !text
  %wb6 = llvm.getelementptr %wins[%c5] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wp7 = llvm.load %wb6 : !llvm.ptr -> !llvm.ptr
  %wl9 = llvm.getelementptr %wb6[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wn10 = llvm.load %wl9 : !llvm.ptr -> i64
  %d11 = func.call @st_desc8(%wp7, %wn10) : (!llvm.ptr, i64) -> !d
  %m12 = builtin.unrealized_conversion_cast %d11 : !d to !m8
  %s13 = builtin.unrealized_conversion_cast %m12 : !m8 to !text
  %ws14, %wl15 = func.call @st_word(%c16) : (index) -> (index, index)
  %w17 = trikeshed.slice %blob[%ws14, %wl15] : !text -> !text
  %wb19 = llvm.getelementptr %wins[%c18] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wp20 = llvm.load %wb19 : !llvm.ptr -> !llvm.ptr
  %wl21 = llvm.getelementptr %wb19[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wn22 = llvm.load %wl21 : !llvm.ptr -> i64
  %d23 = func.call @st_desc8(%wp20, %wn22) : (!llvm.ptr, i64) -> !d
  %m24 = builtin.unrealized_conversion_cast %d23 : !d to !m8
  %s25 = builtin.unrealized_conversion_cast %m24 : !m8 to !text
  %ws26, %wl27 = func.call @st_word(%c28) : (index) -> (index, index)
  %w29 = trikeshed.slice %blob[%ws26, %wl27] : !text -> !text
  %whole30 = trikeshed.combine %w4, %s13, %w17, %s25, %w29 : !text, !text, !text, !text, !text -> !text
  %sz = trikeshed.size %whole30 : !text
  %szi = arith.index_cast %sz : index to i64
  %capi = arith.index_cast %cap : i64 to index
  %fits = arith.cmpi ule, %sz, %capi : index
  scf.if %fits {
    %end = trikeshed.drain %whole30, %mi : !text, !m8 -> index
  }
  return %szi : i64
}

func.func private @st_l_24(%vals: !llvm.ptr, %wins: !llvm.ptr, %rows: !llvm.ptr, %nrows: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %c3 = arith.constant 94 : index
  %c5 = arith.constant 0 : i64
  %c12 = arith.constant 1 : index
  %c17 = arith.constant 10 : i64
  %c20 = arith.constant 48 : i8
  %c24 = arith.constant 95 : index
  %c26 = arith.constant 1 : i64
  %c42 = arith.constant 96 : index
  %c44 = arith.constant 2 : i64
  %c60 = arith.constant 97 : index
  %di = func.call @st_desc8(%into, %cap) : (!llvm.ptr, i64) -> !d
  %mi = builtin.unrealized_conversion_cast %di : !d to !m8
  %bg = memref.get_global @st_blob : memref<2642xi8>
  %blob = trikeshed.text %bg : memref<2642xi8> -> !text
  %spg = memref.get_global @st_sp : memref<32xi8>
  %sp = trikeshed.text %spg : memref<32xi8> -> !text
  %ws1, %wl2 = func.call @st_word(%c3) : (index) -> (index, index)
  %w4 = trikeshed.slice %blob[%ws1, %wl2] : !text -> !text
  %vp6 = llvm.getelementptr %vals[%c5] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv7 = llvm.load %vp6 : !llvm.ptr -> i64
  %dc8 = func.call @st_dcount(%vv7) : (i64) -> index
  %pg9 = memref.get_global @st_pow : memref<20xi64>
  %powers10 = trikeshed.text %pg9 : memref<20xi64> -> !s64
  %digits11 = trikeshed.series %dc8 : !text {
  ^bb0(%k: index):
    %last13 = arith.subi %dc8, %c12 : index
    %e14 = arith.subi %last13, %k : index
    %p15 = trikeshed.at %powers10[%e14] : !s64, index -> i64
    %q16 = arith.divui %vv7, %p15 : i64
    %dd18 = arith.remui %q16, %c17 : i64
    %d819 = arith.trunci %dd18 : i64 to i8
    %ch21 = arith.addi %d819, %c20 : i8
    trikeshed.yield %ch21 : i8
  }
  %ws22, %wl23 = func.call @st_word(%c24) : (index) -> (index, index)
  %w25 = trikeshed.slice %blob[%ws22, %wl23] : !text -> !text
  %vp27 = llvm.getelementptr %vals[%c26] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv28 = llvm.load %vp27 : !llvm.ptr -> i64
  %dc29 = func.call @st_dcount(%vv28) : (i64) -> index
  %pg30 = memref.get_global @st_pow : memref<20xi64>
  %powers31 = trikeshed.text %pg30 : memref<20xi64> -> !s64
  %digits32 = trikeshed.series %dc29 : !text {
  ^bb0(%k: index):
    %last33 = arith.subi %dc29, %c12 : index
    %e34 = arith.subi %last33, %k : index
    %p35 = trikeshed.at %powers31[%e34] : !s64, index -> i64
    %q36 = arith.divui %vv28, %p35 : i64
    %dd37 = arith.remui %q36, %c17 : i64
    %d838 = arith.trunci %dd37 : i64 to i8
    %ch39 = arith.addi %d838, %c20 : i8
    trikeshed.yield %ch39 : i8
  }
  %ws40, %wl41 = func.call @st_word(%c42) : (index) -> (index, index)
  %w43 = trikeshed.slice %blob[%ws40, %wl41] : !text -> !text
  %vp45 = llvm.getelementptr %vals[%c44] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv46 = llvm.load %vp45 : !llvm.ptr -> i64
  %dc47 = func.call @st_dcount(%vv46) : (i64) -> index
  %pg48 = memref.get_global @st_pow : memref<20xi64>
  %powers49 = trikeshed.text %pg48 : memref<20xi64> -> !s64
  %digits50 = trikeshed.series %dc47 : !text {
  ^bb0(%k: index):
    %last51 = arith.subi %dc47, %c12 : index
    %e52 = arith.subi %last51, %k : index
    %p53 = trikeshed.at %powers49[%e52] : !s64, index -> i64
    %q54 = arith.divui %vv46, %p53 : i64
    %dd55 = arith.remui %q54, %c17 : i64
    %d856 = arith.trunci %dd55 : i64 to i8
    %ch57 = arith.addi %d856, %c20 : i8
    trikeshed.yield %ch57 : i8
  }
  %ws58, %wl59 = func.call @st_word(%c60) : (index) -> (index, index)
  %w61 = trikeshed.slice %blob[%ws58, %wl59] : !text -> !text
  %whole62 = trikeshed.combine %w4, %digits11, %w25, %digits32, %w43, %digits50, %w61 : !text, !text, !text, !text, !text, !text, !text -> !text
  %sz = trikeshed.size %whole62 : !text
  %szi = arith.index_cast %sz : index to i64
  %capi = arith.index_cast %cap : i64 to index
  %fits = arith.cmpi ule, %sz, %capi : index
  scf.if %fits {
    %end = trikeshed.drain %whole62, %mi : !text, !m8 -> index
  }
  return %szi : i64
}

func.func private @st_l_25(%vals: !llvm.ptr, %wins: !llvm.ptr, %rows: !llvm.ptr, %nrows: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %c3 = arith.constant 98 : index
  %c5 = arith.constant 0 : i64
  %c12 = arith.constant 1 : index
  %c17 = arith.constant 10 : i64
  %c20 = arith.constant 48 : i8
  %c24 = arith.constant 99 : index
  %c26 = arith.constant 4 : i64
  %c32 = arith.constant 0 : index
  %c35 = arith.constant 100 : index
  %c40 = arith.constant 16 : i64
  %c44 = arith.constant 8 : i64
  %c52 = arith.constant 101 : index
  %c54 = arith.constant 1 : i64
  %c70 = arith.constant 102 : index
  %c72 = arith.constant 2 : i64
  %c88 = arith.constant 103 : index
  %c90 = arith.constant 3 : i64
  %c106 = arith.constant 104 : index
  %di = func.call @st_desc8(%into, %cap) : (!llvm.ptr, i64) -> !d
  %mi = builtin.unrealized_conversion_cast %di : !d to !m8
  %bg = memref.get_global @st_blob : memref<2642xi8>
  %blob = trikeshed.text %bg : memref<2642xi8> -> !text
  %spg = memref.get_global @st_sp : memref<32xi8>
  %sp = trikeshed.text %spg : memref<32xi8> -> !text
  %ws1, %wl2 = func.call @st_word(%c3) : (index) -> (index, index)
  %w4 = trikeshed.slice %blob[%ws1, %wl2] : !text -> !text
  %vp6 = llvm.getelementptr %vals[%c5] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv7 = llvm.load %vp6 : !llvm.ptr -> i64
  %dc8 = func.call @st_dcount(%vv7) : (i64) -> index
  %pg9 = memref.get_global @st_pow : memref<20xi64>
  %powers10 = trikeshed.text %pg9 : memref<20xi64> -> !s64
  %digits11 = trikeshed.series %dc8 : !text {
  ^bb0(%k: index):
    %last13 = arith.subi %dc8, %c12 : index
    %e14 = arith.subi %last13, %k : index
    %p15 = trikeshed.at %powers10[%e14] : !s64, index -> i64
    %q16 = arith.divui %vv7, %p15 : i64
    %dd18 = arith.remui %q16, %c17 : i64
    %d819 = arith.trunci %dd18 : i64 to i8
    %ch21 = arith.addi %d819, %c20 : i8
    trikeshed.yield %ch21 : i8
  }
  %ws22, %wl23 = func.call @st_word(%c24) : (index) -> (index, index)
  %w25 = trikeshed.slice %blob[%ws22, %wl23] : !text -> !text
  %vp27 = llvm.getelementptr %vals[%c26] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv28 = llvm.load %vp27 : !llvm.ptr -> i64
  %ni29 = arith.index_cast %vv28 : i64 to index
  %join30, %jco31 = trikeshed.combineAll %ni29 : !text, !coords {
  ^bb0(%j: index):
    %isz33 = arith.cmpi eq, %j, %c32 : index
    %sl34:2 = func.call @st_word(%c35) : (index) -> (index, index)
    %seplen36 = arith.select %isz33, %c32, %sl34#1 : index
    %gated37 = trikeshed.slice %blob[%sl34#0, %seplen36] : !text -> !text
    %j6438 = arith.index_cast %j : index to i64
    %jo39 = arith.muli %j6438, %c40 : i64
    %jb41 = llvm.getelementptr %wins[%jo39] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %wp42 = llvm.load %jb41 : !llvm.ptr -> !llvm.ptr
    %lp43 = llvm.getelementptr %jb41[%c44] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %wl45 = llvm.load %lp43 : !llvm.ptr -> i64
  %d46 = func.call @st_desc8(%wp42, %wl45) : (!llvm.ptr, i64) -> !d
  %m47 = builtin.unrealized_conversion_cast %d46 : !d to !m8
  %s48 = builtin.unrealized_conversion_cast %m47 : !m8 to !text
    %jv49 = trikeshed.combine %gated37, %s48 : !text, !text -> !text
    trikeshed.yield %jv49 : !text
  }
  %ws50, %wl51 = func.call @st_word(%c52) : (index) -> (index, index)
  %w53 = trikeshed.slice %blob[%ws50, %wl51] : !text -> !text
  %vp55 = llvm.getelementptr %vals[%c54] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv56 = llvm.load %vp55 : !llvm.ptr -> i64
  %dc57 = func.call @st_dcount(%vv56) : (i64) -> index
  %pg58 = memref.get_global @st_pow : memref<20xi64>
  %powers59 = trikeshed.text %pg58 : memref<20xi64> -> !s64
  %digits60 = trikeshed.series %dc57 : !text {
  ^bb0(%k: index):
    %last61 = arith.subi %dc57, %c12 : index
    %e62 = arith.subi %last61, %k : index
    %p63 = trikeshed.at %powers59[%e62] : !s64, index -> i64
    %q64 = arith.divui %vv56, %p63 : i64
    %dd65 = arith.remui %q64, %c17 : i64
    %d866 = arith.trunci %dd65 : i64 to i8
    %ch67 = arith.addi %d866, %c20 : i8
    trikeshed.yield %ch67 : i8
  }
  %ws68, %wl69 = func.call @st_word(%c70) : (index) -> (index, index)
  %w71 = trikeshed.slice %blob[%ws68, %wl69] : !text -> !text
  %vp73 = llvm.getelementptr %vals[%c72] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv74 = llvm.load %vp73 : !llvm.ptr -> i64
  %dc75 = func.call @st_dcount(%vv74) : (i64) -> index
  %pg76 = memref.get_global @st_pow : memref<20xi64>
  %powers77 = trikeshed.text %pg76 : memref<20xi64> -> !s64
  %digits78 = trikeshed.series %dc75 : !text {
  ^bb0(%k: index):
    %last79 = arith.subi %dc75, %c12 : index
    %e80 = arith.subi %last79, %k : index
    %p81 = trikeshed.at %powers77[%e80] : !s64, index -> i64
    %q82 = arith.divui %vv74, %p81 : i64
    %dd83 = arith.remui %q82, %c17 : i64
    %d884 = arith.trunci %dd83 : i64 to i8
    %ch85 = arith.addi %d884, %c20 : i8
    trikeshed.yield %ch85 : i8
  }
  %ws86, %wl87 = func.call @st_word(%c88) : (index) -> (index, index)
  %w89 = trikeshed.slice %blob[%ws86, %wl87] : !text -> !text
  %vp91 = llvm.getelementptr %vals[%c90] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv92 = llvm.load %vp91 : !llvm.ptr -> i64
  %dc93 = func.call @st_dcount(%vv92) : (i64) -> index
  %pg94 = memref.get_global @st_pow : memref<20xi64>
  %powers95 = trikeshed.text %pg94 : memref<20xi64> -> !s64
  %digits96 = trikeshed.series %dc93 : !text {
  ^bb0(%k: index):
    %last97 = arith.subi %dc93, %c12 : index
    %e98 = arith.subi %last97, %k : index
    %p99 = trikeshed.at %powers95[%e98] : !s64, index -> i64
    %q100 = arith.divui %vv92, %p99 : i64
    %dd101 = arith.remui %q100, %c17 : i64
    %d8102 = arith.trunci %dd101 : i64 to i8
    %ch103 = arith.addi %d8102, %c20 : i8
    trikeshed.yield %ch103 : i8
  }
  %ws104, %wl105 = func.call @st_word(%c106) : (index) -> (index, index)
  %w107 = trikeshed.slice %blob[%ws104, %wl105] : !text -> !text
  %whole108 = trikeshed.combine %w4, %digits11, %w25, %join30, %w53, %digits60, %w71, %digits78, %w89, %digits96, %w107 : !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text -> !text
  %sz = trikeshed.size %whole108 : !text
  %szi = arith.index_cast %sz : index to i64
  %capi = arith.index_cast %cap : i64 to index
  %fits = arith.cmpi ule, %sz, %capi : index
  scf.if %fits {
    %end = trikeshed.drain %whole108, %mi : !text, !m8 -> index
  }
  return %szi : i64
}

func.func private @st_l_26(%vals: !llvm.ptr, %wins: !llvm.ptr, %rows: !llvm.ptr, %nrows: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %c3 = arith.constant 105 : index
  %c5 = arith.constant 0 : i64
  %c12 = arith.constant 1 : index
  %c17 = arith.constant 10 : i64
  %c20 = arith.constant 48 : i8
  %c24 = arith.constant 106 : index
  %c29 = arith.constant 64 : i64
  %c35 = arith.constant 8 : i64
  %c38 = arith.constant 16 : i64
  %c41 = arith.constant 24 : i64
  %c44 = arith.constant 32 : i64
  %c47 = arith.constant 40 : i64
  %c50 = arith.constant 48 : i64
  %c55 = arith.constant 110 : index
  %c60 = arith.constant 9 : index
  %c63 = arith.constant 0 : index
  %c86 = arith.constant 3 : index
  %di = func.call @st_desc8(%into, %cap) : (!llvm.ptr, i64) -> !d
  %mi = builtin.unrealized_conversion_cast %di : !d to !m8
  %bg = memref.get_global @st_blob : memref<2642xi8>
  %blob = trikeshed.text %bg : memref<2642xi8> -> !text
  %spg = memref.get_global @st_sp : memref<32xi8>
  %sp = trikeshed.text %spg : memref<32xi8> -> !text
  %ws1, %wl2 = func.call @st_word(%c3) : (index) -> (index, index)
  %w4 = trikeshed.slice %blob[%ws1, %wl2] : !text -> !text
  %vp6 = llvm.getelementptr %vals[%c5] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv7 = llvm.load %vp6 : !llvm.ptr -> i64
  %dc8 = func.call @st_dcount(%vv7) : (i64) -> index
  %pg9 = memref.get_global @st_pow : memref<20xi64>
  %powers10 = trikeshed.text %pg9 : memref<20xi64> -> !s64
  %digits11 = trikeshed.series %dc8 : !text {
  ^bb0(%k: index):
    %last13 = arith.subi %dc8, %c12 : index
    %e14 = arith.subi %last13, %k : index
    %p15 = trikeshed.at %powers10[%e14] : !s64, index -> i64
    %q16 = arith.divui %vv7, %p15 : i64
    %dd18 = arith.remui %q16, %c17 : i64
    %d819 = arith.trunci %dd18 : i64 to i8
    %ch21 = arith.addi %d819, %c20 : i8
    trikeshed.yield %ch21 : i8
  }
  %ws22, %wl23 = func.call @st_word(%c24) : (index) -> (index, index)
  %w25 = trikeshed.slice %blob[%ws22, %wl23] : !text -> !text
  %ni26 = arith.index_cast %nrows : i64 to index
  %rows27, %rco28 = trikeshed.combineAll %ni26 : !text, !coords {
  ^bb0(%j: index):
  %j6430 = arith.index_cast %j : index to i64
  %ro31 = arith.muli %j6430, %c29 : i64
  %rb32 = llvm.getelementptr %rows[%ro31] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fp33 = llvm.getelementptr %rb32[%c5] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fv34 = llvm.load %fp33 : !llvm.ptr -> !llvm.ptr
  %fp36 = llvm.getelementptr %rb32[%c35] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fv37 = llvm.load %fp36 : !llvm.ptr -> i64
  %fp39 = llvm.getelementptr %rb32[%c38] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fv40 = llvm.load %fp39 : !llvm.ptr -> i64
  %fp42 = llvm.getelementptr %rb32[%c41] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fv43 = llvm.load %fp42 : !llvm.ptr -> i64
  %fp45 = llvm.getelementptr %rb32[%c44] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fv46 = llvm.load %fp45 : !llvm.ptr -> i64
  %fp48 = llvm.getelementptr %rb32[%c47] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fv49 = llvm.load %fp48 : !llvm.ptr -> !llvm.ptr
  %fp51 = llvm.getelementptr %rb32[%c50] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fv52 = llvm.load %fp51 : !llvm.ptr -> i64
  %ws53, %wl54 = func.call @st_word(%c55) : (index) -> (index, index)
  %w56 = trikeshed.slice %blob[%ws53, %wl54] : !text -> !text
  %d57 = func.call @st_desc8(%fv34, %fv37) : (!llvm.ptr, i64) -> !d
  %m58 = builtin.unrealized_conversion_cast %d57 : !d to !m8
  %s59 = builtin.unrealized_conversion_cast %m58 : !m8 to !text
  %li61 = arith.index_cast %fv37 : i64 to index
  %sub62 = arith.subi %c60, %li61 : index
  %ge64 = arith.cmpi sge, %sub62, %c63 : index
  %n65 = arith.select %ge64, %sub62, %c63 : index
  %sp66 = trikeshed.slice %sp[%c63, %n65] : !text -> !text
  %pl67 = trikeshed.combine %s59, %sp66 : !text, !text -> !text
  %dc68 = func.call @st_dcount(%fv40) : (i64) -> index
  %pg69 = memref.get_global @st_pow : memref<20xi64>
  %powers70 = trikeshed.text %pg69 : memref<20xi64> -> !s64
  %digits71 = trikeshed.series %dc68 : !text {
  ^bb0(%k: index):
    %last72 = arith.subi %dc68, %c12 : index
    %e73 = arith.subi %last72, %k : index
    %p74 = trikeshed.at %powers70[%e73] : !s64, index -> i64
    %q75 = arith.divui %fv40, %p74 : i64
    %dd76 = arith.remui %q75, %c17 : i64
    %d877 = arith.trunci %dd76 : i64 to i8
    %ch78 = arith.addi %d877, %c20 : i8
    trikeshed.yield %ch78 : i8
  }
  %sub79 = arith.subi %c60, %dc68 : index
  %ge80 = arith.cmpi sge, %sub79, %c63 : index
  %n81 = arith.select %ge80, %sub79, %c63 : index
  %sp82 = trikeshed.slice %sp[%c63, %n81] : !text -> !text
  %pr83 = trikeshed.combine %sp82, %digits71 : !text, !text -> !text
  %ws84, %wl85 = func.call @st_word(%c86) : (index) -> (index, index)
  %w87 = trikeshed.slice %blob[%ws84, %wl85] : !text -> !text
  %row88 = trikeshed.combine %w56, %pl67, %pr83, %w87 : !text, !text, !text, !text -> !text
    trikeshed.yield %row88 : !text
  }
  %whole89 = trikeshed.combine %w4, %digits11, %w25, %rows27 : !text, !text, !text, !text -> !text
  %sz = trikeshed.size %whole89 : !text
  %szi = arith.index_cast %sz : index to i64
  %capi = arith.index_cast %cap : i64 to index
  %fits = arith.cmpi ule, %sz, %capi : index
  scf.if %fits {
    %end = trikeshed.drain %whole89, %mi : !text, !m8 -> index
  }
  return %szi : i64
}

func.func private @st_l_27(%vals: !llvm.ptr, %wins: !llvm.ptr, %rows: !llvm.ptr, %nrows: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %c3 = arith.constant 107 : index
  %c5 = arith.constant 0 : i64
  %c12 = arith.constant 1 : index
  %c17 = arith.constant 10 : i64
  %c20 = arith.constant 48 : i8
  %c24 = arith.constant 106 : index
  %c29 = arith.constant 64 : i64
  %c35 = arith.constant 8 : i64
  %c38 = arith.constant 16 : i64
  %c41 = arith.constant 24 : i64
  %c44 = arith.constant 32 : i64
  %c47 = arith.constant 40 : i64
  %c50 = arith.constant 48 : i64
  %c55 = arith.constant 110 : index
  %c60 = arith.constant 9 : index
  %c63 = arith.constant 0 : index
  %c86 = arith.constant 3 : index
  %di = func.call @st_desc8(%into, %cap) : (!llvm.ptr, i64) -> !d
  %mi = builtin.unrealized_conversion_cast %di : !d to !m8
  %bg = memref.get_global @st_blob : memref<2642xi8>
  %blob = trikeshed.text %bg : memref<2642xi8> -> !text
  %spg = memref.get_global @st_sp : memref<32xi8>
  %sp = trikeshed.text %spg : memref<32xi8> -> !text
  %ws1, %wl2 = func.call @st_word(%c3) : (index) -> (index, index)
  %w4 = trikeshed.slice %blob[%ws1, %wl2] : !text -> !text
  %vp6 = llvm.getelementptr %vals[%c5] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv7 = llvm.load %vp6 : !llvm.ptr -> i64
  %dc8 = func.call @st_dcount(%vv7) : (i64) -> index
  %pg9 = memref.get_global @st_pow : memref<20xi64>
  %powers10 = trikeshed.text %pg9 : memref<20xi64> -> !s64
  %digits11 = trikeshed.series %dc8 : !text {
  ^bb0(%k: index):
    %last13 = arith.subi %dc8, %c12 : index
    %e14 = arith.subi %last13, %k : index
    %p15 = trikeshed.at %powers10[%e14] : !s64, index -> i64
    %q16 = arith.divui %vv7, %p15 : i64
    %dd18 = arith.remui %q16, %c17 : i64
    %d819 = arith.trunci %dd18 : i64 to i8
    %ch21 = arith.addi %d819, %c20 : i8
    trikeshed.yield %ch21 : i8
  }
  %ws22, %wl23 = func.call @st_word(%c24) : (index) -> (index, index)
  %w25 = trikeshed.slice %blob[%ws22, %wl23] : !text -> !text
  %ni26 = arith.index_cast %nrows : i64 to index
  %rows27, %rco28 = trikeshed.combineAll %ni26 : !text, !coords {
  ^bb0(%j: index):
  %j6430 = arith.index_cast %j : index to i64
  %ro31 = arith.muli %j6430, %c29 : i64
  %rb32 = llvm.getelementptr %rows[%ro31] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fp33 = llvm.getelementptr %rb32[%c5] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fv34 = llvm.load %fp33 : !llvm.ptr -> !llvm.ptr
  %fp36 = llvm.getelementptr %rb32[%c35] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fv37 = llvm.load %fp36 : !llvm.ptr -> i64
  %fp39 = llvm.getelementptr %rb32[%c38] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fv40 = llvm.load %fp39 : !llvm.ptr -> i64
  %fp42 = llvm.getelementptr %rb32[%c41] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fv43 = llvm.load %fp42 : !llvm.ptr -> i64
  %fp45 = llvm.getelementptr %rb32[%c44] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fv46 = llvm.load %fp45 : !llvm.ptr -> i64
  %fp48 = llvm.getelementptr %rb32[%c47] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fv49 = llvm.load %fp48 : !llvm.ptr -> !llvm.ptr
  %fp51 = llvm.getelementptr %rb32[%c50] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fv52 = llvm.load %fp51 : !llvm.ptr -> i64
  %ws53, %wl54 = func.call @st_word(%c55) : (index) -> (index, index)
  %w56 = trikeshed.slice %blob[%ws53, %wl54] : !text -> !text
  %d57 = func.call @st_desc8(%fv34, %fv37) : (!llvm.ptr, i64) -> !d
  %m58 = builtin.unrealized_conversion_cast %d57 : !d to !m8
  %s59 = builtin.unrealized_conversion_cast %m58 : !m8 to !text
  %li61 = arith.index_cast %fv37 : i64 to index
  %sub62 = arith.subi %c60, %li61 : index
  %ge64 = arith.cmpi sge, %sub62, %c63 : index
  %n65 = arith.select %ge64, %sub62, %c63 : index
  %sp66 = trikeshed.slice %sp[%c63, %n65] : !text -> !text
  %pl67 = trikeshed.combine %s59, %sp66 : !text, !text -> !text
  %dc68 = func.call @st_dcount(%fv40) : (i64) -> index
  %pg69 = memref.get_global @st_pow : memref<20xi64>
  %powers70 = trikeshed.text %pg69 : memref<20xi64> -> !s64
  %digits71 = trikeshed.series %dc68 : !text {
  ^bb0(%k: index):
    %last72 = arith.subi %dc68, %c12 : index
    %e73 = arith.subi %last72, %k : index
    %p74 = trikeshed.at %powers70[%e73] : !s64, index -> i64
    %q75 = arith.divui %fv40, %p74 : i64
    %dd76 = arith.remui %q75, %c17 : i64
    %d877 = arith.trunci %dd76 : i64 to i8
    %ch78 = arith.addi %d877, %c20 : i8
    trikeshed.yield %ch78 : i8
  }
  %sub79 = arith.subi %c60, %dc68 : index
  %ge80 = arith.cmpi sge, %sub79, %c63 : index
  %n81 = arith.select %ge80, %sub79, %c63 : index
  %sp82 = trikeshed.slice %sp[%c63, %n81] : !text -> !text
  %pr83 = trikeshed.combine %sp82, %digits71 : !text, !text -> !text
  %ws84, %wl85 = func.call @st_word(%c86) : (index) -> (index, index)
  %w87 = trikeshed.slice %blob[%ws84, %wl85] : !text -> !text
  %row88 = trikeshed.combine %w56, %pl67, %pr83, %w87 : !text, !text, !text, !text -> !text
    trikeshed.yield %row88 : !text
  }
  %whole89 = trikeshed.combine %w4, %digits11, %w25, %rows27 : !text, !text, !text, !text -> !text
  %sz = trikeshed.size %whole89 : !text
  %szi = arith.index_cast %sz : index to i64
  %capi = arith.index_cast %cap : i64 to index
  %fits = arith.cmpi ule, %sz, %capi : index
  scf.if %fits {
    %end = trikeshed.drain %whole89, %mi : !text, !m8 -> index
  }
  return %szi : i64
}

func.func private @st_l_28(%vals: !llvm.ptr, %wins: !llvm.ptr, %rows: !llvm.ptr, %nrows: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %c3 = arith.constant 108 : index
  %c5 = arith.constant 0 : i64
  %c12 = arith.constant 1 : index
  %c17 = arith.constant 10 : i64
  %c20 = arith.constant 48 : i8
  %c24 = arith.constant 106 : index
  %c29 = arith.constant 64 : i64
  %c35 = arith.constant 8 : i64
  %c38 = arith.constant 16 : i64
  %c41 = arith.constant 24 : i64
  %c44 = arith.constant 32 : i64
  %c47 = arith.constant 40 : i64
  %c50 = arith.constant 48 : i64
  %c55 = arith.constant 110 : index
  %c60 = arith.constant 9 : index
  %c63 = arith.constant 0 : index
  %c86 = arith.constant 3 : index
  %di = func.call @st_desc8(%into, %cap) : (!llvm.ptr, i64) -> !d
  %mi = builtin.unrealized_conversion_cast %di : !d to !m8
  %bg = memref.get_global @st_blob : memref<2642xi8>
  %blob = trikeshed.text %bg : memref<2642xi8> -> !text
  %spg = memref.get_global @st_sp : memref<32xi8>
  %sp = trikeshed.text %spg : memref<32xi8> -> !text
  %ws1, %wl2 = func.call @st_word(%c3) : (index) -> (index, index)
  %w4 = trikeshed.slice %blob[%ws1, %wl2] : !text -> !text
  %vp6 = llvm.getelementptr %vals[%c5] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %vv7 = llvm.load %vp6 : !llvm.ptr -> i64
  %dc8 = func.call @st_dcount(%vv7) : (i64) -> index
  %pg9 = memref.get_global @st_pow : memref<20xi64>
  %powers10 = trikeshed.text %pg9 : memref<20xi64> -> !s64
  %digits11 = trikeshed.series %dc8 : !text {
  ^bb0(%k: index):
    %last13 = arith.subi %dc8, %c12 : index
    %e14 = arith.subi %last13, %k : index
    %p15 = trikeshed.at %powers10[%e14] : !s64, index -> i64
    %q16 = arith.divui %vv7, %p15 : i64
    %dd18 = arith.remui %q16, %c17 : i64
    %d819 = arith.trunci %dd18 : i64 to i8
    %ch21 = arith.addi %d819, %c20 : i8
    trikeshed.yield %ch21 : i8
  }
  %ws22, %wl23 = func.call @st_word(%c24) : (index) -> (index, index)
  %w25 = trikeshed.slice %blob[%ws22, %wl23] : !text -> !text
  %ni26 = arith.index_cast %nrows : i64 to index
  %rows27, %rco28 = trikeshed.combineAll %ni26 : !text, !coords {
  ^bb0(%j: index):
  %j6430 = arith.index_cast %j : index to i64
  %ro31 = arith.muli %j6430, %c29 : i64
  %rb32 = llvm.getelementptr %rows[%ro31] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fp33 = llvm.getelementptr %rb32[%c5] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fv34 = llvm.load %fp33 : !llvm.ptr -> !llvm.ptr
  %fp36 = llvm.getelementptr %rb32[%c35] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fv37 = llvm.load %fp36 : !llvm.ptr -> i64
  %fp39 = llvm.getelementptr %rb32[%c38] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fv40 = llvm.load %fp39 : !llvm.ptr -> i64
  %fp42 = llvm.getelementptr %rb32[%c41] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fv43 = llvm.load %fp42 : !llvm.ptr -> i64
  %fp45 = llvm.getelementptr %rb32[%c44] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fv46 = llvm.load %fp45 : !llvm.ptr -> i64
  %fp48 = llvm.getelementptr %rb32[%c47] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fv49 = llvm.load %fp48 : !llvm.ptr -> !llvm.ptr
  %fp51 = llvm.getelementptr %rb32[%c50] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fv52 = llvm.load %fp51 : !llvm.ptr -> i64
  %ws53, %wl54 = func.call @st_word(%c55) : (index) -> (index, index)
  %w56 = trikeshed.slice %blob[%ws53, %wl54] : !text -> !text
  %d57 = func.call @st_desc8(%fv34, %fv37) : (!llvm.ptr, i64) -> !d
  %m58 = builtin.unrealized_conversion_cast %d57 : !d to !m8
  %s59 = builtin.unrealized_conversion_cast %m58 : !m8 to !text
  %li61 = arith.index_cast %fv37 : i64 to index
  %sub62 = arith.subi %c60, %li61 : index
  %ge64 = arith.cmpi sge, %sub62, %c63 : index
  %n65 = arith.select %ge64, %sub62, %c63 : index
  %sp66 = trikeshed.slice %sp[%c63, %n65] : !text -> !text
  %pl67 = trikeshed.combine %s59, %sp66 : !text, !text -> !text
  %dc68 = func.call @st_dcount(%fv40) : (i64) -> index
  %pg69 = memref.get_global @st_pow : memref<20xi64>
  %powers70 = trikeshed.text %pg69 : memref<20xi64> -> !s64
  %digits71 = trikeshed.series %dc68 : !text {
  ^bb0(%k: index):
    %last72 = arith.subi %dc68, %c12 : index
    %e73 = arith.subi %last72, %k : index
    %p74 = trikeshed.at %powers70[%e73] : !s64, index -> i64
    %q75 = arith.divui %fv40, %p74 : i64
    %dd76 = arith.remui %q75, %c17 : i64
    %d877 = arith.trunci %dd76 : i64 to i8
    %ch78 = arith.addi %d877, %c20 : i8
    trikeshed.yield %ch78 : i8
  }
  %sub79 = arith.subi %c60, %dc68 : index
  %ge80 = arith.cmpi sge, %sub79, %c63 : index
  %n81 = arith.select %ge80, %sub79, %c63 : index
  %sp82 = trikeshed.slice %sp[%c63, %n81] : !text -> !text
  %pr83 = trikeshed.combine %sp82, %digits71 : !text, !text -> !text
  %ws84, %wl85 = func.call @st_word(%c86) : (index) -> (index, index)
  %w87 = trikeshed.slice %blob[%ws84, %wl85] : !text -> !text
  %row88 = trikeshed.combine %w56, %pl67, %pr83, %w87 : !text, !text, !text, !text -> !text
    trikeshed.yield %row88 : !text
  }
  %whole89 = trikeshed.combine %w4, %digits11, %w25, %rows27 : !text, !text, !text, !text -> !text
  %sz = trikeshed.size %whole89 : !text
  %szi = arith.index_cast %sz : index to i64
  %capi = arith.index_cast %cap : i64 to index
  %fits = arith.cmpi ule, %sz, %capi : index
  scf.if %fits {
    %end = trikeshed.drain %whole89, %mi : !text, !m8 -> index
  }
  return %szi : i64
}

func.func private @st_l_29(%vals: !llvm.ptr, %wins: !llvm.ptr, %rows: !llvm.ptr, %nrows: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %c3 = arith.constant 109 : index
  %c8 = arith.constant 64 : i64
  %c12 = arith.constant 0 : i64
  %c15 = arith.constant 8 : i64
  %c18 = arith.constant 16 : i64
  %c21 = arith.constant 24 : i64
  %c24 = arith.constant 32 : i64
  %c27 = arith.constant 40 : i64
  %c30 = arith.constant 48 : i64
  %c35 = arith.constant 110 : index
  %c40 = arith.constant 22 : index
  %c43 = arith.constant 0 : index
  %c52 = arith.constant 1 : index
  %c57 = arith.constant 10 : i64
  %c60 = arith.constant 48 : i8
  %c62 = arith.constant 9 : index
  %c70 = arith.constant 3 : index
  %di = func.call @st_desc8(%into, %cap) : (!llvm.ptr, i64) -> !d
  %mi = builtin.unrealized_conversion_cast %di : !d to !m8
  %bg = memref.get_global @st_blob : memref<2642xi8>
  %blob = trikeshed.text %bg : memref<2642xi8> -> !text
  %spg = memref.get_global @st_sp : memref<32xi8>
  %sp = trikeshed.text %spg : memref<32xi8> -> !text
  %ws1, %wl2 = func.call @st_word(%c3) : (index) -> (index, index)
  %w4 = trikeshed.slice %blob[%ws1, %wl2] : !text -> !text
  %ni5 = arith.index_cast %nrows : i64 to index
  %rows6, %rco7 = trikeshed.combineAll %ni5 : !text, !coords {
  ^bb0(%j: index):
  %j649 = arith.index_cast %j : index to i64
  %ro10 = arith.muli %j649, %c8 : i64
  %rb11 = llvm.getelementptr %rows[%ro10] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fp13 = llvm.getelementptr %rb11[%c12] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fv14 = llvm.load %fp13 : !llvm.ptr -> !llvm.ptr
  %fp16 = llvm.getelementptr %rb11[%c15] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fv17 = llvm.load %fp16 : !llvm.ptr -> i64
  %fp19 = llvm.getelementptr %rb11[%c18] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fv20 = llvm.load %fp19 : !llvm.ptr -> i64
  %fp22 = llvm.getelementptr %rb11[%c21] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fv23 = llvm.load %fp22 : !llvm.ptr -> i64
  %fp25 = llvm.getelementptr %rb11[%c24] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fv26 = llvm.load %fp25 : !llvm.ptr -> i64
  %fp28 = llvm.getelementptr %rb11[%c27] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fv29 = llvm.load %fp28 : !llvm.ptr -> !llvm.ptr
  %fp31 = llvm.getelementptr %rb11[%c30] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fv32 = llvm.load %fp31 : !llvm.ptr -> i64
  %ws33, %wl34 = func.call @st_word(%c35) : (index) -> (index, index)
  %w36 = trikeshed.slice %blob[%ws33, %wl34] : !text -> !text
  %d37 = func.call @st_desc8(%fv14, %fv17) : (!llvm.ptr, i64) -> !d
  %m38 = builtin.unrealized_conversion_cast %d37 : !d to !m8
  %s39 = builtin.unrealized_conversion_cast %m38 : !m8 to !text
  %li41 = arith.index_cast %fv17 : i64 to index
  %sub42 = arith.subi %c40, %li41 : index
  %ge44 = arith.cmpi sge, %sub42, %c43 : index
  %n45 = arith.select %ge44, %sub42, %c43 : index
  %sp46 = trikeshed.slice %sp[%c43, %n45] : !text -> !text
  %pl47 = trikeshed.combine %s39, %sp46 : !text, !text -> !text
  %dc48 = func.call @st_dcount(%fv20) : (i64) -> index
  %pg49 = memref.get_global @st_pow : memref<20xi64>
  %powers50 = trikeshed.text %pg49 : memref<20xi64> -> !s64
  %digits51 = trikeshed.series %dc48 : !text {
  ^bb0(%k: index):
    %last53 = arith.subi %dc48, %c52 : index
    %e54 = arith.subi %last53, %k : index
    %p55 = trikeshed.at %powers50[%e54] : !s64, index -> i64
    %q56 = arith.divui %fv20, %p55 : i64
    %dd58 = arith.remui %q56, %c57 : i64
    %d859 = arith.trunci %dd58 : i64 to i8
    %ch61 = arith.addi %d859, %c60 : i8
    trikeshed.yield %ch61 : i8
  }
  %sub63 = arith.subi %c62, %dc48 : index
  %ge64 = arith.cmpi sge, %sub63, %c43 : index
  %n65 = arith.select %ge64, %sub63, %c43 : index
  %sp66 = trikeshed.slice %sp[%c43, %n65] : !text -> !text
  %pr67 = trikeshed.combine %sp66, %digits51 : !text, !text -> !text
  %ws68, %wl69 = func.call @st_word(%c70) : (index) -> (index, index)
  %w71 = trikeshed.slice %blob[%ws68, %wl69] : !text -> !text
  %row72 = trikeshed.combine %w36, %pl47, %pr67, %w71 : !text, !text, !text, !text -> !text
    trikeshed.yield %row72 : !text
  }
  %whole73 = trikeshed.combine %w4, %rows6 : !text, !text -> !text
  %sz = trikeshed.size %whole73 : !text
  %szi = arith.index_cast %sz : index to i64
  %capi = arith.index_cast %cap : i64 to index
  %fits = arith.cmpi ule, %sz, %capi : index
  scf.if %fits {
    %end = trikeshed.drain %whole73, %mi : !text, !m8 -> index
  }
  return %szi : i64
}

func.func @nixev_ts_stats(%kind: i32, %vals: !llvm.ptr, %wins: !llvm.ptr, %rows: !llvm.ptr, %nrows: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %c1 = arith.constant 0 : i32
  %c5 = arith.constant 1 : i32
  %c9 = arith.constant 2 : i32
  %c13 = arith.constant 3 : i32
  %c17 = arith.constant 4 : i32
  %c21 = arith.constant 5 : i32
  %c25 = arith.constant 6 : i32
  %c29 = arith.constant 7 : i32
  %c33 = arith.constant 8 : i32
  %c37 = arith.constant 9 : i32
  %c41 = arith.constant 10 : i32
  %c45 = arith.constant 11 : i32
  %c49 = arith.constant 12 : i32
  %c53 = arith.constant 13 : i32
  %c57 = arith.constant 14 : i32
  %c61 = arith.constant 15 : i32
  %c65 = arith.constant 16 : i32
  %c69 = arith.constant 17 : i32
  %c73 = arith.constant 18 : i32
  %c77 = arith.constant 19 : i32
  %c81 = arith.constant 20 : i32
  %c85 = arith.constant 21 : i32
  %c89 = arith.constant 22 : i32
  %c93 = arith.constant 23 : i32
  %c97 = arith.constant 24 : i32
  %c101 = arith.constant 25 : i32
  %c105 = arith.constant 26 : i32
  %c109 = arith.constant 27 : i32
  %c113 = arith.constant 28 : i32
  %c117 = arith.constant 29 : i32
%eq2 = arith.cmpi eq, %kind, %c1 : i32
%r3 = scf.if %eq2 -> (i64) {
  %v4 = func.call @st_l_0(%vals, %wins, %rows, %nrows, %into, %cap) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
  scf.yield %v4 : i64
} else {
  %eq6 = arith.cmpi eq, %kind, %c5 : i32
  %r7 = scf.if %eq6 -> (i64) {
    %v8 = func.call @st_l_1(%vals, %wins, %rows, %nrows, %into, %cap) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
    scf.yield %v8 : i64
  } else {
    %eq10 = arith.cmpi eq, %kind, %c9 : i32
    %r11 = scf.if %eq10 -> (i64) {
      %v12 = func.call @st_l_2(%vals, %wins, %rows, %nrows, %into, %cap) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
      scf.yield %v12 : i64
    } else {
      %eq14 = arith.cmpi eq, %kind, %c13 : i32
      %r15 = scf.if %eq14 -> (i64) {
        %v16 = func.call @st_l_3(%vals, %wins, %rows, %nrows, %into, %cap) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
        scf.yield %v16 : i64
      } else {
        %eq18 = arith.cmpi eq, %kind, %c17 : i32
        %r19 = scf.if %eq18 -> (i64) {
          %v20 = func.call @st_l_4(%vals, %wins, %rows, %nrows, %into, %cap) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
          scf.yield %v20 : i64
        } else {
          %eq22 = arith.cmpi eq, %kind, %c21 : i32
          %r23 = scf.if %eq22 -> (i64) {
            %v24 = func.call @st_l_5(%vals, %wins, %rows, %nrows, %into, %cap) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
            scf.yield %v24 : i64
          } else {
            %eq26 = arith.cmpi eq, %kind, %c25 : i32
            %r27 = scf.if %eq26 -> (i64) {
              %v28 = func.call @st_l_6(%vals, %wins, %rows, %nrows, %into, %cap) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
              scf.yield %v28 : i64
            } else {
              %eq30 = arith.cmpi eq, %kind, %c29 : i32
              %r31 = scf.if %eq30 -> (i64) {
                %v32 = func.call @st_l_7(%vals, %wins, %rows, %nrows, %into, %cap) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
                scf.yield %v32 : i64
              } else {
                %eq34 = arith.cmpi eq, %kind, %c33 : i32
                %r35 = scf.if %eq34 -> (i64) {
                  %v36 = func.call @st_l_8(%vals, %wins, %rows, %nrows, %into, %cap) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
                  scf.yield %v36 : i64
                } else {
                  %eq38 = arith.cmpi eq, %kind, %c37 : i32
                  %r39 = scf.if %eq38 -> (i64) {
                    %v40 = func.call @st_l_9(%vals, %wins, %rows, %nrows, %into, %cap) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
                    scf.yield %v40 : i64
                  } else {
                    %eq42 = arith.cmpi eq, %kind, %c41 : i32
                    %r43 = scf.if %eq42 -> (i64) {
                      %v44 = func.call @st_l_10(%vals, %wins, %rows, %nrows, %into, %cap) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
                      scf.yield %v44 : i64
                    } else {
                      %eq46 = arith.cmpi eq, %kind, %c45 : i32
                      %r47 = scf.if %eq46 -> (i64) {
                        %v48 = func.call @st_l_11(%vals, %wins, %rows, %nrows, %into, %cap) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
                        scf.yield %v48 : i64
                      } else {
                        %eq50 = arith.cmpi eq, %kind, %c49 : i32
                        %r51 = scf.if %eq50 -> (i64) {
                          %v52 = func.call @st_l_12(%vals, %wins, %rows, %nrows, %into, %cap) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
                          scf.yield %v52 : i64
                        } else {
                          %eq54 = arith.cmpi eq, %kind, %c53 : i32
                          %r55 = scf.if %eq54 -> (i64) {
                            %v56 = func.call @st_l_13(%vals, %wins, %rows, %nrows, %into, %cap) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
                            scf.yield %v56 : i64
                          } else {
                            %eq58 = arith.cmpi eq, %kind, %c57 : i32
                            %r59 = scf.if %eq58 -> (i64) {
                              %v60 = func.call @st_l_14(%vals, %wins, %rows, %nrows, %into, %cap) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
                              scf.yield %v60 : i64
                            } else {
                              %eq62 = arith.cmpi eq, %kind, %c61 : i32
                              %r63 = scf.if %eq62 -> (i64) {
                                %v64 = func.call @st_l_15(%vals, %wins, %rows, %nrows, %into, %cap) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
                                scf.yield %v64 : i64
                              } else {
                                %eq66 = arith.cmpi eq, %kind, %c65 : i32
                                %r67 = scf.if %eq66 -> (i64) {
                                  %v68 = func.call @st_l_16(%vals, %wins, %rows, %nrows, %into, %cap) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
                                  scf.yield %v68 : i64
                                } else {
                                  %eq70 = arith.cmpi eq, %kind, %c69 : i32
                                  %r71 = scf.if %eq70 -> (i64) {
                                    %v72 = func.call @st_l_17(%vals, %wins, %rows, %nrows, %into, %cap) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
                                    scf.yield %v72 : i64
                                  } else {
                                    %eq74 = arith.cmpi eq, %kind, %c73 : i32
                                    %r75 = scf.if %eq74 -> (i64) {
                                      %v76 = func.call @st_l_18(%vals, %wins, %rows, %nrows, %into, %cap) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
                                      scf.yield %v76 : i64
                                    } else {
                                      %eq78 = arith.cmpi eq, %kind, %c77 : i32
                                      %r79 = scf.if %eq78 -> (i64) {
                                        %v80 = func.call @st_l_19(%vals, %wins, %rows, %nrows, %into, %cap) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
                                        scf.yield %v80 : i64
                                      } else {
                                        %eq82 = arith.cmpi eq, %kind, %c81 : i32
                                        %r83 = scf.if %eq82 -> (i64) {
                                          %v84 = func.call @st_l_20(%vals, %wins, %rows, %nrows, %into, %cap) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
                                          scf.yield %v84 : i64
                                        } else {
                                          %eq86 = arith.cmpi eq, %kind, %c85 : i32
                                          %r87 = scf.if %eq86 -> (i64) {
                                            %v88 = func.call @st_l_21(%vals, %wins, %rows, %nrows, %into, %cap) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
                                            scf.yield %v88 : i64
                                          } else {
                                            %eq90 = arith.cmpi eq, %kind, %c89 : i32
                                            %r91 = scf.if %eq90 -> (i64) {
                                              %v92 = func.call @st_l_22(%vals, %wins, %rows, %nrows, %into, %cap) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
                                              scf.yield %v92 : i64
                                            } else {
                                              %eq94 = arith.cmpi eq, %kind, %c93 : i32
                                              %r95 = scf.if %eq94 -> (i64) {
                                                %v96 = func.call @st_l_23(%vals, %wins, %rows, %nrows, %into, %cap) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
                                                scf.yield %v96 : i64
                                              } else {
                                                %eq98 = arith.cmpi eq, %kind, %c97 : i32
                                                %r99 = scf.if %eq98 -> (i64) {
                                                  %v100 = func.call @st_l_24(%vals, %wins, %rows, %nrows, %into, %cap) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
                                                  scf.yield %v100 : i64
                                                } else {
                                                  %eq102 = arith.cmpi eq, %kind, %c101 : i32
                                                  %r103 = scf.if %eq102 -> (i64) {
                                                    %v104 = func.call @st_l_25(%vals, %wins, %rows, %nrows, %into, %cap) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
                                                    scf.yield %v104 : i64
                                                  } else {
                                                    %eq106 = arith.cmpi eq, %kind, %c105 : i32
                                                    %r107 = scf.if %eq106 -> (i64) {
                                                      %v108 = func.call @st_l_26(%vals, %wins, %rows, %nrows, %into, %cap) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
                                                      scf.yield %v108 : i64
                                                    } else {
                                                      %eq110 = arith.cmpi eq, %kind, %c109 : i32
                                                      %r111 = scf.if %eq110 -> (i64) {
                                                        %v112 = func.call @st_l_27(%vals, %wins, %rows, %nrows, %into, %cap) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
                                                        scf.yield %v112 : i64
                                                      } else {
                                                        %eq114 = arith.cmpi eq, %kind, %c113 : i32
                                                        %r115 = scf.if %eq114 -> (i64) {
                                                          %v116 = func.call @st_l_28(%vals, %wins, %rows, %nrows, %into, %cap) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
                                                          scf.yield %v116 : i64
                                                        } else {
                                                          %eq118 = arith.cmpi eq, %kind, %c117 : i32
                                                          %r119 = scf.if %eq118 -> (i64) {
                                                            %v120 = func.call @st_l_29(%vals, %wins, %rows, %nrows, %into, %cap) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
                                                            scf.yield %v120 : i64
                                                          } else {
                                                            %v121 = func.call @st_l_29(%vals, %wins, %rows, %nrows, %into, %cap) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
                                                            scf.yield %v121 : i64
                                                          }
                                                          scf.yield %r119 : i64
                                                        }
                                                        scf.yield %r115 : i64
                                                      }
                                                      scf.yield %r111 : i64
                                                    }
                                                    scf.yield %r107 : i64
                                                  }
                                                  scf.yield %r103 : i64
                                                }
                                                scf.yield %r99 : i64
                                              }
                                              scf.yield %r95 : i64
                                            }
                                            scf.yield %r91 : i64
                                          }
                                          scf.yield %r87 : i64
                                        }
                                        scf.yield %r83 : i64
                                      }
                                      scf.yield %r79 : i64
                                    }
                                    scf.yield %r75 : i64
                                  }
                                  scf.yield %r71 : i64
                                }
                                scf.yield %r67 : i64
                              }
                              scf.yield %r63 : i64
                            }
                            scf.yield %r59 : i64
                          }
                          scf.yield %r55 : i64
                        }
                        scf.yield %r51 : i64
                      }
                      scf.yield %r47 : i64
                    }
                    scf.yield %r43 : i64
                  }
                  scf.yield %r39 : i64
                }
                scf.yield %r35 : i64
              }
              scf.yield %r31 : i64
            }
            scf.yield %r27 : i64
          }
          scf.yield %r23 : i64
        }
        scf.yield %r19 : i64
      }
      scf.yield %r15 : i64
    }
    scf.yield %r11 : i64
  }
  scf.yield %r7 : i64
}
  return %r3 : i64
}
