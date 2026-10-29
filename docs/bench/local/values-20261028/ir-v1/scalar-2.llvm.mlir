module {
  llvm.func @scalar(%arg0: i32, %arg1: !llvm.ptr) -> i64 {
    llvm.switch %arg0 : i32, ^bb11 [
      0: ^bb10,
      1: ^bb1,
      2: ^bb2,
      3: ^bb3,
      4: ^bb4,
      5: ^bb5,
      6: ^bb6,
      7: ^bb7,
      8: ^bb8,
      9: ^bb9,
      10: ^bb10
    ]
  ^bb1:  // 2 preds: ^bb0, ^bb14
    %0 = llvm.mlir.constant(0 : i64) : i64
    llvm.return %0 : i64
  ^bb2:  // 2 preds: ^bb0, ^bb13
    %1 = llvm.mlir.constant(1 : i64) : i64
    llvm.return %1 : i64
  ^bb3:  // 2 preds: ^bb0, ^bb21
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
    llvm.cond_br %13, ^bb13, ^bb11
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
    llvm.cond_br %24, ^bb14, ^bb11
  ^bb6:  // 3 preds: ^bb0, ^bb8, ^bb18
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
    llvm.cond_br %35, ^bb15, ^bb11
  ^bb7:  // 2 preds: ^bb0, ^bb22
    %36 = llvm.mlir.constant(24 : i64) : i64
    %37 = llvm.getelementptr %arg1[%36] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %38 = llvm.load %37 : !llvm.ptr -> !llvm.ptr
    %39 = llvm.mlir.zero : !llvm.ptr
    %40 = llvm.icmp "eq" %38, %39 : !llvm.ptr
    llvm.cond_br %40, ^bb16, ^bb17
  ^bb8:  // 2 preds: ^bb0, ^bb22
    %41 = llvm.mlir.constant(18 : i32) : i32
    %42 = llvm.mlir.constant(728 : i64) : i64
    %43 = llvm.getelementptr %arg1[%42] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %41, %43 : i32, !llvm.ptr
    llvm.br ^bb6
  ^bb9:  // 2 preds: ^bb0, ^bb30
    %44 = llvm.mlir.constant(16 : i64) : i64
    %45 = llvm.getelementptr %arg1[%44] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %46 = llvm.load %45 : !llvm.ptr -> !llvm.ptr
    %47 = llvm.mlir.zero : !llvm.ptr
    %48 = llvm.icmp "eq" %46, %47 : !llvm.ptr
    llvm.cond_br %48, ^bb19, ^bb20
  ^bb10:  // 2 preds: ^bb0, ^bb0
    %49 = llvm.mlir.constant(0 : i64) : i64
    %50 = llvm.getelementptr %arg1[%49] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %51 = llvm.load %50 : !llvm.ptr -> !llvm.ptr
    %52 = llvm.mlir.zero : !llvm.ptr
    %53 = llvm.icmp "eq" %51, %52 : !llvm.ptr
    llvm.cond_br %53, ^bb23, ^bb24
  ^bb11:  // 5 preds: ^bb0, ^bb4, ^bb5, ^bb6, ^bb27
    %54 = llvm.mlir.constant(4 : i64) : i64
    llvm.return %54 : i64
  ^bb12:  // pred: ^bb15
    %55 = llvm.mlir.constant(6 : i64) : i64
    llvm.return %55 : i64
  ^bb13:  // pred: ^bb4
    %56 = llvm.mlir.constant(0 : i8) : i8
    %57 = llvm.mlir.constant(641 : i64) : i64
    %58 = llvm.getelementptr %arg1[%57] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %56, %58 : i8, !llvm.ptr
    %59 = llvm.mlir.constant(0 : i32) : i32
    %60 = llvm.mlir.constant(716 : i64) : i64
    %61 = llvm.getelementptr %arg1[%60] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %59, %61 : i32, !llvm.ptr
    %62 = llvm.mlir.constant(1 : i32) : i32
    %63 = llvm.sub %5, %62 : i32
    %64 = llvm.mlir.constant(712 : i64) : i64
    %65 = llvm.getelementptr %arg1[%64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %63, %65 : i32, !llvm.ptr
    llvm.br ^bb2
  ^bb14:  // pred: ^bb5
    %66 = llvm.mlir.constant(0 : i8) : i8
    %67 = llvm.mlir.constant(641 : i64) : i64
    %68 = llvm.getelementptr %arg1[%67] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %66, %68 : i8, !llvm.ptr
    %69 = llvm.mlir.constant(0 : i32) : i32
    %70 = llvm.mlir.constant(716 : i64) : i64
    %71 = llvm.getelementptr %arg1[%70] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %69, %71 : i32, !llvm.ptr
    %72 = llvm.mlir.constant(1 : i32) : i32
    %73 = llvm.sub %16, %72 : i32
    %74 = llvm.mlir.constant(712 : i64) : i64
    %75 = llvm.getelementptr %arg1[%74] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %73, %75 : i32, !llvm.ptr
    llvm.br ^bb1
  ^bb15:  // pred: ^bb6
    %76 = llvm.mlir.constant(0 : i8) : i8
    %77 = llvm.mlir.constant(641 : i64) : i64
    %78 = llvm.getelementptr %arg1[%77] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %76, %78 : i8, !llvm.ptr
    %79 = llvm.mlir.constant(0 : i32) : i32
    %80 = llvm.mlir.constant(716 : i64) : i64
    %81 = llvm.getelementptr %arg1[%80] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %79, %81 : i32, !llvm.ptr
    %82 = llvm.mlir.constant(1 : i32) : i32
    %83 = llvm.sub %27, %82 : i32
    %84 = llvm.mlir.constant(712 : i64) : i64
    %85 = llvm.getelementptr %arg1[%84] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %83, %85 : i32, !llvm.ptr
    llvm.br ^bb12
  ^bb16:  // 2 preds: ^bb7, ^bb17
    %86 = llvm.mlir.constant(50 : i64) : i64
    llvm.return %86 : i64
  ^bb17:  // pred: ^bb7
    %87 = llvm.mlir.constant(0 : i64) : i64
    %88 = llvm.getelementptr %38[%87] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %89 = llvm.load %88 : !llvm.ptr -> i8
    %90 = llvm.mlir.constant(2 : i8) : i8
    %91 = llvm.icmp "ule" %89, %90 : i8
    llvm.cond_br %91, ^bb16, ^bb18
  ^bb18:  // pred: ^bb17
    %92 = llvm.mlir.constant(3 : i32) : i32
    %93 = llvm.mlir.constant(728 : i64) : i64
    %94 = llvm.getelementptr %arg1[%93] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %92, %94 : i32, !llvm.ptr
    llvm.br ^bb6
  ^bb19:  // 2 preds: ^bb9, ^bb20
    %95 = llvm.mlir.constant(66 : i64) : i64
    llvm.return %95 : i64
  ^bb20:  // pred: ^bb9
    %96 = llvm.mlir.constant(0 : i64) : i64
    %97 = llvm.getelementptr %46[%96] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %98 = llvm.load %97 : !llvm.ptr -> i8
    %99 = llvm.mlir.constant(2 : i8) : i8
    %100 = llvm.icmp "ule" %98, %99 : i8
    llvm.cond_br %100, ^bb19, ^bb21
  ^bb21:  // pred: ^bb20
    %101 = llvm.mlir.constant(5 : i8) : i8
    %102 = llvm.icmp "eq" %98, %101 : i8
    llvm.cond_br %102, ^bb22, ^bb3
  ^bb22:  // pred: ^bb21
    %103 = llvm.mlir.constant(8 : i64) : i64
    %104 = llvm.getelementptr %46[%103] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %105 = llvm.load %104 : !llvm.ptr -> i8
    %106 = llvm.mlir.constant(0 : i8) : i8
    %107 = llvm.icmp "ne" %105, %106 : i8
    llvm.cond_br %107, ^bb7, ^bb8
  ^bb23:  // pred: ^bb10
    %108 = llvm.mlir.constant(74 : i64) : i64
    llvm.return %108 : i64
  ^bb24:  // pred: ^bb10
    %109 = llvm.mlir.constant(0 : i64) : i64
    %110 = llvm.getelementptr %51[%109] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %111 = llvm.load %110 : !llvm.ptr -> i8
    %112 = llvm.mlir.constant(11 : i8) : i8
    %113 = llvm.icmp "eq" %111, %112 : i8
    llvm.cond_br %113, ^bb25, ^bb26
  ^bb25:  // pred: ^bb24
    %114 = llvm.mlir.constant(8 : i64) : i64
    %115 = llvm.getelementptr %51[%114] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %116 = llvm.load %115 : !llvm.ptr -> !llvm.ptr
    %117 = llvm.mlir.constant(5685503168 : i64) : i64
    %118 = llvm.inttoptr %117 : i64 to !llvm.ptr
    %119 = llvm.icmp "eq" %116, %118 : !llvm.ptr
    llvm.cond_br %119, ^bb27, ^bb26
  ^bb26:  // 2 preds: ^bb24, ^bb25
    %120 = llvm.mlir.constant(79 : i64) : i64
    llvm.return %120 : i64
  ^bb27:  // pred: ^bb25
    %121 = llvm.mlir.constant(712 : i64) : i64
    %122 = llvm.getelementptr %arg1[%121] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %123 = llvm.load %122 : !llvm.ptr -> i32
    %124 = llvm.mlir.constant(716 : i64) : i64
    %125 = llvm.getelementptr %arg1[%124] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %126 = llvm.load %125 : !llvm.ptr -> i32
    %127 = llvm.mlir.constant(640 : i64) : i64
    %128 = llvm.getelementptr %arg1[%127] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %129 = llvm.load %128 : !llvm.ptr -> i8
    %130 = llvm.mlir.constant(0 : i32) : i32
    %131 = llvm.icmp "eq" %123, %130 : i32
    %132 = llvm.mlir.constant(0 : i32) : i32
    %133 = llvm.icmp "eq" %126, %132 : i32
    %134 = llvm.and %131, %133 : i1
    %135 = llvm.mlir.constant(0 : i8) : i8
    %136 = llvm.icmp "ne" %129, %135 : i8
    %137 = llvm.and %134, %136 : i1
    llvm.cond_br %137, ^bb28, ^bb11
  ^bb28:  // pred: ^bb27
    %138 = llvm.mlir.constant(704 : i64) : i64
    %139 = llvm.getelementptr %arg1[%138] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %140 = llvm.load %139 : !llvm.ptr -> i32
    %141 = llvm.mlir.constant(708 : i64) : i64
    %142 = llvm.getelementptr %arg1[%141] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %143 = llvm.load %142 : !llvm.ptr -> i32
    %144 = llvm.zext %140 : i32 to i64
    %145 = llvm.zext %123 : i32 to i64
    %146 = llvm.add %144, %145 : i64
    %147 = llvm.zext %143 : i32 to i64
    %148 = llvm.icmp "uge" %146, %147 : i64
    llvm.cond_br %148, ^bb29, ^bb30
  ^bb29:  // pred: ^bb28
    %149 = llvm.mlir.constant(77 : i64) : i64
    llvm.return %149 : i64
  ^bb30:  // pred: ^bb28
    %150 = llvm.mlir.constant(16 : i64) : i64
    %151 = llvm.getelementptr %51[%150] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %152 = llvm.load %151 : !llvm.ptr -> !llvm.ptr
    %153 = llvm.mlir.constant(136 : i64) : i64
    %154 = llvm.getelementptr %arg1[%153] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %152, %154 : !llvm.ptr, !llvm.ptr
    %155 = llvm.mlir.constant(1 : i8) : i8
    %156 = llvm.mlir.constant(641 : i64) : i64
    %157 = llvm.getelementptr %arg1[%156] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %155, %157 : i8, !llvm.ptr
    %158 = llvm.mlir.constant(1 : i32) : i32
    %159 = llvm.mlir.constant(716 : i64) : i64
    %160 = llvm.getelementptr %arg1[%159] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %158, %160 : i32, !llvm.ptr
    %161 = llvm.mlir.constant(1 : i32) : i32
    %162 = llvm.add %123, %161 : i32
    %163 = llvm.mlir.constant(712 : i64) : i64
    %164 = llvm.getelementptr %arg1[%163] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %162, %164 : i32, !llvm.ptr
    %165 = llvm.mlir.constant(720 : i64) : i64
    %166 = llvm.getelementptr %arg1[%165] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %167 = llvm.load %166 : !llvm.ptr -> i32
    %168 = llvm.mlir.constant(1 : i32) : i32
    %169 = llvm.add %167, %168 : i32
    %170 = llvm.mlir.constant(720 : i64) : i64
    %171 = llvm.getelementptr %arg1[%170] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %169, %171 : i32, !llvm.ptr
    %172 = llvm.mlir.zero : !llvm.ptr
    %173 = llvm.mlir.constant(16 : i64) : i64
    %174 = llvm.getelementptr %arg1[%173] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %172, %174 : !llvm.ptr, !llvm.ptr
    %175 = llvm.mlir.zero : !llvm.ptr
    %176 = llvm.mlir.constant(24 : i64) : i64
    %177 = llvm.getelementptr %arg1[%176] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %175, %177 : !llvm.ptr, !llvm.ptr
    llvm.br ^bb9
  }
}

