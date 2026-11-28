// The store's hashes: lib/Store/Hash.cpp's bodies.  The C++ keeps the declarations (include/Nix/Store.h) and a forward
// each where a C++ type crosses (a string_view in, a Text or a Hash out, the message of a failure thrown).
//
//   nixstore::hashSize                  the mangled name itself: a digest's bytes by algorithm (md5 16, sha1 20, sha256 32,
//                                       sha512 64; 0 for no algorithm)
//   nixstore_ts_algoname(a)             the algorithm's name, a C string ("?" for no algorithm)
//   nixstore_ts_algoof(p, n)            the algorithm a name is, or -1 (parseHashAlgo)
//   nixstore_hs_init / update / finish  a HashSink (algo i32 @0, its algorithm's context @16, the bytes taken @336): the
//                                       algorithm's module is called on the context (Md5, Sha1, Sha512, and SHA-256
//                                       through nixstore_s256_*: Sha256.mlir, or libcrypto where the build links it)
//   nixstore_ts_hashstring(a, p, n, h)  the digest of n bytes
//   nixstore_ts_hashfile(a, path, n, h, err)   the digest of a file's bytes: read after read into one page of 64 KiB,
//                                       each chunk a slice of the page's view, taken by the sink
//   nixstore_ts_hashtext(h, format, includeAlgo, out)   Hash::to_string: the Text sized once to the name, the separator and
//                                       the digits; the prefix one combine drained once, the digits Encoders.mlir's
//   nixstore_ts_hashinto(h, format, includeAlgo, into)  the same text written at `into`: its bytes
//   nixstore_ts_hashparse(p, n, known, h, err)   parseHash: HashParse.mlir's parser, and the wording of what it refuses
//                                       (the words by its code, from one table of spans; one combine drained once)
//   nixstore_ts_hashparse0(p, n, known, h, warning, err)   parseHashAllowEmpty: the empty string is the algorithm's
//                                       hash of zeros, said in the warning
//
// A Hash is algo i32 @0 and bytes[64] @4 (the forward's `Hash h;` has zeroed the bytes: a digest shorter than 64 leaves
// the rest zero, as the C++ did).  HashFormat: 0 base 16, 1 Nix's base 32, 2 base 64, 3 SRI.  An entry that can fail
// answers 0, or 1 with the message in the Text at err, which the forward throws.
//
// Written as HashOps.mlir.t and expanded by gen.py (both kept outside the repository, with the lane's harnesses: the
// literals are spans of one blob).  Lowered by --trikeshed-lower-cursors and the stock buffer pipeline
// (lib/CMakeLists.txt mlnix_lower_trikeshed).
!s = !trikeshed.series<i8>
!s64 = !trikeshed.series<i64>
!m = memref<?xi8, strided<[1], offset: ?>>
!m64 = memref<?xi64, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

memref.global "private" constant @hs_words : memref<405xi8> =
  dense<"0x6d643500736861310073686132353600736861353132003f00756e6b6e6f776e206861736820616c676f726974686d2027272c206578706563742027626c616b6533272c20276d6435272c202773686131272c2027736861323536272c206f72202773686135313227686173682027272073686f756c642068617665207479706520272720646f6573206e6f7420696e636c756465206120747970652c206e6f72206973207468652074797065206f7468657277697365206b6e6f776e2066726f6d20636f6e7465787427206861732077726f6e67206c656e67746820666f72206861736820616c676f726974686d2027696e76616c696420626173652d313620686173682027696e76616c6964206e6978333220686173682027696e76616c696420535249206861736820276f70656e696e672066696c652027273a2072656164696e672066696c6520273a2d666f756e6420656d70747920686173682c20617373756d696e672027656d7074792068617368207265717569726573206578706c69636974206861736820616c676f726974686d">
// the algorithms' names, each with its NUL, in HashAlgo's order; the last is no algorithm's
memref.global "private" constant @hs_names : memref<10xi64> = dense<[0, 4, 4, 5, 9, 7, 16, 7, 23, 2]>
// what parseHash refuses, by HashParse.mlir's code (1 to 7): the words before the hash (or the name), after it, and
// after the algorithm's name
memref.global "private" constant @hs_refusals : memref<42xi64> = dense<[25, 24, 49, 56, 0, 0, 105, 6, 111, 20, 48, 1, 105, 6, 131, 71, 0, 0, 105, 6, 202, 39, 48, 1, 241, 22, 48, 1, 0, 0, 263, 20, 48, 1, 0, 0, 283, 18, 48, 1, 0, 0]>

// the C library
func.func private @close(i32) -> i32
func.func private @read(i32, !llvm.ptr, i64) -> i64
func.func private @strerror(i32) -> !llvm.ptr
func.func private @strlen(!llvm.ptr) -> i64
// the system's words, the recorder's note (FileOps.mlir) and a Text sized (StorePaths.cpp)
func.func private @nixsi_os_open(!llvm.ptr, i64) -> i32
func.func private @nixfs_os_errno() -> i32
func.func private @nixstore_fs_note(i32, !llvm.ptr)
func.func private @nixstore_text_sized(!llvm.ptr, i64) -> !llvm.ptr
// the digests (Md5.mlir, Sha1.mlir, Sha512.mlir; SHA-256 by the build's choice: Sha256Own.mlir or Sha256OpenSsl.mlir)
func.func private @mlnix_md5_init(!llvm.ptr)
func.func private @mlnix_md5_update(!llvm.ptr, !llvm.ptr, i64)
func.func private @mlnix_md5_final(!llvm.ptr, !llvm.ptr)
func.func private @mlnix_sha1_init(!llvm.ptr)
func.func private @mlnix_sha1_update(!llvm.ptr, !llvm.ptr, i64)
func.func private @mlnix_sha1_final(!llvm.ptr, !llvm.ptr)
func.func private @nixstore_s256_init(!llvm.ptr)
func.func private @nixstore_s256_update(!llvm.ptr, !llvm.ptr, i64)
func.func private @nixstore_s256_final(!llvm.ptr, !llvm.ptr)
func.func private @mlnix_sha512_init(!llvm.ptr)
func.func private @mlnix_sha512_update(!llvm.ptr, !llvm.ptr, i64)
func.func private @mlnix_sha512_final(!llvm.ptr, !llvm.ptr)
// the digits (Encoders.mlir) and the parser (HashParse.mlir)
func.func private @mlnix_base16_encode(!llvm.ptr, i64, !llvm.ptr) -> i64
func.func private @mlnix_nix32_encode(!llvm.ptr, i64, !llvm.ptr) -> i64
func.func private @mlnix_base64_encode(!llvm.ptr, i64, !llvm.ptr) -> i64
func.func private @nixstore_ts_parsehash(!llvm.ptr, i64, i64, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64

// the descriptor of n cells at p
func.func private @hs_desc(%p: !llvm.ptr, %n: i64) -> !d {
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

// A failure's message put in the Text at err: the words at [ao, an), the bytes [p1, n1), the words at [bo, bn), the
// bytes [p2, n2), the words at [co, cn), and what the system says of error e (strerror) unless e is negative.  One
// combine, drained once into the Text sized to it.  Answers 1.
func.func private @hs_fail(%err: !llvm.ptr, %ao: index, %an: index, %p1: !llvm.ptr, %n1: i64, %bo: index, %bn: index, %p2: !llvm.ptr, %n2: i64, %co: index, %cn: index, %e: i32) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %z32 = arith.constant 0 : i32
  %words_g = memref.get_global @hs_words : memref<405xi8>
  %words = trikeshed.text %words_g : memref<405xi8> -> !s
  %a = trikeshed.slice %words[%ao, %an] : !s -> !s
  %b = trikeshed.slice %words[%bo, %bn] : !s -> !s
  %c = trikeshed.slice %words[%co, %cn] : !s -> !s
  %w1_d = func.call @hs_desc(%p1, %n1) : (!llvm.ptr, i64) -> !d
  %w1_m = builtin.unrealized_conversion_cast %w1_d : !d to !m
  %w1 = builtin.unrealized_conversion_cast %w1_m : !m to !s
  %w2_d = func.call @hs_desc(%p2, %n2) : (!llvm.ptr, i64) -> !d
  %w2_m = builtin.unrealized_conversion_cast %w2_d : !d to !m
  %w2 = builtin.unrealized_conversion_cast %w2_m : !m to !s
  %said = arith.cmpi sge, %e, %z32 : i32
  %wp, %wn = scf.if %said -> (!llvm.ptr, i64) {
    %t = func.call @strerror(%e) : (i32) -> !llvm.ptr
    %tn = func.call @strlen(%t) : (!llvm.ptr) -> i64
    scf.yield %t, %tn : !llvm.ptr, i64
  } else {
    scf.yield %p1, %c0 : !llvm.ptr, i64
  }
  %why_d = func.call @hs_desc(%wp, %wn) : (!llvm.ptr, i64) -> !d
  %why_m = builtin.unrealized_conversion_cast %why_d : !d to !m
  %why = builtin.unrealized_conversion_cast %why_m : !m to !s
  %msg = trikeshed.combine %a, %w1, %b, %w2, %c, %why : !s, !s, !s, !s, !s, !s -> !s
  %sz = trikeshed.size %msg : !s
  %sz64 = arith.index_cast %sz : index to i64
  %room = func.call @nixstore_text_sized(%err, %sz64) : (!llvm.ptr, i64) -> !llvm.ptr
  %into_d = func.call @hs_desc(%room, %sz64) : (!llvm.ptr, i64) -> !d
  %into = builtin.unrealized_conversion_cast %into_d : !d to !m
  %end = trikeshed.drain %msg, %into : !s, !m -> index
  return %c1 : i64
}

//===----------------------------------------------------------------------===//
// The algorithms: a digest's size, a name, the algorithm of a name
//===----------------------------------------------------------------------===//

// a digest's bytes: 16, 20, 32, 64 in HashAlgo's order; 0 for anything else
func.func private @hs_size(%a: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c16 = arith.constant 16 : i64
  %c20 = arith.constant 20 : i64
  %c32 = arith.constant 32 : i64
  %c64 = arith.constant 64 : i64
  %is0 = arith.cmpi eq, %a, %c0 : i64
  %is1 = arith.cmpi eq, %a, %c1 : i64
  %is2 = arith.cmpi eq, %a, %c2 : i64
  %is3 = arith.cmpi eq, %a, %c3 : i64
  %s3 = arith.select %is3, %c64, %c0 : i64
  %s2 = arith.select %is2, %c32, %s3 : i64
  %s1 = arith.select %is1, %c20, %s2 : i64
  %s0 = arith.select %is0, %c16, %s1 : i64
  return %s0 : i64
}

// size_t nixstore::hashSize(HashAlgo)
func.func @_ZN8nixstore8hashSizeENS_8HashAlgoE(%a: i32) -> i64 {
  %a64 = arith.extsi %a : i32 to i64
  %r = func.call @hs_size(%a64) : (i64) -> i64
  return %r : i64
}

// where the algorithm's name lies in the blob, and its bytes (the NUL after them not counted); no algorithm's is "?"
func.func private @hs_name(%a: i64) -> (index, index) {
  %c0 = arith.constant 0 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %i1 = arith.constant 1 : index
  %i2 = arith.constant 2 : index
  %low = arith.cmpi sge, %a, %c0 : i64
  %high = arith.cmpi sle, %a, %c3 : i64
  %known = arith.andi %low, %high : i1
  %row = arith.select %known, %a, %c4 : i64
  %ri = arith.index_cast %row : i64 to index
  %tg = memref.get_global @hs_names : memref<10xi64>
  %tab = trikeshed.text %tg : memref<10xi64> -> !s64
  %at = arith.muli %ri, %i2 : index
  %at1 = arith.addi %at, %i1 : index
  %off = trikeshed.at %tab[%at] : !s64, index -> i64
  %len = trikeshed.at %tab[%at1] : !s64, index -> i64
  %offi = arith.index_cast %off : i64 to index
  %leni = arith.index_cast %len : i64 to index
  %n = arith.subi %leni, %i1 : index
  return %offi, %n : index, index
}

// the address of the blob's byte at `off`
func.func private @hs_word(%off: index) -> !llvm.ptr {
  %words_g = memref.get_global @hs_words : memref<405xi8>
  %words = trikeshed.text %words_g : memref<405xi8> -> !s
  %base = memref.extract_aligned_pointer_as_index %words_g : memref<405xi8> -> index
  %at = arith.addi %base, %off : index
  %at64 = arith.index_cast %at : index to i64
  %p = llvm.inttoptr %at64 : i64 to !llvm.ptr
  return %p : !llvm.ptr
}

func.func @nixstore_ts_algoname(%a: i64) -> !llvm.ptr {
  %off, %n = func.call @hs_name(%a) : (i64) -> (index, index)
  %p = func.call @hs_word(%off) : (index) -> !llvm.ptr
  return %p : !llvm.ptr
}

// parseHashAlgo: the algorithm whose name the n bytes at p are, or -1
func.func @nixstore_ts_algoof(%p: !llvm.ptr, %n: i64) -> i64 {
  %m1 = arith.constant -1 : i64
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %z32 = arith.constant 0 : i32
  %words_g = memref.get_global @hs_words : memref<405xi8>
  %words = trikeshed.text %words_g : memref<405xi8> -> !s
  %md5_o = arith.constant 0 : index  // "md5"
  %md5_n = arith.constant 3 : index
  %md5 = trikeshed.slice %words[%md5_o, %md5_n] : !s -> !s
  %sha1_o = arith.constant 4 : index  // "sha1"
  %sha1_n = arith.constant 4 : index
  %sha1 = trikeshed.slice %words[%sha1_o, %sha1_n] : !s -> !s
  %sha256_o = arith.constant 9 : index  // "sha256"
  %sha256_n = arith.constant 6 : index
  %sha256 = trikeshed.slice %words[%sha256_o, %sha256_n] : !s -> !s
  %sha512_o = arith.constant 16 : index  // "sha512"
  %sha512_n = arith.constant 6 : index
  %sha512 = trikeshed.slice %words[%sha512_o, %sha512_n] : !s -> !s
  %name_d = func.call @hs_desc(%p, %n) : (!llvm.ptr, i64) -> !d
  %name_m = builtin.unrealized_conversion_cast %name_d : !d to !m
  %name = builtin.unrealized_conversion_cast %name_m : !m to !s
  %k0 = trikeshed.compare %name, %md5 unsigned : !s, !s
  %k1 = trikeshed.compare %name, %sha1 unsigned : !s, !s
  %k2 = trikeshed.compare %name, %sha256 unsigned : !s, !s
  %k3 = trikeshed.compare %name, %sha512 unsigned : !s, !s
  %is0 = arith.cmpi eq, %k0, %z32 : i32
  %is1 = arith.cmpi eq, %k1, %z32 : i32
  %is2 = arith.cmpi eq, %k2, %z32 : i32
  %is3 = arith.cmpi eq, %k3, %z32 : i32
  %r3 = arith.select %is3, %c3, %m1 : i64
  %r2 = arith.select %is2, %c2, %r3 : i64
  %r1 = arith.select %is1, %c1, %r2 : i64
  %r0 = arith.select %is0, %c0, %r1 : i64
  return %r0 : i64
}

//===----------------------------------------------------------------------===//
// HashSink
//===----------------------------------------------------------------------===//

func.func @nixstore_hs_init(%s: !llvm.ptr) {
  %c16 = arith.constant 16 : i64
  %a0 = arith.constant 0 : i32
  %a1 = arith.constant 1 : i32
  %a2 = arith.constant 2 : i32
  %a3 = arith.constant 3 : i32
  %algo = llvm.load %s : !llvm.ptr -> i32
  %ctx = llvm.getelementptr %s[%c16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %is2 = arith.cmpi eq, %algo, %a2 : i32
  scf.if %is2 {
    func.call @nixstore_s256_init(%ctx) : (!llvm.ptr) -> ()
  } else {
    %is0 = arith.cmpi eq, %algo, %a0 : i32
    scf.if %is0 {
      func.call @mlnix_md5_init(%ctx) : (!llvm.ptr) -> ()
    } else {
      %is1 = arith.cmpi eq, %algo, %a1 : i32
      scf.if %is1 {
        func.call @mlnix_sha1_init(%ctx) : (!llvm.ptr) -> ()
      } else {
        %is3 = arith.cmpi eq, %algo, %a3 : i32
        scf.if %is3 {
          func.call @mlnix_sha512_init(%ctx) : (!llvm.ptr) -> ()
        }
      }
    }
  }
  return
}

func.func @nixstore_hs_update(%s: !llvm.ptr, %p: !llvm.ptr, %n: i64) {
  %c16 = arith.constant 16 : i64
  %c336 = arith.constant 336 : i64
  %a0 = arith.constant 0 : i32
  %a1 = arith.constant 1 : i32
  %a2 = arith.constant 2 : i32
  %a3 = arith.constant 3 : i32
  %algo = llvm.load %s : !llvm.ptr -> i32
  %ctx = llvm.getelementptr %s[%c16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %tp = llvm.getelementptr %s[%c336] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %t = llvm.load %tp : !llvm.ptr -> i64
  %t2 = arith.addi %t, %n : i64
  llvm.store %t2, %tp : i64, !llvm.ptr
  %is2 = arith.cmpi eq, %algo, %a2 : i32
  scf.if %is2 {
    func.call @nixstore_s256_update(%ctx, %p, %n) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  } else {
    %is0 = arith.cmpi eq, %algo, %a0 : i32
    scf.if %is0 {
      func.call @mlnix_md5_update(%ctx, %p, %n) : (!llvm.ptr, !llvm.ptr, i64) -> ()
    } else {
      %is1 = arith.cmpi eq, %algo, %a1 : i32
      scf.if %is1 {
        func.call @mlnix_sha1_update(%ctx, %p, %n) : (!llvm.ptr, !llvm.ptr, i64) -> ()
      } else {
        %is3 = arith.cmpi eq, %algo, %a3 : i32
        scf.if %is3 {
          func.call @mlnix_sha512_update(%ctx, %p, %n) : (!llvm.ptr, !llvm.ptr, i64) -> ()
        }
      }
    }
  }
  return
}

func.func @nixstore_hs_finish(%s: !llvm.ptr, %h: !llvm.ptr) {
  %c4 = arith.constant 4 : i64
  %c16 = arith.constant 16 : i64
  %a0 = arith.constant 0 : i32
  %a1 = arith.constant 1 : i32
  %a2 = arith.constant 2 : i32
  %a3 = arith.constant 3 : i32
  %algo = llvm.load %s : !llvm.ptr -> i32
  %ctx = llvm.getelementptr %s[%c16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  llvm.store %algo, %h : i32, !llvm.ptr
  %out = llvm.getelementptr %h[%c4] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %is2 = arith.cmpi eq, %algo, %a2 : i32
  scf.if %is2 {
    func.call @nixstore_s256_final(%ctx, %out) : (!llvm.ptr, !llvm.ptr) -> ()
  } else {
    %is0 = arith.cmpi eq, %algo, %a0 : i32
    scf.if %is0 {
      func.call @mlnix_md5_final(%ctx, %out) : (!llvm.ptr, !llvm.ptr) -> ()
    } else {
      %is1 = arith.cmpi eq, %algo, %a1 : i32
      scf.if %is1 {
        func.call @mlnix_sha1_final(%ctx, %out) : (!llvm.ptr, !llvm.ptr) -> ()
      } else {
        %is3 = arith.cmpi eq, %algo, %a3 : i32
        scf.if %is3 {
          func.call @mlnix_sha512_final(%ctx, %out) : (!llvm.ptr, !llvm.ptr) -> ()
        }
      }
    }
  }
  return
}

// a sink of the algorithm a made at s (352 bytes, 16-aligned): no byte taken yet
func.func private @hs_sink(%s: !llvm.ptr, %a: i64) {
  %c0 = arith.constant 0 : i64
  %c336 = arith.constant 336 : i64
  %a32 = arith.trunci %a : i64 to i32
  llvm.store %a32, %s : i32, !llvm.ptr
  %tp = llvm.getelementptr %s[%c336] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  llvm.store %c0, %tp : i64, !llvm.ptr
  func.call @nixstore_hs_init(%s) : (!llvm.ptr) -> ()
  return
}

func.func @nixstore_ts_hashstring(%a: i64, %p: !llvm.ptr, %n: i64, %h: !llvm.ptr) {
  %c44 = arith.constant 44 : i64
  %s = llvm.alloca %c44 x i64 {alignment = 16 : i64} : (i64) -> !llvm.ptr
  func.call @hs_sink(%s, %a) : (!llvm.ptr, i64) -> ()
  func.call @nixstore_hs_update(%s, %p, %n) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  func.call @nixstore_hs_finish(%s, %h) : (!llvm.ptr, !llvm.ptr) -> ()
  return
}

// What hashFile says of a file that could not be opened (e: the system's error): `opening file '<path>': <what the
// system says>`.  The one place that wording is made.
func.func private @hs_file_notopened(%err: !llvm.ptr, %cp: !llvm.ptr, %n: i64, %e: i32) -> i64 {
  %c0 = arith.constant 0 : i64
  %opening_o = arith.constant 301 : index  // "opening file '"
  %opening_n = arith.constant 14 : index
  %why_o = arith.constant 315 : index  // "': "
  %why_n = arith.constant 3 : index
  %none_o = arith.constant 0 : index  // ""
  %none_n = arith.constant 0 : index
  %f = func.call @hs_fail(%err, %opening_o, %opening_n, %cp, %n, %why_o, %why_n, %cp, %c0, %none_o, %none_n, %e) : (!llvm.ptr, index, index, !llvm.ptr, i64, index, index, !llvm.ptr, i64, index, index, i32) -> i64
  return %f : i64
}

// The file's bytes through the sink: read after read into the page (their order is the effect, so an scf.while), each
// chunk read a slice of the one view of the page, which the sink takes.  1 when the file ended, 2 when a read failed.
func.func private @hs_feed(%s: !llvm.ptr, %fd: i32, %buf: !llvm.ptr, %cap: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %z = arith.constant 0 : index
  %page_d = func.call @hs_desc(%buf, %cap) : (!llvm.ptr, i64) -> !d
  %page_m = builtin.unrealized_conversion_cast %page_d : !d to !m
  %page = builtin.unrealized_conversion_cast %page_m : !m to !s
  %se = scf.while (%state = %c0) : (i64) -> (i64) {
    %go = arith.cmpi eq, %state, %c0 : i64
    scf.condition(%go) %state : i64
  } do {
  ^bb0(%sa: i64):
    %k = func.call @read(%fd, %buf, %cap) : (i32, !llvm.ptr, i64) -> i64
    %some = arith.cmpi sgt, %k, %c0 : i64
    scf.if %some {
      %ki = arith.index_cast %k : i64 to index
      %chunk = trikeshed.slice %page[%z, %ki] : !s -> !s
      %cn = trikeshed.size %chunk : !s
      %cn64 = arith.index_cast %cn : index to i64
      func.call @nixstore_hs_update(%s, %buf, %cn64) : (!llvm.ptr, !llvm.ptr, i64) -> ()
    }
    %neg = arith.cmpi slt, %k, %c0 : i64
    %s1 = arith.select %some, %c0, %c1 : i64
    %s2 = arith.select %neg, %c2, %s1 : i64
    scf.yield %s2 : i64
  }
  return %se : i64
}

// hashFile: the file's bytes through a sink, a page of 64 KiB at a time (hs_feed).  A file that cannot be opened is said
// with what the system says; a read that fails is said without it, the file closed first, as the C++ said it.
func.func @nixstore_ts_hashfile(%a: i64, %cp: !llvm.ptr, %n: i64, %h: !llvm.ptr, %err: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c2 = arith.constant 2 : i64
  %c44 = arith.constant 44 : i64
  %c65536 = arith.constant 65536 : i64
  %z32 = arith.constant 0 : i32
  %m1 = arith.constant -1 : i32
  %kF = arith.constant 70 : i32
  %reading_o = arith.constant 318 : index  // "reading file '"
  %reading_n = arith.constant 14 : index
  %quote_o = arith.constant 48 : index  // "'"
  %quote_n = arith.constant 1 : index
  %none_o = arith.constant 0 : index  // ""
  %none_n = arith.constant 0 : index
  %s = llvm.alloca %c44 x i64 {alignment = 16 : i64} : (i64) -> !llvm.ptr
  %buf = llvm.alloca %c65536 x i8 : (i64) -> !llvm.ptr
  func.call @hs_sink(%s, %a) : (!llvm.ptr, i64) -> ()
  func.call @nixstore_fs_note(%kF, %cp) : (i32, !llvm.ptr) -> ()
  %fd = func.call @nixsi_os_open(%cp, %c0) : (!llvm.ptr, i64) -> i32
  %opened = arith.cmpi sge, %fd, %z32 : i32
  %r = scf.if %opened -> (i64) {
    %se = func.call @hs_feed(%s, %fd, %buf, %c65536) : (!llvm.ptr, i32, !llvm.ptr, i64) -> i64
    %rcc = func.call @close(%fd) : (i32) -> i32
    %failed = arith.cmpi eq, %se, %c2 : i64
    %res = scf.if %failed -> (i64) {
      %f = func.call @hs_fail(%err, %reading_o, %reading_n, %cp, %n, %quote_o, %quote_n, %cp, %c0, %none_o, %none_n, %m1) : (!llvm.ptr, index, index, !llvm.ptr, i64, index, index, !llvm.ptr, i64, index, index, i32) -> i64
      scf.yield %f : i64
    } else {
      func.call @nixstore_hs_finish(%s, %h) : (!llvm.ptr, !llvm.ptr) -> ()
      scf.yield %c0 : i64
    }
    scf.yield %res : i64
  } else {
    %e = func.call @nixfs_os_errno() : () -> i32
    %f0 = func.call @hs_file_notopened(%err, %cp, %n, %e) : (!llvm.ptr, !llvm.ptr, i64, i32) -> i64
    scf.yield %f0 : i64
  }
  return %r : i64
}

//===----------------------------------------------------------------------===//
// Hash::to_string
//===----------------------------------------------------------------------===//

// the bytes of a hash's text: the prefix's (the name and a separator, for SRI or when asked) and the digits'
func.func private @hs_textlen(%h: !llvm.ptr, %fmt: i64, %incl: i64) -> (i64, i64) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %c5 = arith.constant 5 : i64
  %c8 = arith.constant 8 : i64
  %a32 = llvm.load %h : !llvm.ptr -> i32
  %a = arith.extsi %a32 : i32 to i64
  %n = func.call @hs_size(%a) : (i64) -> i64
  %off, %nlen = func.call @hs_name(%a) : (i64) -> (index, index)
  %nlen64 = arith.index_cast %nlen : index to i64
  %sri = arith.cmpi eq, %fmt, %c3 : i64
  %asked = arith.cmpi ne, %incl, %c0 : i64
  %has = arith.ori %sri, %asked : i1
  %pre1 = arith.addi %nlen64, %c1 : i64
  %pre = arith.select %has, %pre1, %c0 : i64
  // base 16: 2n; Nix's base 32: ceil(8n / 5); base 64: 4 for every 3 bytes begun
  %hex = arith.muli %n, %c2 : i64
  %n8 = arith.muli %n, %c8 : i64
  %n84 = arith.addi %n8, %c4 : i64
  %n32 = arith.divui %n84, %c5 : i64
  %n2 = arith.addi %n, %c2 : i64
  %g = arith.divui %n2, %c3 : i64
  %b64 = arith.muli %g, %c4 : i64
  %is0 = arith.cmpi eq, %fmt, %c0 : i64
  %is1 = arith.cmpi eq, %fmt, %c1 : i64
  %d1 = arith.select %is1, %n32, %b64 : i64
  %digits = arith.select %is0, %hex, %d1 : i64
  return %pre, %digits : i64, i64
}

// The text written at `into` (room for its bytes: 135 hold any), and how many: the prefix one combine of two slices
// drained once, then the digits; no digit is written for a digest of no bytes, as the C++ appended none.
func.func @nixstore_ts_hashinto(%h: !llvm.ptr, %fmt: i64, %incl: i64, %into: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %z = arith.constant 0 : index
  %i1 = arith.constant 1 : index
  %words_g = memref.get_global @hs_words : memref<405xi8>
  %words = trikeshed.text %words_g : memref<405xi8> -> !s
  %seps_o = arith.constant 332 : index  // ":-"
  %seps_n = arith.constant 2 : index
  %pre, %digits = func.call @hs_textlen(%h, %fmt, %incl) : (!llvm.ptr, i64, i64) -> (i64, i64)
  %a32 = llvm.load %h : !llvm.ptr -> i32
  %a = arith.extsi %a32 : i32 to i64
  %n = func.call @hs_size(%a) : (i64) -> i64
  %off, %nlen = func.call @hs_name(%a) : (i64) -> (index, index)
  %has = arith.cmpi ne, %pre, %c0 : i64
  %sri = arith.cmpi eq, %fmt, %c3 : i64
  %namen = arith.select %has, %nlen, %z : index
  %sepn = arith.select %has, %i1, %z : index
  %dash = arith.addi %seps_o, %i1 : index
  %sepo = arith.select %sri, %dash, %seps_o : index
  %name = trikeshed.slice %words[%off, %namen] : !s -> !s
  %sep = trikeshed.slice %words[%sepo, %sepn] : !s -> !s
  %prefix = trikeshed.combine %name, %sep : !s, !s -> !s
  %room_d = func.call @hs_desc(%into, %pre) : (!llvm.ptr, i64) -> !d
  %room = builtin.unrealized_conversion_cast %room_d : !d to !m
  %end = trikeshed.drain %prefix, %room : !s, !m -> index
  %bytes = llvm.getelementptr %h[%c4] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %at = llvm.getelementptr %into[%pre] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %some = arith.cmpi ne, %n, %c0 : i64
  scf.if %some {
    %is0 = arith.cmpi eq, %fmt, %c0 : i64
    scf.if %is0 {
      %w = func.call @mlnix_base16_encode(%bytes, %n, %at) : (!llvm.ptr, i64, !llvm.ptr) -> i64
    } else {
      %is1 = arith.cmpi eq, %fmt, %c1 : i64
      scf.if %is1 {
        %w = func.call @mlnix_nix32_encode(%bytes, %n, %at) : (!llvm.ptr, i64, !llvm.ptr) -> i64
      } else {
        %w = func.call @mlnix_base64_encode(%bytes, %n, %at) : (!llvm.ptr, i64, !llvm.ptr) -> i64
      }
    }
  }
  %total = arith.addi %pre, %digits : i64
  return %total : i64
}

func.func @nixstore_ts_hashtext(%h: !llvm.ptr, %fmt: i64, %incl: i64, %out: !llvm.ptr) {
  %pre, %digits = func.call @hs_textlen(%h, %fmt, %incl) : (!llvm.ptr, i64, i64) -> (i64, i64)
  %total = arith.addi %pre, %digits : i64
  %room = func.call @nixstore_text_sized(%out, %total) : (!llvm.ptr, i64) -> !llvm.ptr
  %w = func.call @nixstore_ts_hashinto(%h, %fmt, %incl, %room) : (!llvm.ptr, i64, i64, !llvm.ptr) -> i64
  return
}

//===----------------------------------------------------------------------===//
// parseHash, parseHashAllowEmpty
//===----------------------------------------------------------------------===//

func.func @nixstore_ts_hashparse(%p: !llvm.ptr, %n: i64, %known: i64, %h: !llvm.ptr, %err: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %c6 = arith.constant 6 : i64
  %c7 = arith.constant 7 : i64
  %c8 = arith.constant 8 : i64
  %c16 = arith.constant 16 : i64
  %m1 = arith.constant -1 : i32
  %z = arith.constant 0 : index
  %i1 = arith.constant 1 : index
  %i2 = arith.constant 2 : index
  %i3 = arith.constant 3 : index
  %i4 = arith.constant 4 : index
  %i5 = arith.constant 5 : index
  %info = llvm.alloca %c3 x i64 : (i64) -> !llvm.ptr
  %i1p = llvm.getelementptr %info[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %i2p = llvm.getelementptr %info[%c16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  llvm.store %c0, %info : i64, !llvm.ptr
  llvm.store %c0, %i1p : i64, !llvm.ptr
  llvm.store %c0, %i2p : i64, !llvm.ptr
  // the base 64 decoder's room: as long as the text
  %ni = arith.index_cast %n : i64 to index
  %room = memref.alloc(%ni) : memref<?xi8>
  %rb = memref.extract_aligned_pointer_as_index %room : memref<?xi8> -> index
  %rb64 = arith.index_cast %rb : index to i64
  %scratch = llvm.inttoptr %rb64 : i64 to !llvm.ptr
  %out = llvm.getelementptr %h[%c4] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %code = func.call @nixstore_ts_parsehash(%p, %n, %known, %out, %scratch, %info) : (!llvm.ptr, i64, i64, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
  %algo = llvm.load %info : !llvm.ptr -> i64
  %ok = arith.cmpi eq, %code, %c0 : i64
  %r = scf.if %ok -> (i64) {
    %a32 = arith.trunci %algo : i64 to i32
    llvm.store %a32, %h : i32, !llvm.ptr
    scf.yield %c0 : i64
  } else {
    // the refusal's words by its code (7, an SRI digest, for any other); the hash as it was given, or for an unknown
    // algorithm the name before the colon; and the name of the algorithm meant (2: the context's, 4: the hash's)
    %hi = arith.cmpi sgt, %code, %c7 : i64
    %lo = arith.cmpi slt, %code, %c1 : i64
    %odd = arith.ori %hi, %lo : i1
    %row = arith.select %odd, %c7, %code : i64
    %row0 = arith.subi %row, %c1 : i64
    %at64 = arith.muli %row0, %c6 : i64
    %at = arith.index_cast %at64 : i64 to index
    %at1 = arith.addi %at, %i1 : index
    %at2 = arith.addi %at, %i2 : index
    %at3 = arith.addi %at, %i3 : index
    %at4 = arith.addi %at, %i4 : index
    %at5 = arith.addi %at, %i5 : index
    %tg = memref.get_global @hs_refusals : memref<42xi64>
    %tab = trikeshed.text %tg : memref<42xi64> -> !s64
    %ao64 = trikeshed.at %tab[%at] : !s64, index -> i64
    %an64 = trikeshed.at %tab[%at1] : !s64, index -> i64
    %bo64 = trikeshed.at %tab[%at2] : !s64, index -> i64
    %bn64 = trikeshed.at %tab[%at3] : !s64, index -> i64
    %co64 = trikeshed.at %tab[%at4] : !s64, index -> i64
    %cn64 = trikeshed.at %tab[%at5] : !s64, index -> i64
    %ao = arith.index_cast %ao64 : i64 to index
    %an = arith.index_cast %an64 : i64 to index
    %bo = arith.index_cast %bo64 : i64 to index
    %bn = arith.index_cast %bn64 : i64 to index
    %co = arith.index_cast %co64 : i64 to index
    %cn = arith.index_cast %cn64 : i64 to index
    %is1 = arith.cmpi eq, %row, %c1 : i64
    %is2 = arith.cmpi eq, %row, %c2 : i64
    %is4 = arith.cmpi eq, %row, %c4 : i64
    %colon = llvm.load %i1p : !llvm.ptr -> i64
    %n1 = arith.select %is1, %colon, %n : i64
    %named = arith.ori %is2, %is4 : i1
    %which = arith.select %is2, %known, %algo : i64
    %noff, %nlen = func.call @hs_name(%which) : (i64) -> (index, index)
    %np = func.call @hs_word(%noff) : (index) -> !llvm.ptr
    %nlen64 = arith.index_cast %nlen : index to i64
    %n2 = arith.select %named, %nlen64, %c0 : i64
    %f = func.call @hs_fail(%err, %ao, %an, %p, %n1, %bo, %bn, %np, %n2, %co, %cn, %m1) : (!llvm.ptr, index, index, !llvm.ptr, i64, index, index, !llvm.ptr, i64, index, index, i32) -> i64
    scf.yield %f : i64
  }
  return %r : i64
}

func.func @nixstore_ts_hashparse0(%p: !llvm.ptr, %n: i64, %known: i64, %h: !llvm.ptr, %warning: !llvm.ptr, %err: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c3 = arith.constant 3 : i64
  %m1 = arith.constant -1 : i32
  %words_g = memref.get_global @hs_words : memref<405xi8>
  %words = trikeshed.text %words_g : memref<405xi8> -> !s
  %assuming_o = arith.constant 334 : index  // "found empty hash, assuming '"
  %assuming_n = arith.constant 28 : index
  %assuming = trikeshed.slice %words[%assuming_o, %assuming_n] : !s -> !s
  %quote_o = arith.constant 48 : index  // "'"
  %quote_n = arith.constant 1 : index
  %quote = trikeshed.slice %words[%quote_o, %quote_n] : !s -> !s
  %explicit_o = arith.constant 362 : index  // "empty hash requires explicit hash algorithm"
  %explicit_n = arith.constant 43 : index
  %none_o = arith.constant 0 : index  // ""
  %none_n = arith.constant 0 : index
  %empty = arith.cmpi eq, %n, %c0 : i64
  %r = scf.if %empty -> (i64) {
    %unknown = arith.cmpi slt, %known, %c0 : i64
    %r1 = scf.if %unknown -> (i64) {
      %f = func.call @hs_fail(%err, %explicit_o, %explicit_n, %p, %c0, %none_o, %none_n, %p, %c0, %none_o, %none_n, %m1) : (!llvm.ptr, index, index, !llvm.ptr, i64, index, index, !llvm.ptr, i64, index, index, i32) -> i64
      scf.yield %f : i64
    } else {
      // the algorithm's hash of zeros (the bytes are the forward's, zeroed), and the warning that says so in SRI
      %a32 = arith.trunci %known : i64 to i32
      llvm.store %a32, %h : i32, !llvm.ptr
      %wb = llvm.ptrtoint %warning : !llvm.ptr to i64
      %wanted = arith.cmpi ne, %wb, %c0 : i64
      scf.if %wanted {
        %pre, %digits = func.call @hs_textlen(%h, %c3, %c1) : (!llvm.ptr, i64, i64) -> (i64, i64)
        %tn = arith.addi %pre, %digits : i64
        %an = arith.index_cast %assuming_n : index to i64
        %t0 = arith.addi %an, %tn : i64
        %total = arith.addi %t0, %c1 : i64
        %room = func.call @nixstore_text_sized(%warning, %total) : (!llvm.ptr, i64) -> !llvm.ptr
        %head_d = func.call @hs_desc(%room, %an) : (!llvm.ptr, i64) -> !d
        %head = builtin.unrealized_conversion_cast %head_d : !d to !m
        %e1 = trikeshed.drain %assuming, %head : !s, !m -> index
        %at = llvm.getelementptr %room[%an] : (!llvm.ptr, i64) -> !llvm.ptr, i8
        %w = func.call @nixstore_ts_hashinto(%h, %c3, %c1, %at) : (!llvm.ptr, i64, i64, !llvm.ptr) -> i64
        %last = llvm.getelementptr %room[%t0] : (!llvm.ptr, i64) -> !llvm.ptr, i8
        %tail_d = func.call @hs_desc(%last, %c1) : (!llvm.ptr, i64) -> !d
        %tail = builtin.unrealized_conversion_cast %tail_d : !d to !m
        %e2 = trikeshed.drain %quote, %tail : !s, !m -> index
      }
      scf.yield %c0 : i64
    }
    scf.yield %r1 : i64
  } else {
    %r2 = func.call @nixstore_ts_hashparse(%p, %n, %known, %h, %err) : (!llvm.ptr, i64, i64, !llvm.ptr, !llvm.ptr) -> i64
    scf.yield %r2 : i64
  }
  return %r : i64
}
