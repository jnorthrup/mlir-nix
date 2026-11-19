// nixstore::isInStore(string_view storeDir, string_view path), lowered from C++ (lib/Store/StorePaths.cpp) into MLIR.
// path.size() > storeDir.size() + 1 && path.substr(0, storeDir.size()) == storeDir && path[storeDir.size()] == '/'.
// The length guard is branched on first (llvm.cond_br), as the C++ && short-circuits: only when it holds are the prefix
// bytes and path[storeDir.size()] read, so every read is in bounds.  bcmp reads only, as the C++ substr comparison does.
//
// std::string_view mangles differently per standard library, so the body is a neutral symbol and two wrappers carry the
// platform mangled names (scripts/cxx-interfaces.py gives the Linux one; the Mac libc++ one is beside it).  Each platform
// links its own and ignores the other.  A string_view is [2 x i64] = {data ptr as i64, size}.
module {
  llvm.func @bcmp(!llvm.ptr, !llvm.ptr, i64) -> i32
  llvm.func @mlnix_isInStore(%sd: !llvm.ptr, %ss: i64, %pd: !llvm.ptr, %ps: i64) -> i1 {
    %one = llvm.mlir.constant(1 : i64) : i64
    %ss1 = llvm.add %ss, %one : i64
    %cond1 = llvm.icmp "ugt" %ps, %ss1 : i64
    %false = llvm.mlir.constant(0 : i1) : i1
    llvm.cond_br %cond1, ^bb1, ^bb2
  ^bb1:
    %cmp = llvm.call @bcmp(%pd, %sd, %ss) : (!llvm.ptr, !llvm.ptr, i64) -> i32
    %cz = llvm.mlir.constant(0 : i32) : i32
    %cond2 = llvm.icmp "eq" %cmp, %cz : i32
    %chp = llvm.getelementptr %pd[%ss] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %ch = llvm.load %chp : !llvm.ptr -> i8
    %slash = llvm.mlir.constant(47 : i8) : i8
    %cond3 = llvm.icmp "eq" %ch, %slash : i8
    %r = llvm.and %cond2, %cond3 : i1
    llvm.br ^bb3(%r : i1)
  ^bb2:
    llvm.br ^bb3(%false : i1)
  ^bb3(%res: i1):
    llvm.return %res : i1
  }
  // Linux (libstdc++): _ZN8nixstore9isInStoreESt17basic_string_viewIcSt11char_traitsIcEES3_
  // Linux coerces string_view to [2 x i64] = {size, data ptr} (index 0 = size, 1 = pointer) — the opposite of Mac.
  llvm.func @_ZN8nixstore9isInStoreESt17basic_string_viewIcSt11char_traitsIcEES3_(%storeDir: !llvm.array<2 x i64>, %path: !llvm.array<2 x i64>) -> i1 {
    %ss = llvm.extractvalue %storeDir[0] : !llvm.array<2 x i64>
    %sd_i = llvm.extractvalue %storeDir[1] : !llvm.array<2 x i64>
    %sd = llvm.inttoptr %sd_i : i64 to !llvm.ptr
    %ps = llvm.extractvalue %path[0] : !llvm.array<2 x i64>
    %pd_i = llvm.extractvalue %path[1] : !llvm.array<2 x i64>
    %pd = llvm.inttoptr %pd_i : i64 to !llvm.ptr
    %r = llvm.call @mlnix_isInStore(%sd, %ss, %pd, %ps) : (!llvm.ptr, i64, !llvm.ptr, i64) -> i1
    llvm.return %r : i1
  }
  // Mac (libc++): the object symbol is __ZN...NSt3__1... (Mac's assembler adds the leading underscore to _ZN...)
  llvm.func @_ZN8nixstore9isInStoreENSt3__117basic_string_viewIcNS0_11char_traitsIcEEEES4_(%storeDir: !llvm.array<2 x i64>, %path: !llvm.array<2 x i64>) -> i1 {
    %sd_i = llvm.extractvalue %storeDir[0] : !llvm.array<2 x i64>
    %sd = llvm.inttoptr %sd_i : i64 to !llvm.ptr
    %ss = llvm.extractvalue %storeDir[1] : !llvm.array<2 x i64>
    %pd_i = llvm.extractvalue %path[0] : !llvm.array<2 x i64>
    %pd = llvm.inttoptr %pd_i : i64 to !llvm.ptr
    %ps = llvm.extractvalue %path[1] : !llvm.array<2 x i64>
    %r = llvm.call @mlnix_isInStore(%sd, %ss, %pd, %ps) : (!llvm.ptr, i64, !llvm.ptr, i64) -> i1
    llvm.return %r : i1
  }
}
