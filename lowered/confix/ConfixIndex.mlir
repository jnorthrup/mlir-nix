// ConfixIndex.mlir -- the bodies of the confix dialect's confix.index, confix.columns and confix.unescape (Confix.td):
// a JSON or CBOR text's index as TrikeShed hands it out (ConfixIndexK's Spans, Tags and DirectChildren, and the kid
// series), its Columns facet (ConfixColumns.kt), and a string's value (KnownSchema.decodeEscaped).  trikeshed-lower-cursors
// lowers each of the three ops into a call of its function here (ConfixDialect.cpp), so what the ops do is written once,
// in the confix dialect's reads of the scan's record and in TrikeShed's ops, and not built op by op by the lowering.
//
//   confix_index(bytes, syntax) -> spans, tags, kids, kid, fault, at
//       the scan (confix.scan, into a record sized for the text), then the rows' columns, each a series over
//       confix.row, and the kid series over confix.kid.  After a fault the series are empty.
//   confix_columns(rows, kids, text, objects, names, at) -> table
//       ConfixColumns.kt's slots, a column after the other: cell c * size(objects) + r is the row of the value of the
//       member of objects[r] whose key is written as name c (names[at[c]]: the names are one text and each one's
//       (start, length) in it), the last such member's, or -1.
//   confix_column(table, width, c) -> column
//       column c of that table as cells of its own: a cursor's column, which whoever holds the cursor frees.
//   confix_unescape(text) -> value
//       one walk over the text: the bytes between two escapes are a slice drained into the value's cells (sized for the
//       text: no value is longer), an escape's value is written after it.
//
// A series is its buffer at a function's boundary (memref<?xT, strided<[1], offset: ?>>: trikeshed-lower-cursors), so a
// module that lowers one of the ops calls these by name with the buffers it has; every result is a buffer of its own,
// which the caller frees (confix_unescape's is the first cells of one).  Built by lib/CMakeLists.txt into TrikeShedRuntime
// with the scanner (lib/Confix/confix.ll) for the tests that run a lowered module, and by utils/mlnixci's Makefile:
// mlnix-opt --trikeshed-lower-cursors --confix-to-llvm, then the buffer pipeline.  The rows are numbered in 32 bits and
// read unsigned, as the scanner writes them.

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

// what a backslash and a byte name in JSON (\" \\ \/ \b \f \n \r \t), 0 where they name nothing; a hex digit's value,
// 16 where the byte is not one
memref.global "private" constant @confix_named : memref<256xi8> = dense<"0x00000000000000000000000000000000000000000000000000000000000000000000220000000000000000000000002F00000000000000000000000000000000000000000000000000000000000000000000000000000000000000005C0000000000080000000C000000000000000A0000000D000900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000">
memref.global "private" constant @confix_hex : memref<256xi8> = dense<"0x10101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101000010203040506070809101010101010100A0B0C0D0E0F10101010101010101010101010101010101010101010101010100A0B0C0D0E0F101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010">

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

// ---- confix.columns

func.func @confix_columns(%rows: !ix, %kids: !s32, %text: !text, %objects: !s32, %names: !text, %at: !pieces) -> !s32 {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c2 = arith.constant 2 : index
  %zero = arith.constant 0 : i32
  %none = arith.constant -1 : i32
  %one64 = arith.constant 1 : i64
  %string = arith.constant 4 : i8
  %object = arith.constant 5 : i8
  %k0 = trikeshed.key 0 : !ik
  %k1 = trikeshed.key 1 : !ik
  %k2 = trikeshed.key 2 : !ik
  %spans = trikeshed.column %rows[%k0] : !ix, !ik -> !spans
  %tags = trikeshed.column %rows[%k1] : !ix, !ik -> !text
  %children = trikeshed.column %rows[%k2] : !ix, !ik -> !pieces
  %m = trikeshed.size %objects : !s32
  %width = trikeshed.size %at : !pieces
  %cells = arith.muli %m, %width : index
  %slots = memref.alloc(%cells) : memref<?xi32>
  scf.for %i = %c0 to %cells step %c1 {
    memref.store %none, %slots[%i] : memref<?xi32>
  }
  scf.for %r = %c0 to %m step %c1 {
    %obj32 = trikeshed.at %objects[%r] : !s32, index -> i32
    %obj = arith.index_castui %obj32 : i32 to index
    %tag = trikeshed.at %tags[%obj] : !text, index -> i8
    %isObject = arith.cmpi eq, %tag, %object : i8
    scf.if %isObject {
      // its members: a key and a value, alternating (a key with no value after it is none)
      %fc = trikeshed.at %children[%obj] : !pieces, index -> !tp
      %first32 = trikeshed.first %fc : !tp -> i32
      %count32 = trikeshed.second %fc : !tp -> i32
      %first = arith.index_castui %first32 : i32 to index
      %count = arith.index_castui %count32 : i32 to index
      %members = arith.divui %count, %c2 : index
      scf.for %j = %c0 to %members step %c1 {
        %j2 = arith.muli %j, %c2 : index
        %keyAt = arith.addi %first, %j2 : index
        %valueAt = arith.addi %keyAt, %c1 : index
        %key32 = trikeshed.at %kids[%keyAt] : !s32, index -> i32
        %value = trikeshed.at %kids[%valueAt] : !s32, index -> i32
        %key = arith.index_castui %key32 : i32 to index
        %keyTag = trikeshed.at %tags[%key] : !text, index -> i8
        %isString = arith.cmpi eq, %keyTag, %string : i8
        scf.if %isString {
          // the key as written, between its quotes: [open + 1, close); in 64 bits, so that a string cut short at the
          // text's end (close = open) has the length -1, which is no name's
          %span = trikeshed.at %spans[%key] : !spans, index -> !tw
          %open32 = trikeshed.first %span : !tw -> i32
          %close32 = trikeshed.second %span : !tw -> i32
          %open = arith.extui %open32 : i32 to i64
          %close = arith.extui %close32 : i32 to i64
          %inner = arith.addi %open, %one64 : i64
          %len = arith.subi %close, %inner : i64
          scf.for %c = %c0 to %width step %c1 {
            %piece = trikeshed.at %at[%c] : !pieces, index -> !tp
            %size32 = trikeshed.second %piece : !tp -> i32
            %size = arith.extui %size32 : i32 to i64
            %sized = arith.cmpi eq, %len, %size : i64
            scf.if %sized {
              %from32 = trikeshed.first %piece : !tp -> i32
              %from = arith.index_castui %from32 : i32 to index
              %innerAt = arith.index_castui %inner : i64 to index
              %n = arith.index_castui %len : i64 to index
              %written = trikeshed.slice %text[%innerAt, %n] : !text -> !text
              %name = trikeshed.slice %names[%from, %n] : !text -> !text
              %order = trikeshed.compare %written, %name : !text, !text
              %same = arith.cmpi eq, %order, %zero : i32
              scf.if %same {
                %column = arith.muli %c, %m : index
                %cell = arith.addi %column, %r : index
                memref.store %value, %slots[%cell] : memref<?xi32>
              }
            }
          }
        }
      }
    }
  }
  %table = trikeshed.text %slots : memref<?xi32> -> !s32
  return %table : !s32
}

func.func @confix_column(%table: !s32, %width: index, %c: index) -> !s32 {
  %all = trikeshed.size %table : !s32
  %m = arith.divui %all, %width : index
  %from = arith.muli %c, %m : index
  %run = trikeshed.slice %table[%from, %m] : !s32 -> !s32
  %cells = memref.alloc(%m) : memref<?xi32>
  %end = trikeshed.drain %run, %cells : !s32, memref<?xi32> -> index
  %column = trikeshed.text %cells : memref<?xi32> -> !s32
  return %column : !s32
}

// ---- confix.unescape

// four hex digits from p on: (their value, 16 or more when one of them is not a hex digit)
func.func private @confix_hex4(%text: !text, %p: index) -> !tp {
  %c4 = arith.constant 4 : index
  %zero = arith.constant 0 : i32
  %four = arith.constant 4 : i32
  %low = arith.constant 15 : i32
  %table = memref.get_global @confix_hex : memref<256xi8>
  %hex = trikeshed.text %table : memref<256xi8> -> !text
  %digits = trikeshed.slice %text[%p, %c4] : !text -> !text
  %none = trikeshed.j %zero, %zero : i32, i32 -> !tp
  %read = trikeshed.fold %digits, %none : !text, !tp -> !tp {
  ^bb0(%acc: !tp, %b: i8):
    %u = trikeshed.first %acc : !tp -> i32
    %bad = trikeshed.second %acc : !tp -> i32
    %b32 = arith.extui %b : i8 to i32
    %d8 = trikeshed.at %hex[%b32] : !text, i32 -> i8
    %d = arith.extui %d8 : i8 to i32
    %shifted = arith.shli %u, %four : i32
    %digit = arith.andi %d, %low : i32
    %u2 = arith.ori %shifted, %digit : i32
    %bad2 = arith.ori %bad, %d : i32
    %next = trikeshed.j %u2, %bad2 : i32, i32 -> !tp
    trikeshed.yield %next : !tp
  }
  return %read : !tp
}

// i is the byte read, w the next free cell, run where the bytes not yet written begin: the bytes of [run, i) are
// themselves, and are drained when an escape ends them or the text does.  A backslash that begins none of JSON's escapes
// is kept as written: it begins the next run.
func.func @confix_unescape(%text: !text) -> !text {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c2 = arith.constant 2 : index
  %c3 = arith.constant 3 : index
  %c6 = arith.constant 6 : index
  %zero8 = arith.constant 0 : i8
  %backslash = arith.constant 92 : i8
  %letterU = arith.constant 117 : i8
  %bad16 = arith.constant 16 : i32
  %n = trikeshed.size %text : !text
  %cells = memref.alloc(%n) : memref<?xi8>
  %table = memref.get_global @confix_named : memref<256xi8>
  %named = trikeshed.text %table : memref<256xi8> -> !text
  %iEnd, %wEnd, %runEnd = scf.while (%i = %c0, %w = %c0, %run = %c0) : (index, index, index) -> (index, index, index) {
    %going = arith.cmpi ult, %i, %n : index
    scf.condition(%going) %i, %w, %run : index, index, index
  } do {
  ^bb0(%i: index, %w: index, %run: index):
    %x = trikeshed.at %text[%i] : !text, index -> i8
    %i1 = arith.addi %i, %c1 : index
    %isBackslash = arith.cmpi eq, %x, %backslash : i8
    %more = arith.cmpi ult, %i1, %n : index
    %escape = arith.andi %isBackslash, %more : i1
    %i2, %w2, %run2 = scf.if %escape -> (index, index, index) {
      // the run before the backslash
      %len = arith.subi %i, %run : index
      %some = arith.cmpi ne, %len, %c0 : index
      scf.if %some {
        %bytes = trikeshed.slice %text[%run, %len] : !text -> !text
        %room = memref.subview %cells[%w] [%len] [1] : memref<?xi8> to memref<?xi8, strided<[1], offset: ?>>
        %end = trikeshed.drain %bytes, %room : !text, memref<?xi8, strided<[1], offset: ?>> -> index
      }
      %wr = arith.addi %w, %len : index
      %y = trikeshed.at %text[%i1] : !text, index -> i8
      %y32 = arith.extui %y : i8 to i32
      %name = trikeshed.at %named[%y32] : !text, i32 -> i8
      %simple = arith.cmpi ne, %name, %zero8 : i8
      %i3, %w3, %run3 = scf.if %simple -> (index, index, index) {
        // \" \\ \/ \b \f \n \r \t: the byte each names
        memref.store %name, %cells[%wr] : memref<?xi8>
        %ie = arith.addi %i, %c2 : index
        %we = arith.addi %wr, %c1 : index
        scf.yield %ie, %we, %ie : index, index, index
      } else {
        // \uXXXX, its four digits within the text
        %isU = arith.cmpi eq, %y, %letterU : i8
        %i6 = arith.addi %i, %c6 : index
        %fits = arith.cmpi ule, %i6, %n : index
        %maybeU = arith.andi %isU, %fits : i1
        %i4, %w4, %run4 = scf.if %maybeU -> (index, index, index) {
          %p = arith.addi %i, %c2 : index
          %h = func.call @confix_hex4(%text, %p) : (!text, index) -> !tp
          %u = trikeshed.first %h : !tp -> i32
          %bad = trikeshed.second %h : !tp -> i32
          %isHex = arith.cmpi ult, %bad, %bad16 : i32
          %i5, %w5, %run5 = scf.if %isHex -> (index, index, index) {
            %cp, %used = func.call @confix_point(%text, %i, %u) : (!text, index, i32) -> (i32, index)
            %b0, %b1, %b2, %b3, %wide = func.call @confix_utf8(%cp) : (i32) -> (i8, i8, i8, i8, index)
            // four cells written (wr + 3 < i + 6 <= n), the first `wide` of them the value
            %wr1 = arith.addi %wr, %c1 : index
            %wr2 = arith.addi %wr, %c2 : index
            %wr3 = arith.addi %wr, %c3 : index
            memref.store %b0, %cells[%wr] : memref<?xi8>
            memref.store %b1, %cells[%wr1] : memref<?xi8>
            memref.store %b2, %cells[%wr2] : memref<?xi8>
            memref.store %b3, %cells[%wr3] : memref<?xi8>
            %ie = arith.addi %i, %used : index
            %we = arith.addi %wr, %wide : index
            scf.yield %ie, %we, %ie : index, index, index
          } else {
            scf.yield %i1, %wr, %i : index, index, index
          }
          scf.yield %i5, %w5, %run5 : index, index, index
        } else {
          scf.yield %i1, %wr, %i : index, index, index
        }
        scf.yield %i4, %w4, %run4 : index, index, index
      }
      scf.yield %i3, %w3, %run3 : index, index, index
    } else {
      scf.yield %i1, %w, %run : index, index, index
    }
    scf.yield %i2, %w2, %run2 : index, index, index
  }
  // the last run
  %tail = arith.subi %n, %runEnd : index
  %left = arith.cmpi ne, %tail, %c0 : index
  scf.if %left {
    %bytes = trikeshed.slice %text[%runEnd, %tail] : !text -> !text
    %room = memref.subview %cells[%wEnd] [%tail] [1] : memref<?xi8> to memref<?xi8, strided<[1], offset: ?>>
    %end = trikeshed.drain %bytes, %room : !text, memref<?xi8, strided<[1], offset: ?>> -> index
  }
  %size = arith.addi %wEnd, %tail : index
  %all = trikeshed.text %cells : memref<?xi8> -> !text
  %value = trikeshed.slice %all[%c0, %size] : !text -> !text
  return %value : !text
}

// The code point of the \uXXXX at i, whose digits are u, and how many bytes of the text it is: a high surrogate followed
// by \u and a low one is one code point (12 bytes); any other surrogate is U+FFFD.
func.func private @confix_point(%text: !text, %i: index, %u: i32) -> (i32, index) {
  %c6 = arith.constant 6 : index
  %c7 = arith.constant 7 : index
  %c8 = arith.constant 8 : index
  %c12 = arith.constant 12 : index
  %backslash = arith.constant 92 : i8
  %letterU = arith.constant 117 : i8
  %bad16 = arith.constant 16 : i32
  %ten = arith.constant 10 : i32
  %highFrom = arith.constant 55296 : i32   // 0xD800
  %lowFrom = arith.constant 56320 : i32    // 0xDC00
  %lowTo = arith.constant 57344 : i32      // 0xE000
  %plane = arith.constant 65536 : i32      // 0x10000
  %replacement = arith.constant 65533 : i32  // 0xFFFD
  %n = trikeshed.size %text : !text
  %geHigh = arith.cmpi uge, %u, %highFrom : i32
  %ltLow = arith.cmpi ult, %u, %lowFrom : i32
  %ltEnd = arith.cmpi ult, %u, %lowTo : i32
  %high = arith.andi %geHigh, %ltLow : i1
  %surrogate = arith.andi %geHigh, %ltEnd : i1
  %i12 = arith.addi %i, %c12 : index
  %room = arith.cmpi ule, %i12, %n : index
  %both = arith.andi %high, %room : i1
  %cp, %used = scf.if %both -> (i32, index) {
    %i6 = arith.addi %i, %c6 : index
    %i7 = arith.addi %i, %c7 : index
    %i8 = arith.addi %i, %c8 : index
    %b6 = trikeshed.at %text[%i6] : !text, index -> i8
    %b7 = trikeshed.at %text[%i7] : !text, index -> i8
    %isBackslash = arith.cmpi eq, %b6, %backslash : i8
    %isU = arith.cmpi eq, %b7, %letterU : i8
    %h = func.call @confix_hex4(%text, %i8) : (!text, index) -> !tp
    %v = trikeshed.first %h : !tp -> i32
    %bad = trikeshed.second %h : !tp -> i32
    %isHex = arith.cmpi ult, %bad, %bad16 : i32
    %vGe = arith.cmpi uge, %v, %lowFrom : i32
    %vLt = arith.cmpi ult, %v, %lowTo : i32
    %escaped = arith.andi %isBackslash, %isU : i1
    %low = arith.andi %vGe, %vLt : i1
    %read = arith.andi %isHex, %low : i1
    %pair = arith.andi %escaped, %read : i1
    %top = arith.subi %u, %highFrom : i32
    %topBits = arith.shli %top, %ten : i32
    %bottom = arith.subi %v, %lowFrom : i32
    %upper = arith.addi %plane, %topBits : i32
    %point = arith.addi %upper, %bottom : i32
    %cp1 = arith.select %pair, %point, %replacement : i32
    %used1 = arith.select %pair, %c12, %c6 : index
    scf.yield %cp1, %used1 : i32, index
  } else {
    %cp2 = arith.select %surrogate, %replacement, %u : i32
    scf.yield %cp2, %c6 : i32, index
  }
  return %cp, %used : i32, index
}

// A code point in UTF-8: its four bytes' cells and how many of them it is (the cells past that are not its value).
func.func private @confix_utf8(%cp: i32) -> (i8, i8, i8, i8, index) {
  %c1 = arith.constant 1 : index
  %c2 = arith.constant 2 : index
  %c3 = arith.constant 3 : index
  %s6 = arith.constant 6 : i32
  %s12 = arith.constant 12 : i32
  %s18 = arith.constant 18 : i32
  %from2 = arith.constant 128 : i32      // 0x80
  %from3 = arith.constant 2048 : i32     // 0x800
  %from4 = arith.constant 65536 : i32    // 0x10000
  %six = arith.constant 63 : i32         // 0x3F
  %lead2 = arith.constant 192 : i32      // 0xC0
  %lead3 = arith.constant 224 : i32      // 0xE0
  %lead4 = arith.constant 240 : i32      // 0xF0
  %ge2 = arith.cmpi uge, %cp, %from2 : i32
  %ge3 = arith.cmpi uge, %cp, %from3 : i32
  %ge4 = arith.cmpi uge, %cp, %from4 : i32
  %n2 = arith.extui %ge2 : i1 to i32
  %n3 = arith.extui %ge3 : i1 to i32
  %n4 = arith.extui %ge4 : i1 to i32
  %n23 = arith.addi %n2, %n3 : i32
  %more = arith.addi %n23, %n4 : i32
  %moreAt = arith.index_castui %more : i32 to index
  %size = arith.addi %moreAt, %c1 : index
  %is1 = arith.cmpi eq, %size, %c1 : index
  %is2 = arith.cmpi eq, %size, %c2 : index
  %is3 = arith.cmpi eq, %size, %c3 : index
  %r6 = arith.shrui %cp, %s6 : i32
  %r12 = arith.shrui %cp, %s12 : i32
  %r18 = arith.shrui %cp, %s18 : i32
  %m0 = arith.andi %cp, %six : i32
  %m6 = arith.andi %r6, %six : i32
  %m12 = arith.andi %r12, %six : i32
  %t0 = arith.ori %from2, %m0 : i32
  %t6 = arith.ori %from2, %m6 : i32
  %t12 = arith.ori %from2, %m12 : i32
  %l2 = arith.ori %lead2, %r6 : i32
  %l3 = arith.ori %lead3, %r12 : i32
  %l4 = arith.ori %lead4, %r18 : i32
  %a34 = arith.select %is3, %l3, %l4 : i32
  %a234 = arith.select %is2, %l2, %a34 : i32
  %a = arith.select %is1, %cp, %a234 : i32
  %b34 = arith.select %is3, %t6, %t12 : i32
  %b = arith.select %is2, %t0, %b34 : i32
  %c = arith.select %is3, %t0, %t6 : i32
  %b0 = arith.trunci %a : i32 to i8
  %b1 = arith.trunci %b : i32 to i8
  %b2 = arith.trunci %c : i32 to i8
  %b3 = arith.trunci %t0 : i32 to i8
  return %b0, %b1, %b2, %b3, %size : i8, i8, i8, i8, index
}
