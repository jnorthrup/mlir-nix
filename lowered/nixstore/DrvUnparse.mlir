// The derivation ATerm writer (nixstore::unparseTo, lib/Store/StorePaths.cpp) hollowed into the
// TrikeShed dialect.  The C++ bridge marshals the Derivation into flat record arrays (outputs, inputs,
// srcs, args, env), normalizes each output's kind to its (name,path,algo,hash) fields, applies maskOutputs
// and slots __json into the env order; this module iterates those arrays and composes the WHOLE ATerm text
// as one variadic combine of section views, each list a combineAll, each escaped string a combineAll over a
// constant ATerm escape table -- drained ONCE into a pre-sized buffer (fill-drain).  The entry returns the
// bytes written, or -needed when cap is too small (the bridge pre-sizes a worst-case bound and truncates).
// ATerm escaping: " -> \", \ -> \\, \n \r \t -> \n \r \t; every other byte raw (escapeInto's table).
!s = !trikeshed.series<i8>
!m = memref<?xi8, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

memref.global "private" constant @esc_tab : memref<512xi8> = dense<"0x0000010002000300040005000600070008005c745c6e0b000c005c720e000f0010001100120013001400150016001700180019001a001b001c001d001e001f00200021005c2223002400250026002700280029002a002b002c002d002e002f0030003100320033003400350036003700380039003a003b003c003d003e003f0040004100420043004400450046004700480049004a004b004c004d004e004f0050005100520053005400550056005700580059005a005b005c5c5d005e005f0060006100620063006400650066006700680069006a006b006c006d006e006f0070007100720073007400750076007700780079007a007b007c007d007e007f0080008100820083008400850086008700880089008a008b008c008d008e008f0090009100920093009400950096009700980099009a009b009c009d009e009f00a000a100a200a300a400a500a600a700a800a900aa00ab00ac00ad00ae00af00b000b100b200b300b400b500b600b700b800b900ba00bb00bc00bd00be00bf00c000c100c200c300c400c500c600c700c800c900ca00cb00cc00cd00ce00cf00d000d100d200d300d400d500d600d700d800d900da00db00dc00dd00de00df00e000e100e200e300e400e500e600e700e800e900ea00eb00ec00ed00ee00ef00f000f100f200f300f400f500f600f700f800f900fa00fb00fc00fd00fe00ff00">
memref.global "private" constant @esc_len : memref<256xi8> = dense<"0x01010101010101010102020101020101010101010101010101010101010101010101020101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010201010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101">
memref.global "private" constant @l_derive : memref<8xi8> = dense<"0x446572697665285b">
memref.global "private" constant @l_brk : memref<3xi8> = dense<"0x5d2c5b">
memref.global "private" constant @l_brk2 : memref<2xi8> = dense<"0x5d2c">
memref.global "private" constant @l_comma : memref<1xi8> = dense<"0x2c">
memref.global "private" constant @l_obrk : memref<2xi8> = dense<"0x2c5b">
memref.global "private" constant @l_close : memref<2xi8> = dense<"0x5d29">
memref.global "private" constant @l_open : memref<1xi8> = dense<"0x28">
memref.global "private" constant @l_closep : memref<1xi8> = dense<"0x29">
memref.global "private" constant @l_quote : memref<1xi8> = dense<"0x22">

func.func private @nx_desc(%p: !llvm.ptr, %n: i64) -> !d {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %u = llvm.mlir.undef : !d
  %a = llvm.insertvalue %p, %u[0] : !d
  %b = llvm.insertvalue %p, %a[1] : !d
  %c = llvm.insertvalue %c0, %b[2] : !d
  %ee = llvm.insertvalue %n, %c[3, 0] : !d
  %f = llvm.insertvalue %c1, %ee[4, 0] : !d
  return %f : !d
}

func.func @nixstore_ts_unparse(%outs: !llvm.ptr, %nouts: i64, %inputs: !llvm.ptr, %ninputs: i64,
    %srcs: !llvm.ptr, %nsrcs: i64, %platform: !llvm.ptr, %platformLen: i64,
    %builder: !llvm.ptr, %builderLen: i64, %args: !llvm.ptr, %nargs: i64,
    %env: !llvm.ptr, %nenv: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %c10 = arith.constant 64 : i64
  %c13 = arith.constant 0 : i64
  %c16 = arith.constant 8 : i64
  %c19 = arith.constant 16 : i64
  %c22 = arith.constant 24 : i64
  %c25 = arith.constant 32 : i64
  %c28 = arith.constant 40 : i64
  %c31 = arith.constant 48 : i64
  %c34 = arith.constant 56 : i64
  %c37 = arith.constant 0 : index
  %c44 = arith.constant 1 : index
  %c231 = arith.constant 2 : index
  %ni1 = arith.index_cast %nouts : i64 to index
  %ni2 = arith.index_cast %ninputs : i64 to index
  %ni3 = arith.index_cast %nsrcs : i64 to index
  %ni4 = arith.index_cast %nargs : i64 to index
  %ni5 = arith.index_cast %nenv : i64 to index
  %ol6, %oc7 = trikeshed.combineAll %ni1 : !s, !trikeshed.series<!trikeshed.twinpacked<i32>> {
  ^bb0(%k8: index):
  %i9 = arith.index_cast %k8 : index to i64
  %off11 = arith.muli %i9, %c10 : i64
  %ap12 = llvm.getelementptr %outs[%off11] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %ap14 = llvm.getelementptr %ap12[%c13] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %p15 = llvm.load %ap14 : !llvm.ptr -> !llvm.ptr
  %ap17 = llvm.getelementptr %ap12[%c16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %l18 = llvm.load %ap17 : !llvm.ptr -> i64
  %ap20 = llvm.getelementptr %ap12[%c19] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %p21 = llvm.load %ap20 : !llvm.ptr -> !llvm.ptr
  %ap23 = llvm.getelementptr %ap12[%c22] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %l24 = llvm.load %ap23 : !llvm.ptr -> i64
  %ap26 = llvm.getelementptr %ap12[%c25] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %p27 = llvm.load %ap26 : !llvm.ptr -> !llvm.ptr
  %ap29 = llvm.getelementptr %ap12[%c28] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %l30 = llvm.load %ap29 : !llvm.ptr -> i64
  %ap32 = llvm.getelementptr %ap12[%c31] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %p33 = llvm.load %ap32 : !llvm.ptr -> !llvm.ptr
  %ap35 = llvm.getelementptr %ap12[%c34] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %l36 = llvm.load %ap35 : !llvm.ptr -> i64
  %f38 = arith.cmpi eq, %k8, %c37 : index
  %g39 = memref.get_global @l_comma : memref<1xi8>
  %s40 = trikeshed.text %g39 : memref<1xi8> -> !s
  %sl41 = trikeshed.slice %s40[%c37, %c37] : !s -> !s
  %g42 = memref.get_global @l_comma : memref<1xi8>
  %s43 = trikeshed.text %g42 : memref<1xi8> -> !s
  %sl45 = trikeshed.slice %s43[%c37, %c44] : !s -> !s
  %sep46 = arith.select %f38, %sl41, %sl45 : !s
  %g47 = memref.get_global @l_open : memref<1xi8>
  %s48 = trikeshed.text %g47 : memref<1xi8> -> !s
  %sl49 = trikeshed.slice %s48[%c37, %c44] : !s -> !s
  %g50 = memref.get_global @l_comma : memref<1xi8>
  %s51 = trikeshed.text %g50 : memref<1xi8> -> !s
  %sl52 = trikeshed.slice %s51[%c37, %c44] : !s -> !s
  %g53 = memref.get_global @l_closep : memref<1xi8>
  %s54 = trikeshed.text %g53 : memref<1xi8> -> !s
  %sl55 = trikeshed.slice %s54[%c37, %c44] : !s -> !s
  %g56 = memref.get_global @l_quote : memref<1xi8>
  %s57 = trikeshed.text %g56 : memref<1xi8> -> !s
  %sl58 = trikeshed.slice %s57[%c37, %c44] : !s -> !s
  %d59 = func.call @nx_desc(%p15, %l18) : (!llvm.ptr, i64) -> !d
  %m60 = builtin.unrealized_conversion_cast %d59 : !d to !m
  %s61 = builtin.unrealized_conversion_cast %m60 : !m to !s
  %g62 = memref.get_global @l_quote : memref<1xi8>
  %s63 = trikeshed.text %g62 : memref<1xi8> -> !s
  %sl64 = trikeshed.slice %s63[%c37, %c44] : !s -> !s
  %q65 = trikeshed.combine %sl58, %s61, %sl64 : !s, !s, !s -> !s
  %g66 = memref.get_global @l_quote : memref<1xi8>
  %s67 = trikeshed.text %g66 : memref<1xi8> -> !s
  %sl68 = trikeshed.slice %s67[%c37, %c44] : !s -> !s
  %d69 = func.call @nx_desc(%p21, %l24) : (!llvm.ptr, i64) -> !d
  %m70 = builtin.unrealized_conversion_cast %d69 : !d to !m
  %s71 = builtin.unrealized_conversion_cast %m70 : !m to !s
  %g72 = memref.get_global @l_quote : memref<1xi8>
  %s73 = trikeshed.text %g72 : memref<1xi8> -> !s
  %sl74 = trikeshed.slice %s73[%c37, %c44] : !s -> !s
  %q75 = trikeshed.combine %sl68, %s71, %sl74 : !s, !s, !s -> !s
  %g76 = memref.get_global @l_quote : memref<1xi8>
  %s77 = trikeshed.text %g76 : memref<1xi8> -> !s
  %sl78 = trikeshed.slice %s77[%c37, %c44] : !s -> !s
  %d79 = func.call @nx_desc(%p27, %l30) : (!llvm.ptr, i64) -> !d
  %m80 = builtin.unrealized_conversion_cast %d79 : !d to !m
  %s81 = builtin.unrealized_conversion_cast %m80 : !m to !s
  %g82 = memref.get_global @l_quote : memref<1xi8>
  %s83 = trikeshed.text %g82 : memref<1xi8> -> !s
  %sl84 = trikeshed.slice %s83[%c37, %c44] : !s -> !s
  %q85 = trikeshed.combine %sl78, %s81, %sl84 : !s, !s, !s -> !s
  %g86 = memref.get_global @l_quote : memref<1xi8>
  %s87 = trikeshed.text %g86 : memref<1xi8> -> !s
  %sl88 = trikeshed.slice %s87[%c37, %c44] : !s -> !s
  %d89 = func.call @nx_desc(%p33, %l36) : (!llvm.ptr, i64) -> !d
  %m90 = builtin.unrealized_conversion_cast %d89 : !d to !m
  %s91 = builtin.unrealized_conversion_cast %m90 : !m to !s
  %g92 = memref.get_global @l_quote : memref<1xi8>
  %s93 = trikeshed.text %g92 : memref<1xi8> -> !s
  %sl94 = trikeshed.slice %s93[%c37, %c44] : !s -> !s
  %q95 = trikeshed.combine %sl88, %s91, %sl94 : !s, !s, !s -> !s
  %g96 = memref.get_global @l_comma : memref<1xi8>
  %s97 = trikeshed.text %g96 : memref<1xi8> -> !s
  %sl98 = trikeshed.slice %s97[%c37, %c44] : !s -> !s
  %g99 = memref.get_global @l_comma : memref<1xi8>
  %s100 = trikeshed.text %g99 : memref<1xi8> -> !s
  %sl101 = trikeshed.slice %s100[%c37, %c44] : !s -> !s
  %cb102 = trikeshed.combine %sep46, %sl49, %q65, %sl52, %q75, %sl98, %q85, %sl101, %q95, %sl55 : !s, !s, !s, !s, !s, !s, !s, !s, !s, !s -> !s
  trikeshed.yield %cb102 : !s
  }
  %il103, %ic104 = trikeshed.combineAll %ni2 : !s, !trikeshed.series<!trikeshed.twinpacked<i32>> {
  ^bb0(%k105: index):
  %i106 = arith.index_cast %k105 : index to i64
  %off107 = arith.muli %i106, %c25 : i64
  %ap108 = llvm.getelementptr %inputs[%off107] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %ap109 = llvm.getelementptr %ap108[%c13] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %p110 = llvm.load %ap109 : !llvm.ptr -> !llvm.ptr
  %ap111 = llvm.getelementptr %ap108[%c16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %l112 = llvm.load %ap111 : !llvm.ptr -> i64
  %ap113 = llvm.getelementptr %ap108[%c19] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %p114 = llvm.load %ap113 : !llvm.ptr -> !llvm.ptr
  %ap115 = llvm.getelementptr %ap108[%c22] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %l116 = llvm.load %ap115 : !llvm.ptr -> i64
  %ni117 = arith.index_cast %l116 : i64 to index
  %f118 = arith.cmpi eq, %k105, %c37 : index
  %g119 = memref.get_global @l_comma : memref<1xi8>
  %s120 = trikeshed.text %g119 : memref<1xi8> -> !s
  %sl121 = trikeshed.slice %s120[%c37, %c37] : !s -> !s
  %g122 = memref.get_global @l_comma : memref<1xi8>
  %s123 = trikeshed.text %g122 : memref<1xi8> -> !s
  %sl124 = trikeshed.slice %s123[%c37, %c44] : !s -> !s
  %sep125 = arith.select %f118, %sl121, %sl124 : !s
  %g126 = memref.get_global @l_open : memref<1xi8>
  %s127 = trikeshed.text %g126 : memref<1xi8> -> !s
  %sl128 = trikeshed.slice %s127[%c37, %c44] : !s -> !s
  %g129 = memref.get_global @l_quote : memref<1xi8>
  %s130 = trikeshed.text %g129 : memref<1xi8> -> !s
  %sl131 = trikeshed.slice %s130[%c37, %c44] : !s -> !s
  %d132 = func.call @nx_desc(%p110, %l112) : (!llvm.ptr, i64) -> !d
  %m133 = builtin.unrealized_conversion_cast %d132 : !d to !m
  %s134 = builtin.unrealized_conversion_cast %m133 : !m to !s
  %g135 = memref.get_global @l_quote : memref<1xi8>
  %s136 = trikeshed.text %g135 : memref<1xi8> -> !s
  %sl137 = trikeshed.slice %s136[%c37, %c44] : !s -> !s
  %q138 = trikeshed.combine %sl131, %s134, %sl137 : !s, !s, !s -> !s
  %g139 = memref.get_global @l_obrk : memref<2xi8>
  %s140 = trikeshed.text %g139 : memref<2xi8> -> !s
  %nl141, %nc142 = trikeshed.combineAll %ni117 : !s, !trikeshed.series<!trikeshed.twinpacked<i32>> {
  ^bb0(%j143: index):
  %i144 = arith.index_cast %j143 : index to i64
  %off145 = arith.muli %i144, %c19 : i64
  %ap146 = llvm.getelementptr %p114[%off145] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %ap147 = llvm.getelementptr %ap146[%c13] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %p148 = llvm.load %ap147 : !llvm.ptr -> !llvm.ptr
  %ap149 = llvm.getelementptr %ap146[%c16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %l150 = llvm.load %ap149 : !llvm.ptr -> i64
  %f151 = arith.cmpi eq, %j143, %c37 : index
  %g152 = memref.get_global @l_comma : memref<1xi8>
  %s153 = trikeshed.text %g152 : memref<1xi8> -> !s
  %sl154 = trikeshed.slice %s153[%c37, %c37] : !s -> !s
  %g155 = memref.get_global @l_comma : memref<1xi8>
  %s156 = trikeshed.text %g155 : memref<1xi8> -> !s
  %sl157 = trikeshed.slice %s156[%c37, %c44] : !s -> !s
  %sep158 = arith.select %f151, %sl154, %sl157 : !s
  %g159 = memref.get_global @l_quote : memref<1xi8>
  %s160 = trikeshed.text %g159 : memref<1xi8> -> !s
  %sl161 = trikeshed.slice %s160[%c37, %c44] : !s -> !s
  %d162 = func.call @nx_desc(%p148, %l150) : (!llvm.ptr, i64) -> !d
  %m163 = builtin.unrealized_conversion_cast %d162 : !d to !m
  %s164 = builtin.unrealized_conversion_cast %m163 : !m to !s
  %g165 = memref.get_global @l_quote : memref<1xi8>
  %s166 = trikeshed.text %g165 : memref<1xi8> -> !s
  %sl167 = trikeshed.slice %s166[%c37, %c44] : !s -> !s
  %q168 = trikeshed.combine %sl161, %s164, %sl167 : !s, !s, !s -> !s
  %cb169 = trikeshed.combine %sep158, %q168 : !s, !s -> !s
  trikeshed.yield %cb169 : !s
  }
  %g170 = memref.get_global @l_close : memref<2xi8>
  %s171 = trikeshed.text %g170 : memref<2xi8> -> !s
  %cb172 = trikeshed.combine %sep125, %sl128, %q138, %s140, %nl141, %s171 : !s, !s, !s, !s, !s, !s -> !s
  trikeshed.yield %cb172 : !s
  }
  %sl173, %sc174 = trikeshed.combineAll %ni3 : !s, !trikeshed.series<!trikeshed.twinpacked<i32>> {
  ^bb0(%k175: index):
  %i176 = arith.index_cast %k175 : index to i64
  %off177 = arith.muli %i176, %c19 : i64
  %ap178 = llvm.getelementptr %srcs[%off177] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %ap179 = llvm.getelementptr %ap178[%c13] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %p180 = llvm.load %ap179 : !llvm.ptr -> !llvm.ptr
  %ap181 = llvm.getelementptr %ap178[%c16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %l182 = llvm.load %ap181 : !llvm.ptr -> i64
  %f183 = arith.cmpi eq, %k175, %c37 : index
  %g184 = memref.get_global @l_comma : memref<1xi8>
  %s185 = trikeshed.text %g184 : memref<1xi8> -> !s
  %sl186 = trikeshed.slice %s185[%c37, %c37] : !s -> !s
  %g187 = memref.get_global @l_comma : memref<1xi8>
  %s188 = trikeshed.text %g187 : memref<1xi8> -> !s
  %sl189 = trikeshed.slice %s188[%c37, %c44] : !s -> !s
  %sep190 = arith.select %f183, %sl186, %sl189 : !s
  %g191 = memref.get_global @l_quote : memref<1xi8>
  %s192 = trikeshed.text %g191 : memref<1xi8> -> !s
  %sl193 = trikeshed.slice %s192[%c37, %c44] : !s -> !s
  %d194 = func.call @nx_desc(%p180, %l182) : (!llvm.ptr, i64) -> !d
  %m195 = builtin.unrealized_conversion_cast %d194 : !d to !m
  %s196 = builtin.unrealized_conversion_cast %m195 : !m to !s
  %g197 = memref.get_global @l_quote : memref<1xi8>
  %s198 = trikeshed.text %g197 : memref<1xi8> -> !s
  %sl199 = trikeshed.slice %s198[%c37, %c44] : !s -> !s
  %q200 = trikeshed.combine %sl193, %s196, %sl199 : !s, !s, !s -> !s
  %cb201 = trikeshed.combine %sep190, %q200 : !s, !s -> !s
  trikeshed.yield %cb201 : !s
  }
  %al202, %ac203 = trikeshed.combineAll %ni4 : !s, !trikeshed.series<!trikeshed.twinpacked<i32>> {
  ^bb0(%k204: index):
  %i205 = arith.index_cast %k204 : index to i64
  %off206 = arith.muli %i205, %c19 : i64
  %ap207 = llvm.getelementptr %args[%off206] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %ap208 = llvm.getelementptr %ap207[%c13] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %p209 = llvm.load %ap208 : !llvm.ptr -> !llvm.ptr
  %ap210 = llvm.getelementptr %ap207[%c16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %l211 = llvm.load %ap210 : !llvm.ptr -> i64
  %f212 = arith.cmpi eq, %k204, %c37 : index
  %g213 = memref.get_global @l_comma : memref<1xi8>
  %s214 = trikeshed.text %g213 : memref<1xi8> -> !s
  %sl215 = trikeshed.slice %s214[%c37, %c37] : !s -> !s
  %g216 = memref.get_global @l_comma : memref<1xi8>
  %s217 = trikeshed.text %g216 : memref<1xi8> -> !s
  %sl218 = trikeshed.slice %s217[%c37, %c44] : !s -> !s
  %sep219 = arith.select %f212, %sl215, %sl218 : !s
  %g220 = memref.get_global @l_quote : memref<1xi8>
  %s221 = trikeshed.text %g220 : memref<1xi8> -> !s
  %sl222 = trikeshed.slice %s221[%c37, %c44] : !s -> !s
  %d223 = func.call @nx_desc(%p209, %l211) : (!llvm.ptr, i64) -> !d
  %m224 = builtin.unrealized_conversion_cast %d223 : !d to !m
  %s225 = builtin.unrealized_conversion_cast %m224 : !m to !s
  %ni226 = arith.index_cast %l211 : i64 to index
  %g227 = memref.get_global @esc_tab : memref<512xi8>
  %t228 = trikeshed.text %g227 : memref<512xi8> -> !s
  %g229 = memref.get_global @esc_len : memref<256xi8>
  %t230 = trikeshed.text %g229 : memref<256xi8> -> !s
  %ev232, %ec233 = trikeshed.combineAll %ni226 : !s, !trikeshed.series<!trikeshed.twinpacked<i32>> {
  ^bb0(%j234: index):
    %b235 = trikeshed.at %s225[%j234] : !s, index -> i8
    %bi236 = arith.index_castui %b235 : i8 to index
    %bl237 = trikeshed.at %t230[%bi236] : !s, index -> i8
    %bli238 = arith.index_castui %bl237 : i8 to index
    %at239 = arith.muli %bi236, %c231 : index
    %p240 = trikeshed.slice %t228[%at239, %bli238] : !s -> !s
    trikeshed.yield %p240 : !s
  }
  %g241 = memref.get_global @l_quote : memref<1xi8>
  %s242 = trikeshed.text %g241 : memref<1xi8> -> !s
  %sl243 = trikeshed.slice %s242[%c37, %c44] : !s -> !s
  %e244 = trikeshed.combine %sl222, %ev232, %sl243 : !s, !s, !s -> !s
  %cb245 = trikeshed.combine %sep219, %e244 : !s, !s -> !s
  trikeshed.yield %cb245 : !s
  }
  %el246, %ec247 = trikeshed.combineAll %ni5 : !s, !trikeshed.series<!trikeshed.twinpacked<i32>> {
  ^bb0(%k248: index):
  %i249 = arith.index_cast %k248 : index to i64
  %off250 = arith.muli %i249, %c25 : i64
  %ap251 = llvm.getelementptr %env[%off250] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %ap252 = llvm.getelementptr %ap251[%c13] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %p253 = llvm.load %ap252 : !llvm.ptr -> !llvm.ptr
  %ap254 = llvm.getelementptr %ap251[%c16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %l255 = llvm.load %ap254 : !llvm.ptr -> i64
  %ap256 = llvm.getelementptr %ap251[%c19] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %p257 = llvm.load %ap256 : !llvm.ptr -> !llvm.ptr
  %ap258 = llvm.getelementptr %ap251[%c22] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %l259 = llvm.load %ap258 : !llvm.ptr -> i64
  %f260 = arith.cmpi eq, %k248, %c37 : index
  %g261 = memref.get_global @l_comma : memref<1xi8>
  %s262 = trikeshed.text %g261 : memref<1xi8> -> !s
  %sl263 = trikeshed.slice %s262[%c37, %c37] : !s -> !s
  %g264 = memref.get_global @l_comma : memref<1xi8>
  %s265 = trikeshed.text %g264 : memref<1xi8> -> !s
  %sl266 = trikeshed.slice %s265[%c37, %c44] : !s -> !s
  %sep267 = arith.select %f260, %sl263, %sl266 : !s
  %g268 = memref.get_global @l_open : memref<1xi8>
  %s269 = trikeshed.text %g268 : memref<1xi8> -> !s
  %sl270 = trikeshed.slice %s269[%c37, %c44] : !s -> !s
  %g271 = memref.get_global @l_comma : memref<1xi8>
  %s272 = trikeshed.text %g271 : memref<1xi8> -> !s
  %sl273 = trikeshed.slice %s272[%c37, %c44] : !s -> !s
  %g274 = memref.get_global @l_closep : memref<1xi8>
  %s275 = trikeshed.text %g274 : memref<1xi8> -> !s
  %sl276 = trikeshed.slice %s275[%c37, %c44] : !s -> !s
  %g277 = memref.get_global @l_quote : memref<1xi8>
  %s278 = trikeshed.text %g277 : memref<1xi8> -> !s
  %sl279 = trikeshed.slice %s278[%c37, %c44] : !s -> !s
  %d280 = func.call @nx_desc(%p253, %l255) : (!llvm.ptr, i64) -> !d
  %m281 = builtin.unrealized_conversion_cast %d280 : !d to !m
  %s282 = builtin.unrealized_conversion_cast %m281 : !m to !s
  %ni283 = arith.index_cast %l255 : i64 to index
  %g284 = memref.get_global @esc_tab : memref<512xi8>
  %t285 = trikeshed.text %g284 : memref<512xi8> -> !s
  %g286 = memref.get_global @esc_len : memref<256xi8>
  %t287 = trikeshed.text %g286 : memref<256xi8> -> !s
  %ev288, %ec289 = trikeshed.combineAll %ni283 : !s, !trikeshed.series<!trikeshed.twinpacked<i32>> {
  ^bb0(%j290: index):
    %b291 = trikeshed.at %s282[%j290] : !s, index -> i8
    %bi292 = arith.index_castui %b291 : i8 to index
    %bl293 = trikeshed.at %t287[%bi292] : !s, index -> i8
    %bli294 = arith.index_castui %bl293 : i8 to index
    %at295 = arith.muli %bi292, %c231 : index
    %p296 = trikeshed.slice %t285[%at295, %bli294] : !s -> !s
    trikeshed.yield %p296 : !s
  }
  %g297 = memref.get_global @l_quote : memref<1xi8>
  %s298 = trikeshed.text %g297 : memref<1xi8> -> !s
  %sl299 = trikeshed.slice %s298[%c37, %c44] : !s -> !s
  %e300 = trikeshed.combine %sl279, %ev288, %sl299 : !s, !s, !s -> !s
  %g301 = memref.get_global @l_quote : memref<1xi8>
  %s302 = trikeshed.text %g301 : memref<1xi8> -> !s
  %sl303 = trikeshed.slice %s302[%c37, %c44] : !s -> !s
  %d304 = func.call @nx_desc(%p257, %l259) : (!llvm.ptr, i64) -> !d
  %m305 = builtin.unrealized_conversion_cast %d304 : !d to !m
  %s306 = builtin.unrealized_conversion_cast %m305 : !m to !s
  %ni307 = arith.index_cast %l259 : i64 to index
  %g308 = memref.get_global @esc_tab : memref<512xi8>
  %t309 = trikeshed.text %g308 : memref<512xi8> -> !s
  %g310 = memref.get_global @esc_len : memref<256xi8>
  %t311 = trikeshed.text %g310 : memref<256xi8> -> !s
  %ev312, %ec313 = trikeshed.combineAll %ni307 : !s, !trikeshed.series<!trikeshed.twinpacked<i32>> {
  ^bb0(%j314: index):
    %b315 = trikeshed.at %s306[%j314] : !s, index -> i8
    %bi316 = arith.index_castui %b315 : i8 to index
    %bl317 = trikeshed.at %t311[%bi316] : !s, index -> i8
    %bli318 = arith.index_castui %bl317 : i8 to index
    %at319 = arith.muli %bi316, %c231 : index
    %p320 = trikeshed.slice %t309[%at319, %bli318] : !s -> !s
    trikeshed.yield %p320 : !s
  }
  %g321 = memref.get_global @l_quote : memref<1xi8>
  %s322 = trikeshed.text %g321 : memref<1xi8> -> !s
  %sl323 = trikeshed.slice %s322[%c37, %c44] : !s -> !s
  %e324 = trikeshed.combine %sl303, %ev312, %sl323 : !s, !s, !s -> !s
  %cb325 = trikeshed.combine %sep267, %sl270, %e300, %sl273, %e324, %sl276 : !s, !s, !s, !s, !s, !s -> !s
  trikeshed.yield %cb325 : !s
  }
  %g326 = memref.get_global @l_derive : memref<8xi8>
  %s327 = trikeshed.text %g326 : memref<8xi8> -> !s
  %g328 = memref.get_global @l_brk : memref<3xi8>
  %s329 = trikeshed.text %g328 : memref<3xi8> -> !s
  %g330 = memref.get_global @l_brk : memref<3xi8>
  %s331 = trikeshed.text %g330 : memref<3xi8> -> !s
  %g332 = memref.get_global @l_brk : memref<3xi8>
  %s333 = trikeshed.text %g332 : memref<3xi8> -> !s
  %g334 = memref.get_global @l_brk2 : memref<2xi8>
  %s335 = trikeshed.text %g334 : memref<2xi8> -> !s
  %g336 = memref.get_global @l_quote : memref<1xi8>
  %s337 = trikeshed.text %g336 : memref<1xi8> -> !s
  %sl338 = trikeshed.slice %s337[%c37, %c44] : !s -> !s
  %d339 = func.call @nx_desc(%platform, %platformLen) : (!llvm.ptr, i64) -> !d
  %m340 = builtin.unrealized_conversion_cast %d339 : !d to !m
  %s341 = builtin.unrealized_conversion_cast %m340 : !m to !s
  %g342 = memref.get_global @l_quote : memref<1xi8>
  %s343 = trikeshed.text %g342 : memref<1xi8> -> !s
  %sl344 = trikeshed.slice %s343[%c37, %c44] : !s -> !s
  %q345 = trikeshed.combine %sl338, %s341, %sl344 : !s, !s, !s -> !s
  %g346 = memref.get_global @l_comma : memref<1xi8>
  %s347 = trikeshed.text %g346 : memref<1xi8> -> !s
  %sl348 = trikeshed.slice %s347[%c37, %c44] : !s -> !s
  %g349 = memref.get_global @l_quote : memref<1xi8>
  %s350 = trikeshed.text %g349 : memref<1xi8> -> !s
  %sl351 = trikeshed.slice %s350[%c37, %c44] : !s -> !s
  %d352 = func.call @nx_desc(%builder, %builderLen) : (!llvm.ptr, i64) -> !d
  %m353 = builtin.unrealized_conversion_cast %d352 : !d to !m
  %s354 = builtin.unrealized_conversion_cast %m353 : !m to !s
  %ni355 = arith.index_cast %builderLen : i64 to index
  %g356 = memref.get_global @esc_tab : memref<512xi8>
  %t357 = trikeshed.text %g356 : memref<512xi8> -> !s
  %g358 = memref.get_global @esc_len : memref<256xi8>
  %t359 = trikeshed.text %g358 : memref<256xi8> -> !s
  %ev360, %ec361 = trikeshed.combineAll %ni355 : !s, !trikeshed.series<!trikeshed.twinpacked<i32>> {
  ^bb0(%j362: index):
    %b363 = trikeshed.at %s354[%j362] : !s, index -> i8
    %bi364 = arith.index_castui %b363 : i8 to index
    %bl365 = trikeshed.at %t359[%bi364] : !s, index -> i8
    %bli366 = arith.index_castui %bl365 : i8 to index
    %at367 = arith.muli %bi364, %c231 : index
    %p368 = trikeshed.slice %t357[%at367, %bli366] : !s -> !s
    trikeshed.yield %p368 : !s
  }
  %g369 = memref.get_global @l_quote : memref<1xi8>
  %s370 = trikeshed.text %g369 : memref<1xi8> -> !s
  %sl371 = trikeshed.slice %s370[%c37, %c44] : !s -> !s
  %e372 = trikeshed.combine %sl351, %ev360, %sl371 : !s, !s, !s -> !s
  %g373 = memref.get_global @l_obrk : memref<2xi8>
  %s374 = trikeshed.text %g373 : memref<2xi8> -> !s
  %g375 = memref.get_global @l_close : memref<2xi8>
  %s376 = trikeshed.text %g375 : memref<2xi8> -> !s
  %cb377 = trikeshed.combine %s327, %ol6, %s329, %il103, %s331, %sl173, %s335, %q345, %sl348, %e372, %s374, %al202, %s333, %el246, %s376 : !s, !s, !s, !s, !s, !s, !s, !s, !s, !s, !s, !s, !s, !s, !s -> !s
  %sz378 = trikeshed.size %cb377 : !s
  %sz379 = arith.index_cast %sz378 : index to i64
  %neg380 = arith.subi %c13, %sz379 : i64
  %tb381 = arith.cmpi ult, %cap, %sz379 : i64
  %r382 = scf.if %tb381 -> i64 {
    scf.yield %neg380 : i64
  } else {
  %d383 = func.call @nx_desc(%into, %cap) : (!llvm.ptr, i64) -> !d
    %m384 = builtin.unrealized_conversion_cast %d383 : !d to !m
    %end385 = trikeshed.drain %cb377, %m384 : !s, !m -> index
    %w386 = arith.index_cast %end385 : index to i64
    scf.yield %w386 : i64
  }
  return %r382 : i64
  }
