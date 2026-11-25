#!/usr/bin/env python3
"""Writes lowered/tools/ToolFlags.mlir: tools/mlnix.cpp's option-name table (sorted names with their codes) and the
functions over it and over the text lists (mlnix_tf_lookup, mlnix_tf_lines, mlnix_tf_primops, mlnix_tf_count).
Prints the C++ enum that the bridge in tools/mlnix.cpp uses.

  python3 scripts/gen_tool_flags.py WORKTREE
"""
import sys, os

WT = sys.argv[1]

# (name, code).  Names are unique; a code may serve several spellings.
NAMES = [
    # parseCommon (every evaluating and store command)
    ("-I", "INCLUDE"), ("--include", "INCLUDE"), ("--arg", "ARG"), ("--argstr", "ARGSTR"),
    ("-A", "ATTR"), ("--attr", "ATTR"), ("-E", "EXPR"), ("--expr", "EXPR"),
    ("--show-trace", "SHOW_TRACE"), ("--trace-verbose", "TRACE_VERBOSE"), ("--abort-on-warn", "ABORT_ON_WARN"),
    ("--pure-eval", "PURE_EVAL"), ("--impure", "IMPURE"), ("--restrict-eval", "RESTRICT_EVAL"),
    ("--extra-experimental-features", "EXPFEAT"), ("--experimental-features", "EXPFEAT"), ("--option", "OPTION"),
    ("--lint-absolute-path-literals", "LINT_ABS"), ("--lint-short-path-literals", "LINT_SHORT"),
    ("--lint-url-literals", "LINT_URL"), ("--system", "SYSTEM"), ("--store-dir", "STORE_DIR"), ("--store", "STORE"),
    ("--readonly-mode", "READONLY"), ("--read-write-mode", "READWRITE"), ("-K", "KEEP_FAILED"),
    ("--keep-failed", "KEEP_FAILED"), ("-j", "JOBS"), ("--max-jobs", "JOBS"), ("--cores", "CORES"),
    ("--no-opt", "NO_OPT"), ("-v", "NOOP"), ("--verbose", "NOOP"), ("-Q", "NOOP"), ("--no-build-output", "NOOP"),
    ("--quiet", "NOOP"), ("--no-substitute", "NOOP"), ("--fallback", "NOOP"), ("-L", "NOOP"),
    ("--print-build-logs", "NOOP"),
    # cmdInstantiate (instantiate, build, eval, parse, emit-mlir, run-mlir)
    ("--eval", "EVAL"), ("--eval-only", "EVAL"), ("--parse", "PARSE"), ("--parse-only", "PARSE"),
    ("--emit-mlir", "EMIT_MLIR"), ("--strict", "STRICT"), ("--json", "JSON"), ("--xml", "XML"), ("--raw", "RAW"),
    ("--no-location", "NO_LOCATION"), ("--find-file", "FIND_FILE"), ("--dry-run", "DRY_RUN"),
    ("--add-root", "ADD_ROOT"), ("--indirect", "INDIRECT"), ("-o", "OUT_LINK"), ("--out-link", "OUT_LINK"),
    ("--no-out-link", "NO_OUT_LINK"), ("-", "STDIN"),
    # cmdStore: the operation, then the query flags
    ("--add", "OP_ADD"), ("--add-fixed", "OP_ADD_FIXED"), ("--realise", "OP_REALISE"), ("-r", "OP_REALISE"),
    ("--query", "OP_QUERY"), ("-q", "OP_QUERY"), ("--dump", "OP_DUMP"), ("--gc", "OP_GC"),
    ("--delete", "OP_DELETE"), ("--verify-path", "OP_VERIFY"), ("--verify", "OP_VERIFY"),
    ("--print-env", "OP_PRINT_ENV"), ("--restore", "OP_RESTORE"), ("--read-log", "OP_OTHER"),
    ("--dump-db", "OP_OTHER"),
    ("--references", "Q_REFS"), ("--requisites", "Q_REQS"), ("-R", "Q_REQS"), ("--referrers", "Q_REFERRERS"),
    ("--deriver", "Q_DERIVER"), ("-d", "Q_DERIVER"), ("--outputs", "Q_OUTPUTS"), ("--hash", "Q_HASH"),
    ("--size", "Q_SIZE"), ("--include-outputs", "INCLUDE_OUTPUTS"), ("--print-dead", "PRINT_INVALID"),
    ("--print-live", "PRINT_INVALID"), ("--recursive", "RECURSIVE"),
    # cmdHash
    ("--type", "TYPE"), ("--flat", "FLAT"), ("--base32", "BASE32"), ("--nix32", "BASE32"), ("--base16", "BASE16"),
    ("--base64", "BASE64"), ("--sri", "SRI"), ("--truncate", "TRUNCATE"), ("--to-base32", "TO_BASE32"),
    ("--to-nix32", "TO_NIX32"), ("--to-base16", "TO_BASE16"), ("--to-base64", "TO_BASE64"), ("--to-sri", "TO_SRI"),
    ("path", "MODE_PATH"), ("file", "MODE_FILE"),
    # realMain's commands and argv[0] names
    ("--help", "HELP"), ("-h", "HELP"), ("help", "HELP"), ("--version", "VERSION"),
    ("instantiate", "INSTANTIATE"), ("build", "BUILD"), ("eval", "EVAL_CMD"), ("parse", "PARSE_CMD"),
    ("emit-mlir", "EMIT_CMD"), ("run-mlir", "RUN_CMD"), ("primops", "PRIMOPS"), ("store", "STORE_CMD"),
    ("hash", "HASH_CMD"), ("derivation", "DERIVATION"), ("show", "SHOW"),
    ("nix", "PROG_NIX"), ("nix-instantiate", "PROG_INSTANTIATE"), ("nix-build", "PROG_BUILD"),
    ("nix-store", "PROG_STORE"), ("nix-hash", "PROG_HASH"),
    # option names and values: --option NAME VALUE, the --lint-* values, --store values, experimental words, NIX_REMOTE
    ("max-call-depth", "VAL_MAX_CALL_DEPTH"), ("extra-experimental-features", "VAL_EXPFEAT"),
    ("experimental-features", "VAL_EXPFEAT"), ("system", "VAL_SYSTEM"), ("pure-eval", "VAL_PURE_EVAL"),
    ("true", "TRUE"), ("warn", "WARN"), ("fatal", "FATAL"), ("ignore", "IGNORE"),
    ("pipe-operators", "WORD_PIPE"), ("parse-toml-timestamps", "WORD_TOML"), ("dummy://", "DUMMY"),
    ("auto", "AUTO"), ("local", "LOCAL"), ("daemon", "DAEMON"),
]

names = [n for n, _ in NAMES]
assert len(set(names)) == len(names), "duplicate option name"
codes = []
for _, c in NAMES:
    if c not in codes:
        codes.append(c)
code_no = {c: i + 1 for i, c in enumerate(codes)}  # 0 is unused; the lookup gives -1 for no option

srt = sorted(NAMES, key=lambda nc: nc[0].encode())  # byte order: what trikeshed.compare unsigned gives
blob = b"".join(n.encode() for n, _ in srt)
offs, lens, cs = [], [], []
o = 0
for n, c in srt:
    b = n.encode()
    offs.append(o)
    lens.append(len(b))
    cs.append(code_no[c])
    o += len(b)
packed = [(offs[i] << 32) | lens[i] for i in range(len(srt))]
N = len(srt)
assert N < 2**31 and len(blob) < 2**31 and max(lens) < 2**32

MLIR = r'''// tools/mlnix.cpp's option names: the flags of every command, the --option names and values, the experimental words,
// the argv[0] and command names.  One table of @NAMES_N@ names sorted in byte order (the blob, each name's offset and
// length packed as offset << 32 | length, and its code); mlnix_tf_lookup bisects it with trikeshed.compare unsigned,
// as Text's operator< orders names.  The bridge in tools/mlnix.cpp keeps each switch on the code, getenv, the usage
// wording and each option's effect.
//
// The same module writes the lists of mlnix.cpp's output texts, each one combineAll drained once into the caller's
// room (a short room returns -need-2: the bridge resizes and calls again, as ToolOpts.mlir does):
//   mlnix_tf_lines    n windows (ptr, len) one line each: "text\n", or with mode 1 "deleting 'text'\n" (--gc)
//   mlnix_tf_primops  n rows (name ptr, name len, arity) sorted by name: "name arity\n" (the primops command)
//   mlnix_tf_count    "N store paths deleted" (--gc's count, which the bridge prints to stderr)
// The codes are generated by scripts/gen_tool_flags.py (the enum in tools/mlnix.cpp).  Helper names are module-unique (tf_*):
// convert-func-to-llvm exports a func.func private as a global symbol.
!b = !trikeshed.series<i8>
!s64 = !trikeshed.series<i64>
!tp = !trikeshed.twinpacked<i32>
!sp = !trikeshed.series<!tp>
!m = memref<?xi8, strided<[1], offset: ?>>
!m64 = memref<?xi64, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

memref.global "private" constant @tf_blob : memref<@BLOB_N@xi8> = dense<"@BLOB_HEX@">
memref.global "private" constant @tf_packed : memref<@NAMES_N@xi64> = dense<[@PACKED@]>
memref.global "private" constant @tf_codes : memref<@NAMES_N@xi64> = dense<[@CODES@]>
memref.global "private" constant @tf_minus : memref<1xi8> = dense<"0x2D">
memref.global "private" constant @tf_deleting : memref<10xi8> = dense<"0x64656C6574696E672027">
memref.global "private" constant @tf_quote : memref<1xi8> = dense<"0x27">
memref.global "private" constant @tf_nl : memref<1xi8> = dense<"0x0A">
memref.global "private" constant @tf_space : memref<1xi8> = dense<"0x20">
memref.global "private" constant @tf_storepaths : memref<20xi8> = dense<"0x2073746F72652070617468732064656C65746564">
memref.global "private" constant @tf_powers : memref<19xi64> = dense<[1, 10, 100, 1000, 10000, 100000, 1000000, 10000000, 100000000, 1000000000, 10000000000, 100000000000, 1000000000000, 10000000000000, 100000000000000, 1000000000000000, 10000000000000000, 100000000000000000, 1000000000000000000]>

// the descriptor of n bytes at p
func.func private @tf_desc(%p: !llvm.ptr, %n: i64) -> !d {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %u = llvm.mlir.undef : !d
  %a = llvm.insertvalue %p, %u[0] : !d
  %b1 = llvm.insertvalue %p, %a[1] : !d
  %c = llvm.insertvalue %c0, %b1[2] : !d
  %e = llvm.insertvalue %n, %c[3, 0] : !d
  %f = llvm.insertvalue %c1, %e[4, 0] : !d
  return %f : !d
}

// v's digits as printf's %ld writes them (utils/mlnixci/src/text.mlir's digits): a fold over the powers of ten
// gives the count, a series gives each digit, a '-' goes in front of a negative v.  Returns the combined text.
func.func private @tf_digits(%v: i64) -> !b {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c18 = arith.constant 18 : index
  %z = arith.constant 0 : i64
  %ten = arith.constant 10 : i64
  %d0 = arith.constant 48 : i8
  %neg = arith.cmpi slt, %v, %z : i64
  %minusv = arith.subi %z, %v : i64
  %mag = arith.select %neg, %minusv, %v : i64
  %pg = memref.get_global @tf_powers : memref<19xi64>
  %powers = trikeshed.text %pg : memref<19xi64> -> !s64
  %above = trikeshed.slice %powers[%c1, %c18] : !s64 -> !s64
  %count = trikeshed.fold %above, %c1 : !s64, index -> index {
  ^bb0(%acc: index, %p: i64):
    %reach = arith.cmpi uge, %mag, %p : i64
    %more = arith.addi %acc, %c1 : index
    %r = arith.select %reach, %more, %acc : index
    trikeshed.yield %r : index
  }
  %digits = trikeshed.series %count : !b {
  ^bb0(%k: index):
    %last = arith.subi %count, %c1 : index
    %e = arith.subi %last, %k : index
    %p = trikeshed.at %powers[%e] : !s64, index -> i64
    %q = arith.divui %mag, %p : i64
    %dg = arith.remui %q, %ten : i64
    %d8 = arith.trunci %dg : i64 to i8
    %c = arith.addi %d8, %d0 : i8
    trikeshed.yield %c : i8
  }
  %mg = memref.get_global @tf_minus : memref<1xi8>
  %minus = trikeshed.text %mg : memref<1xi8> -> !b
  %signs = arith.select %neg, %c1, %c0 : index
  %sign = trikeshed.slice %minus[%c0, %signs] : !b -> !b
  %all = trikeshed.combine %sign, %digits : !b, !b -> !b
  return %all : !b
}

// size and drain of the combined text %all into the caller's room: the bytes written, or -need-2 when cap is short
func.func private @tf_finish(%all: !b, %into: !llvm.ptr, %cap: i64) -> i64 {
  %m2 = arith.constant -2 : i64
  %sz = trikeshed.size %all : !b
  %szi = arith.index_cast %sz : index to i64
  %neg = arith.subi %m2, %szi : i64
  %short = arith.cmpi ult, %cap, %szi : i64
  %r = scf.if %short -> i64 {
    scf.yield %neg : i64
  } else {
    %d = func.call @tf_desc(%into, %cap) : (!llvm.ptr, i64) -> !d
    %o = builtin.unrealized_conversion_cast %d : !d to !m
    %w = trikeshed.drain %all, %o : !b, !m -> index
    %wi = arith.index_cast %w : index to i64
    scf.yield %wi : i64
  }
  return %r : i64
}

// the option named by the n bytes at p: its code, or -1 when the table has no such name
func.func @mlnix_tf_lookup(%p: !llvm.ptr, %n: i64) -> i64 {
  %c32 = arith.constant 32 : i64
  %c4294967295 = arith.constant 4294967295 : i64
  %m1 = arith.constant -1 : i64
  %c0 = arith.constant 0 : index
  %kd = func.call @tf_desc(%p, %n) : (!llvm.ptr, i64) -> !d
  %km = builtin.unrealized_conversion_cast %kd : !d to !m
  %key = builtin.unrealized_conversion_cast %km : !m to !b
  %bg = memref.get_global @tf_blob : memref<@BLOB_N@xi8>
  %blob = trikeshed.text %bg : memref<@BLOB_N@xi8> -> !b
  %pg = memref.get_global @tf_packed : memref<@NAMES_N@xi64>
  %packed = trikeshed.text %pg : memref<@NAMES_N@xi64> -> !s64
  %cg = memref.get_global @tf_codes : memref<@NAMES_N@xi64>
  %codes = trikeshed.text %cg : memref<@NAMES_N@xi64> -> !s64
  %j = trikeshed.bisect %packed, %key : !s64, !b -> index by {
  ^bb0(%e: i64, %k: !b):
    %off64 = arith.shrui %e, %c32 : i64
    %len64 = arith.andi %e, %c4294967295 : i64
    %off = arith.index_cast %off64 : i64 to index
    %len = arith.index_cast %len64 : i64 to index
    %s = trikeshed.slice %blob[%off, %len] : !b -> !b
    %c = trikeshed.compare %s, %k unsigned : !b, !b
    trikeshed.yield %c : i32
  }
  %hit = arith.cmpi sge, %j, %c0 : index
  %code = scf.if %hit -> i64 {
    %cd = trikeshed.at %codes[%j] : !s64, index -> i64
    scf.yield %cd : i64
  } else {
    scf.yield %m1 : i64
  }
  return %code : i64
}

// n windows (ptr, len) in recs, one line each; mode 1 writes "deleting 'x'" (the --gc lines), else "x"
func.func @mlnix_tf_lines(%recs: !llvm.ptr, %n: i64, %mode: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c2 = arith.constant 2 : index
  %c1i = arith.constant 1 : i64
  %c2i = arith.constant 2 : i64
  %c10 = arith.constant 10 : index
  %two = arith.muli %n, %c2i : i64
  %rd = func.call @tf_desc(%recs, %two) : (!llvm.ptr, i64) -> !d
  %rm = builtin.unrealized_conversion_cast %rd : !d to !m64
  %dg = memref.get_global @tf_deleting : memref<10xi8>
  %deleting = trikeshed.text %dg : memref<10xi8> -> !b
  %qg = memref.get_global @tf_quote : memref<1xi8>
  %quote = trikeshed.text %qg : memref<1xi8> -> !b
  %ng = memref.get_global @tf_nl : memref<1xi8>
  %nl = trikeshed.text %ng : memref<1xi8> -> !b
  %ni = arith.index_cast %n : i64 to index
  %is_del = arith.cmpi eq, %mode, %c1i : i64
  %pre_len = arith.select %is_del, %c10, %c0 : index
  %suf_len = arith.select %is_del, %c1, %c0 : index
  %all, %where = trikeshed.combineAll %ni : !b, !sp {
  ^bb0(%k: index):
    %k2 = arith.muli %k, %c2 : index
    %k2p1 = arith.addi %k2, %c1 : index
    %pk = memref.load %rm[%k2] : !m64
    %lk = memref.load %rm[%k2p1] : !m64
    %pp = llvm.inttoptr %pk : i64 to !llvm.ptr
    %rwd = func.call @tf_desc(%pp, %lk) : (!llvm.ptr, i64) -> !d
    %rwm = builtin.unrealized_conversion_cast %rwd : !d to !m
    %row = builtin.unrealized_conversion_cast %rwm : !m to !b
    %pre = trikeshed.slice %deleting[%c0, %pre_len] : !b -> !b
    %suf = trikeshed.slice %quote[%c0, %suf_len] : !b -> !b
    %part = trikeshed.combine %pre, %row, %suf, %nl : !b, !b, !b, !b -> !b
    trikeshed.yield %part : !b
  }
  %r = func.call @tf_finish(%all, %into, %cap) : (!b, !llvm.ptr, i64) -> i64
  return %r : i64
}

// n rows (name ptr, name len, arity) in recs, in any order: sorted by name (trikeshed.sorted over the row indices,
// names compared unsigned), one line "name arity" each
func.func @mlnix_tf_primops(%recs: !llvm.ptr, %n: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c2 = arith.constant 2 : index
  %c3 = arith.constant 3 : index
  %c1i = arith.constant 1 : i64
  %c2i = arith.constant 2 : i64
  %c3i = arith.constant 3 : i64
  %cells = arith.muli %n, %c3i : i64
  %rd = func.call @tf_desc(%recs, %cells) : (!llvm.ptr, i64) -> !d
  %rm = builtin.unrealized_conversion_cast %rd : !d to !m64
  %ni = arith.index_cast %n : i64 to index
  %ng = memref.get_global @tf_nl : memref<1xi8>
  %nl = trikeshed.text %ng : memref<1xi8> -> !b
  %sg = memref.get_global @tf_space : memref<1xi8>
  %space = trikeshed.text %sg : memref<1xi8> -> !b
  %idx = trikeshed.series %ni : !s64 {
  ^bb0(%i: index):
    %i64 = arith.index_cast %i : index to i64
    trikeshed.yield %i64 : i64
  }
  %srt = trikeshed.sorted %idx : !s64 -> !s64 by {
  ^bb0(%x: i64, %y: i64):
    %xi = arith.index_cast %x : i64 to index
    %yi = arith.index_cast %y : i64 to index
    %x3 = arith.muli %xi, %c3 : index
    %x3b = arith.addi %x3, %c1 : index
    %y3 = arith.muli %yi, %c3 : index
    %y3b = arith.addi %y3, %c1 : index
    %xp = memref.load %rm[%x3] : !m64
    %xl = memref.load %rm[%x3b] : !m64
    %yp = memref.load %rm[%y3] : !m64
    %yl = memref.load %rm[%y3b] : !m64
    %xpp = llvm.inttoptr %xp : i64 to !llvm.ptr
    %ypp = llvm.inttoptr %yp : i64 to !llvm.ptr
    %xd = func.call @tf_desc(%xpp, %xl) : (!llvm.ptr, i64) -> !d
    %xm = builtin.unrealized_conversion_cast %xd : !d to !m
    %xb = builtin.unrealized_conversion_cast %xm : !m to !b
    %yd = func.call @tf_desc(%ypp, %yl) : (!llvm.ptr, i64) -> !d
    %ym = builtin.unrealized_conversion_cast %yd : !d to !m
    %yb = builtin.unrealized_conversion_cast %ym : !m to !b
    %c = trikeshed.compare %xb, %yb unsigned : !b, !b
    trikeshed.yield %c : i32
  }
  %all, %where = trikeshed.combineAll %ni : !b, !sp {
  ^bb0(%k: index):
    %e = trikeshed.at %srt[%k] : !s64, index -> i64
    %ei = arith.index_cast %e : i64 to index
    %b3 = arith.muli %ei, %c3 : index
    %b3p1 = arith.addi %b3, %c1 : index
    %b3p2 = arith.addi %b3, %c2 : index
    %pk = memref.load %rm[%b3] : !m64
    %lk = memref.load %rm[%b3p1] : !m64
    %ar = memref.load %rm[%b3p2] : !m64
    %pp = llvm.inttoptr %pk : i64 to !llvm.ptr
    %rwd = func.call @tf_desc(%pp, %lk) : (!llvm.ptr, i64) -> !d
    %rwm = builtin.unrealized_conversion_cast %rwd : !d to !m
    %name = builtin.unrealized_conversion_cast %rwm : !m to !b
    %digits = func.call @tf_digits(%ar) : (i64) -> !b
    %part = trikeshed.combine %name, %space, %digits, %nl : !b, !b, !b, !b -> !b
    trikeshed.yield %part : !b
  }
  %r = func.call @tf_finish(%all, %into, %cap) : (!b, !llvm.ptr, i64) -> i64
  return %r : i64
}

// "N store paths deleted" for N = n (the --gc count; the bridge prints it with a newline to stderr)
func.func @mlnix_tf_count(%n: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %dg = func.call @tf_digits(%n) : (i64) -> !b
  %sg = memref.get_global @tf_storepaths : memref<20xi8>
  %sfx = trikeshed.text %sg : memref<20xi8> -> !b
  %all = trikeshed.combine %dg, %sfx : !b, !b -> !b
  %r = func.call @tf_finish(%all, %into, %cap) : (!b, !llvm.ptr, i64) -> i64
  return %r : i64
}
'''

out = (MLIR.replace("@NAMES_N@", str(N)).replace("@BLOB_N@", str(len(blob)))
       .replace("@BLOB_HEX@", "0x" + blob.hex().upper())
       .replace("@PACKED@", ", ".join(str(x) for x in packed))
       .replace("@CODES@", ", ".join(str(x) for x in cs)))
path = os.path.join(WT, "lowered/tools/ToolFlags.mlir")
open(path, "w").write(out)
print("names", N, "codes", len(codes), "blob bytes", len(blob), "->", path)
print("// C++ enum (tools/mlnix.cpp)")
print("enum Opt : int64_t {")
print("  OPT_NONE = -1,")
for c in codes:
    print(f"  OPT_{c} = {code_no[c]},")
print("};")
