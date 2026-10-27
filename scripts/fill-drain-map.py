#!/usr/bin/env python3
"""Map the fill/drain pairs written by hand in lib/, include/ and tools/.

A fill/drain pair is a container that is filled (push_back, +=, <<, insert) and then drained into its final shape: an arena
list or string, a Bindings, a StringContext, an op's operands, an output text.  PRELOAD calls the container a MutableSeries
("a list that is mutated says so in its type"; it accumulates, then drains); TrikeShed has the ring and chunked variants
(RingSeries, ChunkedMutableSeries).  Written with std::vector, std::string or std::map the pair is invisible to the reader and to
the optimizer, so this lists them, with what each fill costs: the inline capacity against an L1 line count, whether it
reserves, and which drain it ends in.

usage: fill-drain-map.py [--md] [--sites]
  default   one line per kind of pair, counted
  --sites   every site: file:line, enclosing function or primop, container, fill ops, drains
  --md      the sites as a markdown table (docs/FILL-DRAIN.md)

A heuristic scan of text, not a parse: a site is a local declaration inside a function body, its fills and drains are the
uses of that name before the function's closing brace.  Read the sites before believing a class.
"""
import argparse, collections, pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DIRS = ("lib", "include", "tools")
SKIP = ("Composite", "build")

DECL = re.compile(
    r"^(?P<ind>\s{2,})(?:const\s+)?(?P<type>std::vector|llvm::SmallVector|SmallVector|std::string|llvm::SmallString|SmallString|"
    r"std::ostringstream|std::stringstream|std::map|std::set|std::unordered_map|std::unordered_set|llvm::DenseMap|llvm::DenseSet|"
    r"llvm::StringMap|llvm::StringSet|NixStringContext)\s*(?P<targs><[^;(){}]*?>)?\s+(?P<name>[A-Za-z_]\w*)\s*(?P<after>[;({=])")
FILLS = ("push_back", "emplace_back", "append", "insert", "emplace", "try_emplace")
FUNC = re.compile(r"^[A-Za-z_][^;]*\)\s*(?:const\s*)?(?:noexcept\s*)?(?:override\s*)?\{\s*$")
PRIM = re.compile(r'addPrimOp\(\s*"([^"]+)"')
MKLIST = re.compile(r"\bmkList\(")
INLINE = re.compile(r"<\s*(.*?)\s*,\s*(\d+)\s*>$")

ELEM_BYTES = {"Value *": 8, "Value*": 8, "Attr": 16, "Symbol": 4, "char": 1, "uint8_t": 1, "std::string": 32, "std::string_view": 16,
              "llvm::StringRef": 16, "StringRef": 16, "int64_t": 8, "uint64_t": 8, "size_t": 8, "unsigned": 4, "uint32_t": 4,
              "int": 4, "mlir::Value": 8, "Value": 8, "Operation *": 8, "mlir::Operation *": 8, "const Attr *": 8}


def elem_of(targs):
    if not targs:
        return None
    inner = targs[1:-1].strip()
    m = INLINE.search("<" + inner + ">")
    return (m.group(1), int(m.group(2))) if m else (inner.split(",")[0].strip(), None)


NOT_FUNC = ("if", "for", "while", "switch", "else", "catch", "do", "return", "namespace", "struct", "class", "enum", "extern",
            "static_assert", "union", "try")
HEADER = re.compile(r"^(?P<ind>\s*)(?P<head>[A-Za-z_~\[][^;{}]*\)\s*(?:const\s*)?(?:noexcept\s*)?(?:override\s*)?(?:->\s*[\w:<>*& ]+\s*)?)\{\s*$")


def func_ranges(lines):
    """(start, end, header) of every function body at any indentation (free functions, methods inside a struct, lambdas that
    open a line): a header ending in `) {` up to the next line that starts with a `}` at the same indentation."""
    out = []
    for i, line in enumerate(lines):
        m = HEADER.match(line)
        if not m:
            continue
        first = m.group("head").split("(")[0].split()
        if first and first[0] in NOT_FUNC:
            continue
        ind = m.group("ind")
        j = i + 1
        while j < len(lines) and not (lines[j].startswith(ind + "}") and not lines[j].startswith(ind + " ")):
            j += 1
        out.append((i, min(j, len(lines) - 1), line.strip()[:90]))
    return out


def scan(path):
    lines = path.read_text(errors="replace").splitlines()
    rel = str(path.relative_to(ROOT))
    rows = []
    ranges = func_ranges(lines)
    for i, line in enumerate(lines):
        m = DECL.match(line)
        if not m or "&" in line[: m.end()].split(m.group("name"))[0] or line.lstrip().startswith(("return", "//")):
            continue
        inner = [r for r in ranges if r[0] < i < r[1]]
        if not inner:
            continue
        a, b, fname = min(inner, key=lambda r: r[1] - r[0])
        if True:
            name, typ, targs, after = m.group("name"), m.group("type").split("::")[-1], m.group("targs"), m.group("after")
            # the scope of a local is the rest of its block: up to the next line indented less than the declaration
            ind = len(m.group("ind"))
            end = i + 1
            while end < b and (not lines[end].strip() or len(lines[end]) - len(lines[end].lstrip()) >= ind):
                end += 1
            body = "\n".join(lines[i + 1:end])
            fills = {f: len(re.findall(rf"\b{name}\.{f}\(", body)) for f in FILLS}
            fills = {k: v for k, v in fills.items() if v}
            ops = len(re.findall(rf"\b{name}\s*(?:\+=|<<)", body))
            if ops:
                fills["+=/<<"] = ops
            reserve = bool(re.search(rf"\b{name}\.(?:reserve|resize)\(", body)) or after in "({" and not lines[i][m.end():].lstrip().startswith(")")
            drains = []
            if re.search(rf"\bmkList\([^;]*{name}\.size\(\)|{name}\.size\(\)[^;]*\bmkList\(", body) or (
                    MKLIST.search(body) and re.search(rf"\b{name}\b", body) and re.search(rf"elems\[[^\]]*\]\s*=\s*{name}\[|elems\[[^\]]*\]\s*=\s*\*?\w+;", body)):
                drains.append("mkList")
            if re.search(rf"mk(?:String|Path)\w*\([^;]*\b{name}\b", body):
                drains.append("mkString")
            if re.search(rf"\b(?:bb|builder|b)\.insert\([^;]*\b{name}\b|allocBindings\(\s*{name}\.size", body):
                drains.append("Bindings")
            if re.search(rf"makeContext\(\s*{name}\b|copyContext\([^;]*\b{name}\b", body):
                drains.append("context")
            if re.search(rf"(?:Op|Attr)\w*::create\([^;]*\b{name}\b|builder\.create<[^;]*\b{name}\b", body):
                drains.append("IR operands")
            if re.search(rf"std::(?:copy|memcpy)\([^;]*\b{name}\b|memcpy\([^;]*\b{name}\.data", body):
                drains.append("copy")
            if re.search(rf"std::(?:sort|stable_sort)\(\s*{name}\.", body):
                drains.append("sort in place")
            if re.search(rf"return\s+(?:std::move\()?{name}\)?\s*;", body):
                drains.append("returned")
            if re.search(rf"for\s*\([^)]*:\s*{name}\s*\)", body):
                drains.append("range-for")
            if not fills and not drains:
                continue
            owners = [(r[1] - r[0], PRIM.search(lines[r[0]])) for r in inner]
            owners = [pm.group(1) for _, pm in sorted(owners, key=lambda t: t[0]) if pm]
            owner = owners[0] if owners else None
            elem = elem_of(targs) if targs else None
            row = dict(file=rel, line=i + 1, fn=("primop " + owner) if owner else fname, type=typ, elem=elem[0] if elem else "",
                       inline=elem[1] if elem else None, name=name, fills=fills, reserve=reserve, drains=drains)
            eb = ELEM_BYTES.get(row["elem"])
            row["inline_bytes"] = eb * row["inline"] if eb and row["inline"] else None
            rows.append(row)
    return rows


def klass(r):
    d = set(r["drains"])
    if r["type"] in ("string", "SmallString", "ostringstream", "stringstream"):
        return "text -> arena string" if "mkString" in d else "text built, then used"
    if r["type"] in ("map", "set", "unordered_map", "unordered_set", "DenseMap", "DenseSet", "StringMap", "StringSet", "NixStringContext"):
        return "set -> string context" if "context" in d else "map/set filled, then walked"
    if "mkList" in d:
        return "vector -> arena list"
    if "Bindings" in d:
        return "vector -> Bindings"
    if "IR operands" in d:
        return "vector -> op operands"
    if "copy" in d or "sort in place" in d or "returned" in d:
        return "vector -> copied / returned"
    return "vector filled, then walked"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sites", action="store_true")
    ap.add_argument("--md", action="store_true")
    a = ap.parse_args()
    files = sorted(p for d in DIRS for p in (ROOT / d).rglob("*") if p.suffix in (".cpp", ".h") and not any(s in p.parts for s in SKIP))
    rows = [r for f in files for r in scan(f)]
    by = collections.defaultdict(list)
    for r in rows:
        by[klass(r)].append(r)
    if a.md:
        print("| site | in | container | fills | reserves | inline | drains |\n|---|---|---|---|---|---|---|")
        for r in sorted(rows, key=lambda r: (klass(r), r["file"], r["line"])):
            inl = f"{r['inline']} ({r['inline_bytes']} B)" if r["inline"] and r["inline_bytes"] else (str(r["inline"]) if r["inline"] else "")
            print(f"| {r['file']}:{r['line']} | {r['fn'][:48]} | {r['type']}<{r['elem']}> `{r['name']}` | {','.join(r['fills'])} | "
                  f"{'yes' if r['reserve'] else ''} | {inl} | {', '.join(r['drains'])} |")
        return
    print(f"{len(rows)} local containers that are filled or drained, in {len(files)} files\n")
    for k, v in sorted(by.items(), key=lambda kv: -len(kv[1])):
        print(f"{len(v):4d}  {k}")
        if a.sites:
            for r in sorted(v, key=lambda r: (r["file"], r["line"])):
                inl = f" inline {r['inline']}" if r["inline"] else ""
                print(f"        {r['file']}:{r['line']:<5d} {r['fn'][:40]:40s} {r['type']}<{r['elem'][:22]}> {r['name']}{inl}"
                      f"  fills={','.join(r['fills']) or '-'}{' reserved' if r['reserve'] else ''}  drains={','.join(r['drains']) or '-'}")


main()
