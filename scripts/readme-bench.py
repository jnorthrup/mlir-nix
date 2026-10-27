#!/usr/bin/env python3
"""Render the kali benchmark section of README.md from the raw output of the benchmark host.

docs/bench/kali/NN-<sha9>/ holds, unedited, what scripts/kali-gen.sh and scripts/vs-nix.py printed on the host for one generation
(a commit built, gated and timed there): summary.txt, nixos-toplevel.txt, nixpkgs-73.txt.  NN orders the generations.  This script
reads all of them and rewrites the text between <!-- bench:begin --> and <!-- bench:end --> in README.md: the tables and the parity
line of the newest generation, and the ratio to Nix 2.35.4 of every generation.  The numbers in the README are therefore the host's
own, never retyped, and `--check` fails if they are not.

usage: readme-bench.py [--fetch SHA9] [--readme PATH] [--check]
  --fetch SHA9   first copy that generation's three files from the host (ssh alias `kali`, /tmp/kb/gen-SHA9/) into the next NN-SHA9
  --check        change nothing; exit 1 if the README block is not what the files render to
"""
import argparse, os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIR = os.path.join(ROOT, "docs", "bench", "kali")
BEGIN, END = "<!-- bench:begin -->", "<!-- bench:end -->"
WORKLOADS = ["nixos-toplevel", "nixpkgs-73"]
FILES = ["summary.txt"] + [w + ".txt" for w in WORKLOADS]

TOOL = re.compile(r"^\s+(Nix [\d.]+|Lix [\d.]+|mlnix demand|mlnix)\s+min\s+([\d.]+)s\s+median\s+([\d.]+)s\s+peak RSS\s+(\d+) MB(.*)$")
HEAD = re.compile(r"^== (\S+)\s+\((\d+) interleaved rounds, .*identical output from all: (yes|no)\)")
MEDIAN = re.compile(r"^\s+(mlnix demand|mlnix) / (Nix|Lix) [\d.]+\s+median x([\d.]+)")
STARTUP = re.compile(r"^start-up \(.*\), median of (\d+): (.*)$")
LANG = re.compile(r"lang (eager|demand): TOTAL\s+semantic\s+(\d+/\d+)\s+exact\s+(\d+/\d+)")
FILECHECK = re.compile(r"mlir tests: mlir tests: (.*)$")
PRIMOPS = re.compile(r"primops: primops: (\d+) registered, (\d+) declared")
DIFFTEST = re.compile(r"difftest (eager|demand) \(rc=\d+\): (.*?);?$")


def fail(msg):
    sys.exit("readme-bench: " + msg)


def fetch(sha):
    gens = [d for d in os.listdir(DIR) if re.match(r"\d\d-", d)]
    if any(d.endswith("-" + sha) for d in gens):
        return print("already have", sha)
    dest = os.path.join(DIR, "%02d-%s" % (max([int(d[:2]) for d in gens] + [0]) + 1, sha))
    os.makedirs(dest)
    for f in FILES:
        subprocess.run(["scp", "-q", "kali:/tmp/kb/gen-%s/%s" % (sha, f), dest], check=True)
    if not open(os.path.join(dest, "summary.txt")).read().rstrip().endswith("done"):
        fail("%s: summary.txt does not end in 'done': the generation did not finish" % sha)
    print("fetched", dest)


def parse_workload(path):
    lines = open(path).read().splitlines()
    w = {"host": lines[0], "tools": {}, "startup": "", "median": {}, "pinned": set()}
    for ln in lines[1:]:
        if m := HEAD.match(ln):
            w["name"], w["rounds"], w["identical"] = m[1], int(m[2]), m[3] == "yes"
        elif m := STARTUP.match(ln):
            w["startup"] = m[2]
        elif m := TOOL.match(ln):
            w["tools"][m[1]] = (float(m[2]), float(m[3]), int(m[4]))
            if "[pinned" in m[5]:
                w["pinned"].add(m[1])
        elif m := MEDIAN.match(ln):
            w["median"][(m[1], m[2])] = "×" + m[3]  # the host's own, from unrounded medians
    if "name" not in w or len(w["tools"]) != 4:
        fail("%s: not the output of vs-nix.py (%d tool lines)" % (path, len(w["tools"])))
    if len(w["median"]) != 4:
        fail("%s: expected 4 'median x' ratio lines, found %d" % (path, len(w["median"])))
    if not w["identical"]:
        fail("%s: the evaluators did not print identical output; this is not a comparison" % path)
    return w


def parse_summary(path):
    s = {}
    for ln in open(path).read().splitlines():
        ln = ln[9:] if re.match(r"\d\d:\d\d:\d\d ", ln) else ln
        if m := LANG.match(ln):
            s["lang-" + m[1]] = (m[2], m[3])
        elif m := FILECHECK.match(ln):
            s["filecheck"] = m[1]
        elif m := PRIMOPS.match(ln):
            s["primops"] = (m[1], m[2])
        elif m := DIFFTEST.match(ln):
            s["difftest-" + m[1]] = m[2]
        elif ln.startswith("build rc="):
            s["build"] = ln
    for k in ("lang-eager", "lang-demand", "filecheck", "primops", "difftest-eager", "difftest-demand", "build"):
        if k not in s:
            fail("%s: no %s line" % (path, k))
    return s


def generations():
    gens = []
    for d in sorted(d for d in os.listdir(DIR) if re.match(r"\d\d-", d)):
        p = os.path.join(DIR, d)
        gens.append({"sha": d[3:], "summary": parse_summary(os.path.join(p, "summary.txt")),
                     "w": {n: parse_workload(os.path.join(p, n + ".txt")) for n in WORKLOADS}})
    if not gens:
        fail("no generation under " + DIR)
    return gens


def ratio(a, b):
    return "×%.2f" % (a / b)


def of(tools, prefix):
    return next(v for k, v in tools.items() if k.startswith(prefix))


def table(w):
    t = w["tools"]
    nix, lix, eager, dem = of(t, "Nix"), of(t, "Lix"), t["mlnix"], t["mlnix demand"]
    rows = [("Nix " + next(k for k in t if k.startswith("Nix"))[4:], nix), ("Lix " + next(k for k in t if k.startswith("Lix"))[4:], lix),
            ("mlnix, eager", eager), ("mlnix, demand", dem)]
    out = ["| %s | min | median | peak RSS |" % w["name"], "|---|---:|---:|---:|"]
    pin = lambda n: " (pinned: its best, not timed again)" if any(n.startswith(p) for p in w["pinned"]) else ""
    out += ["| %s%s | %.2f s | %.2f s | %d MB |" % (n, pin(n), v[0], v[1], v[2]) for n, v in rows]
    m = w["median"]
    out.append("| **demand / Nix** | **%s** | **%s** | %s |" % (ratio(dem[0], nix[0]), m[("mlnix demand", "Nix")], ratio(dem[2], nix[2])))
    out.append("| demand / Lix | %s | %s | %s |" % (ratio(dem[0], lix[0]), m[("mlnix demand", "Lix")], ratio(dem[2], lix[2])))
    return "\n".join(out)


def render(gens):
    g = gens[-1]
    s, w0 = g["summary"], g["w"][WORKLOADS[0]]
    rounds = {w["rounds"] for w in g["w"].values()}
    L = ["<!-- generated by scripts/readme-bench.py from docs/bench/kali/; edit those files or the script, not this block -->", ""]
    arch, threads, cpu = w0["host"].split(" | ")
    L.append("Latest generation: commit `%s`, measured on an %s (%s, %s), %s interleaved rounds per workload, every evaluator's output identical to the others'." %
             (g["sha"], cpu, arch, threads, "/".join(map(str, sorted(rounds)))))
    L.append("")
    for n in WORKLOADS:
        L += [table(g["w"][n]), ""]
    L.append("Start-up (`--eval -E 1`, median of 5): %s." % w0["startup"])
    L.append("")
    same = lambda a, b: a == b
    le, ld = s["lang-eager"], s["lang-demand"]
    L.append("Parity at this commit, on the same host: Nix's language tests %s semantic and %s exact (stderr too)%s; dialect tests (FileCheck): %s; "
             "primops: %s registered, %s declared; differential tests, eager: %s; demand: %s." %
             (le[0], le[1], " on both schedules" if same(le, ld) else " eager (demand: %s, %s)" % ld, s["filecheck"], *s["primops"],
              s["difftest-eager"].replace(";", ", "), s["difftest-demand"].replace(";", ", ")))
    L += ["", "Every generation, as the ratio of `mlnix, demand` to Nix 2.35.4 (below 1 is faster; minima are computed from the printed minima, medians are the host's own) and its peak memory:", "",
          "| commit | toplevel min | toplevel median | nixpkgs-73 min | nixpkgs-73 median | toplevel RSS |", "|---|---:|---:|---:|---:|---:|"]
    for g in gens:
        r = []
        for n in WORKLOADS:
            t = g["w"][n]["tools"]
            nix, dem = of(t, "Nix"), t["mlnix demand"]
            r += [ratio(dem[0], nix[0]), g["w"][n]["median"][("mlnix demand", "Nix")]]
        t = g["w"][WORKLOADS[0]]["tools"]
        L.append("| `%s` | %s | %s | %s | %s | %s |" % (g["sha"], *r, ratio(t["mlnix demand"][2], of(t, "Nix")[2])))
    return "\n".join(L)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fetch", metavar="SHA9")
    ap.add_argument("--readme", default=os.path.join(ROOT, "README.md"))
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()
    if a.fetch:
        fetch(a.fetch)
    block = render(generations())
    text = open(a.readme).read()
    i, j = text.find(BEGIN), text.find(END)
    if i < 0 or j < i:
        fail("%s has no %s ... %s block" % (a.readme, BEGIN, END))
    new = text[:i + len(BEGIN)] + "\n" + block + "\n" + text[j:]
    if a.check:
        if new != text:
            sys.exit("readme-bench: README.md is out of date; run scripts/readme-bench.py")
        return print("README.md is up to date")
    open(a.readme, "w").write(new)
    print("wrote", a.readme, "(%d generations, newest %s)" % (len(generations()), generations()[-1]["sha"]))


if __name__ == "__main__":
    main()
