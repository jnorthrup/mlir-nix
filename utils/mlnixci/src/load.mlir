// load.mlir -- a corpus's columns, made at load in TrikeShed's forms, in one function: the composition of columns.mlir's
// facets over the evaluation's index that corpus.mlir used to chain through their C interfaces.
//   corpus_columns  the options (the DirectChildren of the `options` array, a slice of the kids), the Columns facet over
//                   them (opt_members), their cells (opt_cells) and texts (opt_text), the four coded columns (col_code:
//                   DictColumn), the rows in key order (col_order: Cursor.ordered), and the three per-row columns the
//                   server rewrites later (whatif 0, match 1, baseOf -1), each a series
// Compiled like columns.mlir, by mlnix-opt --trikeshed-lower-cursors; corpus.mlir calls it through its C interface and
// keeps the buffers in the corpus's slots.  Every buffer returned is fresh (its allocation is its data); the members'
// table and the cells no slot keeps are freed here, by the deallocation pass.

!text = !trikeshed.series<i8>
!s32 = !trikeshed.series<i32>
!s64 = !trikeshed.series<i64>
!tw = !trikeshed.twin<i32>
!tp = !trikeshed.twinpacked<i32>
!pieces = !trikeshed.series<!tp>
!ix = !trikeshed.cursor<"ConfixIndex", [!tw, i8, !tp]>
!ik = !trikeshed.colkey<"ConfixIndex">

// columns.mlir's facets (the same lowering, so the same calling convention)
func.func private @opt_members(!ix, !s32, !text, i64) -> (!s32, !s32, !s32, !s32, !s32, !s32, !s32)
func.func private @opt_cells(!ix, !s32, !text, !s32, !s32, !s32, !s32, !s32, !s32, !tp, !tp, !tp)
    -> (!pieces, !pieces, !pieces, !pieces, !pieces)
func.func private @opt_text(!ix, !s32, !text, !s32, !s32, !tp) -> (!text, !pieces, !text, !pieces)
func.func private @col_code(!text, !pieces) -> (!s32, !pieces)
func.func private @col_order(!text, !pieces) -> !s32

// The columns of the corpus whose text is t (the JSON, its first len bytes, then the 7 bytes "?(none)"), indexed by rows
// and kids, its options the array at row opts.  In the order of the corpus's slots 4 ..< 21, then 27 and 28:
//   obj value state keys key hay hayAt | section kind state module (codes) | whatif match | the four codes' names |
//   order baseOf
func.func @corpus_columns(%rows: !ix, %kids: !s32, %t: !text, %len: i64, %opts: i64)
    -> (!s64, !pieces, !pieces, !text, !pieces, !text, !pieces, !s32, !s32, !s32, !s32, !s32, !s32,
        !pieces, !pieces, !pieces, !pieces, !s32, !s32) attributes {llvm.emit_c_interface} {
  %c0 = arith.constant 0 : index
  %one = arith.constant 1 : i32
  // the JSON, the text the index was scanned from; "?", "(none)" and "" after it
  %n0 = arith.index_cast %len : i64 to index
  %json = trikeshed.slice %t[%c0, %n0] : !text -> !text
  %end = arith.trunci %len : i64 to i32
  %end1 = arith.addi %end, %one : i32
  %zero = arith.constant 0 : i32
  %six = arith.constant 6 : i32
  %qmark = trikeshed.j %end, %one : i32, i32 -> !tp
  %none = trikeshed.j %end1, %six : i32, i32 -> !tp
  %empty = trikeshed.j %end, %zero : i32, i32 -> !tp
  // the options: the elements of the array, each as its row (DirectChildren)
  %k2 = trikeshed.key 2 : !ik
  %kc = trikeshed.column %rows[%k2] : !ix, !ik -> !pieces
  %fc = trikeshed.at %kc[%opts] : !pieces, i64 -> !tp
  %f = trikeshed.first %fc : !tp -> i32
  %n = trikeshed.second %fc : !tp -> i32
  %fi = arith.index_cast %f : i32 to index
  %ni = arith.index_cast %n : i32 to index
  %options = trikeshed.slice %kids[%fi, %ni] : !s32 -> !s32
  %obj = trikeshed.alpha %options : !s32 -> !s64 {
  ^bb0(%o: i32):
    %r = arith.extui %o : i32 to i64
    trikeshed.yield %r : i64
  }
  // each option's members by name: path, valueShown, value, state, kind, declarations, description
  %path, %shown, %value, %state, %kind, %decl, %desc = func.call @opt_members(%rows, %kids, %json, %opts)
      : (!ix, !s32, !text, i64) -> (!s32, !s32, !s32, !s32, !s32, !s32, !s32)
  // the cells: section, value (when shown), state, kind, module
  %section, %val, %st, %kin, %module = func.call @opt_cells(%rows, %kids, %json, %path, %shown, %value, %state, %kind,
      %decl, %qmark, %none, %empty)
      : (!ix, !s32, !text, !s32, !s32, !s32, !s32, !s32, !s32, !tp, !tp, !tp)
      -> (!pieces, !pieces, !pieces, !pieces, !pieces)
  // the keys and what a row is searched by
  %keys, %key, %hay, %hayAt = func.call @opt_text(%rows, %kids, %json, %path, %desc, %empty)
      : (!ix, !s32, !text, !s32, !s32, !tp) -> (!text, !pieces, !text, !pieces)
  // the coded columns: codes in the order of the names, the pieces in the JSON and "?(none)" after it
  %code0, %dict0 = func.call @col_code(%t, %section) : (!text, !pieces) -> (!s32, !pieces)
  %code1, %dict1 = func.call @col_code(%t, %kin) : (!text, !pieces) -> (!s32, !pieces)
  %code2, %dict2 = func.call @col_code(%t, %st) : (!text, !pieces) -> (!s32, !pieces)
  %code3, %dict3 = func.call @col_code(%t, %module) : (!text, !pieces) -> (!s32, !pieces)
  // what a what-if changed (none yet), what the query matched (all), each row's base row (none yet)
  %whatif = trikeshed.series %ni : !s32 {
  ^bb0(%i: index):
    trikeshed.yield %zero : i32
  }
  %match = trikeshed.series %ni : !s32 {
  ^bb0(%i: index):
    trikeshed.yield %one : i32
  }
  %baseOf = trikeshed.series %ni : !s32 {
  ^bb0(%i: index):
    %unset = arith.constant -1 : i32
    trikeshed.yield %unset : i32
  }
  // the rows in the order of their keys, for the join with another corpus
  %order = func.call @col_order(%keys, %key) : (!text, !pieces) -> !s32
  return %obj, %val, %st, %keys, %key, %hay, %hayAt, %code0, %code1, %code2, %code3, %whatif, %match,
      %dict0, %dict1, %dict2, %dict3, %order, %baseOf
      : !s64, !pieces, !pieces, !text, !pieces, !text, !pieces, !s32, !s32, !s32, !s32, !s32, !s32,
        !pieces, !pieces, !pieces, !pieces, !s32, !s32
}
