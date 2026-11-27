// What a lane refuses (trikeshed-lower-cursors says which law is broken, at the op that breaks it).  A lane lives in the
// frame of the function that makes it: it is made once, in the entry block, and never returned.  A row is one cell a
// column; at, anchor and drain read one column (trikeshed.take gives one, by a constant index); an anchor's cells are
// integers, a cell never forced being 0.  A series drains into a lane of one column of its own element, and a lane
// drains into cells, not into another lane.
//
// RUN: mlnix-opt %s --split-input-file --trikeshed-lower-cursors --verify-diagnostics

func.func @in_a_loop(%n: index) {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  scf.for %i = %c0 to %n step %c1 {
    // expected-error @+2 {{makes a lane of integer or float columns, in the entry block of its function}}
    // expected-error @+1 {{failed to legalize operation 'trikeshed.lane'}}
    %l = trikeshed.lane : !trikeshed.lane<i64>
  }
  return
}

// -----

func.func @returned() -> !trikeshed.lane<i64> {
  // expected-error @+2 {{is in a function that returns a lane}}
  // expected-error @+1 {{failed to legalize operation 'trikeshed.lane'}}
  %l = trikeshed.lane : !trikeshed.lane<i64>
  return %l : !trikeshed.lane<i64>
}

// -----

func.func @halves_apart() {
  // expected-error @+2 {{makes a lane of integer or float columns}}
  // expected-error @+1 {{failed to legalize operation 'trikeshed.lane'}}
  %l = trikeshed.lane : !trikeshed.lane<!trikeshed.twin<i64>>
  return
}

// -----

func.func @a_cell_short(%x: i64) -> index {
  %l = trikeshed.lane : !trikeshed.lane<i64, i8>
  // expected-error @+2 {{takes one cell a column of its lane, of the column's type}}
  // expected-error @+1 {{failed to legalize operation 'trikeshed.append'}}
  %r = trikeshed.append %l, %x : !trikeshed.lane<i64, i8>, i64 -> index
  return %r : index
}

// -----

func.func @a_cell_of_another_type(%x: i32) -> index {
  %l = trikeshed.lane : !trikeshed.lane<i64>
  // expected-error @+2 {{takes one cell a column of its lane, of the column's type}}
  // expected-error @+1 {{failed to legalize operation 'trikeshed.append'}}
  %r = trikeshed.append %l, %x : !trikeshed.lane<i64>, i32 -> index
  return %r : index
}

// -----

func.func @two_columns_read(%l: !trikeshed.lane<i64, i8>, %i: index) -> i64 {
  // expected-error @+2 {{reads a lane of one column}}
  // expected-error @+1 {{failed to legalize operation 'trikeshed.at'}}
  %x = trikeshed.at %l[%i] : !trikeshed.lane<i64, i8>, index -> i64
  return %x : i64
}

// -----

func.func @a_column_by_a_variable(%l: !trikeshed.lane<i64, i64>, %c: index) -> index {
  // expected-error @+2 {{takes a lane's column by a constant index}}
  // expected-error @+1 {{failed to legalize operation 'trikeshed.take'}}
  %col = trikeshed.take %l[%c] : !trikeshed.lane<i64, i64> -> !trikeshed.lane<i64>
  %n = trikeshed.size %col : !trikeshed.lane<i64>
  return %n : index
}

// -----

func.func @float_cells(%l: !trikeshed.lane<f64>, %i: index) -> f64 {
  // expected-error @+2 {{anchors in a lane of one integer column}}
  // expected-error @+1 {{failed to legalize operation 'trikeshed.anchor'}}
  %x = trikeshed.anchor %l[%i] : !trikeshed.lane<f64> -> f64 {
    %one = arith.constant 1.0 : f64
    trikeshed.yield %one : f64
  }
  return %x : f64
}

// -----

func.func @two_columns_drained(%l: !trikeshed.lane<i64, i8>, %into: memref<?xi64>) -> index {
  // expected-error @+2 {{drains a lane of one column}}
  // expected-error @+1 {{failed to legalize operation 'trikeshed.drain'}}
  %n = trikeshed.drain %l, %into : !trikeshed.lane<i64, i8>, memref<?xi64> -> index
  return %n : index
}

// -----

func.func @a_series_into_two_columns(%xs: !trikeshed.series<i64>, %l: !trikeshed.lane<i64, i8>) -> index {
  // expected-error @+2 {{drains a series into a lane of one column of its element}}
  // expected-error @+1 {{failed to legalize operation 'trikeshed.drain'}}
  %n = trikeshed.drain %xs, %l : !trikeshed.series<i64>, !trikeshed.lane<i64, i8> -> index
  return %n : index
}

// -----

func.func @a_series_of_another_element(%xs: !trikeshed.series<i32>, %l: !trikeshed.lane<i8>) -> index {
  // expected-error @+2 {{drains a series into a lane of one column of its element}}
  // expected-error @+1 {{failed to legalize operation 'trikeshed.drain'}}
  %n = trikeshed.drain %xs, %l : !trikeshed.series<i32>, !trikeshed.lane<i8> -> index
  return %n : index
}

// -----

func.func @a_lane_into_a_lane(%from: !trikeshed.lane<i8>, %l: !trikeshed.lane<i8>) -> index {
  // expected-error @+2 {{drains a lane of one column, into a memref or into a buffer of its own}}
  // expected-error @+1 {{failed to legalize operation 'trikeshed.drain'}}
  %n = trikeshed.drain %from, %l : !trikeshed.lane<i8>, !trikeshed.lane<i8> -> index
  return %n : index
}
