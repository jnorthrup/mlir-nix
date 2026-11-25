#!/usr/bin/env python3
"""ci-api differential: two mlnixci servers (old and new) take the same requests over HTTP, and their replies are compared
byte for byte: status line, headers and body.  Only the timings (any JSON key ending in Ms: queryMs, evalMs, the report's
evalMs object) are masked, and Content-Length is checked against the body each server really sent.

  python3 test/ci-api-diff.py OLD_URL NEW_URL N [SEED] [FRAMES]

N API requests (queries and their paging, what-if set/reset/clear, the report, facets asked for on demand, unknown
routes and methods, malformed JSON bodies), each on its own connection (the servers answer Connection: close), in order,
so the overlays stay in step.  FRAMES raw requests: heads with odd framing (Content-Length wrong, repeated, huge or not a
number, a bad request line, bare LFs, a head cut short) and random byte edits of valid requests.  Both servers must start
from an empty overlay (a fresh --state) on the same corpus.  Exit 0 when every reply agrees.
"""
import json
import random
import re
import socket
import sys
import time
from urllib.parse import urlparse

MASK = re.compile(rb'"(\w*Ms)":\s*(\{[^{}]*\}|[-0-9.eE+]+)')
# the two servers run from two checkouts: a reply that names its corpus's file names the checkout
SRCDIR = re.compile(rb'/[^"\s]*?/utils/mlnixci/')


def mask(b):
    return SRCDIR.sub(b"<SRC>/", MASK.sub(rb'"\1":0', b))


def split_reply(raw):
    """(status line + headers, body) with Content-Length checked against the body that came; the head is returned with
    its Content-Length replaced by the masked body's length, so only the timings can differ between servers"""
    head, sep, body = raw.partition(b"\r\n\r\n")
    if not sep:
        return raw, None
    n = None
    for line in head.split(b"\r\n")[1:]:
        k, _, v = line.partition(b":")
        if k.strip().lower() == b"content-length":
            n = v.strip()
    m = mask(body)
    if n is not None and n.isdigit() and int(n) != len(body):
        return head + b" <CL %s but body %d>" % (n, len(body)), m
    if n is not None:
        head = b"\r\n".join(
            (b"Content-Length: %d" % len(m)) if line.lower().startswith(b"content-length:") else line
            for line in head.split(b"\r\n"))
    return head, m


def same(a, b):
    return split_reply(a) == split_reply(b)


def exchange(url, raw, wait=5.0):
    """one request on its own connection: the reply the server sends before it closes (or after `wait` of silence)"""
    u = urlparse(url)
    s = socket.create_connection((u.hostname, u.port), timeout=wait)
    out = b""
    try:
        s.sendall(raw)
        head_done = False
        n = None
        while True:
            try:
                chunk = s.recv(65536)
            except socket.timeout:
                break
            except OSError as e:
                return out + b"<reset %s>" % type(e).__name__.encode()
            if not chunk:
                break
            out += chunk
            if not head_done and b"\r\n\r\n" in out:
                head_done = True
                h = out.partition(b"\r\n\r\n")[0]
                for line in h.split(b"\r\n")[1:]:
                    k, _, v = line.partition(b":")
                    if k.strip().lower() == b"content-length" and v.strip().isdigit():
                        n = int(v.strip())
            if head_done and n is not None and len(out.partition(b"\r\n\r\n")[2]) >= n:
                break
        return out
    finally:
        s.close()


def req(method, path, body=None, raw=None):
    if raw is None and body is not None:
        raw = json.dumps(body).encode()
    raw = raw or b""
    head = "%s %s HTTP/1.1\r\nHost: x\r\nContent-Length: %d\r\n\r\n" % (method, path, len(raw))
    return head.encode() + raw


WORDS = ["host", "etc", "motd", "time", "ETC", "\\/ETC\\/\\u0048ostname", "grüße", "", "q\"t", "a\\b", "%", "tab\there",
         "networking", "firewall", "zone", "x", "  ", "\\u00e9", "${x}", "nul\x00l", "é"]
SECTIONS = ["networking", "services", "time", "nope", ""]
COLUMNS = {"section": SECTIONS, "kind": ["strMatching", "bool", "enum", "int", "list", "nope"],
           "state": ["set", "default", "x"], "module": ["options.nix", "y"], "whatif": ["changed", "same"],
           "match": ["yes", "no"]}
PATHS = [["networking", "hostName"], ["networking", "firewall", "enable"], ["networking", "firewall", "allowedTCPPorts"],
         ["services", "motd", "text"], ["services", "motd", "enable"], ["time", "timeZone"], ["etc", "aaa-first"],
         ["etc", "zzz-last"], ["etc", "motd"], ["a"], ["a", "b"], ["networking"], ["x.y"], ["q\"t"], ["é"], [""]]
VALUES = ["edge-1", "bad host!", "Asia/Tokyo", "Mars/Olympus", 1, -2.5, True, False, None, [22, 80], [22, 70000], [],
          {}, {"x": 2}, "first\n", "last\n", "Grüße \"q\" back\\slash ${n} tab\tend\nsecond ✓", "\u0000", 12345678901234567890,
          "", [1, {"a": [None]}], "\\u0041"]
BODIES = [b"", b"x", b"[]", b'"p"', b'{"path":"a"}', b'{"path":[]}', b'{"path":[1]}', b'{"path":["a",2]}',
          b'{"value":1}', b'{"path":["a"]', b'{"path":["a"],"value"}', b'{"path":{"a":1}}', b"null",
          b'{"path":["a"],"value":1,"path":["b"]}', b'{"path" : [ "a" ] , "value" : [1, {"x": 2}] }',
          b'{"select": {"section": ["time"]}, "q": 5}', b'{"offset": "x"}', b'{"limit": -3}', b'{"q": "\\u00"}',
          b'{"select": []}', b'{"ask": [{"iface": "live"}]}', b"\xff\xfe", b'{"q":"a"}}', b"{}{}"]


def gen_query(rng):
    sel = {}
    for col in rng.sample(list(COLUMNS), rng.randint(0, 3)):
        sel[col] = rng.sample(COLUMNS[col], rng.randint(0, 2))
    body = {"select": sel} if rng.random() < 0.9 else {}
    if rng.random() < 0.6:
        body["q"] = rng.choice(WORDS) if rng.random() < 0.7 else "".join(
            rng.choice("abcxyz HOST\\\"é%$") for _ in range(rng.randint(0, 6)))
    if rng.random() < 0.3:
        body["offset"] = rng.choice([0, 1, 2, 5, 7, 100, -1, "3", None, 2.5])
    if rng.random() < 0.3:
        body["limit"] = rng.choice([0, 1, 2, 3, 150, 2000, 2001, -1, "x", None])
    if rng.random() < 0.05:
        body["select"] = rng.choice([[], "time", None, {"section": "time"}])
    return ("POST", "/api/query", body, None)


def gen_api(rng, overlay_paths):
    r = rng.random()
    if r < 0.40:
        return gen_query(rng)
    if r < 0.62:
        path = rng.choice(PATHS) if rng.random() < 0.85 else [rng.choice(WORDS) for _ in range(rng.randint(1, 3))]
        if rng.random() < 0.3 and overlay_paths:
            path = rng.choice(overlay_paths)
        return ("POST", "/api/whatif/set", {"path": path, "value": rng.choice(VALUES)}, None)
    if r < 0.72:
        path = rng.choice(PATHS) if rng.random() < 0.7 else rng.choice(overlay_paths or PATHS)
        return ("POST", "/api/whatif/reset", {"path": path}, None)
    if r < 0.74:
        return ("POST", "/api/whatif/clear", None, None)
    if r < 0.80:
        return ("GET", "/api/report", None, None)
    if r < 0.86:
        asks = [{"iface": rng.choice(["adhesion", "live", "module", "nope"]),
                 "path": rng.choice(PATHS)} for _ in range(rng.randint(0, 4))]
        return ("POST", "/api/facet", {"ask": asks}, None)
    if r < 0.92:
        return ("POST", rng.choice(["/api/whatif/set", "/api/query", "/api/whatif/reset", "/api/facet"]), None,
                rng.choice(BODIES))
    if r < 0.96:
        return (rng.choice(["GET", "PUT", "DELETE", "HEAD"]), rng.choice(["/nope", "/api/commit", "/api/set", "/",
                                                                          "/api/query", "/index.html", "/?x=1"]),
                None, None)
    return ("GET", "/", None, None)


FRAMES_FIXED = [
    b"GET / HTTP/1.1\r\nHost: x\r\n\r\n",
    b"GET / HTTP/1.1\nHost: x\n\n",
    b"GET /api/report HTTP/1.1\r\nContent-Length: 0\r\n\r\n",
    b"GET /api/report HTTP/1.1\r\ncontent-length:0\r\n\r\n",
    b"GET /api/report HTTP/1.1\r\nContent-Length:   0  \r\n\r\n",
    b"GET /api/report HTTP/1.1\r\nContent-Length: 0\r\nContent-Length: 5\r\n\r\nhello",
    b"POST /api/query HTTP/1.1\r\nContent-Length: 2\r\n\r\n{}",
    b"POST /api/query HTTP/1.1\r\nContent-Length: 9\r\n\r\n{\"q\":1}",
    b"POST /api/query HTTP/1.1\r\nContent-Length: 40\r\n\r\n{}",
    b"POST /api/query HTTP/1.1\r\nContent-Length: 2x\r\n\r\n{}",
    b"POST /api/query HTTP/1.1\r\nContent-Length: -1\r\n\r\n{}",
    b"POST /api/query HTTP/1.1\r\nContent-Length: 99999999999999999999\r\n\r\n",
    b"POST /api/query HTTP/1.1\r\nContent-Length: 1048577\r\n\r\n",
    b"POST /api/query HTTP/1.1\r\nContent-Length: 1048576\r\n\r\n",
    b"POST /api/query HTTP/1.1\r\nTransfer-Encoding: chunked\r\nContent-Length: 2\r\n\r\n{}",
    b"POST /api/query HTTP/1.1\r\nno colon here\r\nContent-Length: 2\r\n\r\n{}",
    b"POST /api/query HTTP/1.1\r\n: empty name\r\nContent-Length: 2\r\n\r\n{}",
    b"POST /api/query HTTP/1.1\r\nX-A: 1\r\n\r\n{}",
    b"GET /api/report\r\n\r\n",
    b"GET  /api/report HTTP/1.1\r\n\r\n",
    b"GET /api/report\tHTTP/1.1\r\n\r\n",
    b"GET /api/report?x=1&y=2 HTTP/1.1\r\n\r\n",
    b"GET /api/report? HTTP/1.1\r\n\r\n",
    b"GET ?x HTTP/1.1\r\n\r\n",
    b" GET / HTTP/1.1\r\n\r\n",
    b"GET / HTTP/1.1\r\n\r\n\r\n\r\n",
    b"\r\n\r\nGET / HTTP/1.1\r\n\r\n",
    b"GET / HTTP/1.1\r\nHost: x\r\n",
    b"GET / HTTP/1.1",
    b"",
    b"\r\n",
    b"\n\n",
    b"GET",
    b"GET /",
    b"GET / ",
    b"POST / HTTP/1.1\r\nContent-Length: 3\r\n\r\nab",
    b"POST /api/whatif/set HTTP/1.1\r\nContent-Length: 27\r\n\r\n{\"path\":[\"a\"],\"value\":\"\\\"\"}",
    b"GET /api/report HTTP/1.1\r\nX-Long: " + b"a" * 70000 + b"\r\n\r\n",
    b"GET /" + b"p" * 300000 + b" HTTP/1.1\r\n\r\n",
    b"GET /api/report HTTP/1.1\r\n" + b"H: 1\r\n" * 20000 + b"\r\n",
    b"POST /api/query HTTP/1.1\r\n" + b"Content-Length: 2\r\n" * 3 + b"\r\n{}",
    b"POST /api/query HTTP/1.1\r\nContent-Length: 2\r\n\r\n{}GET /api/report HTTP/1.1\r\n\r\n",
    b"\x00\x01\x02GET / HTTP/1.1\r\n\r\n",
]
EDITS = [b"\r", b"\n", b" ", b":", b"0", b"9", b"?", b"\t", b"-", b"\x00", b"\xff", b"/", b"G", b"Content-Length", b"\r\n\r\n"]


def mutate(rng, raw):
    b = bytearray(raw)
    for _ in range(rng.randint(1, 4)):
        op = rng.random()
        i = rng.randint(0, len(b)) if b else 0
        if op < 0.4 and b:
            del b[i:i + rng.randint(1, 3)]
        elif op < 0.8:
            b[i:i] = rng.choice(EDITS)
        elif b:
            b[min(i, len(b) - 1)] = rng.randint(0, 255)
    return bytes(b)


VALID = [req("POST", "/api/query", body={"select": {"section": ["time"]}, "q": "zone"}),
         req("GET", "/api/report"), req("GET", "/"),
         req("POST", "/api/whatif/set", body={"path": ["time", "timeZone"], "value": "Asia/Tokyo"}),
         req("POST", "/api/whatif/reset", body={"path": ["time", "timeZone"]}), req("POST", "/api/facet", body={"ask": []})]


def main():
    old, new = sys.argv[1], sys.argv[2]
    n = int(sys.argv[3])
    seed = int(sys.argv[4]) if len(sys.argv) > 4 else 1
    frames = int(sys.argv[5]) if len(sys.argv) > 5 else 0
    rng = random.Random(seed)
    stats, bad = {}, []

    def tally(key):
        stats[key] = stats.get(key, 0) + 1

    def check(i, wire, a, b):
        if same(a, b):
            return True
        bad.append((i, wire, a, b))
        return False

    overlay_paths = []
    for i in range(n):
        method, path, body, raw = gen_api(rng, overlay_paths)
        wire = req(method, path, body=body) if raw is None else req(method, path, raw=raw)
        a = exchange(old, wire)
        b = exchange(new, wire)
        if not check(i, wire, a, b):
            if len(bad) >= 5:
                break
            continue
        status = a.split(b" ", 2)[1] if a[:5] == b"HTTP/" else b"none"
        tally("api %s %s" % (method, status.decode("latin1")))
        if path == "/api/whatif/set" and status == b"200":
            try:
                ops = json.loads(a.partition(b"\r\n\r\n")[2]).get("options", [])
                overlay_paths = [o["path"].split(".") for o in ops if isinstance(o, dict) and "path" in o][:8] \
                    or overlay_paths
            except ValueError:
                pass
        if path == "/api/whatif/clear":
            overlay_paths = []
    for i in range(frames):
        raw = rng.choice(FRAMES_FIXED) if rng.random() < 0.5 else mutate(rng, rng.choice(VALID))
        if rng.random() < 0.1:
            raw = raw[: rng.randint(0, len(raw))]
        a = exchange(old, raw, wait=1.0)
        b = exchange(new, raw, wait=1.0)
        if not check("frame", raw, a, b):
            if len(bad) >= 5:
                break
            continue
        tally("frame " + (a[9:12].decode("latin1") if a[:5] == b"HTTP/" else ("no reply" if not a else "other")))
    print("requests: %d api, %d framings; %s" % (n, frames, ", ".join("%s: %d" % kv for kv in sorted(stats.items()))))
    for i, wire, a, b in bad:
        print("DIFF case %s\n  request: %r\n  old:     %r\n  new:     %r" % (i, wire[:300], a[:300], b[:300]))
    print("same" if not bad else "DIVERGENT: %d" % len(bad))
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
