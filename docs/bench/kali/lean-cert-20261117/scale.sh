#!/bin/bash
# How the three kernels' time grows with the size of a certificate: N facts (p xi), rules p -> q -> r -> s, so 3N lets and
# 2N + 8 hypotheses.  Each checker gets 300 s.
B=~/kif-assess/mlir-nix-cx; T=~/.elan/toolchains/leanprover--lean4---v4.36.0/bin; export PATH=$T:$B/build/bin:$PATH
cd ~/lean-cert/scale
timed() { # label cmd...: wall seconds, peak RSS, the verdict's last line
  python3 - "$@" <<'PY'
import os, subprocess, sys, time
t = time.time()
p = subprocess.Popen(["timeout", "120"] + sys.argv[2:], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
out = p.stdout.read().decode("utf-8", "replace")
_, st, ru = os.wait4(p.pid, 0)
rc = os.waitstatus_to_exitcode(st)
last = [l for l in out.splitlines() if l.strip()]
print(f"{sys.argv[1]:28} rc={rc:3} {time.time()-t:8.2f} s {ru.ru_maxrss/1024:7.0f} MB | {(last[0] if last else '')[:90]}", flush=True)
PY
}
for N in ${NS:-500 1000 2000 4000}; do
 for K in ${KINDS:-s}; do
  # s: a chain p -> q -> r -> s for each of N atoms; h: a hub every q uses, (=> (and (hub) (p ?x)) (q ?x))
  python3 -c "
import sys
n, k = int(sys.argv[1]), sys.argv[2]
print('\n'.join(f'(p x{i})' for i in range(n)))
if k == 's': print('(=> (p ?x) (q ?x))\n(=> (q ?x) (r ?x))\n(=> (r ?x) (s ?x))')
else: print('(base)\n(=> (base) (hub))\n(=> (and (hub) (p ?x)) (q ?x))\n(=> (q ?x) (r ?x))')" $N $K > $K$N.kif
  f=$K$N
  mlnix-kif --chase --lean $f.ndjson $f.kif && mlnix-kif --chase --dump $f.kif > $f.dump
  python3 $B/scripts/kif-lean-check.py $PWD/$f.ndjson $f.dump --nanoda-config $PWD/$f.json | tail -1 | cut -c1-70
  echo "$f: $(stat -c %s $f.ndjson) bytes"
  timed "nanoda_bin $f" nanoda_bin $PWD/$f.json
  timed "con-leche $f" con-leche --verified --jobs=1 $f.ndjson
  timed "con-ron $f" con-ron --verified --jobs=1 $f.ndjson
 done
done
