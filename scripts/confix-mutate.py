#!/usr/bin/env python3
"""Mutants of lowered/nixeval/JsonRead.mlir (builtins.fromJSON's reader, the body of confix.checked and the reification of its rows)
against scripts/confix-check.cc: the check can fail only if it fails here.  (Before the port to MLIR this mutated include/Composite/Confix.h.)

One mutant per site of an operator in the .mlir: a comparison predicate turned (eq/ne, ult/ule, ugt/uge, slt/sle, sgt/sge), an integer
constant moved by one, andi with ori, addi with subi, a select's two values swapped.  Each is lowered as lib/CMakeLists.txt lowers the
module (mlnix-opt --trikeshed-lower-cursors; mlir-opt's buffer pipeline with the cf loops lifted; mlir-translate; clang -O1) and linked
with the check, which is compiled once.
  stage 1  every mutant, run small
  stage 2  the survivors, run medium (a timeout is reported as a timeout, never counted as a kill)
The check stops with a mismatch when a reading does not end within 10 s (the oracle ends on every text), so a mutant that loops
is killed, not timed out.  What survives is compared with EQUIVALENT below: a mutant whose program means what the original's does,
with the reason.  A survivor that is not in the table is a case the check does not have, and the exit status is 1.  A constant
moved out of its type's range (-2^63 - 1 in i64, -129 in i8) is not a program and is not made.

usage: confix-mutate.py [--work DIR] [--jobs N] [--lines A-B] [--sample K] [--small "3000 4 3"] [--medium "20000 5 4"]
(DIR is made if it does not exist and kept; without --work a temporary one is used.  Needs `ninja -C build` (build/bin/mlnix-opt);
LLVM_BIN names the directory of mlir-opt, mlir-translate and clang, CXX the compiler of the check.)"""
import concurrent.futures, os, random, re, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
def opt(name, default):
    return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else default
small, medium = opt("--small", "3000 4 3").split(), opt("--medium", "20000 5 4").split()
lo, hi = (int(x) for x in opt("--lines", "1-100000").split("-"))
jobs = int(opt("--jobs", str(os.cpu_count() or 4)))
sample = int(opt("--sample", "0"))
work = opt("--work", "") or tempfile.mkdtemp(prefix="json-mutants-")
os.makedirs(work, exist_ok=True)
llvm = os.environ.get("LLVM_BIN", "/opt/homebrew/opt/llvm/bin")
cxx = os.environ.get("CXX", "c++")
source = os.path.join(ROOT, "lowered/nixeval/JsonRead.mlir")
checker = os.path.join(ROOT, "scripts/confix-check.cc")
PIPE = ["--lift-cf-to-scf", "--convert-ub-to-llvm", "--ownership-based-buffer-deallocation", "--canonicalize",
        "--buffer-deallocation-simplification", "--bufferization-lower-deallocations", "--convert-scf-to-cf", "--expand-strided-metadata",
        "--lower-affine", "--finalize-memref-to-llvm", "--convert-scf-to-cf", "--convert-arith-to-llvm", "--convert-index-to-llvm",
        "--convert-cf-to-llvm", "--convert-func-to-llvm", "--reconcile-unrealized-casts"]
lines = open(source).read().split("\n")

# Mutants whose program does what the original does.  Key: the function, the line from its first characters, the mutations.
EQUIVALENT = [
    ("js_at", "%m1 = arith.constant -1 : i32", ["-1 -> 0", "-1 -> -2"],
     "the byte past the end: every caller tests the offset against n first, or compares the byte with a printable one, which 0 and -2 are not either"),
    ("js_string", "%ctl = arith.cmpi slt, %c, %ksp", ["slt -> sle"], "c is never 0x20 here: the run of plain bytes above takes every byte from 0x20 up that is not a quote or a backslash"),
    ("js_number", "%c18 = arith.constant 18 : i64", ["18 -> 17"], "the count of digits only chooses whether the magnitude is checked; 18 digits cannot overflow, so the check finds what the shortcut assumes"),
    ("js_number", "%big = arith.cmpi ugt, %digits, %c18", ["ugt -> uge"], "as above"),
    ("js_number", "%digits = arith.subi %p1, %d0", ["arith.subi -> arith.addi"], "as above: every number is checked, which reads the same kind"),
    ("js_number", "%k2 = arith.constant 2 : i32", ["2 -> 3"], "the kind Unsigned is a name: the select that makes it and the test that reads it use the same constant"),
    ("js_hexv", "%k57 = arith.constant 57 : i32", ["57 -> 58"], "the scan has checked the four digits: ':' (58) is never one of them"),
    ("js_hexv", "%k97 = arith.constant 97 : i32", ["97 -> 96"], "as above: '`' (96) is never one of them"),
    ("js_utf8", "%c0 = arith.constant 0 : i64", ["0 -> -1"], "with `shown` always taken, a NUL is shown as U+2400; a NUL is decoded only for the Nul fault's message, where shown is 1"),
    ("js_mk_double", "%z8 = arith.constant 0 : i8", ["0 -> 1", "0 -> -1"], "strtod stops at the first byte that does not continue the number, and 0x01 and 0xff do not; the span is exactly the number"),
    ("js_mk_string", "%c0 = arith.constant 0 : i64", ["0 -> 1", "0 -> -1"], "every string is decoded, which gives a string without escapes its own bytes: only the time changes"),
    ("js_mk_object", "%to = arith.andi %sp, %mask", ["arith.andi -> arith.ori"], "in the room of the keys: the room only grows (the decode loop's own andi is killed)"),
    ("js_mk_object", "%d = arith.subi %to, %from", ["arith.subi -> arith.addi"], "the room of the keys only grows"),
    ("js_mk_object", "%d1 = arith.subi %d, %c1", ["arith.subi -> arith.addi"], "the room of the keys only grows"),
    ("js_reify", "%c2 = arith.constant 2 : i64", ["2 -> 3", "2 -> 1"],
     "the walk reads rowCap or n words for rows, both at least rows; a row past the last has no Value made for it and is passed over"),
]

TURN = {"eq": "ne", "ne": "eq", "ult": "ule", "ule": "ult", "ugt": "uge", "uge": "ugt", "slt": "sle", "sle": "slt", "sgt": "sge", "sge": "sgt"}
sites = []  # (line number, the mutant's line, label)
func_of = {}
func = ""
for i, raw in enumerate(lines, 1):
    fm = re.match(r"func\.func (?:private )?@(\w+)", raw)
    if fm:
        func = fm.group(1)
    func_of[i] = func
    if i < lo or i > hi or raw.lstrip().startswith("//") or "llvm.mlir.global" in raw:
        continue
    m = re.search(r"arith\.cmpi (\w+),", raw)
    if m and m.group(1) in TURN:
        sites.append((i, raw[:m.start(1)] + TURN[m.group(1)] + raw[m.end(1):], m.group(1) + " -> " + TURN[m.group(1)]))
    m = re.search(r"arith\.constant (-?\d+) : (i8|i32|i64|index)", raw)
    if m:
        bits = {"i8": 8, "i32": 32, "i64": 64, "index": 64}[m.group(2)]
        for d in (1, -1):
            v = int(m.group(1)) + d
            if not -(1 << (bits - 1)) <= v < (1 << bits):
                continue
            sites.append((i, raw[:m.start(1)] + str(v) + raw[m.end(1):], "%s -> %d" % (m.group(1), v)))
    for a, b in (("arith.andi", "arith.ori"), ("arith.ori", "arith.andi"), ("arith.addi", "arith.subi"), ("arith.subi", "arith.addi")):
        if a + " " in raw:
            sites.append((i, raw.replace(a + " ", b + " ", 1), a + " -> " + b))
    m = re.search(r"arith\.select (%\w+), (%[\w#]+), (%[\w#]+)", raw)
    if m:
        sites.append((i, raw[:m.start(2)] + m.group(3) + ", " + m.group(2) + raw[m.end(3):], "select swapped"))
if sample and sample < len(sites):
    sites = sorted(random.Random(7).sample(sites, sample))
print("%d mutants of %s, work in %s" % (len(sites), os.path.relpath(source, ROOT), work), flush=True)

sysroot = []
if subprocess.run(["which", "xcrun"], capture_output=True).returncode == 0:
    sysroot = ["-isysroot", subprocess.run(["xcrun", "--show-sdk-path"], capture_output=True, text=True).stdout.strip()]
check_o = os.path.join(work, "check.o")
subprocess.run([cxx] + sysroot + ["-std=c++20", "-O1", "-c", checker, "-o", check_o], check=True)

def build(k):
    line, new, label = sites[k]
    d = os.path.join(work, "m%04d" % k)
    os.makedirs(d, exist_ok=True)
    text = list(lines)
    text[line - 1] = new
    open(d + "/JsonRead.mlir", "w").write("\n".join(text))
    steps = [[os.path.join(ROOT, "build/bin/mlnix-opt"), d + "/JsonRead.mlir", "--trikeshed-lower-cursors", "-o", d + "/cur.mlir"],
             [llvm + "/mlir-opt", d + "/cur.mlir"] + PIPE + ["-o", d + "/low.mlir"],
             [llvm + "/mlir-translate", "--mlir-to-llvmir", d + "/low.mlir", "-o", d + "/m.ll"],
             [llvm + "/clang", "-O1", "-Wno-override-module", "-c", d + "/m.ll", "-o", d + "/m.o"],
             [cxx] + sysroot + [check_o, d + "/m.o", "-o", d + "/check"]]
    for s in steps:
        if subprocess.run(s, capture_output=True).returncode:
            return None
    return d + "/check"

def run(exe, counts, timeout):
    try:
        p = subprocess.run([exe] + counts, capture_output=True, timeout=timeout)
        return "killed" if p.returncode else "survived"
    except subprocess.TimeoutExpired:
        return "timeout"

def s1(k):
    exe = build(k)
    return ("invalid", None) if exe is None else (run(exe, small, 120), exe)
with concurrent.futures.ThreadPoolExecutor(jobs) as ex:
    r1 = dict(zip(range(len(sites)), ex.map(s1, range(len(sites)))))
alive = [k for k in r1 if r1[k][0] in ("survived", "timeout")]
print("stage 1 (small %s): %d killed, %d survived or timed out, %d did not build" % (" ".join(small), sum(r[0] == "killed" for r in r1.values()),
      len(alive), sum(r[0] == "invalid" for r in r1.values())), flush=True)
with concurrent.futures.ThreadPoolExecutor(max(1, jobs // 2)) as ex:
    r2 = dict(zip(alive, ex.map(lambda k: run(r1[k][1], medium, 1800), alive)))
left = [k for k in alive if r2[k] != "killed"]
print("stage 2 (medium %s): %d killed of %d" % (" ".join(medium), len(alive) - len(left), len(alive)))
def reason(k):
    line, new, label = sites[k]
    for f, prefix, labels, why in EQUIVALENT:
        if func_of[line] == f and lines[line - 1].strip().startswith(prefix) and label in labels:
            return why
    return None
unexpected = [k for k in left if reason(k) is None]
print("survived: %d, of which %d are the equivalent mutants in the table and %d are not" % (len(left), len(left) - len(unexpected), len(unexpected)))
for k in left:
    line, new, label = sites[k]
    print("  %-8s line %4d %-14s %-24s %s  [%s]" % (r2[k], line, func_of[line], label, lines[line - 1].strip()[:70],
          "equivalent" if reason(k) else "UNEXPECTED: the check has no case that tells it from the original"))
sys.exit(1 if unexpected else 0)
