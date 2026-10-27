#!/usr/bin/env python3
"""Checks of scripts/benchref.py on generations written here: the pin and its drift, the verdict at its boundary, what a pinned line is
worth (nothing), the golden output, the machine, and what the newest generation does to a verdict.  Exit 0 when every one holds.

usage: check-benchref.py [--lib DIR]      DIR holds the benchref.py to test (default: next to this file); a mutant is tested that way
"""
import argparse, os, sys, tempfile

ap = argparse.ArgumentParser()
ap.add_argument("--lib", default=os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ap.parse_args().lib)
import benchref as b  # noqa: E402

HOST, OTHER = "x86_64 | 8 threads | test cpu", "aarch64 | 10 threads | other cpu"
checks = 0


def check(cond, what):
    global checks
    checks += 1
    if not cond:
        sys.exit("check-benchref: FAILED: " + what)


def write(d, n, sha, host=HOST, nix=None, lix=None, eager=(7, 7, 100), demand=(6, 6, 100), gold="0123456789ab", pinned=()):
    """One generation, one workload `w`.  A tool is (min, median, rss); `pinned` names the tools whose line is a pin."""
    p = os.path.join(d, "%02d-%s" % (n, sha))
    os.makedirs(p)
    tools = [("Nix 2.35.4", nix), ("Lix 2.91.3", lix), ("mlnix", eager), ("mlnix demand", demand)]
    out = [host, "  Nix 2.35.4: x", "", "== w  (5 interleaved rounds, 80 s of a 165 s budget; %sidentical output from all: yes)" % (
        "output sha256 %s; " % gold if gold else "")]
    for name, v in tools:
        if v:
            out.append("   %-14s min %5.2fs  median %5.2fs   peak RSS %5d MB%s" % (name, v[0], v[1], v[2], "   [pinned: best of x]" if name in pinned else "   cpu 4.00s"))
    open(os.path.join(p, "w.txt"), "w").write("\n".join(out) + "\n")


def store(*gens, host=HOST):
    d = tempfile.mkdtemp()
    for i, kw in enumerate(gens, 1):
        write(d, i, "g%d" % i, **kw)
    return b.Store(host, d)


NIX1, NIX2 = (4.0, 4.5, 600), (4.5, 5.0, 650)        # best min 4.0, worst min 4.5: drift 0.125, margin 0.25
LIX1, LIX2 = (8.0, 8.5, 700), (8.0, 8.4, 710)        # drift 0

# the pin
s = store(dict(nix=NIX1, lix=LIX1), dict(nix=NIX2, lix=LIX2))
p = s.pin("w", "Nix 2.35.4") or {}
check(p["min"] == 4.0 and p["median"] == 4.5, "the pin is the best min and the best median, over generations: %r" % p)
check(p["drift"] == 0.125, "drift is (worst min - best min) / best min: %r" % p["drift"])
check(p["rss"] == 650 and p["gens"] == ["01-g1", "02-g2"], "rss is the newest timed one, gens lists the timed ones: %r" % p)
check((s.pin("w", "Lix 2.91.3") or {})["drift"] == 0, "a competitor whose min did not move has drift 0")
check(store(dict(nix=NIX1)).pin("w", "Nix 2.35.4") is None, "one generation is not enough for a drift")
check(s.pin("w", "Nope 1") is None, "an unknown competitor has no pin")

# the verdict at its boundary: needs a lead of more than 2 x 0.125 = 0.25 over the best min 4.0, i.e. a median under 3.0
lead = lambda m: store(dict(nix=NIX1, demand=(5, 5, 1)), dict(nix=NIX2, demand=(m, m, 1))).escaped("w", "Nix 2.35.4")
check(lead(2.97) is True, "a lead of 25.75% (> 25%) is ahead")
check(lead(3.00) is False, "a lead of exactly 25% is not ahead (strictly more)")
check(lead(3.50) is False, "a lead of 12.5% is not ahead when the drift is 12.5%")
check(lead(4.00) is False, "level with the best is not ahead")
check(store(dict(nix=NIX1, lix=LIX1, demand=(5, 5, 1)), dict(nix=NIX2, lix=LIX2, demand=(7.9, 7.9, 1))).escaped("w", "Lix 2.91.3"),
      "a competitor that never moved is beaten by any lead")
check(not store(dict(nix=NIX1, lix=LIX1), dict(nix=NIX2, lix=LIX2, demand=(8.0, 8.0, 1))).escaped("w", "Lix 2.91.3"),
      "level with a competitor that never moved is not ahead")

# the newest generation decides, the eager arm does not
good, bad = (2.0, 2.0, 1), (6.0, 6.0, 1)
check(not store(dict(nix=NIX1, demand=good), dict(nix=NIX2, demand=good), dict(demand=bad)).escaped("w", "Nix 2.35.4"),
      "a newest generation that is not ahead takes the pin away")
check(store(dict(nix=NIX1, demand=bad), dict(nix=NIX2, demand=bad), dict(demand=good)).escaped("w", "Nix 2.35.4"),
      "a newest generation that is ahead pins, whatever the older ones did")
check(store(dict(nix=NIX1), dict(nix=NIX2, demand=good, eager=(9, 9, 1))).escaped("w", "Nix 2.35.4"),
      "the eager arm does not decide")

# a pinned line is not a measurement
s = store(dict(nix=NIX1, demand=good), dict(nix=NIX2, demand=good), dict(nix=(1.0, 1.0, 1), demand=good, pinned=("Nix 2.35.4",)))
p = s.pin("w", "Nix 2.35.4") or {}
check(p["min"] == 4.0 and p["drift"] == 0.125 and len(p["gens"]) == 2, "a pinned line does not move a pin: %r" % p)

# the golden output: the newest recorded one, and a pin needs one
s = store(dict(nix=NIX1, demand=good, gold=None), dict(nix=NIX2, demand=good, gold=None))
check(s.golden("w") is None and not s.escaped("w", "Nix 2.35.4"), "no recorded output hash: nothing is pinned yet")
s = store(dict(nix=NIX1, gold="aaaaaaaaaaaa"), dict(nix=NIX2, gold="bbbbbbbbbbbb"), dict(demand=good, gold=None))
check(s.golden("w") == "bbbbbbbbbbbb", "the golden output is the newest one recorded: %r" % s.golden("w"))
check(s.escaped("w", "Nix 2.35.4"), "a recorded hash from an older generation is enough")

# the machine
s = store(dict(nix=NIX1, demand=good), dict(nix=NIX2, demand=good), host=OTHER)
check(s.generations("w") == [] and s.pin("w", "Nix 2.35.4") is None and s.golden("w") is None, "another machine's generations are not ours")
d = tempfile.mkdtemp()
write(d, 1, "g1", host=OTHER, nix=NIX1, demand=good)
write(d, 2, "g2", nix=NIX1, demand=good)
write(d, 3, "g3", host=OTHER, nix=NIX2, demand=good)
write(d, 4, "g4", nix=NIX2, demand=good)
check([g[0] for g in b.Store(HOST, d).generations("w")] == ["02-g2", "04-g4"], "generations of two machines are told apart")

print("check-benchref: %d checks passed" % checks)
