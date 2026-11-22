// The tool-scale fill-drain of tools/mlnix.cpp hollowed into the TrikeShed dialect: the NIX_PATH split
// (parseNixPath), the help text (printHelp), the nix command's argv-list escaping and expression, the
// eval/parse/emit-mlir/run-mlir argv splice, and cmdStore --print-env's block.  mlnix.cpp keeps only the bridges
// that marshal windows and call these neutral C-ABI entries; the text algebra is here, in trikeshed.slice /
// combine / combineAll / compare / at / series / drain, lowered by --trikeshed-lower-cursors and the stock buffer
// pipeline (tools/CMakeLists.txt mlnix_lower_trikeshed into the mlnix executable).
//
// Every text entry uses the capacity protocol: it sizes the lazy combine, returns -need-2 when cap < need (the
// bridge resizes and calls again), else drains once into the caller's room and returns the bytes written.
// parseNixPath writes 4-i64 records (prefix off/len, path off/len, windows into the input) and returns the count
// or -count-2.  The argv splice drains a series of pointer bits into the caller's char* array.  Nothing here throws:
// the bridges keep usage()/exit, the store/eval calls, getenv and the error wording.
//
// Helper names are module-unique (to_*): convert-func-to-llvm exports a func.func private as a global symbol.
!b = !trikeshed.series<i8>
!q = !trikeshed.series<i64>
!s32 = !trikeshed.series<i32>
!tp = !trikeshed.twinpacked<i32>
!sp = !trikeshed.series<!tp>
!m = memref<?xi8, strided<[1], offset: ?>>
!m64 = memref<?xi64, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

memref.global "private" constant @to_help : memref<1379xi8> = dense<"0x6D6C6E6978202D2061204E697820696D706C656D656E746174696F6E206275696C74206F6E20616E204D4C4952206469616C6563740A0A55736167653A0A20206D6C6E697820696E7374616E7469617465205B6F7074696F6E735D205B46494C45207C202D4520455850525D2E2E2E202020286C696B65206E69782D696E7374616E7469617465290A20206D6C6E6978206275696C64202020202020205B6F7074696F6E735D205B46494C45207C202D4520455850525D2E2E2E202020286C696B65206E69782D6275696C64290A20206D6C6E6978206576616C20202020202020205B6F7074696F6E735D205B46494C45207C202D4520455850525D202020202020283D20696E7374616E7469617465202D2D6576616C202D2D737472696374290A20206D6C6E6978207061727365202020202020205B46494C45207C202D4520455850525D20202020202020202020202020202020283D20696E7374616E7469617465202D2D7061727365290A20206D6C6E697820656D69742D6D6C69722020205B2D2D6E6F2D6F70745D205B46494C45207C202D4520455850525D20202020207072696E7420746865206E6978206469616C6563742049520A20206D6C6E69782072756E2D6D6C69722020202046494C452E6D6C6972205B2D4120415454525D202020202020202020202020206576616C75617465206E6978206469616C6563742049520A20206D6C6E69782073746F7265202020202020202D2D6164647C2D2D6164642D66697865647C2D2D7265616C6973657C2D2D71756572797C2D2D64756D707C2D2D726573746F72657C2D2D67637C2D2D64656C6574657C2D2D766572696679202E2E2E0A20206D6C6E697820686173682020202020202020706174687C66696C657C2D2D746F2D6261736533327C2D2D746F2D6261736531367C2D2D746F2D737269205B2D2D7479706520414C474F5D205B2D2D7372697C2D2D6261736533325D202E2E2E0A20206D6C6E69782064657269766174696F6E202073686F77204452562E2E2E0A0A436F6D6D6F6E206F7074696F6E733A0A20202D41204154545220202D2D617267204E414D45204558505220202D2D617267737472204E414D452053545220202D49205041544820202D2D73686F772D74726163650A20202D2D73746F72652D646972204449522020206C6F676963616C2073746F7265206469726563746F7279202864656661756C74202F6E69782F73746F72652C206F7220244E49585F53544F52455F444952290A20202D2D73746F726520524F4F54202020202020706879736963616C20726F6F74206F662061206368726F6F742073746F726520286C6F63616C3F726F6F743D524F4F54292C206F722064756D6D793A2F2F0A20202D2D726561646F6E6C792D6D6F6465202020636F6D707574652073746F726520706174687320776974686F75742077726974696E670A20202D2D65787472612D6578706572696D656E74616C2D666561747572657320706970652D6F70657261746F72737C70617273652D746F6D6C2D74696D657374616D70730A0A5768656E20696E766F6B6564206173206E69782D696E7374616E74696174652C206E69782D6275696C642C206E69782D73746F7265206F72206E69782D686173682C206D6C6E69780A62656861766573206C696B652074686520636F72726573706F6E64696E67204E697820636F6D6D616E642E2020496E766F6B6564206173206E697820697420697320746865206E697820636F6D6D616E643A0A20206E6978206275696C647C6576616C7C72756E2052454623415454522C206E69782070726F66696C65206164647C6C6973747C72656D6F76652052454623415454522C206E69782064657269766174696F6E7C686173687C73746F72650A">
memref.global "private" constant @to_hoff : memref<23xi32> = dense<[0, 54, 55, 62, 137, 206, 290, 366, 443, 519, 619, 717, 749, 750, 766, 835, 919, 1002, 1058, 1127, 1128, 1201, 1284]>
memref.global "private" constant @to_hlen : memref<23xi32> = dense<[54, 1, 7, 75, 69, 84, 76, 77, 76, 100, 98, 32, 1, 16, 69, 84, 83, 56, 69, 1, 73, 83, 95]>
memref.global "private" constant @to_esc : memref<512xi8> = dense<"0x00000100020003000400050006000700080009005C6E0B000C000D000E000F0010001100120013001400150016001700180019001A001B001C001D001E001F00200021005C2223005C24250026002700280029002A002B002C002D002E002F0030003100320033003400350036003700380039003A003B003C003D003E003F0040004100420043004400450046004700480049004A004B004C004D004E004F0050005100520053005400550056005700580059005A005B005C5C5D005E005F0060006100620063006400650066006700680069006A006B006C006D006E006F0070007100720073007400750076007700780079007A007B007C007D007E007F0080008100820083008400850086008700880089008A008B008C008D008E008F0090009100920093009400950096009700980099009A009B009C009D009E009F00A000A100A200A300A400A500A600A700A800A900AA00AB00AC00AD00AE00AF00B000B100B200B300B400B500B600B700B800B900BA00BB00BC00BD00BE00BF00C000C100C200C300C400C500C600C700C800C900CA00CB00CC00CD00CE00CF00D000D100D200D300D400D500D600D700D800D900DA00DB00DC00DD00DE00DF00E000E100E200E300E400E500E600E700E800E900EA00EB00EC00ED00EE00EF00F000F100F200F300F400F500F600F700F800F900FA00FB00FC00FD00FE00FF00">
memref.global "private" constant @to_esclen : memref<256xi8> = dense<"0x01010101010101010101020101010101010101010101010101010101010101010101020101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010201010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101">
memref.global "private" constant @to_blob : memref<76xi8> = dense<"0x6578706F7274203B203D27270A6578706F7274205F617267733B205F617267733D272028696D706F7274203C6E69782F636C692E6E69783E29207B2061726773203D205B202222205D3B207D">
memref.global "private" constant @to_woff : memref<10xi32> = dense<[0, 7, 9, 11, 13, 34, 35, 68, 70, 71]>
memref.global "private" constant @to_wlen : memref<10xi32> = dense<[7, 2, 2, 2, 21, 1, 33, 2, 1, 5]>
memref.global "private" constant @to_f_eval : memref<7xi8> = dense<"0x2D2D6576616C00">
memref.global "private" constant @to_f_strict : memref<9xi8> = dense<"0x2D2D73747269637400">
memref.global "private" constant @to_f_parse : memref<8xi8> = dense<"0x2D2D706172736500">
memref.global "private" constant @to_f_emit : memref<12xi8> = dense<"0x2D2D656D69742D6D6C697200">

func.func private @to_desc(%p: !llvm.ptr, %n: i64) -> !d {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %u = llvm.mlir.undef : !d
  %a = llvm.insertvalue %p, %u[0] : !d
  %bb = llvm.insertvalue %p, %a[1] : !d
  %c = llvm.insertvalue %c0, %bb[2] : !d
  %e = llvm.insertvalue %n, %c[3, 0] : !d
  %f = llvm.insertvalue %c1, %e[4, 0] : !d
  return %f : !d
}

func.func private @to_np_end(%xs: !b, %i: index, %n: index) -> index {
  %one = arith.constant 1 : index
  %three = arith.constant 3 : index
  %zero = arith.constant 0 : index
  %colon = arith.constant 58 : i8
  %slash = arith.constant 47 : i8
  %true = arith.constant 1 : i1
  %nm1 = arith.subi %n, %one : index
  %r = scf.while (%j = %i) : (index) -> index {
    %in = arith.cmpi ult, %j, %n : index
    %jc = arith.minsi %j, %nm1 : index
    %c = trikeshed.at %xs[%jc] : !b, index -> i8
    %iscolon = arith.cmpi eq, %c, %colon : i8
    %jp3 = arith.addi %j, %three : index
    %fits = arith.cmpi ule, %jp3, %n : index
    %jp1 = arith.addi %j, %one : index
    %s1 = arith.minsi %jp1, %nm1 : index
    %b1 = trikeshed.at %xs[%s1] : !b, index -> i8
    %jp2 = arith.addi %j, %three : index
    %s2b = arith.subi %jp2, %one : index
    %s2 = arith.minsi %s2b, %nm1 : index
    %b2 = trikeshed.at %xs[%s2] : !b, index -> i8
    %u1 = arith.cmpi eq, %b1, %slash : i8
    %u2 = arith.cmpi eq, %b2, %slash : i8
    %u12 = arith.andi %u1, %u2 : i1
    %isurl = arith.andi %fits, %u12 : i1
    %adv3 = arith.andi %iscolon, %isurl : i1
    %notcolon = arith.xori %iscolon, %true : i1
    %adv1 = arith.andi %in, %notcolon : i1
    %go = arith.ori %adv1, %adv3 : i1
    %d3 = arith.select %adv3, %three, %zero : index
    %d1 = arith.select %adv1, %one, %zero : index
    %delta = arith.addi %d3, %d1 : index
    %nj = arith.addi %j, %delta : index
    scf.condition(%go) %nj : index
  } do {
  ^bb0(%j: index):
    scf.yield %j : index
  }
  return %r : index
}

func.func private @to_np_eq(%xs: !b, %i: index, %j: index) -> index {
  %one = arith.constant 1 : index
  %eq = arith.constant 61 : i8
  %true = arith.constant 1 : i1
  %r = scf.for %t = %i to %j step %one iter_args(%found = %j) -> (index) {
    %c = trikeshed.at %xs[%t] : !b, index -> i8
    %iseq = arith.cmpi eq, %c, %eq : i8
    %unset = arith.cmpi eq, %found, %j : index
    %take = arith.andi %iseq, %unset : i1
    %f2 = arith.select %take, %t, %found : index
    scf.yield %f2 : index
  }
  return %r : index
}

func.func @mlnix_ts_nixpath(%p: !llvm.ptr, %n: i64, %recs: !llvm.ptr, %cap: i64) -> i64 {
  %v5 = arith.constant 0 : index
  %v6 = arith.constant 1 : index
  %v7 = arith.constant 4 : index
  %v15 = arith.constant -2 : i64
  %v33 = arith.constant 2 : index
  %v34 = arith.constant 3 : index
  %v1 = func.call @to_desc(%p, %n) : (!llvm.ptr, i64) -> !d
  %v2 = builtin.unrealized_conversion_cast %v1 : !d to !m
  %v3 = builtin.unrealized_conversion_cast %v2 : !m to !b
  %v4 = arith.index_cast %n : i64 to index
  %v8:2 = scf.while (%i = %v5, %c = %v5) : (index, index) -> (index, index) {
    %in = arith.cmpi ult, %i, %v4 : index
    scf.condition(%in) %i, %c : index, index
  } do {
  ^bb0(%i: index, %c: index):
    %v9 = func.call @to_np_end(%v3, %i, %v4) : (!b, index, index) -> index
    %v10 = arith.cmpi ult, %i, %v9 : index
    %v11 = arith.select %v10, %v6, %v5 : index
    %v12 = arith.addi %c, %v11 : index
    %v13 = arith.addi %v9, %v6 : index
    scf.yield %v13, %v12 : index, index
  }
  %v14 = arith.index_cast %v8#1 : index to i64
  %v16 = arith.subi %v15, %v14 : i64
  %v17 = arith.cmpi ult, %cap, %v14 : i64
  %v18 = func.call @to_desc(%recs, %cap) : (!llvm.ptr, i64) -> !d
  %v19 = builtin.unrealized_conversion_cast %v18 : !d to !m64
  %v20 = scf.if %v17 -> i64 {
    scf.yield %v16 : i64
  } else {
    %wres:2 = scf.while (%wi = %v5, %k = %v5) : (index, index) -> (index, index) {
      %win = arith.cmpi ult, %wi, %v4 : index
      scf.condition(%win) %wi, %k : index, index
    } do {
    ^bb0(%wi: index, %k: index):
      %v21 = func.call @to_np_end(%v3, %wi, %v4) : (!b, index, index) -> index
      %v22 = arith.cmpi ult, %wi, %v21 : index
      %v23 = scf.if %v22 -> (index) {
        %v24 = func.call @to_np_eq(%v3, %wi, %v21) : (!b, index, index) -> index
        %v25 = arith.cmpi ult, %v24, %v21 : index
        %v26 = arith.subi %v24, %wi : index
        %v27 = arith.select %v25, %v26, %v5 : index
        %v28 = arith.addi %v24, %v6 : index
        %v29 = arith.select %v25, %v28, %wi : index
        %v30 = arith.subi %v21, %v29 : index
        %v31 = arith.muli %k, %v7 : index
        %v32 = arith.addi %v31, %v6 : index
        %v35 = arith.addi %v31, %v33 : index
        %v36 = arith.addi %v31, %v34 : index
        %v37 = arith.index_cast %wi : index to i64
        %v38 = arith.index_cast %v27 : index to i64
        %v39 = arith.index_cast %v29 : index to i64
        %v40 = arith.index_cast %v30 : index to i64
        memref.store %v37, %v19[%v31] : !m64
        memref.store %v38, %v19[%v32] : !m64
        memref.store %v39, %v19[%v35] : !m64
        memref.store %v40, %v19[%v36] : !m64
        %v41 = arith.addi %k, %v6 : index
        scf.yield %v41 : index
      } else {
        scf.yield %k : index
      }
      %v42 = arith.addi %v21, %v6 : index
      scf.yield %v42, %v23 : index, index
    }
    scf.yield %v14 : i64
  }
  return %v20 : i64
}

func.func @mlnix_ts_help(%into: !llvm.ptr, %cap: i64) -> i64 {
  %v7 = arith.constant 23 : index
  %v17 = arith.constant -2 : i64
  %v1 = memref.get_global @to_help : memref<1379xi8>
  %v2 = trikeshed.text %v1 : memref<1379xi8> -> !b
  %v3 = memref.get_global @to_hoff : memref<23xi32>
  %v4 = trikeshed.text %v3 : memref<23xi32> -> !s32
  %v5 = memref.get_global @to_hlen : memref<23xi32>
  %v6 = trikeshed.text %v5 : memref<23xi32> -> !s32
  %v8, %v9 = trikeshed.combineAll %v7 : !b, !sp {
  ^bb0(%k: index):
    %v10 = trikeshed.at %v4[%k] : !s32, index -> i32
    %v11 = trikeshed.at %v6[%k] : !s32, index -> i32
    %v12 = arith.index_cast %v10 : i32 to index
    %v13 = arith.index_cast %v11 : i32 to index
    %v14 = trikeshed.slice %v2[%v12, %v13] : !b -> !b
    trikeshed.yield %v14 : !b
  }
  %v15 = trikeshed.size %v8 : !b
  %v16 = arith.index_cast %v15 : index to i64
  %v18 = arith.subi %v17, %v16 : i64
  %v19 = arith.cmpi ult, %cap, %v16 : i64
  %v20 = scf.if %v19 -> i64 {
    scf.yield %v18 : i64
  } else {
  %v21 = func.call @to_desc(%into, %cap) : (!llvm.ptr, i64) -> !d
    %v22 = builtin.unrealized_conversion_cast %v21 : !d to !m
    %v23 = trikeshed.drain %v8, %v22 : !b, !m -> index
    %v24 = arith.index_cast %v23 : index to i64
    scf.yield %v24 : i64
  }
  return %v20 : i64
}

func.func @mlnix_ts_nixlist(%wins: !llvm.ptr, %n: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %v1 = arith.constant 2 : i64
  %v15 = arith.constant 6 : index
  %v21 = arith.constant 7 : index
  %v27 = arith.constant 8 : index
  %v33 = arith.constant 9 : index
  %v40 = arith.constant 0 : index
  %v41 = arith.constant 1 : index
  %v42 = arith.constant 2 : index
  %v43 = arith.constant 36 : i8
  %v44 = arith.constant 123 : i8
  %v45 = arith.constant 1 : i1
  %v84 = arith.constant -2 : i64
  %v2 = arith.muli %n, %v1 : i64
  %v3 = func.call @to_desc(%wins, %v2) : (!llvm.ptr, i64) -> !d
  %v4 = builtin.unrealized_conversion_cast %v3 : !d to !m64
  %v5 = memref.get_global @to_blob : memref<76xi8>
  %v6 = trikeshed.text %v5 : memref<76xi8> -> !b
  %v7 = memref.get_global @to_woff : memref<10xi32>
  %v8 = trikeshed.text %v7 : memref<10xi32> -> !s32
  %v9 = memref.get_global @to_wlen : memref<10xi32>
  %v10 = trikeshed.text %v9 : memref<10xi32> -> !s32
  %v11 = memref.get_global @to_esc : memref<512xi8>
  %v12 = trikeshed.text %v11 : memref<512xi8> -> !b
  %v13 = memref.get_global @to_esclen : memref<256xi8>
  %v14 = trikeshed.text %v13 : memref<256xi8> -> !b
  %v16 = trikeshed.at %v8[%v15] : !s32, index -> i32
  %v17 = trikeshed.at %v10[%v15] : !s32, index -> i32
  %v18 = arith.index_cast %v16 : i32 to index
  %v19 = arith.index_cast %v17 : i32 to index
  %v20 = trikeshed.slice %v6[%v18, %v19] : !b -> !b
  %v22 = trikeshed.at %v8[%v21] : !s32, index -> i32
  %v23 = trikeshed.at %v10[%v21] : !s32, index -> i32
  %v24 = arith.index_cast %v22 : i32 to index
  %v25 = arith.index_cast %v23 : i32 to index
  %v26 = trikeshed.slice %v6[%v24, %v25] : !b -> !b
  %v28 = trikeshed.at %v8[%v27] : !s32, index -> i32
  %v29 = trikeshed.at %v10[%v27] : !s32, index -> i32
  %v30 = arith.index_cast %v28 : i32 to index
  %v31 = arith.index_cast %v29 : i32 to index
  %v32 = trikeshed.slice %v6[%v30, %v31] : !b -> !b
  %v34 = trikeshed.at %v8[%v33] : !s32, index -> i32
  %v35 = trikeshed.at %v10[%v33] : !s32, index -> i32
  %v36 = arith.index_cast %v34 : i32 to index
  %v37 = arith.index_cast %v35 : i32 to index
  %v38 = trikeshed.slice %v6[%v36, %v37] : !b -> !b
  %v39 = arith.index_cast %n : i64 to index
  %v46, %v47 = trikeshed.combineAll %v39 : !b, !sp {
  ^bb0(%a: index):
    %v48 = arith.muli %a, %v42 : index
    %v49 = arith.addi %v48, %v41 : index
    %v50 = memref.load %v4[%v48] : !m64
    %v51 = memref.load %v4[%v49] : !m64
    %v52 = llvm.inttoptr %v50 : i64 to !llvm.ptr
  %v53 = func.call @to_desc(%v52, %v51) : (!llvm.ptr, i64) -> !d
  %v54 = builtin.unrealized_conversion_cast %v53 : !d to !m
  %v55 = builtin.unrealized_conversion_cast %v54 : !m to !b
    %v56 = arith.index_cast %v51 : i64 to index
    %v57 = arith.subi %v56, %v41 : index
    %v58, %v59 = trikeshed.combineAll %v56 : !b, !sp {
    ^bb0(%u: index):
      %v60 = trikeshed.at %v55[%u] : !b, index -> i8
      %v61 = arith.index_castui %v60 : i8 to index
      %v62 = arith.cmpi eq, %v60, %v43 : i8
      %v63 = arith.addi %u, %v41 : index
      %v64 = arith.cmpi ult, %v63, %v56 : index
      %v65 = arith.minsi %v63, %v57 : index
      %v66 = trikeshed.at %v55[%v65] : !b, index -> i8
      %v67 = arith.cmpi eq, %v66, %v44 : i8
      %v68 = arith.andi %v64, %v67 : i1
      %v69 = arith.andi %v62, %v68 : i1
      %v70 = trikeshed.at %v14[%v61] : !b, index -> i8
      %v71 = arith.index_castui %v70 : i8 to index
      %v72 = arith.select %v69, %v42, %v41 : index
      %v73 = arith.select %v62, %v72, %v71 : index
      %v74 = arith.xori %v69, %v45 : i1
      %v75 = arith.andi %v62, %v74 : i1
      %v76 = arith.select %v75, %v41, %v40 : index
      %v77 = arith.muli %v61, %v42 : index
      %v78 = arith.addi %v77, %v76 : index
      %v79 = trikeshed.slice %v12[%v78, %v73] : !b -> !b
      trikeshed.yield %v79 : !b
    }
    %v80 = trikeshed.combine %v26, %v58, %v32 : !b, !b, !b -> !b
    trikeshed.yield %v80 : !b
  }
  %v81 = trikeshed.combine %v20, %v46, %v38 : !b, !b, !b -> !b
  %v82 = trikeshed.size %v81 : !b
  %v83 = arith.index_cast %v82 : index to i64
  %v85 = arith.subi %v84, %v83 : i64
  %v86 = arith.cmpi ult, %cap, %v83 : i64
  %v87 = scf.if %v86 -> i64 {
    scf.yield %v85 : i64
  } else {
  %v88 = func.call @to_desc(%into, %cap) : (!llvm.ptr, i64) -> !d
    %v89 = builtin.unrealized_conversion_cast %v88 : !d to !m
    %v90 = trikeshed.drain %v81, %v89 : !b, !m -> index
    %v91 = arith.index_cast %v90 : index to i64
    scf.yield %v91 : i64
  }
  return %v87 : i64
}

func.func @mlnix_ts_args(%argv: !llvm.ptr, %argc: i64, %cmd: i64, %out: !llvm.ptr) -> i64 {
  %v15 = arith.constant 0 : index
  %v16 = arith.constant 1 : index
  %v17 = arith.constant 2 : index
  %v18 = arith.constant 0 : i64
  %v19 = arith.constant 1 : i64
  %v20 = arith.constant 2 : i64
  %v21 = arith.constant 3 : i64
  %v1 = func.call @to_desc(%argv, %argc) : (!llvm.ptr, i64) -> !d
  %v2 = builtin.unrealized_conversion_cast %v1 : !d to !m64
  %v3 = memref.get_global @to_f_eval : memref<7xi8>
  %v4 = memref.extract_aligned_pointer_as_index %v3 : memref<7xi8> -> index
  %v5 = arith.index_cast %v4 : index to i64
  %v6 = memref.get_global @to_f_strict : memref<9xi8>
  %v7 = memref.extract_aligned_pointer_as_index %v6 : memref<9xi8> -> index
  %v8 = arith.index_cast %v7 : index to i64
  %v9 = memref.get_global @to_f_parse : memref<8xi8>
  %v10 = memref.extract_aligned_pointer_as_index %v9 : memref<8xi8> -> index
  %v11 = arith.index_cast %v10 : index to i64
  %v12 = memref.get_global @to_f_emit : memref<12xi8>
  %v13 = memref.extract_aligned_pointer_as_index %v12 : memref<12xi8> -> index
  %v14 = arith.index_cast %v13 : index to i64
  %v22 = arith.cmpi eq, %cmd, %v18 : i64
  %v23 = arith.cmpi eq, %cmd, %v21 : i64
  %v24 = arith.ori %v22, %v23 : i1
  %v25 = arith.select %v24, %v17, %v16 : index
  %v26 = arith.cmpi eq, %cmd, %v19 : i64
  %v27 = arith.cmpi eq, %cmd, %v20 : i64
  %v28 = arith.index_cast %argc : i64 to index
  %v29 = arith.subi %v28, %v16 : index
  %v30 = arith.addi %v29, %v25 : index
  %v31 = arith.subi %v28, %v16 : index
  %v32 = memref.load %v2[%v15] : !m64
  %v33 = trikeshed.series %v30 : !q {
  ^bb0(%t: index):
    %v34 = arith.cmpi eq, %t, %v15 : index
    %v35 = arith.cmpi uge, %t, %v16 : index
    %v36 = arith.cmpi ule, %t, %v25 : index
    %v37 = arith.andi %v35, %v36 : i1
    %v38 = arith.subi %t, %v16 : index
    %v39 = arith.cmpi eq, %v38, %v15 : index
    %v40 = arith.select %v39, %v5, %v8 : i64
    %v41 = arith.select %v27, %v14, %v40 : i64
    %v42 = arith.select %v26, %v11, %v41 : i64
    %v43 = arith.subi %t, %v25 : index
    %v44 = arith.addi %v43, %v16 : index
    %v45 = arith.maxsi %v44, %v15 : index
    %v46 = arith.minsi %v45, %v31 : index
    %v47 = memref.load %v2[%v46] : !m64
    %v48 = arith.select %v37, %v42, %v47 : i64
    %v49 = arith.select %v34, %v32, %v48 : i64
    trikeshed.yield %v49 : i64
  }
  %v50 = arith.index_cast %v30 : index to i64
  %v51 = func.call @to_desc(%out, %v50) : (!llvm.ptr, i64) -> !d
  %v52 = builtin.unrealized_conversion_cast %v51 : !d to !m64
  %v53 = trikeshed.drain %v33, %v52 : !q, !m64 -> index
  return %v50 : i64
}

func.func @mlnix_ts_printenv(%envs: !llvm.ptr, %nenv: i64, %args: !llvm.ptr, %nargs: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %v1 = arith.constant 4 : i64
  %v2 = arith.constant 2 : i64
  %v15 = arith.constant 0 : index
  %v21 = arith.constant 1 : index
  %v27 = arith.constant 2 : index
  %v33 = arith.constant 3 : index
  %v39 = arith.constant 4 : index
  %v45 = arith.constant 5 : index
  %v87 = arith.constant -2 : i64
  %v3 = arith.muli %nenv, %v1 : i64
  %v4 = func.call @to_desc(%envs, %v3) : (!llvm.ptr, i64) -> !d
  %v5 = builtin.unrealized_conversion_cast %v4 : !d to !m64
  %v6 = arith.muli %nargs, %v2 : i64
  %v7 = func.call @to_desc(%args, %v6) : (!llvm.ptr, i64) -> !d
  %v8 = builtin.unrealized_conversion_cast %v7 : !d to !m64
  %v9 = memref.get_global @to_blob : memref<76xi8>
  %v10 = trikeshed.text %v9 : memref<76xi8> -> !b
  %v11 = memref.get_global @to_woff : memref<10xi32>
  %v12 = trikeshed.text %v11 : memref<10xi32> -> !s32
  %v13 = memref.get_global @to_wlen : memref<10xi32>
  %v14 = trikeshed.text %v13 : memref<10xi32> -> !s32
  %v16 = trikeshed.at %v12[%v15] : !s32, index -> i32
  %v17 = trikeshed.at %v14[%v15] : !s32, index -> i32
  %v18 = arith.index_cast %v16 : i32 to index
  %v19 = arith.index_cast %v17 : i32 to index
  %v20 = trikeshed.slice %v10[%v18, %v19] : !b -> !b
  %v22 = trikeshed.at %v12[%v21] : !s32, index -> i32
  %v23 = trikeshed.at %v14[%v21] : !s32, index -> i32
  %v24 = arith.index_cast %v22 : i32 to index
  %v25 = arith.index_cast %v23 : i32 to index
  %v26 = trikeshed.slice %v10[%v24, %v25] : !b -> !b
  %v28 = trikeshed.at %v12[%v27] : !s32, index -> i32
  %v29 = trikeshed.at %v14[%v27] : !s32, index -> i32
  %v30 = arith.index_cast %v28 : i32 to index
  %v31 = arith.index_cast %v29 : i32 to index
  %v32 = trikeshed.slice %v10[%v30, %v31] : !b -> !b
  %v34 = trikeshed.at %v12[%v33] : !s32, index -> i32
  %v35 = trikeshed.at %v14[%v33] : !s32, index -> i32
  %v36 = arith.index_cast %v34 : i32 to index
  %v37 = arith.index_cast %v35 : i32 to index
  %v38 = trikeshed.slice %v10[%v36, %v37] : !b -> !b
  %v40 = trikeshed.at %v12[%v39] : !s32, index -> i32
  %v41 = trikeshed.at %v14[%v39] : !s32, index -> i32
  %v42 = arith.index_cast %v40 : i32 to index
  %v43 = arith.index_cast %v41 : i32 to index
  %v44 = trikeshed.slice %v10[%v42, %v43] : !b -> !b
  %v46 = trikeshed.at %v12[%v45] : !s32, index -> i32
  %v47 = trikeshed.at %v14[%v45] : !s32, index -> i32
  %v48 = arith.index_cast %v46 : i32 to index
  %v49 = arith.index_cast %v47 : i32 to index
  %v50 = trikeshed.slice %v10[%v48, %v49] : !b -> !b
  %v51 = arith.index_cast %nenv : i64 to index
  %v52, %v53 = trikeshed.combineAll %v51 : !b, !sp {
  ^bb0(%e: index):
    %v54 = arith.muli %e, %v39 : index
    %v55 = arith.addi %v54, %v21 : index
    %v56 = arith.addi %v54, %v27 : index
    %v57 = arith.addi %v54, %v33 : index
    %v58 = memref.load %v5[%v54] : !m64
    %v59 = memref.load %v5[%v55] : !m64
    %v60 = memref.load %v5[%v56] : !m64
    %v61 = memref.load %v5[%v57] : !m64
    %v62 = llvm.inttoptr %v58 : i64 to !llvm.ptr
  %v63 = func.call @to_desc(%v62, %v59) : (!llvm.ptr, i64) -> !d
  %v64 = builtin.unrealized_conversion_cast %v63 : !d to !m
  %v65 = builtin.unrealized_conversion_cast %v64 : !m to !b
    %v66 = llvm.inttoptr %v60 : i64 to !llvm.ptr
  %v67 = func.call @to_desc(%v66, %v61) : (!llvm.ptr, i64) -> !d
  %v68 = builtin.unrealized_conversion_cast %v67 : !d to !m
  %v69 = builtin.unrealized_conversion_cast %v68 : !m to !b
    %v70 = trikeshed.combine %v20, %v65, %v26, %v65, %v32, %v69, %v38 : !b, !b, !b, !b, !b, !b, !b -> !b
    trikeshed.yield %v70 : !b
  }
  %v71 = arith.index_cast %nargs : i64 to index
  %v72, %v73 = trikeshed.combineAll %v71 : !b, !sp {
  ^bb0(%a: index):
    %v74 = arith.muli %a, %v27 : index
    %v75 = arith.addi %v74, %v21 : index
    %v76 = memref.load %v8[%v74] : !m64
    %v77 = memref.load %v8[%v75] : !m64
    %v78 = llvm.inttoptr %v76 : i64 to !llvm.ptr
  %v79 = func.call @to_desc(%v78, %v77) : (!llvm.ptr, i64) -> !d
  %v80 = builtin.unrealized_conversion_cast %v79 : !d to !m
  %v81 = builtin.unrealized_conversion_cast %v80 : !m to !b
    %v82 = trikeshed.combine %v81, %v50 : !b, !b -> !b
    trikeshed.yield %v82 : !b
  }
  %v83 = trikeshed.combine %v44, %v72, %v38 : !b, !b, !b -> !b
  %v84 = trikeshed.combine %v52, %v83 : !b, !b -> !b
  %v85 = trikeshed.size %v84 : !b
  %v86 = arith.index_cast %v85 : index to i64
  %v88 = arith.subi %v87, %v86 : i64
  %v89 = arith.cmpi ult, %cap, %v86 : i64
  %v90 = scf.if %v89 -> i64 {
    scf.yield %v88 : i64
  } else {
  %v91 = func.call @to_desc(%into, %cap) : (!llvm.ptr, i64) -> !d
    %v92 = builtin.unrealized_conversion_cast %v91 : !d to !m
    %v93 = trikeshed.drain %v84, %v92 : !b, !m -> index
    %v94 = arith.index_cast %v93 : index to i64
    scf.yield %v94 : i64
  }
  return %v90 : i64
}
