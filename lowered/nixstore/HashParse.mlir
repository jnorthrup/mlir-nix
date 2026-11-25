// The hash-name parser and the hash compression of lib/Store/Hash.cpp, hollowed into the TrikeShed dialect: parseHash
// (the `algo:` and `algo-` prefixes, the type checks, parseRest's length dispatch) and compressHash (the XOR fold of the
// digest into newSize bytes).  Hash.cpp keeps the bridges: it sizes the scratch, passes the Hash's bytes, and throws the
// error wording (the code and the algorithm index come back in `info`).  The hex digits, the nix32 and base64 decoders
// are Decoders.mlir's entries (mlnix_nix32_decode, mlnix_base64_decode), called here as C-ABI symbols.
//
// nixstore_ts_parsehash(s, n, known, out, scratch, info) -> code; `known` is the context's HashAlgo or -1.
//   0 ok (out holds the digest, info[0] the algorithm), 1 unknown algorithm before ':' (info[1] = the colon's index),
//   2 the prefix's algorithm is not the known one, 3 no algorithm at all, 4 wrong length (or a base64 digest of the
//   wrong size), 5 a non-hex character in base-16, 6 an invalid nix32 digit, 7 an invalid SRI digest (base64).
//   info[0] = the algorithm (HashAlgo's order: md5, sha1, sha256, sha512) once one is decided; info[2] = the base64
//   decoder's count (scratch must hold n bytes).
// nixstore_ts_compress(in, n, newSize, out): out (64 bytes) is zeroed, then out[i % newSize] ^= in[i] for i < n.
//
// Nix semantics, byte for byte the old C++ (parseHash, parseRest, compressHash): the first ':' decides an explicit
// algorithm (an unknown name throws); without ':' a '-' whose prefix is an algorithm name makes an SRI (base64 only).
// A hex digest is 2*size characters, nix32 (8*size-1)/5+1, base64 ((4*size/3)+3)/4*4 (SRI: any base64 length).
//
// Every read is through trikeshed.at over the input series<i8>, guarded by the loop bound; the algorithm names are
// trikeshed.compare against constant texts; the byte stores are guarded.  Each entry returns a value and allocates nothing.
!s = !trikeshed.series<i8>
!m = memref<?xi8, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

memref.global "private" constant @hp_hex : memref<256xi8> =
  dense<[-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, -1, -1, -1, -1, -1, -1, -1, 10, 11, 12, 13, 14, 15, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 10, 11, 12, 13, 14, 15, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1]>
memref.global "private" constant @hp_md5 : memref<3xi8> = dense<[109, 100, 53]>
memref.global "private" constant @hp_sha1 : memref<4xi8> = dense<[115, 104, 97, 49]>
memref.global "private" constant @hp_sha256 : memref<6xi8> = dense<[115, 104, 97, 50, 53, 54]>
memref.global "private" constant @hp_sha512 : memref<6xi8> = dense<[115, 104, 97, 53, 49, 50]>

// Decoders.mlir's entries (1 valid, 0 invalid), called as C-ABI symbols
func.func private @mlnix_nix32_decode(!llvm.ptr, i64, i64, !llvm.ptr) -> i32
func.func private @mlnix_base64_decode(!llvm.ptr, i64, !llvm.ptr, !llvm.ptr) -> i32

// the descriptor of n i8 cells at p
func.func private @hp_desc(%p: !llvm.ptr, %n: i64) -> !d {
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

// the first index of ch in p[0, n), or n
func.func private @hp_find(%p: !llvm.ptr, %n: i64, %ch: i8) -> i64 {
  %d = func.call @hp_desc(%p, %n) : (!llvm.ptr, i64) -> !d
  %mm = builtin.unrealized_conversion_cast %d : !d to !m
  %ss = builtin.unrealized_conversion_cast %mm : !m to !s
  %zi = arith.constant 0 : index
  %oi = arith.constant 1 : index
  %true = arith.constant true
  %false = arith.constant false
  %ni = arith.index_cast %n : i64 to index
  %k, %f = scf.while (%k = %zi, %f = %false) : (index, i1) -> (index, i1) {
    %in = arith.cmpi ult, %k, %ni : index
    %nf = arith.xori %f, %true : i1
    %go = arith.andi %in, %nf : i1
    scf.condition(%go) %k, %f : index, i1
  } do {
  ^bb0(%k: index, %f: i1):
    %c = trikeshed.at %ss[%k] : !s, index -> i8
    %eq = arith.cmpi eq, %c, %ch : i8
    %k2 = arith.addi %k, %oi : index
    scf.yield %k2, %eq : index, i1
  }
  %km1 = arith.subi %k, %oi : index
  %r = arith.select %f, %km1, %k : index
  %r64 = arith.index_cast %r : index to i64
  return %r64 : i64
}

// hashAlgo's index for the name p[0, n) (md5 0, sha1 1, sha256 2, sha512 3), or -1 when it is none of them
func.func private @hp_algo(%p: !llvm.ptr, %n: i64) -> i64 {
  %d = func.call @hp_desc(%p, %n) : (!llvm.ptr, i64) -> !d
  %mm = builtin.unrealized_conversion_cast %d : !d to !m
  %ss = builtin.unrealized_conversion_cast %mm : !m to !s
  %g0 = memref.get_global @hp_md5 : memref<3xi8>
  %t0 = trikeshed.text %g0 : memref<3xi8> -> !s
  %g1 = memref.get_global @hp_sha1 : memref<4xi8>
  %t1 = trikeshed.text %g1 : memref<4xi8> -> !s
  %g2 = memref.get_global @hp_sha256 : memref<6xi8>
  %t2 = trikeshed.text %g2 : memref<6xi8> -> !s
  %g3 = memref.get_global @hp_sha512 : memref<6xi8>
  %t3 = trikeshed.text %g3 : memref<6xi8> -> !s
  %q0 = trikeshed.compare %ss, %t0 unsigned : !s, !s
  %q1 = trikeshed.compare %ss, %t1 unsigned : !s, !s
  %q2 = trikeshed.compare %ss, %t2 unsigned : !s, !s
  %q3 = trikeshed.compare %ss, %t3 unsigned : !s, !s
  %z = arith.constant 0 : i32
  %e0 = arith.cmpi eq, %q0, %z : i32
  %e1 = arith.cmpi eq, %q1, %z : i32
  %e2 = arith.cmpi eq, %q2, %z : i32
  %e3 = arith.cmpi eq, %q3, %z : i32
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %cm1 = arith.constant -1 : i64
  %r3 = arith.select %e3, %c3, %cm1 : i64
  %r2 = arith.select %e2, %c2, %r3 : i64
  %r1 = arith.select %e1, %c1, %r2 : i64
  %r = arith.select %e0, %c0, %r1 : i64
  return %r : i64
}

// parseRest: the digest of rest (rn bytes at rp) of algorithm `algo` (size sz), written to out.  sri: a base64 digest
// after `algo-`.  Returns the code of the header comment.
func.func private @hp_rest(%rp: !llvm.ptr, %rn: i64, %sri: i1, %sz: i64, %out: !llvm.ptr, %scratch: !llvm.ptr,
                           %info: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %c5 = arith.constant 5 : i64
  %c6 = arith.constant 6 : i64
  %c7 = arith.constant 7 : i64
  %c8 = arith.constant 8 : i64
  %true = arith.constant true
  %zi = arith.constant 0 : index
  %oi = arith.constant 1 : index
  %c2i = arith.constant 2 : index
  %c4_32 = arith.constant 4 : i32
  %c0_8 = arith.constant 0 : i8
  %c0_32 = arith.constant 0 : i32
  %d = func.call @hp_desc(%rp, %rn) : (!llvm.ptr, i64) -> !d
  %mm = builtin.unrealized_conversion_cast %d : !d to !m
  %ss = builtin.unrealized_conversion_cast %mm : !m to !s
  %szi = arith.index_cast %sz : i64 to index
  %nsri = arith.xori %sri, %true : i1
  // the length classes, in parseRest's order
  %sz2 = arith.muli %sz, %c2 : i64
  %hexlen = arith.cmpi eq, %rn, %sz2 : i64
  %hexpath = arith.andi %nsri, %hexlen : i1
  %sz8 = arith.muli %sz, %c8 : i64
  %sz8m1 = arith.subi %sz8, %c1 : i64
  %n32len0 = arith.divui %sz8m1, %c5 : i64
  %n32len = arith.addi %n32len0, %c1 : i64
  %n32l = arith.cmpi eq, %rn, %n32len : i64
  %n32path = arith.andi %nsri, %n32l : i1
  %sz4 = arith.muli %sz, %c4 : i64
  %sz4d = arith.divui %sz4, %c3 : i64
  %b64a = arith.addi %sz4d, %c3 : i64
  %b64b = arith.divui %b64a, %c4 : i64
  %b64len = arith.muli %b64b, %c4 : i64
  %b64l = arith.cmpi eq, %rn, %b64len : i64
  %b64path = arith.ori %sri, %b64l : i1
  %r = scf.if %hexpath -> i64 {
    // base-16: each pair is two digits; a character that is not a hex digit fails the whole digest
    %tab = memref.get_global @hp_hex : memref<256xi8>
    %ok = scf.for %i = %zi to %szi step %oi iter_args(%okacc = %true) -> (i1) {
      %i2 = arith.muli %i, %c2i : index
      %i21 = arith.addi %i2, %oi : index
      %ca = trikeshed.at %ss[%i2] : !s, index -> i8
      %cb = trikeshed.at %ss[%i21] : !s, index -> i8
      %ua = arith.extui %ca : i8 to i32
      %ub = arith.extui %cb : i8 to i32
      %uai = arith.index_cast %ua : i32 to index
      %ubi = arith.index_cast %ub : i32 to index
      %da8 = memref.load %tab[%uai] : memref<256xi8>
      %db8 = memref.load %tab[%ubi] : memref<256xi8>
      %da = arith.extsi %da8 : i8 to i32
      %db = arith.extsi %db8 : i8 to i32
      %va = arith.cmpi sge, %da, %c0_32 : i32
      %vb = arith.cmpi sge, %db, %c0_32 : i32
      %v = arith.andi %va, %vb : i1
      %hi = arith.shli %da, %c4_32 : i32
      %byte32 = arith.ori %hi, %db : i32
      %byte = arith.trunci %byte32 : i32 to i8
      %ii = arith.index_cast %i : index to i64
      %ptr = llvm.getelementptr %out[%ii] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      scf.if %v {
        llvm.store %byte, %ptr : i8, !llvm.ptr
      }
      %okn = arith.andi %okacc, %v : i1
      scf.yield %okn : i1
    }
    %rc = arith.select %ok, %c0, %c5 : i64
    scf.yield %rc : i64
  } else {
    %r2 = scf.if %n32path -> i64 {
      // nix32: the output is zero-filled first, the decoder ORs the digits in
      scf.for %i = %zi to %szi step %oi {
        %ii = arith.index_cast %i : index to i64
        %ptr = llvm.getelementptr %out[%ii] : (!llvm.ptr, i64) -> !llvm.ptr, i8
        llvm.store %c0_8, %ptr : i8, !llvm.ptr
      }
      %rv = func.call @mlnix_nix32_decode(%rp, %rn, %sz, %out) : (!llvm.ptr, i64, i64, !llvm.ptr) -> i32
      %okv = arith.cmpi ne, %rv, %c0_32 : i32
      %rc = arith.select %okv, %c0, %c6 : i64
      scf.yield %rc : i64
    } else {
      %r3 = scf.if %b64path -> i64 {
        // base64 (SRI, or the base64 length): the decoded count must be the digest's size
        %slot = llvm.getelementptr %info[%c2] : (!llvm.ptr, i64) -> !llvm.ptr, i64
        %rv = func.call @mlnix_base64_decode(%rp, %rn, %scratch, %slot) : (!llvm.ptr, i64, !llvm.ptr, !llvm.ptr) -> i32
        %outlen = llvm.load %slot : !llvm.ptr -> i64
        %okr = arith.cmpi ne, %rv, %c0_32 : i32
        %oklen = arith.cmpi eq, %outlen, %sz : i64
        %okb = arith.andi %okr, %oklen : i1
        %rc = scf.if %okb -> i64 {
          scf.for %i = %zi to %szi step %oi {
            %ii = arith.index_cast %i : index to i64
            %sp = llvm.getelementptr %scratch[%ii] : (!llvm.ptr, i64) -> !llvm.ptr, i8
            %dp = llvm.getelementptr %out[%ii] : (!llvm.ptr, i64) -> !llvm.ptr, i8
            %byte = llvm.load %sp : !llvm.ptr -> i8
            llvm.store %byte, %dp : i8, !llvm.ptr
          }
          scf.yield %c0 : i64
        } else {
          %bad = arith.select %sri, %c7, %c4 : i64
          scf.yield %bad : i64
        }
        scf.yield %rc : i64
      } else {
        scf.yield %c4 : i64
      }
      scf.yield %r3 : i64
    }
    scf.yield %r2 : i64
  }
  return %r : i64
}

// parseHash (the C++ wrapper keeps the error wording and sizes the scratch to n bytes)
func.func @nixstore_ts_parsehash(%p: !llvm.ptr, %n: i64, %known: i64, %out: !llvm.ptr, %scratch: !llvm.ptr,
                                 %info: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c4 = arith.constant 4 : i64
  %c5 = arith.constant 5 : i64
  %cm1 = arith.constant -1 : i64
  %c58 = arith.constant 58 : i8
  %c45 = arith.constant 45 : i8
  %true = arith.constant true
  %colon = func.call @hp_find(%p, %n, %c58) : (!llvm.ptr, i64, i8) -> i64
  %dash = func.call @hp_find(%p, %n, %c45) : (!llvm.ptr, i64, i8) -> i64
  %hascolon = arith.cmpi ult, %colon, %n : i64
  %hasdash = arith.cmpi ult, %dash, %n : i64
  // an explicit algorithm before ':' (an unknown name is an error); else a known one before '-' makes an SRI
  %colonalg = func.call @hp_algo(%p, %colon) : (!llvm.ptr, i64) -> i64
  %dashalg0 = func.call @hp_algo(%p, %dash) : (!llvm.ptr, i64) -> i64
  %dashalg = arith.select %hasdash, %dashalg0, %cm1 : i64
  %colonunk0 = arith.cmpi slt, %colonalg, %c0 : i64
  %unknown = arith.andi %hascolon, %colonunk0 : i1
  %dashok = arith.cmpi sge, %dashalg, %c0 : i64
  %nocolon = arith.xori %hascolon, %true : i1
  %sri = arith.andi %nocolon, %dashok : i1
  %parsed = arith.select %hascolon, %colonalg, %dashalg : i64
  %off_colon = arith.addi %colon, %c1 : i64
  %off_dash = arith.addi %dash, %c1 : i64
  %off1 = arith.select %sri, %off_dash, %c0 : i64
  %off = arith.select %hascolon, %off_colon, %off1 : i64
  %rn = arith.subi %n, %off : i64
  %rp = llvm.getelementptr %p[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %r = scf.if %unknown -> i64 {
    %slot1 = llvm.getelementptr %info[%c1] : (!llvm.ptr, i64) -> !llvm.ptr, i64
    llvm.store %colon, %slot1 : i64, !llvm.ptr
    scf.yield %c1 : i64
  } else {
    %hasp = arith.cmpi sge, %parsed, %c0 : i64
    %hask = arith.cmpi sge, %known, %c0 : i64
    %neq = arith.cmpi ne, %parsed, %known : i64
    %both = arith.andi %hasp, %hask : i1
    %mism = arith.andi %both, %neq : i1
    %nhasp = arith.xori %hasp, %true : i1
    %nhask = arith.xori %hask, %true : i1
    %notype = arith.andi %nhasp, %nhask : i1
    %code = scf.if %mism -> i64 {
      scf.yield %c2 : i64
    } else {
      %c3 = arith.constant 3 : i64
      %nt = scf.if %notype -> i64 {
        scf.yield %c3 : i64
      } else {
        %algo = arith.select %hasp, %parsed, %known : i64
        %slot0 = llvm.getelementptr %info[%c0] : (!llvm.ptr, i64) -> !llvm.ptr, i64
        llvm.store %algo, %slot0 : i64, !llvm.ptr
        // digest size: md5 16, sha1 20, sha256 32, sha512 64
        %a0 = arith.cmpi eq, %algo, %c0 : i64
        %a1 = arith.cmpi eq, %algo, %c1 : i64
        %a2 = arith.cmpi eq, %algo, %c2 : i64
        %s16 = arith.constant 16 : i64
        %s20 = arith.constant 20 : i64
        %s32 = arith.constant 32 : i64
        %s64 = arith.constant 64 : i64
        %t2 = arith.select %a2, %s32, %s64 : i64
        %t1 = arith.select %a1, %s20, %t2 : i64
        %sz = arith.select %a0, %s16, %t1 : i64
        %rc = func.call @hp_rest(%rp, %rn, %sri, %sz, %out, %scratch, %info) : (!llvm.ptr, i64, i1, i64, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
        scf.yield %rc : i64
      }
      scf.yield %nt : i64
    }
    scf.yield %code : i64
  }
  return %r : i64
}

// compressHash: the digest's bytes XOR-folded into newSize bytes; out is 64 bytes, zeroed first
func.func @nixstore_ts_compress(%in: !llvm.ptr, %n: i64, %newsize: i64, %out: !llvm.ptr) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c64 = arith.constant 64 : i64
  %zi = arith.constant 0 : index
  %oi = arith.constant 1 : index
  %c0_8 = arith.constant 0 : i8
  %c64i = arith.constant 64 : index
  scf.for %z = %zi to %c64i step %oi {
    %zi64 = arith.index_cast %z : index to i64
    %zp = llvm.getelementptr %out[%zi64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_8, %zp : i8, !llvm.ptr
  }
  %d = func.call @hp_desc(%in, %n) : (!llvm.ptr, i64) -> !d
  %mm = builtin.unrealized_conversion_cast %d : !d to !m
  %ss = builtin.unrealized_conversion_cast %mm : !m to !s
  %ni = arith.index_cast %n : i64 to index
  %ns = arith.index_cast %newsize : i64 to index
  scf.for %i = %zi to %ni step %oi {
    %c = trikeshed.at %ss[%i] : !s, index -> i8
    %j = arith.remui %i, %ns : index
    %j64 = arith.index_cast %j : index to i64
    %ptr = llvm.getelementptr %out[%j64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %old = llvm.load %ptr : !llvm.ptr -> i8
    %x = arith.xori %old, %c : i8
    llvm.store %x, %ptr : i8, !llvm.ptr
  }
  return
}
