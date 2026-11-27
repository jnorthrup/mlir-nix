#!/usr/bin/env python3
"""The gap census of the C++ relegated to MLIR, at every scale (docs/GAP-ANALYSIS.md).

usage: gap-census.py [--rev REV] [--top K] [--seal] [--diff OLD [NEW]]
  (nothing)     the census of HEAD, every scale
  --rev REV     another revision
  --top K       rows per list at scales 2-3 (default 12)
  --seal        also seal the run's rows as the revision's snapshot
  --diff A [B]  what moved between two sealed snapshots (B defaults to HEAD's), by scale

The yardstick is TrikeShed's PRELOAD.md algebra (Join, Series, Cursor; lazy views first, materialisation later), the
fill-drain pair (a lazy composition drained once into cells sized ahead) and the two storage shapes of
docs/BTRFS-COMPRESSOR.md: the trie CAS (CursorTrie.kt: HashTrie's digest-folded sealed pages, LaneTrie's append-only
rows) and the heap store (clusters fill, drain sorted, seal compressed).  The scales:
  0  the repository: C++ code lines, the product MLIR's op mix, its fill-drain share
  1  each subsystem: the C++ left beside the MLIR that replaced it, and what that MLIR is written in
  2  the store shapes: every keyed or ordered store of the C++, the shape TrikeShed gives it, where its algorithm lives
  3  functions: the C++ spans that remain, and the product MLIR functions that loop in llvm/arith (the bypass)
  4  the roots: declared ops with no lowering, declared ops no product module uses
A file's measures are kept by its blob id, so a run reads only what changed: .git/gap-cas holds 256 leaves by the id's
first byte, each an append log replayed at start (HashTrie's open leaf); a leaf past 4,096 rows seals, sorted by the
rest of the id and zlib-compressed (the heap store's sealed page).  A sealed snapshot is a run's rows sorted by key,
compressed, under .git/gap-cas/snap/<commit>.z.
"""
import argparse, collections, importlib.util, json, os, re, subprocess, sys, zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VERSION = "gap-census 2"
CXX = (".cpp", ".h", ".hpp", ".cc")
PRODUCT_MLIR = ("lowered/", "utils/mlnixci/src/")
SHAPE = collections.OrderedDict([  # kind -> (pattern in C++, TrikeShed's shape, where the algorithm lives)
    ("trie", (r"\bPatricia<", "crit-bit trie over lane rows (keys by path); HashTrie by digest fold", "lowered/nixstore/Patricia.mlir")),
    ("heap", (r"\b(GrowFunnel|Funnel|MinMaxHeap|Pegs)<|\bclusterOrder\b", "heap store: cluster fill, sorted drain, sealed page", "lowered/composite/ClusterOps.mlir")),
    ("hash", (r"\b(WordTable|TextTable)<", "dense bucket by computed cell; the funnel only past the window", "include/Composite/Table.h")),
    ("rows", (r"\bSorted(Map|Set)\b|\bsortRows\b|\bmlnix_rows_\w+|\bnixstore_ts_row\w+", "fill, then one sorted drain (sorted/bisect over split rows)", "lowered/composite/Rows.mlir lowered/nixstore/SortedRows.mlir")),
    ("files", (r"\binfoFile\(|\.cache/mlnix|readdir\(", "LaneTrie rows / HashTrie pages at the I/O boundary", "C++")),
])
DIALECTS = ("trikeshed", "confix", "kursive")
OPRE = re.compile(r'(?<![!#\w.])((?:trikeshed|confix|kursive|llvm|scf|cf|arith|memref|func|math|index|ub)\.[A-Za-z_][\w.]*)')  # ops, not !types or #attrs
LOOPS = {"scf.for", "scf.while", "cf.br", "cf.cond_br", "llvm.br", "llvm.cond_br"}
FN_MLIR = re.compile(r'^\s*(?:func\.func|llvm\.func)\s+(?:\w+\s+)*@([\w$.]+)')
FN_CXX = re.compile(r'^[A-Za-z_][\w:<>,*&\s~]*?\b([~\w]+(?:::[~\w]+)*)\s*\([^;]*$')
CONTROL = re.compile(r'^\s*(if|for|while|switch|return|else|do|case|struct|class|namespace|enum|union|template|extern|#)\b')


def git(*a, inp=None):
    return subprocess.run(["git", "-C", ROOT] + list(a), input=inp, capture_output=True, check=True).stdout


def code_lines_fn():
    spec = importlib.util.spec_from_file_location("cxx_lines", os.path.join(ROOT, "scripts", "cxx-lines.py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m.code_lines, m.area


code_lines, area = code_lines_fn()


# ---- the store: leaves by the id's first byte, an append log each, sealed sorted and compressed past LEAF rows ----
# In the common git directory, so every worktree of the checkout reads the same leaves (a blob id names the same file).
CAS = os.path.join(ROOT, subprocess.run(["git", "-C", ROOT, "rev-parse", "--git-common-dir"], capture_output=True, text=True,
                                         check=True).stdout.strip(), "gap-cas")
LEAF = 4096


class Cas:
    def __init__(self):
        os.makedirs(os.path.join(CAS, "snap"), exist_ok=True)
        self.rows, self.new = {}, collections.defaultdict(list)

    def leaf(self, slot):
        if slot in self.rows: return self.rows[slot]
        rows, base = {}, os.path.join(CAS, slot)
        if os.path.exists(base + ".z"):
            for line in zlib.decompress(open(base + ".z", "rb").read()).decode().splitlines():
                k, v = line.split("\t", 1); rows[k] = v
        if os.path.exists(base + ".log"):
            for line in open(base + ".log", encoding="utf-8"):
                k, v = line.rstrip("\n").split("\t", 1); rows[k] = v  # the newest row wins, as in the pack
        self.rows[slot] = rows
        return rows

    def get(self, blob):
        v = self.leaf(blob[:2]).get(blob[2:])
        return json.loads(v) if v else None

    def put(self, blob, value):
        v = json.dumps(value, separators=(",", ":"), sort_keys=True)
        self.leaf(blob[:2])[blob[2:]] = v
        self.new[blob[:2]].append(blob[2:] + "\t" + v)

    def commit(self):
        for slot, lines in self.new.items():
            base = os.path.join(CAS, slot)
            with open(base + ".log", "a", encoding="utf-8") as f: f.write("\n".join(lines) + "\n")
            rows = self.rows[slot]
            if sum(1 for _ in open(base + ".log", encoding="utf-8")) > LEAF:  # seal: sorted by the tail, compressed
                page = "\n".join(k + "\t" + rows[k] for k in sorted(rows)).encode()
                open(base + ".z.tmp", "wb").write(zlib.compress(page, 9)); os.replace(base + ".z.tmp", base + ".z")
                open(base + ".log", "w").close()
        self.new.clear()


def seal(commit, rows):
    page = "\n".join("\t".join(map(str, r)) for r in sorted(rows, key=lambda r: tuple(map(str, r[:-1])))).encode()
    open(os.path.join(CAS, "snap", commit + ".z"), "wb").write(zlib.compress(page, 9))


def unseal(commit):
    p = os.path.join(CAS, "snap", commit + ".z")
    if not os.path.exists(p): sys.exit(f"no sealed snapshot of {commit[:12]}: run gap-census.py --rev {commit[:12]} --seal")
    return {tuple(l.split("\t")[:-1]): l.split("\t")[-1] for l in zlib.decompress(open(p, "rb").read()).decode().splitlines()}


# ---- the measures of one file ----
def strip_mlir(line):
    i = line.find("//")
    return line if i < 0 else line[:i]


def measure_mlir(text):
    ops, fns, cur, depth = collections.Counter(), [], None, 0
    for n, raw in enumerate(text.splitlines(), 1):
        line = strip_mlir(raw)
        m = FN_MLIR.match(line)
        if m and cur is None and "{" in line:
            cur, depth = {"name": m.group(1), "line": n, "ops": 0, "ts": 0, "llvm": 0, "loops": 0, "drains": 0, "comp": 0}, 0
        found = OPRE.findall(line)
        for op in found:
            if op.startswith(("func.func", "llvm.func")): continue
            ops[op] += 1
            if cur is not None:
                cur["ops"] += 1
                d = op.split(".", 1)[0]
                cur["ts"] += d in DIALECTS
                cur["llvm"] += d == "llvm"
                cur["loops"] += op in LOOPS
                cur["drains"] += op == "trikeshed.drain"
                cur["comp"] += op in ("trikeshed.combine", "trikeshed.combineAll")
        if cur is not None:
            depth += line.count("{") - line.count("}")
            if depth <= 0 and "}" in line:
                cur["lines"] = n - cur["line"] + 1; fns.append(cur); cur = None
    return {"kind": "mlir", "lines": text.count("\n"), "ops": dict(ops), "fns": fns}


def measure_cxx(path, text):
    m = {"kind": "cxx", "code": code_lines(text), "area": area(path), "shapes": {}, "fns": [], "appends": 0}
    for kind, (pat, _, _) in SHAPE.items():
        m["shapes"][kind] = len(re.findall(pat, text))
    m["appends"] = len(re.findall(r"\.(append|push|emplace)\(", text))
    lines, i = text.splitlines(), 0
    while i < len(lines):  # function spans: a head at the left margin whose body closes at the same depth
        head = lines[i]
        fm = FN_CXX.match(head) if not CONTROL.match(head) else None
        if fm and not head.rstrip().endswith(";"):
            j, depth, opened = i, 0, False
            while j < len(lines):
                depth += lines[j].count("{") - lines[j].count("}")
                opened = opened or "{" in lines[j]
                if lines[j].rstrip().endswith(";") and not opened: break
                if opened and depth <= 0: break
                j += 1
            if opened and j > i:
                body = "\n".join(lines[i:j + 1])
                m["fns"].append({"name": fm.group(1), "line": i + 1, "code": code_lines(body + "\n"),
                                 "appends": len(re.findall(r"\.(append|push|emplace)\(", body)),
                                 "throws": len(re.findall(r"\bthrow\b|\bthrowError\b|\berror<", body))})
                i = j + 1
                continue
        i += 1
    return m


def census(rev):
    cas = Cas()
    tree = [l.split("\t", 1) for l in git("ls-tree", "-r", rev).decode().splitlines()]
    files = [(meta.split()[2], path) for meta, path in tree if meta.split()[1] == "blob"]
    want = [(b, p) for b, p in files if p.endswith(CXX) or (p.endswith(".mlir") and p.startswith(PRODUCT_MLIR))
            or p.endswith(".td")]
    out, todo = {}, []
    for blob, path in want:
        got = cas.get(blob)
        if got and got.get("v") == VERSION and got.get("path") == path: out[path] = got
        else: todo.append((blob, path))
    if todo:
        data = git("cat-file", "--batch", inp="".join(b + "\n" for b, _ in todo).encode())
        at = 0
        for blob, path in todo:
            head_end = data.index(b"\n", at)
            size = int(data[at:head_end].split()[2])
            text = data[head_end + 1: head_end + 1 + size].decode("utf-8", "replace")
            at = head_end + 1 + size + 1
            if path.endswith(".td"): m = {"kind": "td", "defs": [(c.split("_", 1)[-1] + "Op", d) for c, d in
                                                                 re.findall(r'def (\w+)Op\s*:\s*\w+<"([\w.]+)"', text)],
                                          "dialect": "kursive" if "Kursive" in path else "confix" if "Confix" in path else "trikeshed" if "TrikeShed" in path else "nix"}
            elif path.endswith(".mlir"): m = measure_mlir(text)
            else: m = measure_cxx(path, text)
            m["v"], m["path"] = VERSION, path
            cas.put(blob, m)
            out[path] = m
        cas.commit()
    return out


# ---- the scales ----
def rows_of(c, top, rev):
    rows = []
    cxx = {p: m for p, m in c.items() if m["kind"] == "cxx"}
    mlir = {p: m for p, m in c.items() if m["kind"] == "mlir"}
    allops = collections.Counter()
    for m in mlir.values(): allops.update(m["ops"])
    def share(ops, d): return sum(n for o, n in ops.items() if o.split(".", 1)[0] in d)
    tot = sum(allops.values())
    ts, ll = share(allops, DIALECTS), share(allops, ("llvm",))
    fd = [f for m in mlir.values() for f in m["fns"] if f["drains"] and f["comp"]]
    fd_lines = sum(f["lines"] for f in fd)
    mlir_lines = sum(m["lines"] for m in mlir.values())
    rows += [(0, "repo", "cxx code lines", sum(m["code"] for m in cxx.values())),
             (0, "repo", "product mlir lines", mlir_lines), (0, "repo", "product mlir ops", tot),
             (0, "repo", "dialect ops %", round(100.0 * ts / max(tot, 1), 1)), (0, "repo", "llvm ops %", round(100.0 * ll / max(tot, 1), 1)),
             (0, "repo", "fill-drain fn lines %", round(100.0 * fd_lines / max(mlir_lines, 1), 1)),
             (0, "repo", "fill-drain functions", len(fd))]
    # scale 1: C++ by area, the MLIR beside it by directory
    by_area = collections.Counter()
    for m in cxx.values(): by_area[m["area"]] += m["code"]
    for a, n in sorted(by_area.items()): rows.append((1, a, "cxx code lines", n))
    by_dir = collections.defaultdict(collections.Counter)
    for p, m in mlir.items():
        d = os.path.dirname(p)
        by_dir[d]["lines"] += m["lines"]; by_dir[d]["ops"] += sum(m["ops"].values())
        by_dir[d]["ts"] += share(m["ops"], DIALECTS); by_dir[d]["llvm"] += share(m["ops"], ("llvm",))
        by_dir[d]["fd"] += sum(f["lines"] for f in m["fns"] if f["drains"] and f["comp"])
    for d, v in sorted(by_dir.items()):
        rows += [(1, d, "mlir lines", v["lines"]), (1, d, "dialect ops %", round(100.0 * v["ts"] / max(v["ops"], 1), 1)),
                 (1, d, "llvm ops %", round(100.0 * v["llvm"] / max(v["ops"], 1), 1)),
                 (1, d, "fill-drain lines %", round(100.0 * v["fd"] / max(v["lines"], 1), 1))]
    # scale 2: the store shapes
    for kind, (_, target, home) in SHAPE.items():
        sites = sorted(((m["shapes"][kind], p) for p, m in cxx.items() if m["shapes"][kind]), reverse=True)
        rows.append((2, kind, "c++ sites", sum(n for n, _ in sites)))
        for n, p in sites[:top]: rows.append((2, kind + " " + p, "sites", n))
        for h in home.split():
            if h in mlir:
                ops = mlir[h]["ops"]; t = sum(ops.values())
                rows.append((2, kind + " " + h, "dialect ops %", round(100.0 * share(ops, DIALECTS) / max(t, 1), 1)))
    # scale 3: the C++ spans left, and the bypass functions of the product MLIR
    spans = sorted(((f["code"], p, f) for p, m in cxx.items() if not p.startswith("scripts/") for f in m["fns"]), key=lambda x: -x[0])
    for code, p, f in spans[:top * 3]:
        rows.append((3, f"cxx {p}:{f['line']} {f['name']}", "code lines", code))
    bypass = sorted(((f["ops"] - f["ts"], p, f) for p, m in mlir.items() for f in m["fns"]
                     if f["ops"] >= 30 and f["loops"] and f["ts"] * 10 < f["ops"]), key=lambda x: -x[0])
    rows.append((3, "mlir bypass", "functions", len(bypass)))
    rows.append((3, "mlir bypass", "ops", sum(b[0] for b in bypass)))
    for n, p, f in bypass[:top * 2]:
        rows.append((3, f"mlir {p}:{f['line']} @{f['name']}", "non-dialect ops", n))
    # scale 4: the roots
    names = set(git("grep", "-h", "-o", "-w", "-E", r"[A-Z][A-Za-z]*Op", rev, "--", "lib/*.cpp").decode().split())
    used = collections.Counter()
    for m in mlir.values(): used.update(m["ops"])
    for p, m in c.items():
        if m["kind"] != "td" or m["dialect"] not in DIALECTS: continue
        for cls, d in m["defs"]:
            op = m["dialect"] + "." + d
            if cls not in names: rows.append((4, op, "no lowering", 1))
            elif not used[op]: rows.append((4, op, "no product use", 1))
    return rows


def show(rows):
    names = {0: "the repository", 1: "subsystems", 2: "store shapes (C++ sites; the module holding the algorithm)",
             3: "functions (C++ spans left; product MLIR functions looping outside the dialects)", 4: "roots"}
    last = None
    for s, k, what, v in rows:
        if s != last: print(f"\n== scale {s}: {names[s]}"); last = s
        print(f"  {k:72} {what:24} {v}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rev", default="HEAD")
    ap.add_argument("--top", type=int, default=12)
    ap.add_argument("--seal", action="store_true")
    ap.add_argument("--diff", nargs="+")
    a = ap.parse_args()
    if a.diff:
        old = git("rev-parse", a.diff[0]).decode().strip()
        new = git("rev-parse", a.diff[1] if len(a.diff) > 1 else "HEAD").decode().strip()
        A, B = unseal(old), unseal(new)
        for k in sorted(set(A) | set(B), key=lambda k: (int(k[0]), k[1:])):
            if A.get(k) != B.get(k): print(f"  {k[0]} {k[1]:72} {k[2]:24} {A.get(k, '-'):>8} -> {B.get(k, '-')}")
        return
    rev = git("rev-parse", a.rev).decode().strip()
    rows = rows_of(census(rev), a.top, rev)
    print(f"gap census of {rev[:12]} ({VERSION})")
    show(rows)
    if a.seal: seal(rev, rows); print(f"\nsealed: .git/gap-cas/snap/{rev}.z")


if __name__ == "__main__":
    main()
