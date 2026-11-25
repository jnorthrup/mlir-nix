#!/usr/bin/env python3
"""Dense-metacharacter generator for the kursive (re2mlir) differential.

  kursive-dense.py module OUT.mlir N SEED   a module of N `kursive.pattern` ops (the reader's input); run it through
                                            `mlnix-opt OUT --re2mlir[=pool-cap=P set-cap=S] --kursive-to-program[=step-cap=C]`
                                            with the old and the new binary and cmp the outputs (errors and counts included).
  kursive-dense.py cases OUT.txt N SEED     N `builtins.match`/`builtins.split` Nix expressions, one per line, for
                                            kursive-probe-style runs (mlnix eval --strict --json --expr E).

Pattern mix: 40% dense metacharacter strings (the ERE operators, brackets, classes, braces, backslashes, bytes
outside ASCII), 25% bracket-dense fragments, 25% grammar-built patterns (valid most of the time), 10% fixed corners.
Bytes that Nix's strings cannot hold (NUL) are never generated.
"""
import random, sys

DENSE = list("()|*+?{}[]^$.\\-,:=0123456789abcxyz ~&#")
FRAG = ["[[:alpha:]", "[[:alpha:]]", "[[:foo:]]", "[[:digit:]]+", "[:alpha:]", "[.-.]", "[.a.]", "[=a=]", "[[=a=]]",
        "[[.-.]]", "[a-]", "[]-a]", "[^]a]", "[--z]", "[a-a]", "[z-a]", "[\\\\]", "[a\\]", "[\\.]", "a{,}", "a{,2}",
        "a{2,}}", "a{1}{2}", "a{1,2}{3}", "a{}", "a{x}", "a{1,2", "a}", "{1}", "a{0}", "a{3,2}", "a{99999}", "()*",
        "(|)", "(*)", "^*", "$*", "a^", "b$c", "\\(", "\\)", "\\{", "\\}", "\\*", "\\\\", "\\b", "\\w", "\\d", "\\1",
        "\\n", "\\t", "é", "é+", "[é]", "[é-ü]", "\xff", "\x80+", "[\x80-\xff]", ".*.*.*", "(a|b|)*", "((()))", "(((a)))*"]
ATOMS = ["a", "b", "c", ".", "[ab]", "[^a]", "[a-c]", "[[:alpha:]]", "[[:digit:]]", "\\.", "x", "(a|b)", "()", "(a*)",
         "[[:space:]]", "\\\\", "\\*", "^", "$", "[]]", "[-]"]


def dense(r):
    n = r.randint(1, 16)
    return "".join(r.choice(DENSE) for _ in range(n))


def frag(r):
    k = r.randint(1, 4)
    return "".join(r.choice(FRAG + DENSE) for _ in range(k))


def grammar(r, d=0):
    k = r.random()
    if d > 3 or k < 0.3:
        p = r.choice(ATOMS)
    elif k < 0.5:
        p = grammar(r, d + 1) + grammar(r, d + 1)
    elif k < 0.65:
        p = "(" + grammar(r, d + 1) + ")"
    elif k < 0.8:
        p = grammar(r, d + 1) + "|" + grammar(r, d + 1)
    else:
        p = "(" + grammar(r, d + 1) + ")"
    q = r.random()
    if q < 0.15: p += "*"
    elif q < 0.25: p += "+"
    elif q < 0.32: p += "?"
    elif q < 0.36: p += "{%d,%d}" % (r.randint(0, 2), r.randint(1, 3))
    if r.random() < 0.03: p = "^" + p
    if r.random() < 0.03: p = p + "$"
    if r.random() < 0.02: p = p.replace(")", "", 1)  # invalid sometimes
    return p


FIXED = ["(a|ab)(c|bcd)(d*)", "(a*)", "a+", "x*", "", "(.*)", "^a", "b$", "[[:alpha:]]+", "[a-]", "[]a]", "(", ")", "*a",
         "a**", "\\", "[a", "a{2,1}", "a{", "a{1", "(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)"]


def pattern(r):
    k = r.random()
    if k < 0.40: return dense(r)
    if k < 0.65: return frag(r)
    if k < 0.90: return grammar(r)
    return r.choice(FIXED)


def mlir_bytes(s):
    b = s.encode("utf-8", "surrogateescape") if isinstance(s, str) else s
    out = []
    for c in b:
        if 0x20 <= c < 0x7f and c not in (0x22, 0x5c):
            out.append(chr(c))
        else:
            out.append("\\%02X" % c)
    return "".join(out)


def nixstr(s):
    """A Nix string literal as bytes (bytes >= 0x80 pass through as UTF-8 bytes)."""
    b = s.encode("utf-8") if isinstance(s, str) else s
    out = bytearray()
    for c in b:
        if c == 0x5c: out += b"\\\\"
        elif c == 0x22: out += b'\\"'
        elif c == 0x0a: out += b"\\n"
        elif c == 0x09: out += b"\\t"
        else: out.append(c)
    s2 = bytes(out).replace(b"${", b"\\${")
    return b'"' + s2 + b'"'


def text(r):
    return "".join(r.choice("abcx.1 é") for _ in range(r.randint(0, 10)))


def main():
    mode, out, n, seed = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
    r = random.Random(seed)
    if mode == "module":
        with open(out, "w") as f:
            f.write("module {\n")
            for i in range(n):
                f.write('  kursive.pattern @p%d "%s"\n' % (i, mlir_bytes(pattern(r))))
            f.write("}\n")
    elif mode == "cases":
        with open(out, "wb") as f:
            for _ in range(n):
                fn = r.choice(["match", "split"])
                f.write(b"builtins." + fn.encode() + b" " + nixstr(pattern(r)) + b" " + nixstr(text(r)) + b"\n")
    else:
        sys.exit("mode: module | cases")


if __name__ == "__main__":
    main()
