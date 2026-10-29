//===- NixOps.td - The Nix language as an MLIR dialect ------*- tablegen -*-===//
//
// Design
// ------
// Every SSA value of type !nix.value denotes a *lazy* Nix value (a thunk).
// Defining an op does not evaluate it; the evaluator materialises a thunk per
// (op, activation frame) and only runs the op when the value is forced.  This
// gives exact Nix call-by-need semantics with plain SSA data-flow.
//
// Bodies of `nix.expr` and `nix.lambda` are single-block *graph* regions, so
// SSA values may be used before they are defined and may form cycles.  That is
// precisely what `let` and `rec { }` need: recursive bindings are just
// forward/cyclic SSA references, and all lexical scoping is resolved at
// lowering time.  Only `with` remains dynamic (`nix.with_var`).
//
// Memory effects and speculation are separate contracts. NoMemoryEffect permits
// value numbering; it does not promise that forcing a thunk terminates without
// errors or effects from its lazy operands. Only scalar literals are always
// speculatable. Fallible/forcing ops remain conservative even with constant
// operands; a folding pass may first replace them with a proven scalar literal.
//===----------------------------------------------------------------------===//

#ifndef NIX_OPS_TD
#define NIX_OPS_TD

include "mlir/IR/RegionKindInterface.td"
include "mlir/IR/SymbolInterfaces.td"
include "NixBase.td"

class Nix_Op<string mnemonic, list<Trait> traits = []>
    : Op<Nix_Dialect, mnemonic, traits>;

//===----------------------------------------------------------------------===//
// Structure
//===----------------------------------------------------------------------===//

def Nix_ExprOp : Nix_Op<"expr", [
    Symbol, SingleBlock, IsolatedFromAbove,
    DeclareOpInterfaceMethods<RegionKindInterface>]> {
  let summary = "a top-level Nix expression (one source file / -E string)";
  let arguments = (ins SymbolNameAttr:$sym_name,
                       OptionalAttr<StrAttr>:$source_path,
                       OptionalAttr<StrAttr>:$base_dir);
  let regions = (region SizedRegion<1>:$body);
  let assemblyFormat = "$sym_name attr-dict-with-keyword $body";
}

def Nix_ReturnOp : Nix_Op<"return", [Terminator, NoMemoryEffect, NixModes<[], [0]>,
    ParentOneOf<["ExprOp", "LambdaOp"]>]> {
  let summary = "result of the enclosing expression / lambda body";
  let arguments = (ins NixVal:$value);
  let assemblyFormat = "$value attr-dict";
}

def Nix_LambdaOp : Nix_Op<"lambda", [SingleBlock,
    DeclareOpInterfaceMethods<RegionKindInterface>]> {
  let summary = "function abstraction";
  let description = [{
    The body is a graph region with exactly one block argument: the value the
    function is applied to.  For pattern-matching lambdas (`{ a, b ? 1, ... }:`)
    `formals`/`formal_defaults`/`ellipsis` describe the pattern; the body binds
    each formal with `nix.formal`.  `arg_name` is the simple argument name or the
    `@`-binding, kept for printing and diagnostics.

    The deferred form (the sea-of-nodes schedule, MLNIX_DEFER) carries no body
    graph at lowering time.  `body_index` is `file j row` (a TwInt) into the
    frontend's pool of deferred lambdas, and `captures` are the values the body
    reads from the enclosing scopes: the `with` chain, innermost first, then the
    free names the pool row lists.  The body is minted on the first call, from
    the retained AST, by the same generator that mints it eagerly.  The captures
    are real operands so that the uses the waiting body will make exist already.

    A deferred lambda is a shell that exists only in memory, between lowering
    and its first call: its block is empty, so this verifier (the SingleBlock
    trait) refuses it, and it can be neither printed as custom syntax nor read
    back.  The evaluator never verifies, and `mlnix emit-mlir` lowers eagerly.
  }];
  let arguments = !con((ins OptionalAttr<StrArrayAttr>:$formals,
                       OptionalAttr<DenseBoolArrayAttr>:$formal_defaults,
                       UnitAttr:$ellipsis,
                       OptionalAttr<StrAttr>:$arg_name,
                       OptionalAttr<StrAttr>:$name,
                       OptionalAttr<DenseI64ArrayAttr>:$formal_locs,
                       Variadic<NixVal>:$captures,
                       OptionalAttr<I64Attr>:$body_index), NixPos);
  let results = (outs NixFreshVal:$result);
  let regions = (region SizedRegion<1>:$body);
  let assemblyFormat = "(`(`$captures^`)`)? attr-dict-with-keyword $body";
  let hasVerifier = 1;
  let extraClassDeclaration = [{
    bool hasFormals() { return getFormals().has_value(); }
    ::mlir::BlockArgument getArgument() { return getBody().front().getArgument(0); }
  }];
}

def Nix_FormalOp : Nix_Op<"formal", [NoMemoryEffect]> {
  let summary = "bind one formal of a pattern lambda";
  let description = [{
    `arg.name` if the argument set has the attribute, otherwise `default`.
  }];
  let arguments = !con((ins NixVal:$arg, Nix_NameProp:$name, Optional<NixVal>:$default_value), NixPos);
  let results = (outs NixVal:$result);
  let assemblyFormat = "$arg $name (`default` $default_value^)? attr-dict";
}

//===----------------------------------------------------------------------===//
// Constants / references
//===----------------------------------------------------------------------===//

def Nix_IntOp : Nix_Op<"int", [ConstantLike, Pure]> {
  let arguments = !con((ins I64Attr:$value), NixPos);
  let results = (outs NixVal:$result);
  let assemblyFormat = "$value attr-dict";
  let hasFolder = 1;
}

def Nix_FloatOp : Nix_Op<"float", [ConstantLike, Pure]> {
  let arguments = !con((ins F64Attr:$value), NixPos);
  let results = (outs NixVal:$result);
  let assemblyFormat = "$value attr-dict";
  let hasFolder = 1;
}

def Nix_StringOp : Nix_Op<"str", [ConstantLike, Pure]> {
  let summary = "string literal (no context)";
  let arguments = !con((ins Nix_NameProp:$value), NixPos);
  let results = (outs NixVal:$result);
  let assemblyFormat = "$value attr-dict";
  let hasFolder = 1;
}

def Nix_BoolOp : Nix_Op<"bool", [ConstantLike, Pure]> {
  let summary = "the literals `true` and `false`";
  let arguments = (ins BoolAttr:$value);
  let results = (outs NixVal:$result);
  let assemblyFormat = "$value attr-dict";
  let hasFolder = 1;
}

def Nix_NullOp : Nix_Op<"null", [ConstantLike, Pure]> {
  let summary = "the literal `null`";
  let results = (outs NixVal:$result);
  let assemblyFormat = "attr-dict";
  let hasFolder = 1;
}

def Nix_PathOp : Nix_Op<"path", [Pure]> {
  let summary = "absolute, canonical path literal";
  let arguments = !con((ins Nix_NameProp:$value), NixPos);
  let results = (outs NixVal:$result);
  let assemblyFormat = "$value attr-dict";
}

def Nix_BuiltinOp : Nix_Op<"builtin", [NoMemoryEffect]> {
  let summary = "reference to an entry of the global base environment";
  let arguments = (ins Nix_NameProp:$name);
  let results = (outs NixVal:$result);
  let assemblyFormat = "$name attr-dict";
}

def Nix_WithVarOp : Nix_Op<"with_var", [NoMemoryEffect]> {
  let summary = "dynamically scoped variable lookup through `with` scopes";
  let description = [{
    Looks `name` up in each scope operand in order (innermost `with` first).
  }];
  let arguments = !con((ins Nix_NameProp:$name, Variadic<NixVal>:$scopes), NixPos);
  let results = (outs NixVal:$result);
  let assemblyFormat = "$name (`in` $scopes^)? attr-dict";
}

//===----------------------------------------------------------------------===//
// Data constructors
//===----------------------------------------------------------------------===//

def Nix_ListOp : Nix_Op<"list"> {
  let arguments = !con((ins Variadic<NixVal>:$elements), NixPos);
  let results = (outs NixFreshVal:$result);
  let assemblyFormat = "`[` $elements `]` attr-dict";
}

def Nix_AttrsOp : Nix_Op<"attrs", [AttrSizedOperandSegments]> {
  let summary = "attribute set construction";
  let description = [{
    `names[i]` is bound to `values[i]`.  Dynamic attributes (`${e} = v;`) pair
    `dyn_names[j]` with `dyn_values[j]`; they are inserted in order at
    evaluation time and a `null` name drops the attribute.
  }];
  let arguments = !con((ins Nix_NamesProp:$names, Variadic<NixVal>:$values,
                       Variadic<NixVal>:$dyn_names, Variadic<NixVal>:$dyn_values,
                       Nix_I64sProp:$positions), NixPos);
  let results = (outs NixFreshVal:$result);
  let assemblyFormat = [{
    $names `(` $values `)` (`dynamic` `(` $dyn_names^ `)` `=` `(` $dyn_values `)`)? attr-dict
  }];
  let hasVerifier = 1;
}

//===----------------------------------------------------------------------===//
// Elimination forms
//===----------------------------------------------------------------------===//

def Nix_SelectOp : Nix_Op<"select", [NoMemoryEffect, AttrSizedOperandSegments, NixModes<[0], []>]> {
  let summary = "attribute path selection `e.a.b or d`";
  let description = [{
    `path` has one element per path component: a name for a literal component
    (`a`), the null name for a computed one (`${e}`) which takes the next operand
    of `dyn_keys`.  This is the static/dynamic mix used by `memref.subview`:
    literal names are properties (a pointer and a length, not uniqued), not ops.

        %v = nix.select %set ["pkgs", %k, "version"] or %default
  }];
  let arguments = !con((ins NixVal:$base, Variadic<NixVal>:$dyn_keys,
                       Optional<NixVal>:$default_value, Nix_NamesProp:$path), NixPos);
  let results = (outs NixVal:$result);
  let assemblyFormat =
      "$base custom<AttrPath>($path, $dyn_keys) (`or` $default_value^)? attr-dict";
  let hasVerifier = 1;
}

def Nix_HasAttrOp : Nix_Op<"has_attr", [NoMemoryEffect, NixModes<[0], []>]> {
  let summary = "attribute path test `e ? a.b`";
  let description = [{ `path`/`dyn_keys` as in `nix.select`. }];
  let arguments = !con((ins NixVal:$base, Variadic<NixVal>:$dyn_keys, Nix_NamesProp:$path), NixPos);
  let results = (outs NixVal:$result);
  let assemblyFormat = "$base custom<AttrPath>($path, $dyn_keys) attr-dict";
  let hasVerifier = 1;
}

def Nix_ApplyOp : Nix_Op<"apply", NixFxUser> {
  let summary = "(curried) function application";
  let arguments = !con((ins NixVal:$callee, Variadic<NixVal>:$args), NixPos);
  let results = (outs NixVal:$result);
  let assemblyFormat = "$callee `(` $args `)` attr-dict";
}

def Nix_IfOp : Nix_Op<"if", [NoMemoryEffect, NixModes<[0], [1, 2]>]> {
  let arguments = !con((ins NixVal:$cond, NixVal:$then_value, NixVal:$else_value), NixPos);
  let results = (outs NixVal:$result);
  let assemblyFormat = "$cond `then` $then_value `else` $else_value attr-dict";
}

def Nix_AssertOp : Nix_Op<"assert", [NoMemoryEffect, NixModes<[0], [1]>]> {
  let arguments = !con((ins NixVal:$cond, NixVal:$body, OptionalAttr<StrAttr>:$text), NixPos);
  let results = (outs NixVal:$result);
  let assemblyFormat = "$cond `in` $body attr-dict";
}

//===----------------------------------------------------------------------===//
// Native operators (the others desugar to calls of __sub, __mul, __div,
// __lessThan exactly as upstream Nix does, so they remain overridable).
//===----------------------------------------------------------------------===//

class Nix_BinOp<string mnemonic, list<Trait> traits = [NoMemoryEffect]> : Nix_Op<mnemonic, traits> {
  let arguments = !con((ins NixVal:$lhs, NixVal:$rhs), NixPos);
  let results = (outs NixVal:$result);
  let assemblyFormat = "$lhs `,` $rhs attr-dict";
}

def Nix_EqOp      : Nix_BinOp<"eq", [NoMemoryEffect, NixModes<[0, 1], []>]>;
def Nix_NeqOp     : Nix_BinOp<"neq", [NoMemoryEffect, NixModes<[0, 1], []>]>;
def Nix_AndOp     : Nix_BinOp<"and", [NoMemoryEffect, NixModes<[0, 1], []>]>;
def Nix_OrOp      : Nix_BinOp<"or", [NoMemoryEffect, NixModes<[0, 1], []>]>;
def Nix_ImplOp    : Nix_BinOp<"impl", [NoMemoryEffect, NixModes<[0, 1], []>]>;
// `a // b` and `a ++ b` allocate a new attribute set / list.
class Nix_FreshBinOp<string mnemonic> : Nix_BinOp<mnemonic, [NixModes<[0, 1], []>]> {
  let results = (outs NixFreshVal:$result);
}
def Nix_UpdateOp  : Nix_FreshBinOp<"update">;
def Nix_ConcatListsOp : Nix_FreshBinOp<"concat_lists">;

def Nix_NotOp : Nix_Op<"not", [NoMemoryEffect, NixModes<[0], []>]> {
  let arguments = !con((ins NixVal:$operand), NixPos);
  let results = (outs NixVal:$result);
  let assemblyFormat = "$operand attr-dict";
}

def Nix_ConcatStringsOp : Nix_Op<"concat_strings", [NoMemoryEffect]> {
  let summary = "`+` (force_string = false) and string interpolation (true)";
  let arguments = !con((ins Variadic<NixVal>:$parts, UnitAttr:$force_string), NixPos);
  let results = (outs NixVal:$result);
  let assemblyFormat = "$parts attr-dict";
  let hasFolder = 1;
}

#endif // NIX_OPS_TD
