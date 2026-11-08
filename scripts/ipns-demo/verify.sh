#!/bin/sh
# scripts/ipns-demo/verify.sh HOST OTHER_IPNS_NAME [OTHER_HOST]
#
# From this host's demo node: resolve the other host's IPNS name, fetch what it points to, hash every binary again against the
# manifest, and compare the other build with this one (this host's manifest from publish.sh): the same sources, different
# binaries (another compiler, C++ library or platform), the same sumo-nix answer.
set -e
host=$1; name=$2; other=${3:-other}
export IPFS_PATH="$HOME/.cache/bc-coop/ipfs-demo-$host"
t0=$(python3 -c 'import time;print(time.time())')
path=$(ipfs name resolve --nocache --dht-timeout=30s "/ipns/$name")
t1=$(python3 -c 'import time;print(time.time())')
D="$HOME/.cache/bc-coop/ipns-fetched-$other"
rm -rf "$D" && ipfs get -o "$D" "$path" >/dev/null 2>&1
python3 - "$host" "$name" "$path" "$D" "$HOME/.cache/bc-coop/ipns-demo-$host/manifest.json" "$t0" "$t1" <<'PY'
import hashlib, json, os, sys
host, name, path, d, mine, t0, t1 = sys.argv[1:8]
o = json.load(open(os.path.join(d, "manifest.json"))); m = json.load(open(mine))
ok = True
def check(what, cond, detail=""):
    global ok; ok &= bool(cond); print(("ok   " if cond else "FAIL ") + what + (f"  ({detail})" if detail else ""))
print(f"/ipns/{name} -> {path}  (resolved in {float(t1) - float(t0):.2f} s)")
print(f"{o['host']}: {o['platform']['os']} {o['platform']['machine']}, {o['compiler']}, {o['c++ library']}")
print(f"{m['host']}: {m['platform']['os']} {m['platform']['machine']}, {m['compiler']}, {m['c++ library']}")
for b, x in sorted(o["binaries"].items()):
    got = hashlib.sha256(open(os.path.join(d, "bin", b), "rb").read()).hexdigest()
    check(f"{b}: the fetched bytes have the manifest's sha256", got == x["sha256"], got[:12])
check("the same sources", o["sources"]["sha256"] == m["sources"]["sha256"], o["sources"]["sha256"][:12] + " vs " + m["sources"]["sha256"][:12])
for b in sorted(set(o["binaries"]) & set(m["binaries"])):
    check(f"{b}: a separate build (the binaries differ)", o["binaries"][b]["sha256"] != m["binaries"][b]["sha256"])
check("the same sumo-nix answer", o["sumo-full ontology"]["answer"] == m["sumo-full ontology"]["answer"], json.dumps(o["sumo-full ontology"]["answer"], sort_keys=True)[:90])
for g in sorted(o["gates"]): print(f"     {o['host']} gate {g}: {o['gates'][g]}")
print(f"     {o['host']} sumo-full ontology: {o['sumo-full ontology']['seconds']} s, memory {o['sumo-full ontology']['memory']}")
sys.exit(0 if ok else 1)
PY
