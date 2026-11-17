# Who reasons over SUMO: Nix, the MLIR layers, Vampire, Lean

The split under test:

- Nix pins the corpora (sumo.full's 78 files, PINS) and builds what is derived from them.  It is not the reasoner: kif.nix
  parses sumo.full in 1.4 s and 845 MB on mlnix, after an OOM kill at 12 GB (PRELOAD-DIALECTS.md).
- The MLIR layers parse and match.  mlnix-kif reads sumo.full into kif IR in 0.7 s and 201 MB; kif-chase runs the Horn
  fragment, keeping each derived fact's rule and premises; kif-to-trikeshed makes sumo.nix's tables TrikeShed cursors, so
  the 90,404 ancestor links take 0.07 s and 78 MB compiled, against 3.0 s and 902 MB for sumo.nix on Nix
  (PRELOAD-DIALECTS.md, "sumo-nix's tables over TrikeShed").
- Vampire searches what is not Horn.  On SUMO's 84 tests, sumo-nix's Horn solver tq.nix gives 10 pass, 31 open and 43
  unsupported.
- Lean checks: the chase's certificates, Vampire's proofs, and (untested) proofs about the rule compiler and the passes.

Three tests on Kali put numbers on it.  Kali is shared (the live mini-luci demo, other builds), so wall times carry load
noise.  The tables, with exact commands and versions, are in bench/kali/reasoning-20261117/; the raw logs stay on Kali in
~/lean-test, ~/vampire-test and ~/lean-tax.

## 1. Certificates: the kernel is cheap, elaborating generated source is not

kif-chase's paperclip stratum 1 (7,147 facts, 1,964 derived; the chase takes 0.07 s) in Lean 4.36.0: the 5,183 asserted
facts and the 10 rules as axioms over `Holds : Term -> Prop`, each derived fact a theorem `dN : Holds fact := rK args
premises` built from the chase's record (test1-lean-certificates.md).

| step | time | peak RSS |
|---|---|---|
| `lean` on the generated file (740 kB) | 16.0-16.3 s | 863 MB |
| of that, the kernel (type checking with and without `debug.skipKernelTC`) | 0.35-0.4 s | |
| `leanchecker` replaying the .olean, over an empty module | 0.70 s against 0.52 s | 446 MB |
| nanoda, an independent kernel, on the export (7,540 declarations) | 0.14-0.19 s | 9 MB |

A wrong premise and a wrong rule instance fail in the elaborator; a corrupted proof handed to addDecl fails in the kernel;
a false theorem let through with `debug.skipKernelTC` is rejected by leanchecker and by nanoda.  What costs is the
elaborator reading generated text, so a certificate should reach the kernel as terms (addDecl, or the export format that
nanoda reads), not as .lean source.

## 2. Search: Vampire finds the proofs, Lean re-checks the ones it is handed

The 43 tests tq.nix calls unsupported, each as SigmaKEE translates it (KB Merge.kif at SUMO 25bb366, as upstream's
tqsp-ci.yml), through Vampire 5.1.0 `--mode casc --cores 2 -t 60` (test2-vampire-sumo-tq.md):

| outcome | tests |
|---|---|
| proved, first-order: 0.32-0.83 s and 36-42 MB each, 2-10 axioms used | 20 |
| "proved", higher-order TQC2: its translated conjecture is valid by itself | 1 |
| timeout at 60 s and at 300 s, first-order (SP04, TQG3_c, TQG44, TQG50) | 4 |
| timeout, higher-order (TQG27, TQG4, TQM10, TQM3) | 4 |
| timeout, modal: the translation dropped the test's assertions (TQC1, TQC2b, TQC2b2, TQC3) | 4 |
| input error: SigmaKEE's typed (TFF) output does not load in Vampire 5.1.0 | 10 |

Every first-order proof came from the same early CASC strategy, with SInE relevance filtering.  With the typed KB
minimally repaired (a separate set: one ill-sorted axiom dropped, '-' renamed in declarations), NUM1, TQG11 and TQG19 are
proved in 56-59 s, and NUM2 within the 300 s limit.

Vampire-Hammer (93e0c0c, Lean 4.34.1), given the axioms Vampire's proof used and the conjecture, re-proves all 21 and the
kernel checks them (TQC2 encoded by hand; `#print axioms` shows only propext, Classical.choice and Quot.sound).  Each file
takes 2.4-4.3 s, mostly importing the library: the hammer adds a median 0.26 s over the same file closed by `sorry`.
Given the whole KB instead (13,094 hypotheses, for TQG3_d), elaborating the statement alone takes 136 s and 2.6 GB, the
default heartbeat limit stops the hammer at 95 s, and without a limit it has nothing at 900 s.

So relevance filtering belongs to the search, and Lean checks the slice of axioms a proof used.  The weak link in SUMO's
own pipeline is the translation: 14 of the 43 tests never reach Vampire intact.

The proofs the hammer rebuilt also pass the kernels that check kif-chase's certificates (section 4;
bench/kali/reasoning-20261117/test2-kernels.log and test2-kernels.sh).  These are 29 theorems: the 21 tests, 7 of them
in a second translation, and TQG11 from the repaired typed KB.  The hammer's package is pinned to Lean 4.34.1, whose
toolchain ships no exporter, so lean4export at its tag v4.34.0 writes them.  That is the same format, 3.1.0, as the
4.36.0 toolchain's leanexport.  The export holds every declaration the proofs use: 141 MB, 8,699 declarations, and no
axiom but propext, Classical.choice and Quot.sound.

| kernel | the file | without the 29 theorems |
|---|---|---|
| nanoda_bin | 14.1 s, 203 MB | 13.6 s |
| con-leche --verified, one thread | 42.8 s, 262 MB | 40.9 s |
| con-ron --verified, one thread | 44.4 s, 548 MB | 42.7 s |

The proofs are small: 30 to 3,443 expressions each, median 773.  Together they cost the kernels 0.5-1.9 s; the
library under them is the rest.  Each kernel rejects the control, two theorems' statements swapped:
- nanoda_bin fails its `def_eq` assertion;
- con-leche and con-ron report a type mismatch in tq_sigma_partitionTest1.

Once in three runs a Vampire under the hammer deadlocked, so the script gives a compile 120 s and kills a stuck Vampire
before trying again.

What no kernel checks is that a statement is its problem's: tptp2lean.py wrote each one from the TPTP problem SigmaKEE
made.  test2-statements.py checks it, as kif-lean-check.py checks kif-chase's claims against the dump
(test2-statements.log):
- it decodes each statement from the exported kernel terms;
- it reads the problem Vampire ran with a TPTP parser of its own, not tptp2lean.py's;
- the statement must be h1 -> .. -> hk -> goal, with the goal the conjecture and each hi an axiom of the problem, up to
  the names of bound variables, under one assignment of the problem's symbols to the theorem's (arity and sorts kept).

If so, the theorem the kernels accept, instantiated by that assignment, says the conjecture holds in every model of those
axioms.  So the problem is a Theorem whatever Vampire did.

All 28 statements are their problems'.  TQC2 is THF, encoded by hand, and not read.  The 28 bind 176 symbols and 99
hypotheses; each hypothesis is one of the axioms Vampire's proof used, and every assignment is one to one.  All 82
controls disagree:
- a statement against another test's problem whose conjecture has another form;
- against its own problem with the conjecture negated;
- against its own problem without the axioms its first hypothesis matches.

The check takes 59 s, mostly reading the 20 SUMO KBs of 3.4 MB.  The match uses no name from the export.  lean4export
writes an expression once up to alpha-equivalence, so two statements that differ only in binder names share one record,
with the first one's names: tq_sigma1_TQG34 carries tq_tqsp_TQG34's.  Matching hypotheses to axioms by those names
failed for 6 theorems before the check was made name-free.

## 3. The taxonomy: a table, entered as kernel terms

SUMO's 9,045 classes and 90,404 ancestor links (mlnix on onto.nix, agreeing with an independent Python reader) in Lean
4.36.0 (test3-lean-taxonomy.md):

| encoding | wall | peak RSS | .olean | result |
|---|---|---|---|---|
| `def ... := #[...]`, default options | 70 s | 1,688 MiB | | maximum recursion depth |
| the same, both limits lifted | 975 s | 6,143 MiB | | killed at the 6 GiB cap |
| `noncomputable def` | 224 s | 4,423 MiB | 13.2 MB | ok |
| kernel terms, built in a command and added by addDecl | 4.7 s (1.6 s empty) | 1,751 MiB (1,568 empty) | 11.6 MB | ok |
| one inductive type, an enum: 1,000 / 4,000 classes, no heartbeat limit | 26 / 390 s | 986 / 5,536 MiB | 54 / 790 MB | ok |
| the enum of all 9,045 classes | 1,200 s | 4,320 MiB | | timeout |

The enum's .olean grows as the square of its size, and the enum passes the default heartbeat limit between 1,000 and
2,000 constructors with no deriving at all.  Deriving DecidableEq adds little with Lean 4.36's linear construction (1,000
classes: 28.6 s against 25.5 s).  The older quadratic construction, on constructors with a field, reproduces the 2025
report of timeouts past 30-40 constructors (40 take 7.9 s, 100 time out), and with a field on each constructor Lean caps
an inductive at 244 constructors.  Facts about the table are proved by `decide +kernel` (`rfl` hits the recursion limit):
eight took 101 s over the kernel-term table, 0.8-18.5 s each.

So the taxonomy stays a table, as sumo.nix and the TrikeShed query already compute it; Lean holds it as terms and proves
things about it.

## 4. The certificate path: `mlnix-kif --chase --lean`

Built after the tests, as test 1 points: the MLIR layer writes kernel terms, and nothing elaborates.  `mlnix-kif --chase
--lean OUT` (lib/Dialect/KifLean.cpp) writes what kif-chase derived as one theorem in lean4export's format that uses no axiom:
the atoms, the asserted facts and the rules are hypotheses (`(equal a b)` adds Same and same; an `(instance X C)` premise read
through the ontology adds Sub, sub_trans, inst_up and the subclass edges its proofs use), and each derived fact is a let of
its proof, its rule applied to the bindings (found again by matching the premises against `from`) and to the proofs of its
premises.  The lets are the claims: a kernel checks each let against its fact, whether anything uses it or not.  The Lean 4.36
toolchain ships three kernels that read the format: nanoda_bin, and con-leche and con-ron, whose `--verified` mode carries a
proof that what they accept proves no False (they refuse axioms, so the theory's facts are hypotheses, not axioms).
`scripts/kif-lean-check.py` decodes the claims and compares them with the chase's dump; `scripts/kif-lean-kernels.py` runs
the three kernels on a certificate and on three controls with one proof broken (bench/kali/lean-cert-20261117/).

Paperclip's stratum 1 on Kali (the same 1,964 derived facts as test 1):

| step | time | peak RSS |
|---|---|---|
| mlnix-kif: read, chase, write the certificate (5.05 MB, 8,666 hypotheses, 1,964 lets) | 0.11-0.12 s (the writing 0.04 s) | 68 MB |
| kif-lean-check.py: the claims decoded, equal to the dump | 0.46 s | |
| nanoda_bin | 0.12-0.14 s | 19 MB |
| con-leche --verified, one thread | 0.26-0.32 s | 47 MB |
| con-ron --verified, one thread | 0.32-0.34 s | 83 MB |

against test 1's 16 s and 863 MB to elaborate the generated .lean.  Each kernel rejects each control: a premise's proof
swapped for another fact's, a binding changed, and the last let (which nothing uses) claiming another fact.

Two choices keep the kernels near linear, both measured: the conclusion is a trivial `Done`, since a body that names every
let (`pack d.1 .. d.n`) took the same certificate 1.3-1.9 s; and the lets go depth first from the facts derived last, since in
the chase's order a chain of 12,000 lets took 10-23 s, against 0.2-0.4 s depth first.  The limit is depth: the certificate is
one term, nanoda_bin reads a de Bruijn index as a u16 (hypotheses and lets under 65,536), and con-leche and con-ron did not
finish a 64,000-deep certificate in 120 s (nanoda_bin: 0.9 s).

So a larger theory's certificate is written in pieces: `--lean-piece N` makes theorems closure.0, closure.1, .. of at most N
lets each, in the same order, each with only the hypotheses its lets use, and a fact that a let of an earlier piece proves a
hypothesis there too (`i.K`, for let d.K).  That such an import is what the earlier let proves is the one link no kernel
sees, since each checks one theorem at a time; kif-lean-check.py checks it with the claims (each i.K claims what d.K claims,
d.K in an earlier piece).  SUMO's taxonomy is the first theory past the limit: sumo.full's 10,308 subclass edges with
transitivity, which kif-chase closes into sumo.nix's 90,404 ancestor links (each class's count equal to sumo.nix's) by 80,096
derived facts in 1.0 s.  On Kali, in pieces of 4,000 lets (bench/kali/lean-cert-20261117/pieces.log):

| step | time | peak RSS |
|---|---|---|
| mlnix-kif: read, chase, write 21 theorems (76 MB; 71,791 hypotheses in all, 18,898 of them imports; at most 10,213 deep) | 1.87 s | 237 MB |
| kif-lean-check.py: the claims decoded, equal to the dump, every import an earlier piece's let | 8.6 s | 0.9 GB |
| nanoda_bin | 2.20 s | 120 MB |
| con-leche --verified, one thread | 3.78 s | 122 MB |
| con-ron --verified, one thread | 4.59 s | 223 MB |

Each kernel rejects each control (at 8,000 lets a piece).  Larger pieces cost more, not less: at 16,000 lets (6 theorems,
32,131 deep) the kernels take 7.8-8.6 s, though the pieces import a third fewer facts.  The same holds for the synthetic
theories one theorem could not hold: 48,000 lets in 12 pieces check in 0.5-1.3 s, where one theorem was past nanoda_bin's u16
and con-leche's and con-ron's 120 s.  This is the role the split gives Lean for SUMO: not the taxonomy as Lean types (test
3), but kernel-checked proofs about the table the MLIR layer computes, each of its 90,404 links proved from SUMO's own edges.

## Not done

- Pieces chosen for their imports: a piece is a run of the depth-first order, and SUMO's upper classes make about one import
  for every four lets; grouping the lets by the classes they rest on would make fewer.
- Negation as failure (paperclip's second stratum): a `(not ..)` premise rests on the closed world of the stratum below, which
  a certificate would have to state; `--lean` refuses such a fact.
- Vampire as the search behind the kif and sumo dialects for what is not Horn, its proofs re-checked in Lean from the
  axioms they used.
- The link from a TPTP problem back to its KIF test, SigmaKEE's translation: section 2's statements are checked against
  the problem, and nothing checks the problem against the test.
- SigmaKEE's translation, upstream: typed output that loads in Vampire 5.1.0, test assertions kept (typed tests write them
  as untyped formulas; four modal tests lose them), one process per test.
- Lean proofs about the rule compiler (the NARS-Rete note's "the compiler must show that the specialization preserves"
  the rules): untested.
