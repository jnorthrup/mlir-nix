#!/usr/bin/env python3
"""Report for the profiles scripts/linux-prof/sigprof.c writes: symbolizes the stacks, then shows
where the CPU time went, as shares of the busiest thread's samples.

usage: report.py RUN.prof [RUN.prof ...] [--top N] [--all-threads]
                          [--callers REGEX] [--children REGEX]

  --callers REGEX    for samples whose innermost frame matches, the callers one level up
  --children REGEX   for samples that pass through a frame matching, what that frame called

Needs llvm-symbolizer (LLVM_SYMBOLIZER overrides the path).  Frames are named from the symbol
tables only: a stripped library shows as its file name.  Several profiles are summed.
"""
import argparse
import collections
import os
import re
import struct
import subprocess
import sys

SYMBOLIZER = os.environ.get("LLVM_SYMBOLIZER") or next(
    (p for p in ("/usr/lib/llvm-22/bin/llvm-symbolizer", "/usr/bin/llvm-symbolizer", "llvm-symbolizer") if os.path.exists(p) or "/" not in p),
    "llvm-symbolizer")

# The innermost matching frame names the phase.  First match, scanning from the leaf outwards.
PHASES = [
    ("parse",            r"nixfe::.*Parser|nixfe::parse|nixfe::Source|nixfe::Lexer|nixfe::ExprArena"),
    ("mint (demand)",    r"EvalState::mintLambda|nixfe::mintBody"),
    ("lower (file)",     r"EvalState::lowerToMLIR|nixfe::genExpr|nixfe::lower|nixfe::Gen::"),
    ("drv / store",      r"nixstore::|derivationStrict|hashDerivation|nixev::.*[Dd]rv"),
    ("eval",             r"EvalState::(evalOp|forceThunk|forceValue|callFunction|callLambda|evalTail|evalFile|evalDefinition|operand|lookup)"),
    ("startup",          r"loadNixDialects|loadPrimDialects|registerEvalModels|MLIRContext::MLIRContext|irdl::|EvalState::EvalState"),
    ("teardown",         r"EvalState::~EvalState|MLIRContext::~MLIRContext|Operation::erase|Operation::destroy|dropAllReferences"),
]
PHASES = [(n, re.compile(rx)) for n, rx in PHASES]

# Kinds of leaf work.  First match wins.  A stripped library shows as "name.so?".
KINDS = [
    ("MLIR uniquing",    r"StorageUniquer|AttributeUniquer|ParametricStorageUniquer|FileLineColRange|StringAttrStorage|DenseSetImpl|getOrCreate"),
    ("MLIR ops / IR",    r"mlir::(Operation|OpBuilder|Block|Region|Builder|OperationState|RewritePattern|PatternApplicator|Value|OpResult|detail::OperandStorage)|OpBuilder"),
    ("operand lookup",   r"EvalState::(lookup|operand)|nixev::Slot|DenseMapBase::LookupBucketFor"),
    ("evaluator",        r"nixev::|EvalModels|CoreEval"),
    ("parser / lexer",   r"nixfe::|Parser::|Lexer"),
    ("malloc / free",    r"^(malloc|free|calloc|realloc|operator_new|operator_delete|_int_malloc|_int_free|cfree)$|BumpPtrAllocator|safe_malloc"),
    ("memory ops",       r"^(memcpy|memmove|memset|memcmp|strlen|bcmp)\w*$|^__mem\w+"),
    ("hashing",          r"xxh3|sha256|SHA|Hash"),
    ("libc (stripped)",  r"^libc\.so"),
    ("libLLVM",          r"^libLLVM"),
    ("libstdc++",        r"^libstdc\+\+"),
]
KINDS = [(n, re.compile(rx)) for n, rx in KINDS]


_TEMPLATE_ARGS = re.compile(r"<[^<>]*>")
_PARAMS = re.compile(r"\([^()]*\)")
_OPERATOR = re.compile(r"operator\s*(\(\)|<=>|<<=|>>=|<<|>>|<=|>=|->\*|->|\[\]|&&|\|\||\+\+|--|[-+*/%^&|~!=<>,]=?)")
_QUALIFIERS = re.compile(r"(\s+(const|volatile|noexcept|&&|&))+$")


def shorten(name):
    """'ret ns::Class::method<T>(args) const' -> 'ns::Class::method': what a profile groups on."""
    s = name.replace("(anonymous namespace)", "{anon}")
    s = re.sub(r"operator\s+(new|delete)", r"operator_\1", s)
    s = _OPERATOR.sub(lambda m: "operator_call" if m.group(1) == "()" else "operator_op", s)
    while _TEMPLATE_ARGS.search(s):
        s = _TEMPLATE_ARGS.sub("", s)
    while _PARAMS.search(s):
        s = _PARAMS.sub("", s)
    s = _QUALIFIERS.sub("", s.strip())
    return s.split()[-1] if s.split() else name


def elf_loads(path):
    """PT_LOAD segments of an ELF64 file as (offset, vaddr, filesz)."""
    try:
        with open(path, "rb") as fh:
            head = fh.read(64)
            if head[:4] != b"\x7fELF" or head[4] != 2:
                return []
            phoff, = struct.unpack_from("<Q", head, 32)
            phentsize, phnum = struct.unpack_from("<HH", head, 54)
            fh.seek(phoff)
            table = fh.read(phentsize * phnum)
    except OSError:
        return []
    loads = []
    for i in range(phnum):
        p_type, _flags, p_offset, p_vaddr, _paddr, p_filesz, _memsz, _align = struct.unpack_from("<IIQQQQQQ", table, i * phentsize)
        if p_type == 1:
            loads.append((p_offset, p_vaddr, p_filesz))
    return loads


class Profile:
    def __init__(self, path):
        self.stacks = []  # (tid, [pc ...] leaf first)
        self.maps = []    # (start, end, offset, path)
        self.interval_ns = 1000000
        self.restorer = 0
        with open(path) as fh:
            for line in fh:
                if line.startswith("S "):
                    f = line.split()
                    self.stacks.append((int(f[1], 16), [int(x, 16) for x in f[2:]]))
                elif line.startswith("M "):
                    m = re.match(r"M ([0-9a-f]+)-([0-9a-f]+) (\S+) ([0-9a-f]+) \S+ \d+\s*(.*)$", line)
                    if m and "x" in m.group(3) and m.group(5).startswith("/"):
                        self.maps.append((int(m.group(1), 16), int(m.group(2), 16), int(m.group(4), 16), m.group(5).replace(" (deleted)", "")))
                elif line.startswith("interval_ns"):
                    self.interval_ns = int(line.split()[1])
                elif line.startswith("restorer"):
                    self.restorer = int(line.split()[1], 16)
        self.maps.sort()

    def locate(self, pc):
        lo, hi = 0, len(self.maps)
        while lo < hi:
            mid = (lo + hi) // 2
            if self.maps[mid][1] <= pc:
                lo = mid + 1
            else:
                hi = mid
        if lo < len(self.maps) and self.maps[lo][0] <= pc < self.maps[lo][1]:
            return self.maps[lo]
        return None

    def trimmed(self, pcs):
        """Drop the handler and the signal trampoline in front of the interrupted frame."""
        for k in range(min(4, len(pcs))):
            if self.restorer and self.restorer <= pcs[k] < self.restorer + 16:
                return pcs[k + 1:]
        return pcs[2:]


def symbolize(profile, wanted, loads_cache):
    """wanted: set of (pc, is_leaf).  Returns {(pc, is_leaf): (function, module basename)}."""
    per_module = collections.defaultdict(list)
    out = {}
    for pc, leaf in wanted:
        m = profile.locate(pc)
        if not m:
            out[(pc, leaf)] = ("[unmapped]", "?")
            continue
        start, _end, offset, path = m
        loads = loads_cache.setdefault(path, elf_loads(path))
        addr = pc if leaf else pc - 1
        file_off = addr - start + offset
        vaddr = None
        for p_off, p_vaddr, p_filesz in loads:
            if p_off <= file_off < p_off + p_filesz:
                vaddr = file_off - p_off + p_vaddr
                break
        if vaddr is None:
            vaddr = file_off
        per_module[path].append(((pc, leaf), vaddr))
    for path, items in per_module.items():
        base = os.path.basename(path)
        # No --functions=short: without DWARF it answers ?? where the default reads the symbol table.
        cmd = [SYMBOLIZER, f"--obj={path}", "--demangle", "--no-inlines"]
        text = "".join(f"0x{v:x}\n" for _k, v in items)
        res = subprocess.run(cmd, input=text, capture_output=True, text=True)
        lines = res.stdout.split("\n")
        # three lines per address: function, file:line:col, blank
        for idx, (key, _v) in enumerate(items):
            fn = lines[idx * 3].strip() if idx * 3 < len(lines) else "??"
            out[key] = (shorten(fn) if fn and fn != "??" else f"{base}?", base)
    return out


def classify(table, name, module):
    for label, rx in table:
        if rx.search(name):
            return label
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("profiles", nargs="+")
    ap.add_argument("--top", type=int, default=30)
    ap.add_argument("--all-threads", action="store_true")
    ap.add_argument("--callers")
    ap.add_argument("--children")
    args = ap.parse_args()

    loads_cache = {}
    all_stacks = []    # [(names leaf-first, modules leaf-first)]
    thread_total = collections.Counter()
    nprof = len(args.profiles)
    interval_ms = 1.0
    for path in args.profiles:
        prof = Profile(path)
        interval_ms = prof.interval_ns / 1e6
        by_thread = collections.Counter(tid for tid, _ in prof.stacks)
        busiest = by_thread.most_common(1)[0][0] if by_thread else None
        for tid, n in by_thread.items():
            thread_total[("busiest" if tid == busiest else "other")] += n
        wanted = set()
        trimmed = []
        for tid, pcs in prof.stacks:
            if not args.all_threads and tid != busiest:
                continue
            t = prof.trimmed(pcs)
            if t:
                trimmed.append(t)
                wanted.add((t[0], True))
                wanted.update((pc, False) for pc in t[1:])
        sym = symbolize(prof, wanted, loads_cache)
        for t in trimmed:
            names, mods = [], []
            for i, pc in enumerate(t):
                fn, mod = sym[(pc, i == 0)]
                names.append(fn)
                mods.append(mod)
            all_stacks.append((names, mods))

    total = len(all_stacks)
    if not total:
        sys.exit("no samples")
    print(f"{total} samples over {nprof} profile(s), {interval_ms:g} ms each: {total * interval_ms / nprof:.0f} ms of CPU per run "
          f"({'all threads' if args.all_threads else 'busiest thread'}; other threads: {thread_total['other']} samples)")

    mod_leaf = collections.Counter(m[0] for _n, m in all_stacks)
    print("\nleaf time by module:")
    for mod, n in mod_leaf.most_common(8):
        print(f"  {100 * n / total:5.1f}%  {mod}")

    phase_count = collections.Counter()
    phase_kind = collections.defaultdict(collections.Counter)
    for names, mods in all_stacks:
        phase = "other"
        for nm in names:
            p = classify(PHASES, nm, "")
            if p:
                phase = p
                break
        kind = classify(KINDS, names[0], mods[0]) or "other"
        phase_count[phase] += 1
        phase_kind[phase][kind] += 1
    print("\nphase (innermost phase frame on the stack):")
    for ph, n in phase_count.most_common():
        kinds = ", ".join(f"{k} {100 * c / total:.1f}" for k, c in phase_kind[ph].most_common(5))
        print(f"  {100 * n / total:5.1f}%  {n * interval_ms / nprof:7.0f} ms  {ph:14s} {kinds}")

    self_count = collections.Counter(names[0] for names, _m in all_stacks)
    incl_count = collections.Counter()
    for names, _m in all_stacks:
        for nm in set(names):
            incl_count[nm] += 1
    print(f"\ntop {args.top} by self time:")
    for nm, n in self_count.most_common(args.top):
        print(f"  {100 * n / total:5.1f}%  {nm[:130]}")
    print(f"\ntop {args.top} by inclusive time:")
    for nm, n in incl_count.most_common(args.top):
        print(f"  {100 * n / total:5.1f}%  {nm[:130]}")

    if args.callers:
        rx = re.compile(args.callers)
        c = collections.Counter()
        hits = 0
        for names, _m in all_stacks:
            if rx.search(names[0]):
                hits += 1
                caller = next((nm for nm in names[1:] if not rx.search(nm)), "(root)")
                c[caller] += 1
        print(f"\ncallers of leaf frames matching /{args.callers}/ ({100 * hits / total:.1f}% of samples):")
        for nm, n in c.most_common(args.top):
            print(f"  {100 * n / total:5.1f}%  {nm[:130]}")
    if args.children:
        rx = re.compile(args.children)
        c = collections.Counter()
        hits = 0
        for names, _m in all_stacks:
            for i, nm in enumerate(names):
                if rx.search(nm):
                    hits += 1
                    c[names[i - 1] if i > 0 else "(self)"] += 1
                    break
        print(f"\nwhat frames matching /{args.children}/ call ({100 * hits / total:.1f}% of samples pass through):")
        for nm, n in c.most_common(args.top):
            print(f"  {100 * n / total:5.1f}%  {nm[:130]}")


if __name__ == "__main__":
    main()
