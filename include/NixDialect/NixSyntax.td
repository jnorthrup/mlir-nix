//===- NixSyntax.td - The concentric layers of a Nix source, as a dialect -*- tablegen -*-===//
//
// The front end is to build no tree (docs/FABRIC.md, rung 10).  What it can know of a source before it parses
// it is a set of concentric layers, each found by a scan no dearer than the lexer, each a view by position over
// offsets of the source.  This file declares those layers in MLIR's own terms, regions and blocks, so that the
// layout has one written definition.  The kinds of tokens and bands are generated from it
// (NixSyntaxEnums.h.inc) for the lexer and the scan, which no longer spell them out in C++.
//
// The ops are the documentation of the layout, not what is allocated.  Cliff Click's lesson besides the sea of
// nodes: do not allocate parse results, parse them into a fixed buffer.  The scan writes the same structure as
// rows of one buffer, reused from source to source, and the parser takes its view of the buffer by position.
//
//   layer 0  syn.band   the delimiters: { } [ ] ( ) "..." ''...'' ${ } let-in  built: Confix.cpp, mlnix-parse -b
//   layer 1  syn.semi   the qualified semicolons, the statements of a band    built: the same scan, mlnix-parse -b
//   layer 2  heads      the names a statement binds, read where it starts     to build: Parser.cpp
//   layer 3  values     the nix dialect, parsed in the scope the heads made   to build: Parser.cpp, MLIRGen.cpp
//
//===----------------------------------------------------------------------===//

#ifndef NIX_SYNTAX_TD
#define NIX_SYNTAX_TD

include "mlir/IR/OpBase.td"
include "mlir/IR/EnumAttr.td"
include "mlir/IR/Properties.td"

def Syn_Dialect : Dialect {
  let name = "syn";
  let cppNamespace = "::nixfe::syn";
  let summary = "the concentric layers of a Nix source: bands, statements, heads, values";
  let description = [{
    A source nests.  Each delimited part of it is a band, and a band is a region inside the region around it,
    so the bands of a source nest exactly as regions do.  A band of bindings (the braces of an attribute set,
    `let ... in`) is divided by its qualified semicolons into statements: each statement is a block of the
    band's region, and its semicolon, `syn.semi`, is the block's terminator.  A band of formals is divided the
    same way by its commas, `syn.comma`.  Any other band has one block.

    The layers are found outside in, each by a scan of the one before:

    0. The bands.  The lexer's state machine without tokens (Confix.cpp), checked against the lexer's own
       delimiters over every file of nixpkgs (`mlnix-parse -b`): about twice the lexer's speed.
    1. The statements.  The same scan keeps the semicolons that end statements, discarding the others;
       qualifying a semicolon costs no more than lexing it.  It runs where the parser asks: a band is scanned
       (`Bands::need`) when the names it binds are first read, from its opening delimiter to its closing one
       and no further, and a band already met is found by where it opens.  A run ahead over the whole source
       was tried (a thread from 64 KiB up, 745f861): 24.3% of the bytes the toplevel reads are inside a band
       whose heads are read, so three quarters of what it scanned nothing used.
    2. The heads.  Where a statement starts, the names it binds are read from its first tokens, and only
       those: `a.b.c = e;` binds `a`, `inherit x y;` and `inherit (e) x y;` bind `x` and `y`,
       `"${e}" = v;` binds nothing a scope can see.  So a `let`, a `rec` set or a formals list knows all its
       names before the parser reaches its first value, and no reference waits for a name to appear.
    3. The values.  Parsed straight into the nix dialect, in the scope the heads made.  A value is a span of
       its statement, so a value nothing demands can stay a span: `file j [begin, end)`.

    Nothing in this dialect is allocated: the scan writes bands and statements as rows of a fixed buffer
    reused from source to source, and the parser views a band's statements as the slice of that buffer
    between the band's opening and closing offsets.
  }];
}

//===----------------------------------------------------------------------===//
// Kinds, generated for the C++ (NixSyntaxEnums.h.inc)
//===----------------------------------------------------------------------===//

class Syn_TokCase<string sym, int val, string str> : I32EnumAttrCase<sym, val, str>;

// What the lexer emits.  The string of a case is how a syntax error names the token ("unexpected 'then'").
def Syn_Tok : I32EnumAttr<"Tok", "a token of the Nix lexer", [
    Syn_TokCase<"T_EOF", 0, "end of file">,
    Syn_TokCase<"T_ID", 1, "identifier">,
    Syn_TokCase<"T_INT", 2, "integer">,
    Syn_TokCase<"T_FLOAT", 3, "floating-point literal">,
    Syn_TokCase<"T_STR", 4, "string">,
    Syn_TokCase<"T_IND_STR", 5, "string">,
    Syn_TokCase<"T_PATH", 6, "path">,
    Syn_TokCase<"T_HPATH", 7, "'~/…' path">,
    Syn_TokCase<"T_SPATH", 8, "'<…>' path">,
    Syn_TokCase<"T_URI", 9, "URI">,
    Syn_TokCase<"T_PATH_END", 10, "end of path">,
    Syn_TokCase<"T_DOLLAR_CURLY", 11, "'${'">,
    Syn_TokCase<"T_IND_STRING_OPEN", 12, "start of an indented string">,
    Syn_TokCase<"T_IND_STRING_CLOSE", 13, "end of an indented string">,
    Syn_TokCase<"T_IF", 14, "'if'">,
    Syn_TokCase<"T_THEN", 15, "'then'">,
    Syn_TokCase<"T_ELSE", 16, "'else'">,
    Syn_TokCase<"T_ASSERT", 17, "'assert'">,
    Syn_TokCase<"T_WITH", 18, "'with'">,
    Syn_TokCase<"T_LET", 19, "'let'">,
    Syn_TokCase<"T_IN", 20, "'in'">,
    Syn_TokCase<"T_REC", 21, "'rec'">,
    Syn_TokCase<"T_INHERIT", 22, "'inherit'">,
    Syn_TokCase<"T_OR_KW", 23, "'or'">,
    Syn_TokCase<"T_ELLIPSIS", 24, "'...'">,
    Syn_TokCase<"T_EQ", 25, "'=='">,
    Syn_TokCase<"T_NEQ", 26, "'!='">,
    Syn_TokCase<"T_LEQ", 27, "'<='">,
    Syn_TokCase<"T_GEQ", 28, "'>='">,
    Syn_TokCase<"T_AND", 29, "'&&'">,
    Syn_TokCase<"T_OR", 30, "'||'">,
    Syn_TokCase<"T_IMPL", 31, "'->'">,
    Syn_TokCase<"T_UPDATE", 32, "'//'">,
    Syn_TokCase<"T_CONCAT", 33, "'++'">,
    Syn_TokCase<"T_PIPE_FROM", 34, "'<|'">,
    Syn_TokCase<"T_PIPE_INTO", 35, "'|>'">,
    Syn_TokCase<"T_CHAR", 36, "a character">  // one character, in Token::ch; named by the character itself
  ]> {
  let cppNamespace = "::nixfe";
  let underlyingType = "uint8_t";
  let genSpecializedAttr = 0;
}

// The keywords: the text of each is its string, and its value is its token's, so the identifier rule's tie
// with a keyword (the earlier rule wins, a longer identifier wins: `iffy`) is one lookup of the identifier.
def Syn_Keyword : I32EnumAttr<"Keyword", "the text of a keyword", [
    I32EnumAttrCase<"If", 14, "if">,
    I32EnumAttrCase<"Then", 15, "then">,
    I32EnumAttrCase<"Else", 16, "else">,
    I32EnumAttrCase<"Assert", 17, "assert">,
    I32EnumAttrCase<"With", 18, "with">,
    I32EnumAttrCase<"Let", 19, "let">,
    I32EnumAttrCase<"In", 20, "in">,
    I32EnumAttrCase<"Rec", 21, "rec">,
    I32EnumAttrCase<"Inherit", 22, "inherit">,
    I32EnumAttrCase<"Or", 23, "or">
  ]> {
  let cppNamespace = "::nixfe";
  let underlyingType = "uint8_t";
  let genSpecializedAttr = 0;
}

// What opens a band: its value is the opening character, `$` for an interpolation and `'` for an indented
// string.  A band of kind `let` opens at the keyword and closes at its `in`.
def Syn_BandKind : I32EnumAttr<"BandKind", "the delimiter that opens a band", [
    I32EnumAttrCase<"K_BRACE", 123, "brace">,
    I32EnumAttrCase<"K_BRACKET", 91, "bracket">,
    I32EnumAttrCase<"K_PAREN", 40, "paren">,
    I32EnumAttrCase<"K_STRING", 34, "string">,
    I32EnumAttrCase<"K_IND_STRING", 39, "ind_string">,
    I32EnumAttrCase<"K_INTERP", 36, "interp">,
    I32EnumAttrCase<"K_LET", 108, "let">
  ]> {
  let cppNamespace = "::nixfe::confix";
  let underlyingType = "uint8_t";
  let genSpecializedAttr = 0;
}

//===----------------------------------------------------------------------===//
// The layout: regions and blocks
//===----------------------------------------------------------------------===//

class Syn_Op<string mnemonic, list<Trait> traits = []> : Op<Syn_Dialect, mnemonic, traits>;

def Syn_SourceOp : Syn_Op<"source", [NoTerminator, SingleBlock]> {
  let summary = "one input, whose bands are the regions nested in this one";
  let arguments = (ins I32Prop:$size);
  let regions = (region SizedRegion<1>:$bands);
  let description = [{
    The text itself is not here: an op refers to it by offsets, which are 32-bit (a source of 4 GiB or more
    is refused).  The ops of the one block are the outermost bands, in the order they open.
  }];
}

def Syn_BandOp : Syn_Op<"band"> {
  let summary = "a delimited part of a source: a region inside the region around it";
  let arguments = (ins I32Prop:$kind, I32Prop:$open, I32Prop:$close);
  let regions = (region AnyRegion:$statements);
  let description = [{
    `kind` is a BandKind; `open` is the offset of the opening delimiter and `close` that of the closing one
    (a string's closing quote, an indented string's first closing quote, the `in` of a `let`).  The bands
    inside this one are ops of its blocks, in the order they open.

    A band of bindings, the braces of an attribute set or a `let ... in`, has one block for each of its
    statements, `attrpath = value;` or `inherit ...;`, each ended by the `syn.semi` that ends the statement.
    A band of formals, `{ a, b ? e, ... }`, has one block for each formal, ended by `syn.comma` except the
    last.  Every other band has a single block.  Which of these a pair of braces is, the parser decides as
    it does now, by looking past the first name (Parser.cpp, looksLikeFormals); the scan keeps both the
    semicolons and the commas of a brace band.
  }];
}

def Syn_SemiOp : Syn_Op<"semi", [Terminator]> {
  let summary = "a qualified semicolon: the end of one statement";
  let arguments = (ins I32Prop:$offset);
  let description = [{
    A semicolon is scanned only where the lexer would make it a token: never inside a string, an indented
    string or a comment.  It belongs to the innermost band open around it.  It is disqualified when a
    `with e;` or an `assert e;` of its own band takes it: each `with` and each `assert` raises its band's
    count of semicolons owed, and a semicolon met while the count is above zero pays one and ends nothing.
    `let` opens a band that its `in` closes, unless the next token is `{` (the old `let { ... }`, whose
    braces are the band), so the semicolons of a `let` inside a value never end the statement around it.
    Every other semicolon is qualified.  In a band of bindings it ends a statement; anywhere else it is a
    syntax error, which the parser reports in its own words when it reaches it.
  }];
}

def Syn_CommaOp : Syn_Op<"comma", [Terminator]> {
  let summary = "the end of one formal of a formals band";
  let arguments = (ins I32Prop:$offset);
  let description = [{
    Formals are the only syntax with commas, so every comma the scan meets at the level of a brace band
    belongs to that band, which is then a formals band; a comma anywhere else is a syntax error.
  }];
}

#endif // NIX_SYNTAX_TD
