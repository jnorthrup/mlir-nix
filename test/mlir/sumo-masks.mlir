// PRELOAD-DIALECTS step 6: SumoClassifier's INSTANCES and DISJOINT masks over a KIF theory, as the trikeshed compositions of
// lib/Dialect/SumoMasks.mlir over sumo.relation's rows; the theory read by mlnix-kif and laid out by kif-to-trikeshed in the
// same process (never printed as kif IR and parsed again), lowered and run.
//
// RUN: d=%S/../kif; mlnix-kif $d/taxonomy-a.kif $d/taxonomy-b.kif $d/taxonomy-c.kif --query %S/../../lib/Dialect/SumoMasks.mlir --query %s --pass kif-to-trikeshed,trikeshed-lower-cursors | mlir-opt --ownership-based-buffer-deallocation --canonicalize --buffer-deallocation-simplification --bufferization-lower-deallocations --convert-scf-to-cf --expand-strided-metadata --lower-affine --finalize-memref-to-llvm --convert-arith-to-llvm --convert-index-to-llvm --convert-cf-to-llvm --convert-func-to-llvm --reconcile-unrealized-casts | mlir-runner -e main -entry-point-result=i32 -shared-libs=$(ls $(dirname $(which mlir-runner))/../lib/libmlir_runner_utils.* | head -1) | FileCheck %s
//
// The numbers are sumo.nix's, from its own evaluation (test/kif/masks-oracle.nix):
//   mlnix eval --strict --json --arg sumo <sumo-nix> --arg files '[ ./test/kif/taxonomy-a.kif ./test/kif/taxonomy-b.kif ./test/kif/taxonomy-c.kif ]' test/kif/masks-oracle.nix
// things, instance-type links, classes, disjoint links; then each thing by name, its number of classes (closed upward);
// then each class by name (sumo.nix's `classes`), the number of classes disjoint from it.

//   [[4,25,16,80],[1,8,5,11],[4,0,4,7,1,7,6,7,4,10,0,10,6,0,10,4]]
// (things: "a string" Fido Oak123 Socrates; classes: ?C Agent Animal Canine CognitiveAgent Dog Hominid Human Mammal Oak
// Organism Plant Primate SentientAgent Tree Vertebrate)

// CHECK: [4,  25,  16,  80]
// CHECK: [1,  8,  5,  11]
// CHECK: [4,  0,  4,  7,  1,  7,  6,  7,  4,  10,  0,  10,  6,  0,  10,  4]
// CHECK: 0

!s8 = !trikeshed.series<i8>
!s32 = !trikeshed.series<i32>
!tp = !trikeshed.twinpacked<i32>
!sp = !trikeshed.series<!tp>
!terms = !trikeshed.cursor<"KifTerm", [i8, !tp, !tp]>
!tk = !trikeshed.colkey<"KifTerm">
!facts = !trikeshed.cursor<"KifFact", [i32, i32]>
!pairs = !trikeshed.cursor<"pairs", [i32, i32]>
!pk = !trikeshed.colkey<"pairs">

func.func private @printMemrefI32(memref<*xi32>) attributes {llvm.emit_c_interface}

func.func private @masks_print(%xs: !s32) {
  %n = trikeshed.size %xs : !s32
  %out = memref.alloc(%n) : memref<?xi32>
  %end = trikeshed.drain %xs, %out : !s32, memref<?xi32> -> index
  %u = memref.cast %out : memref<?xi32> to memref<*xi32>
  func.call @printMemrefI32(%u) : (memref<*xi32>) -> ()
  return
}

func.func private @masks_sum(%xs: !s32) -> i32 {
  %zero = arith.constant 0 : i32
  %s = trikeshed.fold %xs, %zero : !s32, i32 -> i32 {
  ^bb0(%acc: i32, %x: i32):
    %y = arith.addi %acc, %x : i32
    trikeshed.yield %y : i32
  }
  return %s : i32
}

func.func @main() -> i32 {
  %terms, %kids, %text = kif.terms @kb : !terms, !s32, !s8
  %facts = kif.facts @kb : !facts
  %t1 = trikeshed.key 1 : !tk
  %names = trikeshed.column %terms[%t1] : !terms, !tk -> !sp
  %n = trikeshed.size %names : !sp

  %subclass = kif.atom_row @kb "subclass" : i32
  %instance = kif.atom_row @kb "instance" : i32
  %disjoint = kif.atom_row @kb "disjoint" : i32
  %partition = kif.atom_row @kb "partition" : i32
  %decomposition = kif.atom_row @kb "disjointDecomposition" : i32
  %sub = sumo.relation %subclass of %facts in %terms, %kids : !facts, !terms, !s32 -> !pairs
  %ins = sumo.relation %instance of %facts in %terms, %kids : !facts, !terms, !s32 -> !pairs
  %dis = sumo.relation %disjoint of %facts in %terms, %kids : !facts, !terms, !s32 -> !pairs
  %p0 = trikeshed.key 0 : !pk
  %p1 = trikeshed.key 1 : !pk
  %child = trikeshed.column %sub[%p0] : !pairs, !pk -> !s32
  %parent = trikeshed.column %sub[%p1] : !pairs, !pk -> !s32
  %thing = trikeshed.column %ins[%p0] : !pairs, !pk -> !s32
  %class = trikeshed.column %ins[%p1] : !pairs, !pk -> !s32
  %da = trikeshed.column %dis[%p0] : !pairs, !pk -> !s32
  %db = trikeshed.column %dis[%p1] : !pairs, !pk -> !s32

  %types, %typeRows = func.call @sumo_instance_types(%child, %parent, %thing, %class, %n)
    : (!s32, !s32, !s32, !s32, index) -> (!sp, !s32)
  %pa, %pd = func.call @sumo_parts_disjoint(%partition, %facts, %terms, %kids) : (i32, !facts, !terms, !s32) -> (!s32, !s32)
  %qa, %qd = func.call @sumo_parts_disjoint(%decomposition, %facts, %terms, %kids) : (i32, !facts, !terms, !s32) -> (!s32, !s32)
  %a = trikeshed.combine %da, %db, %pa, %qa : !s32, !s32, !s32, !s32 -> !s32
  %d = trikeshed.combine %db, %da, %pd, %qd : !s32, !s32, !s32, !s32 -> !s32
  %masks, %maskRows = func.call @sumo_disjoint(%child, %parent, %a, %d, %n) : (!s32, !s32, !s32, !s32, index) -> (!sp, !s32)

  %thingRows = func.call @sumo_distinct(%thing) : (!s32) -> !s32
  %things = func.call @sumo_by_name(%thingRows, %names, %text) : (!s32, !sp, !s8) -> !s32
  %both = trikeshed.combine %child, %parent : !s32, !s32 -> !s32
  %classRows = func.call @sumo_distinct(%both) : (!s32) -> !s32
  %classes = func.call @sumo_by_name(%classRows, %names, %text) : (!s32, !sp, !s8) -> !s32
  %perThing = func.call @sumo_counts(%types, %things) : (!sp, !s32) -> !s32
  %perClass = func.call @sumo_counts(%masks, %classes) : (!sp, !s32) -> !s32

  %nt = trikeshed.size %things : !s32
  %nc = trikeshed.size %classes : !s32
  %nt32 = arith.index_cast %nt : index to i32
  %nc32 = arith.index_cast %nc : index to i32
  %lt = func.call @masks_sum(%perThing) : (!s32) -> i32
  %lc = func.call @masks_sum(%perClass) : (!s32) -> i32
  %four = arith.constant 4 : index
  %counts = trikeshed.series %four : !s32 {
  ^bb0(%i: index):
    %k1 = arith.constant 1 : index
    %k2 = arith.constant 2 : index
    %k3 = arith.constant 3 : index
    %i1 = arith.cmpi eq, %i, %k1 : index
    %i2 = arith.cmpi eq, %i, %k2 : index
    %i3 = arith.cmpi eq, %i, %k3 : index
    %v3 = arith.select %i3, %lc, %nt32 : i32
    %v2 = arith.select %i2, %nc32, %v3 : i32
    %v1 = arith.select %i1, %lt, %v2 : i32
    trikeshed.yield %v1 : i32
  }
  func.call @masks_print(%counts) : (!s32) -> ()
  func.call @masks_print(%perThing) : (!s32) -> ()
  func.call @masks_print(%perClass) : (!s32) -> ()
  %ok = arith.constant 0 : i32
  return %ok : i32
}
