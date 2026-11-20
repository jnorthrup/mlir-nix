// SHA-512 (FIPS 180-4), hollowed from lib/Store/Hash.cpp's SHA512Ctx into the TrikeShed dialect: the compression
// function, the buffering of update and the padding of final are here; HashSink (Hash.cpp) keeps its interface and
// holds this context as plain state in its impl bytes, calling the three entries below.  SHA-256, MD5 and SHA-1 stay on
// the platform's implementations.
//
// The context is 208 bytes, the old struct's layout: h[8] i64 @0, buf[128] i8 @64, bufLen i64 @192, totalLen i64 @200.
//   mlnix_sha512_init(ctx)            the initial hash value, empty buffer, length 0
//   mlnix_sha512_update(ctx, p, n)    totalLen += n; the bytes drained into the buffer, a block compressed whenever it
//                                     fills (a whole block straight from the input when the buffer is empty: the same
//                                     128 bytes are compressed, the buffer's stale bytes are never read again)
//   mlnix_sha512_final(ctx, out)      0x80, zeros to 112 mod 128 and the 128-bit big-endian bit length, as ONE update of
//                                     a combine (a slice of the constant pad + a series of the length bytes), then the
//                                     digest as a series of the big-endian bytes of h, drained into out[64]
// The compression: w[0..16) are a fold over each 8-byte slice of the block (big-endian), the schedule and the 80 rounds
// are scf.for loops over i64 with K read by trikeshed.at from its constant table.  Helper names are module-unique
// (sha512_*): the pipeline exports func.func private as global symbols.
!b = !trikeshed.series<i8>
!q = !trikeshed.series<i64>
!m = memref<?xi8, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

memref.global "private" constant @sha512_k : memref<80xi64> =
  dense<[4794697086780616226, 8158064640168781261, -5349999486874862801, -1606136188198331460, 4131703408338449720, 6480981068601479193, -7908458776815382629, -6116909921290321640, -2880145864133508542, 1334009975649890238, 2608012711638119052, 6128411473006802146, 8268148722764581231, -9160688886553864527, -7215885187991268811, -4495734319001033068, -1973867731355612462, -1171420211273849373, 1135362057144423861, 2597628984639134821, 3308224258029322869, 5365058923640841347, 6679025012923562964, 8573033837759648693, -7476448914759557205, -6327057829258317296, -5763719355590565569, -4658551843659510044, -4116276920077217854, -3051310485924567259, 489312712824947311, 1452737877330783856, 2861767655752347644, 3322285676063803686, 5560940570517711597, 5996557281743188959, 7280758554555802590, 8532644243296465576, -9096487096722542874, -7894198246740708037, -6719396339535248540, -6333637450476146687, -4446306890439682159, -4076793802049405392, -3345356375505022440, -2983346525034927856, -860691631967231958, 1182934255886127544, 1847814050463011016, 2177327727835720531, 2830643537854262169, 3796741975233480872, 4115178125766777443, 5681478168544905931, 6601373596472566643, 7507060721942968483, 8399075790359081724, 8693463985226723168, -8878714635349349518, -8302665154208450068, -8016688836872298968, -6606660893046293015, -4685533653050689259, -4147400797238176981, -3880063495543823972, -3348786107499101689, -1523767162380948706, -757361751448694408, 500013540394364858, 748580250866718886, 1242879168328830382, 1977374033974150939, 2944078676154940804, 3659926193048069267, 4368137639120453308, 4836135668995329356, 5532061633213252278, 6448918945643986474, 6902733635092675308, 7801388544844847127]>
memref.global "private" constant @sha512_iv : memref<8xi64> =
  dense<[7640891576956012808, -4942790177534073029, 4354685564936845355, -6534734903238641935, 5840696475078001361, -7276294671716946913, 2270897969802886507, 6620516959819538809]>
memref.global "private" constant @sha512_pad : memref<128xi8> =
  dense<[-128, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]>

// the descriptor of n i8 cells at p (a struct, not a memref: returning it allocates nothing and clones nothing)
func.func private @sha512_desc(%p: !llvm.ptr, %n: i64) -> !d {
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

func.func @mlnix_sha512_init(%ctx: !llvm.ptr) {
  %z = arith.constant 0 : i64
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c8 = arith.constant 8 : index
  %ivg = memref.get_global @sha512_iv : memref<8xi64>
  %iv = trikeshed.text %ivg : memref<8xi64> -> !q
  scf.for %i = %c0 to %c8 step %c1 {
    %x = trikeshed.at %iv[%i] : !q, index -> i64
    %i64 = arith.index_cast %i : index to i64
    %hp = llvm.getelementptr %ctx[%i64] : (!llvm.ptr, i64) -> !llvm.ptr, i64
    llvm.store %x, %hp : i64, !llvm.ptr
  }
  %c24 = arith.constant 24 : i64
  %c25 = arith.constant 25 : i64
  %blp = llvm.getelementptr %ctx[%c24] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  llvm.store %z, %blp : i64, !llvm.ptr
  %tlp = llvm.getelementptr %ctx[%c25] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  llvm.store %z, %tlp : i64, !llvm.ptr
  return
}

// one 128-byte block at p into the hash value h[8]
func.func private @sha512_compress(%h: !llvm.ptr, %p: !llvm.ptr) {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c2i = arith.constant 2 : index
  %c7i = arith.constant 7 : index
  %c8i = arith.constant 8 : index
  %c15i = arith.constant 15 : index
  %c16i = arith.constant 16 : index
  %c80i = arith.constant 80 : index
  %z = arith.constant 0 : i64
  %c128 = arith.constant 128 : i64
  %m1 = arith.constant -1 : i64
  %sh1 = arith.constant 1 : i64
  %sh3 = arith.constant 3 : i64
  %sh6 = arith.constant 6 : i64
  %sh7 = arith.constant 7 : i64
  %sh8 = arith.constant 8 : i64
  %sh14 = arith.constant 14 : i64
  %sh18 = arith.constant 18 : i64
  %sh19 = arith.constant 19 : i64
  %sh23 = arith.constant 23 : i64
  %sh25 = arith.constant 25 : i64
  %sh28 = arith.constant 28 : i64
  %sh30 = arith.constant 30 : i64
  %sh34 = arith.constant 34 : i64
  %sh36 = arith.constant 36 : i64
  %sh39 = arith.constant 39 : i64
  %sh41 = arith.constant 41 : i64
  %sh45 = arith.constant 45 : i64
  %sh46 = arith.constant 46 : i64
  %sh50 = arith.constant 50 : i64
  %sh56 = arith.constant 56 : i64
  %sh61 = arith.constant 61 : i64
  %sh63 = arith.constant 63 : i64
  %d = func.call @sha512_desc(%p, %c128) : (!llvm.ptr, i64) -> !d
  %dm = builtin.unrealized_conversion_cast %d : !d to !m
  %bytes = builtin.unrealized_conversion_cast %dm : !m to !b
  %kg = memref.get_global @sha512_k : memref<80xi64>
  %ks = trikeshed.text %kg : memref<80xi64> -> !q
  %w = memref.alloca() : memref<80xi64>
  scf.for %i = %c0 to %c16i step %c1 {
    %off = arith.muli %i, %c8i : index
    %wb = trikeshed.slice %bytes[%off, %c8i] : !b -> !b
    %word = trikeshed.fold %wb, %z : !b, i64 -> i64 {
    ^bb0(%acc: i64, %x: i8):
      %xs = arith.extui %x : i8 to i64
      %sh = arith.shli %acc, %sh8 : i64
      %nx = arith.ori %sh, %xs : i64
      trikeshed.yield %nx : i64
    }
    memref.store %word, %w[%i] : memref<80xi64>
  }
  scf.for %i = %c16i to %c80i step %c1 {
    %i15 = arith.subi %i, %c15i : index
    %i2 = arith.subi %i, %c2i : index
    %i16 = arith.subi %i, %c16i : index
    %i7 = arith.subi %i, %c7i : index
    %w15 = memref.load %w[%i15] : memref<80xi64>
    %w2 = memref.load %w[%i2] : memref<80xi64>
    %w16 = memref.load %w[%i16] : memref<80xi64>
    %w7 = memref.load %w[%i7] : memref<80xi64>
    %a1r = arith.shrui %w15, %sh1 : i64
    %a1l = arith.shli %w15, %sh63 : i64
    %a1 = arith.ori %a1r, %a1l : i64
    %a8r = arith.shrui %w15, %sh8 : i64
    %a8l = arith.shli %w15, %sh56 : i64
    %a8 = arith.ori %a8r, %a8l : i64
    %a7 = arith.shrui %w15, %sh7 : i64
    %s0x = arith.xori %a1, %a8 : i64
    %s0 = arith.xori %s0x, %a7 : i64
    %b19r = arith.shrui %w2, %sh19 : i64
    %b19l = arith.shli %w2, %sh45 : i64
    %b19 = arith.ori %b19r, %b19l : i64
    %b61r = arith.shrui %w2, %sh61 : i64
    %b61l = arith.shli %w2, %sh3 : i64
    %b61 = arith.ori %b61r, %b61l : i64
    %b6 = arith.shrui %w2, %sh6 : i64
    %s1x = arith.xori %b19, %b61 : i64
    %s1 = arith.xori %s1x, %b6 : i64
    %t0 = arith.addi %w16, %s0 : i64
    %t1 = arith.addi %t0, %w7 : i64
    %wi = arith.addi %t1, %s1 : i64
    memref.store %wi, %w[%i] : memref<80xi64>
  }
  %c0x = arith.constant 0 : i64
  %hp0 = llvm.getelementptr %h[%c0x] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %h0 = llvm.load %hp0 : !llvm.ptr -> i64
  %c1x64 = arith.constant 1 : i64
  %hp1 = llvm.getelementptr %h[%c1x64] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %h1 = llvm.load %hp1 : !llvm.ptr -> i64
  %c2x = arith.constant 2 : i64
  %hp2 = llvm.getelementptr %h[%c2x] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %h2 = llvm.load %hp2 : !llvm.ptr -> i64
  %c3x = arith.constant 3 : i64
  %hp3 = llvm.getelementptr %h[%c3x] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %h3 = llvm.load %hp3 : !llvm.ptr -> i64
  %c4x = arith.constant 4 : i64
  %hp4 = llvm.getelementptr %h[%c4x] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %h4 = llvm.load %hp4 : !llvm.ptr -> i64
  %c5x = arith.constant 5 : i64
  %hp5 = llvm.getelementptr %h[%c5x] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %h5 = llvm.load %hp5 : !llvm.ptr -> i64
  %c6x = arith.constant 6 : i64
  %hp6 = llvm.getelementptr %h[%c6x] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %h6 = llvm.load %hp6 : !llvm.ptr -> i64
  %c7x = arith.constant 7 : i64
  %hp7 = llvm.getelementptr %h[%c7x] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %h7 = llvm.load %hp7 : !llvm.ptr -> i64
  %r:8 = scf.for %i = %c0 to %c80i step %c1 iter_args(%a = %h0, %b = %h1, %c = %h2, %dd = %h3, %e = %h4, %f = %h5, %g = %h6, %hh = %h7) -> (i64, i64, i64, i64, i64, i64, i64, i64) {
    %e14r = arith.shrui %e, %sh14 : i64
    %e14l = arith.shli %e, %sh50 : i64
    %e14 = arith.ori %e14r, %e14l : i64
    %e18r = arith.shrui %e, %sh18 : i64
    %e18l = arith.shli %e, %sh46 : i64
    %e18 = arith.ori %e18r, %e18l : i64
    %e41r = arith.shrui %e, %sh41 : i64
    %e41l = arith.shli %e, %sh23 : i64
    %e41 = arith.ori %e41r, %e41l : i64
    %S1x = arith.xori %e14, %e18 : i64
    %S1 = arith.xori %S1x, %e41 : i64
    %ef = arith.andi %e, %f : i64
    %ne = arith.xori %e, %m1 : i64
    %neg = arith.andi %ne, %g : i64
    %ch = arith.xori %ef, %neg : i64
    %ki = trikeshed.at %ks[%i] : !q, index -> i64
    %wi = memref.load %w[%i] : memref<80xi64>
    %u0 = arith.addi %hh, %S1 : i64
    %u1 = arith.addi %u0, %ch : i64
    %u2 = arith.addi %u1, %ki : i64
    %t1 = arith.addi %u2, %wi : i64
    %a28r = arith.shrui %a, %sh28 : i64
    %a28l = arith.shli %a, %sh36 : i64
    %a28 = arith.ori %a28r, %a28l : i64
    %a34r = arith.shrui %a, %sh34 : i64
    %a34l = arith.shli %a, %sh30 : i64
    %a34 = arith.ori %a34r, %a34l : i64
    %a39r = arith.shrui %a, %sh39 : i64
    %a39l = arith.shli %a, %sh25 : i64
    %a39 = arith.ori %a39r, %a39l : i64
    %S0x = arith.xori %a28, %a34 : i64
    %S0 = arith.xori %S0x, %a39 : i64
    %ab = arith.andi %a, %b : i64
    %ac = arith.andi %a, %c : i64
    %bc = arith.andi %b, %c : i64
    %mjx = arith.xori %ab, %ac : i64
    %mj = arith.xori %mjx, %bc : i64
    %t2 = arith.addi %S0, %mj : i64
    %ne2 = arith.addi %dd, %t1 : i64
    %na = arith.addi %t1, %t2 : i64
    scf.yield %na, %a, %b, %c, %ne2, %e, %f, %g : i64, i64, i64, i64, i64, i64, i64, i64
  }
  %s0 = arith.addi %h0, %r#0 : i64
  llvm.store %s0, %hp0 : i64, !llvm.ptr
  %s1 = arith.addi %h1, %r#1 : i64
  llvm.store %s1, %hp1 : i64, !llvm.ptr
  %s2 = arith.addi %h2, %r#2 : i64
  llvm.store %s2, %hp2 : i64, !llvm.ptr
  %s3 = arith.addi %h3, %r#3 : i64
  llvm.store %s3, %hp3 : i64, !llvm.ptr
  %s4 = arith.addi %h4, %r#4 : i64
  llvm.store %s4, %hp4 : i64, !llvm.ptr
  %s5 = arith.addi %h5, %r#5 : i64
  llvm.store %s5, %hp5 : i64, !llvm.ptr
  %s6 = arith.addi %h6, %r#6 : i64
  llvm.store %s6, %hp6 : i64, !llvm.ptr
  %s7 = arith.addi %h7, %r#7 : i64
  llvm.store %s7, %hp7 : i64, !llvm.ptr
  return
}

func.func @mlnix_sha512_update(%ctx: !llvm.ptr, %p: !llvm.ptr, %n: i64) {
  %c0 = arith.constant 0 : i64
  %c8 = arith.constant 8 : i64
  %c24 = arith.constant 24 : i64
  %c25 = arith.constant 25 : i64
  %c64 = arith.constant 64 : i64
  %c128 = arith.constant 128 : i64
  %tlp = llvm.getelementptr %ctx[%c25] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %tl = llvm.load %tlp : !llvm.ptr -> i64
  %tl2 = arith.addi %tl, %n : i64
  llvm.store %tl2, %tlp : i64, !llvm.ptr
  %blp = llvm.getelementptr %ctx[%c24] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %bl0 = llvm.load %blp : !llvm.ptr -> i64
  %buf = llvm.getelementptr %ctx[%c64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %src = func.call @sha512_desc(%p, %n) : (!llvm.ptr, i64) -> !d
  %srcm = builtin.unrealized_conversion_cast %src : !d to !m
  %input = builtin.unrealized_conversion_cast %srcm : !m to !b
  %fin:2 = scf.while (%off = %c0, %bl = %bl0) : (i64, i64) -> (i64, i64) {
    %more = arith.cmpi ult, %off, %n : i64
    scf.condition(%more) %off, %bl : i64, i64
  } do {
  ^bb0(%off: i64, %bl: i64):
    %left = arith.subi %n, %off : i64
    %empty = arith.cmpi eq, %bl, %c0 : i64
    %whole = arith.cmpi uge, %left, %c128 : i64
    %direct = arith.andi %empty, %whole : i1
    %nx:2 = scf.if %direct -> (i64, i64) {
      %at = llvm.getelementptr %p[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      func.call @sha512_compress(%ctx, %at) : (!llvm.ptr, !llvm.ptr) -> ()
      %o2 = arith.addi %off, %c128 : i64
      scf.yield %o2, %c0 : i64, i64
    } else {
      %room = arith.subi %c128, %bl : i64
      %take = arith.minui %left, %room : i64
      %offi = arith.index_cast %off : i64 to index
      %takei = arith.index_cast %take : i64 to index
      %piece = trikeshed.slice %input[%offi, %takei] : !b -> !b
      %dst = llvm.getelementptr %buf[%bl] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %dd = func.call @sha512_desc(%dst, %take) : (!llvm.ptr, i64) -> !d
      %dm = builtin.unrealized_conversion_cast %dd : !d to !m
      %end = trikeshed.drain %piece, %dm : !b, !m -> index
      %bl2 = arith.addi %bl, %take : i64
      %o2 = arith.addi %off, %take : i64
      %full = arith.cmpi eq, %bl2, %c128 : i64
      %bl3 = scf.if %full -> (i64) {
        func.call @sha512_compress(%ctx, %buf) : (!llvm.ptr, !llvm.ptr) -> ()
        scf.yield %c0 : i64
      } else {
        scf.yield %bl2 : i64
      }
      scf.yield %o2, %bl3 : i64, i64
    }
    scf.yield %nx#0, %nx#1 : i64, i64
  }
  llvm.store %fin#1, %blp : i64, !llvm.ptr
  return
}

func.func @mlnix_sha512_final(%ctx: !llvm.ptr, %out: !llvm.ptr) {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c8i = arith.constant 8 : index
  %c15i = arith.constant 15 : index
  %c16i = arith.constant 16 : index
  %c64i = arith.constant 64 : index
  %z = arith.constant 0 : i64
  %c3 = arith.constant 3 : i64
  %c8 = arith.constant 8 : i64
  %c24 = arith.constant 24 : i64
  %c25 = arith.constant 25 : i64
  %c56 = arith.constant 56 : i64
  %c64 = arith.constant 64 : i64
  %c111 = arith.constant 111 : i64
  %c1x64 = arith.constant 1 : i64
  %c127 = arith.constant 127 : i64
  %c128 = arith.constant 128 : i64
  %tlp = llvm.getelementptr %ctx[%c25] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %tl = llvm.load %tlp : !llvm.ptr -> i64
  %bits = arith.shli %tl, %c3 : i64
  %blp = llvm.getelementptr %ctx[%c24] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %bl = llvm.load %blp : !llvm.ptr -> i64
  // zeros after the 0x80 so that bufLen lands on 112: (111 - bufLen) mod 128
  %zr = arith.subi %c111, %bl : i64
  %zr2 = arith.addi %zr, %c128 : i64
  %zeros = arith.andi %zr2, %c127 : i64
  %padn = arith.addi %zeros, %c1x64 : i64
  %padi = arith.index_cast %padn : i64 to index
  %pg = memref.get_global @sha512_pad : memref<128xi8>
  %pt = trikeshed.text %pg : memref<128xi8> -> !b
  %pad = trikeshed.slice %pt[%c0, %padi] : !b -> !b
  // the 128-bit big-endian bit length: the high 8 bytes are 0 (a u64 count)
  %len = trikeshed.series %c16i : !b {
  ^bb0(%k: index):
    %hi = arith.cmpi ult, %k, %c8i : index
    %e = arith.subi %c15i, %k : index
    %e64 = arith.index_cast %e : index to i64
    %sh = arith.muli %e64, %c8 : i64
    %shc = arith.minui %sh, %c56 : i64
    %v = arith.shrui %bits, %shc : i64
    %v8 = arith.trunci %v : i64 to i8
    %z8 = arith.constant 0 : i8
    %r = arith.select %hi, %z8, %v8 : i8
    trikeshed.yield %r : i8
  }
  %tail = trikeshed.combine %pad, %len : !b, !b -> !b
  %room = memref.alloca() : memref<144xi8>
  %roomv = memref.cast %room : memref<144xi8> to !m
  %tn = trikeshed.drain %tail, %roomv : !b, !m -> index
  %base = memref.extract_aligned_pointer_as_index %room : memref<144xi8> -> index
  %base64 = arith.index_cast %base : index to i64
  %bp = llvm.inttoptr %base64 : i64 to !llvm.ptr
  %tn64 = arith.index_cast %tn : index to i64
  func.call @mlnix_sha512_update(%ctx, %bp, %tn64) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  // the digest: byte j is h[j/8] >> (56 - 8 (j%8))
  %digest = trikeshed.series %c64i : !b {
  ^bb0(%j: index):
    %wi = arith.divui %j, %c8i : index
    %bi = arith.remui %j, %c8i : index
    %wi64 = arith.index_cast %wi : index to i64
    %hp = llvm.getelementptr %ctx[%wi64] : (!llvm.ptr, i64) -> !llvm.ptr, i64
    %hv = llvm.load %hp : !llvm.ptr -> i64
    %bi64 = arith.index_cast %bi : index to i64
    %b8 = arith.muli %bi64, %c8 : i64
    %sh = arith.subi %c56, %b8 : i64
    %v = arith.shrui %hv, %sh : i64
    %v8 = arith.trunci %v : i64 to i8
    trikeshed.yield %v8 : i8
  }
  %od = func.call @sha512_desc(%out, %c64) : (!llvm.ptr, i64) -> !d
  %om = builtin.unrealized_conversion_cast %od : !d to !m
  %dn = trikeshed.drain %digest, %om : !b, !m -> index
  return
}
