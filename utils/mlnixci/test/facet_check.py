#!/usr/bin/env python3
"""The compiled query (query.mlir, built as a shared object) against the same query counted by hand, on random corpora
and selections.
    python3 test/facet_check.py BUILD/query.so [rounds]      exit 0 when every answer agrees"""
import ctypes
import random
import sys

FACETS = 6


class MemRef1(ctypes.Structure):  # memref<?xi32>, as the LLVM lowering lays a ranked memref out
    _fields_ = [("allocated", ctypes.c_void_p), ("aligned", ctypes.c_void_p),
                ("offset", ctypes.c_int64), ("size", ctypes.c_int64), ("stride", ctypes.c_int64)]


def view(buf, size):
    p = ctypes.cast(buf, ctypes.c_void_p)
    return MemRef1(p, p, 0, size, 1)


def compiled(query, cols, sel, n):
    """the hits and each column's counts, from the compiled query"""
    keep = []
    c, s, o = [], [], []
    for f in range(FACETS):
        cb = (ctypes.c_int32 * max(n, 1))(*cols[f])
        sb = (ctypes.c_int32 * max(len(sel[f]), 1))(*sel[f])
        ob = (ctypes.c_int32 * max(len(sel[f]), 1))()
        keep += [cb, sb, ob]
        c.append(view(cb, n))
        s.append(view(sb, len(sel[f])))
        o.append((ob, view(ob, len(sel[f]))))
    rb = (ctypes.c_int32 * max(n, 1))()
    rows = view(rb, n)
    args = [ctypes.byref(m) for m in c] + [ctypes.byref(m) for m in s] + [ctypes.byref(m) for _, m in o] + [ctypes.byref(rows)]
    total = query(*args)
    return list(rb[:total]), [list(ob[:len(sel[f])]) for f, (ob, _) in enumerate(o)]


def counted(cols, sel, n):
    """the same, counted by hand: a row is a hit when every column selects its code; a column's counts are those of the
    rows every other column selects"""
    rows, counts = [], [[0] * len(sel[f]) for f in range(FACETS)]
    for r in range(n):
        fails, failed = 0, -1
        for f in range(FACETS):
            if not sel[f][cols[f][r]]:
                fails, failed = fails + 1, f
        if fails == 0:
            rows.append(r)
        for f in range(FACETS):
            if fails == 0 or (fails == 1 and failed == f):
                counts[f][cols[f][r]] += 1
    return rows, counts


def main():
    lib = ctypes.CDLL(sys.argv[1])
    query = lib._mlir_ciface_corpus_query
    query.restype = ctypes.c_int64
    query.argtypes = [ctypes.POINTER(MemRef1)] * (3 * FACETS + 1)
    rounds = int(sys.argv[2]) if len(sys.argv) > 2 else 2000
    rng = random.Random(20261116)
    checked = 0
    for rnd in range(rounds):
        n = rng.getrandbits(32) % 300  # includes the empty corpus
        if rnd == rounds - 1:
            n = 22000  # one the size of NixOS's
        cols, sel = [], []
        for f in range(FACETS):
            codes = 1 + rng.getrandbits(32) % (200 if f == 3 else 12)
            cols.append([rng.getrandbits(32) % codes for _ in range(n)])
            s = [1] * codes
            if rng.getrandbits(32) % 2:  # a selection on this column: a few codes on, the rest off
                s = [int(rng.getrandbits(32) % 3 == 0) for _ in range(codes)]
            sel.append(s)
        got = compiled(query, cols, sel, n)
        want = counted(cols, sel, n)
        if got != want:
            print(f"round {rnd} (n={n}): the compiled query differs (hits {len(got[0])}, expected {len(want[0])})",
                  file=sys.stderr)
            return 1
        checked += 1
    print(f"facet-check: {checked} queries, the compiled query agrees with the counted one")
    return 0


if __name__ == "__main__":
    sys.exit(main())
