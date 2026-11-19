#!/usr/bin/env python3
"""cxx-interfaces.py BUILD [--out DIR] [--jobs N]: the interfaces between mlir-nix's C++ components, read from what the compiler
makes of each translation unit.  Every entry of BUILD/compile_commands.json is compiled again with its own flags to LLVM IR
(-S -emit-llvm), and:

  - a function or variable one component defines (external linkage) and another component uses is an interface (a component
    is a CMake target: NixEval, NixStore, NixFrontend, MLIRNix, MLIRTrikeShed, TrikeShedRuntime, and each tool);
  - its form is the ABI signature the compiler gave it: what a lowered implementation must define for the C++ callers to keep
    linking, and what a lowered caller declares;
  - what it needs is what its code reaches inside its translation unit (calls, function pointers, globals, through the unit's
    own helpers), by kind:
      C          libc and the system (malloc, write, io_uring_*): MLIR's llvm dialect calls these as mlnixci does;
      C++ rt     the C++ runtime: new/delete, std::, exceptions (__cxa_throw, a landing pad): replace these first;
      MLIR API   MLIR's and LLVM's C++ classes: compiler code, whose lowering is to declarations (ODS, IRDL, PDL), not code;
                 so is everything a dialect library (MLIRNix, MLIRTrikeShed) exports, whatever its code reaches.
    A call of another component's interface is listed, and does not raise the kind.

Writes DIR/README.md (the components; each interface by provider and user, with its C++ signature, its ABI and what it
needs) and DIR/<component>.mlir (the component's interface as llvm.func declarations, made by mlir-translate --import-llvm,
each named by its C++ signature).  DIR defaults to docs/interfaces in the source tree.  The LLVM tools (llvm-cxxfilt,
mlir-translate) come from LLVM_BIN, else /usr/lib/llvm-22/bin, else /opt/homebrew/opt/llvm/bin.
"""
import collections, concurrent.futures, json, os, re, shlex, subprocess, sys, tempfile

args = sys.argv[1:]
if not args or args[0].startswith("-"):
    sys.exit(__doc__)
BUILD = os.path.abspath(args[0])
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "docs/interfaces")
JOBS = os.cpu_count() or 4
i = 1
while i < len(args):
    if args[i] == "--out": OUT = os.path.abspath(args[i + 1]); i += 2
    elif args[i] == "--jobs": JOBS = int(args[i + 1]); i += 2
    else: sys.exit(f"unknown argument {args[i]}")
LLVM_BIN = os.environ.get("LLVM_BIN") or next(
    (d for d in ("/usr/lib/llvm-22/bin", "/opt/homebrew/opt/llvm/bin") if os.path.exists(os.path.join(d, "mlir-translate"))), "")

# ── the translation units, compiled to IR ─────────────────────────────────────────────────────────────────────────

def component(entry):
    """The CMake target an entry's object belongs to (its CMakeFiles/<target>.dir), obj.X read as X."""
    out = entry.get("output") or shlex.split(entry["command"])[shlex.split(entry["command"]).index("-o") + 1]
    m = re.search(r"CMakeFiles/([^/]+)\.dir/", out)
    t = m.group(1) if m else "?"
    return t[4:] if t.startswith("obj.") else t

def ir_command(entry):
    argv = entry.get("arguments") or shlex.split(entry["command"])
    out, skip = [], False
    for a in argv:
        if skip: skip = False; continue
        if a == "-o": skip = True; continue
        if a == "-c": continue
        out.append(a)
    return out + ["-S", "-emit-llvm", "-o", "-"]

entries = [e for e in json.load(open(os.path.join(BUILD, "compile_commands.json"))) if not e["file"].endswith(".hxx.cxx")]

def compile_ir(e):
    """The unit, read from its IR (parsed here, so no unit's text outlives its reading)."""
    p = subprocess.run(ir_command(e), cwd=e.get("directory", BUILD), capture_output=True, text=True)
    if p.returncode != 0:
        raise SystemExit(f"cxx-interfaces: {e['file']}: the IR compile failed:\n{p.stderr[-2000:]}")
    return Unit(e, p.stdout)

# ── the IR, read ──────────────────────────────────────────────────────────────────────────────────────────────────

NAME = r'@("(?:[^"\\]|\\.)*"|[-\w$.]+)'
LINKAGES = {"private", "internal", "available_externally", "linkonce", "weak", "common", "appending", "extern_weak",
            "linkonce_odr", "weak_odr", "external"}

def unquote(n):
    return n[1:-1].encode().decode("unicode_escape") if n.startswith('"') else n

def close_of(s, i):
    """The index just past the bracket that closes the one at s[i]."""
    pairs = {"(": ")", "{": "}", "[": "]", "<": ">"}
    stack = []
    for j in range(i, len(s)):
        c = s[j]
        if c in pairs: stack.append(pairs[c])
        elif stack and c == stack[-1]:
            stack.pop()
            if not stack: return j + 1
    return len(s)

def split_top(s):
    parts, depth, cur = [], 0, []
    for c in s:
        if c in "({[<": depth += 1
        elif c in ")}]>": depth -= 1
        if c == "," and depth == 0: parts.append("".join(cur).strip()); cur = []
        else: cur.append(c)
    if "".join(cur).strip(): parts.append("".join(cur).strip())
    return parts

def lead_type(s):
    """The type a parameter starts with."""
    s = s.strip()
    if s and s[0] in "{[<": return s[:close_of(s, 0)]
    return s.split()[0] if s else ""

ABI_ATTRS = re.compile(r"\b(sret|byval|inalloca|preallocated)\s*\(|\b(zeroext|signext|inreg|swiftself|swifterror)\b")

class Unit:
    def __init__(self, entry, text):
        self.file = os.path.relpath(entry["file"], REPO)
        self.comp = component(entry)
        self.header = [l for l in text.splitlines() if l.startswith(("target datalayout", "target triple"))]
        self.types = {}      # %name -> its definition line
        self.defs = {}       # symbol -> {"kind", "linkage", "sig", "refs", "eh"}
        self.decls = {}      # symbol -> its declaration (a function: its declare line; a variable: its line)
        lines = text.splitlines()
        k = 0
        while k < len(lines):
            l = lines[k]
            if l.startswith("%") and " = type " in l:
                self.types[l.split(" = type ")[0]] = l
            elif l.startswith("define "):
                body = []
                k += 1
                while k < len(lines) and lines[k] != "}":
                    body.append(lines[k]); k += 1
                self.function(l, body)
            elif l.startswith("declare "):
                m = re.search(NAME, l)
                if m: self.decls[unquote(m.group(1))] = l
            elif l.startswith("@"):
                self.variable(l)
            k += 1

    def function(self, head, body):
        m = re.search(NAME + r"\(", head)
        name = unquote(m.group(1))
        pre = head[len("define "):m.start()].split()
        linkage = next((t for t in pre if t in LINKAGES), "external")
        p0 = m.end() - 1
        p1 = close_of(head, p0)
        refs = set()
        for b in body + [head[p1:]]:
            for r in re.findall(NAME, b): refs.add(unquote(r))
        refs.discard(name)
        eh = "personality" in head[p1:] or any("landingpad" in b or "__cxa_throw" in b for b in body)
        self.defs[name] = {"kind": "function", "linkage": linkage, "head": head, "params": head[p0 + 1:p1 - 1],
                           "pre": head[len("define "):m.start()], "refs": refs, "eh": eh, "body": body}

    def variable(self, l):
        m = re.match(NAME + r"\s*=\s*(.*)$", l)
        if not m: return
        name, rest = unquote(m.group(1)), m.group(2)
        toks = rest.split()
        if not ({"global", "constant"} & set(toks)): return  # an alias, an ifunc
        if {"external", "extern_weak"} & set(toks[:3]):  # a declaration: a definition never spells external linkage
            self.decls[name] = l
            return
        linkage = next((t for t in toks[:4] if t in LINKAGES), "external")
        refs = {unquote(r) for r in re.findall(NAME, rest)}
        refs.discard(name)
        self.defs[name] = {"kind": "variable", "linkage": linkage, "head": l, "refs": refs, "eh": False}

    def exported(self):
        return {n: d for n, d in self.defs.items() if d["linkage"] in ("external", "weak", "common")}

# ── the components, joined ────────────────────────────────────────────────────────────────────────────────────────

def demangle_all(names):
    tool = os.path.join(LLVM_BIN, "llvm-cxxfilt") if LLVM_BIN else "c++filt"
    names = sorted(names)
    p = subprocess.run([tool, "-n"] if LLVM_BIN else [tool], input="\n".join(names), capture_output=True, text=True)
    out = p.stdout.splitlines()
    return dict(zip(names, out)) if len(out) == len(names) else {n: n for n in names}

def kind_of(sym, dem):
    """Where an external symbol comes from: C (libc, the system), C++ rt, MLIR API."""
    d = dem.get(sym, sym)
    if sym.startswith("llvm."): return None  # an intrinsic
    if (sym.startswith(("__cxa_", "__gxx_", "_Unwind_", "__dynamic_cast", "_ZTVN10__cxxabiv", "_ZTIN10__cxxabiv"))
            or d.startswith(("std::", "operator new", "operator delete", "typeinfo for std::", "vtable for std::",
                             "typeinfo name for std::", "vtable for __cxxabiv1", "typeinfo for __cxxabiv1",
                             "__gnu_cxx::", "VTT for std::")) or re.match(r"(typeinfo|vtable) for (int|char|long|void|unsigned)", d)):
        return "C++ rt"
    if re.match(r"(typeinfo for |vtable for |typeinfo name for |guard variable for )?(mlir|llvm)::", d) or d.startswith("(anonymous namespace)::mlir"):
        return "MLIR API"
    if sym.startswith("_Z"): return "C++ other"
    return "C"

READONLY_LIBC = {"memcmp", "bcmp", "memchr", "strlen", "strnlen", "strncmp", "strcmp", "strchr", "strrchr",
                 "strspn", "strcspn", "strpbrk", "strstr", "strcasecmp", "strncasecmp", "strcasestr"}

def const_flag(name, d, demangled):
    """For a C++ method, whether clang proved `this` read-only.  At the build's optimization level clang's
    function-attrs pass marks the `this` parameter `readonly` (reads, never writes) or `readnone` when the
    method cannot mutate the object: that is the compiler's own proof, and a non-const method carrying it is
    a const candidate.  `this` is the first pointer parameter, or the second when the first is an sret return
    buffer; a function whose first non-sret parameter is not a pointer, or whose name is a single
    namespace::function, is a free function (no `this`).  The fix lane confirms each by adding const and
    rebuilding (a static method or a free function rejects const at compile time)."""
    if not name.startswith("_ZN"): return None
    declared = name.startswith("_ZNK")
    params = split_top(d.get("params", ""))
    if not params: return None
    pi = 1 if re.search(r"\bsret\b", params[0]) else 0
    if pi >= len(params): return None
    p = params[pi].strip()
    if not p.startswith("ptr"): return None  # no pointer `this`: a free function
    if len(demangled.split("(")[0].split("::")) < 3: return None  # need namespace::Class::method; ns::func is free
    ro = bool(re.search(r"\b(readonly|readnone)\b", p))
    return ("reads-only" if ro else "may-mutate", declared)

def features(r, dem):
    """Which parts of the C++ runtime an interface's code reaches: exceptions, new/delete, std:: calls, RTTI."""
    f = set()
    for x in r["C++ rt"] | r["C++ other"]:
        d = dem.get(x, x)
        if x == "(exceptions)" or x.startswith(("__cxa_", "__gxx_personality", "_Unwind_")): f.add("exceptions")
        elif d.startswith(("operator new", "operator delete")): f.add("new/delete")
        elif d.startswith(("typeinfo", "vtable", "VTT")) or x.startswith("__dynamic_cast"): f.add("RTTI")
        else: f.add("std::" if d.startswith(("std::", "__gnu_cxx::")) else "other C++")
    return f

def mlir_named(n, dem):
    """An interface that is itself MLIR's or LLVM's C++ API: an op class ODS made, a TypeID, a pass's registration."""
    return bool(re.match(r"(typeinfo for |vtable for |typeinfo name for |guard variable for )?(mlir|llvm)::", dem.get(n, n)))

def main():
    with concurrent.futures.ThreadPoolExecutor(JOBS) as ex:
        units = list(ex.map(compile_ir, entries))
    provider = {}  # symbol -> the component that defines it (external linkage), or None when several do
    for u in units:
        for n in u.exported():
            provider[n] = u.comp if provider.get(n, u.comp) == u.comp else None
    allsyms = set(provider)
    for u in units:
        for d in u.defs.values(): allsyms |= d["refs"]
        allsyms |= set(u.decls)
    dem = demangle_all(allsyms)

    # what each exported definition reaches inside its unit
    reach = {}  # (unit file, symbol) -> {"project": {sym: comp}, "C": set, "C++ rt": set, "MLIR API": set, "C++ other": set, "eh": bool}
    for u in units:
        for n, d in u.exported().items():
            seen, todo = {n}, [n]
            r = {"project": {}, "C": set(), "C++ rt": set(), "MLIR API": set(), "C++ other": set(), "eh": False}
            while todo:
                x = u.defs[todo.pop()]
                r["eh"] |= x["eh"]
                for ref in x["refs"]:
                    if ref in seen: continue
                    seen.add(ref)
                    if ref in u.defs:
                        if u.defs[ref]["linkage"] in ("external", "weak", "common") and ref != n and provider.get(ref):
                            r["project"][ref] = u.comp  # another interface of this unit: listed, and followed
                        todo.append(ref)
                    elif provider.get(ref):
                        r["project"][ref] = provider[ref]
                    else:
                        k = kind_of(ref, dem)
                        if k: r[k].add(ref)
            if r["eh"]: r["C++ rt"].add("(exceptions)")
            reach[(u.file, n)] = r

    # the interfaces: a symbol defined by one component and named by a unit of another
    users = collections.defaultdict(set)  # symbol -> components that use it
    for u in units:
        named = set(u.decls)
        for d in u.defs.values(): named |= d["refs"]
        for n in named:
            p = provider.get(n)
            if p and p != u.comp: users[n].add(u.comp)
    home = {}  # symbol -> (unit, def)
    for u in units:
        for n, d in u.exported().items():
            if provider.get(n) == u.comp: home[n] = (u, d)

    def level(r, n=None):
        if n is not None and (mlir_named(n, dem) or provider.get(n, "").startswith("MLIR")): return "MLIR API"
        return "MLIR API" if r["MLIR API"] else "C++ rt" if (r["C++ rt"] or r["C++ other"]) else "C"

    def abi(u, d):
        if d["kind"] == "variable":
            m = re.match(NAME + r"\s*=\s*(.*?)\b(global|constant)\s+(.*)$", d["head"])
            return f"{m.group(3)} {lead_type(m.group(4))}" if m else "variable"
        params = [lead_type(p) + "".join(f" {a.group(0).rstrip('(')}" for a in ABI_ATTRS.finditer(p)) for p in split_top(d["params"])]
        pre = d["pre"].strip()
        opener = {"}": "{", "]": "[", ">": "<"}.get(pre[-1:] if pre else "")
        ret = pre[pre.rfind(opener):] if opener else (pre.split()[-1] if pre else "void")
        rattrs = "".join(f"{a} " for a in ("zeroext", "signext") if re.search(rf"\b{a}\b", pre))
        return f"{rattrs}{ret} ({', '.join(params)})"

    os.makedirs(OUT, exist_ok=True)
    comps = sorted({u.comp for u in units})
    runtime_names = {}
    rows = []
    for c in comps:
        us = [u for u in units if u.comp == c]
        defined = sum(1 for u in us for d in u.defs.values() if d["kind"] == "function")
        exported = [n for n in home if home[n][0].comp == c and users.get(n)]
        names = collections.defaultdict(set)  # each name once per component
        for u in us:
            named = set(u.decls)
            for d in u.defs.values(): named |= d["refs"]
            for n in named:
                if n in u.defs: continue
                p = provider.get(n)
                if p and p != c: names["project"].add(n)
                elif not p:
                    k = kind_of(n, dem)
                    if k: names[k].add(n)
        imports = collections.Counter({k: len(v) for k, v in names.items()})
        runtime_names[c] = names["C++ rt"] | names["C++ other"]
        lv = collections.Counter(level(reach[(home[n][0].file, n)], n) for n in exported)
        ft = collections.Counter()
        for n in exported:
            if level(reach[(home[n][0].file, n)], n) == "C++ rt":
                for x in features(reach[(home[n][0].file, n)], dem): ft[x] += 1
        rows.append((c, len(us), defined, len(exported), lv, imports, ft))

    md = []
    w = md.append
    triple = next((l for u in units for l in u.header if l.startswith("target triple")), "")
    w("# The C++ interfaces\n")
    w(f"Generated by `scripts/cxx-interfaces.py` from a build's translation units, each compiled again with its own flags to")
    w(f"LLVM IR ({triple.split('=')[-1].strip()}).  Do not edit: run it again.\n")
    w("A component is a CMake target.  An interface is a function or variable one component defines and another uses.  Its ABI")
    w("is the signature the compiler gave it: what a lowered implementation must define so the C++ callers keep linking, and")
    w("what a lowered caller declares (`<component>.mlir` has each component's interface as `llvm.func` declarations).  What it")
    w("needs is what its code reaches inside its translation unit, through the unit's own helpers:\n")
    w("- **C**: libc and the system only (and other interfaces): it can be written in MLIR's dialects now, calling libc as mlnixci does;")
    w("- **C++ rt**: the C++ runtime as well: new/delete, `std::`, exceptions (a throw or a landing pad): those go first;")
    w("- **MLIR API**: MLIR's or LLVM's C++ classes: compiler code, whose lowering is to declarations (ODS, IRDL, PDL), not to code.\n")
    w("## Components\n")
    w("| component | units | functions defined | interface (used elsewhere) | of it C / C++ rt / MLIR API | names it imports: project / C / C++ rt / MLIR API |")
    w("|---|---|---|---|---|---|")
    for c, nu, defined, nexp, lv, imp, ft in rows:
        w(f"| {c} | {nu} | {defined} | {nexp} | {lv['C']} / {lv['C++ rt']} / {lv['MLIR API']} | "
          f"{imp['project']} / {imp['C']} / {imp['C++ rt'] + imp['C++ other']} / {imp['MLIR API']} |")
    w("")
    w("What the interfaces that need the C++ runtime need of it (one interface can need several):\n")
    w("| component | C++ rt interfaces | exceptions | new/delete | std:: calls | RTTI | other C++ |")
    w("|---|---|---|---|---|---|---|")
    for c, nu, defined, nexp, lv, imp, ft in rows:
        if lv["C++ rt"]:
            w(f"| {c} | {lv['C++ rt']} | {ft['exceptions']} | {ft['new/delete']} | {ft['std::']} | {ft['RTTI']} | {ft['other C++']} |")
    w("")
    for c in comps:
        syms = sorted((n for n in home if home[n][0].comp == c and users.get(n)), key=lambda n: dem.get(n, n))
        if not syms: continue
        w(f"## {c}: {len(syms)} used by other components\n")
        by_user = collections.defaultdict(list)
        for n in syms:
            by_user[", ".join(sorted(users[n]))].append(n)
        for who in sorted(by_user):
            w(f"### used by {who}\n")
            w("| C++ | ABI | needs | unit |")
            w("|---|---|---|---|")
            for n in by_user[who]:
                u, d = home[n]
                r = reach[(u.file, n)]
                needs = level(r, n)
                extra = []
                if mlir_named(n, dem) or c.startswith("MLIR"): extra.append("is MLIR's API (a dialect library's)")
                elif needs != "C":
                    if r["C++ rt"] or r["C++ other"]: extra.append(", ".join(sorted(features(r, dem))))
                    if r["MLIR API"]:
                        top = sorted({re.sub(r"<.*", "", dem.get(x, x)).split("(")[0] for x in r["MLIR API"]})
                        extra.append(f"{len(r['MLIR API'])} MLIR/LLVM names ({', '.join(top[:3])}{', ...' if len(top) > 3 else ''})")
                cell = needs + (": " + "; ".join(extra) if extra else "")
                sig = dem.get(n, n).replace("|", "\\|")
                w(f"| `{sig}` | `{abi(u, d).replace('|', '/')}` | {cell.replace('|', '/')} | {os.path.basename(u.file)} |")
            w("")
    w("## The C++ runtime each component imports\n")
    w("Every name a component's units reach in the C++ runtime (libc++ or libstdc++, libc++abi or libsupc++), whether or not an")
    w("interface reaches it: what has to go for the component to link without a C++ runtime.\n")
    for c in comps:
        rn = sorted({re.sub(r"\(.*", "", dem.get(x, x)) for x in runtime_names.get(c, ())})
        if rn:
            w(f"- **{c}** ({len(rn)}): " + ", ".join(f"`{x}`" for x in rn))
    w("")
    w("## Const audit (the hand-written runtime's interface methods)\n")
    w("Only NixEval, NixStore, NixFrontend and the tools: the dialect libraries (MLIRNix, MLIRTrikeShed) are MLIR's")
    w("API and lower to declarations, not const-ification.  The signal is clang's own: at the build's optimization")
    w("level it marks a method's `this` parameter `readonly`/`readnone` when the method cannot mutate the object.")
    w("reads-only = clang proved `this` read-only; may-mutate = it did not.  A reads-only method not yet declared const")
    w("is a candidate to REVIEW, not an automatic change: physical read-only of `this` is not logical const.  A method")
    w("that mutates state through a member pointer (Store::deletePath, ensurePath, addTextToStore, registerValidPath, ...)")
    w("is physically reads-only here but logically mutating, and must NOT be made const.  Pure readers (showType,")
    w("isValidPath, queryPathInfo, allValidPaths, queryReferrers, resolveExprPath, ...) are the real candidates.  The fix")
    w("lane decides each and confirms by adding const and rebuilding.\n")
    cand = []
    counts = collections.Counter()
    for c in comps:
        if c.startswith("MLIR"): continue
        for n in sorted((n for n in home if home[n][0].comp == c and users.get(n)), key=lambda n: dem.get(n, n)):
            u, d = home[n]
            if d["kind"] != "function": continue
            cf = const_flag(n, d, dem.get(n, n))
            if cf is None: continue
            flag, declared = cf
            counts[(c, flag, declared)] += 1
            if flag == "reads-only" and not declared:
                cand.append((c, dem.get(n, n), os.path.basename(u.file)))
    w("| component | reads-only | of it not yet const (candidates) | may-mutate |")
    w("|---|---|---|---|---|")
    for c in comps:
        if c.startswith("MLIR"): continue
        ro = counts[(c, "reads-only", True)] + counts[(c, "reads-only", False)]
        ca = counts[(c, "reads-only", False)]
        mu = counts[(c, "mutates", True)] + counts[(c, "mutates", False)]
        if ro or mu:
            w(f"| {c} | {ro} | {ca} | {mu} |")
    w("")
    if cand:
        w("Const candidates (reads-only `this`, not yet const):\n")
        for c, sig, unit in cand:
            w(f"- `{sig}` ({c}, {unit})")
        w("")
    open(os.path.join(OUT, "README.md"), "w").write("\n".join(md) + "\n")

    # each component's interface as MLIR declarations
    for c in comps:
        syms = [n for n in home if home[n][0].comp == c and users.get(n)]
        if not syms: continue
        pieces = []
        for u in sorted({home[n][0] for n in syms}, key=lambda u: u.file):
            mine = [n for n in syms if home[n][0] is u]
            lines = list(u.header) + list(u.types.values())
            for n in mine:
                d = u.defs[n]
                if d["kind"] == "function":
                    params = ", ".join(re.sub(r"\s+%[-\w$.\"]+$", "", p) for p in split_top(d["params"]))
                    pre = re.sub(r"\b(" + "|".join(LINKAGES) + r"|dso_local|hidden|protected|local_unnamed_addr|unnamed_addr|dllexport)\b", "", d["pre"])
                    lines.append(f"declare {pre.strip()} @\"{n}\"({params})")
                else:
                    m = re.match(NAME + r"\s*=\s*(.*?)\b(global|constant)\s+(.*)$", d["head"])
                    ty = lead_type(m.group(4))
                    quals = re.sub(r"\b(" + "|".join(LINKAGES) + r"|dso_local|hidden|protected|dllexport)\b", "", m.group(2)).split()
                    lines.append(" ".join([f"@\"{n}\" = external"] + quals + [m.group(3), ty]))
            with tempfile.NamedTemporaryFile("w", suffix=".ll", delete=False) as f:
                f.write("\n".join(lines) + "\n")
            p = subprocess.run([os.path.join(LLVM_BIN, "mlir-translate"), "--import-llvm", f.name], capture_output=True, text=True)
            os.unlink(f.name)
            if p.returncode != 0:
                raise SystemExit(f"cxx-interfaces: mlir-translate on {u.file}'s interface: {p.stderr[-1500:]}")
            pieces.append((u.file, p.stdout))
        out = [f"// {c}'s interface: what other components use, as the compiler's ABI gives it (scripts/cxx-interfaces.py; do not edit)."]
        for file, text in pieces:
            out.append(f"\n// ── {file}")
            for l in text.splitlines():
                s = l.strip()
                m = re.match(r'(llvm\.func|llvm\.mlir\.global)\b.*?@("(?:[^"\\]|\\.)*"|[-\w$.]+)', s)
                if not m: continue
                n = unquote(m.group(2))
                out.append(f"// {dem.get(n, n)}")
                out.append(s)
        open(os.path.join(OUT, f"{c}.mlir"), "w").write("module {\n" + "\n".join("  " + l if l else l for l in out) + "\n}\n")
    total = sum(r[3] for r in rows)
    print(f"cxx-interfaces: {len(units)} units, {len(comps)} components, {total} interface symbols; written to {OUT}")

main()
