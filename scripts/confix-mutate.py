#!/usr/bin/env python3
"""Mutants of include/Composite/Confix.h against scripts/confix-check.cc: the check can fail only if it fails here.

One mutant per site of an operator (a comparison flipped, a constant moved by one, && with ||, + with -, true with false, a ! dropped), the
header copied with that one change and the check built with it.
  stage 1  every mutant, built -O1, run small
  stage 2  the survivors, run medium (a timeout is reported as a timeout, never counted as a kill)
  stage 3  the survivors, built with AddressSanitizer and UndefinedBehaviorSanitizer (undefined behaviour fatal), run medium
  stage 4  (--full) the survivors, run full, a few at a time
What survives every stage is compared with EQUIVALENT below: a mutant whose program means what the original's does, with the reason.  A survivor
that is not in the table is a case the check does not have, and the exit status is 1.

usage: confix-mutate.py [--work DIR] [--jobs N] [--lines A-B] [--full "100000 6 4"] [--small "3000 4 3"] [--medium "20000 5 4"]
(DIR must not exist; it is removed at the end unless --work is given.  CXX names the compiler, c++ by default.  About 3 minutes without --full.)"""
import concurrent.futures, os, re, shutil, subprocess, sys, tempfile, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
def opt(name, default):
    return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else default
small, medium, full = opt("--small", "3000 4 3").split(), opt("--medium", "20000 5 4").split(), opt("--full", "100000 6 4").split()
lo, hi = (int(x) for x in opt("--lines", "1-100000").split("-"))
jobs = int(opt("--jobs", str(os.cpu_count() or 4)))
cxx = os.environ.get("CXX", "c++")
sysroot = []
if shutil.which("xcrun"):
    sysroot = ["-isysroot", subprocess.run(["xcrun", "--show-sdk-path"], capture_output=True, text=True).stdout.strip()]
header = os.path.join(ROOT, "include/Composite/Confix.h")
checker = os.path.join(ROOT, "scripts/confix-check.cc")
lines = open(header).read().split("\n")
ENV = dict(os.environ, ASAN_OPTIONS="allow_user_poisoning=0:detect_leaks=0")

# Mutants whose program does what the original does.  Key: the line, from its first characters, and the mutation made on it.
EQUIVALENT = [
    ("uint32_t at = 0, end = 0;", ["0 -> 1"], "the two offsets of a Scan that found no fault say nothing, and a caller reads them only when the Scan is a fault"),
    ("auto bad = [&](Fault f, uint32_t at)", ["0 -> 1"], "`end` is read for Unsigned and Nul, where the scan sets it; a fault of the syntax has no end"),
    ("if (uint8_t(c) < 0x20) return bad(Fault::ControlChar", ["< -> <=", "0x20 -> 0x21"],
     "c is never 0x20 here: the run of plain bytes above takes every byte from 0x20 up that is not a quote or a backslash"),
    ("digits = p - digits;", ["- -> +"], "`digits` only chooses between the sum of the digits and the facets for a number, and both read the same value"),
    ("if (digits > 18) {", ["> -> >=", "18 -> 17"], "as above: the facets and the sum of 18 digits (which cannot overflow) agree"),
    ("uint32_t run = p + 1;", ["1 -> 0"], "the byte at p is not a backslash (the test above), so the search for the next one ends in the same place from p as from p + 1"),
    ("if (to + 1 - first <= 18) {", ["- -> +", "1 -> 2", "<= -> <", "18 -> 17"], "as above, in readLong: which way a number is read changes the time, not the value"),
    ("return negative ? int64_t(facet<text::Integer<10, true>>", ["true -> false", "false -> true"],
     "the unsigned facet reads a negative number as strtoull does, modulo 2^64, which is the same bits as the signed one; a positive number that fits is the same in both"),
]

SKIP = re.compile(r"^\s*(//|#|namespace|template|inline\s+\w[\w:<>\s,*&]*\(.*\)\s*(const\s*)?\{?\s*$|struct |enum |\}|using |static_assert)")
sites = []   # (line number, start, end, replacement, label)
for i, raw in enumerate(lines, 1):
    if i < lo or i > hi or SKIP.match(raw):
        continue
    k = raw.find(" // ")
    code = raw if k < 0 else raw[:k]
    masked = re.sub(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])+\'', lambda m: "\0" * len(m.group(0)), code)   # strings and character literals are left alone
    def add(m, rep, label):
        sites.append((i, m.start(), m.end(), rep, label))
    for m in re.finditer(r"==", masked): add(m, "!=", "== -> !=")
    for m in re.finditer(r"!=", masked): add(m, "==", "!= -> ==")
    for m in re.finditer(r"(?<![<>=!-])<=(?!=)", masked): add(m, "<", "<= -> <")
    for m in re.finditer(r"(?<![<>=!-])>=(?!=)", masked): add(m, ">", ">= -> >")
    for m in re.finditer(r"(?<![<>=!\-\w])<(?![<=\w:])", masked): add(m, "<=", "< -> <=")
    for m in re.finditer(r"(?<![<>=!\-])>(?![>=])(?=\s)", masked): add(m, ">=", "> -> >=")
    for m in re.finditer(r"&&", masked): add(m, "||", "&& -> ||")
    for m in re.finditer(r"\|\|", masked): add(m, "&&", "|| -> &&")
    for m in re.finditer(r"(?<=\s)\+(?=\s)", masked): add(m, "-", "+ -> -")
    for m in re.finditer(r"(?<=\w)\s-\s(?=[\w(])", masked): add(m, " + ", "- -> +")
    for m in re.finditer(r"\btrue\b", masked): add(m, "false", "true -> false")
    for m in re.finditer(r"\bfalse\b", masked): add(m, "true", "false -> true")
    for m in re.finditer(r"(?<![\w.])!(?!=)", masked): add(m, "", "! dropped")
    for m in re.finditer(r"\b(0[xX][0-9A-Fa-f]+|\d+)(?:ull|u|ULL|U)?\b", masked):
        txt = m.group(0)
        number = re.match(r"0[xX][0-9A-Fa-f]+|\d+", txt)
        assert number
        core = number.group(0)
        suffix = txt[len(core):]
        v = int(core, 16) if core[:2] in ("0x", "0X") else int(core)
        fmt = (lambda x: hex(x)) if core[:2] in ("0x", "0X") else str
        for d in (1, -1):
            if v + d >= 0 and not (v == 0 and d == -1):
                add(m, fmt(v + d) + suffix, "%s -> %s" % (core, fmt(v + d)))

keep = "--work" in sys.argv
work = opt("--work", "")
if keep:
    if os.path.exists(work):
        sys.exit("%s exists; name a directory that does not" % work)
    os.makedirs(work)
else:
    work = tempfile.mkdtemp(prefix="confix-mutants-")
print("%d mutation sites in %s lines %d-%d, work in %s" % (len(sites), os.path.basename(header), lo, min(hi, len(lines)), work), flush=True)

def build(k, sanitize=False):
    i, a, b, rep, label = sites[k]
    d = os.path.join(work, "m%04d" % k)
    if not os.path.isdir(d):
        os.makedirs(os.path.join(d, "Composite"))
        new = list(lines)
        new[i - 1] = lines[i - 1][:a] + rep + lines[i - 1][b:]
        open(os.path.join(d, "Composite/Confix.h"), "w").write("\n".join(new))
    exe = os.path.join(d, "check-san" if sanitize else "check")
    flags = ["-O1", "-g", "-fsanitize=address,undefined", "-fno-sanitize-recover=undefined"] if sanitize else ["-O1"]
    # only Confix.h is the mutant's: the first -I finds it there, the rest of the headers in the tree
    p = subprocess.run([cxx] + sysroot + ["-std=c++20", "-w"] + flags + ["-I", d, "-I", os.path.join(ROOT, "include"), checker, "-o", exe],
                       capture_output=True, text=True, errors="replace", timeout=600)
    return exe if p.returncode == 0 else None

def run(exe, size, timeout):
    t = time.time()
    try:
        p = subprocess.run([exe] + size, capture_output=True, text=True, errors="replace", timeout=timeout, cwd=ROOT, env=ENV)
        return ("killed" if p.returncode != 0 else "survived"), time.time() - t
    except subprocess.TimeoutExpired:
        return "timeout", time.time() - t

def stage(ks, fn, njobs):
    with concurrent.futures.ThreadPoolExecutor(njobs) as ex:
        return dict(zip(ks, ex.map(fn, ks)))

def s1(k):
    exe = build(k)
    if exe is None:
        return ("invalid", 0)
    r = run(exe, small, 300)
    if r[0] == "killed":
        shutil.rmtree(os.path.dirname(exe), ignore_errors=True)   # a mutant that is dead is not kept
    return r
ks = [k for k in range(len(sites))]
r1 = stage(ks, s1, jobs)
surv = [k for k in ks if r1[k][0] == "survived"]
print("stage 1 (small %s): %d killed, %d survived, %d timeouts, %d did not compile" % (" ".join(small), sum(r1[k][0] == "killed" for k in ks), len(surv),
      sum(r1[k][0] == "timeout" for k in ks), sum(r1[k][0] == "invalid" for k in ks)), flush=True)
r2 = stage(surv, lambda k: run(os.path.join(work, "m%04d" % k, "check"), medium, 600), max(2, jobs // 2))
surv2 = [k for k in surv if r2[k][0] != "killed"]
print("stage 2 (medium %s): %d killed, %d survived, %d timeouts" % (" ".join(medium), sum(r2[k][0] == "killed" for k in surv), sum(r2[k][0] == "survived" for k in surv),
      sum(r2[k][0] == "timeout" for k in surv)), flush=True)
def s3(k):
    exe = build(k, sanitize=True)
    return ("invalid", 0) if exe is None else run(exe, medium, 900)
r3 = stage(surv2, s3, max(2, jobs // 2))
surv3 = [k for k in surv2 if r3[k][0] != "killed"]
print("stage 3 (sanitized, medium): %d killed, %d survived, %d timeouts" % (sum(r3[k][0] == "killed" for k in surv2), sum(r3[k][0] == "survived" for k in surv2),
      sum(r3[k][0] == "timeout" for k in surv2)), flush=True)
final = {k: "survived" for k in surv3}
if "--full" in sys.argv:
    r4 = stage(surv3, lambda k: run(os.path.join(work, "m%04d" % k, "check"), full, 3000), 3)
    final = {k: r4[k][0] for k in surv3 if r4[k][0] != "killed"}
    print("stage 4 (full %s): %d killed, %d survived, %d timeouts" % (" ".join(full), sum(r4[k][0] == "killed" for k in surv3), sum(r4[k][0] == "survived" for k in surv3),
          sum(r4[k][0] == "timeout" for k in surv3)), flush=True)

def reason(k):
    i, a, b, rep, label = sites[k]
    for prefix, labels, why in EQUIVALENT:
        if lines[i - 1].strip().startswith(prefix) and label in labels:
            return why
    return None
unexpected = [k for k in final if reason(k) is None]
seen = {(p, l) for k in final if reason(k) for p, ls, _ in EQUIVALENT for l in ls if lines[sites[k][0] - 1].strip().startswith(p) and sites[k][4] == l}
print("\nsurvived every stage: %d, of which %d are the equivalent mutants in the table and %d are not" % (len(final), len(final) - len(unexpected), len(unexpected)))
for k in sorted(final, key=lambda k: sites[k][0]):
    i, a, b, rep, label = sites[k]
    print("  line %3d  %-14s %s  [%s]" % (i, label, lines[i - 1].strip()[:90], "equivalent" if reason(k) else "UNEXPECTED: the check has no case that tells it from the original"))
stale = [(p, l) for p, ls, _ in EQUIVALENT for l in ls if (p, l) not in seen]
if stale and "--lines" not in sys.argv:
    print("\nin the table and not found among the survivors (killed now, or the line has changed):")
    for p, l in stale:
        print("  %s  [%s]" % (p, l))
if not keep:
    shutil.rmtree(work, ignore_errors=True)
sys.exit(1 if unexpected else 0)
