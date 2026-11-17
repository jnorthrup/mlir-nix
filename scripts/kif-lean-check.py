#!/usr/bin/env python3
"""kif-lean-check.py EXPORT DUMP [--rules] [--mutate premise|binding|statement OUT] [--nanoda-config OUT]

Reads the theorem `mlnix-kif --chase --lean EXPORT` wrote (lean4export's NDJSON; lib/Dialect/KifLean.cpp) and checks what it
STATES against the chase's closure, DUMP (`mlnix-kif --chase --dump` on the same files): its fact hypotheses are exactly the
asserted facts, its lets and its Pack exactly the derived facts, and each let applies the rule the dump names to proofs of
the premises the dump lists, in order.  It also checks that the file declares nothing but that theorem: no axiom, and no
constant in any expression.  Whether the proofs are proofs is a Lean kernel's to check (nanoda_bin, con-leche, con-ron).

--rules            print each rule hypothesis decoded back to KIF
--mutate KIND OUT  write a copy with one proof broken, a control a kernel must reject:
                     premise    the first let that uses an asserted fact applies its rule to a proof of another fact
                     binding    the first let with a variable binds it to another term
                     statement  the first let claims the next let's fact
--nanoda-config OUT  write a nanoda_bin config for EXPORT that permits no axiom at all
"""
import json, sys


def load(path):
    names, exprs, decls, lines = {0: ()}, {}, [], {"meta": None, "levels": []}
    for line in open(path, encoding="utf-8"):
        o = json.loads(line)
        if "in" in o:
            if "str" in o:
                names[o["in"]] = names[o["str"]["pre"]] + (o["str"]["str"],)
            else:
                names[o["in"]] = names[o["num"]["pre"]] + (o["num"]["i"],)
        elif "il" in o:
            lines["levels"].append(o)
        elif "ie" in o:
            k = next(x for x in o if x != "ie")
            exprs[o["ie"]] = [k, o[k]]
        elif "meta" in o:
            lines["meta"] = o
        else:
            decls.append(o)
    return names, exprs, decls, lines


def show(t):
    return t if isinstance(t, str) else "(" + " ".join(show(x) for x in t) + ")"


class Theorem:
    def __init__(self, path):
        self.names, self.exprs, self.decls, self.lines = load(path)
        self.errors = []
        if len(self.decls) != 1 or "thm" not in self.decls[0]:
            raise SystemExit(f"{path}: declares {[next(iter(d)) for d in self.decls]}, not one theorem")
        self.thm = self.decls[0]["thm"]
        consts = [i for i, (k, _) in self.exprs.items() if k == "const"]
        if consts:
            raise SystemExit(f"{path}: {len(consts)} expressions name a constant; the theorem should use none")

    def kind(self, e):
        return self.exprs[e][0]

    def spine(self, e):
        args = []
        while self.kind(e) == "app":
            f = self.exprs[e][1]
            args.append(f["arg"])
            e = f["fn"]
        return e, args[::-1]

    def binder(self, e, stack):
        """The stack entry a bvar refers to."""
        if self.kind(e) != "bvar":
            return None
        i = self.exprs[e][1]
        return stack[len(stack) - 1 - i] if i < len(stack) else None

    def term(self, e, stack):
        b = self.binder(e, stack)
        if b is not None:
            if b["kind"] in ("atom", "var"):
                return b["text"]
            if b["kind"] == "nil":
                return []
            raise ValueError(f"a term refers to {b['kind']}")
        head, args = self.spine(e)
        hb = self.binder(head, stack)
        if hb is None or hb["kind"] != "cons" or len(args) != 2:
            raise ValueError("a term that is neither an atom, nil nor cons x xs")
        rest = self.term(args[1], stack)
        if isinstance(rest, str):
            raise ValueError("cons onto an atom")
        return [self.term(args[0], stack)] + rest

    def holds(self, e, stack):
        head, args = self.spine(e)
        hb = self.binder(head, stack)
        if hb is None or hb["kind"] != "Holds" or len(args) != 1:
            raise ValueError("not Holds t")
        return self.term(args[0], stack)

    def premise(self, e, stack):
        head, args = self.spine(e)
        hb = self.binder(head, stack)
        if hb and hb["kind"] == "Same" and len(args) == 2:
            return ["equal", self.term(args[0], stack), self.term(args[1], stack)]
        return self.holds(e, stack)

    FIXED = {("Term",): "Term", ("Holds",): "Holds", ("nil",): "nil", ("cons",): "cons", ("Same",): "Same",
             ("same",): "same", ("Sub",): "Sub", ("sub_trans",): "sub_trans", ("inst_up",): "inst_up",
             ("Pack",): "Pack", ("pack",): "pack"}

    def decode(self):
        """The hypotheses, the lets and the conclusion, decoded."""
        stack, e = [], self.thm["type"]
        self.hyps = []
        while self.kind(e) == "forallE":
            f = self.exprs[e][1]
            name = self.names[f["name"]]
            b = {"name": name, "type": f["type"]}
            if name in self.FIXED:
                b["kind"] = self.FIXED[name]
            elif len(name) == 2 and name[0] in ("a", "f", "r", "o"):
                b["kind"] = {"a": "atom", "f": "fact", "r": "rule", "o": "edge"}[name[0]]
                b["text"] = name[1]
            else:
                raise SystemExit(f"a hypothesis named {name}")
            if b["kind"] == "fact":
                b["stmt"] = self.holds(f["type"], stack)
            elif b["kind"] == "rule":
                b["rule"] = self.rule(f["type"], stack)
            stack.append(b)
            self.hyps.append(b)
            e = f["body"]
        cb = self.binder(e, stack)
        if cb is None or cb["kind"] != "Pack":
            raise SystemExit("the theorem does not conclude Pack")
        self.B = len(stack)
        pack = next(b for b in stack if b["kind"] == "pack")
        self.packed, t, inner = [], pack["type"], stack[: stack.index(pack)]
        while self.kind(t) == "forallE":
            f = self.exprs[t][1]
            self.packed.append(show(self.holds(f["type"], inner)))
            inner = inner + [{"kind": "hyp"}]
            t = f["body"]
        # the proof: the same binders as lambdas, then the lets
        v = self.thm["value"]
        for b in self.hyps:
            if self.kind(v) != "lam" or self.exprs[v][1]["type"] != b["type"] or self.names[self.exprs[v][1]["name"]] != b["name"]:
                raise SystemExit("the proof's binders are not the statement's")
            v = self.exprs[v][1]["body"]
        self.lets, lstack = [], list(stack)
        while self.kind(v) == "letE":
            f = self.exprs[v][1]
            stmt = self.holds(f["type"], lstack)
            proof = self.proof(f["value"], lstack)
            self.lets.append({"stmt": stmt, "node": v, "depth": len(lstack), **proof})
            lstack.append({"kind": "let", "stmt": stmt})
            v = f["body"]
        head, args = self.spine(v)
        hb = self.binder(head, lstack)
        if hb is None or hb["kind"] != "pack":
            raise SystemExit("the proof does not end in pack d.1 .. d.n")
        if [show(self.binder(a, lstack)["stmt"]) for a in args] != [show(l["stmt"]) for l in self.lets]:
            raise SystemExit("pack is not applied to the lets in order")
        self.stack = stack

    def rule(self, t, stack):
        """∀ vars, H p1 → .. → H pn → Holds c, as (vars, premises, consequent)."""
        vars_, prem, inner = [], [], list(stack)
        while self.kind(t) == "forallE":
            f = self.exprs[t][1]
            tb = self.binder(f["type"], inner)
            if tb is not None and tb["kind"] == "Term" and not prem:
                text = self.names[f["name"]][-1]
                vars_.append(text)
                inner.append({"kind": "var", "text": text})
            else:
                prem.append(self.premise(f["type"], inner))
                inner.append({"kind": "hyp"})
            t = self.exprs[t][1]["body"]
        return vars_, prem, self.holds(t, inner)

    def proof(self, e, stack):
        """A let's value: the rule binder, its terms, and what each premise's proof proves."""
        head, args = self.spine(e)
        rb = self.binder(head, stack)
        if rb is None or rb["kind"] != "rule":
            raise ValueError("a let's value does not apply a rule hypothesis")
        m = len(rb["rule"][0])
        terms = [self.term(a, stack) for a in args[:m]]
        facts = []
        for a in args[m:]:
            b = self.binder(a, stack)
            if b is not None and b["kind"] in ("fact", "let"):
                facts.append(show(b["stmt"]))
                continue
            h, xs = self.spine(a)
            hb = self.binder(h, stack)
            if hb and hb["kind"] == "same" and len(xs) == 1:
                continue  # (equal t t): no fact
            if hb and hb["kind"] == "inst_up" and len(xs) == 5:
                fb = self.binder(xs[3], stack)
                facts.append(show(fb["stmt"]))
                continue
            raise ValueError("a premise's proof is neither a fact, a let, same t nor inst_up")
        return {"rule": rb["text"], "terms": terms, "facts": facts}


def check(th, dump_path):
    asserted, derived = [], {}
    for line in open(dump_path, encoding="utf-8"):
        parts = line.rstrip("\n").split("\t")
        if parts[1] == "-":
            asserted.append(parts[0])
        else:
            derived[parts[0]] = (int(parts[1].rsplit("#", 1)[1]), parts[2:])
    facts = [show(b["stmt"]) for b in th.hyps if b["kind"] == "fact"]
    errs = []
    if sorted(facts) != sorted(asserted):
        errs.append(f"the fact hypotheses ({len(facts)}) are not the dump's asserted facts ({len(asserted)}): "
                    f"{sorted(set(facts) ^ set(asserted))[:5]}")
    lets = [show(l["stmt"]) for l in th.lets]
    if sorted(lets) != sorted(derived):
        errs.append(f"the lets ({len(lets)}) are not the dump's derived facts ({len(derived)}): {sorted(set(lets) ^ set(derived))[:5]}")
    if th.packed != lets:
        errs.append("Pack does not list the lets' facts in order")
    for l in th.lets:
        s = show(l["stmt"])
        if s in derived and (l["rule"], l["facts"]) != (derived[s][0], derived[s][1]):
            errs.append(f"{s}: by r.{l['rule']} from {l['facts']}, the dump has #{derived[s][0]} from {derived[s][1]}")
    return errs


def summary(th, path):
    count = lambda k: sum(1 for b in th.hyps if b["kind"] == k)
    return (f"{path.rsplit('/', 1)[-1]}: one theorem, no axiom, no constant; {th.B} hypotheses ({count('atom')} atoms, "
            f"{count('fact')} facts, {count('rule')} rules, {count('edge')} ontology edges); {len(th.lets)} lets")


# ---- controls: one proof broken, the file written again in dependency order

def mutate(th, kind):
    ex = th.exprs
    new = lambda k, f: (ex.__setitem__(max(ex) + 1, [k, f]), max(ex))[1]

    def bvar(depth, q):
        return new("bvar", depth - 1 - q)

    def encode(t, depth):
        q = {b["kind"]: i for i, b in enumerate(th.stack) if b["kind"] in ("nil", "cons", "Holds")}
        atoms = {b["text"]: i for i, b in enumerate(th.stack) if b["kind"] == "atom"}
        if isinstance(t, str):
            return bvar(depth, atoms[t])
        e = bvar(depth, q["nil"])
        for x in reversed(t):
            e = new("app", {"fn": new("app", {"fn": bvar(depth, q["cons"]), "arg": encode(x, depth)}), "arg": e})
        return e

    def respine(e, i, arg):  # the spine of e with its i-th argument replaced
        head, args = th.spine(e)
        args[i] = arg
        for a in args:
            head = new("app", {"fn": head, "arg": a})
        return head

    holds_q = next(i for i, b in enumerate(th.stack) if b["kind"] == "Holds")
    for li, l in enumerate(th.lets):
        f = ex[l["node"]][1]
        head, args = th.spine(f["value"])
        m = len(th.binder(head, th.stack + [{"kind": "let"}] * li)["rule"][0])
        if kind == "premise":
            stack = th.stack + [{"kind": "let", "stmt": x["stmt"]} for x in th.lets[:li]]
            for i in range(m, len(args)):
                b = th.binder(args[i], stack)
                if b is not None and b["kind"] == "fact":
                    other = next(q for q, c in enumerate(stack) if c["kind"] == "fact" and c["stmt"] != b["stmt"])
                    f["value"] = respine(f["value"], i, bvar(l["depth"], other))
                    return f"{show(l['stmt'])}: premise {i - m + 1} is a proof of {show(stack[other]['stmt'])}"
        elif kind == "binding" and m:
            atoms = [b["text"] for b in th.stack if b["kind"] == "atom"]
            other = next(a for a in atoms if a != l["terms"][0])
            f["value"] = respine(f["value"], 0, encode(other, l["depth"]))
            return f"{show(l['stmt'])}: its rule's first variable is bound to {other}, not {show(l['terms'][0])}"
        elif kind == "statement" and li + 1 < len(th.lets):
            claim = th.lets[li + 1]["stmt"]
            f["type"] = new("app", {"fn": bvar(l["depth"], holds_q), "arg": encode(claim, l["depth"])})
            return f"the proof of {show(l['stmt'])} claims {show(claim)}"
    raise SystemExit(f"no let to break by {kind}")


def write(th, out):
    ex, order, ids = th.exprs, [], {}
    kids = lambda k, f: [f[x] for x in {"app": ("fn", "arg"), "forallE": ("type", "body"), "lam": ("type", "body"),
                                       "letE": ("type", "value", "body")}.get(k, ())]
    stack = [(th.thm["value"], False), (th.thm["type"], False)]
    while stack:
        e, done = stack.pop()
        if e in ids:
            continue
        if done:
            ids[e] = len(order)
            order.append(e)
            continue
        stack.append((e, True))
        stack.extend((c, False) for c in kids(*ex[e]) if c not in ids)
    with open(out, "w", encoding="utf-8") as o:
        o.write(json.dumps(th.lines["meta"], separators=(",", ":")) + "\n")
        for i in sorted(th.names):
            if i:
                n = th.names[i]
                pre = next(j for j in th.names if th.names[j] == n[:-1])
                rec = {"str": {"pre": pre, "str": n[-1]}} if isinstance(n[-1], str) else {"num": {"i": n[-1], "pre": pre}}
                o.write(json.dumps({"in": i, **rec}, separators=(",", ":"), ensure_ascii=False) + "\n")
        for lv in th.lines["levels"]:
            o.write(json.dumps(lv, separators=(",", ":")) + "\n")
        for e in order:
            k, f = ex[e]
            if isinstance(f, dict):
                f = {x: (ids[y] if x in ("fn", "arg", "type", "body", "value") else y) for x, y in f.items()}
            o.write(json.dumps({k: f, "ie": ids[e]}, separators=(",", ":")) + "\n")
        thm = dict(th.thm, type=ids[th.thm["type"]], value=ids[th.thm["value"]])
        o.write(json.dumps({"thm": thm}, separators=(",", ":")) + "\n")


def main(argv):
    if len(argv) < 3:
        raise SystemExit(__doc__)
    export, dump = argv[1], argv[2]
    th = Theorem(export)
    if "--nanoda-config" in argv:
        json.dump({"export_file_path": export, "use_stdin": False, "permitted_axioms": [], "unpermitted_axiom_hard_error": True,
                   "nat_extension": False, "string_extension": False, "print_success_message": True},
                  open(argv[argv.index("--nanoda-config") + 1], "w"), indent=1)
    th.decode()
    if "--mutate" in argv:
        i = argv.index("--mutate")
        print(mutate(th, argv[i + 1]))
        write(th, argv[i + 2])
        return 0
    print(summary(th, export))
    if "--rules" in argv:
        for b in th.hyps:
            if b["kind"] == "rule":
                vs, prem, c = b["rule"]
                ante = show(prem[0]) if len(prem) == 1 else "(and " + " ".join(show(p) for p in prem) + ")"
                print(f"r.{b['text']}: forall {' '.join(vs) or '-'}: (=> {ante} {show(c)})")
    errs = check(th, dump)
    for e in errs[:10]:
        print("DISAGREES:", e)
    if errs:
        return 1
    print(f"agrees with the dump: {sum(1 for b in th.hyps if b['kind'] == 'fact')} asserted facts, {len(th.lets)} derived "
          f"facts, each by the dump's rule from the dump's premises")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
