#!/usr/bin/env python3
"""ci-corpus-unterminated.py STACK.dylib [N]: corpus_load never crashes on a text cut inside a string.

The Confix scan closes a quote that is the text's last byte at that byte (close == open), so that string's inside is
negative.  corpus_load refuses such a text ("the evaluation ends inside a string"); before the fix the columns read it
and bus-errored (the 2026-11-22 minimal crasher, 57 bytes).  Python here never loads the stack: it writes case files and
spawns ci-corpus-snap (test/ci-corpus-snap.c, built with clang beside this test), one process per case, so a crash is a
nonzero exit status and no interpreter dies.  Cases: the 57-byte crasher, every cut of a small corpus, N random cuts.
"""
import os
import random
import shutil
import struct
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
MIN = bytes([123, 34, 34, 123, 34, 34, 34, 34, 123, 34, 34, 123, 34, 34, 123, 34, 34, 34, 34, 125, 125, 34, 34, 91,
             93, 125, 125, 34, 111, 112, 116, 105, 111, 110, 115, 34, 91, 123, 34, 34, 34, 34, 34, 34, 102, 97, 108,
             115, 101, 34, 115, 116, 97, 116, 101, 34, 34])
UNTERMINATED = 'the evaluation ends inside a string'
REFUSALS = {'the evaluation is not a JSON object', 'the evaluation has no options', UNTERMINATED}

SMALL = (b'{"options":[{"path":["networking","dhcp"],"state":"set","kind":"boolean","value":true,'
         b'"description":"a \\"quoted\\" text \\u2019"},{"path":["services","x"],"state":"default",'
         b'"kind":"string","value":"a/modules/b","declarations":["modules/x/y.nix"]}],'
         b'"etc":{"a.txt":{"text":"hello"}}}\n')


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


def case_file(path, text, mut=None, ms=0.0):
    with open(path, 'wb') as f:
        f.write(struct.pack('<QQQ', len(text), (1 << 64) - 1 if mut is None else len(mut),
                            struct.unpack('<Q', struct.pack('<d', ms))[0]))
        f.write(text)
        if mut is not None:
            f.write(mut)


def build_harness(scratch):
    exe = os.path.join(scratch, 'ci-corpus-snap')
    src = os.path.join(HERE, 'ci-corpus-snap.c')
    # the system clang finds dlfcn.h (on macOS Homebrew's does not); else whichever clang is on PATH
    cc = next((c for c in ('/usr/bin/clang', 'clang', 'clang-22') if shutil.which(c)), 'clang')
    r = subprocess.run([cc, '-O1', src, '-o', exe], capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit('cannot build ci-corpus-snap: ' + r.stderr)
    return exe


def main():
    lib = os.path.abspath(sys.argv[1])
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 200
    fails = total = refused = 0
    with tempfile.TemporaryDirectory() as scratch:
        exe = build_harness(scratch)
        for name, data in cases(n):
            total += 1
            path = os.path.join(scratch, 'case.bin')
            case_file(path, data)
            r = subprocess.run([exe, lib, path], capture_output=True, text=True)
            if r.returncode != 0:
                fails += 1
                print('CRASH rc=%d %s %r' % (r.returncode, name, data[:80]))
                continue
            first = r.stdout.split('\n', 1)[0]
            if first.startswith('base refused '):
                refused += 1
                msg = first[len('base refused '):]
                if msg not in REFUSALS:
                    fails += 1
                    print('UNKNOWN REFUSAL %s %r' % (name, msg))
                if name == 'min' and msg != UNTERMINATED:
                    fails += 1
                    print('MIN NOT REFUSED AS UNTERMINATED: %r' % msg)
            elif not first.startswith('base len='):
                fails += 1
                print('BAD OUTPUT %s %r' % (name, first[:80]))
    print('ci-corpus-unterminated: %d cases, %d refused, %d failures' % (total, refused, fails))
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
