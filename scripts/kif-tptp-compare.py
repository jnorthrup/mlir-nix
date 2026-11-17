#!/usr/bin/env python3
"""kif-tptp-compare.py SIGMA.tptp OURS.p [--examples OUT]

Compares the TPTP problem `mlnix-kif --tptp` writes (lib/Dialect/KifTptp.cpp) with SigmaKEE's translation of the same KB
(the SUMO.tptp it writes), form by form.  Both write `% f: <the form>` before what a form becomes.  A form's formulas
(SigmaKEE writes several where it expands a row variable or instantiates a predicate variable) are compared:
  * as texts (the fof's formula, its name and role aside): `same text`;
  * where the texts differ, as formulas: parsed, the and/or chains flattened and ordered, and each run of one quantifier
    one block, its variables ordered by name: `same formula` (the formula written another way);
  * else `different`.  `SigmaKEE only`: a form SigmaKEE writes and we do not; `ours only`: the other way.
The counts are by where the form comes from (SigmaKEE's comment: the KB's file, or its cache, SUMO_Cache.kif; ours have
no file) and by the form's predicate.  --examples writes the first differences of each kind, the two texts side by side.

kif-tptp-compare.py --flat SIGMA.p OURS.p [--examples OUT]
compares two problems as multisets of formulas, include()s followed, the conjectures apart from the axioms (a test's
problem: SigmaKEE's KB with the test's tells, and its query): each formula of one matched by text, then by formula, in
the other.
"""
import collections, re, sys

FOF = re.compile(r"^(?:fof|tff)\(([^,]+),(\w+),(.*)\)\.\s*$")

# The two axioms with two predicate variables SigmaKEE instantiates (PredVarInst.handleDoubles): it writes both sets of
# instances under whichever of them a thread meets first, mlnix-kif each under its own; compared as one.
DOUBLES = ("(=> (and (instance ?REL1 Predicate) (instance ?REL2 Predicate) (disjointRelation ?REL1 ?REL2) (?REL1 @ROW2)) "
           "(not (?REL2 @ROW2)))",
           "(=> (and (subrelation ?REL1 ?REL2) (instance ?REL1 Predicate) (instance ?REL2 Predicate) (?REL1 @ROW)) "
           "(?REL2 @ROW))")
DOUBLES_KEY = "(the two double predicate variable axioms)"

# What SUMOKBtoTPTPKB writes after the KB (printListFnSemanticAxioms, printPartitionSemanticAxioms) has no `% f:` line of
# its own, so it would count under the last form's; mlnix-kif writes it under EXTRAS_KEY, and SigmaKEE's is moved there.
EXTRAS_KEY = "(the ListFn and partition axioms SUMOKBtoTPTPKB writes)"


def extras():
    def vs(v, k):
        return ",".join(f"{v}{i}" for i in range(1, k + 1))
    out = set()
    for k in range(1, 8):
        xs = vs("V__X", k)
        fn = f"s__ListFn__{k}Fn({xs})"
        out.add(f"! [{xs}] : s__instance({fn},s__List)")
        out.add(f"! [{xs}] : (s__ListLengthFn({fn}) = n__{k})")
        for i in range(1, k + 1):
            out.add(f"! [{xs}] : (s__ListOrderFn({fn},n__{i}) = V__X{i})")
            out.add(f"! [{xs}] : s__inList(V__X{i},{fn})")
    for k in range(2, 8):
        cs = vs("V__C", k)
        allv = "V__C," + cs
        atom = f"s__partition__{k + 1}(V__C,{cs})"
        disj = " | ".join(f"s__instance(V__OBJ,V__C{i})" for i in range(1, k + 1))
        out.add(f"! [{allv}] : ({atom} => (s__ChildrenOfFn(V__C) = s__ListFn__{k}Fn({cs})))")
        out.add(f"! [V__OBJ,{allv}] : (({atom} & s__instance(V__OBJ,V__C)) => ({disj}))")
    return {f"({x})" for x in out}


EXTRAS = extras()


def blocks(path):
    """{key: [formula texts]}, {key: source}, {key: why not written}"""
    forms, source, skipped = collections.defaultdict(list), {}, {}
    key = None
    for line in open(path, errors="replace"):
        line = line.rstrip("\n")
        if line.startswith("% f: "):
            key = line[5:].strip()
            if key in DOUBLES:
                key = DOUBLES_KEY
            forms.setdefault(key, [])
        elif key is not None and line.startswith("% ") and " from file " in line:
            source[key] = "cache" if "SUMO_Cache" in line else "kb"
        elif key is not None and line.startswith("% not written: "):
            skipped[key] = line[len("% not written: "):]
        elif key is not None and line.startswith("% is higher order"):
            skipped[key] = "higher order"
        else:
            m = FOF.match(line)
            if m and key is not None and m.group(2) != "conjecture":
                forms[EXTRAS_KEY if m.group(3) in EXTRAS else key].append(m.group(3))
    return forms, source, skipped


TOKEN = re.compile(r"""\s*(?:(?P<sq>'(?:[^'\\]|\\.)*')|(?P<dq>"(?:[^"\\]|\\.)*")|(?P<w>[A-Za-z0-9_$]+)
  |(?P<op><=>|<~>|=>|<=|~\||~&|!=|[()\[\],:!?~&|=]))""", re.X)


def tokens(s):
    out, i = [], 0
    while i < len(s):
        m = TOKEN.match(s, i)
        if not m or m.end() == i:
            if s[i:].strip() == "":
                break
            raise SyntaxError(s[i:i + 30])
        out.append(m.group(m.lastgroup or 0))
        i = m.end()
    return out


class Reader:
    def __init__(self, s):
        self.t, self.i = tokens(s), 0

    def peek(self):
        return self.t[self.i] if self.i < len(self.t) else None

    def take(self, want=None):
        tok = self.t[self.i]
        if want and tok != want:
            raise SyntaxError(f"{want} expected, {tok} found")
        self.i += 1
        return tok

    def formula(self):
        a = self.unitary()
        op = self.peek()
        if op in ("&", "|"):
            parts = [a]
            while self.peek() == op:
                self.take()
                parts.append(self.unitary())
            return (op,) + tuple(parts)
        if op in ("=>", "<=", "<=>", "<~>", "~|", "~&"):
            self.take()
            return (op, a, self.unitary())
        return a

    def unitary(self):
        v = self.peek()
        if v in ("!", "?"):
            self.take()
            self.take("[")
            vs = [self.take()]
            while self.peek() == ",":
                self.take()
                vs.append(self.take())
            self.take("]")
            self.take(":")
            return (v, tuple(vs), self.unitary())
        if v == "~":
            self.take()
            return ("~", self.unitary())
        if v == "(":
            self.take()
            f = self.formula()
            self.take(")")
            return f
        t = self.term()
        if self.peek() in ("=", "!="):
            return (self.take(), t, self.term())
        return t

    def term(self):
        w = self.take()
        if self.peek() == "(":
            self.take()
            args = [self.term()]
            while self.peek() == ",":
                self.take()
                args.append(self.term())
            self.take(")")
            return ("app", w) + tuple(args)
        return w


def canon(f):
    if not isinstance(f, tuple):
        return f
    k = f[0]
    if k in ("&", "|"):
        parts = []
        for p in f[1:]:
            c = canon(p)
            parts.extend(c[1:] if isinstance(c, tuple) and c[0] == k else [c])
        return (k,) + tuple(sorted(parts, key=repr))
    if k in ("!", "?"):
        vs, body = set(f[1]), canon(f[2])
        while isinstance(body, tuple) and body[0] == k:
            vs |= set(body[1])
            body = body[2]
        return (k, tuple(sorted(vs)), body)
    return (k,) + tuple(canon(x) for x in f[1:])


def same_formula(a, b):
    try:
        return canon(Reader(a).formula()) == canon(Reader(b).formula())
    except (SyntaxError, IndexError):
        return False


INCLUDE = re.compile(r"^include\('([^']+)'\)\.")


def flat(path, seen=None):
    """[(role, formula text)] of a problem, include()s followed"""
    seen = seen if seen is not None else set()
    if path in seen:
        return []
    seen.add(path)
    out = []
    for line in open(path, errors="replace"):
        m = INCLUDE.match(line)
        if m:
            inc = m.group(1)
            if not inc.startswith("/"):
                import os
                inc = os.path.join(os.path.dirname(path), inc)
            out.extend(flat(inc, seen))
            continue
        m = FOF.match(line.rstrip("\n"))
        if m:
            out.append(("conjecture" if m.group(2) in ("conjecture", "question") else "axiom", m.group(3)))
    return out


def compare_flat(argv):
    a, b = flat(argv[2]), flat(argv[3])
    out = open(argv[argv.index("--examples") + 1], "w") if "--examples" in argv else None
    for role in ("axiom", "conjecture"):
        x = collections.Counter(t for r, t in a if r == role)
        y = collections.Counter(t for r, t in b if r == role)
        same = x & y
        xo, yo = x - same, y - same
        # by formula: the and/or chains and the quantifier blocks in any order, extra parentheses aside
        def canon_of(t):
            try:
                return repr(canon(Reader(t).formula()))
            except (SyntaxError, IndexError):
                return "unparsed:" + t
        cx = collections.Counter()
        for t, k in xo.items():
            cx[canon_of(t)] += k
        cy = collections.Counter()
        for t, k in yo.items():
            cy[canon_of(t)] += k
        sameform = cx & cy
        print(f"{role:10} SigmaKEE {sum(x.values())}, ours {sum(y.values())}: same text {sum(same.values())}, "
              f"same formula {sum(sameform.values())}, SigmaKEE only {sum((cx - sameform).values())}, "
              f"ours only {sum((cy - sameform).values())}")
        if out:
            left, right = cx - sameform, cy - sameform
            for t, k in xo.items():
                if left[canon_of(t)] > 0:
                    out.write(f"== {role} SigmaKEE only: {t}\n")
            for t, k in yo.items():
                if right[canon_of(t)] > 0:
                    out.write(f"== {role} ours only: {t}\n")
    return 0


def main(argv):
    if argv[1] == "--flat":
        return compare_flat(argv)
    sig, sig_src, sig_skip = blocks(argv[1])
    ours, _, our_skip = blocks(argv[2])
    out = open(argv[argv.index("--examples") + 1], "w") if "--examples" in argv else None
    counts = collections.Counter()
    by_pred = collections.defaultdict(collections.Counter)
    examples = collections.Counter()
    for key in sorted(set(sig) | set(ours)):
        a, b = sorted(sig.get(key, [])), sorted(ours.get(key, []))
        if not a and not b:
            continue
        src = sig_src.get(key, "ours")
        m = re.match(r"\((\S+)", key)
        pred = m.group(1) if m else key
        if a == b:
            kind = "same text"
        elif not b:
            kind = "SigmaKEE only"
        elif not a:
            kind = "ours only"
        elif len(a) == len(b) and all(any(same_formula(x, y) for y in b) for x in a):
            kind = "same formula"
        else:
            kind = "different"
        counts[(src, kind)] += 1
        by_pred[pred][kind] += 1
        if out and kind != "same text" and examples[(kind, pred)] < 3:
            examples[(kind, pred)] += 1
            why = our_skip.get(key) or sig_skip.get(key) or ""
            out.write(f"== {kind} [{src}] {key}" + (f"  ({why})" if why else "") + "\n")
            for x in a:
                out.write(f"   SigmaKEE: {x}\n")
            for y in b:
                out.write(f"   ours:     {y}\n")
    kinds = ["same text", "same formula", "different", "SigmaKEE only", "ours only"]
    for src in ("kb", "cache", "ours"):
        row = [counts[(src, k)] for k in kinds]
        if sum(row):
            print(f"{src:6} " + "  ".join(f"{k}: {n}" for k, n in zip(kinds, row)))
    total = [sum(counts[(s, k)] for s in ("kb", "cache", "ours")) for k in kinds]
    print("all    " + "  ".join(f"{k}: {n}" for k, n in zip(kinds, total)))
    print("by predicate (the 25 with most forms not the same text):")
    worst = sorted(by_pred.items(), key=lambda kv: -(sum(kv[1].values()) - kv[1]["same text"]))[:25]
    for pred, c in worst:
        print(f"  {pred:28} " + "  ".join(f"{k}: {c[k]}" for k in kinds if c[k]))
    skipped = collections.Counter(our_skip.values())
    print("not written by mlnix-kif:", dict(skipped))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
