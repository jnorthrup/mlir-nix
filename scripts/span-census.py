#!/usr/bin/env python3
"""How span-based is the code?  Static counts over lib/ include/ tools/ (not Composite/), by directory (run from anywhere).

A span is a non-owning (pointer, count): std::string_view, llvm::StringRef, llvm::ArrayRef, composite::Slice, std::span, nixfe::Name.
Owning containers: std::string, std::vector, std::map, std::set, std::unordered_map, std::function, llvm::SmallVector.
"""
import collections, pathlib, re

ROOT = pathlib.Path(__file__).resolve().parent.parent
AREAS = {
    "front end (lib/Frontend, include/Nix/{AST,Pos,Name,LexRules,Confix,MLIRGen}.h)":
        lambda p: "lib/Frontend" in p or any(p.endswith(f"include/Nix/{n}.h") for n in ("AST", "Pos", "Name", "LexRules", "Confix", "MLIRGen")),
    "evaluator (lib/Eval, include/Nix/Eval.h, Arena.h)":
        lambda p: "lib/Eval" in p or p.endswith("include/Nix/Eval.h") or p.endswith("include/Nix/Arena.h"),
    "store (lib/Store, include/Nix/Store*.h)": lambda p: "lib/Store" in p or "include/Nix/Store" in p or "include/Nix/Hash" in p,
    "dialects (lib/Dialect, include/NixDialect)": lambda p: "lib/Dialect" in p or "include/NixDialect" in p,
    "tools": lambda p: p.startswith("tools/"),
}
SPAN = {"string_view": r"\bstd::string_view\b", "StringRef": r"\bllvm::StringRef\b|\bStringRef\b", "ArrayRef": r"\b(?:llvm::)?(?:Mutable)?ArrayRef<",
        "Slice": r"\bSlice<", "Name": r"\bnixfe::Name\b|\bName\b(?=\s*[&\w])"}
OWN = {"std::string": r"\bstd::string\b(?!_view)", "std::vector": r"\bstd::vector<", "std::map": r"\bstd::map<", "std::set": r"\bstd::set<",
       "std::unordered_*": r"\bstd::unordered_(?:map|set)<", "std::function": r"\bstd::function<", "SmallVector": r"\b(?:llvm::)?SmallVector<"}
# signatures: a parameter or a return type
PARAM_OWN = re.compile(r"[(,]\s*(?:const\s+)?std::(?:string|vector<[^()]*?>)\s*(?:&)?\s*\w*\s*[,)]")
PARAM_VIEW = re.compile(r"[(,]\s*(?:const\s+)?(?:std::string_view|llvm::StringRef|StringRef|llvm::ArrayRef<[^()]*?>|ArrayRef<[^()]*?>)\s*\w*\s*[,)]")
RET_OWN = re.compile(r"^\s*(?:static\s+|inline\s+)?(?:std::string|std::vector<[^()]*?>)\s+(?:\w+::)?\w+\s*\(", re.M)
RET_VIEW = re.compile(r"^\s*(?:static\s+|inline\s+)?(?:std::string_view|llvm::StringRef|StringRef|llvm::ArrayRef<[^()]*?>|ArrayRef<[^()]*?>)\s+(?:\w+::)?\w+\s*\(", re.M)

files = [p for d in ("lib", "include", "tools") for p in sorted((ROOT / d).rglob("*"))
         if p.suffix in (".cpp", ".h") and "Composite" not in p.parts and "build" not in p.parts]
tot = collections.defaultdict(collections.Counter)
lines = collections.Counter()
for p in files:
    rel = str(p.relative_to(ROOT))
    text = re.sub(r"//.*", "", p.read_text(errors="replace"))
    for area, pred in AREAS.items():
        if not pred(rel):
            continue
        c = tot[area]
        lines[area] += text.count("\n")
        for k, rx in {**SPAN, **OWN}.items():
            c[k] += len(re.findall(rx, text))
        c["param owning"] += len(PARAM_OWN.findall(text))
        c["param view"] += len(PARAM_VIEW.findall(text))
        c["return owning"] += len(RET_OWN.findall(text))
        c["return view"] += len(RET_VIEW.findall(text))
        break
cols = list(SPAN) + list(OWN) + ["param view", "param owning", "return view", "return owning"]
for area, c in tot.items():
    print(f"\n{area}   [{lines[area]} lines]")
    print("   spans:    " + "  ".join(f"{k} {c[k]}" for k in SPAN))
    print("   owning:   " + "  ".join(f"{k} {c[k]}" for k in OWN))
    print(f"   signatures: params view {c['param view']} / owning {c['param owning']};  returns view {c['return view']} / owning {c['return owning']}")
