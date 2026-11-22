// text.mlir -- the texts a reply is made of, and the query's reply made of them, in TrikeShed's ops.  The builder
// (series.mlir) and the routes (api.mlir) reach them through their C interfaces.
//   json_escape  Kotlin's combine(xs α { escapes[it] }): each byte's escape is a slice of one constant table (six bytes a
//                byte, its length in a second), the parts combined (trikeshed.combineAll) and drained into the room
//   digits       printf's %ld: '-' when negative, then the digits of the magnitude, the first not 0 unless it is 0 --
//                the digit count a fold over the powers of ten, each digit an element of a series; decimal drains them
//   fixed6       printf's %f for the query's time: the whole milliseconds, '.', and six digits of the fraction, rounded
//                half up (%f rounds the exact binary value: they differ only when the seventh decimal is a 5 within a
//                rounding error)
//   query_reply  POST /api/query's reply: the counts, each facet's codes and the page of hits, one combine of the
//                pieces -- the corpus's own text where a piece is written there, a literal, or a number's digits
//   report_reply GET /api/report's (and a what-if's): the overlay, the options the what-if changed with their values
//                and states before and after, and the /etc files that differ (columns.mlir's etc_join)
// Compiled like columns.mlir, by mlnix-opt --trikeshed-lower-cursors.

!text = !trikeshed.series<i8>
!s32 = !trikeshed.series<i32>
!s64 = !trikeshed.series<i64>
!tp = !trikeshed.twinpacked<i32>
!tw = !trikeshed.twin<i32>
!pieces = !trikeshed.series<!tp>
!coords = !trikeshed.series<!tp>
!spans = !trikeshed.series<!tw>

// byte b's escape at 6 b: \" \\ \n \r \t, \u00XX (lower-case hex) for the other bytes below 32, else b itself
memref.global "private" constant @escapes : memref<1536xi8> = dense<"0x5C75303030305C75303030315C75303030325C75303030335C75303030345C75303030355C75303030365C75303030375C75303030385C74000000005C6E000000005C75303030625C75303030635C72000000005C75303030655C75303030665C75303031305C75303031315C75303031325C75303031335C75303031345C75303031355C75303031365C75303031375C75303031385C75303031395C75303031615C75303031625C75303031635C75303031645C75303031655C75303031662000000000002100000000005C22000000002300000000002400000000002500000000002600000000002700000000002800000000002900000000002A00000000002B00000000002C00000000002D00000000002E00000000002F00000000003000000000003100000000003200000000003300000000003400000000003500000000003600000000003700000000003800000000003900000000003A00000000003B00000000003C00000000003D00000000003E00000000003F00000000004000000000004100000000004200000000004300000000004400000000004500000000004600000000004700000000004800000000004900000000004A00000000004B00000000004C00000000004D00000000004E00000000004F00000000005000000000005100000000005200000000005300000000005400000000005500000000005600000000005700000000005800000000005900000000005A00000000005B00000000005C5C000000005D00000000005E00000000005F00000000006000000000006100000000006200000000006300000000006400000000006500000000006600000000006700000000006800000000006900000000006A00000000006B00000000006C00000000006D00000000006E00000000006F00000000007000000000007100000000007200000000007300000000007400000000007500000000007600000000007700000000007800000000007900000000007A00000000007B00000000007C00000000007D00000000007E00000000007F00000000008000000000008100000000008200000000008300000000008400000000008500000000008600000000008700000000008800000000008900000000008A00000000008B00000000008C00000000008D00000000008E00000000008F00000000009000000000009100000000009200000000009300000000009400000000009500000000009600000000009700000000009800000000009900000000009A00000000009B00000000009C00000000009D00000000009E00000000009F0000000000A00000000000A10000000000A20000000000A30000000000A40000000000A50000000000A60000000000A70000000000A80000000000A90000000000AA0000000000AB0000000000AC0000000000AD0000000000AE0000000000AF0000000000B00000000000B10000000000B20000000000B30000000000B40000000000B50000000000B60000000000B70000000000B80000000000B90000000000BA0000000000BB0000000000BC0000000000BD0000000000BE0000000000BF0000000000C00000000000C10000000000C20000000000C30000000000C40000000000C50000000000C60000000000C70000000000C80000000000C90000000000CA0000000000CB0000000000CC0000000000CD0000000000CE0000000000CF0000000000D00000000000D10000000000D20000000000D30000000000D40000000000D50000000000D60000000000D70000000000D80000000000D90000000000DA0000000000DB0000000000DC0000000000DD0000000000DE0000000000DF0000000000E00000000000E10000000000E20000000000E30000000000E40000000000E50000000000E60000000000E70000000000E80000000000E90000000000EA0000000000EB0000000000EC0000000000ED0000000000EE0000000000EF0000000000F00000000000F10000000000F20000000000F30000000000F40000000000F50000000000F60000000000F70000000000F80000000000F90000000000FA0000000000FB0000000000FC0000000000FD0000000000FE0000000000FF0000000000">
memref.global "private" constant @escape_lengths : memref<256xi8> = dense<"0x06060606060606060602020606020606060606060606060606060606060606060101020101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010201010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101">
memref.global "private" constant @powers : memref<19xi64> = dense<[1, 10, 100, 1000, 10000, 100000, 1000000, 10000000, 100000000, 1000000000, 10000000000, 100000000000, 1000000000000, 10000000000000, 100000000000000, 1000000000000000, 10000000000000000, 100000000000000000, 1000000000000000000]>
memref.global "private" constant @minus : memref<1xi8> = dense<45>
// the query's reply, as written before it was made here (api.mlir's lit20..lit40)
memref.global "private" constant @q_total : memref<9xi8> = dense<"0x7B22746F74616C223A">  // {"total":
memref.global "private" constant @q_rows : memref<8xi8> = dense<"0x2C22726F7773223A">  // ,"rows":
memref.global "private" constant @q_ms : memref<11xi8> = dense<"0x2C2271756572794D73223A">  // ,"queryMs":
memref.global "private" constant @q_facets : memref<11xi8> = dense<"0x2C22666163657473223A5B">  // ,"facets":[
memref.global "private" constant @q_comma : memref<1xi8> = dense<"0x2C">  // ,
memref.global "private" constant @q_name : memref<9xi8> = dense<"0x7B226E616D65223A22">  // {"name":"
memref.global "private" constant @q_values : memref<12xi8> = dense<"0x222C2276616C756573223A5B">  // ","values":[
memref.global "private" constant @q_v : memref<6xi8> = dense<"0x7B2276223A22">  // {"v":"
memref.global "private" constant @q_n : memref<6xi8> = dense<"0x222C226E223A">  // ","n":
memref.global "private" constant @q_on : memref<11xi8> = dense<"0x2C226F6E223A747275657D">  // ,"on":true}
memref.global "private" constant @q_off : memref<12xi8> = dense<"0x2C226F6E223A66616C73657D">  // ,"on":false}
memref.global "private" constant @q_close : memref<2xi8> = dense<"0x5D7D">  // ]}
memref.global "private" constant @q_hits : memref<10xi8> = dense<"0x5D2C2268697473223A5B">  // ],"hits":[
memref.global "private" constant @q_row : memref<7xi8> = dense<"0x7B22726F77223A">  // {"row":
memref.global "private" constant @q_changed : memref<23xi8> = dense<"0x2C226368616E676564223A747275652C2262617365223A">  // ,"changed":true,"base":
memref.global "private" constant @q_null : memref<4xi8> = dense<"0x6E756C6C">  // null
memref.global "private" constant @q_value : memref<9xi8> = dense<"0x7B2276616C7565223A">  // {"value":
memref.global "private" constant @q_hidden : memref<23xi8> = dense<"0x6E756C6C2C2276616C756553686F776E223A66616C7365">  // null,"valueShown":false
memref.global "private" constant @q_shown : memref<18xi8> = dense<"0x2C2276616C756553686F776E223A74727565">  // ,"valueShown":true
memref.global "private" constant @q_state : memref<10xi8> = dense<"0x2C227374617465223A22">  // ,"state":"
memref.global "private" constant @q_end_state : memref<2xi8> = dense<"0x227D">  // "}
memref.global "private" constant @q_brace : memref<1xi8> = dense<"0x7D">  // }
memref.global "private" constant @q_dot : memref<1xi8> = dense<"0x2E">  // .
// the report's, as written before it was made here (api.mlir's lit41..lit51)
memref.global "private" constant @r_overlay : memref<12xi8> = dense<"0x7B226F7665726C6179223A22">  // {"overlay":"
memref.global "private" constant @r_evalms : memref<19xi8> = dense<"0x222C226576616C4D73223A7B2262617365223A">  // ","evalMs":{"base":
memref.global "private" constant @r_whatif : memref<10xi8> = dense<"0x2C22776861746966223A">  // ,"whatif":
memref.global "private" constant @r_options : memref<13xi8> = dense<"0x7D2C226F7074696F6E73223A5B">  // },"options":[
memref.global "private" constant @r_path : memref<9xi8> = dense<"0x7B2270617468223A22">  // {"path":"
memref.global "private" constant @r_from : memref<9xi8> = dense<"0x222C2266726F6D223A">  // ","from":
memref.global "private" constant @r_to : memref<6xi8> = dense<"0x2C22746F223A">  // ,"to":
memref.global "private" constant @r_fromstate : memref<13xi8> = dense<"0x2C2266726F6D5374617465223A">  // ,"fromState":
memref.global "private" constant @r_quote : memref<1xi8> = dense<"0x22">  // "
memref.global "private" constant @r_tostate : memref<12xi8> = dense<"0x2C22746F5374617465223A22">  // ,"toState":"
memref.global "private" constant @r_endopt : memref<2xi8> = dense<"0x227D">  // "}
memref.global "private" constant @r_etc : memref<9xi8> = dense<"0x5D2C22657463223A5B">  // ],"etc":[

// xs as the inside of a JSON string, written into `into` (six bytes of room a byte): how many bytes were written
func.func @json_escape(%xs: !text, %into: memref<?xi8>) -> index attributes {llvm.emit_c_interface} {
  %six = arith.constant 6 : index
  %eg = memref.get_global @escapes : memref<1536xi8>
  %table = trikeshed.text %eg : memref<1536xi8> -> !text
  %lg = memref.get_global @escape_lengths : memref<256xi8>
  %lengths = trikeshed.text %lg : memref<256xi8> -> !text
  %n = trikeshed.size %xs : !text
  %escaped, %where = trikeshed.combineAll %n : !text, !pieces {
  ^bb0(%k: index):
    %b = trikeshed.at %xs[%k] : !text, index -> i8
    %bi = arith.index_castui %b : i8 to index
    %l = trikeshed.at %lengths[%bi] : !text, index -> i8
    %li = arith.index_castui %l : i8 to index
    %at = arith.muli %bi, %six : index
    %part = trikeshed.slice %table[%at, %li] : !text -> !text
    trikeshed.yield %part : !text
  }
  %end = trikeshed.drain %escaped, %into : !text, memref<?xi8> -> index
  return %end : index
}

// the inside of a JSON string for xs's bytes, as json_escape writes it, made into a buffer of its own (what a reply that
// combines it with other pieces reads; json_escape drains the same view into the builder's room)
func.func private @escaped(%xs: !text) -> !text {
  %six = arith.constant 6 : index
  %eg = memref.get_global @escapes : memref<1536xi8>
  %table = trikeshed.text %eg : memref<1536xi8> -> !text
  %lg = memref.get_global @escape_lengths : memref<256xi8>
  %lengths = trikeshed.text %lg : memref<256xi8> -> !text
  %n = trikeshed.size %xs : !text
  %escaped, %where = trikeshed.combineAll %n : !text, !pieces {
  ^bb0(%k: index):
    %b = trikeshed.at %xs[%k] : !text, index -> i8
    %bi = arith.index_castui %b : i8 to index
    %l = trikeshed.at %lengths[%bi] : !text, index -> i8
    %li = arith.index_castui %l : i8 to index
    %at = arith.muli %bi, %six : index
    %part = trikeshed.slice %table[%at, %li] : !text -> !text
    trikeshed.yield %part : !text
  }
  return %escaped : !text
}

// v's digits as printf's %ld writes them
func.func @digits(%v: i64) -> !text {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c18 = arith.constant 18 : index
  %z = arith.constant 0 : i64
  %ten = arith.constant 10 : i64
  %d0 = arith.constant 48 : i8
  // the magnitude, unsigned: the most negative i64's is 2^63
  %neg = arith.cmpi slt, %v, %z : i64
  %minusv = arith.subi %z, %v : i64
  %mag = arith.select %neg, %minusv, %v : i64
  %pg = memref.get_global @powers : memref<19xi64>
  %powers = trikeshed.text %pg : memref<19xi64> -> !s64
  // 1 + how many of 10, 100, .. 10^18 the magnitude reaches
  %above = trikeshed.slice %powers[%c1, %c18] : !s64 -> !s64
  %count = trikeshed.fold %above, %c1 : !s64, index -> index {
  ^bb0(%acc: index, %p: i64):
    %reach = arith.cmpi uge, %mag, %p : i64
    %more = arith.addi %acc, %c1 : index
    %r = arith.select %reach, %more, %acc : index
    trikeshed.yield %r : index
  }
  %digits = trikeshed.series %count : !text {
  ^bb0(%k: index):
    %last = arith.subi %count, %c1 : index
    %e = arith.subi %last, %k : index
    %p = trikeshed.at %powers[%e] : !s64, index -> i64
    %q = arith.divui %mag, %p : i64
    %d = arith.remui %q, %ten : i64
    %d8 = arith.trunci %d : i64 to i8
    %c = arith.addi %d8, %d0 : i8
    trikeshed.yield %c : i8
  }
  %mg = memref.get_global @minus : memref<1xi8>
  %minus = trikeshed.text %mg : memref<1xi8> -> !text
  %signs = arith.select %neg, %c1, %c0 : index
  %sign = trikeshed.slice %minus[%c0, %signs] : !text -> !text
  %all = trikeshed.combine %sign, %digits : !text, !text -> !text
  return %all : !text
}

// v's digits, into `into` (20 bytes of room): how many bytes were written
func.func @decimal(%v: i64, %into: memref<?xi8>) -> index attributes {llvm.emit_c_interface} {
  %all = func.call @digits(%v) : (i64) -> !text
  %end = trikeshed.drain %all, %into : !text, memref<?xi8> -> index
  return %end : index
}

// x as printf's %f writes the query's time (a few milliseconds, never negative): the whole part, '.', six digits
func.func @fixed6(%x: f64) -> !text {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c5 = arith.constant 5 : index
  %c6 = arith.constant 6 : index
  %million = arith.constant 1000000 : i64
  %fm = arith.constant 1.0e6 : f64
  %half = arith.constant 0.5 : f64
  %zf = arith.constant 0.0 : f64
  %ten = arith.constant 10 : i64
  %d0 = arith.constant 48 : i8
  %pos = arith.maximumf %x, %zf : f64
  %scaled = arith.mulf %pos, %fm : f64
  %rounded = arith.addf %scaled, %half : f64
  %u = arith.fptoui %rounded : f64 to i64
  %whole = arith.divui %u, %million : i64
  %frac = arith.remui %u, %million : i64
  %w = func.call @digits(%whole) : (i64) -> !text
  %pg = memref.get_global @powers : memref<19xi64>
  %powers = trikeshed.text %pg : memref<19xi64> -> !s64
  %f = trikeshed.series %c6 : !text {
  ^bb0(%k: index):
    %e = arith.subi %c5, %k : index
    %p = trikeshed.at %powers[%e] : !s64, index -> i64
    %q = arith.divui %frac, %p : i64
    %d = arith.remui %q, %ten : i64
    %d8 = arith.trunci %d : i64 to i8
    %c = arith.addi %d8, %d0 : i8
    trikeshed.yield %c : i8
  }
  %dg = memref.get_global @q_dot : memref<1xi8>
  %dot = trikeshed.text %dg : memref<1xi8> -> !text
  %all = trikeshed.combine %w, %dot, %f : !text, !text, !text -> !text
  return %all : !text
}

// POST /api/query's reply, one combine of its pieces:
//   {"total":T,"rows":N,"queryMs":F,"facets":[{"name":"section","values":[{"v":"...","n":C,"on":true}, ...]}, ...],
//    "hits":[{"row":<the option as the corpus writes it>[,"changed":true,"base":null | {"value":V,"valueShown":true,
//    "state":"S"}]}, ...]}
// text, spans, obj: the corpus's text (its "?(none)" after the JSON included), its index's spans, each row's element;
// whatif, baseOf: each row's what-if code and base row; btext, bval, bst: the base's text, value and state pieces (a
// value -1 when it is not shown); page: the hit rows to write; ks, picked: each column's code count and whether the
// request selects in it; counts, sels: each column's codes' counts and selection, one column after another; dict0..3:
// the names of the codes of columns 0..3, pieces of text; names, nameAt: the columns' names and the names of the codes
// of the two fixed columns (api.mlir's k_names and k_name_at).  A fresh buffer; the caller frees it.
func.func @query_reply(%text: !text, %spans: !spans, %obj: !s64, %whatif: !s32, %baseOf: !s32,
                       %btext: !text, %bval: !coords, %bst: !coords, %page: !s32,
                       %ks: !s64, %picked: !s64, %counts: !s32, %sels: !s32,
                       %dict0: !coords, %dict1: !coords, %dict2: !coords, %dict3: !coords,
                       %names: !text, %nameAt: !s64, %total: i64, %n: i64, %ms: f64) -> !text
    attributes {llvm.emit_c_interface} {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c2 = arith.constant 2 : index
  %c3 = arith.constant 3 : index
  %c4 = arith.constant 4 : index
  %c6 = arith.constant 6 : index
  %c8 = arith.constant 8 : index
  %z32 = arith.constant 0 : i32
  %z64 = arith.constant 0 : i64
  %m1 = arith.constant -1 : i32
  %totalG = memref.get_global @q_total : memref<9xi8>
  %Ltotal = trikeshed.text %totalG : memref<9xi8> -> !text
  %rowsG = memref.get_global @q_rows : memref<8xi8>
  %Lrows = trikeshed.text %rowsG : memref<8xi8> -> !text
  %msG = memref.get_global @q_ms : memref<11xi8>
  %Lms = trikeshed.text %msG : memref<11xi8> -> !text
  %facetsG = memref.get_global @q_facets : memref<11xi8>
  %Lfacets = trikeshed.text %facetsG : memref<11xi8> -> !text
  %commaG = memref.get_global @q_comma : memref<1xi8>
  %Lcomma = trikeshed.text %commaG : memref<1xi8> -> !text
  %nameG = memref.get_global @q_name : memref<9xi8>
  %Lname = trikeshed.text %nameG : memref<9xi8> -> !text
  %valuesG = memref.get_global @q_values : memref<12xi8>
  %Lvalues = trikeshed.text %valuesG : memref<12xi8> -> !text
  %vG = memref.get_global @q_v : memref<6xi8>
  %Lv = trikeshed.text %vG : memref<6xi8> -> !text
  %nG = memref.get_global @q_n : memref<6xi8>
  %Ln = trikeshed.text %nG : memref<6xi8> -> !text
  %onG = memref.get_global @q_on : memref<11xi8>
  %Lon = trikeshed.text %onG : memref<11xi8> -> !text
  %offG = memref.get_global @q_off : memref<12xi8>
  %Loff = trikeshed.text %offG : memref<12xi8> -> !text
  %closeG = memref.get_global @q_close : memref<2xi8>
  %Lclose = trikeshed.text %closeG : memref<2xi8> -> !text
  %hitsG = memref.get_global @q_hits : memref<10xi8>
  %Lhits = trikeshed.text %hitsG : memref<10xi8> -> !text
  %rowG = memref.get_global @q_row : memref<7xi8>
  %Lrow = trikeshed.text %rowG : memref<7xi8> -> !text
  %changedG = memref.get_global @q_changed : memref<23xi8>
  %Lchanged = trikeshed.text %changedG : memref<23xi8> -> !text
  %nullG = memref.get_global @q_null : memref<4xi8>
  %Lnull = trikeshed.text %nullG : memref<4xi8> -> !text
  %valueG = memref.get_global @q_value : memref<9xi8>
  %Lvalue = trikeshed.text %valueG : memref<9xi8> -> !text
  %hiddenG = memref.get_global @q_hidden : memref<23xi8>
  %Lhidden = trikeshed.text %hiddenG : memref<23xi8> -> !text
  %shownG = memref.get_global @q_shown : memref<18xi8>
  %Lshown = trikeshed.text %shownG : memref<18xi8> -> !text
  %stateG = memref.get_global @q_state : memref<10xi8>
  %Lstate = trikeshed.text %stateG : memref<10xi8> -> !text
  %end_stateG = memref.get_global @q_end_state : memref<2xi8>
  %Lend_state = trikeshed.text %end_stateG : memref<2xi8> -> !text
  %braceG = memref.get_global @q_brace : memref<1xi8>
  %Lbrace = trikeshed.text %braceG : memref<1xi8> -> !text
  // the facets: each column's name and its codes, each code's name, count and whether the selection holds it
  %facets, %facetsAt = trikeshed.combineAll %c6 : !text, !pieces {
  ^bb0(%fi: index):
    %k64 = trikeshed.at %ks[%fi] : !s64, index -> i64
    %k = arith.index_cast %k64 : i64 to index
    // where the column's codes start among all the columns' codes: the code counts of the columns before it
    %before = trikeshed.slice %ks[%c0, %fi] : !s64 -> !s64
    %start64 = trikeshed.fold %before, %z64 : !s64, i64 -> i64 {
    ^bb0(%acc: i64, %x: i64):
      %sum = arith.addi %acc, %x : i64
      trikeshed.yield %sum : i64
    }
    %start = arith.index_cast %start64 : i64 to index
    %p64 = trikeshed.at %picked[%fi] : !s64, index -> i64
    %pickedF = arith.cmpi ne, %p64, %z64 : i64
    %nfs64 = trikeshed.at %nameAt[%fi] : !s64, index -> i64
    %fi1 = arith.addi %fi, %c1 : index
    %nfe64 = trikeshed.at %nameAt[%fi1] : !s64, index -> i64
    %nfs = arith.index_cast %nfs64 : i64 to index
    %nfe = arith.index_cast %nfe64 : i64 to index
    %nfl = arith.subi %nfe, %nfs : index
    %fname = trikeshed.slice %names[%nfs, %nfl] : !text -> !text
    %coded = arith.cmpi ult, %fi, %c4 : index
    %is1 = arith.cmpi eq, %fi, %c1 : index
    %is2 = arith.cmpi eq, %fi, %c2 : index
    %is3 = arith.cmpi eq, %fi, %c3 : index
    %is4 = arith.cmpi eq, %fi, %c4 : index
    %d01 = arith.select %is1, %dict1, %dict0 : !coords
    %d012 = arith.select %is2, %dict2, %d01 : !coords
    %dict = arith.select %is3, %dict3, %d012 : !coords
    // the fixed columns' codes: whatif's same and changed are names 6 and 7, match's no and yes 8 and 9
    %fixedAt = arith.select %is4, %c6, %c8 : index
    %valueText = arith.select %coded, %text, %names : !text
    %values, %valuesAt = trikeshed.combineAll %k : !text, !pieces {
    ^bb0(%c: index):
      %vs, %vl = scf.if %coded -> (index, index) {
        %piece = trikeshed.at %dict[%c] : !coords, index -> !tp
        %s32 = trikeshed.first %piece : !tp -> i32
        %l32 = trikeshed.second %piece : !tp -> i32
        %s = arith.index_cast %s32 : i32 to index
        %l = arith.index_cast %l32 : i32 to index
        scf.yield %s, %l : index, index
      } else {
        %ni = arith.addi %fixedAt, %c : index
        %ni1 = arith.addi %ni, %c1 : index
        %s64 = trikeshed.at %nameAt[%ni] : !s64, index -> i64
        %e64 = trikeshed.at %nameAt[%ni1] : !s64, index -> i64
        %s = arith.index_cast %s64 : i64 to index
        %e = arith.index_cast %e64 : i64 to index
        %l = arith.subi %e, %s : index
        scf.yield %s, %l : index, index
      }
      %vname = trikeshed.slice %valueText[%vs, %vl] : !text -> !text
      %at = arith.addi %start, %c : index
      %count32 = trikeshed.at %counts[%at] : !s32, index -> i32
      %count = arith.extsi %count32 : i32 to i64
      %num = func.call @digits(%count) : (i64) -> !text
      %sel = trikeshed.at %sels[%at] : !s32, index -> i32
      %selected = arith.cmpi ne, %sel, %z32 : i32
      %on = arith.andi %pickedF, %selected : i1
      %onoff = arith.select %on, %Lon, %Loff : !text
      %later = arith.cmpi ugt, %c, %c0 : index
      %sl = arith.select %later, %c1, %c0 : index
      %sep = trikeshed.slice %Lcomma[%c0, %sl] : !text -> !text
      %part = trikeshed.combine %sep, %Lv, %vname, %Ln, %num, %onoff : !text, !text, !text, !text, !text, !text -> !text
      trikeshed.yield %part : !text
    }
    %later = arith.cmpi ugt, %fi, %c0 : index
    %sl = arith.select %later, %c1, %c0 : index
    %sep = trikeshed.slice %Lcomma[%c0, %sl] : !text -> !text
    %part = trikeshed.combine %sep, %Lname, %fname, %Lvalues, %values, %Lclose : !text, !text, !text, !text, !text, !text -> !text
    trikeshed.yield %part : !text
  }
  // the page of hits: each option as the corpus writes it, and when the what-if changed it, the base's value and state
  %np = trikeshed.size %page : !s32
  %hits, %hitsAt = trikeshed.combineAll %np : !text, !pieces {
  ^bb0(%i: index):
    %r32 = trikeshed.at %page[%i] : !s32, index -> i32
    %r = arith.index_cast %r32 : i32 to index
    %o64 = trikeshed.at %obj[%r] : !s64, index -> i64
    %o = arith.index_cast %o64 : i64 to index
    %span = trikeshed.at %spans[%o] : !spans, index -> !tw
    %open32 = trikeshed.first %span : !tw -> i32
    %close32 = trikeshed.second %span : !tw -> i32
    %open = arith.index_cast %open32 : i32 to index
    %close = arith.index_cast %close32 : i32 to index
    %rawl0 = arith.subi %close, %open : index
    %rawl = arith.addi %rawl0, %c1 : index
    %raw = trikeshed.slice %text[%open, %rawl] : !text -> !text
    %w = trikeshed.at %whatif[%r] : !s32, index -> i32
    %changed = arith.cmpi ne, %w, %z32 : i32
    %b32 = trikeshed.at %baseOf[%r] : !s32, index -> i32
    %some = arith.cmpi sge, %b32, %z32 : i32
    %hasBase = arith.andi %changed, %some : i1
    %ok = arith.constant true
    %none = arith.xori %some, %ok : i1
    %noBase = arith.andi %changed, %none : i1
    // the base's value (unless hidden) and state, as coordinates into its text; nothing when there is no base
    %hidden, %vs, %vl, %ss, %sl = scf.if %hasBase -> (i1, index, index, index, index) {
      %b = arith.index_cast %b32 : i32 to index
      %vp = trikeshed.at %bval[%b] : !coords, index -> !tp
      %vs32 = trikeshed.first %vp : !tp -> i32
      %vl32 = trikeshed.second %vp : !tp -> i32
      %h = arith.cmpi eq, %vs32, %m1 : i32
      %vs0 = arith.index_cast %vs32 : i32 to index
      %vl0 = arith.index_cast %vl32 : i32 to index
      %vsx = arith.select %h, %c0, %vs0 : index
      %vlx = arith.select %h, %c0, %vl0 : index
      %sp = trikeshed.at %bst[%b] : !coords, index -> !tp
      %ss32 = trikeshed.first %sp : !tp -> i32
      %sl32 = trikeshed.second %sp : !tp -> i32
      %ssx = arith.index_cast %ss32 : i32 to index
      %slx = arith.index_cast %sl32 : i32 to index
      scf.yield %h, %vsx, %vlx, %ssx, %slx : i1, index, index, index, index
    } else {
      %f = arith.constant false
      scf.yield %f, %c0, %c0, %c0, %c0 : i1, index, index, index, index
    }
    %shown = arith.xori %hidden, %ok : i1
    %valueShown = arith.andi %hasBase, %shown : i1
    %valueHidden = arith.andi %hasBase, %hidden : i1
    %n23 = arith.constant 23 : index
    %n18 = arith.constant 18 : index
    %n10 = arith.constant 10 : index
    %n9 = arith.constant 9 : index
    %lc = arith.select %changed, %n23, %c0 : index
    %ln = arith.select %noBase, %c4, %c0 : index
    %lv = arith.select %hasBase, %n9, %c0 : index
    %lh = arith.select %valueHidden, %n23, %c0 : index
    %lsh = arith.select %valueShown, %n18, %c0 : index
    %lst = arith.select %hasBase, %n10, %c0 : index
    %le = arith.select %hasBase, %c2, %c0 : index
    %pChanged = trikeshed.slice %Lchanged[%c0, %lc] : !text -> !text
    %pNull = trikeshed.slice %Lnull[%c0, %ln] : !text -> !text
    %pValue = trikeshed.slice %Lvalue[%c0, %lv] : !text -> !text
    %pHidden = trikeshed.slice %Lhidden[%c0, %lh] : !text -> !text
    %value = trikeshed.slice %btext[%vs, %vl] : !text -> !text
    %pShown = trikeshed.slice %Lshown[%c0, %lsh] : !text -> !text
    %pState = trikeshed.slice %Lstate[%c0, %lst] : !text -> !text
    %state = trikeshed.slice %btext[%ss, %sl] : !text -> !text
    %pEnd = trikeshed.slice %Lend_state[%c0, %le] : !text -> !text
    %later = arith.cmpi ugt, %i, %c0 : index
    %sepl = arith.select %later, %c1, %c0 : index
    %sep = trikeshed.slice %Lcomma[%c0, %sepl] : !text -> !text
    %part = trikeshed.combine %sep, %Lrow, %raw, %pChanged, %pNull, %pValue, %pHidden, %value, %pShown, %pState, %state, %pEnd, %Lbrace
      : !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text -> !text
    trikeshed.yield %part : !text
  }
  %dt = func.call @digits(%total) : (i64) -> !text
  %dn = func.call @digits(%n) : (i64) -> !text
  %dms = func.call @fixed6(%ms) : (f64) -> !text
  %reply = trikeshed.combine %Ltotal, %dt, %Lrows, %dn, %Lms, %dms, %Lfacets, %facets, %Lhits, %hits, %Lclose
    : !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text -> !text
  return %reply : !text
}

// GET /api/report's reply, and a what-if's, one combine of its pieces:
//   {"overlay":"<the overlay, escaped>","evalMs":{"base":B,"whatif":W},"options":[{"path":"<key>","from":<value>|null,
//    "to":<value>|null,"fromState":"<state>"|null,"toState":"<state>"}, ...],"etc":[{"name":"<name>","from":<text>|null,
//    "to":<text>|null}, ...]}
// ov: the overlay's text; msb, msc: each evaluation's time.  The options: each row of the corpus (text; its keys' text
// and each row's key; value, -1 when it is not shown; state) the what-if changed (whatif), and its base row (baseOf, -1
// for none) in the base (btext, bval, bst).  The /etc files: columns.mlir's etc_join of the base's (ta) and the
// what-if's (tb) by name, its entries (A's member e < size(namesA), else B's member e - size(namesA)) and each one's
// other side; namesA, valuesA, namesB, valuesB their members' pieces.  A fresh buffer; the caller frees it.
func.func @report_reply(%ov: !text, %msb: f64, %msc: f64, %text: !text, %keys: !text, %key: !coords, %val: !coords,
                        %st: !coords, %whatif: !s32, %baseOf: !s32, %btext: !text, %bval: !coords, %bst: !coords,
                        %ta: !text, %namesA: !coords, %valuesA: !coords, %tb: !text, %namesB: !coords, %valuesB: !coords,
                        %entries: !s32, %other: !s32) -> !text attributes {llvm.emit_c_interface} {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c4 = arith.constant 4 : index
  %z32 = arith.constant 0 : i32
  %m1 = arith.constant -1 : i32
  %true = arith.constant true
  %dq = arith.constant 34 : i8
  %overlayG = memref.get_global @r_overlay : memref<12xi8>
  %Roverlay = trikeshed.text %overlayG : memref<12xi8> -> !text
  %evalmsG = memref.get_global @r_evalms : memref<19xi8>
  %Revalms = trikeshed.text %evalmsG : memref<19xi8> -> !text
  %whatifG = memref.get_global @r_whatif : memref<10xi8>
  %Rwhatif = trikeshed.text %whatifG : memref<10xi8> -> !text
  %optionsG = memref.get_global @r_options : memref<13xi8>
  %Roptions = trikeshed.text %optionsG : memref<13xi8> -> !text
  %pathG = memref.get_global @r_path : memref<9xi8>
  %Rpath = trikeshed.text %pathG : memref<9xi8> -> !text
  %fromG = memref.get_global @r_from : memref<9xi8>
  %Rfrom = trikeshed.text %fromG : memref<9xi8> -> !text
  %toG = memref.get_global @r_to : memref<6xi8>
  %Rto = trikeshed.text %toG : memref<6xi8> -> !text
  %fromstateG = memref.get_global @r_fromstate : memref<13xi8>
  %Rfromstate = trikeshed.text %fromstateG : memref<13xi8> -> !text
  %quoteG = memref.get_global @r_quote : memref<1xi8>
  %Rquote = trikeshed.text %quoteG : memref<1xi8> -> !text
  %tostateG = memref.get_global @r_tostate : memref<12xi8>
  %Rtostate = trikeshed.text %tostateG : memref<12xi8> -> !text
  %endoptG = memref.get_global @r_endopt : memref<2xi8>
  %Rendopt = trikeshed.text %endoptG : memref<2xi8> -> !text
  %etcG = memref.get_global @r_etc : memref<9xi8>
  %Retc = trikeshed.text %etcG : memref<9xi8> -> !text
  %commaG = memref.get_global @q_comma : memref<1xi8>
  %Rcomma = trikeshed.text %commaG : memref<1xi8> -> !text
  %nullG = memref.get_global @q_null : memref<4xi8>
  %Rnull = trikeshed.text %nullG : memref<4xi8> -> !text
  %braceG = memref.get_global @q_brace : memref<1xi8>
  %Rbrace = trikeshed.text %braceG : memref<1xi8> -> !text
  %closeG = memref.get_global @q_close : memref<2xi8>
  %Rclose = trikeshed.text %closeG : memref<2xi8> -> !text
  %nameG = memref.get_global @q_name : memref<9xi8>
  %Rname = trikeshed.text %nameG : memref<9xi8> -> !text
  %ovEscaped = func.call @escaped(%ov) : (!text) -> !text
  %base = func.call @fixed6(%msb) : (f64) -> !text
  %what = func.call @fixed6(%msc) : (f64) -> !text
  // the options the what-if changed, in the corpus's order
  %n = trikeshed.size %whatif : !s32
  %rows = trikeshed.series %n : !s32 {
  ^bb0(%i: index):
    %r = arith.index_cast %i : index to i32
    trikeshed.yield %r : i32
  }
  %changed = trikeshed.where %rows : !s32 -> !s32 {
  ^bb0(%r: i32):
    %w = trikeshed.at %whatif[%r] : !s32, i32 -> i32
    %c = arith.cmpi ne, %w, %z32 : i32
    trikeshed.yield %c : i1
  }
  %nc = trikeshed.size %changed : !s32
  %options, %optionsAt = trikeshed.combineAll %nc : !text, !pieces {
  ^bb0(%i: index):
    %r32 = trikeshed.at %changed[%i] : !s32, index -> i32
    %r = arith.index_cast %r32 : i32 to index
    %kp = trikeshed.at %key[%r] : !coords, index -> !tp
    %ks32 = trikeshed.first %kp : !tp -> i32
    %kl32 = trikeshed.second %kp : !tp -> i32
    %ks = arith.index_cast %ks32 : i32 to index
    %kl = arith.index_cast %kl32 : i32 to index
    %path = trikeshed.slice %keys[%ks, %kl] : !text -> !text
    %b32 = trikeshed.at %baseOf[%r] : !s32, index -> i32
    %hasB = arith.cmpi sge, %b32, %z32 : i32
    // from and fromState: the base row's value (when it is shown) and state; null without a base row
    %fromShown, %fs, %fl, %ss, %sl = scf.if %hasB -> (i1, index, index, index, index) {
      %b = arith.index_cast %b32 : i32 to index
      %vp = trikeshed.at %bval[%b] : !coords, index -> !tp
      %vs32 = trikeshed.first %vp : !tp -> i32
      %vl32 = trikeshed.second %vp : !tp -> i32
      %shown = arith.cmpi ne, %vs32, %m1 : i32
      %vs0 = arith.index_cast %vs32 : i32 to index
      %vl0 = arith.index_cast %vl32 : i32 to index
      %vs = arith.select %shown, %vs0, %c0 : index
      %vl = arith.select %shown, %vl0, %c0 : index
      %sp = trikeshed.at %bst[%b] : !coords, index -> !tp
      %s32 = trikeshed.first %sp : !tp -> i32
      %l32 = trikeshed.second %sp : !tp -> i32
      %sx = arith.index_cast %s32 : i32 to index
      %lx = arith.index_cast %l32 : i32 to index
      scf.yield %shown, %vs, %vl, %sx, %lx : i1, index, index, index, index
    } else {
      %f = arith.constant false
      scf.yield %f, %c0, %c0, %c0, %c0 : i1, index, index, index, index
    }
    %fromV = trikeshed.slice %btext[%fs, %fl] : !text -> !text
    %fnl = arith.select %fromShown, %c0, %c4 : index
    %fromNull = trikeshed.slice %Rnull[%c0, %fnl] : !text -> !text
    // to: the row's value, or null when it is not shown
    %tp = trikeshed.at %val[%r] : !coords, index -> !tp
    %ts32 = trikeshed.first %tp : !tp -> i32
    %tl32 = trikeshed.second %tp : !tp -> i32
    %toShown = arith.cmpi ne, %ts32, %m1 : i32
    %ts0 = arith.index_cast %ts32 : i32 to index
    %tl0 = arith.index_cast %tl32 : i32 to index
    %ts = arith.select %toShown, %ts0, %c0 : index
    %tl = arith.select %toShown, %tl0, %c0 : index
    %toV = trikeshed.slice %text[%ts, %tl] : !text -> !text
    %tnl = arith.select %toShown, %c0, %c4 : index
    %toNull = trikeshed.slice %Rnull[%c0, %tnl] : !text -> !text
    %ql = arith.select %hasB, %c1, %c0 : index
    %fsQuote = trikeshed.slice %Rquote[%c0, %ql] : !text -> !text
    %fsV = trikeshed.slice %btext[%ss, %sl] : !text -> !text
    %snl = arith.select %hasB, %c0, %c4 : index
    %fsNull = trikeshed.slice %Rnull[%c0, %snl] : !text -> !text
    %stp = trikeshed.at %st[%r] : !coords, index -> !tp
    %sts32 = trikeshed.first %stp : !tp -> i32
    %stl32 = trikeshed.second %stp : !tp -> i32
    %sts = arith.index_cast %sts32 : i32 to index
    %stl = arith.index_cast %stl32 : i32 to index
    %toState = trikeshed.slice %text[%sts, %stl] : !text -> !text
    %later = arith.cmpi ugt, %i, %c0 : index
    %sepl = arith.select %later, %c1, %c0 : index
    %sep = trikeshed.slice %Rcomma[%c0, %sepl] : !text -> !text
    %part = trikeshed.combine %sep, %Rpath, %path, %Rfrom, %fromV, %fromNull, %Rto, %toV, %toNull, %Rfromstate, %fsQuote,
                              %fsV, %fsQuote, %fsNull, %Rtostate, %toState, %Rendopt
      : !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text -> !text
    trikeshed.yield %part : !text
  }
  // the /etc files that differ, in name order: etc_join's entries
  %ne = trikeshed.size %entries : !s32
  %nA = trikeshed.size %namesA : !coords
  %etc, %etcAt = trikeshed.combineAll %ne : !text, !pieces {
  ^bb0(%k: index):
    %e32 = trikeshed.at %entries[%k] : !s32, index -> i32
    %e = arith.index_cast %e32 : i32 to index
    %inA = arith.cmpi ult, %e, %nA : index
    %eB = arith.subi %e, %nA : index
    %o32 = trikeshed.at %other[%k] : !s32, index -> i32
    %o = arith.index_cast %o32 : i32 to index
    // the name: A's member e, or B's member e - size(A)
    %np, %fromP, %w = scf.if %inA -> (!tp, !tp, index) {
      %x = trikeshed.at %namesA[%e] : !coords, index -> !tp
      %y = trikeshed.at %valuesA[%e] : !coords, index -> !tp
      scf.yield %x, %y, %o : !tp, !tp, index
    } else {
      %x = trikeshed.at %namesB[%eB] : !coords, index -> !tp
      scf.yield %x, %x, %eB : !tp, !tp, index
    }
    %nameText = arith.select %inA, %ta, %tb : !text
    %ns32 = trikeshed.first %np : !tp -> i32
    %nl32 = trikeshed.second %np : !tp -> i32
    %ns = arith.index_cast %ns32 : i32 to index
    %nl = arith.index_cast %nl32 : i32 to index
    %name = trikeshed.slice %nameText[%ns, %nl] : !text -> !text
    // to: B's member of that name (the entry's own when it is B's), or null
    %wi = arith.index_cast %w : index to i64
    %zero = arith.constant 0 : i64
    %hasW = arith.cmpi sge, %wi, %zero : i64
    %wAt = arith.select %hasW, %w, %c0 : index
    %nB = trikeshed.size %namesB : !coords
    %anyB = arith.cmpi ugt, %nB, %c0 : index
    %toP = scf.if %anyB -> (!tp) {
      %y = trikeshed.at %valuesB[%wAt] : !coords, index -> !tp
      scf.yield %y : !tp
    } else {
      scf.yield %np : !tp
    }
    // f: the file's text as the report writes it -- a JSON string as written, anything else written into one (its text
    // escaped, between quotes), or null when there is no such file
    %fs32 = trikeshed.first %fromP : !tp -> i32
    %fl32 = trikeshed.second %fromP : !tp -> i32
    %fs0 = arith.index_cast %fs32 : i32 to index
    %fl0 = arith.index_cast %fl32 : i32 to index
    %fs = arith.select %inA, %fs0, %c0 : index
    %fl = arith.select %inA, %fl0, %c0 : index
    %fRaw = trikeshed.slice %ta[%fs, %fl] : !text -> !text
    %fB = trikeshed.at %ta[%fs] : !text, index -> i8
    %fStr = arith.cmpi eq, %fB, %dq : i8
    %fNotStr = arith.xori %fStr, %true : i1
    %fQuoted = arith.andi %inA, %fNotStr : i1
    %fBody = scf.if %fQuoted -> (!text) {
      %x = func.call @escaped(%fRaw) : (!text) -> !text
      scf.yield %x : !text
    } else {
      scf.yield %fRaw : !text
    }
    %fql = arith.select %fQuoted, %c1, %c0 : index
    %fQ = trikeshed.slice %Rquote[%c0, %fql] : !text -> !text
    %fnl = arith.select %inA, %c0, %c4 : index
    %fNone = trikeshed.slice %Rnull[%c0, %fnl] : !text -> !text
    // t: the file's text as the report writes it -- a JSON string as written, anything else written into one (its text
    // escaped, between quotes), or null when there is no such file
    %ts32 = trikeshed.first %toP : !tp -> i32
    %tl32 = trikeshed.second %toP : !tp -> i32
    %ts0 = arith.index_cast %ts32 : i32 to index
    %tl0 = arith.index_cast %tl32 : i32 to index
    %ts = arith.select %hasW, %ts0, %c0 : index
    %tl = arith.select %hasW, %tl0, %c0 : index
    %tRaw = trikeshed.slice %tb[%ts, %tl] : !text -> !text
    %tB = trikeshed.at %tb[%ts] : !text, index -> i8
    %tStr = arith.cmpi eq, %tB, %dq : i8
    %tNotStr = arith.xori %tStr, %true : i1
    %tQuoted = arith.andi %hasW, %tNotStr : i1
    %tBody = scf.if %tQuoted -> (!text) {
      %x = func.call @escaped(%tRaw) : (!text) -> !text
      scf.yield %x : !text
    } else {
      scf.yield %tRaw : !text
    }
    %tql = arith.select %tQuoted, %c1, %c0 : index
    %tQ = trikeshed.slice %Rquote[%c0, %tql] : !text -> !text
    %tnl = arith.select %hasW, %c0, %c4 : index
    %tNone = trikeshed.slice %Rnull[%c0, %tnl] : !text -> !text
    %later = arith.cmpi ugt, %k, %c0 : index
    %sepl = arith.select %later, %c1, %c0 : index
    %sep = trikeshed.slice %Rcomma[%c0, %sepl] : !text -> !text
    %part = trikeshed.combine %sep, %Rname, %name, %Rfrom, %fQ, %fBody, %fQ, %fNone, %Rto, %tQ, %tBody, %tQ, %tNone, %Rbrace
      : !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text -> !text
    trikeshed.yield %part : !text
  }
  %reply = trikeshed.combine %Roverlay, %ovEscaped, %Revalms, %base, %Rwhatif, %what, %Roptions, %options, %Retc, %etc, %Rclose
    : !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text -> !text
  return %reply : !text
}

// ---- the head of every reply, the error replies, and the what-if overlay's edits (api.mlir's and http.mlir's builder
// calls before; each is one combine of slices and literals, drained once)

// the head, as http.mlir's snprintf("HTTP/1.1 %ld %s\r\nContent-Type: %s\r\nContent-Length: %ld\r\n...") wrote it
memref.global "private" constant @h_http : memref<9xi8> = dense<"0x485454502F312E3120">  // HTTP/1.1
memref.global "private" constant @h_sp : memref<1xi8> = dense<"0x20">  // ' '
memref.global "private" constant @h_type : memref<16xi8> = dense<"0x0D0A436F6E74656E742D547970653A20">  // \r\nContent-Type:
memref.global "private" constant @h_length : memref<18xi8> = dense<"0x0D0A436F6E74656E742D4C656E6774683A20">  // \r\nContent-Length:
memref.global "private" constant @h_tail : memref<48xi8> = dense<"0x0D0A43616368652D436F6E74726F6C3A206E6F2D73746F72650D0A436F6E6E656374696F6E3A20636C6F73650D0A0D0A">  // \r\nCache-Control: no-store\r\nConnection: close\r\n\r\n
// the reasons of 200, 400, 404, 413, 422 and any other status (500), one after another; the two content types
memref.global "private" constant @h_reasons : memref<80xi8> = dense<"0x4F4B42616420526571756573744E6F7420466F756E645061796C6F616420546F6F204C61726765556E70726F6365737361626C6520456E74697479496E7465726E616C20536572766572204572726F72">  // OK, Bad Request, Not Found, Payload Too Large, Unprocessable Entity, Internal Server Error
memref.global "private" constant @h_reason_at : memref<7xi64> = dense<[0, 2, 13, 22, 39, 59, 80]>
memref.global "private" constant @h_statuses : memref<5xi64> = dense<[200, 400, 404, 413, 422]>
memref.global "private" constant @h_types : memref<40xi8> = dense<"0x746578742F68746D6C3B20636861727365743D7574662D386170706C69636174696F6E2F6A736F6E">  // text/html; charset=utf-8, application/json
// {"error":"...", and the overlay's punctuation
memref.global "private" constant @e_open : memref<10xi8> = dense<"0x7B226572726F72223A22">  // {"error":"
memref.global "private" constant @e_close : memref<2xi8> = dense<"0x227D">  // "}
memref.global "private" constant @o_sep : memref<2xi8> = dense<"0x2C20">  // ", "
memref.global "private" constant @o_open : memref<2xi8> = dense<"0x7B22">  // {"
memref.global "private" constant @o_key : memref<3xi8> = dense<"0x223A20">  // ": (quote, colon, space)
memref.global "private" constant @o_close : memref<1xi8> = dense<"0x7D">  // }

// A reply's head: its status and reason, its type (html, else JSON), its body's length; drained into `into` (the room in
// front of the body is 256 bytes, more than any head): how many bytes were written.
func.func @head_reply(%status: i64, %html: i64, %bodyLen: i64, %into: memref<?xi8>) -> index
    attributes {llvm.emit_c_interface} {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c5 = arith.constant 5 : index
  %c16 = arith.constant 16 : index
  %c24 = arith.constant 24 : index
  %z64 = arith.constant 0 : i64
  %httpG = memref.get_global @h_http : memref<9xi8>
  %Lhttp = trikeshed.text %httpG : memref<9xi8> -> !text
  %spG = memref.get_global @h_sp : memref<1xi8>
  %Lsp = trikeshed.text %spG : memref<1xi8> -> !text
  %typeG = memref.get_global @h_type : memref<16xi8>
  %Ltype = trikeshed.text %typeG : memref<16xi8> -> !text
  %lengthG = memref.get_global @h_length : memref<18xi8>
  %Llength = trikeshed.text %lengthG : memref<18xi8> -> !text
  %tailG = memref.get_global @h_tail : memref<48xi8>
  %Ltail = trikeshed.text %tailG : memref<48xi8> -> !text
  %reasonsG = memref.get_global @h_reasons : memref<80xi8>
  %reasons = trikeshed.text %reasonsG : memref<80xi8> -> !text
  %reasonAtG = memref.get_global @h_reason_at : memref<7xi64>
  %reasonAt = trikeshed.text %reasonAtG : memref<7xi64> -> !s64
  %statusesG = memref.get_global @h_statuses : memref<5xi64>
  %statuses = trikeshed.text %statusesG : memref<5xi64> -> !s64
  %typesG = memref.get_global @h_types : memref<40xi8>
  %types = trikeshed.text %typesG : memref<40xi8> -> !text
  // the status's place among the five with a reason of their own, else the sixth's (500's)
  %places = trikeshed.series %c5 : !s64 {
  ^bb0(%k: index):
    %k64 = arith.index_cast %k : index to i64
    trikeshed.yield %k64 : i64
  }
  %which = trikeshed.fold %places, %c5 : !s64, index -> index {
  ^bb0(%acc: index, %k64: i64):
    %k = arith.index_cast %k64 : i64 to index
    %s = trikeshed.at %statuses[%k] : !s64, index -> i64
    %is = arith.cmpi eq, %s, %status : i64
    %unseen = arith.cmpi eq, %acc, %c5 : index
    %first = arith.andi %is, %unseen : i1
    %r = arith.select %first, %k, %acc : index
    trikeshed.yield %r : index
  }
  %which1 = arith.addi %which, %c1 : index
  %rs64 = trikeshed.at %reasonAt[%which] : !s64, index -> i64
  %re64 = trikeshed.at %reasonAt[%which1] : !s64, index -> i64
  %rs = arith.index_cast %rs64 : i64 to index
  %re = arith.index_cast %re64 : i64 to index
  %rl = arith.subi %re, %rs : index
  %reason = trikeshed.slice %reasons[%rs, %rl] : !text -> !text
  %isHtml = arith.cmpi ne, %html, %z64 : i64
  %ts = arith.select %isHtml, %c0, %c24 : index
  %tl = arith.select %isHtml, %c24, %c16 : index
  %type = trikeshed.slice %types[%ts, %tl] : !text -> !text
  %ds = func.call @digits(%status) : (i64) -> !text
  %dl = func.call @digits(%bodyLen) : (i64) -> !text
  %head = trikeshed.combine %Lhttp, %ds, %Lsp, %reason, %Ltype, %type, %Llength, %dl, %Ltail
    : !text, !text, !text, !text, !text, !text, !text, !text, !text -> !text
  %end = trikeshed.drain %head, %into : !text, memref<?xi8> -> index
  return %end : index
}

// {"error":"<lead><a escaped><mid><b escaped>"}: lead and mid are written as they are (literals already JSON), a and b
// escaped as json_escape escapes (a request's method and path, a file's name, mlnix's errors).  A fresh buffer.
func.func @error_reply(%lead: !text, %a: !text, %mid: !text, %b: !text) -> !text attributes {llvm.emit_c_interface} {
  %six = arith.constant 6 : index
  %openG = memref.get_global @e_open : memref<10xi8>
  %Lopen = trikeshed.text %openG : memref<10xi8> -> !text
  %closeG = memref.get_global @e_close : memref<2xi8>
  %Lclose = trikeshed.text %closeG : memref<2xi8> -> !text
  %eg = memref.get_global @escapes : memref<1536xi8>
  %table = trikeshed.text %eg : memref<1536xi8> -> !text
  %lg = memref.get_global @escape_lengths : memref<256xi8>
  %lengths = trikeshed.text %lg : memref<256xi8> -> !text
  %na = trikeshed.size %a : !text
  %ea, %eaAt = trikeshed.combineAll %na : !text, !pieces {
  ^bb0(%k: index):
    %x = trikeshed.at %a[%k] : !text, index -> i8
    %xi = arith.index_castui %x : i8 to index
    %l = trikeshed.at %lengths[%xi] : !text, index -> i8
    %li = arith.index_castui %l : i8 to index
    %at = arith.muli %xi, %six : index
    %part = trikeshed.slice %table[%at, %li] : !text -> !text
    trikeshed.yield %part : !text
  }
  %nb = trikeshed.size %b : !text
  %eb, %ebAt = trikeshed.combineAll %nb : !text, !pieces {
  ^bb0(%k: index):
    %x = trikeshed.at %b[%k] : !text, index -> i8
    %xi = arith.index_castui %x : i8 to index
    %l = trikeshed.at %lengths[%xi] : !text, index -> i8
    %li = arith.index_castui %l : i8 to index
    %at = arith.muli %xi, %six : index
    %part = trikeshed.slice %table[%at, %li] : !text -> !text
    trikeshed.yield %part : !text
  }
  %reply = trikeshed.combine %Lopen, %lead, %ea, %mid, %eb, %Lclose : !text, !text, !text, !text, !text, !text -> !text
  return %reply : !text
}

// The overlay with [from, to) replaced by the body's [vs, vs + vl): a member's value set (its old value's span), a member
// cut (with one comma beside it; vl 0), or the overlay as it was (from = to = its end).  A fresh buffer.
func.func @overlay_put(%ov: !text, %from: index, %to: index, %body: !text, %vs: index, %vl: index) -> !text
    attributes {llvm.emit_c_interface} {
  %c0 = arith.constant 0 : index
  %n = trikeshed.size %ov : !text
  %head = trikeshed.slice %ov[%c0, %from] : !text -> !text
  %value = trikeshed.slice %body[%vs, %vl] : !text -> !text
  %tl = arith.subi %n, %to : index
  %tail = trikeshed.slice %ov[%to, %tl] : !text -> !text
  %next = trikeshed.combine %head, %value, %tail : !text, !text, !text -> !text
  return %next : !text
}

// The overlay with the members a path lacks inserted at `at` (after the last member of the deepest object that exists,
// a ", " first when it has one): "<segment level>": {"<segment>": ... <the body's value> } ... -- each segment the
// inside of its string in the body, as written.  A fresh buffer.
func.func @overlay_insert(%ov: !text, %at: index, %comma: index, %body: !text, %segs: !coords, %level: index, %vs: index,
                          %vl: index) -> !text attributes {llvm.emit_c_interface} {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c2 = arith.constant 2 : index
  %sepG = memref.get_global @o_sep : memref<2xi8>
  %Lsep = trikeshed.text %sepG : memref<2xi8> -> !text
  %openG = memref.get_global @o_open : memref<2xi8>
  %Lopen = trikeshed.text %openG : memref<2xi8> -> !text
  %keyG = memref.get_global @o_key : memref<3xi8>
  %Lkey = trikeshed.text %keyG : memref<3xi8> -> !text
  %closeG = memref.get_global @o_close : memref<1xi8>
  %Lclose = trikeshed.text %closeG : memref<1xi8> -> !text
  %quoteG = memref.get_global @r_quote : memref<1xi8>
  %Lquote = trikeshed.text %quoteG : memref<1xi8> -> !text
  %n = trikeshed.size %ov : !text
  %ns = trikeshed.size %segs : !coords
  %head = trikeshed.slice %ov[%c0, %at] : !text -> !text
  %sl = arith.muli %comma, %c2 : index
  %sep = trikeshed.slice %Lsep[%c0, %sl] : !text -> !text
  %seg = trikeshed.at %segs[%level] : !coords, index -> !tp
  %ks32 = trikeshed.first %seg : !tp -> i32
  %kl32 = trikeshed.second %seg : !tp -> i32
  %ks = arith.index_cast %ks32 : i32 to index
  %kl = arith.index_cast %kl32 : i32 to index
  %key = trikeshed.slice %body[%ks, %kl] : !text -> !text
  %from = arith.addi %level, %c1 : index
  %deeper = arith.subi %ns, %from : index
  %opens, %opensAt = trikeshed.combineAll %deeper : !text, !pieces {
  ^bb0(%j: index):
    %i = arith.addi %from, %j : index
    %sj = trikeshed.at %segs[%i] : !coords, index -> !tp
    %ss32 = trikeshed.first %sj : !tp -> i32
    %sl32 = trikeshed.second %sj : !tp -> i32
    %ss = arith.index_cast %ss32 : i32 to index
    %sln = arith.index_cast %sl32 : i32 to index
    %name = trikeshed.slice %body[%ss, %sln] : !text -> !text
    %part = trikeshed.combine %Lopen, %name, %Lkey : !text, !text, !text -> !text
    trikeshed.yield %part : !text
  }
  %value = trikeshed.slice %body[%vs, %vl] : !text -> !text
  %closes, %closesAt = trikeshed.combineAll %deeper : !text, !pieces {
  ^bb0(%j: index):
    trikeshed.yield %Lclose : !text
  }
  %tl = arith.subi %n, %at : index
  %tail = trikeshed.slice %ov[%at, %tl] : !text -> !text
  %next = trikeshed.combine %head, %sep, %Lquote, %key, %Lkey, %opens, %value, %closes, %tail
    : !text, !text, !text, !text, !text, !text, !text, !text, !text -> !text
  return %next : !text
}
