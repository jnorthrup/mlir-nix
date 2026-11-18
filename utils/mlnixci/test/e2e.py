#!/usr/bin/env python3
"""End-to-end check of a running mlnixci on os/: python3 test/e2e.py http://host:port [os-dir]

The corpus is read only: os/settings.json must be byte for byte what it was.  What changes is the what-if overlay."""
import hashlib, json, os, sys, urllib.request, urllib.error

B = sys.argv[1].rstrip("/")
OS = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(__file__), "..", "os")
failures = 0


def call(method, path, body=None, raw=None):
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    req = urllib.request.Request(B + path, data=data, method=method,
                                 headers={"Content-Type": "application/json"} if data else {})
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return r.status, r.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()


def check(name, cond, info: object = ""):
    global failures
    failures += not cond
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else "  -> " + str(info)[:400]))


def q(select=None, text="", **kw):
    s, b = call("POST", "/api/query", dict(select=select or {}, q=text, **kw))
    return s, json.loads(b) if s == 200 else b


def counts(res, facet):
    return {v["v"]: v["n"] for f in res["facets"] if f["name"] == facet for v in f["values"]}


def paths(res):
    return [".".join(h["row"]["path"]) for h in res["hits"]]


def report():
    return json.loads(call("GET", "/api/report")[1])


settings_hash = hashlib.sha256(open(os.path.join(OS, "settings.json"), "rb").read()).hexdigest()

# ---- facets
s, r = q()
check("query: 7 options, all hits", s == 200 and r["total"] == 7 and r["rows"] == 7, (s, r))
check("section counts", counts(r, "section") == {"networking": 3, "services": 3, "time": 1}, counts(r, "section"))
check("kind facet names the type, not its arguments", "strMatching" in counts(r, "kind"), counts(r, "kind"))
check("state facet", counts(r, "state") == {"set": 3, "default": 4}, counts(r, "state"))
check("module facet", counts(r, "module") == {"options.nix": 7}, counts(r, "module"))
check("nothing changed yet", counts(r, "whatif") == {"same": 7, "changed": 0}, counts(r, "whatif"))
check("the query ran compiled", isinstance(r.get("queryMs"), (int, float)), r.get("queryMs"))

s, r = q({"section": ["services"]})
check("select a section", r["total"] == 3 and all(p.startswith("services.") for p in paths(r)), paths(r))
check("a column's own counts ignore its selection", counts(r, "section")["networking"] == 3, counts(r, "section"))
check("the other columns count the selection", counts(r, "state") == {"set": 1, "default": 2}, counts(r, "state"))
check("the selected value is on", [v["v"] for f in r["facets"] if f["name"] == "section" for v in f["values"] if v["on"]] == ["services"])

s, r = q({"state": ["set"]}, "host")
check("text and state together", paths(r) == ["networking.hostName"], paths(r))
check("match counts", counts(r, "match") == {"no": 2, "yes": 1}, counts(r, "match"))
# the query is read as the search text is: its escapes ("\/" is '/', "\u0048" is 'H') read, then lower-cased
s, b = call("POST", "/api/query", raw=br'{"q": "\/ETC\/\u0048ostname"}')
r = json.loads(b) if s == 200 else {}
check("a query's escapes read, then lower-cased", paths(r) == ["networking.hostName"], (s, b[:300]))
s, r = q({"section": ["networking", "time"], "kind": ["bool", "enum"]})
check("two values in two columns", sorted(paths(r)) == ["networking.firewall.enable", "time.timeZone"], paths(r))
s, r = q({}, "", offset=2, limit=2)
check("offset and limit page the hits", r["total"] == 7 and len(r["hits"]) == 2, r)

# ---- what-if
s, b = call("POST", "/api/whatif/set", {"path": ["networking", "hostName"], "value": "edge-1"})
rep = json.loads(b) if s == 200 else {}
ch = {o["path"]: o for o in rep.get("options", [])}
check("what-if hostName", s == 200 and ch.get("networking.hostName", {}).get("to") == "edge-1"
      and ch["networking.hostName"]["from"] == "mlnix-os", (s, b[:300]))
check("its /etc file in the report", [e for e in rep.get("etc", []) if e["name"] == "hostname"] ==
      [{"name": "hostname", "from": "mlnix-os\n", "to": "edge-1\n"}], rep.get("etc"))
s, b = call("POST", "/api/whatif/set", {"path": ["networking", "hostName"], "value": "bad host!"})
check("hostName outside strMatching refused", s == 422 and "error" in json.loads(b), (s, b[:300]))
check("a refusal keeps the overlay", json.loads(report()["overlay"]) == {"networking": {"hostName": "edge-1"}}, report()["overlay"])
s, b = call("POST", "/api/whatif/set", {"path": ["networking", "firewall", "allowedTCPPorts"], "value": [22, 70000]})
check("port 70000 refused", s == 422, (s, b[:300]))

tricky = 'Grüße "quoted" back\\slash ${notinterp} tab\tend\nsecond line ✓'
s, b = call("POST", "/api/whatif/set", {"path": ["services", "motd", "text"], "value": tricky})
check("non-ASCII, quotes, backslash, ${ round-trip", s == 200 and
      {o["path"]: o for o in json.loads(b)["options"]}["services.motd.text"]["to"] == tricky, (s, b[:300]))
s, b = call("POST", "/api/whatif/set", {"path": ["time", "timeZone"], "value": "Asia/Tokyo"})
tz = {o["path"]: o for o in json.loads(b)["options"]}.get("time.timeZone", {}) if s == 200 else {}
check("an option at its default set: state and value change", tz.get("fromState") == "default" and tz.get("toState") == "set"
      and tz.get("to") == "Asia/Tokyo", (s, b[:300]))
s, b = call("POST", "/api/whatif/set", {"path": ["time", "timeZone"], "value": "Mars/Olympus"})
check("enum outside choices refused", s == 422, (s, b[:200]))

s, r = q({"whatif": ["changed"]})
check("the what-if facet selects the changed options", sorted(paths(r)) == ["networking.hostName", "services.motd.text", "time.timeZone"], paths(r))
h = {".".join(x["row"]["path"]): x for x in r["hits"]}
check("a changed hit carries its base", h["networking.hostName"].get("base", {}).get("value") == "mlnix-os", h.get("networking.hostName"))

s, b = call("POST", "/api/whatif/reset", {"path": ["networking", "hostName"]})
check("reset one", s == 200 and "networking.hostName" not in {o["path"] for o in json.loads(b)["options"]}, (s, b[:300]))
check("reset drops the emptied object", "networking" not in json.loads(report()["overlay"]), report()["overlay"])
s, b = call("POST", "/api/whatif/reset", {"path": ["networking", "hostName"]})
check("reset of an absent member", s == 200, (s, b[:200]))
s, b = call("POST", "/api/whatif/clear")
check("clear", s == 200 and json.loads(b)["options"] == [] and json.loads(b)["etc"] == [] and json.loads(b)["overlay"] == "{}", b[:300])

# ---- the /etc join (columns.mlir's etc_join): a file changed, one removed, two added, in name order
call("POST", "/api/whatif/set", {"path": ["networking", "firewall", "allowedTCPPorts"], "value": [22, 80]})
call("POST", "/api/whatif/set", {"path": ["services", "motd", "enable"], "value": False})
call("POST", "/api/whatif/set", {"path": ["etc", "aaa-first"], "value": "first\n"})
s, b = call("POST", "/api/whatif/set", {"path": ["etc", "zzz-last"], "value": "last\n"})
etc = json.loads(b).get("etc", []) if s == 200 else []
check("the /etc join: changed, removed and added files, in name order",
      [(e["name"], e["from"] is None, e["to"] is None) for e in etc] == [("aaa-first", True, False),
      ("mlnixci/firewall.rules", False, False), ("motd", False, True), ("zzz-last", True, False)], (s, etc))
s, b = call("POST", "/api/whatif/clear")
check("clear again", s == 200 and json.loads(b)["etc"] == [], b[:300])

# ---- the facets asked for on demand: answer.nix, through eval.nix --arg request
def ask(*asks):
    s, b = call("POST", "/api/facet", {"ask": [{"iface": i, "path": p} for i, p in asks]})
    return s, (json.loads(b)["answers"] if s == 200 else b)


host = open("/proc/sys/kernel/hostname").read().strip() if os.path.exists("/proc/sys/kernel/hostname") else None
s, a = ask(("adhesion", ["networking", "hostName"]), ("live", ["networking", "hostName"]), ("module", []), ("nope", []))
check("facet: adhesion, the declaration's file and line", s == 200 and a[0]["declared"][0]["file"] == "options.nix"
      and a[0]["declared"][0]["line"] == 5 and a[0]["defined"] == ["settings.json"], (s, a))
check("facet: live, the running system's beside the configured", s == 200 and a[1]["live"] == host
      and a[1]["configured"] == "mlnix-os" and a[1]["source"] == "/proc/sys/kernel/hostname", a[1] if s == 200 else a)
check("facet: no what-if, an empty module", s == 200 and a[2]["count"] == 0, a[2] if s == 200 else a)
check("facet: an unknown one answers its error", s == 200 and a[3].get("error") == "no facet nope", a[3] if s == 200 else a)
call("POST", "/api/whatif/set", {"path": ["networking", "hostName"], "value": "edge-1"})
s, a = ask(("module", []), ("adhesion", ["networking", "hostName"]), ("live", ["networking", "hostName"]))
check("facet: the what-if as the module it adheres as", s == 200 and a[0]["count"] == 1
      and '  networking.hostName = lib.mkForce "edge-1";\n' in a[0]["text"], a)
check("facet: the what-if defines it, at mkForce", s == 200 and a[1]["defined"] == ["mlnixci what-if"]
      and a[1]["priority"] == 50 and a[2]["configured"] == "edge-1", a)
call("POST", "/api/whatif/clear")
s, b = call("POST", "/api/facet", raw=b"[1]")
check("facet: not an object 400", s == 400, (s, b))
for cut in (b'{"ask": ', b'{"ask": [', b'{"ask": [{"iface": "live"', b'{"ask": [{"iface": "}"'):
    s, b = call("POST", "/api/facet", raw=cut)
    check("facet: cut short 400 " + cut.decode(), s == 400, (s, b))

# ---- requests that are wrong, and the rest
s, b = call("POST", "/api/whatif/set", raw=b'{"path": ["x"], "value": ')
check("malformed body 400", s == 400, (s, b))
s, b = call("POST", "/api/whatif/set", {"path": "networking", "value": 1})
check("path not an array 400", s == 400, (s, b))
s, b = call("POST", "/api/query", raw=b"[1]")
check("query not an object 400", s == 400, (s, b))
s, b = call("GET", "/nope")
check("unknown route 404", s == 404, s)
for gone in ("/api/commit", "/api/set"):
    check("no " + gone, call("POST", gone)[0] == 404)
s, b = call("GET", "/")
check("page", s == 200 and "<title>mlnixci</title>" in b, s)
check("settings.json untouched", hashlib.sha256(open(os.path.join(OS, "settings.json"), "rb").read()).hexdigest() == settings_hash)
sys.exit(1 if failures else 0)
