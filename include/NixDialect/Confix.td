//===- Confix.td - TrikeShed's Confix scanner, as a dialect over LLVM IR -------------*- tablegen -*-===//
//
// TrikeShed's parse/confix (src/commonMain/kotlin/borg/trikeshed/parse/confix/Confix.kt) scans a text once into a flat index: Syntax.scan0
// for JSON, Syntax.scanCbor0 for CBOR, Syntax.scanYaml0 for YAML, then Syntax.buildTree gives every span its depth and its children.  This dialect is that scan.  The
// scan itself is LLVM IR (lib/Confix/confix.ll) taken from the IR Kotlin/Native makes of those functions, and reads a CharSeries
// (include/Composite/CharSeries.h) and nothing else: no libc, no allocation, no recursion, no strings.
//
// It scans as Kotlin does, without checking: a stray `]` closes nothing, `-+-` is a number, every JSON number is a Double, a CBOR break
// that no indefinite item is waiting for is a Nothing.  Where Kotlin throws, the scan stops with a fault (below); where Kotlin would never
// come back (a length that sends the position back), it stops with Backward.
//
// The Flat record, which the caller owns and fills before the scan (the C layout of the struct).  The text is at most 2^31 - 1 bytes, as a
// Kotlin Int is.  `room` is a count of rows; a text of n bytes has at most n rows, so room = n cannot fail with Room:
//
//   total  u32   out  the rows found
//   fault  u32   out  why the scan stopped (FaultKind), 0 for none
//   at     u32   out  the offset it stopped at; for Bounds the row
//   room   u32   in   how many rows the arrays below hold
//   span   ptr   out  [room] of { open u32, close u32 }   the first and the last byte of each element (a string's quotes included)
//   tag    ptr   out  [room] of u8                        TagKind of each element
//   depth  ptr   out  [room] of u32                       how many elements enclose it
//   start  ptr   out  [room + 1] of u32                   childOf(k) is kid[start[k] .. start[k + 1])
//   kid    ptr   out  [room] of u32                       the rows of each element's direct children, in order
//   work   ptr   --   [3 * room] of u32                   scratch
//
// YAML differs in two ways.  Its scan makes the rows as it parses and sorts them (buildTree's sort, which Kotlin does on every syntax and which
// JSON and CBOR need not do), and it keeps the lines of the text and the open nodes in `work`:
//   work   [max(9 * (n + 1), 3 * room)] of u32.
// And no room that follows from n is always enough: Kotlin's parser reads a line again for every blank line before it, so a text of 164 bytes (20
// blank lines, then thirty nested `- `) has 3233 rows.  The caller picks room, and scans again with more on the fault Room.
// A YAML text that begins (after white space) with `{` or `[` is scanned as JSON, as Kotlin does, with the sizes of JSON.
//
// The rows are in the order the elements open.  An object's children are its keys and its values, alternating.  After a fault only total,
// fault and at are meant to be read, except after Bounds, which comes after the whole tree is made.
//
// Oracle: TrikeShed itself.  test/mlir/inputs/confix-golden.ll holds what the real Syntax.scan0, Syntax.scanCbor0 and Syntax.scanYaml0 gave for
// the texts it lists (and those that Kotlin never answers, whose fault Backward is this port's), and test/mlir/confix.mlir runs the scanner on them.
//
//===----------------------------------------------------------------------===//

#ifndef CONFIX_TD
#define CONFIX_TD

include "mlir/IR/OpBase.td"
include "mlir/IR/EnumAttr.td"
include "mlir/Interfaces/SideEffectInterfaces.td"
include "mlir/Dialect/LLVMIR/LLVMOpBase.td"

def Confix_Dialect : Dialect {
  let name = "confix";
  let cppNamespace = "::mlir::confix";
  let summary = "TrikeShed's Confix scanner";
  let dependentDialects = ["::mlir::LLVM::LLVMDialect"];
}

// ---- the syntaxes, the kinds of element, and the faults.  The numbers are those of the IR and of include/Composite/Confix.h (Tag).

def Confix_Json : I32EnumAttrCase<"Json", 0, "json">;
def Confix_Cbor : I32EnumAttrCase<"Cbor", 1, "cbor">;
def Confix_Yaml : I32EnumAttrCase<"Yaml", 2, "yaml">;
def Confix_SyntaxKind : I32EnumAttr<"SyntaxKind", "the syntax a text is scanned as", [Confix_Json, Confix_Cbor, Confix_Yaml]> {
  let cppNamespace = "::mlir::confix";
}

def Confix_Nothing : I32EnumAttrCase<"Nothing", 0, "nothing">;
def Confix_Boolean : I32EnumAttrCase<"Boolean", 1, "boolean">;
def Confix_Long    : I32EnumAttrCase<"Long", 2, "long">;
def Confix_Double  : I32EnumAttrCase<"Double", 3, "double">;
def Confix_String  : I32EnumAttrCase<"String", 4, "string">;
def Confix_Object  : I32EnumAttrCase<"Object", 5, "object">;
def Confix_Array   : I32EnumAttrCase<"Array", 6, "array">;
def Confix_Bytes   : I32EnumAttrCase<"Bytes", 7, "bytes">;
def Confix_TagKind : I32EnumAttr<"TagKind", "what an element is (IOMemento)",
    [Confix_Nothing, Confix_Boolean, Confix_Long, Confix_Double, Confix_String, Confix_Object, Confix_Array, Confix_Bytes]> {
  let cppNamespace = "::mlir::confix";
}

def Confix_NoFault   : I32EnumAttrCase<"None", 0, "none">;
def Confix_Truncated : I32EnumAttrCase<"Truncated", 1, "truncated">;   // a read past the end of the text (Kotlin: an index out of bounds)
def Confix_Reserved  : I32EnumAttrCase<"Reserved", 2, "reserved">;     // CBOR additional information 28 to 30 (Kotlin: error("cbor ai"))
def Confix_Bounds    : I32EnumAttrCase<"Bounds", 3, "bounds">;         // a span past the text (Kotlin: Syntax.indexed's require)
def Confix_Backward  : I32EnumAttrCase<"Backward", 4, "backward">;     // a length that sends the position back to or before the item
def Confix_Room      : I32EnumAttrCase<"Room", 5, "room">;             // more rows than the Flat record has room for
def Confix_FaultKind : I32EnumAttr<"FaultKind", "why a scan stopped",
    [Confix_NoFault, Confix_Truncated, Confix_Reserved, Confix_Bounds, Confix_Backward, Confix_Room]> {
  let cppNamespace = "::mlir::confix";
}

class Confix_Op<string mnemonic, list<Trait> traits = []> : Op<Confix_Dialect, mnemonic, traits>;

def Confix_ScanOp : Confix_Op<"scan"> {
  let summary = "scan a text into a Flat record";
  let description = [{
    `src` points to the CharSeries to scan: its size and its data, from offset 0 (the cursor, pos, limit and mark, is not read).  `flat`
    points to the Flat record described at the head of this file.  The results are the fault (0 for none) and where it was.

    Laws:
      - same bytes, same rows;
      - a JSON text never faults but with Room: Kotlin's scan0 does not check;
      - the rows are in the order of their `open`, and a row's children are the rows it directly encloses;
      - for every row k, the rows of kid[start[k] ..< start[k + 1]] have depth[k] + 1 in depth.
  }];
  let arguments = (ins Confix_SyntaxKind:$syntax, Arg<LLVM_AnyPointer, "", [MemRead]>:$src, Arg<LLVM_AnyPointer, "", [MemWrite]>:$flat);
  let results = (outs I32:$fault, I32:$at);
  let assemblyFormat = "$syntax $src `into` $flat attr-dict `:` type($src) `,` type($flat)";
}

def Confix_SizeOp : Confix_Op<"size"> {
  let summary = "how many rows a scan found";
  let arguments = (ins Arg<LLVM_AnyPointer, "", [MemRead]>:$flat);
  let results = (outs I32:$total);
  let assemblyFormat = "$flat attr-dict `:` type($flat)";
}

def Confix_RowOp : Confix_Op<"row"> {
  let summary = "the columns of row k of a scan";
  let description = [{
    `open` and `close` are the offsets of the first and the last byte, `tag` a TagKind, `depth` how many elements enclose the row, and
    `first` and `count` say where its children are: kid[first ..< first + count].  k must be below `total`.
  }];
  let arguments = (ins Arg<LLVM_AnyPointer, "", [MemRead]>:$flat, I32:$k);
  let results = (outs I32:$open, I32:$close, I32:$tag, I32:$depth, I32:$first, I32:$count);
  let assemblyFormat = "$flat `[` $k `]` attr-dict `:` type($flat)";
}

def Confix_KidOp : Confix_Op<"kid"> {
  let summary = "the row at a place of the kid array";
  let arguments = (ins Arg<LLVM_AnyPointer, "", [MemRead]>:$flat, I32:$at);
  let results = (outs I32:$row);
  let assemblyFormat = "$flat `[` $at `]` attr-dict `:` type($flat)";
}

#endif // CONFIX_TD
