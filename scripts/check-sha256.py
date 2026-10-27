#!/usr/bin/env python3
"""Check lib/Store/Sha256.cpp against hashlib.

Builds test/sha256/check.cpp twice with the host's C++ compiler: with the x86 SHA instructions replaced by plain C++
(-DNIX_SHA256_EMULATE_X86, test/sha256/emulate_x86.h), which runs the hardware path's shuffles and message schedule on any host,
and as the code is built for production (on a host without the instructions that is the portable path; on one with them, the
instructions themselves).  Each is fed many lengths, around the block and padding boundaries and random, in random chunkings;
every digest must equal hashlib's.

usage: check-sha256.py [--cases N] [--cxx c++] [--source lib/Store/Sha256.cpp]
"""
import argparse, hashlib, os, random, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def splitmix_bytes(seed, n):
    out = bytearray()
    x = seed
    mask = (1 << 64) - 1
    for _ in range(n):
        x = (x + 0x9E3779B97F4A7C15) & mask
        z = x
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & mask
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & mask
        out.append((z ^ (z >> 31)) & 0xFF)
    return bytes(out)


def build(cxx, out, emulate, source):
    cmd = [cxx, "-std=c++17", "-O1", "-I", os.path.join(ROOT, "include")]
    if sys.platform == "darwin":  # the Command Line Tools' c++ does not find libc++ without the SDK
        sdk = subprocess.run(["xcrun", "--show-sdk-path"], capture_output=True, text=True).stdout.strip()
        if sdk:
            cmd += ["-isysroot", sdk]
    if emulate:
        cmd += ["-DNIX_SHA256_EMULATE_X86", "-I", os.path.join(ROOT, "test", "sha256")]
    cmd += [os.path.join(ROOT, "test", "sha256", "check.cpp"), source, "-o", out]
    subprocess.run(cmd, check=True)


def cases(n, rng):
    lens = [0, 1, 2, 3, 54, 55, 56, 57, 63, 64, 65, 119, 120, 121, 127, 128, 129, 191, 192, 193, 1000, 4096, 65536, 1 << 20]
    out = []
    for i in range(n):
        ln = lens[i] if i < len(lens) else rng.choice([rng.randrange(0, 300), rng.randrange(0, 5000), rng.randrange(0, 200000)])
        k = rng.choice([0, 1, 2, 5, 12])
        chunks = [rng.choice([0, 1, 3, 7, 31, 55, 56, 63, 64, 65, 100, 128, 1000, 100000]) or 1 for _ in range(k)]
        out.append((ln, rng.getrandbits(64), chunks))
    return out


def run(binary, cs):
    text = "".join(f"{ln} {seed} {' '.join(map(str, ch))}\n" for ln, seed, ch in cs) + "hw\n"
    res = subprocess.run([binary], input=text, capture_output=True, text=True, check=True).stdout.split()
    return res[:-1], res[-1] == "1"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cases", type=int, default=400)
    ap.add_argument("--cxx", default=os.environ.get("CXX", "c++"))
    ap.add_argument("--source", default=os.path.join(ROOT, "lib", "Store", "Sha256.cpp"), help="the file under test (to check a mutant)")
    args = ap.parse_args()
    rng = random.Random(20261027)
    cs = cases(args.cases, rng)
    want = [hashlib.sha256(splitmix_bytes(seed, ln)).hexdigest() for ln, seed, _ in cs]
    bad = 0
    with tempfile.TemporaryDirectory() as d:
        for name, emulate in (("emulated x86 SHA instructions", True), ("as built here", False)):
            exe = os.path.join(d, "check-emu" if emulate else "check-native")
            build(args.cxx, exe, emulate, args.source)
            got, hw = run(exe, cs)
            wrong = [i for i, (g, w) in enumerate(zip(got, want)) if g != w]
            print(f"{name}: {len(cs) - len(wrong)}/{len(cs)} digests equal hashlib's; hardware path in use: {hw}")
            for i in wrong[:5]:
                print(f"  case {i}: length {cs[i][0]} chunks {cs[i][2]}: got {got[i]} want {want[i]}")
            bad += len(wrong)
            if emulate and not hw:  # the self-test rejected the hardware path: the digests above are the portable code's
                print("  the hardware path was rejected by its own self-test: it is wrong")
                bad += 1
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
