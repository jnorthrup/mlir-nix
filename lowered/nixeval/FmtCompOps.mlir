// The composition residue of lib/Eval/Formats.cpp's fromTOML: an open TOML array's elements drained into the list's
// cells.  Lowered by lib/CMakeLists.txt's mlnix_lower_trikeshed into NixEval.
//
// nixev_ts_toml_cells(elems, n, into): n Value* cells (pointer bits, i64) drained once into the list's elems.
!text = !trikeshed.series<i8>
!s64 = !trikeshed.series<i64>
!m8 = memref<?xi8, strided<[1], offset: ?>>
!m64 = memref<?xi64, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

func.func private @fc_desc64(%p: !llvm.ptr, %n: i64) -> !d {
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

// an open TOML array's elements: the window of Value* bits drained once into the list's cells
func.func @nixev_ts_toml_cells(%elems: !llvm.ptr, %n: i64, %into: !llvm.ptr) {
  %sd = func.call @fc_desc64(%elems, %n) : (!llvm.ptr, i64) -> !d
  %sm = builtin.unrealized_conversion_cast %sd : !d to !m64
  %ss = builtin.unrealized_conversion_cast %sm : !m64 to !s64
  %id = func.call @fc_desc64(%into, %n) : (!llvm.ptr, i64) -> !d
  %im = builtin.unrealized_conversion_cast %id : !d to !m64
  %end = trikeshed.drain %ss, %im : !s64, !m64 -> index
  return
}
