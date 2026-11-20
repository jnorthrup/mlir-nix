// kursive-run.mlir's driver: the texts, and regex_match of each pattern's Program (@pN_steps, @pN_sets, @pN_counts)
// over its text through mlnix_kursive_walk.
memref.global "private" constant @t1 : memref<4xi8> = dense<[97, 98, 97, 99]>
memref.global "private" constant @t2 : memref<7xi8> = dense<[102, 111, 111, 45, 49, 50, 51]>
memref.global "private" constant @t3 : memref<4xi8> = dense<[120, 120, 120, 120]>
memref.global "private" constant @t4 : memref<4xi8> = dense<[97, 98, 99, 100]>
memref.global "private" constant @t5 : memref<1xi8> = dense<[121]>

func.func private @printMemrefI32(memref<*xi32>) attributes {llvm.emit_c_interface}

func.func private @run_ptr32(%m: memref<?xi32>) -> !llvm.ptr {
  %i = memref.extract_aligned_pointer_as_index %m : memref<?xi32> -> index
  %w = arith.index_cast %i : index to i64
  %p = llvm.inttoptr %w : i64 to !llvm.ptr
  return %p : !llvm.ptr
}
func.func private @run_ptr64(%m: memref<?xi64>) -> !llvm.ptr {
  %i = memref.extract_aligned_pointer_as_index %m : memref<?xi64> -> index
  %w = arith.index_cast %i : index to i64
  %p = llvm.inttoptr %w : i64 to !llvm.ptr
  return %p : !llvm.ptr
}
func.func private @run_ptr8(%m: memref<?xi8>) -> !llvm.ptr {
  %i = memref.extract_aligned_pointer_as_index %m : memref<?xi8> -> index
  %w = arith.index_cast %i : index to i64
  %p = llvm.inttoptr %w : i64 to !llvm.ptr
  return %p : !llvm.ptr
}

// regex_match of a Program (its globals as memrefs) over a text; prints [result, best marks].
func.func private @run(%steps: memref<?xi32>, %sets: memref<?xi64>, %counts: memref<5xi32>, %text: memref<?xi8>) {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c2 = arith.constant 2 : index
  %c3 = arith.constant 3 : index
  %z = arith.constant 0 : i32
  %one = arith.constant 1 : i32
  %groups = memref.load %counts[%c2] : memref<5xi32>
  %loops = memref.load %counts[%c3] : memref<5xi32>
  %g1 = arith.addi %groups, %one : i32
  %slots32 = arith.addi %g1, %g1 : i32
  %slots = arith.index_cast %slots32 : i32 to index
  %loops2 = arith.addi %loops, %loops : i32
  %nl = arith.index_cast %loops2 : i32 to index
  %nl1 = arith.addi %nl, %c1 : index
  %caps = memref.alloca(%slots) : memref<?xi32>
  %best = memref.alloca(%slots) : memref<?xi32>
  %larr = memref.alloca(%nl1) : memref<?xi32>
  %cap = arith.constant 4096 : i32
  %stackN = arith.constant 12288 : index
  %stack = memref.alloca(%stackN) : memref<?xi32>
  %budget = memref.alloca() : memref<1xi64>
  %b0 = arith.constant 17179869184 : i64
  memref.store %b0, %budget[%c0] : memref<1xi64>
  %budgetD = memref.cast %budget : memref<1xi64> to memref<?xi64>
  %n = memref.dim %text, %c0 : memref<?xi8>
  %n32 = arith.index_cast %n : index to i32
  %ps = func.call @run_ptr32(%steps) : (memref<?xi32>) -> !llvm.ptr
  %pt = func.call @run_ptr64(%sets) : (memref<?xi64>) -> !llvm.ptr
  %px = func.call @run_ptr8(%text) : (memref<?xi8>) -> !llvm.ptr
  %pc = func.call @run_ptr32(%caps) : (memref<?xi32>) -> !llvm.ptr
  %pb = func.call @run_ptr32(%best) : (memref<?xi32>) -> !llvm.ptr
  %pl = func.call @run_ptr32(%larr) : (memref<?xi32>) -> !llvm.ptr
  %pk = func.call @run_ptr32(%stack) : (memref<?xi32>) -> !llvm.ptr
  %pg = func.call @run_ptr64(%budgetD) : (memref<?xi64>) -> !llvm.ptr
  %r = func.call @mlnix_kursive_walk(%ps, %pt, %groups, %loops, %px, %n32, %z, %one, %z, %pc, %pb, %pl, %pk, %cap, %pg)
      : (!llvm.ptr, !llvm.ptr, i32, i32, !llvm.ptr, i32, i32, i32, i32, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i32, !llvm.ptr) -> i32
  %outN = arith.addi %slots, %c1 : index
  %out = memref.alloca(%outN) : memref<?xi32>
  memref.store %r, %out[%c0] : memref<?xi32>
  scf.for %i = %c0 to %slots step %c1 {
    %v = memref.load %best[%i] : memref<?xi32>
    %j = arith.addi %i, %c1 : index
    memref.store %v, %out[%j] : memref<?xi32>
  }
  %u = memref.cast %out : memref<?xi32> to memref<*xi32>
  func.call @printMemrefI32(%u) : (memref<*xi32>) -> ()
  return
}

func.func @main() -> i32 {
  %s1 = memref.get_global @p1_steps : memref<48xi32>
  %e1 = memref.get_global @p1_sets : memref<12xi64>
  %k1 = memref.get_global @p1_counts : memref<5xi32>
  %x1 = memref.get_global @t1 : memref<4xi8>
  %s1d = memref.cast %s1 : memref<48xi32> to memref<?xi32>
  %e1d = memref.cast %e1 : memref<12xi64> to memref<?xi64>
  %x1d = memref.cast %x1 : memref<4xi8> to memref<?xi8>
  func.call @run(%s1d, %e1d, %k1, %x1d) : (memref<?xi32>, memref<?xi64>, memref<5xi32>, memref<?xi8>) -> ()
  %s2 = memref.get_global @p2_steps : memref<64xi32>
  %e2 = memref.get_global @p2_sets : memref<12xi64>
  %k2 = memref.get_global @p2_counts : memref<5xi32>
  %x2 = memref.get_global @t2 : memref<7xi8>
  %s2d = memref.cast %s2 : memref<64xi32> to memref<?xi32>
  %e2d = memref.cast %e2 : memref<12xi64> to memref<?xi64>
  %x2d = memref.cast %x2 : memref<7xi8> to memref<?xi8>
  func.call @run(%s2d, %e2d, %k2, %x2d) : (memref<?xi32>, memref<?xi64>, memref<5xi32>, memref<?xi8>) -> ()
  %s3 = memref.get_global @p3_steps : memref<28xi32>
  %e3 = memref.get_global @p3_sets : memref<4xi64>
  %k3 = memref.get_global @p3_counts : memref<5xi32>
  %x3 = memref.get_global @t3 : memref<4xi8>
  %s3d = memref.cast %s3 : memref<28xi32> to memref<?xi32>
  %e3d = memref.cast %e3 : memref<4xi64> to memref<?xi64>
  %x3d = memref.cast %x3 : memref<4xi8> to memref<?xi8>
  func.call @run(%s3d, %e3d, %k3, %x3d) : (memref<?xi32>, memref<?xi64>, memref<5xi32>, memref<?xi8>) -> ()
  %s4 = memref.get_global @p4_steps : memref<92xi32>
  %e4 = memref.get_global @p4_sets : memref<32xi64>
  %k4 = memref.get_global @p4_counts : memref<5xi32>
  %x4 = memref.get_global @t4 : memref<4xi8>
  %s4d = memref.cast %s4 : memref<92xi32> to memref<?xi32>
  %e4d = memref.cast %e4 : memref<32xi64> to memref<?xi64>
  %x4d = memref.cast %x4 : memref<4xi8> to memref<?xi8>
  func.call @run(%s4d, %e4d, %k4, %x4d) : (memref<?xi32>, memref<?xi64>, memref<5xi32>, memref<?xi8>) -> ()
  %s5 = memref.get_global @p5_steps : memref<40xi32>
  %e5 = memref.get_global @p5_sets : memref<8xi64>
  %k5 = memref.get_global @p5_counts : memref<5xi32>
  %x5 = memref.get_global @t5 : memref<1xi8>
  %s5d = memref.cast %s5 : memref<40xi32> to memref<?xi32>
  %e5d = memref.cast %e5 : memref<8xi64> to memref<?xi64>
  %x5d = memref.cast %x5 : memref<1xi8> to memref<?xi8>
  func.call @run(%s5d, %e5d, %k5, %x5d) : (memref<?xi32>, memref<?xi64>, memref<5xi32>, memref<?xi8>) -> ()
  %ok = arith.constant 0 : i32
  return %ok : i32
}
