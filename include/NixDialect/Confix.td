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

// ---- the syntaxes, the kinds of element, and the faults.  The numbers are those of the IR and of the rows confix.checked writes.

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

// ---- the Nix delimiter scan: the frontend's bands (Nix/Confix.h), the same index-first reading of a source.
//
// The scan is lowered/nixfrontend/ConfixScan.mlir, lowered at build time (lib/CMakeLists.txt) and linked into NixFrontend:
// the lexer's state machine without tokens, the character classes as tables, the longest-match
// rules called back from Nix/LexRules.h (shared with the lexer).  The record, which the caller owns and fills (all fields
// 8 bytes, in this order):
//
//   src     ptr   in   the source's bytes
//   n       i64   in   its size (below 2^32 - 1: the spans are 32-bit)
//   start   i64   in   where the scan begins (0 for a whole source)
//   rooted  i64   in   1 when the scan ends where its first band closes (a scan from Bands::need)
//   span    ptr   out  [rowCap] of u64: open << 32 | close, the closing delimiter's offset (0 until the band closes)
//   kind    ptr   out  [rowCap] of u8: the BandKind, the character that opens the band
//   stmts   ptr   out  [rowCap] of u64: first << 32 | count into ends, the band's qualified semicolons and commas
//   ends    ptr   out  [endCap] of u32: the statement ends, a band's together and in order
//   rows    i64   in/out  the bands already met / after the scan
//   nends   i64   in/out  the ends already met / after
//   rowCap  i64   in   the room of span, kind and stmts
//   endCap  i64   in   the room of ends
//
// The status is 0 when the source balances, 1 when it does not (a string or comment that does not end, a closer that
// matches nothing, a path ending in a slash: the bands are then not to be used), 2 when the room ran out: the caller
// doubles the arrays and scans again, as the caller of confix.scan does on YAML's Room.

def Confix_BandsOp : Confix_Op<"bands"> {
  let summary = "scan a Nix source's delimiters into a band record";
  let arguments = (ins Arg<LLVM_AnyPointer, "", [MemWrite]>:$rec);
  let results = (outs I32:$status);
  let assemblyFormat = "$rec attr-dict `:` type($rec)";
}

// ---- builtins.fromJSON's scan: a JSON text checked as that reader checks it, into the rows of its index.
//
// The scan confix.scan makes is Kotlin's, which does not check.  This one is the reader of builtins.fromJSON (the C++
// port of Confix it replaces was include/Composite/Confix.h): its faults are nlohmann's, at the offsets that reader had
// reached, and a number without a fraction or an exponent that fits 64 bits is a Long.  Its body is
// lowered/nixeval/JsonRead.mlir (confix_scan_checked, linked into NixEval with the reification that reads the rows).
// The record, which the caller owns (all fields 8 bytes, in this order):
//
//   src     ptr   in   the text's bytes
//   n       i64   in   its size (below 2^32 - 1: the offsets are 32-bit)
//   at      i64   out  where the reading had got to when it stopped (the column of nlohmann's message is at + 1); for
//                      Unsigned and Nul where the number or the string opens
//   end     i64   out  for Unsigned and Nul, one past it; in: nonzero for the store's reading of __json
//                      (lowered/nixstore/StructuredAttrsOps.mlir), where an Unsigned is a Long row and a Nul a String row,
//                      as nlohmann reads them, not faults
//
// The rows are not the record's: they are a lane of the caller's, `!trikeshed.lane<i32, i32, i8, i32>` (TrikeShed.td: a
// MutableSeries in LaneTrie's shape), which the scan fills by trikeshed.append, in the order the elements open:
//
//   open    i32   the first byte of the element (a string's quote included)
//   close   i32   its last byte; a container's is 0 until its closer is read, where trikeshed.anchor mints it
//   tag     i8    TagKind (Nothing, Boolean, Long, Double, String, Object, Array)
//   up      i32   the row of the container the element is in, -1 for the root: the open containers are these links, not
//                 a stack, and a row's direct children (an object's keys and values alternating) are the rows whose `up`
//                 it is, in order: trikeshed.adjacency of `up` over the drained rows gives each row its (first, count)
//
// So nothing is sized ahead and nothing is asked of the caller while the scan runs.  The fault, 0 for none: 1 the text
// ended where a value was expected, 2 an invalid
// literal, 3 a key expected, 4 ':' expected, 5 '}' expected, 6 ']' expected, 7 trailing content, 8 a string without its
// closing quote, 9 a control character in a string, 10 a backslash at the end, 11 \u without four hex digits, 12 a high
// surrogate not followed by \u, 13 a backslash before a character that is not an escape, 14 Unsigned (an integer from
// 2^63 to 2^64 - 1), 15 Nul (a string with \u0000).  No recursion: a document nested as deep as it is long is scanned.

def Confix_CheckedOp : Confix_Op<"checked"> {
  let summary = "scan a JSON text, checking it as builtins.fromJSON does, into the rows of its index";
  let arguments = (ins Arg<LLVM_AnyPointer, "", [MemWrite]>:$rec, AnyType:$rows);
  let results = (outs I32:$fault);
  let assemblyFormat = "$rec `,` $rows attr-dict `:` type($rec) `,` type($rows)";
}

// ---- the index as TrikeShed's series and cursor (PRELOAD-DIALECTS step 5): ConfixIndex's facets, lowered below TrikeShed.
//
// The ops above read a Flat record through a pointer.  These two are the same index as Kotlin hands it out
// (ConfixIndex = FacetedRow<ConfixIndexK>, parse/confix/ConfixIndexK.kt), in the types of include/Composite/TrikeShed.td:
// the rows are a Cursor, a span a Twin, a row's children a TwinPacked (first, count) into a Series of rows.  They are lowered
// by trikeshed-lower-cursors, through Composite/CursorLowering.h's CursorLoweringInterface, in the same conversion as the
// TrikeShed ops that read them; the scan itself is still confix.ll's.

def Confix_IndexOp : Confix_Op<"index", [Pure]> {
  let summary = "scan a text into its index: TrikeShed's cursor of rows and series of children";
  let description = [{
    Syntax.scanIndex (Confix.kt) for JSON and CBOR.  `text` is a `!trikeshed.series<i8>`.  `rows` is a cursor of schema
    "ConfixIndex", one row per element in the order the elements open, with the columns of confix.checked's rows
    (span, tag, kids) and the facets of ConfixIndexK:

      0 span  !trikeshed.twin<i32>        (open, close): the first and the last byte, a string's quotes included  (Spans)
      1 tag   i8                           the TagKind (IOMemento)                                                (Tags)
      2 kids  !trikeshed.twinpacked<i32>   (first, count) into `kids`: the rows of its direct children     (DirectChildren)

    `kids` is the series of those rows; an object's children are its keys and its values, alternating.  `fault` and `at`
    are confix.scan's; after a fault, `rows` and `kids` are empty (where Kotlin throws).  YAML is not taken: its rows can
    outgrow the room a text of n bytes gives, and it needs the retry on Room that a caller of confix.scan makes.

    Laws (those of confix.scan): same bytes, same rows; a JSON text never faults; the rows are in the order of their open;
    the children of row k are kids[first(k) ..< first(k) + count(k)], the rows it directly encloses.
  }];
  let arguments = (ins Confix_SyntaxKind:$syntax, AnyType:$text);
  let results = (outs AnyType:$rows, AnyType:$kids, I32:$fault, I32:$at);
  let assemblyFormat = "$syntax $text attr-dict `:` type($text) `->` type($rows) `,` type($kids)";
  let hasVerifier = 1;
}

def Confix_ColumnsOp : Confix_Op<"columns", [Pure]> {
  let summary = "the Columns facet: the members of a series of objects, by name";
  let description = [{
    ConfixIndexK.Columns (parse/confix/ConfixColumns.kt) over the objects whose rows `objects` lists, then cursorSelect of
    the columns `names`: row r, column c of `table` is the row of the value of the member named names[c] of the element at
    row objects[r], or -1 when that element is not an object or has no such member.  As in Kotlin's table of member
    positions, a name that a later member repeats is that later member's, and only the table is made: a cell is read
    through the index (its span, its tag) when it is needed.  Kotlin's facet takes a root array's elements; `objects` is
    any series of rows: an array's children (a slice of `kids`), or one object.

    A key is matched by its bytes between its quotes, as written: a key spelled with an escape (`"\u0070ath"`) is not the
    name it decodes to, where Kotlin decodes the key first.  Only JSON is taken.
  }];
  let arguments = (ins Confix_SyntaxKind:$syntax, AnyType:$rows, AnyType:$kids, AnyType:$text, AnyType:$objects,
                       StrArrayAttr:$names);
  let results = (outs AnyType:$table);
  let assemblyFormat = [{
    $syntax $rows `,` $kids `,` $text `,` $objects $names attr-dict `:` type($rows) `,` type($kids) `,` type($text) `,`
    type($objects) `->` type($table)
  }];
  let hasVerifier = 1;
}

def Confix_UnescapeOp : Confix_Op<"unescape", [Pure]> {
  let summary = "a string's value: the bytes between its quotes with their escapes read";
  let description = [{
    KnownSchema.decodeEscaped (parse/confix/KnownSchema.kt) over the bytes between a JSON string's quotes, giving bytes:
    each of \" \\ \/ \b \f \n \r \t is the one byte it names, and \uXXXX its code point in UTF-8, a high and a low
    surrogate in a row one code point (4 bytes).  A lone surrogate is U+FFFD: Kotlin's String keeps the lone half, which
    UTF-8 cannot hold, and Kotlin's encodeToByteArray writes U+FFFD for it.  Every other byte is itself.  Kotlin takes
    the text to be valid and reads any other letter after a backslash as \u; here a backslash that begins none of
    JSON's escapes (an unknown letter, \u without four hex digits, a backslash at the end) is kept as written, and
    what follows it is read as text.  Only JSON is taken.
    Laws: the value is never longer than the text; a text without a backslash is its own value; the value of a text
    escaped as JSON escapes it is that text.
  }];
  let arguments = (ins Confix_SyntaxKind:$syntax, AnyType:$text);
  let results = (outs AnyType:$value);
  let assemblyFormat = "$syntax $text attr-dict `:` type($text) `->` type($value)";
  let hasVerifier = 1;
}

#endif // CONFIX_TD
