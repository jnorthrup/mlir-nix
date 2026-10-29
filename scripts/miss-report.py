#!/usr/bin/env python3
"""Which loads miss, and what they read: the report over miss-sample's output.

usage: miss-report.py SAMPLES.txt BINARY [TOP]

Each sample is the address of a load that missed and the address it read.  The load is placed in BINARY (built with
line tables, -g1) through the child's maps and the ELF's PT_LOAD headers, and symbolized: the innermost source line
(what was being read) and the outermost function.  The data address is classed by the mapping it falls in: the
evaluator's arena (anonymous regions of a few MiB and up), the malloc heap (MLIR operations, attributes, std
containers), the stack, the binary's own data, a mapped file (sources).
"""
import collections, re, subprocess, sys

samples_path, binary = sys.argv[1], sys.argv[2]
top = int(sys.argv[3]) if len(sys.argv) > 3 else 40

samples, maps = [], []
in_maps = False
for line in open(samples_path):
    if line.startswith("== maps"):
        in_maps = True
        continue
    if in_maps:
        m = re.match(r"([0-9a-f]+)-([0-9a-f]+) (\S+) ([0-9a-f]+) \S+ \d+\s*(.*)", line)
        if m:
            maps.append((int(m.group(1), 16), int(m.group(2), 16), m.group(3), int(m.group(4), 16), m.group(5).strip()))
    else:
        ip, addr = line.split()
        samples.append((int(ip, 16), int(addr, 16)))

# The executable's load segments: file offset -> link-time address.
loads = []
for l in subprocess.run(["readelf", "-lW", binary], capture_output=True, text=True).stdout.splitlines():
    f = l.split()
    if f and f[0] == "LOAD":
        loads.append((int(f[1], 16), int(f[2], 16), int(f[4], 16)))  # offset, vaddr, filesz
binname = binary.split("/")[-1]

def link_addr(ip):
    for start, end, perms, pgoff, name in maps:
        if start <= ip < end and name.endswith(binname):
            off = ip - start + pgoff
            for o, v, sz in loads:
                if o <= off < o + sz:
                    return off - o + v
    return None

def data_class(a):
    if a == 0: return "no data address (not precise)"
    for start, end, perms, pgoff, name in maps:
        if start <= a < end:
            if name == "[heap]": return "malloc heap"
            if name.startswith("[stack"): return "stack"
            if name.endswith(binname): return "binary data"
            if name and not name.startswith("["): return "mapped file"
            return "arena (anon >= 4 MiB)" if end - start >= (4 << 20) else "anon < 4 MiB (malloc arenas, small maps)"
    return "unmapped at the last map (freed, or mapped late)"

ips = collections.Counter(ip for ip, _ in samples)
la = {ip: link_addr(ip) for ip in ips}
known = sorted({a for a in la.values() if a is not None})
sym = {}
if known:
    p = subprocess.run(["llvm-symbolizer-22", "--obj=" + binary, "--functions=linkage", "--demangle"],
                       input="\n".join(hex(a) for a in known), capture_output=True, text=True)
    blocks = p.stdout.strip().split("\n\n")
    for a, b in zip(known, blocks):
        lines = b.split("\n")
        frames = [(lines[i], lines[i + 1]) for i in range(0, len(lines) - 1, 2)]
        inner_fn, inner_loc = frames[0]
        outer_fn = frames[-1][0]
        loc = re.sub(r".*/(lib|include)/", r"\1/", inner_loc)
        sym[a] = (loc, inner_fn, outer_fn)

total = len(samples)
by_site = collections.Counter()
site_class = collections.defaultdict(collections.Counter)
by_fn = collections.Counter()
by_class = collections.Counter()
for ip, addr in samples:
    a = la[ip]
    loc, inner, outer = sym.get(a, ("?", "?", "outside the binary (libc, libstdc++, MLIR shared code)" if a is None else "?"))
    key = (loc, inner[:60], outer[:60])
    by_site[key] += 1
    c = data_class(addr)
    site_class[key][c] += 1
    by_fn[outer[:70]] += 1
    by_class[c] += 1

print(f"{total} samples")
print("== by data class:", ", ".join(f"{k} {100.0 * v / total:.1f}%" for k, v in by_class.most_common()))
print("== by outermost function:")
for f, n in by_fn.most_common(15):
    print(f"  {100.0 * n / total:5.1f}%  {f}")
print(f"== top {top} load sites (innermost line, its function, the outermost function; what they read):")
for key, n in by_site.most_common(top):
    loc, inner, outer = key
    cls = ", ".join(f"{k.split(' ')[0]} {100.0 * v / n:.0f}%" for k, v in site_class[key].most_common(2))
    print(f"  {100.0 * n / total:5.1f}%  {loc:38} {inner:40} in {outer:40} [{cls}]")
