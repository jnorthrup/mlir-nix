#!/usr/bin/env python3
"""Outputs built in the mlnixos chroot against Hydra's:  vs-hydra.py CHROOT_HELPER ROOT LOG...
The chroot's store is /nix/store, so a derivation built there has the store path Hydra gave it, and cache.nixos.org's
narinfo for that path carries Hydra's NAR hash.  For each derivation a log says it built, take its outputs (nix-store
-q --outputs inside the chroot), hash each one's NAR inside the chroot (nix-hash --type sha256 --base32), and compare.
Fixed-output paths (sources) are content-addressed: equal by construction, and listed apart."""
import re, subprocess, sys, urllib.request

X, R, logs = sys.argv[1], sys.argv[2], sys.argv[3:]


def chroot(*args):
    r = subprocess.run([X, R, *args], capture_output=True, text=True)
    return r.stdout.strip(), r.returncode


drvs = []
for log in logs:
    for m in re.finditer(r"^building '(/nix/store/[^']+\.drv)'", open(log, errors="replace").read(), re.M):
        if m.group(1) not in drvs:
            drvs.append(m.group(1))
same = diff = missing = fixed = 0
for drv in drvs:
    outs, rc = chroot("/bin/nix-store", "-q", "--outputs", drv)
    if rc:
        continue
    for out in outs.split():
        h = out.split("/")[-1][:32]
        try:
            info = urllib.request.urlopen(f"https://cache.nixos.org/{h}.narinfo", timeout=20).read().decode()
        except Exception:
            missing += 1
            print(f"   not on cache.nixos.org: {out}")
            continue
        hydra = re.search(r"^NarHash: sha256:(\S+)", info, re.M).group(1)
        if re.search(r"^CA: fixed:", info, re.M):
            fixed += 1
        mine, _ = chroot("/bin/nix-hash", "--type", "sha256", "--base32", out)
        if mine == hydra:
            same += 1
        else:
            diff += 1
            print(f"   DIFFERS: {out}\n     chroot {mine}\n     Hydra  {hydra}")
print(f"   {same} the same as Hydra's ({fixed} of them fixed outputs), {diff} different, {missing} not on the cache")
