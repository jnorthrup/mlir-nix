// ConfixIndex.mlir -- the body of the confix dialect's confix.index (Confix.td): a JSON or CBOR text's index as TrikeShed
// hands it out (ConfixIndexK's Spans, Tags and DirectChildren, and the kid series).  trikeshed-lower-cursors lowers the
// op into a call of its function here (ConfixDialect.cpp), so what the op does is written once, in the confix dialect's
// reads of the scan's record and in TrikeShed's ops, and not built op by op by the lowering.
//
//   confix_index(bytes, syntax) -> spans, tags, kids, kid, fault, at
//       the scan (confix.scan, into a record sized for the text), then the rows' columns, each a series over
//       confix.row, and the kid series over confix.kid.  After a fault the series are empty.
//
// A series is its buffer at a function's boundary (memref<?xT, strided<[1], offset: ?>>: trikeshed-lower-cursors), so a
// module that lowers the op calls this by name with the buffers it has, and every result is a buffer of its own, which
// the caller frees.  Lowered by mlnix-opt --trikeshed-lower-cursors --confix-to-llvm (the scan's ops), then the buffer
// pipeline.  Whoever links a module that lowered the op links this: lib/CMakeLists.txt puts it in TrikeShedRuntime with
// the scanner (lib/Confix/confix.ll) for the tests that run a lowered module; utils/mlnixci's Makefile links its LLVM IR
// into the module that calls it.  The rows are numbered in 32 bits and read unsigned, as the scanner writes them.

!text = !trikeshed.series<i8>
!s32 = !trikeshed.series<i32>
!tw = !trikeshed.twin<i32>
!tp = !trikeshed.twinpacked<i32>
!spans = !trikeshed.series<!tw>
!pieces = !trikeshed.series<!tp>
!ix = !trikeshed.cursor<"ConfixIndex", [!tw, i8, !tp]>
!ik = !trikeshed.colkey<"ConfixIndex">
// Confix.td's Flat record (total, fault, at, room, span, tag, depth, start, kid, work) and the CharSeries the scan reads
// (size, data, pos, limit, mark)
!flat = !llvm.struct<(i32, i32, i32, i32, ptr, ptr, ptr, ptr, ptr, ptr)>
!chars = !llvm.struct<(i32, ptr, i32, i32, i32)>

// ---- confix.index

// The record's six arrays are one block of 32-bit words, sized for room = n + 1 rows (a JSON or CBOR text of n bytes has
// at most n): span 2 room, depth room, start room + 1, kid room, work 3 room, then the tags' room bytes.
func.func @confix_index(%bytes: memref<?xi8, strided<[1], offset: ?>>, %syntax: i32) -> (!spans, !text, !pieces, !s32, i32, i32) {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c2 = arith.constant 2 : index
  %c3 = arith.constant 3 : index
  %c4 = arith.constant 4 : index
  %c5 = arith.constant 5 : index
  %c8 = arith.constant 8 : index
  %zero = arith.constant 0 : i32
  %one = arith.constant 1 : i32
  %unset = arith.constant -1 : i32
  %n = memref.dim %bytes, %c0 : memref<?xi8, strided<[1], offset: ?>>
  %room = arith.addi %n, %c1 : index
  %room2 = arith.muli %room, %c2 : index
  %room3 = arith.muli %room, %c3 : index
  %room4 = arith.muli %room, %c4 : index
  %room5 = arith.muli %room, %c5 : index
  %room8 = arith.muli %room, %c8 : index
  %kidAt = arith.addi %room4, %c1 : index
  %workAt = arith.addi %room5, %c1 : index
  %tagAt = arith.addi %room8, %c1 : index
  %tagRoom = arith.addi %room, %c3 : index
  %tagWords = arith.divui %tagRoom, %c4 : index
  %words = arith.addi %tagAt, %tagWords : index
  %block = memref.alloc(%words) : memref<?xi32>
  %blockAt = memref.extract_aligned_pointer_as_index %block : memref<?xi32> -> index
  %blockWord = arith.index_castui %blockAt : index to i64
  %span = llvm.inttoptr %blockWord : i64 to !llvm.ptr
  %depthOff = arith.index_castui %room2 : index to i64
  %startOff = arith.index_castui %room3 : index to i64
  %kidOff = arith.index_castui %kidAt : index to i64
  %workOff = arith.index_castui %workAt : index to i64
  %tagOff = arith.index_castui %tagAt : index to i64
  %depth = llvm.getelementptr %span[%depthOff] : (!llvm.ptr, i64) -> !llvm.ptr, i32
  %start = llvm.getelementptr %span[%startOff] : (!llvm.ptr, i64) -> !llvm.ptr, i32
  %kid = llvm.getelementptr %span[%kidOff] : (!llvm.ptr, i64) -> !llvm.ptr, i32
  %work = llvm.getelementptr %span[%workOff] : (!llvm.ptr, i64) -> !llvm.ptr, i32
  %tag = llvm.getelementptr %span[%tagOff] : (!llvm.ptr, i64) -> !llvm.ptr, i32
  // the record, and the text as the CharSeries the scan reads: its bytes start at its view's offset
  %flat = llvm.alloca %one x !flat : (i32) -> !llvm.ptr
  %chars = llvm.alloca %one x !chars : (i32) -> !llvm.ptr
  %room32 = arith.index_castui %room : index to i32
  %f3 = llvm.getelementptr %flat[0, 3] : (!llvm.ptr) -> !llvm.ptr, !flat
  %f4 = llvm.getelementptr %flat[0, 4] : (!llvm.ptr) -> !llvm.ptr, !flat
  %f5 = llvm.getelementptr %flat[0, 5] : (!llvm.ptr) -> !llvm.ptr, !flat
  %f6 = llvm.getelementptr %flat[0, 6] : (!llvm.ptr) -> !llvm.ptr, !flat
  %f7 = llvm.getelementptr %flat[0, 7] : (!llvm.ptr) -> !llvm.ptr, !flat
  %f8 = llvm.getelementptr %flat[0, 8] : (!llvm.ptr) -> !llvm.ptr, !flat
  %f9 = llvm.getelementptr %flat[0, 9] : (!llvm.ptr) -> !llvm.ptr, !flat
  llvm.store %room32, %f3 : i32, !llvm.ptr
  llvm.store %span, %f4 : !llvm.ptr, !llvm.ptr
  llvm.store %tag, %f5 : !llvm.ptr, !llvm.ptr
  llvm.store %depth, %f6 : !llvm.ptr, !llvm.ptr
  llvm.store %start, %f7 : !llvm.ptr, !llvm.ptr
  llvm.store %kid, %f8 : !llvm.ptr, !llvm.ptr
  llvm.store %work, %f9 : !llvm.ptr, !llvm.ptr
  %base, %offset, %size, %stride = memref.extract_strided_metadata %bytes : memref<?xi8, strided<[1], offset: ?>> -> memref<i8>, index, index, index
  %bytesAt = memref.extract_aligned_pointer_as_index %bytes : memref<?xi8, strided<[1], offset: ?>> -> index
  %firstAt = arith.addi %bytesAt, %offset : index
  %firstWord = arith.index_castui %firstAt : index to i64
  %data = llvm.inttoptr %firstWord : i64 to !llvm.ptr
  %n32 = arith.index_castui %n : index to i32
  %s0 = llvm.getelementptr %chars[0, 0] : (!llvm.ptr) -> !llvm.ptr, !chars
  %s1 = llvm.getelementptr %chars[0, 1] : (!llvm.ptr) -> !llvm.ptr, !chars
  %s2 = llvm.getelementptr %chars[0, 2] : (!llvm.ptr) -> !llvm.ptr, !chars
  %s3 = llvm.getelementptr %chars[0, 3] : (!llvm.ptr) -> !llvm.ptr, !chars
  %s4 = llvm.getelementptr %chars[0, 4] : (!llvm.ptr) -> !llvm.ptr, !chars
  llvm.store %n32, %s0 : i32, !llvm.ptr
  llvm.store %data, %s1 : !llvm.ptr, !llvm.ptr
  llvm.store %zero, %s2 : i32, !llvm.ptr
  llvm.store %n32, %s3 : i32, !llvm.ptr
  llvm.store %unset, %s4 : i32, !llvm.ptr
  %json = arith.cmpi eq, %syntax, %zero : i32
  %fault, %at = scf.if %json -> (i32, i32) {
    %f, %a = confix.scan json %chars into %flat : !llvm.ptr, !llvm.ptr
    scf.yield %f, %a : i32, i32
  } else {
    %f, %a = confix.scan cbor %chars into %flat : !llvm.ptr, !llvm.ptr
    scf.yield %f, %a : i32, i32
  }
  %total = confix.size %flat : !llvm.ptr
  %ok = arith.cmpi eq, %fault, %zero : i32
  %found = arith.index_castui %total : i32 to index
  %rows = arith.select %ok, %found, %c0 : index
  // Spans (open, close), Tags, and DirectChildren as (first, count) into the kids
  %spans = trikeshed.series %rows : !spans {
  ^bb0(%r: index):
    %k = arith.index_cast %r : index to i32
    %open, %close, %t, %d, %first, %count = confix.row %flat[%k] : !llvm.ptr
    %s = trikeshed.j %open, %close : i32, i32 -> !tw
    trikeshed.yield %s : !tw
  }
  %tags = trikeshed.series %rows : !text {
  ^bb0(%r: index):
    %k = arith.index_cast %r : index to i32
    %open, %close, %t, %d, %first, %count = confix.row %flat[%k] : !llvm.ptr
    %t8 = arith.trunci %t : i32 to i8
    trikeshed.yield %t8 : i8
  }
  %kids = trikeshed.series %rows : !pieces {
  ^bb0(%r: index):
    %k = arith.index_cast %r : index to i32
    %open, %close, %t, %d, %first, %count = confix.row %flat[%k] : !llvm.ptr
    %p = trikeshed.j %first, %count : i32, i32 -> !tp
    trikeshed.yield %p : !tp
  }
  // the kid series: every row but the root, as many as where the last row's children end
  %some = arith.cmpi ne, %rows, %c0 : index
  %nk = scf.if %some -> (index) {
    %last = arith.subi %rows, %c1 : index
    %k = arith.index_cast %last : index to i32
    %open, %close, %t, %d, %first, %count = confix.row %flat[%k] : !llvm.ptr
    %end = arith.addi %first, %count : i32
    %e = arith.index_castui %end : i32 to index
    scf.yield %e : index
  } else {
    scf.yield %c0 : index
  }
  %kid_series = trikeshed.series %nk : !s32 {
  ^bb0(%i: index):
    %k = arith.index_cast %i : index to i32
    %row = confix.kid %flat[%k] : !llvm.ptr
    trikeshed.yield %row : i32
  }
  return %spans, %tags, %kids, %kid_series, %fault, %at : !spans, !text, !pieces, !s32, i32, i32
}
