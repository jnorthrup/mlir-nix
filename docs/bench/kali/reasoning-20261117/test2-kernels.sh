#!/bin/bash
# Kali: test 2's Vampire-Hammer theorems (the problems Vampire solved, re-proved in Lean from the axioms its proofs used)
# through the three kernels that read lean4export's format, as kif-chase's certificates are checked.
#   export.sh   -> ~/vampire-test/export: src/ (each proved file, its theorem renamed tq_<set>_<test>), build/ (.olean),
#                  all.ndjson (leanexport of every theorem and what it depends on), the kernels' verdicts, a control.
set -u
V=~/vampire-test
H=$V/src/vampire-hammer
E=$V/export
T=~/.elan/toolchains/leanprover--lean4---v4.36.0/bin
# the hammer's package is pinned to Lean v4.34.1, whose toolchain ships no exporter: lean4export's tag v4.34.0 (format 3.1.0,
# the one the v4.36.0 toolchain's leanexport writes), built with v4.34.1 in $V/src/lean4export-4.34
X=$V/src/lean4export-4.34/.lake/build/bin/lean4export
# lean is elan's, which takes the hammer package's toolchain; the kernels are named by their path in v4.36.0's
export PATH=$HOME/.elan/toolchains/leanprover--lean4---v4.34.1/bin:$HOME/.elan/bin:/usr/local/bin:/usr/bin:/bin
mkdir -p $E/src $E/build && cd $E
timed() { # LABEL OUT ERR CMD..: CMD's stdout to OUT, its stderr to ERR; its wall time and peak RSS to this script's stdout
  python3 -c '
import resource, subprocess, sys, time
label, out, err, cmd = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
t = time.time()
with open(out, "w") as o, open(err, "w") as e:
    rc = subprocess.call(cmd, stdout=o, stderr=e)
dt = time.time() - t
print(f"{label:44} rc={rc} {dt:7.2f} s {resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss / 1024:7.0f} MB", flush=True)
sys.exit(rc)' "$@"
}
LAKE=~/.elan/bin/lake
# as test 2 ran them (scripts/09-hammer.py): `lake env lean` in the vampire-hammer package, which finds Vampire; lake env adds
# the package's paths to LEAN_PATH, here the build directory of these modules
export LEAN_PATH=$E/build
# the proved theorems: results.json's hammer "proved", and the hand-encoded THF TQC2
python3 - $V <<'EOF' > list.tsv
import json, sys
v = sys.argv[1]
for t in json.load(open(f"{v}/logs/final/results.json")):
    for src, x in t.items():
        if isinstance(x, dict) and isinstance(x.get("hammer"), dict) and x["hammer"].get("hammer") == "proved":
            print(src, t["test"], x["hammer"]["lean_file"], sep="\t")
print("thf", "TQC2", f"{v}/lean/thf/TQC2.lean", sep="\t")
EOF
echo "$(wc -l < list.tsv) theorems"
: > names.txt; : > modules.txt
while IFS=$'\t' read -r set test file; do
  id=$(echo "${set}_${test}" | tr -c 'A-Za-z0-9_\n' '_')
  mod=H_$id
  t=${test//-/_}
  sed -E "s/\btq_${t}\b/tq_${id}/g" "$file" > src/$mod.lean
  grep -q "theorem tq_${id}" src/$mod.lean || { echo "no theorem tq_${id} in src/$mod.lean"; continue; }
  # compiling runs the hammer, which runs Vampire (portfolio mode, 7 cores): once in three runs here a Vampire deadlocked
  # (asleep on a futex, its workers gone, deaf to SIGTERM) and the compile waited on it; so a compile has 120 s, and a stuck
  # Vampire is killed before the next attempt
  for try in 1 2 3; do
    [ -f build/$mod.olean ] && break
    (cd $H && timed "compile $mod" $E/build/$mod.out $E/build/$mod.err timeout -k 5 120 $LAKE env lean --root=$E/src -o $E/build/$mod.olean $E/src/$mod.lean) \
      || { echo "  attempt $try: $(tail -c 200 build/$mod.err)"; pkill -9 -u "$(id -u)" -f "$H/.lake/vampire/build/vampire"; rm -f build/$mod.olean; }
  done
  [ -f build/$mod.olean ] || { echo "  no olean: $(head -c 300 build/$mod.out) $(head -c 300 build/$mod.err)"; continue; }
  grep -h "depends on axioms" build/$mod.out | head -1
  echo "tq_${id}" >> names.txt; echo "$mod" >> modules.txt
done < list.tsv
{ sed 's/^/import /' modules.txt; } > src/All.lean
(cd $H && timed "compile All" $E/build/All.out $E/build/All.err $LAKE env lean --root=$E/src -o $E/build/All.olean $E/src/All.lean)
(cd $H && timed "lean4export All ($(wc -l < $E/names.txt) theorems)" $E/all.ndjson $E/export.err $LAKE env $X All -- $(cat $E/names.txt))
head -c 300 export.err
echo "all.ndjson: $(stat -c %s all.ndjson) bytes, $(grep -c . all.ndjson) records"
# the export's declarations; each theorem's proof as a DAG of expressions; base.ndjson, the file without the 29 theorems (the
# library their proofs use: what checking them costs is all.ndjson's time less base.ndjson's); and the control,
# swapped.ndjson: two theorems' statements swapped, the two records moved to the end (where every expression is defined:
# nothing depends on them), so each proof is checked against the other's statement
python3 - all.ndjson base.ndjson swapped.ndjson <<'EOF'
import json, sys, collections
names, kids, consts, kinds, thms, axioms = {0: ()}, {}, {}, collections.Counter(), [], []
for n, line in enumerate(open(sys.argv[1])):
    r = json.loads(line)
    if "in" in r:
        x = r.get("str") or r.get("num")
        names[r["in"]] = names[x["pre"]] + ((x["str"] if "str" in r else x["i"]),)
    elif "ie" in r:
        k = next(k for k in r if k != "ie")
        f = r[k]
        if isinstance(f, dict):
            kids[r["ie"]] = tuple(f[x] for x in ("fn", "arg", "type", "body", "value", "struct", "expr")
                                  if x in f and isinstance(f[x], int))
            if k == "const":
                consts[r["ie"]] = f["name"]
        else:
            kids[r["ie"]] = ()
    elif "il" not in r and "meta" not in r:
        k = next(iter(r))
        kinds[k] += 1
        nm = ".".join(map(str, names[r[k]["name"]])) if "name" in r[k] else ""  # an inductive block names its types inside
        if k == "axiom":
            axioms.append(nm)
        if k == "thm" and nm.startswith("tq_"):  # a test's theorem, or a lemma its elaboration made (tq_...._proof_1)
            thms.append((n, nm, r))
print("declarations:", dict(kinds), "axioms:", sorted(axioms))
def dag(root):  # the distinct expressions under root, and the constants they name
    seen, named, todo = set(), set(), [root]
    while todo:
        e = todo.pop()
        if e not in seen:
            seen.add(e)
            if e in consts:
                named.add(consts[e])
            todo.extend(kids[e])
    return len(seen), named
sizes = []
for n, nm, r in thms:
    (ns, _), (nv, cv) = dag(r["thm"]["type"]), dag(r["thm"]["value"])
    if "." not in nm:
        sizes.append(nv)
    print(f"  {nm:34} statement {ns:6} expressions, proof {nv:7} expressions naming {len(cv):4} constants")
sizes.sort()
print(f"{len(sizes)} theorems (and {len(thms) - len(sizes)} lemmas their elaboration made): proofs of {sizes[0]}..{sizes[-1]} "
      f"expressions, median {sizes[len(sizes) // 2]}")
drop = {n for n, _, _ in thms}
main = [t for t in thms if "." not in t[1]]
(n0, a0, ra), (n1, a1, rb) = main[0], main[1]
ra2 = {"thm": dict(ra["thm"], type=rb["thm"]["type"])}
rb2 = {"thm": dict(rb["thm"], type=ra["thm"]["type"])}
with open(sys.argv[2], "w") as base, open(sys.argv[3], "w") as swapped:
    for n, line in enumerate(open(sys.argv[1])):
        if n not in drop:
            base.write(line)
        if n not in (n0, n1):
            swapped.write(line)
    for r in (ra2, rb2):
        swapped.write(json.dumps(r, separators=(",", ":"), ensure_ascii=False) + "\n")
print(f"control: the statements of {a0} and {a1} swapped")
EOF
for f in all base swapped; do
  cat > nanoda-$f.json <<EOF
{"export_file_path": "$E/$f.ndjson", "use_stdin": false, "permitted_axioms": ["propext", "Classical.choice", "Quot.sound"],
 "unpermitted_axiom_hard_error": true, "nat_extension": true, "string_extension": true, "print_success_message": true}
EOF
  for k in "nanoda_bin nanoda-$f.json" "con-leche --verified --jobs=1 $f.ndjson" "con-ron --verified --jobs=1 $f.ndjson"; do
    set -- $k; c=$1; shift; timed "$c $f" k.out k.err timeout 1800 $T/$c "$@"
    { cat k.out k.err; } | grep -E "^(Checked|Error|error|con-leche:|con-ron:|thread|assertion)" | head -3 | cut -c1-200
  done
done
rm -f k.out k.err
