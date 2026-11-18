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
//               arguments and the lambda's own argument is the last. The idiom 77de09c:docs/MLIR.md names for the gap that
//               nix.lambda is not isolated: a pass manager can run on a body, on several threads, loaded on demand.
//   son.defer   the lambda as a node that holds no body, only the row it is minted from and the values it captures.
//   nix-defer   nix.lambda -> son.defer + son.body   (the demand schedule, as a rewrite)
//   son-mint    son.defer -> nix.lambda               (the eager schedule; the inverse: a round trip is the identity)
//   son.release what a call's frame may keep when it returns: the Graal arm's frame (graal/, BodyRoot.release),
//               made by son-release from the schedule's must-force set (what is forced on every path that returns)
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

    `arg_forced`, derived by `son-release` as `son.release` is: the body forces its argument on every path on which it
    returns, and returns on some path (its must-force set, SonDialect.cpp MustForce); a pattern's body always does, as a
    call checks the set before the body runs. It is the callee's half of a call's must-force set, the half a caller does
    not see when the function arrives as a value: a caller that finds it on the body it calls may compute the argument
    before the call, and make no cell over its own frame for it (the Graal arm, graal/: ApplyNode). An argument whose
    computation throws is passed as the error, so a callee that throws first still throws its own.

    `forced_captures`, derived the same way: the captures, by index, that the body forces on every path on which it
    returns. With `arg_forced` it is the body's must-force set over its block arguments. A body that returns a closure
    it makes (`son.defer`) over its own argument, whose row forces that capture, forces its argument once the closure is
    applied: a curried call (`f a b`) applies it at once, so its caller may compute `a` first as well.
  }];
  let arguments = (ins SymbolNameAttr:$sym_name, ConfinedAttr<I32Attr, [IntMinValue<0>]>:$captures, AnyAttr:$lambda,
                       UnitAttr:$arg_forced, OptionalAttr<DenseI32ArrayAttr>:$forced_captures);
  let regions = (region SizedRegion<1>:$body);
  let assemblyFormat = "$sym_name `captures` $captures `lambda` $lambda (`arg_forced` $arg_forced^)? "
                       "(`forced_captures` $forced_captures^)? attr-dict-with-keyword $body";
  let hasVerifier = 1;
}

def Son_DeferOp : Son_Op<"defer", [DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "a lambda that holds no body yet";
  let description = [{
    Evaluating a call of the value mints the row's body with the captures bound to the operands. The value has an
    identity of its own (two defers of one row are two functions), so the result is a fresh value.
  }];
  let arguments = (ins SymbolRefAttr:$row, Variadic<NixAny>:$captures);
  let results = (outs NixFreshFn:$result); // the lambda it stands for
  let assemblyFormat = "$row `(` custom<NixValues>($captures, type($captures)) `)` attr-dict";
}

def Son_ReleaseOp : Son_Op<"release", [ParentOneOf<["BodyOp", "::mlir::nix::ExprOp"]>]> {
  let summary = "what a call's frame may keep when the call returns";
  let description = [{
    The Graal arm's frame, in the IR (graal/: BodyRoot.release).  A call of a body is a frame of slots, one per block
    argument and per op result; an op runs when its value is first forced, and an op result passed on without forcing (a
    list element, an attribute's value, an argument of an apply or a primop, a capture of a defer or of a lambda not
    deferred yet) is a cell that holds the frame until it is forced.  An argument passed on is the caller's cell, as it
    came, and holds no frame.  When the call returns, the frame keeps what its unforced cells can read and releases the
    rest.  Which cells are still unforced is known only then; `kept` is what the IR knows before.  The schedule knows the
    values forced on every path on which the call returns (the must-force set, SonDialect.cpp: the return value, what a
    forced op always forces, what both arms of an if force, a callee's argument where the callee is a defer of the frame
    that forces it; a throw returns on no path): a cell among them is a value by the return and reads nothing.  So `kept`
    is the other cells and their operands, followed through the operands not forced either (a forced one is kept as the
    value it is).  Every value of the frame not in `kept` is released when the call returns, on every path.  The
    verifier checks that no value a cell can read is released; `kept` may hold more (a release that keeps the whole
    frame is sound).  `son-release` makes it; `son-mint` drops it (it is derived, and a minted lambda is not a frame).
  }];
  let arguments = (ins Variadic<NixAny>:$kept);
  let assemblyFormat = "`(` custom<NixValues>($kept, type($kept)) `)` attr-dict";
  let hasVerifier = 1;
}

#endif // SON_TD
