// series.mlir -- byte series, their coordinates, and the builder replies are made in.
//
// A text is a series of bytes: a pointer and a length.  A piece of it is a coordinate: TrikeShed's TwinPacked of two u32
// in one i64, start << 32 | length (Pack.h's TwInt; !trikeshed.twinpacked<i32>, which src/index.mlir and
// src/columns.mlir read with trikeshed.first and trikeshed.second), the half-open [start, start + length).  Nothing here
// makes a string.  A piece is read where it lies, compared where it lies, and copied only into the builder, whose buffer
// can start with room for a reply's head, so that the head is written in front of the body and nothing moves.  What the
// builder writes besides pieces, a string's escapes and a number's digits, text.mlir makes in TrikeShed's ops.

llvm.func @malloc(i64) -> !llvm.ptr
llvm.func @realloc(!llvm.ptr, i64) -> !llvm.ptr
llvm.func @free(!llvm.ptr)
llvm.func @memcpy(!llvm.ptr, !llvm.ptr, i64) -> !llvm.ptr
llvm.func @memcmp(!llvm.ptr, !llvm.ptr, i64) -> i32
llvm.func @memchr(!llvm.ptr, i32, i64) -> !llvm.ptr
llvm.func @memmem(!llvm.ptr, i64, !llvm.ptr, i64) -> !llvm.ptr
llvm.func @snprintf(!llvm.ptr, i64, !llvm.ptr, ...) -> i32
llvm.func @_mlir_ciface_json_escape(!llvm.ptr, !llvm.ptr) -> i64
llvm.func @_mlir_ciface_decimal(i64, !llvm.ptr) -> i64

llvm.mlir.global internal constant @k_f("%f\00") : !llvm.array<3 x i8>

// ---- coordinates

// the piece [s, e)
func.func @tw(%s: i64, %e: i64) -> i64 {
  %c32 = arith.constant 32 : i64
  %m = arith.constant 4294967295 : i64
  %hi = arith.shli %s, %c32 : i64
  %n = arith.subi %e, %s : i64
  %lo = arith.andi %n, %m : i64
  %t = arith.ori %hi, %lo : i64
  return %t : i64
}

// its start
func.func @tw_s(%t: i64) -> i64 {
  %c32 = arith.constant 32 : i64
  %s = arith.shrui %t, %c32 : i64
  return %s : i64
}

// its end
func.func @tw_e(%t: i64) -> i64 {
  %s = func.call @tw_s(%t) : (i64) -> i64
  %n = func.call @tw_n(%t) : (i64) -> i64
  %e = arith.addi %s, %n : i64
  return %e : i64
}

// its length
func.func @tw_n(%t: i64) -> i64 {
  %m = arith.constant 4294967295 : i64
  %n = arith.andi %t, %m : i64
  return %n : i64
}

// a series' buffer as the descriptor the LLVM lowering lays out (memref<?xT, strided<[1], offset: ?>>), of the n elements
// at p: what src/index.mlir and src/columns.mlir take a text or a column as
func.func @view(%d: !llvm.ptr, %p: !llvm.ptr, %n: i64) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %q0 = llvm.getelementptr %d[0, 0] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>
  llvm.store %p, %q0 : !llvm.ptr, !llvm.ptr
  %q1 = llvm.getelementptr %d[0, 1] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>
  llvm.store %p, %q1 : !llvm.ptr, !llvm.ptr
  %q2 = llvm.getelementptr %d[0, 2] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>
  llvm.store %c0, %q2 : i64, !llvm.ptr
  %q3 = llvm.getelementptr %d[0, 3, 0] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>
  llvm.store %n, %q3 : i64, !llvm.ptr
  %q4 = llvm.getelementptr %d[0, 4, 0] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>
  llvm.store %c1, %q4 : i64, !llvm.ptr
  return
}

// ---- bytes where they lie

func.func @at(%p: !llvm.ptr, %i: i64) -> i8 {
  %q = llvm.getelementptr %p[%i] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %c = llvm.load %q : !llvm.ptr -> i8
  return %c : i8
}

func.func @off(%p: !llvm.ptr, %i: i64) -> !llvm.ptr {
  %q = llvm.getelementptr %p[%i] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  return %q : !llvm.ptr
}

// the piece of a at ta has the bytes of the n bytes at b
func.func @is(%a: !llvm.ptr, %ta: i64, %b: !llvm.ptr, %n: i64) -> i1 {
  %la = func.call @tw_n(%ta) : (i64) -> i64
  %same = arith.cmpi eq, %la, %n : i64
  %r = scf.if %same -> (i1) {
    %s = func.call @tw_s(%ta) : (i64) -> i64
    %pa = func.call @off(%a, %s) : (!llvm.ptr, i64) -> !llvm.ptr
    %c = llvm.call @memcmp(%pa, %b, %n) : (!llvm.ptr, !llvm.ptr, i64) -> i32
    %z = arith.constant 0 : i32
    %eq = arith.cmpi eq, %c, %z : i32
    scf.yield %eq : i1
  } else {
    %f = arith.constant false
    scf.yield %f : i1
  }
  return %r : i1
}

// two pieces with the same bytes
func.func @same(%a: !llvm.ptr, %ta: i64, %b: !llvm.ptr, %tb: i64) -> i1 {
  %s = func.call @tw_s(%tb) : (i64) -> i64
  %pb = func.call @off(%b, %s) : (!llvm.ptr, i64) -> !llvm.ptr
  %n = func.call @tw_n(%tb) : (i64) -> i64
  %r = func.call @is(%a, %ta, %pb, %n) : (!llvm.ptr, i64, !llvm.ptr, i64) -> i1
  return %r : i1
}

// the first byte b in [from, to), or -1
func.func @find(%p: !llvm.ptr, %from: i64, %to: i64, %b: i8) -> i64 {
  %m1 = arith.constant -1 : i64
  %n = arith.subi %to, %from : i64
  %c0 = arith.constant 0 : i64
  %none = arith.cmpi sle, %n, %c0 : i64
  %r = scf.if %none -> (i64) {
    scf.yield %m1 : i64
  } else {
    %start = func.call @off(%p, %from) : (!llvm.ptr, i64) -> !llvm.ptr
    %bi = arith.extui %b : i8 to i32
    %hit = llvm.call @memchr(%start, %bi, %n) : (!llvm.ptr, i32, i64) -> !llvm.ptr
    %null = llvm.mlir.zero : !llvm.ptr
    %miss = llvm.icmp "eq" %hit, %null : !llvm.ptr
    %ri = scf.if %miss -> (i64) {
      scf.yield %m1 : i64
    } else {
      %hi = llvm.ptrtoint %hit : !llvm.ptr to i64
      %pi = llvm.ptrtoint %p : !llvm.ptr to i64
      %d = arith.subi %hi, %pi : i64
      scf.yield %d : i64
    }
    scf.yield %ri : i64
  }
  return %r : i64
}

// the last byte b in [from, to), or -1
func.func @rfind(%p: !llvm.ptr, %from: i64, %to: i64, %b: i8) -> i64 {
  %m1 = arith.constant -1 : i64
  %c1 = arith.constant 1 : i64
  %r = scf.while (%i = %to) : (i64) -> i64 {
    %more = arith.cmpi sgt, %i, %from : i64
    %j = arith.subi %i, %c1 : i64
    %go = scf.if %more -> (i1) {
      %x = func.call @at(%p, %j) : (!llvm.ptr, i64) -> i8
      %ne = arith.cmpi ne, %x, %b : i8
      scf.yield %ne : i1
    } else {
      %f = arith.constant false
      scf.yield %f : i1
    }
    %res = arith.select %more, %j, %m1 : i64
    scf.condition(%go) %res : i64
  } do {
  ^bb0(%j: i64):
    scf.yield %j : i64
  }
  return %r : i64
}

// the first place the n bytes at q appear in [from, to), or -1
func.func @search(%p: !llvm.ptr, %from: i64, %to: i64, %q: !llvm.ptr, %n: i64) -> i64 {
  %m1 = arith.constant -1 : i64
  %len = arith.subi %to, %from : i64
  %short = arith.cmpi slt, %len, %n : i64
  %r = scf.if %short -> (i64) {
    scf.yield %m1 : i64
  } else {
    %start = func.call @off(%p, %from) : (!llvm.ptr, i64) -> !llvm.ptr
    %hit = llvm.call @memmem(%start, %len, %q, %n) : (!llvm.ptr, i64, !llvm.ptr, i64) -> !llvm.ptr
    %null = llvm.mlir.zero : !llvm.ptr
    %miss = llvm.icmp "eq" %hit, %null : !llvm.ptr
    %ri = scf.if %miss -> (i64) {
      scf.yield %m1 : i64
    } else {
      %hi = llvm.ptrtoint %hit : !llvm.ptr to i64
      %pi = llvm.ptrtoint %p : !llvm.ptr to i64
      %d = arith.subi %hi, %pi : i64
      scf.yield %d : i64
    }
    scf.yield %ri : i64
  }
  return %r : i64
}

// a decimal at [from, to), read as atol reads one: blanks, a minus, digits; the first other byte ends it
func.func @number(%p: !llvm.ptr, %from: i64, %to: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c9 = arith.constant 9 : i64
  %c10 = arith.constant 10 : i64
  %c48 = arith.constant 48 : i64
  %sp = arith.constant 32 : i8
  %minus = arith.constant 45 : i8
  %false = arith.constant false
  %i0 = scf.while (%i = %from) : (i64) -> i64 {
    %in = arith.cmpi slt, %i, %to : i64
    %go = scf.if %in -> (i1) {
      %x = func.call @at(%p, %i) : (!llvm.ptr, i64) -> i8
      %b = arith.cmpi eq, %x, %sp : i8
      scf.yield %b : i1
    } else {
      scf.yield %false : i1
    }
    scf.condition(%go) %i : i64
  } do {
  ^bb0(%i: i64):
    %n = arith.addi %i, %c1 : i64
    scf.yield %n : i64
  }
  %in0 = arith.cmpi slt, %i0, %to : i64
  %neg = scf.if %in0 -> (i1) {
    %x = func.call @at(%p, %i0) : (!llvm.ptr, i64) -> i8
    %m = arith.cmpi eq, %x, %minus : i8
    scf.yield %m : i1
  } else {
    scf.yield %false : i1
  }
  %i0n = arith.addi %i0, %c1 : i64
  %i1 = arith.select %neg, %i0n, %i0 : i64
  %res:3 = scf.while (%i = %i1, %v = %c0) : (i64, i64) -> (i64, i64, i64) {
    %in = arith.cmpi slt, %i, %to : i64
    %dig:2 = scf.if %in -> (i1, i64) {
      %x = func.call @at(%p, %i) : (!llvm.ptr, i64) -> i8
      %xz = arith.extui %x : i8 to i64
      %d = arith.subi %xz, %c48 : i64
      %isd = arith.cmpi ule, %d, %c9 : i64
      scf.yield %isd, %d : i1, i64
    } else {
      scf.yield %false, %c0 : i1, i64
    }
    scf.condition(%dig#0) %i, %v, %dig#1 : i64, i64, i64
  } do {
  ^bb0(%i: i64, %v: i64, %d: i64):
    %n = arith.addi %i, %c1 : i64
    %v10 = arith.muli %v, %c10 : i64
    %nv = arith.addi %v10, %d : i64
    scf.yield %n, %nv : i64, i64
  }
  %negv = arith.subi %c0, %res#1 : i64
  %r = arith.select %neg, %negv, %res#1 : i64
  return %r : i64
}



// ---- the builder: one growing buffer; a reply is taken out of it whole

llvm.mlir.global internal @ob_p() : !llvm.ptr {
  %0 = llvm.mlir.zero : !llvm.ptr
  llvm.return %0 : !llvm.ptr
}
llvm.mlir.global internal @ob_n(0 : i64) : i64
llvm.mlir.global internal @ob_cap(0 : i64) : i64

// room for k more bytes: where they go
func.func @ob_room(%k: i64) -> !llvm.ptr {
  %pp = llvm.mlir.addressof @ob_p : !llvm.ptr
  %np = llvm.mlir.addressof @ob_n : !llvm.ptr
  %cp = llvm.mlir.addressof @ob_cap : !llvm.ptr
  %p = llvm.load %pp : !llvm.ptr -> !llvm.ptr
  %n = llvm.load %np : !llvm.ptr -> i64
  %cap = llvm.load %cp : !llvm.ptr -> i64
  %need = arith.addi %n, %k : i64
  %grow = arith.cmpi sgt, %need, %cap : i64
  %q = scf.if %grow -> (!llvm.ptr) {
    %c2 = arith.constant 2 : i64
    %c4096 = arith.constant 4096 : i64
    %dbl = arith.muli %cap, %c2 : i64
    %a = arith.maxsi %dbl, %need : i64
    %newcap = arith.maxsi %a, %c4096 : i64
    %r = llvm.call @realloc(%p, %newcap) : (!llvm.ptr, i64) -> !llvm.ptr
    llvm.store %r, %pp : !llvm.ptr, !llvm.ptr
    llvm.store %newcap, %cp : i64, !llvm.ptr
    scf.yield %r : !llvm.ptr
  } else {
    scf.yield %p : !llvm.ptr
  }
  %end = func.call @off(%q, %n) : (!llvm.ptr, i64) -> !llvm.ptr
  return %end : !llvm.ptr
}

func.func @ob_used(%k: i64) {
  %np = llvm.mlir.addressof @ob_n : !llvm.ptr
  %n = llvm.load %np : !llvm.ptr -> i64
  %m = arith.addi %n, %k : i64
  llvm.store %m, %np : i64, !llvm.ptr
  return
}

func.func @ob_len() -> i64 {
  %np = llvm.mlir.addressof @ob_n : !llvm.ptr
  %n = llvm.load %np : !llvm.ptr -> i64
  return %n : i64
}

func.func @ob_base() -> !llvm.ptr {
  %pp = llvm.mlir.addressof @ob_p : !llvm.ptr
  %p = llvm.load %pp : !llvm.ptr -> !llvm.ptr
  return %p : !llvm.ptr
}

// begin again with gap bytes of room in front
func.func @ob_start(%gap: i64) {
  %np = llvm.mlir.addressof @ob_n : !llvm.ptr
  %c0 = arith.constant 0 : i64
  llvm.store %c0, %np : i64, !llvm.ptr
  %r = func.call @ob_room(%gap) : (i64) -> !llvm.ptr
  func.call @ob_used(%gap) : (i64) -> ()
  return
}

// the buffer, which is the caller's now; the builder is empty
func.func @ob_take() -> !llvm.ptr {
  %pp = llvm.mlir.addressof @ob_p : !llvm.ptr
  %np = llvm.mlir.addressof @ob_n : !llvm.ptr
  %cp = llvm.mlir.addressof @ob_cap : !llvm.ptr
  %p = llvm.load %pp : !llvm.ptr -> !llvm.ptr
  %null = llvm.mlir.zero : !llvm.ptr
  %c0 = arith.constant 0 : i64
  llvm.store %null, %pp : !llvm.ptr, !llvm.ptr
  llvm.store %c0, %np : i64, !llvm.ptr
  llvm.store %c0, %cp : i64, !llvm.ptr
  return %p : !llvm.ptr
}

func.func @ob_bytes(%src: !llvm.ptr, %k: i64) {
  %end = func.call @ob_room(%k) : (i64) -> !llvm.ptr
  %r = llvm.call @memcpy(%end, %src, %k) : (!llvm.ptr, !llvm.ptr, i64) -> !llvm.ptr
  func.call @ob_used(%k) : (i64) -> ()
  return
}

func.func @ob_piece(%base: !llvm.ptr, %t: i64) {
  %s = func.call @tw_s(%t) : (i64) -> i64
  %n = func.call @tw_n(%t) : (i64) -> i64
  %src = func.call @off(%base, %s) : (!llvm.ptr, i64) -> !llvm.ptr
  func.call @ob_bytes(%src, %n) : (!llvm.ptr, i64) -> ()
  return
}

func.func @ob_byte(%c: i8) {
  %c1 = arith.constant 1 : i64
  %end = func.call @ob_room(%c1) : (i64) -> !llvm.ptr
  llvm.store %c, %end : i8, !llvm.ptr
  func.call @ob_used(%c1) : (i64) -> ()
  return
}

// v as printf's %ld writes it: text.mlir's decimal, written into the room
func.func @ob_i64(%v: i64) {
  %one = arith.constant 1 : i32
  %c24 = arith.constant 24 : i64
  %dst = func.call @ob_room(%c24) : (i64) -> !llvm.ptr
  %into = llvm.alloca %one x !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)> : (i32) -> !llvm.ptr
  func.call @view(%into, %dst, %c24) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %k = llvm.call @_mlir_ciface_decimal(%v, %into) : (i64, !llvm.ptr) -> i64
  func.call @ob_used(%k) : (i64) -> ()
  return
}

func.func @ob_f64(%v: f64) {
  %room = arith.constant 400 : i64
  %end = func.call @ob_room(%room) : (i64) -> !llvm.ptr
  %fmt = llvm.mlir.addressof @k_f : !llvm.ptr
  %r = llvm.call @snprintf(%end, %room, %fmt, %v) vararg(!llvm.func<i32 (ptr, i64, ptr, ...)>) : (!llvm.ptr, i64, !llvm.ptr, f64) -> i32
  %k = arith.extsi %r : i32 to i64
  func.call @ob_used(%k) : (i64) -> ()
  return
}

// the piece as the inside of a JSON string: text.mlir's json_escape, written into the room (six bytes a byte at most)
func.func @ob_esc(%base: !llvm.ptr, %t: i64) {
  %one = arith.constant 1 : i32
  %c6 = arith.constant 6 : i64
  %s = func.call @tw_s(%t) : (i64) -> i64
  %n = func.call @tw_n(%t) : (i64) -> i64
  %room = arith.muli %n, %c6 : i64
  %dst = func.call @ob_room(%room) : (i64) -> !llvm.ptr
  %src = func.call @off(%base, %s) : (!llvm.ptr, i64) -> !llvm.ptr
  %from = llvm.alloca %one x !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)> : (i32) -> !llvm.ptr
  func.call @view(%from, %src, %n) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %into = llvm.alloca %one x !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)> : (i32) -> !llvm.ptr
  func.call @view(%into, %dst, %room) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %k = llvm.call @_mlir_ciface_json_escape(%from, %into) : (!llvm.ptr, !llvm.ptr) -> i64
  func.call @ob_used(%k) : (i64) -> ()
  return
}

// the piece as a JSON string: "..." escaped
func.func @ob_quoted(%base: !llvm.ptr, %t: i64) {
  %q = arith.constant 34 : i8
  func.call @ob_byte(%q) : (i8) -> ()
  func.call @ob_esc(%base, %t) : (!llvm.ptr, i64) -> ()
  func.call @ob_byte(%q) : (i8) -> ()
  return
}

