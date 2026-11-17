#!/bin/bash
# Kali: the certificate in pieces (mlnix-kif --lean-piece), on what one theorem could not hold.
#   pieces.sh            the synthetic theories s16000 and h16000 (scale.sh's), and SUMO's taxonomy (sumo/subclass.kif:
#                        sumo.full's 10,308 subclass edges and transitivity, whose closure is sumo.nix's 90,404 links)
# For each workload and piece size: the certificate written (time, peak RSS, size), its claims decoded and compared with
# the chase's dump (kif-lean-check.py), and the three kernels on it (kif-lean-kernels.py --times, 900 s each), with the
# controls for the size given in CONTROLS.  Output under ~/lean-cert/pieces.
set -u
B=~/kif-assess/mlir-nix-cx
export PATH=$B/build/bin:$HOME/.elan/toolchains/leanprover--lean4---v4.36.0/bin:$PATH
O=~/lean-cert/pieces
mkdir -p $O && cd $O
cp ~/lean-cert/scale/s16000.kif ~/lean-cert/scale/h16000.kif ~/lean-cert/sumo/subclass.kif .
timed() { # LABEL CMD..: wall time and peak RSS of CMD
  python3 -c '
import resource, subprocess, sys, time
t = time.time(); rc = subprocess.call(sys.argv[2:]); dt = time.time() - t
print(f"{sys.argv[1]:34} rc={rc} {dt:7.2f} s {resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss / 1024:7.0f} MB", flush=True)
sys.exit(rc)' "$@"
}
for w in ${WORKLOADS:-s16000 h16000 subclass}; do
  mlnix-kif --chase --dump $w.kif > $w.dump
  echo "== $w: $(grep -c . $w.dump) facts in the closure, $(awk -F'\t' '$2 != "-"' $w.dump | wc -l) derived"
  for p in ${PIECES:-4000 8000 16000}; do
    f=$w.p$p
    timed "write $f" mlnix-kif --chase --lean $f.ndjson --lean-piece $p --stats $w.kif 2> $f.stats
    grep -E "^(chase|lean):" $f.stats | tr '\n' ' '; echo "$(stat -c %s $f.ndjson) bytes"
    timed "decode $f" python3 $B/scripts/kif-lean-check.py $f.ndjson $w.dump > $f.check
    cat $f.check
    ctl=""; [ "$p" = "${CONTROLS:-8000}" ] && ctl=--controls
    python3 $B/scripts/kif-lean-kernels.py $PWD/$f.ndjson $w.dump --times --timeout 900 $ctl
    rm -f $f.ndjson
  done
done
