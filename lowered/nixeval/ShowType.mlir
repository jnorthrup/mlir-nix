// nixev::EvalState::showType(Value const&) (static), lowered from C++ (lib/Eval/Eval.cpp) into MLIR.
// ABI from scripts/cxx-interfaces.py (docs/interfaces/NixEval.mlir): one ptr to a 24-byte Value, returns a nonnull
// ptr to a static string.  Value: VType type (u8) at 0, aux (u32) at 4, union at 8 (str.ctx ptr at 16).
// VType: Thunk0 App1 AttrApp2 Failed3 Blackhole4 Int5 Float6 Bool7 Null8 String9 Path10 Attrs11 List12 Lambda13
// PrimOp14 PrimOpApp15.  A type-tag switch returning a constant string; String reads str.ctx to choose its wording.
module {
  llvm.mlir.global internal constant @s_int("an integer\00") : !llvm.array<11 x i8>
  llvm.mlir.global internal constant @s_bool("a Boolean\00") : !llvm.array<10 x i8>
  llvm.mlir.global internal constant @s_strctx("a string with context\00") : !llvm.array<22 x i8>
  llvm.mlir.global internal constant @s_str("a string\00") : !llvm.array<9 x i8>
  llvm.mlir.global internal constant @s_path("a path\00") : !llvm.array<7 x i8>
  llvm.mlir.global internal constant @s_null("null\00") : !llvm.array<5 x i8>
  llvm.mlir.global internal constant @s_attrs("a set\00") : !llvm.array<6 x i8>
  llvm.mlir.global internal constant @s_list("a list\00") : !llvm.array<7 x i8>
  llvm.mlir.global internal constant @s_lambda("a function\00") : !llvm.array<11 x i8>
  llvm.mlir.global internal constant @s_primop("a built-in function\00") : !llvm.array<20 x i8>
  llvm.mlir.global internal constant @s_primopapp("a partially applied built-in function\00") : !llvm.array<38 x i8>
  llvm.mlir.global internal constant @s_float("a float\00") : !llvm.array<8 x i8>
  llvm.mlir.global internal constant @s_thunk("a thunk\00") : !llvm.array<8 x i8>
  llvm.mlir.global internal constant @s_unknown("?\00") : !llvm.array<2 x i8>
  llvm.func @_ZN5nixev9EvalState8showTypeERKNS_5ValueE(%v: !llvm.ptr) -> !llvm.ptr {
    %p_int = llvm.mlir.addressof @s_int : !llvm.ptr
    %p_bool = llvm.mlir.addressof @s_bool : !llvm.ptr
    %p_strctx = llvm.mlir.addressof @s_strctx : !llvm.ptr
    %p_str = llvm.mlir.addressof @s_str : !llvm.ptr
    %p_path = llvm.mlir.addressof @s_path : !llvm.ptr
    %p_null = llvm.mlir.addressof @s_null : !llvm.ptr
    %p_attrs = llvm.mlir.addressof @s_attrs : !llvm.ptr
    %p_list = llvm.mlir.addressof @s_list : !llvm.ptr
    %p_lambda = llvm.mlir.addressof @s_lambda : !llvm.ptr
    %p_primop = llvm.mlir.addressof @s_primop : !llvm.ptr
    %p_primopapp = llvm.mlir.addressof @s_primopapp : !llvm.ptr
    %p_float = llvm.mlir.addressof @s_float : !llvm.ptr
    %p_thunk = llvm.mlir.addressof @s_thunk : !llvm.ptr
    %p_unknown = llvm.mlir.addressof @s_unknown : !llvm.ptr
    %t = llvm.load %v : !llvm.ptr -> i8
    %ti = llvm.zext %t : i8 to i32
    %c4 = llvm.mlir.constant(4 : i32) : i32
    %c5 = llvm.mlir.constant(5 : i32) : i32
    %c6 = llvm.mlir.constant(6 : i32) : i32
    %c7 = llvm.mlir.constant(7 : i32) : i32
    %c8 = llvm.mlir.constant(8 : i32) : i32
    %c9 = llvm.mlir.constant(9 : i32) : i32
    %c10 = llvm.mlir.constant(10 : i32) : i32
    %c11 = llvm.mlir.constant(11 : i32) : i32
    %c12 = llvm.mlir.constant(12 : i32) : i32
    %c13 = llvm.mlir.constant(13 : i32) : i32
    %c14 = llvm.mlir.constant(14 : i32) : i32
    %c15 = llvm.mlir.constant(15 : i32) : i32
    %is_thunk = llvm.icmp "ule" %ti, %c4 : i32
    %is_int = llvm.icmp "eq" %ti, %c5 : i32
    %is_float = llvm.icmp "eq" %ti, %c6 : i32
    %is_bool = llvm.icmp "eq" %ti, %c7 : i32
    %is_null = llvm.icmp "eq" %ti, %c8 : i32
    %is_string = llvm.icmp "eq" %ti, %c9 : i32
    %is_path = llvm.icmp "eq" %ti, %c10 : i32
    %is_attrs = llvm.icmp "eq" %ti, %c11 : i32
    %is_list = llvm.icmp "eq" %ti, %c12 : i32
    %is_lambda = llvm.icmp "eq" %ti, %c13 : i32
    %is_primop = llvm.icmp "eq" %ti, %c14 : i32
    %is_primopapp = llvm.icmp "eq" %ti, %c15 : i32
    %ctxp = llvm.getelementptr %v[16] : (!llvm.ptr) -> !llvm.ptr, i8
    %ctx = llvm.load %ctxp : !llvm.ptr -> !llvm.ptr
    %ctxi = llvm.ptrtoint %ctx : !llvm.ptr to i64
    %cz64 = llvm.mlir.constant(0 : i64) : i64
    %hasctx = llvm.icmp "ne" %ctxi, %cz64 : i64
    %p_string = llvm.select %hasctx, %p_strctx, %p_str : i1, !llvm.ptr
    %r0 = llvm.select %is_float, %p_float, %p_unknown : i1, !llvm.ptr
    %r1 = llvm.select %is_primopapp, %p_primopapp, %r0 : i1, !llvm.ptr
    %r2 = llvm.select %is_primop, %p_primop, %r1 : i1, !llvm.ptr
    %r3 = llvm.select %is_lambda, %p_lambda, %r2 : i1, !llvm.ptr
    %r4 = llvm.select %is_list, %p_list, %r3 : i1, !llvm.ptr
    %r5 = llvm.select %is_attrs, %p_attrs, %r4 : i1, !llvm.ptr
    %r6 = llvm.select %is_path, %p_path, %r5 : i1, !llvm.ptr
    %r7 = llvm.select %is_string, %p_string, %r6 : i1, !llvm.ptr
    %r8 = llvm.select %is_null, %p_null, %r7 : i1, !llvm.ptr
    %r9 = llvm.select %is_bool, %p_bool, %r8 : i1, !llvm.ptr
    %r10 = llvm.select %is_int, %p_int, %r9 : i1, !llvm.ptr
    %r11 = llvm.select %is_thunk, %p_thunk, %r10 : i1, !llvm.ptr
    llvm.return %r11 : !llvm.ptr
  }
}
