#!/usr/bin/env python3
"""tptp-summary.py RESULTS.tsv RUNS.jsonl: kali-tptp-tests.sh's results next to test 2's (logs/vampire/runs.jsonl), a test
a line: the status Vampire gave mlnix-kif's problem, and the statuses it gave SigmaKEE's in each of test 2's sets
(sigma: SigmaKEE's FOF or TFF translation; sigma1: the same, one process per test; tqsp: ..; -t300: the 300 s runs;
tfffix-: the typed KB repaired), then the counts.
"""
import collections, json, sys


def main(argv):
    runs = collections.defaultdict(dict)
    for line in open(argv[2]):
        r = json.loads(line)
        runs[r["test"]][r["set"]] = r["szs"]
    rows, counts = [], collections.Counter()
    for line in open(argv[1]):
        f = line.rstrip("\n").split("\t")
        test, ours, secs = f[0], f[3].split("=", 1)[1], f[4]
        conj = f[2].split("=", 1)[1]
        cmp_ = f[6] if len(f) > 6 else ""
        sig = runs.get(test, {})
        best = "Theorem" if "Theorem" in sig.values() else ("Timeout" if "Timeout" in sig.values() else "none")
        fof = sig.get("sigma", "-")
        rows.append((test, ours, secs, conj, " ".join(f"{k}:{v}" for k, v in sorted(sig.items())), cmp_))
        counts[(ours, best)] += 1
    w = max(len(r[0]) for r in rows)
    for r in rows:
        print(f"{r[0]:{w}}  ours {r[1]:14} {r[2]:>7}  conj {r[3]:40.40}  test 2: {r[4]}")
        if r[5]:
            print(f"{'':{w}}  vs SigmaKEE's problem: {r[5]}")
    print()
    print("ours vs test 2's best (any set):")
    for (o, b), k in sorted(counts.items(), key=lambda kv: -kv[1]):
        print(f"  ours {o:14} test 2 {b:8} {k}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
