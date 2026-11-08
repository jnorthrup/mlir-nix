#!/bin/sh
# scripts/ipns-demo/publish.sh HOST
#
# One host's build of mlnix, published under its own IPNS name (docs/IPNS-DEMO.md): the binaries of build/bin and manifest.json,
# what this build is (the platform, the compiler and C++ library it links, the LLVM it was built against, a hash of the
# sources, a hash of each binary) and what it did (the gates run here, and sumo-nix's full ontology).  The Mac and Kali build
# the same sources separately: the source hashes agree, the binary hashes do not.  Run from the mlir-nix root.
set -e
host=$1
export IPFS_PATH="$HOME/.cache/bc-coop/ipfs-demo-$host"
ROOT=$(pwd)
OUT="$HOME/.cache/bc-coop/ipns-demo-$host"
rm -rf "$OUT" && mkdir -p "$OUT/bin"
for b in mlnix mlnix-opt mlnix-kif; do cp "build/bin/$b" "$OUT/bin/"; done

python3 - "$host" "$ROOT" "$OUT" <<'PY'
import hashlib, json, os, platform, re, subprocess, sys, time
host, root, out = sys.argv[1:4]
def run(*c, **k):
    try: return subprocess.run(c, capture_output=True, text=True, timeout=k.get("timeout", 600), cwd=k.get("cwd", root), env=k.get("env")).stdout
    except Exception as e: return f"({e})"
def sha(p): return hashlib.sha256(open(p, "rb").read()).hexdigest()
cache = open(os.path.join(root, "build", "CMakeCache.txt")).read()
cv = lambda k: (re.search(r"^%s:[A-Z]+=(.*)$" % re.escape(k), cache, re.M) or [None, ""])[1]
cxx = cv("CMAKE_CXX_COMPILER")
if cxx.startswith("/Library/Developer") or not cxx: cxx = cxx or "c++"
mlnix = os.path.join(root, "build", "bin", "mlnix")
links = run("otool", "-L", mlnix) if sys.platform == "darwin" else run("ldd", mlnix)
stdlib = "libc++" if "libc++" in links else "libstdc++" if "libstdc++" in links else "static or unknown"
# the sources: every file of lib, include, tools and the top CMakeLists, in path order
files = sorted(os.path.join(d, f) for top in ("lib", "include", "tools") for d, _, fs in os.walk(os.path.join(root, top)) for f in fs
               if not f.endswith((".pyc",)) and "__pycache__" not in d) + [os.path.join(root, "CMakeLists.txt")]
h = hashlib.sha256()
for f in files: h.update(os.path.relpath(f, root).encode() + b"\0" + hashlib.sha256(open(f, "rb").read()).digest())
gates = {}
for name, cmd, env in [("lang", ["python3", "scripts/run-lang-tests.py", "--mlnix", "build/bin/mlnix"], None),
                       ("lang-defer", ["python3", "scripts/run-lang-tests.py", "--mlnix", "build/bin/mlnix"], dict(os.environ, MLNIX_DEFER="1")),
                       ("primops", ["python3", "scripts/check-prims.py"], None)]:
    o = run(*cmd, env=env).strip().split("\n")
    gates[name] = o[-1] if o else ""
sumo = os.path.expanduser("~/work/sumo-nix")
onto = os.path.join(out, "onto.nix")
src = open(os.path.expanduser("~/work/sumo-bench/onto.nix") if os.path.exists(os.path.expanduser("~/work/sumo-bench/onto.nix"))
           else os.path.join(root, "scripts", "ipns-demo", "onto.nix")).read()
open(onto, "w").write(re.sub(r"root \? [^,]+,", f"root ? {sumo},", src))
t = time.time(); ans = run(mlnix, "eval", "--strict", "--json", onto, "--arg", "n", "null"); dt = time.time() - t
m = {
  "host": host,
  "platform": {"system": platform.system(), "release": platform.release(), "machine": platform.machine(),
               "os": run("sw_vers", "-productVersion").strip() if sys.platform == "darwin" else (open("/etc/os-release").read().split("PRETTY_NAME=")[1].split("\n")[0].strip('"'))},
  "compiler": run(cxx, "--version").split("\n")[0], "c++ library": stdlib,
  "llvm": cv("MLIR_DIR") or cv("LLVM_DIR"), "build type": cv("CMAKE_BUILD_TYPE"),
  "sources": {"files": len(files), "sha256": h.hexdigest()},
  "binaries": {b: {"sha256": sha(os.path.join(out, "bin", b)), "bytes": os.path.getsize(os.path.join(out, "bin", b))} for b in sorted(os.listdir(os.path.join(out, "bin")))},
  "gates": gates,
  "sumo-full ontology": {"answer": json.loads(ans) if ans.startswith("{") else ans, "seconds": round(dt, 2),
                         "memory": "measured on kali only (12 GB cgroup, no swap); see docs/PRELOAD-DIALECTS.md" if host != "kali" else None},
  "published": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
}
if host == "kali":
    import resource
    p = subprocess.run(["sudo", "-n", "systemd-run", "--scope", "-q", f"--uid={os.getuid()}", f"--gid={os.getgid()}", "-p", "MemoryMax=12G",
                        "-p", "MemorySwapMax=0", "-E", f"HOME={os.environ['HOME']}", mlnix, "eval", "--strict", "--json", onto, "--arg", "n", "null"],
                       capture_output=True)
    m["sumo-full ontology"]["memory"] = {"peak MB": resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss // 1024, "rc": p.returncode,
                                         "cap": "12 GB cgroup, no swap"}
json.dump(m, open(os.path.join(out, "manifest.json"), "w"), indent=1, sort_keys=True)
print(json.dumps({k: m[k] for k in ("compiler", "c++ library", "sources", "gates")}, indent=1))
PY

cid=$(ipfs add -r -Q --pin "$OUT")
ipfs key list | grep -qx "mlnix-$host" || ipfs key gen --type=ed25519 "mlnix-$host" >/dev/null
name=$(ipfs key list -l | awk -v k="mlnix-$host" '$2 == k {print $1}')
ipfs name publish --key="mlnix-$host" --lifetime=72h --ttl=1m --allow-offline "/ipfs/$cid" >/dev/null
echo "cid  $cid"
echo "ipns $name"
echo "$name" > "$OUT.ipns"
