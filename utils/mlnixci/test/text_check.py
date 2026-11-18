#!/usr/bin/env python3
"""text.mlir's texts (built as a shared object) against what the builder wrote before them: a JSON string's inside as
ob_esc escaped it (" \\ \\n \\r \\t as two bytes, the other bytes below 32 as \\u00XX in lower-case hex) and a number as
printf's %ld writes it.
    python3 test/text_check.py BUILD/text.so      exit 0 when every text agrees"""
import ctypes
import random
import sys


class MemRef1(ctypes.Structure):  # memref<?xi8>, as the LLVM lowering lays a ranked memref out
    _fields_ = [("allocated", ctypes.c_void_p), ("aligned", ctypes.c_void_p),
                ("offset", ctypes.c_int64), ("size", ctypes.c_int64), ("stride", ctypes.c_int64)]


def view(buf, size):
    p = ctypes.cast(buf, ctypes.c_void_p)
    return MemRef1(p, p, 0, size, 1)


def escaped(xs):
    out = bytearray()
    for x in xs:
        if x in b'"\\\n\r\t':
            out += b"\\" + {34: b'"', 92: b"\\", 10: b"n", 13: b"r", 9: b"t"}[x]
        elif x < 32:
            out += b"\\u00%02x" % x
        else:
            out.append(x)
    return bytes(out)


def main():
    lib = ctypes.CDLL(sys.argv[1])
    esc, dec = lib._mlir_ciface_json_escape, lib._mlir_ciface_decimal
    esc.restype = dec.restype = ctypes.c_int64
    dec.argtypes = [ctypes.c_int64, ctypes.POINTER(MemRef1)]

    def run_esc(xs):
        src = (ctypes.c_char * max(len(xs), 1)).from_buffer_copy(xs or b"\0")
        dst = (ctypes.c_char * max(6 * len(xs), 1))()
        a, b = view(src, len(xs)), view(dst, 6 * len(xs))
        n = esc(ctypes.byref(a), ctypes.byref(b))
        return dst.raw[:n]

    def run_dec(v):
        dst = (ctypes.c_char * 24)()
        n = dec(v, ctypes.byref(view(dst, 24)))
        return dst.raw[:n]

    rnd = random.Random(20261118)
    special = b'"\\\n\r\t\x00\x01\x1f\x7f\x80\xff /u'
    texts = [b"", bytes(range(256))] + [bytes([b]) for b in range(256)]
    for _ in range(2000):
        n = rnd.randrange(65)
        texts.append(bytes(rnd.choice(special) if rnd.random() < 0.3 else rnd.randrange(256) for _ in range(n)))
    texts.append(bytes(rnd.randrange(256) for _ in range(100000)))
    bad = [t for t in texts if run_esc(t) != escaped(t)]
    numbers = [0, 1, -1, 9, -9, 10, -10, 2**63 - 1, -2**63, -2**63 + 1]
    for k in range(19):
        numbers += [10**k, -10**k, 10**k - 1, -(10**k - 1), 10**k + 1]
    for _ in range(10000):
        numbers.append(rnd.randrange(-2**63, 2**63) >> rnd.randrange(64))
    wrong = [v for v in numbers if run_dec(v) != b"%d" % v]
    print(f"json_escape: {len(texts) - len(bad)} of {len(texts)} texts as ob_esc wrote them; "
          f"decimal: {len(numbers) - len(wrong)} of {len(numbers)} numbers as %ld writes them")
    for t in bad[:3]:
        print("  escape differs:", t[:40], run_esc(t)[:80], escaped(t)[:80])
    for v in wrong[:3]:
        print("  decimal differs:", v, run_dec(v), b"%d" % v)
    sys.exit(1 if bad or wrong else 0)


if __name__ == "__main__":
    main()
