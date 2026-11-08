// kif-chase: a theory's rules chained forward, each new fact a kif.derived with the rule (datalog.nix's name: the consequent's
// relation and the rule's place) and the facts its premises matched.  @onto says what (instance X Class) means.
// RUN: mlnix-opt %s --kif-chase | FileCheck %s
// RUN: mlnix-opt %s --kif-chase | mlnix-opt | FileCheck %s
// The importer and the closure dump (scripts/kif-oracle.py compares it with datalog.nix and with nix-truffle):
// RUN: d=$(dirname %s)/../kif; mlnix-kif --chase --dump --ontology $d/chase-onto.kif $d/chase-cases.kif | FileCheck %s --check-prefix=DUMP

// The ontology gives classes, not facts: it is not chased.
// CHECK-LABEL: kif.theory @onto
// CHECK-NOT: kif.derived
kif.theory @onto {
  %sub = kif.atom "subclass"
  %dog = kif.atom "Dog"
  %mammal = kif.atom "Mammal"
  %s = kif.list(%sub, %dog, %mammal)
  kif.fact %s
}

// rex is a Dog, a Dog is a Mammal: round 1 gives (furry rex) from the instance fact; round 2 (furry2 rex) from it.
// CHECK-LABEL: kif.theory @kb
// CHECK: kif.derived %[[F1:[0-9]+]] by "furry#1" round 1 from(%{{[0-9]+}})
// CHECK: kif.derived %{{[0-9]+}} by "furry2#2" round 2 from(%[[F1]])
kif.theory @kb attributes {ontology = @onto} {
  %inst = kif.atom "instance"
  %rex = kif.atom "rex"
  %dog = kif.atom "Dog"
  %mammal = kif.atom "Mammal"
  %x = kif.var "?x"
  %f = kif.list(%inst, %rex, %dog)
  kif.fact %f
  %p = kif.list(%inst, %x, %mammal)
  %furry = kif.atom "furry"
  %c = kif.list(%furry, %x)
  kif.rule %p implies %c
  %next = kif.atom "furry2"
  %c2 = kif.list(%next, %x)
  kif.rule %c implies %c2
}

// DUMP: (allowed p1)	allowed#{{[0-9]+}}	(person p1)
// DUMP: (animal rex)	animal#1	(instance rex Dog)
// DUMP: (fof a d)	fof#3	(likes a b)	(likes b d)
// DUMP: (h x)	h#{{[0-9]+}}	(likes a c)
// DUMP: (petOwner ann)	petOwner#2	(instance rex Dog)	(owns ann rex)
