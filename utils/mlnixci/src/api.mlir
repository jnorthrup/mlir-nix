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
llvm.func @_mlir_ciface_etc_join(!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
llvm.func @_mlir_ciface_report_reply(!llvm.ptr, !llvm.ptr, f64, f64, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr)
llvm.func @_mlir_ciface_query_text(!llvm.ptr, !llvm.ptr)
llvm.func @_mlir_ciface_query_reply(!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64, i64, f64)
llvm.func @_mlir_ciface_corpus_query(!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64

func.func private @tw(i64, i64) -> i64
func.func private @tw_s(i64) -> i64
func.func private @tw_e(i64) -> i64
func.func private @tw_n(i64) -> i64
func.func private @off(!llvm.ptr, i64) -> !llvm.ptr
func.func private @is(!llvm.ptr, i64, !llvm.ptr, i64) -> i1
func.func private @ob_start(i64)
func.func private @ob_room(i64) -> !llvm.ptr
func.func private @ob_used(i64)
func.func private @ob_bytes(!llvm.ptr, i64)
func.func private @cx_scan(!llvm.ptr, i64) -> !llvm.ptr
func.func private @cx_free(!llvm.ptr)
func.func private @cx_tag(!llvm.ptr, i64) -> i64
func.func private @cx_open(!llvm.ptr, i64) -> i64
func.func private @cx_close(!llvm.ptr, i64) -> i64
func.func private @cx_nkids(!llvm.ptr, i64) -> i64
func.func private @cx_kid(!llvm.ptr, i64, i64) -> i64
func.func private @cx_d(!llvm.ptr, i32) -> !llvm.ptr
func.func private @cx_text(!llvm.ptr) -> !llvm.ptr
func.func private @view(!llvm.ptr, !llvm.ptr, i64)
func.func private @getp(!llvm.ptr, i64) -> !llvm.ptr
func.func private @geti(!llvm.ptr, i64) -> i64
func.func private @ld64(!llvm.ptr, i64) -> i64
func.func private @st64(!llvm.ptr, i64, i64)
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
llvm.mlir.global internal constant @lit12("no route ") : !llvm.array<9 x i8>
llvm.mlir.global internal constant @lit13(" ") : !llvm.array<1 x i8>
llvm.mlir.global internal constant @lit14("cannot read ") : !llvm.array<12 x i8>
llvm.mlir.global internal constant @lit15("query: a JSON object is required") : !llvm.array<32 x i8>
llvm.mlir.global internal constant @lit52("mlnix failed") : !llvm.array<12 x i8>
llvm.mlir.global internal constant @lit53("cannot write ") : !llvm.array<13 x i8>
llvm.mlir.global internal constant @lit56("request: not JSON") : !llvm.array<17 x i8>
llvm.mlir.global internal constant @lit57("request: an object is required") : !llvm.array<30 x i8>
llvm.mlir.global internal constant @lit58("request: \5C\22path\5C\22 is empty") : !llvm.array<26 x i8>
llvm.mlir.global internal constant @lit59("request: \5C\22value\5C\22 is required") : !llvm.array<30 x i8>
llvm.mlir.global internal constant @lit60("request: \5C\22path\5C\22 must be an array of strings") : !llvm.array<45 x i8>
llvm.mlir.global internal constant @lit61("overlay: ") : !llvm.array<9 x i8>
llvm.mlir.global internal constant @lit62(" is not an object") : !llvm.array<17 x i8>
llvm.mlir.global internal constant @lit66("the overlay is not a JSON object") : !llvm.array<32 x i8>
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

// {"error":"<lead><a escaped><mid><b escaped>"} with its status: text.mlir's error_reply, written into the builder.  lead
// and mid are literals written as they are; a and b are escaped (a request's method or path, a file, mlnix's error).
llvm.func @_mlir_ciface_error_reply(!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr)
func.func @fail_text(%status: i64, %lead: !llvm.ptr, %leadN: i64, %a: !llvm.ptr, %aN: i64, %mid: !llvm.ptr, %midN: i64,
                     %b: !llvm.ptr, %bN: i64) {
  %one = arith.constant 1 : i32
  %dl = llvm.alloca %one x !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)> : (i32) -> !llvm.ptr
  func.call @view(%dl, %lead, %leadN) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %da = llvm.alloca %one x !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)> : (i32) -> !llvm.ptr
  func.call @view(%da, %a, %aN) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %dm = llvm.alloca %one x !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)> : (i32) -> !llvm.ptr
  func.call @view(%dm, %mid, %midN) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %db = llvm.alloca %one x !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)> : (i32) -> !llvm.ptr
  func.call @view(%db, %b, %bN) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %reply = llvm.alloca %one x !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)> : (i32) -> !llvm.ptr
  llvm.call @_mlir_ciface_error_reply(%reply, %dl, %da, %dm, %db) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> ()
  func.call @begin(%status) : (i64) -> ()
  func.call @ob_made(%reply) : (!llvm.ptr) -> ()
  return
}

// {"error":"<the n bytes at p, escaped>"}
func.func @fail_with(%status: i64, %p: !llvm.ptr, %n: i64) {
  %c0 = arith.constant 0 : i64
  func.call @fail_text(%status, %p, %c0, %p, %n, %p, %c0, %p, %c0) : (i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64) -> ()
  return
}

// a piece's place and length, for fail_text
func.func @piece_at(%base: !llvm.ptr, %t: i64) -> (!llvm.ptr, i64) {
  %s = func.call @tw_s(%t) : (i64) -> i64
  %n = func.call @tw_n(%t) : (i64) -> i64
  %p = func.call @off(%base, %s) : (!llvm.ptr, i64) -> !llvm.ptr
  return %p, %n : !llvm.ptr, i64
}

// mlnix's refusal (422): its error, or "mlnix failed" when it said nothing
func.func @fail_refused() {
  %c0 = arith.constant 0 : i64
  %e = func.call @run_err() : () -> !llvm.ptr
  %en = func.call @run_err_n() : () -> i64
  %c422 = arith.constant 422 : i64
  %said = arith.cmpi sgt, %en, %c0 : i64
  %failed = llvm.mlir.addressof @lit52 : !llvm.ptr
  %c12 = arith.constant 12 : i64
  %leadN = arith.select %said, %c0, %c12 : i64
  %at = arith.select %said, %e, %failed : !llvm.ptr
  %an = arith.select %said, %en, %c0 : i64
  func.call @fail_text(%c422, %failed, %leadN, %at, %an, %failed, %c0, %failed, %c0) : (i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64) -> ()
  return
}

// "cannot <what> <file>" (500)
func.func @fail_file(%what: !llvm.ptr, %whatN: i64, %file: !llvm.ptr) {
  %c0 = arith.constant 0 : i64
  %c500 = arith.constant 500 : i64
  %fl = llvm.call @strlen(%file) : (!llvm.ptr) -> i64
  func.call @fail_text(%c500, %what, %whatN, %file, %fl, %what, %c0, %what, %c0) : (i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64) -> ()
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

// ---- the routes

// which: the route request.mlir's rq_route named (its kursive alternation's group, 0 for none): 1 the page, 2 POST
// /api/query, 3 GET /api/query, 4 the report, 5 6 7 the what-if's set, reset and clear, 8 the facets
func.func @route(%in: !llvm.ptr, %method: i64, %path: i64, %body: i64, %route: i64) {
  %which = arith.index_cast %route : i64 to index
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
    %noRoute = llvm.mlir.addressof @lit12 : !llvm.ptr
    %noRoute_n = arith.constant 9 : i64
    %sp = llvm.mlir.addressof @lit13 : !llvm.ptr
    %sp_n = arith.constant 1 : i64
    %mp, %mn = func.call @piece_at(%in, %method) : (!llvm.ptr, i64) -> (!llvm.ptr, i64)
    %pp, %pn = func.call @piece_at(%in, %path) : (!llvm.ptr, i64) -> (!llvm.ptr, i64)
    func.call @fail_text(%c404, %noRoute, %noRoute_n, %mp, %mn, %sp, %sp_n, %pp, %pn) : (i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64) -> ()
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
    %lit5 = llvm.mlir.addressof @lit14 : !llvm.ptr
    %litn5 = arith.constant 12 : i64
    func.call @fail_file(%lit5, %litn5, %page) : (!llvm.ptr, i64, !llvm.ptr) -> ()
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
        func.call @fail_refused() : () -> ()
      } else {
        %out = func.call @run_out() : () -> !llvm.ptr
        %on = func.call @run_out_n() : () -> i64
        %c200 = arith.constant 200 : i64
        func.call @begin(%c200) : (i64) -> ()
        func.call @ob_bytes(%out, %on) : (!llvm.ptr, i64) -> ()
        llvm.call @free(%out) : (!llvm.ptr) -> ()
      }
    } else {
      %cannot = llvm.mlir.addressof @lit53 : !llvm.ptr
      %cannot_n = arith.constant 13 : i64
      func.call @fail_file(%cannot, %cannot_n, %file) : (!llvm.ptr, i64, !llvm.ptr) -> ()
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

llvm.func @_mlir_ciface_rq_query(!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr)
llvm.func @_mlir_ciface_rq_pick(!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
llvm.func @_mlir_ciface_rq_hay_end(!llvm.ptr) -> i64
llvm.func @_mlir_ciface_rq_match(!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
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
  // the body, through its index (request.mlir's rq_query): the select's row, the text searched for, offset and limit;
  // then each column's selection (rq_pick: the select's array for the column, its elements against the codes' names)
  %i0 = arith.constant 0 : i32
  %i1 = arith.constant 1 : i32
  %i2 = arith.constant 2 : i32
  %i3 = arith.constant 3 : i32
  %fd0 = func.call @cx_d(%f, %i0) : (!llvm.ptr, i32) -> !llvm.ptr
  %fd1 = func.call @cx_d(%f, %i1) : (!llvm.ptr, i32) -> !llvm.ptr
  %fd2 = func.call @cx_d(%f, %i2) : (!llvm.ptr, i32) -> !llvm.ptr
  %fd3 = func.call @cx_d(%f, %i3) : (!llvm.ptr, i32) -> !llvm.ptr
  %ftd = func.call @cx_text(%f) : (!llvm.ptr) -> !llvm.ptr
  %asked = llvm.alloca %one32 x !llvm.array<4 x i64> : (i32) -> !llvm.ptr
  %askedD = llvm.alloca %one32 x !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)> : (i32) -> !llvm.ptr
  func.call @view(%askedD, %asked, %c4) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  llvm.call @_mlir_ciface_rq_query(%fd0, %fd1, %fd2, %fd3, %ftd, %askedD) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> ()
  %select = func.call @geti(%asked, %c0) : (!llvm.ptr, i64) -> i64
  %qt = func.call @geti(%asked, %c1) : (!llvm.ptr, i64) -> i64
  %offset = func.call @geti(%asked, %c2) : (!llvm.ptr, i64) -> i64
  %limit = func.call @geti(%asked, %c3) : (!llvm.ptr, i64) -> i64
  %names = llvm.mlir.addressof @k_names : !llvm.ptr
  %c7 = arith.constant 7 : i64
  %c8 = arith.constant 8 : i64
  %c17 = arith.constant 17 : i64
  %c49 = arith.constant 49 : i64
  %tlen0 = func.call @geti(%cur, %c1) : (!llvm.ptr, i64) -> i64
  %textLen = arith.addi %tlen0, %c7 : i64
  // the fixed columns' codes' names: whatif's same and changed (names 6, 7), match's no and yes (8, 9)
  %fixed = llvm.alloca %one32 x !llvm.array<4 x i64> : (i32) -> !llvm.ptr
  scf.for %c = %c0 to %c4 step %c1 : i64 {
    %nk = arith.addi %c6, %c : i64
    %np = func.call @name_piece(%nk) : (i64) -> i64
    func.call @st64(%fixed, %c, %np) : (!llvm.ptr, i64, i64) -> ()
  }
  %dn = llvm.alloca %one32 x !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)> : (i32) -> !llvm.ptr
  %dv = llvm.alloca %one32 x !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)> : (i32) -> !llvm.ptr
  %dp = llvm.alloca %one32 x !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)> : (i32) -> !llvm.ptr
  %dsel = llvm.alloca %one32 x !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)> : (i32) -> !llvm.ptr
  scf.for %fi = %c0 to %c6 step %c1 : i64 {
    %k = func.call @codes(%fi) : (i64) -> i64
    %ps = llvm.getelementptr %sels[%fi] : (!llvm.ptr, i64) -> !llvm.ptr, !llvm.ptr
    %sel = llvm.load %ps : !llvm.ptr -> !llvm.ptr
    %nt = func.call @name_piece(%fi) : (i64) -> i64
    %nsx = func.call @tw_s(%nt) : (i64) -> i64
    %nl = func.call @tw_n(%nt) : (i64) -> i64
    %np = func.call @off(%names, %nsx) : (!llvm.ptr, i64) -> !llvm.ptr
    func.call @view(%dn, %np, %nl) : (!llvm.ptr, !llvm.ptr, i64) -> ()
    // the codes' names: pieces of the corpus's text (the coded columns' dictionaries), else of the names
    %coded = arith.cmpi slt, %fi, %c4 : i64
    %slot = arith.addi %c17, %fi : i64
    %pieces = scf.if %coded -> (!llvm.ptr) {
      %dict = func.call @getp(%cur, %slot) : (!llvm.ptr, i64) -> !llvm.ptr
      scf.yield %dict : !llvm.ptr
    } else {
      %isw = arith.cmpi eq, %fi, %c4 : i64
      %at = arith.select %isw, %c0, %c2 : i64
      %fp = llvm.getelementptr %fixed[%at] : (!llvm.ptr, i64) -> !llvm.ptr, i64
      scf.yield %fp : !llvm.ptr
    }
    %vText = arith.select %coded, %text, %names : !llvm.ptr
    %vLen = arith.select %coded, %textLen, %c49 : i64
    func.call @view(%dv, %vText, %vLen) : (!llvm.ptr, !llvm.ptr, i64) -> ()
    func.call @view(%dp, %pieces, %k) : (!llvm.ptr, !llvm.ptr, i64) -> ()
    func.call @view(%dsel, %sel, %k) : (!llvm.ptr, !llvm.ptr, i64) -> ()
    %picks = llvm.call @_mlir_ciface_rq_pick(%fd0, %fd1, %fd2, %fd3, %ftd, %select, %dn, %dv, %dp, %dsel)
        : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
    %picked = arith.cmpi ne, %picks, %c0 : i64
    scf.if %picked {
      func.call @st64(%anys, %fi, %c1) : (!llvm.ptr, i64, i64) -> ()
    }
  }
  // the text searched for; the match column's selection is "yes" only, when there is one
  %qlow, %qn = func.call @search_query(%bp, %qt) : (!llvm.ptr, i64) -> (!llvm.ptr, i64)
  // every row's text searched at once: request.mlir's rq_match (one trikeshed alpha over hayAt, rd_search on each
  // row's piece of hay, drained into match); hay is viewed as far as its furthest piece (rq_hay_end)
  %hay = func.call @getp(%cur, %c9) : (!llvm.ptr, i64) -> !llvm.ptr
  %hayAt = func.call @getp(%cur, %c10) : (!llvm.ptr, i64) -> !llvm.ptr
  %match = func.call @getp(%cur, %c16) : (!llvm.ptr, i64) -> !llvm.ptr
  %dAt = llvm.alloca %one32 x !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)> : (i32) -> !llvm.ptr
  func.call @view(%dAt, %hayAt, %n) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %hayN = llvm.call @_mlir_ciface_rq_hay_end(%dAt) : (!llvm.ptr) -> i64
  %dHay = llvm.alloca %one32 x !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)> : (i32) -> !llvm.ptr
  func.call @view(%dHay, %hay, %hayN) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %dQ = llvm.alloca %one32 x !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)> : (i32) -> !llvm.ptr
  func.call @view(%dQ, %qlow, %qn) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %dMatch = llvm.alloca %one32 x !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)> : (i32) -> !llvm.ptr
  func.call @view(%dMatch, %match, %n) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %nm = llvm.call @_mlir_ciface_rq_match(%dHay, %dAt, %dQ, %dMatch) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
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
  %c13 = arith.constant 13 : i64
  %c14 = arith.constant 14 : i64
  %c15 = arith.constant 15 : i64
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
  func.call @ob_made(%reply) : (!llvm.ptr) -> ()
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

// ---- the report: text.mlir's report_reply over the overlay, the options the what-if changed (their values and states
// before and after) and the /etc files whose text differs (columns.mlir's etc_join), written into the builder

func.func @report() {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %c5 = arith.constant 5 : i64
  %c6 = arith.constant 6 : i64
  %c7 = arith.constant 7 : i64
  %c8 = arith.constant 8 : i64
  %c9 = arith.constant 9 : i64
  %c10 = arith.constant 10 : i64
  %c11 = arith.constant 11 : i64
  %c12 = arith.constant 12 : i64
  %c13 = arith.constant 13 : i64
  %c14 = arith.constant 14 : i64
  %c15 = arith.constant 15 : i64
  %c16 = arith.constant 16 : i64
  %c20 = arith.constant 20 : i64
  %c25 = arith.constant 25 : i64
  %c26 = arith.constant 26 : i64
  %c28 = arith.constant 28 : i64
  %c29 = arith.constant 29 : i64
  %c40 = arith.constant 40 : i64
  %i0 = arith.constant 0 : i32
  %i1 = arith.constant 1 : i32
  %i2 = arith.constant 2 : i32
  %i3 = arith.constant 3 : i32
  %cur = func.call @cur() : () -> !llvm.ptr
  %bc = func.call @base() : () -> !llvm.ptr
  %c200 = arith.constant 200 : i64
  func.call @begin(%c200) : (i64) -> ()
  %pov = llvm.mlir.addressof @g_ov : !llvm.ptr
  %ov = llvm.load %pov : !llvm.ptr -> !llvm.ptr
  %povn = llvm.mlir.addressof @g_ovn : !llvm.ptr
  %ovn = llvm.load %povn : !llvm.ptr -> i64
  %msb = func.call @geti(%bc, %c26) : (!llvm.ptr, i64) -> i64
  %msbf = arith.bitcast %msb : i64 to f64
  %msc = func.call @geti(%cur, %c26) : (!llvm.ptr, i64) -> i64
  %mscf = arith.bitcast %msc : i64 to f64
  // the /etc objects of the base (A) and of the what-if (B): their members joined by name, and each member's pieces
  %fb = func.call @getp(%bc, %c2) : (!llvm.ptr, i64) -> !llvm.ptr
  %eb = func.call @geti(%bc, %c25) : (!llvm.ptr, i64) -> i64
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
  %kb1 = arith.addi %kb, %c1 : i64
  %kc1 = arith.addi %kc, %c1 : i64
  %entries = llvm.call @calloc(%room, %c4) : (i64, i64) -> !llvm.ptr
  %other = llvm.call @calloc(%room, %c4) : (i64, i64) -> !llvm.ptr
  %namesA = llvm.call @calloc(%kb1, %c8) : (i64, i64) -> !llvm.ptr
  %valuesA = llvm.call @calloc(%kb1, %c8) : (i64, i64) -> !llvm.ptr
  %namesB = llvm.call @calloc(%kc1, %c8) : (i64, i64) -> !llvm.ptr
  %valuesB = llvm.call @calloc(%kc1, %c8) : (i64, i64) -> !llvm.ptr
  %rd = llvm.call @calloc(%c20, %c40) : (i64, i64) -> !llvm.ptr
  func.call @desc(%rd, %c0, %entries, %both) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
  func.call @desc(%rd, %c1, %other, %both) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
  func.call @desc(%rd, %c2, %namesA, %kb) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
  func.call @desc(%rd, %c3, %valuesA, %kb) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
  func.call @desc(%rd, %c4, %namesB, %kc) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
  func.call @desc(%rd, %c5, %valuesB, %kc) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
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
  %r0 = func.call @dk(%rd, %c0) : (!llvm.ptr, i64) -> !llvm.ptr
  %r1 = func.call @dk(%rd, %c1) : (!llvm.ptr, i64) -> !llvm.ptr
  %r2 = func.call @dk(%rd, %c2) : (!llvm.ptr, i64) -> !llvm.ptr
  %r3 = func.call @dk(%rd, %c3) : (!llvm.ptr, i64) -> !llvm.ptr
  %r4 = func.call @dk(%rd, %c4) : (!llvm.ptr, i64) -> !llvm.ptr
  %r5 = func.call @dk(%rd, %c5) : (!llvm.ptr, i64) -> !llvm.ptr
  %ne = llvm.call @_mlir_ciface_etc_join(%a0, %a1, %a2, %a3, %at, %eb, %b0, %b1, %b2, %b3, %bt, %ec, %r0, %r1, %r2, %r3, %r4, %r5) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
  // the entries etc_join found, and the corpus and its base: report_reply's descriptors
  func.call @desc(%rd, %c0, %entries, %ne) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
  func.call @desc(%rd, %c1, %other, %ne) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
  %n = func.call @geti(%cur, %c3) : (!llvm.ptr, i64) -> i64
  %text = func.call @getp(%cur, %c0) : (!llvm.ptr, i64) -> !llvm.ptr
  %len = func.call @geti(%cur, %c1) : (!llvm.ptr, i64) -> i64
  %tlen = arith.addi %len, %c7 : i64
  %keys = func.call @getp(%cur, %c7) : (!llvm.ptr, i64) -> !llvm.ptr
  %klen = func.call @geti(%cur, %c29) : (!llvm.ptr, i64) -> i64
  %key = func.call @getp(%cur, %c8) : (!llvm.ptr, i64) -> !llvm.ptr
  %val = func.call @getp(%cur, %c5) : (!llvm.ptr, i64) -> !llvm.ptr
  %st = func.call @getp(%cur, %c6) : (!llvm.ptr, i64) -> !llvm.ptr
  %whatif = func.call @getp(%cur, %c15) : (!llvm.ptr, i64) -> !llvm.ptr
  %baseOf = func.call @getp(%cur, %c28) : (!llvm.ptr, i64) -> !llvm.ptr
  %btext = func.call @getp(%bc, %c0) : (!llvm.ptr, i64) -> !llvm.ptr
  %blen = func.call @geti(%bc, %c1) : (!llvm.ptr, i64) -> i64
  %btlen = arith.addi %blen, %c7 : i64
  %bn = func.call @geti(%bc, %c3) : (!llvm.ptr, i64) -> i64
  %bval = func.call @getp(%bc, %c5) : (!llvm.ptr, i64) -> !llvm.ptr
  %bst = func.call @getp(%bc, %c6) : (!llvm.ptr, i64) -> !llvm.ptr
  func.call @desc(%rd, %c6, %ov, %ovn) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
  func.call @desc(%rd, %c7, %text, %tlen) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
  func.call @desc(%rd, %c8, %keys, %klen) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
  func.call @desc(%rd, %c9, %key, %n) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
  func.call @desc(%rd, %c10, %val, %n) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
  func.call @desc(%rd, %c11, %st, %n) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
  func.call @desc(%rd, %c12, %whatif, %n) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
  func.call @desc(%rd, %c13, %baseOf, %n) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
  func.call @desc(%rd, %c14, %btext, %btlen) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
  func.call @desc(%rd, %c15, %bval, %bn) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
  func.call @desc(%rd, %c16, %bst, %bn) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
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
  %one32 = arith.constant 1 : i32
  %reply = llvm.alloca %one32 x !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)> : (i32) -> !llvm.ptr
  llvm.call @_mlir_ciface_report_reply(%reply, %r6, %msbf, %mscf, %r7, %r8, %r9, %r10, %r11, %r12, %r13, %r14, %r15, %r16, %at, %r2, %r3, %bt, %r4, %r5, %r0, %r1) : (!llvm.ptr, !llvm.ptr, f64, f64, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> ()
  func.call @ob_made(%reply) : (!llvm.ptr) -> ()
  llvm.call @free(%rd) : (!llvm.ptr) -> ()
  llvm.call @free(%entries) : (!llvm.ptr) -> ()
  llvm.call @free(%other) : (!llvm.ptr) -> ()
  llvm.call @free(%namesA) : (!llvm.ptr) -> ()
  llvm.call @free(%valuesA) : (!llvm.ptr) -> ()
  llvm.call @free(%namesB) : (!llvm.ptr) -> ()
  llvm.call @free(%valuesB) : (!llvm.ptr) -> ()
  return
}

// a text that text.mlir made (a fresh buffer: its descriptor at r), written into the builder, then freed
func.func @ob_made(%r: !llvm.ptr) {
  %pa = llvm.getelementptr %r[0, 0] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>
  %buf = llvm.load %pa : !llvm.ptr -> !llvm.ptr
  %pd = llvm.getelementptr %r[0, 1] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>
  %data = llvm.load %pd : !llvm.ptr -> !llvm.ptr
  %po = llvm.getelementptr %r[0, 2] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>
  %off = llvm.load %po : !llvm.ptr -> i64
  %pn = llvm.getelementptr %r[0, 3, 0] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>
  %len = llvm.load %pn : !llvm.ptr -> i64
  %at = llvm.getelementptr %data[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  func.call @ob_bytes(%at, %len) : (!llvm.ptr, i64) -> ()
  llvm.call @free(%buf) : (!llvm.ptr) -> ()
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
      func.call @fail_refused() : () -> ()
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
    %lit60 = llvm.mlir.addressof @lit53 : !llvm.ptr
    %litn60 = arith.constant 13 : i64
    func.call @fail_file(%lit60, %litn60, %file) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  }
  return
}

// The request {"path": [segments], "value": json}: its index, the segments' coordinates (inside their quotes) and the
// value's, all in the body; false, with the reply made, when it is not one.  request.mlir's rq_body reads it through the
// index (KeyToChild, the tags, the kids); what it lacks first is the reply (e: 1 not JSON, 2 not an object, 3 "path" not
// an array, 4 "path" empty, 5 a segment not a string, 6 no "value").
llvm.func @_mlir_ciface_rq_body(!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64)
func.func @request(%bp: !llvm.ptr, %bn: i64, %want: i1) -> (!llvm.ptr, !llvm.ptr, i64, i64, i1) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %one = arith.constant 1 : i32
  %i0 = arith.constant 0 : i32
  %i1 = arith.constant 1 : i32
  %i2 = arith.constant 2 : i32
  %i3 = arith.constant 3 : i32
  %null = llvm.mlir.zero : !llvm.ptr
  %f = func.call @cx_scan(%bp, %bn) : (!llvm.ptr, i64) -> !llvm.ptr
  %isNull = llvm.icmp "eq" %f, %null : !llvm.ptr
  %r:4 = scf.if %isNull -> (i64, !llvm.ptr, i64, i64) {
    scf.yield %c1, %null, %c0, %c0 : i64, !llvm.ptr, i64, i64
  } else {
    %res = llvm.alloca %one x !llvm.struct<(i64, struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>, i64)> : (i32) -> !llvm.ptr
    %d0 = func.call @cx_d(%f, %i0) : (!llvm.ptr, i32) -> !llvm.ptr
    %d1 = func.call @cx_d(%f, %i1) : (!llvm.ptr, i32) -> !llvm.ptr
    %d2 = func.call @cx_d(%f, %i2) : (!llvm.ptr, i32) -> !llvm.ptr
    %d3 = func.call @cx_d(%f, %i3) : (!llvm.ptr, i32) -> !llvm.ptr
    %td = func.call @cx_text(%f) : (!llvm.ptr) -> !llvm.ptr
    %w = arith.extui %want : i1 to i64
    llvm.call @_mlir_ciface_rq_body(%res, %d0, %d1, %d2, %d3, %td, %w) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64) -> ()
    %pe = llvm.getelementptr %res[0, 0] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(i64, struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>, i64)>
    %e = llvm.load %pe : !llvm.ptr -> i64
    %ps = llvm.getelementptr %res[0, 1, 0] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(i64, struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>, i64)>
    %segs = llvm.load %ps : !llvm.ptr -> !llvm.ptr
    %pn = llvm.getelementptr %res[0, 1, 3, 0] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(i64, struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>, i64)>
    %ns = llvm.load %pn : !llvm.ptr -> i64
    %pv = llvm.getelementptr %res[0, 2] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(i64, struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>, i64)>
    %vt = llvm.load %pv : !llvm.ptr -> i64
    scf.yield %e, %segs, %ns, %vt : i64, !llvm.ptr, i64, i64
  }
  %e6 = arith.addi %r#0, %c0 : i64
  %ok = arith.cmpi eq, %e6, %c0 : i64
  scf.if %ok {
  } else {
    %c400 = arith.constant 400 : i64
    %lit61 = llvm.mlir.addressof @lit56 : !llvm.ptr
    %lit62 = llvm.mlir.addressof @lit57 : !llvm.ptr
    %lit63 = llvm.mlir.addressof @lit58 : !llvm.ptr
    %lit64 = llvm.mlir.addressof @lit59 : !llvm.ptr
    %lit65 = llvm.mlir.addressof @lit60 : !llvm.ptr
    %which = arith.index_cast %e6 : i64 to index
    %why:2 = scf.index_switch %which -> !llvm.ptr, i64
    case 1 {
      %litn61 = arith.constant 17 : i64
      scf.yield %lit61, %litn61 : !llvm.ptr, i64
    }
    case 2 {
      %litn62 = arith.constant 30 : i64
      scf.yield %lit62, %litn62 : !llvm.ptr, i64
    }
    case 4 {
      %litn63 = arith.constant 26 : i64
      scf.yield %lit63, %litn63 : !llvm.ptr, i64
    }
    case 6 {
      %litn64 = arith.constant 30 : i64
      scf.yield %lit64, %litn64 : !llvm.ptr, i64
    }
    default {
      %litn65 = arith.constant 45 : i64
      scf.yield %lit65, %litn65 : !llvm.ptr, i64
    }
    func.call @fail_text(%c400, %why#0, %why#1, %why#0, %c0, %why#0, %c0, %why#0, %c0) : (i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64) -> ()
  }
  return %f, %r#1, %r#2, %r#3, %ok : !llvm.ptr, !llvm.ptr, i64, i64, i1
}

// The overlay's edits are text.mlir's: one combine of the overlay's slices, the body's and literals, made into a fresh
// buffer, which is the next overlay (its allocation is its data: offset 0).
llvm.func @_mlir_ciface_overlay_put(!llvm.ptr, !llvm.ptr, i64, i64, !llvm.ptr, i64, i64)
llvm.func @_mlir_ciface_overlay_insert(!llvm.ptr, !llvm.ptr, i64, i64, !llvm.ptr, !llvm.ptr, i64, i64, i64)

func.func @ov_made(%r: !llvm.ptr) -> (!llvm.ptr, i64) {
  %pa = llvm.getelementptr %r[0, 0] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>
  %buf = llvm.load %pa : !llvm.ptr -> !llvm.ptr
  %pn = llvm.getelementptr %r[0, 3, 0] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>
  %len = llvm.load %pn : !llvm.ptr -> i64
  return %buf, %len : !llvm.ptr, i64
}

// the overlay with [from, to) replaced by the body's [vs, vs + vl)
func.func @ov_put(%ov: !llvm.ptr, %ovn: i64, %from: i64, %to: i64, %bp: !llvm.ptr, %bn: i64, %vs: i64, %vl: i64) -> (!llvm.ptr, i64) {
  %one = arith.constant 1 : i32
  %dov = llvm.alloca %one x !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)> : (i32) -> !llvm.ptr
  func.call @view(%dov, %ov, %ovn) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %db = llvm.alloca %one x !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)> : (i32) -> !llvm.ptr
  func.call @view(%db, %bp, %bn) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %res = llvm.alloca %one x !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)> : (i32) -> !llvm.ptr
  llvm.call @_mlir_ciface_overlay_put(%res, %dov, %from, %to, %db, %vs, %vl) : (!llvm.ptr, !llvm.ptr, i64, i64, !llvm.ptr, i64, i64) -> ()
  %r:2 = func.call @ov_made(%res) : (!llvm.ptr) -> (!llvm.ptr, i64)
  return %r#0, %r#1 : !llvm.ptr, i64
}

// the overlay with the path's segments from level on inserted at `at`, around the body's [vs, vs + vl)
func.func @ov_insert(%ov: !llvm.ptr, %ovn: i64, %at: i64, %comma: i64, %bp: !llvm.ptr, %bn: i64, %segs: !llvm.ptr, %ns: i64,
                     %level: i64, %vs: i64, %vl: i64) -> (!llvm.ptr, i64) {
  %one = arith.constant 1 : i32
  %dov = llvm.alloca %one x !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)> : (i32) -> !llvm.ptr
  func.call @view(%dov, %ov, %ovn) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %db = llvm.alloca %one x !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)> : (i32) -> !llvm.ptr
  func.call @view(%db, %bp, %bn) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %ds = llvm.alloca %one x !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)> : (i32) -> !llvm.ptr
  func.call @view(%ds, %segs, %ns) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %res = llvm.alloca %one x !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)> : (i32) -> !llvm.ptr
  llvm.call @_mlir_ciface_overlay_insert(%res, %dov, %at, %comma, %db, %ds, %level, %vs, %vl) : (!llvm.ptr, !llvm.ptr, i64, i64, !llvm.ptr, !llvm.ptr, i64, i64, i64) -> ()
  %r:2 = func.call @ov_made(%res) : (!llvm.ptr) -> (!llvm.ptr, i64)
  return %r#0, %r#1 : !llvm.ptr, i64
}

// The overlay with the member at the path set to the value (all coordinates in the body bp): the old value's span
// replaced, or the missing members inserted after the last member of the deepest object that exists.
// request.mlir's walks over the overlay's index, through their C interfaces: the index's columns (cx_d 0..2), its kids
// (cx_d 3) and its text (cx_text) are the descriptors rq_body reads; the path's segments are coordinates in the body
// (bp, bn).  set: (kind, level, a, b) of ov_set_walk; else (from, to, _, _) of ov_cut_walk.
llvm.func @_mlir_ciface_ov_set_walk(!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr)
llvm.func @_mlir_ciface_ov_cut_walk(!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr)

func.func @ov_walk(%set: i1, %d: !llvm.ptr, %bp: !llvm.ptr, %bn: i64, %segs: !llvm.ptr, %ns: i64) -> (i64, i64, i64, i64) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %i0 = arith.constant 0 : i32
  %i1 = arith.constant 1 : i32
  %i2 = arith.constant 2 : i32
  %i3 = arith.constant 3 : i32
  %one = arith.constant 1 : i32
  %d0 = func.call @cx_d(%d, %i0) : (!llvm.ptr, i32) -> !llvm.ptr
  %d1 = func.call @cx_d(%d, %i1) : (!llvm.ptr, i32) -> !llvm.ptr
  %d2 = func.call @cx_d(%d, %i2) : (!llvm.ptr, i32) -> !llvm.ptr
  %d3 = func.call @cx_d(%d, %i3) : (!llvm.ptr, i32) -> !llvm.ptr
  %td = func.call @cx_text(%d) : (!llvm.ptr) -> !llvm.ptr
  %dbody = llvm.alloca %one x !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)> : (i32) -> !llvm.ptr
  func.call @view(%dbody, %bp, %bn) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %dsegs = llvm.alloca %one x !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)> : (i32) -> !llvm.ptr
  func.call @view(%dsegs, %segs, %ns) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %out = llvm.alloca %one x !llvm.array<4 x i64> : (i32) -> !llvm.ptr
  %dout = llvm.alloca %one x !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)> : (i32) -> !llvm.ptr
  func.call @view(%dout, %out, %c4) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  scf.if %set {
    llvm.call @_mlir_ciface_ov_set_walk(%d0, %d1, %d2, %d3, %td, %dbody, %dsegs, %dout)
        : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> ()
  } else {
    llvm.call @_mlir_ciface_ov_cut_walk(%d0, %d1, %d2, %d3, %td, %dbody, %dsegs, %dout)
        : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> ()
  }
  %k0 = func.call @ld64(%out, %c0) : (!llvm.ptr, i64) -> i64
  %k1 = func.call @ld64(%out, %c1) : (!llvm.ptr, i64) -> i64
  %k2 = func.call @ld64(%out, %c2) : (!llvm.ptr, i64) -> i64
  %k3 = func.call @ld64(%out, %c3) : (!llvm.ptr, i64) -> i64
  return %k0, %k1, %k2, %k3 : i64, i64, i64, i64
}

func.func @set_at(%ov: !llvm.ptr, %ovn: i64, %bp: !llvm.ptr, %bn: i64, %segs: !llvm.ptr, %ns: i64, %value: i64) -> (!llvm.ptr, i64, i1) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
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
    // request.mlir's ov_set_walk: kind 1 insert at a (the comma b), 2 replace [a, b), 3 not an object (level names it)
    %k:4 = func.call @ov_walk(%true, %d, %bp, %bn, %segs, %ns)
        : (i1, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> (i64, i64, i64, i64)
    %isNotObj = arith.cmpi eq, %k#0, %c3 : i64
    %r:3 = scf.if %isNotObj -> (!llvm.ptr, i64, i1) {
      %c400 = arith.constant 400 : i64
      %lit66 = llvm.mlir.addressof @lit61 : !llvm.ptr
      %litn66 = arith.constant 9 : i64
      %seg = func.call @ld64(%segs, %k#1) : (!llvm.ptr, i64) -> i64
      %sp, %sn = func.call @piece_at(%bp, %seg) : (!llvm.ptr, i64) -> (!llvm.ptr, i64)
      %lit67 = llvm.mlir.addressof @lit62 : !llvm.ptr
      %litn67 = arith.constant 17 : i64
      func.call @fail_text(%c400, %lit66, %litn66, %sp, %sn, %lit67, %litn67, %lit67, %c0) : (i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64) -> ()
      scf.yield %null, %c0, %false : !llvm.ptr, i64, i1
    } else {
      // the next overlay: text.mlir's overlay_insert (the members the path lacks, after the last member of the deepest
      // object it has) or overlay_put (the old value's span replaced)
      %isInsert = arith.cmpi eq, %k#0, %c1 : i64
      %vs = func.call @tw_s(%value) : (i64) -> i64
      %vl = func.call @tw_n(%value) : (i64) -> i64
      %made:2 = scf.if %isInsert -> (!llvm.ptr, i64) {
        %m:2 = func.call @ov_insert(%ov, %ovn, %k#2, %k#3, %bp, %bn, %segs, %ns, %k#1, %vs, %vl)
            : (!llvm.ptr, i64, i64, i64, !llvm.ptr, i64, !llvm.ptr, i64, i64, i64, i64) -> (!llvm.ptr, i64)
        scf.yield %m#0, %m#1 : !llvm.ptr, i64
      } else {
        %m:2 = func.call @ov_put(%ov, %ovn, %k#2, %k#3, %bp, %bn, %vs, %vl)
            : (!llvm.ptr, i64, i64, i64, !llvm.ptr, i64, i64, i64) -> (!llvm.ptr, i64)
        scf.yield %m#0, %m#1 : !llvm.ptr, i64
      }
      scf.yield %made#0, %made#1, %true : !llvm.ptr, i64, i1
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
// request.mlir's ov_cut_walk: [from, to) is what the edit cuts (ov_put of nothing there).
func.func @remove_at(%ov: !llvm.ptr, %ovn: i64, %bp: !llvm.ptr, %bn: i64, %segs: !llvm.ptr, %ns: i64) -> (!llvm.ptr, i64, i1) {
  %c0 = arith.constant 0 : i64
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
    %k:4 = func.call @ov_walk(%false, %d, %bp, %bn, %segs, %ns)
        : (i1, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> (i64, i64, i64, i64)
    %made:2 = func.call @ov_put(%ov, %ovn, %k#0, %k#1, %ov, %ovn, %c0, %c0)
        : (!llvm.ptr, i64, i64, i64, !llvm.ptr, i64, i64, i64) -> (!llvm.ptr, i64)
    scf.yield %made#0, %made#1, %true : !llvm.ptr, i64, i1
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
    %s:3 = func.call @set_at(%ov, %ovn, %bp, %bn, %r#1, %r#2, %r#3) : (!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, i64) -> (!llvm.ptr, i64, i1)
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
    %s:3 = func.call @remove_at(%ov, %ovn, %bp, %bn, %r#1, %r#2) : (!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64) -> (!llvm.ptr, i64, i1)
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
