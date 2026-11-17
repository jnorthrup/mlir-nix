#!/bin/bash
# Kali: SUMO's 43 tq.nix-unsupported tests as mlnix-kif --tptp translates them (Merge.kif at SUMO 25bb366 and the test, as
# test 2 gave SigmaKEE the same), through Vampire 5.1.0 as test 2 ran it (--mode casc --cores 2 -t 60), next to test 2's
# results for SigmaKEE's translation (logs/vampire/runs.jsonl, set sigma).
#   run-tests.sh [TESTS...]  -> ~/tptp/tests/<test>.p, .out; a line a test; ~/tptp/tests/results.tsv
#   RESUME=1 run-tests.sh   keeps results.tsv and skips each test that already has its line (a run cut short: the VM rebooted)
set -u
B=~/kif-assess/mlir-nix-cx
V=~/vampire-test
K=$V/sigma-top/KBs/Merge.kif
O=~/tptp/tests
VAMPIRE=$V/opt/vampire-5.1.0/vampire
mkdir -p $O && cd $O
tests=${*:-$(sed 's/\.kif\.tq$//' $V/lists/unsupported43.txt)}
if [ "${RESUME:-0}" = 1 ] && [ -f results.tsv ]; then
  # a line is complete when it has the SigmaKEE column (the last printf), so a test killed mid-line runs again
  done_tests=$(awk -F'\t' 'NF >= 6 || /mlnix-kif failed/ {print $1}' results.tsv)
  awk -F'\t' 'NF >= 6 || /mlnix-kif failed/' results.tsv > results.tsv.keep && mv results.tsv.keep results.tsv
  tests=$(for t in $tests; do echo "$done_tests" | grep -qx "$t" || echo "$t"; done)
  echo "resuming: $(echo "$done_tests" | grep -c .) done, $(echo $tests | wc -w) to run" >&2
else
  : > results.tsv
fi
for t in $tests; do
  f=$V/src/sumo/tests/$t.kif.tq
  $B/build/bin/mlnix-kif --tptp $t.p $K $f 2> $t.err || { printf "%s\tmlnix-kif failed\n" "$t" | tee -a results.tsv; continue; }
  expect=$(grep -o "^(answer [a-z]*" $f | head -1 | cut -c9-)
  conj=$(grep -c "^fof(query_" $t.p)
  skipped=$(grep -A1 "^% f: (query" $t.p | grep -o "not written: .*" | head -1)
  untrans=$(grep -c "^% not written: " $t.p)
  s=$(date +%s.%N)
  if [ "$conj" -gt 0 ]; then # without a conjecture there is nothing to ask
    timeout 90 $VAMPIRE --mode casc --cores 2 -t 60 --memory_limit 1400 --proof tptp --input_syntax tptp $t.p > $t.out 2>&1
  else
    echo "no conjecture" > $t.out
  fi
  e=$(date +%s.%N)
  szs=$(grep -o "SZS status [A-Za-z]*" $t.out | head -1 | cut -d" " -f3)
  [ "$conj" -gt 0 ] || szs="no-conjecture"
  used=$(grep -c "^fof(.*,\(axiom\|conjecture\|plain\),.*file(" $t.out)
  sig=$(python3 -c "
import json,sys
for l in open('$V/logs/vampire/runs.jsonl'):
    r=json.loads(l)
    if r['set']=='sigma' and r['test']=='$t': print(r['szs']); break
")
  cmp=""
  if [ -f $V/problems/sigma/$t/problem.tptp ]; then # the problem test 2 gave Vampire, formula by formula
    python3 $B/scripts/kif-tptp-compare.py --flat $V/problems/sigma/$t/problem.tptp $t.p --examples $t.cmp > $t.cmpsum
    cmp=$(tr -d "," < $t.cmpsum | awk '{printf "%s%s: same %s+%s, SigmaKEE only %s, ours only %s", (NR>1?"; ":""), $1, $8, $11, $14, $17}')
  fi
  printf "%s\texpect=%s\tconjectures=%s%s\tours=%s\t%ss\tSigmaKEE=%s\t%s\n" "$t" "${expect:-?}" "$conj" \
    "${skipped:+ ($skipped)}" "${szs:-none}" "$(awk "BEGIN{printf \"%.2f\", $e - $s}")" "${sig:-?}" "$cmp" | tee -a results.tsv
done
