// eval.mlir -- the evaluation: mlnix as a child process, its output and its errors read into two growing series.
//
// The settings (from the command line) and the result of the last run are module state, read through the functions
// below.  An overlay is passed as a file in the state directory: { networking = { ... }; } as JSON, read by eval.nix.

llvm.func @malloc(i64) -> !llvm.ptr
llvm.func @realloc(!llvm.ptr, i64) -> !llvm.ptr
llvm.func @free(!llvm.ptr)
llvm.func @memcpy(!llvm.ptr, !llvm.ptr, i64) -> !llvm.ptr
llvm.func @strlen(!llvm.ptr) -> i64
llvm.func @strerror(i32) -> !llvm.ptr
llvm.func @pipe2(!llvm.ptr, i32) -> i32
llvm.func @close(i32) -> i32
llvm.func @read(i32, !llvm.ptr, i64) -> i64
llvm.func @write(i32, !llvm.ptr, i64) -> i64
llvm.func @open(!llvm.ptr, i32, ...) -> i32
llvm.func @rename(!llvm.ptr, !llvm.ptr) -> i32
llvm.func @poll(!llvm.ptr, i64, i32) -> i32
llvm.func @waitpid(i32, !llvm.ptr, i32) -> i32
llvm.func @clock_gettime(i32, !llvm.ptr) -> i32
llvm.func @sigemptyset(!llvm.ptr) -> i32
llvm.func @posix_spawn_file_actions_init(!llvm.ptr) -> i32
llvm.func @posix_spawn_file_actions_destroy(!llvm.ptr) -> i32
llvm.func @posix_spawn_file_actions_adddup2(!llvm.ptr, i32, i32) -> i32
llvm.func @posix_spawnattr_init(!llvm.ptr) -> i32
llvm.func @posix_spawnattr_destroy(!llvm.ptr) -> i32
llvm.func @posix_spawnattr_setsigmask(!llvm.ptr, !llvm.ptr) -> i32
llvm.func @posix_spawnattr_setflags(!llvm.ptr, i16) -> i32
llvm.func @posix_spawnp(!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> i32
llvm.mlir.global external @environ() : !llvm.ptr
// reads.mlir (TrikeShed's ops): the lines of the errors kept
llvm.func @_mlir_ciface_rd_kept(!llvm.ptr, !llvm.ptr)

func.func private @off(!llvm.ptr, i64) -> !llvm.ptr
func.func private @view(!llvm.ptr, !llvm.ptr, i64)

llvm.mlir.global internal constant @k_instantiate("instantiate\00") : !llvm.array<12 x i8>
llvm.mlir.global internal constant @k_eval("--eval\00") : !llvm.array<7 x i8>
llvm.mlir.global internal constant @k_strict("--strict\00") : !llvm.array<9 x i8>
llvm.mlir.global internal constant @k_json("--json\00") : !llvm.array<7 x i8>
llvm.mlir.global internal constant @k_arg("--arg\00") : !llvm.array<6 x i8>
llvm.mlir.global internal constant @k_overlay("overlay\00") : !llvm.array<8 x i8>
llvm.mlir.global internal constant @k_request("request\00") : !llvm.array<8 x i8>
llvm.mlir.global internal constant @k_cannotrun("cannot run ") : !llvm.array<11 x i8>
llvm.mlir.global internal constant @k_colon(": ") : !llvm.array<2 x i8>
llvm.mlir.global internal constant @k_tmp(".tmp\00") : !llvm.array<5 x i8>

// ---- the settings: C strings from the command line; args is an array of them (--arg / --argstr triples)

llvm.mlir.global internal @s_mlnix() : !llvm.ptr {
  %0 = llvm.mlir.zero : !llvm.ptr
  llvm.return %0 : !llvm.ptr
}
llvm.mlir.global internal @s_corpus() : !llvm.ptr {
  %0 = llvm.mlir.zero : !llvm.ptr
  llvm.return %0 : !llvm.ptr
}
llvm.mlir.global internal @s_args() : !llvm.ptr {
  %0 = llvm.mlir.zero : !llvm.ptr
  llvm.return %0 : !llvm.ptr
}
llvm.mlir.global internal @s_nargs(0 : i64) : i64

func.func @eval_settings(%mlnix: !llvm.ptr, %corpus: !llvm.ptr, %args: !llvm.ptr, %nargs: i64) {
  %a = llvm.mlir.addressof @s_mlnix : !llvm.ptr
  llvm.store %mlnix, %a : !llvm.ptr, !llvm.ptr
  %b = llvm.mlir.addressof @s_corpus : !llvm.ptr
  llvm.store %corpus, %b : !llvm.ptr, !llvm.ptr
  %c = llvm.mlir.addressof @s_args : !llvm.ptr
  llvm.store %args, %c : !llvm.ptr, !llvm.ptr
  %d = llvm.mlir.addressof @s_nargs : !llvm.ptr
  llvm.store %nargs, %d : i64, !llvm.ptr
  return
}

// ---- the last run

llvm.mlir.global internal @r_status(0 : i64) : i64
llvm.mlir.global internal @r_ms(0.0 : f64) : f64
// out: { ptr, len, cap } and err: { ptr, len, cap }
llvm.mlir.global internal @r_out() : !llvm.array<3 x i64> {
  %0 = llvm.mlir.zero : !llvm.array<3 x i64>
  llvm.return %0 : !llvm.array<3 x i64>
}
llvm.mlir.global internal @r_err() : !llvm.array<3 x i64> {
  %0 = llvm.mlir.zero : !llvm.array<3 x i64>
  llvm.return %0 : !llvm.array<3 x i64>
}

func.func @run_status() -> i64 {
  %a = llvm.mlir.addressof @r_status : !llvm.ptr
  %v = llvm.load %a : !llvm.ptr -> i64
  return %v : i64
}
func.func @run_ms() -> f64 {
  %a = llvm.mlir.addressof @r_ms : !llvm.ptr
  %v = llvm.load %a : !llvm.ptr -> f64
  return %v : f64
}
// the output's buffer, which is the caller's now
func.func @run_out() -> !llvm.ptr {
  %a = llvm.mlir.addressof @r_out : !llvm.ptr
  %p = llvm.load %a : !llvm.ptr -> !llvm.ptr
  %null = llvm.mlir.zero : !llvm.ptr
  llvm.store %null, %a : !llvm.ptr, !llvm.ptr
  return %p : !llvm.ptr
}
func.func @run_out_n() -> i64 {
  %a = llvm.mlir.addressof @r_out : !llvm.ptr
  %q = llvm.getelementptr %a[1] : (!llvm.ptr) -> !llvm.ptr, i64
  %v = llvm.load %q : !llvm.ptr -> i64
  return %v : i64
}
func.func @run_err() -> !llvm.ptr {
  %a = llvm.mlir.addressof @r_err : !llvm.ptr
  %p = llvm.load %a : !llvm.ptr -> !llvm.ptr
  return %p : !llvm.ptr
}
func.func @run_err_n() -> i64 {
  %a = llvm.mlir.addressof @r_err : !llvm.ptr
  %q = llvm.getelementptr %a[1] : (!llvm.ptr) -> !llvm.ptr, i64
  %v = llvm.load %q : !llvm.ptr -> i64
  return %v : i64
}

// append n bytes at src to the series { ptr, len, cap } at s
func.func @grow(%s: !llvm.ptr, %src: !llvm.ptr, %n: i64) {
  %pl = llvm.getelementptr %s[1] : (!llvm.ptr) -> !llvm.ptr, i64
  %pc = llvm.getelementptr %s[2] : (!llvm.ptr) -> !llvm.ptr, i64
  %p = llvm.load %s : !llvm.ptr -> !llvm.ptr
  %len = llvm.load %pl : !llvm.ptr -> i64
  %cap = llvm.load %pc : !llvm.ptr -> i64
  %need = arith.addi %len, %n : i64
  %c1 = arith.constant 1 : i64
  %need1 = arith.addi %need, %c1 : i64
  %small = arith.cmpi sgt, %need1, %cap : i64
  %q = scf.if %small -> (!llvm.ptr) {
    %c2 = arith.constant 2 : i64
    %c65536 = arith.constant 65536 : i64
    %d = arith.muli %cap, %c2 : i64
    %m = arith.maxsi %d, %need1 : i64
    %nc = arith.maxsi %m, %c65536 : i64
    %r = llvm.call @realloc(%p, %nc) : (!llvm.ptr, i64) -> !llvm.ptr
    llvm.store %r, %s : !llvm.ptr, !llvm.ptr
    llvm.store %nc, %pc : i64, !llvm.ptr
    scf.yield %r : !llvm.ptr
  } else {
    scf.yield %p : !llvm.ptr
  }
  %end = func.call @off(%q, %len) : (!llvm.ptr, i64) -> !llvm.ptr
  %x = llvm.call @memcpy(%end, %src, %n) : (!llvm.ptr, !llvm.ptr, i64) -> !llvm.ptr
  llvm.store %need, %pl : i64, !llvm.ptr
  // a NUL after the bytes, for the C library
  %nul = func.call @off(%q, %need) : (!llvm.ptr, i64) -> !llvm.ptr
  %z = arith.constant 0 : i8
  llvm.store %z, %nul : i8, !llvm.ptr
  return
}

func.func @clear(%s: !llvm.ptr) {
  %p = llvm.load %s : !llvm.ptr -> !llvm.ptr
  llvm.call @free(%p) : (!llvm.ptr) -> ()
  %null = llvm.mlir.zero : !llvm.ptr
  llvm.store %null, %s : !llvm.ptr, !llvm.ptr
  %c0 = arith.constant 0 : i64
  %pl = llvm.getelementptr %s[1] : (!llvm.ptr) -> !llvm.ptr, i64
  %pc = llvm.getelementptr %s[2] : (!llvm.ptr) -> !llvm.ptr, i64
  llvm.store %c0, %pl : i64, !llvm.ptr
  llvm.store %c0, %pc : i64, !llvm.ptr
  return
}

func.func @now_ms() -> f64 {
  %one = arith.constant 1 : i32
  %ts = llvm.alloca %one x !llvm.array<2 x i64> : (i32) -> !llvm.ptr
  %r = llvm.call @clock_gettime(%one, %ts) : (i32, !llvm.ptr) -> i32
  %s = llvm.load %ts : !llvm.ptr -> i64
  %pn = llvm.getelementptr %ts[1] : (!llvm.ptr) -> !llvm.ptr, i64
  %ns = llvm.load %pn : !llvm.ptr -> i64
  %sf = arith.sitofp %s : i64 to f64
  %nf = arith.sitofp %ns : i64 to f64
  %k3 = arith.constant 1.0e3 : f64
  %k6 = arith.constant 1.0e6 : f64
  %a = arith.mulf %sf, %k3 : f64
  %b = arith.divf %nf, %k6 : f64
  %m = arith.addf %a, %b : f64
  return %m : f64
}

// mlnix evaluates the corpus, with the overlay file when one is given (null for none).  The status, the output, the
// errors (a refusal's, without the evaluator's warnings) and the time are the last run's.
func.func @evaluate(%overlay: !llvm.ptr) {
  %null = llvm.mlir.zero : !llvm.ptr
  func.call @evaluate_with(%overlay, %null) : (!llvm.ptr, !llvm.ptr) -> ()
  return
}

// The same, with a request file when one is given (null for none): the facets a page asks for on demand, which the
// corpus's eval.nix answers instead of the corpus (answer.nix).
func.func @evaluate_with(%overlay: !llvm.ptr, %request: !llvm.ptr) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c8 = arith.constant 8 : i64
  %z32 = arith.constant 0 : i32
  %one = arith.constant 1 : i32
  %two = arith.constant 2 : i32
  %m1 = arith.constant -1 : i64
  %null = llvm.mlir.zero : !llvm.ptr
  %out = llvm.mlir.addressof @r_out : !llvm.ptr
  %err = llvm.mlir.addressof @r_err : !llvm.ptr
  func.call @clear(%out) : (!llvm.ptr) -> ()
  func.call @clear(%err) : (!llvm.ptr) -> ()
  %t0 = func.call @now_ms() : () -> f64
  // argv: mlnix instantiate --eval --strict --json CORPUS ARGS... [--arg overlay FILE] [--arg request FILE] NULL
  %pm = llvm.mlir.addressof @s_mlnix : !llvm.ptr
  %mlnix = llvm.load %pm : !llvm.ptr -> !llvm.ptr
  %pc = llvm.mlir.addressof @s_corpus : !llvm.ptr
  %corpus = llvm.load %pc : !llvm.ptr -> !llvm.ptr
  %pa = llvm.mlir.addressof @s_args : !llvm.ptr
  %args = llvm.load %pa : !llvm.ptr -> !llvm.ptr
  %pn = llvm.mlir.addressof @s_nargs : !llvm.ptr
  %nargs = llvm.load %pn : !llvm.ptr -> i64
  %c13 = arith.constant 13 : i64
  %slots = arith.addi %nargs, %c13 : i64
  %argvBytes = arith.muli %slots, %c8 : i64
  %argv2 = llvm.call @malloc(%argvBytes) : (i64) -> !llvm.ptr
  %ki = llvm.mlir.addressof @k_instantiate : !llvm.ptr
  %ke = llvm.mlir.addressof @k_eval : !llvm.ptr
  %ks = llvm.mlir.addressof @k_strict : !llvm.ptr
  %kj = llvm.mlir.addressof @k_json : !llvm.ptr
  %ka = llvm.mlir.addressof @k_arg : !llvm.ptr
  %ko = llvm.mlir.addressof @k_overlay : !llvm.ptr
  func.call @argv_put(%argv2, %c0, %mlnix) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  func.call @argv_put(%argv2, %c1, %ki) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %c5 = arith.constant 5 : i64
  %c6 = arith.constant 6 : i64
  func.call @argv_put(%argv2, %c2, %ke) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  func.call @argv_put(%argv2, %c3, %ks) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  func.call @argv_put(%argv2, %c4, %kj) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  func.call @argv_put(%argv2, %c5, %corpus) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  scf.for %i = %c0 to %nargs step %c1 : i64 {
    %src = llvm.getelementptr %args[%i] : (!llvm.ptr, i64) -> !llvm.ptr, !llvm.ptr
    %a = llvm.load %src : !llvm.ptr -> !llvm.ptr
    %j = arith.addi %i, %c6 : i64
    func.call @argv_put(%argv2, %j, %a) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  }
  %afterArgs = arith.addi %nargs, %c6 : i64
  %hasOverlay = llvm.icmp "ne" %overlay, %null : !llvm.ptr
  %end = scf.if %hasOverlay -> (i64) {
    func.call @argv_put(%argv2, %afterArgs, %ka) : (!llvm.ptr, i64, !llvm.ptr) -> ()
    %j1 = arith.addi %afterArgs, %c1 : i64
    func.call @argv_put(%argv2, %j1, %ko) : (!llvm.ptr, i64, !llvm.ptr) -> ()
    %j2 = arith.addi %afterArgs, %c2 : i64
    func.call @argv_put(%argv2, %j2, %overlay) : (!llvm.ptr, i64, !llvm.ptr) -> ()
    %j3 = arith.addi %afterArgs, %c3 : i64
    scf.yield %j3 : i64
  } else {
    scf.yield %afterArgs : i64
  }
  %hasRequest = llvm.icmp "ne" %request, %null : !llvm.ptr
  %kr = llvm.mlir.addressof @k_request : !llvm.ptr
  %end2 = scf.if %hasRequest -> (i64) {
    func.call @argv_put(%argv2, %end, %ka) : (!llvm.ptr, i64, !llvm.ptr) -> ()
    %q1 = arith.addi %end, %c1 : i64
    func.call @argv_put(%argv2, %q1, %kr) : (!llvm.ptr, i64, !llvm.ptr) -> ()
    %q2 = arith.addi %end, %c2 : i64
    func.call @argv_put(%argv2, %q2, %request) : (!llvm.ptr, i64, !llvm.ptr) -> ()
    %q3 = arith.addi %end, %c3 : i64
    scf.yield %q3 : i64
  } else {
    scf.yield %end : i64
  }
  func.call @argv_put(%argv2, %end2, %null) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  // the pipes, the child's descriptors, and its signal mask: the server blocks SIGTERM and SIGINT to read them from its
  // ring; the child takes them as usual
  %fds = llvm.alloca %one x !llvm.array<4 x i32> : (i32) -> !llvm.ptr
  %fdsErr = llvm.getelementptr %fds[2] : (!llvm.ptr) -> !llvm.ptr, i32
  %cloexec = arith.constant 524288 : i32
  %p1 = llvm.call @pipe2(%fds, %cloexec) : (!llvm.ptr, i32) -> i32
  %p2 = llvm.call @pipe2(%fdsErr, %cloexec) : (!llvm.ptr, i32) -> i32
  %outR = llvm.load %fds : !llvm.ptr -> i32
  %pOutW = llvm.getelementptr %fds[1] : (!llvm.ptr) -> !llvm.ptr, i32
  %outW = llvm.load %pOutW : !llvm.ptr -> i32
  %errR = llvm.load %fdsErr : !llvm.ptr -> i32
  %pErrW = llvm.getelementptr %fds[3] : (!llvm.ptr) -> !llvm.ptr, i32
  %errW = llvm.load %pErrW : !llvm.ptr -> i32
  %fa = llvm.alloca %one x !llvm.array<512 x i8> : (i32) -> !llvm.ptr
  %at = llvm.alloca %one x !llvm.array<512 x i8> : (i32) -> !llvm.ptr
  %mask = llvm.alloca %one x !llvm.array<256 x i8> : (i32) -> !llvm.ptr
  %pidp = llvm.alloca %one x i32 : (i32) -> !llvm.ptr
  %x1 = llvm.call @posix_spawn_file_actions_init(%fa) : (!llvm.ptr) -> i32
  %x2 = llvm.call @posix_spawn_file_actions_adddup2(%fa, %outW, %one) : (!llvm.ptr, i32, i32) -> i32
  %x3 = llvm.call @posix_spawn_file_actions_adddup2(%fa, %errW, %two) : (!llvm.ptr, i32, i32) -> i32
  %x4 = llvm.call @posix_spawnattr_init(%at) : (!llvm.ptr) -> i32
  %x5 = llvm.call @sigemptyset(%mask) : (!llvm.ptr) -> i32
  %x6 = llvm.call @posix_spawnattr_setsigmask(%at, %mask) : (!llvm.ptr, !llvm.ptr) -> i32
  %setmask = arith.constant 8 : i16
  %x7 = llvm.call @posix_spawnattr_setflags(%at, %setmask) : (!llvm.ptr, i16) -> i32
  %envp = llvm.mlir.addressof @environ : !llvm.ptr
  %env = llvm.load %envp : !llvm.ptr -> !llvm.ptr
  %spawned = llvm.call @posix_spawnp(%pidp, %mlnix, %fa, %at, %argv2, %env) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> i32
  %x8 = llvm.call @posix_spawnattr_destroy(%at) : (!llvm.ptr) -> i32
  %x9 = llvm.call @posix_spawn_file_actions_destroy(%fa) : (!llvm.ptr) -> i32
  %y1 = llvm.call @close(%outW) : (i32) -> i32
  %y2 = llvm.call @close(%errW) : (i32) -> i32
  llvm.call @free(%argv2) : (!llvm.ptr) -> ()
  %failed = arith.cmpi ne, %spawned, %z32 : i32
  %status = scf.if %failed -> (i64) {
    %y3 = llvm.call @close(%outR) : (i32) -> i32
    %y4 = llvm.call @close(%errR) : (i32) -> i32
    %kc = llvm.mlir.addressof @k_cannotrun : !llvm.ptr
    %c11 = arith.constant 11 : i64
    func.call @grow(%err, %kc, %c11) : (!llvm.ptr, !llvm.ptr, i64) -> ()
    %ml = llvm.call @strlen(%mlnix) : (!llvm.ptr) -> i64
    func.call @grow(%err, %mlnix, %ml) : (!llvm.ptr, !llvm.ptr, i64) -> ()
    %kcol = llvm.mlir.addressof @k_colon : !llvm.ptr
    func.call @grow(%err, %kcol, %c2) : (!llvm.ptr, !llvm.ptr, i64) -> ()
    %why = llvm.call @strerror(%spawned) : (i32) -> !llvm.ptr
    %wl = llvm.call @strlen(%why) : (!llvm.ptr) -> i64
    func.call @grow(%err, %why, %wl) : (!llvm.ptr, !llvm.ptr, i64) -> ()
    scf.yield %m1 : i64
  } else {
    func.call @drain_pipes(%outR, %errR) : (i32, i32) -> ()
    %pid = llvm.load %pidp : !llvm.ptr -> i32
    %stp = llvm.alloca %one x i32 : (i32) -> !llvm.ptr
    llvm.store %z32, %stp : i32, !llvm.ptr
    %w = llvm.call @waitpid(%pid, %stp, %z32) : (i32, !llvm.ptr, i32) -> i32
    %st = llvm.load %stp : !llvm.ptr -> i32
    // WIFEXITED: no signal in the low 7 bits; WEXITSTATUS: bits 8..15; WTERMSIG: the low 7 bits
    %c127 = arith.constant 127 : i32
    %c255 = arith.constant 255 : i32
    %c8i = arith.constant 8 : i32
    %c128 = arith.constant 128 : i32
    %sig = arith.andi %st, %c127 : i32
    %exited = arith.cmpi eq, %sig, %z32 : i32
    %hi = arith.shrui %st, %c8i : i32
    %code = arith.andi %hi, %c255 : i32
    %killed = arith.addi %sig, %c128 : i32
    %s = arith.select %exited, %code, %killed : i32
    %s64 = arith.extsi %s : i32 to i64
    scf.yield %s64 : i64
  }
  %ps = llvm.mlir.addressof @r_status : !llvm.ptr
  llvm.store %status, %ps : i64, !llvm.ptr
  %t1 = func.call @now_ms() : () -> f64
  %dt = arith.subf %t1, %t0 : f64
  %pms = llvm.mlir.addressof @r_ms : !llvm.ptr
  llvm.store %dt, %pms : f64, !llvm.ptr
  // the evaluator's warnings are not the error a refusal reports
  %refused = arith.cmpi ne, %status, %c0 : i64
  scf.if %refused {
    func.call @drop_warnings() : () -> ()
  }
  return
}

func.func @argv_put(%argv: !llvm.ptr, %i: i64, %p: !llvm.ptr) {
  %q = llvm.getelementptr %argv[%i] : (!llvm.ptr, i64) -> !llvm.ptr, !llvm.ptr
  llvm.store %p, %q : !llvm.ptr, !llvm.ptr
  return
}

// read both pipes until both are closed
func.func @drain_pipes(%outR: i32, %errR: i32) {
  %one = arith.constant 1 : i32
  %z32 = arith.constant 0 : i32
  %m1i = arith.constant -1 : i32
  %c0 = arith.constant 0 : i64
  %c2 = arith.constant 2 : i64
  %c65536 = arith.constant 65536 : i64
  %events = arith.constant 1 : i16
  %ready = arith.constant 25 : i16
  %zero16 = arith.constant 0 : i16
  %out = llvm.mlir.addressof @r_out : !llvm.ptr
  %err = llvm.mlir.addressof @r_err : !llvm.ptr
  %fds = llvm.alloca %one x !llvm.array<2 x struct<(i32, i16, i16)>> : (i32) -> !llvm.ptr
  %buf = llvm.alloca %one x !llvm.array<65536 x i8> : (i32) -> !llvm.ptr
  %f0 = llvm.getelementptr %fds[0, 0, 0] : (!llvm.ptr) -> !llvm.ptr, !llvm.array<2 x struct<(i32, i16, i16)>>
  %e0 = llvm.getelementptr %fds[0, 0, 1] : (!llvm.ptr) -> !llvm.ptr, !llvm.array<2 x struct<(i32, i16, i16)>>
  %f1 = llvm.getelementptr %fds[0, 1, 0] : (!llvm.ptr) -> !llvm.ptr, !llvm.array<2 x struct<(i32, i16, i16)>>
  %e1 = llvm.getelementptr %fds[0, 1, 1] : (!llvm.ptr) -> !llvm.ptr, !llvm.array<2 x struct<(i32, i16, i16)>>
  llvm.store %outR, %f0 : i32, !llvm.ptr
  llvm.store %events, %e0 : i16, !llvm.ptr
  llvm.store %errR, %f1 : i32, !llvm.ptr
  llvm.store %events, %e1 : i16, !llvm.ptr
  %open0 = arith.constant 2 : i64
  %done = scf.while (%open = %open0) : (i64) -> i64 {
    %more = arith.cmpi sgt, %open, %c0 : i64
    scf.condition(%more) %open : i64
  } do {
  ^bb0(%open: i64):
    %pr = llvm.call @poll(%fds, %c2, %m1i) : (!llvm.ptr, i64, i32) -> i32
    %c1 = arith.constant 1 : i64
    %left = scf.for %i = %c0 to %c2 step %c1 iter_args(%o = %open) -> (i64) : i64 {
      %pf = llvm.getelementptr %fds[0, %i, 0] : (!llvm.ptr, i64) -> !llvm.ptr, !llvm.array<2 x struct<(i32, i16, i16)>>
      %pre = llvm.getelementptr %fds[0, %i, 2] : (!llvm.ptr, i64) -> !llvm.ptr, !llvm.array<2 x struct<(i32, i16, i16)>>
      %fd = llvm.load %pf : !llvm.ptr -> i32
      %re = llvm.load %pre : !llvm.ptr -> i16
      %live = arith.cmpi sge, %fd, %z32 : i32
      %bits = arith.andi %re, %ready : i16
      %has = arith.cmpi ne, %bits, %zero16 : i16
      %go = arith.andi %live, %has : i1
      %o2 = scf.if %go -> (i64) {
        %n = llvm.call @read(%fd, %buf, %c65536) : (i32, !llvm.ptr, i64) -> i64
        %got = arith.cmpi sgt, %n, %c0 : i64
        %o3 = scf.if %got -> (i64) {
          %isErr = arith.cmpi eq, %i, %c1 : i64
          %dst = arith.select %isErr, %err, %out : !llvm.ptr
          func.call @grow(%dst, %buf, %n) : (!llvm.ptr, !llvm.ptr, i64) -> ()
          scf.yield %o : i64
        } else {
          %y = llvm.call @close(%fd) : (i32) -> i32
          llvm.store %m1i, %pf : i32, !llvm.ptr
          %o4 = arith.subi %o, %c1 : i64
          scf.yield %o4 : i64
        }
        scf.yield %o3 : i64
      } else {
        scf.yield %o : i64
      }
      scf.yield %o2 : i64
    }
    scf.yield %left : i64
  }
  return
}

// keep the lines of the errors that do not begin "evaluation warning:" (reads.mlir's rd_kept: the errors' parts at '\n'
// kept by a where and combined, a NUL after them); they are the errors now
func.func @drop_warnings() {
  %one = arith.constant 1 : i32
  %c1 = arith.constant 1 : i64
  %err = llvm.mlir.addressof @r_err : !llvm.ptr
  %p = llvm.load %err : !llvm.ptr -> !llvm.ptr
  %pl = llvm.getelementptr %err[1] : (!llvm.ptr) -> !llvm.ptr, i64
  %pc = llvm.getelementptr %err[2] : (!llvm.ptr) -> !llvm.ptr, i64
  %n = llvm.load %pl : !llvm.ptr -> i64
  %from = llvm.alloca %one x !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)> : (i32) -> !llvm.ptr
  func.call @view(%from, %p, %n) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %res = llvm.alloca %one x !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)> : (i32) -> !llvm.ptr
  llvm.call @_mlir_ciface_rd_kept(%res, %from) : (!llvm.ptr, !llvm.ptr) -> ()
  llvm.call @free(%p) : (!llvm.ptr) -> ()
  // a fresh buffer: its allocation is its data; its last byte is the NUL
  %kept = llvm.load %res : !llvm.ptr -> !llvm.ptr
  %psize = llvm.getelementptr %res[0, 3, 0] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>
  %size = llvm.load %psize : !llvm.ptr -> i64
  %k = arith.subi %size, %c1 : i64
  llvm.store %kept, %err : !llvm.ptr, !llvm.ptr
  llvm.store %k, %pl : i64, !llvm.ptr
  llvm.store %size, %pc : i64, !llvm.ptr
  return
}

// write the n bytes at p to the file (a C string), through a file beside it renamed over it
func.func @write_file(%path: !llvm.ptr, %p: !llvm.ptr, %n: i64) -> i1 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c5 = arith.constant 5 : i64
  %z32 = arith.constant 0 : i32
  %plen = llvm.call @strlen(%path) : (!llvm.ptr) -> i64
  %tl0 = arith.addi %plen, %c5 : i64
  %tmp = llvm.call @malloc(%tl0) : (i64) -> !llvm.ptr
  %a = llvm.call @memcpy(%tmp, %path, %plen) : (!llvm.ptr, !llvm.ptr, i64) -> !llvm.ptr
  %kt = llvm.mlir.addressof @k_tmp : !llvm.ptr
  %tend = func.call @off(%tmp, %plen) : (!llvm.ptr, i64) -> !llvm.ptr
  %b = llvm.call @memcpy(%tend, %kt, %c5) : (!llvm.ptr, !llvm.ptr, i64) -> !llvm.ptr
  // O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC
  %flags = arith.constant 524865 : i32
  %mode = arith.constant 420 : i32
  %fd = llvm.call @open(%tmp, %flags, %mode) vararg(!llvm.func<i32 (ptr, i32, ...)>) : (!llvm.ptr, i32, i32) -> i32
  %opened = arith.cmpi sge, %fd, %z32 : i32
  %ok = scf.if %opened -> (i1) {
    %w = llvm.call @write(%fd, %p, %n) : (i32, !llvm.ptr, i64) -> i64
    %all = arith.cmpi eq, %w, %n : i64
    %c = llvm.call @close(%fd) : (i32) -> i32
    %closed = arith.cmpi eq, %c, %z32 : i32
    %wrote = arith.andi %all, %closed : i1
    %r = scf.if %wrote -> (i1) {
      %rn = llvm.call @rename(%tmp, %path) : (!llvm.ptr, !llvm.ptr) -> i32
      %moved = arith.cmpi eq, %rn, %z32 : i32
      scf.yield %moved : i1
    } else {
      %f = arith.constant false
      scf.yield %f : i1
    }
    scf.yield %r : i1
  } else {
    %f = arith.constant false
    scf.yield %f : i1
  }
  llvm.call @free(%tmp) : (!llvm.ptr) -> ()
  return %ok : i1
}
