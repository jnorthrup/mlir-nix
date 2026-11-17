#!/usr/bin/env python3
"""15-statements.py EXPORT [--show THEOREM]

The kernels check that each proof proves its statement (14-export.sh).  This script checks the part they do not: that the
statement says what the TPTP problem Vampire solved says.

For each theorem tq_<set>_<test> in EXPORT (lean4export's NDJSON of the Vampire-Hammer theorems):
  * its statement is decoded from the kernel terms: the carrier sorts and their Inhabited instances, the symbols, then a
    formula;
  * the problem is the file logs/vampire/runs.jsonl names for the test (include()s followed), read by this script's own
    TPTP parser, not tptp2lean.py's;
  * the two are compared.  The formula is h1 -> .. -> hk -> goal, for some k: the goal must be the problem's conjecture
    (False when it has none), and each hi one of its axioms (any role but conjecture and type), up to the names of bound
    variables, under one assignment of the problem's symbols to the theorem's (arity and sorts kept).

If all of that holds, the theorem the kernels accept, instantiated by that assignment, says that the conjecture follows
from those axioms in every model (every carrier nonempty).  So the problem is a Theorem whatever Vampire did.  Numerals
and distinct objects of FOF are constants in the theorem, with nothing said of them, so the theorem is the stronger
statement.

The match uses no name from the export: lean4export writes an expression once up to alpha-equivalence, so two theorems
whose statements differ only in binder names share one record, with the first theorem's names (tq_tqsp_TQG34 and
tq_sigma1_TQG34 do).  The kernels need no names; neither does this check.

Controls: each statement against another test's problem (one whose conjecture has another form), against its own
problem with the conjecture negated, and against its own problem without the axioms its first hypothesis matches.  All
must disagree.  THF problems (TQC2, encoded by hand) are not read.
"""
import json, os, re, sys, collections

V = os.path.expanduser("~/vampire-test")


# ---- the export -----------------------------------------------------------------------------------------------------

class Export:
    def __init__(self, path):
        self.names, self.levels, self.lines, self.thms = {0: ()}, {0: 0}, {}, {}
        ie = re.compile(r'"ie":(\d+)')
        for line in open(path):
            if '"ie":' in line:  # an expression (a name's string is escaped, so `"ie":` is a key)
                self.lines[int(ie.search(line).group(1))] = line
                continue
            r = json.loads(line)
            if "in" in r:
                x = r.get("str") or r.get("num")
                self.names[r["in"]] = self.names[x["pre"]] + ((x["str"] if "str" in r else x["i"]),)
            elif "il" in r:
                below = self.levels.get(r["succ"]) if "succ" in r else None
                self.levels[r["il"]] = below + 1 if below is not None else None
            elif "thm" in r:
                n = ".".join(map(str, self.names[r["thm"]["name"]]))
                if n.startswith("tq_") and "." not in n:
                    self.thms[n] = r["thm"]
        self.cache = {}

    def e(self, i):
        if i not in self.cache:
            r = json.loads(self.lines[i])
            k = next(k for k in r if k != "ie")
            self.cache[i] = (k, r[k])
        return self.cache[i]

    def name(self, n):
        return ".".join(map(str, self.names[n]))

    def spine(self, i):
        args = []
        while self.e(i)[0] == "app":
            f = self.e(i)[1]
            args.append(f["arg"])
            i = f["fn"]
        return i, args[::-1]

    def const(self, i):
        k, f = self.e(i)
        return self.name(f["name"]) if k == "const" else None

    def mentions(self, i, target, memo=None):
        """Does expression i mention the bvar `target` (counted from i's own position)?  target -1 means any loose bvar."""
        memo = {} if memo is None else memo
        key = (i, target)
        if key not in memo:
            k, f = self.e(i)
            if k == "bvar":
                out = f >= 0 if target == -1 else f == target
            elif k == "app":
                out = self.mentions(f["fn"], target, memo) or self.mentions(f["arg"], target, memo)
            elif k in ("lam", "forallE"):
                out = self.mentions(f["type"], target, memo) or self.mentions_under(f["body"], target, 1, memo)
            elif k == "letE":
                out = (self.mentions(f["type"], target, memo) or self.mentions(f["value"], target, memo)
                       or self.mentions_under(f["body"], target, 1, memo))
            elif k == "proj":
                out = self.mentions(f["struct"], target, memo)
            else:
                out = False
            memo[key] = out
        return memo[key]

    def mentions_under(self, i, target, n, memo):
        if target == -1:
            return self.loose(i, n, memo)
        return self.mentions(i, target + n, memo)

    def loose(self, i, depth, memo):  # a bvar >= depth: bound outside
        key = ("loose", i, depth)
        if key not in memo:
            k, f = self.e(i)
            if k == "bvar":
                out = f >= depth
            elif k == "app":
                out = self.loose(f["fn"], depth, memo) or self.loose(f["arg"], depth, memo)
            elif k in ("lam", "forallE"):
                out = self.loose(f["type"], depth, memo) or self.loose(f["body"], depth + 1, memo)
            elif k == "letE":
                out = (self.loose(f["type"], depth, memo) or self.loose(f["value"], depth, memo)
                       or self.loose(f["body"], depth + 1, memo))
            elif k == "proj":
                out = self.loose(f["struct"], depth, memo)
            else:
                out = False
            memo[key] = out
        return memo[key]

    def closed(self, i):
        return not self.loose(i, 0, {})

    def show(self, i):  # a term printed: constants by name, literals by value
        head, args = self.spine(i)
        k, f = self.e(head)
        h = (self.name(f["name"]) if k == "const" else f if k in ("natVal", "strVal") else f"#{f}" if k == "bvar"
             else f"<{k}>")
        return str(h) if not args else "(" + " ".join([str(h)] + [self.show(a) for a in args]) + ")"


class Mismatch(Exception):
    pass


# The canonical form both sides are brought to:
#   formulas  ("all"|"ex", sort, body)  ("not", a)  ("and"|"or"|"imp"|"iff", a, b)  ("eq"|"ne", s, t)  ("true",) ("false",)
#             ("pred", sym, args)  ("ipred", "$less".., args)
#   terms     ("var", n: the n-th quantifier from the formula's top)  ("fun", sym, args)  ("int", n)  ("ifun", "$sum".., args)
#   sorts     ("U",) the carrier of $i, ("int",), ("sort", sym)
#   symbols   ("L", context index) on the Lean side; ("T", name, arity), ("T", "num"|"dq", text), ("T", name, "sort") on
#             the TPTP side

# Int's operations as Lean 4.34.1 elaborates them (set_option pp.all): (TPTP name, type arguments, the instance)
INT_OPS = {"HAdd.hAdd": ("$sum", 3, "(instHAdd Int Int.instAdd)"), "HSub.hSub": ("$difference", 3, "(instHSub Int Int.instSub)"),
           "HMul.hMul": ("$product", 3, "(instHMul Int Int.instMul)"), "Neg.neg": ("$uminus", 1, "Int.instNegInt")}
INT_RELS = {"LT.lt": ("$less", "Int.instLTInt"), "LE.le": ("$lesseq", "Int.instLEInt"),
            "GT.gt": ("$greater", "Int.instLTInt"), "GE.ge": ("$greatereq", "Int.instLEInt")}


class LeanSide:
    def __init__(self, X, thm):
        self.X = X
        self.ctx = []          # outermost first: ("sort", name) ("inst",) ("sym", name, argsorts, res) ("var", n) ("imp",)
        self.syms = []
        e = thm["type"]
        phase = 0
        while self.X.e(e)[0] == "forallE":
            f = self.X.e(e)[1]
            name, T = self.X.name(f["name"]), f["type"]
            # a binder (c : U) is a constant, or the goal's own quantifier when no hypothesis comes between: tptp2lean.py
            # names variables as TPTP does, capitalised; taken the wrong way, it can only make a match fail
            if phase == 0 and self.is_type_sort(T):
                kind = ("sort", name)
            elif phase == 0 and self.is_inhabited(T):
                kind = ("inst",)
            elif not name[:1].isupper() and self.symtype(T) is not None:
                kind = ("sym", name) + self.symtype(T)
                phase = 1
                self.syms.append(len(self.ctx))
            else:
                break
            self.ctx.append(kind)
            e = f["body"]
        self.body = self.formula(e, self.ctx)

    def is_type_sort(self, T):
        k, f = self.X.e(T)
        return k == "sort" and self.X.levels.get(f) == 1

    def is_inhabited(self, T):
        head, args = self.X.spine(T)
        return self.X.const(head) == "Inhabited" and len(args) == 1 and self.sortref(args[0], self.ctx) is not None

    def sortref(self, T, ctx):
        k, f = self.X.e(T)
        if k == "bvar" and ctx[len(ctx) - 1 - f][0] == "sort":
            j = len(ctx) - 1 - f
            return ("U",) if ctx[j][1] == "U" else ("sort", ("L", j))
        if k == "const" and self.X.name(f["name"]) == "Int":
            return ("int",)
        return None

    def symtype(self, T):  # (argsorts, result) of a symbol's type, or None when T is no symbol's type
        args, ctx = [], list(self.ctx)
        while True:
            k, f = self.X.e(T)
            if k == "sort" and self.X.levels.get(f) == 0:
                return tuple(args), ("o",)
            s = self.sortref(T, ctx)
            if s is not None:
                return tuple(args), s
            if k != "forallE" or self.X.mentions(f["body"], 0):
                return None
            a = self.sortref(f["type"], ctx)
            if a is None:
                return None
            args.append(a)
            ctx.append(("arg",))
            T = f["body"]

    def formula(self, e, ctx):
        X = self.X
        k, f = X.e(e)
        n = sum(1 for c in ctx if c[0] == "var")
        if k == "forallE":
            s = self.sortref(f["type"], ctx)
            if s is not None:
                return ("all", s, self.formula(f["body"], ctx + [("var", n)]))
            if X.mentions(f["body"], 0):
                raise Mismatch("a dependent arrow that is no quantifier")
            return ("imp", self.formula(f["type"], ctx), self.formula(f["body"], ctx + [("imp",)]))
        head, args = X.spine(e)
        c = X.const(head)
        if c in ("True", "False") and not args:
            return (c.lower(),)
        if c == "Not" and len(args) == 1:
            return ("not", self.formula(args[0], ctx))
        if c in ("And", "Or", "Iff") and len(args) == 2:
            return ({"And": "and", "Or": "or", "Iff": "iff"}[c], self.formula(args[0], ctx), self.formula(args[1], ctx))
        if c in ("Eq", "Ne") and len(args) == 3:
            if self.sortref(args[0], ctx) is None:
                raise Mismatch(f"{c} at a type that is no sort")
            return ({"Eq": "eq", "Ne": "ne"}[c], self.term(args[1], ctx), self.term(args[2], ctx))
        if c == "Exists" and len(args) == 2:
            s = self.sortref(args[0], ctx)
            lk, lf = X.e(args[1])
            if s is None or lk != "lam" or self.sortref(lf["type"], ctx) != s:
                raise Mismatch("Exists over no sort, or not of a lambda over it")
            return ("ex", s, self.formula(lf["body"], ctx + [("var", n)]))
        if c in INT_RELS and len(args) == 4:
            op, inst = INT_RELS[c]
            if X.const(args[0]) != "Int" or not X.closed(args[1]) or X.show(args[1]) != inst:
                raise Mismatch(f"{c} at {X.show(args[0])} by {X.show(args[1])}")
            return ("ipred", op, (self.term(args[2], ctx), self.term(args[3], ctx)))
        hk, hf = X.e(head)
        if hk == "bvar":
            j = len(ctx) - 1 - hf
            if ctx[j][0] == "sym" and ctx[j][3] == ("o",) and len(ctx[j][2]) == len(args):
                return ("pred", ("L", j), tuple(self.term(a, ctx) for a in args))
        raise Mismatch(f"no formula: {X.show(e)}")

    def term(self, e, ctx):
        X = self.X
        head, args = X.spine(e)
        hk, hf = X.e(head)
        if hk == "bvar":
            j = len(ctx) - 1 - hf
            if ctx[j][0] == "var" and not args:
                return ("var", ctx[j][1])
            if ctx[j][0] == "sym" and ctx[j][3] != ("o",) and len(ctx[j][2]) == len(args):
                return ("fun", ("L", j), tuple(self.term(a, ctx) for a in args))
        c = X.const(head)
        if c == "OfNat.ofNat" and len(args) == 3 and X.const(args[0]) == "Int" and X.e(args[1])[0] == "natVal":
            v = X.e(args[1])[1]
            if not X.closed(args[2]) or X.show(args[2]) != f"(instOfNat {v})":
                raise Mismatch(f"an Int numeral by {X.show(args[2])}")
            return ("int", int(v))
        if c in INT_OPS:
            op, ntypes, inst = INT_OPS[c]
            arity = 1 if op == "$uminus" else 2
            if len(args) == ntypes + 1 + arity:
                if any(X.const(t) != "Int" for t in args[:ntypes]) or not X.closed(args[ntypes]) or X.show(args[ntypes]) != inst:
                    raise Mismatch(f"{c} at {[X.show(t) for t in args[:ntypes]]} by {X.show(args[ntypes])}")
                return ("ifun", op, tuple(self.term(a, ctx) for a in args[ntypes + 1:]))
        raise Mismatch(f"no term: {X.show(e)}")


# ---- the problem --------------------------------------------------------------------------------------------------

TOKEN = re.compile(r"""(?P<skip>\s+|%[^\n]*|/\*.*?\*/)|(?P<sq>'(?:[^'\\]|\\.)*')|(?P<dq>"(?:[^"\\]|\\.)*")
  |(?P<num>[+-]?[0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?(?:/[0-9]+)?)|(?P<word>\$\$?[A-Za-z_][A-Za-z0-9_]*|[A-Za-z_][A-Za-z0-9_]*)
  |(?P<op><=>|<~>|=>|<=|~\||~&|!=|[()\[\],.:!?~&|=*>])""", re.S | re.X)
HEAD = re.compile(r"(?m)^[ \t]*(fof|tff|thf|cnf)\(\s*('(?:[^'\\]|\\.)*'|[A-Za-z0-9_$]+)\s*,\s*([a-z_]+)\s*,")
INCLUDE = re.compile(r"(?m)^[ \t]*include\(\s*'([^']+)'")


def tokens(text):
    out, i = [], 0
    while i < len(text):
        m = TOKEN.match(text, i)
        if not m:
            raise SyntaxError(f"at {text[i:i + 30]!r}")
        if m.lastgroup != "skip":
            out.append((m.lastgroup, m.group()))
        i = m.end()
    return out


class Problem:
    """A TPTP problem: its annotated formulas, found by their heads, each read by TptpReader."""
    files, parsed = {}, {}

    def __init__(self, path):
        self.entries = []          # (language, name, role, text, start, end)
        self.read(path)
        self.langs = {e[0] for e in self.entries}
        self.typed = "tff" in self.langs
        self.conj = [e for e in self.entries if e[2] == "conjecture"]
        self.axioms = [e for e in self.entries if e[2] not in ("type", "conjecture")]
        self.by_shape = collections.defaultdict(list)
        if not self.langs - {"fof", "tff"}:
            for e in self.axioms:
                self.by_shape[shape(self.formula(e))].append(e)
        self.decl = {}
        if self.typed:
            for e in self.entries:
                if e[2] == "type":
                    t = tokens(e[3][e[4]:e[5]])
                    body = t[6:]
                    depth, j = 0, 0
                    while depth or body[j][1] not in (",", ")"):
                        depth += 1 if body[j][1] in "([" else -1 if body[j][1] in ")]" else 0
                        j += 1
                    body = [x for x in body[:j] if x[1] not in ("(", ")")]
                    if len(body) >= 3 and body[1][1] == ":":
                        self.decl[body[0][1]] = [x[1] for x in body[2:] if x[1] not in ("*", ">")]

    def read(self, path):
        if path not in Problem.files:
            text = open(path, errors="replace").read()
            heads = list(HEAD.finditer(text))
            own = [(m.group(1), m.group(2), m.group(3), text, m.start(),
                    heads[k + 1].start() if k + 1 < len(heads) else len(text)) for k, m in enumerate(heads)]
            incs = [m.group(1) for m in INCLUDE.finditer(text)]
            Problem.files[path] = (own, [i if os.path.isabs(i) else os.path.join(os.path.dirname(path), i) for i in incs])
        own, incs = Problem.files[path]
        for i in incs:
            self.read(i)
        self.entries += own

    def formula(self, e):
        key = (id(e[3]), e[4], self.typed)
        if key not in self.parsed:
            t = tokens(e[3][e[4]:e[5]])
            body = t[6:]
            depth, j = 0, 0
            while depth or body[j][1] not in (",", ")"):
                depth += 1 if body[j][1] in "([" else -1 if body[j][1] in ")]" else 0
                j += 1
            self.parsed[key] = TptpReader(body[:j], self.typed).whole()
        return self.parsed[key]


class TptpReader:
    BINARY = {"=>", "<=", "<=>", "<~>", "~|", "~&"}

    def __init__(self, t, typed):
        self.t, self.i, self.typed = t, 0, typed

    def peek(self):
        return self.t[self.i][1] if self.i < len(self.t) else None

    def take(self, want=None):
        tok = self.t[self.i]
        if want is not None and tok[1] != want:
            raise SyntaxError(f"{want!r} expected, {tok[1]!r} found")
        self.i += 1
        return tok

    def whole(self):
        f = self.formula([])
        if self.i != len(self.t):
            raise SyntaxError(f"left over: {' '.join(x[1] for x in self.t[self.i:self.i + 8])}")
        return f

    def formula(self, scope):
        a = self.unitary(scope)
        op = self.peek()
        if op in ("&", "|"):
            parts = [a]
            while self.peek() == op:
                self.take()
                parts.append(self.unitary(scope))
            out = parts[-1]
            for p in reversed(parts[:-1]):
                out = ("and" if op == "&" else "or", p, out)
            return out
        if op in self.BINARY:
            self.take()
            b = self.unitary(scope)
            return {"=>": ("imp", a, b), "<=": ("imp", b, a), "<=>": ("iff", a, b), "<~>": ("not", ("iff", a, b)),
                    "~|": ("not", ("or", a, b)), "~&": ("not", ("and", a, b))}[op]
        return a

    def unitary(self, scope):
        v = self.peek()
        if v in ("!", "?"):
            self.take()
            self.take("[")
            vs = []
            while True:
                name = self.take()[1]
                sort = ("U",)
                if self.peek() == ":":
                    self.take()
                    w = self.take()[1]
                    sort = {"$i": ("U",), "$int": ("int",)}.get(w, ("sort", ("T", w, "sort")))
                vs.append((name, sort))
                if self.peek() != ",":
                    break
                self.take()
            self.take("]")
            self.take(":")
            body = self.unitary(scope + [n for n, _ in vs])
            for name, sort in reversed(vs):
                body = ("all" if v == "!" else "ex", sort, body)
            return body
        if v == "~":
            self.take()
            return ("not", self.unitary(scope))
        if v == "(":
            self.take()
            f = self.formula(scope)
            self.take(")")
            return f
        lhs = self.term(scope)
        if self.peek() in ("=", "!="):
            op = self.take()[1]
            return ("eq" if op == "=" else "ne", lhs, self.term(scope))
        if lhs[0] == "fun" and lhs[1][1] in ("$true", "$false") and not lhs[2]:
            return (lhs[1][1][1:],)
        if lhs[0] == "fun" and lhs[1][1] in ("$less", "$lesseq", "$greater", "$greatereq"):
            return ("ipred", lhs[1][1], lhs[2])
        if lhs[0] != "fun" or lhs[1][1].startswith("$"):
            raise SyntaxError(f"no atom: {lhs}")
        return ("pred",) + lhs[1:]

    def term(self, scope):
        k, v = self.take()
        if k == "num":
            if self.typed and re.fullmatch(r"[+-]?[0-9]+", v):  # TFF: an integer
                n = int(v)
                return ("int", n) if n >= 0 else ("ifun", "$uminus", (("int", -n),))
            return ("fun", ("T", "num", v), ())
        if k == "dq":
            return ("fun", ("T", "dq", v), ())
        if v[0].isupper() or v[0] == "_":
            if v not in scope:
                raise SyntaxError(f"free variable {v}")
            return ("var", len(scope) - 1 - scope[::-1].index(v))
        args = []
        if self.peek() == "(":
            self.take()
            while True:
                args.append(self.term(scope))
                if self.peek() != ",":
                    break
                self.take()
            self.take(")")
        if v in ("$sum", "$difference", "$product", "$uminus"):
            return ("ifun", v, tuple(args))
        return ("fun", ("T", v, len(args)), tuple(args))


# ---- the comparison -----------------------------------------------------------------------------------------------

class Renaming:
    """The assignment of the problem's symbols to the theorem's.  The theorem holds for every value of its symbols, so any
    assignment will do, two symbols to one included; one to one is tried first (injective), as it is what tptp2lean.py
    meant."""
    def __init__(self, lean, prob, injective=True):
        self.lean, self.prob, self.injective, self.fwd, self.back = lean, prob, injective, {}, {}

    def copy(self):
        r = Renaming(self.lean, self.prob, self.injective)
        r.fwd, r.back = dict(self.fwd), dict(self.back)
        return r

    def pair(self, l, t, kind, nargs):
        if l in self.fwd:
            return self.fwd[l] == t
        if self.injective and t in self.back:
            return False
        entry = self.lean.ctx[l[1]]
        if entry[0] == "sort":
            ok = kind == "sort"
        else:
            argsorts, res = entry[2], entry[3]
            ok = entry[0] == "sym" and len(argsorts) == nargs and (kind == "pred") == (res == ("o",))
            if ok and self.prob.typed and t[1] in self.prob.decl:
                want = [{"$i": ("U",), "$int": ("int",), "$o": ("o",)}.get(w, ("sort", ("T", w, "sort")))
                        for w in self.prob.decl[t[1]]]
                have = list(argsorts) + [res]
                ok = len(want) == len(have) and all(self.same_sort(h, w) for h, w in zip(have, want))
        if ok:
            self.fwd[l], self.back[t] = t, l
        return ok

    def same_sort(self, a, b):
        if a[0] != b[0]:
            return False
        return self.pair(a[1], b[1], "sort", 0) if a[0] == "sort" else True

    def same(self, a, b):  # a from the Lean side, b from the TPTP side
        if a[0] != b[0]:
            return False
        k = a[0]
        if k in ("all", "ex"):
            return self.same_sort(a[1], b[1]) and self.same(a[2], b[2])
        if k == "not":
            return self.same(a[1], b[1])
        if k in ("and", "or", "imp", "iff", "eq", "ne"):
            return self.same(a[1], b[1]) and self.same(a[2], b[2])
        if k in ("true", "false"):
            return True
        if k in ("pred", "fun"):
            return (len(a[2]) == len(b[2]) and self.pair(a[1], b[1], k, len(a[2]))
                    and all(self.same(x, y) for x, y in zip(a[2], b[2])))
        if k in ("ipred", "ifun"):
            return a[1] == b[1] and len(a[2]) == len(b[2]) and all(self.same(x, y) for x, y in zip(a[2], b[2]))
        if k in ("var", "int"):
            return a[1] == b[1]
        raise ValueError(k)


def shape(f):  # a formula with its symbols forgotten: the index from a hypothesis to the axioms it may be
    if isinstance(f, tuple):
        if f and f[0] in ("L", "T"):
            return "s"
        return tuple(shape(x) for x in f)
    return f


def compare(lean, prob, negate_conj=False, drop=(), prefer=()):
    """(agrees, the axioms or what differs, whether the assignment is one to one)"""
    ok, res = compare_by(lean, prob, negate_conj, drop, prefer, True)
    if ok:
        return ok, res, True
    return compare_by(lean, prob, negate_conj, drop, prefer, False) + (False,)


def compare_by(lean, prob, negate_conj, drop, prefer, injective):
    """(True, [the axioms h1..hk are, as entries]) when the statement is the problem's, else (False, what differs).  drop: axioms
    (their formulas) the problem is taken without; prefer: names tried first where a hypothesis matches several axioms
    (SigmaKEE gives some formulas the same name, and some are written twice)."""
    if len(prob.conj) > 1:
        return False, "more than one conjecture"
    conj = prob.formula(prob.conj[0]) if prob.conj else ("false",)
    if negate_conj:
        conj = ("not", conj)
    ants, g = [], lean.body
    while g[0] == "imp":
        ants.append(g[1])
        g = g[2]
    why = f"the goal is not the conjecture {prob.conj[0][1] if prob.conj else '(none: False)'}"
    for k in range(len(ants), -1, -1):  # the most hypotheses first
        goal = g
        for a in reversed(ants[k:]):
            goal = ("imp", a, goal)
        r = Renaming(lean, prob, injective)
        if not r.same(goal, conj):
            continue
        found = search(ants[:k], r, prob, drop, set(prefer))
        if found is not None:
            return True, found
        why = f"of {k} hypotheses, not each an axiom of the problem"
    return False, why


def search(hyps, r, prob, drop, prefer):
    """An axiom for each hypothesis, under one assignment: the most constrained hypothesis first, and back when stuck."""
    if not hyps:
        return []
    best = None
    for i, h in enumerate(hyps):
        cands = []
        for e in sorted(prob.by_shape.get(shape(h), []), key=lambda e: e[1] not in prefer):
            f = prob.formula(e)
            if f in drop:
                continue
            r2 = r.copy()
            if r2.same(h, f):
                cands.append((e, r2))
        if not cands:
            return None
        if best is None or len(cands) < len(best[1]):
            best = (i, cands)
        if len(cands) == 1:
            break
    i, cands = best
    for e, r2 in cands:
        rest = search(hyps[:i] + hyps[i + 1:], r2, prob, drop, prefer)
        if rest is not None:
            return rest[:i] + [e] + rest[i:]
    return None


def main(argv):
    X = Export(argv[1])
    runs = {}
    for line in open(f"{V}/logs/vampire/runs.jsonl"):
        r = json.loads(line)
        runs[(r["set"], r["test"])] = r
    srcs = {}
    for line in open(f"{V}/export/list.tsv"):
        s, t, f = line.rstrip("\n").split("\t")
        srcs["tq_" + re.sub(r"[^A-Za-z0-9_]", "_", f"{s}_{t}")] = (s, t, f)
    show = argv[argv.index("--show") + 1] if "--show" in argv else None
    problems, leans, good, bad = {}, {}, 0, 0
    for n in sorted(X.thms):
        s, t, f = srcs[n]
        run = runs.get((s, t))
        if run is None:
            print(f"{n:32} not read: " + ("THF, encoded by hand" if s == "thf" else f"no Vampire run of {s}/{t}"))
            continue
        path = run["problem"]
        if path not in problems:
            problems[path] = Problem(path)
        prob = problems[path]
        if prob.langs - {"fof", "tff"}:
            print(f"{n:32} not read: the problem is {sorted(prob.langs)}")
            continue
        try:
            lean = LeanSide(X, X.thms[n])
            ok, res, inj = compare(lean, prob, prefer=run["used_input_formulas"])
        except (Mismatch, SyntaxError) as e:
            print(f"{n:32} DISAGREES: {e}")
            bad += 1
            continue
        if show == n:
            print("  body", lean.body)
            for e in prob.conj:
                print("  conjecture", prob.formula(e))
        if not ok:
            print(f"{n:32} DISAGREES: {res}")
            bad += 1
            continue
        leans[n] = (lean, path, res)
        used = [e for e in prob.axioms if e[1] in set(run["used_input_formulas"])]
        same = sorted(repr(prob.formula(e)) for e in used) == sorted(repr(prob.formula(e)) for e in res)
        print(f"{n:32} agrees: {len(lean.syms)} symbols; {len(res)} hypothes{'i' if len(res) == 1 else 'e'}s, the axioms "
              f"{', '.join(e[1] for e in res) or '-'}; the goal "
              f"{'the conjecture ' + prob.conj[0][1] if prob.conj else 'False'}"
              + ("; the axioms Vampire's proof used" if same else f"; Vampire's proof used {sorted(e[1] for e in used)}")
              + ("" if inj else "; two of the theorem's symbols assigned one of the problem's"))
        good += 1
    print(f"{good} statements are their problems', {bad} disagree")
    # the controls: a statement may hold of another problem too (TQROW_noDomain's is TQROW_withDomain's problem as well, and
    # a hypothesis whose symbols occur nowhere else matches any axiom of its form), so the other problem is one whose
    # conjecture has another form, and the axioms taken away are all those the first hypothesis matches by itself
    names = sorted(leans)
    caught, tried = 0, 0
    conj_shape = lambda q: shape(q.formula(q.conj[0])) if q.conj else None
    for i, n in enumerate(names):
        lean, path, res = leans[n]
        prob = problems[path]
        other = next(leans[m][1] for m in names[i + 1:] + names[:i]
                     if srcs[m][1] != srcs[n][1] and conj_shape(problems[leans[m][1]]) != conj_shape(prob))
        controls = [("another test's problem", problems[other], {}),
                    ("its conjecture negated", prob, {"negate_conj": True})]
        if res:
            first = lean.body[1]  # h1
            drop = tuple(prob.formula(e) for e in prob.by_shape.get(shape(first), [])
                         if Renaming(lean, prob, False).same(first, prob.formula(e)))
            controls.append((f"its problem without the {len(drop)} axioms its first hypothesis matches", prob, {"drop": drop}))
        for what, q, kw in controls:
            tried += 1
            try:
                ok, out, _ = compare(lean, q, **kw)
            except (Mismatch, SyntaxError) as e:
                ok, out = False, str(e)
            if ok:
                print(f"CONTROL NOT CAUGHT: {n} against {what}: {out}")
            else:
                caught += 1
    print(f"controls: {caught} of {tried} disagree (each statement against another test's problem, with a conjecture of "
          f"another form; against its own, the conjecture negated; and against its own without the axioms its first "
          f"hypothesis matches)")
    return 0 if bad == 0 and caught == tried else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
