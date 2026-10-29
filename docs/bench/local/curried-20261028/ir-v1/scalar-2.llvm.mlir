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
  ^bb1:  // 3 preds: ^bb0, ^bb15, ^bb16
    %0 = llvm.mlir.constant(0 : i64) : i64
    llvm.return %0 : i64
  ^bb2:  // 3 preds: ^bb0, ^bb15, ^bb17
    %1 = llvm.mlir.constant(1 : i64) : i64
    llvm.return %1 : i64
  ^bb3:  // 5 preds: ^bb0, ^bb14, ^bb21, ^bb24, ^bb39
    %2 = llvm.mlir.constant(3 : i64) : i64
    llvm.return %2 : i64
  ^bb4:  // 2 preds: ^bb0, ^bb40
    %3 = llvm.mlir.constant(8 : i64) : i64
    %4 = llvm.getelementptr %arg1[%3] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %5 = llvm.load %4 : !llvm.ptr -> !llvm.ptr
    %6 = llvm.mlir.zero : !llvm.ptr
    %7 = llvm.icmp "eq" %5, %6 : !llvm.ptr
    llvm.cond_br %7, ^bb12, ^bb13
  ^bb5:  // 2 preds: ^bb0, ^bb28
    %8 = llvm.mlir.constant(712 : i64) : i64
    %9 = llvm.getelementptr %arg1[%8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %10 = llvm.load %9 : !llvm.ptr -> i32
    %11 = llvm.mlir.constant(716 : i64) : i64
    %12 = llvm.getelementptr %arg1[%11] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %13 = llvm.load %12 : !llvm.ptr -> i32
    %14 = llvm.mlir.constant(1 : i32) : i32
    %15 = llvm.icmp "eq" %10, %14 : i32
    %16 = llvm.mlir.constant(1 : i32) : i32
    %17 = llvm.icmp "eq" %13, %16 : i32
    %18 = llvm.and %15, %17 : i1
    llvm.cond_br %18, ^bb16, ^bb11
  ^bb6:  // 3 preds: ^bb0, ^bb20, ^bb23
    %19 = llvm.mlir.constant(712 : i64) : i64
    %20 = llvm.getelementptr %arg1[%19] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %21 = llvm.load %20 : !llvm.ptr -> i32
    %22 = llvm.mlir.constant(716 : i64) : i64
    %23 = llvm.getelementptr %arg1[%22] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %24 = llvm.load %23 : !llvm.ptr -> i32
    %25 = llvm.mlir.constant(1 : i32) : i32
    %26 = llvm.icmp "eq" %21, %25 : i32
    %27 = llvm.mlir.constant(1 : i32) : i32
    %28 = llvm.icmp "eq" %24, %27 : i32
    %29 = llvm.and %26, %28 : i1
    llvm.cond_br %29, ^bb17, ^bb11
  ^bb7:  // 2 preds: ^bb0, ^bb28
    %30 = llvm.mlir.constant(24 : i64) : i64
    %31 = llvm.getelementptr %arg1[%30] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %32 = llvm.load %31 : !llvm.ptr -> !llvm.ptr
    %33 = llvm.mlir.zero : !llvm.ptr
    %34 = llvm.icmp "eq" %32, %33 : !llvm.ptr
    llvm.cond_br %34, ^bb18, ^bb19
  ^bb8:  // 2 preds: ^bb0, ^bb36
    %35 = llvm.mlir.constant(24 : i64) : i64
    %36 = llvm.getelementptr %arg1[%35] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %37 = llvm.load %36 : !llvm.ptr -> !llvm.ptr
    %38 = llvm.mlir.zero : !llvm.ptr
    %39 = llvm.icmp "eq" %37, %38 : !llvm.ptr
    llvm.cond_br %39, ^bb26, ^bb27
  ^bb9:  // 2 preds: ^bb0, ^bb40
    %40 = llvm.mlir.constant(16 : i64) : i64
    %41 = llvm.getelementptr %arg1[%40] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %42 = llvm.load %41 : !llvm.ptr -> !llvm.ptr
    %43 = llvm.mlir.zero : !llvm.ptr
    %44 = llvm.icmp "eq" %42, %43 : !llvm.ptr
    llvm.cond_br %44, ^bb29, ^bb30
  ^bb10:  // 2 preds: ^bb0, ^bb0
    %45 = llvm.mlir.constant(0 : i64) : i64
    %46 = llvm.getelementptr %arg1[%45] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %47 = llvm.load %46 : !llvm.ptr -> !llvm.ptr
    %48 = llvm.mlir.zero : !llvm.ptr
    %49 = llvm.icmp "eq" %47, %48 : !llvm.ptr
    llvm.cond_br %49, ^bb37, ^bb38
  ^bb11:  // 4 preds: ^bb0, ^bb5, ^bb6, ^bb33
    %50 = llvm.mlir.constant(4 : i64) : i64
    llvm.return %50 : i64
  ^bb12:  // 2 preds: ^bb4, ^bb13
    %51 = llvm.mlir.constant(26 : i64) : i64
    llvm.return %51 : i64
  ^bb13:  // pred: ^bb4
    %52 = llvm.mlir.constant(0 : i64) : i64
    %53 = llvm.getelementptr %5[%52] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %54 = llvm.load %53 : !llvm.ptr -> i8
    %55 = llvm.mlir.constant(2 : i8) : i8
    %56 = llvm.icmp "ule" %54, %55 : i8
    llvm.cond_br %56, ^bb12, ^bb14
  ^bb14:  // pred: ^bb13
    %57 = llvm.mlir.constant(5 : i8) : i8
    %58 = llvm.icmp "eq" %54, %57 : i8
    llvm.cond_br %58, ^bb15, ^bb3
  ^bb15:  // pred: ^bb14
    %59 = llvm.mlir.constant(8 : i64) : i64
    %60 = llvm.getelementptr %5[%59] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %61 = llvm.load %60 : !llvm.ptr -> i8
    %62 = llvm.mlir.constant(0 : i8) : i8
    %63 = llvm.icmp "ne" %61, %62 : i8
    llvm.cond_br %63, ^bb1, ^bb2
  ^bb16:  // pred: ^bb5
    %64 = llvm.mlir.constant(0 : i8) : i8
    %65 = llvm.mlir.constant(641 : i64) : i64
    %66 = llvm.getelementptr %arg1[%65] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %64, %66 : i8, !llvm.ptr
    %67 = llvm.mlir.constant(0 : i32) : i32
    %68 = llvm.mlir.constant(716 : i64) : i64
    %69 = llvm.getelementptr %arg1[%68] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %67, %69 : i32, !llvm.ptr
    %70 = llvm.mlir.constant(1 : i32) : i32
    %71 = llvm.sub %10, %70 : i32
    %72 = llvm.mlir.constant(712 : i64) : i64
    %73 = llvm.getelementptr %arg1[%72] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %71, %73 : i32, !llvm.ptr
    llvm.br ^bb1
  ^bb17:  // pred: ^bb6
    %74 = llvm.mlir.constant(0 : i8) : i8
    %75 = llvm.mlir.constant(641 : i64) : i64
    %76 = llvm.getelementptr %arg1[%75] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %74, %76 : i8, !llvm.ptr
    %77 = llvm.mlir.constant(0 : i32) : i32
    %78 = llvm.mlir.constant(716 : i64) : i64
    %79 = llvm.getelementptr %arg1[%78] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %77, %79 : i32, !llvm.ptr
    %80 = llvm.mlir.constant(1 : i32) : i32
    %81 = llvm.sub %21, %80 : i32
    %82 = llvm.mlir.constant(712 : i64) : i64
    %83 = llvm.getelementptr %arg1[%82] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %81, %83 : i32, !llvm.ptr
    llvm.br ^bb2
  ^bb18:  // 2 preds: ^bb7, ^bb19
    %84 = llvm.mlir.constant(50 : i64) : i64
    llvm.return %84 : i64
  ^bb19:  // pred: ^bb7
    %85 = llvm.mlir.constant(0 : i64) : i64
    %86 = llvm.getelementptr %32[%85] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %87 = llvm.load %86 : !llvm.ptr -> i8
    %88 = llvm.mlir.constant(2 : i8) : i8
    %89 = llvm.icmp "ule" %87, %88 : i8
    llvm.cond_br %89, ^bb18, ^bb20
  ^bb20:  // pred: ^bb19
    %90 = llvm.mlir.constant(9 : i8) : i8
    %91 = llvm.icmp "eq" %87, %90 : i8
    llvm.cond_br %91, ^bb21, ^bb6
  ^bb21:  // pred: ^bb20
    %92 = llvm.mlir.constant(8 : i64) : i64
    %93 = llvm.getelementptr %32[%92] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %94 = llvm.load %93 : !llvm.ptr -> !llvm.ptr
    %95 = llvm.mlir.constant(0 : i64) : i64
    %96 = llvm.getelementptr %94[%95] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %97 = llvm.load %96 : !llvm.ptr -> i32
    %98 = llvm.mlir.constant(-1 : i32) : i32
    %99 = llvm.icmp "eq" %97, %98 : i32
    llvm.cond_br %99, ^bb3, ^bb22
  ^bb22:  // pred: ^bb21
    %100 = llvm.zext %97 : i32 to i64
    %101 = llvm.mlir.constant(0 : i64) : i64
    llvm.br ^bb23(%101, %100 : i64, i64)
  ^bb23(%102: i64, %103: i64):  // 2 preds: ^bb22, ^bb25
    %104 = llvm.icmp "ult" %102, %103 : i64
    llvm.cond_br %104, ^bb24, ^bb6
  ^bb24:  // pred: ^bb23
    %105 = llvm.add %102, %103 : i64
    %106 = llvm.mlir.constant(1 : i64) : i64
    %107 = llvm.lshr %105, %106 : i64
    %108 = llvm.mlir.constant(16 : i64) : i64
    %109 = llvm.mlir.constant(16 : i64) : i64
    %110 = llvm.mul %107, %109 : i64
    %111 = llvm.add %110, %108 : i64
    %112 = llvm.getelementptr %94[%111] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %113 = llvm.load %112 : !llvm.ptr -> i32
    %114 = llvm.mlir.constant(5 : i32) : i32
    %115 = llvm.icmp "eq" %113, %114 : i32
    llvm.cond_br %115, ^bb3, ^bb25
  ^bb25:  // pred: ^bb24
    %116 = llvm.mlir.constant(5 : i32) : i32
    %117 = llvm.icmp "ult" %113, %116 : i32
    %118 = llvm.mlir.constant(1 : i64) : i64
    %119 = llvm.add %107, %118 : i64
    %120 = llvm.select %117, %119, %102 : i1, i64
    %121 = llvm.select %117, %103, %107 : i1, i64
    llvm.br ^bb23(%120, %121 : i64, i64)
  ^bb26:  // 2 preds: ^bb8, ^bb27
    %122 = llvm.mlir.constant(58 : i64) : i64
    llvm.return %122 : i64
  ^bb27:  // pred: ^bb8
    %123 = llvm.mlir.constant(0 : i64) : i64
    %124 = llvm.getelementptr %37[%123] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %125 = llvm.load %124 : !llvm.ptr -> i8
    %126 = llvm.mlir.constant(2 : i8) : i8
    %127 = llvm.icmp "ule" %125, %126 : i8
    llvm.cond_br %127, ^bb26, ^bb28
  ^bb28:  // pred: ^bb27
    %128 = llvm.mlir.constant(11 : i8) : i8
    %129 = llvm.icmp "eq" %125, %128 : i8
    %130 = llvm.mlir.constant(12 : i8) : i8
    %131 = llvm.icmp "eq" %125, %130 : i8
    %132 = llvm.mlir.constant(13 : i8) : i8
    %133 = llvm.icmp "eq" %125, %132 : i8
    %134 = llvm.or %131, %133 : i1
    %135 = llvm.or %129, %134 : i1
    llvm.cond_br %135, ^bb5, ^bb7
  ^bb29:  // pred: ^bb9
    %136 = llvm.mlir.constant(66 : i64) : i64
    llvm.return %136 : i64
  ^bb30:  // pred: ^bb9
    %137 = llvm.mlir.constant(0 : i64) : i64
    %138 = llvm.getelementptr %42[%137] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %139 = llvm.load %138 : !llvm.ptr -> i8
    %140 = llvm.mlir.constant(11 : i8) : i8
    %141 = llvm.icmp "eq" %139, %140 : i8
    llvm.cond_br %141, ^bb31, ^bb32
  ^bb31:  // pred: ^bb30
    %142 = llvm.mlir.constant(8 : i64) : i64
    %143 = llvm.getelementptr %42[%142] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %144 = llvm.load %143 : !llvm.ptr -> !llvm.ptr
    %145 = llvm.mlir.constant(5366731072 : i64) : i64
    %146 = llvm.inttoptr %145 : i64 to !llvm.ptr
    %147 = llvm.icmp "eq" %144, %146 : !llvm.ptr
    llvm.cond_br %147, ^bb33, ^bb32
  ^bb32:  // 2 preds: ^bb30, ^bb31
    %148 = llvm.mlir.constant(71 : i64) : i64
    llvm.return %148 : i64
  ^bb33:  // pred: ^bb31
    %149 = llvm.mlir.constant(712 : i64) : i64
    %150 = llvm.getelementptr %arg1[%149] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %151 = llvm.load %150 : !llvm.ptr -> i32
    %152 = llvm.mlir.constant(716 : i64) : i64
    %153 = llvm.getelementptr %arg1[%152] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %154 = llvm.load %153 : !llvm.ptr -> i32
    %155 = llvm.mlir.constant(640 : i64) : i64
    %156 = llvm.getelementptr %arg1[%155] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %157 = llvm.load %156 : !llvm.ptr -> i8
    %158 = llvm.mlir.constant(0 : i32) : i32
    %159 = llvm.icmp "eq" %151, %158 : i32
    %160 = llvm.mlir.constant(0 : i32) : i32
    %161 = llvm.icmp "eq" %154, %160 : i32
    %162 = llvm.and %159, %161 : i1
    %163 = llvm.mlir.constant(0 : i8) : i8
    %164 = llvm.icmp "ne" %157, %163 : i8
    %165 = llvm.and %162, %164 : i1
    llvm.cond_br %165, ^bb34, ^bb11
  ^bb34:  // pred: ^bb33
    %166 = llvm.mlir.constant(704 : i64) : i64
    %167 = llvm.getelementptr %arg1[%166] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %168 = llvm.load %167 : !llvm.ptr -> i32
    %169 = llvm.mlir.constant(708 : i64) : i64
    %170 = llvm.getelementptr %arg1[%169] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %171 = llvm.load %170 : !llvm.ptr -> i32
    %172 = llvm.zext %168 : i32 to i64
    %173 = llvm.zext %151 : i32 to i64
    %174 = llvm.add %172, %173 : i64
    %175 = llvm.zext %171 : i32 to i64
    %176 = llvm.icmp "uge" %174, %175 : i64
    llvm.cond_br %176, ^bb35, ^bb36
  ^bb35:  // pred: ^bb34
    %177 = llvm.mlir.constant(69 : i64) : i64
    llvm.return %177 : i64
  ^bb36:  // pred: ^bb34
    %178 = llvm.mlir.constant(16 : i64) : i64
    %179 = llvm.getelementptr %42[%178] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %180 = llvm.load %179 : !llvm.ptr -> !llvm.ptr
    %181 = llvm.mlir.constant(136 : i64) : i64
    %182 = llvm.getelementptr %arg1[%181] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %180, %182 : !llvm.ptr, !llvm.ptr
    %183 = llvm.mlir.constant(1 : i8) : i8
    %184 = llvm.mlir.constant(641 : i64) : i64
    %185 = llvm.getelementptr %arg1[%184] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %183, %185 : i8, !llvm.ptr
    %186 = llvm.mlir.constant(1 : i32) : i32
    %187 = llvm.mlir.constant(716 : i64) : i64
    %188 = llvm.getelementptr %arg1[%187] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %186, %188 : i32, !llvm.ptr
    %189 = llvm.mlir.constant(1 : i32) : i32
    %190 = llvm.add %151, %189 : i32
    %191 = llvm.mlir.constant(712 : i64) : i64
    %192 = llvm.getelementptr %arg1[%191] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %190, %192 : i32, !llvm.ptr
    %193 = llvm.mlir.constant(720 : i64) : i64
    %194 = llvm.getelementptr %arg1[%193] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %195 = llvm.load %194 : !llvm.ptr -> i32
    %196 = llvm.mlir.constant(1 : i32) : i32
    %197 = llvm.add %195, %196 : i32
    %198 = llvm.mlir.constant(720 : i64) : i64
    %199 = llvm.getelementptr %arg1[%198] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %197, %199 : i32, !llvm.ptr
    llvm.br ^bb8
  ^bb37:  // 2 preds: ^bb10, ^bb38
    %200 = llvm.mlir.constant(74 : i64) : i64
    llvm.return %200 : i64
  ^bb38:  // pred: ^bb10
    %201 = llvm.mlir.constant(0 : i64) : i64
    %202 = llvm.getelementptr %47[%201] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %203 = llvm.load %202 : !llvm.ptr -> i8
    %204 = llvm.mlir.constant(2 : i8) : i8
    %205 = llvm.icmp "ule" %203, %204 : i8
    llvm.cond_br %205, ^bb37, ^bb39
  ^bb39:  // pred: ^bb38
    %206 = llvm.mlir.constant(5 : i8) : i8
    %207 = llvm.icmp "eq" %203, %206 : i8
    llvm.cond_br %207, ^bb40, ^bb3
  ^bb40:  // pred: ^bb39
    %208 = llvm.mlir.constant(8 : i64) : i64
    %209 = llvm.getelementptr %47[%208] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %210 = llvm.load %209 : !llvm.ptr -> i8
    %211 = llvm.mlir.constant(0 : i8) : i8
    %212 = llvm.icmp "ne" %210, %211 : i8
    llvm.cond_br %212, ^bb4, ^bb9
  }
}

