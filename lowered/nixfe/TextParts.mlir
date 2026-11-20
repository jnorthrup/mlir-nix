// Parser.cpp's text algorithms hollowed into trikeshed fill-drain (the C++ bodies are gone; the bridges marshal
// the parts and keep the grammar actions, the throws and the node building):
//   nixfe_ts_strip(recs, n, out, cap, wins) -> written -- stripIndentation.  recs is 3 i64 words a part: the text
//     window's ptr bits, its length, its kind (0 a literal with indent, 1 a literal without, 2 an antiquotation
//     Node).  Pass 1 scans the indent (minIndent); pass 2 walks every literal part's bytes with the carried
//     (atStartOfLine, curDropped) state and fills the KEPT SEGMENTS -- one contiguous slice a line, its leading
//     minIndent spaces dropped -- into cells; ONE combineAll of those slices drains once into the caller's Text.
//     The last part's trailing all-space line after its last newline is dropped (length 0).  wins is 2 words a
//     part: its stripped bytes' offset/length in out.  The Node parts and the strLit/concat stay in the bridge.
//   nixfe_ts_strparts(ctx) -> kind -- parseStringParts' loop driver: the fast path (one text run then the closing
//     quote), the T_STR / T_DOLLAR_CURLY loop and the interpolated/single selection.  The grammar actions are
//     callbacks at the points the C++ loop did them: peek (0 T_STR / 1 '${' / 2 '"' / 3 other), str (take + nameOf,
//     push unless the fast path may still fire), push, expr (parseExpr under the '${'), close (the '"' check).
//     kind 0 the empty literal, 1 the single text (ctx.single), 2 a concatenation (the bridge's parts).
//   nixfe_ts_path_kind(hp, lit, n) -> kind -- makePath's lint classification: 1 home, 2 absolute, 3 short, 0 none.
//   nixfe_ts_path_msg(kind, lit, n, into, cap) -> written -- the lint message as ONE combine of blob-word slices
//     and the literal's windows (the short-path message names it twice), drained once.
//   nixfe_ts_path_home(home, hn, lit, n, into, cap) -> written -- the home path's text: home + the literal past
//     its '~', one combine drained once.  canonPath (CanonPath.mlir) and the trailing '/' stay in the bridge.
!s = !trikeshed.series<i8>
!m = memref<?xi8, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>
!coords = !trikeshed.series<!trikeshed.twinpacked<i32>>

// the descriptor of n cells at p (a struct, not a memref: returning it allocates nothing and clones nothing)
func.func private @tp_desc(%p: !llvm.ptr, %n: i64) -> !d {
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

func.func @nixfe_ts_strip(%recs: !llvm.ptr, %n: i64, %out: !llvm.ptr, %cap: i64, %wins: !llvm.ptr) -> i64 {
  %c0_i64 = arith.constant 0 : i64
  %c1_i64 = arith.constant 1 : i64
  %c2_i64 = arith.constant 2 : i64
  %c3_i64 = arith.constant 3 : i64
  %c4_i64 = arith.constant 1000000 : i64
  %c5_i8 = arith.constant 32 : i8
  %c6_i8 = arith.constant 10 : i8
  %c7_index = arith.constant 0 : index
  %c8_index = arith.constant 1 : index
  %ni_1 = arith.index_cast %n : i64 to index
  %n3_2 = arith.muli %n, %c3_i64 : i64
  %n2_3 = arith.muli %n, %c2_i64 : i64
  %rc_4 = func.call @tp_desc(%recs, %n3_2) : (!llvm.ptr, i64) -> !d
  %recm_5 = builtin.unrealized_conversion_cast %rc_4 : !d to memref<?xi64>
  %wc_6 = func.call @tp_desc(%wins, %n2_3) : (!llvm.ptr, i64) -> !d
  %winm_7 = builtin.unrealized_conversion_cast %wc_6 : !d to memref<?xi64>
  %p1:4 = scf.for %k = %c7_index to %ni_1 step %c8_index iter_args(%aS = %c1_i64, %ci = %c0_i64, %mi = %c4_i64, %tot = %c0_i64) -> (i64, i64, i64, i64) {
  %k_8 = arith.index_cast %k : index to i64
  %k3_9 = arith.muli %k_8, %c3_i64 : i64
  %k31_10 = arith.addi %k3_9, %c1_i64 : i64
  %k32_11 = arith.addi %k3_9, %c2_i64 : i64
  %kindi_12 = arith.index_cast %k32_11 : i64 to index
  %kind_13 = memref.load %recm_5[%kindi_12] : memref<?xi64>
  %leni_14 = arith.index_cast %k31_10 : i64 to index
  %len_15 = memref.load %recm_5[%leni_14] : memref<?xi64>
  %lit0_16 = arith.cmpi eq, %kind_13, %c0_i64 : i64
  %p_17, %p_18, %p_19, %p_20 = scf.if %lit0_16 -> (i64, i64, i64, i64) {
  %pbi_21 = arith.index_cast %k3_9 : i64 to index
  %pb_22 = memref.load %recm_5[%pbi_21] : memref<?xi64>
  %ptr_23 = llvm.inttoptr %pb_22 : i64 to !llvm.ptr
  %txd_24 = func.call @tp_desc(%ptr_23, %len_15) : (!llvm.ptr, i64) -> !d
  %txm_25 = builtin.unrealized_conversion_cast %txd_24 : !d to !m
  %tx_26 = builtin.unrealized_conversion_cast %txm_25 : !m to !s
  %lni_27 = arith.index_cast %len_15 : i64 to index
  %in:3 = scf.for %j = %c7_index to %lni_27 step %c8_index iter_args(%a = %aS, %c = %ci, %m = %mi) -> (i64, i64, i64) {
  %ch_28 = trikeshed.at %tx_26[%j] : !s, index -> i8
  %sp_29 = arith.cmpi eq, %ch_28, %c5_i8 : i8
  %nl_30 = arith.cmpi eq, %ch_28, %c6_i8 : i8
  %anz_31 = arith.cmpi ne, %a, %c0_i64 : i64
  %q_32, %q_33, %q_34 = scf.if %anz_31 -> (i64, i64, i64) {
  %q_35, %q_36, %q_37 = scf.if %sp_29 -> (i64, i64, i64) {
  %ci2_38 = arith.addi %c, %c1_i64 : i64
  scf.yield %a, %ci2_38, %m : i64, i64, i64
    } else {
  %q_39, %q_40, %q_41 = scf.if %nl_30 -> (i64, i64, i64) {
  scf.yield %a, %c0_i64, %m : i64, i64, i64
    } else {
  %mi2_42 = arith.minui %m, %c : i64
  scf.yield %c0_i64, %c, %mi2_42 : i64, i64, i64
    }
  scf.yield %q_39, %q_40, %q_41 : i64, i64, i64
    }
  scf.yield %q_35, %q_36, %q_37 : i64, i64, i64
    } else {
  %q_43, %q_44, %q_45 = scf.if %nl_30 -> (i64, i64, i64) {
  scf.yield %c1_i64, %c0_i64, %m : i64, i64, i64
    } else {
  scf.yield %a, %c, %m : i64, i64, i64
    }
  scf.yield %q_43, %q_44, %q_45 : i64, i64, i64
    }
  scf.yield %q_32, %q_33, %q_34 : i64, i64, i64
  }
  %tot2_46 = arith.addi %tot, %len_15 : i64
  scf.yield %in#0, %in#1, %in#2, %tot2_46 : i64, i64, i64, i64
    } else {
  %anz_47 = arith.cmpi ne, %aS, %c0_i64 : i64
  %q_48, %q_49, %q_50 = scf.if %anz_47 -> (i64, i64, i64) {
  %mi2_51 = arith.minui %mi, %ci : i64
  scf.yield %c0_i64, %ci, %mi2_51 : i64, i64, i64
    } else {
  scf.yield %aS, %ci, %mi : i64, i64, i64
    }
  %k1_52 = arith.cmpi eq, %kind_13, %c1_i64 : i64
  %tot2_53 = arith.addi %tot, %len_15 : i64
  %tot_54 = arith.select %k1_52, %tot2_53, %tot : i64
  scf.yield %q_48, %q_49, %q_50, %tot_54 : i64, i64, i64, i64
    }
  scf.yield %p_17, %p_18, %p_19, %p_20 : i64, i64, i64, i64
  }
  %tp_55 = arith.addi %p1#3, %n : i64
  %words_56 = arith.muli %tp_55, %c2_i64 : i64
  %wsi_57 = arith.index_cast %words_56 : i64 to index
  %segs_58 = memref.alloc(%wsi_57) : memref<?xi64>
  %p2:4 = scf.for %k2 = %c7_index to %ni_1 step %c8_index iter_args(%aS2 = %c1_i64, %dr = %c0_i64, %off = %c0_i64, %ns = %c0_i64) -> (i64, i64, i64, i64) {
  %k2_59 = arith.index_cast %k2 : index to i64
  %k3_60 = arith.muli %k2_59, %c3_i64 : i64
  %k31_61 = arith.addi %k3_60, %c1_i64 : i64
  %k32_62 = arith.addi %k3_60, %c2_i64 : i64
  %kindi_63 = arith.index_cast %k32_62 : i64 to index
  %kind_64 = memref.load %recm_5[%kindi_63] : memref<?xi64>
  %leni_65 = arith.index_cast %k31_61 : i64 to index
  %len_66 = memref.load %recm_5[%leni_65] : memref<?xi64>
  %pbi_67 = arith.index_cast %k3_60 : i64 to index
  %pb_68 = memref.load %recm_5[%pbi_67] : memref<?xi64>
  %node_69 = arith.cmpi eq, %kind_64, %c2_i64 : i64
  %k2x2_70 = arith.muli %k2_59, %c2_i64 : i64
  %k2x21_71 = arith.addi %k2x2_70, %c1_i64 : i64
  %p_72, %p_73, %p_74, %p_75 = scf.if %node_69 -> (i64, i64, i64, i64) {
  %si_76 = arith.index_cast %k2x2_70 : i64 to index
  memref.store %c0_i64, %winm_7[%si_76] : memref<?xi64>
  %si_77 = arith.index_cast %k2x21_71 : i64 to index
  memref.store %c0_i64, %winm_7[%si_77] : memref<?xi64>
  scf.yield %c0_i64, %c0_i64, %off, %ns : i64, i64, i64, i64
    } else {
  %ptr_78 = llvm.inttoptr %pb_68 : i64 to !llvm.ptr
  %txd_79 = func.call @tp_desc(%ptr_78, %len_66) : (!llvm.ptr, i64) -> !d
  %txm_80 = builtin.unrealized_conversion_cast %txd_79 : !d to !m
  %tx_81 = builtin.unrealized_conversion_cast %txm_80 : !m to !s
  %lni_82 = arith.index_cast %len_66 : i64 to index
  %in2:6 = scf.for %j2 = %c7_index to %lni_82 step %c8_index iter_args(%a2 = %aS2, %d2 = %dr, %ks = %c0_i64, %of = %off, %ne = %ns, %sn = %c0_i64) -> (i64, i64, i64, i64, i64, i64) {
  %ch_83 = trikeshed.at %tx_81[%j2] : !s, index -> i8
  %nl_84 = arith.cmpi eq, %ch_83, %c6_i8 : i8
  %sp_85 = arith.cmpi eq, %ch_83, %c5_i8 : i8
  %j_86 = arith.index_cast %j2 : index to i64
  %j1_87 = arith.addi %j_86, %c1_i64 : i64
  %q_88, %q_89, %q_90, %q_91, %q_92, %q_93 = scf.if %nl_84 -> (i64, i64, i64, i64, i64, i64) {
  %eln_94 = arith.subi %j1_87, %ks : i64
  %addr_95 = arith.addi %pb_68, %ks : i64
  %ne2_96 = arith.muli %ne, %c2_i64 : i64
  %ne21_97 = arith.addi %ne2_96, %c1_i64 : i64
  %si_98 = arith.index_cast %ne2_96 : i64 to index
  memref.store %addr_95, %segs_58[%si_98] : memref<?xi64>
  %si_99 = arith.index_cast %ne21_97 : i64 to index
  memref.store %eln_94, %segs_58[%si_99] : memref<?xi64>
  %of2_100 = arith.addi %of, %eln_94 : i64
  %ne3_101 = arith.addi %ne, %c1_i64 : i64
  scf.yield %c1_i64, %c0_i64, %j1_87, %of2_100, %ne3_101, %c1_i64 : i64, i64, i64, i64, i64, i64
    } else {
  %anz_102 = arith.cmpi ne, %a2, %c0_i64 : i64
  %q_103, %q_104, %q_105, %q_106, %q_107, %q_108 = scf.if %anz_102 -> (i64, i64, i64, i64, i64, i64) {
  %q_109, %q_110, %q_111, %q_112, %q_113, %q_114 = scf.if %sp_85 -> (i64, i64, i64, i64, i64, i64) {
  %keep_115 = arith.cmpi uge, %d2, %p1#2 : i64
  %ks1_116 = arith.addi %ks, %c1_i64 : i64
  %ks_117 = arith.select %keep_115, %ks, %ks1_116 : i64
  %d3_118 = arith.addi %d2, %c1_i64 : i64
  scf.yield %a2, %d3_118, %ks_117, %of, %ne, %sn : i64, i64, i64, i64, i64, i64
    } else {
  scf.yield %c0_i64, %c0_i64, %ks, %of, %ne, %sn : i64, i64, i64, i64, i64, i64
    }
  scf.yield %q_109, %q_110, %q_111, %q_112, %q_113, %q_114 : i64, i64, i64, i64, i64, i64
    } else {
  scf.yield %a2, %d2, %ks, %of, %ne, %sn : i64, i64, i64, i64, i64, i64
    }
  scf.yield %q_103, %q_104, %q_105, %q_106, %q_107, %q_108 : i64, i64, i64, i64, i64, i64
    }
  scf.yield %q_88, %q_89, %q_90, %q_91, %q_92, %q_93 : i64, i64, i64, i64, i64, i64
  }
  %fln_119 = arith.subi %len_66, %in2#2 : i64
  %nm1_120 = arith.subi %n, %c1_i64 : i64
  %last_121 = arith.cmpi eq, %k2_59, %nm1_120 : i64
  %snz_122 = arith.cmpi ne, %in2#5, %c0_i64 : i64
  %aend_123 = arith.cmpi ne, %in2#0, %c0_i64 : i64
  %g1_124 = arith.andi %last_121, %snz_122 : i1
  %drop_125 = arith.andi %g1_124, %aend_123 : i1
  %fln_126 = arith.select %drop_125, %c0_i64, %fln_119 : i64
  %addrf_127 = arith.addi %pb_68, %in2#2 : i64
  %nef_128 = arith.muli %in2#4, %c2_i64 : i64
  %nef1_129 = arith.addi %nef_128, %c1_i64 : i64
  %si_130 = arith.index_cast %nef_128 : i64 to index
  memref.store %addrf_127, %segs_58[%si_130] : memref<?xi64>
  %si_131 = arith.index_cast %nef1_129 : i64 to index
  memref.store %fln_126, %segs_58[%si_131] : memref<?xi64>
  %offend_132 = arith.addi %in2#3, %fln_126 : i64
  %nsend_133 = arith.addi %in2#4, %c1_i64 : i64
  %wlen_134 = arith.subi %offend_132, %off : i64
  %si_135 = arith.index_cast %k2x2_70 : i64 to index
  memref.store %off, %winm_7[%si_135] : memref<?xi64>
  %si_136 = arith.index_cast %k2x21_71 : i64 to index
  memref.store %wlen_134, %winm_7[%si_136] : memref<?xi64>
  scf.yield %in2#0, %in2#1, %offend_132, %nsend_133 : i64, i64, i64, i64
    }
  scf.yield %p_72, %p_73, %p_74, %p_75 : i64, i64, i64, i64
  }
  %nsi_137 = arith.index_cast %p2#3 : i64 to index
  %all, %co = trikeshed.combineAll %nsi_137 : !s, !coords {
  ^bb0(%kk: index):
  %kk_138 = arith.index_cast %kk : index to i64
  %w0_139 = arith.muli %kk_138, %c2_i64 : i64
  %w1_140 = arith.addi %w0_139, %c1_i64 : i64
  %pbi_141 = arith.index_cast %w0_139 : i64 to index
  %pb_142 = memref.load %segs_58[%pbi_141] : memref<?xi64>
  %lni_143 = arith.index_cast %w1_140 : i64 to index
  %ln_144 = memref.load %segs_58[%lni_143] : memref<?xi64>
  %sp_145 = llvm.inttoptr %pb_142 : i64 to !llvm.ptr
  %partd_146 = func.call @tp_desc(%sp_145, %ln_144) : (!llvm.ptr, i64) -> !d
  %partm_147 = builtin.unrealized_conversion_cast %partd_146 : !d to !m
  %part_148 = builtin.unrealized_conversion_cast %partm_147 : !m to !s
  trikeshed.yield %part_148 : !s
  }
  %sz_149 = trikeshed.size %all : !s
  %sz_150 = arith.index_cast %sz_149 : index to i64
  %ok_151 = arith.cmpi ule, %sz_150, %cap : i64
  %written_152 = scf.if %ok_151 -> (i64) {
  %into_153 = func.call @tp_desc(%out, %sz_150) : (!llvm.ptr, i64) -> !d
  %intom_154 = builtin.unrealized_conversion_cast %into_153 : !d to !m
  %end_155 = trikeshed.drain %all, %intom_154 : !s, !m -> index
  %end_156 = arith.index_cast %end_155 : index to i64
  scf.yield %end_156 : i64
    } else {
  %neg_157 = arith.subi %c0_i64, %sz_150 : i64
  scf.yield %neg_157 : i64
    }
  return %written_152 : i64
}

func.func private @nixfe_sp_peek(!llvm.ptr) -> i64
func.func private @nixfe_sp_str(!llvm.ptr, i64)
func.func private @nixfe_sp_push(!llvm.ptr)
func.func private @nixfe_sp_expr(!llvm.ptr)
func.func private @nixfe_sp_close(!llvm.ptr)

func.func private @tp_strloop(%ctx: !llvm.ptr, %hs0: i64) -> i64 {
  %c0_i64 = arith.constant 0 : i64
  %c1_i64 = arith.constant 1 : i64
  %c2_i64 = arith.constant 2 : i64
  %wl:2 = scf.while (%inter = %c0_i64, %hs = %hs0) : (i64, i64) -> (i64, i64) {
  %t_1 = func.call @nixfe_sp_peek(%ctx) : (!llvm.ptr) -> i64
  %iss_2 = arith.cmpi eq, %t_1, %c0_i64 : i64
  %isd_3 = arith.cmpi eq, %t_1, %c1_i64 : i64
  %go_4 = arith.ori %iss_2, %isd_3 : i1
  scf.condition(%go_4) %inter, %hs : i64, i64
  } do {
  ^bb0(%inter2: i64, %hs2: i64):
  %t2_5 = func.call @nixfe_sp_peek(%ctx) : (!llvm.ptr) -> i64
  %iss_6 = arith.cmpi eq, %t2_5, %c0_i64 : i64
  %u_7, %u_8 = scf.if %iss_6 -> (i64, i64) {
  func.call @nixfe_sp_str(%ctx, %c1_i64) : (!llvm.ptr, i64) -> ()
  scf.yield %inter2, %c1_i64 : i64, i64
    } else {
  func.call @nixfe_sp_expr(%ctx) : (!llvm.ptr) -> ()
  scf.yield %c1_i64, %hs2 : i64, i64
    }
  scf.yield %u_7, %u_8 : i64, i64
  }
  func.call @nixfe_sp_close(%ctx) : (!llvm.ptr) -> ()
  %hasi_9 = arith.cmpi ne, %wl#0, %c0_i64 : i64
  %hass_10 = arith.cmpi ne, %wl#1, %c0_i64 : i64
  %k1_11 = arith.select %hass_10, %c1_i64, %c0_i64 : i64
  %k_12 = arith.select %hasi_9, %c2_i64, %k1_11 : i64
  return %k_12 : i64
}

func.func @nixfe_ts_strparts(%ctx: !llvm.ptr) -> i64 {
  %c0_i64 = arith.constant 0 : i64
  %c1_i64 = arith.constant 1 : i64
  %c2_i64 = arith.constant 2 : i64
  %t0_1 = func.call @nixfe_sp_peek(%ctx) : (!llvm.ptr) -> i64
  %iss_2 = arith.cmpi eq, %t0_1, %c0_i64 : i64
  %k_3 = scf.if %iss_2 -> (i64) {
  func.call @nixfe_sp_str(%ctx, %c0_i64) : (!llvm.ptr, i64) -> ()
  %t1_4 = func.call @nixfe_sp_peek(%ctx) : (!llvm.ptr) -> i64
  %isc_5 = arith.cmpi eq, %t1_4, %c2_i64 : i64
  %kk_6 = scf.if %isc_5 -> (i64) {
  scf.yield %c1_i64 : i64
    } else {
  func.call @nixfe_sp_push(%ctx) : (!llvm.ptr) -> ()
  %ll_7 = func.call @tp_strloop(%ctx, %c0_i64) : (!llvm.ptr, i64) -> i64
  scf.yield %ll_7 : i64
    }
  scf.yield %kk_6 : i64
    } else {
  %ise_8 = arith.cmpi eq, %t0_1, %c2_i64 : i64
  %kk_9 = scf.if %ise_8 -> (i64) {
  scf.yield %c0_i64 : i64
    } else {
  %ll_10 = func.call @tp_strloop(%ctx, %c0_i64) : (!llvm.ptr, i64) -> i64
  scf.yield %ll_10 : i64
    }
  scf.yield %kk_9 : i64
    }
  return %k_3 : i64
}

func.func @nixfe_ts_path_kind(%hp: i64, %p: !llvm.ptr, %n: i64) -> i64 {
  %c0_i64 = arith.constant 0 : i64
  %c1_i64 = arith.constant 1 : i64
  %c2_i64 = arith.constant 2 : i64
  %c3_i64 = arith.constant 3 : i64
  %c4_i8 = arith.constant 47 : i8
  %c5_i8 = arith.constant 46 : i8
  %c6_index = arith.constant 0 : index
  %ish_1 = arith.cmpi ne, %hp, %c0_i64 : i64
  %kind_2 = scf.if %ish_1 -> (i64) {
  scf.yield %c1_i64 : i64
    } else {
  %hasn_3 = arith.cmpi ugt, %n, %c0_i64 : i64
  %r_4 = scf.if %hasn_3 -> (i64) {
  %litd_5 = func.call @tp_desc(%p, %n) : (!llvm.ptr, i64) -> !d
  %litm_6 = builtin.unrealized_conversion_cast %litd_5 : !d to !m
  %lit_7 = builtin.unrealized_conversion_cast %litm_6 : !m to !s
  %c0_8 = trikeshed.at %lit_7[%c6_index] : !s, index -> i8
  %sl_9 = arith.cmpi eq, %c0_8, %c4_i8 : i8
  %r_10 = scf.if %sl_9 -> (i64) {
  scf.yield %c2_i64 : i64
    } else {
  %dot_11 = arith.cmpi eq, %c0_8, %c5_i8 : i8
  %r_12 = scf.if %dot_11 -> (i64) {
  scf.yield %c0_i64 : i64
    } else {
  scf.yield %c3_i64 : i64
    }
  scf.yield %r_12 : i64
    }
  scf.yield %r_10 : i64
    } else {
  scf.yield %c0_i64 : i64
    }
  scf.yield %r_4 : i64
    }
  return %kind_2 : i64
}

memref.global "private" constant @tp_blob : memref<256xi8> = dense<"0x686f6d652070617468206c69746572616c7320617265206e6f7420706f727461626c652e20436f6e7369646572207265706c6163696e672070617468206c69746572616c20276162736f6c7574652070617468206c69746572616c7320617265206e6f7420706f727461626c652e20436f6e7369646572207265706c6163696e672070617468206c69746572616c202727206279206120737472696e672c2072656c617469766520706174682c206f7220706172616d6574657272656c61746976652070617468206c69746572616c2027272073686f756c64206265207072656669786564207769746820272e2720666f7220636c61726974793a20272e2f27">

memref.global "private" constant @tp_off : memref<6xi32> = dense<[0, 70, 144, 186, 209, 255]>

memref.global "private" constant @tp_len : memref<6xi32> = dense<[70, 74, 42, 23, 46, 1]>

func.func private @tp_bounds(%i: index) -> (index, index) {
  %og_1 = memref.get_global @tp_off : memref<6xi32>
  %lg_2 = memref.get_global @tp_len : memref<6xi32>
  %o32_3 = memref.load %og_1[%i] : memref<6xi32>
  %l32_4 = memref.load %lg_2[%i] : memref<6xi32>
  %oi_5 = arith.index_castui %o32_3 : i32 to index
  %li_6 = arith.index_castui %l32_4 : i32 to index
  return %oi_5, %li_6 : index, index
}

func.func @nixfe_ts_path_msg(%kind: i64, %p: !llvm.ptr, %n: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %c0_i64 = arith.constant 0 : i64
  %c1_i64 = arith.constant 1 : i64
  %c2_i64 = arith.constant 3 : i64
  %c3_index = arith.constant 0 : index
  %c4_index = arith.constant 1 : index
  %c5_index = arith.constant 2 : index
  %c6_index = arith.constant 3 : index
  %c7_index = arith.constant 4 : index
  %c8_index = arith.constant 5 : index
  %ish_1 = arith.cmpi eq, %kind, %c1_i64 : i64
  %iss_2 = arith.cmpi eq, %kind, %c2_i64 : i64
  %bg_3 = memref.get_global @tp_blob : memref<256xi8>
  %blob_4 = trikeshed.text %bg_3 : memref<256xi8> -> !s
  %o0_5, %l0_6 = func.call @tp_bounds(%c3_index) : (index) -> (index, index)
  %o1_7, %l1_8 = func.call @tp_bounds(%c4_index) : (index) -> (index, index)
  %o2_9, %l2_10 = func.call @tp_bounds(%c5_index) : (index) -> (index, index)
  %o3_11, %l3_12 = func.call @tp_bounds(%c6_index) : (index) -> (index, index)
  %o4_13, %l4_14 = func.call @tp_bounds(%c7_index) : (index) -> (index, index)
  %o5_15, %l5_16 = func.call @tp_bounds(%c8_index) : (index) -> (index, index)
  %p0stA_17 = arith.select %ish_1, %o0_5, %o1_7 : index
  %p0st_18 = arith.select %iss_2, %o3_11, %p0stA_17 : index
  %p0lnA_19 = arith.select %ish_1, %l0_6, %l1_8 : index
  %p0ln_20 = arith.select %iss_2, %l3_12, %p0lnA_19 : index
  %p0_21 = trikeshed.slice %blob_4[%p0st_18, %p0ln_20] : !s -> !s
  %p1d_22 = func.call @tp_desc(%p, %n) : (!llvm.ptr, i64) -> !d
  %p1m_23 = builtin.unrealized_conversion_cast %p1d_22 : !d to !m
  %p1_24 = builtin.unrealized_conversion_cast %p1m_23 : !m to !s
  %p2st_25 = arith.select %iss_2, %o4_13, %o2_9 : index
  %p2ln_26 = arith.select %iss_2, %l4_14, %l2_10 : index
  %p2_27 = trikeshed.slice %blob_4[%p2st_25, %p2ln_26] : !s -> !s
  %p3ln_28 = arith.select %iss_2, %n, %c0_i64 : i64
  %p3d_29 = func.call @tp_desc(%p, %p3ln_28) : (!llvm.ptr, i64) -> !d
  %p3m_30 = builtin.unrealized_conversion_cast %p3d_29 : !d to !m
  %p3_31 = builtin.unrealized_conversion_cast %p3m_30 : !m to !s
  %p4ln_32 = arith.select %iss_2, %l5_16, %c3_index : index
  %p4_33 = trikeshed.slice %blob_4[%o5_15, %p4ln_32] : !s -> !s
  %all_34 = trikeshed.combine %p0_21, %p1_24, %p2_27, %p3_31, %p4_33 : !s, !s, !s, !s, !s -> !s
  %sz_35 = trikeshed.size %all_34 : !s
  %sz_36 = arith.index_cast %sz_35 : index to i64
  %ok_37 = arith.cmpi ule, %sz_36, %cap : i64
  %written_38 = scf.if %ok_37 -> (i64) {
  %into_39 = func.call @tp_desc(%into, %sz_36) : (!llvm.ptr, i64) -> !d
  %intom_40 = builtin.unrealized_conversion_cast %into_39 : !d to !m
  %end_41 = trikeshed.drain %all_34, %intom_40 : !s, !m -> index
  %end_42 = arith.index_cast %end_41 : index to i64
  scf.yield %end_42 : i64
    } else {
  %neg_43 = arith.subi %c0_i64, %sz_36 : i64
  scf.yield %neg_43 : i64
    }
  return %written_38 : i64
}

func.func @nixfe_ts_path_home(%home: !llvm.ptr, %hn: i64, %p: !llvm.ptr, %n: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %c0_i64 = arith.constant 0 : i64
  %c1_i64 = arith.constant 1 : i64
  %c2_index = arith.constant 0 : index
  %c3_index = arith.constant 1 : index
  %hwd_1 = func.call @tp_desc(%home, %hn) : (!llvm.ptr, i64) -> !d
  %hwm_2 = builtin.unrealized_conversion_cast %hwd_1 : !d to !m
  %hw_3 = builtin.unrealized_conversion_cast %hwm_2 : !m to !s
  %hasn_4 = arith.cmpi ugt, %n, %c0_i64 : i64
  %st_5 = arith.select %hasn_4, %c3_index, %c2_index : index
  %nm1_6 = arith.subi %n, %c1_i64 : i64
  %nm1i_7 = arith.index_cast %nm1_6 : i64 to index
  %ln_8 = arith.select %hasn_4, %nm1i_7, %c2_index : index
  %litd_9 = func.call @tp_desc(%p, %n) : (!llvm.ptr, i64) -> !d
  %litm_10 = builtin.unrealized_conversion_cast %litd_9 : !d to !m
  %lit_11 = builtin.unrealized_conversion_cast %litm_10 : !m to !s
  %rest_12 = trikeshed.slice %lit_11[%st_5, %ln_8] : !s -> !s
  %all_13 = trikeshed.combine %hw_3, %rest_12 : !s, !s -> !s
  %sz_14 = trikeshed.size %all_13 : !s
  %sz_15 = arith.index_cast %sz_14 : index to i64
  %ok_16 = arith.cmpi ule, %sz_15, %cap : i64
  %written_17 = scf.if %ok_16 -> (i64) {
  %into_18 = func.call @tp_desc(%into, %sz_15) : (!llvm.ptr, i64) -> !d
  %intom_19 = builtin.unrealized_conversion_cast %into_18 : !d to !m
  %end_20 = trikeshed.drain %all_13, %intom_19 : !s, !m -> index
  %end_21 = arith.index_cast %end_20 : index to i64
  scf.yield %end_21 : i64
    } else {
  %neg_22 = arith.subi %c0_i64, %sz_15 : i64
  scf.yield %neg_22 : i64
    }
  return %written_17 : i64
}
