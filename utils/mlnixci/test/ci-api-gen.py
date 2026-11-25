#!/usr/bin/env python3
"""ci-api: generates the cases for ci_api_diff (C; no ctypes).  Each line is one case (see ci_api_diff.c):
R what-if requests (overlays, bodies, set or reset), F fail_with, N the 404, and C corpora with their Q queries.
usage: ci-api-gen.py OUT N_EDIT N_FAIL N_404 N_CORPUS N_QUERY [SEED]
The generators are the ones the lane used (api_diff.py, query_diff.py), with the same shapes of input."""
import json
import random
import sys

out_path = sys.argv[1]
N_EDIT, N_FAIL, N_404, N_CORPUS, N_QUERY = (int(x) for x in sys.argv[2:7])
rng = random.Random(int(sys.argv[7]) if len(sys.argv) > 7 else 7)


def hx(b):
    return b.hex()


# ---- what-if overlays and bodies
KEYS = ["a", "b", "services", "nix", "port", "x.y", "q\\\"t", "\\u00e9t\\u00e9", "", "k k", "\\\\", "settings", "n0"]


def key():
    if rng.random() < 0.8:
        return rng.choice(KEYS)
    return "".join(rng.choice("abcxyz.\\\"é ") for _ in range(rng.randint(0, 5))).replace("\\", "\\\\").replace('"', '\\"')


def ws():
    return rng.choice(["", "", " ", "\n", "  ", "\t"])


def value(d):
    r = rng.random()
    if d > 0 and r < 0.35:
        return obj(d - 1)
    if r < 0.5:
        return "[" + ws() + (", ".join(value(d - 1) for _ in range(rng.randint(0, 3))) if d > 0 else "") + ws() + "]"
    return rng.choice(["1", "-2.5", "true", "false", "null", '"s"', '"a\\"b"', '"\\u00e9"', '""', "{}", "[]",
                       "12345678901234567890", '"${x}"'])


def obj(d):
    ks = [key() for _ in range(rng.randint(0, 4))]
    return "{" + ws() + ("," + ws()).join('"%s"%s:%s%s' % (k, ws(), ws(), value(d)) for k in ks) + ws() + "}"


def overlay():
    if rng.random() < 0.03:
        return rng.choice(["[]", '"x"', "1", "{", "", "nul", '{"a":}', '{"a" 1}'])
    return obj(rng.randint(0, 3))


def keys_of(text):
    try:
        v = json.loads(text)
    except Exception:
        return []
    paths = []

    def walk(v, p):
        if isinstance(v, dict):
            for k, x in v.items():
                paths.append(p + [k])
                walk(x, p + [k])

    walk(v, [])
    return paths


def jstr(s):
    return json.dumps(s, ensure_ascii=rng.random() < 0.5)


def body(ov, want):
    if rng.random() < 0.04:
        return rng.choice(['', 'x', '[]', '"p"', '{"path":"a"}', '{"path":[]}', '{"path":[1]}', '{"path":["a",2]}',
                           '{"value":1}', '{"path":["a"]', '{"path":["a"],"value"}', '{"path":{"a":1}}', 'null',
                           '{"path":["a"],"value":1,"path":["b"]}', '{"path" : [ "a" ] , "value" : [1, {"x": 2}] }']).encode()
    paths = keys_of(ov)
    if paths and rng.random() < 0.7:
        p = list(rng.choice(paths))
        if rng.random() < 0.4:
            p = p + [rng.choice(["a", "new", "z"]) for _ in range(rng.randint(1, 3))]
    else:
        p = [rng.choice(["a", "b", "new", "services", "x.y", "é", 'q"t', ""]) for _ in range(rng.randint(1, 4))]
    ps = "[" + ws() + ("," + ws()).join(jstr(s) for s in p) + ws() + "]"
    members = ['"path"%s:%s%s' % (ws(), ws(), ps)]
    if (want and rng.random() < 0.95) or (not want and rng.random() < 0.2):
        members.append('"value"%s:%s%s' % (ws(), ws(), value(2)))
    if rng.random() < 0.1:
        members.append('"other": 1')
    rng.shuffle(members)
    return ("{" + ws() + ("," + ws()).join(members) + ws() + "}").encode()


# ---- query corpora and bodies (query_diff.py's)
SECTIONS = ["services", "networking", "nix", "boot", "users", "sé", 'q"t']
KINDS = ["boolean", "string", "signed integer", "list of string", "null or string", "attribute set of (submodule)"]
STATES = ["default", "set", "whatif", "unset"]
WORDS = ["port", "enable", "hostName", "settings", "cores", "ssh", "nginx", "max-jobs", "Allow", "the", "é", "’"]


def corpus():
    opts = []
    for i in range(rng.randint(0, 40)):
        sec = rng.choice(SECTIONS)
        o = {"path": [sec] + [rng.choice(WORDS) for _ in range(rng.randint(0, 3))]}
        if rng.random() < 0.9:
            o["valueShown"] = rng.random() < 0.8
        o["value"] = rng.choice(["true", "false", '"x"', "22", "[ ]", "{ a = 1; }", "null"])
        o["state"] = rng.choice(STATES)
        o["kind"] = rng.choice(KINDS)
        if rng.random() < 0.9:
            o["declarations"] = ["/nix/store/x/nixos/modules/%s/%s.nix" % (sec, rng.choice(WORDS))
                                 for _ in range(rng.randint(0, 2))]
        o["description"] = " ".join(rng.choice(WORDS) for _ in range(rng.randint(0, 8)))
        opts.append(o)
    etc = {rng.choice(["hosts", "nix/nix.conf", "ssh/sshd_config"]): {"text": "x %d" % i}
           for i in range(rng.randint(0, 3))}
    return json.dumps({"options": opts, "etc": etc}, ensure_ascii=rng.random() < 0.5).encode(), opts


def qws():
    return rng.choice(["", "", " ", "\n"])


def query(opts):
    if rng.random() < 0.05:
        return rng.choice([b"", b"x", b"[]", b'"q"', b"{", b'{"select":', b"null", b"{}", b'{"q":}'])
    members = []
    if rng.random() < 0.6:
        cols = {}
        for name in ["section", "kind", "state", "module", "whatif", "match", "other", "Section"]:
            if rng.random() < 0.35:
                pool = {"section": SECTIONS, "kind": KINDS, "state": STATES, "module": SECTIONS + ["x/y"],
                        "whatif": ["same", "changed"], "match": ["no", "yes"]}.get(name, ["a"])
                if rng.random() < 0.08:
                    cols[name] = rng.choice(["services", 1, None, {"a": 1}, []])
                else:
                    cols[name] = [rng.choice(pool + [1, True, None, "zz", ["services"]])
                                  for _ in range(rng.randint(0, 3))]
        sel = json.dumps(cols, ensure_ascii=rng.random() < 0.5)
        if rng.random() < 0.05:
            sel = rng.choice(["[]", '"services"', "1", "null"])
        members.append('"select":' + qws() + sel)
    if rng.random() < 0.5:
        q = rng.choice(WORDS + ["", "ss", "SSH", "port enable", "\\", '"', "é", "nix.", "services."])
        qv = json.dumps(q, ensure_ascii=rng.random() < 0.5) if rng.random() < 0.9 else rng.choice(['1', 'null', '["ssh"]'])
        members.append('"q":' + qws() + qv)
    for k in ("offset", "limit"):
        if rng.random() < 0.4:
            v = rng.choice(["0", "1", "5", "-3", "2001", "1500", "3.7", "1e2", '"7"', "true", "null", "[2]",
                            "99999999999999999999", str(rng.randint(0, 50)), "-0", "  4"])
            members.append('"%s":%s%s' % (k, qws(), v))
    rng.shuffle(members)
    return ("{" + qws() + ("," + qws()).join(members) + qws() + "}").encode()


# ---- the 404 and fail_with inputs (api_diff.py's)
def fail_case():
    status = rng.choice([400, 404, 413, 422, 500, 200, rng.randint(0, 999)])
    if rng.random() < 0.5:
        t = bytes(rng.randrange(256) for _ in range(rng.randint(0, 40)))
    else:
        t = rng.choice([b"request too large", b"bad request line", b'mlnix: error: "x"\n\tat \\ y', "é’".encode()])
    return "F\t%d\t%s" % (status, hx(t))


def route_case():
    m = rng.choice([b"PUT", b"get", b"DELETE", b"", b'G"E\\T', bytes(rng.randrange(33, 256) for _ in range(rng.randint(0, 6)))])
    if m in (b"GET", b"POST"):
        m = b"PATCH"
    p = bytes(rng.choice([rng.randrange(256), 47, 97]) for _ in range(rng.randint(0, 30)))
    return "N\t%s\t%s" % (hx(m), hx(p))


units = []
for i in range(N_EDIT):
    ov = overlay().encode()
    want = rng.random() < 0.6
    b = body(ov.decode(), want)
    units.append(["R\t%s\t%s\t%d" % (hx(ov), hx(b), 1 if want else 0)])
for i in range(N_FAIL):
    units.append([fail_case()])
for i in range(N_404):
    units.append([route_case()])
for c in range(N_CORPUS):
    js, opts = corpus()
    u = ["C\t" + hx(js)]
    for q in range(N_QUERY):
        u.append("Q\t%s\t%d" % (hx(query(opts)), 1 if rng.random() < 0.95 else 0))
    units.append(u)
rng.shuffle(units)
with open(out_path, "w") as f:
    for u in units:
        f.write("\n".join(u) + "\n")
print("cases: %d edits, %d fail_with, %d 404, %d corpora x %d queries -> %s" %
      (N_EDIT, N_FAIL, N_404, N_CORPUS, N_QUERY, out_path))
