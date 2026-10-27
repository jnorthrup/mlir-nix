#!/usr/bin/env python3
"""mlnix against reference Nix and Lix, interleaved on the same machine.

usage: vs-nix.py [--runs N] [--budget SECONDS] [--workload NAME]... [--demand] [--mlnix PATH]
                 [--native] [--no-copy] [--gc-heap SIZE] [--ref NAME=PATH ...]

* Default: the reference evaluators run INSIDE the container "nixref" and are timed there
  (date +%s%N), so `docker exec` start-up is not counted.  nixpkgs is first copied into the
  container's own filesystem (/tmp/np-bench) so a bind mount is not what is measured.  The
  container's own nix-instantiate is the first reference, the base of the ratios.
* --native: the reference evaluators run on this machine (Linux: GNU date, /proc).  Each is given
  as --ref NAME=/path/to/nix-instantiate; the first is the base.  nixpkgs is ./.cache/nixpkgs.
* mlnix runs from this checkout, exactly as scripts/bench.py does.  --demand adds a second mlnix
  arm with MLNIX_DEFER=1, the sea-of-nodes schedule (docs/SEA-OF-NODES.md).
* Runs alternate, the first evaluator rotating, and the result hashes are compared: a faster
  answer that differs is not a comparison.
* --budget SECONDS caps the wall clock of each workload: a round that would not fit is not
  started, and the peak-RSS run of a reference is skipped if it would not fit.  The rounds
  actually run are printed.
* Peak RSS of a reference comes from one extra, untimed run that polls /proc/<pid>/status; its
  CPU time and thunk count from NIX_SHOW_STATS in that same run.
"""
import argparse, os, platform, statistics, subprocess, sys, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bench import ROOT, run_once  # noqa: E402

NP = "/tmp/np-bench"  # nixpkgs inside the container
NATIVE = False


def workloads(work, np):
    return {
        "nixos-toplevel": {
            "mlnix": ["instantiate", "--readonly-mode", "--eval", "--strict", "test/nixos-toplevel.nix", "--arg", "nixpkgs", "./.cache/nixpkgs"],
            "nix": f"--eval --strict {work}/test/nixos-toplevel.nix --arg nixpkgs {np}",
        },
        "nixpkgs-73": {
            "mlnix": ["instantiate", "--readonly-mode", "--eval", "--strict", "--json", "test/nixpkgs-drvs.nix", "--argstr", "system", "x86_64-linux"],
            "nix": f"--eval --strict --json {work}/test/nixpkgs-drvs.nix --arg nixpkgs {np} --argstr system x86_64-linux",
        },
    }


def host(script, env=""):
    """Run a shell command where the reference evaluators live: the container, or here (--native)."""
    cmd = ["bash", "-c", f"{env} {script}"] if NATIVE else ["docker", "exec", "nixref", "bash", "-c", f"{env} {script}"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(f"{'command' if NATIVE else 'container command'} failed: {r.stderr[:500]}")
    return r.stdout.strip()


def nix_once(args, work, env="", binary="nix-instantiate"):
    out = host(
        f"cd {work}; s=$(date +%s%N); {binary} --readonly-mode {args} >/tmp/nix.out 2>/tmp/nix.err; rc=$?; e=$(date +%s%N); "
        f'echo "$(( (e-s)/1000000 )) $rc $(sha256sum /tmp/nix.out | cut -c1-12)"',
        env,
    )
    ms, rc, h = out.split()
    return int(ms) / 1000.0, int(rc), h


def nix_rss_and_cpu(args, work, binary="nix-instantiate"):
    out = host(
        f"cd {work}" + r"""
        j() { grep -o "\"$1\": *[0-9.e+-]*" /tmp/nixstats.json | head -1 | cut -d: -f2 | tr -d ' '; }
        NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/nixstats.json """ + binary + r""" --readonly-mode """ + args + r""" >/dev/null 2>&1 &
        pid=$!; hwm=0
        while kill -0 $pid 2>/dev/null; do v=$(grep VmHWM /proc/$pid/status 2>/dev/null | tr -dc 0-9); [ -n "$v" ] && hwm=$v; sleep 0.02; done
        wait $pid
        echo "$hwm $(j cpuTime) $(j nrThunks) $(j heapSize)" """
    )
    hwm, cpu, thunks, heap = out.split()
    return int(hwm) / 1024.0, float(cpu), int(thunks), int(heap) / 1e6


def machine():
    if NATIVE:
        cpu = next((l.split(":", 1)[1].strip() for l in open("/proc/cpuinfo") if l.startswith("model name")), "?")
        return f"{platform.machine()} | {os.cpu_count()} threads | {cpu}"
    return host("uname -m; nproc").replace("\n", " | ")


def main():
    global NATIVE
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", type=int, default=5)
    ap.add_argument("--budget", type=float, default=0, help="wall-clock cap in seconds for each workload (0: none)")
    ap.add_argument("--workload", action="append", default=[], choices=list(workloads("", "")), help="only this workload (repeatable)")
    ap.add_argument("--demand", action="store_true", help="also run mlnix with MLNIX_DEFER=1")
    ap.add_argument("--mlnix", default=os.path.join(ROOT, "build", "bin", "mlnix"))
    ap.add_argument("--native", action="store_true", help="reference evaluators run on this machine, not in the container")
    ap.add_argument("--no-copy", action="store_true")
    ap.add_argument("--ref", action="append", default=[], help="reference evaluator NAME=/path/to/nix-instantiate (inside the container unless --native)")
    ap.add_argument("--gc-heap", default="", help="also time the first reference with GC_INITIAL_HEAP_SIZE=<size> (e.g. 4g)")
    a = ap.parse_args()
    NATIVE = a.native
    work = ROOT if NATIVE else "/work"
    np = os.path.join(ROOT, ".cache", "nixpkgs") if NATIVE else NP
    refs = ([] if NATIVE else [("Nix 2.35.4", "nix-instantiate")]) + [tuple(r.split("=", 1)) for r in a.ref]
    if not refs:
        sys.exit("--native needs at least one --ref NAME=/path/to/nix-instantiate")
    arms = [("mlnix", {})] + ([("mlnix demand", {"MLNIX_DEFER": "1"})] if a.demand else [])
    if not NATIVE and not a.no_copy:
        host(f"[ -d {NP} ] || cp -a /work/.cache/nixpkgs {NP}")
    print(machine())
    for n, binary in refs:
        print(f"  {n}: {host(binary + ' --version').splitlines()[0]}")
    # start-up floors: an empty evaluation
    floors = {n: statistics.median(nix_once("--eval -E 1", work, binary=b)[0] for _ in range(5)) for n, b in refs}
    for n, extra in arms:
        floors[n] = statistics.median(run_once(a.mlnix, ["instantiate", "--eval", "-E", "1"], extra)[0] for _ in range(5))
    print("start-up (--eval -E 1), median of 5: " + ", ".join(f"{n} {t*1000:.0f} ms" for n, t in floors.items()) + "\n")
    rc = 0
    for name, w in workloads(work, np).items():
        if a.workload and name not in a.workload:
            continue
        who_all = [n for n, _ in refs] + [n for n, _ in arms]
        times = {n: [] for n in who_all}
        hashes = {n: set() for n in who_all}
        peak = {n: 0.0 for n, _ in arms}
        gt = []
        t_start, rounds, round_cost, reserve = time.monotonic(), 0, 0.0, 0.0
        for i in range(a.runs):
            if a.budget and rounds and (time.monotonic() - t_start) + 1.15 * round_cost + reserve > a.budget:
                break
            r0 = time.monotonic()
            rot = who_all[i % len(who_all):] + who_all[:i % len(who_all)]
            for who in rot:
                if who in dict(arms):
                    t, r, code, h = run_once(a.mlnix, w["mlnix"], dict(arms)[who])
                    times[who].append(t); hashes[who].add(h); peak[who] = max(peak[who], r)
                    if code: print(f"{name}: {who} failed rc={code}"); rc = 1
                else:
                    t, code, h = nix_once(w["nix"], work, binary=dict(refs)[who])
                    times[who].append(t); hashes[who].add(h)
                    if code: print(f"{name}: {who} failed rc={code}"); rc = 1
                    if a.gc_heap and who == refs[0][0]:
                        gt.append(nix_once(w["nix"], work, f"GC_INITIAL_HEAP_SIZE={a.gc_heap}", dict(refs)[who])[0])
            round_cost = max(round_cost, time.monotonic() - r0)
            rounds += 1
            if rounds == 1:  # the peak-RSS runs of the references cost about one run each
                reserve = 1.3 * sum(times[n][0] for n, _ in refs)
        same = len({frozenset(v) for v in hashes.values()}) == 1 and all(len(v) == 1 for v in hashes.values())
        if not same:
            rc = 1
        spent = time.monotonic() - t_start
        h = f"output sha256 {next(iter(hashes[arms[0][0]]))}; " if same else ""
        print(f"== {name}  ({rounds} interleaved rounds, {spent:.0f} s{f' of a {a.budget:.0f} s budget' if a.budget else ''}; {h}"
              f"identical output from all: {'yes' if same else 'NO ' + str(hashes)})")
        for n, binary in refs:
            if a.budget and (time.monotonic() - t_start) + 1.3 * times[n][0] > a.budget:
                extra = "(peak RSS skipped: budget)"
            else:
                try:
                    rss, cpu, thunks, heap = nix_rss_and_cpu(w["nix"], work, binary)
                    extra = f"peak RSS {rss:5.0f} MB   cpu {cpu:.2f}s   thunks {thunks/1e6:.1f}M"
                except Exception:
                    extra = "(no stats)"
            print(f"   {n:<14s} min {min(times[n]):5.2f}s  median {statistics.median(times[n]):5.2f}s   {extra}")
        if gt:
            print(f"   {refs[0][0]} with GC_INITIAL_HEAP_SIZE={a.gc_heap}: min {min(gt):5.2f}s  median {statistics.median(gt):5.2f}s")
        for n, _ in arms:
            print(f"   {n:<14s} min {min(times[n]):5.2f}s  median {statistics.median(times[n]):5.2f}s   peak RSS {peak[n]:5.0f} MB")
        for n, _ in arms:
            for r, _ in refs:
                print(f"   {n} / {r:<12s} median x{statistics.median(times[n])/statistics.median(times[r]):.2f}")
        print()
    return rc


if __name__ == "__main__":
    sys.exit(main())
