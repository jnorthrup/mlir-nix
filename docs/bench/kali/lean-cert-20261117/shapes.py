#!/usr/bin/env python3
"""Which shape costs the kernels: a chain of n lets, or one application to n arguments.  Writes two lean4export files per n:
  lets-n: ∀ (Term : Type) (Holds : Term → Prop) (a : Term) (f : Holds a) (r : ∀ x, Holds x → Holds x), Holds a
          := fun .. => let d0 := r a f; let d1 := r a d0; ..; d(n-1)
  app-n:  ∀ (Term) (Holds) (a) (f : Holds a) (Pack : Prop) (pack : Holds a → .. (n times) → Pack), Pack := fun .. => pack f .. f
"""
import sys

class W:
    def __init__(self, path):
        self.o = open(path, "w"); self.n = 0; self.names = {}; self.memo = {}
        self.o.write('{"meta":{"exporter":{"name":"shapes","version":"1"},"format":{"version":"3.1.0"},"lean":{"githash":"","version":""}}}\n{"il":1,"succ":0}\n')
    def name(self, s):
        if s not in self.names:
            self.names[s] = len(self.names) + 1
            self.o.write('{"in":%d,"str":{"pre":0,"str":"%s"}}\n' % (self.names[s], s))
        return self.names[s]
    def e(self, key, rec):
        if key not in self.memo:
            self.memo[key] = self.n; self.o.write(rec % self.n + "\n"); self.n += 1
        return self.memo[key]
    def sort(self, l): return self.e(("s", l), '{"ie":%%d,"sort":%d}' % l)
    def bvar(self, i): return self.e(("b", i), '{"bvar":%d,"ie":%%d}' % i)
    def app(self, f, a): return self.e(("a", f, a), '{"app":{"arg":%d,"fn":%d},"ie":%%d}' % (a, f))
    def pi(self, n, t, b): return self.e(("p", n, t, b), '{"forallE":{"binderInfo":"default","body":%d,"name":%d,"type":%d},"ie":%%d}' % (b, n, t))
    def lam(self, n, t, b): return self.e(("l", n, t, b), '{"lam":{"binderInfo":"default","body":%d,"name":%d,"type":%d},"ie":%%d}' % (b, n, t))
    def let(self, n, t, v, b): return self.e(("t", n, t, v, b), '{"ie":%%d,"letE":{"body":%d,"name":%d,"nondep":false,"type":%d,"value":%d}}' % (b, n, t, v))
    def thm(self, n, t, v): self.o.write('{"thm":{"all":[%d],"levelParams":[],"name":%d,"type":%d,"value":%d}}\n' % (n, n, t, v)); self.o.close()

def ref(w, depth, q): return w.bvar(depth - 1 - q)

def lets(n, path):
    w = W(path)
    # places: 0 Term, 1 Holds, 2 a, 3 f, 4 r
    holds_a = lambda d: w.app(ref(w, d, 1), ref(w, d, 2))
    types = [w.sort(1), w.pi(w.name("t"), ref(w, 1, 0), w.sort(0)), ref(w, 2, 0), holds_a(3),
             w.pi(w.name("x"), ref(w, 4, 0), w.pi(w.name("h"), w.app(ref(w, 5, 1), w.bvar(0)), w.app(ref(w, 6, 1), w.bvar(1))))]
    names = [w.name(x) for x in ("Term", "Holds", "a", "f", "r")]
    B = 5
    body = ref(w, B + n, B + n - 1)
    for i in range(n - 1, -1, -1):
        d = B + i
        prev = ref(w, d, 3) if i == 0 else ref(w, d, B + i - 1)
        body = w.let(w.name("d"), holds_a(d), w.app(w.app(ref(w, d, 4), ref(w, d, 2)), prev), body)
    ty = holds_a(B)
    for q in range(B - 1, -1, -1): ty = w.pi(names[q], types[q], ty); body = w.lam(names[q], types[q], body)
    w.thm(w.name("t"), ty, body)

def app(n, path):
    w = W(path)
    holds_a = lambda d: w.app(ref(w, d, 1), ref(w, d, 2))
    packty = ref(w, 5 + n, 4)
    for i in range(n - 1, -1, -1): packty = w.pi(w.name("h"), holds_a(5 + i), packty)
    types = [w.sort(1), w.pi(w.name("t"), ref(w, 1, 0), w.sort(0)), ref(w, 2, 0), holds_a(3), w.sort(0), packty]
    names = [w.name(x) for x in ("Term", "Holds", "a", "f", "Pack", "pack")]
    B = 6
    body = ref(w, B, 5)
    for i in range(n): body = w.app(body, ref(w, B, 3))
    ty = ref(w, B, 4)
    for q in range(B - 1, -1, -1): ty = w.pi(names[q], types[q], ty); body = w.lam(names[q], types[q], body)
    w.thm(w.name("t"), ty, body)

if __name__ == "__main__" and len(sys.argv) > 1 and sys.argv[1] not in ("far", "tree"):
    for n in map(int, sys.argv[1:]):
        lets(n, f"lets-{n}.ndjson"); app(n, f"app-{n}.ndjson")

def far(n, path, k=200, lists=False, pack=False):
    """lets that reach k back, over k atoms; with lists, each let's fact is (p x) as cons p (cons x nil); with pack, the
    conclusion is all the lets (Pack), else the last."""
    w = W(path)
    # places: 0 Term, 1 Holds, 2 nil, 3 cons, 4 p, 5.. atoms x0..x(k-1), then facts f0..f(k-1), then r, then Pack, pack
    A, F = 5, 5 + k
    R = F + k
    B = R + 1 + (2 if pack else 0)
    def term(d, j):
        if not lists: return ref(w, d, A + j)
        e = ref(w, d, 2)
        e = w.app(w.app(ref(w, d, 3), ref(w, d, A + j)), e)
        return w.app(w.app(ref(w, d, 3), ref(w, d, 4)), e)
    holds = lambda d, j: w.app(ref(w, d, 1), term(d, j))
    def rterm(d, x):  # the rule's statement, x a bvar index at depth d
        if not lists: return x
        e = ref(w, d, 2)
        e = w.app(w.app(ref(w, d, 3), x), e)
        return w.app(w.app(ref(w, d, 3), ref(w, d, 4)), e)
    types = [w.sort(1), w.pi(w.name("t"), ref(w, 1, 0), w.sort(0)), ref(w, 2, 0),
             w.pi(w.name("x"), ref(w, 3, 0), w.pi(w.name("xs"), ref(w, 4, 0), ref(w, 5, 0))), ref(w, 4, 0)]
    names = [w.name(x) for x in ("Term", "Holds", "nil", "cons", "p")]
    for j in range(k): types.append(ref(w, A + j, 0)); names.append(w.name("x%d" % j))
    for j in range(k): types.append(holds(F + j, j)); names.append(w.name("f%d" % j))
    q = R
    types.append(w.pi(w.name("x"), ref(w, q, 0), w.pi(w.name("h"), w.app(ref(w, q + 1, 1), rterm(q + 1, w.bvar(0))),
                                                   w.app(ref(w, q + 2, 1), rterm(q + 2, w.bvar(1))))))
    names.append(w.name("r"))
    if pack:
        P = R + 1
        packty = ref(w, P + 1 + n, P)
        for i in range(n - 1, -1, -1): packty = w.pi(w.name("h"), holds(P + 1 + i, i % k), packty)
        types += [w.sort(0), packty]; names += [w.name("Pack"), w.name("pack")]
        body = ref(w, B + n, P + 1)
        for i in range(n): body = w.app(body, ref(w, B + n, B + i))
        ty = ref(w, B, P)
    else:
        body = ref(w, B + n, B + n - 1)
        ty = holds(B, (n - 1) % k)
    for i in range(n - 1, -1, -1):
        d = B + i
        prev = ref(w, d, F + i) if i < k else ref(w, d, B + i - k)
        body = w.let(w.name("d"), holds(d, i % k), w.app(w.app(ref(w, d, R), term(d, i % k)), prev), body)
    for q in range(B - 1, -1, -1): ty = w.pi(names[q], types[q], ty); body = w.lam(names[q], types[q], body)
    w.thm(w.name("t"), ty, body)

if __name__ == "__main__" and len(sys.argv) > 1 and sys.argv[1] == "far":
    n = int(sys.argv[2])
    far(n, f"far-{n}.ndjson"); far(n, f"farl-{n}.ndjson", lists=True); far(n, f"farp-{n}.ndjson", pack=True)
    far(n, f"farlp-{n}.ndjson", lists=True, pack=True)

def tree(n, path, k=200):
    """far's lets, the conclusion all of them as a balanced tree of And, And and intro being hypotheses:
    (And : Prop → Prop → Prop) (intro : ∀ a b : Prop, a → b → And a b)."""
    w = W(path)
    A, F = 5, 5 + k
    R = F + k
    AND, INTRO = R + 1, R + 2
    B = R + 3
    holds = lambda d, j: w.app(ref(w, d, 1), ref(w, d, A + j))
    types = [w.sort(1), w.pi(w.name("t"), ref(w, 1, 0), w.sort(0)), ref(w, 2, 0),
             w.pi(w.name("x"), ref(w, 3, 0), w.pi(w.name("xs"), ref(w, 4, 0), ref(w, 5, 0))), ref(w, 4, 0)]
    names = [w.name(x) for x in ("Term", "Holds", "nil", "cons", "p")]
    for j in range(k): types.append(ref(w, A + j, 0)); names.append(w.name("x%d" % j))
    for j in range(k): types.append(holds(F + j, j)); names.append(w.name("f%d" % j))
    q = R
    types.append(w.pi(w.name("x"), ref(w, q, 0), w.pi(w.name("h"), w.app(ref(w, q + 1, 1), w.bvar(0)), w.app(ref(w, q + 2, 1), w.bvar(1)))))
    names.append(w.name("r"))
    prop = w.sort(0)
    types.append(w.pi(w.name("a"), prop, w.pi(w.name("b"), prop, prop))); names.append(w.name("And"))
    q = INTRO  # ∀ a b : Prop, a → b → And a b
    types.append(w.pi(w.name("a"), prop, w.pi(w.name("b"), prop, w.pi(w.name("ha"), w.bvar(1), w.pi(w.name("hb"), w.bvar(1),
                 w.app(w.app(ref(w, q + 4, AND), w.bvar(3)), w.bvar(2)))))))
    names.append(w.name("intro"))
    memo = {}
    def ttype(d, lo, hi):  # the conjunction of lets lo..hi-1 at depth d
        if (d, lo, hi) in memo: return memo[(d, lo, hi)]
        if hi - lo == 1: r = holds(d, lo % k)
        else:
            mid = (lo + hi) // 2
            r = w.app(w.app(ref(w, d, AND), ttype(d, lo, mid)), ttype(d, mid, hi))
        memo[(d, lo, hi)] = r
        return r
    def tproof(d, lo, hi):
        if hi - lo == 1: return ref(w, d, B + lo)
        mid = (lo + hi) // 2
        e = w.app(w.app(ref(w, d, INTRO), ttype(d, lo, mid)), ttype(d, mid, hi))
        return w.app(w.app(e, tproof(d, lo, mid)), tproof(d, mid, hi))
    body = tproof(B + n, 0, n)
    ty = ttype(B, 0, n)
    for i in range(n - 1, -1, -1):
        d = B + i
        prev = ref(w, d, F + i) if i < k else ref(w, d, B + i - k)
        body = w.let(w.name("d"), holds(d, i % k), w.app(w.app(ref(w, d, R), ref(w, d, A + i % k)), prev), body)
    for q in range(B - 1, -1, -1): ty = w.pi(names[q], types[q], ty); body = w.lam(names[q], types[q], body)
    w.thm(w.name("t"), ty, body)

if __name__ == "__main__" and len(sys.argv) > 1 and sys.argv[1] == "tree":
    for n in map(int, sys.argv[2:]): tree(n, f"tree-{n}.ndjson")
