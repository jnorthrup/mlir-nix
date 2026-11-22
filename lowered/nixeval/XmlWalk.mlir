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
// formal count, formals' {ptr, len} windows}), nixev_xw_cells (n i64 of bridge-owned scratch: a set's sorted order lives
// through its children's walk, and an exception unwinding through here leaks nothing).
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
// 10 bool, 11 string, 12 path, 13 null, 14 unevaluated, 15 float, 16 true, 17 false, 18 "1"
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

// the descriptor of n cells at p (a struct, not a memref: returning it allocates nothing and clones nothing)
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

// a new row: kind, depth, word w as its name, every slot absent
func.func private @xw_row(%x: !llvm.ptr, %kind: i64, %depth: i64, %w: index) -> !llvm.ptr {
  %c8 = arith.constant 8 : i64
  %c16 = arith.constant 16 : i64
  %c24 = arith.constant 24 : i64
  %c40 = arith.constant 40 : i64
  %absent = arith.constant -1 : i64
  %zi = arith.constant 0 : index
  %one = arith.constant 1 : index
  %eight = arith.constant 8 : index
  %r = func.call @nixev_xw_row(%x) : (!llvm.ptr) -> !llvm.ptr
  llvm.store %kind, %r : i64, !llvm.ptr
  %dp = llvm.getelementptr %r[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  llvm.store %depth, %dp : i64, !llvm.ptr
  %wp, %wl = func.call @xw_word(%w) : (index) -> (i64, i64)
  %np = llvm.getelementptr %r[%c16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  llvm.store %wp, %np : i64, !llvm.ptr
  %lp = llvm.getelementptr %r[%c24] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  llvm.store %wl, %lp : i64, !llvm.ptr
  scf.for %s = %zi to %eight step %one {
    %s64 = arith.index_cast %s : index to i64
    %so = arith.muli %s64, %c16 : i64
    %o = arith.addi %so, %c40 : i64
    %sp = llvm.getelementptr %r[%o] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %absent, %sp : i64, !llvm.ptr
  }
  return %r : !llvm.ptr
}

// slot s of row r: the bits and the length (-1 absent, -2 an integer)
func.func private @xw_slot(%r: !llvm.ptr, %s: i64, %bits: i64, %len: i64) {
  %c8 = arith.constant 8 : i64
  %c16 = arith.constant 16 : i64
  %c32 = arith.constant 32 : i64
  %so = arith.muli %s, %c16 : i64
  %o = arith.addi %so, %c32 : i64
  %bp = llvm.getelementptr %r[%o] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  llvm.store %bits, %bp : i64, !llvm.ptr
  %lp = llvm.getelementptr %bp[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  llvm.store %len, %lp : i64, !llvm.ptr
  return
}

// posToXML: path (an absolute file only), line and column, when the position holds any
func.func private @xw_pos(%x: !llvm.ptr, %r: !llvm.ptr, %pos: !llvm.ptr) {
  %c0 = arith.constant 0 : i64
  %c4 = arith.constant 4 : i64
  %c8 = arith.constant 8 : i64
  %c16 = arith.constant 16 : i64
  %c24 = arith.constant 24 : i64
  %sCol = arith.constant 0 : i64
  %sLine = arith.constant 3 : i64
  %sPath = arith.constant 6 : i64
  %int = arith.constant -2 : i64
  %z32 = arith.constant 0 : i32
  %slash = arith.constant 47 : i8
  %out = llvm.alloca %c4 x i64 : (i64) -> !llvm.ptr
  %f = func.call @nixev_xw_pos(%x, %pos, %out) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> i32
  %found = arith.cmpi ne, %f, %z32 : i32
  scf.if %found {
    %fp = llvm.load %out : !llvm.ptr -> !llvm.ptr
    %flp = llvm.getelementptr %out[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %fl = llvm.load %flp : !llvm.ptr -> i64
    %lnp = llvm.getelementptr %out[%c16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %line = llvm.load %lnp : !llvm.ptr -> i64
    %clp = llvm.getelementptr %out[%c24] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %col = llvm.load %clp : !llvm.ptr -> i64
    %some = arith.cmpi sgt, %fl, %c0 : i64
    scf.if %some {
      %fd = func.call @xw_desc(%fp, %fl) : (!llvm.ptr, i64) -> !d
      %fm = builtin.unrealized_conversion_cast %fd : !d to !m8
      %fs = builtin.unrealized_conversion_cast %fm : !m8 to !text
      %zi = arith.constant 0 : index
      %first = trikeshed.at %fs[%zi] : !text, index -> i8
      %abs = arith.cmpi eq, %first, %slash : i8
      scf.if %abs {
        %fb = llvm.ptrtoint %fp : !llvm.ptr to i64
        func.call @xw_slot(%r, %sPath, %fb, %fl) : (!llvm.ptr, i64, i64, i64) -> ()
      }
    }
    func.call @xw_slot(%r, %sLine, %line, %int) : (!llvm.ptr, i64, i64, i64) -> ()
    func.call @xw_slot(%r, %sCol, %col, %int) : (!llvm.ptr, i64, i64, i64) -> ()
  }
  return
}

// a Value* that may be null: its string's window, or length -1 when it is null or not a string
func.func private @xw_strwin(%p: !llvm.ptr) -> (i64, i64) {
  %c0 = arith.constant 0 : i64
  %c4 = arith.constant 4 : i64
  %c8 = arith.constant 8 : i64
  %absent = arith.constant -1 : i64
  %tString = arith.constant 9 : i8
  %pb = llvm.ptrtoint %p : !llvm.ptr to i64
  %isNull = arith.cmpi eq, %pb, %c0 : i64
  %w:2 = scf.if %isNull -> (i64, i64) {
    scf.yield %c0, %absent : i64, i64
  } else {
    %t = llvm.load %p : !llvm.ptr -> i8
    %isStr = arith.cmpi eq, %t, %tString : i8
    %ap = llvm.getelementptr %p[%c4] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %a32 = llvm.load %ap : !llvm.ptr -> i32
    %a = arith.extui %a32 : i32 to i64
    %sp = llvm.getelementptr %p[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %s = llvm.load %sp : !llvm.ptr -> i64
    %l = arith.select %isStr, %a, %absent : i64
    scf.yield %s, %l : i64, i64
  }
  return %w#0, %w#1 : i64, i64
}

// attributes i and j of a set by their names' bytes (unsigned): lexicographicOrder's order
func.func private @xw_symcmp(%x: !llvm.ptr, %b: !llvm.ptr, %i: i64, %j: i64) -> i32 {
  %c1 = arith.constant 1 : i64
  %c16 = arith.constant 16 : i64
  %lenp = llvm.alloca %c1 x i64 : (i64) -> !llvm.ptr
  %i1 = arith.addi %i, %c1 : i64
  %oi = arith.muli %i1, %c16 : i64
  %ai = llvm.getelementptr %b[%oi] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %si = llvm.load %ai : !llvm.ptr -> i32
  %j1 = arith.addi %j, %c1 : i64
  %oj = arith.muli %j1, %c16 : i64
  %aj = llvm.getelementptr %b[%oj] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %sj = llvm.load %aj : !llvm.ptr -> i32
  // the names' windows live in the symbol table; the views live and die in this helper
  %zi = arith.constant 0 : index
  %pi = func.call @nixev_xw_sym(%x, %si, %lenp) : (!llvm.ptr, i32, !llvm.ptr) -> !llvm.ptr
  %ni = llvm.load %lenp : !llvm.ptr -> i64
  %pj = func.call @nixev_xw_sym(%x, %sj, %lenp) : (!llvm.ptr, i32, !llvm.ptr) -> !llvm.ptr
  %nj = llvm.load %lenp : !llvm.ptr -> i64
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

// two {ptr, len} windows at wins + 16a and + 16b by their bytes (unsigned)
func.func private @xw_wincmp(%wins: !llvm.ptr, %a: i64, %b: i64) -> i32 {
  %c8 = arith.constant 8 : i64
  %c16 = arith.constant 16 : i64
  %zi = arith.constant 0 : index
  %oa = arith.muli %a, %c16 : i64
  %pa = llvm.getelementptr %wins[%oa] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %dap = llvm.load %pa : !llvm.ptr -> !llvm.ptr
  %lap = llvm.getelementptr %pa[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %na = llvm.load %lap : !llvm.ptr -> i64
  %ob = arith.muli %b, %c16 : i64
  %pb = llvm.getelementptr %wins[%ob] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %dbp = llvm.load %pb : !llvm.ptr -> !llvm.ptr
  %lbp = llvm.getelementptr %pb[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %nb = llvm.load %lbp : !llvm.ptr -> i64
  %da = func.call @xw_desc(%dap, %na) : (!llvm.ptr, i64) -> !d
  %ma = builtin.unrealized_conversion_cast %da : !d to !m8
  %sa = builtin.unrealized_conversion_cast %ma : !m8 to !text
  %nai = arith.index_cast %na : i64 to index
  %va = trikeshed.slice %sa[%zi, %nai] : !text -> !text
  %db = func.call @xw_desc(%dbp, %nb) : (!llvm.ptr, i64) -> !d
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
  %c8 = arith.constant 8 : i64
  %c16 = arith.constant 16 : i64
  %kOpen = arith.constant 0 : i64
  %kClose = arith.constant 1 : i64
  %sName = arith.constant 4 : i64
  %wAttr = arith.constant 1 : index
  %zi = arith.constant 0 : index
  %one = arith.constant 1 : index
  %n32 = llvm.load %b : !llvm.ptr -> i32
  %n = arith.extui %n32 : i32 to i64
  %ni = arith.index_cast %n : i64 to index
  %lenp = llvm.alloca %c1 x i64 : (i64) -> !llvm.ptr
  // the order: the row indices sorted by name, drained into cells that live through the children's walk
  %cells = func.call @nixev_xw_cells(%x, %n) : (!llvm.ptr, i64) -> !llvm.ptr
  %idx = trikeshed.series %ni : !s64 {
  ^bb0(%q: index):
    %q64 = arith.index_cast %q : index to i64
    trikeshed.yield %q64 : i64
  }
  %srt = trikeshed.sorted %idx : !s64 -> !s64 by {
  ^bb0(%ia: i64, %ib: i64):
    %c = func.call @xw_symcmp(%x, %b, %ia, %ib) : (!llvm.ptr, !llvm.ptr, i64, i64) -> i32
    trikeshed.yield %c : i32
  }
  %cd = func.call @xw_desc(%cells, %n) : (!llvm.ptr, i64) -> !d
  %cm = builtin.unrealized_conversion_cast %cd : !d to !m64
  %end = trikeshed.drain %srt, %cm : !s64, !m64 -> index
  %d1 = arith.addi %depth, %c1 : i64
  scf.for %k = %zi to %ni step %one {
    %k64 = arith.index_cast %k : index to i64
    %ko = arith.muli %k64, %c8 : i64
    %cp = llvm.getelementptr %cells[%ko] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %i = llvm.load %cp : !llvm.ptr -> i64
    %i1 = arith.addi %i, %c1 : i64
    %ao = arith.muli %i1, %c16 : i64
    %a = llvm.getelementptr %b[%ao] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %sym = llvm.load %a : !llvm.ptr -> i32
    %np = func.call @nixev_xw_sym(%x, %sym, %lenp) : (!llvm.ptr, i32, !llvm.ptr) -> !llvm.ptr
    %nl = llvm.load %lenp : !llvm.ptr -> i64
    %nb = llvm.ptrtoint %np : !llvm.ptr to i64
    %r = func.call @xw_row(%x, %kOpen, %depth, %wAttr) : (!llvm.ptr, i64, i64, index) -> !llvm.ptr
    func.call @xw_slot(%r, %sName, %nb, %nl) : (!llvm.ptr, i64, i64, i64) -> ()
    %apos = func.call @nixev_xw_apos(%x, %a) : (!llvm.ptr, !llvm.ptr) -> !llvm.ptr
    scf.if %loc {
      func.call @xw_pos(%x, %r, %apos) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> ()
    }
    %vp = llvm.getelementptr %a[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %val = llvm.load %vp : !llvm.ptr -> !llvm.ptr
    func.call @xw_value(%x, %val, %strict, %loc, %d1, %apos) : (!llvm.ptr, !llvm.ptr, i1, i1, i64, !llvm.ptr) -> ()
    %rc = func.call @xw_row(%x, %kClose, %depth, %wAttr) : (!llvm.ptr, i64, i64, index) -> !llvm.ptr
  }
  return
}

// toXML: one value at depth, forced first when strict
func.func private @xw_value(%x: !llvm.ptr, %v: !llvm.ptr, %strict: i1, %loc: i1, %depth: i64, %pos: !llvm.ptr) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c4 = arith.constant 4 : i64
  %c7 = arith.constant 7 : i64
  %c8 = arith.constant 8 : i64
  %c16 = arith.constant 16 : i64
  %c24 = arith.constant 24 : i64
  %c32 = arith.constant 32 : i64
  %c40 = arith.constant 40 : i64
  %c48 = arith.constant 48 : i64
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
  %t8 = llvm.load %v : !llvm.ptr -> i8
  %t = arith.index_castui %t8 : i8 to index
  %auxp = llvm.getelementptr %v[%c4] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %wordp = llvm.getelementptr %v[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %d1 = arith.addi %depth, %c1 : i64
  %d2 = arith.addi %depth, %c2 : i64
  scf.index_switch %t
  case 5 {
    %r = func.call @xw_row(%x, %kEmpty, %depth, %wInt) : (!llvm.ptr, i64, i64, index) -> !llvm.ptr
    %iv = llvm.load %wordp : !llvm.ptr -> i64
    func.call @xw_slot(%r, %sValue, %iv, %int) : (!llvm.ptr, i64, i64, i64) -> ()
    scf.yield
  }
  case 6 {
    %lenp = llvm.alloca %c1 x i64 : (i64) -> !llvm.ptr
    %fp = func.call @nixev_xw_float(%x, %v, %lenp) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> !llvm.ptr
    %fl = llvm.load %lenp : !llvm.ptr -> i64
    %fb = llvm.ptrtoint %fp : !llvm.ptr to i64
    %r = func.call @xw_row(%x, %kEmpty, %depth, %wFloat) : (!llvm.ptr, i64, i64, index) -> !llvm.ptr
    func.call @xw_slot(%r, %sValue, %fb, %fl) : (!llvm.ptr, i64, i64, i64) -> ()
    scf.yield
  }
  case 7 {
    %b = llvm.load %wordp : !llvm.ptr -> i8
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
    %a32 = llvm.load %auxp : !llvm.ptr -> i32
    %a = arith.extui %a32 : i32 to i64
    %pb = llvm.load %wordp : !llvm.ptr -> i64
    %r = func.call @xw_row(%x, %kEmpty, %depth, %wPath) : (!llvm.ptr, i64, i64, index) -> !llvm.ptr
    func.call @xw_slot(%r, %sValue, %pb, %a) : (!llvm.ptr, i64, i64, i64) -> ()
    scf.yield
  }
  case 11 {
    %bind = llvm.load %wordp : !llvm.ptr -> !llvm.ptr
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
    %a32 = llvm.load %auxp : !llvm.ptr -> i32
    %n = arith.extui %a32 : i32 to i64
    %ni = arith.index_cast %n : i64 to index
    %elems = llvm.load %wordp : !llvm.ptr -> !llvm.ptr
    %r = func.call @xw_row(%x, %kOpen, %depth, %wList) : (!llvm.ptr, i64, i64, index) -> !llvm.ptr
    scf.for %i = %zi to %ni step %one {
      %i64 = arith.index_cast %i : index to i64
      %eo = arith.muli %i64, %c8 : i64
      %ep = llvm.getelementptr %elems[%eo] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %e = llvm.load %ep : !llvm.ptr -> !llvm.ptr
      func.call @xw_value(%x, %e, %strict, %loc, %d1, %pos) : (!llvm.ptr, !llvm.ptr, i1, i1, i64, !llvm.ptr) -> ()
    }
    %rc = func.call @xw_row(%x, %kClose, %depth, %wList) : (!llvm.ptr, i64, i64, index) -> !llvm.ptr
    scf.yield
  }
  case 13 {
    // {pos, has formals, arg name ptr, its length or -1, ellipsis, formal count, the formals' windows}
    %rec = llvm.alloca %c7 x i64 : (i64) -> !llvm.ptr
    func.call @nixev_xw_lambda(%x, %v, %rec) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> ()
    %lpos = llvm.load %rec : !llvm.ptr -> !llvm.ptr
    %hfp = llvm.getelementptr %rec[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %hf = llvm.load %hfp : !llvm.ptr -> i64
    %app = llvm.getelementptr %rec[%c16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %ab = llvm.load %app : !llvm.ptr -> i64
    %alp = llvm.getelementptr %rec[%c24] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %al = llvm.load %alp : !llvm.ptr -> i64
    %elp = llvm.getelementptr %rec[%c32] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %el = llvm.load %elp : !llvm.ptr -> i64
    %nfp = llvm.getelementptr %rec[%c40] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %nf = llvm.load %nfp : !llvm.ptr -> i64
    %wsp = llvm.getelementptr %rec[%c48] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %wins = llvm.load %wsp : !llvm.ptr -> !llvm.ptr
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
      %idx = trikeshed.series %nfi : !s64 {
      ^bb0(%q: index):
        %q64 = arith.index_cast %q : index to i64
        trikeshed.yield %q64 : i64
      }
      %srt = trikeshed.sorted %idx : !s64 -> !s64 by {
      ^bb0(%fa: i64, %fb: i64):
        %c = func.call @xw_wincmp(%wins, %fa, %fb) : (!llvm.ptr, i64, i64) -> i32
        trikeshed.yield %c : i32
      }
      scf.for %j = %zi to %nfi step %one {
        %e = trikeshed.at %srt[%j] : !s64, index -> i64
        %eo = arith.muli %e, %c16 : i64
        %wp = llvm.getelementptr %wins[%eo] : (!llvm.ptr, i64) -> !llvm.ptr, i8
        %wb = llvm.load %wp : !llvm.ptr -> i64
        %wlp = llvm.getelementptr %wp[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
        %wl = llvm.load %wlp : !llvm.ptr -> i64
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
