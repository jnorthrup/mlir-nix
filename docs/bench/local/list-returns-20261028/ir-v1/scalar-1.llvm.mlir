module {
  llvm.func @scalar(%arg0: i32, %arg1: !llvm.ptr) -> i64 {
    llvm.switch %arg0 : i32, ^bb9 [
      0: ^bb8,
      1: ^bb1,
      2: ^bb2,
      3: ^bb3,
      4: ^bb4,
      5: ^bb5,
      6: ^bb6,
      7: ^bb7,
      8: ^bb8
    ]
  ^bb1:  // 2 preds: ^bb0, ^bb12
    %0 = llvm.mlir.constant(0 : i64) : i64
    llvm.return %0 : i64
  ^bb2:  // 2 preds: ^bb0, ^bb11
    %1 = llvm.mlir.constant(1 : i64) : i64
    llvm.return %1 : i64
  ^bb3:  // pred: ^bb0
    %2 = llvm.mlir.constant(3 : i64) : i64
    llvm.return %2 : i64
  ^bb4:  // pred: ^bb0
    %3 = llvm.mlir.constant(712 : i64) : i64
    %4 = llvm.getelementptr %arg1[%3] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %5 = llvm.load %4 : !llvm.ptr -> i32
    %6 = llvm.mlir.constant(716 : i64) : i64
    %7 = llvm.getelementptr %arg1[%6] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %8 = llvm.load %7 : !llvm.ptr -> i32
    %9 = llvm.mlir.constant(1 : i32) : i32
    %10 = llvm.icmp "eq" %5, %9 : i32
    %11 = llvm.mlir.constant(1 : i32) : i32
    %12 = llvm.icmp "eq" %8, %11 : i32
    %13 = llvm.and %10, %12 : i1
    llvm.cond_br %13, ^bb11, ^bb9
  ^bb5:  // pred: ^bb0
    %14 = llvm.mlir.constant(712 : i64) : i64
    %15 = llvm.getelementptr %arg1[%14] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %16 = llvm.load %15 : !llvm.ptr -> i32
    %17 = llvm.mlir.constant(716 : i64) : i64
    %18 = llvm.getelementptr %arg1[%17] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %19 = llvm.load %18 : !llvm.ptr -> i32
    %20 = llvm.mlir.constant(1 : i32) : i32
    %21 = llvm.icmp "eq" %16, %20 : i32
    %22 = llvm.mlir.constant(1 : i32) : i32
    %23 = llvm.icmp "eq" %19, %22 : i32
    %24 = llvm.and %21, %23 : i1
    llvm.cond_br %24, ^bb12, ^bb9
  ^bb6:  // 2 preds: ^bb0, ^bb15
    %25 = llvm.mlir.constant(712 : i64) : i64
    %26 = llvm.getelementptr %arg1[%25] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %27 = llvm.load %26 : !llvm.ptr -> i32
    %28 = llvm.mlir.constant(716 : i64) : i64
    %29 = llvm.getelementptr %arg1[%28] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %30 = llvm.load %29 : !llvm.ptr -> i32
    %31 = llvm.mlir.constant(1 : i32) : i32
    %32 = llvm.icmp "eq" %27, %31 : i32
    %33 = llvm.mlir.constant(1 : i32) : i32
    %34 = llvm.icmp "eq" %30, %33 : i32
    %35 = llvm.and %32, %34 : i1
    llvm.cond_br %35, ^bb13, ^bb9
  ^bb7:  // 2 preds: ^bb0, ^bb23
    %36 = llvm.mlir.constant(true) : i1
    %37 = llvm.mlir.zero : !llvm.ptr
    %38 = llvm.mlir.constant(16 : i64) : i64
    %39 = llvm.getelementptr %arg1[%38] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %40 = llvm.load %39 : !llvm.ptr -> !llvm.ptr
    %41 = llvm.icmp "ne" %40, %37 : !llvm.ptr
    %42 = llvm.mlir.constant(8 : i64) : i64
    %43 = llvm.getelementptr %arg1[%42] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %44 = llvm.load %43 : !llvm.ptr -> !llvm.ptr
    %45 = llvm.icmp "ne" %44, %37 : !llvm.ptr
    %46 = llvm.and %41, %45 : i1
    %47 = llvm.mlir.constant(16 : i64) : i64
    %48 = llvm.getelementptr %arg1[%47] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %49 = llvm.load %48 : !llvm.ptr -> !llvm.ptr
    %50 = llvm.icmp "ne" %49, %37 : !llvm.ptr
    %51 = llvm.and %46, %50 : i1
    llvm.cond_br %51, ^bb15, ^bb14
  ^bb8:  // 2 preds: ^bb0, ^bb0
    %52 = llvm.mlir.constant(0 : i64) : i64
    %53 = llvm.getelementptr %arg1[%52] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %54 = llvm.load %53 : !llvm.ptr -> !llvm.ptr
    %55 = llvm.mlir.zero : !llvm.ptr
    %56 = llvm.icmp "eq" %54, %55 : !llvm.ptr
    llvm.cond_br %56, ^bb16, ^bb17
  ^bb9:  // 5 preds: ^bb0, ^bb4, ^bb5, ^bb6, ^bb20
    %57 = llvm.mlir.constant(4 : i64) : i64
    llvm.return %57 : i64
  ^bb10:  // pred: ^bb13
    %58 = llvm.mlir.constant(6 : i64) : i64
    llvm.return %58 : i64
  ^bb11:  // pred: ^bb4
    %59 = llvm.mlir.constant(0 : i8) : i8
    %60 = llvm.mlir.constant(641 : i64) : i64
    %61 = llvm.getelementptr %arg1[%60] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %59, %61 : i8, !llvm.ptr
    %62 = llvm.mlir.constant(0 : i32) : i32
    %63 = llvm.mlir.constant(716 : i64) : i64
    %64 = llvm.getelementptr %arg1[%63] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %62, %64 : i32, !llvm.ptr
    %65 = llvm.mlir.constant(1 : i32) : i32
    %66 = llvm.sub %5, %65 : i32
    %67 = llvm.mlir.constant(712 : i64) : i64
    %68 = llvm.getelementptr %arg1[%67] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %66, %68 : i32, !llvm.ptr
    llvm.br ^bb2
  ^bb12:  // pred: ^bb5
    %69 = llvm.mlir.constant(0 : i8) : i8
    %70 = llvm.mlir.constant(641 : i64) : i64
    %71 = llvm.getelementptr %arg1[%70] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %69, %71 : i8, !llvm.ptr
    %72 = llvm.mlir.constant(0 : i32) : i32
    %73 = llvm.mlir.constant(716 : i64) : i64
    %74 = llvm.getelementptr %arg1[%73] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %72, %74 : i32, !llvm.ptr
    %75 = llvm.mlir.constant(1 : i32) : i32
    %76 = llvm.sub %16, %75 : i32
    %77 = llvm.mlir.constant(712 : i64) : i64
    %78 = llvm.getelementptr %arg1[%77] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %76, %78 : i32, !llvm.ptr
    llvm.br ^bb1
  ^bb13:  // pred: ^bb6
    %79 = llvm.mlir.constant(0 : i8) : i8
    %80 = llvm.mlir.constant(641 : i64) : i64
    %81 = llvm.getelementptr %arg1[%80] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %79, %81 : i8, !llvm.ptr
    %82 = llvm.mlir.constant(0 : i32) : i32
    %83 = llvm.mlir.constant(716 : i64) : i64
    %84 = llvm.getelementptr %arg1[%83] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %82, %84 : i32, !llvm.ptr
    %85 = llvm.mlir.constant(1 : i32) : i32
    %86 = llvm.sub %27, %85 : i32
    %87 = llvm.mlir.constant(712 : i64) : i64
    %88 = llvm.getelementptr %arg1[%87] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %86, %88 : i32, !llvm.ptr
    llvm.br ^bb10
  ^bb14:  // pred: ^bb7
    %89 = llvm.mlir.constant(50 : i64) : i64
    llvm.return %89 : i64
  ^bb15:  // pred: ^bb7
    %90 = llvm.mlir.constant(20 : i32) : i32
    %91 = llvm.mlir.constant(728 : i64) : i64
    %92 = llvm.getelementptr %arg1[%91] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %90, %92 : i32, !llvm.ptr
    llvm.br ^bb6
  ^bb16:  // pred: ^bb8
    %93 = llvm.mlir.constant(58 : i64) : i64
    llvm.return %93 : i64
  ^bb17:  // pred: ^bb8
    %94 = llvm.mlir.constant(0 : i64) : i64
    %95 = llvm.getelementptr %54[%94] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %96 = llvm.load %95 : !llvm.ptr -> i8
    %97 = llvm.mlir.constant(11 : i8) : i8
    %98 = llvm.icmp "eq" %96, %97 : i8
    llvm.cond_br %98, ^bb18, ^bb19
  ^bb18:  // pred: ^bb17
    %99 = llvm.mlir.constant(8 : i64) : i64
    %100 = llvm.getelementptr %54[%99] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %101 = llvm.load %100 : !llvm.ptr -> !llvm.ptr
    %102 = llvm.mlir.constant(5089913888 : i64) : i64
    %103 = llvm.inttoptr %102 : i64 to !llvm.ptr
    %104 = llvm.icmp "eq" %101, %103 : !llvm.ptr
    llvm.cond_br %104, ^bb20, ^bb19
  ^bb19:  // 2 preds: ^bb17, ^bb18
    %105 = llvm.mlir.constant(63 : i64) : i64
    llvm.return %105 : i64
  ^bb20:  // pred: ^bb18
    %106 = llvm.mlir.constant(712 : i64) : i64
    %107 = llvm.getelementptr %arg1[%106] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %108 = llvm.load %107 : !llvm.ptr -> i32
    %109 = llvm.mlir.constant(716 : i64) : i64
    %110 = llvm.getelementptr %arg1[%109] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %111 = llvm.load %110 : !llvm.ptr -> i32
    %112 = llvm.mlir.constant(640 : i64) : i64
    %113 = llvm.getelementptr %arg1[%112] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %114 = llvm.load %113 : !llvm.ptr -> i8
    %115 = llvm.mlir.constant(0 : i32) : i32
    %116 = llvm.icmp "eq" %108, %115 : i32
    %117 = llvm.mlir.constant(0 : i32) : i32
    %118 = llvm.icmp "eq" %111, %117 : i32
    %119 = llvm.and %116, %118 : i1
    %120 = llvm.mlir.constant(0 : i8) : i8
    %121 = llvm.icmp "ne" %114, %120 : i8
    %122 = llvm.and %119, %121 : i1
    llvm.cond_br %122, ^bb21, ^bb9
  ^bb21:  // pred: ^bb20
    %123 = llvm.mlir.constant(704 : i64) : i64
    %124 = llvm.getelementptr %arg1[%123] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %125 = llvm.load %124 : !llvm.ptr -> i32
    %126 = llvm.mlir.constant(708 : i64) : i64
    %127 = llvm.getelementptr %arg1[%126] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %128 = llvm.load %127 : !llvm.ptr -> i32
    %129 = llvm.zext %125 : i32 to i64
    %130 = llvm.zext %108 : i32 to i64
    %131 = llvm.add %129, %130 : i64
    %132 = llvm.zext %128 : i32 to i64
    %133 = llvm.icmp "uge" %131, %132 : i64
    llvm.cond_br %133, ^bb22, ^bb23
  ^bb22:  // pred: ^bb21
    %134 = llvm.mlir.constant(61 : i64) : i64
    llvm.return %134 : i64
  ^bb23:  // pred: ^bb21
    %135 = llvm.mlir.constant(16 : i64) : i64
    %136 = llvm.getelementptr %54[%135] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %137 = llvm.load %136 : !llvm.ptr -> !llvm.ptr
    %138 = llvm.mlir.constant(136 : i64) : i64
    %139 = llvm.getelementptr %arg1[%138] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %137, %139 : !llvm.ptr, !llvm.ptr
    %140 = llvm.mlir.constant(1 : i8) : i8
    %141 = llvm.mlir.constant(641 : i64) : i64
    %142 = llvm.getelementptr %arg1[%141] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %140, %142 : i8, !llvm.ptr
    %143 = llvm.mlir.constant(1 : i32) : i32
    %144 = llvm.mlir.constant(716 : i64) : i64
    %145 = llvm.getelementptr %arg1[%144] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %143, %145 : i32, !llvm.ptr
    %146 = llvm.mlir.constant(1 : i32) : i32
    %147 = llvm.add %108, %146 : i32
    %148 = llvm.mlir.constant(712 : i64) : i64
    %149 = llvm.getelementptr %arg1[%148] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %147, %149 : i32, !llvm.ptr
    %150 = llvm.mlir.constant(720 : i64) : i64
    %151 = llvm.getelementptr %arg1[%150] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %152 = llvm.load %151 : !llvm.ptr -> i32
    %153 = llvm.mlir.constant(1 : i32) : i32
    %154 = llvm.add %152, %153 : i32
    %155 = llvm.mlir.constant(720 : i64) : i64
    %156 = llvm.getelementptr %arg1[%155] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %154, %156 : i32, !llvm.ptr
    %157 = llvm.mlir.zero : !llvm.ptr
    %158 = llvm.mlir.constant(16 : i64) : i64
    %159 = llvm.getelementptr %arg1[%158] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %157, %159 : !llvm.ptr, !llvm.ptr
    llvm.br ^bb7
  }
}

