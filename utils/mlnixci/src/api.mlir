// api.mlir -- the routes: the facets and their counts, the what-if overlay, the report of what the overlay changes, and
// the facets a page asks for on demand (POST /api/facet, answered by the corpus's eval.nix).
//
// A reply is made in the builder after 256 bytes of room, where http.mlir writes its head.  A request's body is read
// where it lies in its connection's buffer: a JSON body is scanned there and its strings are coordinates into it.  The
// overlay is a JSON text held whole; an edit is a splice at the coordinates of its index, made into the next text.

llvm.func @malloc(i64) -> !llvm.ptr
llvm.func @calloc(i64, i64) -> !llvm.ptr
llvm.func @free(!llvm.ptr)
llvm.func @memcpy(!llvm.ptr, !llvm.ptr, i64) -> !llvm.ptr
llvm.func @strlen(!llvm.ptr) -> i64
llvm.func @open(!llvm.ptr, i32, ...) -> i32
llvm.func @read(i32, !llvm.ptr, i64) -> i64
llvm.func @close(i32) -> i32
llvm.func @unlink(!llvm.ptr) -> i32
llvm.func @_mlir_ciface_etc_join(!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr) -> i64
llvm.func @_mlir_ciface_query_text(!llvm.ptr, !llvm.ptr)
llvm.func @_mlir_ciface_query_reply(!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64, i64, f64)
llvm.func @_mlir_ciface_corpus_query(!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64

func.func private @tw(i64, i64) -> i64
func.func private @tw_s(i64) -> i64
func.func private @tw_e(i64) -> i64
func.func private @tw_n(i64) -> i64
func.func private @off(!llvm.ptr, i64) -> !llvm.ptr
func.func private @is(!llvm.ptr, i64, !llvm.ptr, i64) -> i1
func.func private @same(!llvm.ptr, i64, !llvm.ptr, i64) -> i1
func.func private @search(!llvm.ptr, i64, i64, !llvm.ptr, i64) -> i64
func.func private @number(!llvm.ptr, i64, i64) -> i64
func.func private @ob_start(i64)
func.func private @ob_room(i64) -> !llvm.ptr
func.func private @ob_used(i64)
func.func private @ob_len() -> i64
func.func private @ob_take() -> !llvm.ptr
func.func private @ob_bytes(!llvm.ptr, i64)
func.func private @ob_piece(!llvm.ptr, i64)
func.func private @ob_i64(i64)
func.func private @ob_f64(f64)
func.func private @ob_esc(!llvm.ptr, i64)
func.func private @cx_scan(!llvm.ptr, i64) -> !llvm.ptr
func.func private @cx_free(!llvm.ptr)
func.func private @cx_tag(!llvm.ptr, i64) -> i64
func.func private @cx_open(!llvm.ptr, i64) -> i64
func.func private @cx_close(!llvm.ptr, i64) -> i64
func.func private @cx_raw(!llvm.ptr, i64) -> i64
func.func private @cx_str(!llvm.ptr, i64) -> i64
func.func private @cx_nkids(!llvm.ptr, i64) -> i64
func.func private @cx_kid(!llvm.ptr, i64, i64) -> i64
func.func private @cx_member(!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
func.func private @cx_member_at(!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
func.func private @cx_find_at(!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
func.func private @cx_d(!llvm.ptr, i32) -> !llvm.ptr
func.func private @cx_text(!llvm.ptr) -> !llvm.ptr
func.func private @view(!llvm.ptr, !llvm.ptr, i64)
func.func private @getp(!llvm.ptr, i64) -> !llvm.ptr
func.func private @geti(!llvm.ptr, i64) -> i64
func.func private @ld64(!llvm.ptr, i64) -> i64
func.func private @st64(!llvm.ptr, i64, i64)
func.func private @ld32(!llvm.ptr, i64) -> i64
func.func private @st32(!llvm.ptr, i64, i64)
func.func private @corpus_load(!llvm.ptr, i64, f64) -> !llvm.ptr
func.func private @corpus_free(!llvm.ptr)
func.func private @corpus_mark(!llvm.ptr, !llvm.ptr)
func.func private @corpus_why() -> !llvm.ptr
func.func private @corpus_why_n() -> i64
func.func private @evaluate(!llvm.ptr)
func.func private @evaluate_with(!llvm.ptr, !llvm.ptr)
func.func private @run_status() -> i64
func.func private @run_ms() -> f64
func.func private @run_out() -> !llvm.ptr
func.func private @run_out_n() -> i64
func.func private @run_err() -> !llvm.ptr
func.func private @run_err_n() -> i64
func.func private @write_file(!llvm.ptr, !llvm.ptr, i64) -> i1
func.func private @now_ms() -> f64

llvm.mlir.global internal constant @lit0("{}") : !llvm.array<2 x i8>
llvm.mlir.global internal constant @lit1("{\22error\22:\22") : !llvm.array<10 x i8>
llvm.mlir.global internal constant @lit2("\22}") : !llvm.array<2 x i8>
llvm.mlir.global internal constant @lit3("GET") : !llvm.array<3 x i8>
llvm.mlir.global internal constant @lit4("POST") : !llvm.array<4 x i8>
llvm.mlir.global internal constant @lit5("/") : !llvm.array<1 x i8>
llvm.mlir.global internal constant @lit6("/index.html") : !llvm.array<11 x i8>
llvm.mlir.global internal constant @lit7("/api/query") : !llvm.array<10 x i8>
llvm.mlir.global internal constant @lit8("/api/report") : !llvm.array<11 x i8>
llvm.mlir.global internal constant @lit9("/api/whatif/set") : !llvm.array<15 x i8>
llvm.mlir.global internal constant @lit10("/api/whatif/reset") : !llvm.array<17 x i8>
llvm.mlir.global internal constant @lit11("/api/whatif/clear") : !llvm.array<17 x i8>
llvm.mlir.global internal constant @lit12("no route ") : !llvm.array<9 x i8>
llvm.mlir.global internal constant @lit13(" ") : !llvm.array<1 x i8>
llvm.mlir.global internal constant @lit14("cannot read ") : !llvm.array<12 x i8>
llvm.mlir.global internal constant @lit15("query: a JSON object is required") : !llvm.array<32 x i8>
llvm.mlir.global internal constant @lit16("select") : !llvm.array<6 x i8>
llvm.mlir.global internal constant @lit17("q") : !llvm.array<1 x i8>
llvm.mlir.global internal constant @lit18("offset") : !llvm.array<6 x i8>
llvm.mlir.global internal constant @lit19("limit") : !llvm.array<5 x i8>
llvm.mlir.global internal constant @lit24(",") : !llvm.array<1 x i8>
llvm.mlir.global internal constant @lit25("{\22name\22:\22") : !llvm.array<9 x i8>
llvm.mlir.global internal constant @lit31("]}") : !llvm.array<2 x i8>
llvm.mlir.global internal constant @lit35("null") : !llvm.array<4 x i8>
llvm.mlir.global internal constant @lit40("}") : !llvm.array<1 x i8>
llvm.mlir.global internal constant @lit41("{\22overlay\22:\22") : !llvm.array<12 x i8>
llvm.mlir.global internal constant @lit42("\22,\22evalMs\22:{\22base\22:") : !llvm.array<19 x i8>
llvm.mlir.global internal constant @lit43(",\22whatif\22:") : !llvm.array<10 x i8>
llvm.mlir.global internal constant @lit44("},\22options\22:[") : !llvm.array<13 x i8>
llvm.mlir.global internal constant @lit45("{\22path\22:\22") : !llvm.array<9 x i8>
llvm.mlir.global internal constant @lit46("\22,\22from\22:") : !llvm.array<9 x i8>
llvm.mlir.global internal constant @lit47(",\22to\22:") : !llvm.array<6 x i8>
llvm.mlir.global internal constant @lit48(",\22fromState\22:") : !llvm.array<13 x i8>
llvm.mlir.global internal constant @lit49("\22") : !llvm.array<1 x i8>
llvm.mlir.global internal constant @lit50(",\22toState\22:\22") : !llvm.array<12 x i8>
llvm.mlir.global internal constant @lit51("],\22etc\22:[") : !llvm.array<9 x i8>
llvm.mlir.global internal constant @lit52("mlnix failed") : !llvm.array<12 x i8>
llvm.mlir.global internal constant @lit53("cannot write ") : !llvm.array<13 x i8>
llvm.mlir.global internal constant @lit54("path") : !llvm.array<4 x i8>
llvm.mlir.global internal constant @lit55("value") : !llvm.array<5 x i8>
llvm.mlir.global internal constant @lit56("request: not JSON") : !llvm.array<17 x i8>
llvm.mlir.global internal constant @lit57("request: an object is required") : !llvm.array<30 x i8>
llvm.mlir.global internal constant @lit58("request: \5C\22path\5C\22 is empty") : !llvm.array<26 x i8>
llvm.mlir.global internal constant @lit59("request: \5C\22value\5C\22 is required") : !llvm.array<30 x i8>
llvm.mlir.global internal constant @lit60("request: \5C\22path\5C\22 must be an array of strings") : !llvm.array<45 x i8>
llvm.mlir.global internal constant @lit61("overlay: ") : !llvm.array<9 x i8>
llvm.mlir.global internal constant @lit62(" is not an object") : !llvm.array<17 x i8>
llvm.mlir.global internal constant @lit63(", ") : !llvm.array<2 x i8>
llvm.mlir.global internal constant @lit64("\22: ") : !llvm.array<3 x i8>
llvm.mlir.global internal constant @lit65("{\22") : !llvm.array<2 x i8>
llvm.mlir.global internal constant @lit66("the overlay is not a JSON object") : !llvm.array<32 x i8>
llvm.mlir.global internal constant @lit67("/api/facet") : !llvm.array<10 x i8>
llvm.mlir.global internal constant @lit68("facet: a JSON object is required") : !llvm.array<32 x i8>

llvm.mlir.global internal @g_base() : !llvm.ptr {
  %0 = llvm.mlir.zero : !llvm.ptr
  llvm.return %0 : !llvm.ptr
}
llvm.mlir.global internal @g_cur() : !llvm.ptr {
  %0 = llvm.mlir.zero : !llvm.ptr
  llvm.return %0 : !llvm.ptr
}
llvm.mlir.global internal @g_ov() : !llvm.ptr {
  %0 = llvm.mlir.zero : !llvm.ptr
  llvm.return %0 : !llvm.ptr
}
llvm.mlir.global internal @g_ovn(0 : i64) : i64
llvm.mlir.global internal @g_ovfile() : !llvm.ptr {
  %0 = llvm.mlir.zero : !llvm.ptr
  llvm.return %0 : !llvm.ptr
}
llvm.mlir.global internal @g_askfile() : !llvm.ptr {
  %0 = llvm.mlir.zero : !llvm.ptr
  llvm.return %0 : !llvm.ptr
}
llvm.mlir.global internal @g_page() : !llvm.ptr {
  %0 = llvm.mlir.zero : !llvm.ptr
  llvm.return %0 : !llvm.ptr
}
llvm.mlir.global internal @g_status(200 : i64) : i64
llvm.mlir.global internal @g_html(0 : i64) : i64

// The columns' names, and the names of the codes of the two fixed columns, as coordinates into one series:
//   section kind state module whatif match | same changed (whatif) | no yes (match)
llvm.mlir.global internal constant @k_names("sectionkindstatemodulewhatifmatchsamechangednoyes") : !llvm.array<49 x i8>
llvm.mlir.global internal constant @k_name_at(dense<[0, 7, 11, 16, 22, 28, 33, 37, 44, 46, 49]> : tensor<11xi64>) : !llvm.array<11 x i64>

func.func @api_init(%page: !llvm.ptr, %ovfile: !llvm.ptr, %base: !llvm.ptr, %cur: !llvm.ptr, %askfile: !llvm.ptr) {
  %a = llvm.mlir.addressof @g_page : !llvm.ptr
  llvm.store %page, %a : !llvm.ptr, !llvm.ptr
  %a2 = llvm.mlir.addressof @g_askfile : !llvm.ptr
  llvm.store %askfile, %a2 : !llvm.ptr, !llvm.ptr
  %b = llvm.mlir.addressof @g_ovfile : !llvm.ptr
  llvm.store %ovfile, %b : !llvm.ptr, !llvm.ptr
  %c = llvm.mlir.addressof @g_base : !llvm.ptr
  llvm.store %base, %c : !llvm.ptr, !llvm.ptr
  %d = llvm.mlir.addressof @g_cur : !llvm.ptr
  llvm.store %cur, %d : !llvm.ptr, !llvm.ptr
  %ov = func.call @empty_object() : () -> !llvm.ptr
  %e = llvm.mlir.addressof @g_ov : !llvm.ptr
  llvm.store %ov, %e : !llvm.ptr, !llvm.ptr
  %c2 = arith.constant 2 : i64
  %f = llvm.mlir.addressof @g_ovn : !llvm.ptr
  llvm.store %c2, %f : i64, !llvm.ptr
  return
}

// "{}" in a buffer of its own
func.func @empty_object() -> !llvm.ptr {
  %c2 = arith.constant 2 : i64
  %p = llvm.call @malloc(%c2) : (i64) -> !llvm.ptr
  %e = llvm.mlir.addressof @lit0 : !llvm.ptr
  %e_n = arith.constant 2 : i64
  %r = llvm.call @memcpy(%p, %e, %c2) : (!llvm.ptr, !llvm.ptr, i64) -> !llvm.ptr
  return %p : !llvm.ptr
}

func.func @api_status() -> i64 {
  %a = llvm.mlir.addressof @g_status : !llvm.ptr
  %v = llvm.load %a : !llvm.ptr -> i64
  return %v : i64
}

func.func @api_html() -> i64 {
  %a = llvm.mlir.addressof @g_html : !llvm.ptr
  %v = llvm.load %a : !llvm.ptr -> i64
  return %v : i64
}

func.func @cur() -> !llvm.ptr {
  %a = llvm.mlir.addressof @g_cur : !llvm.ptr
  %v = llvm.load %a : !llvm.ptr -> !llvm.ptr
  return %v : !llvm.ptr
}

func.func @base() -> !llvm.ptr {
  %a = llvm.mlir.addressof @g_base : !llvm.ptr
  %v = llvm.load %a : !llvm.ptr -> !llvm.ptr
  return %v : !llvm.ptr
}

// a reply: its status, JSON, 256 bytes of room for the head
func.func @begin(%status: i64) {
  %gap = arith.constant 256 : i64
  func.call @ob_start(%gap) : (i64) -> ()
  %a = llvm.mlir.addressof @g_status : !llvm.ptr
  llvm.store %status, %a : i64, !llvm.ptr
  %b = llvm.mlir.addressof @g_html : !llvm.ptr
  %c0 = arith.constant 0 : i64
  llvm.store %c0, %b : i64, !llvm.ptr
  return
}

func.func @fail(%status: i64) {
  func.call @begin(%status) : (i64) -> ()
  %lit1 = llvm.mlir.addressof @lit1 : !llvm.ptr
  %litn1 = arith.constant 10 : i64
  func.call @ob_bytes(%lit1, %litn1) : (!llvm.ptr, i64) -> ()
  return
}

func.func @fail_end() {
  %lit2 = llvm.mlir.addressof @lit2 : !llvm.ptr
  %litn2 = arith.constant 2 : i64
  func.call @ob_bytes(%lit2, %litn2) : (!llvm.ptr, i64) -> ()
  return
}

func.func @fail_with(%status: i64, %p: !llvm.ptr, %n: i64) {
  func.call @fail(%status) : (i64) -> ()
  %c0 = arith.constant 0 : i64
  %t = func.call @tw(%c0, %n) : (i64, i64) -> i64
  func.call @ob_esc(%p, %t) : (!llvm.ptr, i64) -> ()
  func.call @fail_end() : () -> ()
  return
}

func.func @name_piece(%k: i64) -> i64 {
  %a = llvm.mlir.addressof @k_name_at : !llvm.ptr
  %c1 = arith.constant 1 : i64
  %k1 = arith.addi %k, %c1 : i64
  %s = func.call @ld64(%a, %k) : (!llvm.ptr, i64) -> i64
  %e = func.call @ld64(%a, %k1) : (!llvm.ptr, i64) -> i64
  %t = func.call @tw(%s, %e) : (i64, i64) -> i64
  return %t : i64
}

// how many codes column fi has
func.func @codes(%fi: i64) -> i64 {
  %c2 = arith.constant 2 : i64
  %c4 = arith.constant 4 : i64
  %c21 = arith.constant 21 : i64
  %coded = arith.cmpi slt, %fi, %c4 : i64
  %r = scf.if %coded -> (i64) {
    %c = func.call @cur() : () -> !llvm.ptr
    %slot = arith.addi %c21, %fi : i64
    %v = func.call @geti(%c, %slot) : (!llvm.ptr, i64) -> i64
    scf.yield %v : i64
  } else {
    scf.yield %c2 : i64
  }
  return %r : i64
}

// what code c of column fi stands for: a piece of the corpus's text, or of the names
func.func @value_name(%fi: i64, %c: i64) -> (!llvm.ptr, i64) {
  %c4 = arith.constant 4 : i64
  %c6 = arith.constant 6 : i64
  %c8 = arith.constant 8 : i64
  %c17 = arith.constant 17 : i64
  %coded = arith.cmpi slt, %fi, %c4 : i64
  %r:2 = scf.if %coded -> (!llvm.ptr, i64) {
    %cur = func.call @cur() : () -> !llvm.ptr
    %c0 = arith.constant 0 : i64
    %text = func.call @getp(%cur, %c0) : (!llvm.ptr, i64) -> !llvm.ptr
    %slot = arith.addi %c17, %fi : i64
    %dict = func.call @getp(%cur, %slot) : (!llvm.ptr, i64) -> !llvm.ptr
    %t = func.call @ld64(%dict, %c) : (!llvm.ptr, i64) -> i64
    scf.yield %text, %t : !llvm.ptr, i64
  } else {
    %names = llvm.mlir.addressof @k_names : !llvm.ptr
    %isw = arith.cmpi eq, %fi, %c4 : i64
    %b = arith.select %isw, %c6, %c8 : i64
    %k = arith.addi %b, %c : i64
    %t = func.call @name_piece(%k) : (i64) -> i64
    scf.yield %names, %t : !llvm.ptr, i64
  }
  return %r#0, %r#1 : !llvm.ptr, i64
}

// ---- the routes

func.func @route(%in: !llvm.ptr, %method: i64, %path: i64, %body: i64) {
  %get = llvm.mlir.addressof @lit3 : !llvm.ptr
  %get_n = arith.constant 3 : i64
  %post = llvm.mlir.addressof @lit4 : !llvm.ptr
  %post_n = arith.constant 4 : i64
  %root = llvm.mlir.addressof @lit5 : !llvm.ptr
  %root_n = arith.constant 1 : i64
  %index = llvm.mlir.addressof @lit6 : !llvm.ptr
  %index_n = arith.constant 11 : i64
  %query = llvm.mlir.addressof @lit7 : !llvm.ptr
  %query_n = arith.constant 10 : i64
  %report = llvm.mlir.addressof @lit8 : !llvm.ptr
  %report_n = arith.constant 11 : i64
  %set = llvm.mlir.addressof @lit9 : !llvm.ptr
  %set_n = arith.constant 15 : i64
  %reset = llvm.mlir.addressof @lit10 : !llvm.ptr
  %reset_n = arith.constant 17 : i64
  %clear = llvm.mlir.addressof @lit11 : !llvm.ptr
  %clear_n = arith.constant 17 : i64
  %facet = llvm.mlir.addressof @lit67 : !llvm.ptr
  %facet_n = arith.constant 10 : i64
  %isGet = func.call @is(%in, %method, %get, %get_n) : (!llvm.ptr, i64, !llvm.ptr, i64) -> i1
  %isPost = func.call @is(%in, %method, %post, %post_n) : (!llvm.ptr, i64, !llvm.ptr, i64) -> i1
  %pRoot = func.call @is(%in, %path, %root, %root_n) : (!llvm.ptr, i64, !llvm.ptr, i64) -> i1
  %pIndex = func.call @is(%in, %path, %index, %index_n) : (!llvm.ptr, i64, !llvm.ptr, i64) -> i1
  %pQuery = func.call @is(%in, %path, %query, %query_n) : (!llvm.ptr, i64, !llvm.ptr, i64) -> i1
  %pReport = func.call @is(%in, %path, %report, %report_n) : (!llvm.ptr, i64, !llvm.ptr, i64) -> i1
  %pSet = func.call @is(%in, %path, %set, %set_n) : (!llvm.ptr, i64, !llvm.ptr, i64) -> i1
  %pReset = func.call @is(%in, %path, %reset, %reset_n) : (!llvm.ptr, i64, !llvm.ptr, i64) -> i1
  %pClear = func.call @is(%in, %path, %clear, %clear_n) : (!llvm.ptr, i64, !llvm.ptr, i64) -> i1
  %pFacet = func.call @is(%in, %path, %facet, %facet_n) : (!llvm.ptr, i64, !llvm.ptr, i64) -> i1
  %pPage = arith.ori %pRoot, %pIndex : i1
  %r1 = arith.andi %isGet, %pPage : i1
  %r2 = arith.andi %isPost, %pQuery : i1
  %r3 = arith.andi %isGet, %pQuery : i1
  %r4 = arith.andi %isGet, %pReport : i1
  %r5 = arith.andi %isPost, %pSet : i1
  %r6 = arith.andi %isPost, %pReset : i1
  %r7 = arith.andi %isPost, %pClear : i1
  %r8 = arith.andi %isPost, %pFacet : i1
  %i0 = arith.constant 0 : index
  %i1 = arith.constant 1 : index
  %i2 = arith.constant 2 : index
  %i3 = arith.constant 3 : index
  %i4 = arith.constant 4 : index
  %i5 = arith.constant 5 : index
  %i6 = arith.constant 6 : index
  %i7 = arith.constant 7 : index
  %i8 = arith.constant 8 : index
  %s8 = arith.select %r8, %i8, %i0 : index
  %s7 = arith.select %r7, %i7, %s8 : index
  %s6 = arith.select %r6, %i6, %s7 : index
  %s5 = arith.select %r5, %i5, %s6 : index
  %s4 = arith.select %r4, %i4, %s5 : index
  %s3 = arith.select %r3, %i3, %s4 : index
  %s2 = arith.select %r2, %i2, %s3 : index
  %which = arith.select %r1, %i1, %s2 : index
  %c0 = arith.constant 0 : i64
  %none = func.call @tw(%c0, %c0) : (i64, i64) -> i64
  scf.index_switch %which
  case 1 {
    func.call @page() : () -> ()
    scf.yield
  }
  case 2 {
    func.call @query(%in, %body) : (!llvm.ptr, i64) -> ()
    scf.yield
  }
  case 3 {
    func.call @query(%in, %none) : (!llvm.ptr, i64) -> ()
    scf.yield
  }
  case 4 {
    func.call @report() : () -> ()
    scf.yield
  }
  case 5 {
    func.call @whatif_set(%in, %body) : (!llvm.ptr, i64) -> ()
    scf.yield
  }
  case 6 {
    func.call @whatif_reset(%in, %body) : (!llvm.ptr, i64) -> ()
    scf.yield
  }
  case 7 {
    %next = func.call @empty_object() : () -> !llvm.ptr
    %c2 = arith.constant 2 : i64
    func.call @whatif(%next, %c2) : (!llvm.ptr, i64) -> ()
    scf.yield
  }
  case 8 {
    func.call @facet(%in, %body) : (!llvm.ptr, i64) -> ()
    scf.yield
  }
  default {
    %c404 = arith.constant 404 : i64
    func.call @fail(%c404) : (i64) -> ()
    %lit3 = llvm.mlir.addressof @lit12 : !llvm.ptr
    %litn3 = arith.constant 9 : i64
    func.call @ob_bytes(%lit3, %litn3) : (!llvm.ptr, i64) -> ()
    func.call @ob_esc(%in, %method) : (!llvm.ptr, i64) -> ()
    %lit4 = llvm.mlir.addressof @lit13 : !llvm.ptr
    %litn4 = arith.constant 1 : i64
    func.call @ob_bytes(%lit4, %litn4) : (!llvm.ptr, i64) -> ()
    func.call @ob_esc(%in, %path) : (!llvm.ptr, i64) -> ()
    func.call @fail_end() : () -> ()
    scf.yield
  }
  return
}

// the page, read from its file each time
func.func @page() {
  %pp = llvm.mlir.addressof @g_page : !llvm.ptr
  %page = llvm.load %pp : !llvm.ptr -> !llvm.ptr
  %flags = arith.constant 524288 : i32
  %fd = llvm.call @open(%page, %flags) vararg(!llvm.func<i32 (ptr, i32, ...)>) : (!llvm.ptr, i32) -> i32
  %z32 = arith.constant 0 : i32
  %ok = arith.cmpi sge, %fd, %z32 : i32
  scf.if %ok {
    %c200 = arith.constant 200 : i64
    func.call @begin(%c200) : (i64) -> ()
    %h = llvm.mlir.addressof @g_html : !llvm.ptr
    %c1 = arith.constant 1 : i64
    llvm.store %c1, %h : i64, !llvm.ptr
    %true = arith.constant true
    %chunk = arith.constant 65536 : i64
    %c0 = arith.constant 0 : i64
    scf.while (%go = %true) : (i1) -> () {
      scf.condition(%go)
    } do {
      %room = func.call @ob_room(%chunk) : (i64) -> !llvm.ptr
      %n = llvm.call @read(%fd, %room, %chunk) : (i32, !llvm.ptr, i64) -> i64
      %got = arith.cmpi sgt, %n, %c0 : i64
      scf.if %got {
        func.call @ob_used(%n) : (i64) -> ()
      }
      scf.yield %got : i1
    }
    %x = llvm.call @close(%fd) : (i32) -> i32
  } else {
    %c500 = arith.constant 500 : i64
    func.call @fail(%c500) : (i64) -> ()
    %lit5 = llvm.mlir.addressof @lit14 : !llvm.ptr
    %litn5 = arith.constant 12 : i64
    func.call @ob_bytes(%lit5, %litn5) : (!llvm.ptr, i64) -> ()
    %n = llvm.call @strlen(%page) : (!llvm.ptr) -> i64
    %c0 = arith.constant 0 : i64
    %t = func.call @tw(%c0, %n) : (i64, i64) -> i64
    func.call @ob_esc(%page, %t) : (!llvm.ptr, i64) -> ()
    func.call @fail_end() : () -> ()
  }
  return
}

// ---- the facets asked for on demand

// {"ask": [{"iface": I, "path": [...]}, ...]}: the corpus's eval.nix answers it (answer.nix), evaluated by mlnix with the
// request's file and the what-if overlay, when there is one; its JSON is the reply as mlnix wrote it.  An evaluation
// that fails is 422 with mlnix's error.
func.func @facet(%in: !llvm.ptr, %body: i64) {
  %c0 = arith.constant 0 : i64
  %c2 = arith.constant 2 : i64
  %c5 = arith.constant 5 : i64
  %m1 = arith.constant -1 : i64
  %null = llvm.mlir.zero : !llvm.ptr
  %bs = func.call @tw_s(%body) : (i64) -> i64
  %bn = func.call @tw_n(%body) : (i64) -> i64
  %bp = func.call @off(%in, %bs) : (!llvm.ptr, i64) -> !llvm.ptr
  %some = arith.cmpi sgt, %bn, %c0 : i64
  %tag = scf.if %some -> (i64) {
    %f = func.call @cx_scan(%bp, %bn) : (!llvm.ptr, i64) -> !llvm.ptr
    %bad = llvm.icmp "eq" %f, %null : !llvm.ptr
    %t = scf.if %bad -> (i64) {
      scf.yield %m1 : i64
    } else {
      %t0 = func.call @cx_tag(%f, %c0) : (!llvm.ptr, i64) -> i64
      // a text cut short still scans as an object: its last byte must be the root's '}'
      %cl = func.call @cx_close(%f, %c0) : (!llvm.ptr, i64) -> i64
      %inside = arith.cmpi ult, %cl, %bn : i64
      %last = scf.if %inside -> (i8) {
        %pc = llvm.getelementptr %bp[%cl] : (!llvm.ptr, i64) -> !llvm.ptr, i8
        %ch = llvm.load %pc : !llvm.ptr -> i8
        scf.yield %ch : i8
      } else {
        %z8 = arith.constant 0 : i8
        scf.yield %z8 : i8
      }
      %brace = arith.constant 125 : i8
      %closed = arith.cmpi eq, %last, %brace : i8
      %t1 = arith.select %closed, %t0, %m1 : i64
      func.call @cx_free(%f) : (!llvm.ptr) -> ()
      scf.yield %t1 : i64
    }
    scf.yield %t : i64
  } else {
    scf.yield %m1 : i64
  }
  %isObj = arith.cmpi eq, %tag, %c5 : i64
  scf.if %isObj {
    %pfile = llvm.mlir.addressof @g_askfile : !llvm.ptr
    %file = llvm.load %pfile : !llvm.ptr -> !llvm.ptr
    %ok = func.call @write_file(%file, %bp, %bn) : (!llvm.ptr, !llvm.ptr, i64) -> i1
    scf.if %ok {
      // the overlay's file holds the overlay whenever it is not {} (whatif writes it before an evaluation, and back
      // after a refusal)
      %pov = llvm.mlir.addressof @g_ov : !llvm.ptr
      %ov = llvm.load %pov : !llvm.ptr -> !llvm.ptr
      %povn = llvm.mlir.addressof @g_ovn : !llvm.ptr
      %ovn = llvm.load %povn : !llvm.ptr -> i64
      %ovt = func.call @tw(%c0, %ovn) : (i64, i64) -> i64
      %emptyObj = llvm.mlir.addressof @lit0 : !llvm.ptr
      %ovEmpty = func.call @is(%ov, %ovt, %emptyObj, %c2) : (!llvm.ptr, i64, !llvm.ptr, i64) -> i1
      %povfile = llvm.mlir.addressof @g_ovfile : !llvm.ptr
      %ovfile = llvm.load %povfile : !llvm.ptr -> !llvm.ptr
      %with = arith.select %ovEmpty, %null, %ovfile : !llvm.ptr
      func.call @evaluate_with(%with, %file) : (!llvm.ptr, !llvm.ptr) -> ()
      %gone = llvm.call @unlink(%file) : (!llvm.ptr) -> i32
      %status = func.call @run_status() : () -> i64
      %refused = arith.cmpi ne, %status, %c0 : i64
      scf.if %refused {
        %e = func.call @run_err() : () -> !llvm.ptr
        %en = func.call @run_err_n() : () -> i64
        %c422 = arith.constant 422 : i64
        func.call @fail(%c422) : (i64) -> ()
        %said = arith.cmpi sgt, %en, %c0 : i64
        scf.if %said {
          %et = func.call @tw(%c0, %en) : (i64, i64) -> i64
          func.call @ob_esc(%e, %et) : (!llvm.ptr, i64) -> ()
        } else {
          %failed = llvm.mlir.addressof @lit52 : !llvm.ptr
          %failed_n = arith.constant 12 : i64
          func.call @ob_bytes(%failed, %failed_n) : (!llvm.ptr, i64) -> ()
        }
        func.call @fail_end() : () -> ()
      } else {
        %out = func.call @run_out() : () -> !llvm.ptr
        %on = func.call @run_out_n() : () -> i64
        %c200 = arith.constant 200 : i64
        func.call @begin(%c200) : (i64) -> ()
        func.call @ob_bytes(%out, %on) : (!llvm.ptr, i64) -> ()
        llvm.call @free(%out) : (!llvm.ptr) -> ()
      }
    } else {
      %c500 = arith.constant 500 : i64
      func.call @fail(%c500) : (i64) -> ()
      %cannot = llvm.mlir.addressof @lit53 : !llvm.ptr
      %cannot_n = arith.constant 13 : i64
      func.call @ob_bytes(%cannot, %cannot_n) : (!llvm.ptr, i64) -> ()
      %fl = llvm.call @strlen(%file) : (!llvm.ptr) -> i64
      %ft = func.call @tw(%c0, %fl) : (i64, i64) -> i64
      func.call @ob_esc(%file, %ft) : (!llvm.ptr, i64) -> ()
      func.call @fail_end() : () -> ()
    }
  } else {
    %c400 = arith.constant 400 : i64
    %why = llvm.mlir.addressof @lit68 : !llvm.ptr
    %why_n = arith.constant 32 : i64
    func.call @fail_with(%c400, %why, %why_n) : (i64, !llvm.ptr, i64) -> ()
  }
  return
}

// ---- the query

// {"select": {"section": ["services"], ...}, "q": "ssh", "offset": 0, "limit": 150}: the hits, a page of their rows,
// and each column's codes with their counts
func.func @query(%in: !llvm.ptr, %body: i64) {
  %c0 = arith.constant 0 : i64
  %c2 = arith.constant 2 : i64
  %c5 = arith.constant 5 : i64
  %m1 = arith.constant -1 : i64
  %emptyObj = llvm.mlir.addressof @lit0 : !llvm.ptr
  %emptyObj_n = arith.constant 2 : i64
  %bn0 = func.call @tw_n(%body) : (i64) -> i64
  %bs = func.call @tw_s(%body) : (i64) -> i64
  %isEmpty = arith.cmpi eq, %bn0, %c0 : i64
  %bpIn = func.call @off(%in, %bs) : (!llvm.ptr, i64) -> !llvm.ptr
  %bp = arith.select %isEmpty, %emptyObj, %bpIn : !llvm.ptr
  %bn = arith.select %isEmpty, %c2, %bn0 : i64
  %f = func.call @cx_scan(%bp, %bn) : (!llvm.ptr, i64) -> !llvm.ptr
  %null = llvm.mlir.zero : !llvm.ptr
  %bad = llvm.icmp "eq" %f, %null : !llvm.ptr
  %tag = scf.if %bad -> (i64) {
    scf.yield %m1 : i64
  } else {
    %t = func.call @cx_tag(%f, %c0) : (!llvm.ptr, i64) -> i64
    scf.yield %t : i64
  }
  %isObj = arith.cmpi eq, %tag, %c5 : i64
  scf.if %isObj {
    func.call @query_run(%bp, %f) : (!llvm.ptr, !llvm.ptr) -> ()
  } else {
    %c400 = arith.constant 400 : i64
    %why = llvm.mlir.addressof @lit15 : !llvm.ptr
    %why_n = arith.constant 32 : i64
    func.call @fail_with(%c400, %why, %why_n) : (i64, !llvm.ptr, i64) -> ()
  }
  func.call @cx_free(%f) : (!llvm.ptr) -> ()
  return
}

// a memref<?xi32> descriptor, as the lowering lays one out: { allocated, aligned, offset, size, stride }
func.func @desc(%d: !llvm.ptr, %k: i64, %p: !llvm.ptr, %size: i64) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c5 = arith.constant 5 : i64
  %base = arith.muli %k, %c5 : i64
  %q0 = llvm.getelementptr %d[%base] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  llvm.store %p, %q0 : !llvm.ptr, !llvm.ptr
  %q1 = llvm.getelementptr %q0[1] : (!llvm.ptr) -> !llvm.ptr, i64
  llvm.store %p, %q1 : !llvm.ptr, !llvm.ptr
  %q2 = llvm.getelementptr %q0[2] : (!llvm.ptr) -> !llvm.ptr, i64
  llvm.store %c0, %q2 : i64, !llvm.ptr
  %q3 = llvm.getelementptr %q0[3] : (!llvm.ptr) -> !llvm.ptr, i64
  llvm.store %size, %q3 : i64, !llvm.ptr
  %q4 = llvm.getelementptr %q0[4] : (!llvm.ptr) -> !llvm.ptr, i64
  llvm.store %c1, %q4 : i64, !llvm.ptr
  return
}

func.func @dk(%d: !llvm.ptr, %k: i64) -> !llvm.ptr {
  %c5 = arith.constant 5 : i64
  %base = arith.muli %k, %c5 : i64
  %q = llvm.getelementptr %d[%base] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  return %q : !llvm.ptr
}

// what the query at qt (a string's inside in the request body bp) is searched for: columns.mlir's query_text, as a
// malloc'd buffer and its length (a fresh buffer: its allocation is its data)
func.func @search_query(%bp: !llvm.ptr, %qt: i64) -> (!llvm.ptr, i64) {
  %one = arith.constant 1 : i32
  %s = func.call @tw_s(%qt) : (i64) -> i64
  %n = func.call @tw_n(%qt) : (i64) -> i64
  %at = llvm.getelementptr %bp[%s] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %d = llvm.alloca %one x !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)> : (i32) -> !llvm.ptr
  func.call @view(%d, %at, %n) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %res = llvm.alloca %one x !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)> : (i32) -> !llvm.ptr
  llvm.call @_mlir_ciface_query_text(%res, %d) : (!llvm.ptr, !llvm.ptr) -> ()
  %pb = llvm.getelementptr %res[0, 0] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>
  %buf = llvm.load %pb : !llvm.ptr -> !llvm.ptr
  %pn = llvm.getelementptr %res[0, 3, 0] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>
  %len = llvm.load %pn : !llvm.ptr -> i64
  return %buf, %len : !llvm.ptr, i64
}

func.func @query_run(%bp: !llvm.ptr, %f: !llvm.ptr) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %c5 = arith.constant 5 : i64
  %c6 = arith.constant 6 : i64
  %c9 = arith.constant 9 : i64
  %c10 = arith.constant 10 : i64
  %c11 = arith.constant 11 : i64
  %c12 = arith.constant 12 : i64
  %c16 = arith.constant 16 : i64
  %c18 = arith.constant 18 : i64
  %c19 = arith.constant 19 : i64
  %c40 = arith.constant 40 : i64
  %m1 = arith.constant -1 : i64
  %one32 = arith.constant 1 : i32
  %false = arith.constant false
  %true = arith.constant true
  %cur = func.call @cur() : () -> !llvm.ptr
  %n = func.call @geti(%cur, %c3) : (!llvm.ptr, i64) -> i64
  %text = func.call @getp(%cur, %c0) : (!llvm.ptr, i64) -> !llvm.ptr
  %n1 = arith.maxsi %n, %c1 : i64
  // per column: the selection (every code on until a request selects some), the counts, and whether it selects; the
  // columns' selections and counts one column after another in one buffer each (query_reply reads them so), each
  // column's code count in kcount
  %sels = llvm.call @calloc(%c6, %c40) : (i64, i64) -> !llvm.ptr
  %cnts = llvm.call @calloc(%c6, %c40) : (i64, i64) -> !llvm.ptr
  %anys = llvm.call @calloc(%c6, %c40) : (i64, i64) -> !llvm.ptr
  %kcount = llvm.call @calloc(%c6, %c40) : (i64, i64) -> !llvm.ptr
  %kall = scf.for %fi = %c0 to %c6 step %c1 iter_args(%acc = %c0) -> (i64) : i64 {
    %k = func.call @codes(%fi) : (i64) -> i64
    func.call @st64(%kcount, %fi, %k) : (!llvm.ptr, i64, i64) -> ()
    %next = arith.addi %acc, %k : i64
    scf.yield %next : i64
  }
  %kall1 = arith.maxsi %kall, %c1 : i64
  %selAll = llvm.call @calloc(%kall1, %c4) : (i64, i64) -> !llvm.ptr
  %cntAll = llvm.call @calloc(%kall1, %c4) : (i64, i64) -> !llvm.ptr
  %kend = scf.for %fi = %c0 to %c6 step %c1 iter_args(%at = %c0) -> (i64) : i64 {
    %k = func.call @ld64(%kcount, %fi) : (!llvm.ptr, i64) -> i64
    %sel = llvm.getelementptr %selAll[%at] : (!llvm.ptr, i64) -> !llvm.ptr, i32
    scf.for %c = %c0 to %k step %c1 : i64 {
      func.call @st32(%sel, %c, %c1) : (!llvm.ptr, i64, i64) -> ()
    }
    %cnt = llvm.getelementptr %cntAll[%at] : (!llvm.ptr, i64) -> !llvm.ptr, i32
    %ps = llvm.getelementptr %sels[%fi] : (!llvm.ptr, i64) -> !llvm.ptr, !llvm.ptr
    llvm.store %sel, %ps : !llvm.ptr, !llvm.ptr
    %pc = llvm.getelementptr %cnts[%fi] : (!llvm.ptr, i64) -> !llvm.ptr, !llvm.ptr
    llvm.store %cnt, %pc : !llvm.ptr, !llvm.ptr
    %next = arith.addi %at, %k : i64
    scf.yield %next : i64
  }
  %kselect = llvm.mlir.addressof @lit16 : !llvm.ptr
  %kselect_n = arith.constant 6 : i64
  %select = func.call @cx_member(%bp, %f, %c0, %kselect, %kselect_n) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
  %names = llvm.mlir.addressof @k_names : !llvm.ptr
  scf.for %fi = %c0 to %c6 step %c1 : i64 {
    %hasSel = arith.cmpi sge, %select, %c0 : i64
    %vs = scf.if %hasSel -> (i64) {
      %nt = func.call @name_piece(%fi) : (i64) -> i64
      %ns = func.call @tw_s(%nt) : (i64) -> i64
      %nl = func.call @tw_n(%nt) : (i64) -> i64
      %np = func.call @off(%names, %ns) : (!llvm.ptr, i64) -> !llvm.ptr
      %v = func.call @cx_member(%bp, %f, %select, %np, %nl) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
      scf.yield %v : i64
    } else {
      scf.yield %m1 : i64
    }
    %hasVs = arith.cmpi sge, %vs, %c0 : i64
    %picks = scf.if %hasVs -> (i1) {
      %t = func.call @cx_tag(%f, %vs) : (!llvm.ptr, i64) -> i64
      %isArr = arith.cmpi eq, %t, %c6 : i64
      %nk = func.call @cx_nkids(%f, %vs) : (!llvm.ptr, i64) -> i64
      %some = arith.cmpi sgt, %nk, %c0 : i64
      %b = arith.andi %isArr, %some : i1
      scf.yield %b : i1
    } else {
      scf.yield %false : i1
    }
    scf.if %picks {
      func.call @st64(%anys, %fi, %c1) : (!llvm.ptr, i64, i64) -> ()
      %ps = llvm.getelementptr %sels[%fi] : (!llvm.ptr, i64) -> !llvm.ptr, !llvm.ptr
      %sel = llvm.load %ps : !llvm.ptr -> !llvm.ptr
      %k = func.call @codes(%fi) : (i64) -> i64
      scf.for %c = %c0 to %k step %c1 : i64 {
        func.call @st32(%sel, %c, %c0) : (!llvm.ptr, i64, i64) -> ()
      }
      %nk = func.call @cx_nkids(%f, %vs) : (!llvm.ptr, i64) -> i64
      scf.for %j = %c0 to %nk step %c1 : i64 {
        %kid = func.call @cx_kid(%f, %vs, %j) : (!llvm.ptr, i64, i64) -> i64
        %kt = func.call @cx_tag(%f, %kid) : (!llvm.ptr, i64) -> i64
        %isStr = arith.cmpi eq, %kt, %c4 : i64
        %raw = func.call @cx_raw(%f, %kid) : (!llvm.ptr, i64) -> i64
        %str = func.call @cx_str(%f, %kid) : (!llvm.ptr, i64) -> i64
        %name = arith.select %isStr, %str, %raw : i64
        scf.for %c = %c0 to %k step %c1 : i64 {
          %vn:2 = func.call @value_name(%fi, %c) : (i64, i64) -> (!llvm.ptr, i64)
          %eq = func.call @same(%bp, %name, %vn#0, %vn#1) : (!llvm.ptr, i64, !llvm.ptr, i64) -> i1
          scf.if %eq {
            func.call @st32(%sel, %c, %c1) : (!llvm.ptr, i64, i64) -> ()
          }
        }
      }
    }
  }
  // the text searched for; the match column's selection is "yes" only, when there is one
  %kq = llvm.mlir.addressof @lit17 : !llvm.ptr
  %kq_n = arith.constant 1 : i64
  %qr = func.call @cx_member(%bp, %f, %c0, %kq, %kq_n) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
  %nothing = func.call @tw(%c0, %c0) : (i64, i64) -> i64
  %hasQ = arith.cmpi sge, %qr, %c0 : i64
  %qt = scf.if %hasQ -> (i64) {
    %t = func.call @cx_tag(%f, %qr) : (!llvm.ptr, i64) -> i64
    %isStr = arith.cmpi eq, %t, %c4 : i64
    %in = func.call @cx_str(%f, %qr) : (!llvm.ptr, i64) -> i64
    %r = arith.select %isStr, %in, %nothing : i64
    scf.yield %r : i64
  } else {
    scf.yield %nothing : i64
  }
  %qlow, %qn = func.call @search_query(%bp, %qt) : (!llvm.ptr, i64) -> (!llvm.ptr, i64)
  %hay = func.call @getp(%cur, %c9) : (!llvm.ptr, i64) -> !llvm.ptr
  %hayAt = func.call @getp(%cur, %c10) : (!llvm.ptr, i64) -> !llvm.ptr
  %match = func.call @getp(%cur, %c16) : (!llvm.ptr, i64) -> !llvm.ptr
  %noq = arith.cmpi eq, %qn, %c0 : i64
  scf.for %r = %c0 to %n step %c1 : i64 {
    %ht = func.call @ld64(%hayAt, %r) : (!llvm.ptr, i64) -> i64
    %hs = func.call @tw_s(%ht) : (i64) -> i64
    %he = func.call @tw_e(%ht) : (i64) -> i64
    %hit = scf.if %noq -> (i1) {
      scf.yield %true : i1
    } else {
      %pos = func.call @search(%hay, %hs, %he, %qlow, %qn) : (!llvm.ptr, i64, i64, !llvm.ptr, i64) -> i64
      %found = arith.cmpi sge, %pos, %c0 : i64
      scf.yield %found : i1
    }
    %mi = arith.extui %hit : i1 to i64
    func.call @st32(%match, %r, %mi) : (!llvm.ptr, i64, i64) -> ()
  }
  llvm.call @free(%qlow) : (!llvm.ptr) -> ()
  %anyMatch = func.call @ld64(%anys, %c5) : (!llvm.ptr, i64) -> i64
  %someQ = arith.cmpi sgt, %qn, %c0 : i64
  %notAny = arith.cmpi eq, %anyMatch, %c0 : i64
  %force = arith.andi %someQ, %notAny : i1
  scf.if %force {
    %ps = llvm.getelementptr %sels[5] : (!llvm.ptr) -> !llvm.ptr, !llvm.ptr
    %sel5 = llvm.load %ps : !llvm.ptr -> !llvm.ptr
    func.call @st32(%sel5, %c0, %c0) : (!llvm.ptr, i64, i64) -> ()
    func.call @st32(%sel5, %c1, %c1) : (!llvm.ptr, i64, i64) -> ()
  }
  %koff = llvm.mlir.addressof @lit18 : !llvm.ptr
  %koff_n = arith.constant 6 : i64
  %klim = llvm.mlir.addressof @lit19 : !llvm.ptr
  %klim_n = arith.constant 5 : i64
  %or = func.call @cx_member(%bp, %f, %c0, %koff, %koff_n) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
  %lr = func.call @cx_member(%bp, %f, %c0, %klim, %klim_n) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
  %hasOff = arith.cmpi sge, %or, %c0 : i64
  %offset = scf.if %hasOff -> (i64) {
    %raw = func.call @cx_raw(%f, %or) : (!llvm.ptr, i64) -> i64
    %s = func.call @tw_s(%raw) : (i64) -> i64
    %e = func.call @tw_e(%raw) : (i64) -> i64
    %v = func.call @number(%bp, %s, %e) : (!llvm.ptr, i64, i64) -> i64
    %v0 = arith.maxsi %v, %c0 : i64
    scf.yield %v0 : i64
  } else {
    scf.yield %c0 : i64
  }
  %hasLim = arith.cmpi sge, %lr, %c0 : i64
  %c150 = arith.constant 150 : i64
  %c2000 = arith.constant 2000 : i64
  %limit = scf.if %hasLim -> (i64) {
    %raw = func.call @cx_raw(%f, %lr) : (!llvm.ptr, i64) -> i64
    %s = func.call @tw_s(%raw) : (i64) -> i64
    %e = func.call @tw_e(%raw) : (i64) -> i64
    %v = func.call @number(%bp, %s, %e) : (!llvm.ptr, i64, i64) -> i64
    %v0 = arith.maxsi %v, %c0 : i64
    %v1 = arith.minsi %v0, %c2000 : i64
    scf.yield %v1 : i64
  } else {
    scf.yield %c150 : i64
  }
  // the query: query.mlir, compiled from TrikeShed's cursor ops
  %rows = llvm.call @calloc(%n1, %c4) : (i64, i64) -> !llvm.ptr
  %descs = llvm.call @calloc(%c19, %c40) : (i64, i64) -> !llvm.ptr
  scf.for %fi = %c0 to %c6 step %c1 : i64 {
    %colSlot = arith.addi %c11, %fi : i64
    %col = func.call @getp(%cur, %colSlot) : (!llvm.ptr, i64) -> !llvm.ptr
    func.call @desc(%descs, %fi, %col, %n) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
    %k = func.call @codes(%fi) : (i64) -> i64
    %ps = llvm.getelementptr %sels[%fi] : (!llvm.ptr, i64) -> !llvm.ptr, !llvm.ptr
    %sel = llvm.load %ps : !llvm.ptr -> !llvm.ptr
    %ks = arith.addi %c6, %fi : i64
    func.call @desc(%descs, %ks, %sel, %k) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
    %pc = llvm.getelementptr %cnts[%fi] : (!llvm.ptr, i64) -> !llvm.ptr, !llvm.ptr
    %cnt = llvm.load %pc : !llvm.ptr -> !llvm.ptr
    %ko = arith.addi %c12, %fi : i64
    func.call @desc(%descs, %ko, %cnt, %k) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
  }
  func.call @desc(%descs, %c18, %rows, %n) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
  %d0 = func.call @dk(%descs, %c0) : (!llvm.ptr, i64) -> !llvm.ptr
  %d1 = func.call @dk(%descs, %c1) : (!llvm.ptr, i64) -> !llvm.ptr
  %d2 = func.call @dk(%descs, %c2) : (!llvm.ptr, i64) -> !llvm.ptr
  %d3 = func.call @dk(%descs, %c3) : (!llvm.ptr, i64) -> !llvm.ptr
  %d4 = func.call @dk(%descs, %c4) : (!llvm.ptr, i64) -> !llvm.ptr
  %d5 = func.call @dk(%descs, %c5) : (!llvm.ptr, i64) -> !llvm.ptr
  %c7 = arith.constant 7 : i64
  %c8 = arith.constant 8 : i64
  %c13 = arith.constant 13 : i64
  %c14 = arith.constant 14 : i64
  %c15 = arith.constant 15 : i64
  %c17 = arith.constant 17 : i64
  %d6 = func.call @dk(%descs, %c6) : (!llvm.ptr, i64) -> !llvm.ptr
  %d7 = func.call @dk(%descs, %c7) : (!llvm.ptr, i64) -> !llvm.ptr
  %d8 = func.call @dk(%descs, %c8) : (!llvm.ptr, i64) -> !llvm.ptr
  %d9 = func.call @dk(%descs, %c9) : (!llvm.ptr, i64) -> !llvm.ptr
  %d10 = func.call @dk(%descs, %c10) : (!llvm.ptr, i64) -> !llvm.ptr
  %d11 = func.call @dk(%descs, %c11) : (!llvm.ptr, i64) -> !llvm.ptr
  %d12 = func.call @dk(%descs, %c12) : (!llvm.ptr, i64) -> !llvm.ptr
  %d13 = func.call @dk(%descs, %c13) : (!llvm.ptr, i64) -> !llvm.ptr
  %d14 = func.call @dk(%descs, %c14) : (!llvm.ptr, i64) -> !llvm.ptr
  %d15 = func.call @dk(%descs, %c15) : (!llvm.ptr, i64) -> !llvm.ptr
  %d16 = func.call @dk(%descs, %c16) : (!llvm.ptr, i64) -> !llvm.ptr
  %d17 = func.call @dk(%descs, %c17) : (!llvm.ptr, i64) -> !llvm.ptr
  %d18 = func.call @dk(%descs, %c18) : (!llvm.ptr, i64) -> !llvm.ptr
  %t0 = func.call @now_ms() : () -> f64
  %total = llvm.call @_mlir_ciface_corpus_query(%d0, %d1, %d2, %d3, %d4, %d5, %d6, %d7, %d8, %d9, %d10, %d11, %d12, %d13, %d14, %d15, %d16, %d17, %d18) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
  %t1 = func.call @now_ms() : () -> f64
  %dt = arith.subf %t1, %t0 : f64
  // the reply: text.mlir's query_reply, its pieces combined in one text, written into the builder
  %c200 = arith.constant 200 : i64
  func.call @begin(%c200) : (i64) -> ()
  %lim = arith.addi %offset, %limit : i64
  %end = arith.minsi %total, %lim : i64
  %from = arith.minsi %offset, %end : i64
  %np = arith.subi %end, %from : i64
  %page = llvm.getelementptr %rows[%from] : (!llvm.ptr, i64) -> !llvm.ptr, i32
  %flat = func.call @getp(%cur, %c2) : (!llvm.ptr, i64) -> !llvm.ptr
  %zero32 = arith.constant 0 : i32
  %c20 = arith.constant 20 : i64
  %c28 = arith.constant 28 : i64
  %c49 = arith.constant 49 : i64
  %len = func.call @geti(%cur, %c1) : (!llvm.ptr, i64) -> i64
  %tlen = arith.addi %len, %c7 : i64
  %bc = func.call @base() : () -> !llvm.ptr
  %btext = func.call @getp(%bc, %c0) : (!llvm.ptr, i64) -> !llvm.ptr
  %blen = func.call @geti(%bc, %c1) : (!llvm.ptr, i64) -> i64
  %btlen = arith.addi %blen, %c7 : i64
  %bn = func.call @geti(%bc, %c3) : (!llvm.ptr, i64) -> i64
  %obj = func.call @getp(%cur, %c4) : (!llvm.ptr, i64) -> !llvm.ptr
  %baseOf = func.call @getp(%cur, %c28) : (!llvm.ptr, i64) -> !llvm.ptr
  %bval = func.call @getp(%bc, %c5) : (!llvm.ptr, i64) -> !llvm.ptr
  %bst = func.call @getp(%bc, %c6) : (!llvm.ptr, i64) -> !llvm.ptr
  %nameAt = llvm.mlir.addressof @k_name_at : !llvm.ptr
  // the descriptors query_reply takes, in its order: the spans are the index's own, whatif the query's column 4
  %rd = llvm.call @calloc(%c20, %c40) : (i64, i64) -> !llvm.ptr
  func.call @desc(%rd, %c0, %text, %tlen) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
  func.call @desc(%rd, %c2, %obj, %n) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
  func.call @desc(%rd, %c4, %baseOf, %n) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
  func.call @desc(%rd, %c5, %btext, %btlen) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
  func.call @desc(%rd, %c6, %bval, %bn) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
  func.call @desc(%rd, %c7, %bst, %bn) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
  func.call @desc(%rd, %c8, %page, %np) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
  func.call @desc(%rd, %c9, %kcount, %c6) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
  func.call @desc(%rd, %c10, %anys, %c6) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
  func.call @desc(%rd, %c11, %cntAll, %kall) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
  func.call @desc(%rd, %c12, %selAll, %kall) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
  scf.for %fi = %c0 to %c4 step %c1 : i64 {
    %slot = arith.addi %c17, %fi : i64
    %dict = func.call @getp(%cur, %slot) : (!llvm.ptr, i64) -> !llvm.ptr
    %k = func.call @ld64(%kcount, %fi) : (!llvm.ptr, i64) -> i64
    %at = arith.addi %c13, %fi : i64
    func.call @desc(%rd, %at, %dict, %k) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
  }
  func.call @desc(%rd, %c17, %names, %c49) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
  func.call @desc(%rd, %c18, %nameAt, %c11) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
  %r0 = func.call @dk(%rd, %c0) : (!llvm.ptr, i64) -> !llvm.ptr
  %r1 = func.call @cx_d(%flat, %zero32) : (!llvm.ptr, i32) -> !llvm.ptr
  %r2 = func.call @dk(%rd, %c2) : (!llvm.ptr, i64) -> !llvm.ptr
  %r4 = func.call @dk(%rd, %c4) : (!llvm.ptr, i64) -> !llvm.ptr
  %r5 = func.call @dk(%rd, %c5) : (!llvm.ptr, i64) -> !llvm.ptr
  %r6 = func.call @dk(%rd, %c6) : (!llvm.ptr, i64) -> !llvm.ptr
  %r7 = func.call @dk(%rd, %c7) : (!llvm.ptr, i64) -> !llvm.ptr
  %r8 = func.call @dk(%rd, %c8) : (!llvm.ptr, i64) -> !llvm.ptr
  %r9 = func.call @dk(%rd, %c9) : (!llvm.ptr, i64) -> !llvm.ptr
  %r10 = func.call @dk(%rd, %c10) : (!llvm.ptr, i64) -> !llvm.ptr
  %r11 = func.call @dk(%rd, %c11) : (!llvm.ptr, i64) -> !llvm.ptr
  %r12 = func.call @dk(%rd, %c12) : (!llvm.ptr, i64) -> !llvm.ptr
  %r13 = func.call @dk(%rd, %c13) : (!llvm.ptr, i64) -> !llvm.ptr
  %r14 = func.call @dk(%rd, %c14) : (!llvm.ptr, i64) -> !llvm.ptr
  %r15 = func.call @dk(%rd, %c15) : (!llvm.ptr, i64) -> !llvm.ptr
  %r16 = func.call @dk(%rd, %c16) : (!llvm.ptr, i64) -> !llvm.ptr
  %r17 = func.call @dk(%rd, %c17) : (!llvm.ptr, i64) -> !llvm.ptr
  %r18 = func.call @dk(%rd, %c18) : (!llvm.ptr, i64) -> !llvm.ptr
  %reply = llvm.alloca %one32 x !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)> : (i32) -> !llvm.ptr
  llvm.call @_mlir_ciface_query_reply(%reply, %r0, %r1, %r2, %d4, %r4, %r5, %r6, %r7, %r8, %r9, %r10, %r11, %r12, %r13, %r14, %r15, %r16, %r17, %r18, %total, %n, %dt) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64, i64, f64) -> ()
  %pa = llvm.getelementptr %reply[0, 0] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>
  %rbuf = llvm.load %pa : !llvm.ptr -> !llvm.ptr
  %pd = llvm.getelementptr %reply[0, 1] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>
  %rdata = llvm.load %pd : !llvm.ptr -> !llvm.ptr
  %po = llvm.getelementptr %reply[0, 2] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>
  %roff = llvm.load %po : !llvm.ptr -> i64
  %pn = llvm.getelementptr %reply[0, 3, 0] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>
  %rlen = llvm.load %pn : !llvm.ptr -> i64
  %rat = llvm.getelementptr %rdata[%roff] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  func.call @ob_bytes(%rat, %rlen) : (!llvm.ptr, i64) -> ()
  llvm.call @free(%rbuf) : (!llvm.ptr) -> ()
  llvm.call @free(%rd) : (!llvm.ptr) -> ()
  llvm.call @free(%selAll) : (!llvm.ptr) -> ()
  llvm.call @free(%cntAll) : (!llvm.ptr) -> ()
  llvm.call @free(%kcount) : (!llvm.ptr) -> ()
  llvm.call @free(%sels) : (!llvm.ptr) -> ()
  llvm.call @free(%cnts) : (!llvm.ptr) -> ()
  llvm.call @free(%anys) : (!llvm.ptr) -> ()
  llvm.call @free(%rows) : (!llvm.ptr) -> ()
  llvm.call @free(%descs) : (!llvm.ptr) -> ()
  return
}

// ---- the report: the overlay, then each changed option (its value and state before and after), and each /etc file
// whose text differs

func.func @report() {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c3 = arith.constant 3 : i64
  %c5 = arith.constant 5 : i64
  %c6 = arith.constant 6 : i64
  %c7 = arith.constant 7 : i64
  %c8 = arith.constant 8 : i64
  %c15 = arith.constant 15 : i64
  %c26 = arith.constant 26 : i64
  %c28 = arith.constant 28 : i64
  %m1 = arith.constant -1 : i64
  %true = arith.constant true
  %cur = func.call @cur() : () -> !llvm.ptr
  %bc = func.call @base() : () -> !llvm.ptr
  %c200 = arith.constant 200 : i64
  func.call @begin(%c200) : (i64) -> ()
  %lit31 = llvm.mlir.addressof @lit41 : !llvm.ptr
  %litn31 = arith.constant 12 : i64
  func.call @ob_bytes(%lit31, %litn31) : (!llvm.ptr, i64) -> ()
  %pov = llvm.mlir.addressof @g_ov : !llvm.ptr
  %ov = llvm.load %pov : !llvm.ptr -> !llvm.ptr
  %povn = llvm.mlir.addressof @g_ovn : !llvm.ptr
  %ovn = llvm.load %povn : !llvm.ptr -> i64
  %ovt = func.call @tw(%c0, %ovn) : (i64, i64) -> i64
  func.call @ob_esc(%ov, %ovt) : (!llvm.ptr, i64) -> ()
  %lit32 = llvm.mlir.addressof @lit42 : !llvm.ptr
  %litn32 = arith.constant 19 : i64
  func.call @ob_bytes(%lit32, %litn32) : (!llvm.ptr, i64) -> ()
  %msb = func.call @geti(%bc, %c26) : (!llvm.ptr, i64) -> i64
  %msbf = arith.bitcast %msb : i64 to f64
  func.call @ob_f64(%msbf) : (f64) -> ()
  %lit33 = llvm.mlir.addressof @lit43 : !llvm.ptr
  %litn33 = arith.constant 10 : i64
  func.call @ob_bytes(%lit33, %litn33) : (!llvm.ptr, i64) -> ()
  %msc = func.call @geti(%cur, %c26) : (!llvm.ptr, i64) -> i64
  %mscf = arith.bitcast %msc : i64 to f64
  func.call @ob_f64(%mscf) : (f64) -> ()
  %lit34 = llvm.mlir.addressof @lit44 : !llvm.ptr
  %litn34 = arith.constant 13 : i64
  func.call @ob_bytes(%lit34, %litn34) : (!llvm.ptr, i64) -> ()
  %n = func.call @geti(%cur, %c3) : (!llvm.ptr, i64) -> i64
  %text = func.call @getp(%cur, %c0) : (!llvm.ptr, i64) -> !llvm.ptr
  %keys = func.call @getp(%cur, %c7) : (!llvm.ptr, i64) -> !llvm.ptr
  %key = func.call @getp(%cur, %c8) : (!llvm.ptr, i64) -> !llvm.ptr
  %val = func.call @getp(%cur, %c5) : (!llvm.ptr, i64) -> !llvm.ptr
  %st = func.call @getp(%cur, %c6) : (!llvm.ptr, i64) -> !llvm.ptr
  %whatif = func.call @getp(%cur, %c15) : (!llvm.ptr, i64) -> !llvm.ptr
  %baseOf = func.call @getp(%cur, %c28) : (!llvm.ptr, i64) -> !llvm.ptr
  %btext = func.call @getp(%bc, %c0) : (!llvm.ptr, i64) -> !llvm.ptr
  %bval = func.call @getp(%bc, %c5) : (!llvm.ptr, i64) -> !llvm.ptr
  %bst = func.call @getp(%bc, %c6) : (!llvm.ptr, i64) -> !llvm.ptr
  %last = scf.for %r = %c0 to %n step %c1 iter_args(%first = %true) -> (i1) : i64 {
    %w = func.call @ld32(%whatif, %r) : (!llvm.ptr, i64) -> i64
    %ch = arith.cmpi ne, %w, %c0 : i64
    %nf = scf.if %ch -> (i1) {
      %notFirst = arith.xori %first, %true : i1
      scf.if %notFirst {
        %lit35 = llvm.mlir.addressof @lit24 : !llvm.ptr
        %litn35 = arith.constant 1 : i64
        func.call @ob_bytes(%lit35, %litn35) : (!llvm.ptr, i64) -> ()
      }
      %lit36 = llvm.mlir.addressof @lit45 : !llvm.ptr
      %litn36 = arith.constant 9 : i64
      func.call @ob_bytes(%lit36, %litn36) : (!llvm.ptr, i64) -> ()
      %k = func.call @ld64(%key, %r) : (!llvm.ptr, i64) -> i64
      func.call @ob_piece(%keys, %k) : (!llvm.ptr, i64) -> ()
      %lit37 = llvm.mlir.addressof @lit46 : !llvm.ptr
      %litn37 = arith.constant 9 : i64
      func.call @ob_bytes(%lit37, %litn37) : (!llvm.ptr, i64) -> ()
      %b = func.call @ld32(%baseOf, %r) : (!llvm.ptr, i64) -> i64
      %hasB = arith.cmpi sge, %b, %c0 : i64
      scf.if %hasB {
        %vb = func.call @ld64(%bval, %b) : (!llvm.ptr, i64) -> i64
        %hidden = arith.cmpi eq, %vb, %m1 : i64
        scf.if %hidden {
          %lit38 = llvm.mlir.addressof @lit35 : !llvm.ptr
          %litn38 = arith.constant 4 : i64
          func.call @ob_bytes(%lit38, %litn38) : (!llvm.ptr, i64) -> ()
        } else {
          func.call @ob_piece(%btext, %vb) : (!llvm.ptr, i64) -> ()
        }
      } else {
        %lit39 = llvm.mlir.addressof @lit35 : !llvm.ptr
        %litn39 = arith.constant 4 : i64
        func.call @ob_bytes(%lit39, %litn39) : (!llvm.ptr, i64) -> ()
      }
      %lit40 = llvm.mlir.addressof @lit47 : !llvm.ptr
      %litn40 = arith.constant 6 : i64
      func.call @ob_bytes(%lit40, %litn40) : (!llvm.ptr, i64) -> ()
      %vc = func.call @ld64(%val, %r) : (!llvm.ptr, i64) -> i64
      %hiddenC = arith.cmpi eq, %vc, %m1 : i64
      scf.if %hiddenC {
        %lit41 = llvm.mlir.addressof @lit35 : !llvm.ptr
        %litn41 = arith.constant 4 : i64
        func.call @ob_bytes(%lit41, %litn41) : (!llvm.ptr, i64) -> ()
      } else {
        func.call @ob_piece(%text, %vc) : (!llvm.ptr, i64) -> ()
      }
      %lit42 = llvm.mlir.addressof @lit48 : !llvm.ptr
      %litn42 = arith.constant 13 : i64
      func.call @ob_bytes(%lit42, %litn42) : (!llvm.ptr, i64) -> ()
      scf.if %hasB {
        %lit43 = llvm.mlir.addressof @lit49 : !llvm.ptr
        %litn43 = arith.constant 1 : i64
        func.call @ob_bytes(%lit43, %litn43) : (!llvm.ptr, i64) -> ()
        %sb = func.call @ld64(%bst, %b) : (!llvm.ptr, i64) -> i64
        func.call @ob_piece(%btext, %sb) : (!llvm.ptr, i64) -> ()
        %lit44 = llvm.mlir.addressof @lit49 : !llvm.ptr
        %litn44 = arith.constant 1 : i64
        func.call @ob_bytes(%lit44, %litn44) : (!llvm.ptr, i64) -> ()
      } else {
        %lit45 = llvm.mlir.addressof @lit35 : !llvm.ptr
        %litn45 = arith.constant 4 : i64
        func.call @ob_bytes(%lit45, %litn45) : (!llvm.ptr, i64) -> ()
      }
      %lit46 = llvm.mlir.addressof @lit50 : !llvm.ptr
      %litn46 = arith.constant 12 : i64
      func.call @ob_bytes(%lit46, %litn46) : (!llvm.ptr, i64) -> ()
      %sc = func.call @ld64(%st, %r) : (!llvm.ptr, i64) -> i64
      func.call @ob_piece(%text, %sc) : (!llvm.ptr, i64) -> ()
      %lit47 = llvm.mlir.addressof @lit2 : !llvm.ptr
      %litn47 = arith.constant 2 : i64
      func.call @ob_bytes(%lit47, %litn47) : (!llvm.ptr, i64) -> ()
      %false = arith.constant false
      scf.yield %false : i1
    } else {
      scf.yield %first : i1
    }
    scf.yield %nf : i1
  }
  %lit48 = llvm.mlir.addressof @lit51 : !llvm.ptr
  %litn48 = arith.constant 9 : i64
  func.call @ob_bytes(%lit48, %litn48) : (!llvm.ptr, i64) -> ()
  func.call @etc_diff(%bc, %cur) : (!llvm.ptr, !llvm.ptr) -> ()
  %lit49 = llvm.mlir.addressof @lit31 : !llvm.ptr
  %litn49 = arith.constant 2 : i64
  func.call @ob_bytes(%lit49, %litn49) : (!llvm.ptr, i64) -> ()
  return
}

// an /etc file's text as a JSON string: a string as it is written, anything else written into one
func.func @etc_value(%t: !llvm.ptr, %f: !llvm.ptr, %v: i64) {
  %c4 = arith.constant 4 : i64
  %tag = func.call @cx_tag(%f, %v) : (!llvm.ptr, i64) -> i64
  %raw = func.call @cx_raw(%f, %v) : (!llvm.ptr, i64) -> i64
  %isStr = arith.cmpi eq, %tag, %c4 : i64
  scf.if %isStr {
    func.call @ob_piece(%t, %raw) : (!llvm.ptr, i64) -> ()
  } else {
    %lit50 = llvm.mlir.addressof @lit49 : !llvm.ptr
    %litn50 = arith.constant 1 : i64
    func.call @ob_bytes(%lit50, %litn50) : (!llvm.ptr, i64) -> ()
    func.call @ob_esc(%t, %raw) : (!llvm.ptr, i64) -> ()
    %lit51 = llvm.mlir.addressof @lit49 : !llvm.ptr
    %litn51 = arith.constant 1 : i64
    func.call @ob_bytes(%lit51, %litn51) : (!llvm.ptr, i64) -> ()
  }
  return
}

// the /etc files of the two corpora, joined by name: columns.mlir's etc_join gives the files that differ, in name order
// (entry e < kb: the base's file e, its what-if file other[e] or -1; else the what-if's file e - kb, which the base lacks)
func.func @etc_diff(%bc: !llvm.ptr, %cur: !llvm.ptr) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c4 = arith.constant 4 : i64
  %c25 = arith.constant 25 : i64
  %i0 = arith.constant 0 : i32
  %i1 = arith.constant 1 : i32
  %i2 = arith.constant 2 : i32
  %i3 = arith.constant 3 : i32
  %tb = func.call @getp(%bc, %c0) : (!llvm.ptr, i64) -> !llvm.ptr
  %fb = func.call @getp(%bc, %c2) : (!llvm.ptr, i64) -> !llvm.ptr
  %eb = func.call @geti(%bc, %c25) : (!llvm.ptr, i64) -> i64
  %tc = func.call @getp(%cur, %c0) : (!llvm.ptr, i64) -> !llvm.ptr
  %fc = func.call @getp(%cur, %c2) : (!llvm.ptr, i64) -> !llvm.ptr
  %ec = func.call @geti(%cur, %c25) : (!llvm.ptr, i64) -> i64
  %hasEb = arith.cmpi sge, %eb, %c0 : i64
  %kb = scf.if %hasEb -> (i64) {
    %k = func.call @cx_nkids(%fb, %eb) : (!llvm.ptr, i64) -> i64
    %h = arith.divui %k, %c2 : i64
    scf.yield %h : i64
  } else {
    scf.yield %c0 : i64
  }
  %hasEc = arith.cmpi sge, %ec, %c0 : i64
  %kc = scf.if %hasEc -> (i64) {
    %k = func.call @cx_nkids(%fc, %ec) : (!llvm.ptr, i64) -> i64
    %h = arith.divui %k, %c2 : i64
    scf.yield %h : i64
  } else {
    scf.yield %c0 : i64
  }
  %both = arith.addi %kb, %kc : i64
  %room = arith.addi %both, %c1 : i64
  %entries = llvm.call @calloc(%room, %c4) : (i64, i64) -> !llvm.ptr
  %other = llvm.call @calloc(%room, %c4) : (i64, i64) -> !llvm.ptr
  %v = llvm.alloca %i1 x !llvm.array<2 x struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>> : (i32) -> !llvm.ptr
  %ve = llvm.getelementptr %v[0, 0] : (!llvm.ptr) -> !llvm.ptr, !llvm.array<2 x struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>>
  %vo = llvm.getelementptr %v[0, 1] : (!llvm.ptr) -> !llvm.ptr, !llvm.array<2 x struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>>
  func.call @view(%ve, %entries, %both) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  func.call @view(%vo, %other, %both) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %a0 = func.call @cx_d(%fb, %i0) : (!llvm.ptr, i32) -> !llvm.ptr
  %a1 = func.call @cx_d(%fb, %i1) : (!llvm.ptr, i32) -> !llvm.ptr
  %a2 = func.call @cx_d(%fb, %i2) : (!llvm.ptr, i32) -> !llvm.ptr
  %a3 = func.call @cx_d(%fb, %i3) : (!llvm.ptr, i32) -> !llvm.ptr
  %at = func.call @cx_text(%fb) : (!llvm.ptr) -> !llvm.ptr
  %b0 = func.call @cx_d(%fc, %i0) : (!llvm.ptr, i32) -> !llvm.ptr
  %b1 = func.call @cx_d(%fc, %i1) : (!llvm.ptr, i32) -> !llvm.ptr
  %b2 = func.call @cx_d(%fc, %i2) : (!llvm.ptr, i32) -> !llvm.ptr
  %b3 = func.call @cx_d(%fc, %i3) : (!llvm.ptr, i32) -> !llvm.ptr
  %bt = func.call @cx_text(%fc) : (!llvm.ptr) -> !llvm.ptr
  %n = llvm.call @_mlir_ciface_etc_join(%a0, %a1, %a2, %a3, %at, %eb, %b0, %b1, %b2, %b3, %bt, %ec, %ve, %vo) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr) -> i64
  scf.for %k = %c0 to %n step %c1 : i64 {
    %e = func.call @ld32(%entries, %k) : (!llvm.ptr, i64) -> i64
    %o = func.call @ld32(%other, %k) : (!llvm.ptr, i64) -> i64
    %more = arith.cmpi sgt, %k, %c0 : i64
    scf.if %more {
      %lit52 = llvm.mlir.addressof @lit24 : !llvm.ptr
      %litn52 = arith.constant 1 : i64
      func.call @ob_bytes(%lit52, %litn52) : (!llvm.ptr, i64) -> ()
    }
    %lit53 = llvm.mlir.addressof @lit25 : !llvm.ptr
    %litn53 = arith.constant 9 : i64
    func.call @ob_bytes(%lit53, %litn53) : (!llvm.ptr, i64) -> ()
    %inA = arith.cmpi slt, %e, %kb : i64
    %j = arith.subi %e, %kb : i64
    scf.if %inA {
      %e2 = arith.muli %e, %c2 : i64
      %key = func.call @cx_kid(%fb, %eb, %e2) : (!llvm.ptr, i64, i64) -> i64
      %name = func.call @cx_str(%fb, %key) : (!llvm.ptr, i64) -> i64
      func.call @ob_piece(%tb, %name) : (!llvm.ptr, i64) -> ()
    } else {
      %j2 = arith.muli %j, %c2 : i64
      %key = func.call @cx_kid(%fc, %ec, %j2) : (!llvm.ptr, i64, i64) -> i64
      %name = func.call @cx_str(%fc, %key) : (!llvm.ptr, i64) -> i64
      func.call @ob_piece(%tc, %name) : (!llvm.ptr, i64) -> ()
    }
    %lit54 = llvm.mlir.addressof @lit46 : !llvm.ptr
    %litn54 = arith.constant 9 : i64
    func.call @ob_bytes(%lit54, %litn54) : (!llvm.ptr, i64) -> ()
    scf.if %inA {
      %e2 = arith.muli %e, %c2 : i64
      %e21 = arith.addi %e2, %c1 : i64
      %va = func.call @cx_kid(%fb, %eb, %e21) : (!llvm.ptr, i64, i64) -> i64
      func.call @etc_value(%tb, %fb, %va) : (!llvm.ptr, !llvm.ptr, i64) -> ()
    } else {
      %lit55 = llvm.mlir.addressof @lit35 : !llvm.ptr
      %litn55 = arith.constant 4 : i64
      func.call @ob_bytes(%lit55, %litn55) : (!llvm.ptr, i64) -> ()
    }
    %lit56 = llvm.mlir.addressof @lit47 : !llvm.ptr
    %litn56 = arith.constant 6 : i64
    func.call @ob_bytes(%lit56, %litn56) : (!llvm.ptr, i64) -> ()
    // the what-if's file: other[e] for the base's file e, else file e - kb
    %w = arith.select %inA, %o, %j : i64
    %hasW = arith.cmpi sge, %w, %c0 : i64
    scf.if %hasW {
      %w2 = arith.muli %w, %c2 : i64
      %w21 = arith.addi %w2, %c1 : i64
      %vb = func.call @cx_kid(%fc, %ec, %w21) : (!llvm.ptr, i64, i64) -> i64
      func.call @etc_value(%tc, %fc, %vb) : (!llvm.ptr, !llvm.ptr, i64) -> ()
    } else {
      %lit57 = llvm.mlir.addressof @lit35 : !llvm.ptr
      %litn57 = arith.constant 4 : i64
      func.call @ob_bytes(%lit57, %litn57) : (!llvm.ptr, i64) -> ()
    }
    %lit58 = llvm.mlir.addressof @lit40 : !llvm.ptr
    %litn58 = arith.constant 1 : i64
    func.call @ob_bytes(%lit58, %litn58) : (!llvm.ptr, i64) -> ()
  }
  llvm.call @free(%entries) : (!llvm.ptr) -> ()
  llvm.call @free(%other) : (!llvm.ptr) -> ()
  return
}

// ---- the what-if overlay

// Evaluate with next (a buffer this takes) as the overlay; keep it when the module system accepts it.
func.func @whatif(%next: !llvm.ptr, %nn: i64) {
  %c0 = arith.constant 0 : i64
  %c2 = arith.constant 2 : i64
  %true = arith.constant true
  %emptyObj = llvm.mlir.addressof @lit0 : !llvm.ptr
  %emptyObj_n = arith.constant 2 : i64
  %nt = func.call @tw(%c0, %nn) : (i64, i64) -> i64
  %isEmpty = func.call @is(%next, %nt, %emptyObj, %c2) : (!llvm.ptr, i64, !llvm.ptr, i64) -> i1
  %pfile = llvm.mlir.addressof @g_ovfile : !llvm.ptr
  %file = llvm.load %pfile : !llvm.ptr -> !llvm.ptr
  %null = llvm.mlir.zero : !llvm.ptr
  %wrote = scf.if %isEmpty -> (i1) {
    func.call @evaluate(%null) : (!llvm.ptr) -> ()
    scf.yield %true : i1
  } else {
    %ok = func.call @write_file(%file, %next, %nn) : (!llvm.ptr, !llvm.ptr, i64) -> i1
    scf.if %ok {
      func.call @evaluate(%file) : (!llvm.ptr) -> ()
    }
    scf.yield %ok : i1
  }
  scf.if %wrote {
    %status = func.call @run_status() : () -> i64
    %refused = arith.cmpi ne, %status, %c0 : i64
    scf.if %refused {
      // the file is the overlay kept
      %pov = llvm.mlir.addressof @g_ov : !llvm.ptr
      %ov = llvm.load %pov : !llvm.ptr -> !llvm.ptr
      %povn = llvm.mlir.addressof @g_ovn : !llvm.ptr
      %ovn = llvm.load %povn : !llvm.ptr -> i64
      %ovt = func.call @tw(%c0, %ovn) : (i64, i64) -> i64
      %ovEmpty = func.call @is(%ov, %ovt, %emptyObj, %c2) : (!llvm.ptr, i64, !llvm.ptr, i64) -> i1
      scf.if %ovEmpty {
      } else {
        %k = func.call @write_file(%file, %ov, %ovn) : (!llvm.ptr, !llvm.ptr, i64) -> i1
      }
      llvm.call @free(%next) : (!llvm.ptr) -> ()
      %e = func.call @run_err() : () -> !llvm.ptr
      %en = func.call @run_err_n() : () -> i64
      %c422 = arith.constant 422 : i64
      func.call @fail(%c422) : (i64) -> ()
      %said = arith.cmpi sgt, %en, %c0 : i64
      scf.if %said {
        %et = func.call @tw(%c0, %en) : (i64, i64) -> i64
        func.call @ob_esc(%e, %et) : (!llvm.ptr, i64) -> ()
      } else {
        %lit59 = llvm.mlir.addressof @lit52 : !llvm.ptr
        %litn59 = arith.constant 12 : i64
        func.call @ob_bytes(%lit59, %litn59) : (!llvm.ptr, i64) -> ()
      }
      func.call @fail_end() : () -> ()
    } else {
      %out = func.call @run_out() : () -> !llvm.ptr
      %on = func.call @run_out_n() : () -> i64
      %ms = func.call @run_ms() : () -> f64
      %c = func.call @corpus_load(%out, %on, %ms) : (!llvm.ptr, i64, f64) -> !llvm.ptr
      %bad = llvm.icmp "eq" %c, %null : !llvm.ptr
      scf.if %bad {
        llvm.call @free(%next) : (!llvm.ptr) -> ()
        %c500 = arith.constant 500 : i64
        %why = func.call @corpus_why() : () -> !llvm.ptr
        %whyn = func.call @corpus_why_n() : () -> i64
        func.call @fail_with(%c500, %why, %whyn) : (i64, !llvm.ptr, i64) -> ()
      } else {
        %pcur = llvm.mlir.addressof @g_cur : !llvm.ptr
        %old = llvm.load %pcur : !llvm.ptr -> !llvm.ptr
        func.call @corpus_free(%old) : (!llvm.ptr) -> ()
        llvm.store %c, %pcur : !llvm.ptr, !llvm.ptr
        %pov = llvm.mlir.addressof @g_ov : !llvm.ptr
        %oldov = llvm.load %pov : !llvm.ptr -> !llvm.ptr
        llvm.call @free(%oldov) : (!llvm.ptr) -> ()
        llvm.store %next, %pov : !llvm.ptr, !llvm.ptr
        %povn = llvm.mlir.addressof @g_ovn : !llvm.ptr
        llvm.store %nn, %povn : i64, !llvm.ptr
        %bc = func.call @base() : () -> !llvm.ptr
        func.call @corpus_mark(%c, %bc) : (!llvm.ptr, !llvm.ptr) -> ()
        func.call @report() : () -> ()
      }
    }
  } else {
    llvm.call @free(%next) : (!llvm.ptr) -> ()
    %c500 = arith.constant 500 : i64
    func.call @fail(%c500) : (i64) -> ()
    %lit60 = llvm.mlir.addressof @lit53 : !llvm.ptr
    %litn60 = arith.constant 13 : i64
    func.call @ob_bytes(%lit60, %litn60) : (!llvm.ptr, i64) -> ()
    %fl = llvm.call @strlen(%file) : (!llvm.ptr) -> i64
    %ft = func.call @tw(%c0, %fl) : (i64, i64) -> i64
    func.call @ob_esc(%file, %ft) : (!llvm.ptr, i64) -> ()
    func.call @fail_end() : () -> ()
  }
  return
}

// The request {"path": [segments], "value": json}: its index, the segments' coordinates (inside their quotes) and the
// value's, all in the body; false, with the reply made, when it is not one.
func.func @request(%bp: !llvm.ptr, %bn: i64, %want: i1) -> (!llvm.ptr, !llvm.ptr, i64, i64, i1) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %c5 = arith.constant 5 : i64
  %c6 = arith.constant 6 : i64
  %c8 = arith.constant 8 : i64
  %m1 = arith.constant -1 : i64
  %true = arith.constant true
  %false = arith.constant false
  %null = llvm.mlir.zero : !llvm.ptr
  %f = func.call @cx_scan(%bp, %bn) : (!llvm.ptr, i64) -> !llvm.ptr
  %isNull = llvm.icmp "eq" %f, %null : !llvm.ptr
  %e1 = arith.select %isNull, %c1, %c0 : i64
  %tag0 = scf.if %isNull -> (i64) {
    scf.yield %m1 : i64
  } else {
    %t = func.call @cx_tag(%f, %c0) : (!llvm.ptr, i64) -> i64
    scf.yield %t : i64
  }
  %ok1 = arith.cmpi eq, %e1, %c0 : i64
  %notObj = arith.cmpi ne, %tag0, %c5 : i64
  %bad2 = arith.andi %ok1, %notObj : i1
  %e2 = arith.select %bad2, %c2, %e1 : i64
  %ok2 = arith.cmpi eq, %e2, %c0 : i64
  %kpath = llvm.mlir.addressof @lit54 : !llvm.ptr
  %kpath_n = arith.constant 4 : i64
  %p = scf.if %ok2 -> (i64) {
    %v = func.call @cx_member(%bp, %f, %c0, %kpath, %kpath_n) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
    scf.yield %v : i64
  } else {
    scf.yield %m1 : i64
  }
  %hasP = arith.cmpi sge, %p, %c0 : i64
  %pt = scf.if %hasP -> (i64) {
    %t = func.call @cx_tag(%f, %p) : (!llvm.ptr, i64) -> i64
    scf.yield %t : i64
  } else {
    scf.yield %m1 : i64
  }
  %notArr = arith.cmpi ne, %pt, %c6 : i64
  %bad3 = arith.andi %ok2, %notArr : i1
  %e3 = arith.select %bad3, %c3, %e2 : i64
  %ok3 = arith.cmpi eq, %e3, %c0 : i64
  %ns = scf.if %ok3 -> (i64) {
    %k = func.call @cx_nkids(%f, %p) : (!llvm.ptr, i64) -> i64
    scf.yield %k : i64
  } else {
    scf.yield %c0 : i64
  }
  %emptyP = arith.cmpi eq, %ns, %c0 : i64
  %bad4 = arith.andi %ok3, %emptyP : i1
  %e4 = arith.select %bad4, %c4, %e3 : i64
  %ns1 = arith.maxsi %ns, %c1 : i64
  %segs = llvm.call @calloc(%ns1, %c8) : (i64, i64) -> !llvm.ptr
  %badSeg = scf.for %k = %c0 to %ns step %c1 iter_args(%bad = %false) -> (i1) : i64 {
    %s = func.call @cx_kid(%f, %p, %k) : (!llvm.ptr, i64, i64) -> i64
    %st = func.call @cx_tag(%f, %s) : (!llvm.ptr, i64) -> i64
    %isS = arith.cmpi eq, %st, %c4 : i64
    %in = func.call @cx_str(%f, %s) : (!llvm.ptr, i64) -> i64
    func.call @st64(%segs, %k, %in) : (!llvm.ptr, i64, i64) -> ()
    %notS = arith.xori %isS, %true : i1
    %nb = arith.ori %bad, %notS : i1
    scf.yield %nb : i1
  }
  %ok4 = arith.cmpi eq, %e4, %c0 : i64
  %bad5 = arith.andi %ok4, %badSeg : i1
  %e5 = arith.select %bad5, %c5, %e4 : i64
  %ok5 = arith.cmpi eq, %e5, %c0 : i64
  %look = arith.andi %ok5, %want : i1
  %kvalue = llvm.mlir.addressof @lit55 : !llvm.ptr
  %kvalue_n = arith.constant 5 : i64
  %v = scf.if %look -> (i64) {
    %r = func.call @cx_member(%bp, %f, %c0, %kvalue, %kvalue_n) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
    scf.yield %r : i64
  } else {
    scf.yield %m1 : i64
  }
  %noV = arith.cmpi slt, %v, %c0 : i64
  %bad6 = arith.andi %look, %noV : i1
  %e6 = arith.select %bad6, %c6, %e5 : i64
  %hasV = arith.cmpi sge, %v, %c0 : i64
  %vt = scf.if %hasV -> (i64) {
    %r = func.call @cx_raw(%f, %v) : (!llvm.ptr, i64) -> i64
    scf.yield %r : i64
  } else {
    scf.yield %c0 : i64
  }
  %ok = arith.cmpi eq, %e6, %c0 : i64
  scf.if %ok {
  } else {
    %c400 = arith.constant 400 : i64
    func.call @fail(%c400) : (i64) -> ()
    %which = arith.index_cast %e6 : i64 to index
    scf.index_switch %which
    case 1 {
      %lit61 = llvm.mlir.addressof @lit56 : !llvm.ptr
      %litn61 = arith.constant 17 : i64
      func.call @ob_bytes(%lit61, %litn61) : (!llvm.ptr, i64) -> ()
      scf.yield
    }
    case 2 {
      %lit62 = llvm.mlir.addressof @lit57 : !llvm.ptr
      %litn62 = arith.constant 30 : i64
      func.call @ob_bytes(%lit62, %litn62) : (!llvm.ptr, i64) -> ()
      scf.yield
    }
    case 4 {
      %lit63 = llvm.mlir.addressof @lit58 : !llvm.ptr
      %litn63 = arith.constant 26 : i64
      func.call @ob_bytes(%lit63, %litn63) : (!llvm.ptr, i64) -> ()
      scf.yield
    }
    case 6 {
      %lit64 = llvm.mlir.addressof @lit59 : !llvm.ptr
      %litn64 = arith.constant 30 : i64
      func.call @ob_bytes(%lit64, %litn64) : (!llvm.ptr, i64) -> ()
      scf.yield
    }
    default {
      %lit65 = llvm.mlir.addressof @lit60 : !llvm.ptr
      %litn65 = arith.constant 45 : i64
      func.call @ob_bytes(%lit65, %litn65) : (!llvm.ptr, i64) -> ()
      scf.yield
    }
    func.call @fail_end() : () -> ()
  }
  return %f, %segs, %ns, %vt, %ok : !llvm.ptr, !llvm.ptr, i64, i64, i1
}

// The overlay with the member at the path set to the value (all coordinates in the body bp): the old value's span
// replaced, or the missing members inserted after the last member of the deepest object that exists.
func.func @set_at(%ov: !llvm.ptr, %ovn: i64, %bp: !llvm.ptr, %segs: !llvm.ptr, %ns: i64, %value: i64) -> (!llvm.ptr, i64, i1) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c5 = arith.constant 5 : i64
  %m1 = arith.constant -1 : i64
  %true = arith.constant true
  %false = arith.constant false
  %null = llvm.mlir.zero : !llvm.ptr
  %d = func.call @cx_scan(%ov, %ovn) : (!llvm.ptr, i64) -> !llvm.ptr
  %isNull = llvm.icmp "eq" %d, %null : !llvm.ptr
  %tag0 = scf.if %isNull -> (i64) {
    scf.yield %m1 : i64
  } else {
    %t = func.call @cx_tag(%d, %c0) : (!llvm.ptr, i64) -> i64
    scf.yield %t : i64
  }
  %isObj = arith.cmpi eq, %tag0, %c5 : i64
  %res:3 = scf.if %isObj -> (!llvm.ptr, i64, i1) {
    // walk the path: kind 0 while walking, 1 insert at obj, 2 replace v, 3 not an object
    %w:4 = scf.while (%i = %c0, %obj = %c0, %kind = %c0, %v = %m1) : (i64, i64, i64, i64) -> (i64, i64, i64, i64) {
      %go = arith.cmpi eq, %kind, %c0 : i64
      scf.condition(%go) %i, %obj, %kind, %v : i64, i64, i64, i64
    } do {
    ^bb0(%i: i64, %obj: i64, %kind: i64, %v: i64):
      %seg = func.call @ld64(%segs, %i) : (!llvm.ptr, i64) -> i64
      %vv = func.call @cx_member_at(%ov, %d, %obj, %bp, %seg) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
      %absent = arith.cmpi slt, %vv, %c0 : i64
      %i1 = arith.addi %i, %c1 : i64
      %last = arith.cmpi eq, %i1, %ns : i64
      %vt = scf.if %absent -> (i64) {
        scf.yield %m1 : i64
      } else {
        %t = func.call @cx_tag(%d, %vv) : (!llvm.ptr, i64) -> i64
        scf.yield %t : i64
      }
      %notObj = arith.cmpi ne, %vt, %c5 : i64
      %k3 = arith.select %notObj, %c3, %c0 : i64
      %k2 = arith.select %last, %c2, %k3 : i64
      %k1 = arith.select %absent, %c1, %k2 : i64
      %walk = arith.cmpi eq, %k1, %c0 : i64
      %nobj = arith.select %walk, %vv, %obj : i64
      %ni = arith.select %walk, %i1, %i : i64
      scf.yield %ni, %nobj, %k1, %vv : i64, i64, i64, i64
    }
    %level = arith.addi %w#0, %c0 : i64
    %kind = arith.addi %w#2, %c0 : i64
    %isNotObj = arith.cmpi eq, %kind, %c3 : i64
    %r:3 = scf.if %isNotObj -> (!llvm.ptr, i64, i1) {
      %c400 = arith.constant 400 : i64
      func.call @fail(%c400) : (i64) -> ()
      %lit66 = llvm.mlir.addressof @lit61 : !llvm.ptr
      %litn66 = arith.constant 9 : i64
      func.call @ob_bytes(%lit66, %litn66) : (!llvm.ptr, i64) -> ()
      %seg = func.call @ld64(%segs, %level) : (!llvm.ptr, i64) -> i64
      func.call @ob_esc(%bp, %seg) : (!llvm.ptr, i64) -> ()
      %lit67 = llvm.mlir.addressof @lit62 : !llvm.ptr
      %litn67 = arith.constant 17 : i64
      func.call @ob_bytes(%lit67, %litn67) : (!llvm.ptr, i64) -> ()
      func.call @fail_end() : () -> ()
      scf.yield %null, %c0, %false : !llvm.ptr, i64, i1
    } else {
      func.call @ob_start(%c0) : (i64) -> ()
      %isInsert = arith.cmpi eq, %kind, %c1 : i64
      scf.if %isInsert {
        %obj = arith.addi %w#1, %c0 : i64
        %kids = func.call @cx_nkids(%d, %obj) : (!llvm.ptr, i64) -> i64
        %empty = arith.cmpi eq, %kids, %c0 : i64
        %at = scf.if %empty -> (i64) {
          %o = func.call @cx_open(%d, %obj) : (!llvm.ptr, i64) -> i64
          %a = arith.addi %o, %c1 : i64
          scf.yield %a : i64
        } else {
          %lk = arith.subi %kids, %c1 : i64
          %lastKid = func.call @cx_kid(%d, %obj, %lk) : (!llvm.ptr, i64, i64) -> i64
          %cl = func.call @cx_close(%d, %lastKid) : (!llvm.ptr, i64) -> i64
          %a = arith.addi %cl, %c1 : i64
          scf.yield %a : i64
        }
        %head = func.call @tw(%c0, %at) : (i64, i64) -> i64
        func.call @ob_piece(%ov, %head) : (!llvm.ptr, i64) -> ()
        scf.if %empty {
        } else {
          %lit68 = llvm.mlir.addressof @lit63 : !llvm.ptr
          %litn68 = arith.constant 2 : i64
          func.call @ob_bytes(%lit68, %litn68) : (!llvm.ptr, i64) -> ()
        }
        %lit69 = llvm.mlir.addressof @lit49 : !llvm.ptr
        %litn69 = arith.constant 1 : i64
        func.call @ob_bytes(%lit69, %litn69) : (!llvm.ptr, i64) -> ()
        %seg = func.call @ld64(%segs, %level) : (!llvm.ptr, i64) -> i64
        func.call @ob_piece(%bp, %seg) : (!llvm.ptr, i64) -> ()
        %lit70 = llvm.mlir.addressof @lit64 : !llvm.ptr
        %litn70 = arith.constant 3 : i64
        func.call @ob_bytes(%lit70, %litn70) : (!llvm.ptr, i64) -> ()
        %from = arith.addi %level, %c1 : i64
        scf.for %j = %from to %ns step %c1 : i64 {
          %lit71 = llvm.mlir.addressof @lit65 : !llvm.ptr
          %litn71 = arith.constant 2 : i64
          func.call @ob_bytes(%lit71, %litn71) : (!llvm.ptr, i64) -> ()
          %sj = func.call @ld64(%segs, %j) : (!llvm.ptr, i64) -> i64
          func.call @ob_piece(%bp, %sj) : (!llvm.ptr, i64) -> ()
          %lit72 = llvm.mlir.addressof @lit64 : !llvm.ptr
          %litn72 = arith.constant 3 : i64
          func.call @ob_bytes(%lit72, %litn72) : (!llvm.ptr, i64) -> ()
        }
        func.call @ob_piece(%bp, %value) : (!llvm.ptr, i64) -> ()
        scf.for %j = %from to %ns step %c1 : i64 {
          %lit73 = llvm.mlir.addressof @lit40 : !llvm.ptr
          %litn73 = arith.constant 1 : i64
          func.call @ob_bytes(%lit73, %litn73) : (!llvm.ptr, i64) -> ()
        }
        %tail = func.call @tw(%at, %ovn) : (i64, i64) -> i64
        func.call @ob_piece(%ov, %tail) : (!llvm.ptr, i64) -> ()
      } else {
        %v = arith.addi %w#3, %c0 : i64
        %o = func.call @cx_open(%d, %v) : (!llvm.ptr, i64) -> i64
        %cl = func.call @cx_close(%d, %v) : (!llvm.ptr, i64) -> i64
        %cl1 = arith.addi %cl, %c1 : i64
        %head = func.call @tw(%c0, %o) : (i64, i64) -> i64
        func.call @ob_piece(%ov, %head) : (!llvm.ptr, i64) -> ()
        func.call @ob_piece(%bp, %value) : (!llvm.ptr, i64) -> ()
        %tail = func.call @tw(%cl1, %ovn) : (i64, i64) -> i64
        func.call @ob_piece(%ov, %tail) : (!llvm.ptr, i64) -> ()
      }
      %nn = func.call @ob_len() : () -> i64
      %next = func.call @ob_take() : () -> !llvm.ptr
      scf.yield %next, %nn, %true : !llvm.ptr, i64, i1
    }
    scf.yield %r#0, %r#1, %r#2 : !llvm.ptr, i64, i1
  } else {
    %c400 = arith.constant 400 : i64
    %why = llvm.mlir.addressof @lit66 : !llvm.ptr
    %why_n = arith.constant 32 : i64
    func.call @fail_with(%c400, %why, %why_n) : (i64, !llvm.ptr, i64) -> ()
    scf.yield %null, %c0, %false : !llvm.ptr, i64, i1
  }
  func.call @cx_free(%d) : (!llvm.ptr) -> ()
  return %res#0, %res#1, %res#2 : !llvm.ptr, i64, i1
}

// The overlay without the member at the path, and without the objects that leaves empty.  Absent is not an error.
func.func @remove_at(%ov: !llvm.ptr, %ovn: i64, %bp: !llvm.ptr, %segs: !llvm.ptr, %ns: i64) -> (!llvm.ptr, i64, i1) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c5 = arith.constant 5 : i64
  %c8 = arith.constant 8 : i64
  %m1 = arith.constant -1 : i64
  %true = arith.constant true
  %false = arith.constant false
  %null = llvm.mlir.zero : !llvm.ptr
  %d = func.call @cx_scan(%ov, %ovn) : (!llvm.ptr, i64) -> !llvm.ptr
  %isNull = llvm.icmp "eq" %d, %null : !llvm.ptr
  %tag0 = scf.if %isNull -> (i64) {
    scf.yield %m1 : i64
  } else {
    %t = func.call @cx_tag(%d, %c0) : (!llvm.ptr, i64) -> i64
    scf.yield %t : i64
  }
  %isObj = arith.cmpi eq, %tag0, %c5 : i64
  %res:3 = scf.if %isObj -> (!llvm.ptr, i64, i1) {
    %ns1 = arith.addi %ns, %c1 : i64
    %objs = llvm.call @calloc(%ns1, %c8) : (i64, i64) -> !llvm.ptr
    %keys = llvm.call @calloc(%ns1, %c8) : (i64, i64) -> !llvm.ptr
    %vals = llvm.call @calloc(%ns1, %c8) : (i64, i64) -> !llvm.ptr
    %idxs = llvm.call @calloc(%ns1, %c8) : (i64, i64) -> !llvm.ptr
    // walk: state 0 while walking, 1 absent (nothing to cut), 2 found
    %w:2 = scf.while (%i = %c0, %state = %c0) : (i64, i64) -> (i64, i64) {
      %go = arith.cmpi eq, %state, %c0 : i64
      scf.condition(%go) %i, %state : i64, i64
    } do {
    ^bb0(%i: i64, %state: i64):
      %o = func.call @ld64(%objs, %i) : (!llvm.ptr, i64) -> i64
      %seg = func.call @ld64(%segs, %i) : (!llvm.ptr, i64) -> i64
      %ix = func.call @cx_find_at(%ov, %d, %o, %bp, %seg) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
      %absent = arith.cmpi slt, %ix, %c0 : i64
      %r:2 = scf.if %absent -> (i64, i64) {
        scf.yield %i, %c1 : i64, i64
      } else {
        %key = func.call @cx_kid(%d, %o, %ix) : (!llvm.ptr, i64, i64) -> i64
        %ix1 = arith.addi %ix, %c1 : i64
        %v = func.call @cx_kid(%d, %o, %ix1) : (!llvm.ptr, i64, i64) -> i64
        func.call @st64(%keys, %i, %key) : (!llvm.ptr, i64, i64) -> ()
        func.call @st64(%vals, %i, %v) : (!llvm.ptr, i64, i64) -> ()
        func.call @st64(%idxs, %i, %ix) : (!llvm.ptr, i64, i64) -> ()
        %i1 = arith.addi %i, %c1 : i64
        %last = arith.cmpi eq, %i1, %ns : i64
        %r2:2 = scf.if %last -> (i64, i64) {
          scf.yield %i, %c2 : i64, i64
        } else {
          %vt = func.call @cx_tag(%d, %v) : (!llvm.ptr, i64) -> i64
          %vObj = arith.cmpi eq, %vt, %c5 : i64
          func.call @st64(%objs, %i1, %v) : (!llvm.ptr, i64, i64) -> ()
          %stt = arith.select %vObj, %c0, %c1 : i64
          scf.yield %i1, %stt : i64, i64
        }
        scf.yield %r2#0, %r2#1 : i64, i64
      }
      scf.yield %r#0, %r#1 : i64, i64
    }
    %found = arith.cmpi eq, %w#1, %c2 : i64
    func.call @ob_start(%c0) : (i64) -> ()
    scf.if %found {
      // cut the deepest member whose object keeps another member (or the top level's)
      %top = arith.subi %ns, %c1 : i64
      %level = scf.while (%l = %top) : (i64) -> i64 {
        %deep = arith.cmpi sgt, %l, %c0 : i64
        %alone = scf.if %deep -> (i1) {
          %o = func.call @ld64(%objs, %l) : (!llvm.ptr, i64) -> i64
          %k = func.call @cx_nkids(%d, %o) : (!llvm.ptr, i64) -> i64
          %two = arith.cmpi eq, %k, %c2 : i64
          scf.yield %two : i1
        } else {
          scf.yield %false : i1
        }
        scf.condition(%alone) %l : i64
      } do {
      ^bb0(%l: i64):
        %up = arith.subi %l, %c1 : i64
        scf.yield %up : i64
      }
      %o = func.call @ld64(%objs, %level) : (!llvm.ptr, i64) -> i64
      %key = func.call @ld64(%keys, %level) : (!llvm.ptr, i64) -> i64
      %v = func.call @ld64(%vals, %level) : (!llvm.ptr, i64) -> i64
      %pos = func.call @ld64(%idxs, %level) : (!llvm.ptr, i64) -> i64
      %nk = func.call @cx_nkids(%d, %o) : (!llvm.ptr, i64) -> i64
      %p2 = arith.addi %pos, %c2 : i64
      %hasNext = arith.cmpi slt, %p2, %nk : i64
      %hasPrev = arith.cmpi sgt, %pos, %c0 : i64
      // [from, to) is cut: the member and one comma beside it
      %cut:2 = scf.if %hasNext -> (i64, i64) {
        %from = func.call @cx_open(%d, %key) : (!llvm.ptr, i64) -> i64
        %nextKey = func.call @cx_kid(%d, %o, %p2) : (!llvm.ptr, i64, i64) -> i64
        %to = func.call @cx_open(%d, %nextKey) : (!llvm.ptr, i64) -> i64
        scf.yield %from, %to : i64, i64
      } else {
        %vc = func.call @cx_close(%d, %v) : (!llvm.ptr, i64) -> i64
        %to = arith.addi %vc, %c1 : i64
        %r3:2 = scf.if %hasPrev -> (i64, i64) {
          %pm = arith.subi %pos, %c1 : i64
          %prevVal = func.call @cx_kid(%d, %o, %pm) : (!llvm.ptr, i64, i64) -> i64
          %pc = func.call @cx_close(%d, %prevVal) : (!llvm.ptr, i64) -> i64
          %from = arith.addi %pc, %c1 : i64
          scf.yield %from, %to : i64, i64
        } else {
          %from = func.call @cx_open(%d, %key) : (!llvm.ptr, i64) -> i64
          scf.yield %from, %to : i64, i64
        }
        scf.yield %r3#0, %r3#1 : i64, i64
      }
      %head = func.call @tw(%c0, %cut#0) : (i64, i64) -> i64
      func.call @ob_piece(%ov, %head) : (!llvm.ptr, i64) -> ()
      %tail = func.call @tw(%cut#1, %ovn) : (i64, i64) -> i64
      func.call @ob_piece(%ov, %tail) : (!llvm.ptr, i64) -> ()
    } else {
      %all = func.call @tw(%c0, %ovn) : (i64, i64) -> i64
      func.call @ob_piece(%ov, %all) : (!llvm.ptr, i64) -> ()
    }
    llvm.call @free(%objs) : (!llvm.ptr) -> ()
    llvm.call @free(%keys) : (!llvm.ptr) -> ()
    llvm.call @free(%vals) : (!llvm.ptr) -> ()
    llvm.call @free(%idxs) : (!llvm.ptr) -> ()
    %nn = func.call @ob_len() : () -> i64
    %next = func.call @ob_take() : () -> !llvm.ptr
    scf.yield %next, %nn, %true : !llvm.ptr, i64, i1
  } else {
    %c400 = arith.constant 400 : i64
    %why = llvm.mlir.addressof @lit66 : !llvm.ptr
    %why_n = arith.constant 32 : i64
    func.call @fail_with(%c400, %why, %why_n) : (i64, !llvm.ptr, i64) -> ()
    scf.yield %null, %c0, %false : !llvm.ptr, i64, i1
  }
  func.call @cx_free(%d) : (!llvm.ptr) -> ()
  return %res#0, %res#1, %res#2 : !llvm.ptr, i64, i1
}

func.func @whatif_set(%in: !llvm.ptr, %body: i64) {
  %bs = func.call @tw_s(%body) : (i64) -> i64
  %bn = func.call @tw_n(%body) : (i64) -> i64
  %bp = func.call @off(%in, %bs) : (!llvm.ptr, i64) -> !llvm.ptr
  %true = arith.constant true
  %r:5 = func.call @request(%bp, %bn, %true) : (!llvm.ptr, i64, i1) -> (!llvm.ptr, !llvm.ptr, i64, i64, i1)
  scf.if %r#4 {
    %pov = llvm.mlir.addressof @g_ov : !llvm.ptr
    %ov = llvm.load %pov : !llvm.ptr -> !llvm.ptr
    %povn = llvm.mlir.addressof @g_ovn : !llvm.ptr
    %ovn = llvm.load %povn : !llvm.ptr -> i64
    %s:3 = func.call @set_at(%ov, %ovn, %bp, %r#1, %r#2, %r#3) : (!llvm.ptr, i64, !llvm.ptr, !llvm.ptr, i64, i64) -> (!llvm.ptr, i64, i1)
    scf.if %s#2 {
      func.call @whatif(%s#0, %s#1) : (!llvm.ptr, i64) -> ()
    }
  }
  func.call @cx_free(%r#0) : (!llvm.ptr) -> ()
  llvm.call @free(%r#1) : (!llvm.ptr) -> ()
  return
}

func.func @whatif_reset(%in: !llvm.ptr, %body: i64) {
  %c0 = arith.constant 0 : i64
  %c5 = arith.constant 5 : i64
  %m1 = arith.constant -1 : i64
  %bs = func.call @tw_s(%body) : (i64) -> i64
  %bn = func.call @tw_n(%body) : (i64) -> i64
  %bp = func.call @off(%in, %bs) : (!llvm.ptr, i64) -> !llvm.ptr
  %false = arith.constant false
  %r:5 = func.call @request(%bp, %bn, %false) : (!llvm.ptr, i64, i1) -> (!llvm.ptr, !llvm.ptr, i64, i64, i1)
  scf.if %r#4 {
    %pov = llvm.mlir.addressof @g_ov : !llvm.ptr
    %ov = llvm.load %pov : !llvm.ptr -> !llvm.ptr
    %povn = llvm.mlir.addressof @g_ovn : !llvm.ptr
    %ovn = llvm.load %povn : !llvm.ptr -> i64
    %s:3 = func.call @remove_at(%ov, %ovn, %bp, %r#1, %r#2) : (!llvm.ptr, i64, !llvm.ptr, !llvm.ptr, i64) -> (!llvm.ptr, i64, i1)
    scf.if %s#2 {
      // an overlay left with no member is {}
      %d2 = func.call @cx_scan(%s#0, %s#1) : (!llvm.ptr, i64) -> !llvm.ptr
      %null = llvm.mlir.zero : !llvm.ptr
      %isNull = llvm.icmp "eq" %d2, %null : !llvm.ptr
      %emptied = scf.if %isNull -> (i1) {
        scf.yield %false : i1
      } else {
        %k = func.call @cx_nkids(%d2, %c0) : (!llvm.ptr, i64) -> i64
        %none = arith.cmpi eq, %k, %c0 : i64
        scf.yield %none : i1
      }
      func.call @cx_free(%d2) : (!llvm.ptr) -> ()
      scf.if %emptied {
        llvm.call @free(%s#0) : (!llvm.ptr) -> ()
        %e = func.call @empty_object() : () -> !llvm.ptr
        %c2 = arith.constant 2 : i64
        func.call @whatif(%e, %c2) : (!llvm.ptr, i64) -> ()
      } else {
        func.call @whatif(%s#0, %s#1) : (!llvm.ptr, i64) -> ()
      }
    }
  }
  func.call @cx_free(%r#0) : (!llvm.ptr) -> ()
  llvm.call @free(%r#1) : (!llvm.ptr) -> ()
  return
}
