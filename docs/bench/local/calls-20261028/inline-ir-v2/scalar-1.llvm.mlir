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
  ^bb1:  // 2 preds: ^bb0, ^bb10
    %0 = llvm.mlir.constant(0 : i64) : i64
    llvm.return %0 : i64
  ^bb2:  // 2 preds: ^bb0, ^bb11
    %1 = llvm.mlir.constant(1 : i64) : i64
    llvm.return %1 : i64
  ^bb3:  // 3 preds: ^bb0, ^bb15, ^bb18
    %2 = llvm.mlir.constant(3 : i64) : i64
    llvm.return %2 : i64
  ^bb4:  // 2 preds: ^bb0, ^bb22
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
    llvm.cond_br %13, ^bb10, ^bb9
  ^bb5:  // 3 preds: ^bb0, ^bb14, ^bb17
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
    llvm.cond_br %24, ^bb11, ^bb9
  ^bb6:  // 2 preds: ^bb0, ^bb22
    %25 = llvm.mlir.constant(8 : i64) : i64
    %26 = llvm.getelementptr %arg1[%25] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %27 = llvm.load %26 : !llvm.ptr -> !llvm.ptr
    %28 = llvm.mlir.zero : !llvm.ptr
    %29 = llvm.icmp "eq" %27, %28 : !llvm.ptr
    llvm.cond_br %29, ^bb12, ^bb13
  ^bb7:  // 2 preds: ^bb0, ^bb30
    %30 = llvm.mlir.constant(8 : i64) : i64
    %31 = llvm.getelementptr %arg1[%30] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %32 = llvm.load %31 : !llvm.ptr -> !llvm.ptr
    %33 = llvm.mlir.zero : !llvm.ptr
    %34 = llvm.icmp "eq" %32, %33 : !llvm.ptr
    llvm.cond_br %34, ^bb20, ^bb21
  ^bb8:  // 2 preds: ^bb0, ^bb0
    %35 = llvm.mlir.constant(0 : i64) : i64
    %36 = llvm.getelementptr %arg1[%35] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %37 = llvm.load %36 : !llvm.ptr -> !llvm.ptr
    %38 = llvm.mlir.zero : !llvm.ptr
    %39 = llvm.icmp "eq" %37, %38 : !llvm.ptr
    llvm.cond_br %39, ^bb23, ^bb24
  ^bb9:  // 4 preds: ^bb0, ^bb4, ^bb5, ^bb27
    %40 = llvm.mlir.constant(4 : i64) : i64
    llvm.return %40 : i64
  ^bb10:  // pred: ^bb4
    %41 = llvm.mlir.constant(0 : i8) : i8
    %42 = llvm.mlir.constant(641 : i64) : i64
    %43 = llvm.getelementptr %arg1[%42] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %41, %43 : i8, !llvm.ptr
    %44 = llvm.mlir.constant(0 : i32) : i32
    %45 = llvm.mlir.constant(716 : i64) : i64
    %46 = llvm.getelementptr %arg1[%45] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %44, %46 : i32, !llvm.ptr
    %47 = llvm.mlir.constant(1 : i32) : i32
    %48 = llvm.sub %5, %47 : i32
    %49 = llvm.mlir.constant(712 : i64) : i64
    %50 = llvm.getelementptr %arg1[%49] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %48, %50 : i32, !llvm.ptr
    llvm.br ^bb1
  ^bb11:  // pred: ^bb5
    %51 = llvm.mlir.constant(0 : i8) : i8
    %52 = llvm.mlir.constant(641 : i64) : i64
    %53 = llvm.getelementptr %arg1[%52] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %51, %53 : i8, !llvm.ptr
    %54 = llvm.mlir.constant(0 : i32) : i32
    %55 = llvm.mlir.constant(716 : i64) : i64
    %56 = llvm.getelementptr %arg1[%55] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %54, %56 : i32, !llvm.ptr
    %57 = llvm.mlir.constant(1 : i32) : i32
    %58 = llvm.sub %16, %57 : i32
    %59 = llvm.mlir.constant(712 : i64) : i64
    %60 = llvm.getelementptr %arg1[%59] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %58, %60 : i32, !llvm.ptr
    llvm.br ^bb2
  ^bb12:  // 2 preds: ^bb6, ^bb13
    %61 = llvm.mlir.constant(42 : i64) : i64
    llvm.return %61 : i64
  ^bb13:  // pred: ^bb6
    %62 = llvm.mlir.constant(0 : i64) : i64
    %63 = llvm.getelementptr %27[%62] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %64 = llvm.load %63 : !llvm.ptr -> i8
    %65 = llvm.mlir.constant(2 : i8) : i8
    %66 = llvm.icmp "ule" %64, %65 : i8
    llvm.cond_br %66, ^bb12, ^bb14
  ^bb14:  // pred: ^bb13
    %67 = llvm.mlir.constant(9 : i8) : i8
    %68 = llvm.icmp "eq" %64, %67 : i8
    llvm.cond_br %68, ^bb15, ^bb5
  ^bb15:  // pred: ^bb14
    %69 = llvm.mlir.constant(8 : i64) : i64
    %70 = llvm.getelementptr %27[%69] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %71 = llvm.load %70 : !llvm.ptr -> !llvm.ptr
    %72 = llvm.mlir.constant(0 : i64) : i64
    %73 = llvm.getelementptr %71[%72] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %74 = llvm.load %73 : !llvm.ptr -> i32
    %75 = llvm.mlir.constant(-1 : i32) : i32
    %76 = llvm.icmp "eq" %74, %75 : i32
    llvm.cond_br %76, ^bb3, ^bb16
  ^bb16:  // pred: ^bb15
    %77 = llvm.zext %74 : i32 to i64
    %78 = llvm.mlir.constant(0 : i64) : i64
    llvm.br ^bb17(%78, %77 : i64, i64)
  ^bb17(%79: i64, %80: i64):  // 2 preds: ^bb16, ^bb19
    %81 = llvm.icmp "ult" %79, %80 : i64
    llvm.cond_br %81, ^bb18, ^bb5
  ^bb18:  // pred: ^bb17
    %82 = llvm.add %79, %80 : i64
    %83 = llvm.mlir.constant(1 : i64) : i64
    %84 = llvm.lshr %82, %83 : i64
    %85 = llvm.mlir.constant(16 : i64) : i64
    %86 = llvm.mlir.constant(16 : i64) : i64
    %87 = llvm.mul %84, %86 : i64
    %88 = llvm.add %87, %85 : i64
    %89 = llvm.getelementptr %71[%88] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %90 = llvm.load %89 : !llvm.ptr -> i32
    %91 = llvm.mlir.constant(5 : i32) : i32
    %92 = llvm.icmp "eq" %90, %91 : i32
    llvm.cond_br %92, ^bb3, ^bb19
  ^bb19:  // pred: ^bb18
    %93 = llvm.mlir.constant(5 : i32) : i32
    %94 = llvm.icmp "ult" %90, %93 : i32
    %95 = llvm.mlir.constant(1 : i64) : i64
    %96 = llvm.add %84, %95 : i64
    %97 = llvm.select %94, %96, %79 : i1, i64
    %98 = llvm.select %94, %80, %84 : i1, i64
    llvm.br ^bb17(%97, %98 : i64, i64)
  ^bb20:  // 2 preds: ^bb7, ^bb21
    %99 = llvm.mlir.constant(50 : i64) : i64
    llvm.return %99 : i64
  ^bb21:  // pred: ^bb7
    %100 = llvm.mlir.constant(0 : i64) : i64
    %101 = llvm.getelementptr %32[%100] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %102 = llvm.load %101 : !llvm.ptr -> i8
    %103 = llvm.mlir.constant(2 : i8) : i8
    %104 = llvm.icmp "ule" %102, %103 : i8
    llvm.cond_br %104, ^bb20, ^bb22
  ^bb22:  // pred: ^bb21
    %105 = llvm.mlir.constant(11 : i8) : i8
    %106 = llvm.icmp "eq" %102, %105 : i8
    %107 = llvm.mlir.constant(12 : i8) : i8
    %108 = llvm.icmp "eq" %102, %107 : i8
    %109 = llvm.mlir.constant(13 : i8) : i8
    %110 = llvm.icmp "eq" %102, %109 : i8
    %111 = llvm.or %108, %110 : i1
    %112 = llvm.or %106, %111 : i1
    llvm.cond_br %112, ^bb4, ^bb6
  ^bb23:  // pred: ^bb8
    %113 = llvm.mlir.constant(58 : i64) : i64
    llvm.return %113 : i64
  ^bb24:  // pred: ^bb8
    %114 = llvm.mlir.constant(0 : i64) : i64
    %115 = llvm.getelementptr %37[%114] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %116 = llvm.load %115 : !llvm.ptr -> i8
    %117 = llvm.mlir.constant(11 : i8) : i8
    %118 = llvm.icmp "eq" %116, %117 : i8
    llvm.cond_br %118, ^bb25, ^bb26
  ^bb25:  // pred: ^bb24
    %119 = llvm.mlir.constant(8 : i64) : i64
    %120 = llvm.getelementptr %37[%119] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %121 = llvm.load %120 : !llvm.ptr -> !llvm.ptr
    %122 = llvm.mlir.constant(5660331984 : i64) : i64
    %123 = llvm.inttoptr %122 : i64 to !llvm.ptr
    %124 = llvm.icmp "eq" %121, %123 : !llvm.ptr
    llvm.cond_br %124, ^bb27, ^bb26
  ^bb26:  // 2 preds: ^bb24, ^bb25
    %125 = llvm.mlir.constant(63 : i64) : i64
    llvm.return %125 : i64
  ^bb27:  // pred: ^bb25
    %126 = llvm.mlir.constant(712 : i64) : i64
    %127 = llvm.getelementptr %arg1[%126] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %128 = llvm.load %127 : !llvm.ptr -> i32
    %129 = llvm.mlir.constant(716 : i64) : i64
    %130 = llvm.getelementptr %arg1[%129] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %131 = llvm.load %130 : !llvm.ptr -> i32
    %132 = llvm.mlir.constant(640 : i64) : i64
    %133 = llvm.getelementptr %arg1[%132] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %134 = llvm.load %133 : !llvm.ptr -> i8
    %135 = llvm.mlir.constant(0 : i32) : i32
    %136 = llvm.icmp "eq" %128, %135 : i32
    %137 = llvm.mlir.constant(0 : i32) : i32
    %138 = llvm.icmp "eq" %131, %137 : i32
    %139 = llvm.and %136, %138 : i1
    %140 = llvm.mlir.constant(0 : i8) : i8
    %141 = llvm.icmp "ne" %134, %140 : i8
    %142 = llvm.and %139, %141 : i1
    llvm.cond_br %142, ^bb28, ^bb9
  ^bb28:  // pred: ^bb27
    %143 = llvm.mlir.constant(704 : i64) : i64
    %144 = llvm.getelementptr %arg1[%143] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %145 = llvm.load %144 : !llvm.ptr -> i32
    %146 = llvm.mlir.constant(708 : i64) : i64
    %147 = llvm.getelementptr %arg1[%146] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %148 = llvm.load %147 : !llvm.ptr -> i32
    %149 = llvm.zext %145 : i32 to i64
    %150 = llvm.zext %128 : i32 to i64
    %151 = llvm.add %149, %150 : i64
    %152 = llvm.zext %148 : i32 to i64
    %153 = llvm.icmp "uge" %151, %152 : i64
    llvm.cond_br %153, ^bb29, ^bb30
  ^bb29:  // pred: ^bb28
    %154 = llvm.mlir.constant(61 : i64) : i64
    llvm.return %154 : i64
  ^bb30:  // pred: ^bb28
    %155 = llvm.mlir.constant(16 : i64) : i64
    %156 = llvm.getelementptr %37[%155] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %157 = llvm.load %156 : !llvm.ptr -> !llvm.ptr
    %158 = llvm.mlir.constant(136 : i64) : i64
    %159 = llvm.getelementptr %arg1[%158] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %157, %159 : !llvm.ptr, !llvm.ptr
    %160 = llvm.mlir.constant(1 : i8) : i8
    %161 = llvm.mlir.constant(641 : i64) : i64
    %162 = llvm.getelementptr %arg1[%161] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %160, %162 : i8, !llvm.ptr
    %163 = llvm.mlir.constant(1 : i32) : i32
    %164 = llvm.mlir.constant(716 : i64) : i64
    %165 = llvm.getelementptr %arg1[%164] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %163, %165 : i32, !llvm.ptr
    %166 = llvm.mlir.constant(1 : i32) : i32
    %167 = llvm.add %128, %166 : i32
    %168 = llvm.mlir.constant(712 : i64) : i64
    %169 = llvm.getelementptr %arg1[%168] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %167, %169 : i32, !llvm.ptr
    %170 = llvm.mlir.constant(720 : i64) : i64
    %171 = llvm.getelementptr %arg1[%170] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %172 = llvm.load %171 : !llvm.ptr -> i32
    %173 = llvm.mlir.constant(1 : i32) : i32
    %174 = llvm.add %172, %173 : i32
    %175 = llvm.mlir.constant(720 : i64) : i64
    %176 = llvm.getelementptr %arg1[%175] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %174, %176 : i32, !llvm.ptr
    llvm.br ^bb7
  }
}

