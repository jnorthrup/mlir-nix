//===- Sumo.td - SUMO's relations as ops, and the solver's requests -*- tablegen -*-===//
//
// The top layer. A sumo op stands for a KIF fact and lowers to one (`sumo-to-kif`); it lives in a `kif.theory`, which
// is why this dialect needs no container of its own:
//
//   sumo.subclass "Human" "Hominid"      ->  (subclass Human Hominid)
//   sumo.instance "nginx" "NIXService"   ->  (instance nginx NIXService)
//   sumo.domain "part" 1 "Object"        ->  (domain part 1 Object)
//   sumo.range  "part" 2 "Object"        ->  (range part 2 Object)
//   sumo.holds "dependsOn" ["curl", "openssl"]  ->  (dependsOn curl openssl)
//
// The solver is the layers below it: the facts and the rules of the theory, chained forward by sumo-nix/datalog.nix
// on the nix dialect. Subclass reasoning (an instance of a subclass is an instance of the class) is the ontology's
// (sumo-nix/sumo.nix), read from the pinned Merge.kif.
//
//===----------------------------------------------------------------------===//

#ifndef SUMO_TD
#define SUMO_TD

include "mlir/IR/OpBase.td"
include "mlir/IR/AttrTypeBase.td"
include "mlir/Interfaces/SideEffectInterfaces.td"

def Sumo_Dialect : Dialect {
  let name = "sumo";
  let cppNamespace = "::mlir::sumo";
  let summary = "SUMO relations as KIF facts";
  let dependentDialects = ["::mlir::kif::KifDialect"];
}

class Sumo_Op<string mnemonic, list<Trait> traits = []>
    : Op<Sumo_Dialect, mnemonic, !listconcat(traits, [HasParent<"::mlir::kif::TheoryOp">])>;

def Sumo_SubclassOp : Sumo_Op<"subclass"> {
  let summary = "every instance of the child is an instance of the parent";
  let arguments = (ins StrAttr:$child, StrAttr:$parent);
  let assemblyFormat = "$child $parent attr-dict";
}

def Sumo_InstanceOp : Sumo_Op<"instance"> {
  let summary = "a thing belongs to a class";
  let arguments = (ins StrAttr:$thing, StrAttr:$class_name);
  let assemblyFormat = "$thing $class_name attr-dict";
}

def Sumo_DomainOp : Sumo_Op<"domain"> {
  let summary = "the class the argument at a position of a relation belongs to";
  let arguments = (ins StrAttr:$relation, ConfinedAttr<I32Attr, [IntMinValue<1>]>:$position, StrAttr:$class_name);
  let assemblyFormat = "$relation $position $class_name attr-dict";
}

def Sumo_RangeOp : Sumo_Op<"range"> {
  let summary = "the class the argument at a position of a relation belongs to, for the value it gives";
  let arguments = (ins StrAttr:$relation, ConfinedAttr<I32Attr, [IntMinValue<1>]>:$position, StrAttr:$class_name);
  let assemblyFormat = "$relation $position $class_name attr-dict";
}

def Sumo_HoldsOp : Sumo_Op<"holds"> {
  let summary = "a relation holds between things";
  let arguments = (ins StrAttr:$relation, StrArrayAttr:$args);
  let assemblyFormat = "$relation $args attr-dict";
}

// ---- a relation of a theory as a TrikeShed cursor (PRELOAD-DIALECTS step 6): lowered in trikeshed-lower-cursors

// Not a Sumo_Op: a query over a theory's tables, used outside the theory.
def Sumo_RelationOp : Op<Sumo_Dialect, "relation", [Pure]> {
  let summary = "a relation's rows in a theory: the arguments of each top-level fact (relation a1 .. an), a cursor";
  let description = [{
    sumo-nix's sumo.nix reads a relation as `top name` kept to the forms of its arity whose arguments are strings (not
    lists): `parents` from (subclass Child Parent), `classOf` from (instance Thing Class), `domains` from (domain Relation
    Position Class).  SumoClassifier.kt's taxonomy keeps the same pairs as flat term-id pairs (`subclassEdges`,
    `instanceEdges`, the domain slots).  This op is that projection over a theory's tables (kif.terms, kif.facts):

      %sub = sumo.relation %subclass of %facts in %terms, %kids
           : i32, !trikeshed.cursor<"KifFact", [i32, i32]>, !trikeshed.cursor<"KifTerm", [i8, ...]>, !trikeshed.series<i32>
             -> !trikeshed.cursor<"subclass", [i32, i32]>

    `relation` is the row of the relation's atom (kif.atom_row); the result has one i32 column per argument, its width the
    arity, and one row per fact (term rows; a fact asserted twice is two rows), in the facts' order.  A fact is kept when
    its term is a list of arity + 1 elements, the first the relation, none of the others a list.  sumo.nix's strings are
    the atoms, the variables and the string literals; SumoClassifier also leaves out variables, string literals and a
    domain position that is not an integer, so on such facts the two differ, and this op follows sumo.nix.
  }];
  let arguments = (ins I32:$relation, AnyType:$facts, AnyType:$terms, AnyType:$kids);
  let results = (outs AnyType:$rows);
  let assemblyFormat = [{
    $relation `of` $facts `in` $terms `,` $kids attr-dict `:` type($facts) `,` type($terms) `,` type($kids) `->` type($rows)
  }];
  let hasVerifier = 1;
}

#endif // SUMO_TD
