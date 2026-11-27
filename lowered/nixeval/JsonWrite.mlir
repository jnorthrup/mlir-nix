// builtins.toJSON's writer: lib/Eval/Formats.cpp's printValueAsJSON, whole, as a single-pass fill and one drain.
//
// The walk of the value is here: the depth guard, when a cell is forced, a set's members in the byte order of their
// names, the brackets and the separators, a string's escapes, an integer's digits and a float's text.
//
// The fill.  The text is written once, a piece at a time, where it will stand: each piece is drained into the fill's
// open cells (4096 bytes in the entry's frame), and when those are full they become the next rows of a lane
// (!trikeshed.lane<i8>: a MutableSeries in LaneTrie's shape, pages that never move and are never copied again).
// The drain.  When the walk ends the text is the lane (the open cells' fill its last rows), or, when it never left
// them, the open cells: the bridge is asked ONCE for room of exactly its size (nixev_jw_room) and it is drained into
// that, one drain.  Nothing is measured first, and nothing is written into a buffer that grows.
// The plan.  A set's members are written in the order of their layout (the names' symbols as the Bindings holds
// them), which is the same for every set of those names: a second lane (the plan, !trikeshed.lane<i64>) keeps each
// layout's order, taken once by trikeshed.sorted, behind a cell that trikeshed.anchor mints for the layout's first
// set.  A list of a hundred thousand records sorts their names once.
//
// The evaluator stays lib/Eval/Formats.cpp's, as callbacks on ctx (its JsonWalk): forcing a cell, a string's context
// and its UTF-8 check, a path's copy to the store, a set's __toString and outPath, a name's bytes and position, and
// the words of the errors.  No callback throws through these frames: one that fails keeps its error and answers so,
// the walk returns at once through every open set and list, each adding its trace (nixev_jw_trace: "while evaluating
// attribute 'a'", "... list element at index i", innermost first, as the catch blocks did), the lanes' pages go back,
// and the bridge throws the error again.  The depth of the walk is the evaluator's own count (EvalState::callDepth,
// through `depth`): one more for each value while it is written, as CallDepth counted it, so a cell forced from here
// meets the limit where it met it before.
//
//   nixev_ts_json(ctx, v, pos, depth, limit, flags) -> 0, or 1 with the error in ctx
//     flags: 1 strict (force every cell; else a cell not yet a value prints null), 2 every cell goes through forceCell
//     (an MLNIX_STATS run), 4 paths are copied to the store.
//
// A Value is three words (Eval.h): the tag in word 0's low byte and the count (a string's or path's bytes, a list's
// cells) in its high half; word 1 the integer, the float's bits, the boolean's byte, the bytes' address, the Bindings or
// the cells.  A Bindings is a count (word 0's low half), then from word 2 a row of two words a member: the name's symbol
// in the first's low half, the value's cell in the second.  They are read as word views (trikeshed.at), never by offset.
// The escape table is Nix's (PrintOps.mlir's, copied by the generator: \b \f \n \r \t, \u00xx for the other control bytes).
// The tables below (@jw_esc and @jw_esc_len, copied from PrintOps.mlir's @jesc and @jesc_len; @jw_pow; @jw_ids) are
// written in place by the trikeshed-mlir-nix-workspace skill's scripts/jsonwrite/jsonwrite-gen.py (`jsonwrite-gen.py REPO`,
// `--check` to compare only); everything else in this file is the source.
// Lowered by --trikeshed-lower-cursors and the stock buffer pipeline (lib/CMakeLists.txt mlnix_lower_trikeshed).  The
// helpers are internal to the object (llvm.linkage on a func.func survives convert-func-to-llvm): the walk recurses
// through them, and LLVM passes only the cells of the lanes that are read (a count's and a column's address each).
!text = !trikeshed.series<i8>
!s64 = !trikeshed.series<i64>
!bytes = !trikeshed.lane<i8>
!plan = !trikeshed.lane<i64>
!m8 = memref<?xi8, strided<[1], offset: ?>>
!m32 = memref<?xi32, strided<[1], offset: ?>>
!m64 = memref<?xi64, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

// true false null: 0/4, 4/5, 9/4
memref.global "private" constant @jw_words : memref<13xi8> = dense<"0x7472756566616c73656e756c6c">
// byte b's escape at 6 b, its length at b
memref.global "private" constant @jw_esc : memref<1536xi8> = dense<"0x5c75303030305c75303030315c75303030325c75303030335c75303030345c75303030355c75303030365c75303030375c62000000005c74000000005c6e000000005c75303030625c66000000005c72000000005c75303030655c75303030665c75303031305c75303031315c75303031325c75303031335c75303031345c75303031355c75303031365c75303031375c75303031385c75303031395c75303031615c75303031625c75303031635c75303031645c75303031655c75303031662000000000002100000000005c22000000002300000000002400000000002500000000002600000000002700000000002800000000002900000000002a00000000002b00000000002c00000000002d00000000002e00000000002f00000000003000000000003100000000003200000000003300000000003400000000003500000000003600000000003700000000003800000000003900000000003a00000000003b00000000003c00000000003d00000000003e00000000003f00000000004000000000004100000000004200000000004300000000004400000000004500000000004600000000004700000000004800000000004900000000004a00000000004b00000000004c00000000004d00000000004e00000000004f00000000005000000000005100000000005200000000005300000000005400000000005500000000005600000000005700000000005800000000005900000000005a00000000005b00000000005c5c000000005d00000000005e00000000005f00000000006000000000006100000000006200000000006300000000006400000000006500000000006600000000006700000000006800000000006900000000006a00000000006b00000000006c00000000006d00000000006e00000000006f00000000007000000000007100000000007200000000007300000000007400000000007500000000007600000000007700000000007800000000007900000000007a00000000007b00000000007c00000000007d00000000007e00000000007f00000000008000000000008100000000008200000000008300000000008400000000008500000000008600000000008700000000008800000000008900000000008a00000000008b00000000008c00000000008d00000000008e00000000008f00000000009000000000009100000000009200000000009300000000009400000000009500000000009600000000009700000000009800000000009900000000009a00000000009b00000000009c00000000009d00000000009e00000000009f0000000000a00000000000a10000000000a20000000000a30000000000a40000000000a50000000000a60000000000a70000000000a80000000000a90000000000aa0000000000ab0000000000ac0000000000ad0000000000ae0000000000af0000000000b00000000000b10000000000b20000000000b30000000000b40000000000b50000000000b60000000000b70000000000b80000000000b90000000000ba0000000000bb0000000000bc0000000000bd0000000000be0000000000bf0000000000c00000000000c10000000000c20000000000c30000000000c40000000000c50000000000c60000000000c70000000000c80000000000c90000000000ca0000000000cb0000000000cc0000000000cd0000000000ce0000000000cf0000000000d00000000000d10000000000d20000000000d30000000000d40000000000d50000000000d60000000000d70000000000d80000000000d90000000000da0000000000db0000000000dc0000000000dd0000000000de0000000000df0000000000e00000000000e10000000000e20000000000e30000000000e40000000000e50000000000e60000000000e70000000000e80000000000e90000000000ea0000000000eb0000000000ec0000000000ed0000000000ee0000000000ef0000000000f00000000000f10000000000f20000000000f30000000000f40000000000f50000000000f60000000000f70000000000f80000000000f90000000000fa0000000000fb0000000000fc0000000000fd0000000000fe0000000000ff0000000000">
memref.global "private" constant @jw_esc_len : memref<256xi8> = dense<"0x06060606060606060202020602020606060606060606060606060606060606060101020101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010201010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101">
// a negative integer's sign
memref.global "private" constant @jw_minus : memref<1xi8> = dense<45>
// the powers of ten, 10^0 .. 10^18
memref.global "private" constant @jw_pow : memref<19xi64> = dense<[1, 10, 100, 1000, 10000, 100000, 1000000, 10000000, 100000000, 1000000000, 10000000000, 100000000000, 1000000000000, 10000000000000, 100000000000000, 1000000000000000, 10000000000000000, 100000000000000000, 1000000000000000000]>
// the rows as they lie, 0 .. 255 (a slice of it is a set's rows); the plan's 64 cells, none forced
memref.global "private" constant @jw_ids : memref<256xi64> = dense<[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244, 245, 246, 247, 248, 249, 250, 251, 252, 253, 254, 255]>
memref.global "private" constant @jw_none : memref<64xi64> = dense<0>

// the evaluator (Formats.cpp).  force, string, path: 0, or 1 with the error kept.  attrs: 1 the set's __toString text
// (slot: its bytes, their count), 2 its outPath (slot: the value, its position), 0 its members, -1 an error kept.
// syms: the symbol table's prefix words and names (slot), good until a cell is forced.  row: a member's name (slot: its
// bytes, their count) and its position.  fail: the error of a value that is no JSON (v), or of the depth (v null); 1.
// trace: the open set's member (a) or the open list's index is added to the error kept.  room: n bytes of the text.
func.func private @nixev_jw_force(!llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
func.func private @nixev_jw_string(!llvm.ptr, !llvm.ptr) -> i64
func.func private @nixev_jw_path(!llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
func.func private @nixev_jw_attrs(!llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
func.func private @nixev_jw_syms(!llvm.ptr, !llvm.ptr)
func.func private @nixev_jw_row(!llvm.ptr, !llvm.ptr, !llvm.ptr) -> !llvm.ptr
func.func private @nixev_jw_fail(!llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
func.func private @nixev_jw_trace(!llvm.ptr, !llvm.ptr, i64, !llvm.ptr)
func.func private @nixev_jw_room(!llvm.ptr, i64) -> !llvm.ptr
// JsonFloat.mlir: d's text into 32 bytes (a 64-byte buffer for snprintf)
func.func private @nixstore_ts_jsonfloat(f64, !llvm.ptr, !llvm.ptr) -> i64

// the descriptor of n cells at p (a struct, not a memref: returning it allocates nothing and clones nothing); the
// cells' type is the cast's, where it is used
func.func private @jw_desc(%p: !llvm.ptr, %n: i64) -> !d attributes { llvm.linkage = #llvm.linkage<internal> } {
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

// ---- the walk's own words (w, ten of them in the entry's frame):
//   0 the fill: the bytes in the open cells      1 ctx                  2 the open cells' address
//   3 the depth's address (EvalState::callDepth) 4 the depth's limit    5 the flags
//   6 the float's snprintf buffer                8, 9 the slot a callback answers in
func.func private @jw_w(%wp: !llvm.ptr, %k: index) -> i64 attributes { llvm.linkage = #llvm.linkage<internal> } {
  %c10 = arith.constant 10 : i64
  %d = func.call @jw_desc(%wp, %c10) : (!llvm.ptr, i64) -> !d
  %m = builtin.unrealized_conversion_cast %d : !d to !m64
  %s = builtin.unrealized_conversion_cast %m : !m64 to !s64
  %x = trikeshed.at %s[%k] : !s64, index -> i64
  return %x : i64
}

func.func private @jw_p(%wp: !llvm.ptr, %k: index) -> !llvm.ptr attributes { llvm.linkage = #llvm.linkage<internal> } {
  %x = func.call @jw_w(%wp, %k) : (!llvm.ptr, index) -> i64
  %p = llvm.inttoptr %x : i64 to !llvm.ptr
  return %p : !llvm.ptr
}

// the fill is now `end`
func.func private @jw_filled(%wp: !llvm.ptr, %end: i64) attributes { llvm.linkage = #llvm.linkage<internal> } {
  %c0 = arith.constant 0 : index
  %c10 = arith.constant 10 : i64
  %d = func.call @jw_desc(%wp, %c10) : (!llvm.ptr, i64) -> !d
  %m = builtin.unrealized_conversion_cast %d : !d to !m64
  memref.store %end, %m[%c0] : !m64
  return
}

// the open cells (4096 bytes)
func.func private @jw_cells(%wp: !llvm.ptr) -> !d attributes { llvm.linkage = #llvm.linkage<internal> } {
  %c2 = arith.constant 2 : index
  %cap = arith.constant 4096 : i64
  %sp = func.call @jw_p(%wp, %c2) : (!llvm.ptr, index) -> !llvm.ptr
  %d = func.call @jw_desc(%sp, %cap) : (!llvm.ptr, i64) -> !d
  return %d : !d
}

// ---- the fill.  The open cells become the lane's next rows (one drain: a page's run at a time, a page opened where a
// run begins one), and are empty.
func.func private @jw_seal(%wp: !llvm.ptr, %out: !bytes) attributes { llvm.linkage = #llvm.linkage<internal> } {
  %c0 = arith.constant 0 : index
  %z = arith.constant 0 : i64
  %fill = func.call @jw_w(%wp, %c0) : (!llvm.ptr, index) -> i64
  %cd = func.call @jw_cells(%wp) : (!llvm.ptr) -> !d
  %cm = builtin.unrealized_conversion_cast %cd : !d to !m8
  %cs = builtin.unrealized_conversion_cast %cm : !m8 to !text
  %filli = arith.index_cast %fill : i64 to index
  %full = trikeshed.slice %cs[%c0, %filli] : !text -> !text
  %rows = trikeshed.drain %full, %out : !text, !bytes -> index
  func.call @jw_filled(%wp, %z) : (!llvm.ptr, i64) -> ()
  return
}

// Room for k bytes in the open cells (k <= 4096): where they go.  When they do not fit, the open cells are sealed first.
func.func private @jw_room(%wp: !llvm.ptr, %out: !bytes, %k: i64) -> i64 attributes { llvm.linkage = #llvm.linkage<internal> } {
  %c0 = arith.constant 0 : index
  %z = arith.constant 0 : i64
  %cap = arith.constant 4096 : i64
  %fill = func.call @jw_w(%wp, %c0) : (!llvm.ptr, index) -> i64
  %need = arith.addi %fill, %k : i64
  %over = arith.cmpi ugt, %need, %cap : i64
  %at = scf.if %over -> (i64) {
    func.call @jw_seal(%wp, %out) : (!llvm.ptr, !bytes) -> ()
    scf.yield %z : i64
  } else {
    scf.yield %fill : i64
  }
  return %at : i64
}

// one byte
func.func private @jw_byte(%wp: !llvm.ptr, %out: !bytes, %b: i8) attributes { llvm.linkage = #llvm.linkage<internal> } {
  %one = arith.constant 1 : i64
  %at = func.call @jw_room(%wp, %out, %one) : (!llvm.ptr, !bytes, i64) -> i64
  %cd = func.call @jw_cells(%wp) : (!llvm.ptr) -> !d
  %cm = builtin.unrealized_conversion_cast %cd : !d to !m8
  %ati = arith.index_cast %at : i64 to index
  memref.store %b, %cm[%ati] : !m8
  %end = arith.addi %at, %one : i64
  func.call @jw_filled(%wp, %end) : (!llvm.ptr, i64) -> ()
  return
}

// a word of jw_words
func.func private @jw_word(%wp: !llvm.ptr, %out: !bytes, %off: index, %len: index) attributes { llvm.linkage = #llvm.linkage<internal> } {
  %five = arith.constant 5 : i64
  %at = func.call @jw_room(%wp, %out, %five) : (!llvm.ptr, !bytes, i64) -> i64
  %cd = func.call @jw_cells(%wp) : (!llvm.ptr) -> !d
  %cm = builtin.unrealized_conversion_cast %cd : !d to !m8
  %ati = arith.index_cast %at : i64 to index
  %dst = memref.subview %cm[%ati] [%len] [1] : !m8 to !m8
  %g = memref.get_global @jw_words : memref<13xi8>
  %blob = trikeshed.text %g : memref<13xi8> -> !text
  %word = trikeshed.slice %blob[%off, %len] : !text -> !text
  %e = trikeshed.drain %word, %dst : !text, !m8 -> index
  %len64 = arith.index_cast %len : index to i64
  %end = arith.addi %at, %len64 : i64
  func.call @jw_filled(%wp, %end) : (!llvm.ptr, i64) -> ()
  return
}

// An integer: '-' when it is negative, then the digits of the magnitude (the most negative's is 2^63, read unsigned).  How
// many: one more than the powers of ten from 10 up that the magnitude reaches, which is where trikeshed.bisect puts
// it among them (the order never says equal, so the answer is -(that count) - 1).  Each digit is an element of a series
// and the sign a slice of none or one byte: one combine, drained where the text stands (the series is never made).
func.func private @jw_int(%wp: !llvm.ptr, %out: !bytes, %x: i64) attributes { llvm.linkage = #llvm.linkage<internal> } {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c18 = arith.constant 18 : index
  %c21 = arith.constant 21 : index
  %z = arith.constant 0 : i64
  %ten = arith.constant 10 : i64
  %k21 = arith.constant 21 : i64
  %below = arith.constant -1 : i32
  %above = arith.constant 1 : i32
  %zero = arith.constant 48 : i8
  %at = func.call @jw_room(%wp, %out, %k21) : (!llvm.ptr, !bytes, i64) -> i64
  %neg = arith.cmpi slt, %x, %z : i64
  %minusx = arith.subi %z, %x : i64
  %mag = arith.select %neg, %minusx, %x : i64
  %pg = memref.get_global @jw_pow : memref<19xi64>
  %powers = trikeshed.text %pg : memref<19xi64> -> !s64
  %tens = trikeshed.slice %powers[%c1, %c18] : !s64 -> !s64
  %place = trikeshed.bisect %tens, %mag : !s64, i64 -> index by {
  ^bb0(%p: i64, %m: i64):
    %reached = arith.cmpi ule, %p, %m : i64
    %c = arith.select %reached, %below, %above : i32
    trikeshed.yield %c : i32
  }
  %count = arith.subi %c0, %place : index
  %digits = trikeshed.series %count : !text {
  ^bb0(%k: index):
    %last = arith.subi %count, %c1 : index
    %e = arith.subi %last, %k : index
    %pw = trikeshed.at %powers[%e] : !s64, index -> i64
    %q = arith.divui %mag, %pw : i64
    %dg = arith.remui %q, %ten : i64
    %d8 = arith.trunci %dg : i64 to i8
    %ch = arith.addi %d8, %zero : i8
    trikeshed.yield %ch : i8
  }
  %mg = memref.get_global @jw_minus : memref<1xi8>
  %minus = trikeshed.text %mg : memref<1xi8> -> !text
  %signs = arith.select %neg, %c1, %c0 : index
  %sign = trikeshed.slice %minus[%c0, %signs] : !text -> !text
  %all = trikeshed.combine %sign, %digits : !text, !text -> !text
  %cd = func.call @jw_cells(%wp) : (!llvm.ptr) -> !d
  %cm = builtin.unrealized_conversion_cast %cd : !d to !m8
  %ati = arith.index_cast %at : i64 to index
  %dst = memref.subview %cm[%ati] [%c21] [1] : !m8 to !m8
  %w = trikeshed.drain %all, %dst : !text, !m8 -> index
  %w64 = arith.index_cast %w : index to i64
  %end = arith.addi %at, %w64 : i64
  func.call @jw_filled(%wp, %end) : (!llvm.ptr, i64) -> ()
  return
}

// a float's text (JsonFloat.mlir's)
func.func private @jw_float(%wp: !llvm.ptr, %out: !bytes, %bits: i64) attributes { llvm.linkage = #llvm.linkage<internal> } {
  %c2 = arith.constant 2 : index
  %c6 = arith.constant 6 : index
  %k32 = arith.constant 32 : i64
  %at = func.call @jw_room(%wp, %out, %k32) : (!llvm.ptr, !bytes, i64) -> i64
  %sp = func.call @jw_p(%wp, %c2) : (!llvm.ptr, index) -> !llvm.ptr
  %dst = llvm.getelementptr %sp[%at] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fb = func.call @jw_p(%wp, %c6) : (!llvm.ptr, index) -> !llvm.ptr
  %fx = arith.bitcast %bits : i64 to f64
  %n = func.call @nixstore_ts_jsonfloat(%fx, %dst, %fb) : (f64, !llvm.ptr, !llvm.ptr) -> i64
  %end = arith.addi %at, %n : i64
  func.call @jw_filled(%wp, %end) : (!llvm.ptr, i64) -> ()
  return
}

// the n bytes at p as a JSON string: a quote, each byte's escape (its entry of the table, its length in the other), a
// quote.  The bytes go 680 at a time, so that a run's escapes (at most six bytes a byte) fit the open cells: one
// trikeshed.fold a run, which carries where the text stands.
func.func private @jw_string(%wp: !llvm.ptr, %out: !bytes, %p: !llvm.ptr, %n: i64) attributes { llvm.linkage = #llvm.linkage<internal> } {
  %c0 = arith.constant 0 : index
  %six = arith.constant 6 : index
  %run = arith.constant 680 : index
  %quote = arith.constant 34 : i8
  func.call @jw_byte(%wp, %out, %quote) : (!llvm.ptr, !bytes, i8) -> ()
  %eg = memref.get_global @jw_esc : memref<1536xi8>
  %table = trikeshed.text %eg : memref<1536xi8> -> !text
  %lg = memref.get_global @jw_esc_len : memref<256xi8>
  %lengths = trikeshed.text %lg : memref<256xi8> -> !text
  %ni = arith.index_cast %n : i64 to index
  scf.for %from = %c0 to %ni step %run {
    %left = arith.subi %ni, %from : index
    %len = arith.minui %left, %run : index
    %cap = arith.muli %len, %six : index
    %cap64 = arith.index_cast %cap : index to i64
    %at = func.call @jw_room(%wp, %out, %cap64) : (!llvm.ptr, !bytes, i64) -> i64
    %from64 = arith.index_cast %from : index to i64
    %src = llvm.getelementptr %p[%from64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %len64 = arith.index_cast %len : index to i64
    %xd = func.call @jw_desc(%src, %len64) : (!llvm.ptr, i64) -> !d
    %xm = builtin.unrealized_conversion_cast %xd : !d to !m8
    %xs = builtin.unrealized_conversion_cast %xm : !m8 to !text
    %cd = func.call @jw_cells(%wp) : (!llvm.ptr) -> !d
    %cm = builtin.unrealized_conversion_cast %cd : !d to !m8
    %ati = arith.index_cast %at : i64 to index
    // each byte's table entry drained whole (six bytes) where the text stands, which then goes on by the escape's own
    // length: what an entry holds past its escape is written over by the next byte's, or lies past the fill
    %e = trikeshed.fold %xs, %ati : !text, index -> index {
    ^bb0(%o: index, %b: i8):
      %bi = arith.index_castui %b : i8 to index
      %l = trikeshed.at %lengths[%bi] : !text, index -> i8
      %li = arith.index_castui %l : i8 to index
      %eo = arith.muli %bi, %six : index
      %entry = trikeshed.slice %table[%eo, %six] : !text -> !text
      %dst = memref.subview %cm[%o] [%six] [1] : !m8 to !m8
      %w = trikeshed.drain %entry, %dst : !text, !m8 -> index
      %on = arith.addi %o, %li : index
      trikeshed.yield %on : index
    }
    %end = arith.index_cast %e : index to i64
    func.call @jw_filled(%wp, %end) : (!llvm.ptr, i64) -> ()
  }
  func.call @jw_byte(%wp, %out, %quote) : (!llvm.ptr, !bytes, i8) -> ()
  return
}

// ---- the value.  Word k of the n words at p (a Value's three, a Bindings', a list's cells, a callback's slot).
func.func private @jw_at(%p: !llvm.ptr, %n: i64, %k: index) -> i64 attributes { llvm.linkage = #llvm.linkage<internal> } {
  %d = func.call @jw_desc(%p, %n) : (!llvm.ptr, i64) -> !d
  %m = builtin.unrealized_conversion_cast %d : !d to !m64
  %s = builtin.unrealized_conversion_cast %m : !m64 to !s64
  %x = trikeshed.at %s[%k] : !s64, index -> i64
  return %x : i64
}

// the order of two members by their names' bytes: the symbols' prefix words (a name's first eight bytes, big-endian),
// the bytes themselves only where those are equal (Bindings::lexicographicOrder's order).  rows: the Bindings' words.
func.func private @jw_name_order(%rows: !llvm.ptr, %prefixes: !llvm.ptr, %names: !llvm.ptr, %a: i64, %b: i64) -> i32 attributes { llvm.linkage = #llvm.linkage<internal> } {
  %bound = arith.constant 2147483647 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %low = arith.constant 4294967295 : i64
  %rd = func.call @jw_desc(%rows, %bound) : (!llvm.ptr, i64) -> !d
  %rm = builtin.unrealized_conversion_cast %rd : !d to !m64
  %rs = builtin.unrealized_conversion_cast %rm : !m64 to !s64
  %a2 = arith.muli %a, %c2 : i64
  %ar = arith.addi %a2, %c2 : i64
  %b2 = arith.muli %b, %c2 : i64
  %br = arith.addi %b2, %c2 : i64
  %aw = trikeshed.at %rs[%ar] : !s64, i64 -> i64
  %bw = trikeshed.at %rs[%br] : !s64, i64 -> i64
  %sa = arith.andi %aw, %low : i64
  %sb = arith.andi %bw, %low : i64
  %pd = func.call @jw_desc(%prefixes, %bound) : (!llvm.ptr, i64) -> !d
  %pm = builtin.unrealized_conversion_cast %pd : !d to !m64
  %ps = builtin.unrealized_conversion_cast %pm : !m64 to !s64
  %pa = trikeshed.at %ps[%sa] : !s64, i64 -> i64
  %pb = trikeshed.at %ps[%sb] : !s64, i64 -> i64
  %tie = arith.cmpi eq, %pa, %pb : i64
  %r = scf.if %tie -> (i32) {
    // a name is a StringRef: two words, its bytes' address and their count
    %nd = func.call @jw_desc(%names, %bound) : (!llvm.ptr, i64) -> !d
    %nm = builtin.unrealized_conversion_cast %nd : !d to !m64
    %ns = builtin.unrealized_conversion_cast %nm : !m64 to !s64
    %sa2 = arith.muli %sa, %c2 : i64
    %sa3 = arith.addi %sa2, %c1 : i64
    %sb2 = arith.muli %sb, %c2 : i64
    %sb3 = arith.addi %sb2, %c1 : i64
    %ap = trikeshed.at %ns[%sa2] : !s64, i64 -> i64
    %an = trikeshed.at %ns[%sa3] : !s64, i64 -> i64
    %bp = trikeshed.at %ns[%sb2] : !s64, i64 -> i64
    %bn = trikeshed.at %ns[%sb3] : !s64, i64 -> i64
    %app = llvm.inttoptr %ap : i64 to !llvm.ptr
    %bpp = llvm.inttoptr %bp : i64 to !llvm.ptr
    %ad = func.call @jw_desc(%app, %an) : (!llvm.ptr, i64) -> !d
    %am = builtin.unrealized_conversion_cast %ad : !d to !m8
    %at = builtin.unrealized_conversion_cast %am : !m8 to !text
    %bd = func.call @jw_desc(%bpp, %bn) : (!llvm.ptr, i64) -> !d
    %bm = builtin.unrealized_conversion_cast %bd : !d to !m8
    %bt = builtin.unrealized_conversion_cast %bm : !m8 to !text
    %c = trikeshed.compare %at, %bt unsigned : !text, !text
    scf.yield %c : i32
  } else {
    %lt = arith.cmpi ult, %pa, %pb : i64
    %m1 = arith.constant -1 : i32
    %o1 = arith.constant 1 : i32
    %c = arith.select %lt, %m1, %o1 : i32
    scf.yield %c : i32
  }
  return %r : i32
}

// One value, counted in the evaluator's depth while it is written (CallDepth): past the limit it is the depth's error.
// THE DEPTH'S RULE, in this one place: the evaluator's CallDepth counts and then compares (`if (++d > max) { --d; throw; }`),
// so a value is past the limit when depth + 1 > limit, and the count is left as it was.  Nix's addCallDepth compares
// before it counts (`if (d > max) throw; ++d;`): were the evaluator's to become that, %past compares %depth, not %deeper.
func.func private @jw_value(%wp: !llvm.ptr, %out: !bytes, %plan: !plan, %v: !llvm.ptr, %pos: !llvm.ptr) -> i64 attributes { llvm.linkage = #llvm.linkage<internal> } {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c3 = arith.constant 3 : index
  %c4 = arith.constant 4 : index
  %z = arith.constant 0 : i64
  %one = arith.constant 1 : i64
  %one32 = arith.constant 1 : i32
  %dp = func.call @jw_p(%wp, %c3) : (!llvm.ptr, index) -> !llvm.ptr
  %dd = func.call @jw_desc(%dp, %one) : (!llvm.ptr, i64) -> !d
  %dm = builtin.unrealized_conversion_cast %dd : !d to !m32
  %depth = memref.load %dm[%c0] : !m32
  %deeper = arith.addi %depth, %one32 : i32
  %limit64 = func.call @jw_w(%wp, %c4) : (!llvm.ptr, index) -> i64
  %limit = arith.trunci %limit64 : i64 to i32
  %past = arith.cmpi ugt, %deeper, %limit : i32
  %r = scf.if %past -> (i64) {
    %ctx = func.call @jw_p(%wp, %c1) : (!llvm.ptr, index) -> !llvm.ptr
    %none = llvm.inttoptr %z : i64 to !llvm.ptr
    %f = func.call @nixev_jw_fail(%ctx, %none, %pos) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
    scf.yield %f : i64
  } else {
    memref.store %deeper, %dm[%c0] : !m32
    %s = func.call @jw_written(%wp, %out, %plan, %v, %pos) : (!llvm.ptr, !bytes, !plan, !llvm.ptr, !llvm.ptr) -> i64
    memref.store %depth, %dm[%c0] : !m32
    scf.yield %s : i64
  }
  return %r : i64
}

// The value written: forced first when the walk is strict (a cell that is one already is only looked at, unless every
// cell is counted), then by its tag.
func.func private @jw_written(%wp: !llvm.ptr, %out: !bytes, %plan: !plan, %v: !llvm.ptr, %pos: !llvm.ptr) -> i64 attributes { llvm.linkage = #llvm.linkage<internal> } {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c4 = arith.constant 4 : index
  %c5 = arith.constant 5 : index
  %c9 = arith.constant 9 : index
  %z = arith.constant 0 : i64
  %one = arith.constant 1 : i64
  %two = arith.constant 2 : i64
  %three = arith.constant 3 : i64
  %four = arith.constant 4 : i64
  %byte = arith.constant 255 : i64
  %k32 = arith.constant 32 : i64
  %ctx = func.call @jw_p(%wp, %c1) : (!llvm.ptr, index) -> !llvm.ptr
  %flags = func.call @jw_w(%wp, %c5) : (!llvm.ptr, index) -> i64
  %strictb = arith.andi %flags, %one : i64
  %strict = arith.cmpi ne, %strictb, %z : i64
  %everyb = arith.andi %flags, %two : i64
  %every = arith.cmpi ne, %everyb, %z : i64
  %head0 = func.call @jw_at(%v, %three, %c0) : (!llvm.ptr, i64, index) -> i64
  %tag0 = arith.andi %head0, %byte : i64
  %cell = arith.cmpi ule, %tag0, %four : i64
  %due = arith.ori %cell, %every : i1
  %force = arith.andi %strict, %due : i1
  %forced = scf.if %force -> (i64) {
    %f = func.call @nixev_jw_force(%ctx, %v, %pos) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
    scf.yield %f : i64
  } else {
    scf.yield %z : i64
  }
  %failed = arith.cmpi ne, %forced, %z : i64
  %r = scf.if %failed -> (i64) {
    scf.yield %one : i64
  } else {
    %head = func.call @jw_at(%v, %three, %c0) : (!llvm.ptr, i64, index) -> i64
    %tag = arith.andi %head, %byte : i64
    %count = arith.shrui %head, %k32 : i64
    %word = func.call @jw_at(%v, %three, %c1) : (!llvm.ptr, i64, index) -> i64
    %t5 = arith.constant 5 : i64
    %t6 = arith.constant 6 : i64
    %t7 = arith.constant 7 : i64
    %t8 = arith.constant 8 : i64
    %t9 = arith.constant 9 : i64
    %t10 = arith.constant 10 : i64
    %t11 = arith.constant 11 : i64
    %t12 = arith.constant 12 : i64
    %isString = arith.cmpi eq, %tag, %t9 : i64
    %s9 = scf.if %isString -> (i64) {
      // its context taken, its bytes checked as UTF-8; then the string
      %bad = func.call @nixev_jw_string(%ctx, %v) : (!llvm.ptr, !llvm.ptr) -> i64
      %fine = arith.cmpi eq, %bad, %z : i64
      scf.if %fine {
        %sp = llvm.inttoptr %word : i64 to !llvm.ptr
        func.call @jw_string(%wp, %out, %sp, %count) : (!llvm.ptr, !bytes, !llvm.ptr, i64) -> ()
      }
      scf.yield %bad : i64
    } else {
      %isAttrs = arith.cmpi eq, %tag, %t11 : i64
      %s11 = scf.if %isAttrs -> (i64) {
        %sa = func.call @jw_set(%wp, %out, %plan, %v, %pos) : (!llvm.ptr, !bytes, !plan, !llvm.ptr, !llvm.ptr) -> i64
        scf.yield %sa : i64
      } else {
        %isInt = arith.cmpi eq, %tag, %t5 : i64
        %s5 = scf.if %isInt -> (i64) {
          func.call @jw_int(%wp, %out, %word) : (!llvm.ptr, !bytes, i64) -> ()
          scf.yield %z : i64
        } else {
          %isList = arith.cmpi eq, %tag, %t12 : i64
          %s12 = scf.if %isList -> (i64) {
            %sl = func.call @jw_list(%wp, %out, %plan, %v, %pos) : (!llvm.ptr, !bytes, !plan, !llvm.ptr, !llvm.ptr) -> i64
            scf.yield %sl : i64
          } else {
            %isBool = arith.cmpi eq, %tag, %t7 : i64
            %s7 = scf.if %isBool -> (i64) {
              // true 0/4, false 4/5
              %bit = arith.andi %word, %byte : i64
              %set = arith.cmpi ne, %bit, %z : i64
              %woff = arith.select %set, %c0, %c4 : index
              %wlen = arith.select %set, %c4, %c5 : index
              func.call @jw_word(%wp, %out, %woff, %wlen) : (!llvm.ptr, !bytes, index, index) -> ()
              scf.yield %z : i64
            } else {
              // null, and a cell that is not a value yet (the walk is not strict): null 9/4
              %isNull = arith.cmpi eq, %tag, %t8 : i64
              %isCell = arith.cmpi ule, %tag, %four : i64
              %nullish = arith.ori %isNull, %isCell : i1
              %s8 = scf.if %nullish -> (i64) {
                func.call @jw_word(%wp, %out, %c9, %c4) : (!llvm.ptr, !bytes, index, index) -> ()
                scf.yield %z : i64
              } else {
                %isFloat = arith.cmpi eq, %tag, %t6 : i64
                %s6 = scf.if %isFloat -> (i64) {
                  func.call @jw_float(%wp, %out, %word) : (!llvm.ptr, !bytes, i64) -> ()
                  scf.yield %z : i64
                } else {
                  %isPath = arith.cmpi eq, %tag, %t10 : i64
                  %s10 = scf.if %isPath -> (i64) {
                    %sp2 = func.call @jw_path(%wp, %out, %v, %word, %count) : (!llvm.ptr, !bytes, !llvm.ptr, i64, i64) -> i64
                    scf.yield %sp2 : i64
                  } else {
                    // a function: no JSON
                    %no = func.call @nixev_jw_fail(%ctx, %v, %pos) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
                    scf.yield %no : i64
                  }
                  scf.yield %s10 : i64
                }
                scf.yield %s6 : i64
              }
              scf.yield %s8 : i64
            }
            scf.yield %s7 : i64
          }
          scf.yield %s12 : i64
        }
        scf.yield %s5 : i64
      }
      scf.yield %s11 : i64
    }
    scf.yield %s9 : i64
  }
  return %r : i64
}

// a path: its own bytes, or (flags 4) its copy's in the store
func.func private @jw_path(%wp: !llvm.ptr, %out: !bytes, %v: !llvm.ptr, %word: i64, %count: i64) -> i64 attributes { llvm.linkage = #llvm.linkage<internal> } {
  %c1 = arith.constant 1 : index
  %c5 = arith.constant 5 : index
  %c8 = arith.constant 8 : index
  %c9 = arith.constant 9 : index
  %z = arith.constant 0 : i64
  %four = arith.constant 4 : i64
  %k8 = arith.constant 8 : i64
  %flags = func.call @jw_w(%wp, %c5) : (!llvm.ptr, index) -> i64
  %copyb = arith.andi %flags, %four : i64
  %copy = arith.cmpi ne, %copyb, %z : i64
  %r = scf.if %copy -> (i64) {
    %ctx = func.call @jw_p(%wp, %c1) : (!llvm.ptr, index) -> !llvm.ptr
    %slot = llvm.getelementptr %wp[%k8] : (!llvm.ptr, i64) -> !llvm.ptr, i64
    %bad = func.call @nixev_jw_path(%ctx, %v, %slot) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
    %fine = arith.cmpi eq, %bad, %z : i64
    scf.if %fine {
      %cp = func.call @jw_p(%wp, %c8) : (!llvm.ptr, index) -> !llvm.ptr
      %cn = func.call @jw_w(%wp, %c9) : (!llvm.ptr, index) -> i64
      func.call @jw_string(%wp, %out, %cp, %cn) : (!llvm.ptr, !bytes, !llvm.ptr, i64) -> ()
    }
    scf.yield %bad : i64
  } else {
    %pp = llvm.inttoptr %word : i64 to !llvm.ptr
    func.call @jw_string(%wp, %out, %pp, %count) : (!llvm.ptr, !bytes, !llvm.ptr, i64) -> ()
    scf.yield %z : i64
  }
  return %r : i64
}

// a list: [ its cells in order, a comma between ]; a cell that fails is named by its index (the list's own position)
func.func private @jw_list(%wp: !llvm.ptr, %out: !bytes, %plan: !plan, %v: !llvm.ptr, %pos: !llvm.ptr) -> i64 attributes { llvm.linkage = #llvm.linkage<internal> } {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %z = arith.constant 0 : i64
  %one = arith.constant 1 : i64
  %three = arith.constant 3 : i64
  %k32 = arith.constant 32 : i64
  %open = arith.constant 91 : i8
  %close = arith.constant 93 : i8
  %comma = arith.constant 44 : i8
  func.call @jw_byte(%wp, %out, %open) : (!llvm.ptr, !bytes, i8) -> ()
  %head = func.call @jw_at(%v, %three, %c0) : (!llvm.ptr, i64, index) -> i64
  %n = arith.shrui %head, %k32 : i64
  %cellsw = func.call @jw_at(%v, %three, %c1) : (!llvm.ptr, i64, index) -> i64
  %cells = llvm.inttoptr %cellsw : i64 to !llvm.ptr
  %ed = func.call @jw_desc(%cells, %n) : (!llvm.ptr, i64) -> !d
  %em = builtin.unrealized_conversion_cast %ed : !d to !m64
  %es = builtin.unrealized_conversion_cast %em : !m64 to !s64
  %w:2 = scf.while (%i = %z, %s = %z) : (i64, i64) -> (i64, i64) {
    %more = arith.cmpi ult, %i, %n : i64
    %fine = arith.cmpi eq, %s, %z : i64
    %go = arith.andi %more, %fine : i1
    scf.condition(%go) %i, %s : i64, i64
  } do {
  ^bb0(%ib: i64, %sb: i64):
    %later = arith.cmpi ne, %ib, %z : i64
    scf.if %later {
      func.call @jw_byte(%wp, %out, %comma) : (!llvm.ptr, !bytes, i8) -> ()
    }
    %ii = arith.index_cast %ib : i64 to index
    %cw = trikeshed.at %es[%ii] : !s64, index -> i64
    %cell = llvm.inttoptr %cw : i64 to !llvm.ptr
    %sc = func.call @jw_value(%wp, %out, %plan, %cell, %pos) : (!llvm.ptr, !bytes, !plan, !llvm.ptr, !llvm.ptr) -> i64
    %bad = arith.cmpi ne, %sc, %z : i64
    scf.if %bad {
      %ctx = func.call @jw_p(%wp, %c1) : (!llvm.ptr, index) -> !llvm.ptr
      %none = llvm.inttoptr %z : i64 to !llvm.ptr
      func.call @nixev_jw_trace(%ctx, %none, %ib, %pos) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr) -> ()
    }
    %next = arith.addi %ib, %one : i64
    scf.yield %next, %sc : i64, i64
  }
  %ok = arith.cmpi eq, %w#1, %z : i64
  scf.if %ok {
    func.call @jw_byte(%wp, %out, %close) : (!llvm.ptr, !bytes, i8) -> ()
  }
  return %w#1 : i64
}

// a set: its __toString's text or its outPath's value where it has one (the bridge says), else { its members }
func.func private @jw_set(%wp: !llvm.ptr, %out: !bytes, %plan: !plan, %v: !llvm.ptr, %pos: !llvm.ptr) -> i64 attributes { llvm.linkage = #llvm.linkage<internal> } {
  %c1 = arith.constant 1 : index
  %c8 = arith.constant 8 : index
  %c9 = arith.constant 9 : index
  %z = arith.constant 0 : i64
  %one = arith.constant 1 : i64
  %two = arith.constant 2 : i64
  %k8 = arith.constant 8 : i64
  %ctx = func.call @jw_p(%wp, %c1) : (!llvm.ptr, index) -> !llvm.ptr
  %slot = llvm.getelementptr %wp[%k8] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %kind = func.call @nixev_jw_attrs(%ctx, %v, %slot) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
  %s0 = func.call @jw_w(%wp, %c8) : (!llvm.ptr, index) -> i64
  %s1 = func.call @jw_w(%wp, %c9) : (!llvm.ptr, index) -> i64
  %members = arith.cmpi eq, %kind, %z : i64
  %r = scf.if %members -> (i64) {
    %sm = func.call @jw_members(%wp, %out, %plan, %v) : (!llvm.ptr, !bytes, !plan, !llvm.ptr) -> i64
    scf.yield %sm : i64
  } else {
    %text = arith.cmpi eq, %kind, %one : i64
    %rt = scf.if %text -> (i64) {
      %tp = llvm.inttoptr %s0 : i64 to !llvm.ptr
      func.call @jw_string(%wp, %out, %tp, %s1) : (!llvm.ptr, !bytes, !llvm.ptr, i64) -> ()
      scf.yield %z : i64
    } else {
      %path = arith.cmpi eq, %kind, %two : i64
      %rp = scf.if %path -> (i64) {
        %ov = llvm.inttoptr %s0 : i64 to !llvm.ptr
        %op = llvm.inttoptr %s1 : i64 to !llvm.ptr
        %so = func.call @jw_value(%wp, %out, %plan, %ov, %op) : (!llvm.ptr, !bytes, !plan, !llvm.ptr, !llvm.ptr) -> i64
        scf.yield %so : i64
      } else {
        scf.yield %one : i64
      }
      scf.yield %rp : i64
    }
    scf.yield %rt : i64
  }
  return %r : i64
}

// the symbol of member `row` of a Bindings: the low half of the member's first word
func.func private @jw_sym(%rows: !llvm.ptr, %row: i64) -> i64 attributes { llvm.linkage = #llvm.linkage<internal> } {
  %bound = arith.constant 2147483647 : i64
  %two = arith.constant 2 : i64
  %low = arith.constant 4294967295 : i64
  %rd = func.call @jw_desc(%rows, %bound) : (!llvm.ptr, i64) -> !d
  %rm = builtin.unrealized_conversion_cast %rd : !d to !m64
  %rs = builtin.unrealized_conversion_cast %rm : !m64 to !s64
  %r2 = arith.muli %row, %two : i64
  %at = arith.addi %r2, %two : i64
  %w = trikeshed.at %rs[%at] : !s64, i64 -> i64
  %sym = arith.andi %w, %low : i64
  return %sym : i64
}

// { the members in the byte order of their names, a comma between }.  None and one as they lie.  More in the order
// of their layout, which is the same for every set of the same names: the plan keeps it, taken once (jw_planned).  A
// set of more than 256 members is put in order by itself (jw_sorted).
func.func private @jw_members(%wp: !llvm.ptr, %out: !bytes, %plan: !plan, %v: !llvm.ptr) -> i64 attributes { llvm.linkage = #llvm.linkage<internal> } {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %z = arith.constant 0 : i64
  %one = arith.constant 1 : i64
  %three = arith.constant 3 : i64
  %k256 = arith.constant 256 : i64
  %low = arith.constant 4294967295 : i64
  %open = arith.constant 123 : i8
  %close = arith.constant 125 : i8
  func.call @jw_byte(%wp, %out, %open) : (!llvm.ptr, !bytes, i8) -> ()
  %bw = func.call @jw_at(%v, %three, %c1) : (!llvm.ptr, i64, index) -> i64
  %rows = llvm.inttoptr %bw : i64 to !llvm.ptr
  %head = func.call @jw_at(%rows, %one, %c0) : (!llvm.ptr, i64, index) -> i64
  %n = arith.andi %head, %low : i64
  %few = arith.cmpi ule, %n, %one : i64
  %r = scf.if %few -> (i64) {
    %single = arith.cmpi eq, %n, %one : i64
    %r1 = scf.if %single -> (i64) {
      %s1 = func.call @jw_member(%wp, %out, %plan, %rows, %z, %z) : (!llvm.ptr, !bytes, !plan, !llvm.ptr, i64, i64) -> i64
      scf.yield %s1 : i64
    } else {
      scf.yield %z : i64
    }
    scf.yield %r1 : i64
  } else {
    %wide = arith.cmpi ugt, %n, %k256 : i64
    %rw = scf.if %wide -> (i64) {
      %sw = func.call @jw_sorted(%wp, %out, %plan, %rows, %n) : (!llvm.ptr, !bytes, !plan, !llvm.ptr, i64) -> i64
      scf.yield %sw : i64
    } else {
      %sp = func.call @jw_planned(%wp, %out, %plan, %rows, %n) : (!llvm.ptr, !bytes, !plan, !llvm.ptr, i64) -> i64
      scf.yield %sp : i64
    }
    scf.yield %rw : i64
  }
  %ok = arith.cmpi eq, %r, %z : i64
  scf.if %ok {
    func.call @jw_byte(%wp, %out, %close) : (!llvm.ptr, !bytes, i8) -> ()
  }
  return %r : i64
}

// The members put in order here, and written: trikeshed.sorted over the rows, compared by their names' bytes.  The
// order is taken before any member is written: nothing is forced in between, so the symbol table's words hold.
func.func private @jw_sorted(%wp: !llvm.ptr, %out: !bytes, %plan: !plan, %rows: !llvm.ptr, %n: i64) -> i64 attributes { llvm.linkage = #llvm.linkage<internal> } {
  %c1 = arith.constant 1 : index
  %c8 = arith.constant 8 : index
  %c9 = arith.constant 9 : index
  %z = arith.constant 0 : i64
  %one = arith.constant 1 : i64
  %k8 = arith.constant 8 : i64
  %ctx = func.call @jw_p(%wp, %c1) : (!llvm.ptr, index) -> !llvm.ptr
  %slot = llvm.getelementptr %wp[%k8] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  func.call @nixev_jw_syms(%ctx, %slot) : (!llvm.ptr, !llvm.ptr) -> ()
  %prefixes = func.call @jw_p(%wp, %c8) : (!llvm.ptr, index) -> !llvm.ptr
  %names = func.call @jw_p(%wp, %c9) : (!llvm.ptr, index) -> !llvm.ptr
  %ni = arith.index_cast %n : i64 to index
  %lie = trikeshed.series %ni : !s64 {
  ^bb0(%k: index):
    %k64 = arith.index_cast %k : index to i64
    trikeshed.yield %k64 : i64
  }
  %order = trikeshed.sorted %lie : !s64 -> !s64 by {
  ^bb0(%a: i64, %b: i64):
    %c = func.call @jw_name_order(%rows, %prefixes, %names, %a, %b) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, i64) -> i32
    trikeshed.yield %c : i32
  }
  %w:2 = scf.while (%j = %z, %s = %z) : (i64, i64) -> (i64, i64) {
    %more = arith.cmpi ult, %j, %n : i64
    %fine = arith.cmpi eq, %s, %z : i64
    %go = arith.andi %more, %fine : i1
    scf.condition(%go) %j, %s : i64, i64
  } do {
  ^bb0(%jb: i64, %sb: i64):
    %ji = arith.index_cast %jb : i64 to index
    %row = trikeshed.at %order[%ji] : !s64, index -> i64
    %sm = func.call @jw_member(%wp, %out, %plan, %rows, %row, %jb) : (!llvm.ptr, !bytes, !plan, !llvm.ptr, i64, i64) -> i64
    %next = arith.addi %jb, %one : i64
    scf.yield %next, %sm : i64, i64
  }
  return %w#1 : i64
}

// The members written in their layout's order, which the plan keeps.  The plan (a lane of words, in the entry's frame)
// begins with 64 cells, none forced.  A layout's key (its names' symbols, folded) names a cell, and trikeshed.anchor
// mints it for the first set of the layout: the members' order is taken (trikeshed.sorted over the rows as they lie)
// and appended to the plan behind the Bindings it was taken of; the cell is where that record begins.  Every later
// set of the same names (the same count and the same symbols row by row: the record's Bindings says) is written in
// that order, read where the plan keeps it, and nothing is sorted.  A cell another layout holds is passed over (eight
// are tried from the key's); a set that finds none is put in order by itself.
func.func private @jw_planned(%wp: !llvm.ptr, %out: !bytes, %plan: !plan, %rows: !llvm.ptr, %n: i64) -> i64 attributes { llvm.linkage = #llvm.linkage<internal> } {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c8 = arith.constant 8 : index
  %c9 = arith.constant 9 : index
  %z = arith.constant 0 : i64
  %one = arith.constant 1 : i64
  %k8 = arith.constant 8 : i64
  %k29 = arith.constant 29 : i64
  %cells = arith.constant 63 : i64
  %low = arith.constant 4294967295 : i64
  %seed = arith.constant -3750763034362895579 : i64
  %prime = arith.constant 1099511628211 : i64
  %ig = memref.get_global @jw_ids : memref<256xi64>
  %all = trikeshed.text %ig : memref<256xi64> -> !s64
  %ni = arith.index_cast %n : i64 to index
  %lie = trikeshed.slice %all[%c0, %ni] : !s64 -> !s64
  %key = trikeshed.fold %lie, %seed : !s64, i64 -> i64 {
  ^bb0(%acc: i64, %lr: i64):
    %sym = func.call @jw_sym(%rows, %lr) : (!llvm.ptr, i64) -> i64
    %x = arith.xori %acc, %sym : i64
    %m = arith.muli %x, %prime : i64
    trikeshed.yield %m : i64
  }
  %high = arith.shrui %key, %k29 : i64
  %mixed = arith.xori %key, %high : i64
  // the plan's cells are made when the first layout asks
  %have = trikeshed.size %plan : !plan
  %none = arith.cmpi eq, %have, %c0 : index
  scf.if %none {
    %zg = memref.get_global @jw_none : memref<64xi64>
    %zs = trikeshed.text %zg : memref<64xi64> -> !s64
    %made = trikeshed.drain %zs, %plan : !s64, !plan -> index
  }
  %found:2 = scf.while (%try = %z, %rec = %z) : (i64, i64) -> (i64, i64) {
    %more = arith.cmpi ult, %try, %k8 : i64
    %open = arith.cmpi eq, %rec, %z : i64
    %go = arith.andi %more, %open : i1
    scf.condition(%go) %try, %rec : i64, i64
  } do {
  ^bb0(%tb: i64, %rb: i64):
    %sum = arith.addi %mixed, %tb : i64
    %cell64 = arith.andi %sum, %cells : i64
    %cell = arith.index_cast %cell64 : i64 to index
    %at = trikeshed.anchor %plan[%cell] : !plan -> i64 {
      // the first set of a layout: its members' order, behind its Bindings
      %ctx = func.call @jw_p(%wp, %c1) : (!llvm.ptr, index) -> !llvm.ptr
      %slot = llvm.getelementptr %wp[%k8] : (!llvm.ptr, i64) -> !llvm.ptr, i64
      func.call @nixev_jw_syms(%ctx, %slot) : (!llvm.ptr, !llvm.ptr) -> ()
      %prefixes = func.call @jw_p(%wp, %c8) : (!llvm.ptr, index) -> !llvm.ptr
      %names = func.call @jw_p(%wp, %c9) : (!llvm.ptr, index) -> !llvm.ptr
      %order = trikeshed.sorted %lie : !s64 -> !s64 by {
      ^bb0(%a: i64, %b: i64):
        %c = func.call @jw_name_order(%rows, %prefixes, %names, %a, %b) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, i64) -> i32
        trikeshed.yield %c : i32
      }
      %rowsw = llvm.ptrtoint %rows : !llvm.ptr to i64
      %begin = trikeshed.append %plan, %rowsw : !plan, i64 -> index
      %end = trikeshed.drain %order, %plan : !s64, !plan -> index
      %begin64 = arith.index_cast %begin : index to i64
      trikeshed.yield %begin64 : i64
    }
    // the record there is this layout's when its Bindings has this count and these symbols
    %ati = arith.index_cast %at : i64 to index
    %theirsw = trikeshed.at %plan[%ati] : !plan, index -> i64
    %theirs = llvm.inttoptr %theirsw : i64 to !llvm.ptr
    %thead = func.call @jw_at(%theirs, %one, %c0) : (!llvm.ptr, i64, index) -> i64
    %tn = arith.andi %thead, %low : i64
    %samen = arith.cmpi eq, %tn, %n : i64
    %differ = scf.if %samen -> (i64) {
      %d = trikeshed.fold %lie, %z : !s64, i64 -> i64 {
      ^bb0(%sofar: i64, %q: i64):
        %mine = func.call @jw_sym(%rows, %q) : (!llvm.ptr, i64) -> i64
        %its = func.call @jw_sym(%theirs, %q) : (!llvm.ptr, i64) -> i64
        %dx = arith.xori %mine, %its : i64
        %either = arith.ori %sofar, %dx : i64
        trikeshed.yield %either : i64
      }
      scf.yield %d : i64
    } else {
      scf.yield %one : i64
    }
    %same = arith.cmpi eq, %differ, %z : i64
    %recn = arith.select %same, %at, %z : i64
    %tnext = arith.addi %tb, %one : i64
    scf.yield %tnext, %recn : i64, i64
  }
  %planned = arith.cmpi ne, %found#1, %z : i64
  %r = scf.if %planned -> (i64) {
    %w:2 = scf.while (%j = %z, %s = %z) : (i64, i64) -> (i64, i64) {
      %jmore = arith.cmpi ult, %j, %n : i64
      %fine = arith.cmpi eq, %s, %z : i64
      %jgo = arith.andi %jmore, %fine : i1
      scf.condition(%jgo) %j, %s : i64, i64
    } do {
    ^bb0(%jb: i64, %sb: i64):
      %pj = arith.addi %found#1, %jb : i64
      %pj1 = arith.addi %pj, %one : i64
      %pi = arith.index_cast %pj1 : i64 to index
      %row = trikeshed.at %plan[%pi] : !plan, index -> i64
      %sm = func.call @jw_member(%wp, %out, %plan, %rows, %row, %jb) : (!llvm.ptr, !bytes, !plan, !llvm.ptr, i64, i64) -> i64
      %next = arith.addi %jb, %one : i64
      scf.yield %next, %sm : i64, i64
    }
    scf.yield %w#1 : i64
  } else {
    %ss = func.call @jw_sorted(%wp, %out, %plan, %rows, %n) : (!llvm.ptr, !bytes, !plan, !llvm.ptr, i64) -> i64
    scf.yield %ss : i64
  }
  return %r : i64
}

// member `row` of the Bindings, the j-th written: a comma after the first, "name": and the value; a value that fails
// is named by the member
func.func private @jw_member(%wp: !llvm.ptr, %out: !bytes, %plan: !plan, %rows: !llvm.ptr, %row: i64, %j: i64) -> i64 attributes { llvm.linkage = #llvm.linkage<internal> } {
  %c1 = arith.constant 1 : index
  %c8 = arith.constant 8 : index
  %c9 = arith.constant 9 : index
  %z = arith.constant 0 : i64
  %two = arith.constant 2 : i64
  %k8 = arith.constant 8 : i64
  %comma = arith.constant 44 : i8
  %colon = arith.constant 58 : i8
  %later = arith.cmpi ne, %j, %z : i64
  scf.if %later {
    func.call @jw_byte(%wp, %out, %comma) : (!llvm.ptr, !bytes, i8) -> ()
  }
  // the member's two words lie from word 2 + 2 row of the Bindings
  %r2 = arith.muli %row, %two : i64
  %at = arith.addi %r2, %two : i64
  %a = llvm.getelementptr %rows[%at] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %ctx = func.call @jw_p(%wp, %c1) : (!llvm.ptr, index) -> !llvm.ptr
  %slot = llvm.getelementptr %wp[%k8] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %apos = func.call @nixev_jw_row(%ctx, %a, %slot) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> !llvm.ptr
  %np = func.call @jw_p(%wp, %c8) : (!llvm.ptr, index) -> !llvm.ptr
  %nn = func.call @jw_w(%wp, %c9) : (!llvm.ptr, index) -> i64
  func.call @jw_string(%wp, %out, %np, %nn) : (!llvm.ptr, !bytes, !llvm.ptr, i64) -> ()
  func.call @jw_byte(%wp, %out, %colon) : (!llvm.ptr, !bytes, i8) -> ()
  %cw = func.call @jw_at(%a, %two, %c1) : (!llvm.ptr, i64, index) -> i64
  %cell = llvm.inttoptr %cw : i64 to !llvm.ptr
  %s = func.call @jw_value(%wp, %out, %plan, %cell, %apos) : (!llvm.ptr, !bytes, !plan, !llvm.ptr, !llvm.ptr) -> i64
  %bad = arith.cmpi ne, %s, %z : i64
  scf.if %bad {
    func.call @nixev_jw_trace(%ctx, %a, %z, %apos) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr) -> ()
  }
  return %s : i64
}

// ---- the entry: the lane and the open cells made here, the walk, then the one drain into room of the text's size
func.func @nixev_ts_json(%ctx: !llvm.ptr, %v: !llvm.ptr, %pos: !llvm.ptr, %depth: !llvm.ptr, %limit: i64, %flags: i64) -> i64 {
  %out = trikeshed.lane : !bytes
  %plan = trikeshed.lane : !plan
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c2 = arith.constant 2 : index
  %c3 = arith.constant 3 : index
  %c4 = arith.constant 4 : index
  %c5 = arith.constant 5 : index
  %c6 = arith.constant 6 : index
  %z = arith.constant 0 : i64
  %k10 = arith.constant 10 : i64
  %k64 = arith.constant 64 : i64
  %cap = arith.constant 4096 : i64
  %wp = llvm.alloca %k10 x i64 : (i64) -> !llvm.ptr
  %cells = llvm.alloca %cap x i8 : (i64) -> !llvm.ptr
  %fb = llvm.alloca %k64 x i8 : (i64) -> !llvm.ptr
  %wd = func.call @jw_desc(%wp, %k10) : (!llvm.ptr, i64) -> !d
  %wm = builtin.unrealized_conversion_cast %wd : !d to !m64
  %ctxw = llvm.ptrtoint %ctx : !llvm.ptr to i64
  %cellsw = llvm.ptrtoint %cells : !llvm.ptr to i64
  %depthw = llvm.ptrtoint %depth : !llvm.ptr to i64
  %fbw = llvm.ptrtoint %fb : !llvm.ptr to i64
  memref.store %z, %wm[%c0] : !m64
  memref.store %ctxw, %wm[%c1] : !m64
  memref.store %cellsw, %wm[%c2] : !m64
  memref.store %depthw, %wm[%c3] : !m64
  memref.store %limit, %wm[%c4] : !m64
  memref.store %flags, %wm[%c5] : !m64
  memref.store %fbw, %wm[%c6] : !m64
  %s = func.call @jw_value(%wp, %out, %plan, %v, %pos) : (!llvm.ptr, !bytes, !plan, !llvm.ptr, !llvm.ptr) -> i64
  %ok = arith.cmpi eq, %s, %z : i64
  scf.if %ok {
    %sealed = trikeshed.size %out : !bytes
    %short = arith.cmpi eq, %sealed, %c0 : index
    scf.if %short {
      // a text that never left the open cells: they are the text
      %fill = func.call @jw_w(%wp, %c0) : (!llvm.ptr, index) -> i64
      %room = func.call @nixev_jw_room(%ctx, %fill) : (!llvm.ptr, i64) -> !llvm.ptr
      %rd = func.call @jw_desc(%room, %fill) : (!llvm.ptr, i64) -> !d
      %rm = builtin.unrealized_conversion_cast %rd : !d to !m8
      %cd = func.call @jw_cells(%wp) : (!llvm.ptr) -> !d
      %cm = builtin.unrealized_conversion_cast %cd : !d to !m8
      %cs = builtin.unrealized_conversion_cast %cm : !m8 to !text
      %filli = arith.index_cast %fill : i64 to index
      %open = trikeshed.slice %cs[%c0, %filli] : !text -> !text
      %e1 = trikeshed.drain %open, %rm : !text, !m8 -> index
    } else {
      // the open cells' fill is the lane's last rows; the lane is the text
      func.call @jw_seal(%wp, %out) : (!llvm.ptr, !bytes) -> ()
      %total = trikeshed.size %out : !bytes
      %total64 = arith.index_cast %total : index to i64
      %room2 = func.call @nixev_jw_room(%ctx, %total64) : (!llvm.ptr, i64) -> !llvm.ptr
      %rd2 = func.call @jw_desc(%room2, %total64) : (!llvm.ptr, i64) -> !d
      %rm2 = builtin.unrealized_conversion_cast %rd2 : !d to !m8
      %e2 = trikeshed.drain %out, %rm2 : !bytes, !m8 -> index
    }
  }
  return %s : i64
}
