#!/usr/bin/env python3
"""ci-corpus-unterminated.py STACK.dylib [N]: corpus_load must never crash on a text cut inside a string.

The Confix scan closes a quote that is the text's last byte at that byte (close == open), so the string's inside is
negative; corpus_load refuses such a text ("the evaluation ends inside a string"), where the columns read it and bus
errored (the 2026-11-22 minimal crasher: 57 bytes).  Each text runs in its own child process, so a crash is an exit
code, not a dead test.  The cases: the 57-byte crasher, every cut of a small corpus, and N random cuts (default 200).
"""
import ctypes
import os
import random
import subprocess
import sys
import tempfile

MIN = bytes([123, 34, 34, 123, 34, 34, 34, 34, 123, 34, 34, 123, 34, 34, 123, 34, 34, 34, 34, 125, 125, 34, 34, 91,
             93, 125, 125, 34, 111, 112, 116, 105, 111, 110, 115, 34, 91, 123, 34, 34, 34, 34, 34, 34, 102, 97, 108,
             115, 101, 34, 115, 116, 97, 116, 101, 34, 34])
UNTERMINATED = b'the evaluation ends inside a string'
REFUSALS = {b'the evaluation is not a JSON object', b'the evaluation has no options', UNTERMINATED}

SMALL = (b'{"options":[{"path":["networking","dhcp"],"state":"set","kind":"boolean","value":true,'
         b'"description":"a \\"quoted\\" text \\u2019"},{"path":["services","x"],"state":"default",'
         b'"kind":"string","value":"a/modules/b","declarations":["modules/x/y.nix"]}],'
         b'"etc":{"a.txt":{"text":"hello"}}}\n')


def child(lib, path):
    """load the bytes of path with lib's corpus_load; print 'ok' or the refusal's wording"""
    l = ctypes.CDLL(lib, mode=ctypes.RTLD_LOCAL)
    l.corpus_load.restype = ctypes.c_void_p
    l.corpus_load.argtypes = [ctypes.c_void_p, ctypes.c_int64, ctypes.c_double]
    l.corpus_why.restype = ctypes.c_void_p
    l.corpus_why_n.restype = ctypes.c_int64
    libc = ctypes.CDLL(None)
    libc.malloc.restype = ctypes.c_void_p
    libc.malloc.argtypes = [ctypes.c_size_t]
    data = open(path, 'rb').read()
    p = libc.malloc(len(data) + 8)
    ctypes.memmove(p, data, len(data))
    c = l.corpus_load(p, len(data), 0.0)
    if c:
        print('ok')
    else:
        print('refused ' + ctypes.string_at(l.corpus_why(), l.corpus_why_n()).decode())


def run(lib, data, scratch):
    path = os.path.join(scratch, 'case.json')
    with open(path, 'wb') as f:
        f.write(data)
    r = subprocess.run([sys.executable, os.path.abspath(__file__), '--child', lib, path], capture_output=True)
    return r.returncode, r.stdout.decode().strip()


def cases(n):
    rnd = random.Random(2026)
    yield 'min', MIN
    yield 'open quote', b'{"options":[{"path":"'
    yield 'lone quote', b'"'
    yield 'quote after a value', b'{"options":[],"etc":{"a":1},"x":"'
    for k in range(1, len(SMALL)):
        yield 'cut %d' % k, SMALL[:k]
    for k in range(n):
        cut = rnd.randint(1, len(SMALL))
        data = SMALL[:cut]
        if rnd.random() < 0.5:
            data += bytes(rnd.choice(b'"{}[],:\\ a') for _ in range(rnd.randint(1, 6)))
        yield 'random %d' % k, data


def main():
    if sys.argv[1] == '--child':
        child(sys.argv[2], sys.argv[3])
        return 0
    lib = sys.argv[1]
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 200
    fails = 0
    total = 0
    refused = 0
    with tempfile.TemporaryDirectory() as scratch:
        for name, data in cases(n):
            total += 1
            rc, out = run(lib, data, scratch)
            if rc != 0:
                fails += 1
                print('CRASH rc=%d %s %r' % (rc, name, data[:80]))
                continue
            if out.startswith('refused '):
                refused += 1
                msg = out[len('refused '):].encode()
                if msg not in REFUSALS:
                    fails += 1
                    print('UNKNOWN REFUSAL %s %r' % (name, msg))
            elif out != 'ok':
                fails += 1
                print('BAD OUTPUT %s %r' % (name, out))
            if name == 'min' and out != 'refused ' + UNTERMINATED.decode():
                fails += 1
                print('MIN NOT REFUSED AS UNTERMINATED: %r' % out)
    print('ci-corpus-unterminated: %d cases, %d refused, %d failures' % (total, refused, fails))
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
