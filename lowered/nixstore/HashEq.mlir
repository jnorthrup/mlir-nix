// nixstore::Hash::operator==(Hash const&) const, lowered from C++ (lib/Store/Hash.cpp) into MLIR.
// The ABI is the one scripts/cxx-interfaces.py extracted (docs/interfaces/NixStore.mlir): two pointers to a
// 68-byte Hash (i32 algo at 0, uint8_t bytes[64] at 4), returning i1.  algo == o.algo && memcmp(bytes, o.bytes,
// hashSize(algo)) == 0.  hashSize: MD5(0)=16, SHA1(1)=20, SHA256(2)=32, SHA512(3)=64.  bcmp reads only, as the
// C++ memcmp does; both buffers are 64 bytes, so the call is safe even when the algos differ (the result is
// then false via the algo comparison).  Built into NixStore by lib/CMakeLists.txt under -DMLNIX_LOWERED=ON,
// which compiles Hash.cpp with MLNIX_LOWERED_HASH_EQ so the C++ definition is omitted.
module {
  llvm.func @bcmp(!llvm.ptr, !llvm.ptr, i64) -> i32
  llvm.func @_ZNK8nixstore4HasheqERKS0_(%a: !llvm.ptr, %b: !llvm.ptr) -> i1 {
    %algo_a = llvm.load %a : !llvm.ptr -> i32
    %algo_b = llvm.load %b : !llvm.ptr -> i32
    %eq_algo = llvm.icmp "eq" %algo_a, %algo_b : i32
    %c0 = llvm.mlir.constant(0 : i32) : i32
    %c1 = llvm.mlir.constant(1 : i32) : i32
    %c2 = llvm.mlir.constant(2 : i32) : i32
    %s16 = llvm.mlir.constant(16 : i64) : i64
    %s20 = llvm.mlir.constant(20 : i64) : i64
    %s32 = llvm.mlir.constant(32 : i64) : i64
    %s64 = llvm.mlir.constant(64 : i64) : i64
    %is0 = llvm.icmp "eq" %algo_a, %c0 : i32
    %is1 = llvm.icmp "eq" %algo_a, %c1 : i32
    %is2 = llvm.icmp "eq" %algo_a, %c2 : i32
    %t1 = llvm.select %is2, %s32, %s64 : i1, i64
    %t2 = llvm.select %is1, %s20, %t1 : i1, i64
    %size = llvm.select %is0, %s16, %t2 : i1, i64
    %bytes_a = llvm.getelementptr %a[4] : (!llvm.ptr) -> !llvm.ptr, i8
    %bytes_b = llvm.getelementptr %b[4] : (!llvm.ptr) -> !llvm.ptr, i8
    %cmp = llvm.call @bcmp(%bytes_a, %bytes_b, %size) : (!llvm.ptr, !llvm.ptr, i64) -> i32
    %cz = llvm.mlir.constant(0 : i32) : i32
    %eq_bytes = llvm.icmp "eq" %cmp, %cz : i32
    %res = llvm.and %eq_algo, %eq_bytes : i1
    llvm.return %res : i1
  }
}
