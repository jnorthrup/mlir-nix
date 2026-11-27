#!/usr/bin/env python3
"""Every `mlnix store` operation, an old binary against a new one, byte for byte: stdout, stderr, exit status, and the store
(objects, info files, roots) after every change.

usage: store-index-diff.py OLD NEW WORK [--cases a,b,...] [--seeds N] [--big]
  OLD, NEW   two mlnix binaries (OLD is the reference: one from before the index, b77b980 or earlier)
  WORK       a directory for the stores; each run writes fresh directories under it and removes none

A case is a store (scripts' gen-store layout: ROOT/nix/store, ROOT/nix/var/mlnix/info) and a list of steps.  The
reference run gives every command to OLD.  The test run gives each command to the binary its step names (NEW unless the
step says OLD: a store shared with an older mlnix), and between commands does what only the new binary's index can
notice: the index file removed, cut, damaged or made read-only, a query killed while it writes the index, queries at
once.  Both runs use the same ROOT (the reference's is moved aside before the test's is made), so paths in messages are
the same.  The index file, `info.trie`, is the one thing the comparison leaves out.
Python only spawns the binaries and compares what they wrote."""
import hashlib, os, random, signal, stat, subprocess, sys, time

A32 = "0123456789abcdfghijklmnpqrsvwxyz"
ENV = {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": "/var/empty", "LC_ALL": "C", "TZ": "UTC"}


def run(binary, args, env=None, cwd=None, timeout=600):
    e = dict(ENV)
    if env:
        e.update(env)
    p = subprocess.run([binary] + args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=e, cwd=cwd, timeout=timeout)
    return (p.returncode, p.stdout, p.stderr)


def snapshot(store):
    """What the store holds (its objects, its info files, its roots), but for the index file and for times."""
    h = hashlib.sha256()
    n = 0
    for top in sorted({store.real_store, store.state}):
        for base, dirs, files in os.walk(top, followlinks=False):
            dirs.sort()
            for name in sorted(dirs + files):
                p = os.path.join(base, name)
                rel = os.path.relpath(p, store.root)
                if p == store.index:
                    continue
                st = os.lstat(p)
                kind = stat.S_IFMT(st.st_mode)
                h.update(f"{rel}\0{kind:o}\0{stat.S_IMODE(st.st_mode):o}\0".encode())
                if stat.S_ISLNK(st.st_mode):
                    h.update(os.readlink(p).encode())
                elif stat.S_ISREG(st.st_mode):
                    try:
                        with open(p, "rb") as f:
                            h.update(hashlib.sha256(f.read()).digest())
                    except OSError as e:
                        h.update(f"unreadable {e.errno}".encode())
                h.update(b"\n")
                n += 1
    return f"{n} entries {h.hexdigest()}"


class Store:
    """A chroot store at root (mlnix store --store root), or a physical one (--store-dir root/store, state in root/var)."""

    def __init__(self, root, physical=False):
        self.root, self.physical = root, physical
        if physical:
            self.store_dir = os.path.join(root, "store")
            self.state = os.path.join(root, "var")
            self.real_store = self.store_dir
            self.opts, self.env = ["--store-dir", self.store_dir], {"MLNIX_STATE_DIR": self.state}
        else:
            self.store_dir = "/nix/store"
            self.state = os.path.join(root, "nix", "var", "mlnix")
            self.real_store = os.path.join(root, "nix", "store")
            self.opts, self.env = ["--store", root], {}
        self.info = os.path.join(self.state, "info")
        self.index = os.path.join(self.state, "info.trie")
        self.env = dict(self.env, HOME=os.path.join(root, "home"))
        os.makedirs(self.env["HOME"], exist_ok=True)

    def make(self, n, fan, seed):
        """gen-store's store, written here so that a physical store's paths can be made too."""
        rng = random.Random(seed)
        os.makedirs(self.real_store, exist_ok=True)
        os.makedirs(self.info, exist_ok=True)
        paths = []
        for i in range(n):
            h = "".join(rng.choice(A32) for _ in range(32))
            base = f"{h}-p{i}"
            p = self.store_dir + "/" + base
            refs = sorted(set(rng.sample(paths, min(len(paths), rng.randint(0, fan))))) if paths else []
            with open(os.path.join(self.real_store, base), "w") as f:
                f.write(f"p{i}\n")
            nar = "sha256:" + rng.choice("01") + "".join(rng.choice(A32) for _ in range(51))
            lines = [f"path: {p}", f"narHash: {nar}", "narSize: 120"] + [f"ref: {r}" for r in refs]
            if rng.random() < 0.2:
                lines.append(f"deriver: {self.store_dir}/{''.join(rng.choice(A32) for _ in range(32))}-p{i}.drv")
            if rng.random() < 0.1:
                lines.append("ca: fixed:r:sha256:" + rng.choice("01") + "".join(rng.choice(A32) for _ in range(51)))
            with open(os.path.join(self.info, base), "w") as f:
                f.write("\n".join(lines) + "\n")
            paths.append(p)
        return paths


def damage(store, how, rng):
    """What an index file may suffer between two commands."""
    f = store.index
    if not os.path.exists(f):
        return
    size = os.path.getsize(f)
    mode = stat.S_IMODE(os.stat(f).st_mode)
    if how not in ("rm", "ro", "rw"):
        os.chmod(f, 0o644)  # what damages a file does not ask whether it may
    if how == "rm":
        os.makedirs(os.path.join(store.root, "gone"), exist_ok=True)
        os.rename(f, os.path.join(store.root, "gone", f"info.trie.{rng.randrange(1 << 30)}"))
    elif how == "cut" and size:
        with open(f, "r+b") as fh:
            fh.truncate(rng.randrange(size))
    elif how == "tail" and size:  # the end lost: zeros where it was
        with open(f, "r+b") as fh:
            fh.truncate(rng.randrange(size))
            fh.truncate(size)
    elif how == "bytes" and size:
        with open(f, "r+b") as fh:
            for _ in range(rng.randint(1, 24)):
                fh.seek(rng.randrange(size))
                fh.write(bytes([rng.randrange(256)]))
    elif how == "words" and size > 256:
        with open(f, "r+b") as fh:
            for _ in range(rng.randint(1, 6)):
                fh.seek(rng.randrange(size // 8) * 8)
                fh.write(rng.getrandbits(64).to_bytes(8, "little"))
    elif how == "head":
        with open(f, "r+b") as fh:
            fh.seek(8 * rng.randrange(16))
            fh.write(rng.choice([0, rng.getrandbits(64)]).to_bytes(8, "little"))
    elif how == "zero":
        with open(f, "r+b") as fh:
            fh.write(bytes(256))
    elif how == "empty":
        with open(f, "r+b") as fh:
            fh.truncate(0)
    elif how == "junk":
        with open(f, "wb") as fh:
            fh.write(rng.randbytes(rng.randrange(1, 200000)))
    elif how == "ro":
        os.chmod(f, 0o444)
    elif how == "rw":
        os.chmod(f, 0o644)
    if how not in ("rm", "ro", "rw"):
        os.chmod(f, mode)


DAMAGES = ["rm", "cut", "tail", "bytes", "words", "head", "zero", "empty", "junk", "ro", "rw"]


def execute(case, old, new, root, reference):
    """One run of a case: the results of its commands and the snapshots, in step order."""
    store = Store(root, case.get("physical", False))
    ctx = case["setup"](store)
    rng = random.Random(case["seed"] * 7919 + 1)
    results = []
    for step in case["steps"](store, ctx):
        kind = step[0]
        if kind == "run":  # ("run", who, args[, front]): front is a subcommand other than `store`
            who, args = step[1], step[2]
            front = step[3] if len(step) > 3 else "store"
            binary = old if (reference or who == "o") else new
            results.append((" ".join(args), run(binary, [front] + store.opts + args, store.env, cwd=root)))
        elif kind == "fs":  # the same change of the files in both runs
            step[1](store, ctx)
        elif kind == "snap":
            results.append(("snapshot", snapshot(store)))
        elif kind == "idx":
            if not reference:
                damage(store, step[1], rng)
        elif kind == "kill":  # a query of the new binary killed while it works; the reference does nothing
            if not reference:
                e = dict(ENV)
                e.update(store.env)
                p = subprocess.Popen([new, "store"] + store.opts + step[1], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=e, cwd=root)
                time.sleep(step[2])
                p.send_signal(signal.SIGKILL)
                p.wait()
        elif kind == "par":  # queries at once: each one's result is what it is alone
            procs = []
            for who, args in step[1]:
                binary = old if (reference or who == "o") else new
                e = dict(ENV)
                e.update(store.env)
                procs.append((args, subprocess.Popen([binary, "store"] + store.opts + args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=e, cwd=root)))
            for args, p in procs:
                out, err = p.communicate()
                results.append((" ".join(args), (p.returncode, out, err)))
    results.append(("final snapshot", snapshot(store)))
    return results


def compare(name, ref, test):
    if len(ref) != len(test):
        return f"{name}: {len(ref)} results against {len(test)}"
    for i, (a, b) in enumerate(zip(ref, test)):
        if a != b:
            def show(r):
                if isinstance(r[1], tuple):
                    return f"exit {r[1][0]}\n      stdout {r[1][1][:600]!r}\n      stderr {r[1][2][:600]!r}"
                return str(r[1])
            return f"{name}: step {i} `{a[0]}` differs\n    old: {show(a)}\n    new: {show(b)}"
    return None


# ---------------------------------------------------------------------------------------------------------------------
# the cases
# ---------------------------------------------------------------------------------------------------------------------

def fixture_files(store, ctx):
    """Files to add, beside the store."""
    d = os.path.join(store.root, "fixtures")
    os.makedirs(os.path.join(d, "tree", "sub"), exist_ok=True)
    for name, text in [("one.txt", "one\n"), ("two.txt", "two two\n"), ("empty", ""), ("tree/a", "a\n"), ("tree/sub/b", "bb\n")]:
        with open(os.path.join(d, name), "w") as f:
            f.write(text)
    os.chmod(os.path.join(d, "tree", "a"), 0o755)
    if not os.path.islink(os.path.join(d, "tree", "link")):
        os.symlink("a", os.path.join(d, "tree", "link"))
    ctx["fixtures"] = d


def add_roots(store, ctx, rng, k):
    roots = os.path.join(store.state, "gcroots")
    os.makedirs(roots, exist_ok=True)
    for i in range(k):
        if not ctx["paths"]:
            break
        p = rng.choice(ctx["paths"])
        target = p if rng.random() < 0.5 else (os.path.join(store.real_store, os.path.basename(p)))
        link = os.path.join(roots, f"root{i}")
        if not os.path.lexists(link):
            os.symlink(target, link)


def odd_entries(store, ctx, rng):
    """Info entries an index must leave to the store's own reading: each is a path the old binary answers for in its way."""
    paths = ctx["paths"]
    def name(suffix="-odd"):
        return "".join(rng.choice(A32) for _ in range(32)) + suffix + str(rng.randrange(1000))
    def obj(base, text="x\n"):
        with open(os.path.join(store.real_store, base), "w") as f:
            f.write(text)
    def info(base, text):
        with open(os.path.join(store.info, base), "w") as f:
            f.write(text)
    ref = (f"ref: {rng.choice(paths)}\n" if paths else "")
    good = "narHash: sha256:" + "0" * 52 + "\nnarSize: 5\n"
    made = []
    b = name(); obj(b); info(b, f"path: {store.store_dir}/{b}\nnarHash: sha256:{'z' * 52}\nnarSize: 5\n{ref}"); made.append(b)      # a hash parseHash refuses
    b = name(); obj(b); info(b, f"path: {store.store_dir}/{b}\nnarHash: nohash:abc\nnarSize: 5\n{ref}"); made.append(b)          # an algorithm it does not know
    b = name(); obj(b); info(b, f"path: {store.store_dir}/{b}\nnarHash: md5:{'0' * 32}\nnarSize: 5\n{ref}"); made.append(b)      # another algorithm: read
    b = name(); obj(b); info(b, ""); made.append(b)                                                                             # nothing
    b = name(); obj(b); info(b, f"path: {store.store_dir}/{b}\n{good}{ref}".rstrip("\n")); made.append(b)                       # no newline at the end
    b = name(); obj(b); info(b, f"path: {store.store_dir}/{b}\n{good}{ref}junk without a colon\nref\nref:\nref: \n: x\n"); made.append(b)
    b = name(); info(b, f"path: {store.store_dir}/{b}\n{good}{ref}"); made.append(b)                                            # no store object: not valid
    b = name(); obj(b); made.append(b)                                                                                          # no info: not valid
    b = name(".tmp"); obj(b); info(b, f"path: {store.store_dir}/{b}\n{good}{ref}"); made.append(b)                              # a name allValidPaths passes over
    b = "short-name"; obj(b); info(b, f"path: {store.store_dir}/{b}\n{good}{ref}"); made.append(b)
    b = name(); obj(b); os.mkdir(os.path.join(store.info, b)); made.append(b)                                                   # a directory where a file is expected
    b = name(); obj(b); os.symlink("/nowhere/at/all", os.path.join(store.info, b)); made.append(b)                              # a link to nothing
    if paths:
        b = name(); obj(b); os.symlink(os.path.join(store.info, os.path.basename(rng.choice(paths))), os.path.join(store.info, b)); made.append(b)  # a link to another's info
        other = os.path.basename(rng.choice(paths))                                                                             # the same key (13 characters of the hash) as another
        b = other[:13] + "".join(rng.choice(A32) for _ in range(19)) + "-twin"; obj(b); info(b, f"path: {store.store_dir}/{b}\n{good}ref: {store.store_dir}/{other}\n"); made.append(b)
    b = "NOT-A-HASH-AT-ALL-BUT-LONG-ENOUGH-FOR-A-NAME-" + str(rng.randrange(1000)); obj(b); info(b, f"path: {store.store_dir}/{b}\n{good}{ref}"); made.append(b)
    b = name("-big"); obj(b); info(b, f"path: {store.store_dir}/{b}\n{good}" + "".join(f"ref: {store.store_dir}/{'0' * 32}-filler{i}\n" for i in range(30000)) + ref); made.append(b)  # more than a megabyte
    if os.geteuid() != 0:
        b = name("-locked"); obj(b); info(b, f"path: {store.store_dir}/{b}\n{good}{ref}"); os.chmod(os.path.join(store.info, b), 0); made.append(b)
    ctx["odd"] = [store.store_dir + "/" + b for b in made]


def query_steps(store, ctx, rng, k, mix):
    """k queries over the store's paths, and paths it does not have."""
    pool = list(ctx["paths"]) + ctx.get("odd", []) + ctx.get("extra", [])
    ghost = store.store_dir + "/" + "0" * 32 + "-ghost"
    steps = []
    kinds = ["--references", "--referrers", "--requisites", "--deriver", "--outputs", "--hash", "--size", None, "--referrers", "--referrers"]
    for _ in range(k):
        q = rng.choice(kinds)
        n = 1 if rng.random() < 0.8 else rng.randint(2, 4)
        ps = [rng.choice(pool) if pool and rng.random() < 0.9 else rng.choice([ghost, "not/a/store/path", store.store_dir, store.store_dir + "/x"]) for _ in range(n)]
        args = ["--query"] + ([q] if q else []) + (["--include-outputs"] if q == "--requisites" and rng.random() < 0.3 else []) + ps
        steps.append(("run", "o" if mix and rng.random() < 0.3 else "n", args))
    return steps


def case_random(seed, n, fan, mix, odd=False, roots=0, physical=False, big=False):
    def setup(store):
        rng = random.Random(seed)
        ctx = {"paths": store.make(n, fan, seed)}
        fixture_files(store, ctx)
        if odd:
            odd_entries(store, ctx, rng)
        add_roots(store, ctx, rng, roots)
        return ctx

    def steps(store, ctx):
        rng = random.Random(seed * 31 + 7)
        paths = list(ctx["paths"])
        fx = ctx["fixtures"]
        out = [("snap",)]
        out += query_steps(store, ctx, rng, 6, mix)
        rounds = 8 if big else 40
        for _ in range(rounds):
            r = rng.random()
            who = "o" if mix and rng.random() < 0.35 else "n"
            if r < 0.40:
                out += query_steps(store, ctx, rng, rng.randint(1, 4), mix)
            elif r < 0.50:
                f = rng.choice(["one.txt", "two.txt", "empty", "tree", "missing-file"])
                if rng.random() < 0.6:
                    out.append(("run", who, ["--add", os.path.join(fx, f)]))
                else:
                    out.append(("run", who, ["--add-fixed", rng.choice(["sha256", "sha1", "md5", "sha512", "nohash"]), os.path.join(fx, rng.choice(["one.txt", "two.txt", "empty"]))]))
                out.append(("snap",))
            elif r < 0.64:
                k = 1 if rng.random() < 0.7 else rng.randint(2, 5)
                ps = [rng.choice(paths) if paths and rng.random() < 0.9 else store.store_dir + "/" + "0" * 32 + "-ghost" for _ in range(k)]
                if paths and rng.random() < 0.5:
                    ps[0] = paths[-rng.randint(1, min(len(paths), 8))]  # a late path: often a leaf, which goes
                out.append(("run", who, ["--delete"] + ps))
                out.append(("snap",))
            elif r < 0.70:
                out.append(("run", who, ["--gc", rng.choice(["--print-dead", "--print-live"])]))
            elif r < 0.72 and not big:
                out.append(("run", who, ["--gc"]))
                out.append(("snap",))
            elif r < 0.76:
                out.append(("run", who, [rng.choice(["--dump-db", "--read-log", "--verify-path"])] + ([rng.choice(paths)] if paths else [])))
            elif r < 0.79 and not big:
                out.append(("run", who, ["--verify"]))
            elif r < 0.86:
                out.append(("idx", rng.choice(DAMAGES)))
            elif r < 0.90:
                p = rng.choice(paths) if paths else store.store_dir + "/x"
                out.append(("kill", ["--query", "--referrers", p] if rng.random() < 0.6 else ["--gc", "--print-dead"], rng.choice([0.0, 0.002, 0.01, 0.03, 0.08])))
            elif r < 0.94:
                qs = [(("o" if mix and rng.random() < 0.4 else "n"), s[2]) for s in query_steps(store, ctx, rng, rng.randint(2, 4), False)]
                out.append(("par", qs))
            else:
                def touch(store, ctx, rng=random.Random(rng.random())):  # a path's object changed or gone behind the store's back
                    if ctx["paths"]:
                        b = os.path.basename(rng.choice(ctx["paths"]))
                        f = os.path.join(store.real_store, b)
                        if os.path.isfile(f) and os.access(f, os.W_OK):
                            with open(f, "a") as fh:
                                fh.write("changed\n")
                out.append(("fs", touch))
        out += query_steps(store, ctx, rng, 6, mix)
        out.append(("run", "n", ["--gc", "--print-dead"]))
        return out

    return {"seed": seed, "setup": setup, "steps": steps, "physical": physical}


def case_build(seed, mix):
    """Derivations instantiated and realised in a fresh physical store: a small graph, fixed-output and plain."""
    exprs = [
        'derivation { name = "a"; system = builtins.currentSystem; builder = "/bin/sh"; args = [ "-c" "echo hi > $out" ]; }',
        'let a = derivation { name = "a"; system = builtins.currentSystem; builder = "/bin/sh"; args = [ "-c" "echo hi > $out" ]; }; in derivation { name = "b"; system = builtins.currentSystem; builder = "/bin/sh"; args = [ "-c" "echo ${a} > $out; /bin/cat ${a} >> $out" ]; }',
        'let a = derivation { name = "a"; system = builtins.currentSystem; builder = "/bin/sh"; args = [ "-c" "echo hi > $out" ]; }; b = derivation { name = "b"; system = builtins.currentSystem; builder = "/bin/sh"; args = [ "-c" "echo ${a} > $out; /bin/cat ${a} >> $out" ]; }; in derivation { name = "c"; system = builtins.currentSystem; builder = "/bin/sh"; outputs = [ "out" "dev" ]; args = [ "-c" "/bin/mkdir $out; echo ${b} > $out/b; echo ${a} > $dev" ]; }',
        'derivation { name = "fails"; system = builtins.currentSystem; builder = "/bin/sh"; args = [ "-c" "echo no >&2; exit 3" ]; }',
        'derivation { name = "noout"; system = builtins.currentSystem; builder = "/bin/sh"; args = [ "-c" "true" ]; }',
        'builtins.toFile "text" "some text\\n"',
    ]

    def setup(store):
        os.makedirs(store.real_store, exist_ok=True)
        ctx = {"paths": []}
        fixture_files(store, ctx)
        return ctx

    def steps(store, ctx):
        rng = random.Random(seed)
        out = []
        for e in exprs:
            who = "o" if mix and rng.random() < 0.4 else "n"
            out.append(("run", who, ["-E", e], "instantiate"))
        out.append(("snap",))
        out.append(("fs", lambda store, ctx: ctx.update(drvs=sorted(store.store_dir + "/" + b for b in os.listdir(store.real_store) if b.endswith(".drv")))))

        def later(store, ctx):
            rng2 = random.Random(seed + 1)
            more = []
            for d in ctx.get("drvs", []):
                who = "o" if mix and rng2.random() < 0.4 else "n"
                more.append(("run", who, ["--query", "--outputs", d]))
                more.append(("run", who, ["--query", "--references", d]))
                more.append(("run", who, ["--query", "--requisites", d]))
                more.append(("run", "o" if mix and rng2.random() < 0.4 else "n", ["--realise", d]))
                more.append(("snap",))
                more.append(("run", who, ["--query", "--requisites", "--include-outputs", d]))
                more.append(("run", who, ["--query", "--referrers", d]))
                more.append(("run", who, ["--print-env", d]))
            more.append(("run", "n", ["--gc", "--print-dead"]))
            more.append(("run", "n", ["--verify"]))
            for d in ctx.get("drvs", []):
                more.append(("run", "o" if mix and rng2.random() < 0.4 else "n", ["--realise", d]))  # again: nothing to build
            more.append(("run", "n", ["--gc"]))
            more.append(("snap",))
            for d in ctx.get("drvs", []):
                more.append(("run", "n", ["--query", "--referrers", d]))
            return more
        out.append(("later", later))
        return out

    return {"seed": seed, "setup": setup, "steps": steps, "physical": True}


def expand(case):
    """A case whose later steps depend on what its earlier ones made: `("later", fn)` is replaced as the run reaches it."""
    inner = case["steps"]

    def steps(store, ctx):
        for s in inner(store, ctx):
            if s[0] == "later":
                yield from s[1](store, ctx)
            else:
                yield s
    c = dict(case)
    c["steps"] = steps
    return c


def all_cases(seeds, big):
    cases = {}
    for s in range(seeds):
        cases[f"empty-{s}"] = case_random(100 + s, 0, 4, mix=bool(s % 2))
        cases[f"one-{s}"] = case_random(200 + s, 1, 4, mix=bool(s % 2), roots=1)
        cases[f"few-{s}"] = case_random(300 + s, 17, 3, mix=bool(s % 2), roots=2)
        cases[f"hundred-{s}"] = case_random(400 + s, 100, 1 + s % 7, mix=True, roots=3)
        cases[f"odd-{s}"] = case_random(500 + s, 60, 4, mix=bool(s % 2), odd=True, roots=2)
        cases[f"thousand-{s}"] = case_random(600 + s, 1000, 2 + s % 9, mix=bool(s % 2), roots=5)
        cases[f"physical-{s}"] = case_random(700 + s, 40, 4, mix=bool(s % 2), roots=2, physical=True)
        cases[f"build-{s}"] = case_build(800 + s, mix=bool(s % 2))
    if big:
        cases["five-thousand"] = case_random(900, 5000, 4, mix=True, roots=8, big=True)
        cases["twenty-thousand"] = case_random(901, 20000, 4, mix=True, roots=8, big=True)
        cases["twenty-thousand-wide"] = case_random(902, 20000, 12, mix=False, roots=3, big=True)
    return {k: expand(v) for k, v in cases.items()}


def main():
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    old, new, work = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2]), os.path.abspath(sys.argv[3])
    seeds, big, only = 2, False, None
    rest = sys.argv[4:]
    while rest:
        a = rest.pop(0)
        if a == "--seeds":
            seeds = int(rest.pop(0))
        elif a == "--big":
            big = True
        elif a == "--cases":
            only = rest.pop(0).split(",")
    os.makedirs(work, exist_ok=True)
    stamp = f"{int(time.time())}-{os.getpid()}"
    cases = all_cases(seeds, big)
    failed = commands = 0
    for name, case in cases.items():
        if only and not any(name.startswith(o) for o in only):
            continue
        root = os.path.join(work, f"{name}-{stamp}")
        t0 = time.time()
        ref = execute(case, old, new, root, True)
        os.rename(root, root + ".old")
        test = execute(case, old, new, root, False)
        os.rename(root, root + ".new")
        diff = compare(name, ref, test)
        commands += sum(1 for r in ref if isinstance(r[1], tuple))
        errors = sum(1 for r in ref if isinstance(r[1], tuple) and r[1][0] != 0)
        if diff:
            failed += 1
            print("FAIL " + diff, flush=True)
        else:
            print(f"same  {name}: {len(ref)} results ({errors} of the commands fail, as they should), {time.time() - t0:.0f} s", flush=True)
    print(f"{commands} commands compared, {failed} cases differ")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
