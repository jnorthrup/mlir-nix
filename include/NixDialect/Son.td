//===- Son.td - The sea of nodes: when a lambda body exists -------*- tablegen -*-===//
//
// The layer between the nix dialect and TrikeShed's series. A nix.lambda is a node whose body is a graph region of
// nodes; most of those nodes are never evaluated (docs/SEA-OF-NODES.md: 89-90% on nixos-toplevel). The schedule decides
// when they exist. The evaluator does it in memory: `nix.lambda` carries a pool row (`body_index`, `file j row`) and
// the body is minted on the first call from the retained source (MLNIX_DEFER). That deferred shell cannot be printed,
// parsed or verified. This dialect gives it an IR form that can:
//
//   son.pool @bodies { son.body @row0 captures 2 {..} { ^bb0(%c0, %c1, %x): .. } .. }
//   %f = son.defer @bodies::@row0(%a, %b)
//
//   son.body    a lambda body closed over its captures: IsolatedFromAbove, the captures are the first block
//               arguments and the lambda's own argument is the last. The idiom docs/MLIR.md names for the gap that
//               nix.lambda is not isolated: a pass manager can run on a body, on several threads, loaded on demand.
//   son.defer   the lambda as a node that holds no body, only the row it is minted from and the values it captures.
//   nix-defer   nix.lambda -> son.defer + son.body   (the demand schedule, as a rewrite)
//   son-mint    son.defer -> nix.lambda               (the eager schedule; the inverse: a round trip is the identity)
//
// The pool rows are TrikeShed's PoolCol columns (TrikeShed.td); lowering the pool to trikeshed.append and trikeshed.anchor
// is the next step.
//
//===----------------------------------------------------------------------===//

#ifndef SON_TD
#define SON_TD

include "mlir/IR/OpBase.td"
include "mlir/IR/RegionKindInterface.td"
include "mlir/IR/SymbolInterfaces.td"
include "NixBase.td"

def Son_Dialect : Dialect {
  let name = "son";
  let cppNamespace = "::mlir::son";
  let summary = "The schedule of a sea of nodes: deferred lambda bodies";
  let dependentDialects = ["::mlir::nix::NixDialect"];
}

class Son_Op<string mnemonic, list<Trait> traits = []> : Op<Son_Dialect, mnemonic, traits>;

def Son_PoolOp : Son_Op<"pool", [Symbol, SymbolTable, SingleBlock, NoTerminator, IsolatedFromAbove]> {
  let summary = "the lambda bodies that wait for their first call";
  let arguments = (ins SymbolNameAttr:$sym_name);
  let regions = (region SizedRegion<1>:$rows);
  let assemblyFormat = "$sym_name attr-dict-with-keyword $rows";
}

def Son_BodyOp : Son_Op<"body", [Symbol, HasParent<"PoolOp">, SingleBlock, IsolatedFromAbove,
    DeclareOpInterfaceMethods<RegionKindInterface>]> {
  let summary = "one lambda body, closed over its captures";
  let description = [{
    The entry block takes `captures` arguments, then the lambda's argument, all `!nix.value`. `lambda` holds the
    properties of the `nix.lambda` it came from (formals, arg_name, name, positions), so `son-mint` restores it exactly.
  }];
  let arguments = (ins SymbolNameAttr:$sym_name, ConfinedAttr<I32Attr, [IntMinValue<0>]>:$captures, AnyAttr:$lambda);
  let regions = (region SizedRegion<1>:$body);
  let assemblyFormat = "$sym_name `captures` $captures `lambda` $lambda attr-dict-with-keyword $body";
  let hasVerifier = 1;
}

def Son_DeferOp : Son_Op<"defer", [DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "a lambda that holds no body yet";
  let description = [{
    Evaluating a call of the value mints the row's body with the captures bound to the operands. The value has an
    identity of its own (two defers of one row are two functions), so the result is a fresh value.
  }];
  let arguments = (ins SymbolRefAttr:$row, Variadic<NixVal>:$captures);
  let results = (outs NixFreshVal:$result);
  let assemblyFormat = "$row `(` $captures `)` attr-dict";
}

#endif // SON_TD
