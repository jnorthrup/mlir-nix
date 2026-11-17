#!/bin/bash
# KIF files through test/mlir/kif-trikeshed.mlir's query (sumo-nix's sumo.nix tables written in trikeshed ops over the
# theory, kif-to-trikeshed, trikeshed-lower-cursors, LLVM, compiled) against sumo.nix's own evaluation of the same files
# (test/kif/taxonomy-oracle.nix through mlnix eval).  PRELOAD-DIALECTS step 6.
#
#   scripts/sumo-trikeshed.sh SUMO_NIX BIN OUT [F.kif...]
#
# No files: SUMO_NIX/sumo.full/PINS's 78, in its order.  BIN holds mlnix, mlnix-kif and mlnix-opt; LLVM_BIN (default
# /usr/lib/llvm-22/bin) mlir-opt and mlir-translate; CC (clang-22, clang or LLVM_BIN's clang) links against LLVM_BIN/../lib's
# libmlir_runner_utils.  CAP, when set, is put before each step (a memory cap: on Kali
#   CAP="sudo -n systemd-run --scope -q -p MemoryMax=4G -p MemorySwapMax=0 sudo -n -u $USER --"
# makes an OOM kill the result rather than swap).  Each step's wall time and peak RSS go to OUT/times.txt.
set -u
[ $# -ge 3 ] || { sed -n '2,13p' "$0"; exit 2; }
S=$1; B=$2; O=$3; shift 3
R=$(cd "$(dirname "$0")/.." && pwd)
L=${LLVM_BIN:-/usr/lib/llvm-22/bin}
CC=${CC:-$(command -v clang-22 || command -v clang || echo "$L/clang")}
CAP=${CAP:-}
mkdir -p "$O"; : > "$O/times.txt"
if [ $# -gt 0 ]; then files=("$@"); else
  mapfile -t files < <(grep -v '^#' "$S/sumo.full/PINS" | awk -v d="$S/sumo.full" 'NF >= 2 { print d "/" $2 }')
fi
# step LABEL CMD...: CMD under CAP, its wall time and its peak RSS appended to times.txt
step() {
  local label=$1; shift
  $CAP python3 -c '
import resource, subprocess, sys, time
label, times, cmd = sys.argv[1], sys.argv[2], sys.argv[3:]
t0 = time.monotonic(); rc = subprocess.call(cmd); dt = time.monotonic() - t0
rss = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss / 1024.0
open(times, "a").write("%-10s wall=%6.2fs peakRSS=%5.0fMB rc=%d\n" % (label, dt, rss, rc))
sys.exit(rc)' "$label" "$O/times.txt" "$@" || { echo "$label failed (rc=$?)"; exit 1; }
}
echo "files: ${#files[@]}"
nixfiles="[ ${files[*]} ]"
step oracle "$B/mlnix" eval --strict --json --arg sumo "$S" --arg files "$nixfiles" "$R/test/kif/taxonomy-oracle.nix" > "$O/oracle.json"
step theory "$B/mlnix-kif" "${files[@]}" -o "$O/kb.mlir"
{ sed '1d;$d' "$O/kb.mlir"; cat "$R/test/mlir/kif-trikeshed.mlir"; } > "$O/query.mlir"
step lower "$B/mlnix-opt" "$O/query.mlir" --kif-to-trikeshed --trikeshed-lower-cursors -o "$O/q1.mlir"
step llvm "$L/mlir-opt" "$O/q1.mlir" --ownership-based-buffer-deallocation --canonicalize \
  --buffer-deallocation-simplification --bufferization-lower-deallocations --convert-scf-to-cf --expand-strided-metadata \
  --lower-affine --finalize-memref-to-llvm --convert-arith-to-llvm --convert-index-to-llvm --convert-cf-to-llvm \
  --convert-func-to-llvm --reconcile-unrealized-casts -o "$O/q2.mlir"
step translate "$L/mlir-translate" --mlir-to-llvmir "$O/q2.mlir" -o "$O/q.ll"
step cc "$CC" -O2 -Wno-override-module "$O/q.ll" -L"$L/../lib" -lmlir_runner_utils -Wl,-rpath,"$L/../lib" -o "$O/q"
step query "$O/q" > "$O/query.out"
cat "$O/times.txt"
python3 - "$O" <<'EOF'
import json, re, sys
o = sys.argv[1]
want = json.load(open(o + "/oracle.json"))
got = [[int(x) for x in m.split(",")] for m in re.findall(r"^\[([-0-9, ]*)\]$", open(o + "/query.out").read(), re.M)]
names = "forms classes withParent ancestorLinks things relations humanAncestors".split()
print("sumo.nix :", dict(zip(names, want[0])))
print("trikeshed:", dict(zip(names, got[0])) if got else None)
same = len(got) == 2 and got[0] == want[0] and got[1] == want[1]
print("each class's ancestors (%d classes): %s" % (len(want[1]), "equal" if len(got) == 2 and got[1] == want[1] else "DIFFERENT"))
sys.exit(0 if same else 1)
EOF
