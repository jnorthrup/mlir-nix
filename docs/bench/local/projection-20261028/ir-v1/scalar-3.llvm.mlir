module {
  llvm.func @scalar(%arg0: i32, %arg1: !llvm.ptr) -> i64 {
    llvm.switch %arg0 : i32, ^bb10 [
      0: ^bb9,
      1: ^bb1,
      2: ^bb2,
      3: ^bb3,
      4: ^bb4,
      5: ^bb5,
      6: ^bb6,
      7: ^bb7,
      8: ^bb8,
      9: ^bb9
    ]
  ^bb1:  // 2 preds: ^bb0, ^bb11
    %0 = llvm.mlir.constant(0 : i64) : i64
    llvm.return %0 : i64
  ^bb2:  // 2 preds: ^bb0, ^bb12
    %1 = llvm.mlir.constant(1 : i64) : i64
    llvm.return %1 : i64
  ^bb3:  // 3 preds: ^bb0, ^bb18, ^bb22
    %2 = llvm.mlir.constant(3 : i64) : i64
    llvm.return %2 : i64
  ^bb4:  // 3 preds: ^bb0, ^bb15, ^bb19
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
    llvm.cond_br %13, ^bb11, ^bb10
  ^bb5:  // 3 preds: ^bb0, ^bb15, ^bb19
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
    llvm.cond_br %24, ^bb12, ^bb10
  ^bb6:  // 2 preds: ^bb0, ^bb23
    %25 = llvm.mlir.constant(24 : i64) : i64
    %26 = llvm.getelementptr %arg1[%25] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %27 = llvm.load %26 : !llvm.ptr -> !llvm.ptr
    %28 = llvm.mlir.zero : !llvm.ptr
    %29 = llvm.icmp "eq" %27, %28 : !llvm.ptr
    llvm.cond_br %29, ^bb13, ^bb14
  ^bb7:  // 2 preds: ^bb0, ^bb23
    %30 = llvm.mlir.constant(40 : i64) : i64
    %31 = llvm.getelementptr %arg1[%30] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %32 = llvm.load %31 : !llvm.ptr -> !llvm.ptr
    %33 = llvm.mlir.zero : !llvm.ptr
    %34 = llvm.icmp "eq" %32, %33 : !llvm.ptr
    llvm.cond_br %34, ^bb16, ^bb17
  ^bb8:  // 2 preds: ^bb0, ^bb31
    %35 = llvm.mlir.constant(32 : i64) : i64
    %36 = llvm.getelementptr %arg1[%35] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %37 = llvm.load %36 : !llvm.ptr -> !llvm.ptr
    %38 = llvm.mlir.zero : !llvm.ptr
    %39 = llvm.icmp "eq" %37, %38 : !llvm.ptr
    llvm.cond_br %39, ^bb20, ^bb21
  ^bb9:  // 2 preds: ^bb0, ^bb0
    %40 = llvm.mlir.constant(0 : i64) : i64
    %41 = llvm.getelementptr %arg1[%40] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %42 = llvm.load %41 : !llvm.ptr -> !llvm.ptr
    %43 = llvm.mlir.zero : !llvm.ptr
    %44 = llvm.icmp "eq" %42, %43 : !llvm.ptr
    llvm.cond_br %44, ^bb24, ^bb25
  ^bb10:  // 4 preds: ^bb0, ^bb4, ^bb5, ^bb28
    %45 = llvm.mlir.constant(4 : i64) : i64
    llvm.return %45 : i64
  ^bb11:  // pred: ^bb4
    %46 = llvm.mlir.constant(0 : i8) : i8
    %47 = llvm.mlir.constant(641 : i64) : i64
    %48 = llvm.getelementptr %arg1[%47] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %46, %48 : i8, !llvm.ptr
    %49 = llvm.mlir.constant(0 : i32) : i32
    %50 = llvm.mlir.constant(716 : i64) : i64
    %51 = llvm.getelementptr %arg1[%50] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %49, %51 : i32, !llvm.ptr
    %52 = llvm.mlir.constant(1 : i32) : i32
    %53 = llvm.sub %5, %52 : i32
    %54 = llvm.mlir.constant(712 : i64) : i64
    %55 = llvm.getelementptr %arg1[%54] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %53, %55 : i32, !llvm.ptr
    llvm.br ^bb1
  ^bb12:  // pred: ^bb5
    %56 = llvm.mlir.constant(0 : i8) : i8
    %57 = llvm.mlir.constant(641 : i64) : i64
    %58 = llvm.getelementptr %arg1[%57] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %56, %58 : i8, !llvm.ptr
    %59 = llvm.mlir.constant(0 : i32) : i32
    %60 = llvm.mlir.constant(716 : i64) : i64
    %61 = llvm.getelementptr %arg1[%60] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %59, %61 : i32, !llvm.ptr
    %62 = llvm.mlir.constant(1 : i32) : i32
    %63 = llvm.sub %16, %62 : i32
    %64 = llvm.mlir.constant(712 : i64) : i64
    %65 = llvm.getelementptr %arg1[%64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %63, %65 : i32, !llvm.ptr
    llvm.br ^bb2
  ^bb13:  // 2 preds: ^bb6, ^bb14
    %66 = llvm.mlir.constant(42 : i64) : i64
    llvm.return %66 : i64
  ^bb14:  // pred: ^bb6
    %67 = llvm.mlir.constant(0 : i64) : i64
    %68 = llvm.getelementptr %27[%67] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %69 = llvm.load %68 : !llvm.ptr -> i8
    %70 = llvm.mlir.constant(2 : i8) : i8
    %71 = llvm.icmp "ule" %69, %70 : i8
    llvm.cond_br %71, ^bb13, ^bb15
  ^bb15:  // pred: ^bb14
    %72 = llvm.mlir.constant(5 : i8) : i8
    %73 = llvm.icmp "eq" %69, %72 : i8
    llvm.cond_br %73, ^bb4, ^bb5
  ^bb16:  // 2 preds: ^bb7, ^bb17
    %74 = llvm.mlir.constant(50 : i64) : i64
    llvm.return %74 : i64
  ^bb17:  // pred: ^bb7
    %75 = llvm.mlir.constant(0 : i64) : i64
    %76 = llvm.getelementptr %32[%75] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %77 = llvm.load %76 : !llvm.ptr -> i8
    %78 = llvm.mlir.constant(2 : i8) : i8
    %79 = llvm.icmp "ule" %77, %78 : i8
    llvm.cond_br %79, ^bb16, ^bb18
  ^bb18:  // pred: ^bb17
    %80 = llvm.mlir.constant(5 : i8) : i8
    %81 = llvm.icmp "eq" %77, %80 : i8
    llvm.cond_br %81, ^bb19, ^bb3
  ^bb19:  // pred: ^bb18
    %82 = llvm.mlir.constant(8 : i64) : i64
    %83 = llvm.getelementptr %32[%82] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %84 = llvm.load %83 : !llvm.ptr -> i8
    %85 = llvm.mlir.constant(0 : i8) : i8
    %86 = llvm.icmp "ne" %84, %85 : i8
    llvm.cond_br %86, ^bb4, ^bb5
  ^bb20:  // 2 preds: ^bb8, ^bb21
    %87 = llvm.mlir.constant(58 : i64) : i64
    llvm.return %87 : i64
  ^bb21:  // pred: ^bb8
    %88 = llvm.mlir.constant(0 : i64) : i64
    %89 = llvm.getelementptr %37[%88] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %90 = llvm.load %89 : !llvm.ptr -> i8
    %91 = llvm.mlir.constant(2 : i8) : i8
    %92 = llvm.icmp "ule" %90, %91 : i8
    llvm.cond_br %92, ^bb20, ^bb22
  ^bb22:  // pred: ^bb21
    %93 = llvm.mlir.constant(5 : i8) : i8
    %94 = llvm.icmp "eq" %90, %93 : i8
    llvm.cond_br %94, ^bb23, ^bb3
  ^bb23:  // pred: ^bb22
    %95 = llvm.mlir.constant(8 : i64) : i64
    %96 = llvm.getelementptr %37[%95] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %97 = llvm.load %96 : !llvm.ptr -> i8
    %98 = llvm.mlir.constant(0 : i8) : i8
    %99 = llvm.icmp "ne" %97, %98 : i8
    llvm.cond_br %99, ^bb6, ^bb7
  ^bb24:  // pred: ^bb9
    %100 = llvm.mlir.constant(66 : i64) : i64
    llvm.return %100 : i64
  ^bb25:  // pred: ^bb9
    %101 = llvm.mlir.constant(0 : i64) : i64
    %102 = llvm.getelementptr %42[%101] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %103 = llvm.load %102 : !llvm.ptr -> i8
    %104 = llvm.mlir.constant(11 : i8) : i8
    %105 = llvm.icmp "eq" %103, %104 : i8
    llvm.cond_br %105, ^bb26, ^bb27
  ^bb26:  // pred: ^bb25
    %106 = llvm.mlir.constant(8 : i64) : i64
    %107 = llvm.getelementptr %42[%106] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %108 = llvm.load %107 : !llvm.ptr -> !llvm.ptr
    %109 = llvm.mlir.constant(5710640768 : i64) : i64
    %110 = llvm.inttoptr %109 : i64 to !llvm.ptr
    %111 = llvm.icmp "eq" %108, %110 : !llvm.ptr
    llvm.cond_br %111, ^bb28, ^bb27
  ^bb27:  // 2 preds: ^bb25, ^bb26
    %112 = llvm.mlir.constant(71 : i64) : i64
    llvm.return %112 : i64
  ^bb28:  // pred: ^bb26
    %113 = llvm.mlir.constant(712 : i64) : i64
    %114 = llvm.getelementptr %arg1[%113] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %115 = llvm.load %114 : !llvm.ptr -> i32
    %116 = llvm.mlir.constant(716 : i64) : i64
    %117 = llvm.getelementptr %arg1[%116] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %118 = llvm.load %117 : !llvm.ptr -> i32
    %119 = llvm.mlir.constant(640 : i64) : i64
    %120 = llvm.getelementptr %arg1[%119] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %121 = llvm.load %120 : !llvm.ptr -> i8
    %122 = llvm.mlir.constant(0 : i32) : i32
    %123 = llvm.icmp "eq" %115, %122 : i32
    %124 = llvm.mlir.constant(0 : i32) : i32
    %125 = llvm.icmp "eq" %118, %124 : i32
    %126 = llvm.and %123, %125 : i1
    %127 = llvm.mlir.constant(0 : i8) : i8
    %128 = llvm.icmp "ne" %121, %127 : i8
    %129 = llvm.and %126, %128 : i1
    llvm.cond_br %129, ^bb29, ^bb10
  ^bb29:  // pred: ^bb28
    %130 = llvm.mlir.constant(704 : i64) : i64
    %131 = llvm.getelementptr %arg1[%130] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %132 = llvm.load %131 : !llvm.ptr -> i32
    %133 = llvm.mlir.constant(708 : i64) : i64
    %134 = llvm.getelementptr %arg1[%133] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %135 = llvm.load %134 : !llvm.ptr -> i32
    %136 = llvm.zext %132 : i32 to i64
    %137 = llvm.zext %115 : i32 to i64
    %138 = llvm.add %136, %137 : i64
    %139 = llvm.zext %135 : i32 to i64
    %140 = llvm.icmp "uge" %138, %139 : i64
    llvm.cond_br %140, ^bb30, ^bb31
  ^bb30:  // pred: ^bb29
    %141 = llvm.mlir.constant(69 : i64) : i64
    llvm.return %141 : i64
  ^bb31:  // pred: ^bb29
    %142 = llvm.mlir.constant(16 : i64) : i64
    %143 = llvm.getelementptr %42[%142] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %144 = llvm.load %143 : !llvm.ptr -> !llvm.ptr
    %145 = llvm.mlir.constant(136 : i64) : i64
    %146 = llvm.getelementptr %arg1[%145] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %144, %146 : !llvm.ptr, !llvm.ptr
    %147 = llvm.mlir.constant(1 : i8) : i8
    %148 = llvm.mlir.constant(641 : i64) : i64
    %149 = llvm.getelementptr %arg1[%148] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %147, %149 : i8, !llvm.ptr
    %150 = llvm.mlir.constant(1 : i32) : i32
    %151 = llvm.mlir.constant(716 : i64) : i64
    %152 = llvm.getelementptr %arg1[%151] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %150, %152 : i32, !llvm.ptr
    %153 = llvm.mlir.constant(1 : i32) : i32
    %154 = llvm.add %115, %153 : i32
    %155 = llvm.mlir.constant(712 : i64) : i64
    %156 = llvm.getelementptr %arg1[%155] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %154, %156 : i32, !llvm.ptr
    %157 = llvm.mlir.constant(720 : i64) : i64
    %158 = llvm.getelementptr %arg1[%157] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %159 = llvm.load %158 : !llvm.ptr -> i32
    %160 = llvm.mlir.constant(1 : i32) : i32
    %161 = llvm.add %159, %160 : i32
    %162 = llvm.mlir.constant(720 : i64) : i64
    %163 = llvm.getelementptr %arg1[%162] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %161, %163 : i32, !llvm.ptr
    %164 = llvm.mlir.constant(724 : i64) : i64
    %165 = llvm.getelementptr %arg1[%164] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %166 = llvm.load %165 : !llvm.ptr -> i32
    %167 = llvm.mlir.constant(1 : i32) : i32
    %168 = llvm.add %166, %167 : i32
    %169 = llvm.mlir.constant(724 : i64) : i64
    %170 = llvm.getelementptr %arg1[%169] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %168, %170 : i32, !llvm.ptr
    %171 = llvm.mlir.zero : !llvm.ptr
    %172 = llvm.mlir.constant(32 : i64) : i64
    %173 = llvm.getelementptr %arg1[%172] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %171, %173 : !llvm.ptr, !llvm.ptr
    %174 = llvm.mlir.zero : !llvm.ptr
    %175 = llvm.mlir.constant(40 : i64) : i64
    %176 = llvm.getelementptr %arg1[%175] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %174, %176 : !llvm.ptr, !llvm.ptr
    llvm.br ^bb8
  }
}

