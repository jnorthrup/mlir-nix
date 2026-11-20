//===- Kursive.td - TrikeShed's kursive combinators as a dialect: regular expressions as combinators -*- tablegen -*-===//
//
// ../TrikeShed/src/commonMain/kotlin/borg/trikeshed/parse/kursive (legacy/Jursive.kt, std.kt): a KursiveStep is
// (JursiveCharSeries) -> Boolean, a parser over a cursor with a checkpoint and a rewind, and the grammar is the
// combinators `then`, `or`, `opt`, `repeat(min)`, `many`, `maybe`, `choice`, `Char.s`/`ch`, `lit`, `peekIs`; a named
// parser emits (name, start, end), a span.  Here those combinators are ops over `!kursive.step` values, in the region of
// a `kursive.regex`:
//
//   kursive.set      one byte from a 256-bit set (Char.s, peekIs over a set)
//   kursive.lit      a literal byte string (std.lit)
//   kursive.then     a sequence (then)
//   kursive.or       alternatives: Kotlin's ordered choice (or, choice), or with `longest` the POSIX alternation that
//                    std::regex::extended executes (every branch tried, the longest wins)
//   kursive.repeat   greedy repetition [min, max], max -1 unbounded (repeat(min), many, opt = [0, 1], maybe)
//   kursive.group    a capture: the span a named parser emits, numbered
//   kursive.bol, kursive.eol, kursive.empty
//
// `--re2mlir` reads POSIX extended regular expressions (`kursive.pattern`, what builtins.match and builtins.split take)
// into these combinators, accepting and rejecting what Kursive.h's compiler accepts and rejects (Invalid, Space).
// `--kursive-to-program` lowers each `kursive.regex` to the Step/Set Program that mlnix_kursive_walk
// (lowered/nixeval/KursiveOps.mlir) runs, as constant globals.  The passes are in lib/Dialect/KursiveDialect.cpp.
//
//===----------------------------------------------------------------------===//

#ifndef KURSIVE_TD
#define KURSIVE_TD

include "mlir/IR/OpBase.td"
include "mlir/IR/AttrTypeBase.td"
include "mlir/IR/CommonAttrConstraints.td"
include "mlir/IR/SymbolInterfaces.td"
include "mlir/Interfaces/SideEffectInterfaces.td"

def Kursive_Dialect : Dialect {
  let name = "kursive";
  let cppNamespace = "::mlir::kursive";
  let summary = "TrikeShed's kursive parser combinators; regular expressions as combinators";
  let useDefaultTypePrinterParser = 1;
}

def Kursive_StepType : TypeDef<Kursive_Dialect, "Step"> {
  let mnemonic = "step";
  let summary = "a KursiveStep: (JursiveCharSeries) -> Boolean, a parser that moves the cursor or fails";
}

def Kursive_Step : Type<CPred<"::llvm::isa<::mlir::kursive::StepType>($_self)">, "a kursive step", "::mlir::kursive::StepType">,
    BuildableType<"$_builder.getType<::mlir::kursive::StepType>()">;

class Kursive_Op<string mnemonic, list<Trait> traits = []> : Op<Kursive_Dialect, mnemonic, traits>;

//===----------------------------------------------------------------------===//
// The texts and the grammars
//===----------------------------------------------------------------------===//

def Kursive_PatternOp : Kursive_Op<"pattern", [Symbol]> {
  let summary = "a POSIX extended regular expression, as text; --re2mlir reads it into combinators";
  let arguments = (ins SymbolNameAttr:$sym_name, StrAttr:$source);
  let assemblyFormat = "$sym_name $source attr-dict";
}

def Kursive_RejectedOp : Kursive_Op<"rejected", [Symbol]> {
  let summary = "a pattern --re2mlir did not take, and why: \"invalid\" or \"space\" (Kursive.h's Error)";
  let arguments = (ins SymbolNameAttr:$sym_name, StrAttr:$source, StrAttr:$error);
  let assemblyFormat = "$sym_name $source $error attr-dict";
}

def Kursive_RegexOp : Kursive_Op<"regex", [Symbol, SingleBlock]> {
  let summary = "one regular expression: its combinators, the step `kursive.yield` names, and its group count";
  let arguments = (ins SymbolNameAttr:$sym_name, I32Attr:$groups);
  let regions = (region SizedRegion<1>:$body);
  let assemblyFormat = "$sym_name `groups` $groups attr-dict-with-keyword $body";
}

def Kursive_YieldOp : Kursive_Op<"yield", [Terminator, HasParent<"RegexOp">]> {
  let summary = "the top step of a regex";
  let arguments = (ins Kursive_Step:$step);
  let assemblyFormat = "$step attr-dict";
}

//===----------------------------------------------------------------------===//
// The combinators.  kursive.set and kursive.lit are each slots of the Program's set table, in the order they stand, so
// they are not Pure: two equal sets are two slots, as the compiler made them.
//===----------------------------------------------------------------------===//

def Kursive_SetOp : Kursive_Op<"set"> {
  let summary = "one byte that is in the set: four 64-bit words, byte c is bit c % 64 of word c / 64 (Char.s, peekIs)";
  let arguments = (ins ConfinedAttr<DenseI64ArrayAttr, [DenseArrayCount<4>]>:$words);
  let results = (outs Kursive_Step:$step);
  let assemblyFormat = "$words attr-dict";
}

def Kursive_LitOp : Kursive_Op<"lit"> {
  let summary = "these bytes, in order (std.lit); one set slot per byte";
  let arguments = (ins StrAttr:$bytes);
  let results = (outs Kursive_Step:$step);
  let assemblyFormat = "$bytes attr-dict";
}

def Kursive_ThenOp : Kursive_Op<"then", [Pure]> {
  let summary = "each step in turn (then)";
  let arguments = (ins Variadic<Kursive_Step>:$steps);
  let results = (outs Kursive_Step:$step);
  let assemblyFormat = "$steps attr-dict";
}

def Kursive_OrOp : Kursive_Op<"or", [Pure]> {
  let summary = "alternatives: ordered choice (or, choice), or with `longest` POSIX alternation (the longest wins)";
  let arguments = (ins Variadic<Kursive_Step>:$steps, UnitAttr:$longest);
  let results = (outs Kursive_Step:$step);
  let assemblyFormat = "(`longest` $longest^)? $steps attr-dict";
}

def Kursive_RepeatOp : Kursive_Op<"repeat", [Pure]> {
  let summary = "the step, greedily, min to max times; max -1 is no bound (repeat(min), many, opt = [0, 1], maybe)";
  let arguments = (ins Kursive_Step:$body, I32Attr:$min, I32Attr:$max);
  let results = (outs Kursive_Step:$step);
  let assemblyFormat = "$body `[` $min `,` $max `]` attr-dict";
}

def Kursive_GroupOp : Kursive_Op<"group", [Pure]> {
  let summary = "a capture: the span the step took, as group `index` (a named parser's (name, start, end))";
  let arguments = (ins Kursive_Step:$body, I32Attr:$index);
  let results = (outs Kursive_Step:$step);
  let assemblyFormat = "$index $body attr-dict";
}

def Kursive_BolOp : Kursive_Op<"bol", [Pure]> {
  let summary = "the cursor at the start";
  let results = (outs Kursive_Step:$step);
  let assemblyFormat = "attr-dict";
}

def Kursive_EolOp : Kursive_Op<"eol", [Pure]> {
  let summary = "the cursor at the end";
  let results = (outs Kursive_Step:$step);
  let assemblyFormat = "attr-dict";
}

def Kursive_EmptyOp : Kursive_Op<"empty", [Pure]> {
  let summary = "nothing: always succeeds, moves nothing";
  let results = (outs Kursive_Step:$step);
  let assemblyFormat = "attr-dict";
}

#endif // KURSIVE_TD
