#!/usr/bin/env python3
"""Run a command under a kill timer and (Linux) a memory cap; on either breach, keep the state of the process, then kill it.

The rule: a run (a test, a benchmark, a mutant) may take 20% more than the best that run has done, its alpha, and no more.  Past that
it is stopped where it is (SIGSTOP), what it was doing is kept, and it is killed: on Linux a core file (gcore, the newest per tag) and
the backtrace of every thread (gdb), both through sudo because the YAMA ptrace scope lets no process but an ancestor trace another; on
macOS the call tree of two seconds of /usr/bin/sample.  A memory cap is the same rule for memory: on Linux the command runs in a cgroup
of its own whose memory.high is the cap, so a process that reaches it is throttled, not killed, and its state is taken there;
memory.max, a quarter higher, is the backstop; memory.peak is the peak of the run.  macOS has no cgroups: a cap is ignored there.

The wait blocks on the exit itself (a pidfd on Linux, a kqueue on macOS) and on the cgroup's memory.events, so the wall time of a run
is as exact as a plain wait4.  The cgroup is /sys/fs/cgroup/mlnix, made once with sudo and given to the user (cgroup v2 delegation):
this process moves itself into mlnix/driver, so that it may move each command into a sibling mlnix/run-*.

usage: runcap.py [--deadline S | --alpha S [--over 0.2]] [--mem MB] [--diag DIR] [--tag NAME] [--stdout FILE] -- COMMAND ...
Prints one JSON line (rc, wall, at: when the breach was, peak and maxrss in bytes, verdict: ok | exit N | timeout | memory, diag: the
files kept).  Exit status: the command's, 124 after a timeout, 137 at the memory cap.
"""
import argparse, getpass, glob, itertools, json, os, select, signal, subprocess, sys, time

OVER = 0.2
LINUX = sys.platform.startswith("linux")
CG = "/sys/fs/cgroup/mlnix"
_seq = itertools.count()


def deadline(alpha, over=OVER):
    return alpha * (1 + over)


def _write(path, text):
    with open(path, "w") as f:
        f.write(text)


def _events(cg):
    """memory.events of a cgroup: high, max, oom, oom_kill, ..."""
    return {k: int(v) for k, v in (ln.split() for ln in open(cg + "/memory.events").read().splitlines() if ln.strip())}


def _signal(pgid, sig):
    """Signal a process group; one that has exited (a zombie: EPERM on macOS) or is gone is no error."""
    try:
        os.killpg(pgid, sig)
    except (PermissionError, ProcessLookupError):
        pass


def _driver():
    """Put this process in CG/driver (making CG on first use); False where that cannot be done."""
    if open("/proc/self/cgroup").read().strip().endswith("::/mlnix/driver"):
        return True
    me = getpass.getuser()
    make = f"[ -d {CG}/driver ] || {{ mkdir -p {CG}/driver && chown -R {me}:{me} {CG} && echo '+memory +pids' > {CG}/cgroup.subtree_control; }}"
    return subprocess.run(["sudo", "-n", "sh", "-c", f"{make} && echo {os.getpid()} > {CG}/driver/cgroup.procs"]).returncode == 0


def _wait(pid, timeout, cg):
    """Block until the child exits (True), the timeout passes, or its cgroup's memory events change."""
    if LINUX:
        fd = os.pidfd_open(pid)
        ev = open(cg + "/memory.events") if cg else None
        try:
            pl = select.poll()
            pl.register(fd, select.POLLIN)
            if ev:
                ev.read()
                pl.register(ev.fileno(), select.POLLPRI | select.POLLERR)
            return any(f == fd for f, _ in pl.poll(None if timeout is None else max(0, int(timeout * 1000))))
        finally:
            os.close(fd)
            if ev:
                ev.close()
    kq = select.kqueue()
    try:
        ke = select.kevent(pid, filter=select.KQ_FILTER_PROC, flags=select.KQ_EV_ADD | select.KQ_EV_ONESHOT, fflags=select.KQ_NOTE_EXIT)
        return bool(kq.control([ke], 1, timeout))
    except ProcessLookupError:
        return True
    finally:
        kq.close()


def _group(pgid):
    """The processes of a process group, the evaluator's first."""
    if LINUX:
        pids = []
        for d in os.listdir("/proc"):
            try:
                if d.isdigit() and int(open(f"/proc/{d}/stat").read().rsplit(")", 1)[1].split()[2]) == pgid:
                    pids.append(int(d))
            except OSError:
                pass
    else:
        pids = [int(x) for x in subprocess.run(["pgrep", "-g", str(pgid)], capture_output=True, text=True).stdout.split()]

    def name(p):
        try:
            if LINUX:
                return open(f"/proc/{p}/comm").read().strip()
            return subprocess.run(["ps", "-o", "comm=", "-p", str(p)], capture_output=True, text=True).stdout or ""
        except OSError:
            return ""
    return sorted(pids, key=lambda p: ("mlnix" not in name(p), p))


def take_state(pgid, diag, tag):
    """Keep what the processes of the group are doing; the paths of what was kept.  One core per tag: the newest."""
    os.makedirs(diag, exist_ok=True)
    kept = []
    for old in glob.glob(os.path.join(diag, f"{tag}-*.core.*")):
        os.remove(old)
    for pid in _group(pgid)[:2]:
        base = os.path.join(diag, f"{tag}-{pid}")
        if LINUX:
            with open(base + ".bt.txt", "w") as f:
                subprocess.run(["sudo", "-n", "gdb", "-batch", "-p", str(pid), "-ex", "thread apply all bt"], stdout=f, stderr=subprocess.STDOUT)
            subprocess.run(["sudo", "-n", "gcore", "-o", base + ".core", str(pid)], capture_output=True)
            subprocess.run(["sudo", "-n", "chown", getpass.getuser(), f"{base}.core.{pid}"], capture_output=True)
            kept += [base + ".bt.txt", f"{base}.core.{pid}"]
        else:
            subprocess.run(["/usr/bin/sample", str(pid), "2", "-file", base + ".sample.txt"], capture_output=True)
            kept.append(base + ".sample.txt")
    return [k for k in kept if os.path.exists(k)]


def run(cmd, env=None, cwd=None, deadline=None, mem=None, diag="/tmp/runcap", tag="run", stdout=None):
    """Run cmd; return dict(rc, wall, at, peak, maxrss, verdict, diag).  deadline in seconds, mem in bytes (Linux only)."""
    cg = None
    if LINUX and mem and _driver():
        cg = f"{CG}/run-{os.getpid()}-{next(_seq)}"
        os.mkdir(cg)
        _write(cg + "/memory.high", str(mem))
        _write(cg + "/memory.max", str(mem + mem // 4))
        _write(cg + "/memory.swap.max", "0")

    def pre():
        os.setsid()  # a group of its own: a kill takes every process the command made
        if cg:
            _write(cg + "/cgroup.procs", "0")

    out = open(stdout, "wb") if stdout else None
    t0 = time.perf_counter()
    p = subprocess.Popen(cmd, env=env, cwd=cwd, stdout=out or subprocess.DEVNULL, stderr=subprocess.DEVNULL, preexec_fn=pre)
    verdict, kept, at = None, [], None
    while True:
        over_mem = cg is not None and _events(cg).get("high", 0) > 0
        if not over_mem:
            left = None if deadline is None else deadline - (time.perf_counter() - t0)
            if _wait(p.pid, left, cg):
                break
        over_time = deadline is not None and time.perf_counter() - t0 >= deadline
        over_mem = over_mem or (cg is not None and _events(cg).get("high", 0) > 0)
        if over_time or over_mem:
            at = round(time.perf_counter() - t0, 3)
            verdict = "timeout" if over_time else "memory"
            _signal(p.pid, signal.SIGSTOP)  # frozen at the breach: the state kept is the state there
            kept = take_state(p.pid, diag, tag)
            _signal(p.pid, signal.SIGKILL)
            break
    _, status, ru = os.wait4(p.pid, 0)
    wall = time.perf_counter() - t0
    p.returncode = rc = os.waitstatus_to_exitcode(status)
    if out:
        out.close()
    maxrss = ru.ru_maxrss * (1024 if LINUX else 1)
    peak = maxrss
    if cg:
        peak = int(open(cg + "/memory.peak").read())
        if not verdict and _events(cg).get("oom_kill", 0):
            verdict = "memory"
        for _ in range(100):
            try:
                os.rmdir(cg)
                break
            except OSError:
                time.sleep(0.01)
    return {"rc": rc, "wall": wall, "at": at, "peak": peak, "maxrss": maxrss,
            "verdict": verdict or ("ok" if rc == 0 else f"exit {rc}"), "diag": kept}


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--deadline", type=float)
    ap.add_argument("--alpha", type=float, help="the record of this run, in seconds: the deadline is alpha * (1 + over)")
    ap.add_argument("--over", type=float, default=OVER)
    ap.add_argument("--mem", type=float, help="memory cap in MB (Linux)")
    ap.add_argument("--diag", default="/tmp/runcap")
    ap.add_argument("--tag", default="run")
    ap.add_argument("--stdout")
    ap.add_argument("cmd", nargs=argparse.REMAINDER)
    a = ap.parse_args()
    cmd = a.cmd[1:] if a.cmd[:1] == ["--"] else a.cmd
    d = a.deadline if a.deadline else deadline(a.alpha, a.over) if a.alpha else None
    r = run(cmd, deadline=d, mem=int(a.mem * 2**20) if a.mem else None, diag=a.diag, tag=a.tag, stdout=a.stdout)
    print(json.dumps(dict(r, wall=round(r["wall"], 3))))
    sys.exit(124 if r["verdict"] == "timeout" else 137 if r["verdict"] == "memory" else r["rc"])


if __name__ == "__main__":
    main()
