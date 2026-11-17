// PRELOAD-DIALECTS step 6: sumo-nix's sumo.nix over a KIF theory as TrikeShed's series (kif.terms, kif.facts), the
// ancestors by trikeshed.closure (ClosureIndex), lowered by kif-to-trikeshed and trikeshed-lower-cursors and run.
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
// TABLES-DAG: memref.global "private" constant @__kif_kb_tag : memref<75xi8>
// TABLES-DAG: memref.global "private" constant @__kif_kb_fact_term : memref<28xi32>
// TABLES-DAG: memref.global "private" constant @__kif_kb_rule_antecedent : memref<2xi32>
// TABLES-DAG: memref.global "private" constant @__kif_kb_rule_consequent : memref<2xi32>
// TABLES-DAG: trikeshed.closure

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

memref.global "private" constant @k_subclass : memref<8xi8> = dense<[115, 117, 98, 99, 108, 97, 115, 115]>
memref.global "private" constant @k_instance : memref<8xi8> = dense<[105, 110, 115, 116, 97, 110, 99, 101]>
memref.global "private" constant @k_domain : memref<6xi8> = dense<[100, 111, 109, 97, 105, 110]>
memref.global "private" constant @k_Human : memref<5xi8> = dense<[72, 117, 109, 97, 110]>
func.func private @printMemrefI32(memref<*xi32>) attributes {llvm.emit_c_interface}

// The row of the atom written as the bytes of name, or -1: the theory holds each atom once.
func.func private @atom_row(%tags: !s8, %names: !sp, %text: !s8, %name: !s8) -> i32 {
  %n = trikeshed.size %tags : !s8
  %rows = trikeshed.series %n : !s32 {
  ^bb0(%i: index):
    %r = arith.index_cast %i : index to i32
    trikeshed.yield %r : i32
  }
  %hits = trikeshed.where %rows : !s32 -> !s32 {
  ^bb0(%r: i32):
    %tag = trikeshed.at %tags[%r] : !s8, i32 -> i8
    %atom = arith.constant 0 : i8
    %isAtom = arith.cmpi eq, %tag, %atom : i8
    %hit = scf.if %isAtom -> (i1) {
      %p = trikeshed.at %names[%r] : !sp, i32 -> !tp
      %s = trikeshed.first %p : !tp -> i32
      %l = trikeshed.second %p : !tp -> i32
      %si = arith.index_cast %s : i32 to index
      %li = arith.index_cast %l : i32 to index
      %piece = trikeshed.slice %text[%si, %li] : !s8 -> !s8
      %c = trikeshed.compare %piece, %name unsigned : !s8, !s8
      %zero = arith.constant 0 : i32
      %same = arith.cmpi eq, %c, %zero : i32
      scf.yield %same : i1
    } else {
      %no = arith.constant false
      scf.yield %no : i1
    }
    trikeshed.yield %hit : i1
  }
  %k = trikeshed.size %hits : !s32
  %c0 = arith.constant 0 : index
  %some = arith.cmpi ugt, %k, %c0 : index
  %row = scf.if %some -> (i32) {
    %r = trikeshed.at %hits[%c0] : !s32, index -> i32
    scf.yield %r : i32
  } else {
    %none = arith.constant -1 : i32
    scf.yield %none : i32
  }
  return %row : i32
}

// Is term t a top-level form of relation rel with arity elements (rel included), none of its arguments a list: what
// sumo.nix's `top rel` and its `length f == arity && isString ...` keep.
func.func private @is_form(%tags: !s8, %kfc: !sp, %kid: !s32, %t: i32, %rel: i32, %arity: i32) -> i1 {
  %list = arith.constant 2 : i8
  %tag = trikeshed.at %tags[%t] : !s8, i32 -> i8
  %isList = arith.cmpi eq, %tag, %list : i8
  %form = scf.if %isList -> (i1) {
    %fc = trikeshed.at %kfc[%t] : !sp, i32 -> !tp
    %f = trikeshed.first %fc : !tp -> i32
    %n = trikeshed.second %fc : !tp -> i32
    %sized = arith.cmpi eq, %n, %arity : i32
    %ok = scf.if %sized -> (i1) {
      %h = trikeshed.at %kid[%f] : !s32, i32 -> i32
      %isRel = arith.cmpi eq, %h, %rel : i32
      %one = arith.constant 1 : i32
      %f1 = arith.addi %f, %one : i32
      %end = arith.addi %f, %n : i32
      %args = scf.for %e = %f1 to %end step %one iter_args(%acc = %isRel) -> (i1) : i32 {
        %a = trikeshed.at %kid[%e] : !s32, i32 -> i32
        %at = trikeshed.at %tags[%a] : !s8, i32 -> i8
        %notList = arith.cmpi ne, %at, %list : i8
        %acc2 = arith.andi %acc, %notList : i1
        scf.yield %acc2 : i1
      }
      scf.yield %args : i1
    } else {
      %no = arith.constant false
      scf.yield %no : i1
    }
    scf.yield %ok : i1
  } else {
    %no = arith.constant false
    scf.yield %no : i1
  }
  return %form : i1
}

// The k-th element (k 1 or more) of each of the forms ts: a column of a relation's rows.
func.func private @element(%kfc: !sp, %kid: !s32, %ts: !s32, %k: i32) -> !s32 {
  %col = trikeshed.alpha %ts : !s32 -> !s32 {
  ^bb0(%t: i32):
    %fc = trikeshed.at %kfc[%t] : !sp, i32 -> !tp
    %f = trikeshed.first %fc : !tp -> i32
    %at = arith.addi %f, %k : i32
    %x = trikeshed.at %kid[%at] : !s32, i32 -> i32
    trikeshed.yield %x : i32
  }
  return %col : !s32
}

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

// The first place in xs (sorted ascending) whose element is not below v: bisect with an order that is never equal.
func.func private @lower_bound(%xs: !s32, %v: i32) -> i32 {
  %at = trikeshed.bisect %xs, %v : !s32, i32 -> index by {
  ^bb0(%x: i32, %key: i32):
    %below = arith.cmpi slt, %x, %key : i32
    %before = arith.constant -1 : i32
    %after = arith.constant 1 : i32
    %o = arith.select %below, %before, %after : i32
    trikeshed.yield %o : i32
  }
  %at32 = arith.index_cast %at : index to i32
  %m1 = arith.constant -1 : i32
  %lb = arith.subi %m1, %at32 : i32
  return %lb : i32
}

// sumo.nix over the theory @kb, counted as onto.nix counts it: forms, classes, withParent, ancestorLinks, things,
// relations, humanAncestors.
func.func @main() -> i32 {
  %terms, %kid, %text = kif.terms @kb : !terms, !s32, !s8
  %facts = kif.facts @kb : !facts
  %rules = kif.rules @kb : !rules
  %t0 = trikeshed.key 0 : !tk
  %t1 = trikeshed.key 1 : !tk
  %t2 = trikeshed.key 2 : !tk
  %tags = trikeshed.column %terms[%t0] : !terms, !tk -> !s8
  %names = trikeshed.column %terms[%t1] : !terms, !tk -> !sp
  %kfc = trikeshed.column %terms[%t2] : !terms, !tk -> !sp
  %f0 = trikeshed.key 0 : !fk
  %forms = trikeshed.column %facts[%f0] : !facts, !fk -> !s32
  %r0 = trikeshed.key 0 : !rk
  %antecedents = trikeshed.column %rules[%r0] : !rules, !rk -> !s32
  %nfacts = trikeshed.size %forms : !s32
  %nrules = trikeshed.size %antecedents : !s32
  %nforms = arith.addi %nfacts, %nrules : index

  %gs = memref.get_global @k_subclass : memref<8xi8>
  %gi = memref.get_global @k_instance : memref<8xi8>
  %gd = memref.get_global @k_domain : memref<6xi8>
  %gh = memref.get_global @k_Human : memref<5xi8>
  %vs = memref.cast %gs : memref<8xi8> to memref<?xi8, strided<[1], offset: ?>>
  %vi = memref.cast %gi : memref<8xi8> to memref<?xi8, strided<[1], offset: ?>>
  %vd = memref.cast %gd : memref<6xi8> to memref<?xi8, strided<[1], offset: ?>>
  %vh = memref.cast %gh : memref<5xi8> to memref<?xi8, strided<[1], offset: ?>>
  %ns = builtin.unrealized_conversion_cast %vs : memref<?xi8, strided<[1], offset: ?>> to !s8
  %ni = builtin.unrealized_conversion_cast %vi : memref<?xi8, strided<[1], offset: ?>> to !s8
  %nd = builtin.unrealized_conversion_cast %vd : memref<?xi8, strided<[1], offset: ?>> to !s8
  %nh = builtin.unrealized_conversion_cast %vh : memref<?xi8, strided<[1], offset: ?>> to !s8
  %subclass = func.call @atom_row(%tags, %names, %text, %ns) : (!s8, !sp, !s8, !s8) -> i32
  %instance = func.call @atom_row(%tags, %names, %text, %ni) : (!s8, !sp, !s8, !s8) -> i32
  %domain = func.call @atom_row(%tags, %names, %text, %nd) : (!s8, !sp, !s8, !s8) -> i32
  %human = func.call @atom_row(%tags, %names, %text, %nh) : (!s8, !sp, !s8, !s8) -> i32
  %c1 = arith.constant 1 : i32
  %c2 = arith.constant 2 : i32
  %c3 = arith.constant 3 : i32
  %c4 = arith.constant 4 : i32

  // parents: (subclass Child Parent)
  %subs = trikeshed.where %forms : !s32 -> !s32 {
  ^bb0(%t: i32):
    %ok = func.call @is_form(%tags, %kfc, %kid, %t, %subclass, %c3) : (!s8, !sp, !s32, i32, i32, i32) -> i1
    trikeshed.yield %ok : i1
  }
  %child = func.call @element(%kfc, %kid, %subs, %c1) : (!sp, !s32, !s32, i32) -> !s32
  %parent = func.call @element(%kfc, %kid, %subs, %c2) : (!sp, !s32, !s32, i32) -> !s32
  %m = trikeshed.size %subs : !s32
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

  // ancestors: the edges in the order of their child, each term's (first, count) among them, then the closure
  %edges = trikeshed.series %m : !s32 {
  ^bb0(%i: index):
    %e = arith.index_cast %i : index to i32
    trikeshed.yield %e : i32
  }
  %byChild = trikeshed.sorted %edges : !s32 -> !s32 by {
  ^bb0(%a: i32, %b: i32):
    %ca = trikeshed.at %child[%a] : !s32, i32 -> i32
    %cb = trikeshed.at %child[%b] : !s32, i32 -> i32
    %lt = arith.cmpi slt, %ca, %cb : i32
    %gt = arith.cmpi sgt, %ca, %cb : i32
    %m1 = arith.constant -1 : i32
    %p1 = arith.constant 1 : i32
    %z = arith.constant 0 : i32
    %g = arith.select %gt, %p1, %z : i32
    %o = arith.select %lt, %m1, %g : i32
    trikeshed.yield %o : i32
  }
  %cs = trikeshed.project %child[%byChild] : !s32, !s32 -> !s32
  %ps = trikeshed.project %parent[%byChild] : !s32, !s32 -> !s32
  %nterms = trikeshed.size %tags : !s8
  %up = trikeshed.series %nterms : !sp {
  ^bb0(%i: index):
    %v = arith.index_cast %i : index to i32
    %one = arith.constant 1 : i32
    %v1 = arith.addi %v, %one : i32
    %lb = func.call @lower_bound(%cs, %v) : (!s32, i32) -> i32
    %ub = func.call @lower_bound(%cs, %v1) : (!s32, i32) -> i32
    %count = arith.subi %ub, %lb : i32
    %fc = trikeshed.j %lb, %count : i32, i32 -> !tp
    trikeshed.yield %fc : !tp
  }
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

  // classOf: (instance Thing Class); domains: (domain Relation Position Class)
  %insts = trikeshed.where %forms : !s32 -> !s32 {
  ^bb0(%t: i32):
    %ok = func.call @is_form(%tags, %kfc, %kid, %t, %instance, %c3) : (!s8, !sp, !s32, i32, i32, i32) -> i1
    trikeshed.yield %ok : i1
  }
  %thing = func.call @element(%kfc, %kid, %insts, %c1) : (!sp, !s32, !s32, i32) -> !s32
  %allThings = func.call @distinct(%thing) : (!s32) -> !s32
  %things = trikeshed.size %allThings : !s32
  %doms = trikeshed.where %forms : !s32 -> !s32 {
  ^bb0(%t: i32):
    %ok = func.call @is_form(%tags, %kfc, %kid, %t, %domain, %c4) : (!s8, !sp, !s32, i32, i32, i32) -> i1
    trikeshed.yield %ok : i1
  }
  %relation = func.call @element(%kfc, %kid, %doms, %c1) : (!sp, !s32, !s32, i32) -> !s32
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
