//===- JoinOps.td - The Join algebra as a dialect ---------------*- tablegen -*-===//
//
// TrikeShed's kernel (../TrikeShed/PRELOAD.md) says most shapes collapse back to Join:
//
//   Join<A, B>        two values composed                    !join.pair<A, B>
//   Twin<T>           Join<T, T>                             !join.pair<T, T>
//   a j b             the infix constructor                  join.make
//   a, b              the two components                     join.first / join.second
//   TwInt             Twin<Int> collapsed to one Long        join-densify: !join.pair<i32, i32> -> i64
//
// The JVM stops at Long, so only two Ints collapse there.  LLVM has integers of any width,
// so every Join of fixed-width scalars collapses to ONE integer: a segment of an immutable
// buffer, Join<buffer, Twin<start, end>> = !join.pair<i32, !join.pair<i32, i32>>, is an i96.
//
// Series, Cursor and the Confix index are further layers of the same composite; they are
// not here until something consumes them.
//
//===----------------------------------------------------------------------===//

#ifndef JOIN_OPS_TD
#define JOIN_OPS_TD

include "mlir/IR/OpBase.td"
include "mlir/IR/AttrTypeBase.td"
include "mlir/Interfaces/SideEffectInterfaces.td"

def Join_Dialect : Dialect {
  let name = "join";
  let cppNamespace = "::mlir::join";
  let summary = "Join<A, B>: the one binary composition the other shapes collapse to";
  let description = [{
    `!join.pair<A, B>` composes two values.  `join.make`, `join.first` and `join.second`
    construct and project it.  The `join-densify` pass collapses a join of fixed-width
    scalars (integers, floats, and joins of those) into a single integer, the first
    component in the high bits.
  }];
  let dependentDialects = ["::mlir::arith::ArithDialect"];
  let useDefaultTypePrinterParser = 1;
}

class Join_Type<string name, string typeMnemonic> : TypeDef<Join_Dialect, name> {
  let mnemonic = typeMnemonic;
}

def Join_PairType : Join_Type<"Pair", "pair"> {
  let summary = "Join<A, B>";
  let parameters = (ins "::mlir::Type":$a, "::mlir::Type":$b);
  let assemblyFormat = "`<` $a `,` $b `>`";
  let builders = [TypeBuilderWithInferredContext<(ins "::mlir::Type":$a, "::mlir::Type":$b),
                  [{ return $_get(a.getContext(), a, b); }]>];
}

class Join_Op<string mnemonic, list<Trait> traits = []> : Op<Join_Dialect, mnemonic, traits>;

def Join_MakeOp : Join_Op<"make", [Pure,
    TypesMatchWith<"first operand has the pair's first type", "result", "a",
                   "::llvm::cast<::mlir::join::PairType>($_self).getA()">,
    TypesMatchWith<"second operand has the pair's second type", "result", "b",
                   "::llvm::cast<::mlir::join::PairType>($_self).getB()">]> {
  let summary = "`a j b`";
  let arguments = (ins AnyType:$a, AnyType:$b);
  let results = (outs Join_PairType:$result);
  let assemblyFormat = "$a `,` $b attr-dict `:` type($result)";
  let hasFolder = 1;
  let builders = [OpBuilder<(ins "::mlir::Value":$a, "::mlir::Value":$b),
                  [{ build($_builder, $_state, PairType::get(a.getType(), b.getType()), a, b); }]>];
}

def Join_FirstOp : Join_Op<"first", [Pure,
    TypesMatchWith<"result has the pair's first type", "pair", "result",
                   "::llvm::cast<::mlir::join::PairType>($_self).getA()">]> {
  let summary = "the first component of a Join";
  let arguments = (ins Join_PairType:$pair);
  let results = (outs AnyType:$result);
  let assemblyFormat = "$pair attr-dict `:` type($pair)";
  let hasFolder = 1;
}

def Join_SecondOp : Join_Op<"second", [Pure,
    TypesMatchWith<"result has the pair's second type", "pair", "result",
                   "::llvm::cast<::mlir::join::PairType>($_self).getB()">]> {
  let summary = "the second component of a Join";
  let arguments = (ins Join_PairType:$pair);
  let results = (outs AnyType:$result);
  let assemblyFormat = "$pair attr-dict `:` type($pair)";
  let hasFolder = 1;
}

#endif // JOIN_OPS_TD
