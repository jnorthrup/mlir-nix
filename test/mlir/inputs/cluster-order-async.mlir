// Two independent owned clusters feed a dependent coroutine. Standard async
// lowering owns suspension and completion. The native kernel owns only scratch.
module {
  memref.global "private" constant @keys8 : memref<8xi64> = dense<[3, -2, 3, 0, -2, 7, 1, 7]>
  memref.global "private" constant @order8 : memref<8xi64> = dense<[1, 4, 3, 6, 0, 2, 5, 7]>
  memref.global "private" constant @keys23 : memref<23xi64> = dense<[7, 3, 9, 1, 8, 12, 5, 14, 0, 11, 6, 13, 2, 10, 4, 20, 16, 18, 15, 19, 17, 22, 21]>
  memref.global "private" constant @order23 : memref<23xi64> = dense<[8, 3, 12, 1, 14, 6, 10, 0, 4, 2, 13, 9, 5, 11, 7, 18, 16, 20, 17, 19, 15, 22, 21]>
  memref.global "private" @alias : memref<8xi64> = dense<[3, -2, 3, 0, -2, 7, 1, 7]>
  memref.global "private" constant @large : memref<24xi64> = dense<0>
  memref.global "private" @rejected : memref<24xi64> = dense<99>
  memref.global "private" @short : memref<4xi64> = dense<99>

  func.func private @check(%actual: memref<?xi64>, %expected: memref<?xi64>) {
    %zero = arith.constant 0 : index
    %one = arith.constant 1 : index
    %n = memref.dim %actual, %zero : memref<?xi64>
    scf.for %i = %zero to %n step %one {
      %a = memref.load %actual[%i] : memref<?xi64>
      %e = memref.load %expected[%i] : memref<?xi64>
      %equal = arith.cmpi eq, %a, %e : i64
      cf.assert %equal, "wrong cluster permutation"
    }
    return
  }

  func.func @main() -> i32 {
    %t8, %v8 = async.execute -> !async.value<memref<8xi64>> {
      %keys = memref.get_global @keys8 : memref<8xi64>
      %out = memref.alloc() : memref<8xi64>
      %ok = "trikeshed.cluster_order"(%keys, %out) : (memref<8xi64>, memref<8xi64>) -> i1
      cf.assert %ok, "cluster refused eight rows"
      async.yield %out : memref<8xi64>
    }
    %t23, %v23 = async.execute -> !async.value<memref<23xi64>> {
      %keys = memref.get_global @keys23 : memref<23xi64>
      %out = memref.alloc() : memref<23xi64>
      %ok = "trikeshed.cluster_order"(%keys, %out) : (memref<23xi64>, memref<23xi64>) -> i1
      cf.assert %ok, "cluster refused a full run"
      async.yield %out : memref<23xi64>
    }
    %done = async.execute (%v8 as %a8: !async.value<memref<8xi64>>, %v23 as %a23: !async.value<memref<23xi64>>) {
      %ref8 = memref.get_global @order8 : memref<8xi64>
      %ref23 = memref.get_global @order23 : memref<23xi64>
      %a = memref.cast %a8 : memref<8xi64> to memref<?xi64>
      %b = memref.cast %a23 : memref<23xi64> to memref<?xi64>
      %ra = memref.cast %ref8 : memref<8xi64> to memref<?xi64>
      %rb = memref.cast %ref23 : memref<23xi64> to memref<?xi64>
      func.call @check(%a, %ra) : (memref<?xi64>, memref<?xi64>) -> ()
      func.call @check(%b, %rb) : (memref<?xi64>, memref<?xi64>) -> ()
      memref.dealloc %a8 : memref<8xi64>
      memref.dealloc %a23 : memref<23xi64>
      async.yield
    }
    async.await %done : !async.token

    %zero = arith.constant 0 : index
    %one = arith.constant 1 : index
    %true = arith.constant true
    %sentinel = arith.constant 99 : i64
    %empty = memref.alloc() : memref<0xi64>
    %empty_ok = "trikeshed.cluster_order"(%empty, %empty) : (memref<0xi64>, memref<0xi64>) -> i1
    cf.assert %empty_ok, "empty run failed"
    memref.dealloc %empty : memref<0xi64>

    %alias = memref.get_global @alias : memref<8xi64>
    %alias_ok = "trikeshed.cluster_order"(%alias, %alias) : (memref<8xi64>, memref<8xi64>) -> i1
    cf.assert %alias_ok, "alias run failed"
    %ref = memref.get_global @order8 : memref<8xi64>
    %alias_d = memref.cast %alias : memref<8xi64> to memref<?xi64>
    %ref_d = memref.cast %ref : memref<8xi64> to memref<?xi64>
    func.call @check(%alias_d, %ref_d) : (memref<?xi64>, memref<?xi64>) -> ()

    %large = memref.get_global @large : memref<24xi64>
    %rejected = memref.get_global @rejected : memref<24xi64>
    %large_ok = "trikeshed.cluster_order"(%large, %rejected) : (memref<24xi64>, memref<24xi64>) -> i1
    %large_no = arith.xori %large_ok, %true : i1
    cf.assert %large_no, "over-capacity run accepted"
    %n = arith.constant 24 : index
    scf.for %i = %zero to %n step %one {
      %v = memref.load %rejected[%i] : memref<24xi64>
      %same = arith.cmpi eq, %v, %sentinel : i64
      cf.assert %same, "rejection wrote output"
    }
    %short = memref.get_global @short : memref<4xi64>
    %mismatch = "trikeshed.cluster_order"(%ref, %short) : (memref<8xi64>, memref<4xi64>) -> i1
    %mismatch_no = arith.xori %mismatch, %true : i1
    cf.assert %mismatch_no, "unequal lengths accepted"
    %stride = memref.subview %ref[0] [4] [2] : memref<8xi64> to memref<4xi64, strided<[2]>>
    %stride_ok = "trikeshed.cluster_order"(%stride, %short) : (memref<4xi64, strided<[2]>>, memref<4xi64>) -> i1
    %stride_no = arith.xori %stride_ok, %true : i1
    cf.assert %stride_no, "non-unit stride accepted"
    %four = arith.constant 4 : index
    scf.for %i = %zero to %four step %one {
      %v = memref.load %short[%i] : memref<4xi64>
      %same = arith.cmpi eq, %v, %sentinel : i64
      cf.assert %same, "invalid descriptor wrote output"
    }
    %result = arith.constant 0 : i32
    return %result : i32
  }
}
