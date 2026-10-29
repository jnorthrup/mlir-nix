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
  ^bb3:  // 2 preds: ^bb0, ^bb24
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
  ^bb6:  // 3 preds: ^bb0, ^bb18, ^bb21
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
  ^bb7:  // 2 preds: ^bb0, ^bb25
    %36 = llvm.mlir.constant(24 : i64) : i64
    %37 = llvm.getelementptr %arg1[%36] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %38 = llvm.load %37 : !llvm.ptr -> !llvm.ptr
    %39 = llvm.mlir.zero : !llvm.ptr
    %40 = llvm.icmp "eq" %38, %39 : !llvm.ptr
    llvm.cond_br %40, ^bb16, ^bb17
  ^bb8:  // 2 preds: ^bb0, ^bb25
    %41 = llvm.mlir.constant(32 : i64) : i64
    %42 = llvm.getelementptr %arg1[%41] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %43 = llvm.load %42 : !llvm.ptr -> !llvm.ptr
    %44 = llvm.mlir.zero : !llvm.ptr
    %45 = llvm.icmp "eq" %43, %44 : !llvm.ptr
    llvm.cond_br %45, ^bb19, ^bb20
  ^bb9:  // 2 preds: ^bb0, ^bb33
    %46 = llvm.mlir.constant(16 : i64) : i64
    %47 = llvm.getelementptr %arg1[%46] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %48 = llvm.load %47 : !llvm.ptr -> !llvm.ptr
    %49 = llvm.mlir.zero : !llvm.ptr
    %50 = llvm.icmp "eq" %48, %49 : !llvm.ptr
    llvm.cond_br %50, ^bb22, ^bb23
  ^bb10:  // 2 preds: ^bb0, ^bb0
    %51 = llvm.mlir.constant(0 : i64) : i64
    %52 = llvm.getelementptr %arg1[%51] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %53 = llvm.load %52 : !llvm.ptr -> !llvm.ptr
    %54 = llvm.mlir.zero : !llvm.ptr
    %55 = llvm.icmp "eq" %53, %54 : !llvm.ptr
    llvm.cond_br %55, ^bb26, ^bb27
  ^bb11:  // 5 preds: ^bb0, ^bb4, ^bb5, ^bb6, ^bb30
    %56 = llvm.mlir.constant(4 : i64) : i64
    llvm.return %56 : i64
  ^bb12:  // pred: ^bb15
    %57 = llvm.mlir.constant(6 : i64) : i64
    llvm.return %57 : i64
  ^bb13:  // pred: ^bb4
    %58 = llvm.mlir.constant(0 : i8) : i8
    %59 = llvm.mlir.constant(641 : i64) : i64
    %60 = llvm.getelementptr %arg1[%59] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %58, %60 : i8, !llvm.ptr
    %61 = llvm.mlir.constant(0 : i32) : i32
    %62 = llvm.mlir.constant(716 : i64) : i64
    %63 = llvm.getelementptr %arg1[%62] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %61, %63 : i32, !llvm.ptr
    %64 = llvm.mlir.constant(1 : i32) : i32
    %65 = llvm.sub %5, %64 : i32
    %66 = llvm.mlir.constant(712 : i64) : i64
    %67 = llvm.getelementptr %arg1[%66] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %65, %67 : i32, !llvm.ptr
    llvm.br ^bb2
  ^bb14:  // pred: ^bb5
    %68 = llvm.mlir.constant(0 : i8) : i8
    %69 = llvm.mlir.constant(641 : i64) : i64
    %70 = llvm.getelementptr %arg1[%69] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %68, %70 : i8, !llvm.ptr
    %71 = llvm.mlir.constant(0 : i32) : i32
    %72 = llvm.mlir.constant(716 : i64) : i64
    %73 = llvm.getelementptr %arg1[%72] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %71, %73 : i32, !llvm.ptr
    %74 = llvm.mlir.constant(1 : i32) : i32
    %75 = llvm.sub %16, %74 : i32
    %76 = llvm.mlir.constant(712 : i64) : i64
    %77 = llvm.getelementptr %arg1[%76] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %75, %77 : i32, !llvm.ptr
    llvm.br ^bb1
  ^bb15:  // pred: ^bb6
    %78 = llvm.mlir.constant(0 : i8) : i8
    %79 = llvm.mlir.constant(641 : i64) : i64
    %80 = llvm.getelementptr %arg1[%79] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %78, %80 : i8, !llvm.ptr
    %81 = llvm.mlir.constant(0 : i32) : i32
    %82 = llvm.mlir.constant(716 : i64) : i64
    %83 = llvm.getelementptr %arg1[%82] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %81, %83 : i32, !llvm.ptr
    %84 = llvm.mlir.constant(1 : i32) : i32
    %85 = llvm.sub %27, %84 : i32
    %86 = llvm.mlir.constant(712 : i64) : i64
    %87 = llvm.getelementptr %arg1[%86] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %85, %87 : i32, !llvm.ptr
    llvm.br ^bb12
  ^bb16:  // 2 preds: ^bb7, ^bb17
    %88 = llvm.mlir.constant(50 : i64) : i64
    llvm.return %88 : i64
  ^bb17:  // pred: ^bb7
    %89 = llvm.mlir.constant(0 : i64) : i64
    %90 = llvm.getelementptr %38[%89] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %91 = llvm.load %90 : !llvm.ptr -> i8
    %92 = llvm.mlir.constant(2 : i8) : i8
    %93 = llvm.icmp "ule" %91, %92 : i8
    llvm.cond_br %93, ^bb16, ^bb18
  ^bb18:  // pred: ^bb17
    %94 = llvm.mlir.constant(3 : i32) : i32
    %95 = llvm.mlir.constant(728 : i64) : i64
    %96 = llvm.getelementptr %arg1[%95] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %94, %96 : i32, !llvm.ptr
    llvm.br ^bb6
  ^bb19:  // 2 preds: ^bb8, ^bb20
    %97 = llvm.mlir.constant(58 : i64) : i64
    llvm.return %97 : i64
  ^bb20:  // pred: ^bb8
    %98 = llvm.mlir.constant(0 : i64) : i64
    %99 = llvm.getelementptr %43[%98] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %100 = llvm.load %99 : !llvm.ptr -> i8
    %101 = llvm.mlir.constant(2 : i8) : i8
    %102 = llvm.icmp "ule" %100, %101 : i8
    llvm.cond_br %102, ^bb19, ^bb21
  ^bb21:  // pred: ^bb20
    %103 = llvm.mlir.constant(4 : i32) : i32
    %104 = llvm.mlir.constant(728 : i64) : i64
    %105 = llvm.getelementptr %arg1[%104] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %103, %105 : i32, !llvm.ptr
    llvm.br ^bb6
  ^bb22:  // 2 preds: ^bb9, ^bb23
    %106 = llvm.mlir.constant(66 : i64) : i64
    llvm.return %106 : i64
  ^bb23:  // pred: ^bb9
    %107 = llvm.mlir.constant(0 : i64) : i64
    %108 = llvm.getelementptr %48[%107] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %109 = llvm.load %108 : !llvm.ptr -> i8
    %110 = llvm.mlir.constant(2 : i8) : i8
    %111 = llvm.icmp "ule" %109, %110 : i8
    llvm.cond_br %111, ^bb22, ^bb24
  ^bb24:  // pred: ^bb23
    %112 = llvm.mlir.constant(5 : i8) : i8
    %113 = llvm.icmp "eq" %109, %112 : i8
    llvm.cond_br %113, ^bb25, ^bb3
  ^bb25:  // pred: ^bb24
    %114 = llvm.mlir.constant(8 : i64) : i64
    %115 = llvm.getelementptr %48[%114] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %116 = llvm.load %115 : !llvm.ptr -> i8
    %117 = llvm.mlir.constant(0 : i8) : i8
    %118 = llvm.icmp "ne" %116, %117 : i8
    llvm.cond_br %118, ^bb7, ^bb8
  ^bb26:  // pred: ^bb10
    %119 = llvm.mlir.constant(74 : i64) : i64
    llvm.return %119 : i64
  ^bb27:  // pred: ^bb10
    %120 = llvm.mlir.constant(0 : i64) : i64
    %121 = llvm.getelementptr %53[%120] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %122 = llvm.load %121 : !llvm.ptr -> i8
    %123 = llvm.mlir.constant(11 : i8) : i8
    %124 = llvm.icmp "eq" %122, %123 : i8
    llvm.cond_br %124, ^bb28, ^bb29
  ^bb28:  // pred: ^bb27
    %125 = llvm.mlir.constant(8 : i64) : i64
    %126 = llvm.getelementptr %53[%125] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %127 = llvm.load %126 : !llvm.ptr -> !llvm.ptr
    %128 = llvm.mlir.constant(5417056880 : i64) : i64
    %129 = llvm.inttoptr %128 : i64 to !llvm.ptr
    %130 = llvm.icmp "eq" %127, %129 : !llvm.ptr
    llvm.cond_br %130, ^bb30, ^bb29
  ^bb29:  // 2 preds: ^bb27, ^bb28
    %131 = llvm.mlir.constant(79 : i64) : i64
    llvm.return %131 : i64
  ^bb30:  // pred: ^bb28
    %132 = llvm.mlir.constant(712 : i64) : i64
    %133 = llvm.getelementptr %arg1[%132] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %134 = llvm.load %133 : !llvm.ptr -> i32
    %135 = llvm.mlir.constant(716 : i64) : i64
    %136 = llvm.getelementptr %arg1[%135] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %137 = llvm.load %136 : !llvm.ptr -> i32
    %138 = llvm.mlir.constant(640 : i64) : i64
    %139 = llvm.getelementptr %arg1[%138] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %140 = llvm.load %139 : !llvm.ptr -> i8
    %141 = llvm.mlir.constant(0 : i32) : i32
    %142 = llvm.icmp "eq" %134, %141 : i32
    %143 = llvm.mlir.constant(0 : i32) : i32
    %144 = llvm.icmp "eq" %137, %143 : i32
    %145 = llvm.and %142, %144 : i1
    %146 = llvm.mlir.constant(0 : i8) : i8
    %147 = llvm.icmp "ne" %140, %146 : i8
    %148 = llvm.and %145, %147 : i1
    llvm.cond_br %148, ^bb31, ^bb11
  ^bb31:  // pred: ^bb30
    %149 = llvm.mlir.constant(704 : i64) : i64
    %150 = llvm.getelementptr %arg1[%149] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %151 = llvm.load %150 : !llvm.ptr -> i32
    %152 = llvm.mlir.constant(708 : i64) : i64
    %153 = llvm.getelementptr %arg1[%152] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %154 = llvm.load %153 : !llvm.ptr -> i32
    %155 = llvm.zext %151 : i32 to i64
    %156 = llvm.zext %134 : i32 to i64
    %157 = llvm.add %155, %156 : i64
    %158 = llvm.zext %154 : i32 to i64
    %159 = llvm.icmp "uge" %157, %158 : i64
    llvm.cond_br %159, ^bb32, ^bb33
  ^bb32:  // pred: ^bb31
    %160 = llvm.mlir.constant(77 : i64) : i64
    llvm.return %160 : i64
  ^bb33:  // pred: ^bb31
    %161 = llvm.mlir.constant(16 : i64) : i64
    %162 = llvm.getelementptr %53[%161] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %163 = llvm.load %162 : !llvm.ptr -> !llvm.ptr
    %164 = llvm.mlir.constant(136 : i64) : i64
    %165 = llvm.getelementptr %arg1[%164] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %163, %165 : !llvm.ptr, !llvm.ptr
    %166 = llvm.mlir.constant(1 : i8) : i8
    %167 = llvm.mlir.constant(641 : i64) : i64
    %168 = llvm.getelementptr %arg1[%167] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %166, %168 : i8, !llvm.ptr
    %169 = llvm.mlir.constant(1 : i32) : i32
    %170 = llvm.mlir.constant(716 : i64) : i64
    %171 = llvm.getelementptr %arg1[%170] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %169, %171 : i32, !llvm.ptr
    %172 = llvm.mlir.constant(1 : i32) : i32
    %173 = llvm.add %134, %172 : i32
    %174 = llvm.mlir.constant(712 : i64) : i64
    %175 = llvm.getelementptr %arg1[%174] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %173, %175 : i32, !llvm.ptr
    %176 = llvm.mlir.constant(720 : i64) : i64
    %177 = llvm.getelementptr %arg1[%176] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %178 = llvm.load %177 : !llvm.ptr -> i32
    %179 = llvm.mlir.constant(1 : i32) : i32
    %180 = llvm.add %178, %179 : i32
    %181 = llvm.mlir.constant(720 : i64) : i64
    %182 = llvm.getelementptr %arg1[%181] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %180, %182 : i32, !llvm.ptr
    %183 = llvm.mlir.zero : !llvm.ptr
    %184 = llvm.mlir.constant(16 : i64) : i64
    %185 = llvm.getelementptr %arg1[%184] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %183, %185 : !llvm.ptr, !llvm.ptr
    %186 = llvm.mlir.zero : !llvm.ptr
    %187 = llvm.mlir.constant(24 : i64) : i64
    %188 = llvm.getelementptr %arg1[%187] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %186, %188 : !llvm.ptr, !llvm.ptr
    %189 = llvm.mlir.zero : !llvm.ptr
    %190 = llvm.mlir.constant(32 : i64) : i64
    %191 = llvm.getelementptr %arg1[%190] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %189, %191 : !llvm.ptr, !llvm.ptr
    llvm.br ^bb9
  }
}

