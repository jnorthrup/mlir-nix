// derivationStrict's pure algebra hollowed from lib/Eval/StoreBuiltins.cpp into the TrikeShed dialect.  The bridge keeps
// every force (and so the forcing order), the Value building, the store calls (closure, readDerivation, hashing, the
// .drv write) and the throws; what is here is the text algebra between them:
//
//   nixev_ts_drv_word(p, n, lo, hi)   which word of the blob in [lo, hi) the n bytes at p are, else -1: the
//       outputHashMode words (0 recursive, 1 nar, 2 flat, 3 text, 4 git), the six attributes structuredAttrs disables
//       (5..10), drvPath (11).  slice + compare unsigned (Text ==).
//   nixev_ts_drv_msg(code, a, an, b, bn, into, cap)   every message derivationStrict throws, warns, traces or uses as a
//       context element: code's row of 7 template pieces (a blob word, -1 window a, -2 window b) as ONE combineAll
//       drained once.  Returns the size; drains only when it fits cap (the bridge's room 256 + 2 (an + bn) always does).
//   nixev_ts_drv_outputs(wins, n, order)   the `outputs` attribute's names in the order given: 0 when they are a set
//       (no duplicate, no drvPath, not empty) with the sorted row indices drained into order, else k << 2 | code
//       (1 duplicate at k, 2 drvPath at k, 3 empty), k the first name the old insert loop threw at.  trikeshed.sorted
//       (stable) of the row indices: a name equal to its sorted predecessor is a later occurrence.
//   nixev_ts_drv_ctx(wins, n, recs)   the derivation's context elements sorted (byte order, unsigned) and made unique,
//       each classified into a record of 6 i64 {row, kind, a off, a len, b off, b len}: kind 0 "=drv" (a: the path
//       after '='), 1 "!out!drv" (a: the drv after the second '!', b: the output between; with no second '!' a is the
//       whole element and b the rest after the first byte, as substr(npos + 1) / substr(1, npos - 1) were), 2 a plain
//       path (a: whole).  Returns the number of records.
//   nixev_ts_drv_jsonobj(p, ends, k, into, cap)   __structuredAttrs' JSON object: "{" the k "key":value pieces (the
//       bytes at p, piece j ending at ends[j]) joined by "," "}", one combine drained once; returns the size.
//
// Windows are 16-byte records {ptr, i64 n}.  Helper names are module-unique (ds_*): convert-func-to-llvm exports a
// func.func private as a global symbol.  Lowered by lib/CMakeLists.txt's mlnix_lower_trikeshed into NixEval.
!s = !trikeshed.series<i8>
!s32 = !trikeshed.series<i32>
!s64 = !trikeshed.series<i64>
!tp = !trikeshed.twinpacked<i32>
!sp = !trikeshed.series<!tp>
!m = memref<?xi8, strided<[1], offset: ?>>
!m64 = memref<?xi64, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

memref.global "private" constant @ds_blob : memref<1350xi8> = dense<"0x7265637572736976656E6172666C617474657874676974616C6C6F7765645265666572656E636573616C6C6F77656452657175697369746573646973616C6C6F7765645265666572656E636573646973616C6C6F776564526571756973697465736D617853697A656D6178436C6F7375726553697A65647276506174687B2C7D696E76616C69642064657269766174696F6E206E616D653A202E20506C656173652070617373206120646966666572656E7420276E616D65272E6578706572696D656E74616C204E69782066656174757265202764796E616D69632D64657269766174696F6E73272069732064697361626C65643B2061646420272D2D65787472612D6578706572696D656E74616C2D6665617475726573202720746F20656E61626C652069746769742D68617368696E67696E76616C69642076616C756520272720666F7220276F7574707574486173684D6F646527206174747269627574656475706C69636174652064657269766174696F6E206F7574707574202727696E76616C69642064657269766174696F6E206F7574707574206E616D652027647276506174682764657269766174696F6E2063616E6E6F74206861766520616E20656D70747920736574206F66206F757470757473756E6B6E6F776E206861736820616C676F726974686D2027272C206578706563742027626C616B6533272C20276D6435272C202773686131272C2027736861323536272C206F7220277368613531322763612D64657269766174696F6E73696D707572652D64657269766174696F6E7372657175697265642061747472696275746520276275696C64657227206D697373696E67726571756972656420617474726962757465202773797374656D27206D697373696E6764657269766174696F6E206E616D65732061726520616C6C6F77656420746F20656E6420696E20272E64727627206F6E6C7920696620746865792070726F6475636520612073696E676C652064657269766174696F6E2066696C656D756C7469706C65206F75747075747320617265206E6F7420737570706F7274656420696E2066697865642D6F75747075742064657269766174696F6E7361747472696275746520276E616D6527206D697373696E67696E2074686520617474727365742070617373656420617320617267756D656E7420746F206275696C74696E732E64657269766174696F6E5374726963747768696C65206576616C756174696E67207468652064657269766174696F6E2061747472696275746520276E616D65277768696C65206576616C756174696E6720617474726962757465202727206F662064657269766174696F6E20277768696C65206576616C756174696E672064657269766174696F6E2027270A202077686F7365206E616D6520617474726962757465206973206C6F636174656420617420496E20612064657269766174696F6E206E616D65642027272C2027737472756374757265644174747273272064697361626C65732074686520656666656374206F66207468652064657269766174696F6E206174747269627574652027273B2075736520276F7574707574436865636B732E3C6F75747075743E2E2720696E7374656164496E2064657269766174696F6E2027273A2073657474696E67207374727563747572656420617474726962757465732076696120275F5F6A736F6E2720697320646570726563617465642C20616E64206D617920626520646973616C6C6F77656420696E206675747572652076657273696F6E73206F66204E69782E2053657420275F5F737472756374757265644174747273203D20747275652720696E73746561642E213D">
memref.global "private" constant @ds_off : memref<52xi32> = dense<[0, 9, 12, 16, 20, 23, 40, 57, 77, 97, 104, 118, 125, 125, 126, 127, 128, 153, 186, 212, 231, 281, 295, 306, 321, 353, 382, 383, 423, 469, 493, 549, 563, 581, 617, 652, 743, 805, 829, 891, 939, 967, 984, 1013, 1052, 1075, 1145, 1175, 1184, 1199, 1348, 1349]>
memref.global "private" constant @ds_len : memref<52xi32> = dense<[9, 3, 4, 4, 3, 17, 17, 20, 20, 7, 14, 7, 0, 1, 1, 1, 25, 33, 26, 19, 50, 14, 11, 15, 32, 29, 1, 40, 46, 24, 56, 14, 18, 36, 35, 91, 62, 24, 62, 48, 28, 17, 29, 39, 23, 70, 30, 9, 15, 149, 1, 1]>
memref.global "private" constant @ds_tmpl : memref<161xi32> = dense<[16, -1, 17, 12, 12, 12, 12, 18, 19, 20, 19, 21, 12, 12, 18, 22, 20, 22, 21, 12, 12, 23, -1, 24, 12, 12, 12, 12, 25, -1, 26, 12, 12, 12, 12, 27, 12, 12, 12, 12, 12, 12, 28, 12, 12, 12, 12, 12, 12, 29, -1, 30, 12, 12, 12, 12, 18, 31, 20, 31, 21, 12, 12, 18, 32, 20, 32, 21, 12, 12, 33, 12, 12, 12, 12, 12, 12, 34, 12, 12, 12, 12, 12, 12, 35, 12, 12, 12, 12, 12, 12, 36, 12, 12, 12, 12, 12, 12, 37, 12, 12, 12, 12, 12, 12, 38, 12, 12, 12, 12, 12, 12, 39, 12, 12, 12, 12, 12, 12, 40, -1, 41, -2, 26, 12, 12, 42, -1, 43, -2, 12, 12, 12, 44, -1, 45, -2, 46, -2, 47, 48, -1, 49, 12, 12, 12, 12, 50, -1, 50, -2, 12, 12, 12, 51, -1, 12, 12, 12, 12, 12]>

// the descriptor of n cells at p (i8 and i64 cells share the struct)
func.func private @ds_desc(%p: !llvm.ptr, %n: i64) -> !d {
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

// window k of a {ptr, n} record array: its pointer and length
func.func private @ds_win(%w: !llvm.ptr, %k: i64) -> (!llvm.ptr, i64) {
  %two = arith.constant 2 : i64
  %one = arith.constant 1 : i64
  %k2 = arith.muli %k, %two : i64
  %qp = llvm.getelementptr %w[%k2] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %p = llvm.load %qp : !llvm.ptr -> !llvm.ptr
  %k3 = arith.addi %k2, %one : i64
  %qn = llvm.getelementptr %w[%k3] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %n = llvm.load %qn : !llvm.ptr -> i64
  return %p, %n : !llvm.ptr, i64
}

// the (start, length) of word id in the blob
func.func private @ds_word(%id: index) -> (index, index) {
  %og = memref.get_global @ds_off : memref<52xi32>
  %offs = trikeshed.text %og : memref<52xi32> -> !s32
  %lg = memref.get_global @ds_len : memref<52xi32>
  %lens = trikeshed.text %lg : memref<52xi32> -> !s32
  %o = trikeshed.at %offs[%id] : !s32, index -> i32
  %l = trikeshed.at %lens[%id] : !s32, index -> i32
  %oi = arith.index_cast %o : i32 to index
  %li = arith.index_cast %l : i32 to index
  return %oi, %li : index, index
}

// the order of two windows: compare unsigned (memcmp, then the shorter is less), as std::string_view <
func.func private @ds_cmp(%pa: !llvm.ptr, %na: i64, %pb: !llvm.ptr, %nb: i64) -> i32 {
  %da = func.call @ds_desc(%pa, %na) : (!llvm.ptr, i64) -> !d
  %ma = builtin.unrealized_conversion_cast %da : !d to !m
  %xa = builtin.unrealized_conversion_cast %ma : !m to !s
  %db = func.call @ds_desc(%pb, %nb) : (!llvm.ptr, i64) -> !d
  %mb = builtin.unrealized_conversion_cast %db : !d to !m
  %xb = builtin.unrealized_conversion_cast %mb : !m to !s
  %c = trikeshed.compare %xa, %xb unsigned : !s, !s
  return %c : i32
}

// whether the n bytes at p are word id
func.func private @ds_is(%p: !llvm.ptr, %n: i64, %id: index) -> i1 {
  %false = arith.constant false
  %z32 = arith.constant 0 : i32
  %w:2 = func.call @ds_word(%id) : (index) -> (index, index)
  %ni = arith.index_cast %n : i64 to index
  %eqlen = arith.cmpi eq, %ni, %w#1 : index
  %r = scf.if %eqlen -> (i1) {
    %g = memref.get_global @ds_blob : memref<1350xi8>
    %b = trikeshed.text %g : memref<1350xi8> -> !s
    %wd = trikeshed.slice %b[%w#0, %w#1] : !s -> !s
    %dx = func.call @ds_desc(%p, %n) : (!llvm.ptr, i64) -> !d
    %mx = builtin.unrealized_conversion_cast %dx : !d to !m
    %x = builtin.unrealized_conversion_cast %mx : !m to !s
    %c = trikeshed.compare %x, %wd unsigned : !s, !s
    %e = arith.cmpi eq, %c, %z32 : i32
    scf.yield %e : i1
  } else {
    scf.yield %false : i1
  }
  return %r : i1
}

func.func @nixev_ts_drv_word(%p: !llvm.ptr, %n: i64, %lo: i64, %hi: i64) -> i64 {
  %one = arith.constant 1 : i64
  %cm1 = arith.constant -1 : i64
  %z = arith.constant 0 : i64
  %r:2 = scf.while (%id = %lo, %f = %cm1) : (i64, i64) -> (i64, i64) {
    %in = arith.cmpi slt, %id, %hi : i64
    %no = arith.cmpi slt, %f, %z : i64
    %go = arith.andi %in, %no : i1
    scf.condition(%go) %id, %f : i64, i64
  } do {
  ^bb0(%id: i64, %f: i64):
    %ii = arith.index_cast %id : i64 to index
    %hit = func.call @ds_is(%p, %n, %ii) : (!llvm.ptr, i64, index) -> i1
    %nf = arith.select %hit, %id, %f : i64
    %id1 = arith.addi %id, %one : i64
    scf.yield %id1, %nf : i64, i64
  }
  return %r#1 : i64
}

//===----------------------------------------------------------------------===//
// messages
//===----------------------------------------------------------------------===//

func.func @nixev_ts_drv_msg(%code: i64, %a: !llvm.ptr, %an: i64, %b: !llvm.ptr, %bn: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %c0 = arith.constant 0 : index
  %c7 = arith.constant 7 : index
  %m1 = arith.constant -1 : i32
  %m2 = arith.constant -2 : i32
  %g = memref.get_global @ds_blob : memref<1350xi8>
  %base = memref.extract_aligned_pointer_as_index %g : memref<1350xi8> -> index
  %base64 = arith.index_cast %base : index to i64
  %bp = llvm.inttoptr %base64 : i64 to !llvm.ptr
  %tg = memref.get_global @ds_tmpl : memref<161xi32>
  %tmpl = trikeshed.text %tg : memref<161xi32> -> !s32
  %ci = arith.index_cast %code : i64 to index
  %row = arith.muli %ci, %c7 : index
  // piece j: the word's bytes in the blob, or window a / b, chosen at the pointer level (no select of views)
  %all, %co = trikeshed.combineAll %c7 : !s, !sp {
  ^bb0(%j: index):
    %tj = arith.addi %row, %j : index
    %id = trikeshed.at %tmpl[%tj] : !s32, index -> i32
    %isa = arith.cmpi eq, %id, %m1 : i32
    %isb = arith.cmpi eq, %id, %m2 : i32
    %z32 = arith.constant 0 : i32
    %isw = arith.cmpi sge, %id, %z32 : i32
    %wid32 = arith.select %isw, %id, %z32 : i32
    %wid = arith.index_cast %wid32 : i32 to index
    %w:2 = func.call @ds_word(%wid) : (index) -> (index, index)
    %wo = arith.index_cast %w#0 : index to i64
    %wl = arith.index_cast %w#1 : index to i64
    %wp = llvm.getelementptr %bp[%wo] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %p1 = llvm.select %isb, %b, %wp : i1, !llvm.ptr
    %p2 = llvm.select %isa, %a, %p1 : i1, !llvm.ptr
    %l1 = arith.select %isb, %bn, %wl : i64
    %l2 = arith.select %isa, %an, %l1 : i64
    %pd = func.call @ds_desc(%p2, %l2) : (!llvm.ptr, i64) -> !d
    %pm = builtin.unrealized_conversion_cast %pd : !d to !m
    %piece = builtin.unrealized_conversion_cast %pm : !m to !s
    trikeshed.yield %piece : !s
  }
  %sz = trikeshed.size %all : !s
  %szi = arith.index_cast %sz : index to i64
  %capi = arith.index_cast %cap : i64 to index
  %fits = arith.cmpi ule, %sz, %capi : index
  scf.if %fits {
    %di = func.call @ds_desc(%into, %cap) : (!llvm.ptr, i64) -> !d
    %mi = builtin.unrealized_conversion_cast %di : !d to !m
    %end = trikeshed.drain %all, %mi : !s, !m -> index
  }
  return %szi : i64
}

//===----------------------------------------------------------------------===//
// the outputs attribute
//===----------------------------------------------------------------------===//

func.func @nixev_ts_drv_outputs(%w: !llvm.ptr, %n: i64, %order: !llvm.ptr) -> i64 {
  %z = arith.constant 0 : index
  %one = arith.constant 1 : index
  %z64 = arith.constant 0 : i64
  %one64 = arith.constant 1 : i64
  %three = arith.constant 3 : i64
  %drvp = arith.constant 11 : index
  %z32 = arith.constant 0 : i32
  %empty = arith.cmpi eq, %n, %z64 : i64
  %r = scf.if %empty -> (i64) {
    scf.yield %three : i64
  } else {
    %ni = arith.index_cast %n : i64 to index
    %idx = trikeshed.series %ni : !s64 {
    ^bb0(%q: index):
      %q64 = arith.index_cast %q : index to i64
      trikeshed.yield %q64 : i64
    }
    %srt = trikeshed.sorted %idx : !s64 -> !s64 by {
    ^bb0(%ia: i64, %ib: i64):
      %wa:2 = func.call @ds_win(%w, %ia) : (!llvm.ptr, i64) -> (!llvm.ptr, i64)
      %wb:2 = func.call @ds_win(%w, %ib) : (!llvm.ptr, i64) -> (!llvm.ptr, i64)
      %c = func.call @ds_cmp(%wa#0, %wa#1, %wb#0, %wb#1) : (!llvm.ptr, i64, !llvm.ptr, i64) -> i32
      trikeshed.yield %c : i32
    }
    // the first later occurrence (dup) and the first drvPath, by row; n means none
    %f:2 = scf.for %j = %z to %ni step %one iter_args(%dup = %n, %dp = %n) -> (i64, i64) {
      %e = trikeshed.at %srt[%j] : !s64, index -> i64
      %we:2 = func.call @ds_win(%w, %e) : (!llvm.ptr, i64) -> (!llvm.ptr, i64)
      %isd = func.call @ds_is(%we#0, %we#1, %drvp) : (!llvm.ptr, i64, index) -> i1
      %dpe = arith.minsi %dp, %e : i64
      %dp2 = arith.select %isd, %dpe, %dp : i64
      %first = arith.cmpi eq, %j, %z : index
      %later = scf.if %first -> (i1) {
        %false = arith.constant false
        scf.yield %false : i1
      } else {
        %jp = arith.subi %j, %one : index
        %pe = trikeshed.at %srt[%jp] : !s64, index -> i64
        %wp:2 = func.call @ds_win(%w, %pe) : (!llvm.ptr, i64) -> (!llvm.ptr, i64)
        %c = func.call @ds_cmp(%wp#0, %wp#1, %we#0, %we#1) : (!llvm.ptr, i64, !llvm.ptr, i64) -> i32
        %eq = arith.cmpi eq, %c, %z32 : i32
        scf.yield %eq : i1
      }
      %dupe = arith.minsi %dup, %e : i64
      %dup2 = arith.select %later, %dupe, %dup : i64
      scf.yield %dup2, %dp2 : i64, i64
    }
    // the insert loop checked a name for a duplicate before drvPath, so a tie goes to the duplicate
    %k = arith.minsi %f#0, %f#1 : i64
    %ok = arith.cmpi eq, %k, %n : i64
    %res = scf.if %ok -> (i64) {
      %od = func.call @ds_desc(%order, %n) : (!llvm.ptr, i64) -> !d
      %om = builtin.unrealized_conversion_cast %od : !d to !m64
      %os = builtin.unrealized_conversion_cast %om : !m64 to !s64
      %end = trikeshed.drain %srt, %om : !s64, !m64 -> index
      scf.yield %z64 : i64
    } else {
      %isdup = arith.cmpi eq, %k, %f#0 : i64
      %two = arith.constant 2 : i64
      %code = arith.select %isdup, %one64, %two : i64
      %k4 = arith.shli %k, %two : i64
      %rr = arith.ori %k4, %code : i64
      scf.yield %rr : i64
    }
    scf.yield %res : i64
  }
  return %r : i64
}

//===----------------------------------------------------------------------===//
// the context elements
//===----------------------------------------------------------------------===//

// store record slot (r * 6 + s)
func.func private @ds_put(%recs: !llvm.ptr, %r: i64, %s: i64, %v: i64) {
  %six = arith.constant 6 : i64
  %r6 = arith.muli %r, %six : i64
  %at = arith.addi %r6, %s : i64
  %q = llvm.getelementptr %recs[%at] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  llvm.store %v, %q : i64, !llvm.ptr
  return
}

func.func @nixev_ts_drv_ctx(%w: !llvm.ptr, %n: i64, %recs: !llvm.ptr) -> i64 {
  %z = arith.constant 0 : index
  %one = arith.constant 1 : index
  %z64 = arith.constant 0 : i64
  %one64 = arith.constant 1 : i64
  %z32 = arith.constant 0 : i32
  %empty = arith.cmpi eq, %n, %z64 : i64
  %r = scf.if %empty -> (i64) {
    scf.yield %z64 : i64
  } else {
    %ni = arith.index_cast %n : i64 to index
    %idx = trikeshed.series %ni : !s64 {
    ^bb0(%q: index):
      %q64 = arith.index_cast %q : index to i64
      trikeshed.yield %q64 : i64
    }
    %srt = trikeshed.sorted %idx : !s64 -> !s64 by {
    ^bb0(%ia: i64, %ib: i64):
      %wa:2 = func.call @ds_win(%w, %ia) : (!llvm.ptr, i64) -> (!llvm.ptr, i64)
      %wb:2 = func.call @ds_win(%w, %ib) : (!llvm.ptr, i64) -> (!llvm.ptr, i64)
      %c = func.call @ds_cmp(%wa#0, %wa#1, %wb#0, %wb#1) : (!llvm.ptr, i64, !llvm.ptr, i64) -> i32
      trikeshed.yield %c : i32
    }
    %cnt = scf.for %j = %z to %ni step %one iter_args(%nr = %z64) -> (i64) {
      %e = trikeshed.at %srt[%j] : !s64, index -> i64
      %we:2 = func.call @ds_win(%w, %e) : (!llvm.ptr, i64) -> (!llvm.ptr, i64)
      %first = arith.cmpi eq, %j, %z : index
      %fresh = scf.if %first -> (i1) {
        %true = arith.constant true
        scf.yield %true : i1
      } else {
        %jp = arith.subi %j, %one : index
        %pe = trikeshed.at %srt[%jp] : !s64, index -> i64
        %wp:2 = func.call @ds_win(%w, %pe) : (!llvm.ptr, i64) -> (!llvm.ptr, i64)
        %c = func.call @ds_cmp(%wp#0, %wp#1, %we#0, %we#1) : (!llvm.ptr, i64, !llvm.ptr, i64) -> i32
        %ne = arith.cmpi ne, %c, %z32 : i32
        scf.yield %ne : i1
      }
      %nr2 = scf.if %fresh -> (i64) {
        %dx = func.call @ds_desc(%we#0, %we#1) : (!llvm.ptr, i64) -> !d
        %mx = builtin.unrealized_conversion_cast %dx : !d to !m
        %x = builtin.unrealized_conversion_cast %mx : !m to !s
        %has = arith.cmpi sgt, %we#1, %z64 : i64
        %c0b = scf.if %has -> (i8) {
          %b0 = trikeshed.at %x[%z] : !s, index -> i8
          scf.yield %b0 : i8
        } else {
          %nul = arith.constant 0 : i8
          scf.yield %nul : i8
        }
        %eqc = arith.constant 61 : i8
        %bang = arith.constant 33 : i8
        %isdrv = arith.cmpi eq, %c0b, %eqc : i8
        %isout = arith.cmpi eq, %c0b, %bang : i8
        // the second '!': part 0 of Series.div at '!' over the bytes after the first; npos when it is the rest
        %rest = arith.subi %we#1, %one64 : i64
        %p = scf.if %isout -> (i64) {
          %more = arith.cmpi sgt, %rest, %z64 : i64
          %pp = scf.if %more -> (i64) {
            %resti = arith.index_cast %rest : i64 to index
            %tail = trikeshed.slice %x[%one, %resti] : !s -> !s
            %ps = trikeshed.parts %tail, %bang : !s, i8 -> !sp
            %p0 = trikeshed.at %ps[%z] : !sp, index -> !tp
            %l = trikeshed.second %p0 : !tp -> i32
            %l64 = arith.extui %l : i32 to i64
            %at = arith.addi %l64, %one64 : i64
            scf.yield %at : i64
          } else {
            scf.yield %we#1 : i64
          }
          scf.yield %pp : i64
        } else {
          scf.yield %we#1 : i64
        }
        %found = arith.cmpi slt, %p, %we#1 : i64
        // kind 1: a = (p + 1, n - p - 1), b = (1, p - 1); no second '!': a = (0, n), b = (1, n - 1)
        %p1 = arith.addi %p, %one64 : i64
        %np1 = arith.subi %we#1, %p1 : i64
        %pm1 = arith.subi %p, %one64 : i64
        %oa = arith.select %found, %p1, %z64 : i64
        %la = arith.select %found, %np1, %we#1 : i64
        %lb = arith.select %found, %pm1, %rest : i64
        %two = arith.constant 2 : i64
        %kind0 = arith.select %isout, %one64, %two : i64
        %kind = arith.select %isdrv, %z64, %kind0 : i64
        // kind 0: a = (1, n - 1); kind 2: a = (0, n)
        %ao1 = arith.select %isout, %oa, %z64 : i64
        %al1 = arith.select %isout, %la, %we#1 : i64
        %ao = arith.select %isdrv, %one64, %ao1 : i64
        %al = arith.select %isdrv, %rest, %al1 : i64
        %bo = arith.select %isout, %one64, %z64 : i64
        %bl = arith.select %isout, %lb, %z64 : i64
        %s0 = arith.constant 0 : i64
        %s2 = arith.constant 2 : i64
        %s3 = arith.constant 3 : i64
        %s4 = arith.constant 4 : i64
        %s5 = arith.constant 5 : i64
        func.call @ds_put(%recs, %nr, %s0, %e) : (!llvm.ptr, i64, i64, i64) -> ()
        func.call @ds_put(%recs, %nr, %one64, %kind) : (!llvm.ptr, i64, i64, i64) -> ()
        func.call @ds_put(%recs, %nr, %s2, %ao) : (!llvm.ptr, i64, i64, i64) -> ()
        func.call @ds_put(%recs, %nr, %s3, %al) : (!llvm.ptr, i64, i64, i64) -> ()
        func.call @ds_put(%recs, %nr, %s4, %bo) : (!llvm.ptr, i64, i64, i64) -> ()
        func.call @ds_put(%recs, %nr, %s5, %bl) : (!llvm.ptr, i64, i64, i64) -> ()
        %nr1 = arith.addi %nr, %one64 : i64
        scf.yield %nr1 : i64
      } else {
        scf.yield %nr : i64
      }
      scf.yield %nr2 : i64
    }
    scf.yield %cnt : i64
  }
  return %r : i64
}

//===----------------------------------------------------------------------===//
// __structuredAttrs' object
//===----------------------------------------------------------------------===//

func.func @nixev_ts_drv_jsonobj(%p: !llvm.ptr, %ends: !llvm.ptr, %k: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %z = arith.constant 0 : index
  %one = arith.constant 1 : index
  %z64 = arith.constant 0 : i64
  %wopen = arith.constant 13 : index
  %wcomma = arith.constant 14 : index
  %wclose = arith.constant 15 : index
  %g = memref.get_global @ds_blob : memref<1350xi8>
  %blob = trikeshed.text %g : memref<1350xi8> -> !s
  %ki = arith.index_cast %k : i64 to index
  %ed = func.call @ds_desc(%ends, %k) : (!llvm.ptr, i64) -> !d
  %em = builtin.unrealized_conversion_cast %ed : !d to !m64
  %es = builtin.unrealized_conversion_cast %em : !m64 to !s64
  // the pieces' bytes: ends[k - 1] of them (none when k is 0)
  %has = arith.cmpi sgt, %ki, %z : index
  %km1 = arith.subi %ki, %one : index
  %lastat = arith.select %has, %km1, %z : index
  %total = scf.if %has -> (i64) {
    %t = trikeshed.at %es[%lastat] : !s64, index -> i64
    scf.yield %t : i64
  } else {
    scf.yield %z64 : i64
  }
  %bd = func.call @ds_desc(%p, %total) : (!llvm.ptr, i64) -> !d
  %bm = builtin.unrealized_conversion_cast %bd : !d to !m
  %bytes = builtin.unrealized_conversion_cast %bm : !m to !s
  %cw:2 = func.call @ds_word(%wcomma) : (index) -> (index, index)
  %all, %co = trikeshed.combineAll %ki : !s, !sp {
  ^bb0(%j: index):
    %first = arith.cmpi eq, %j, %z : index
    %jp = arith.subi %j, %one : index
    %jq = arith.select %first, %z, %jp : index
    %pe = trikeshed.at %es[%jq] : !s64, index -> i64
    %from64 = arith.select %first, %z64, %pe : i64
    %to64 = trikeshed.at %es[%j] : !s64, index -> i64
    %from = arith.index_cast %from64 : i64 to index
    %to = arith.index_cast %to64 : i64 to index
    %len = arith.subi %to, %from : index
    %piece = trikeshed.slice %bytes[%from, %len] : !s -> !s
    %sl = arith.select %first, %z, %cw#1 : index
    %sep = trikeshed.slice %blob[%cw#0, %sl] : !s -> !s
    %row = trikeshed.combine %sep, %piece : !s, !s -> !s
    trikeshed.yield %row : !s
  }
  %ow:2 = func.call @ds_word(%wopen) : (index) -> (index, index)
  %open = trikeshed.slice %blob[%ow#0, %ow#1] : !s -> !s
  %clw:2 = func.call @ds_word(%wclose) : (index) -> (index, index)
  %close = trikeshed.slice %blob[%clw#0, %clw#1] : !s -> !s
  %whole = trikeshed.combine %open, %all, %close : !s, !s, !s -> !s
  %sz = trikeshed.size %whole : !s
  %szi = arith.index_cast %sz : index to i64
  %capi = arith.index_cast %cap : i64 to index
  %fits = arith.cmpi ule, %sz, %capi : index
  scf.if %fits {
    %di = func.call @ds_desc(%into, %cap) : (!llvm.ptr, i64) -> !d
    %mi = builtin.unrealized_conversion_cast %di : !d to !m
    %end = trikeshed.drain %whole, %mi : !s, !m -> index
  }
  return %szi : i64
}
