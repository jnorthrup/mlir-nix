// builtins.toXML's walk, hollowed out of lib/Eval/Formats.cpp (its XMLWriter, element stack, toXML/showAttrsXML/posToXML
// recursion, attribute rows and formals' order are gone): the FILL of a fill-drain.  The walk visits the value as Nix
// does -- the value forced first, a derivation's drvPath then outPath forced before its tag, a set's attributes in name
// order (trikeshed.sorted over the rows, unsigned bytes: lexicographicOrder's order), a list's elements in order, a
// function's formals sorted by their bytes -- and appends one row a tag line.  XmlOps.mlir's nixev_ts_xml_text is the
// DRAIN: every row's line composed and drained once into the text.  Lowered by lib/CMakeLists.txt's mlnix_lower_trikeshed
// into NixEval.
//
// The element stack is the recursion: each close row names the element its open row named, at the open's depth.
//
// A row is 20 i64 cells in the bridge's rows (nixev_xw_row appends one and returns it; it holds until the next):
//   [0] kind (0 open '<n ...>', 1 close '</n>', 2 empty '<n ... />')   [1] depth (two spaces each)
//   [2] the name's bytes (a word of @xw_blob)   [3] its length
//   [4 + 2s] slot s's bits, [5 + 2s] its length: -1 absent, -2 an integer (the bits), else a window (bits = address).
//   The slots are the attributes in name order (a tag's attributes are a subset, and strcmp sorts a subset as it sorts
//   the whole): 0 column, 1 drvPath, 2 ellipsis, 3 line, 4 name, 5 outPath, 6 path, 7 value.
// Every window is on bytes that outlive the walk: a string's or path's arena bytes, the symbol table's names, the
// formals' and argument's StringAttrs, the file table's paths, this module's words, the bridge's Bump (a float's text).
//
// The callbacks (Formats.cpp) keep the evaluator: nixev_xw_force (forceValue at a position), nixev_xw_ctx
// (copyContext), nixev_xw_isdrv (isDerivation), nixev_xw_drvattr (the drvPath/outPath attribute, forced at its position
// when strict; null when absent), nixev_xw_seen (the derivations met: TextSet insert, 1 when new), nixev_xw_sym (a
// symbol's bytes), nixev_xw_apos (positionOf), nixev_xw_pos (decodePos: {file ptr, len, line, column}, 0 when none),
// nixev_xw_float (printFloat's text), nixev_xw_lambda (a lambda's {pos, has formals, arg name ptr, len or -1, ellipsis,
// formal count}), nixev_xw_names (the bridge's n formal windows, 16 bytes each), nixev_xw_formal (formal j's {ptr, len}
// into its window), nixev_xw_cells (n i64 of bridge-owned scratch: a set's sorted order lives
// through its children's walk, and an exception unwinding through here leaks nothing).
//
// RECORDS.  Every record the walk reads is a word view made ONCE where it is read (a Value's 2 words, a Bindings' header
// and rows, a list's cells, a lambda's record, a formal window, a callback's out-slot): trikeshed.at over a series<i64>
// of the record's words, the fields as arith on those words (the type is the low byte of word 0, aux the high half, a
// Bindings' size the low half of its word 0, an Attr row's name the low half of its word, its value the next word).  A
// row the walk writes is a word view of the bridge's 20 cells, written with memref.store.  The one pointer computed in
// llvm is an Attr's address for the positionOf callback (pointer arithmetic, no load).
//
// Value: type u8 @0 (Int 5, Float 6, Bool 7, Null 8, String 9, Path 10, Attrs 11, List 12, Lambda 13), aux u32 @4
// (a string's or path's length, a list's size), the word @8 (int, bool byte, string/path bytes, Bindings*, cells).
// Bindings: size u32 @0, the Attr rows @16; Attr (16 bytes): Symbol u32 @0, PosIdx u32 @4, Value* @8.
!text = !trikeshed.series<i8>
!s32 = !trikeshed.series<i32>
!s64 = !trikeshed.series<i64>
!m8 = memref<?xi8, strided<[1], offset: ?>>
!m64 = memref<?xi64, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

// the words: 0 expr, 1 attr, 2 attrs, 3 derivation, 4 repeated, 5 list, 6 function, 7 attrspat, 8 varpat, 9 int,
// 10 bool, 11 string, 12 path, 13 null, 14 unevaluated, 15 float, 16 true, 17 false, 18 \"1\"
memref.global "private" constant @xw_blob : memref<104xi8> = dense<"0x6578707261747472617474727364657269766174696f6e72657065617465646c69737466756e6374696f6e6174747273706174766172706174696e74626f6f6c737472696e67706174686e756c6c756e6576616c7561746564666c6f61747472756566616c736531">
memref.global "private" constant @xw_off : memref<19xi32> = dense<[0, 4, 8, 13, 23, 31, 35, 43, 51, 57, 60, 64, 70, 74, 78, 89, 94, 98, 103]>
memref.global "private" constant @xw_len : memref<19xi32> = dense<[4, 4, 5, 10, 8, 4, 8, 8, 6, 3, 4, 6, 4, 4, 11, 5, 4, 5, 1]>

func.func private @nixev_xw_row(!llvm.ptr) -> !llvm.ptr
func.func private @nixev_xw_cells(!llvm.ptr, i64) -> !llvm.ptr
func.func private @nixev_xw_force(!llvm.ptr, !llvm.ptr, !llvm.ptr)
func.func private @nixev_xw_ctx(!llvm.ptr, !llvm.ptr)
func.func private @nixev_xw_isdrv(!llvm.ptr, !llvm.ptr) -> i32
func.func private @nixev_xw_drvattr(!llvm.ptr, !llvm.ptr, i64, i32) -> !llvm.ptr
func.func private @nixev_xw_seen(!llvm.ptr, !llvm.ptr, i64) -> i32
func.func private @nixev_xw_sym(!llvm.ptr, i32, !llvm.ptr) -> !llvm.ptr
func.func private @nixev_xw_apos(!llvm.ptr, !llvm.ptr) -> !llvm.ptr
func.func private @nixev_xw_pos(!llvm.ptr, !llvm.ptr, !llvm.ptr) -> i32
func.func private @nixev_xw_float(!llvm.ptr, !llvm.ptr, !llvm.ptr) -> !llvm.ptr
func.func private @nixev_xw_lambda(!llvm.ptr, !llvm.ptr, !llvm.ptr)
func.func private @nixev_xw_names(!llvm.ptr, i64) -> !llvm.ptr
func.func private @nixev_xw_formal(!llvm.ptr, i64, !llvm.ptr)

// the descriptor of n cells at p (a struct, not a memref: returning it allocates nothing and clones nothing); the
// caller casts it to a memref and a series at its own use site, so each record's view is made once, where it is read
func.func private @xw_desc(%p: !llvm.ptr, %n: i64) -> !d {
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

// word w: its address in @xw_blob and its length
func.func private @xw_word(%w: index) -> (i64, i64) {
  %og = memref.get_global @xw_off : memref<19xi32>
  %offs = trikeshed.text %og : memref<19xi32> -> !s32
  %lg = memref.get_global @xw_len : memref<19xi32>
  %lens = trikeshed.text %lg : memref<19xi32> -> !s32
  %o = trikeshed.at %offs[%w] : !s32, index -> i32
  %l = trikeshed.at %lens[%w] : !s32, index -> i32
  %bg = memref.get_global @xw_blob : memref<104xi8>
  %base = memref.extract_aligned_pointer_as_index %bg : memref<104xi8> -> index
  %oi = arith.index_castui %o : i32 to index
  %at = arith.addi %base, %oi : index
  %at64 = arith.index_cast %at : index to i64
  %l64 = arith.extui %l : i32 to i64
  return %at64, %l64 : i64, i64
}

// a new row: kind, depth, word w as its name, every slot absent (the row's 20 words are written through a view)
func.func private @xw_row(%x: !llvm.ptr, %kind: i64, %depth: i64, %w: index) -> !llvm.ptr {
  %c20 = arith.constant 20 : i64
  %absent = arith.constant -1 : i64
  %zi = arith.constant 0 : index
  %one = arith.constant 1 : index
  %two = arith.constant 2 : index
  %three = arith.constant 3 : index
  %five = arith.constant 5 : index
  %eight = arith.constant 8 : index
  %r = func.call @nixev_xw_row(%x) : (!llvm.ptr) -> !llvm.ptr
  %wp, %wl = func.call @xw_word(%w) : (index) -> (i64, i64)
  %rd = func.call @xw_desc(%r, %c20) : (!llvm.ptr, i64) -> !d
  %rm = builtin.unrealized_conversion_cast %rd : !d to !m64
  memref.store %kind, %rm[%zi] : !m64
  memref.store %depth, %rm[%one] : !m64
  memref.store %wp, %rm[%two] : !m64
  memref.store %wl, %rm[%three] : !m64
  scf.for %s = %zi to %eight step %one {
    %sk = arith.muli %s, %two : index
    %k = arith.addi %sk, %five : index
    memref.store %absent, %rm[%k] : !m64
  }
  return %r : !llvm.ptr
}

// slot s of row r: the bits and the length (-1 absent, -2 an integer), words 4+2s and 5+2s of the row
func.func private @xw_slot(%r: !llvm.ptr, %s: i64, %bits: i64, %len: i64) {
  %c20 = arith.constant 20 : i64
  %zi = arith.constant 0 : index
  %one = arith.constant 1 : index
  %two = arith.constant 2 : index
  %four = arith.constant 4 : index
  %rd = func.call @xw_desc(%r, %c20) : (!llvm.ptr, i64) -> !d
  %rm = builtin.unrealized_conversion_cast %rd : !d to !m64
  %si = arith.index_cast %s : i64 to index
  %sk = arith.muli %si, %two : index
  %kb = arith.addi %sk, %four : index
  %kl = arith.addi %kb, %one : index
  memref.store %bits, %rm[%kb] : !m64
  memref.store %len, %rm[%kl] : !m64
  return
}

// posToXML: path (an absolute file only), line and column, when the position holds any
func.func private @xw_pos(%x: !llvm.ptr, %r: !llvm.ptr, %pos: !llvm.ptr) {
  %c0 = arith.constant 0 : i64
  %c4 = arith.constant 4 : i64
  %sCol = arith.constant 0 : i64
  %sLine = arith.constant 3 : i64
  %sPath = arith.constant 6 : i64
  %int = arith.constant -2 : i64
  %z32 = arith.constant 0 : i32
  %slash = arith.constant 47 : i8
  %zi = arith.constant 0 : index
  %one = arith.constant 1 : index
  %two = arith.constant 2 : index
  %three = arith.constant 3 : index
  %out = llvm.alloca %c4 x i64 : (i64) -> !llvm.ptr
  %f = func.call @nixev_xw_pos(%x, %pos, %out) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> i32
  %found = arith.cmpi ne, %f, %z32 : i32
  scf.if %found {
    // the out-slot's four words: the file's pointer, length, line, column
    %od = func.call @xw_desc(%out, %c4) : (!llvm.ptr, i64) -> !d
    %om = builtin.unrealized_conversion_cast %od : !d to !m64
    %os = builtin.unrealized_conversion_cast %om : !m64 to !s64
    %fw = trikeshed.at %os[%zi] : !s64, index -> i64
    %fl = trikeshed.at %os[%one] : !s64, index -> i64
    %line = trikeshed.at %os[%two] : !s64, index -> i64
    %col = trikeshed.at %os[%three] : !s64, index -> i64
    %fp = llvm.inttoptr %fw : i64 to !llvm.ptr
    %some = arith.cmpi sgt, %fl, %c0 : i64
    scf.if %some {
      %fd = func.call @xw_desc(%fp, %fl) : (!llvm.ptr, i64) -> !d
      %fm = builtin.unrealized_conversion_cast %fd : !d to !m8
      %fs = builtin.unrealized_conversion_cast %fm : !m8 to !trikeshed.series<i8>
      %first = trikeshed.at %fs[%zi] : !trikeshed.series<i8>, index -> i8
      %abs = arith.cmpi eq, %first, %slash : i8
      scf.if %abs {
        func.call @xw_slot(%r, %sPath, %fw, %fl) : (!llvm.ptr, i64, i64, i64) -> ()
      }
    }
    func.call @xw_slot(%r, %sLine, %line, %int) : (!llvm.ptr, i64, i64, i64) -> ()
    func.call @xw_slot(%r, %sCol, %col, %int) : (!llvm.ptr, i64, i64, i64) -> ()
  }
  return
}

// a Value* that may be null: its string's window, or length -1 when it is null or not a string (the Value's two words)
func.func private @xw_strwin(%p: !llvm.ptr) -> (i64, i64) {
  %c0 = arith.constant 0 : i64
  %c32 = arith.constant 32 : i64
  %c2 = arith.constant 2 : i64
  %absent = arith.constant -1 : i64
  %tString = arith.constant 9 : i8
  %zi = arith.constant 0 : index
  %one = arith.constant 1 : index
  %pb = llvm.ptrtoint %p : !llvm.ptr to i64
  %isNull = arith.cmpi eq, %pb, %c0 : i64
  %w:2 = scf.if %isNull -> (i64, i64) {
    scf.yield %c0, %absent : i64, i64
  } else {
    %vd = func.call @xw_desc(%p, %c2) : (!llvm.ptr, i64) -> !d
    %vm = builtin.unrealized_conversion_cast %vd : !d to !m64
    %vs = builtin.unrealized_conversion_cast %vm : !m64 to !s64
    %w0 = trikeshed.at %vs[%zi] : !s64, index -> i64
    %s = trikeshed.at %vs[%one] : !s64, index -> i64
    %t8 = arith.trunci %w0 : i64 to i8
    %isStr = arith.cmpi eq, %t8, %tString : i8
    %a = arith.shrui %w0, %c32 : i64
    %l = arith.select %isStr, %a, %absent : i64
    scf.yield %s, %l : i64, i64
  }
  return %w#0, %w#1 : i64, i64
}

// attributes i and j of a set (n rows) by their names' bytes (unsigned): lexicographicOrder's order
func.func private @xw_symcmp(%x: !llvm.ptr, %b: !llvm.ptr, %n: i64, %i: i64, %j: i64) -> i32 {
  %c2 = arith.constant 2 : i64
  %lenp = llvm.alloca %c2 x i64 : (i64) -> !llvm.ptr
  %lenq = llvm.alloca %c2 x i64 : (i64) -> !llvm.ptr
  %zi = arith.constant 0 : index
  %nw0 = arith.muli %n, %c2 : i64
  %nw = arith.addi %nw0, %c2 : i64
  %rd = func.call @xw_desc(%b, %nw) : (!llvm.ptr, i64) -> !d
  %rm = builtin.unrealized_conversion_cast %rd : !d to !m64
  %rs = builtin.unrealized_conversion_cast %rm : !m64 to !s64
  // row i's name is word 2+2i (the low half); the lengths come back through the callback's slot
  %i1 = arith.addi %i, %c2 : i64
  %i2 = arith.muli %i, %c2 : i64
  %ni_w = arith.addi %i2, %c2 : i64
  %j2 = arith.muli %j, %c2 : i64
  %nj_w = arith.addi %j2, %c2 : i64
  %ni_x = arith.index_cast %ni_w : i64 to index
  %nj_x = arith.index_cast %nj_w : i64 to index
  %si64 = trikeshed.at %rs[%ni_x] : !s64, index -> i64
  %sj64 = trikeshed.at %rs[%nj_x] : !s64, index -> i64
  %si = arith.trunci %si64 : i64 to i32
  %sj = arith.trunci %sj64 : i64 to i32
  %pi = func.call @nixev_xw_sym(%x, %si, %lenp) : (!llvm.ptr, i32, !llvm.ptr) -> !llvm.ptr
  %lenv = func.call @xw_desc(%lenp, %c2) : (!llvm.ptr, i64) -> !d
  %lm = builtin.unrealized_conversion_cast %lenv : !d to !m64
  %ls = builtin.unrealized_conversion_cast %lm : !m64 to !s64
  %ni = trikeshed.at %ls[%zi] : !s64, index -> i64
  %pj = func.call @nixev_xw_sym(%x, %sj, %lenq) : (!llvm.ptr, i32, !llvm.ptr) -> !llvm.ptr
  %lqv = func.call @xw_desc(%lenq, %c2) : (!llvm.ptr, i64) -> !d
  %lqm = builtin.unrealized_conversion_cast %lqv : !d to !m64
  %lqs = builtin.unrealized_conversion_cast %lqm : !m64 to !s64
  %nj = trikeshed.at %lqs[%zi] : !s64, index -> i64
  // the names' windows live in the symbol table; the views live and die in this helper
  %di = func.call @xw_desc(%pi, %ni) : (!llvm.ptr, i64) -> !d
  %mi = builtin.unrealized_conversion_cast %di : !d to !m8
  %si8 = builtin.unrealized_conversion_cast %mi : !m8 to !text
  %nii = arith.index_cast %ni : i64 to index
  %ti = trikeshed.slice %si8[%zi, %nii] : !text -> !text
  %dj = func.call @xw_desc(%pj, %nj) : (!llvm.ptr, i64) -> !d
  %mj = builtin.unrealized_conversion_cast %dj : !d to !m8
  %sj8 = builtin.unrealized_conversion_cast %mj : !m8 to !text
  %nji = arith.index_cast %nj : i64 to index
  %tj = trikeshed.slice %sj8[%zi, %nji] : !text -> !text
  %c = trikeshed.compare %ti, %tj unsigned : !text, !text
  return %c : i32
}

// two {ptr, len} windows of the n formals at wins, at a and b, by their bytes (unsigned)
func.func private @xw_wincmp(%wins: !llvm.ptr, %n: i64, %a: i64, %b: i64) -> i32 {
  %c2 = arith.constant 2 : i64
  %zi = arith.constant 0 : index
  %one = arith.constant 1 : index
  %nw = arith.muli %n, %c2 : i64
  %wd = func.call @xw_desc(%wins, %nw) : (!llvm.ptr, i64) -> !d
  %wm = builtin.unrealized_conversion_cast %wd : !d to !m64
  %ws = builtin.unrealized_conversion_cast %wm : !m64 to !s64
  %a2 = arith.muli %a, %c2 : i64
  %b2 = arith.muli %b, %c2 : i64
  %a2x = arith.index_cast %a2 : i64 to index
  %b2x = arith.index_cast %b2 : i64 to index
  %a2y = arith.addi %a2x, %one : index
  %b2y = arith.addi %b2x, %one : index
  %dap = trikeshed.at %ws[%a2x] : !s64, index -> i64
  %na = trikeshed.at %ws[%a2y] : !s64, index -> i64
  %dbp = trikeshed.at %ws[%b2x] : !s64, index -> i64
  %nb = trikeshed.at %ws[%b2y] : !s64, index -> i64
  %dap_p = llvm.inttoptr %dap : i64 to !llvm.ptr
  %dbp_p = llvm.inttoptr %dbp : i64 to !llvm.ptr
  %da = func.call @xw_desc(%dap_p, %na) : (!llvm.ptr, i64) -> !d
  %ma = builtin.unrealized_conversion_cast %da : !d to !m8
  %sa = builtin.unrealized_conversion_cast %ma : !m8 to !text
  %nai = arith.index_cast %na : i64 to index
  %va = trikeshed.slice %sa[%zi, %nai] : !text -> !text
  %db = func.call @xw_desc(%dbp_p, %nb) : (!llvm.ptr, i64) -> !d
  %mb = builtin.unrealized_conversion_cast %db : !d to !m8
  %sb = builtin.unrealized_conversion_cast %mb : !m8 to !text
  %nbi = arith.index_cast %nb : i64 to index
  %vb = trikeshed.slice %sb[%zi, %nbi] : !text -> !text
  %c = trikeshed.compare %va, %vb unsigned : !text, !text
  return %c : i32
}

// showAttrsXML: the set's attributes in name order, each an <attr name=...> around its value
func.func private @xw_attrs(%x: !llvm.ptr, %b: !llvm.ptr, %strict: i1, %loc: i1, %depth: i64) {
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c8 = arith.constant 8 : i64
  %c16 = arith.constant 16 : i64
  %kOpen = arith.constant 0 : i64
  %kClose = arith.constant 1 : i64
  %sName = arith.constant 4 : i64
  %wAttr = arith.constant 1 : index
  %zi = arith.constant 0 : index
  %one = arith.constant 1 : index
  // the header: the size is the low half of word 0 (the header's two words are always there)
  %hd = func.call @xw_desc(%b, %c2) : (!llvm.ptr, i64) -> !d
  %hm = builtin.unrealized_conversion_cast %hd : !d to !m64
  %hs = builtin.unrealized_conversion_cast %hm : !m64 to !s64
  %h0 = trikeshed.at %hs[%zi] : !s64, index -> i64
  %n32 = arith.trunci %h0 : i64 to i32
  %n = arith.extui %n32 : i32 to i64
  %ni = arith.index_cast %n : i64 to index
  // the rows: two words each (the name in the low half of the first, then the value pointer)
  %nw0 = arith.muli %n, %c2 : i64
  %nw = arith.addi %nw0, %c2 : i64
  %rd = func.call @xw_desc(%b, %nw) : (!llvm.ptr, i64) -> !d
  %rm = builtin.unrealized_conversion_cast %rd : !d to !m64
  %rs = builtin.unrealized_conversion_cast %rm : !m64 to !s64
  // the order: the row indices sorted by name, drained into cells that live through the children's walk
  %cells = func.call @nixev_xw_cells(%x, %n) : (!llvm.ptr, i64) -> !llvm.ptr
  %idx = trikeshed.series %ni : !s64 {
  ^bb0(%q: index):
    %q64 = arith.index_cast %q : index to i64
    trikeshed.yield %q64 : i64
  }
  %srt = trikeshed.sorted %idx : !s64 -> !s64 by {
  ^bb0(%ia: i64, %ib: i64):
    %c = func.call @xw_symcmp(%x, %b, %n, %ia, %ib) : (!llvm.ptr, !llvm.ptr, i64, i64, i64) -> i32
    trikeshed.yield %c : i32
  }
  %cd = func.call @xw_desc(%cells, %n) : (!llvm.ptr, i64) -> !d
  %cm = builtin.unrealized_conversion_cast %cd : !d to !m64
  %end = trikeshed.drain %srt, %cm : !s64, !m64 -> index
  %cs = builtin.unrealized_conversion_cast %cm : !m64 to !s64
  %d1 = arith.addi %depth, %c1 : i64
  %lenp = llvm.alloca %c1 x i64 : (i64) -> !llvm.ptr
  scf.for %k = %zi to %ni step %one {
    %i = trikeshed.at %cs[%k] : !s64, index -> i64
    %i1 = arith.addi %i, %c1 : i64
    // the name's word and the row's value word (word 2+2i and 3+2i of the rows)
    %ri2 = arith.muli %i, %c2 : i64
    %nwi = arith.addi %ri2, %c2 : i64
    %vwi = arith.addi %nwi, %c1 : i64
    %nwx = arith.index_cast %nwi : i64 to index
    %vwx = arith.index_cast %vwi : i64 to index
    %sym64 = trikeshed.at %rs[%nwx] : !s64, index -> i64
    %sym = arith.trunci %sym64 : i64 to i32
    %np = func.call @nixev_xw_sym(%x, %sym, %lenp) : (!llvm.ptr, i32, !llvm.ptr) -> !llvm.ptr
    %lv = func.call @xw_desc(%lenp, %c1) : (!llvm.ptr, i64) -> !d
    %lm = builtin.unrealized_conversion_cast %lv : !d to !m64
    %ls = builtin.unrealized_conversion_cast %lm : !m64 to !s64
    %nl = trikeshed.at %ls[%zi] : !s64, index -> i64
    %nb = llvm.ptrtoint %np : !llvm.ptr to i64
    %r = func.call @xw_row(%x, %kOpen, %depth, %wAttr) : (!llvm.ptr, i64, i64, index) -> !llvm.ptr
    func.call @xw_slot(%r, %sName, %nb, %nl) : (!llvm.ptr, i64, i64, i64) -> ()
    // the Attr row's address (pointer arithmetic for positionOf; the row's fields are read through the rows' view)
    %ao = arith.muli %i1, %c16 : i64
    %a = llvm.getelementptr %b[%ao] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %apos = func.call @nixev_xw_apos(%x, %a) : (!llvm.ptr, !llvm.ptr) -> !llvm.ptr
    scf.if %loc {
      func.call @xw_pos(%x, %r, %apos) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> ()
    }
    %val64 = trikeshed.at %rs[%vwx] : !s64, index -> i64
    %val = llvm.inttoptr %val64 : i64 to !llvm.ptr
    func.call @xw_value(%x, %val, %strict, %loc, %d1, %apos) : (!llvm.ptr, !llvm.ptr, i1, i1, i64, !llvm.ptr) -> ()
    %rc = func.call @xw_row(%x, %kClose, %depth, %wAttr) : (!llvm.ptr, i64, i64, index) -> !llvm.ptr
  }
  return
}

// toXML: one value at depth, forced first when strict.  Its two words (type/aux, the union) are read once, after the
// forcing (which may replace a thunk's contents).
func.func private @xw_value(%x: !llvm.ptr, %v: !llvm.ptr, %strict: i1, %loc: i1, %depth: i64, %pos: !llvm.ptr) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c7 = arith.constant 7 : i64
  %c8 = arith.constant 8 : i64
  %c16 = arith.constant 16 : i64
  %c24 = arith.constant 24 : i64
  %c32 = arith.constant 32 : i64
  %c40 = arith.constant 40 : i64
  %kOpen = arith.constant 0 : i64
  %kClose = arith.constant 1 : i64
  %kEmpty = arith.constant 2 : i64
  %sEllipsis = arith.constant 2 : i64
  %sName = arith.constant 4 : i64
  %sValue = arith.constant 7 : i64
  %int = arith.constant -2 : i64
  %absent = arith.constant -1 : i64
  %z32 = arith.constant 0 : i32
  %z8 = arith.constant 0 : i8
  %zi = arith.constant 0 : index
  %one = arith.constant 1 : index
  %wAttrs = arith.constant 2 : index
  %wDrv = arith.constant 3 : index
  %wRepeated = arith.constant 4 : index
  %wList = arith.constant 5 : index
  %wFunction = arith.constant 6 : index
  %wAttrspat = arith.constant 7 : index
  %wVarpat = arith.constant 8 : index
  %wInt = arith.constant 9 : index
  %wBool = arith.constant 10 : index
  %wString = arith.constant 11 : index
  %wPath = arith.constant 12 : index
  %wNull = arith.constant 13 : index
  %wUneval = arith.constant 14 : index
  %wFloat = arith.constant 15 : index
  %wTrue = arith.constant 16 : index
  %wFalse = arith.constant 17 : index
  %wOne = arith.constant 18 : index
  %wAttr = arith.constant 1 : index
  scf.if %strict {
    func.call @nixev_xw_force(%x, %v, %pos) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> ()
  }
  // the Value's words: word 0 holds VType (low byte) and aux (the high half), word 1 the union
  %vd = func.call @xw_desc(%v, %c2) : (!llvm.ptr, i64) -> !d
  %vm = builtin.unrealized_conversion_cast %vd : !d to !m64
  %vs = builtin.unrealized_conversion_cast %vm : !m64 to !s64
  %w0 = trikeshed.at %vs[%zi] : !s64, index -> i64
  %w1 = trikeshed.at %vs[%one] : !s64, index -> i64
  %t8 = arith.trunci %w0 : i64 to i8
  %t = arith.index_castui %t8 : i8 to index
  %aux = arith.shrui %w0, %c32 : i64
  %d1 = arith.addi %depth, %c1 : i64
  %d2 = arith.addi %depth, %c2 : i64
  scf.index_switch %t
  case 5 {
    %r = func.call @xw_row(%x, %kEmpty, %depth, %wInt) : (!llvm.ptr, i64, i64, index) -> !llvm.ptr
    func.call @xw_slot(%r, %sValue, %w1, %int) : (!llvm.ptr, i64, i64, i64) -> ()
    scf.yield
  }
  case 6 {
    %lenp = llvm.alloca %c1 x i64 : (i64) -> !llvm.ptr
    %fp = func.call @nixev_xw_float(%x, %v, %lenp) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> !llvm.ptr
    %lv = func.call @xw_desc(%lenp, %c1) : (!llvm.ptr, i64) -> !d
    %lm = builtin.unrealized_conversion_cast %lv : !d to !m64
    %ls = builtin.unrealized_conversion_cast %lm : !m64 to !s64
    %fl = trikeshed.at %ls[%zi] : !s64, index -> i64
    %fb = llvm.ptrtoint %fp : !llvm.ptr to i64
    %r = func.call @xw_row(%x, %kEmpty, %depth, %wFloat) : (!llvm.ptr, i64, i64, index) -> !llvm.ptr
    func.call @xw_slot(%r, %sValue, %fb, %fl) : (!llvm.ptr, i64, i64, i64) -> ()
    scf.yield
  }
  case 7 {
    // the bool byte is the low byte of the union word
    %b = arith.trunci %w1 : i64 to i8
    %isT = arith.cmpi ne, %b, %z8 : i8
    %w = arith.select %isT, %wTrue, %wFalse : index
    %wp, %wl = func.call @xw_word(%w) : (index) -> (i64, i64)
    %r = func.call @xw_row(%x, %kEmpty, %depth, %wBool) : (!llvm.ptr, i64, i64, index) -> !llvm.ptr
    func.call @xw_slot(%r, %sValue, %wp, %wl) : (!llvm.ptr, i64, i64, i64) -> ()
    scf.yield
  }
  case 8 {
    %r = func.call @xw_row(%x, %kEmpty, %depth, %wNull) : (!llvm.ptr, i64, i64, index) -> !llvm.ptr
    scf.yield
  }
  case 9 {
    func.call @nixev_xw_ctx(%x, %v) : (!llvm.ptr, !llvm.ptr) -> ()
    %sb, %sl = func.call @xw_strwin(%v) : (!llvm.ptr) -> (i64, i64)
    %r = func.call @xw_row(%x, %kEmpty, %depth, %wString) : (!llvm.ptr, i64, i64, index) -> !llvm.ptr
    func.call @xw_slot(%r, %sValue, %sb, %sl) : (!llvm.ptr, i64, i64, i64) -> ()
    scf.yield
  }
  case 10 {
    %r = func.call @xw_row(%x, %kEmpty, %depth, %wPath) : (!llvm.ptr, i64, i64, index) -> !llvm.ptr
    func.call @xw_slot(%r, %sValue, %w1, %aux) : (!llvm.ptr, i64, i64, i64) -> ()
    scf.yield
  }
  case 11 {
    %bind = llvm.inttoptr %w1 : i64 to !llvm.ptr
    %isd32 = func.call @nixev_xw_isdrv(%x, %v) : (!llvm.ptr, !llvm.ptr) -> i32
    %isd = arith.cmpi ne, %isd32, %z32 : i32
    scf.if %isd {
      // drvPath then outPath, each forced at its position when strict, before the tag
      %s32 = arith.extui %strict : i1 to i32
      %dpv = func.call @nixev_xw_drvattr(%x, %v, %c0, %s32) : (!llvm.ptr, !llvm.ptr, i64, i32) -> !llvm.ptr
      %db, %dl = func.call @xw_strwin(%dpv) : (!llvm.ptr) -> (i64, i64)
      %opv = func.call @nixev_xw_drvattr(%x, %v, %c1, %s32) : (!llvm.ptr, !llvm.ptr, i64, i32) -> !llvm.ptr
      %ob, %ol = func.call @xw_strwin(%opv) : (!llvm.ptr) -> (i64, i64)
      %sDrv = arith.constant 1 : i64
      %sOut = arith.constant 5 : i64
      %r = func.call @xw_row(%x, %kOpen, %depth, %wDrv) : (!llvm.ptr, i64, i64, index) -> !llvm.ptr
      func.call @xw_slot(%r, %sDrv, %db, %dl) : (!llvm.ptr, i64, i64, i64) -> ()
      func.call @xw_slot(%r, %sOut, %ob, %ol) : (!llvm.ptr, i64, i64, i64) -> ()
      // a derivation's attributes once per drvPath: an empty or missing one is always «repeated»
      %some = arith.cmpi sgt, %dl, %c0 : i64
      %fresh32 = scf.if %some -> (i32) {
        %dp = llvm.inttoptr %db : i64 to !llvm.ptr
        %s = func.call @nixev_xw_seen(%x, %dp, %dl) : (!llvm.ptr, !llvm.ptr, i64) -> i32
        scf.yield %s : i32
      } else {
        scf.yield %z32 : i32
      }
      %fresh = arith.cmpi ne, %fresh32, %z32 : i32
      scf.if %fresh {
        func.call @xw_attrs(%x, %bind, %strict, %loc, %d1) : (!llvm.ptr, !llvm.ptr, i1, i1, i64) -> ()
      } else {
        %rr = func.call @xw_row(%x, %kEmpty, %d1, %wRepeated) : (!llvm.ptr, i64, i64, index) -> !llvm.ptr
      }
      %rc = func.call @xw_row(%x, %kClose, %depth, %wDrv) : (!llvm.ptr, i64, i64, index) -> !llvm.ptr
    } else {
      %r = func.call @xw_row(%x, %kOpen, %depth, %wAttrs) : (!llvm.ptr, i64, i64, index) -> !llvm.ptr
      func.call @xw_attrs(%x, %bind, %strict, %loc, %d1) : (!llvm.ptr, !llvm.ptr, i1, i1, i64) -> ()
      %rc = func.call @xw_row(%x, %kClose, %depth, %wAttrs) : (!llvm.ptr, i64, i64, index) -> !llvm.ptr
    }
    scf.yield
  }
  case 12 {
    // the list's size is aux; its cells are pointer bits, read as one view
    %ni = arith.index_cast %aux : i64 to index
    %elems = llvm.inttoptr %w1 : i64 to !llvm.ptr
    %ed = func.call @xw_desc(%elems, %aux) : (!llvm.ptr, i64) -> !d
    %em = builtin.unrealized_conversion_cast %ed : !d to !m64
    %es = builtin.unrealized_conversion_cast %em : !m64 to !s64
    %r = func.call @xw_row(%x, %kOpen, %depth, %wList) : (!llvm.ptr, i64, i64, index) -> !llvm.ptr
    scf.for %i = %zi to %ni step %one {
      %e64 = trikeshed.at %es[%i] : !s64, index -> i64
      %e = llvm.inttoptr %e64 : i64 to !llvm.ptr
      func.call @xw_value(%x, %e, %strict, %loc, %d1, %pos) : (!llvm.ptr, !llvm.ptr, i1, i1, i64, !llvm.ptr) -> ()
    }
    %rc = func.call @xw_row(%x, %kClose, %depth, %wList) : (!llvm.ptr, i64, i64, index) -> !llvm.ptr
    scf.yield
  }
  case 13 {
    // {pos, has formals, arg name ptr, its length or -1, ellipsis, formal count}: six words, read as one view
    %rec = llvm.alloca %c7 x i64 : (i64) -> !llvm.ptr
    func.call @nixev_xw_lambda(%x, %v, %rec) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> ()
    %rd = func.call @xw_desc(%rec, %c7) : (!llvm.ptr, i64) -> !d
    %rm = builtin.unrealized_conversion_cast %rd : !d to !m64
    %rs = builtin.unrealized_conversion_cast %rm : !m64 to !s64
    %i2 = arith.constant 2 : index
    %i3 = arith.constant 3 : index
    %i4 = arith.constant 4 : index
    %i5 = arith.constant 5 : index
    %lpw = trikeshed.at %rs[%zi] : !s64, index -> i64
    %hf = trikeshed.at %rs[%one] : !s64, index -> i64
    %ab = trikeshed.at %rs[%i2] : !s64, index -> i64
    %al = trikeshed.at %rs[%i3] : !s64, index -> i64
    %el = trikeshed.at %rs[%i4] : !s64, index -> i64
    %nf = trikeshed.at %rs[%i5] : !s64, index -> i64
    %lpos = llvm.inttoptr %lpw : i64 to !llvm.ptr
    %r = func.call @xw_row(%x, %kOpen, %depth, %wFunction) : (!llvm.ptr, i64, i64, index) -> !llvm.ptr
    scf.if %loc {
      func.call @xw_pos(%x, %r, %lpos) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> ()
    }
    %hasF = arith.cmpi ne, %hf, %c0 : i64
    scf.if %hasF {
      %pa = func.call @xw_row(%x, %kOpen, %d1, %wAttrspat) : (!llvm.ptr, i64, i64, index) -> !llvm.ptr
      func.call @xw_slot(%pa, %sName, %ab, %al) : (!llvm.ptr, i64, i64, i64) -> ()
      %ell = arith.cmpi ne, %el, %c0 : i64
      %op, %ol = func.call @xw_word(%wOne) : (index) -> (i64, i64)
      %ell_l = arith.select %ell, %ol, %absent : i64
      func.call @xw_slot(%pa, %sEllipsis, %op, %ell_l) : (!llvm.ptr, i64, i64, i64) -> ()
      // the formals by their bytes, an <attr name=.../> each
      %nfi = arith.index_cast %nf : i64 to index
      // the formals' windows: the bridge's buffer, one nixev_xw_formal per formal (a StringRef each)
      %wins = func.call @nixev_xw_names(%x, %nf) : (!llvm.ptr, i64) -> !llvm.ptr
      scf.for %g = %zi to %nfi step %one {
        %g64 = arith.index_cast %g : index to i64
        %go = arith.muli %g64, %c16 : i64
        %gp = llvm.getelementptr %wins[%go] : (!llvm.ptr, i64) -> !llvm.ptr, i8
        func.call @nixev_xw_formal(%v, %g64, %gp) : (!llvm.ptr, i64, !llvm.ptr) -> ()
      }
      %idx = trikeshed.series %nfi : !s64 {
      ^bb0(%q: index):
        %q64 = arith.index_cast %q : index to i64
        trikeshed.yield %q64 : i64
      }
      %srt = trikeshed.sorted %idx : !s64 -> !s64 by {
      ^bb0(%fa: i64, %fb: i64):
        %c = func.call @xw_wincmp(%wins, %nf, %fa, %fb) : (!llvm.ptr, i64, i64, i64) -> i32
        trikeshed.yield %c : i32
      }
      // the windows' view: word 2g the bytes' address, word 2g+1 the length
      %wnw = arith.muli %nf, %c2 : i64
      %wd = func.call @xw_desc(%wins, %wnw) : (!llvm.ptr, i64) -> !d
      %wm = builtin.unrealized_conversion_cast %wd : !d to !m64
      %ws = builtin.unrealized_conversion_cast %wm : !m64 to !s64
      scf.for %j = %zi to %nfi step %one {
        %e = trikeshed.at %srt[%j] : !s64, index -> i64
        %e2 = arith.muli %e, %c2 : i64
        %e2x = arith.index_cast %e2 : i64 to index
        %e2y = arith.addi %e2x, %one : index
        %wb = trikeshed.at %ws[%e2x] : !s64, index -> i64
        %wl = trikeshed.at %ws[%e2y] : !s64, index -> i64
        %ar = func.call @xw_row(%x, %kEmpty, %d2, %wAttr) : (!llvm.ptr, i64, i64, index) -> !llvm.ptr
        func.call @xw_slot(%ar, %sName, %wb, %wl) : (!llvm.ptr, i64, i64, i64) -> ()
      }
      %pc = func.call @xw_row(%x, %kClose, %d1, %wAttrspat) : (!llvm.ptr, i64, i64, index) -> !llvm.ptr
    } else {
      // <varpat name=.../>: the argument's name, empty when it has none
      %neg = arith.cmpi slt, %al, %c0 : i64
      %vl = arith.select %neg, %c0, %al : i64
      %vr = func.call @xw_row(%x, %kEmpty, %d1, %wVarpat) : (!llvm.ptr, i64, i64, index) -> !llvm.ptr
      func.call @xw_slot(%vr, %sName, %ab, %vl) : (!llvm.ptr, i64, i64, i64) -> ()
    }
    %rc = func.call @xw_row(%x, %kClose, %depth, %wFunction) : (!llvm.ptr, i64, i64, index) -> !llvm.ptr
    scf.yield
  }
  default {
    %r = func.call @xw_row(%x, %kEmpty, %depth, %wUneval) : (!llvm.ptr, i64, i64, index) -> !llvm.ptr
    scf.yield
  }
  return
}

// printValueAsXML's document: <expr> around the value at depth 1 (no position), the rows left in the bridge's fill
func.func @nixev_ts_xml_walk(%x: !llvm.ptr, %v: !llvm.ptr, %strict: i32, %loc: i32) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %z32 = arith.constant 0 : i32
  %wExpr = arith.constant 0 : index
  %s = arith.cmpi ne, %strict, %z32 : i32
  %l = arith.cmpi ne, %loc, %z32 : i32
  %null = llvm.inttoptr %c0 : i64 to !llvm.ptr
  %r = func.call @xw_row(%x, %c0, %c0, %wExpr) : (!llvm.ptr, i64, i64, index) -> !llvm.ptr
  func.call @xw_value(%x, %v, %s, %l, %c1, %null) : (!llvm.ptr, !llvm.ptr, i1, i1, i64, !llvm.ptr) -> ()
  %rc = func.call @xw_row(%x, %c1, %c0, %wExpr) : (!llvm.ptr, i64, i64, index) -> !llvm.ptr
  return
}
