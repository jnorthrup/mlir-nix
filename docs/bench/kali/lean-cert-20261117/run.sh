#!/bin/bash
# kif-chase's paperclip stratum 1 (test 1's workload) as a Lean certificate: mlnix-kif --lean, decoded against the dump,
# checked by nanoda_bin, con-leche and con-ron; run inside a 4 GB scope on Kali.
B=~/kif-assess/mlir-nix-cx; T=~/.elan/toolchains/leanprover--lean4---v4.36.0/bin
export PATH=$T:$B/build/bin:$PATH
O=~/lean-cert/paperclip; mkdir -p $O; cd $O; rm -f *.ndjson *.dump *.txt
S=~/kif-assess/sumo-nix/paperclip
K="$B/test/kif/paperclip-structural.kif $S/world.kif $S/analysis.kif"
{
echo "== inputs"; sha256sum $K | cut -c1-16,64-; git -C $B log --oneline -1; uptime
echo "== mlnix-kif --chase --lean, three runs (its --stats: the phases' times and peak RSS)"
for i in 1 2 3; do
  python3 - "$K" <<'PY'
import os, subprocess, sys, time
t = time.time()
p = subprocess.run(["mlnix-kif", "--chase", "--lean", "pc.ndjson", "--stats"] + sys.argv[1].split(), capture_output=True, text=True)
ru = os.wait4 if False else None
import resource
print(f"rc={p.returncode} wall {time.time()-t:.3f} s, max RSS {resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss/1024:.0f} MB |", " | ".join(l for l in p.stderr.splitlines() if l.startswith(("chase", "lean", "read"))))
PY
done
mlnix-kif --chase --dump $K > pc.dump
echo "== the certificate"; ls -l pc.ndjson | awk '{print $5 " bytes"}'; wc -l < pc.ndjson; sha256sum pc.ndjson | cut -c1-16
python3 -c "
import json, collections
c = collections.Counter()
for l in open('pc.ndjson'):
    o = json.loads(l); c[next(k for k in o if k not in ('ie','in','il'))] += 1
print(dict(c))"
echo "== the dump"; wc -l < pc.dump; grep -c -v "	-$" pc.dump
echo "== decoded against the dump"
s=$(date +%s.%N); python3 $B/scripts/kif-lean-check.py pc.ndjson pc.dump; echo "rc=$? $(python3 -c "print(round($(date +%s.%N)-$s,2))") s"
echo "== kernels, three runs each"
for i in 1 2 3; do python3 $B/scripts/kif-lean-kernels.py $PWD/pc.ndjson pc.dump --times; done
echo "== kernels on the controls"
python3 $B/scripts/kif-lean-kernels.py $PWD/pc.ndjson pc.dump --controls --times
echo "== con-leche, all threads"; s=$(date +%s.%N); con-leche --verified pc.ndjson 2>&1 | tail -1; echo "$(python3 -c "print(round($(date +%s.%N)-$s,2))") s"
uptime
} 2>&1
