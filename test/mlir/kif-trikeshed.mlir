// PRELOAD-DIALECTS step 6: sumo-nix's sumo.nix over a KIF theory in dialect forms.  The theory as TrikeShed's series and
// cursors (kif.terms, kif.facts), each relation a cursor of rows (sumo.relation: SumoClassifier's taxonomy projection),
// `parents` grouped by child (trikeshed.adjacency) and closed (trikeshed.closure: ClosureIndex); lowered by
// kif-to-trikeshed and trikeshed-lower-cursors and run.
//
// RUN: d=%S/../kif; { mlnix-kif $d/taxonomy-a.kif $d/taxonomy-b.kif | sed '1d;$d'; cat %s; } | mlnix-opt --kif-to-trikeshed | FileCheck %s --check-prefix=TABLES
// RUN: d=%S/../kif; { mlnix-kif $d/taxonomy-a.kif $d/taxonomy-b.kif | sed '1d;$d'; cat %s; } | mlnix-opt --kif-to-trikeshed --trikeshed-lower-cursors | mlir-opt --ownership-based-buffer-deallocation --canonicalize --buffer-deallocation-simplification --bufferization-lower-deallocations --convert-scf-to-cf --expand-strided-metadata --lower-affine --finalize-memref-to-llvm --convert-arith-to-llvm --convert-index-to-llvm --convert-cf-to-llvm --convert-func-to-llvm --reconcile-unrealized-casts | mlir-runner -e main -entry-point-result=i32 -shared-libs=$(ls $(dirname $(which mlir-runner))/../lib/libmlir_runner_utils.* | head -1) | FileCheck %s
//
// The theory is mlnix-kif's @kb of the two files (its module's first and last lines cut, so it and this file are one
// module).  The numbers are sumo.nix's, from its own evaluation (test/kif/taxonomy-oracle.nix):
//   mlnix eval --strict --json --arg sumo <sumo-nix> --arg files '[ ./test/kif/taxonomy-a.kif ./test/kif/taxonomy-b.kif ]' test/kif/taxonomy-oracle.nix
//   [[30,13,12,49,3,3,9],[5,2,5,2,6,6,9,4,1,5,1,3]]
// forms, classes, withParent, ancestorLinks, things, relations, Human's ancestors; then each class with a parent, by name
// (?C Animal Canine CognitiveAgent Dog Hominid Human Mammal Organism Primate SentientAgent Vertebrate): its ancestors.
// scripts/sumo-trikeshed.sh runs this query, compiled, on sumo.full's 78 files against the same oracle (PRELOAD-DIALECTS
// step 6).

// TABLES-NOT: kif.theory
// TABLES-NOT: kif.atom_row
// TABLES-DAG: memref.global "private" constant @__kif_kb_tag : memref<75xi8>
// TABLES-DAG: memref.global "private" constant @__kif_kb_fact_term : memref<28xi32>
// TABLES-DAG: memref.global "private" constant @__kif_kb_rule_antecedent : memref<2xi32>
// TABLES-DAG: memref.global "private" constant @__kif_kb_rule_consequent : memref<2xi32>
// TABLES-DAG: trikeshed.closure
// TABLES-DAG: sumo.relation

// CHECK: [30,  13,  12,  49,  3,  3,  9]
// CHECK: [5,  2,  5,  2,  6,  6,  9,  4,  1,  5,  1,  3]
// CHECK: 0

!s8 = !trikeshed.series<i8>
!s32 = !trikeshed.series<i32>
!tp = !trikeshed.twinpacked<i32>
!sp = !trikeshed.series<!tp>
!terms = !trikeshed.cursor<"KifTerm", [i8, !tp, !tp]>
!tk = !trikeshed.colkey<"KifTerm">
!facts = !trikeshed.cursor<"KifFact", [i32, i32]>
!fk = !trikeshed.colkey<"KifFact">
!rules = !trikeshed.cursor<"KifRule", [i32, i32, i32]>
!rk = !trikeshed.colkey<"KifRule">
!pairs = !trikeshed.cursor<"pairs", [i32, i32]>
!pk = !trikeshed.colkey<"pairs">
!slots = !trikeshed.cursor<"slots", [i32, i32, i32]>
!sk = !trikeshed.colkey<"slots">

func.func private @printMemrefI32(memref<*xi32>) attributes {llvm.emit_c_interface}

// The different rows of xs, ascending: sorted, then the places where a run starts.
func.func private @distinct(%xs: !s32) -> !s32 {
  %sorted = trikeshed.sorted %xs : !s32 -> !s32
  %n = trikeshed.size %sorted : !s32
  %places = trikeshed.series %n : !s32 {
  ^bb0(%i: index):
    %r = arith.index_cast %i : index to i32
    trikeshed.yield %r : i32
  }
  %starts = trikeshed.where %places : !s32 -> !s32 {
  ^bb0(%i: i32):
    %zero = arith.constant 0 : i32
    %first = arith.cmpi eq, %i, %zero : i32
    %start = scf.if %first -> (i1) {
      %yes = arith.constant true
      scf.yield %yes : i1
    } else {
      %one = arith.constant 1 : i32
      %ip = arith.subi %i, %one : i32
      %x = trikeshed.at %sorted[%i] : !s32, i32 -> i32
      %xp = trikeshed.at %sorted[%ip] : !s32, i32 -> i32
      %differs = arith.cmpi ne, %x, %xp : i32
      scf.yield %differs : i1
    }
    trikeshed.yield %start : i1
  }
  %rows = trikeshed.project %sorted[%starts] : !s32, !s32 -> !s32
  return %rows : !s32
}

// The order of two terms' names: their bytes, unsigned, then the shorter first (Nix's attrNames order).
func.func private @name_order(%names: !sp, %text: !s8, %a: i32, %b: i32) -> i32 {
  %pa = trikeshed.at %names[%a] : !sp, i32 -> !tp
  %pb = trikeshed.at %names[%b] : !sp, i32 -> !tp
  %sa = trikeshed.first %pa : !tp -> i32
  %na = trikeshed.second %pa : !tp -> i32
  %sb = trikeshed.first %pb : !tp -> i32
  %nb = trikeshed.second %pb : !tp -> i32
  %sai = arith.index_cast %sa : i32 to index
  %nai = arith.index_cast %na : i32 to index
  %sbi = arith.index_cast %sb : i32 to index
  %nbi = arith.index_cast %nb : i32 to index
  %ta = trikeshed.slice %text[%sai, %nai] : !s8 -> !s8
  %tb = trikeshed.slice %text[%sbi, %nbi] : !s8 -> !s8
  %c = trikeshed.compare %ta, %tb unsigned : !s8, !s8
  return %c : i32
}

// sumo.nix over the theory @kb, counted as sumo-bench's onto.nix counts it: forms, classes, withParent, ancestorLinks,
// things, relations, humanAncestors; then each class with a parent, by name, and its number of ancestors.
func.func @main() -> i32 {
  %terms, %kids, %text = kif.terms @kb : !terms, !s32, !s8
  %facts = kif.facts @kb : !facts
  %rules = kif.rules @kb : !rules
  %t1 = trikeshed.key 1 : !tk
  %names = trikeshed.column %terms[%t1] : !terms, !tk -> !sp
  %f0 = trikeshed.key 0 : !fk
  %forms = trikeshed.column %facts[%f0] : !facts, !fk -> !s32
  %r0 = trikeshed.key 0 : !rk
  %antecedents = trikeshed.column %rules[%r0] : !rules, !rk -> !s32
  %nfacts = trikeshed.size %forms : !s32
  %nrules = trikeshed.size %antecedents : !s32
  %nforms = arith.addi %nfacts, %nrules : index
  %nterms = trikeshed.size %names : !sp

  // the relations: parents (subclass Child Parent), classOf (instance Thing Class), domains (domain Relation Position Class)
  %subclass = kif.atom_row @kb "subclass" : i32
  %instance = kif.atom_row @kb "instance" : i32
  %domain = kif.atom_row @kb "domain" : i32
  %human = kif.atom_row @kb "Human" : i32
  %sub = sumo.relation %subclass of %facts in %terms, %kids : !facts, !terms, !s32 -> !pairs
  %ins = sumo.relation %instance of %facts in %terms, %kids : !facts, !terms, !s32 -> !pairs
  %dom = sumo.relation %domain of %facts in %terms, %kids : !facts, !terms, !s32 -> !slots
  %p0 = trikeshed.key 0 : !pk
  %p1 = trikeshed.key 1 : !pk
  %s0 = trikeshed.key 0 : !sk
  %child = trikeshed.column %sub[%p0] : !pairs, !pk -> !s32
  %parent = trikeshed.column %sub[%p1] : !pairs, !pk -> !s32
  %thing = trikeshed.column %ins[%p0] : !pairs, !pk -> !s32
  %relation = trikeshed.column %dom[%s0] : !slots, !sk -> !s32

  // classes: the children and the parents; withParent: the children
  %m = trikeshed.size %child : !s32
  %m2 = arith.addi %m, %m : index
  %both = trikeshed.series %m2 : !s32 {
  ^bb0(%i: index):
    %inChild = arith.cmpi ult, %i, %m : index
    %x = scf.if %inChild -> (i32) {
      %c = trikeshed.at %child[%i] : !s32, index -> i32
      scf.yield %c : i32
    } else {
      %j = arith.subi %i, %m : index
      %p = trikeshed.at %parent[%j] : !s32, index -> i32
      scf.yield %p : i32
    }
    trikeshed.yield %x : i32
  }
  %allClasses = func.call @distinct(%both) : (!s32) -> !s32
  %classes = trikeshed.size %allClasses : !s32
  %children = func.call @distinct(%child) : (!s32) -> !s32
  %withParent = trikeshed.size %children : !s32

  // ancestors: parents grouped by child over the terms, then closed
  %up, %ps = trikeshed.adjacency %child, %parent over %nterms : !s32, !s32 -> !sp, !s32
  %ancestors, %above = trikeshed.closure %up, %ps : !sp, !s32 -> !sp, !s32
  %links = trikeshed.size %above : !s32
  %c0i = arith.constant 0 : i32
  %hasHuman = arith.cmpi sge, %human, %c0i : i32
  %humanAncestors = scf.if %hasHuman -> (i32) {
    %fc = trikeshed.at %ancestors[%human] : !sp, i32 -> !tp
    %n = trikeshed.second %fc : !tp -> i32
    scf.yield %n : i32
  } else {
    scf.yield %c0i : i32
  }

  %allThings = func.call @distinct(%thing) : (!s32) -> !s32
  %things = trikeshed.size %allThings : !s32
  %allRelations = func.call @distinct(%relation) : (!s32) -> !s32
  %relations = trikeshed.size %allRelations : !s32

  // forms classes withParent ancestorLinks things relations humanAncestors
  %seven = arith.constant 7 : index
  %counts = trikeshed.series %seven : !s32 {
  ^bb0(%i: index):
    %a = arith.index_cast %nforms : index to i32
    %b = arith.index_cast %classes : index to i32
    %c = arith.index_cast %withParent : index to i32
    %d = arith.index_cast %links : index to i32
    %e = arith.index_cast %things : index to i32
    %f = arith.index_cast %relations : index to i32
    %k0 = arith.constant 0 : index
    %k1 = arith.constant 1 : index
    %k2 = arith.constant 2 : index
    %k3 = arith.constant 3 : index
    %k4 = arith.constant 4 : index
    %k5 = arith.constant 5 : index
    %i0 = arith.cmpi eq, %i, %k0 : index
    %i1 = arith.cmpi eq, %i, %k1 : index
    %i2 = arith.cmpi eq, %i, %k2 : index
    %i3 = arith.cmpi eq, %i, %k3 : index
    %i4 = arith.cmpi eq, %i, %k4 : index
    %i5 = arith.cmpi eq, %i, %k5 : index
    %v5 = arith.select %i5, %f, %humanAncestors : i32
    %v4 = arith.select %i4, %e, %v5 : i32
    %v3 = arith.select %i3, %d, %v4 : i32
    %v2 = arith.select %i2, %c, %v3 : i32
    %v1 = arith.select %i1, %b, %v2 : i32
    %v0 = arith.select %i0, %a, %v1 : i32
    trikeshed.yield %v0 : i32
  }
  %out = memref.alloc() : memref<7xi32>
  %outd = memref.cast %out : memref<7xi32> to memref<?xi32>
  %end = trikeshed.drain %counts, %outd : !s32, memref<?xi32> -> index
  %u = memref.cast %out : memref<7xi32> to memref<*xi32>
  func.call @printMemrefI32(%u) : (memref<*xi32>) -> ()

  // each class with a parent, in the order of its name (sumo.nix's attrNames ancestors): its number of ancestors
  %byName = trikeshed.sorted %children : !s32 -> !s32 by {
  ^bb0(%a: i32, %b: i32):
    %c = func.call @name_order(%names, %text, %a, %b) : (!sp, !s8, i32, i32) -> i32
    trikeshed.yield %c : i32
  }
  %perClass = trikeshed.alpha %byName : !s32 -> !s32 {
  ^bb0(%r: i32):
    %fc = trikeshed.at %ancestors[%r] : !sp, i32 -> !tp
    %n = trikeshed.second %fc : !tp -> i32
    trikeshed.yield %n : i32
  }
  %pc = memref.alloc(%withParent) : memref<?xi32>
  %pcEnd = trikeshed.drain %perClass, %pc : !s32, memref<?xi32> -> index
  %pcu = memref.cast %pc : memref<?xi32> to memref<*xi32>
  func.call @printMemrefI32(%pcu) : (memref<*xi32>) -> ()
  %ok = arith.constant 0 : i32
  return %ok : i32
}
