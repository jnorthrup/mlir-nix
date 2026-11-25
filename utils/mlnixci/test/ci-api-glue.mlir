// the old api.mlir's (renamed old_*) and the new one's functions, side by side; each result and the builder after it
// stored at out
func.func private @ob_len() -> i64
func.func private @ob_take() -> !llvm.ptr
func.func private @ob_start(i64)
func.func private @api_status() -> i64
func.func private @old_api_status() -> i64
func.func private @old_set_at(!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, i64) -> (!llvm.ptr, i64, i1)
func.func private @set_at(!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, i64) -> (!llvm.ptr, i64, i1)
func.func private @old_remove_at(!llvm.ptr, i64, !llvm.ptr, !llvm.ptr, i64) -> (!llvm.ptr, i64, i1)
func.func private @remove_at(!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64) -> (!llvm.ptr, i64, i1)
func.func private @old_request(!llvm.ptr, i64, i1) -> (!llvm.ptr, !llvm.ptr, i64, i64, i1)
func.func private @request(!llvm.ptr, i64, i1) -> (!llvm.ptr, !llvm.ptr, i64, i64, i1)
func.func private @old_fail_with(i64, !llvm.ptr, i64)
func.func private @fail_with(i64, !llvm.ptr, i64)
func.func private @old_route(!llvm.ptr, i64, i64, i64)
func.func private @route(!llvm.ptr, i64, i64, i64, i64)
func.func private @cx_free(!llvm.ptr)
func.func private @st64(!llvm.ptr, i64, i64)

// the builder's reply (status, length, buffer) at out[k..k+2]
func.func @g_take(%out: !llvm.ptr, %k: i64, %status: i64) {
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %n = func.call @ob_len() : () -> i64
  %p = func.call @ob_take() : () -> !llvm.ptr
  %pi = llvm.ptrtoint %p : !llvm.ptr to i64
  %k1 = arith.addi %k, %c1 : i64
  %k2 = arith.addi %k, %c2 : i64
  func.call @st64(%out, %k, %status) : (!llvm.ptr, i64, i64) -> ()
  func.call @st64(%out, %k1, %n) : (!llvm.ptr, i64, i64) -> ()
  func.call @st64(%out, %k2, %pi) : (!llvm.ptr, i64, i64) -> ()
  return
}

func.func @g_put3(%out: !llvm.ptr, %k: i64, %p: !llvm.ptr, %n: i64, %ok: i1) {
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %pi = llvm.ptrtoint %p : !llvm.ptr to i64
  %oki = arith.extui %ok : i1 to i64
  %k1 = arith.addi %k, %c1 : i64
  %k2 = arith.addi %k, %c2 : i64
  func.call @st64(%out, %k, %pi) : (!llvm.ptr, i64, i64) -> ()
  func.call @st64(%out, %k1, %n) : (!llvm.ptr, i64, i64) -> ()
  func.call @st64(%out, %k2, %oki) : (!llvm.ptr, i64, i64) -> ()
  return
}

// out: 0..2 old (next, length, ok), 3..5 its builder; 6..8 new, 9..11 its builder
func.func @g_set(%ov: !llvm.ptr, %ovn: i64, %bp: !llvm.ptr, %bn: i64, %segs: !llvm.ptr, %ns: i64, %value: i64, %out: !llvm.ptr) {
  %c0 = arith.constant 0 : i64
  %c3 = arith.constant 3 : i64
  %c6 = arith.constant 6 : i64
  %c9 = arith.constant 9 : i64
  func.call @ob_start(%c0) : (i64) -> ()
  %o:3 = func.call @old_set_at(%ov, %ovn, %bp, %bn, %segs, %ns, %value) : (!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, i64) -> (!llvm.ptr, i64, i1)
  func.call @g_put3(%out, %c0, %o#0, %o#1, %o#2) : (!llvm.ptr, i64, !llvm.ptr, i64, i1) -> ()
  %os = func.call @old_api_status() : () -> i64
  func.call @g_take(%out, %c3, %os) : (!llvm.ptr, i64, i64) -> ()
  func.call @ob_start(%c0) : (i64) -> ()
  %r:3 = func.call @set_at(%ov, %ovn, %bp, %bn, %segs, %ns, %value) : (!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, i64) -> (!llvm.ptr, i64, i1)
  func.call @g_put3(%out, %c6, %r#0, %r#1, %r#2) : (!llvm.ptr, i64, !llvm.ptr, i64, i1) -> ()
  %rs = func.call @api_status() : () -> i64
  func.call @g_take(%out, %c9, %rs) : (!llvm.ptr, i64, i64) -> ()
  return
}

func.func @g_remove(%ov: !llvm.ptr, %ovn: i64, %bp: !llvm.ptr, %bn: i64, %segs: !llvm.ptr, %ns: i64, %out: !llvm.ptr) {
  %c0 = arith.constant 0 : i64
  %c3 = arith.constant 3 : i64
  %c6 = arith.constant 6 : i64
  %c9 = arith.constant 9 : i64
  func.call @ob_start(%c0) : (i64) -> ()
  %o:3 = func.call @old_remove_at(%ov, %ovn, %bp, %segs, %ns) : (!llvm.ptr, i64, !llvm.ptr, !llvm.ptr, i64) -> (!llvm.ptr, i64, i1)
  func.call @g_put3(%out, %c0, %o#0, %o#1, %o#2) : (!llvm.ptr, i64, !llvm.ptr, i64, i1) -> ()
  %os = func.call @old_api_status() : () -> i64
  func.call @g_take(%out, %c3, %os) : (!llvm.ptr, i64, i64) -> ()
  func.call @ob_start(%c0) : (i64) -> ()
  %r:3 = func.call @remove_at(%ov, %ovn, %bp, %bn, %segs, %ns) : (!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64) -> (!llvm.ptr, i64, i1)
  func.call @g_put3(%out, %c6, %r#0, %r#1, %r#2) : (!llvm.ptr, i64, !llvm.ptr, i64, i1) -> ()
  %rs = func.call @api_status() : () -> i64
  func.call @g_take(%out, %c9, %rs) : (!llvm.ptr, i64, i64) -> ()
  return
}

// out: old 0 index, 1 segs, 2 ns, 3 value, 4 ok, 5..7 builder; new 8..15 the same.  The old index and segs are freed
// here; the new ones are left at out for the caller (it hands them to g_set / g_remove, then frees them with g_free)
func.func @g_request(%bp: !llvm.ptr, %bn: i64, %want: i1, %out: !llvm.ptr) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %c5 = arith.constant 5 : i64
  %c8 = arith.constant 8 : i64
  %c9 = arith.constant 9 : i64
  %c10 = arith.constant 10 : i64
  %c11 = arith.constant 11 : i64
  %c12 = arith.constant 12 : i64
  %c13 = arith.constant 13 : i64
  func.call @ob_start(%c0) : (i64) -> ()
  %o:5 = func.call @old_request(%bp, %bn, %want) : (!llvm.ptr, i64, i1) -> (!llvm.ptr, !llvm.ptr, i64, i64, i1)
  %of = llvm.ptrtoint %o#0 : !llvm.ptr to i64
  %ook = arith.extui %o#4 : i1 to i64
  func.call @st64(%out, %c0, %of) : (!llvm.ptr, i64, i64) -> ()
  func.call @st64(%out, %c2, %o#2) : (!llvm.ptr, i64, i64) -> ()
  func.call @st64(%out, %c3, %o#3) : (!llvm.ptr, i64, i64) -> ()
  func.call @st64(%out, %c4, %ook) : (!llvm.ptr, i64, i64) -> ()
  %os = func.call @old_api_status() : () -> i64
  func.call @g_take(%out, %c5, %os) : (!llvm.ptr, i64, i64) -> ()
  // the old segments' coordinates, kept for the comparison: their first, at out[1]
  %onull = llvm.mlir.zero : !llvm.ptr
  %oisnull = llvm.icmp "eq" %o#1, %onull : !llvm.ptr
  %seg0 = scf.if %oisnull -> (i64) {
    %z = arith.constant 0 : i64
    scf.yield %z : i64
  } else {
    %l = llvm.load %o#1 : !llvm.ptr -> i64
    scf.yield %l : i64
  }
  func.call @st64(%out, %c1, %seg0) : (!llvm.ptr, i64, i64) -> ()
  func.call @cx_free(%o#0) : (!llvm.ptr) -> ()
  llvm.call @free(%o#1) : (!llvm.ptr) -> ()
  func.call @ob_start(%c0) : (i64) -> ()
  %r:5 = func.call @request(%bp, %bn, %want) : (!llvm.ptr, i64, i1) -> (!llvm.ptr, !llvm.ptr, i64, i64, i1)
  %rf = llvm.ptrtoint %r#0 : !llvm.ptr to i64
  %rsg = llvm.ptrtoint %r#1 : !llvm.ptr to i64
  %rok = arith.extui %r#4 : i1 to i64
  func.call @st64(%out, %c8, %rf) : (!llvm.ptr, i64, i64) -> ()
  func.call @st64(%out, %c9, %rsg) : (!llvm.ptr, i64, i64) -> ()
  func.call @st64(%out, %c10, %r#2) : (!llvm.ptr, i64, i64) -> ()
  func.call @st64(%out, %c11, %r#3) : (!llvm.ptr, i64, i64) -> ()
  func.call @st64(%out, %c12, %rok) : (!llvm.ptr, i64, i64) -> ()
  %rs = func.call @api_status() : () -> i64
  func.call @g_take(%out, %c13, %rs) : (!llvm.ptr, i64, i64) -> ()
  return
}
llvm.func @free(!llvm.ptr)

func.func @g_free(%f: !llvm.ptr, %segs: !llvm.ptr) {
  func.call @cx_free(%f) : (!llvm.ptr) -> ()
  llvm.call @free(%segs) : (!llvm.ptr) -> ()
  return
}

// fail_with and the 404: out 0..2 old's builder, 3..5 new's
func.func @g_fail(%status: i64, %p: !llvm.ptr, %n: i64, %out: !llvm.ptr) {
  %c0 = arith.constant 0 : i64
  %c3 = arith.constant 3 : i64
  func.call @old_fail_with(%status, %p, %n) : (i64, !llvm.ptr, i64) -> ()
  %os = func.call @old_api_status() : () -> i64
  func.call @g_take(%out, %c0, %os) : (!llvm.ptr, i64, i64) -> ()
  func.call @fail_with(%status, %p, %n) : (i64, !llvm.ptr, i64) -> ()
  %rs = func.call @api_status() : () -> i64
  func.call @g_take(%out, %c3, %rs) : (!llvm.ptr, i64, i64) -> ()
  return
}

func.func @g_404(%in: !llvm.ptr, %m: i64, %p: i64, %out: !llvm.ptr) {
  %c0 = arith.constant 0 : i64
  %c3 = arith.constant 3 : i64
  func.call @old_route(%in, %m, %p, %c0) : (!llvm.ptr, i64, i64, i64) -> ()
  %os = func.call @old_api_status() : () -> i64
  func.call @g_take(%out, %c0, %os) : (!llvm.ptr, i64, i64) -> ()
  func.call @route(%in, %m, %p, %c0, %c0) : (!llvm.ptr, i64, i64, i64, i64) -> ()
  %rs = func.call @api_status() : () -> i64
  func.call @g_take(%out, %c3, %rs) : (!llvm.ptr, i64, i64) -> ()
  return
}

func.func private @old_api_init(!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr)
func.func private @api_init(!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr)
func.func private @old_query(!llvm.ptr, i64)
func.func private @query(!llvm.ptr, i64)
func.func private @corpus_load(!llvm.ptr, i64, f64) -> !llvm.ptr

// a corpus from the JSON at a and b (two copies, malloc'd: the corpus keeps them), given to both
func.func @g_init(%a: !llvm.ptr, %b: !llvm.ptr, %n: i64) -> i64 {
  %z = arith.constant 0.0 : f64
  %null = llvm.mlir.zero : !llvm.ptr
  %base = func.call @corpus_load(%a, %n, %z) : (!llvm.ptr, i64, f64) -> !llvm.ptr
  %cur = func.call @corpus_load(%b, %n, %z) : (!llvm.ptr, i64, f64) -> !llvm.ptr
  func.call @old_api_init(%null, %null, %base, %cur, %null) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> ()
  func.call @api_init(%null, %null, %base, %cur, %null) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> ()
  %ok = llvm.icmp "ne" %cur, %null : !llvm.ptr
  %r = arith.extui %ok : i1 to i64
  return %r : i64
}

// the query: out 0..2 old's builder, 3..5 new's
func.func @g_query(%in: !llvm.ptr, %body: i64, %out: !llvm.ptr) {
  %c0 = arith.constant 0 : i64
  %c3 = arith.constant 3 : i64
  func.call @old_query(%in, %body) : (!llvm.ptr, i64) -> ()
  %os = func.call @old_api_status() : () -> i64
  func.call @g_take(%out, %c0, %os) : (!llvm.ptr, i64, i64) -> ()
  func.call @query(%in, %body) : (!llvm.ptr, i64) -> ()
  %rs = func.call @api_status() : () -> i64
  func.call @g_take(%out, %c3, %rs) : (!llvm.ptr, i64, i64) -> ()
  return
}
