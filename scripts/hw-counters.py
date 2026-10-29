#!/usr/bin/env python3
"""Linux user-space PMU counters for one command; keep separate from timing runs.

Uses perf_event_open directly when perf is absent. Events may be multiplexed;
report raw counts, enabled/running time, and scaled counts, never invent zeros.
Usage: hw-counters.py -- env MLNIX_DEFER=1 build/bin/mlnix instantiate ...
The command's stdout is discarded; stderr is preserved; JSON goes to stdout.
"""
import argparse
import ctypes
import fcntl
import json
import os
import platform
import signal
import struct
import sys
import time

EVENTS = {"cycles": 0, "instructions": 1, "cache_references": 2,
          "cache_misses": 3, "branches": 4, "branch_misses": 5}


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("command", nargs=argparse.REMAINDER)
    args = ap.parse_args()
    cmd = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not cmd:
        ap.error("a command is required")
    syscall = {"x86_64": 298, "aarch64": 241}.get(platform.machine())
    if sys.platform != "linux" or syscall is None:
        ap.error("perf_event_open currently supports Linux x86_64/aarch64")
    libc = ctypes.CDLL(None, use_errno=True)
    read_end, write_end = os.pipe()
    pid = os.fork()
    if pid == 0:
        os.close(write_end)
        if not os.read(read_end, 1):
            os._exit(125)
        os.close(read_end)
        with open(os.devnull, "wb") as sink:
            os.dup2(sink.fileno(), 1)
        try:
            os.execvpe(cmd[0], cmd, os.environ)
        except OSError as error:
            print(error, file=sys.stderr)
            os._exit(127)
    os.close(read_end)
    descriptors, counters = {}, {}
    try:
        for name, config in EVENTS.items():
            attr = bytearray(128)
            struct.pack_into("IIQ", attr, 0, 0, len(attr), config)
            struct.pack_into("Q", attr, 32, 3)  # TOTAL_TIME_ENABLED | TOTAL_TIME_RUNNING
            # disabled | inherit | exclude_kernel | exclude_hv
            struct.pack_into("Q", attr, 40, (1 << 0) | (1 << 1) | (1 << 5) | (1 << 6))
            buf = ctypes.create_string_buffer(bytes(attr))
            fd = libc.syscall(syscall, buf, pid, -1, -1, 0)
            if fd < 0:
                counters[name] = {"unavailable": os.strerror(ctypes.get_errno())}
            else:
                descriptors[name] = fd
                fcntl.ioctl(fd, 0x2403, 0)  # PERF_EVENT_IOC_RESET
                fcntl.ioctl(fd, 0x2400, 0)  # PERF_EVENT_IOC_ENABLE
        start = time.perf_counter()
        os.write(write_end, b"1")
        os.close(write_end)
        write_end = -1
        _, status, usage = os.wait4(pid, 0)
        pid = -1
        wall = time.perf_counter() - start
        for name, fd in descriptors.items():
            fcntl.ioctl(fd, 0x2401, 0)  # PERF_EVENT_IOC_DISABLE
            raw, enabled, running = struct.unpack("QQQ", os.read(fd, 24))
            counters[name] = {"raw": raw, "enabled_ns": enabled, "running_ns": running}
            if running and raw:
                counters[name]["scaled"] = round(raw * enabled / running)
            else:
                counters[name]["unavailable"] = "zero count or event did not run"
        rc = os.waitstatus_to_exitcode(status)
        print(json.dumps({"command": cmd, "exit_code": rc, "wall_seconds": wall,
                          "cpu_seconds": usage.ru_utime + usage.ru_stime,
                          "peak_rss_mib": usage.ru_maxrss / 1024,
                          "scope": "user-space, inherited threads/children", "events": counters}, indent=2))
        return rc if rc >= 0 else 128 - rc
    finally:
        if write_end != -1:
            os.close(write_end)
        if pid > 0:
            os.kill(pid, signal.SIGKILL)
            os.waitpid(pid, 0)
        for fd in descriptors.values():
            os.close(fd)


if __name__ == "__main__":
    sys.exit(main())
