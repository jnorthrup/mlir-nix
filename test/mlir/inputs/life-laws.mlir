// Each local law of the life dialect, broken once (test/mlir/life.mlir runs this with --verify-diagnostics).

func.func @admission_answer_dropped(%c: !life.chan<i32>, %v: i32) {
  life.supervise {
    // expected-error @+1 {{drops the answer of an admission}}
    %ok = life.send %v to %c : i32 to !life.chan<i32>
  }
  return
}

// -----

func.func @admission_of_another_type(%c: !life.chan<i32>, %v: i64) {
  life.supervise {
    // expected-error @+1 {{offers a value of the channel's element type}}
    %ok = life.send %v to %c : i64 to !life.chan<i32>
    %x = arith.select %ok, %v, %v : i64
  }
  return
}

// -----

func.func @detached_work() {
  // expected-error @+1 {{is owned by no supervisor}}
  %j = life.launch : !life.job<none> {
  }
  return
}

// -----

func.func @buffer_touched_while_lent(%ring: !life.owned<i64>, %fd: i32) {
  life.supervise {
    %buf = life.acquire @buffer_16k() release @buffer_free : () -> !life.owned<memref<16384xi8>>
    // expected-error @+1 {{lends operand 2 to the kernel, and it is used before the job is joined}}
    %recv = life.submit @uring_recv(%ring, %fd, %buf) lent [2]
      : (!life.owned<i64>, i32, !life.owned<memref<16384xi8>>) -> !life.job<i32>
    %again = life.submit @uring_recv(%ring, %fd, %buf) : (!life.owned<i64>, i32, !life.owned<memref<16384xi8>>) -> !life.job<i32>
    %n = life.join %recv : !life.job<i32> -> i32
    %m = life.join %again : !life.job<i32> -> i32
  }
  return
}

// -----

life.key @K : () -> !life.element<@K> {
  life.opened
}

func.func @used_after_drain() {
  life.supervise {
    %e = life.open @K() : () -> !life.element<@K>
    // expected-error @+1 {{drains an element that is used after it}}
    life.drain %e : !life.element<@K>
    life.drain %e : !life.element<@K>
  }
  return
}

// -----

func.func @order_of_what_was_not_acquired(%a: !life.owned<i64>, %b: !life.owned<i64>) {
  life.supervise {
    // expected-error @+1 {{orders two resources acquired with life.acquire}}
    life.before %a, %b : !life.owned<i64>, !life.owned<i64>
  }
  return
}

// -----

func.func @join_without_the_result(%ring: !life.owned<i64>, %fd: i32) {
  life.supervise {
    %recv = life.submit @uring_recv(%ring, %fd) : (!life.owned<i64>, i32) -> !life.job<i32>
    // expected-error @+1 {{gives the job's result: one}}
    life.join %recv : !life.job<i32>
  }
  return
}

// -----

func.func @open_of_no_key() {
  life.supervise {
    // expected-error @+1 {{opens @Nowhere, which is no life.key}}
    %e = life.open @Nowhere() : () -> !life.element<@Nowhere>
  }
  return
}

// -----

// expected-error @+1 {{opens '!life.element<@Bad>' first}}
life.key @Bad : () -> i32 {
  life.opened
}

// -----

func.func @loop_of_another_type(%c: !life.chan<i32>) {
  life.supervise {
    // expected-error @+1 {{takes one value of the channel's element type}}
    life.for_each %c : !life.chan<i32> {
    ^bb0(%x: i64):
    }
  }
  return
}

// -----

func.func @no_state_to_read(%c: !life.chan<i32>) {
  // expected-error @+1 {{unregistered operation 'life.is_closed'}}
  %closed = "life.is_closed"(%c) : (!life.chan<i32>) -> i1
  return
}
