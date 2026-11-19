// The type predicates (__isInt/__isFloat/__isBool/__isString/__isPath/__isAttrs/__isList/__isFunction/isNull) and
// EvalState::typeOf, hollowed from lib/Eval/Builtins.cpp's typePred template and lib/Eval/Eval.cpp into MLIR
// (the ShowType.mlir recipe: a type-tag switch over Value's u8 type@0, neutral C-ABI, linked by mlnix_lower_interface).
// Value: VType type (u8) at 0, aux (u32) at 4, union at 8 (boolean is the first byte of the union).
// VType: Thunk0 App1 AttrApp2 Failed3 Blackhole4 Int5 Float6 Bool7 Null8 String9 Path10 Attrs11 List12 Lambda13
// PrimOp14 PrimOpApp15.
//
// @mlnix_type_pred(v, tag, out): forces nothing (the bridge forced v); writes the Bool result into out (type 7 at 0,
// the boolean byte at 8, aux untouched, as mkBool does).  tag is the VType to test; tag 16 is the function group
// (Lambda 13, PrimOp 14, PrimOpApp 15 — Value::isFunction).
//
// EvalState::typeOf is defined here under its exact mangled name (the declaration stays in include/Nix/Eval.h):
// the typeOf wording (int/bool/string/path/null/set/list/lambda/float, thunk for everything else), not showType's.
module {
  llvm.func @mlnix_type_pred(%v: !llvm.ptr, %tag: i32, %out: !llvm.ptr) {
    %t = llvm.load %v : !llvm.ptr -> i8
    %ti = llvm.zext %t : i8 to i32
    %c13 = llvm.mlir.constant(13 : i32) : i32
    %c15 = llvm.mlir.constant(15 : i32) : i32
    %c16 = llvm.mlir.constant(16 : i32) : i32
    %ge13 = llvm.icmp "uge" %ti, %c13 : i32
    %le15 = llvm.icmp "ule" %ti, %c15 : i32
    %isfun = llvm.and %ge13, %le15 : i1
    %funtag = llvm.icmp "eq" %tag, %c16 : i32
    %eq = llvm.icmp "eq" %ti, %tag : i32
    %r = llvm.select %funtag, %isfun, %eq : i1, i1
    %seven = llvm.mlir.constant(7 : i8) : i8
    %tp = llvm.getelementptr %out[0] : (!llvm.ptr) -> !llvm.ptr, i8
    llvm.store %seven, %tp : i8, !llvm.ptr
    %rb = llvm.zext %r : i1 to i8
    %bp = llvm.getelementptr %out[8] : (!llvm.ptr) -> !llvm.ptr, i8
    llvm.store %rb, %bp : i8, !llvm.ptr
    llvm.return
  }
  llvm.mlir.global internal constant @t_int("int\00") : !llvm.array<4 x i8>
  llvm.mlir.global internal constant @t_bool("bool\00") : !llvm.array<5 x i8>
  llvm.mlir.global internal constant @t_string("string\00") : !llvm.array<7 x i8>
  llvm.mlir.global internal constant @t_path("path\00") : !llvm.array<5 x i8>
  llvm.mlir.global internal constant @t_null("null\00") : !llvm.array<5 x i8>
  llvm.mlir.global internal constant @t_set("set\00") : !llvm.array<4 x i8>
  llvm.mlir.global internal constant @t_list("list\00") : !llvm.array<5 x i8>
  llvm.mlir.global internal constant @t_lambda("lambda\00") : !llvm.array<7 x i8>
  llvm.mlir.global internal constant @t_float("float\00") : !llvm.array<6 x i8>
  llvm.mlir.global internal constant @t_thunk("thunk\00") : !llvm.array<6 x i8>
  llvm.func @_ZN5nixev9EvalState6typeOfERKNS_5ValueE(%v: !llvm.ptr) -> !llvm.ptr {
    %p_int = llvm.mlir.addressof @t_int : !llvm.ptr
    %p_bool = llvm.mlir.addressof @t_bool : !llvm.ptr
    %p_string = llvm.mlir.addressof @t_string : !llvm.ptr
    %p_path = llvm.mlir.addressof @t_path : !llvm.ptr
    %p_null = llvm.mlir.addressof @t_null : !llvm.ptr
    %p_set = llvm.mlir.addressof @t_set : !llvm.ptr
    %p_list = llvm.mlir.addressof @t_list : !llvm.ptr
    %p_lambda = llvm.mlir.addressof @t_lambda : !llvm.ptr
    %p_float = llvm.mlir.addressof @t_float : !llvm.ptr
    %p_thunk = llvm.mlir.addressof @t_thunk : !llvm.ptr
    %t = llvm.load %v : !llvm.ptr -> i8
    %ti = llvm.zext %t : i8 to i32
    %c5 = llvm.mlir.constant(5 : i32) : i32
    %c6 = llvm.mlir.constant(6 : i32) : i32
    %c7 = llvm.mlir.constant(7 : i32) : i32
    %c8 = llvm.mlir.constant(8 : i32) : i32
    %c9 = llvm.mlir.constant(9 : i32) : i32
    %c10 = llvm.mlir.constant(10 : i32) : i32
    %c11 = llvm.mlir.constant(11 : i32) : i32
    %c12 = llvm.mlir.constant(12 : i32) : i32
    %c13 = llvm.mlir.constant(13 : i32) : i32
    %c15 = llvm.mlir.constant(15 : i32) : i32
    %is_int = llvm.icmp "eq" %ti, %c5 : i32
    %is_float = llvm.icmp "eq" %ti, %c6 : i32
    %is_bool = llvm.icmp "eq" %ti, %c7 : i32
    %is_null = llvm.icmp "eq" %ti, %c8 : i32
    %is_string = llvm.icmp "eq" %ti, %c9 : i32
    %is_path = llvm.icmp "eq" %ti, %c10 : i32
    %is_attrs = llvm.icmp "eq" %ti, %c11 : i32
    %is_list = llvm.icmp "eq" %ti, %c12 : i32
    %ge13 = llvm.icmp "uge" %ti, %c13 : i32
    %le15 = llvm.icmp "ule" %ti, %c15 : i32
    %is_lambda = llvm.and %ge13, %le15 : i1
    %r0 = llvm.select %is_float, %p_float, %p_thunk : i1, !llvm.ptr
    %r1 = llvm.select %is_lambda, %p_lambda, %r0 : i1, !llvm.ptr
    %r2 = llvm.select %is_list, %p_list, %r1 : i1, !llvm.ptr
    %r3 = llvm.select %is_attrs, %p_set, %r2 : i1, !llvm.ptr
    %r4 = llvm.select %is_null, %p_null, %r3 : i1, !llvm.ptr
    %r5 = llvm.select %is_path, %p_path, %r4 : i1, !llvm.ptr
    %r6 = llvm.select %is_string, %p_string, %r5 : i1, !llvm.ptr
    %r7 = llvm.select %is_bool, %p_bool, %r6 : i1, !llvm.ptr
    %r8 = llvm.select %is_int, %p_int, %r7 : i1, !llvm.ptr
    llvm.return %r8 : !llvm.ptr
  }
}
