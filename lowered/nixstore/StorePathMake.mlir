// The store's path names: lib/Store/StorePaths.cpp's checkName wording, makeStorePath, makeTextPath,
// makeFixedOutputPath, makeOutputPath, hashPlaceholder, toStorePath, and the Texts of baseNameOf, dirOf,
// outputPathName, storePathName, storePathHashPart and jsonFloat.  The C++ keeps a forward each.
//
// The pieces were MLIR already and are called as they are: checkName's scan and outputPathName (StoreName.mlir), the
// fingerprint `type:algo:hex:storeDir:name`, the path `storeDir/nix32-name` and the type `type[:ref]*` (StorePathOps.mlir),
// the digests and a hash's text (HashOps.mlir), the XOR fold (HashParse.mlir), isInStore (IsInStore.mlir).  What is here
// is their composition, which was C++: a name checked, the fingerprint drained into room on the stack (malloc's past
// 4096 bytes), its SHA-256 folded to 20 bytes, the path drained into the Text sized once.
//
//   nixstore_ts_namecheck(p, n, err)                              checkName: the scan's code worded
//   nixstore_ts_makestorepath(sd, sdn, type, tn, hash, name, nn, out)
//   nixstore_ts_textpath(sd, sdn, name, nn, hash, refs, nrefs, out)      type `text[:ref]*`
//   nixstore_ts_fixedpath(sd, sdn, name, nn, method, hash, refs, nrefs, out)
//                                                                 text; source (a NAR's SHA-256); else `output:out`
//                                                                 over the SHA-256 of `fixed:out:[r:]algo:hex:`
//   nixstore_ts_outputpath(sd, sdn, output, on, hash, drvName, dn, out)  type `output:<output>`, name outputPathName's
//   nixstore_ts_placeholder(output, on, out)                      "/" and Nix's base 32 of sha256("nix-output:" output)
//   nixstore_ts_tostorepath(sd, sdn, p, n, out)                   the path up to the slash after its store name
//   nixstore_tx_*                                                 a Text sized to an older entry's bound, cut to what it wrote
// refs are a SortedSet's rows (Texts: bytes @0, length u32 @8, 16 bytes a row).  FileIngestionMethod: 0 flat, 1 NAR,
// 2 text.  An entry that can fail answers 0, or 1 with the message in the Text at out, which the forward throws.
//
// Written as StorePathMake.mlir.t and expanded by gen.py (both kept outside the repository, with the lane's harnesses:
// the literals are spans of one blob).  Lowered by --trikeshed-lower-cursors and the stock buffer pipeline
// (lib/CMakeLists.txt mlnix_lower_trikeshed).  No op here allocates: the rooms are the stack's or malloc's.
!s = !trikeshed.series<i8>
!s64 = !trikeshed.series<i64>
!m = memref<?xi8, strided<[1], offset: ?>>
!m64 = memref<?xi64, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

memref.global "private" constant @spm_words : memref<383xi8> =
  dense<"0x6e616d65206d757374206e6f7420626520656d7074796e616d65202727206d757374206265206e6f206c6f6e676572207468616e20323131206368617261637465727327206973206e6f742076616c696427206973206e6f742076616c69643a20666972737420646173682d73657061726174656420636f6d706f6e656e74206d757374206e6f7420626520272e2727206973206e6f742076616c69643a20666972737420646173682d73657061726174656420636f6d706f6e656e74206d757374206e6f7420626520272e2e272720636f6e7461696e7320696c6c6567616c20636861726163746572202774657874736f757263656f75747075743a6f757466697865643a6f75743a723a6669786564206f75747075742064657269766174696f6e202727206973206e6f7420616c6c6f77656420746f20726566657220746f206f746865722073746f72652070617468732e6e69782d6f75747075743a2f70617468202727206973206e6f7420696e20746865204e69782073746f7265">
// what checkName refuses, by StoreName.mlir's code (1 to 7): the words before the name, after it, and after the
// illegal character
memref.global "private" constant @spm_refusals : memref<42xi64> = dense<[0, 22, 0, 0, 0, 0, 22, 6, 28, 39, 0, 0, 22, 6, 67, 14, 0, 0, 22, 6, 81, 62, 0, 0, 22, 6, 67, 14, 0, 0, 22, 6, 143, 63, 0, 0, 22, 6, 206, 30, 27, 1]>

// the C library
func.func private @strerror(i32) -> !llvm.ptr
func.func private @strlen(!llvm.ptr) -> i64
func.func private @malloc(i64) -> !llvm.ptr
func.func private @free(!llvm.ptr)
// a Text sized (StorePaths.cpp)
func.func private @nixstore_text_sized(!llvm.ptr, i64) -> !llvm.ptr
// StoreName.mlir, StorePathOps.mlir, PathOps.mlir, JsonFloat.mlir, IsInStore.mlir
func.func private @nixstore_ts_checkname(!llvm.ptr, i64, !llvm.ptr) -> i32
func.func private @nixstore_ts_outputname(!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr) -> i64
func.func private @nixstore_ts_storename(!llvm.ptr, i64, !llvm.ptr) -> i64
func.func private @nixstore_ts_storehash(!llvm.ptr, i64, !llvm.ptr) -> i64
func.func private @nixstore_ts_pathfp(!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
func.func private @nixstore_ts_storepath(!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
func.func private @nixstore_ts_maketype(!llvm.ptr, i64, !llvm.ptr, i64, i64, !llvm.ptr, i64) -> i64
func.func private @nixstore_ts_basename(!llvm.ptr, i64, !llvm.ptr) -> i64
func.func private @nixstore_ts_dirname(!llvm.ptr, i64, !llvm.ptr) -> i64
func.func private @nixstore_ts_jsonfloat(f64, !llvm.ptr, !llvm.ptr) -> i64
func.func private @mlnix_isInStore(!llvm.ptr, i64, !llvm.ptr, i64) -> i1
// HashOps.mlir, HashParse.mlir, Encoders.mlir
func.func private @_ZN8nixstore8hashSizeENS_8HashAlgoE(i32) -> i64
func.func private @nixstore_ts_algoname(i64) -> !llvm.ptr
func.func private @nixstore_ts_hashstring(i64, !llvm.ptr, i64, !llvm.ptr)
func.func private @nixstore_ts_hashinto(!llvm.ptr, i64, i64, !llvm.ptr) -> i64
func.func private @nixstore_ts_compress(!llvm.ptr, i64, i64, !llvm.ptr)
func.func private @mlnix_nix32_encode(!llvm.ptr, i64, !llvm.ptr) -> i64

// the descriptor of n cells at p
func.func private @spm_desc(%p: !llvm.ptr, %n: i64) -> !d {
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
func.func private @spm_fail(%err: !llvm.ptr, %ao: index, %an: index, %p1: !llvm.ptr, %n1: i64, %bo: index, %bn: index, %p2: !llvm.ptr, %n2: i64, %co: index, %cn: index, %e: i32) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %z32 = arith.constant 0 : i32
  %words_g = memref.get_global @spm_words : memref<383xi8>
  %words = trikeshed.text %words_g : memref<383xi8> -> !s
  %a = trikeshed.slice %words[%ao, %an] : !s -> !s
  %b = trikeshed.slice %words[%bo, %bn] : !s -> !s
  %c = trikeshed.slice %words[%co, %cn] : !s -> !s
  %w1_d = func.call @spm_desc(%p1, %n1) : (!llvm.ptr, i64) -> !d
  %w1_m = builtin.unrealized_conversion_cast %w1_d : !d to !m
  %w1 = builtin.unrealized_conversion_cast %w1_m : !m to !s
  %w2_d = func.call @spm_desc(%p2, %n2) : (!llvm.ptr, i64) -> !d
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
  %why_d = func.call @spm_desc(%wp, %wn) : (!llvm.ptr, i64) -> !d
  %why_m = builtin.unrealized_conversion_cast %why_d : !d to !m
  %why = builtin.unrealized_conversion_cast %why_m : !m to !s
  %msg = trikeshed.combine %a, %w1, %b, %w2, %c, %why : !s, !s, !s, !s, !s, !s -> !s
  %sz = trikeshed.size %msg : !s
  %sz64 = arith.index_cast %sz : index to i64
  %room = func.call @nixstore_text_sized(%err, %sz64) : (!llvm.ptr, i64) -> !llvm.ptr
  %into_d = func.call @spm_desc(%room, %sz64) : (!llvm.ptr, i64) -> !d
  %into = builtin.unrealized_conversion_cast %into_d : !d to !m
  %end = trikeshed.drain %msg, %into : !s, !m -> index
  return %c1 : i64
}

// room for `need` bytes: the stack's 4096 when they fit, else malloc's (spm_done gives it back)
func.func private @spm_room(%stack: !llvm.ptr, %need: i64) -> !llvm.ptr {
  %c4096 = arith.constant 4096 : i64
  %fits = arith.cmpi ule, %need, %c4096 : i64
  %p = scf.if %fits -> (!llvm.ptr) {
    scf.yield %stack : !llvm.ptr
  } else {
    %q = func.call @malloc(%need) : (i64) -> !llvm.ptr
    scf.yield %q : !llvm.ptr
  }
  return %p : !llvm.ptr
}
func.func private @spm_done(%p: !llvm.ptr, %stack: !llvm.ptr) {
  %a = llvm.ptrtoint %p : !llvm.ptr to i64
  %b = llvm.ptrtoint %stack : !llvm.ptr to i64
  %own = arith.cmpi ne, %a, %b : i64
  scf.if %own {
    func.call @free(%p) : (!llvm.ptr) -> ()
  }
  return
}

// the address of the blob's byte at `off`
func.func private @spm_word(%off: index) -> !llvm.ptr {
  %words_g = memref.get_global @spm_words : memref<383xi8>
  %words = trikeshed.text %words_g : memref<383xi8> -> !s
  %base = memref.extract_aligned_pointer_as_index %words_g : memref<383xi8> -> index
  %at = arith.addi %base, %off : index
  %at64 = arith.index_cast %at : index to i64
  %p = llvm.inttoptr %at64 : i64 to !llvm.ptr
  return %p : !llvm.ptr
}

//===----------------------------------------------------------------------===//
// checkName
//===----------------------------------------------------------------------===//

func.func @nixstore_ts_namecheck(%p: !llvm.ptr, %n: i64, %err: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c6 = arith.constant 6 : i64
  %c7 = arith.constant 7 : i64
  %z32 = arith.constant 0 : i32
  %m1 = arith.constant -1 : i32
  %i1 = arith.constant 1 : index
  %i2 = arith.constant 2 : index
  %i3 = arith.constant 3 : index
  %i4 = arith.constant 4 : index
  %i5 = arith.constant 5 : index
  %bad = llvm.alloca %c1 x i64 : (i64) -> !llvm.ptr
  llvm.store %c0, %bad : i64, !llvm.ptr
  %code32 = func.call @nixstore_ts_checkname(%p, %n, %bad) : (!llvm.ptr, i64, !llvm.ptr) -> i32
  %ok = arith.cmpi eq, %code32, %z32 : i32
  %r = scf.if %ok -> (i64) {
    scf.yield %c0 : i64
  } else {
    // the refusal's words by its code (7, an illegal character, for any other), the name, and for 7 the character
    %code = arith.extsi %code32 : i32 to i64
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
    %tg = memref.get_global @spm_refusals : memref<42xi64>
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
    %is7 = arith.cmpi eq, %row, %c7 : i64
    %n1 = arith.select %is1, %c0, %n : i64
    %where = llvm.load %bad : !llvm.ptr -> i64
    %chp = llvm.getelementptr %p[%where] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %n2 = arith.select %is7, %c1, %c0 : i64
    %f = func.call @spm_fail(%err, %ao, %an, %p, %n1, %bo, %bn, %chp, %n2, %co, %cn, %m1) : (!llvm.ptr, index, index, !llvm.ptr, i64, index, index, !llvm.ptr, i64, index, index, i32) -> i64
    scf.yield %f : i64
  }
  return %r : i64
}

//===----------------------------------------------------------------------===//
// makeStorePath
//===----------------------------------------------------------------------===//

func.func @nixstore_ts_makestorepath(%sd: !llvm.ptr, %sdn: i64, %tp: !llvm.ptr, %tn: i64, %h: !llvm.ptr, %np: !llvm.ptr, %nn: i64, %out: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c4 = arith.constant 4 : i64
  %c8 = arith.constant 8 : i64
  %c9 = arith.constant 9 : i64
  %c20 = arith.constant 20 : i64
  %c32 = arith.constant 32 : i64
  %c34 = arith.constant 34 : i64
  %c4096 = arith.constant 4096 : i64
  %stack = llvm.alloca %c4096 x i8 : (i64) -> !llvm.ptr
  %digest = llvm.alloca %c9 x i64 : (i64) -> !llvm.ptr
  %folded = llvm.alloca %c8 x i64 : (i64) -> !llvm.ptr
  %refused = func.call @nixstore_ts_namecheck(%np, %nn, %out) : (!llvm.ptr, i64, !llvm.ptr) -> i64
  %ok = arith.cmpi eq, %refused, %c0 : i64
  %r = scf.if %ok -> (i64) {
    // the fingerprint `type:algo:hex:storeDir:name`, its SHA-256 folded to 20 bytes, and the path of those
    %a32 = llvm.load %h : !llvm.ptr -> i32
    %a = arith.extsi %a32 : i32 to i64
    %hn = func.call @_ZN8nixstore8hashSizeENS_8HashAlgoE(%a32) : (i32) -> i64
    %ap = func.call @nixstore_ts_algoname(%a) : (i64) -> !llvm.ptr
    %an = func.call @strlen(%ap) : (!llvm.ptr) -> i64
    %hex = arith.muli %hn, %c2 : i64
    %s1 = arith.addi %tn, %an : i64
    %s2 = arith.addi %s1, %hex : i64
    %s3 = arith.addi %s2, %sdn : i64
    %s4 = arith.addi %s3, %nn : i64
    %need = arith.addi %s4, %c4 : i64
    %buf = func.call @spm_room(%stack, %need) : (!llvm.ptr, i64) -> !llvm.ptr
    %bytes = llvm.getelementptr %h[%c4] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %w = func.call @nixstore_ts_pathfp(%tp, %tn, %ap, %an, %bytes, %hn, %sd, %sdn, %np, %nn, %buf, %need) : (!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
    func.call @nixstore_ts_hashstring(%c2, %buf, %w, %digest) : (i64, !llvm.ptr, i64, !llvm.ptr) -> ()
    func.call @spm_done(%buf, %stack) : (!llvm.ptr, !llvm.ptr) -> ()
    %dbytes = llvm.getelementptr %digest[%c4] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    func.call @nixstore_ts_compress(%dbytes, %c32, %c20, %folded) : (!llvm.ptr, i64, i64, !llvm.ptr) -> ()
    %t0 = arith.addi %sdn, %c34 : i64
    %total = arith.addi %t0, %nn : i64
    %room = func.call @nixstore_text_sized(%out, %total) : (!llvm.ptr, i64) -> !llvm.ptr
    %w2 = func.call @nixstore_ts_storepath(%sd, %sdn, %folded, %c20, %np, %nn, %room, %total) : (!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
    scf.yield %c0 : i64
  } else {
    scf.yield %c1 : i64
  }
  return %r : i64
}

// the path whose type is the blob's words at [wo, wn) and each reference after a colon
func.func private @spm_typed(%sd: !llvm.ptr, %sdn: i64, %wo: index, %wn: index, %refs: !llvm.ptr, %nrefs: i64, %h: !llvm.ptr, %np: !llvm.ptr, %nn: i64, %out: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c4096 = arith.constant 4096 : i64
  %null = llvm.mlir.zero : !llvm.ptr
  %stack = llvm.alloca %c4096 x i8 : (i64) -> !llvm.ptr
  %wp = func.call @spm_word(%wo) : (index) -> !llvm.ptr
  %wn64 = arith.index_cast %wn : index to i64
  // the type's bytes (the entry says how many when it is given no room), then the type
  %short = func.call @nixstore_ts_maketype(%wp, %wn64, %refs, %nrefs, %c0, %null, %c0) : (!llvm.ptr, i64, !llvm.ptr, i64, i64, !llvm.ptr, i64) -> i64
  %need0 = arith.subi %c0, %short : i64
  %need = arith.maxsi %need0, %c0 : i64
  %buf = func.call @spm_room(%stack, %need) : (!llvm.ptr, i64) -> !llvm.ptr
  %tn = func.call @nixstore_ts_maketype(%wp, %wn64, %refs, %nrefs, %c0, %buf, %need) : (!llvm.ptr, i64, !llvm.ptr, i64, i64, !llvm.ptr, i64) -> i64
  %r = func.call @nixstore_ts_makestorepath(%sd, %sdn, %buf, %tn, %h, %np, %nn, %out) : (!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr) -> i64
  func.call @spm_done(%buf, %stack) : (!llvm.ptr, !llvm.ptr) -> ()
  return %r : i64
}

func.func @nixstore_ts_textpath(%sd: !llvm.ptr, %sdn: i64, %np: !llvm.ptr, %nn: i64, %h: !llvm.ptr, %refs: !llvm.ptr, %nrefs: i64, %out: !llvm.ptr) -> i64 {
  %text_o = arith.constant 236 : index  // "text"
  %text_n = arith.constant 4 : index
  %r = func.call @spm_typed(%sd, %sdn, %text_o, %text_n, %refs, %nrefs, %h, %np, %nn, %out) : (!llvm.ptr, i64, index, index, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr) -> i64
  return %r : i64
}

func.func @nixstore_ts_fixedpath(%sd: !llvm.ptr, %sdn: i64, %np: !llvm.ptr, %nn: i64, %method: i64, %h: !llvm.ptr, %refs: !llvm.ptr, %nrefs: i64, %out: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c9 = arith.constant 9 : i64
  %c256 = arith.constant 256 : i64
  %a2 = arith.constant 2 : i32
  %m1 = arith.constant -1 : i32
  %z = arith.constant 0 : index
  %i2 = arith.constant 2 : index
  %words_g = memref.get_global @spm_words : memref<383xi8>
  %words = trikeshed.text %words_g : memref<383xi8> -> !s
  %text_o = arith.constant 236 : index  // "text"
  %text_n = arith.constant 4 : index
  %source_o = arith.constant 240 : index  // "source"
  %source_n = arith.constant 6 : index
  %type_o = arith.constant 246 : index  // "output:out"
  %type_n = arith.constant 10 : index
  %fixed_o = arith.constant 256 : index  // "fixed:out:"
  %fixed_n = arith.constant 10 : index
  %fixed = trikeshed.slice %words[%fixed_o, %fixed_n] : !s -> !s
  %rec_o = arith.constant 266 : index  // "r:"
  %rec_n = arith.constant 2 : index
  %colon_o = arith.constant 95 : index  // ":"
  %colon_n = arith.constant 1 : index
  %colon = trikeshed.slice %words[%colon_o, %colon_n] : !s -> !s
  %notallowed_o = arith.constant 268 : index  // "fixed output derivation '"
  %notallowed_n = arith.constant 25 : index
  %toothers_o = arith.constant 293 : index  // "' is not allowed to refer to other store paths."
  %toothers_n = arith.constant 47 : index
  %none_o = arith.constant 0 : index  // ""
  %none_n = arith.constant 0 : index
  %payload = llvm.alloca %c256 x i8 : (i64) -> !llvm.ptr
  %digest = llvm.alloca %c9 x i64 : (i64) -> !llvm.ptr
  %a32 = llvm.load %h : !llvm.ptr -> i32
  %astext = arith.cmpi eq, %method, %c2 : i64
  %r = scf.if %astext -> (i64) {
    %r1 = func.call @spm_typed(%sd, %sdn, %text_o, %text_n, %refs, %nrefs, %h, %np, %nn, %out) : (!llvm.ptr, i64, index, index, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr) -> i64
    scf.yield %r1 : i64
  } else {
    %nar = arith.cmpi eq, %method, %c1 : i64
    %sha256 = arith.cmpi eq, %a32, %a2 : i32
    %assource = arith.andi %nar, %sha256 : i1
    %r2 = scf.if %assource -> (i64) {
      %r3 = func.call @spm_typed(%sd, %sdn, %source_o, %source_n, %refs, %nrefs, %h, %np, %nn, %out) : (!llvm.ptr, i64, index, index, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr) -> i64
      scf.yield %r3 : i64
    } else {
      %refers = arith.cmpi ne, %nrefs, %c0 : i64
      %r4 = scf.if %refers -> (i64) {
        %f = func.call @spm_fail(%out, %notallowed_o, %notallowed_n, %np, %nn, %toothers_o, %toothers_n, %np, %c0, %none_o, %none_n, %m1) : (!llvm.ptr, index, index, !llvm.ptr, i64, index, index, !llvm.ptr, i64, index, index, i32) -> i64
        scf.yield %f : i64
      } else {
        // `fixed:out:[r:]algo:hex:` (the hash's text with its algorithm), hashed: the path is `output:out` over that
        %rn = arith.select %nar, %i2, %z : index
        %rword = trikeshed.slice %words[%rec_o, %rn] : !s -> !s
        %head = trikeshed.combine %fixed, %rword : !s, !s -> !s
        %hn = trikeshed.size %head : !s
        %hn64 = arith.index_cast %hn : index to i64
        %room_d = func.call @spm_desc(%payload, %hn64) : (!llvm.ptr, i64) -> !d
        %room = builtin.unrealized_conversion_cast %room_d : !d to !m
        %e1 = trikeshed.drain %head, %room : !s, !m -> index
        %at = llvm.getelementptr %payload[%hn64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
        %tn = func.call @nixstore_ts_hashinto(%h, %c0, %c1, %at) : (!llvm.ptr, i64, i64, !llvm.ptr) -> i64
        %k = arith.addi %hn64, %tn : i64
        %last = llvm.getelementptr %payload[%k] : (!llvm.ptr, i64) -> !llvm.ptr, i8
        %tail_d = func.call @spm_desc(%last, %c1) : (!llvm.ptr, i64) -> !d
        %tail = builtin.unrealized_conversion_cast %tail_d : !d to !m
        %e2 = trikeshed.drain %colon, %tail : !s, !m -> index
        %total = arith.addi %k, %c1 : i64
        func.call @nixstore_ts_hashstring(%c2, %payload, %total, %digest) : (i64, !llvm.ptr, i64, !llvm.ptr) -> ()
        %tp = func.call @spm_word(%type_o) : (index) -> !llvm.ptr
        %tn64 = arith.index_cast %type_n : index to i64
        %r5 = func.call @nixstore_ts_makestorepath(%sd, %sdn, %tp, %tn64, %digest, %np, %nn, %out) : (!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr) -> i64
        scf.yield %r5 : i64
      }
      scf.yield %r4 : i64
    }
    scf.yield %r2 : i64
  }
  return %r : i64
}

// makeOutputPath: the type `output:<output>` and the name outputPathName's, both in one room, then the path
func.func @nixstore_ts_outputpath(%sd: !llvm.ptr, %sdn: i64, %op: !llvm.ptr, %on: i64, %h: !llvm.ptr, %dp: !llvm.ptr, %dn: i64, %out: !llvm.ptr) -> i64 {
  %c1 = arith.constant 1 : i64
  %c4096 = arith.constant 4096 : i64
  %words_g = memref.get_global @spm_words : memref<383xi8>
  %words = trikeshed.text %words_g : memref<383xi8> -> !s
  %lead_o = arith.constant 246 : index  // "output:"
  %lead_n = arith.constant 7 : index
  %lead = trikeshed.slice %words[%lead_o, %lead_n] : !s -> !s
  %stack = llvm.alloca %c4096 x i8 : (i64) -> !llvm.ptr
  %output_d = func.call @spm_desc(%op, %on) : (!llvm.ptr, i64) -> !d
  %output_m = builtin.unrealized_conversion_cast %output_d : !d to !m
  %output = builtin.unrealized_conversion_cast %output_m : !m to !s
  %type = trikeshed.combine %lead, %output : !s, !s -> !s
  %tn = trikeshed.size %type : !s
  %tn64 = arith.index_cast %tn : index to i64
  %n0 = arith.addi %dn, %c1 : i64
  %namecap = arith.addi %n0, %on : i64
  %need = arith.addi %tn64, %namecap : i64
  %buf = func.call @spm_room(%stack, %need) : (!llvm.ptr, i64) -> !llvm.ptr
  %troom_d = func.call @spm_desc(%buf, %tn64) : (!llvm.ptr, i64) -> !d
  %troom = builtin.unrealized_conversion_cast %troom_d : !d to !m
  %e = trikeshed.drain %type, %troom : !s, !m -> index
  %name = llvm.getelementptr %buf[%tn64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %nn = func.call @nixstore_ts_outputname(%dp, %dn, %op, %on, %name) : (!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr) -> i64
  %r = func.call @nixstore_ts_makestorepath(%sd, %sdn, %buf, %tn64, %h, %name, %nn, %out) : (!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr) -> i64
  func.call @spm_done(%buf, %stack) : (!llvm.ptr, !llvm.ptr) -> ()
  return %r : i64
}

// hashPlaceholder: "/" and the 52 digits of Nix's base 32 of sha256("nix-output:" output)
func.func @nixstore_ts_placeholder(%op: !llvm.ptr, %on: i64, %out: !llvm.ptr) {
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c4 = arith.constant 4 : i64
  %c9 = arith.constant 9 : i64
  %c32 = arith.constant 32 : i64
  %c53 = arith.constant 53 : i64
  %c4096 = arith.constant 4096 : i64
  %words_g = memref.get_global @spm_words : memref<383xi8>
  %words = trikeshed.text %words_g : memref<383xi8> -> !s
  %lead_o = arith.constant 340 : index  // "nix-output:"
  %lead_n = arith.constant 11 : index
  %lead = trikeshed.slice %words[%lead_o, %lead_n] : !s -> !s
  %slash_o = arith.constant 351 : index  // "/"
  %slash_n = arith.constant 1 : index
  %slash = trikeshed.slice %words[%slash_o, %slash_n] : !s -> !s
  %stack = llvm.alloca %c4096 x i8 : (i64) -> !llvm.ptr
  %digest = llvm.alloca %c9 x i64 : (i64) -> !llvm.ptr
  %output_d = func.call @spm_desc(%op, %on) : (!llvm.ptr, i64) -> !d
  %output_m = builtin.unrealized_conversion_cast %output_d : !d to !m
  %output = builtin.unrealized_conversion_cast %output_m : !m to !s
  %text = trikeshed.combine %lead, %output : !s, !s -> !s
  %tn = trikeshed.size %text : !s
  %tn64 = arith.index_cast %tn : index to i64
  %buf = func.call @spm_room(%stack, %tn64) : (!llvm.ptr, i64) -> !llvm.ptr
  %troom_d = func.call @spm_desc(%buf, %tn64) : (!llvm.ptr, i64) -> !d
  %troom = builtin.unrealized_conversion_cast %troom_d : !d to !m
  %e = trikeshed.drain %text, %troom : !s, !m -> index
  func.call @nixstore_ts_hashstring(%c2, %buf, %tn64, %digest) : (i64, !llvm.ptr, i64, !llvm.ptr) -> ()
  func.call @spm_done(%buf, %stack) : (!llvm.ptr, !llvm.ptr) -> ()
  %room = func.call @nixstore_text_sized(%out, %c53) : (!llvm.ptr, i64) -> !llvm.ptr
  %first_d = func.call @spm_desc(%room, %c1) : (!llvm.ptr, i64) -> !d
  %first = builtin.unrealized_conversion_cast %first_d : !d to !m
  %e2 = trikeshed.drain %slash, %first : !s, !m -> index
  %at = llvm.getelementptr %room[%c1] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %bytes = llvm.getelementptr %digest[%c4] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %w = func.call @mlnix_nix32_encode(%bytes, %c32, %at) : (!llvm.ptr, i64, !llvm.ptr) -> i64
  return
}

// toStorePath: a path in the store, up to the first slash after the store directory's (all of it when there is none).
// The slash is found by one fold over the bytes after `storeDir/`: the place, and the first slash's place once met.
func.func @nixstore_ts_tostorepath(%sd: !llvm.ptr, %sdn: i64, %p: !llvm.ptr, %n: i64, %out: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c32 = arith.constant 32 : i64
  %low = arith.constant 4294967295 : i64
  %m1 = arith.constant -1 : i32
  %slash = arith.constant 47 : i8
  %z = arith.constant 0 : index
  %lead_o = arith.constant 352 : index  // "path '"
  %lead_n = arith.constant 6 : index
  %notin_o = arith.constant 358 : index  // "' is not in the Nix store"
  %notin_n = arith.constant 25 : index
  %none_o = arith.constant 0 : index  // ""
  %none_n = arith.constant 0 : index
  %in = func.call @mlnix_isInStore(%sd, %sdn, %p, %n) : (!llvm.ptr, i64, !llvm.ptr, i64) -> i1
  %r = scf.if %in -> (i64) {
    %path_d = func.call @spm_desc(%p, %n) : (!llvm.ptr, i64) -> !d
    %path_m = builtin.unrealized_conversion_cast %path_d : !d to !m
    %path = builtin.unrealized_conversion_cast %path_m : !m to !s
    %from = arith.addi %sdn, %c1 : i64
    %fromi = arith.index_cast %from : i64 to index
    %rest64 = arith.subi %n, %from : i64
    %resti = arith.index_cast %rest64 : i64 to index
    %tail = trikeshed.slice %path[%fromi, %resti] : !s -> !s
    %acc = trikeshed.fold %tail, %c0 : !s, i64 -> i64 {
    ^bb0(%a: i64, %b: i8):
      %pos = arith.andi %a, %low : i64
      %first = arith.shrui %a, %c32 : i64
      %is = arith.cmpi eq, %b, %slash : i8
      %unmet = arith.cmpi eq, %first, %c0 : i64
      %here = arith.andi %is, %unmet : i1
      %pos1 = arith.addi %pos, %c1 : i64
      %first2 = arith.select %here, %pos1, %first : i64
      %hi = arith.shli %first2, %c32 : i64
      %a2 = arith.ori %hi, %pos1 : i64
      trikeshed.yield %a2 : i64
    }
    %met1 = arith.shrui %acc, %c32 : i64
    %met = arith.cmpi ne, %met1, %c0 : i64
    %at0 = arith.subi %met1, %c1 : i64
    %at = arith.addi %from, %at0 : i64
    %len = arith.select %met, %at, %n : i64
    %leni = arith.index_cast %len : i64 to index
    %kept = trikeshed.slice %path[%z, %leni] : !s -> !s
    %room = func.call @nixstore_text_sized(%out, %len) : (!llvm.ptr, i64) -> !llvm.ptr
    %into_d = func.call @spm_desc(%room, %len) : (!llvm.ptr, i64) -> !d
    %into = builtin.unrealized_conversion_cast %into_d : !d to !m
    %e = trikeshed.drain %kept, %into : !s, !m -> index
    scf.yield %c0 : i64
  } else {
    %f = func.call @spm_fail(%out, %lead_o, %lead_n, %p, %n, %notin_o, %notin_n, %p, %c0, %none_o, %none_n, %m1) : (!llvm.ptr, index, index, !llvm.ptr, i64, index, index, !llvm.ptr, i64, index, index, i32) -> i64
    scf.yield %f : i64
  }
  return %r : i64
}

//===----------------------------------------------------------------------===//
// A Text of what an older entry writes: sized to the entry's bound, cut to what it wrote
//===----------------------------------------------------------------------===//

// the Text at out given room for `bound` bytes (none asked for when there are none to write)
func.func private @spm_bound(%out: !llvm.ptr, %bound: i64) -> !llvm.ptr {
  %c0 = arith.constant 0 : i64
  %null = llvm.mlir.zero : !llvm.ptr
  %some = arith.cmpi ne, %bound, %c0 : i64
  %p = scf.if %some -> (!llvm.ptr) {
    %q = func.call @nixstore_text_sized(%out, %bound) : (!llvm.ptr, i64) -> !llvm.ptr
    scf.yield %q : !llvm.ptr
  } else {
    scf.yield %null : !llvm.ptr
  }
  return %p : !llvm.ptr
}
func.func private @spm_cut(%out: !llvm.ptr, %bound: i64, %w: i64) {
  %less = arith.cmpi ne, %w, %bound : i64
  scf.if %less {
    %q = func.call @nixstore_text_sized(%out, %w) : (!llvm.ptr, i64) -> !llvm.ptr
  }
  return
}

func.func @nixstore_tx_basename(%p: !llvm.ptr, %n: i64, %out: !llvm.ptr) {
  %room = func.call @spm_bound(%out, %n) : (!llvm.ptr, i64) -> !llvm.ptr
  %w = func.call @nixstore_ts_basename(%p, %n, %room) : (!llvm.ptr, i64, !llvm.ptr) -> i64
  func.call @spm_cut(%out, %n, %w) : (!llvm.ptr, i64, i64) -> ()
  return
}
func.func @nixstore_tx_dirname(%p: !llvm.ptr, %n: i64, %out: !llvm.ptr) {
  %c1 = arith.constant 1 : i64
  %bound = arith.addi %n, %c1 : i64
  %room = func.call @spm_bound(%out, %bound) : (!llvm.ptr, i64) -> !llvm.ptr
  %w = func.call @nixstore_ts_dirname(%p, %n, %room) : (!llvm.ptr, i64, !llvm.ptr) -> i64
  func.call @spm_cut(%out, %bound, %w) : (!llvm.ptr, i64, i64) -> ()
  return
}
func.func @nixstore_tx_outputname(%dp: !llvm.ptr, %dn: i64, %op: !llvm.ptr, %on: i64, %out: !llvm.ptr) {
  %c1 = arith.constant 1 : i64
  %b0 = arith.addi %dn, %c1 : i64
  %bound = arith.addi %b0, %on : i64
  %room = func.call @spm_bound(%out, %bound) : (!llvm.ptr, i64) -> !llvm.ptr
  %w = func.call @nixstore_ts_outputname(%dp, %dn, %op, %on, %room) : (!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr) -> i64
  func.call @spm_cut(%out, %bound, %w) : (!llvm.ptr, i64, i64) -> ()
  return
}
func.func @nixstore_tx_storename(%p: !llvm.ptr, %n: i64, %out: !llvm.ptr) {
  %room = func.call @spm_bound(%out, %n) : (!llvm.ptr, i64) -> !llvm.ptr
  %w = func.call @nixstore_ts_storename(%p, %n, %room) : (!llvm.ptr, i64, !llvm.ptr) -> i64
  func.call @spm_cut(%out, %n, %w) : (!llvm.ptr, i64, i64) -> ()
  return
}
func.func @nixstore_tx_storehash(%p: !llvm.ptr, %n: i64, %out: !llvm.ptr) {
  %c32 = arith.constant 32 : i64
  %room = func.call @spm_bound(%out, %c32) : (!llvm.ptr, i64) -> !llvm.ptr
  %w = func.call @nixstore_ts_storehash(%p, %n, %room) : (!llvm.ptr, i64, !llvm.ptr) -> i64
  func.call @spm_cut(%out, %c32, %w) : (!llvm.ptr, i64, i64) -> ()
  return
}
func.func @nixstore_tx_jsonfloat(%x: f64, %out: !llvm.ptr) {
  %c32 = arith.constant 32 : i64
  %c64 = arith.constant 64 : i64
  %buf = llvm.alloca %c64 x i8 : (i64) -> !llvm.ptr
  %room = func.call @spm_bound(%out, %c32) : (!llvm.ptr, i64) -> !llvm.ptr
  %w = func.call @nixstore_ts_jsonfloat(%x, %room, %buf) : (f64, !llvm.ptr, !llvm.ptr) -> i64
  func.call @spm_cut(%out, %c32, %w) : (!llvm.ptr, i64, i64) -> ()
  return
}
