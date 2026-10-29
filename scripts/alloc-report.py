#!/usr/bin/env python3
"""The report over alloc-sites' output: allocation sites by count and bytes, each at its first frame inside the binary.

usage: alloc-report.py SITES.txt BINARY [TOP]

Frames in the system libraries (libc++'s operator new, malloc itself) are skipped: a site is named by the first frame atos
places in BINARY (function, file:line), and also summed by that frame's function alone.
"""
import collections, re, subprocess, sys

path, binary = sys.argv[1], sys.argv[2]
top = int(sys.argv[3]) if len(sys.argv) > 3 else 30
head = open(path).readline()
every = int(re.search(r"every (\d+)", head).group(1))
total_calls = int(re.search(r"; (\d+) calls", head).group(1))
base = int(re.search(r"base ([0-9a-f]+)", head).group(1), 16)
sites = []
for line in open(path):
    if line.startswith("#"): continue
    f = line.split()
    sites.append((int(f[0]), int(f[1]), int(f[2]), [int(x, 16) for x in f[3:]]))

pcs = sorted({pc for _, _, _, st in sites for pc in st})
out = subprocess.run(["atos", "-o", binary, "-l", hex(base)] + [hex(p) for p in pcs],
                     capture_output=True, text=True).stdout.strip().split("\n")
name = {}
for pc, s in zip(pcs, out):
    if s.startswith("0x"): continue  # not in the binary
    m = re.match(r"(.*?) \(in [^)]*\)(?: \((.*)\))?", s)
    if m: name[pc] = (m.group(1), m.group(2) or "")

# A site is named by its first frame that is the program's own code: not a container or string the library instantiated, not an allocator.
LIBRARY = re.compile(r"^(std::|llvm::(SmallVector|DenseMap|StringMap|BumpPtr|MallocAllocator|allocate_buffer|SmallPtrSet|DenseSet|StringRef::str|Twine|raw_)|"
                     r"composite::(Growable|MutableSeries)|<deduplicated_symbol>|operator new|mlir::detail::|__)")
def site_of(stack):
    first = None
    for pc in stack:
        if pc in name:
            fn, loc = name[pc]
            first = first or (fn, loc)
            if not LIBRARY.match(fn): return fn, loc
    return first or ("outside the binary", "")

role = sys.argv[4] if len(sys.argv) > 4 else "evaluator"
ev_calls = sum(c for c, _, e, _ in sites if e == 1); all_calls = sum(c for c, _, _, _ in sites)
print(f"the evaluator thread made {100.0 * ev_calls / max(all_calls, 1):.0f}% of the sampled allocations; reporting: {role}")
sites = [(c, b, st) for c, b, e, st in sites if role == "all" or (e == 1) == (role == "evaluator")]
sampled = sum(c for c, _, _ in sites)
by_line, by_fn = collections.Counter(), collections.Counter()
bytes_line, bytes_fn = collections.Counter(), collections.Counter()
for c, b, st in sites:
    fn, loc = site_of(st)
    short = re.sub(r"\(.*", "", fn)[:90]
    by_line[(short, loc)] += c; bytes_line[(short, loc)] += b
    by_fn[short] += c; bytes_fn[short] += b
tb = sum(b for _, b, _ in sites)
print(f"{total_calls} allocations in the process ({total_calls / 1e6:.1f}M); {sampled} sampled here (1 in {every}): ~{sampled * every / 1e6:.2f}M calls, ~{tb * every / 1e6:.0f} MB")
print("== by function (share of allocations, share of bytes):")
for fn, c in by_fn.most_common(top):
    print(f"  {100.0 * c / sampled:5.1f}%  {100.0 * bytes_fn[fn] / tb:5.1f}%  {fn}")
print("== by site:")
for (fn, loc), c in by_line.most_common(top):
    print(f"  {100.0 * c / sampled:5.1f}%  {100.0 * bytes_line[(fn, loc)] / tb:5.1f}%  {loc:34} {fn}")
