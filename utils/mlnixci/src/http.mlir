// http.mlir -- HTTP/1.1 over one io_uring (Connection: close, one request a connection), and main.
//
// A connection is a record: its descriptor, the request's bytes as they arrive (a growing series), the reply (the
// builder's buffer taken whole, its head written into the room in front of the body), and how much of it is sent.  An
// operation's user data is the connection's address with the operation in its low bits.  SIGTERM or SIGINT, read from
// the same ring, drains it: the accept is cancelled, the admitted connections are answered, the listener is closed.
//
//   connection: 0 fd  1 in  2 in's length  3 in's room  4 out  5 out's end  6 sent up to  |  64: 16 KiB to receive into

llvm.func @calloc(i64, i64) -> !llvm.ptr
llvm.func @malloc(i64) -> !llvm.ptr
llvm.func @free(!llvm.ptr)
llvm.func @memcpy(!llvm.ptr, !llvm.ptr, i64) -> !llvm.ptr
llvm.func @strlen(!llvm.ptr) -> i64
llvm.func @strcmp(!llvm.ptr, !llvm.ptr) -> i32
llvm.func @atoi(!llvm.ptr) -> i32
llvm.func @getenv(!llvm.ptr) -> !llvm.ptr
llvm.func @dprintf(i32, !llvm.ptr, ...) -> i32
llvm.func @socket(i32, i32, i32) -> i32
llvm.func @setsockopt(i32, i32, i32, !llvm.ptr, i32) -> i32
llvm.func @bind(i32, !llvm.ptr, i32) -> i32
llvm.func @listen(i32, i32) -> i32
llvm.func @close(i32) -> i32
llvm.func @unlink(!llvm.ptr) -> i32
llvm.func @sigemptyset(!llvm.ptr) -> i32
llvm.func @sigaddset(!llvm.ptr, i32) -> i32
llvm.func @sigprocmask(i32, !llvm.ptr, !llvm.ptr) -> i32
llvm.func @signalfd(i32, !llvm.ptr, i32) -> i32
llvm.func @io_uring_queue_init(i32, !llvm.ptr, i32) -> i32
llvm.func @io_uring_queue_exit(!llvm.ptr)
llvm.func @io_uring_get_sqe(!llvm.ptr) -> !llvm.ptr
llvm.func @io_uring_submit(!llvm.ptr) -> i32
llvm.func @io_uring_submit_and_wait(!llvm.ptr, i32) -> i32
llvm.func @io_uring_peek_cqe(!llvm.ptr, !llvm.ptr) -> i32
llvm.func @io_uring_cqe_seen(!llvm.ptr, !llvm.ptr)
llvm.func @io_uring_prep_accept(!llvm.ptr, i32, !llvm.ptr, !llvm.ptr, i32)
llvm.func @io_uring_prep_recv(!llvm.ptr, i32, !llvm.ptr, i64, i32)
llvm.func @io_uring_prep_send(!llvm.ptr, i32, !llvm.ptr, i64, i32)
llvm.func @io_uring_prep_close(!llvm.ptr, i32)
llvm.func @io_uring_prep_read(!llvm.ptr, i32, !llvm.ptr, i32, i64)
llvm.func @io_uring_prep_cancel64(!llvm.ptr, i64, i32)
llvm.func @io_uring_sqe_set_data64(!llvm.ptr, i64)

func.func private @tw(i64, i64) -> i64
func.func private @off(!llvm.ptr, i64) -> !llvm.ptr
func.func private @view(!llvm.ptr, !llvm.ptr, i64)
func.func private @ob_len() -> i64
func.func private @ob_take() -> !llvm.ptr
func.func private @getp(!llvm.ptr, i64) -> !llvm.ptr
func.func private @geti(!llvm.ptr, i64) -> i64
func.func private @setp(!llvm.ptr, i64, !llvm.ptr)
func.func private @seti(!llvm.ptr, i64, i64)
func.func private @grow(!llvm.ptr, !llvm.ptr, i64)
func.func private @api_init(!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr)
func.func private @api_status() -> i64
func.func private @api_html() -> i64
func.func private @route(!llvm.ptr, i64, i64, i64, i64)
func.func private @fail_with(i64, !llvm.ptr, i64)
func.func private @eval_settings(!llvm.ptr, !llvm.ptr, !llvm.ptr, i64)
func.func private @evaluate(!llvm.ptr)
func.func private @run_status() -> i64
func.func private @run_ms() -> f64
func.func private @run_out() -> !llvm.ptr
func.func private @run_out_n() -> i64
func.func private @run_err() -> !llvm.ptr
func.func private @run_err_n() -> i64
func.func private @corpus_load(!llvm.ptr, i64, f64) -> !llvm.ptr
func.func private @corpus_why() -> !llvm.ptr
func.func private @corpus_why_n() -> i64

llvm.mlir.global internal constant @lit12("request too large") : !llvm.array<17 x i8>
llvm.mlir.global internal constant @lit13("bad request line") : !llvm.array<16 x i8>
llvm.mlir.global internal constant @lit14("mlnixci: cannot listen on port %ld\0A\00") : !llvm.array<36 x i8>
llvm.mlir.global internal constant @lit15("mlnixci: http://[::]:%ld/  corpus=%s rows=%ld (mlnix %.0f ms)\0A\00") : !llvm.array<63 x i8>
llvm.mlir.global internal constant @lit16("mlnixci: drained\0A\00") : !llvm.array<18 x i8>
llvm.mlir.global internal constant @lit17("--arg\00") : !llvm.array<6 x i8>
llvm.mlir.global internal constant @lit18("--argstr\00") : !llvm.array<9 x i8>
llvm.mlir.global internal constant @lit19("--corpus\00") : !llvm.array<9 x i8>
llvm.mlir.global internal constant @lit20("--mlnix\00") : !llvm.array<8 x i8>
llvm.mlir.global internal constant @lit21("--page\00") : !llvm.array<7 x i8>
llvm.mlir.global internal constant @lit22("--state\00") : !llvm.array<8 x i8>
llvm.mlir.global internal constant @lit23("--port\00") : !llvm.array<7 x i8>
llvm.mlir.global internal constant @lit24("mlnix\00") : !llvm.array<6 x i8>
llvm.mlir.global internal constant @lit25("/tmp\00") : !llvm.array<5 x i8>
llvm.mlir.global internal constant @lit26("usage: mlnixci --corpus EVAL.nix --page index.html [--arg NAME EXPR | --argstr NAME STRING]... [--mlnix PATH] [--state DIR] [--port N]\0A\00") : !llvm.array<136 x i8>
llvm.mlir.global internal constant @lit27("RUNTIME_DIRECTORY\00") : !llvm.array<18 x i8>
llvm.mlir.global internal constant @lit28("/mlnixci-overlay.json\00") : !llvm.array<22 x i8>
llvm.mlir.global internal constant @lit31("/mlnixci-facet.json\00") : !llvm.array<20 x i8>
llvm.mlir.global internal constant @lit29("mlnixci: the corpus does not evaluate:\0A%.*s\00") : !llvm.array<44 x i8>
llvm.mlir.global internal constant @lit30("mlnixci: %.*s\0A\00") : !llvm.array<15 x i8>

llvm.mlir.global internal @ring() : !llvm.array<1024 x i8> {
  %0 = llvm.mlir.zero : !llvm.array<1024 x i8>
  llvm.return %0 : !llvm.array<1024 x i8>
}
llvm.mlir.global internal @siginfo() : !llvm.array<128 x i8> {
  %0 = llvm.mlir.zero : !llvm.array<128 x i8>
  llvm.return %0 : !llvm.array<128 x i8>
}
llvm.mlir.global internal @accepting(1 : i64) : i64
llvm.mlir.global internal @draining(0 : i64) : i64
llvm.mlir.global internal @admitted(0 : i64) : i64
llvm.mlir.global internal @listener(-1 : i64) : i64

func.func @load_g(%p: !llvm.ptr) -> i64 {
  %v = llvm.load %p : !llvm.ptr -> i64
  return %v : i64
}

func.func @add_g(%p: !llvm.ptr, %d: i64) {
  %v = llvm.load %p : !llvm.ptr -> i64
  %w = arith.addi %v, %d : i64
  llvm.store %w, %p : i64, !llvm.ptr
  return
}

// a submission entry: the next free one, after submitting what is queued when there is none
func.func @sqe() -> !llvm.ptr {
  %ring = llvm.mlir.addressof @ring : !llvm.ptr
  %s = llvm.call @io_uring_get_sqe(%ring) : (!llvm.ptr) -> !llvm.ptr
  %null = llvm.mlir.zero : !llvm.ptr
  %full = llvm.icmp "eq" %s, %null : !llvm.ptr
  %r = scf.if %full -> (!llvm.ptr) {
    %k = llvm.call @io_uring_submit(%ring) : (!llvm.ptr) -> i32
    %s2 = llvm.call @io_uring_get_sqe(%ring) : (!llvm.ptr) -> !llvm.ptr
    scf.yield %s2 : !llvm.ptr
  } else {
    scf.yield %s : !llvm.ptr
  }
  return %r : !llvm.ptr
}

// operations: 1 accept, 2 recv, 3 send, 4 close, 5 signal, 6 cancel
func.func @tag(%c: !llvm.ptr, %op: i64) -> i64 {
  %a = llvm.ptrtoint %c : !llvm.ptr to i64
  %t = arith.ori %a, %op : i64
  return %t : i64
}

func.func @fd_of(%c: !llvm.ptr) -> i32 {
  %c0 = arith.constant 0 : i64
  %fd = func.call @geti(%c, %c0) : (!llvm.ptr, i64) -> i64
  %r = arith.trunci %fd : i64 to i32
  return %r : i32
}

func.func @accept_next() {
  %s = func.call @sqe() : () -> !llvm.ptr
  %pl = llvm.mlir.addressof @listener : !llvm.ptr
  %l = llvm.load %pl : !llvm.ptr -> i64
  %lfd = arith.trunci %l : i64 to i32
  %null = llvm.mlir.zero : !llvm.ptr
  %cloexec = arith.constant 524288 : i32
  llvm.call @io_uring_prep_accept(%s, %lfd, %null, %null, %cloexec) : (!llvm.ptr, i32, !llvm.ptr, !llvm.ptr, i32) -> ()
  %c1 = arith.constant 1 : i64
  llvm.call @io_uring_sqe_set_data64(%s, %c1) : (!llvm.ptr, i64) -> ()
  return
}

func.func @recv_more(%c: !llvm.ptr) {
  %s = func.call @sqe() : () -> !llvm.ptr
  %fd = func.call @fd_of(%c) : (!llvm.ptr) -> i32
  %c64 = arith.constant 64 : i64
  %buf = func.call @off(%c, %c64) : (!llvm.ptr, i64) -> !llvm.ptr
  %room = arith.constant 16384 : i64
  %z = arith.constant 0 : i32
  llvm.call @io_uring_prep_recv(%s, %fd, %buf, %room, %z) : (!llvm.ptr, i32, !llvm.ptr, i64, i32) -> ()
  %c2 = arith.constant 2 : i64
  %t = func.call @tag(%c, %c2) : (!llvm.ptr, i64) -> i64
  llvm.call @io_uring_sqe_set_data64(%s, %t) : (!llvm.ptr, i64) -> ()
  return
}

func.func @send_more(%c: !llvm.ptr) {
  %s = func.call @sqe() : () -> !llvm.ptr
  %fd = func.call @fd_of(%c) : (!llvm.ptr) -> i32
  %c4 = arith.constant 4 : i64
  %c5 = arith.constant 5 : i64
  %c6 = arith.constant 6 : i64
  %out = func.call @getp(%c, %c4) : (!llvm.ptr, i64) -> !llvm.ptr
  %end = func.call @geti(%c, %c5) : (!llvm.ptr, i64) -> i64
  %sent = func.call @geti(%c, %c6) : (!llvm.ptr, i64) -> i64
  %from = func.call @off(%out, %sent) : (!llvm.ptr, i64) -> !llvm.ptr
  %n = arith.subi %end, %sent : i64
  %nosignal = arith.constant 16384 : i32
  llvm.call @io_uring_prep_send(%s, %fd, %from, %n, %nosignal) : (!llvm.ptr, i32, !llvm.ptr, i64, i32) -> ()
  %c3 = arith.constant 3 : i64
  %t = func.call @tag(%c, %c3) : (!llvm.ptr, i64) -> i64
  llvm.call @io_uring_sqe_set_data64(%s, %t) : (!llvm.ptr, i64) -> ()
  return
}

func.func @close_conn(%c: !llvm.ptr) {
  %s = func.call @sqe() : () -> !llvm.ptr
  %fd = func.call @fd_of(%c) : (!llvm.ptr) -> i32
  llvm.call @io_uring_prep_close(%s, %fd) : (!llvm.ptr, i32) -> ()
  %c4 = arith.constant 4 : i64
  %t = func.call @tag(%c, %c4) : (!llvm.ptr, i64) -> i64
  llvm.call @io_uring_sqe_set_data64(%s, %t) : (!llvm.ptr, i64) -> ()
  return
}

// the reply made by the route: its head (text.mlir's head_reply: the status, its reason, the type, the body's length)
// written into the room in front of its body, then sent
llvm.func @_mlir_ciface_head_reply(i64, i64, i64, !llvm.ptr) -> i64
func.func @respond(%c: !llvm.ptr) {
  %c4 = arith.constant 4 : i64
  %c5 = arith.constant 5 : i64
  %c6 = arith.constant 6 : i64
  %gap = arith.constant 256 : i64
  %status = func.call @api_status() : () -> i64
  %html = func.call @api_html() : () -> i64
  %total = func.call @ob_len() : () -> i64
  %buf = func.call @ob_take() : () -> !llvm.ptr
  %bodyLen = arith.subi %total, %gap : i64
  %one = arith.constant 1 : i32
  %head = llvm.alloca %one x !llvm.array<256 x i8> : (i32) -> !llvm.ptr
  %into = llvm.alloca %one x !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)> : (i32) -> !llvm.ptr
  func.call @view(%into, %head, %gap) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %hl = llvm.call @_mlir_ciface_head_reply(%status, %html, %bodyLen, %into) : (i64, i64, i64, !llvm.ptr) -> i64
  %start = arith.subi %gap, %hl : i64
  %dst = func.call @off(%buf, %start) : (!llvm.ptr, i64) -> !llvm.ptr
  %x = llvm.call @memcpy(%dst, %head, %hl) : (!llvm.ptr, !llvm.ptr, i64) -> !llvm.ptr
  func.call @setp(%c, %c4, %buf) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  func.call @seti(%c, %c5, %total) : (!llvm.ptr, i64, i64) -> ()
  func.call @seti(%c, %c6, %start) : (!llvm.ptr, i64, i64) -> ()
  func.call @send_more(%c) : (!llvm.ptr) -> ()
  return
}

// Answer once the head and the body (Content-Length) have arrived; false while more is to come.  The framing is
// request.mlir's rq_frame (kursive combinators walked over the request where it lies): not all here, too large (413),
// no request line (400), or the method, path, body and the route they name.
llvm.func @_mlir_ciface_rq_frame(!llvm.ptr, !llvm.ptr) -> i64
func.func @complete(%c: !llvm.ptr) -> i1 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %c5 = arith.constant 5 : i64
  %c6 = arith.constant 6 : i64
  %c7 = arith.constant 7 : i64
  %true = arith.constant true
  %false = arith.constant false
  %one = arith.constant 1 : i32
  %in = func.call @getp(%c, %c1) : (!llvm.ptr, i64) -> !llvm.ptr
  %n = func.call @geti(%c, %c2) : (!llvm.ptr, i64) -> i64
  %d = llvm.alloca %one x !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)> : (i32) -> !llvm.ptr
  func.call @view(%d, %in, %n) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %out = llvm.alloca %one x !llvm.array<7 x i64> : (i32) -> !llvm.ptr
  %od = llvm.alloca %one x !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)> : (i32) -> !llvm.ptr
  func.call @view(%od, %out, %c7) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %v = llvm.call @_mlir_ciface_rq_frame(%d, %od) : (!llvm.ptr, !llvm.ptr) -> i64
  %which = arith.index_cast %v : i64 to index
  %done = scf.index_switch %which -> i1
  case 0 {
    scf.yield %false : i1
  }
  case 1 {
    %c413 = arith.constant 413 : i64
    %big = llvm.mlir.addressof @lit12 : !llvm.ptr
    %big_n = arith.constant 17 : i64
    func.call @fail_with(%c413, %big, %big_n) : (i64, !llvm.ptr, i64) -> ()
    func.call @respond(%c) : (!llvm.ptr) -> ()
    scf.yield %true : i1
  }
  case 2 {
    %c400 = arith.constant 400 : i64
    %badLine = llvm.mlir.addressof @lit13 : !llvm.ptr
    %badLine_n = arith.constant 16 : i64
    func.call @fail_with(%c400, %badLine, %badLine_n) : (i64, !llvm.ptr, i64) -> ()
    func.call @respond(%c) : (!llvm.ptr) -> ()
    scf.yield %true : i1
  }
  default {
    %ms = func.call @geti(%out, %c0) : (!llvm.ptr, i64) -> i64
    %me = func.call @geti(%out, %c1) : (!llvm.ptr, i64) -> i64
    %ps = func.call @geti(%out, %c2) : (!llvm.ptr, i64) -> i64
    %pe = func.call @geti(%out, %c3) : (!llvm.ptr, i64) -> i64
    %bs = func.call @geti(%out, %c4) : (!llvm.ptr, i64) -> i64
    %be = func.call @geti(%out, %c5) : (!llvm.ptr, i64) -> i64
    %route = func.call @geti(%out, %c6) : (!llvm.ptr, i64) -> i64
    %method = func.call @tw(%ms, %me) : (i64, i64) -> i64
    %path = func.call @tw(%ps, %pe) : (i64, i64) -> i64
    %body = func.call @tw(%bs, %be) : (i64, i64) -> i64
    func.call @route(%in, %method, %path, %body, %route) : (!llvm.ptr, i64, i64, i64, i64) -> ()
    func.call @respond(%c) : (!llvm.ptr) -> ()
    scf.yield %true : i1
  }
  return %done : i1
}

// one completion
func.func @handle(%d: i64, %res: i32) {
  %c1 = arith.constant 1 : i64
  %c7 = arith.constant 7 : i64
  %z32 = arith.constant 0 : i32
  %op = arith.andi %d, %c7 : i64
  %m = arith.constant -8 : i64
  %addr = arith.andi %d, %m : i64
  %c = llvm.inttoptr %addr : i64 to !llvm.ptr
  %pAcc = llvm.mlir.addressof @accepting : !llvm.ptr
  %pDrain = llvm.mlir.addressof @draining : !llvm.ptr
  %pAdm = llvm.mlir.addressof @admitted : !llvm.ptr
  %which = arith.index_cast %op : i64 to index
  scf.index_switch %which
  case 1 {
    %ok = arith.cmpi sge, %res, %z32 : i32
    scf.if %ok {
      %size = arith.constant 16448 : i64
      %nc = llvm.call @calloc(%c1, %size) : (i64, i64) -> !llvm.ptr
      %fd = arith.extsi %res : i32 to i64
      %c0 = arith.constant 0 : i64
      func.call @seti(%nc, %c0, %fd) : (!llvm.ptr, i64, i64) -> ()
      func.call @add_g(%pAdm, %c1) : (!llvm.ptr, i64) -> ()
      func.call @recv_more(%nc) : (!llvm.ptr) -> ()
    }
    %draining = func.call @load_g(%pDrain) : (!llvm.ptr) -> i64
    %c0b = arith.constant 0 : i64
    %isDraining = arith.cmpi ne, %draining, %c0b : i64
    scf.if %isDraining {
      // cancelled, or a last connection that is still answered
      llvm.store %c0b, %pAcc : i64, !llvm.ptr
    } else {
      func.call @accept_next() : () -> ()
    }
    scf.yield
  }
  case 5 {
    llvm.store %c1, %pDrain : i64, !llvm.ptr
    %s = func.call @sqe() : () -> !llvm.ptr
    llvm.call @io_uring_prep_cancel64(%s, %c1, %z32) : (!llvm.ptr, i64, i32) -> ()
    %c6 = arith.constant 6 : i64
    llvm.call @io_uring_sqe_set_data64(%s, %c6) : (!llvm.ptr, i64) -> ()
    scf.yield
  }
  case 2 {
    %got = arith.cmpi sgt, %res, %z32 : i32
    scf.if %got {
      %n = arith.extsi %res : i32 to i64
      %c8 = arith.constant 8 : i64
      %c64 = arith.constant 64 : i64
      %series = func.call @off(%c, %c8) : (!llvm.ptr, i64) -> !llvm.ptr
      %buf = func.call @off(%c, %c64) : (!llvm.ptr, i64) -> !llvm.ptr
      func.call @grow(%series, %buf, %n) : (!llvm.ptr, !llvm.ptr, i64) -> ()
      %c2 = arith.constant 2 : i64
      %len = func.call @geti(%c, %c2) : (!llvm.ptr, i64) -> i64
      %limit = arith.constant 1114112 : i64
      %over = arith.cmpi sgt, %len, %limit : i64
      scf.if %over {
        %c413 = arith.constant 413 : i64
        %big = llvm.mlir.addressof @lit12 : !llvm.ptr
        %big_n = arith.constant 17 : i64
        func.call @fail_with(%c413, %big, %big_n) : (i64, !llvm.ptr, i64) -> ()
        func.call @respond(%c) : (!llvm.ptr) -> ()
      } else {
        %answered = func.call @complete(%c) : (!llvm.ptr) -> i1
        scf.if %answered {
        } else {
          func.call @recv_more(%c) : (!llvm.ptr) -> ()
        }
      }
    } else {
      func.call @close_conn(%c) : (!llvm.ptr) -> ()
    }
    scf.yield
  }
  case 3 {
    %got = arith.cmpi sgt, %res, %z32 : i32
    scf.if %got {
      %n = arith.extsi %res : i32 to i64
      %c5 = arith.constant 5 : i64
      %c6 = arith.constant 6 : i64
      %sent = func.call @geti(%c, %c6) : (!llvm.ptr, i64) -> i64
      %s2 = arith.addi %sent, %n : i64
      func.call @seti(%c, %c6, %s2) : (!llvm.ptr, i64, i64) -> ()
      %end = func.call @geti(%c, %c5) : (!llvm.ptr, i64) -> i64
      %more = arith.cmpi slt, %s2, %end : i64
      scf.if %more {
        func.call @send_more(%c) : (!llvm.ptr) -> ()
      } else {
        func.call @close_conn(%c) : (!llvm.ptr) -> ()
      }
    } else {
      func.call @close_conn(%c) : (!llvm.ptr) -> ()
    }
    scf.yield
  }
  case 4 {
    %c1b = arith.constant 1 : i64
    %c4 = arith.constant 4 : i64
    %in = func.call @getp(%c, %c1b) : (!llvm.ptr, i64) -> !llvm.ptr
    llvm.call @free(%in) : (!llvm.ptr) -> ()
    %out = func.call @getp(%c, %c4) : (!llvm.ptr, i64) -> !llvm.ptr
    llvm.call @free(%out) : (!llvm.ptr) -> ()
    llvm.call @free(%c) : (!llvm.ptr) -> ()
    %m1 = arith.constant -1 : i64
    func.call @add_g(%pAdm, %m1) : (!llvm.ptr, i64) -> ()
    scf.yield
  }
  default {
    scf.yield
  }
  return
}

func.func @serve(%port: i64, %corpus: !llvm.ptr, %rows: i64, %ms: f64, %ovfile: !llvm.ptr) -> i32 {
  %z32 = arith.constant 0 : i32
  %one = arith.constant 1 : i32
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %af = arith.constant 10 : i32
  %stream = arith.constant 524289 : i32
  %lfd = llvm.call @socket(%af, %stream, %z32) : (i32, i32, i32) -> i32
  %pl = llvm.mlir.addressof @listener : !llvm.ptr
  %lfd64 = arith.extsi %lfd : i32 to i64
  llvm.store %lfd64, %pl : i64, !llvm.ptr
  %on = llvm.alloca %one x i32 : (i32) -> !llvm.ptr
  llvm.store %one, %on : i32, !llvm.ptr
  %offp = llvm.alloca %one x i32 : (i32) -> !llvm.ptr
  llvm.store %z32, %offp : i32, !llvm.ptr
  %four = arith.constant 4 : i32
  %solSocket = arith.constant 1 : i32
  %reuse = arith.constant 2 : i32
  %ipv6 = arith.constant 41 : i32
  %v6only = arith.constant 26 : i32
  %s1 = llvm.call @setsockopt(%lfd, %solSocket, %reuse, %on, %four) : (i32, i32, i32, !llvm.ptr, i32) -> i32
  %s2 = llvm.call @setsockopt(%lfd, %ipv6, %v6only, %offp, %four) : (i32, i32, i32, !llvm.ptr, i32) -> i32
  // sockaddr_in6 { family u16, port u16 (network order), flowinfo u32, addr [16], scope u32 }: any address
  %addr = llvm.alloca %one x !llvm.array<32 x i8> : (i32) -> !llvm.ptr
  %zeros = llvm.mlir.zero : !llvm.array<32 x i8>
  llvm.store %zeros, %addr : !llvm.array<32 x i8>, !llvm.ptr
  %fam = arith.constant 10 : i16
  llvm.store %fam, %addr : i16, !llvm.ptr
  %p16 = arith.trunci %port : i64 to i16
  %c8i16 = arith.constant 8 : i16
  %hi = arith.shrui %p16, %c8i16 : i16
  %lo = arith.shli %p16, %c8i16 : i16
  %be = arith.ori %hi, %lo : i16
  %pp = llvm.getelementptr %addr[2] : (!llvm.ptr) -> !llvm.ptr, i8
  llvm.store %be, %pp : i16, !llvm.ptr
  %len28 = arith.constant 28 : i32
  %b = llvm.call @bind(%lfd, %addr, %len28) : (i32, !llvm.ptr, i32) -> i32
  %backlog = arith.constant 64 : i32
  %l = llvm.call @listen(%lfd, %backlog) : (i32, i32) -> i32
  %bound = arith.cmpi eq, %b, %z32 : i32
  %listening = arith.cmpi eq, %l, %z32 : i32
  %up = arith.andi %bound, %listening : i1
  %ring = llvm.mlir.addressof @ring : !llvm.ptr
  %entries = arith.constant 256 : i32
  %qi = scf.if %up -> (i32) {
    %r = llvm.call @io_uring_queue_init(%entries, %ring, %z32) : (i32, !llvm.ptr, i32) -> i32
    scf.yield %r : i32
  } else {
    %two = arith.constant 2 : i32
    %fmtListen = llvm.mlir.addressof @lit14 : !llvm.ptr
    %fmtListen_n = arith.constant 38 : i64
    %x = llvm.call @dprintf(%two, %fmtListen, %port) vararg(!llvm.func<i32 (i32, ptr, ...)>) : (i32, !llvm.ptr, i64) -> i32
    %m = arith.constant -1 : i32
    scf.yield %m : i32
  }
  %ready = arith.cmpi eq, %qi, %z32 : i32
  %rc = scf.if %ready -> (i32) {
    %two = arith.constant 2 : i32
    %fmtUp = llvm.mlir.addressof @lit15 : !llvm.ptr
    %fmtUp_n = arith.constant 65 : i64
    %x = llvm.call @dprintf(%two, %fmtUp, %port, %corpus, %rows, %ms) vararg(!llvm.func<i32 (i32, ptr, ...)>) : (i32, !llvm.ptr, i64, !llvm.ptr, i64, f64) -> i32
    // SIGTERM and SIGINT are read from the ring
    %set = llvm.alloca %one x !llvm.array<256 x i8> : (i32) -> !llvm.ptr
    %e = llvm.call @sigemptyset(%set) : (!llvm.ptr) -> i32
    %term = arith.constant 15 : i32
    %int = arith.constant 2 : i32
    %a1 = llvm.call @sigaddset(%set, %term) : (!llvm.ptr, i32) -> i32
    %a2 = llvm.call @sigaddset(%set, %int) : (!llvm.ptr, i32) -> i32
    %null = llvm.mlir.zero : !llvm.ptr
    %pm = llvm.call @sigprocmask(%z32, %set, %null) : (i32, !llvm.ptr, !llvm.ptr) -> i32
    %m1i = arith.constant -1 : i32
    %cloexec = arith.constant 524288 : i32
    %sfd = llvm.call @signalfd(%m1i, %set, %cloexec) : (i32, !llvm.ptr, i32) -> i32
    %s = func.call @sqe() : () -> !llvm.ptr
    %si = llvm.mlir.addressof @siginfo : !llvm.ptr
    %c128 = arith.constant 128 : i32
    llvm.call @io_uring_prep_read(%s, %sfd, %si, %c128, %c0) : (!llvm.ptr, i32, !llvm.ptr, i32, i64) -> ()
    %c5 = arith.constant 5 : i64
    llvm.call @io_uring_sqe_set_data64(%s, %c5) : (!llvm.ptr, i64) -> ()
    func.call @accept_next() : () -> ()
    %pAcc = llvm.mlir.addressof @accepting : !llvm.ptr
    %pAdm = llvm.mlir.addressof @admitted : !llvm.ptr
    %cqep = llvm.alloca %one x !llvm.ptr : (i32) -> !llvm.ptr
    scf.while : () -> () {
      %acc = func.call @load_g(%pAcc) : (!llvm.ptr) -> i64
      %adm = func.call @load_g(%pAdm) : (!llvm.ptr) -> i64
      %a = arith.cmpi ne, %acc, %c0 : i64
      %d = arith.cmpi sgt, %adm, %c0 : i64
      %go = arith.ori %a, %d : i1
      scf.condition(%go)
    } do {
      %w = llvm.call @io_uring_submit_and_wait(%ring, %one) : (!llvm.ptr, i32) -> i32
      scf.while : () -> () {
        %p = llvm.call @io_uring_peek_cqe(%ring, %cqep) : (!llvm.ptr, !llvm.ptr) -> i32
        %got = arith.cmpi eq, %p, %z32 : i32
        scf.condition(%got)
      } do {
        %cqe = llvm.load %cqep : !llvm.ptr -> !llvm.ptr
        %data = llvm.load %cqe : !llvm.ptr -> i64
        %pres = llvm.getelementptr %cqe[8] : (!llvm.ptr) -> !llvm.ptr, i8
        %res = llvm.load %pres : !llvm.ptr -> i32
        llvm.call @io_uring_cqe_seen(%ring, %cqe) : (!llvm.ptr, !llvm.ptr) -> ()
        func.call @handle(%data, %res) : (i64, i32) -> ()
        scf.yield
      }
      scf.yield
    }
    %c2 = llvm.call @close(%lfd) : (i32) -> i32
    llvm.call @io_uring_queue_exit(%ring) : (!llvm.ptr) -> ()
    %c3 = llvm.call @close(%sfd) : (i32) -> i32
    %u = llvm.call @unlink(%ovfile) : (!llvm.ptr) -> i32
    %fmtDrained = llvm.mlir.addressof @lit16 : !llvm.ptr
    %fmtDrained_n = arith.constant 20 : i64
    %y = llvm.call @dprintf(%two, %fmtDrained) vararg(!llvm.func<i32 (i32, ptr, ...)>) : (i32, !llvm.ptr) -> i32
    scf.yield %z32 : i32
  } else {
    %r1 = arith.constant 1 : i32
    scf.yield %r1 : i32
  }
  return %rc : i32
}

// argv[i]
func.func @arg(%argv: !llvm.ptr, %i: i64) -> !llvm.ptr {
  %q = llvm.getelementptr %argv[%i] : (!llvm.ptr, i64) -> !llvm.ptr, !llvm.ptr
  %v = llvm.load %q : !llvm.ptr -> !llvm.ptr
  return %v : !llvm.ptr
}

func.func @eq(%a: !llvm.ptr, %b: !llvm.ptr) -> i1 {
  %r = llvm.call @strcmp(%a, %b) : (!llvm.ptr, !llvm.ptr) -> i32
  %z = arith.constant 0 : i32
  %e = arith.cmpi eq, %r, %z : i32
  return %e : i1
}

func.func @main(%argc32: i32, %argv: !llvm.ptr) -> i32 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c8 = arith.constant 8 : i64
  %two = arith.constant 2 : i32
  %null = llvm.mlir.zero : !llvm.ptr
  %argc = arith.extsi %argc32 : i32 to i64
  %kArg = llvm.mlir.addressof @lit17 : !llvm.ptr
  %kArg_n = arith.constant 6 : i64
  %kArgstr = llvm.mlir.addressof @lit18 : !llvm.ptr
  %kArgstr_n = arith.constant 9 : i64
  %kCorpus = llvm.mlir.addressof @lit19 : !llvm.ptr
  %kCorpus_n = arith.constant 9 : i64
  %kMlnix = llvm.mlir.addressof @lit20 : !llvm.ptr
  %kMlnix_n = arith.constant 8 : i64
  %kPage = llvm.mlir.addressof @lit21 : !llvm.ptr
  %kPage_n = arith.constant 7 : i64
  %kState = llvm.mlir.addressof @lit22 : !llvm.ptr
  %kState_n = arith.constant 8 : i64
  %kPort = llvm.mlir.addressof @lit23 : !llvm.ptr
  %kPort_n = arith.constant 7 : i64
  %dMlnix = llvm.mlir.addressof @lit24 : !llvm.ptr
  %dMlnix_n = arith.constant 6 : i64
  %dState = llvm.mlir.addressof @lit25 : !llvm.ptr
  %dState_n = arith.constant 5 : i64
  %usage = llvm.mlir.addressof @lit26 : !llvm.ptr
  %usage_n = arith.constant 138 : i64
  // the settings: corpus, mlnix, page, state, port
  %one = arith.constant 1 : i32
  %set = llvm.alloca %one x !llvm.array<5 x i64> : (i32) -> !llvm.ptr
  func.call @setp(%set, %c0, %null) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  func.call @setp(%set, %c1, %dMlnix) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  func.call @setp(%set, %c2, %null) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  func.call @setp(%set, %c3, %dState) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  %c4 = arith.constant 4 : i64
  %c8080 = arith.constant 8080 : i64
  func.call @seti(%set, %c4, %c8080) : (!llvm.ptr, i64, i64) -> ()
  %argBytes = arith.muli %argc, %c8 : i64
  %args = llvm.call @malloc(%argBytes) : (i64) -> !llvm.ptr
  // walk the arguments: state 0 while walking, 1 done, 2 bad
  %w:3 = scf.while (%i = %c1, %nargs = %c0, %state = %c0) : (i64, i64, i64) -> (i64, i64, i64) {
    %go = arith.cmpi eq, %state, %c0 : i64
    scf.condition(%go) %i, %nargs, %state : i64, i64, i64
  } do {
  ^bb0(%i: i64, %nargs: i64, %state: i64):
    %end = arith.cmpi sge, %i, %argc : i64
    %r:3 = scf.if %end -> (i64, i64, i64) {
      scf.yield %i, %nargs, %c1 : i64, i64, i64
    } else {
      %k = func.call @arg(%argv, %i) : (!llvm.ptr, i64) -> !llvm.ptr
      %isArg = func.call @eq(%k, %kArg) : (!llvm.ptr, !llvm.ptr) -> i1
      %isArgstr = func.call @eq(%k, %kArgstr) : (!llvm.ptr, !llvm.ptr) -> i1
      %triple = arith.ori %isArg, %isArgstr : i1
      %i2 = arith.addi %i, %c2 : i64
      %room3 = arith.cmpi slt, %i2, %argc : i64
      %isTriple = arith.andi %triple, %room3 : i1
      %r2:3 = scf.if %isTriple -> (i64, i64, i64) {
        %i1 = arith.addi %i, %c1 : i64
        %v1 = func.call @arg(%argv, %i1) : (!llvm.ptr, i64) -> !llvm.ptr
        %v2 = func.call @arg(%argv, %i2) : (!llvm.ptr, i64) -> !llvm.ptr
        func.call @setp(%args, %nargs, %k) : (!llvm.ptr, i64, !llvm.ptr) -> ()
        %n1 = arith.addi %nargs, %c1 : i64
        func.call @setp(%args, %n1, %v1) : (!llvm.ptr, i64, !llvm.ptr) -> ()
        %n2 = arith.addi %nargs, %c2 : i64
        func.call @setp(%args, %n2, %v2) : (!llvm.ptr, i64, !llvm.ptr) -> ()
        %n3 = arith.addi %nargs, %c3 : i64
        %i3 = arith.addi %i, %c3 : i64
        scf.yield %i3, %n3, %c0 : i64, i64, i64
      } else {
        %i1 = arith.addi %i, %c1 : i64
        %lacks = arith.cmpi sge, %i1, %argc : i64
        %r3:3 = scf.if %lacks -> (i64, i64, i64) {
          scf.yield %i, %nargs, %c2 : i64, i64, i64
        } else {
          %v = func.call @arg(%argv, %i1) : (!llvm.ptr, i64) -> !llvm.ptr
          %isCorpus = func.call @eq(%k, %kCorpus) : (!llvm.ptr, !llvm.ptr) -> i1
          %isMlnix = func.call @eq(%k, %kMlnix) : (!llvm.ptr, !llvm.ptr) -> i1
          %isPage = func.call @eq(%k, %kPage) : (!llvm.ptr, !llvm.ptr) -> i1
          %isState = func.call @eq(%k, %kState) : (!llvm.ptr, !llvm.ptr) -> i1
          %isPort = func.call @eq(%k, %kPort) : (!llvm.ptr, !llvm.ptr) -> i1
          scf.if %isCorpus {
            func.call @setp(%set, %c0, %v) : (!llvm.ptr, i64, !llvm.ptr) -> ()
          }
          scf.if %isMlnix {
            func.call @setp(%set, %c1, %v) : (!llvm.ptr, i64, !llvm.ptr) -> ()
          }
          scf.if %isPage {
            func.call @setp(%set, %c2, %v) : (!llvm.ptr, i64, !llvm.ptr) -> ()
          }
          scf.if %isState {
            func.call @setp(%set, %c3, %v) : (!llvm.ptr, i64, !llvm.ptr) -> ()
          }
          scf.if %isPort {
            %p = llvm.call @atoi(%v) : (!llvm.ptr) -> i32
            %p64 = arith.extsi %p : i32 to i64
            func.call @seti(%set, %c4, %p64) : (!llvm.ptr, i64, i64) -> ()
          }
          %a0 = arith.ori %isCorpus, %isMlnix : i1
          %a1 = arith.ori %isPage, %isState : i1
          %a2 = arith.ori %a0, %a1 : i1
          %known = arith.ori %a2, %isPort : i1
          %st = arith.select %known, %c0, %c2 : i64
          %i3 = arith.addi %i, %c2 : i64
          scf.yield %i3, %nargs, %st : i64, i64, i64
        }
        scf.yield %r3#0, %r3#1, %r3#2 : i64, i64, i64
      }
      scf.yield %r2#0, %r2#1, %r2#2 : i64, i64, i64
    }
    scf.yield %r#0, %r#1, %r#2 : i64, i64, i64
  }
  %corpus = func.call @getp(%set, %c0) : (!llvm.ptr, i64) -> !llvm.ptr
  %mlnix = func.call @getp(%set, %c1) : (!llvm.ptr, i64) -> !llvm.ptr
  %page = func.call @getp(%set, %c2) : (!llvm.ptr, i64) -> !llvm.ptr
  %state0 = func.call @getp(%set, %c3) : (!llvm.ptr, i64) -> !llvm.ptr
  %port = func.call @geti(%set, %c4) : (!llvm.ptr, i64) -> i64
  %noCorpus = llvm.icmp "eq" %corpus, %null : !llvm.ptr
  %noPage = llvm.icmp "eq" %page, %null : !llvm.ptr
  %badArgs = arith.cmpi eq, %w#2, %c2 : i64
  %missing = arith.ori %noCorpus, %noPage : i1
  %refuse = arith.ori %badArgs, %missing : i1
  %rc = scf.if %refuse -> (i32) {
    %x = llvm.call @dprintf(%two, %usage) vararg(!llvm.func<i32 (i32, ptr, ...)>) : (i32, !llvm.ptr) -> i32
    scf.yield %two : i32
  } else {
    // systemd's RuntimeDirectory, unless a state directory was given
    %kRuntime = llvm.mlir.addressof @lit27 : !llvm.ptr
    %kRuntime_n = arith.constant 18 : i64
    %rt = llvm.call @getenv(%kRuntime) : (!llvm.ptr) -> !llvm.ptr
    %hasRt = llvm.icmp "ne" %rt, %null : !llvm.ptr
    %isTmp = func.call @eq(%state0, %dState) : (!llvm.ptr, !llvm.ptr) -> i1
    %useRt = arith.andi %hasRt, %isTmp : i1
    %state = arith.select %useRt, %rt, %state0 : !llvm.ptr
    // the overlay file: STATE/mlnixci-overlay.json
    %kFile = llvm.mlir.addressof @lit28 : !llvm.ptr
    %kFile_n = arith.constant 22 : i64
    %sl = llvm.call @strlen(%state) : (!llvm.ptr) -> i64
    %fl = arith.addi %sl, %kFile_n : i64
    %ovfile = llvm.call @malloc(%fl) : (i64) -> !llvm.ptr
    %x1 = llvm.call @memcpy(%ovfile, %state, %sl) : (!llvm.ptr, !llvm.ptr, i64) -> !llvm.ptr
    %fe = func.call @off(%ovfile, %sl) : (!llvm.ptr, i64) -> !llvm.ptr
    %x2 = llvm.call @memcpy(%fe, %kFile, %kFile_n) : (!llvm.ptr, !llvm.ptr, i64) -> !llvm.ptr
    // the request of a facet asked for on demand: STATE/mlnixci-facet.json
    %kAsk = llvm.mlir.addressof @lit31 : !llvm.ptr
    %kAsk_n = arith.constant 20 : i64
    %askl = arith.addi %sl, %kAsk_n : i64
    %askfile = llvm.call @malloc(%askl) : (i64) -> !llvm.ptr
    %x3 = llvm.call @memcpy(%askfile, %state, %sl) : (!llvm.ptr, !llvm.ptr, i64) -> !llvm.ptr
    %ae = func.call @off(%askfile, %sl) : (!llvm.ptr, i64) -> !llvm.ptr
    %x4 = llvm.call @memcpy(%ae, %kAsk, %kAsk_n) : (!llvm.ptr, !llvm.ptr, i64) -> !llvm.ptr
    func.call @eval_settings(%mlnix, %corpus, %args, %w#1) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64) -> ()
    func.call @evaluate(%null) : (!llvm.ptr) -> ()
    %status = func.call @run_status() : () -> i64
    %failed = arith.cmpi ne, %status, %c0 : i64
    %r = scf.if %failed -> (i32) {
      %e = func.call @run_err() : () -> !llvm.ptr
      %en = func.call @run_err_n() : () -> i64
      %en32 = arith.trunci %en : i64 to i32
      %fmtFail = llvm.mlir.addressof @lit29 : !llvm.ptr
      %fmtFail_n = arith.constant 46 : i64
      %x = llvm.call @dprintf(%two, %fmtFail, %en32, %e) vararg(!llvm.func<i32 (i32, ptr, ...)>) : (i32, !llvm.ptr, i32, !llvm.ptr) -> i32
      %one32 = arith.constant 1 : i32
      scf.yield %one32 : i32
    } else {
      %out = func.call @run_out() : () -> !llvm.ptr
      %on = func.call @run_out_n() : () -> i64
      %ms = func.call @run_ms() : () -> f64
      %on1 = arith.maxsi %on, %c1 : i64
      %copy = llvm.call @malloc(%on1) : (i64) -> !llvm.ptr
      %x = llvm.call @memcpy(%copy, %out, %on) : (!llvm.ptr, !llvm.ptr, i64) -> !llvm.ptr
      %base = func.call @corpus_load(%out, %on, %ms) : (!llvm.ptr, i64, f64) -> !llvm.ptr
      %cur = func.call @corpus_load(%copy, %on, %ms) : (!llvm.ptr, i64, f64) -> !llvm.ptr
      %noBase = llvm.icmp "eq" %base, %null : !llvm.ptr
      %noCur = llvm.icmp "eq" %cur, %null : !llvm.ptr
      %none = arith.ori %noBase, %noCur : i1
      %r2 = scf.if %none -> (i32) {
        %why = func.call @corpus_why() : () -> !llvm.ptr
        %whyn = func.call @corpus_why_n() : () -> i64
        %wn32 = arith.trunci %whyn : i64 to i32
        %fmtWhy = llvm.mlir.addressof @lit30 : !llvm.ptr
        %fmtWhy_n = arith.constant 17 : i64
        %y = llvm.call @dprintf(%two, %fmtWhy, %wn32, %why) vararg(!llvm.func<i32 (i32, ptr, ...)>) : (i32, !llvm.ptr, i32, !llvm.ptr) -> i32
        %one32 = arith.constant 1 : i32
        scf.yield %one32 : i32
      } else {
        func.call @api_init(%page, %ovfile, %base, %cur, %askfile) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> ()
        %c3b = arith.constant 3 : i64
        %rows = func.call @geti(%base, %c3b) : (!llvm.ptr, i64) -> i64
        %s = func.call @serve(%port, %corpus, %rows, %ms, %ovfile) : (i64, !llvm.ptr, i64, f64, !llvm.ptr) -> i32
        scf.yield %s : i32
      }
      scf.yield %r2 : i32
    }
    scf.yield %r : i32
  }
  return %rc : i32
}
