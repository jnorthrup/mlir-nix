// Kursive's walk (include/Composite/Kursive.h detail::walk) hollowed into MLIR: the backtracking state machine over a
// compiled pattern's Step program, as libstdc++'s std::regex::extended executor answers (Nix on Linux).  One flat
// scf.while carries (sp, pc, pos, bestEnd, found, mode, ret): mode 0 dispatches the step at pc, mode 1 rewinds the
// checkpoint stack.  The caller owns every array (caps/best marks, loop states, the Entry stack); the walk allocates
// nothing.  The bridge (Kursive.h) keeps the primop forcing/coercion, the checkpoint-retry (kursiveRun), pieceOf
// interning and Nix's error wording.  Step is 16B (op u8@0, x/y/z u32@4/8/12) read as 4 i32 words; Set is 4 u64;
// LoopState 2 u32 (pos,count); Entry 3 u32 (tag,a,b).  Helpers are module-unique (kw_*).
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>
!m32 = memref<?xi32, strided<[1], offset: ?>>
!m64 = memref<?xi64, strided<[1], offset: ?>>
!m8 = memref<?xi8, strided<[1], offset: ?>>

func.func private @kw_desc(%p: !llvm.ptr, %n: i64) -> !d {
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

func.func @mlnix_kursive_walk(%steps: !llvm.ptr, %sets: !llvm.ptr, %groups: i32, %nloops: i32,
    %text: !llvm.ptr, %n: i32, %start: i32, %exact: i32, %notNull: i32,
    %caps: !llvm.ptr, %best: !llvm.ptr, %loopArr: !llvm.ptr, %stack: !llvm.ptr,
    %cap: i32, %budget: !llvm.ptr) -> i32 {
  %c1 = arith.constant 0 : i32
  %c2 = arith.constant 1 : i32
  %c3 = arith.constant 2 : i32
  %c4 = arith.constant 4 : i32
  %c5 = arith.constant -1 : i32
  %c6 = arith.constant 0 : i64
  %c7 = arith.constant 0 : index
  %c8 = arith.constant 1 : index
  %c30 = arith.constant 2 : index
  %c35 = arith.constant 3 : i32
  %c36 = arith.constant 1 : i64
  %c43 = arith.constant 4 : index
  %c51 = arith.constant 3 : index
  %c54 = arith.constant 0 : i8
  %c56 = arith.constant 6 : i32
  %c57 = arith.constant 63 : i32
  %c73 = arith.constant 0 : i1
  %c80 = arith.constant 1 : i8
  %c90 = arith.constant 2 : i8
  %c92 = arith.constant 536870912 : i32
  %c93 = arith.constant 1073741824 : i32
  %c124 = arith.constant 3 : i8
  %c127 = arith.constant 4 : i8
  %c129 = arith.constant 805306368 : i32
  %c142 = arith.constant 5 : i8
  %c149 = arith.constant 6 : i8
  %c156 = arith.constant 7 : i8
  %c158 = arith.constant 1 : i1
  %c182 = arith.constant 28 : i32
  %c183 = arith.constant 268435455 : i32
  %c220 = arith.constant 268435456 : i32
  %d9 = func.call @kw_desc(%steps, %c6) : (!llvm.ptr, i64) -> !d
  %stepsM10 = builtin.unrealized_conversion_cast %d9 : !d to !m32
  %d11 = func.call @kw_desc(%sets, %c6) : (!llvm.ptr, i64) -> !d
  %setsM12 = builtin.unrealized_conversion_cast %d11 : !d to !m64
  %d13 = func.call @kw_desc(%text, %c6) : (!llvm.ptr, i64) -> !d
  %textM14 = builtin.unrealized_conversion_cast %d13 : !d to !m8
  %d15 = func.call @kw_desc(%caps, %c6) : (!llvm.ptr, i64) -> !d
  %capsM16 = builtin.unrealized_conversion_cast %d15 : !d to !m32
  %d17 = func.call @kw_desc(%best, %c6) : (!llvm.ptr, i64) -> !d
  %bestM18 = builtin.unrealized_conversion_cast %d17 : !d to !m32
  %d19 = func.call @kw_desc(%loopArr, %c6) : (!llvm.ptr, i64) -> !d
  %loopM20 = builtin.unrealized_conversion_cast %d19 : !d to !m32
  %d21 = func.call @kw_desc(%stack, %c6) : (!llvm.ptr, i64) -> !d
  %stackM22 = builtin.unrealized_conversion_cast %d21 : !d to !m32
  %d23 = func.call @kw_desc(%budget, %c6) : (!llvm.ptr, i64) -> !d
  %budgetM24 = builtin.unrealized_conversion_cast %d23 : !d to !m64
  %g125 = arith.addi %groups, %c2 : i32
  %slots26 = arith.muli %g125, %c3 : i32
  %ix27 = arith.index_cast %slots26 : i32 to index
  %ix28 = arith.index_cast %nloops : i32 to index
  scf.for %i = %c7 to %ix27 step %c8 {
    memref.store %c5, %capsM16[%i] : !m32
  }
  scf.for %i = %c7 to %ix28 step %c8 {
    %i229 = arith.muli %i, %c30 : index
    %i2p131 = arith.addi %i229, %c8 : index
    memref.store %c5, %loopM20[%i229] : !m32
    memref.store %c1, %loopM20[%i2p131] : !m32
  }
  %w:7 = scf.while (%sp = %c1, %pc = %c1, %pos = %start, %bestEnd = %c5, %found = %c1, %mode = %c1, %ret = %c5) : (i32, i32, i32, i32, i32, i32, i32) -> (i32, i32, i32, i32, i32, i32, i32) {
    %go32 = arith.cmpi eq, %ret, %c5 : i32
    scf.condition(%go32) %sp, %pc, %pos, %bestEnd, %found, %mode, %ret : i32, i32, i32, i32, i32, i32, i32
  } do {
    ^bb0(%sp: i32, %pc: i32, %pos: i32, %bestEnd: i32, %found: i32, %mode: i32, %ret: i32):
    %isDisp33 = arith.cmpi eq, %mode, %c1 : i32
    %r34:7 = scf.if %isDisp33 -> (i32, i32, i32, i32, i32, i32, i32) {
      %b37 = memref.load %budgetM24[%c7] : !m64
      %bz38 = arith.cmpi eq, %b37, %c6 : i64
      %r39:7 = scf.if %bz38 -> (i32, i32, i32, i32, i32, i32, i32) {
        scf.yield %sp, %pc, %pos, %bestEnd, %found, %mode, %c3 : i32, i32, i32, i32, i32, i32, i32
      } else {
        %bm140 = arith.subi %b37, %c36 : i64
        memref.store %bm140, %budgetM24[%c7] : !m64
        %ix41 = arith.index_cast %pc : i32 to index
        %pc442 = arith.muli %ix41, %c43 : index
        %opw44 = memref.load %stepsM10[%pc442] : !m32
        %op45 = arith.trunci %opw44 : i32 to i8
        %p146 = arith.addi %pc442, %c8 : index
        %x47 = memref.load %stepsM10[%p146] : !m32
        %p248 = arith.addi %pc442, %c30 : index
        %y49 = memref.load %stepsM10[%p248] : !m32
        %p350 = arith.addi %pc442, %c51 : index
        %z52 = memref.load %stepsM10[%p350] : !m32
        %opeq53 = arith.cmpi eq, %op45, %c54 : i8
        %r55:7 = scf.if %opeq53 -> (i32, i32, i32, i32, i32, i32, i32) {
          %posLtN58 = arith.cmpi ult, %pos, %n : i32
          %rhas59 = scf.if %posLtN58 -> (i1) {
            %ix60 = arith.index_cast %pos : i32 to index
            %ch61 = memref.load %textM14[%ix60] : !m8
            %cz62 = arith.extui %ch61 : i8 to i32
            %wi63 = arith.shrui %cz62, %c56 : i32
            %bit64 = arith.andi %cz62, %c57 : i32
            %x465 = arith.muli %x47, %c4 : i32
            %si66 = arith.addi %x465, %wi63 : i32
            %ix67 = arith.index_cast %si66 : i32 to index
            %w68 = memref.load %setsM12[%ix67] : !m64
            %bit6469 = arith.extui %bit64 : i32 to i64
            %sh70 = arith.shrui %w68, %bit6469 : i64
            %has71 = arith.andi %sh70, %c36 : i64
            %hasb72 = arith.cmpi ne, %has71, %c6 : i64
            scf.yield %hasb72 : i1
          } else {
            scf.yield %c73 : i1
          }
          %pc174 = arith.addi %pc, %c2 : i32
          %pos175 = arith.addi %pos, %c2 : i32
          %npc76 = arith.select %rhas59, %pc174, %pc : i32
          %npos77 = arith.select %rhas59, %pos175, %pos : i32
          %nmode78 = arith.select %rhas59, %c1, %c2 : i32
          scf.yield %sp, %npc76, %npos77, %bestEnd, %found, %nmode78, %c5 : i32, i32, i32, i32, i32, i32, i32
        } else {
          %opeq79 = arith.cmpi eq, %op45, %c80 : i8
          %r81:7 = scf.if %opeq79 -> (i32, i32, i32, i32, i32, i32, i32) {
            %full82 = arith.cmpi eq, %sp, %cap : i32
            %r83:7 = scf.if %full82 -> (i32, i32, i32, i32, i32, i32, i32) {
              scf.yield %sp, %pc, %pos, %bestEnd, %found, %c1, %c3 : i32, i32, i32, i32, i32, i32, i32
            } else {
              %s384 = arith.muli %sp, %c35 : i32
              %ix85 = arith.index_cast %s384 : i32 to index
              memref.store %y49, %stackM22[%ix85] : !m32
              %a186 = arith.addi %ix85, %c8 : index
              memref.store %pos, %stackM22[%a186] : !m32
              %a287 = arith.addi %ix85, %c30 : index
              memref.store %c1, %stackM22[%a287] : !m32
              %sp188 = arith.addi %sp, %c2 : i32
              scf.yield %sp188, %x47, %pos, %bestEnd, %found, %c1, %c5 : i32, i32, i32, i32, i32, i32, i32
            }
            scf.yield %r83#0, %r83#1, %r83#2, %r83#3, %r83#4, %r83#5, %r83#6 : i32, i32, i32, i32, i32, i32, i32
          } else {
            %opeq89 = arith.cmpi eq, %op45, %c90 : i8
            %r91:7 = scf.if %opeq89 -> (i32, i32, i32, i32, i32, i32, i32) {
              %z294 = arith.muli %z52, %c3 : i32
              %ix95 = arith.index_cast %z294 : i32 to index
              %z2p196 = arith.addi %ix95, %c8 : index
              %Lpos97 = memref.load %loopM20[%ix95] : !m32
              %Lcnt98 = memref.load %loopM20[%z2p196] : !m32
              %cnt099 = arith.cmpi eq, %Lcnt98, %c1 : i32
              %posNe100 = arith.cmpi ne, %Lpos97, %pos : i32
              %fr101 = arith.ori %cnt099, %posNe100 : i1
              %cntLt2102 = arith.cmpi ult, %Lcnt98, %c3 : i32
              %canIter103 = arith.ori %fr101, %cntLt2102 : i1
              %r104:7 = scf.if %canIter103 -> (i32, i32, i32, i32, i32, i32, i32) {
                %sp2105 = arith.addi %sp, %c3 : i32
                %ok2106 = arith.cmpi ule, %sp2105, %cap : i32
                %r107:7 = scf.if %ok2106 -> (i32, i32, i32, i32, i32, i32, i32) {
                  %roTag108 = arith.ori %c92, %y49 : i32
                  %s3109 = arith.muli %sp, %c35 : i32
                  %ix110 = arith.index_cast %s3109 : i32 to index
                  memref.store %roTag108, %stackM22[%ix110] : !m32
                  %a1111 = arith.addi %ix110, %c8 : index
                  memref.store %pos, %stackM22[%a1111] : !m32
                  %a2112 = arith.addi %ix110, %c30 : index
                  memref.store %c1, %stackM22[%a2112] : !m32
                  %sp1113 = arith.addi %sp, %c2 : i32
                  %lpTag114 = arith.ori %c93, %z52 : i32
                  %s3115 = arith.muli %sp1113, %c35 : i32
                  %ix116 = arith.index_cast %s3115 : i32 to index
                  memref.store %lpTag114, %stackM22[%ix116] : !m32
                  %a1117 = arith.addi %ix116, %c8 : index
                  memref.store %Lpos97, %stackM22[%a1117] : !m32
                  %a2118 = arith.addi %ix116, %c30 : index
                  memref.store %Lcnt98, %stackM22[%a2118] : !m32
                  scf.if %fr101 {
                    memref.store %pos, %loopM20[%ix95] : !m32
                    memref.store %c2, %loopM20[%z2p196] : !m32
                  } else {
                    %cnt1119 = arith.addi %Lcnt98, %c2 : i32
                    memref.store %cnt1119, %loopM20[%z2p196] : !m32
                  }
                  scf.yield %sp2105, %x47, %pos, %bestEnd, %found, %c1, %c5 : i32, i32, i32, i32, i32, i32, i32
                } else {
                  scf.yield %sp, %pc, %pos, %bestEnd, %found, %c1, %c3 : i32, i32, i32, i32, i32, i32, i32
                }
                scf.yield %r107#0, %r107#1, %r107#2, %r107#3, %r107#4, %r107#5, %r107#6 : i32, i32, i32, i32, i32, i32, i32
              } else {
                %foundb120 = arith.cmpi ne, %found, %c1 : i32
                %nmode121 = arith.select %foundb120, %c2, %c1 : i32
                %npc122 = arith.select %foundb120, %pc, %y49 : i32
                scf.yield %sp, %npc122, %pos, %bestEnd, %found, %nmode121, %c5 : i32, i32, i32, i32, i32, i32, i32
              }
              scf.yield %r104#0, %r104#1, %r104#2, %r104#3, %r104#4, %r104#5, %r104#6 : i32, i32, i32, i32, i32, i32, i32
            } else {
              %opeq123 = arith.cmpi eq, %op45, %c124 : i8
              %r125:7 = scf.if %opeq123 -> (i32, i32, i32, i32, i32, i32, i32) {
                scf.yield %sp, %x47, %pos, %bestEnd, %found, %c1, %c5 : i32, i32, i32, i32, i32, i32, i32
              } else {
                %opeq126 = arith.cmpi eq, %op45, %c127 : i8
                %r128:7 = scf.if %opeq126 -> (i32, i32, i32, i32, i32, i32, i32) {
                  %full130 = arith.cmpi eq, %sp, %cap : i32
                  %r131:7 = scf.if %full130 -> (i32, i32, i32, i32, i32, i32, i32) {
                    scf.yield %sp, %pc, %pos, %bestEnd, %found, %c1, %c3 : i32, i32, i32, i32, i32, i32, i32
                  } else {
                    %ix132 = arith.index_cast %x47 : i32 to index
                    %old133 = memref.load %capsM16[%ix132] : !m32
                    %capTag134 = arith.ori %c129, %x47 : i32
                    %s3135 = arith.muli %sp, %c35 : i32
                    %ix136 = arith.index_cast %s3135 : i32 to index
                    memref.store %capTag134, %stackM22[%ix136] : !m32
                    %a1137 = arith.addi %ix136, %c8 : index
                    memref.store %old133, %stackM22[%a1137] : !m32
                    %a2138 = arith.addi %ix136, %c30 : index
                    memref.store %c1, %stackM22[%a2138] : !m32
                    memref.store %pos, %capsM16[%ix132] : !m32
                    %sp1139 = arith.addi %sp, %c2 : i32
                    %pc1140 = arith.addi %pc, %c2 : i32
                    scf.yield %sp1139, %pc1140, %pos, %bestEnd, %found, %c1, %c5 : i32, i32, i32, i32, i32, i32, i32
                  }
                  scf.yield %r131#0, %r131#1, %r131#2, %r131#3, %r131#4, %r131#5, %r131#6 : i32, i32, i32, i32, i32, i32, i32
                } else {
                  %opeq141 = arith.cmpi eq, %op45, %c142 : i8
                  %r143:7 = scf.if %opeq141 -> (i32, i32, i32, i32, i32, i32, i32) {
                    %at0144 = arith.cmpi eq, %pos, %c1 : i32
                    %pc1145 = arith.addi %pc, %c2 : i32
                    %npc146 = arith.select %at0144, %pc1145, %pc : i32
                    %nmode147 = arith.select %at0144, %c1, %c2 : i32
                    scf.yield %sp, %npc146, %pos, %bestEnd, %found, %nmode147, %c5 : i32, i32, i32, i32, i32, i32, i32
                  } else {
                    %opeq148 = arith.cmpi eq, %op45, %c149 : i8
                    %r150:7 = scf.if %opeq148 -> (i32, i32, i32, i32, i32, i32, i32) {
                      %atN151 = arith.cmpi eq, %pos, %n : i32
                      %pc1152 = arith.addi %pc, %c2 : i32
                      %npc153 = arith.select %atN151, %pc1152, %pc : i32
                      %nmode154 = arith.select %atN151, %c1, %c2 : i32
                      scf.yield %sp, %npc153, %pos, %bestEnd, %found, %nmode154, %c5 : i32, i32, i32, i32, i32, i32, i32
                    } else {
                      %opeq155 = arith.cmpi eq, %op45, %c156 : i8
                      %r157:7 = scf.if %opeq155 -> (i32, i32, i32, i32, i32, i32, i32) {
                        %exact0159 = arith.cmpi eq, %exact, %c1 : i32
                        %posN160 = arith.cmpi eq, %pos, %n : i32
                        %exactOk161 = arith.ori %exact0159, %posN160 : i1
                        %nnz162 = arith.cmpi ne, %notNull, %c1 : i32
                        %posStart163 = arith.cmpi eq, %pos, %start : i32
                        %nnBad164 = arith.andi %nnz162, %posStart163 : i1
                        %nnOk165 = arith.xori %nnBad164, %c158 : i1
                        %sol166 = arith.andi %exactOk161, %nnOk165 : i1
                        %exactb167 = arith.cmpi ne, %exact, %c1 : i32
                        %exSol168 = arith.andi %exactb167, %sol166 : i1
                        %notEx169 = arith.xori %exactb167, %c158 : i1
                        %searchSol170 = arith.andi %notEx169, %sol166 : i1
                        %beNone171 = arith.cmpi eq, %bestEnd, %c5 : i32
                        %posGt172 = arith.cmpi ugt, %pos, %bestEnd : i32
                        %better173 = arith.ori %beNone171, %posGt172 : i1
                        %exOrBetter174 = arith.ori %exactb167, %better173 : i1
                        %needCopy175 = arith.andi %sol166, %exOrBetter174 : i1
                        scf.if %needCopy175 {
                          scf.for %j = %c7 to %ix27 step %c8 {
                            %v176 = memref.load %capsM16[%j] : !m32
                            memref.store %v176, %bestM18[%j] : !m32
                          }
                        }
                        %nfound177 = arith.select %searchSol170, %c2, %found : i32
                        %updBe178 = arith.andi %searchSol170, %better173 : i1
                        %nbe179 = arith.select %updBe178, %pos, %bestEnd : i32
                        %nret180 = arith.select %exSol168, %c2, %c5 : i32
                        %nmode181 = arith.select %exSol168, %c1, %c2 : i32
                        scf.yield %sp, %pc, %pos, %nbe179, %nfound177, %nmode181, %nret180 : i32, i32, i32, i32, i32, i32, i32
                      } else {
                        scf.yield %sp, %pc, %pos, %bestEnd, %found, %c2, %c5 : i32, i32, i32, i32, i32, i32, i32
                      }
                      scf.yield %r157#0, %r157#1, %r157#2, %r157#3, %r157#4, %r157#5, %r157#6 : i32, i32, i32, i32, i32, i32, i32
                    }
                    scf.yield %r150#0, %r150#1, %r150#2, %r150#3, %r150#4, %r150#5, %r150#6 : i32, i32, i32, i32, i32, i32, i32
                  }
                  scf.yield %r143#0, %r143#1, %r143#2, %r143#3, %r143#4, %r143#5, %r143#6 : i32, i32, i32, i32, i32, i32, i32
                }
                scf.yield %r128#0, %r128#1, %r128#2, %r128#3, %r128#4, %r128#5, %r128#6 : i32, i32, i32, i32, i32, i32, i32
              }
              scf.yield %r125#0, %r125#1, %r125#2, %r125#3, %r125#4, %r125#5, %r125#6 : i32, i32, i32, i32, i32, i32, i32
            }
            scf.yield %r91#0, %r91#1, %r91#2, %r91#3, %r91#4, %r91#5, %r91#6 : i32, i32, i32, i32, i32, i32, i32
          }
          scf.yield %r81#0, %r81#1, %r81#2, %r81#3, %r81#4, %r81#5, %r81#6 : i32, i32, i32, i32, i32, i32, i32
        }
        scf.yield %r55#0, %r55#1, %r55#2, %r55#3, %r55#4, %r55#5, %r55#6 : i32, i32, i32, i32, i32, i32, i32
      }
      scf.yield %r39#0, %r39#1, %r39#2, %r39#3, %r39#4, %r39#5, %r39#6 : i32, i32, i32, i32, i32, i32, i32
    } else {
      %sp0184 = arith.cmpi eq, %sp, %c1 : i32
      %r185:7 = scf.if %sp0184 -> (i32, i32, i32, i32, i32, i32, i32) {
        %beSet186 = arith.cmpi ne, %bestEnd, %c5 : i32
        %nret187 = arith.select %beSet186, %c2, %c1 : i32
        scf.yield %sp, %pc, %pos, %bestEnd, %found, %c2, %nret187 : i32, i32, i32, i32, i32, i32, i32
      } else {
        %sp1188 = arith.subi %sp, %c2 : i32
        %s3189 = arith.muli %sp1188, %c35 : i32
        %ix190 = arith.index_cast %s3189 : i32 to index
        %tagW191 = memref.load %stackM22[%ix190] : !m32
        %a1192 = arith.addi %ix190, %c8 : index
        %ea193 = memref.load %stackM22[%a1192] : !m32
        %a2194 = arith.addi %ix190, %c30 : index
        %eb195 = memref.load %stackM22[%a2194] : !m32
        %t196 = arith.shrui %tagW191, %c182 : i32
        %id197 = arith.andi %tagW191, %c183 : i32
        %teq198 = arith.cmpi eq, %t196, %c35 : i32
        %r199:7 = scf.if %teq198 -> (i32, i32, i32, i32, i32, i32, i32) {
          %ix200 = arith.index_cast %id197 : i32 to index
          memref.store %ea193, %capsM16[%ix200] : !m32
          scf.yield %sp1188, %pc, %pos, %bestEnd, %found, %c2, %c5 : i32, i32, i32, i32, i32, i32, i32
        } else {
          %teq201 = arith.cmpi eq, %t196, %c4 : i32
          %r202:7 = scf.if %teq201 -> (i32, i32, i32, i32, i32, i32, i32) {
            %id2203 = arith.muli %id197, %c3 : i32
            %ix204 = arith.index_cast %id2203 : i32 to index
            %id2p1205 = arith.addi %ix204, %c8 : index
            memref.store %ea193, %loopM20[%ix204] : !m32
            memref.store %eb195, %loopM20[%id2p1205] : !m32
            scf.yield %sp1188, %pc, %pos, %bestEnd, %found, %c2, %c5 : i32, i32, i32, i32, i32, i32, i32
          } else {
            %teq206 = arith.cmpi eq, %t196, %c2 : i32
            %r207:7 = scf.if %teq206 -> (i32, i32, i32, i32, i32, i32, i32) {
              %eab208 = arith.cmpi ne, %ea193, %c1 : i32
              %fb209 = arith.cmpi ne, %found, %c1 : i32
              %orv210 = arith.ori %fb209, %eab208 : i1
              %nf211 = arith.select %orv210, %c2, %c1 : i32
              scf.yield %sp1188, %pc, %pos, %bestEnd, %nf211, %c2, %c5 : i32, i32, i32, i32, i32, i32, i32
            } else {
              %teq212 = arith.cmpi eq, %t196, %c3 : i32
              %r213:7 = scf.if %teq212 -> (i32, i32, i32, i32, i32, i32, i32) {
                %fb214 = arith.cmpi ne, %found, %c1 : i32
                %npc215 = arith.select %fb214, %pc, %id197 : i32
                %npos216 = arith.select %fb214, %pos, %ea193 : i32
                %nmode217 = arith.select %fb214, %c2, %c1 : i32
                scf.yield %sp1188, %npc215, %npos216, %bestEnd, %found, %nmode217, %c5 : i32, i32, i32, i32, i32, i32, i32
              } else {
                %teq218 = arith.cmpi eq, %t196, %c1 : i32
                %r219:7 = scf.if %teq218 -> (i32, i32, i32, i32, i32, i32, i32) {
                  %full221 = arith.cmpi eq, %sp1188, %cap : i32
                  %r222:7 = scf.if %full221 -> (i32, i32, i32, i32, i32, i32, i32) {
                    scf.yield %sp1188, %pc, %pos, %bestEnd, %found, %c2, %c3 : i32, i32, i32, i32, i32, i32, i32
                  } else {
                    %s3223 = arith.muli %sp1188, %c35 : i32
                    %ix224 = arith.index_cast %s3223 : i32 to index
                    memref.store %c220, %stackM22[%ix224] : !m32
                    %a1225 = arith.addi %ix224, %c8 : index
                    memref.store %found, %stackM22[%a1225] : !m32
                    %a2226 = arith.addi %ix224, %c30 : index
                    memref.store %c1, %stackM22[%a2226] : !m32
                    %spn227 = arith.addi %sp1188, %c2 : i32
                    scf.yield %spn227, %id197, %ea193, %bestEnd, %c1, %c1, %c5 : i32, i32, i32, i32, i32, i32, i32
                  }
                  scf.yield %r222#0, %r222#1, %r222#2, %r222#3, %r222#4, %r222#5, %r222#6 : i32, i32, i32, i32, i32, i32, i32
                } else {
                  scf.yield %sp1188, %pc, %pos, %bestEnd, %found, %c2, %c5 : i32, i32, i32, i32, i32, i32, i32
                }
                scf.yield %r219#0, %r219#1, %r219#2, %r219#3, %r219#4, %r219#5, %r219#6 : i32, i32, i32, i32, i32, i32, i32
              }
              scf.yield %r213#0, %r213#1, %r213#2, %r213#3, %r213#4, %r213#5, %r213#6 : i32, i32, i32, i32, i32, i32, i32
            }
            scf.yield %r207#0, %r207#1, %r207#2, %r207#3, %r207#4, %r207#5, %r207#6 : i32, i32, i32, i32, i32, i32, i32
          }
          scf.yield %r202#0, %r202#1, %r202#2, %r202#3, %r202#4, %r202#5, %r202#6 : i32, i32, i32, i32, i32, i32, i32
        }
        scf.yield %r199#0, %r199#1, %r199#2, %r199#3, %r199#4, %r199#5, %r199#6 : i32, i32, i32, i32, i32, i32, i32
      }
      scf.yield %r185#0, %r185#1, %r185#2, %r185#3, %r185#4, %r185#5, %r185#6 : i32, i32, i32, i32, i32, i32, i32
    }
    scf.yield %r34#0, %r34#1, %r34#2, %r34#3, %r34#4, %r34#5, %r34#6 : i32, i32, i32, i32, i32, i32, i32
  }
  return %w#6 : i32
}
