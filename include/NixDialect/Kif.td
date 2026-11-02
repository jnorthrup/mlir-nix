//===- Kif.td - SUO-KIF as an MLIR dialect ----------------------*- tablegen -*-===//
//
// The layers of the solver, top to bottom (each lowers to the one below):
//
//   sumo      the SUMO relations as typed ops, and the solver's requests            (Sumo.td)
//   kif       this file: KIF terms, facts and rules as ops                          sumo-to-kif ends here
//   nix       the language the solver runs in: a theory becomes `nix.list`s of `nix.str`  kif-to-nix ends here
//   son       the sea of nodes: the schedule of when a node exists                  (not declared yet)
//   trikeshed Join, Series, Cursor: the data the nodes are made of                  (TrikeShed.td)
//
// A KIF term is a node. `kif.atom`, `kif.var` and `kif.list` are pure and live in a graph region, so stock `cse` makes
// equal terms ONE node: hash-consing, the way a sea of nodes shares them, and a fact that two rules mention is one
// value both read. A `kif.theory` holds terms, the facts and rules that use them, and the sumo ops that stand for facts.
//
// Mirrors sumo-nix/kif.nix (the reader: an atom is a string, a list is a list) and sumo-nix/datalog.nix (the solver
// for the Horn rules: `(=> antecedent consequent)`), which are the oracle for what the lowering must give.
//
//===----------------------------------------------------------------------===//

#ifndef KIF_TD
#define KIF_TD

include "mlir/IR/OpBase.td"
include "mlir/IR/AttrTypeBase.td"
include "mlir/IR/RegionKindInterface.td"
include "mlir/IR/SymbolInterfaces.td"
include "mlir/Interfaces/SideEffectInterfaces.td"

def Kif_Dialect : Dialect {
  let name = "kif";
  let cppNamespace = "::mlir::kif";
  let summary = "SUO-KIF terms, facts and rules";
  let description = [{
    S-expressions of the Knowledge Interchange Format as pure nodes of a graph region: an atom, a variable (`?x`) and
    a list. A fact asserts a term; a rule says that when its antecedent term holds its consequent term holds.
  }];
  let useDefaultTypePrinterParser = 1;
}

def Kif_TermType : TypeDef<Kif_Dialect, "Term"> {
  let mnemonic = "term";
  let summary = "a KIF term";
}

def Kif_Term : Type<CPred<"::llvm::isa<::mlir::kif::TermType>($_self)">, "a KIF term", "::mlir::kif::TermType">,
    BuildableType<"$_builder.getType<::mlir::kif::TermType>()">;

class Kif_Op<string mnemonic, list<Trait> traits = []> : Op<Kif_Dialect, mnemonic, traits>;

def Kif_AtomOp : Kif_Op<"atom", [Pure]> {
  let summary = "a constant: Human, 3, \"text\"";
  let arguments = (ins StrAttr:$name);
  let results = (outs Kif_Term:$term);
  let assemblyFormat = "$name attr-dict";
}

def Kif_VarOp : Kif_Op<"var", [Pure]> {
  let summary = "a variable: its name starts with ?";
  let arguments = (ins StrAttr:$name);
  let results = (outs Kif_Term:$term);
  let assemblyFormat = "$name attr-dict";
  let hasVerifier = 1;
}

def Kif_ListOp : Kif_Op<"list", [Pure]> {
  let summary = "a parenthesized list of terms";
  let arguments = (ins Variadic<Kif_Term>:$elements);
  let results = (outs Kif_Term:$term);
  let assemblyFormat = "`(` $elements `)` attr-dict";
}

def Kif_TheoryOp : Kif_Op<"theory", [Symbol, SingleBlock, NoTerminator, IsolatedFromAbove,
    DeclareOpInterfaceMethods<RegionKindInterface>]> {
  let summary = "terms, facts and rules";
  let arguments = (ins SymbolNameAttr:$sym_name);
  let regions = (region SizedRegion<1>:$body);
  let assemblyFormat = "$sym_name attr-dict-with-keyword $body";
}

def Kif_FactOp : Kif_Op<"fact", [HasParent<"TheoryOp">]> {
  let summary = "a term that holds";
  let arguments = (ins Kif_Term:$term);
  let assemblyFormat = "$term attr-dict";
}

def Kif_RuleOp : Kif_Op<"rule", [HasParent<"TheoryOp">]> {
  let summary = "when the antecedent holds, the consequent holds";
  let description = [{
    The `(=> antecedent consequent)` form. The antecedent is an `and` list of premises, or one premise. The solver
    (sumo-nix/datalog.nix) chains rules forward to a fixpoint and keeps the rule and the premises of every fact it derives.
  }];
  let arguments = (ins Kif_Term:$antecedent, Kif_Term:$consequent);
  let assemblyFormat = "$antecedent `implies` $consequent attr-dict";
}

#endif // KIF_TD
