#!/usr/bin/env python3
"""Which competitors mlnix has left behind on the benchmark host, from the host's own raw output, and what to compare against then.

docs/bench/kali/NN-<sha9>/<workload>.txt are the unedited outputs of scripts/vs-nix.py, one directory per generation.  Of one machine's:

  pin     a competitor's best result on a workload over the generations that timed it: its best min, its best median, and its drift,
          (worst min - best min) / best min, which is how far the host moved the competitor's own best from one generation to the next.
  ahead   the median of `mlnix demand` is under the pin's best min by more than 2 x its drift: a run slower than the best the
          competitor ever managed, by as much as the host has been seen to move that best, still wins.
  golden  the sha256 prefix of the output, recorded by the newest generation in which every evaluator printed the same.

A competitor the newest generation is ahead of, and for which a golden output exists, is not timed again: scripts/vs-nix.py --auto-pin
takes its pin, checks mlnix's output against the golden one, and stops after three rounds once the pin is beaten.  A generation that is
not ahead puts the competitor back among the timed ones for the next.  Only generations of the same machine count (the first line of a
workload file), because a result and an output hash are the machine's: the toplevel's drv path depends on the evaluating host's system.

usage: benchref.py [--dir DIR] [--host LINE]    the table of pins and verdicts
"""
import argparse, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIR = os.path.join(ROOT, "docs", "bench", "kali")
WORKLOADS = ["nixos-toplevel", "nixpkgs-73"]
HEADLINE = "mlnix demand"
FACTOR, MIN_ROUNDS = 2.0, 3
TOOL = re.compile(r"^\s+(Nix [\d.]+|Lix [\d.]+|mlnix demand|mlnix)\s+min\s+([\d.]+)s\s+median\s+([\d.]+)s\s+peak RSS\s+(\d+) MB(.*)$")
GOLD = re.compile(r"^== \S+\s+\(.*output sha256 ([0-9a-f]{12}); identical output from all: yes\)")


def lead(median, p):
    """How far under the pin's best min a median is: 0.1 is ten percent faster."""
    return 1 - median / p["min"]


def ahead(median, p):
    return lead(median, p) > FACTOR * p["drift"]


class Store:
    """The stored generations of one machine."""

    def __init__(self, host, d=DIR):
        self.host, self.d = host, d

    def generations(self, workload):
        """[(NN-sha9, tools, golden)], oldest first.  tools: name -> (min, median, rss, timed); timed is False for a pinned line."""
        out = []
        for g in sorted(x for x in os.listdir(self.d) if re.match(r"\d\d-", x)):
            with open(os.path.join(self.d, g, workload + ".txt")) as stream:
                lines = stream.read().splitlines()
            if lines[0] != self.host:
                continue
            tools, gold = {}, None
            for ln in lines[1:]:
                if m := TOOL.match(ln):
                    tools[m[1]] = (float(m[2]), float(m[3]), int(m[4]), "[pinned" not in m[5])
                elif m := GOLD.match(ln):
                    gold = m[1]
            out.append((g, tools, gold))
        return out

    def pin(self, workload, name):
        rows = [(g, t[name]) for g, t, _ in self.generations(workload) if name in t and t[name][3]]
        if len(rows) < 2:
            return None
        mins = [r[1][0] for r in rows]
        return {"min": min(mins), "median": min(r[1][1] for r in rows), "rss": rows[-1][1][2],
                "drift": (max(mins) - min(mins)) / min(mins), "gens": [g for g, _ in rows]}

    def golden(self, workload):
        return next((gd for _, _, gd in reversed(self.generations(workload)) if gd), None)

    def escaped(self, workload, name):
        """Is the newest generation ahead of `name` on `workload`, with a golden output to check mlnix against in its place?"""
        p, gens = self.pin(workload, name), self.generations(workload)
        return bool(p and self.golden(workload) and HEADLINE in gens[-1][1] and ahead(gens[-1][1][HEADLINE][1], p))


def main():
    ap = argparse.ArgumentParser(description="The pins and verdicts of the stored generations.")
    ap.add_argument("--dir", default=DIR)
    ap.add_argument("--host", help="the machine's line (default: the newest generation's)")
    a = ap.parse_args()
    newest = sorted(x for x in os.listdir(a.dir) if re.match(r"\d\d-", x))[-1]
    s = Store(a.host or open(os.path.join(a.dir, newest, WORKLOADS[0] + ".txt")).readline().rstrip("\n"), a.dir)
    print(s.host)
    print("%-15s %-11s %4s %9s %6s %9s %7s %7s %7s  %s" % ("workload", "competitor", "gens", "best min", "drift", "demand", "lead", "needs", "eager", "next generation"))
    for w in WORKLOADS:
        gens = s.generations(w)
        for n in sorted({n for _, t, _ in gens for n in t if not n.startswith("mlnix")}):
            p, new = s.pin(w, n), gens[-1][1]
            if p is None:
                print("%-15s %-11s %4s  fewer than two generations timed it: timed" % (w, n, "-"))
                continue
            med = new[HEADLINE][1]
            verdict = "pinned" if s.escaped(w, n) else "timed (ahead, but no output hash recorded yet)" if ahead(med, p) and not s.golden(w) else "timed"
            print("%-15s %-11s %4d %8.2fs %5.1f%% %8.2fs %6.1f%% %6.1f%% %6.1f%%  %s" % (
                w, n, len(p["gens"]), p["min"], 100 * p["drift"], med, 100 * lead(med, p), 100 * FACTOR * p["drift"], 100 * lead(new["mlnix"][1], p), verdict))


if __name__ == "__main__":
    main()
