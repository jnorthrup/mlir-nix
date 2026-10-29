#!/usr/bin/env python3
"""Interleaved A/B benchmark of two environment settings of the same mlnix binary.

usage: ab.py [--runs N] [--workload NAME]... [--samples PATH] A_ENV B_ENV
  A_ENV / B_ENV are ';'-separated KEY=VAL lists ("-" for none), e.g.
     ab.py MLNIX_PIPELINE=nix-prims "MLNIX_PIPELINE=nix-prims,cse"

Rounds alternate A,B then B,A so neither arm always runs first; reports
the median of wall and CPU (user+sys) time, min wall, the RSS of each run (this child's own, via wait4) and the result hash
(identical hashes = identical answers). Failed evaluations or differing answers abort the comparison with exit status 1.
Optional samples are JSONL written after each child finishes, outside measurement.
They contain only explicit arm overrides; credential-like keys are redacted.
"""
import argparse, contextlib, hashlib, json, os, re, statistics, subprocess, sys, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bench import WORKLOADS, ROOT  # noqa: E402


def parse_env(s):
    return {} if s == "-" else dict(kv.split("=", 1) for kv in s.split(";"))


def run(binary, args, extra):
    env = dict(os.environ)
    env.setdefault("MLNIX_STORE_ROOT", "/tmp/mlnix-np-root")
    env.setdefault("MLNIX_STATE_DIR", "/tmp/mlnix-np-state")
    env.update(extra)
    t0 = time.perf_counter()
    p = subprocess.Popen([binary] + args, cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    assert p.stdout is not None
    out = p.stdout.read()
    p.stdout.close()
    # wait4 returns THIS child's usage.  getrusage(RUSAGE_CHILDREN).ru_maxrss is a running maximum over every child
    # waited for so far, so the second arm of a pair could never print less than the first.
    _, status, ru = os.wait4(p.pid, 0)
    wall = time.perf_counter() - t0
    p.returncode = os.waitstatus_to_exitcode(status)
    cpu = ru.ru_utime + ru.ru_stime
    rss = ru.ru_maxrss * (1 if sys.platform == "darwin" else 1024) / 1e9  # bytes on macOS, KiB on Linux
    return wall, cpu, rss, p.returncode, hashlib.sha256(out).hexdigest()


def sample_environment(extra):
    sensitive = re.compile(r"(?:^|_)(?:TOKEN|SECRET|PASSWORD|PASSWD|CREDENTIALS?|API_KEY|PRIVATE_KEY|ACCESS_KEY)(?:_|$)", re.I)
    return {key: "[redacted]" if sensitive.search(key) else value for key, value in extra.items()}


def write_sample(stream, record):
    if stream is not None:
        stream.write(json.dumps(record, sort_keys=True, allow_nan=False) + "\n")
        stream.flush()


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--mlnix", default=os.path.join(ROOT, "build", "bin", "mlnix"))
    ap.add_argument("--mlnix-b", help="binary for B (default: same as --mlnix)")
    ap.add_argument("--runs", type=int, default=5)
    ap.add_argument("--workload", action="append", choices=list(WORKLOADS))
    ap.add_argument("--samples", help="create a new JSONL file of individual child results (never overwrite)")
    ap.add_argument("a")
    ap.add_argument("b")
    a = ap.parse_args(argv)
    if a.runs < 1:
        ap.error("--runs must be positive")
    with contextlib.ExitStack() as stack:
        samples = None
        if a.samples:
            try:
                samples = stack.enter_context(open(a.samples, "x", encoding="utf-8"))
            except OSError as error:
                ap.error(f"cannot create sample file: {error}")
        return compare(a, samples)


def compare(a, samples):
    envs = {"A": parse_env(a.a), "B": parse_env(a.b)}
    bins = {"A": a.mlnix, "B": a.mlnix_b or a.mlnix}
    sequence = 0
    for name in a.workload or list(WORKLOADS):
        res = {k: ([], [], [], set()) for k in envs}
        golden = None
        for i in range(a.runs):
            for position, k in enumerate(("A", "B") if i % 2 == 0 else ("B", "A"), 1):
                sequence += 1
                record = {"workload": name, "round": i + 1, "arm": k, "position": position,
                          "sequence": sequence, "binary": bins[k], "environment": sample_environment(envs[k])}
                try:
                    w, c, rss, rc, h = run(bins[k], WORKLOADS[name], envs[k])
                except OSError as e:
                    write_sample(samples, {**record, "status": "startup_error", "returncode": None,
                                           "stdout_sha256": None, "wall_seconds": None, "cpu_seconds": None,
                                           "peak_rss_gb": None, "error": str(e)})
                    print(f"{name}: {k} FAILED: {e}", file=sys.stderr)
                    return 1
                write_sample(samples, {**record, "status": "completed", "returncode": rc,
                                       "stdout_sha256": h, "wall_seconds": w, "cpu_seconds": c,
                                       "peak_rss_gb": rss})
                if rc:
                    print(f"{name}: {k} FAILED rc={rc}; no performance comparison", file=sys.stderr)
                    return 1
                if golden is None:
                    golden = h
                elif h != golden:
                    print(f"{name}: {k} output mismatch in round {i + 1}: {h} != {golden}; no performance comparison",
                          file=sys.stderr)
                    return 1
                res[k][0].append(w); res[k][1].append(c); res[k][2].append(rss); res[k][3].add(h)
        print(f"== {name}  ({a.runs} interleaved runs each; identical output from all: yes)")
        for k in envs:
            w, c, rss, h = res[k]
            print(f"  {k} {os.path.relpath(bins[k], os.path.expanduser('~/work'))[:34]:34s} wall med {statistics.median(w):6.3f}s min {min(w):6.3f}s   cpu med {statistics.median(c):6.3f}s   rss med {statistics.median(rss):5.3f}GB max {max(rss):5.3f}GB   hash {','.join(x[:12] for x in sorted(h))}")
        dw = statistics.median(res['B'][0]) / statistics.median(res['A'][0]) - 1
        dc = statistics.median(res['B'][1]) / statistics.median(res['A'][1]) - 1
        dr = statistics.median(res['B'][2]) / statistics.median(res['A'][2]) - 1
        print(f"  B vs A: wall {dw:+.1%}   cpu {dc:+.1%}   rss {dr:+.1%}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
