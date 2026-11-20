// Ed25519 signature verification (RFC 8032), hollowed from lib/Store/Ed25519.cpp (after TweetNaCl's crypto_sign_open)
// into MLIR: the field arithmetic over GF(2^255-19) as 16 signed 64-bit limbs (gf = memref<16xi64>: set/car/sel/pack/
// neq/par/unpack/A/Z/M/S/inv/pow2523), the point arithmetic in extended coordinates (add/cswap/pack/scalarmult/
// scalarbase/unpackneg), the scalar reduction mod L (modL/reduce), the canonical-S check, the SHA-512 of R || A || M
// (through Sha512.mlir's entries beside it) and the final comparison.  The base64 decoding of the signature and the key
// (Ed25519.cpp's old unbase64: '=' ends the data, any other byte outside the standard alphabet makes it empty) is here
// too, so lib/Store/Ed25519.cpp keeps only the bridge ed25519VerifyBase64 -> mlnix_ed25519_verify_b64.
//
// Entries (C ABI, nothing allocated on the heap, nothing thrown):
//   mlnix_ed25519_verify(sig, siglen, msg, msglen, key, keylen) -> 1 valid / 0 not   (raw bytes; sig 64, key 32)
//   mlnix_ed25519_verify_b64(sig, siglen, msg, msglen, key, keylen) -> 1 / 0          (sig and key in base64)
// The canonical-S check (S < L, little-endian) is a trikeshed.fold over S's bytes whose accumulator carries the index
// and the order decided by the highest differing byte; neq and the final R comparison are trikeshed.compare over the
// packed bytes.  Every limb operation keeps the C++'s exact i64 arithmetic (arith shifts are shrsi where the C++
// shifted a signed i64), so intermediate values, not just results, are the same.  Helper names are module-unique (ed_*).
!gf = memref<16xi64>
!by = memref<32xi8>
!b = !trikeshed.series<i8>
!q = !trikeshed.series<i64>
!m = memref<?xi8, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

memref.global "private" constant @ed_gf0 : memref<16xi64> = dense<[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]>
memref.global "private" constant @ed_gf1 : memref<16xi64> = dense<[1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]>
memref.global "private" constant @ed_D : memref<16xi64> = dense<[30883, 4953, 19914, 30187, 55467, 16705, 2637, 112, 59544, 30585, 16505, 36039, 65139, 11119, 27886, 20995]>
memref.global "private" constant @ed_D2 : memref<16xi64> = dense<[61785, 9906, 39828, 60374, 45398, 33411, 5274, 224, 53552, 61171, 33010, 6542, 64743, 22239, 55772, 9222]>
memref.global "private" constant @ed_X : memref<16xi64> = dense<[54554, 36645, 11616, 51542, 42930, 38181, 51040, 26924, 56412, 64982, 57905, 49316, 21502, 52590, 14035, 8553]>
memref.global "private" constant @ed_Y : memref<16xi64> = dense<[26200, 26214, 26214, 26214, 26214, 26214, 26214, 26214, 26214, 26214, 26214, 26214, 26214, 26214, 26214, 26214]>
memref.global "private" constant @ed_I : memref<16xi64> = dense<[41136, 18958, 6951, 50414, 58488, 44335, 6150, 12099, 55207, 15867, 153, 11085, 57099, 20417, 9344, 11139]>
memref.global "private" constant @ed_L : memref<32xi64> = dense<[237, 211, 245, 92, 26, 99, 18, 88, 214, 156, 247, 162, 222, 249, 222, 20, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 16]>
memref.global "private" constant @ed_b64 : memref<256xi8> = dense<[-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 62, -1, -1, -1, 63, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, -1, -1, -1, -1, -1, -1, -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, -1, -1, -1, -1, -1, -1, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1]>

func.func private @mlnix_sha512_init(!llvm.ptr)
func.func private @mlnix_sha512_update(!llvm.ptr, !llvm.ptr, i64)
func.func private @mlnix_sha512_final(!llvm.ptr, !llvm.ptr)

// the descriptor of n i8 cells at p
func.func private @ed_desc(%p: !llvm.ptr, %n: i64) -> !d {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %u = llvm.mlir.undef : !d
  %a = llvm.insertvalue %p, %u[0] : !d
  %bb = llvm.insertvalue %p, %a[1] : !d
  %c = llvm.insertvalue %c0, %bb[2] : !d
  %e = llvm.insertvalue %n, %c[3, 0] : !d
  %f = llvm.insertvalue %c1, %e[4, 0] : !d
  return %f : !d
}

func.func private @ed_set(%r: !gf, %a: !gf) {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c16 = arith.constant 16 : index
  scf.for %i = %c0 to %c16 step %c1 {
    %x = memref.load %a[%i] : !gf
    memref.store %x, %r[%i] : !gf
  }
  return
}

// car25519: o[i] += 2^16; c = o[i] >> 16; o[(i+1) * (i<15)] += c - 1 + 37 (c - 1) (i==15); o[i] -= c << 16
func.func private @ed_car(%o: !gf) {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c15 = arith.constant 15 : index
  %c16 = arith.constant 16 : index
  %k1 = arith.constant 1 : i64
  %k16 = arith.constant 16 : i64
  %k37 = arith.constant 37 : i64
  %two16 = arith.constant 65536 : i64
  scf.for %i = %c0 to %c16 step %c1 {
    %oi = memref.load %o[%i] : !gf
    %oi1 = arith.addi %oi, %two16 : i64
    %c = arith.shrsi %oi1, %k16 : i64
    %last = arith.cmpi eq, %i, %c15 : index
    %ip1 = arith.addi %i, %c1 : index
    %t = arith.select %last, %c0, %ip1 : index
    %cm1 = arith.subi %c, %k1 : i64
    %m37 = arith.muli %cm1, %k37 : i64
    %sum = arith.addi %cm1, %m37 : i64
    %inc = arith.select %last, %sum, %cm1 : i64
    %ot = memref.load %o[%t] : !gf
    %ot2 = arith.addi %ot, %inc : i64
    memref.store %ot2, %o[%t] : !gf
    %cs = arith.shli %c, %k16 : i64
    %oi2 = arith.subi %oi1, %cs : i64
    memref.store %oi2, %o[%i] : !gf
  }
  return
}

// sel25519: swap p and q where b is 1 (c = ~(b - 1) masks the xor)
func.func private @ed_sel(%p: !gf, %q: !gf, %b: i64) {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c16 = arith.constant 16 : index
  %k1 = arith.constant 1 : i64
  %km1 = arith.constant -1 : i64
  %bm1 = arith.subi %b, %k1 : i64
  %c = arith.xori %bm1, %km1 : i64
  scf.for %i = %c0 to %c16 step %c1 {
    %pi = memref.load %p[%i] : !gf
    %qi = memref.load %q[%i] : !gf
    %x = arith.xori %pi, %qi : i64
    %t = arith.andi %c, %x : i64
    %pi2 = arith.xori %pi, %t : i64
    %qi2 = arith.xori %qi, %t : i64
    memref.store %pi2, %p[%i] : !gf
    memref.store %qi2, %q[%i] : !gf
  }
  return
}

// pack25519: three carries, two conditional subtractions of p, then 32 little-endian bytes
func.func private @ed_pack(%o: !by, %n: !gf) {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c2 = arith.constant 2 : index
  %c14 = arith.constant 14 : index
  %c15 = arith.constant 15 : index
  %c16 = arith.constant 16 : index
  %k1 = arith.constant 1 : i64
  %k8 = arith.constant 8 : i64
  %k16 = arith.constant 16 : i64
  %kffed = arith.constant 65517 : i64
  %kffff = arith.constant 65535 : i64
  %k7fff = arith.constant 32767 : i64
  %m = memref.alloca() : !gf
  %t = memref.alloca() : !gf
  func.call @ed_set(%t, %n) : (!gf, !gf) -> ()
  func.call @ed_car(%t) : (!gf) -> ()
  func.call @ed_car(%t) : (!gf) -> ()
  func.call @ed_car(%t) : (!gf) -> ()
  scf.for %j = %c0 to %c2 step %c1 {
    %t0 = memref.load %t[%c0] : !gf
    %m0 = arith.subi %t0, %kffed : i64
    memref.store %m0, %m[%c0] : !gf
    scf.for %i = %c1 to %c15 step %c1 {
      %im1 = arith.subi %i, %c1 : index
      %ti = memref.load %t[%i] : !gf
      %mp = memref.load %m[%im1] : !gf
      %mps = arith.shrsi %mp, %k16 : i64
      %bit = arith.andi %mps, %k1 : i64
      %u = arith.subi %ti, %kffff : i64
      %mi = arith.subi %u, %bit : i64
      memref.store %mi, %m[%i] : !gf
      %mp2 = arith.andi %mp, %kffff : i64
      memref.store %mp2, %m[%im1] : !gf
    }
    %t15 = memref.load %t[%c15] : !gf
    %m14 = memref.load %m[%c14] : !gf
    %m14s = arith.shrsi %m14, %k16 : i64
    %bit14 = arith.andi %m14s, %k1 : i64
    %u15 = arith.subi %t15, %k7fff : i64
    %m15 = arith.subi %u15, %bit14 : i64
    memref.store %m15, %m[%c15] : !gf
    %m15s = arith.shrsi %m15, %k16 : i64
    %b = arith.andi %m15s, %k1 : i64
    %m14b = arith.andi %m14, %kffff : i64
    memref.store %m14b, %m[%c14] : !gf
    %nb = arith.subi %k1, %b : i64
    func.call @ed_sel(%t, %m, %nb) : (!gf, !gf, i64) -> ()
  }
  scf.for %i = %c0 to %c16 step %c1 {
    %ti = memref.load %t[%i] : !gf
    %lo = arith.trunci %ti : i64 to i8
    %ths = arith.shrsi %ti, %k8 : i64
    %hi = arith.trunci %ths : i64 to i8
    %o0 = arith.muli %i, %c2 : index
    %o1 = arith.addi %o0, %c1 : index
    memref.store %lo, %o[%o0] : !by
    memref.store %hi, %o[%o1] : !by
  }
  return
}

// neq25519: the packed bytes differ
func.func private @ed_neq(%a: !gf, %b: !gf) -> i1 {
  %c = memref.alloca() : !by
  %d = memref.alloca() : !by
  func.call @ed_pack(%c, %a) : (!by, !gf) -> ()
  func.call @ed_pack(%d, %b) : (!by, !gf) -> ()
  %cm = memref.cast %c : !by to !m
  %dm = memref.cast %d : !by to !m
  %cs = builtin.unrealized_conversion_cast %cm : !m to !b
  %ds = builtin.unrealized_conversion_cast %dm : !m to !b
  %ord = trikeshed.compare %cs, %ds unsigned : !b, !b
  %z = arith.constant 0 : i32
  %ne = arith.cmpi ne, %ord, %z : i32
  return %ne : i1
}

// par25519: the low bit of the packed value
func.func private @ed_par(%a: !gf) -> i64 {
  %c0 = arith.constant 0 : index
  %k1 = arith.constant 1 : i64
  %d = memref.alloca() : !by
  func.call @ed_pack(%d, %a) : (!by, !gf) -> ()
  %d0 = memref.load %d[%c0] : !by
  %d064 = arith.extui %d0 : i8 to i64
  %r = arith.andi %d064, %k1 : i64
  return %r : i64
}

func.func private @ed_unpack(%o: !gf, %n: !by) {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c2 = arith.constant 2 : index
  %c15 = arith.constant 15 : index
  %c16 = arith.constant 16 : index
  %k8 = arith.constant 8 : i64
  %k7fff = arith.constant 32767 : i64
  scf.for %i = %c0 to %c16 step %c1 {
    %i0 = arith.muli %i, %c2 : index
    %i1 = arith.addi %i0, %c1 : index
    %lo = memref.load %n[%i0] : !by
    %hi = memref.load %n[%i1] : !by
    %lo64 = arith.extui %lo : i8 to i64
    %hi64 = arith.extui %hi : i8 to i64
    %his = arith.shli %hi64, %k8 : i64
    %v = arith.addi %lo64, %his : i64
    memref.store %v, %o[%i] : !gf
  }
  %o15 = memref.load %o[%c15] : !gf
  %o15m = arith.andi %o15, %k7fff : i64
  memref.store %o15m, %o[%c15] : !gf
  return
}

func.func private @ed_A(%o: !gf, %a: !gf, %b: !gf) {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c16 = arith.constant 16 : index
  scf.for %i = %c0 to %c16 step %c1 {
    %x = memref.load %a[%i] : !gf
    %y = memref.load %b[%i] : !gf
    %s = arith.addi %x, %y : i64
    memref.store %s, %o[%i] : !gf
  }
  return
}

func.func private @ed_Z(%o: !gf, %a: !gf, %b: !gf) {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c16 = arith.constant 16 : index
  scf.for %i = %c0 to %c16 step %c1 {
    %x = memref.load %a[%i] : !gf
    %y = memref.load %b[%i] : !gf
    %s = arith.subi %x, %y : i64
    memref.store %s, %o[%i] : !gf
  }
  return
}

// M: the schoolbook product into t[31], the high limbs folded in times 38, two carries.  o may be a or b.
func.func private @ed_M(%o: !gf, %a: !gf, %b: !gf) {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c15 = arith.constant 15 : index
  %c16 = arith.constant 16 : index
  %c31 = arith.constant 31 : index
  %z = arith.constant 0 : i64
  %k38 = arith.constant 38 : i64
  %t = memref.alloca() : memref<31xi64>
  scf.for %i = %c0 to %c31 step %c1 {
    memref.store %z, %t[%i] : memref<31xi64>
  }
  scf.for %i = %c0 to %c16 step %c1 {
    %ai = memref.load %a[%i] : !gf
    scf.for %j = %c0 to %c16 step %c1 {
      %bj = memref.load %b[%j] : !gf
      %ij = arith.addi %i, %j : index
      %tij = memref.load %t[%ij] : memref<31xi64>
      %p = arith.muli %ai, %bj : i64
      %s = arith.addi %tij, %p : i64
      memref.store %s, %t[%ij] : memref<31xi64>
    }
  }
  scf.for %i = %c0 to %c15 step %c1 {
    %i16 = arith.addi %i, %c16 : index
    %hi = memref.load %t[%i16] : memref<31xi64>
    %ti = memref.load %t[%i] : memref<31xi64>
    %h38 = arith.muli %hi, %k38 : i64
    %s = arith.addi %ti, %h38 : i64
    memref.store %s, %t[%i] : memref<31xi64>
  }
  scf.for %i = %c0 to %c16 step %c1 {
    %ti = memref.load %t[%i] : memref<31xi64>
    memref.store %ti, %o[%i] : !gf
  }
  func.call @ed_car(%o) : (!gf) -> ()
  func.call @ed_car(%o) : (!gf) -> ()
  return
}

// inv25519: i^(p-2) by square-and-multiply, skipping the multiplies at bits 2 and 4
func.func private @ed_inv(%o: !gf, %i: !gf) {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c2 = arith.constant 2 : index
  %c4 = arith.constant 4 : index
  %c253 = arith.constant 253 : index
  %c254 = arith.constant 254 : index
  %c = memref.alloca() : !gf
  func.call @ed_set(%c, %i) : (!gf, !gf) -> ()
  scf.for %k = %c0 to %c254 step %c1 {
    %a = arith.subi %c253, %k : index
    func.call @ed_M(%c, %c, %c) : (!gf, !gf, !gf) -> ()
    %n2 = arith.cmpi ne, %a, %c2 : index
    %n4 = arith.cmpi ne, %a, %c4 : index
    %mul = arith.andi %n2, %n4 : i1
    scf.if %mul {
      func.call @ed_M(%c, %c, %i) : (!gf, !gf, !gf) -> ()
    }
  }
  func.call @ed_set(%o, %c) : (!gf, !gf) -> ()
  return
}

// pow2523: i^((p-5)/8), skipping the multiply at bit 1
func.func private @ed_pow2523(%o: !gf, %i: !gf) {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c250 = arith.constant 250 : index
  %c251 = arith.constant 251 : index
  %c = memref.alloca() : !gf
  func.call @ed_set(%c, %i) : (!gf, !gf) -> ()
  scf.for %k = %c0 to %c251 step %c1 {
    %a = arith.subi %c250, %k : index
    func.call @ed_M(%c, %c, %c) : (!gf, !gf, !gf) -> ()
    %mul = arith.cmpi ne, %a, %c1 : index
    scf.if %mul {
      func.call @ed_M(%c, %c, %i) : (!gf, !gf, !gf) -> ()
    }
  }
  func.call @ed_set(%o, %c) : (!gf, !gf) -> ()
  return
}

// add: p += q in extended coordinates (p may be q: every read of p and q comes before the writes to p)
func.func private @ed_add(%p0: !gf, %p1: !gf, %p2: !gf, %p3: !gf, %q0: !gf, %q1: !gf, %q2: !gf, %q3: !gf) {
  %a = memref.alloca() : !gf
  %b = memref.alloca() : !gf
  %c = memref.alloca() : !gf
  %d = memref.alloca() : !gf
  %t = memref.alloca() : !gf
  %e = memref.alloca() : !gf
  %f = memref.alloca() : !gf
  %g = memref.alloca() : !gf
  %h = memref.alloca() : !gf
  %D2 = memref.get_global @ed_D2 : !gf
  func.call @ed_Z(%a, %p1, %p0) : (!gf, !gf, !gf) -> ()
  func.call @ed_Z(%t, %q1, %q0) : (!gf, !gf, !gf) -> ()
  func.call @ed_M(%a, %a, %t) : (!gf, !gf, !gf) -> ()
  func.call @ed_A(%b, %p0, %p1) : (!gf, !gf, !gf) -> ()
  func.call @ed_A(%t, %q0, %q1) : (!gf, !gf, !gf) -> ()
  func.call @ed_M(%b, %b, %t) : (!gf, !gf, !gf) -> ()
  func.call @ed_M(%c, %p3, %q3) : (!gf, !gf, !gf) -> ()
  func.call @ed_M(%c, %c, %D2) : (!gf, !gf, !gf) -> ()
  func.call @ed_M(%d, %p2, %q2) : (!gf, !gf, !gf) -> ()
  func.call @ed_A(%d, %d, %d) : (!gf, !gf, !gf) -> ()
  func.call @ed_Z(%e, %b, %a) : (!gf, !gf, !gf) -> ()
  func.call @ed_Z(%f, %d, %c) : (!gf, !gf, !gf) -> ()
  func.call @ed_A(%g, %d, %c) : (!gf, !gf, !gf) -> ()
  func.call @ed_A(%h, %b, %a) : (!gf, !gf, !gf) -> ()
  func.call @ed_M(%p0, %e, %f) : (!gf, !gf, !gf) -> ()
  func.call @ed_M(%p1, %h, %g) : (!gf, !gf, !gf) -> ()
  func.call @ed_M(%p2, %g, %f) : (!gf, !gf, !gf) -> ()
  func.call @ed_M(%p3, %e, %h) : (!gf, !gf, !gf) -> ()
  return
}

func.func private @ed_cswap(%p0: !gf, %p1: !gf, %p2: !gf, %p3: !gf, %q0: !gf, %q1: !gf, %q2: !gf, %q3: !gf, %b: i64) {
  func.call @ed_sel(%p0, %q0, %b) : (!gf, !gf, i64) -> ()
  func.call @ed_sel(%p1, %q1, %b) : (!gf, !gf, i64) -> ()
  func.call @ed_sel(%p2, %q2, %b) : (!gf, !gf, i64) -> ()
  func.call @ed_sel(%p3, %q3, %b) : (!gf, !gf, i64) -> ()
  return
}

// pack: y/z with the parity of x/z in the top bit
func.func private @ed_packpt(%r: !by, %p0: !gf, %p1: !gf, %p2: !gf, %p3: !gf) {
  %c31 = arith.constant 31 : index
  %k7 = arith.constant 7 : i64
  %tx = memref.alloca() : !gf
  %ty = memref.alloca() : !gf
  %zi = memref.alloca() : !gf
  func.call @ed_inv(%zi, %p2) : (!gf, !gf) -> ()
  func.call @ed_M(%tx, %p0, %zi) : (!gf, !gf, !gf) -> ()
  func.call @ed_M(%ty, %p1, %zi) : (!gf, !gf, !gf) -> ()
  func.call @ed_pack(%r, %ty) : (!by, !gf) -> ()
  %par = func.call @ed_par(%tx) : (!gf) -> i64
  %top = arith.shli %par, %k7 : i64
  %top8 = arith.trunci %top : i64 to i8
  %r31 = memref.load %r[%c31] : !by
  %r31x = arith.xori %r31, %top8 : i8
  memref.store %r31x, %r[%c31] : !by
  return
}

// scalarmult: the Montgomery ladder over the 256 bits of s, high bit first
func.func private @ed_scalarmult(%p0: !gf, %p1: !gf, %p2: !gf, %p3: !gf, %q0: !gf, %q1: !gf, %q2: !gf, %q3: !gf, %s: !by) {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c8 = arith.constant 8 : index
  %c255 = arith.constant 255 : index
  %c256 = arith.constant 256 : index
  %k1 = arith.constant 1 : i64
  %k7 = arith.constant 7 : i64
  %gf0 = memref.get_global @ed_gf0 : !gf
  %gf1 = memref.get_global @ed_gf1 : !gf
  func.call @ed_set(%p0, %gf0) : (!gf, !gf) -> ()
  func.call @ed_set(%p1, %gf1) : (!gf, !gf) -> ()
  func.call @ed_set(%p2, %gf1) : (!gf, !gf) -> ()
  func.call @ed_set(%p3, %gf0) : (!gf, !gf) -> ()
  scf.for %k = %c0 to %c256 step %c1 {
    %i = arith.subi %c255, %k : index
    %byi = arith.divui %i, %c8 : index
    %sb = memref.load %s[%byi] : !by
    %sb64 = arith.extui %sb : i8 to i64
    %i64 = arith.index_cast %i : index to i64
    %sh = arith.andi %i64, %k7 : i64
    %v = arith.shrui %sb64, %sh : i64
    %b = arith.andi %v, %k1 : i64
    func.call @ed_cswap(%p0, %p1, %p2, %p3, %q0, %q1, %q2, %q3, %b) : (!gf, !gf, !gf, !gf, !gf, !gf, !gf, !gf, i64) -> ()
    func.call @ed_add(%q0, %q1, %q2, %q3, %p0, %p1, %p2, %p3) : (!gf, !gf, !gf, !gf, !gf, !gf, !gf, !gf) -> ()
    func.call @ed_add(%p0, %p1, %p2, %p3, %p0, %p1, %p2, %p3) : (!gf, !gf, !gf, !gf, !gf, !gf, !gf, !gf) -> ()
    func.call @ed_cswap(%p0, %p1, %p2, %p3, %q0, %q1, %q2, %q3, %b) : (!gf, !gf, !gf, !gf, !gf, !gf, !gf, !gf, i64) -> ()
  }
  return
}

func.func private @ed_scalarbase(%p0: !gf, %p1: !gf, %p2: !gf, %p3: !gf, %s: !by) {
  %q0 = memref.alloca() : !gf
  %q1 = memref.alloca() : !gf
  %q2 = memref.alloca() : !gf
  %q3 = memref.alloca() : !gf
  %X = memref.get_global @ed_X : !gf
  %Y = memref.get_global @ed_Y : !gf
  %gf1 = memref.get_global @ed_gf1 : !gf
  func.call @ed_set(%q0, %X) : (!gf, !gf) -> ()
  func.call @ed_set(%q1, %Y) : (!gf, !gf) -> ()
  func.call @ed_set(%q2, %gf1) : (!gf, !gf) -> ()
  func.call @ed_M(%q3, %X, %Y) : (!gf, !gf, !gf) -> ()
  func.call @ed_scalarmult(%p0, %p1, %p2, %p3, %q0, %q1, %q2, %q3, %s) : (!gf, !gf, !gf, !gf, !gf, !gf, !gf, !gf, !by) -> ()
  return
}

// modL: x (64 signed limbs of 8 bits) reduced mod L into r[0..32)
func.func private @ed_modL(%r: memref<64xi8>, %x: memref<64xi64>) {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c12 = arith.constant 12 : index
  %c31 = arith.constant 31 : index
  %c32 = arith.constant 32 : index
  %c63 = arith.constant 63 : index
  %z = arith.constant 0 : i64
  %k4 = arith.constant 4 : i64
  %k8 = arith.constant 8 : i64
  %k16 = arith.constant 16 : i64
  %k128 = arith.constant 128 : i64
  %k255 = arith.constant 255 : i64
  %Lg = memref.get_global @ed_L : memref<32xi64>
  %L = trikeshed.text %Lg : memref<32xi64> -> !q
  scf.for %k = %c0 to %c32 step %c1 {
    %i = arith.subi %c63, %k : index
    %lo = arith.subi %i, %c32 : index
    %hi = arith.subi %i, %c12 : index
    %xi = memref.load %x[%i] : memref<64xi64>
    %x16 = arith.muli %xi, %k16 : i64
    %carry = scf.for %j = %lo to %hi step %c1 iter_args(%cy = %z) -> (i64) {
      %li = arith.subi %j, %lo : index
      %l = trikeshed.at %L[%li] : !q, index -> i64
      %xj = memref.load %x[%j] : memref<64xi64>
      %pr = arith.muli %x16, %l : i64
      %dl = arith.subi %cy, %pr : i64
      %xj2 = arith.addi %xj, %dl : i64
      %xr = arith.addi %xj2, %k128 : i64
      %cy2 = arith.shrsi %xr, %k8 : i64
      %cs = arith.shli %cy2, %k8 : i64
      %xj3 = arith.subi %xj2, %cs : i64
      memref.store %xj3, %x[%j] : memref<64xi64>
      scf.yield %cy2 : i64
    }
    %xh = memref.load %x[%hi] : memref<64xi64>
    %xh2 = arith.addi %xh, %carry : i64
    memref.store %xh2, %x[%hi] : memref<64xi64>
    memref.store %z, %x[%i] : memref<64xi64>
  }
  %carry2 = scf.for %j = %c0 to %c32 step %c1 iter_args(%cy = %z) -> (i64) {
    %x31 = memref.load %x[%c31] : memref<64xi64>
    %q4 = arith.shrsi %x31, %k4 : i64
    %l = trikeshed.at %L[%j] : !q, index -> i64
    %xj = memref.load %x[%j] : memref<64xi64>
    %pr = arith.muli %q4, %l : i64
    %dl = arith.subi %cy, %pr : i64
    %xj2 = arith.addi %xj, %dl : i64
    %cy2 = arith.shrsi %xj2, %k8 : i64
    %xj3 = arith.andi %xj2, %k255 : i64
    memref.store %xj3, %x[%j] : memref<64xi64>
    scf.yield %cy2 : i64
  }
  scf.for %j = %c0 to %c32 step %c1 {
    %l = trikeshed.at %L[%j] : !q, index -> i64
    %xj = memref.load %x[%j] : memref<64xi64>
    %pr = arith.muli %carry2, %l : i64
    %xj2 = arith.subi %xj, %pr : i64
    memref.store %xj2, %x[%j] : memref<64xi64>
  }
  scf.for %i = %c0 to %c32 step %c1 {
    %ip1 = arith.addi %i, %c1 : index
    %xi = memref.load %x[%i] : memref<64xi64>
    %xn = memref.load %x[%ip1] : memref<64xi64>
    %sh = arith.shrsi %xi, %k8 : i64
    %xn2 = arith.addi %xn, %sh : i64
    memref.store %xn2, %x[%ip1] : memref<64xi64>
    %ri = arith.andi %xi, %k255 : i64
    %r8 = arith.trunci %ri : i64 to i8
    memref.store %r8, %r[%i] : memref<64xi8>
  }
  return
}

func.func private @ed_reduce(%r: memref<64xi8>) {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c64 = arith.constant 64 : index
  %z8 = arith.constant 0 : i8
  %x = memref.alloca() : memref<64xi64>
  scf.for %i = %c0 to %c64 step %c1 {
    %ri = memref.load %r[%i] : memref<64xi8>
    %v = arith.extui %ri : i8 to i64
    memref.store %v, %x[%i] : memref<64xi64>
    memref.store %z8, %r[%i] : memref<64xi8>
  }
  func.call @ed_modL(%r, %x) : (memref<64xi8>, memref<64xi64>) -> ()
  return
}

// unpackneg: -A from its 32 bytes; 0 when y has no square root x (not a point)
func.func private @ed_unpackneg(%r0: !gf, %r1: !gf, %r2: !gf, %r3: !gf, %p: !by) -> i1 {
  %c31 = arith.constant 31 : index
  %k7 = arith.constant 7 : i64
  %t = memref.alloca() : !gf
  %chk = memref.alloca() : !gf
  %num = memref.alloca() : !gf
  %den = memref.alloca() : !gf
  %den2 = memref.alloca() : !gf
  %den4 = memref.alloca() : !gf
  %den6 = memref.alloca() : !gf
  %gf0 = memref.get_global @ed_gf0 : !gf
  %gf1 = memref.get_global @ed_gf1 : !gf
  %D = memref.get_global @ed_D : !gf
  %I = memref.get_global @ed_I : !gf
  func.call @ed_set(%r2, %gf1) : (!gf, !gf) -> ()
  func.call @ed_unpack(%r1, %p) : (!gf, !by) -> ()
  func.call @ed_M(%num, %r1, %r1) : (!gf, !gf, !gf) -> ()
  func.call @ed_M(%den, %num, %D) : (!gf, !gf, !gf) -> ()
  func.call @ed_Z(%num, %num, %r2) : (!gf, !gf, !gf) -> ()
  func.call @ed_A(%den, %r2, %den) : (!gf, !gf, !gf) -> ()
  func.call @ed_M(%den2, %den, %den) : (!gf, !gf, !gf) -> ()
  func.call @ed_M(%den4, %den2, %den2) : (!gf, !gf, !gf) -> ()
  func.call @ed_M(%den6, %den4, %den2) : (!gf, !gf, !gf) -> ()
  func.call @ed_M(%t, %den6, %num) : (!gf, !gf, !gf) -> ()
  func.call @ed_M(%t, %t, %den) : (!gf, !gf, !gf) -> ()
  func.call @ed_pow2523(%t, %t) : (!gf, !gf) -> ()
  func.call @ed_M(%t, %t, %num) : (!gf, !gf, !gf) -> ()
  func.call @ed_M(%t, %t, %den) : (!gf, !gf, !gf) -> ()
  func.call @ed_M(%t, %t, %den) : (!gf, !gf, !gf) -> ()
  func.call @ed_M(%r0, %t, %den) : (!gf, !gf, !gf) -> ()
  func.call @ed_M(%chk, %r0, %r0) : (!gf, !gf, !gf) -> ()
  func.call @ed_M(%chk, %chk, %den) : (!gf, !gf, !gf) -> ()
  %ne1 = func.call @ed_neq(%chk, %num) : (!gf, !gf) -> i1
  scf.if %ne1 {
    func.call @ed_M(%r0, %r0, %I) : (!gf, !gf, !gf) -> ()
  }
  func.call @ed_M(%chk, %r0, %r0) : (!gf, !gf, !gf) -> ()
  func.call @ed_M(%chk, %chk, %den) : (!gf, !gf, !gf) -> ()
  %ne2 = func.call @ed_neq(%chk, %num) : (!gf, !gf) -> i1
  %ok = scf.if %ne2 -> (i1) {
    %no = arith.constant 0 : i1
    scf.yield %no : i1
  } else {
    %par = func.call @ed_par(%r0) : (!gf) -> i64
    %p31 = memref.load %p[%c31] : !by
    %p3164 = arith.extui %p31 : i8 to i64
    %top = arith.shrui %p3164, %k7 : i64
    %same = arith.cmpi eq, %par, %top : i64
    scf.if %same {
      func.call @ed_Z(%r0, %gf0, %r0) : (!gf, !gf, !gf) -> ()
    }
    func.call @ed_M(%r3, %r0, %r1) : (!gf, !gf, !gf) -> ()
    %yes = arith.constant 1 : i1
    scf.yield %yes : i1
  }
  return %ok : i1
}

// the address of a stack buffer, for the C-ABI calls into Sha512.mlir
func.func private @ed_addr64(%a: memref<64xi8>) -> !llvm.ptr {
  %ix = memref.extract_aligned_pointer_as_index %a : memref<64xi8> -> index
  %i64 = arith.index_cast %ix : index to i64
  %p = llvm.inttoptr %i64 : i64 to !llvm.ptr
  return %p : !llvm.ptr
}

func.func @mlnix_ed25519_verify(%sm: !llvm.ptr, %smlen: i64, %msg: !llvm.ptr, %mlen: i64, %pk: !llvm.ptr, %pklen: i64) -> i32 {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c32 = arith.constant 32 : index
  %z32 = arith.constant 0 : i32
  %k0 = arith.constant 0 : i64
  %k1 = arith.constant 1 : i64
  %k2 = arith.constant 2 : i64
  %k3 = arith.constant 3 : i64
  %k32 = arith.constant 32 : i64
  %k64 = arith.constant 64 : i64
  %sz1 = arith.cmpi eq, %smlen, %k64 : i64
  %sz2 = arith.cmpi eq, %pklen, %k32 : i64
  %sizes = arith.andi %sz1, %sz2 : i1
  %res = scf.if %sizes -> (i32) {
    %smd = func.call @ed_desc(%sm, %k64) : (!llvm.ptr, i64) -> !d
    %smm = builtin.unrealized_conversion_cast %smd : !d to !m
    %sig = builtin.unrealized_conversion_cast %smm : !m to !b
    %S = trikeshed.slice %sig[%c32, %c32] : !b -> !b
    %Lg = memref.get_global @ed_L : memref<32xi64>
    %L = trikeshed.text %Lg : memref<32xi64> -> !q
    // S < L: the highest byte where S and L differ decides; a fold low to high, the index carried in acc >> 2,
    // the order so far (0 equal, 1 less, 2 greater) in acc & 3
    %ord = trikeshed.fold %S, %k0 : !b, i64 -> i64 {
    ^bb0(%acc: i64, %x: i8):
      %idx = arith.shrui %acc, %k2 : i64
      %st = arith.andi %acc, %k3 : i64
      %idxi = arith.index_cast %idx : i64 to index
      %l = trikeshed.at %L[%idxi] : !q, index -> i64
      %xv = arith.extui %x : i8 to i64
      %lt = arith.cmpi ult, %xv, %l : i64
      %gt = arith.cmpi ugt, %xv, %l : i64
      %st1 = arith.select %gt, %k2, %st : i64
      %st2 = arith.select %lt, %k1, %st1 : i64
      %nidx = arith.addi %idx, %k1 : i64
      %nsh = arith.shli %nidx, %k2 : i64
      %nacc = arith.ori %nsh, %st2 : i64
      trikeshed.yield %nacc : i64
    }
    %ordst = arith.andi %ord, %k3 : i64
    %less = arith.cmpi eq, %ordst, %k1 : i64
    %r1 = scf.if %less -> (i32) {
      %q0 = memref.alloca() : !gf
      %q1 = memref.alloca() : !gf
      %q2 = memref.alloca() : !gf
      %q3 = memref.alloca() : !gf
      %pkb = memref.alloca() : !by
      %pkd = func.call @ed_desc(%pk, %k32) : (!llvm.ptr, i64) -> !d
      %pkm = builtin.unrealized_conversion_cast %pkd : !d to !m
      %pks = builtin.unrealized_conversion_cast %pkm : !m to !b
      %pkbm = memref.cast %pkb : !by to !m
      %pkn = trikeshed.drain %pks, %pkbm : !b, !m -> index
      %onc = func.call @ed_unpackneg(%q0, %q1, %q2, %q3, %pkb) : (!gf, !gf, !gf, !gf, !by) -> i1
      %r2 = scf.if %onc -> (i32) {
        %p0 = memref.alloca() : !gf
        %p1 = memref.alloca() : !gf
        %p2 = memref.alloca() : !gf
        %p3 = memref.alloca() : !gf
        // h = SHA-512(R || A || M), as the old hashString of the three put one after the other
        %cx = memref.alloca() {alignment = 16 : i64} : memref<26xi64>
        %cxi = memref.extract_aligned_pointer_as_index %cx : memref<26xi64> -> index
        %cxi64 = arith.index_cast %cxi : index to i64
        %cxp = llvm.inttoptr %cxi64 : i64 to !llvm.ptr
        func.call @mlnix_sha512_init(%cxp) : (!llvm.ptr) -> ()
        func.call @mlnix_sha512_update(%cxp, %sm, %k32) : (!llvm.ptr, !llvm.ptr, i64) -> ()
        func.call @mlnix_sha512_update(%cxp, %pk, %k32) : (!llvm.ptr, !llvm.ptr, i64) -> ()
        func.call @mlnix_sha512_update(%cxp, %msg, %mlen) : (!llvm.ptr, !llvm.ptr, i64) -> ()
        %h = memref.alloca() : memref<64xi8>
        %hp = func.call @ed_addr64(%h) : (memref<64xi8>) -> !llvm.ptr
        func.call @mlnix_sha512_final(%cxp, %hp) : (!llvm.ptr, !llvm.ptr) -> ()
        func.call @ed_reduce(%h) : (memref<64xi8>) -> ()
        %hs = memref.alloca() : !by
        scf.for %i = %c0 to %c32 step %c1 {
          %hb = memref.load %h[%i] : memref<64xi8>
          memref.store %hb, %hs[%i] : !by
        }
        func.call @ed_scalarmult(%p0, %p1, %p2, %p3, %q0, %q1, %q2, %q3, %hs) : (!gf, !gf, !gf, !gf, !gf, !gf, !gf, !gf, !by) -> ()
        %sb = memref.alloca() : !by
        %sbm = memref.cast %sb : !by to !m
        %sbn = trikeshed.drain %S, %sbm : !b, !m -> index
        func.call @ed_scalarbase(%q0, %q1, %q2, %q3, %sb) : (!gf, !gf, !gf, !gf, !by) -> ()
        func.call @ed_add(%p0, %p1, %p2, %p3, %q0, %q1, %q2, %q3) : (!gf, !gf, !gf, !gf, !gf, !gf, !gf, !gf) -> ()
        %t = memref.alloca() : !by
        func.call @ed_packpt(%t, %p0, %p1, %p2, %p3) : (!by, !gf, !gf, !gf, !gf) -> ()
        %R = trikeshed.slice %sig[%c0, %c32] : !b -> !b
        %tm = memref.cast %t : !by to !m
        %ts = builtin.unrealized_conversion_cast %tm : !m to !b
        %eq = trikeshed.compare %R, %ts unsigned : !b, !b
        %same = arith.cmpi eq, %eq, %z32 : i32
        %r3 = arith.extui %same : i1 to i32
        scf.yield %r3 : i32
      } else {
        scf.yield %z32 : i32
      }
      scf.yield %r2 : i32
    } else {
      scf.yield %z32 : i32
    }
    scf.yield %r1 : i32
  } else {
    scf.yield %z32 : i32
  }
  return %res : i32
}

// unbase64 into out (the first 64 bytes kept): the count of bytes decoded, or -1 on a byte outside the alphabet
// (the old C++ returned an empty Text there).  '=' ends the data; a 32-bit accumulator, a byte out per 8 bits held.
func.func private @ed_unb64(%p: !llvm.ptr, %n: i64, %out: memref<64xi8>) -> i64 {
  %k0 = arith.constant 0 : i64
  %k1 = arith.constant 1 : i64
  %k64 = arith.constant 64 : i64
  %km1 = arith.constant -1 : i64
  %z32 = arith.constant 0 : i32
  %one32 = arith.constant 1 : i32
  %two32 = arith.constant 2 : i32
  %six = arith.constant 6 : i32
  %eight = arith.constant 8 : i32
  %ff = arith.constant 255 : i32
  %eqc = arith.constant 61 : i8
  %dd = func.call @ed_desc(%p, %n) : (!llvm.ptr, i64) -> !d
  %dm = builtin.unrealized_conversion_cast %dd : !d to !m
  %in = builtin.unrealized_conversion_cast %dm : !m to !b
  %tab = memref.get_global @ed_b64 : memref<256xi8>
  %fin:5 = scf.while (%k = %k0, %acc = %z32, %bits = %z32, %cnt = %k0, %st = %z32) : (i64, i32, i32, i64, i32) -> (i64, i32, i32, i64, i32) {
    %inside = arith.cmpi ult, %k, %n : i64
    %running = arith.cmpi eq, %st, %z32 : i32
    %go = arith.andi %inside, %running : i1
    scf.condition(%go) %k, %acc, %bits, %cnt, %st : i64, i32, i32, i64, i32
  } do {
  ^bb0(%k: i64, %acc: i32, %bits: i32, %cnt: i64, %st: i32):
    %ki = arith.index_cast %k : i64 to index
    %c = trikeshed.at %in[%ki] : !b, index -> i8
    %isEq = arith.cmpi eq, %c, %eqc : i8
    %nx:4 = scf.if %isEq -> (i32, i32, i64, i32) {
      scf.yield %acc, %bits, %cnt, %one32 : i32, i32, i64, i32
    } else {
      %cu = arith.extui %c : i8 to i32
      %cix = arith.index_cast %cu : i32 to index
      %v8 = memref.load %tab[%cix] : memref<256xi8>
      %v = arith.extsi %v8 : i8 to i32
      %bad = arith.cmpi slt, %v, %z32 : i32
      %ny:4 = scf.if %bad -> (i32, i32, i64, i32) {
        scf.yield %acc, %bits, %cnt, %two32 : i32, i32, i64, i32
      } else {
        %as = arith.shli %acc, %six : i32
        %acc2 = arith.ori %as, %v : i32
        %bits2 = arith.addi %bits, %six : i32
        %emit = arith.cmpi sge, %bits2, %eight : i32
        %nz:2 = scf.if %emit -> (i32, i64) {
          %bits3 = arith.subi %bits2, %eight : i32
          %sh = arith.shrui %acc2, %bits3 : i32
          %byte = arith.andi %sh, %ff : i32
          %b8 = arith.trunci %byte : i32 to i8
          %room = arith.cmpi ult, %cnt, %k64 : i64
          scf.if %room {
            %ci = arith.index_cast %cnt : i64 to index
            memref.store %b8, %out[%ci] : memref<64xi8>
          }
          %cnt2 = arith.addi %cnt, %k1 : i64
          scf.yield %bits3, %cnt2 : i32, i64
        } else {
          scf.yield %bits2, %cnt : i32, i64
        }
        scf.yield %acc2, %nz#0, %nz#1, %z32 : i32, i32, i64, i32
      }
      scf.yield %ny#0, %ny#1, %ny#2, %ny#3 : i32, i32, i64, i32
    }
    %k2 = arith.addi %k, %k1 : i64
    scf.yield %k2, %nx#0, %nx#1, %nx#2, %nx#3 : i64, i32, i32, i64, i32
  }
  %invalid = arith.cmpi eq, %fin#4, %two32 : i32
  %r = arith.select %invalid, %km1, %fin#3 : i64
  return %r : i64
}

// ed25519VerifyBase64: both decoded here; a bad base64 is an empty text, rejected by the sizes as before
func.func @mlnix_ed25519_verify_b64(%sig: !llvm.ptr, %siglen: i64, %msg: !llvm.ptr, %mlen: i64, %key: !llvm.ptr, %keylen: i64) -> i32 {
  %k0 = arith.constant 0 : i64
  %sb = memref.alloca() : memref<64xi8>
  %kb = memref.alloca() : memref<64xi8>
  %ns = func.call @ed_unb64(%sig, %siglen, %sb) : (!llvm.ptr, i64, memref<64xi8>) -> i64
  %nk = func.call @ed_unb64(%key, %keylen, %kb) : (!llvm.ptr, i64, memref<64xi8>) -> i64
  %sbad = arith.cmpi slt, %ns, %k0 : i64
  %kbad = arith.cmpi slt, %nk, %k0 : i64
  %ns2 = arith.select %sbad, %k0, %ns : i64
  %nk2 = arith.select %kbad, %k0, %nk : i64
  %sp = func.call @ed_addr64(%sb) : (memref<64xi8>) -> !llvm.ptr
  %kp = func.call @ed_addr64(%kb) : (memref<64xi8>) -> !llvm.ptr
  %r = func.call @mlnix_ed25519_verify(%sp, %ns2, %msg, %mlen, %kp, %nk2) : (!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64) -> i32
  return %r : i32
}
