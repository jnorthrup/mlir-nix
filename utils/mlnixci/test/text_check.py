#!/usr/bin/env python3
"""text.mlir's texts (built as a shared object) against what the builder wrote before them: a JSON string's inside as
ob_esc escaped it (" \\ \\n \\r \\t as two bytes, the other bytes below 32 as \\u00XX in lower-case hex), a number as
printf's %ld writes it, and the query's reply as api.mlir wrote it piece by piece (on random corpora, pages and
selections).  queryMs is printf's %f but rounded half up at the sixth decimal (%f rounds the exact binary value), so
the two differ only for a time whose seventh decimal is within a rounding error of 5: the times here are not.
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


def written_reply(c):
    """the reply as api.mlir's builder calls wrote it (query_run, before text.mlir's query_reply)"""
    def piece(t, tp):
        return t[tp >> 32:(tp >> 32) + (tp & 0xffffffff)]
    names, at = c["names"], c["nameAt"]
    out = b'{"total":%d,"rows":%d,"queryMs":%f,"facets":[' % (c["total"], c["n"], c["ms"])
    start = 0
    for fi in range(6):
        out += (b"," if fi else b"") + b'{"name":"' + names[at[fi]:at[fi + 1]] + b'","values":['
        for k in range(c["ks"][fi]):
            if fi < 4:
                v = piece(c["text"], c["dicts"][fi][k])
            else:
                j = (6 if fi == 4 else 8) + k
                v = names[at[j]:at[j + 1]]
            on = c["picked"][fi] and c["sels"][start + k]
            out += (b"," if k else b"") + b'{"v":"' + v + b'","n":%d' % c["counts"][start + k] + \
                (b',"on":true}' if on else b',"on":false}')
        out += b"]}"
        start += c["ks"][fi]
    out += b'],"hits":['
    for i, r in enumerate(c["page"]):
        sp = c["spans"][c["obj"][r]]
        out += (b"," if i else b"") + b'{"row":' + c["text"][sp >> 32:(sp & 0xffffffff) + 1]
        if c["whatif"][r]:
            out += b',"changed":true,"base":'
            b = c["baseOf"][r]
            if b < 0:
                out += b"null"
            else:
                vb = c["bval"][b]
                out += b'{"value":' + (b'null,"valueShown":false' if vb == -1 else piece(c["btext"], vb) + b',"valueShown":true')
                out += b',"state":"' + piece(c["btext"], c["bst"][b]) + b'"}'
        out += b"}"
    return out + b"]}"


def random_corpus(rnd):
    """a corpus, its base, a page and a selection, as query_run hands them to query_reply"""
    names = b"sectionkindstatemodulewhatifmatchsamechangednoyes"
    at = [0, 7, 11, 16, 22, 28, 33, 37, 44, 46, 49]
    text = bytes(rnd.choice(b'abc{}[]":,0123456789 \\') for _ in range(rnd.randrange(1, 400))) + b"?(none)"
    btext = bytes(rnd.choice(b'xyz"0123456789') for _ in range(rnd.randrange(1, 300))) + b"?(none)"
    def tp(t):
        s = rnd.randrange(len(t)); return s << 32 | rnd.randrange(len(t) - s + 1)
    n, bn = rnd.randrange(1, 40), rnd.randrange(1, 40)
    spans = []
    for _ in range(rnd.randrange(1, 60)):
        o = rnd.randrange(len(text)); spans.append(o << 32 | rnd.randrange(o, len(text)))
    ks = [rnd.randrange(1, 9) for _ in range(4)] + [2, 2]
    kt = sum(ks)
    return dict(text=text, btext=btext, names=names, nameAt=at, n=n, total=rnd.randrange(0, n + 1),
                ms=rnd.choice([0.0, rnd.random(), rnd.random() * 1000, 0.25e-6, 0.75e-6, 12.0]),
                spans=spans, obj=[rnd.randrange(len(spans)) for _ in range(n)],
                whatif=[rnd.randrange(2) for _ in range(n)], baseOf=[rnd.randrange(-1, bn) for _ in range(n)],
                bval=[-1 if rnd.random() < 0.3 else tp(btext) for _ in range(bn)], bst=[tp(btext) for _ in range(bn)],
                page=[rnd.randrange(n) for _ in range(rnd.randrange(0, 20))], ks=ks,
                picked=[rnd.randrange(2) for _ in range(6)], counts=[rnd.randrange(0, 10**rnd.randrange(1, 10)) for _ in range(kt)],
                sels=[rnd.randrange(2) for _ in range(kt)], dicts=[[tp(text) for _ in range(ks[f])] for f in range(4)])


def made_reply(fn, c):
    """the reply from text.mlir's query_reply"""
    keep = []
    def arr(ctype, xs):
        b = (ctype * max(len(xs), 1))(*xs); keep.append(b); return ctypes.byref(view(b, len(xs)))
    def txt(t):
        b = (ctypes.c_char * len(t)).from_buffer_copy(t); keep.append(b); return ctypes.byref(view(b, len(t)))
    i64, i32 = ctypes.c_int64, ctypes.c_int32
    res = MemRef1()
    fn(ctypes.byref(res), txt(c["text"]), arr(i64, c["spans"]), arr(i64, c["obj"]), arr(i32, c["whatif"]),
       arr(i32, c["baseOf"]), txt(c["btext"]), arr(i64, c["bval"]), arr(i64, c["bst"]), arr(i32, c["page"]),
       arr(i64, c["ks"]), arr(i64, c["picked"]), arr(i32, c["counts"]), arr(i32, c["sels"]),
       *[arr(i64, d) for d in c["dicts"]], txt(c["names"]), arr(i64, c["nameAt"]),
       ctypes.c_int64(c["total"]), ctypes.c_int64(c["n"]), ctypes.c_double(c["ms"]))
    out = ctypes.string_at(res.aligned + res.offset, res.size)
    ctypes.CDLL(None).free(ctypes.c_void_p(res.allocated))
    return out


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
    replies = [random_corpus(rnd) for _ in range(500)]
    off = [c for c in replies if made_reply(lib._mlir_ciface_query_reply, c) != written_reply(c)]
    print(f"json_escape: {len(texts) - len(bad)} of {len(texts)} texts as ob_esc wrote them; "
          f"decimal: {len(numbers) - len(wrong)} of {len(numbers)} numbers as %ld writes them; "
          f"query_reply: {len(replies) - len(off)} of {len(replies)} replies as the builder wrote them")
    for t in bad[:3]:
        print("  escape differs:", t[:40], run_esc(t)[:80], escaped(t)[:80])
    for v in wrong[:3]:
        print("  decimal differs:", v, run_dec(v), b"%d" % v)
    for c in off[:2]:
        a, b = made_reply(lib._mlir_ciface_query_reply, c), written_reply(c)
        i = next((k for k in range(min(len(a), len(b))) if a[k] != b[k]), min(len(a), len(b)))
        print("  reply differs at byte", i, a[max(0, i - 40):i + 40], b[max(0, i - 40):i + 40])
    sys.exit(1 if bad or wrong or off else 0)


if __name__ == "__main__":
    main()
