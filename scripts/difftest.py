#!/usr/bin/env python3
"""Differential tests: evaluate the same expressions with mlnix and with
reference Nix (docker container `nixref`, see scripts/nixref) and compare.

usage: difftest.py [--mlnix PATH] [-v]
"""
import os, subprocess, sys, argparse

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIX = os.path.join(ROOT, "test", "diff")

CASES = [
    # --- derivations -------------------------------------------------------
    'derivation { name = "foo"; builder = "/bin/sh"; system = "x86_64-linux"; }',
    '(derivation { name = "foo"; builder = "/bin/sh"; system = "x86_64-linux"; args = ["-c" "echo hi > $out"]; }).drvPath',
    'let d = derivation { name = "multi"; builder = "/bin/sh"; system = "x86_64-linux"; outputs = ["out" "dev" "lib"]; }; in [d.drvPath d.out.outPath d.dev.outPath d.lib.outPath d.outputName]',
    'let a = derivation { name = "a"; builder = "/bin/sh"; system = "x86_64-linux"; }; b = derivation { name = "b"; builder = "/bin/sh"; system = "x86_64-linux"; dep = a; s = "${a}/bin"; }; in [b.drvPath b.outPath]',
    'let a = derivation { name = "a"; builder = "/bin/sh"; system = "x86_64-linux"; outputs = ["out" "dev"]; }; b = derivation { name = "b"; builder = "/bin/sh"; system = "x86_64-linux"; d = a.dev; }; in [b.drvPath b.outPath]',
    '(derivation { name = "fo"; builder = "/bin/sh"; system = "x86_64-linux"; outputHash = "sha256-47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU="; outputHashMode = "flat"; }).outPath',
    '(derivation { name = "fo-r"; builder = "/bin/sh"; system = "x86_64-linux"; outputHash = "1b8m03r63zqhnjf7l5wnldhh7c134ap5vpj0850ymkq1iyzicy5s"; outputHashAlgo = "sha256"; outputHashMode = "recursive"; }).outPath',
    '(derivation { name = "fo-sha1"; builder = "/bin/sh"; system = "x86_64-linux"; outputHash = "sha1-2jmj7l5rSw0yVb/vlWAYkK/YBwk="; outputHashMode = "recursive"; }).outPath',
    'let fo = derivation { name = "src"; builder = "/bin/sh"; system = "x86_64-linux"; outputHash = "sha256-47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU="; }; d = derivation { name = "uses-fo"; builder = "/bin/sh"; system = "x86_64-linux"; src = fo; }; in [d.drvPath d.outPath]',
    '(derivation { name = "sa"; builder = "/bin/sh"; system = "x86_64-linux"; __structuredAttrs = true; foo = [1 2 {a = "b";}]; bar = 1.5; baz = null; t = true; }).drvPath',
    '(derivation { name = "esc"; builder = "/bin/sh"; system = "x86_64-linux"; s = "a\\"b\\\\c\\nd\\te\\r"; l = [1 "x" true false null [2 3]]; }).drvPath',
    '(derivation { name = "ign"; builder = "/bin/sh"; system = "x86_64-linux"; __ignoreNulls = true; x = null; y = 1; }).drvPath',
    '(derivation { name = "ph"; builder = "/bin/sh"; system = "x86_64-linux"; p = placeholder "out"; }).drvPath',
    'builtins.toFile "hello.txt" "hello world"',
    'let f = builtins.toFile "a" "x"; in builtins.toFile "b" "ref ${f}"',
    'let f = builtins.toFile "a" "x"; d = derivation { name = "tf"; builder = "/bin/sh"; system = "x86_64-linux"; f = f; }; in [d.drvPath d.outPath]',
    # --- sources copied to the store -----------------------------------------
    '"${./test/diff/file.txt}"',
    '"${./test/diff/dir}"',
    '(derivation { name = "src"; builder = "/bin/sh"; system = "x86_64-linux"; src = ./test/diff/dir; }).drvPath',
    'builtins.path { path = ./test/diff/dir; name = "renamed"; }',
    'builtins.path { path = ./test/diff/dir; filter = p: t: baseNameOf p != "b.txt"; }',
    'builtins.filterSource (p: t: t != "symlink") ./test/diff/dir',
    'builtins.path { path = ./test/diff/file.txt; recursive = false; }',
    'builtins.hashFile "sha256" ./test/diff/file.txt',
    'builtins.readDir ./test/diff/dir',
    # --- string context ------------------------------------------------------
    'let d = derivation { name = "c"; builder = "/bin/sh"; system = "x86_64-linux"; outputs = ["out" "bin"]; }; in builtins.getContext "${d} ${d.bin} ${d.drvPath}"',
    'builtins.getContext (builtins.unsafeDiscardOutputDependency (derivation { name = "c"; builder = "/bin/sh"; system = "x86_64-linux"; }).drvPath)',
    # --- hashing / misc --------------------------------------------------------
    'map (a: builtins.hashString a "abc") ["md5" "sha1" "sha256" "sha512"]',
    'map (f: builtins.convertHash { hash = "sha256-47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU="; toHashFormat = f; }) ["base16" "nix32" "base64" "sri"]',
    'builtins.placeholder "dev"',
    'builtins.toJSON { a = 1.5; b = [ 1e300 0.1 100.0 (-0.0) 1e-7 123456789012345678.0 ]; c = "\\u0001\\n"; }',
    'builtins.fromJSON "{\\"a\\": [1, 2.5, -3e2, \\"\\\\u00e9\\\\ud83d\\\\ude00\\", null, true], \\"b\\": {}}"',
    'builtins.toXML [ 1 "<&>\\"" { a = x: x; } ]',
    'builtins.split "(a)|b" "xaybz"',
    'builtins.match "([a-z]+)-([0-9.]+)(-pre)?" "nix-2.35.4"',
    'map (builtins.compareVersions "1.2.3") [ "1.2.3" "1.2.4" "1.2pre" "1.2.3a" "2" ]',
    'builtins.splitVersion "1.2.3pre4-beta5"',
    'builtins.parseDrvName "nix-unstable-2.35.4pre1234"',
    'builtins.sort builtins.lessThan [ 3 1 2 "x" ]',
    'builtins.genericClosure { startSet = [{key = 1;}]; operator = x: if x.key < 10 then [{key = x.key * 2;} {key = x.key + 3;}] else []; }',
    'toString [ 1 2.5 true false null "x" [ ] [ 3 ] ]',
    'builtins.fromTOML "a = 1\\nb.c = [1, 2]\\n[d]\\ne = \\"x\\"\\n[[f]]\\ng = 1.5\\n[[f]]\\ng = -0.5"',
    'let x = builtins.tryEval (throw "x"); y = builtins.tryEval (assert false; 1); in [x y]',
    'builtins.functionArgs ({a, b ? 1, ...}: a)',
    '(x: x) == (x: x)',
    'let f = x: x; in [ f ] == [ f ]',
    'builtins.attrNames (builtins.mapAttrs (n: v: v) { z = 1; a = 2; "1" = 3; "A" = 4; })',
    '1.0 / 3',
    '[ (9223372036854775807) (-9223372036854775807 - 1) ]',
    'builtins.substring 2 3 "hello world"',
    'builtins.replaceStrings ["" "a"] ["-" "A"] "banana"',
    'builtins.concatStringsSep ", " (builtins.attrValues { a = "1"; b = "2"; })',
    'with builtins; foldl\' (a: b: a + b) 0 (genList (x: x * x) 100)',
]

def run_local(mlnix, expr):
    env = dict(os.environ, NIX_REMOTE="dummy://", NIX_STORE_DIR="/nix/store")
    env["MLNIX_STORE_ROOT"] = "/tmp/mlnix-difftest-root"
    p = subprocess.run([mlnix, "instantiate", "--eval", "--strict", "-E", expr], cwd=ROOT,
                       capture_output=True, env=env, timeout=60)
    return p.returncode, p.stdout.decode(errors="replace").strip()

def run_ref(expr):
    p = subprocess.run(["docker", "exec", "-w", "/work", "nixref", "nix-instantiate", "--readonly-mode",
                        "--eval", "--strict", "-E", expr], capture_output=True, timeout=120)
    return p.returncode, p.stdout.decode(errors="replace").strip()

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mlnix", default=os.path.join(ROOT, "build", "bin", "mlnix"))
    ap.add_argument("-v", action="store_true")
    a = ap.parse_args()
    os.makedirs(os.path.join(FIX, "dir", "sub"), exist_ok=True)
    open(os.path.join(FIX, "file.txt"), "w").write("hello\n")
    open(os.path.join(FIX, "dir", "a.txt"), "w").write("a\n")
    open(os.path.join(FIX, "dir", "b.txt"), "w").write("b\n")
    open(os.path.join(FIX, "dir", "sub", "x.sh"), "w").write("#!/bin/sh\necho x\n")
    os.chmod(os.path.join(FIX, "dir", "sub", "x.sh"), 0o755)
    link = os.path.join(FIX, "dir", "link")
    if not os.path.islink(link):
        os.symlink("a.txt", link)
    ok = 0
    for e in CASES:
        r1 = run_local(a.mlnix, e)
        r2 = run_ref(e)
        good = r1 == r2
        ok += good
        if not good or a.v:
            print(("PASS " if good else "FAIL ") + e)
            if not good:
                print("   mlnix:", r1)
                print("   nix:  ", r2)
    print(f"{ok}/{len(CASES)} identical to Nix 2.35.4")
    return 0 if ok == len(CASES) else 1

if __name__ == "__main__":
    sys.exit(main())
