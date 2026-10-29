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
* --reuse-refs never invokes a reference (including version, startup and RSS probes). It requires
  accepted records from the same host and reference labels, pins compatible output hashes, and
  reports a clear failure when that cache is unavailable rather than timing a reference again.
* --budget SECONDS caps the wall clock of each workload: a round that would not fit is not
  started, and the peak-RSS run of a reference is skipped if it would not fit.  The rounds
  actually run are printed.
* Peak RSS of a reference comes from one extra, untimed run that polls /proc/<pid>/status; its
  CPU time and thunk count from NIX_SHOW_STATS in that same run.
"""
import argparse, hashlib, math, os, platform, re, shlex, statistics, subprocess, sys, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bench import ROOT, run_once  # noqa: E402
import benchref  # noqa: E402

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


def host(script):
    """Run a shell command where the reference evaluators live: the container, or here (--native)."""
    cmd = ["bash", "-c", script] if NATIVE else ["docker", "exec", "nixref", "bash", "-c", script]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(f"{'command' if NATIVE else 'container command'} failed: {r.stderr[:500]}")
    return r.stdout.strip()


def nix_once(args, work, env="", binary="nix-instantiate"):
    # Environment assignments belong to the evaluator, not the preceding cd.
    command = " ".join(shlex.quote(x) for x in ["env", *shlex.split(env), binary])
    out = host(
        f"cd {shlex.quote(work)} || exit 1; "
        "tmp=$(mktemp -d) || exit 1; trap 'rm -rf \"$tmp\"' EXIT; "
        f"s=$(date +%s%N); {command} --readonly-mode {args} >\"$tmp/out\" 2>\"$tmp/err\"; rc=$?; e=$(date +%s%N); "
        'echo "$(( (e-s)/1000000 )) $rc $(sha256sum "$tmp/out" | cut -c1-12)"',
    )
    ms, rc, h = out.split()
    return int(ms) / 1000.0, int(rc), h


def nix_rss_and_cpu(args, work, binary="nix-instantiate"):
    out = host(
        f"cd {shlex.quote(work)} || exit 1\n" + r"""
        tmp=$(mktemp -d) || exit 1
        trap 'rm -rf "$tmp"' EXIT
        j() { grep -o "\"$1\": *[0-9.e+-]*" "$tmp/stats.json" | head -1 | cut -d: -f2 | tr -d ' '; }
        NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH="$tmp/stats.json" """ + shlex.quote(binary) + r""" --readonly-mode """ + args + r""" >/dev/null 2>&1 &
        pid=$!; hwm=0
        while kill -0 $pid 2>/dev/null; do v=$(grep VmHWM /proc/$pid/status 2>/dev/null | tr -dc 0-9); [ -n "$v" ] && hwm=$v; sleep 0.02; done
        wait $pid || exit $?
        echo "$hwm $(j cpuTime) $(j nrThunks) $(j heapSize)" """
    )
    hwm, cpu, thunks, heap = out.split()
    return int(hwm) / 1024.0, float(cpu), int(thunks), int(heap) / 1e6


class ReusedReferences(benchref.Store):
    """Pins only from accepted, compatible output records; never run a reference."""

    def generations(self, workload):
        accepted = []
        for gen, tools, golden in super().generations(workload):
            if not golden:
                continue
            with open(os.path.join(self.d, gen, workload + ".txt")) as stream:
                raw = stream.read()
            # Older harnesses printed accepted-looking tables even after failure.
            if re.search(r"failed rc=|no performance comparison|identical output from all: NO", raw):
                continue
            tools = {name: row for name, row in tools.items()
                     if all(math.isfinite(x) and x > 0 for x in row[:3])}
            accepted.append((gen, tools, golden))
        # Do not mix versions of the workload with different recorded answers.
        golden = accepted[-1][2] if accepted else None
        return [row for row in accepted if row[2] == golden]


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
    ap.add_argument("--auto-pin", action="store_true", help="do not time a competitor scripts/benchref.py pins; print its pin")
    ap.add_argument("--reuse-refs", action="store_true", help="use accepted same-host reference records only; never invoke reference binaries")
    ap.add_argument("--cap", action="store_true", help="stop an mlnix run past (1 + over) times its record, in time and (Linux) memory")
    ap.add_argument("--over", type=float, default=0.2)
    ap.add_argument("--records", default=os.path.join(ROOT, "docs", "bench", "kali"), help="the stored generations: pins and records")
    ap.add_argument("--diag", default="/tmp/vs-nix-diag", help="where the state of a stopped run is kept (scripts/runcap.py)")
    a = ap.parse_args()
    if a.runs <= 0:
        ap.error("--runs must be positive")
    if a.reuse_refs and a.gc_heap:
        ap.error("--gc-heap requires reference execution and cannot be used with --reuse-refs")
    # MLNIX_DEFER is a presence flag, so even "0" means demand. Control the
    # schedules here instead of silently timing demand twice if inherited.
    os.environ.pop("MLNIX_DEFER", None)
    NATIVE = a.native
    work = ROOT if NATIVE else "/work"
    np = os.path.join(ROOT, ".cache", "nixpkgs") if NATIVE else NP
    refs = ([] if NATIVE else [("Nix 2.35.4", "nix-instantiate")]) + [tuple(r.split("=", 1)) for r in a.ref]
    if not refs:
        sys.exit("--native needs at least one --ref NAME=/path/to/nix-instantiate")
    arms = [("mlnix", {})] + ([("mlnix demand", {"MLNIX_DEFER": "1"})] if a.demand else [])
    if not NATIVE and not a.no_copy and not a.reuse_refs:
        host(f"[ -d {NP} ] || cp -a /work/.cache/nixpkgs {NP}")
    mline = machine()
    print(mline)
    store = (ReusedReferences if a.reuse_refs else benchref.Store)(mline, a.records) if a.reuse_refs or a.auto_pin or a.cap else None
    reused = {}
    if a.reuse_refs:
        try:
            for name in a.workload or list(workloads(work, np)):
                pins = {n: store.pin(name, n) for n, _ in refs}
                golden = store.golden(name)
                if not golden or any(pin is None for pin in pins.values()):
                    raise ValueError(f"{name}: need at least two accepted same-host records for each reference and a compatible output hash")
                reused[name] = (pins, golden)
        except (OSError, ValueError, IndexError) as error:
            print(f"cached references unavailable: {error}; reference evaluators will not be run")
            return 1
    for n, binary in refs:
        if a.reuse_refs:
            print(f"  {n}: cached same-host measurements; reference binary not invoked")
        else:
            print(f"  {n}: {host(shlex.quote(binary) + ' --version').splitlines()[0]}")
    # A failed/incorrect startup is not a startup floor. Validate against the
    # literal's known output, so equal crashes cannot establish an oracle.
    startup_hash = hashlib.sha256(b"1\n").hexdigest()[:12]
    floors = {}
    for n, b in ([] if a.reuse_refs else refs):
        samples = []
        for _ in range(5):
            t, code, h = nix_once("--eval -E 1", work, binary=b)
            if code or h != startup_hash:
                print(f"start-up: {n} rejected rc={code}, output={h}; no performance comparison")
                return 1
            samples.append(t)
        floors[n] = statistics.median(samples)
    for n, extra in arms:
        samples = []
        for _ in range(5):
            t, _, code, h = run_once(a.mlnix, ["instantiate", "--eval", "-E", "1"], extra)
            if code or h != startup_hash:
                print(f"start-up: {n} rejected rc={code}, output={h}; no performance comparison")
                return 1
            samples.append(t)
        floors[n] = statistics.median(samples)
    print("start-up (--eval -E 1), median of 5: " + ", ".join(f"{n} {t*1000:.0f} ms" for n, t in floors.items()) + "\n")
    for name, w in workloads(work, np).items():
        if a.workload and name not in a.workload:
            continue
        # escaped competitors are not timed again: their pin stands in; each mlnix arm may take (1 + over) times its record
        pinned = reused[name][0] if a.reuse_refs else {n: store.pin(name, n) for n, _ in refs if store and a.auto_pin and store.escaped(name, n)}
        timed = [(n, b) for n, b in refs if n not in pinned]
        caps = {}
        for n, _ in (arms if store and a.cap else []):
            rec = [t[n] for _, t, _ in store.generations(name) if n in t and t[n][3]]
            if rec:
                linux = NATIVE and sys.platform.startswith("linux")
                caps[n] = dict(deadline=min(r[0] for r in rec) * (1 + a.over), diag=a.diag, tag=f"{name}-{n.replace(' ', '-')}",
                               mem=int(min(r[2] for r in rec) * (1 + a.over) * 2**20) if linux else None)
        who_all = [n for n, _ in timed] + [n for n, _ in arms]
        times = {n: [] for n in who_all}
        golden = reused[name][1] if a.reuse_refs else store.golden(name) if pinned else None
        if pinned and golden is None:
            print(f"{name}: pinned references have no output oracle; no performance comparison")
            return 1
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
                    t, r, code, h = run_once(a.mlnix, w["mlnix"], dict(arms)[who], cap=caps.get(who))
                    peak[who] = max(peak[who], r)
                else:
                    t, code, h = nix_once(w["nix"], work, binary=dict(refs)[who])
                if code:
                    print(f"{name}: {who} failed rc={code}; no performance comparison")
                    return 1
                if golden is None:
                    golden = h
                elif h != golden:
                    print(f"{name}: {who} output mismatch in round {i + 1}: {h} != {golden}; no performance comparison")
                    return 1
                times[who].append(t)
                if a.gc_heap and who == refs[0][0] and who not in dict(arms):
                    t_gc, code_gc, h_gc = nix_once(w["nix"], work, f"GC_INITIAL_HEAP_SIZE={a.gc_heap}", dict(refs)[who])
                    if code_gc or h_gc != golden:
                        print(f"{name}: {who} GC heap arm rejected rc={code_gc}, output={h_gc}; no performance comparison")
                        return 1
                    gt.append(t_gc)
            round_cost = max(round_cost, time.monotonic() - r0)
            rounds += 1
            if rounds == 1:  # the peak-RSS runs of the references cost about one run each
                reserve = 1.3 * sum(times[n][0] for n, _ in timed)
        # Collect optional stats before printing an accepted table. A failed
        # reference process must not leave behind a table that future pins accept.
        extras = {}
        for n, binary in timed:
            if a.budget and (time.monotonic() - t_start) + 1.3 * times[n][0] > a.budget:
                extras[n] = "(peak RSS skipped: budget)"
                continue
            try:
                rss, cpu, thunks, heap = nix_rss_and_cpu(w["nix"], work, binary)
                extras[n] = f"peak RSS {rss:5.0f} MB   cpu {cpu:.2f}s   thunks {thunks/1e6:.1f}M"
            except SystemExit as error:
                print(f"{name}: {n} stats run failed: {error}; no performance comparison")
                return 1
            except (ValueError, OSError):
                extras[n] = "(no stats)"
        spent = time.monotonic() - t_start
        h = (f"pinned: {', '.join(pinned)}; " if pinned else "") + f"output sha256 {golden}; "
        print(f"== {name}  ({rounds} interleaved rounds, {spent:.0f} s{f' of a {a.budget:.0f} s budget' if a.budget else ''}; {h}"
              "identical output from all: yes)")
        for n, binary in refs:
            if n in pinned:
                p = pinned[n]
                print(f"   {n:<14s} min {p['min']:5.2f}s  median {p['median']:5.2f}s   peak RSS {p['rss']:5.0f} MB   "
                      f"[pinned: {'cached, ' if a.reuse_refs else ''}best of {len(p['gens'])} generations, drift {100 * p['drift']:.1f}%]")
                continue
            print(f"   {n:<14s} min {min(times[n]):5.2f}s  median {statistics.median(times[n]):5.2f}s   {extras[n]}")
        if gt:
            print(f"   {refs[0][0]} with GC_INITIAL_HEAP_SIZE={a.gc_heap}: min {min(gt):5.2f}s  median {statistics.median(gt):5.2f}s")
        for n, _ in arms:
            print(f"   {n:<14s} min {min(times[n]):5.2f}s  median {statistics.median(times[n]):5.2f}s   peak RSS {peak[n]:5.0f} MB")
        for n, _ in arms:
            for r, _ in refs:
                base = pinned[r]["median"] if r in pinned else statistics.median(times[r])
                print(f"   {n} / {r:<12s} median x{statistics.median(times[n]) / base:.2f}")
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
