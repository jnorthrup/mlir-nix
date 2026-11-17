// trikeshed.combine and trikeshed.combineAll, Combine.kt's combine of a vararg and of a Series<Series<A>>, and
// confix.unescape, KnownSchema.decodeEscaped: lowered by trikeshed-lower-cursors and run.
//   combine of "bc", "." and "d" (slices of "a/bc//d" and a constant) is "bc.d";
//   combineAll of the parts of "a/bc//d" at '/' (trikeshed.parts) with "." between each two is "a.bc..d", and the
//   coordinates of its 7 parts are their (start, length) in it;
//   combineAll nested: two rows, the parts of "a/bc//d" and of its slice "bc/" each joined so, are "a.bc..d" and "bc.";
//   combineAll of no parts is empty;
//   confix.unescape of JSON's escapes, of \u code points (a surrogate pair, lone surrogates), of escapes JSON does not
//   have (kept as written), and of a text escaped as Python's json.dumps escapes it, which gives that text's UTF-8
//   again.  The bytes are printed as i32.
//
// RUN: mlnix-opt %s | mlnix-opt | FileCheck %s --check-prefix=ROUND
// RUN: mlnix-opt %s --trikeshed-lower-cursors | mlir-opt --ownership-based-buffer-deallocation --canonicalize --buffer-deallocation-simplification --bufferization-lower-deallocations --convert-scf-to-cf --expand-strided-metadata --lower-affine --finalize-memref-to-llvm --convert-arith-to-llvm --convert-index-to-llvm --convert-cf-to-llvm --convert-func-to-llvm --reconcile-unrealized-casts | mlir-runner -e main -entry-point-result=i32 -shared-libs=$(ls $(dirname $(which mlir-runner))/../lib/libmlir_runner_utils.* | head -1) | FileCheck %s

// ROUND: trikeshed.combine %{{.*}}, %{{.*}}, %{{.*}} : !trikeshed.series<i8>, !trikeshed.series<i8>, !trikeshed.series<i8> -> <i8>
// ROUND: trikeshed.combineAll %{{.*}} : <i8>, <!trikeshed.twinpacked<i32>>
// ROUND: confix.unescape json %{{.*}} : !trikeshed.series<i8> -> !trikeshed.series<i8>

// combine
// CHECK: [98, 99, 46, 100]
// combineAll: the text, then its parts' starts and lengths
// CHECK: [97, 46, 98, 99, 46, 46, 100]
// CHECK: [0, 1, 2, 4, 5, 5, 6]
// CHECK: [1, 1, 2, 1, 0, 1, 1]
// nested
// CHECK: [97, 46, 98, 99, 46, 46, 100, 98, 99, 46]
// CHECK: [0, 7]
// CHECK: [7, 3]
// none: empty, as its coordinates (printMemref shows a stray cell after an empty buffer's header)
// CHECK: sizes = [0]
// CHECK: sizes = [0]
// CHECK: sizes = [0]
// confix.unescape
// CHECK: [97, 34, 98, 92, 99, 47, 100, 8, 12, 10, 13, 9, 122]
// CHECK: [65, 195, 169, 226, 128, 153, 240, 159, 152, 128]
// CHECK: [239, 191, 189, 120, 239, 191, 189, 92, 120, 92, 117, 49, 50]
// CHECK: [97, 98, 92]
// CHECK: [92, 117, 48, 48, 71, 49]
// CHECK: [239, 191, 189, 65]
// CHECK: [112, 108, 97, 105, 110]
// CHECK: [104, 195, 169, 108, 108, 111, 32, 34, 119, 195, 182, 114, 108, 100, 34, 32, 92, 32, 47, 32, 10, 9, 226, 128, 153, 32, 240, 159, 152, 128, 32, 1]
// CHECK: 0

!text = !trikeshed.series<i8>
!s32 = !trikeshed.series<i32>
!tp = !trikeshed.twinpacked<i32>
!sp = !trikeshed.series<!tp>

memref.global "private" constant @path : memref<7xi8> = dense<[97, 47, 98, 99, 47, 47, 100]>
memref.global "private" constant @dot : memref<1xi8> = dense<[46]>
memref.global "private" constant @simple : memref<21xi8> = dense<[97, 92, 34, 98, 92, 92, 99, 92, 47, 100, 92, 98, 92, 102, 92, 110, 92, 114, 92, 116, 122]>
memref.global "private" constant @points : memref<30xi8> = dense<[92, 117, 48, 48, 52, 49, 92, 117, 48, 48, 101, 57, 92, 117, 50, 48, 49, 57, 92, 117, 100, 56, 51, 100, 92, 117, 100, 101, 48, 48]>
memref.global "private" constant @lone : memref<19xi8> = dense<[92, 117, 100, 56, 48, 48, 120, 92, 117, 100, 99, 48, 48, 92, 120, 92, 117, 49, 50]>
memref.global "private" constant @end : memref<3xi8> = dense<[97, 98, 92]>
memref.global "private" constant @badhex : memref<6xi8> = dense<[92, 117, 48, 48, 71, 49]>
memref.global "private" constant @highthen : memref<12xi8> = dense<[92, 117, 100, 56, 51, 100, 92, 117, 48, 48, 52, 49]>
memref.global "private" constant @plain : memref<5xi8> = dense<[112, 108, 97, 105, 110]>
memref.global "private" constant @law : memref<61xi8> = dense<[104, 92, 117, 48, 48, 101, 57, 108, 108, 111, 32, 92, 34, 119, 92, 117, 48, 48, 102, 54, 114, 108, 100, 92, 34, 32, 92, 92, 32, 47, 32, 92, 110, 92, 116, 92, 117, 50, 48, 49, 57, 32, 92, 117, 100, 56, 51, 100, 92, 117, 100, 101, 48, 48, 32, 92, 117, 48, 48, 48, 49]>
func.func private @printMemrefI32(memref<*xi32>) attributes {llvm.emit_c_interface}

func.func private @show(%xs: !s32) {
  %n = trikeshed.size %xs : !s32
  %out = memref.alloc(%n) : memref<?xi32>
  %end = trikeshed.drain %xs, %out : !s32, memref<?xi32> -> index
  %u = memref.cast %out : memref<?xi32> to memref<*xi32>
  func.call @printMemrefI32(%u) : (memref<*xi32>) -> ()
  return
}

func.func private @show_bytes(%t: !text) {
  %xs = trikeshed.alpha %t : !text -> !s32 {
  ^bb0(%b: i8):
    %x = arith.extui %b : i8 to i32
    trikeshed.yield %x : i32
  }
  func.call @show(%xs) : (!s32) -> ()
  return
}

func.func private @show_coordinates(%ps: !sp) {
  %starts = trikeshed.alpha %ps : !sp -> !s32 {
  ^bb0(%p: !tp):
    %f = trikeshed.first %p : !tp -> i32
    trikeshed.yield %f : i32
  }
  %lengths = trikeshed.alpha %ps : !sp -> !s32 {
  ^bb0(%q: !tp):
    %c = trikeshed.second %q : !tp -> i32
    trikeshed.yield %c : i32
  }
  func.call @show(%starts) : (!s32) -> ()
  func.call @show(%lengths) : (!s32) -> ()
  return
}

// the parts of t at '/', with dot between each two
func.func private @show_joined(%t: !text, %dot: !text) {
  %slash = arith.constant 47 : i8
  %one = arith.constant 1 : index
  %two = arith.constant 2 : index
  %ps = trikeshed.parts %t, %slash : !text, i8 -> !sp
  %np = trikeshed.size %ps : !sp
  %twice = arith.muli %np, %two : index
  %m = arith.subi %twice, %one : index
  %joined, %at = trikeshed.combineAll %m : !text, !sp {
  ^bb0(%k: index):
    %half = arith.divui %k, %two : index
    %rem = arith.remui %k, %two : index
    %isDot = arith.cmpi eq, %rem, %one : index
    %piece = scf.if %isDot -> (!text) {
      scf.yield %dot : !text
    } else {
      %pc = trikeshed.at %ps[%half] : !sp, index -> !tp
      %s = trikeshed.first %pc : !tp -> i32
      %l = trikeshed.second %pc : !tp -> i32
      %si = arith.index_cast %s : i32 to index
      %li = arith.index_cast %l : i32 to index
      %seg = trikeshed.slice %t[%si, %li] : !text -> !text
      scf.yield %seg : !text
    }
    trikeshed.yield %piece : !text
  }
  func.call @show_bytes(%joined) : (!text) -> ()
  func.call @show_coordinates(%at) : (!sp) -> ()
  return
}

func.func @main() -> i32 {
  %g = memref.get_global @path : memref<7xi8>
  %t = trikeshed.text %g : memref<7xi8> -> !text
  %gd = memref.get_global @dot : memref<1xi8>
  %dot = trikeshed.text %gd : memref<1xi8> -> !text
  %slash = arith.constant 47 : i8
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c2 = arith.constant 2 : index
  %c3 = arith.constant 3 : index
  %c6 = arith.constant 6 : index
  %bc = trikeshed.slice %t[%c2, %c2] : !text -> !text
  %d = trikeshed.slice %t[%c6, %c1] : !text -> !text
  %bcd = trikeshed.combine %bc, %dot, %d : !text, !text, !text -> !text
  func.call @show_bytes(%bcd) : (!text) -> ()
  func.call @show_joined(%t, %dot) : (!text, !text) -> ()
  %rows, %rowAt = trikeshed.combineAll %c2 : !text, !sp {
  ^bb0(%r: index):
    %isFirst = arith.cmpi eq, %r, %c0 : index
    %src = scf.if %isFirst -> (!text) {
      scf.yield %t : !text
    } else {
      %bcs = trikeshed.slice %t[%c2, %c3] : !text -> !text
      scf.yield %bcs : !text
    }
    %pp = trikeshed.parts %src, %slash : !text, i8 -> !sp
    %npp = trikeshed.size %pp : !sp
    %twice2 = arith.muli %npp, %c2 : index
    %mm = arith.subi %twice2, %c1 : index
    %row, %rowParts = trikeshed.combineAll %mm : !text, !sp {
    ^bb0(%j: index):
      %h = arith.divui %j, %c2 : index
      %rm = arith.remui %j, %c2 : index
      %isDot2 = arith.cmpi eq, %rm, %c1 : index
      %piece2 = scf.if %isDot2 -> (!text) {
        scf.yield %dot : !text
      } else {
        %pc2 = trikeshed.at %pp[%h] : !sp, index -> !tp
        %s2 = trikeshed.first %pc2 : !tp -> i32
        %l2 = trikeshed.second %pc2 : !tp -> i32
        %si2 = arith.index_cast %s2 : i32 to index
        %li2 = arith.index_cast %l2 : i32 to index
        %seg2 = trikeshed.slice %src[%si2, %li2] : !text -> !text
        scf.yield %seg2 : !text
      }
      trikeshed.yield %piece2 : !text
    }
    trikeshed.yield %row : !text
  }
  func.call @show_bytes(%rows) : (!text) -> ()
  func.call @show_coordinates(%rowAt) : (!sp) -> ()
  %none, %noneAt = trikeshed.combineAll %c0 : !text, !sp {
  ^bb0(%z: index):
    trikeshed.yield %dot : !text
  }
  func.call @show_bytes(%none) : (!text) -> ()
  func.call @show_coordinates(%noneAt) : (!sp) -> ()
  %g_simple = memref.get_global @simple : memref<21xi8>
  %t_simple = trikeshed.text %g_simple : memref<21xi8> -> !text
  %v_simple = confix.unescape json %t_simple : !text -> !text
  func.call @show_bytes(%v_simple) : (!text) -> ()
  %g_points = memref.get_global @points : memref<30xi8>
  %t_points = trikeshed.text %g_points : memref<30xi8> -> !text
  %v_points = confix.unescape json %t_points : !text -> !text
  func.call @show_bytes(%v_points) : (!text) -> ()
  %g_lone = memref.get_global @lone : memref<19xi8>
  %t_lone = trikeshed.text %g_lone : memref<19xi8> -> !text
  %v_lone = confix.unescape json %t_lone : !text -> !text
  func.call @show_bytes(%v_lone) : (!text) -> ()
  %g_end = memref.get_global @end : memref<3xi8>
  %t_end = trikeshed.text %g_end : memref<3xi8> -> !text
  %v_end = confix.unescape json %t_end : !text -> !text
  func.call @show_bytes(%v_end) : (!text) -> ()
  %g_badhex = memref.get_global @badhex : memref<6xi8>
  %t_badhex = trikeshed.text %g_badhex : memref<6xi8> -> !text
  %v_badhex = confix.unescape json %t_badhex : !text -> !text
  func.call @show_bytes(%v_badhex) : (!text) -> ()
  %g_highthen = memref.get_global @highthen : memref<12xi8>
  %t_highthen = trikeshed.text %g_highthen : memref<12xi8> -> !text
  %v_highthen = confix.unescape json %t_highthen : !text -> !text
  func.call @show_bytes(%v_highthen) : (!text) -> ()
  %g_plain = memref.get_global @plain : memref<5xi8>
  %t_plain = trikeshed.text %g_plain : memref<5xi8> -> !text
  %v_plain = confix.unescape json %t_plain : !text -> !text
  func.call @show_bytes(%v_plain) : (!text) -> ()
  %g_law = memref.get_global @law : memref<61xi8>
  %t_law = trikeshed.text %g_law : memref<61xi8> -> !text
  %v_law = confix.unescape json %t_law : !text -> !text
  func.call @show_bytes(%v_law) : (!text) -> ()
  %zero = arith.constant 0 : i32
  return %zero : i32
}
