// The life dialect (include/NixDialect/Life.td, docs/LIFE.md) on the lifetime it was drawn from: mini-luci's server
// (mini-luci.cpp, serve()).  It is registered, parsed, printed and verified; inputs/life-laws.mlir breaks each local
// law the op verifiers check.  The laws over a whole function (life-verify) and the lowerings are not built.
// RUN: mlnix-opt %s | mlnix-opt | FileCheck %s
// RUN: mlnix-opt %S/inputs/life-laws.mlir --split-input-file --verify-diagnostics

// CHECK-LABEL: life.key @MiniLuci : (i32) -> !life.element<@MiniLuci>
// CHECK: life.acquire @tcp_listen(%{{.*}}) release @close_listener : (i32) -> !life.chan<i32>
// CHECK: life.before
// CHECK: life.for_each
// CHECK: life.send
// CHECK: life.submit @uring_recv({{.*}}) lent [2]
// CHECK: life.opened
// CHECK-LABEL: func.func @main
// CHECK: life.open @MiniLuci
// CHECK: life.drain

// The server.  Its body is its supervisor: the listener, the ring and the request channel are its; the acceptor and the
// responder are its jobs.  Nothing says whether it is running: it exists opened, and drain ends it.
life.key @MiniLuci : (i32) -> !life.element<@MiniLuci> {
^bb0(%port: i32):
  // The kernel admits connections into the listener; closing it cancels the pending accept: admission stops.
  %conns = life.acquire @tcp_listen(%port) release @close_listener : (i32) -> !life.chan<i32>
  %ring = life.acquire @uring_queue_init() release @uring_queue_exit : () -> !life.owned<i64>
  // Acquired first, released first: the ring's teardown is deferred, and a listener released after it stays bound
  // (the port `make check` found still listening after the server had gone).
  life.before %conns, %ring : !life.chan<i32>, !life.owned<i64>
  %requests = life.channel 64 : !life.chan<i32>

  // The acceptor: each accepted connection is offered to the responder.  When the listener is closed and empty, the
  // loop ends, the job completes, and %requests -- whose only sender it is -- closes.
  %acceptor = life.launch : !life.job<none> {
    life.for_each %conns : !life.chan<i32> {
    ^bb0(%fd: i32):
      %admitted = life.send %fd to %requests : i32 to !life.chan<i32>
      // a connection refused at admission is closed, not dropped
      scf.if %admitted {
      } else {
        %c = life.submit @uring_close(%ring, %fd) : (!life.owned<i64>, i32) -> !life.job<none>
        life.join %c : !life.job<none>
      }
    }
  }

  // The responder: answers every admitted connection; its loop ends when %requests is closed and empty.
  %responder = life.launch : !life.job<none> {
    life.for_each %requests : !life.chan<i32> {
    ^bb0(%fd: i32):
      // owned by this iteration, released when it ends
      %buf = life.acquire @buffer_16k() release @buffer_free : () -> !life.owned<memref<16384xi8>>
      // the buffer is the kernel's from the submission until the join
      %recv = life.submit @uring_recv(%ring, %fd, %buf) lent [2]
        : (!life.owned<i64>, i32, !life.owned<memref<16384xi8>>) -> !life.job<i32>
      %n = life.join %recv : !life.job<i32> -> i32
      %send = life.submit @uring_send_reply(%ring, %fd, %buf, %n) lent [2]
        : (!life.owned<i64>, i32, !life.owned<memref<16384xi8>>, i32) -> !life.job<none>
      life.join %send : !life.job<none>
      %closed = life.submit @uring_close(%ring, %fd) : (!life.owned<i64>, i32) -> !life.job<none>
      life.join %closed : !life.job<none>
    }
  }

  // Admission from outside is the kernel's: the element hands out no channel of its own.
  life.opened
}

// The owner: open the server, wait for SIGTERM or SIGINT (a signalfd read, on the kernel's terms like any effect), and
// drain.  Drain closes the listener; the acceptor ends, %requests closes, the responder answers what was admitted and
// ends; the listener is released, then the ring.
func.func @main(%port: i32) {
  life.supervise {
    %server = life.open @MiniLuci(%port) : (i32) -> !life.element<@MiniLuci>
    %sig = life.acquire @signalfd_term_int() release @close_fd : () -> !life.owned<i32>
    %got = life.submit @read_siginfo(%sig) : (!life.owned<i32>) -> !life.job<none>
    life.join %got : !life.job<none>
    life.drain %server : !life.element<@MiniLuci>
  }
  return
}
