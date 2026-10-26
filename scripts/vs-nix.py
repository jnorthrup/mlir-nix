#!/usr/bin/env python3
"""mlnix against reference Nix (container "nixref"), interleaved on the same machine.

usage: vs-nix.py [--runs N] [--mlnix PATH] [--no-copy] [--gc-heap SIZE] [--ref NAME=PATH ...]

* Reference Nix runs INSIDE the container and is timed there (date +%s%N), so
  `docker exec` start-up is not counted.  nixpkgs is first copied into the
  container's own filesystem (/tmp/np-bench) so a bind mount is not what is measured.
* mlnix runs on the host, from the host checkout, exactly as scripts/bench.py does.
* Runs alternate (nix, mlnix, mlnix, nix, ...) and the result hashes are compared:
  a faster answer that differs is not a comparison.
* --ref adds more reference evaluators (a path to a `nix-instantiate` inside the container),
  e.g. --ref "Lix 2.91.3=/nix/store/...-lix-2.91.3/bin/nix-instantiate".
* Peak RSS of reference Nix comes from one extra, untimed run that polls
  /proc/<pid>/status; its CPU time from NIX_SHOW_STATS in that same run.
"""
import argparse, os, statistics, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bench import ROOT, run_once  # noqa: E402

NP = "/tmp/np-bench"
WORKLOADS = {
    "nixos-toplevel": {
        "mlnix": ["instantiate", "--readonly-mode", "--eval", "--strict", "test/nixos-toplevel.nix", "--arg", "nixpkgs", "./.cache/nixpkgs"],
        "nix": f"--eval --strict /work/test/nixos-toplevel.nix --arg nixpkgs {NP}",
    },
    "nixpkgs-73": {
        "mlnix": ["instantiate", "--readonly-mode", "--eval", "--strict", "--json", "test/nixpkgs-drvs.nix", "--argstr", "system", "x86_64-linux"],
        "nix": f"--eval --strict --json /work/test/nixpkgs-drvs.nix --arg nixpkgs {NP} --argstr system x86_64-linux",
    },
}


def docker(script, env=""):
    r = subprocess.run(["docker", "exec", "nixref", "bash", "-c", f"{env} {script}"], capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(f"container command failed: {r.stderr[:500]}")
    return r.stdout.strip()


def nix_once(args, env="", binary="nix-instantiate"):
    out = docker(
        f"cd /work; s=$(date +%s%N); {binary} --readonly-mode {args} >/tmp/nix.out 2>/tmp/nix.err; rc=$?; e=$(date +%s%N); "
        f'echo "$(( (e-s)/1000000 )) $rc $(sha256sum /tmp/nix.out | cut -c1-12)"',
        env,
    )
    ms, rc, h = out.split()
    return int(ms) / 1000.0, int(rc), h


def nix_rss_and_cpu(args, binary="nix-instantiate"):
    out = docker(
        r"""cd /work
        j() { grep -o "\"$1\": *[0-9.e+-]*" /tmp/nixstats.json | head -1 | cut -d: -f2 | tr -d ' '; }
        NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/nixstats.json """ + binary + r""" --readonly-mode """ + args + r""" >/dev/null 2>&1 &
        pid=$!; hwm=0
        while kill -0 $pid 2>/dev/null; do v=$(grep VmHWM /proc/$pid/status 2>/dev/null | tr -dc 0-9); [ -n "$v" ] && hwm=$v; sleep 0.02; done
        wait $pid
        echo "$hwm $(j cpuTime) $(j nrThunks) $(j heapSize)" """
    )
    hwm, cpu, thunks, heap = out.split()
    return int(hwm) / 1024.0, float(cpu), int(thunks), int(heap) / 1e6


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", type=int, default=5)
    ap.add_argument("--mlnix", default=os.path.join(ROOT, "build", "bin", "mlnix"))
    ap.add_argument("--no-copy", action="store_true")
    ap.add_argument("--ref", action="append", default=[], help="extra reference evaluator NAME=/path/to/nix-instantiate (inside the container)")
    ap.add_argument("--gc-heap", default="", help="also time reference Nix with GC_INITIAL_HEAP_SIZE=<size> (e.g. 4g)")
    a = ap.parse_args()
    if not a.no_copy:
        docker(f"[ -d {NP} ] || cp -a /work/.cache/nixpkgs {NP}")
    print(docker("nix --version; uname -m; nproc") .replace("\n", " | "))
    # reference Nix's own start-up floor
    floor = [nix_once("--eval -E 1")[0] for _ in range(5)]
    print(f"reference Nix start-up (--eval -E 1): median {statistics.median(floor)*1000:.0f} ms\n")
    refs = [("Nix 2.35.4", "nix-instantiate")] + [tuple(r.split("=", 1)) for r in a.ref]
    rc = 0
    for name, w in WORKLOADS.items():
        times = {n: [] for n, _ in refs}
        times["mlnix"] = []
        hashes = {n: set() for n in times}
        gt, mrss = [], 0.0
        who_all = [n for n, _ in refs] + ["mlnix"]
        for i in range(a.runs):
            rot = who_all[i % len(who_all):] + who_all[:i % len(who_all)]
            for who in rot:
                if who == "mlnix":
                    t, r, code, h = run_once(a.mlnix, w["mlnix"])
                    times[who].append(t); hashes[who].add(h); mrss = max(mrss, r)
                    if code: print(f"{name}: mlnix failed rc={code}"); rc = 1
                else:
                    binary = dict(refs)[who]
                    t, code, h = nix_once(w["nix"], binary=binary)
                    times[who].append(t); hashes[who].add(h)
                    if code: print(f"{name}: {who} failed rc={code}"); rc = 1
                    if a.gc_heap and who == refs[0][0]:
                        gt.append(nix_once(w["nix"], f"GC_INITIAL_HEAP_SIZE={a.gc_heap}", binary)[0])
        same = len({frozenset(v) for v in hashes.values()}) == 1 and len(hashes["mlnix"]) == 1
        print(f"== {name}  ({a.runs} interleaved runs each; identical output from all: {'yes' if same else 'NO ' + str(hashes)})")
        base = statistics.median(times[refs[0][0]])
        for n, binary in refs:
            try:
                rss, cpu, thunks, heap = nix_rss_and_cpu(w["nix"], binary)
                extra = f"peak RSS {rss:5.0f} MB   cpu {cpu:.2f}s   thunks {thunks/1e6:.1f}M"
            except Exception:
                extra = "(no stats)"
            print(f"   {n:<14s} min {min(times[n]):5.2f}s  median {statistics.median(times[n]):5.2f}s   {extra}")
        if gt:
            print(f"   {refs[0][0]} with GC_INITIAL_HEAP_SIZE={a.gc_heap}: min {min(gt):5.2f}s  median {statistics.median(gt):5.2f}s")
        print(f"   {'mlnix':<14s} min {min(times['mlnix']):5.2f}s  median {statistics.median(times['mlnix']):5.2f}s   peak RSS {mrss:5.0f} MB")
        for n, _ in refs:
            print(f"   mlnix / {n:<12s} median x{statistics.median(times['mlnix'])/statistics.median(times[n]):.2f}")
        print()
    return rc


if __name__ == "__main__":
    sys.exit(main())
