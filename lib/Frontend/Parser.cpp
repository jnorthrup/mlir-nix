//===- Parser.cpp - Nix lexer and parser ----------------------------------===//
//
// The lexer is a faithful hand translation of upstream lexer.l: the same start
// conditions (DEFAULT, STRING, IND_STRING, INPATH, INPATH_SLASH) with the same
// state stack, and flex's longest-match / first-rule tie breaking for the
// DEFAULT state.  The lexer's state never depends on the parser, so a lexer can
// start again at any token of the default state (Lexer::reposition).
//
// The parser is recursive descent + precedence climbing implementing the same
// grammar, precedences and desugarings as upstream parser.y, and it builds no
// tree (see "The parser" below).
//
//===----------------------------------------------------------------------===//

#include "Composite/Views.h"
#include "Composite/Pack.h"
#include "Composite/Rows.h"
#include "Nix/Confix.h"
#include "Nix/LexRules.h"
#include "Nix/MLIRGen.h"
#include "Nix/Numbers.h"
#include "Nix/Pos.h"
#include "mlir/IR/Builders.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/StringMap.h"
#include "llvm/Support/xxhash.h"

#include <assert.h>
#include <errno.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

namespace nixfe {
using composite::α;

namespace {

using enum Tok; // the kinds of tokens are generated from NixDialect/NixSyntax.td (Confix.h includes them)

struct Token {
  Tok t;
  char ch = 0;
  bool hasIndent = false; // IND_STR from the main rule
  bool derived = false;   // the text is not a slice of the input: span.first() indexes the lexer's pool
  uint32_t offset = 0;    // where the lexeme starts in the input (segments are 32-bit)
  join::TwInt span;       // [start, end) of the lexeme in the input: a segment, never a copy
  union {                 // the value of an integer or a float token
    int64_t i = 0;
    double f;
  };
  Pos pos;
};

composite::Text tokName(const Token &t) {
  if (t.t != T_CHAR) return composite::Text(stringifyTok(t.t));
  if ((unsigned char)t.ch >= 0x80) return composite::Text("invalid token");
  return composite::cat("'", t.ch, "'");
}

using namespace lex; // the character classes and matchers shared with the Confix scan

/// The keyword with exactly this text, else T_ID.  The identifier rule matches every keyword's text, so a keyword is
/// an identifier of the same length (the earlier rule wins the tie) and loses to a longer identifier (`iffy`).
Tok keywordOf(std::string_view w) {
  if (w.size() < 2 || w.size() > 7) return T_ID;
  auto k = symbolizeKeyword(llvm::StringRef(w.data(), w.size())); // the generated enum API's optional, at its boundary
  return k ? Tok(uint8_t(*k)) : T_ID;
}

/// The record nixfe_lex_next reads and writes (lowered/nixfrontend/LexScan.mlir): the source and the lexer's state
/// (p, the state stack), then the token it produced.  Every field is 8 bytes, in this order.  dkind: 0 the span is a
/// slice of the input, 1 a fixed derived text (span = index<<32|1), 2 an unescape request (dFrom..dTo).
struct LexRec {
  const char *src;
  uint64_t n, p;
  void *lex;
  uint64_t pipeOps;
  uint8_t *stack;
  uint64_t sp, stackCap;
  uint64_t tok, ch, hasIndent, offset, span, value, posLine, posCol;
  uint64_t errCode, errOff, dFrom, dTo, dkind;
};
static_assert(sizeof(LexRec) == 168 && offsetof(LexRec, lex) == 24 && offsetof(LexRec, stack) == 40 &&
                  offsetof(LexRec, tok) == 64 && offsetof(LexRec, dkind) == 160,
              "the record is the dialect's layout");

extern "C" int32_t nixfe_lex_next(LexRec *rec);
extern "C" uint64_t nixfe_lex_unescape(const char *src, uint64_t n, uint64_t from, uint64_t to, char *out, uint64_t cap);
// The longest-match choice among the rules that can begin a default token (LexRules.h), shared with the Confix scan.
extern "C" uint64_t nixfe_confix_match(const char *src, uint64_t n, uint64_t i);

struct Lexer : public lex::Rules {
  Lexer(Origin *o, const ParseOptions &opts)
      : Rules(o->text->view()), origin(o), opts(opts) {
    if (src.size() >= UINT32_MAX) throw ParseError("input too large (segments are 32-bit)", Pos{1, 1}, origin);
  }

  /// The text of a token: a slice of the input, or an entry of the pool of derived texts.
  std::string_view text(const Token &t) const {
    if (t.derived) return t.span.second() ? kFixed[t.span.first()] : std::string_view(derived[t.span.first()]);
    return src.substr(t.span.first(), t.span.second() - t.span.first());
  }

  bool wantPos = true; // false: no token gets a position (the heads, which go back and forth)
  /// Lex again from `off`, a token's start in the default state, whose position is `at`.
  void reposition(size_t off, Pos at) {
    p = off;
    stack.clear();
    stack.append(uint8_t(S_INITIAL));
    if (wantPos && at.valid()) {
      line = at.line;
      lineStart = off - (at.col - 1);
      nextNl = newlineFrom(lineStart);
    }
  }
  /// Every state on the stack is the default one: what follows is not inside a string or a path.
  bool plain() const {
    for (uint32_t i = 0; i < stack.size(); i++)
      if (stack[i] != S_INITIAL && stack[i] != S_DEFAULT) return false;
    return true;
  }

  /// Produce the next token (T_EOF at end, repeatedly).  The state machine is LexScan.mlir's nixfe_lex_next; this
  /// bridge owns the Token, the derived-text pool and the state stack, and turns the record into the Token API.
  Token nextToken() {
    if (stack.empty()) {
      stack.reserve(32);
      stack.append(uint8_t(S_INITIAL));
    }
    for (;;) {
      LexRec rec;
      rec.src = src.data();
      rec.n = src.size();
      rec.p = p;
      rec.lex = this;
      rec.pipeOps = opts.pipeOperators ? 1 : 0;
      rec.stack = stack.base();
      rec.sp = stack.size();
      rec.stackCap = stack.cap;
      int32_t st = nixfe_lex_next(&rec);
      p = rec.p;
      stack.n = uint32_t(rec.sp);
      if (st == 3) { // the state stack ran out of room: double it and lex the same token again
        stack.reserve(size_t(stack.cap) * 2);
        continue;
      }
      if (st == 1) { // end of input
        Token t;
        t.t = T_EOF;
        t.pos = posAt(src.size());
        t.offset = uint32_t(src.size());
        return t;
      }
      if (st == 2) lexError(rec.errCode, rec.errOff);
      Token t;
      t.t = Tok(rec.tok);
      t.ch = char(rec.ch);
      t.hasIndent = rec.hasIndent != 0;
      t.offset = uint32_t(rec.offset);
      t.pos = Pos{uint32_t(rec.posLine), uint32_t(rec.posCol)};
      if (t.t == T_FLOAT) __builtin_memcpy(&t.f, &rec.value, 8);
      else if (t.t == T_INT) t.i = int64_t(rec.value);
      if (rec.dkind == 2) setDerived(t, unescapeInto(rec.dFrom, rec.dTo));
      else {
        t.derived = rec.dkind == 1;
        t.span = join::TwInt(uint32_t(rec.span >> 32), uint32_t(rec.span));
      }
      return t;
    }
  }

  /// Where an offset is: its line, and its column counted in bytes from the start of the line.  Offsets are asked for in
  /// order, so the line is found by going from newline to newline (one memchr a line, not a test of every byte), and a
  /// token on the line already reached costs one comparison.
  Pos posAt(size_t off) {
    if (!wantPos) return Pos{};
    if (off < lineStart) { // earlier than the last ask: start again
      line = 1;
      lineStart = 0;
      nextNl = newlineFrom(0);
    }
    while (nextNl < off) {
      line++;
      lineStart = nextNl + 1;
      nextNl = newlineFrom(lineStart);
    }
    return Pos{line, uint32_t(off - lineStart + 1)};
  }
  /// The offset of the first newline at or after `from`; the size of the input when there is none.
  size_t newlineFrom(size_t from) const {
    if (from >= src.size()) return src.size();
    const void *q = memchr(src.data() + from, '\n', src.size() - from);
    return q ? static_cast<size_t>(static_cast<const char *>(q) - src.data()) : src.size();
  }

  [[noreturn]] void error(std::string_view msg, size_t off) { throw ParseError(msg, posAt(off), origin); }

  enum State { S_INITIAL, S_DEFAULT, S_STRING, S_IND_STRING, S_INPATH, S_INPATH_SLASH };
  Origin *origin; // kept for the run (newOrigin)
  const ParseOptions &opts;
  /// Texts that are not slices of the input (unescaped strings, `''$`, ...), appended and never
  /// mutated.  Deque: entries do not move.  The four fixed ones are kFixed (a span of second() 1).
  composite::MutableSeries<composite::Text, composite::Chunked<composite::Text>> derived;
  static constexpr std::string_view kFixed[] = {"$", "''", "'", "~/"};
  void setDerived(Token &t, composite::Text s) {
    derived.append(composite::mv(s));
    t.derived = true;
    t.span = join::TwInt(uint32_t(derived.size() - 1), 0);
  }
  /// The state stack (S_INITIAL..S_INPATH_SLASH), grown by the bridge when the lowered machine reports room (status 3).
  composite::MutableSeries<uint8_t> stack;
  size_t p = 0;
  uint32_t line = 1;
  size_t lineStart = 0;          // the offset where `line` starts
  size_t nextNl = newlineFrom(0); // the first newline at or after lineStart

  /// Resolve a string piece's escapes into a derived text: the lowered nixfe_lex_unescape writes into the Text's own
  /// buffer (the output is never longer than the input), and the text is truncated to what it wrote.
  composite::Text unescapeInto(size_t from, size_t to) {
    composite::Text s;
    uint32_t len = uint32_t(to - from);
    s.resize(len);
    uint64_t w = nixfe_lex_unescape(src.data(), src.size(), from, to, s.begin(), len);
    s.truncate(uint32_t(w));
    return s;
  }
  /// The lex errors the lowered machine reports by code; the wording and the position stay here.
  [[noreturn]] void lexError(uint64_t code, size_t off) {
    switch (code) {
    case 1: error("path has a trailing slash", off);
    case 2: error("lexer error in indented string", off);
    case 3: error("input string contains NUL byte", off);
    case 4: error(composite::cat("invalid integer '", src.substr(off, p - off), "'"), off);
    case 5: error(composite::cat("invalid float '", src.substr(off, p - off), "'"), off);
    default:
      error("experimental Nix feature 'pipe-operators' is disabled; add '--extra-experimental-features "
            "pipe-operators' to enable it",
            off);
    }
  }
};

/// The position of an offset (Lexer::posAt), packed line<<32|col, called back per token by the lowered machine.
extern "C" uint64_t nixfe_lex_pos(void *lex, uint64_t off) {
  Pos p = static_cast<Lexer *>(lex)->posAt(off);
  return (uint64_t(p.line) << 32) | p.col;
}
/// The keyword with exactly this text, else T_ID (keywordOf), called back for an identifier.
extern "C" uint64_t nixfe_lex_keyword(const char *src, uint64_t n, uint64_t i, uint64_t len) {
  (void)n;
  return uint64_t(keywordOf(std::string_view(src + i, len)));
}
/// The integer lexeme as readUnsigned reads it: 0 ok (value written), 1 invalid (overflow or past INT64_MAX).
extern "C" uint64_t nixfe_lex_int(const char *src, uint64_t n, uint64_t i, uint64_t len, uint64_t *out) {
  (void)n;
  composite::text::Reading r = nixsys::readUnsigned(std::string_view(src + i, len));
  if (r.overflow || r.value > uint64_t(INT64_MAX)) return 1;
  *out = r.value;
  return 0;
}
/// The float lexeme as strtod reads it: 0 ok (bits written), 1 invalid (errno).
extern "C" uint64_t nixfe_lex_float(const char *src, uint64_t n, uint64_t i, uint64_t len, uint64_t *out) {
  (void)n;
  errno = 0;
  nixsys::CStr txt(std::string_view(src + i, len));
  double d = strtod(txt.c_str(), nullptr);
  if (errno) return 1;
  __builtin_memcpy(out, &d, 8);
  return 0;
}
//===----------------------------------------------------------------------===//
// The parser: upstream's grammar in one pass that builds no tree
//===----------------------------------------------------------------------===//
//
// A parse is one of three.  Gen lowers to the nix dialect as it goes, every name resolved where it is read.  Skip builds
// nothing and learns what each lambda reads from outside itself: a body that waits for its first call is skipped so, and
// parsed again from its first token when it is called.  Show prints what `nix-instantiate --parse` prints.  A `let`, a
// `rec` set and a formals list know their names before their first value: the scan's statements give them (layers 1
// and 2 of NixDialect/NixSyntax.td).  What a parse holds while it runs (sets being bound, scopes) is in storage reused
// from set to set; nothing of it outlives the parse but the ops.

namespace nd = mlir::nix;
using mlir::Value;

enum class Mode : uint8_t { Gen, Skip, Show };

/// The syntax a node was, where a construct looks at its operand's: a call takes more arguments (`(f a) b` is `f a b`), a
/// string is a static name (`${"s"}`), a `let` or `with` whose body is a variable shares its value, a set literal bound
/// to an attribute is still open to the bindings after it, a lambda bound to one takes its name.
enum Kind : uint8_t { K_EXPR, K_VAR, K_CALL, K_STR, K_SET, K_LAMBDA, K_SHARED };

/// A node is a value and what syntax made it, copied as it is passed up: no string, no vector.
struct Node {
  Value v;              // Gen: a set's and a string's are made when they are first used
  Name text;            // K_STR: the literal's text
  Pos pos;
  uint32_t set = 0;     // K_SET: the set
  uint32_t shownAt = 0; // Show: its text, a row of the parse's `texts`
  Kind k = K_EXPR;
};

/// The free names of a lambda being skimmed, each once: compared by hash, found by an index past 32.
struct Free {
  llvm::SmallVector<FreeName, 8> names;
  llvm::SmallVector<uint32_t, 8> hashes;
  llvm::DenseMap<llvm::StringRef, uint32_t> index;
};

/// A lexical scope: a run of rows of the parse's bindings (BindCol, TrikeShed.td), first j count, a view by position.
/// Its names map to values (Gen) or to nothing (Skip, where only their presence counts).
struct Scope {
  Scope *parent = nullptr;
  bool isWith = false;
  Value with;
  Free *free = nullptr; // Skip: the edge of a lambda: a name looked up through it is free in the lambda
  ::join::TwInt rows;   // its bindings
};

struct Comp {
  Name name; // the null name when the component is computed
  Node expr;
  bool computed() const { return name.isNull(); }
};
using Path = llvm::SmallVector<Comp, 4>;

enum DefKind : uint8_t { D_PLAIN, D_INHERITED, D_FROM };
struct Def {
  Name name;
  Pos pos;
  DefKind kind = D_PLAIN;
  uint32_t from = 0; // D_FROM: the source in Set::froms
  Node val;
};
struct Dyn {
  Node name, val;
  Pos pos;
};
/// An attribute set while it is bound: a literal, a set a path makes, the bindings of a `let`.
struct Set {
  composite::MutableSeries<Def> defs; // in the order written until the set is made, then ordered by name
  composite::MutableSeries<Dyn> dyns;
  composite::MutableSeries<Node> froms;     // the sources of `inherit (e) ...`
  composite::MutableSeries<uint32_t> index; // over a handful of defs: open addressing over positions in `defs`, plus one
  bool rec = false, ordered = true;
  Pos pos;
  Scope *scope = nullptr;  // rec or let: its names, bound before its values are parsed
  Scope *values = nullptr; // where its values are parsed (and the sources of `inherit (e)`)
  Scope *outer = nullptr;  // where `inherit x;` reads x
  Set *into = nullptr;     // a literal bound where a set already is: the set it merges into once it is read
};

struct Formal {
  Pos pos;
  Name name;
  Node def;
  bool hasDef = false;
};
struct Hdr {
  Name arg;
  bool formals = false, ellipsis = false;
  llvm::SmallVector<Formal, 8> fs; // ordered by name once read
};

// Parser.cpp's text algorithms are lowered/nixfe/TextParts.mlir (its header has each protocol); the parser keeps the
// grammar actions, the nodes and the throws.
extern "C" int64_t nixfe_ts_strparts(void *ctx);
extern "C" int64_t nixfe_ts_strip(const uint64_t *recs, uint64_t n, char *out, uint64_t cap, uint64_t *wins);
extern "C" int64_t nixfe_ts_path_kind(uint64_t home, const char *lit, uint64_t n);
extern "C" int64_t nixfe_ts_path_msg(int64_t kind, const char *lit, uint64_t n, char *into, uint64_t cap);
extern "C" int64_t nixfe_ts_path_text(int64_t kind, const char *home, uint64_t hn, const char *base, uint64_t bn,
                                      const char *lit, uint64_t n, char *into, uint64_t cap);
extern "C" int64_t nixfe_ts_partloop(void *ctx);

struct Parser {
  Parser(Mode m, Origin *o, const ParseOptions &po, confix::Bands *bands,
         mlir::ModuleOp module = {}, const GenOptions *go = nullptr)
      : mode(m), origin(o), opts(po), lx(origin, opts), bands(bands), module(module),
        b(module ? module.getContext() : nullptr), go(go) {}

  /// The whole source.
  Node top() {
    Node e = parseExpr();
    if (cur().t != T_EOF) unexpected("end of file");
    done();
    return e;
  }
  composite::Text show() {
    Node e = top();
    return composite::Text(txt(e));
  }

  nd::ExprOp genTop(llvm::StringRef sym) {
    b.setInsertionPointToEnd(module.getBody());
    auto op = nd::ExprOp::create(b, noLoc(), b.getStringAttr(sym),
                                 origin->path.empty() ? mlir::StringAttr() : b.getStringAttr(llvm::StringRef(origin->path)),
                                 b.getStringAttr(llvm::StringRef(origin->baseDir)));
    topBlock = new mlir::Block();
    op.getBody().push_back(topBlock);
    b.setInsertionPointToEnd(topBlock);
    Value result;
    eagerAt = cur().offset;
    if (go->scoped) { // scope: <expr>, with the scope's names bound lexically
      auto lam = nd::LambdaOp::create(b, noLoc(), nd::fnType(b.getContext()), mlir::ArrayAttr(), mlir::DenseBoolArrayAttr(), false,
                                      b.getStringAttr("scope"), mlir::StringAttr(), mlir::DenseI64ArrayAttr(),
                                      mlir::ValueRange{}, mlir::IntegerAttr(), 0);
      mlir::Block *lb = new mlir::Block();
      lam.getBody().push_back(lb);
      Value arg = lb->addArgument(valTy(), noLoc());
      b.setInsertionPointToEnd(lb);
      Scope s;
      for (auto &n : go->scopeNames) bindTo(s, Name::of(n), selectLiteral(Pos{}, arg, Name::persist(n)));
      sc = &s;
      Node e = top();
      nd::ReturnOp::create(b, noLoc(), val(e));
      nd::setPos(lam, uint64_t(at(e.pos)));
      sc = nullptr;
      result = lam.getResult();
    } else {
      Node e = top();
      result = val(e);
    }
    b.setInsertionPointToEnd(topBlock);
    nd::ReturnOp::create(b, noLoc(), result);
    return op;
  }

  /// The demand half of the schedule: the lexical scope of the lambda rebuilt from its captures, and its header and body
  /// parsed again from its first token, into its block, by the same path as when nothing waits.
  void mint(nd::LambdaOp lam, const FilePool &pool, uint32_t row) {
    minting = true;
    topBlock = &lam.getBody().front(); // anchored constants (builtins, true/false/null) head the body
    mlir::OperandRange caps = lam.getCaptures();
    // read out of the columns, by value: the pool grows while the body mints
    uint32_t at = pool.rows.col<PoolCol::At>()[row];
    Pos pos = pool.rows.col<PoolCol::AtPos>()[row];
    uint32_t withs = pool.rows.col<PoolCol::Withs>()[row];
    ::join::TwInt names = pool.rows.col<PoolCol::Names>()[row];
    Scope lex;
    for (uint32_t i = 0; i < names.second(); i++) bindTo(lex, Name::of(pool.nameCol[names.first() + i]), caps[withs + i]);
    // `with` never binds lexically and a lexical binding beats every `with`, so the flat map plus the with-chain
    // (outermost pushed first, so the walk meets the innermost first) is the same scope extensionally.
    composite::MutableSeries<Scope, composite::Chunked<Scope>> frames;
    sc = &lex;
    for (unsigned i = withs; i-- > 0;) {
      frames.emplace();
      Scope &f = frames.back();
      f.parent = sc;
      f.isWith = true;
      f.with = caps[i];
      sc = &f;
    }
    jump(at, pos);
    b.setInsertionPointToEnd(topBlock);
    Hdr h;
    Node body = lambdaBody(h, lam.getArgument());
    nd::ReturnOp::create(b, noLoc(), val(body));
    done();
  }

  Mode mode;
  Origin *origin; // kept for the run (newOrigin)
  const ParseOptions &opts;
  Lexer lx;
  composite::Own<Lexer> hl; // the heads': statement starts, read for the names they bind
  confix::Bands *bands; // written as the heads need it: a band is scanned when its names are first read
  mlir::ModuleOp module;
  mlir::OpBuilder b;
  const GenOptions *go;
  mlir::Block *topBlock = nullptr;
  llvm::StringMap<Value> builtinCache;
  Scope *sc = nullptr;                    // where the parse is
  composite::Own<ParseError> undefinedErr; // the first undefined variable: upstream reports it once the source parses
  uint32_t orphans = 0;                   // names a set was given ahead that nothing bound (a parse error must follow)
  bool minting = false;
  /// Where a lambda is lowered with its body even when bodies wait: the whole source, which its importer calls, and
  /// the body of such a lambda when that is a lambda too (`self: super: ...`).  Its body is parsed once, not skimmed
  /// at the import and parsed again at the call.
  uint32_t eagerAt = ~0u;
  composite::MutableSeries<Set, composite::Chunked<Set>> sets; // a Set never moves: sets are held by address while more are made
  composite::MutableSeries<uint32_t> freeSets;
  composite::MutableSeries<Scope, composite::Chunked<Scope>> recScopes; // a rec set's scope lives until the set is made
  /// Every binding of the parse: the scopes' rows, a fixed buffer that only grows while the parse runs.
  composite::Cursor<Name, uint32_t, Value> binds{BindCol{}};
  /// Show: the text of each node printed, a row each.
  composite::MutableSeries<composite::Text> texts; // a row is never written to once it is made: a window on its bytes (txt) holds
  /// stripIndentation: the piece being rewritten, one for all (the allocation is made once, not for each piece).
  composite::Text piece;
  /// The bindings band being parsed: the statement it is at, and that statement's static path.  A set literal that is a
  /// binding's whole value links to the band it is bound in (`up`): what the bindings after it add can land in it.
  struct Ctx {
    uint32_t band, stmt;
    llvm::SmallVector<Name, 4> path;
    Ctx *up;
    uint32_t open; // where the band opens: a band no head needed yet is scanned when a later one does (NixOS/nix#9020)
  };
  // The binding whose value is being parsed: a set literal that is all of the value can merge with what is bound there.
  uint32_t valueAt = ~0u;
  Set *mergeInto = nullptr;
  Ctx *valueCtx = nullptr;

  /// The lookahead: the next `count` tokens, in a ring.  The deepest look is peek(3) (looksLikeFormals), so four slots hold
  /// it; a slot is written only when it is filled, so a reference from cur() or peek() lives until four more tokens are taken.
  static constexpr size_t kLook = 4;
  Token ring[kLook];
  uint32_t head = 0, count = 0;
  bool sawEof = false;

  void fill(size_t n) {
    assert(n < kLook);
    while (count <= n) {
      Token &slot = ring[(head + count) % kLook];
      if (sawEof) slot = ring[(head + count + kLook - 1) % kLook]; // end of file repeats
      else {
        slot = lx.nextToken();
        if (slot.t == T_EOF) sawEof = true;
      }
      count++;
    }
  }
  /// Parse on from `off` (a token's start, in the default state) at `pos`.
  void jump(uint32_t off, Pos pos) {
    lx.reposition(off, pos);
    head = count = 0;
    sawEof = false;
  }
  /// The text of a token as a Name: a slice of the input (never freed) unless the text was derived from it.
  static Name nameOf(Lexer &l, const Token &t) { return t.derived ? Name::persist(l.text(t)) : Name::of(l.text(t)); }
  Name nameOf(const Token &t) { return nameOf(lx, t); }
  const Token &cur() { if (count == 0) fill(0); return ring[head]; }
  const Token &peek(size_t n = 1) { fill(n); return ring[(head + n) % kLook]; }
  static bool isChar(const Token &t, char c) { return t.t == T_CHAR && t.ch == c; }
  bool atChar(char c) { return isChar(cur(), c); }
  Token take() {
    if (count == 0) fill(0);
    Token t = ring[head];
    if (t.t != T_EOF) { head = (head + 1) % kLook; count--; }
    return t;
  }

  [[noreturn]] void unexpected(std::string_view expecting = {}) {
    composite::Text msg = composite::cat("syntax error, unexpected ", tokName(cur()));
    if (!expecting.empty()) msg.put(", expecting ").put(expecting);
    throw ParseError(msg, cur().pos, origin);
  }
  [[noreturn]] void error(std::string_view msg, Pos p) { throw ParseError(msg, p, origin); }
  void expectChar(char c, std::string_view expecting = {}) {
    if (!atChar(c)) {
      if (expecting.empty()) unexpected(composite::cat("'", c, "'"));
      unexpected(expecting);
    }
    take();
  }
  void expect(Tok t, std::string_view what) {
    if (cur().t != t) unexpected(what);
    take();
  }
  composite::Text fmtPos(Pos p) { return composite::cat(origin->name, ':', p.line, ':', p.col); }
  void done() {
    if (orphans) error("internal error: a set was given names ahead that no binding gave it", Pos{});
    if (undefinedErr) throw *undefinedErr;
  }

  //===--------------------------------------------------------------------===//
  // Ops (Gen)
  //===--------------------------------------------------------------------===//

  mlir::Type valTy() { return nd::ValueType::get(b.getContext()); }
  /// A list (PRELOAD.md: Series<!nix.value>).
  mlir::Type listTy() { return composite::SeriesType::get(b.getContext(), valTy()); }
  /// An attribute set: its rows in name order (Series2<symbol, value>).
  mlir::Type attrsTy() { return composite::Series2Type::get(b.getContext(), b.getIntegerType(32), valTy()); }
  mlir::Location noLoc() { return mlir::UnknownLoc::get(b.getContext()); }
  /// The position word of `p` (Nix/Pos.h): what an op carries in its `pos` property.
  int64_t at(Pos p) {
    if (!p.valid()) return 0;
    if (!origin->fileId) origin->fileId = FileTable::get().add(origin->name);
    return static_cast<int64_t>(PackedPos::pack(origin->fileId, p.line, p.col));
  }
  /// A few consumers report errors at the position of an *operand* (a `with` scope, a computed attribute name, a part of
  /// an interpolation): a literal operand gets its position back.
  Value positioned(Value v, Pos p) {
    if (mlir::Operation *d = v.getDefiningOp())
      if (mlir::isa<nd::StringOp, nd::IntOp, nd::FloatOp, nd::PathOp, nd::ListOp>(d) && nd::getPos(d) == 0)
        nd::setPos(d, static_cast<uint64_t>(at(p)));
    return v;
  }
  Value placeholder() {
    return mlir::UnrealizedConversionCastOp::create(b, noLoc(), mlir::TypeRange{valTy()}, mlir::ValueRange{}).getResult(0);
  }
  /// Replace the placeholders of a binding group by their final values.  A member that is an alias of another
  /// (`let a = b; b = a;`) gets an identity node, so that a cycle is a real SSA cycle.
  llvm::SmallVector<Value> finalizeGroup(llvm::ArrayRef<Value> phs, llvm::ArrayRef<Value> values, llvm::ArrayRef<Pos> poses,
                                         llvm::ArrayRef<llvm::SmallVectorImpl<Value> *> remap = {}) {
    llvm::SmallVector<Value> finals;
    for (auto [v, p] : composite::joins(values, poses))
      finals.push_back(v.getDefiningOp<mlir::UnrealizedConversionCastOp>() ? identity(v, p) : v);
    for (auto *vec : remap) // other lists that may hold placeholders, before the placeholders are erased
      for (Value &v : *vec)
        for (size_t i = 0; i < phs.size(); i++)
          if (v == phs[i]) v = finals[i];
    for (auto [ph, fin] : composite::joins(phs, finals)) {
      ph.replaceAllUsesWith(fin);
      ph.getDefiningOp()->erase();
    }
    return finals;
  }
  Value identity(Value v, Pos p) { return nd::ApplyOp::create(b, noLoc(), valTy(), v, mlir::ValueRange{}, at(p)); }
  Value builtin(llvm::StringRef name) {
    auto it = builtinCache.find(name);
    if (it != builtinCache.end()) return it->second;
    mlir::OpBuilder::InsertionGuard g(b);
    b.setInsertionPointToStart(topBlock);
    Value v = nd::BuiltinOp::create(b, noLoc(), valTy(), Name::persist(name));
    return builtinCache[name] = v;
  }
  /// A reference to the base environment.  `true`, `false` and `null` are constants (ConstantLike: they fold, and can be
  /// operands of folded primops); everything else is a `nix.builtin`.
  Value baseRef(llvm::StringRef name) {
    if (name != "true" && name != "false" && name != "null") return builtin(name);
    auto it = builtinCache.find(name);
    if (it != builtinCache.end()) return it->second;
    mlir::OpBuilder::InsertionGuard g(b);
    b.setInsertionPointToStart(topBlock);
    Value v = name == "null" ? nd::NullOp::create(b, noLoc(), valTy()).getResult()
                             : nd::BoolOp::create(b, noLoc(), valTy(), b.getBoolAttr(name == "true")).getResult();
    return builtinCache[name] = v;
  }
  Value str(Name n) { return nd::StringOp::create(b, noLoc(), nd::stringType(b.getContext()), n); }
  /// `base.key` with a literal key.
  Value selectLiteral(Pos p, Value base, Name key, Value def = Value()) {
    Name path[1] = {key};
    return nd::SelectOp::create(b, noLoc(), valTy(), base, mlir::ValueRange{}, def, path, at(p));
  }
  /// Where `name` resolves without a `with`: a lexical binding, else the base environment.  Null when only a `with`, or
  /// nothing, can supply it.
  Value resolveStatic(const Name &n) {
    uint32_t h = hashOf(n);
    for (Scope *c = sc; c; c = c->parent)
      if (Value *v = c->isWith ? nullptr : lookup(*c, n, h)) return *v;
    if (go->isBaseName && go->isBaseName(go->baseNames, n.str())) return baseRef(n.str());
    return Value();
  }
  /// The cell of `n` (hash h) in scope s, or null.
  Value *lookup(Scope &s, const Name &n, uint32_t h) {
    const auto &hs = binds.col<BindCol::Hash>();
    const auto &ks = binds.col<BindCol::Key>();
    for (uint32_t i = s.rows.first(), e = i + s.rows.second(); i < e; i++)
      if (hs[i] == h && sameName(ks[i], n)) return &binds.col<BindCol::Val>()[i];
    return nullptr;
  }
  /// Bind `n` in s to v, again if s binds it already.  The rows of a scope are one run: a scope is bound before the
  /// scopes inside it are.
  void bindTo(Scope &s, const Name &n, Value v) {
    uint32_t h = hashOf(n);
    if (Value *cell = lookup(s, n, h)) {
      *cell = v;
      return;
    }
    if (!s.rows.second()) s.rows = ::join::TwInt(binds.size(), 0);
    else if (s.rows.first() + s.rows.second() != binds.size()) error("internal error: a scope bound after one inside it", Pos{});
    binds.append(n, h, v);
    s.rows = ::join::TwInt(s.rows.first(), s.rows.second() + 1);
  }
  void undefined(Name n, Pos p) {
    ParseError e(composite::cat("undefined variable '", n.str(), "'"), p, origin);
    if (minting) throw e;
    if (!undefinedErr) undefinedErr = composite::own<ParseError>(e);
  }

  //===--------------------------------------------------------------------===//
  // Nodes
  //===--------------------------------------------------------------------===//

  static Node mk(Kind k, Pos p, Value v = {}) {
    Node n;
    n.k = k;
    n.pos = p;
    n.v = v;
    return n;
  }
  Node text(composite::Text s, Kind k, Pos p) {
    Node n = mk(k, p);
    n.shownAt = texts.append(composite::mv(s));
    return n;
  }
  /// The value of a node (Gen): a set or a string is made when it is first used.
  Value val(Node &n) {
    if (n.k == K_SET) {
      n.v = makeSet(n.set);
      n.k = K_EXPR;
    } else if (n.k == K_STR && !n.v) {
      n.v = str(n.text);
    }
    return n.v;
  }
  /// The text of a node (Show): a window on its row of `texts`.
  std::string_view txt(Node &n) {
    if (n.k == K_SET) {
      composite::Text s = showSet(n.set);
      n.shownAt = texts.append(composite::mv(s));
      n.k = K_EXPR;
    }
    return texts[n.shownAt];
  }
  static composite::Text ident(Name n) {
    composite::Text t;
    printIdentifier(t, n.str());
    return t;
  }
  composite::Text showPath(llvm::ArrayRef<Comp> path) {
    composite::Text s;
    for (const Comp &c : path) {
      if (!s.empty()) s += '.';
      if (c.computed()) {
        s.put("\"${");
        if (mode == Mode::Show) s.put(texts[c.expr.shownAt]);
        s.put("}\"");
      } else {
        s.put(ident(c.name));
      }
    }
    return s;
  }

  Node var(Name n, Pos p) {
    if (mode == Mode::Show) return text(ident(n), K_VAR, p);
    llvm::StringRef name = n.str();
    uint32_t h = hashOf(n);
    llvm::SmallVector<Value, 2> withs;
    unsigned nw = 0;
    for (Scope *c = sc; c; c = c->parent) {
      if (c->isWith) {
        withs.push_back(c->with);
        nw++;
        continue;
      }
      if (c->free) note(*c->free, n, h, p, nw == 0);
      if (Value *v = lookup(*c, n, h)) return mk(K_VAR, p, *v);
    }
    if (mode == Mode::Skip) return mk(K_VAR, p);
    if (go->isBaseName && go->isBaseName(go->baseNames, name)) return mk(K_VAR, p, baseRef(name));
    if (withs.empty()) {
      undefined(n, p);
      return mk(K_VAR, p, baseRef("null"));
    }
    return mk(K_VAR, p, nd::WithVarOp::create(b, noLoc(), valTy(), n, withs, at(p)));
  }
  static void note(Free &f, const Name &n, uint32_t h, Pos p, bool strict) {
    uint32_t k = ~0u;
    if (f.index.empty()) {
      for (uint32_t i = 0; i < f.names.size() && k == ~0u; i++)
        if (f.hashes[i] == h && sameName(f.names[i].name, n)) k = i;
    } else if (auto it = f.index.find(n.str()); it != f.index.end()) {
      k = it->second;
    }
    if (k != ~0u) {
      if (strict && !f.names[k].strict) f.names[k] = {n, p, true};
      return;
    }
    f.names.push_back({n, p, strict});
    f.hashes.push_back(h);
    if (!f.index.empty()) f.index[n.str()] = f.names.size() - 1;
    else if (f.names.size() > 32)
      for (uint32_t i = 0; i < f.names.size(); i++) f.index[f.names[i].name.str()] = i;
  }
  Node call(Pos p, Node &f, llvm::MutableArrayRef<Node> args) {
    if (mode == Mode::Show) {
      composite::Text s = composite::cat("(", txt(f));
      for (Node &a : args) s.put(' ').put(txt(a));
      s.put(')');
      return text(composite::mv(s), K_CALL, p);
    }
    if (mode == Mode::Skip) return mk(K_CALL, p);
    Value fv = val(f);
    auto av = llvm::to_vector(args |α| [&](Node &a) { return val(a); });
    return mk(K_CALL, p, nd::ApplyOp::create(b, noLoc(), valTy(), fv, av, at(p)));
  }
  /// `(f a) b` is `f a b` (upstream's makeCall): an argument after a call is one more argument of that call.
  Node extend(Node f, llvm::MutableArrayRef<Node> args) {
    if (mode == Mode::Show) {
      composite::Text s = texts[f.shownAt].clone();
      s.pop_back();
      for (Node &a : args) s.put(' ').put(txt(a));
      s.put(')');
      f.shownAt = texts.append(composite::mv(s));
    } else if (mode == Mode::Gen) {
      auto ap = f.v.getDefiningOp<nd::ApplyOp>();
      llvm::SmallVector<Value> av(ap.getArgs().begin(), ap.getArgs().end());
      for (Node &a : args) av.push_back(val(a));
      f.v = nd::ApplyOp::create(b, noLoc(), valTy(), ap.getCallee(), av, int64_t(nd::getPos(ap)));
      ap.erase();
    }
    return f;
  }
  Node select(Pos p, Node &e, Path &path, Node *def) {
    if (mode == Mode::Show) {
      for (Comp &c : path)
        if (c.computed()) txt(c.expr);
      composite::Text s = composite::cat("(", txt(e), ").", showPath(path));
      if (def) s.put(" or (").put(txt(*def)).put(')');
      return text(composite::mv(s), K_EXPR, p);
    }
    if (mode == Mode::Skip) return mk(K_EXPR, p);
    Value base = val(e);
    llvm::SmallVector<Name> comps;
    llvm::SmallVector<Value> dyn;
    for (Comp &c : path) {
      comps.push_back(c.name);
      if (c.computed()) dyn.push_back(val(c.expr));
    }
    Value dv = def ? val(*def) : Value();
    return mk(K_EXPR, p, nd::SelectOp::create(b, noLoc(), valTy(), base, dyn, dv, comps, at(p)));
  }
  Node hasAttr(Pos p, Node &e, Path &path) {
    if (mode == Mode::Show) {
      for (Comp &c : path)
        if (c.computed()) txt(c.expr);
      return text(composite::cat("((", txt(e), ") ? ", showPath(path), ")"), K_EXPR, p);
    }
    if (mode == Mode::Skip) return mk(K_EXPR, p);
    Value base = val(e);
    llvm::SmallVector<Name> comps;
    llvm::SmallVector<Value> dyn;
    for (Comp &c : path) {
      comps.push_back(c.name);
      if (c.computed()) dyn.push_back(val(c.expr));
    }
    return mk(K_EXPR, p, nd::HasAttrOp::create(b, noLoc(), valTy(), base, dyn, comps, at(p)));
  }
  Node not_(Pos p, Node e) {
    if (mode == Mode::Show) return text(composite::cat("(! ", txt(e), ")"), K_EXPR, p);
    if (mode == Mode::Skip) return mk(K_EXPR, p);
    return mk(K_EXPR, p, nd::NotOp::create(b, noLoc(), valTy(), val(e), at(p)));
  }
  enum Bin { B_EQ, B_NEQ, B_AND, B_OR, B_IMPL, B_UPDATE, B_CONCAT };
  Node bin(Bin k, Pos p, Node &l, Node &r) {
    static const char *const ops[] = {"==", "!=", "&&", "||", "->", "//", "++"};
    if (mode == Mode::Show) return text(composite::cat("(", txt(l), " ", ops[k], " ", txt(r), ")"), K_EXPR, p);
    if (mode == Mode::Skip) return mk(K_EXPR, p);
    Value a = val(l), c = val(r);
    int64_t w = at(p);
    Value v;
    switch (k) {
    case B_EQ: v = nd::EqOp::create(b, noLoc(), valTy(), a, c, w); break;
    case B_NEQ: v = nd::NeqOp::create(b, noLoc(), valTy(), a, c, w); break;
    case B_AND: v = nd::AndOp::create(b, noLoc(), valTy(), a, c, w); break;
    case B_OR: v = nd::OrOp::create(b, noLoc(), valTy(), a, c, w); break;
    case B_IMPL: v = nd::ImplOp::create(b, noLoc(), valTy(), a, c, w); break;
    case B_UPDATE: v = nd::UpdateOp::create(b, noLoc(), attrsTy(), a, c, w); break;
    case B_CONCAT: v = nd::ConcatListsOp::create(b, noLoc(), listTy(), a, c, w); break;
    }
    return mk(K_EXPR, p, v);
  }
  Node concat(Pos p, bool forceString, llvm::MutableArrayRef<Node> parts) {
    if (mode == Mode::Show) {
      composite::Text s("(");
      for (Node &x : parts) s.put(s.size() > 1 ? " + " : "").put(txt(x));
      s.put(')');
      return text(composite::mv(s), K_EXPR, p);
    }
    if (mode == Mode::Skip) return mk(K_EXPR, p);
    auto vs = llvm::to_vector(parts |α| [&](Node &x) { return positioned(val(x), x.pos); });
    if (forceString) // an interpolation: always a string
      return mk(K_EXPR, p, nd::InterpolateOp::create(b, noLoc(), nd::stringType(b.getContext()), vs, at(p)));
    return mk(K_EXPR, p, nd::ConcatStringsOp::create(b, noLoc(), valTy(), vs, at(p)));
  }
  Node intLit(int64_t v, Pos p) {
    if (mode == Mode::Show) return text(composite::str(v), K_EXPR, p);
    return mk(K_EXPR, p, mode == Mode::Gen ? Value(nd::IntOp::create(b, noLoc(), valTy(), b.getI64IntegerAttr(v))) : Value());
  }
  Node strLit(Name t, Pos p) {
    Node n = mk(K_STR, p);
    n.text = t;
    if (mode == Mode::Show) {
      composite::Text lit;
      printLiteralString(lit, t.str());
      n.shownAt = texts.append(composite::mv(lit));
    }
    return n;
  }
  /// A `let` or `with` gives a fresh value, a variable shares the bound one; a `let` or `with` whose body is a variable
  /// (or another such) gets an identity node, so that value identity (`==` on functions, «repeated») matches upstream's.
  Node shared(Node &body, Pos pos) {
    Kind k = body.k == K_VAR || body.k == K_SHARED ? K_SHARED : K_EXPR;
    if (mode != Mode::Gen) return mk(k, pos);
    Value v = val(body);
    return mk(k, pos, k == K_SHARED ? identity(v, pos) : v);
  }

  //===--------------------------------------------------------------------===//
  // Heads: the names of a group, read where its statements start (layer 2)
  //===--------------------------------------------------------------------===//

  uint32_t bandAt(uint32_t off) const { return bands ? bands->at(off) : ~0u; }
  uint32_t bandNeed(uint32_t off) { return bands ? bands->need(off) : ~0u; } // scanned now if no scan has met it
  bool hasBand(uint32_t r) const { return bands && r < bands->size(); }
  Lexer &heads() {
    if (!hl) {
      hl = composite::own<Lexer>(origin, opts);
      hl->wantPos = false;
    }
    return *hl;
  }
  /// Where statement j of band r starts.
  uint32_t stmtStart(uint32_t r, uint32_t j) {
    if (j) return bands->stmts(r)[j - 1] + 1;
    return bands->span(r).first() + (bands->kind(r) == confix::K_LET ? 3 : 1);
  }
  void bind(Scope &s, Name n) {
    if (!lookup(s, n, hashOf(n))) bindTo(s, n, mode == Mode::Gen ? placeholder() : Value());
  }
  enum Got { G_NAME, G_DYN, G_NONE };
  /// The component of an attribute path at t, read on: a static name (an identifier, `or`, "s", ${"s"}), a computed one
  /// (stepped over), or none.
  Got comp(Token &t, Name &n) {
    Lexer &h = heads();
    if (t.t == T_ID) { n = nameOf(h, t); return G_NAME; }
    if (t.t == T_OR_KW) { n = Name::of("or"); return G_NAME; }
    if (!isChar(t, '"') && t.t != T_DOLLAR_CURLY) return G_NONE;
    uint32_t band = bandAt(t.offset);
    if (!hasBand(band)) return G_NONE;
    uint32_t close = bands->span(band).second();
    bool interp = t.t == T_DOLLAR_CURLY;
    Token u = h.nextToken();
    if (interp && isChar(u, '"')) u = h.nextToken();
    else if (interp) goto dynamic;
    n = Name::of("");
    if (u.t == T_STR) {
      n = nameOf(h, u);
      u = h.nextToken();
    }
    if (!isChar(u, '"')) goto dynamic;
    if (interp) u = h.nextToken();
    if (u.offset == close && (interp ? isChar(u, '}') : true)) return G_NAME;
  dynamic:
    h.reposition(close + 1, Pos{});
    return interp && staticInterp(t.offset + 2, close, n) ? G_NAME : G_DYN;
  }
  /// Whether the interpolation whose expression starts at `from` and whose `}` is at `close` is a string literal, a
  /// static name (NixOS/nix#14642), as the parser will find it: a parse of it that builds nothing.  An error is the
  /// parser's to report, where it meets it.
  bool staticInterp(uint32_t from, uint32_t close, Name &n) {
    try {
      Parser p(Mode::Skip, origin, opts, bands);
      p.jump(from, Pos{});
      Node e = p.parseExpr();
      if (e.k != K_STR || !p.atChar('}') || p.cur().offset != close) return false;
      n = e.text;
      return true;
    } catch (const ParseError &) {
      return false;
    }
  }
  struct Head {
    llvm::SmallVector<Name, 4> path, names; // the static prefix of its path; the names it binds
    uint32_t lit = ~0u;                     // the band of a set literal that is all of its value
  };
  /// The head of statement j of band r.  What the lexer refuses here, the parser reports when it gets there.
  Head headOf(uint32_t r, uint32_t j) {
    Head hd;
    try {
      readHead(hd, r, j);
    } catch (const ParseError &) {
    }
    return hd;
  }
  void readHead(Head &hd, uint32_t r, uint32_t j) {
    Lexer &h = heads();
    h.reposition(stmtStart(r, j), Pos{});
    Token t = h.nextToken();
    Name n;
    if (t.t == T_INHERIT) {
      t = h.nextToken();
      if (isChar(t, '(')) {
        uint32_t p = bandAt(t.offset);
        if (!hasBand(p)) return;
        h.reposition(bands->span(p).second() + 1, Pos{});
        t = h.nextToken();
      }
      for (; comp(t, n) == G_NAME; t = h.nextToken()) hd.names.push_back(n);
      return;
    }
    bool all = true;
    for (;;) {
      Got g = comp(t, n);
      if (g == G_NONE) return;
      if (g == G_NAME && all) hd.path.push_back(n);
      else all = false;
      t = h.nextToken();
      if (!isChar(t, '.')) break;
      t = h.nextToken();
    }
    if (!hd.path.empty()) hd.names.push_back(hd.path[0]);
    if (!all || !isChar(t, '=')) return;
    llvm::SmallVector<uint32_t, 2> parens; // `a = ({ ... });`: parentheses keep a literal the whole value
    for (t = h.nextToken(); isChar(t, '('); t = h.nextToken()) parens.push_back(bandAt(t.offset));
    if (t.t == T_REC) t = h.nextToken();
    uint32_t lit = isChar(t, '{') ? bandAt(t.offset) : ~0u;
    if (!hasBand(lit)) return;
    h.reposition(bands->span(lit).second() + 1, Pos{});
    t = h.nextToken();
    for (size_t k = parens.size(); k-- > 0; t = h.nextToken())
      if (!hasBand(parens[k]) || !isChar(t, ')') || t.offset != bands->span(parens[k]).second()) return;
    if (isChar(t, ';') && j < bands->stmts(r).size() && t.offset == bands->stmts(r)[j]) hd.lit = lit;
  }
  /// The first component of the path of each statement of band r, read once: what the bindings after a `rec` literal
  /// give it is looked for among the statements whose path starts as its own.
  llvm::DenseMap<uint32_t, composite::MutableSeries<Name>> firsts;
  Name firstOf(uint32_t r, uint32_t j) {
    auto [it, fresh] = firsts.try_emplace(r);
    if (fresh)
      for (uint32_t k = 0, n = bands->stmts(r).size(); k < n; k++) {
        Head hd = headOf(r, k);
        it->second.append(hd.path.empty() ? Name() : hd.path[0]);
      }
    return it->second[j];
  }
  /// Bind in s the names that statements j0.. of band r give the set at `rel`, a path from the band's own set: with `rel`
  /// empty, the names they bind; else the next component of a path that goes through the set, and what a set literal
  /// bound on the way to it gives it (NixOS/nix#9020: a binding merged into a `rec` set is a member of its scope).
  void adds(uint32_t r, uint32_t j0, llvm::ArrayRef<Name> rel, Scope &s) {
    if (!hasBand(r)) return;
    for (uint32_t j = j0, n = bands->stmts(r).size(); j < n; j++) {
      if (!rel.empty() && firstOf(r, j) != rel[0]) continue;
      Head hd = headOf(r, j);
      if (rel.empty()) {
        for (Name x : hd.names) bind(s, x);
        continue;
      }
      size_t m = composite::min(hd.path.size(), rel.size());
      if (m == 0 || llvm::ArrayRef<Name>(hd.path).take_front(m) != rel.take_front(m)) continue;
      if (hd.path.size() > rel.size()) bind(s, hd.path[rel.size()]);
      else if (hd.lit != ~0u) adds(hd.lit, 0, rel.drop_front(hd.path.size()), s);
    }
  }
  /// The formals of a formals band (the first token after its `{` and after each of its commas), bound in s; and the name
  /// after `}@`, if any, which is the lambda's argument.
  Name formalNames(uint32_t brace, Scope &s) {
    uint32_t r = bandNeed(brace);
    if (!hasBand(r)) return Name();
    try {
      Lexer &h = heads();
      auto ends = bands->stmts(r);
      for (uint32_t j = 0; j <= ends.size(); j++) {
        h.reposition(j ? ends[j - 1] + 1 : brace + 1, Pos{});
        Token t = h.nextToken();
        if (t.t == T_ID) bind(s, nameOf(h, t));
      }
      h.reposition(bands->span(r).second() + 1, Pos{});
      Token t = h.nextToken();
      if (!isChar(t, '@')) return Name();
      t = h.nextToken();
      return t.t == T_ID ? nameOf(h, t) : Name();
    } catch (const ParseError &) {
      return Name();
    }
  }
  /// The statement ends where the scan said (layer 1): checked wherever a statement's semicolon is met in a band scanned.
  void stmtEnd(const Ctx &c) {
    if (!hasBand(c.band) || !atChar(';')) return;
    auto ends = bands->stmts(c.band);
    if (c.stmt >= ends.size() || ends[c.stmt] != cur().offset)
      error("internal error: the scan ends this statement elsewhere", cur().pos);
  }

  //===--------------------------------------------------------------------===//
  // Sets
  //===--------------------------------------------------------------------===//

  uint32_t newSet(Pos pos, Scope *values, Scope *outer) {
    uint32_t si;
    if (!freeSets.empty()) {
      si = freeSets.back();
      freeSets.pop();
    } else {
      si = uint32_t(sets.size());
      sets.emplace();
    }
    Set &s = sets[si];
    s.pos = pos;
    s.values = values;
    s.outer = outer;
    return si;
  }
  void release(uint32_t si) {
    Set &s = sets[si];
    s.defs.clear();
    s.dyns.clear();
    s.froms.clear();
    s.index.clear();
    s.rec = false;
    s.ordered = true;
    s.scope = s.values = s.outer = nullptr;
    s.into = nullptr;
    freeSets.append(si);
  }
  static Node setNode(uint32_t si, Pos p) {
    Node n = mk(K_SET, p);
    n.set = si;
    return n;
  }
  /// The defs ordered by name: the order of the set's ops and of `--parse`.
  void order(Set &s) {
    if (s.ordered) return;
    composite::sortRows(s.defs.data(), s.defs.size(), [](const Def &a, const Def &b) { return composite::lessChars(a.name.chars(), b.name.chars()); });
    s.index.clear();
    s.ordered = true;
  }
  static bool sameName(const Name &a, const Name &b) {
    return a.size == b.size && (a.size == 0 || memcmp(a.data, b.data, a.size) == 0);
  }
  static uint32_t hashOf(const Name &n) {
    return static_cast<uint32_t>(llvm::xxh3_64bits(llvm::ArrayRef<uint8_t>(reinterpret_cast<const uint8_t *>(n.data), n.size)));
  }
  /// A set of a handful is searched by comparing; a larger one has an index, open addressing over positions in `defs`.
  static constexpr uint32_t kScan = 8;
  Def *findDef(Set &s, const Name &n) {
    if (s.index.empty()) {
      for (Def &d : s.defs)
        if (sameName(d.name, n)) return &d;
      return nullptr;
    }
    uint32_t mask = uint32_t(s.index.size() - 1);
    for (uint32_t h = hashOf(n) & mask;; h = (h + 1) & mask) {
      uint32_t k = s.index[h];
      if (!k) return nullptr;
      if (sameName(s.defs[k - 1].name, n)) return &s.defs[k - 1];
    }
  }
  static void indexDef(Set &s, uint32_t k) { // k: the position in `defs`, plus one
    uint32_t mask = uint32_t(s.index.size() - 1);
    uint32_t h = hashOf(s.defs[k - 1].name) & mask;
    while (s.index[h]) h = (h + 1) & mask;
    s.index[h] = k;
  }
  void appendDef(Set &s, Def d) {
    s.defs.append(std::move(d));
    uint32_t n = uint32_t(s.defs.size());
    s.ordered = n <= 1;
    if (!s.index.empty() && n * 2 <= s.index.size()) {
      indexDef(s, n);
    } else if (n > kScan) { // at most a quarter full when built, a half before it is built again
      uint32_t cap = 32;
      while (cap < n * 4) cap *= 2;
      s.index.assign(cap, 0);
      for (uint32_t k = 1; k <= n; k++) indexDef(s, k);
    }
  }
  [[noreturn]] void dupAttr(llvm::ArrayRef<Comp> path, Pos pos, Pos prev) {
    error(composite::cat("attribute '", showPath(path), "' already defined at ", fmtPos(prev)), pos);
  }
  /// Where the value of `path = ...;` in set si is parsed, and the set a literal there merges with (NixOS/nix#9020: a
  /// binding that lands in a `rec` set is parsed in its scope).  A path goes through the sets that will be one when
  /// the literals being read merge: at each component, those of si and of what it merges into; the last is the one
  /// the others merge into.
  composite::Join<Scope *, Set *> target(uint32_t si, llvm::ArrayRef<Comp> path) {
    llvm::SmallVector<Set *, 4> level, next;
    for (Set *s = &sets[si]; s; s = s->into) level.push_back(s);
    for (const Comp &c : path) {
      next.clear();
      for (Set *s : level)
        if (Def *d = c.computed() ? nullptr : findDef(*s, c.name); d && d->kind == D_PLAIN && d->val.k == K_SET)
          for (Set *t = &sets[d->val.set]; t; t = t->into) next.push_back(t);
      if (next.empty()) return {level.back()->values, nullptr};
      level.swap(next);
    }
    return {level.back()->values, level.back()};
  }
  void addAttr(uint32_t si, Path &path, Pos pos, Node e) {
    size_t i = 0;
    for (; i + 1 < path.size(); i++) {
      uint32_t nested;
      if (!path[i].computed()) {
        if (Def *j = findDef(sets[si], path[i].name)) {
          if (j->val.k != K_SET || j->kind != D_PLAIN) dupAttr(llvm::ArrayRef<Comp>(path.data(), i + 1), pos, j->pos);
          nested = j->val.set;
        } else { // a set a path makes is not rec: its values are its parent's
          nested = newSet(Pos{}, sets[si].values, sets[si].values);
          Def d;
          d.name = path[i].name;
          d.pos = pos;
          d.val = setNode(nested, Pos{});
          appendDef(sets[si], std::move(d));
        }
      } else {
        nested = newSet(Pos{}, sets[si].values, sets[si].values);
        sets[si].dyns.append(Dyn{std::move(path[i].expr), setNode(nested, Pos{}), pos});
      }
      si = nested;
    }
    if (path[i].computed()) {
      sets[si].dyns.append(Dyn{std::move(path[i].expr), std::move(e), pos});
      return;
    }
    Def d;
    d.name = path[i].name;
    d.pos = pos;
    d.val = std::move(e);
    addAttrSym(si, path, std::move(d));
  }
  void addAttrSym(uint32_t si, llvm::ArrayRef<Comp> path, Def d) {
    if (Def *j = findDef(sets[si], d.name)) {
      if (d.val.k != K_SET || j->val.k != K_SET || j->kind != D_PLAIN) dupAttr(path, d.pos, j->pos);
      uint32_t into = j->val.set, from = d.val.set;
      Set &ae = sets[from];
      order(ae);
      uint32_t base = uint32_t(sets[into].froms.size());
      Path full(path.begin(), path.end()); // the path to the merged set, for the messages
      for (Def &ad : ae.defs) { // by name, so the duplicate reported first is the least
        if (ad.kind == D_FROM) ad.from += base;
        full.push_back(Comp{ad.name, {}});
        addAttrSym(into, full, std::move(ad));
        full.pop_back();
      }
      for (Dyn &x : ae.dyns) sets[into].dyns.append(std::move(x));
      for (Node &x : ae.froms) sets[into].froms.append(std::move(x));
      release(from);
      return;
    }
    if (d.val.k == K_LAMBDA && mode == Mode::Gen)
      if (auto lam = d.val.v.getDefiningOp<nd::LambdaOp>(); lam && !lam.getNameAttr())
        lam.setNameAttr(b.getStringAttr(d.name.str()));
    appendDef(sets[si], std::move(d));
  }
  /// The value of a group member's placeholder (Gen); a name it was given ahead that nothing bound is an orphan.
  Value member(Scope &s, const Name &n) {
    Value *v = lookup(s, n, hashOf(n));
    if (!v) error(composite::cat("internal error: the heads of a set missed '", n.str(), "'"), Pos{});
    return *v;
  }
  /// Names a group was given ahead that no binding gave it: only a binding the parse refuses can leave one, so the parse
  /// must fail; done() says so if it does not.
  void orphansOf(Scope &s, Set &set) { orphans += uint32_t(s.rows.second() - set.defs.size()); }
  /// Make a set (Gen): its members' values ordered by name, a rec set's placeholders replaced, the attrs op.
  Value makeSet(uint32_t si) {
    Set &s = sets[si];
    order(s);
    llvm::SmallVector<Name> names;
    llvm::SmallVector<int64_t> positions;
    llvm::SmallVector<Value> values, dynNames, dynValues;
    for (Def &d : s.defs) {
      names.push_back(d.name);
      positions.push_back(at(d.pos));
      values.push_back(val(d.val));
    }
    for (Dyn &d : s.dyns) {
      dynNames.push_back(positioned(val(d.name), d.name.pos));
      dynValues.push_back(val(d.val));
    }
    Value r;
    if (!s.rec) {
      r = nd::AttrsOp::create(b, noLoc(), attrsTy(), names, values, dynNames, dynValues, positions, at(s.pos));
    } else {
      llvm::SmallVector<Value> phv;
      llvm::SmallVector<Pos> poses;
      int ov = -1;
      for (size_t i = 0; i < s.defs.size(); i++) {
        phv.push_back(member(*s.scope, s.defs[i].name));
        poses.push_back(s.defs[i].pos);
        if (s.defs[i].name.str() == "__overrides") ov = int(i);
      }
      orphansOf(*s.scope, s);
      // Legacy `__overrides`: attributes of the overrides set replace both the recursive bindings and the result.
      if (ov >= 0)
        for (size_t i = 0; i < s.defs.size(); i++)
          if (int(i) != ov) values[i] = selectLiteral(s.defs[i].pos, values[ov], names[i], values[i]);
      auto finals = finalizeGroup(phv, values, poses, {&dynNames, &dynValues});
      r = nd::AttrsOp::create(b, noLoc(), attrsTy(), names, finals, dynNames, dynValues, positions, at(s.pos));
      if (ov >= 0) r = nd::UpdateOp::create(b, noLoc(), attrsTy(), r, finals[ov], at(s.pos));
    }
    release(si);
    return r;
  }
  composite::Text showSet(uint32_t si) {
    composite::Text r(sets[si].rec ? "rec { " : "{ ");
    r.put(bindings(si)).put('}');
    return r;
  }
  /// The bindings as `--parse` prints them: the inherits, those of each source, the plain ones, the dynamic ones.
  composite::Text bindings(uint32_t si) {
    Set &s = sets[si];
    order(s);
    composite::Text r, inherits;
    composite::MutableSeries<composite::Text> from(s.froms.size()); // by source: the names inherited from it, empty when none
    for (Def &d : s.defs)
      if (d.kind == D_INHERITED) inherits.put(' ').put(ident(d.name));
      else if (d.kind == D_FROM) from[d.from].put(' ').put(ident(d.name));
    if (!inherits.empty()) r.put("inherit").put(inherits).put("; ");
    for (uint32_t i = 0; i < from.size(); i++)
      if (!from[i].empty()) r.put("inherit (").put(txt(s.froms[i])).put(')').put(from[i]).put("; ");
    for (Def &d : s.defs)
      if (d.kind == D_PLAIN) r.put(ident(d.name)).put(" = ").put(txt(d.val)).put("; ");
    for (Dyn &d : s.dyns) r.put("\"${").put(txt(d.name)).put("}\" = ").put(txt(d.val)).put("; ");
    release(si);
    return r;
  }

  /// binds: a sequence of `attrpath = expr;` and `inherit ...;`, into set si, whose statements are band `band`.
  void parseBinds(uint32_t si, uint32_t band, Ctx *up, uint32_t open) {
    Ctx c{band, 0, {}, up, open};
    for (;; c.stmt++) {
      if (cur().t == T_INHERIT) {
        take();
        int from = -1;
        if (atChar('(')) {
          take();
          Scope *s0 = sc;
          sc = sets[si].values;
          Node f = parseExpr();
          sc = s0;
          expectChar(')');
          sets[si].froms.append(std::move(f));
          from = int(sets[si].froms.size()) - 1;
        }
        while (!atChar(';')) {
          Pos apos = cur().pos;
          Name name;
          if (cur().t == T_ID) name = nameOf(take());
          else if (cur().t == T_OR_KW) { take(); name = Name::of("or"); }
          else if (atChar('"') || cur().t == T_DOLLAR_CURLY) {
            Comp an = parseStringAttr();
            if (an.computed()) error("dynamic attributes not allowed in inherit", apos);
            name = an.name;
          } else {
            unexpected();
          }
          if (Def *prev = findDef(sets[si], name))
            error(composite::cat("attribute '", ident(name), "' already defined at ", fmtPos(prev->pos)), apos);
          Def d;
          d.name = name;
          d.pos = apos;
          if (from >= 0) {
            d.kind = D_FROM;
            d.from = uint32_t(from);
            if (mode == Mode::Gen) d.val = mk(K_EXPR, apos, selectLiteral(apos, val(sets[si].froms[from]), name));
          } else {
            d.kind = D_INHERITED;
            Scope *s0 = sc;
            sc = sets[si].outer;
            d.val = var(name, apos);
            sc = s0;
          }
          appendDef(sets[si], std::move(d));
        }
        stmtEnd(c);
        take();
        continue;
      }
      if (cur().t == T_ID || cur().t == T_OR_KW || atChar('"') || cur().t == T_DOLLAR_CURLY) {
        Pos apos = cur().pos;
        Path path = parseAttrPath(si);
        expectChar('=');
        c.path.clear();
        for (Comp &x : path) {
          if (x.computed()) break;
          c.path.push_back(x.name);
        }
        auto [scope, into] = target(si, path);
        valueAt = cur().offset;
        mergeInto = into;
        valueCtx = c.path.size() == path.size() ? &c : nullptr;
        Scope *s0 = sc;
        sc = scope;
        Node e = parseExpr();
        sc = s0;
        stmtEnd(c);
        expectChar(';');
        addAttr(si, path, apos, std::move(e));
        continue;
      }
      break;
    }
  }

  /// A set literal at `{` (after `rec`, if any; `first` is the offset of its first token).
  Node literal(Pos pos, bool rec, uint32_t first) {
    bool direct = first == valueAt; // the whole value of a binding: it can merge, and later bindings can land in it
    Set *into = direct ? mergeInto : nullptr;
    Ctx *up = direct ? valueCtx : nullptr;
    valueAt = ~0u;
    mergeInto = nullptr;
    valueCtx = nullptr;
    uint32_t open = cur().offset, band = rec ? bandNeed(open) : bandAt(open);
    expectChar('{');
    uint32_t si;
    if (into) { // it merges with the set bound there: its `rec` is lost, and that set's scope is its own (NixOS/nix#9020)
      si = newSet(pos, into->values, into->outer);
      sets[si].into = into;
    } else if (rec) {
      recScopes.emplace();
      Scope &rs = recScopes.back();
      rs.parent = sc;
      if (mode != Mode::Show) {
        adds(band, 0, {}, rs); // its names: its statements', then those that bindings after it give it
        llvm::SmallVector<Name, 8> rel;
        for (Ctx *k = up; k; k = k->up) {
          rel.insert(rel.begin(), k->path.begin(), k->path.end());
          adds(hasBand(k->band) ? k->band : bandNeed(k->open), k->stmt + 1, rel, rs);
        }
      }
      si = newSet(pos, &rs, sc);
      sets[si].rec = true;
      sets[si].scope = &rs;
    } else {
      si = newSet(pos, sc, sc);
    }
    parseBinds(si, band, up, open);
    expectChar('}');
    return setNode(si, pos);
  }

  //===--------------------------------------------------------------------===//
  // The grammar
  //===--------------------------------------------------------------------===//

  // expr: expr_function
  Node parseExpr() { return parseFunction(); }

  bool looksLikeFormals() {
    // Called with cur() == '{'.
    const Token &a = peek(1);
    if (a.t == T_ELLIPSIS) return true;
    if (isChar(a, '}')) {
      const Token &b2 = peek(2);
      return isChar(b2, ':') || isChar(b2, '@');
    }
    if (a.t == T_ID) {
      const Token &b2 = peek(2);
      return isChar(b2, ',') || isChar(b2, '?') || (isChar(b2, '}') && (isChar(peek(3), ':') || isChar(peek(3), '@')));
    }
    return false;
  }

  Node parseFunction() {
    const Token &t = cur();
    if ((t.t == T_ID && (isChar(peek(), ':') || (isChar(peek(), '@') && isChar(peek(2), '{')))) ||
        (atChar('{') && looksLikeFormals()))
      return lambda();
    Pos pos = t.pos;
    if (t.t == T_ASSERT) {
      take();
      uint32_t c0 = cur().offset;
      Pos cp = cur().pos;
      Node c = parseExpr();
      expectChar(';');
      Node body = parseFunction();
      if (mode == Mode::Show) return text(composite::cat("assert ", txt(c), "; ", txt(body)), K_EXPR, pos);
      if (mode == Mode::Skip) return mk(K_EXPR, pos);
      Value cv = val(c), bv = val(body);
      return mk(K_EXPR, pos, nd::AssertOp::create(b, noLoc(), valTy(), cv, bv, b.getStringAttr(llvm::StringRef(shown(c0, cp))), at(pos)));
    }
    if (t.t == T_WITH) {
      take();
      Node a = parseExpr();
      expectChar(';');
      Scope ns;
      ns.parent = sc;
      ns.isWith = true;
      if (mode == Mode::Gen) ns.with = positioned(val(a), a.pos);
      Scope *s0 = sc;
      sc = &ns;
      Node body = parseFunction();
      sc = s0;
      if (mode == Mode::Show) return text(composite::cat("(with ", txt(a), "; ", txt(body), ")"), K_EXPR, pos);
      return shared(body, pos);
    }
    if (t.t == T_LET && !isChar(peek(), '{')) {
      uint32_t open = t.offset, band = bandNeed(open);
      take();
      Scope ns;
      ns.parent = sc;
      if (mode != Mode::Show) adds(band, 0, {}, ns);
      uint32_t si = newSet(pos, &ns, sc);
      sets[si].scope = &ns;
      parseBinds(si, band, nullptr, open);
      if (cur().t != T_IN) unexpected("'in'");
      take();
      if (!sets[si].dyns.empty()) error("dynamic attributes not allowed in let", pos);
      composite::Text head;
      if (mode == Mode::Show) {
        head = composite::cat("(let ", bindings(si), "in ");
      } else {
        Set &s = sets[si];
        order(s);
        llvm::SmallVector<Value> phv, values;
        llvm::SmallVector<Pos> poses;
        for (Def &d : s.defs) {
          phv.push_back(member(ns, d.name));
          if (mode == Mode::Gen) values.push_back(val(d.val));
          poses.push_back(d.pos);
        }
        orphansOf(ns, s);
        if (mode == Mode::Gen) {
          auto finals = finalizeGroup(phv, values, poses);
          for (size_t i = 0; i < s.defs.size(); i++) bindTo(ns, s.defs[i].name, finals[i]);
        }
        release(si);
      }
      Scope *s0 = sc;
      sc = &ns;
      Node body = parseFunction();
      sc = s0;
      if (mode == Mode::Show) return text(composite::cat(head, txt(body), ")"), K_EXPR, pos);
      return shared(body, pos);
    }
    return parseIf();
  }

  /// The text `--parse` prints for the expression at `off` (the message of a failed assertion), parsed again.
  composite::Text shown(uint32_t off, Pos pos) {
    ParseOptions quiet;
    quiet.pipeOperators = opts.pipeOperators;
    quiet.home = opts.home;
    Parser p(Mode::Show, origin, quiet, nullptr);
    p.jump(off, pos);
    Node e = p.parseExpr();
    return composite::Text(p.txt(e));
  }

  //===--------------------------------------------------------------------===//
  // Lambdas
  //===--------------------------------------------------------------------===//

  Node lambda() {
    Pos pos = cur().pos;
    uint32_t at0 = cur().offset;
    bool eager = at0 == eagerAt;
    if (mode == Mode::Gen && go->deferBodies && !eager) return defer(pos, at0);
    Hdr h;
    if (mode == Mode::Show) {
      Node body = lambdaBody(h, Value());
      composite::Text s("(");
      if (h.formals) {
        s += "{ ";
        bool first = true;
        for (Formal &f : h.fs) {
          if (!first) s += ", ";
          first = false;
          s += ident(f.name);
          if (f.hasDef) s.put(" ? ").put(txt(f.def));
        }
        if (h.ellipsis) s += first ? "..." : ", ...";
        s += " }";
        if (!h.arg.isNull()) s += " @ ";
      }
      if (!h.arg.isNull()) s += ident(h.arg);
      s.put(": ").put(txt(body)).put(')');
      return text(composite::mv(s), K_LAMBDA, pos);
    }
    if (mode == Mode::Skip) { // what reaches its edge is free in it: an enclosing skim keeps that for the lambda's own call
      Free free;
      Scope edge;
      edge.parent = sc;
      edge.free = &free;
      Scope *s0 = sc;
      sc = &edge;
      lambdaBody(h, Value());
      sc = s0;
      if (go && go->pool) go->pool->see(at0, cur().offset, cur().pos, free.names);
      return mk(K_LAMBDA, pos);
    }
    mlir::Block *blk = new mlir::Block();
    Value arg = blk->addArgument(valTy(), noLoc());
    mlir::OpBuilder::InsertPoint ip = b.saveInsertionPoint();
    b.setInsertionPointToEnd(blk);
    Node body = lambdaBody(h, arg, eager);
    nd::ReturnOp::create(b, noLoc(), val(body));
    b.restoreInsertionPoint(ip);
    nd::LambdaOp lam = shell(h, pos, {}, mlir::IntegerAttr());
    lam.getBody().push_back(blk);
    return mk(K_LAMBDA, pos, lam.getResult());
  }

  /// The defer half of the schedule: the lambda is skimmed (or stepped over, when an enclosing skim saw it), its free names
  /// resolve against the live scope now and become capture operands, and the pool keeps where it starts.  A name no scope
  /// supplies is a static error here, exactly when the eager schedule reports it, unless a `with` could supply it.
  Node defer(Pos pos, uint32_t at0) {
    FilePool &pl = *go->pool;
    Hdr h;
    Free free;
    Scope edge;
    edge.free = &free; // the skim stops here
    Scope *s0 = sc;
    Mode m0 = mode;
    mode = Mode::Skip;
    sc = &edge;
    auto seen = lx.plain() ? pl.seen.find(at0) : pl.seen.end();
    if (seen != pl.seen.end()) { // its header again (the formals), then past its body
      Scope ns;
      ns.parent = &edge;
      header(h, ns, Value());
      FilePool::Seen s = seen->second;
      pl.seen.erase(seen);
      for (uint32_t k = s.free.first(), e = k + s.free.second(); k < e; k++) free.names.push_back(pl.freeCol[k]); // (LLVM's SmallVector)
      jump(s.end, s.endPos);
    } else {
      lambdaBody(h, Value());
    }
    mode = m0;
    sc = s0;
    llvm::SmallVector<Value> caps;
    for (Scope *c = sc; c; c = c->parent)
      if (c->isWith) caps.push_back(c->with); // the lookup's order: innermost first
    unsigned withs = caps.size();
    llvm::SmallVector<llvm::StringRef> names;
    for (FreeName &f : free.names) {
      if (Value v = resolveStatic(f.name)) {
        names.push_back(f.name.str());
        caps.push_back(v);
      } else if (f.strict && withs == 0) {
        undefined(f.name, f.pos);
      }
    }
    uint32_t row = pl.defer(at0, pos, withs, names);
    nd::LambdaOp lam = shell(h, pos, caps, b.getI64IntegerAttr(static_cast<int64_t>(BodyIndex(pl.file, row).raw)));
    mlir::Block *blk = new mlir::Block();
    lam.getBody().push_back(blk);
    blk->addArgument(valTy(), noLoc());
    pl.attach(row, lam); // the node exists, its graph does not: the pool holds where it starts
    return mk(K_LAMBDA, pos, lam.getResult());
  }

  nd::LambdaOp shell(Hdr &h, Pos pos, mlir::ValueRange caps, mlir::IntegerAttr bodyIndex) {
    llvm::SmallVector<mlir::Attribute> names;
    llvm::SmallVector<bool> hasDef;
    llvm::SmallVector<int64_t> locs;
    for (Formal &f : h.fs) {
      names.push_back(b.getStringAttr(f.name.str()));
      hasDef.push_back(f.hasDef);
      locs.push_back(at(f.pos));
    }
    return nd::LambdaOp::create(b, noLoc(), nd::fnType(b.getContext()), h.formals ? b.getArrayAttr(names) : mlir::ArrayAttr(),
                                h.formals ? b.getDenseBoolArrayAttr(hasDef) : mlir::DenseBoolArrayAttr(), h.ellipsis,
                                h.arg.isNull() ? mlir::StringAttr() : b.getStringAttr(h.arg.str()), mlir::StringAttr(),
                                h.formals ? b.getDenseI64ArrayAttr(locs) : mlir::DenseI64ArrayAttr(), caps, bodyIndex,
                                at(pos));
  }

  /// A lambda's header and body, into the current block (Gen), whose argument is `arg`.
  Node lambdaBody(Hdr &h, Value arg, bool eager = false) {
    Scope ns;
    ns.parent = sc;
    header(h, ns, arg);
    if (eager) eagerAt = cur().offset;
    Scope *s0 = sc;
    sc = &ns;
    Node body = parseFunction();
    sc = s0;
    return body;
  }

  /// `x:`, `x@{...}:`, `{...}@x:` or `{...}:`, through the colon: the argument and the formals bound in ns (the formals
  /// before their defaults are parsed, since a default may read any of them, and the argument).
  void header(Hdr &h, Scope &ns, Value arg) {
    Pos pos = cur().pos;
    if (cur().t == T_ID) {
      h.arg = nameOf(take());
      bindTo(ns, h.arg, arg);
      if (atChar(':')) {
        take();
        return;
      }
      take(); // '@'
    }
    h.formals = true;
    if (mode != Mode::Show) {
      Name after = formalNames(cur().offset, ns);
      if (!after.isNull() && h.arg.isNull()) bindTo(ns, after, arg);
    }
    expectChar('{');
    Scope *s0 = sc;
    sc = &ns;
    while (true) {
      if (atChar('}')) { take(); break; }
      if (cur().t == T_ELLIPSIS) {
        take();
        h.ellipsis = true;
        expectChar('}');
        break;
      }
      if (cur().t != T_ID) unexpected();
      Formal f;
      f.pos = cur().pos;
      f.name = nameOf(take());
      if (atChar('?')) {
        take();
        f.def = parseExpr();
        f.hasDef = true;
      }
      h.fs.push_back(std::move(f));
      if (atChar(',')) { take(); continue; }
      if (atChar('}')) { take(); break; }
      unexpected();
    }
    sc = s0;
    if (h.arg.isNull() && atChar('@')) {
      take();
      if (cur().t != T_ID) unexpected("identifier");
      h.arg = nameOf(take());
    }
    validate(h, pos);
    if (mode == Mode::Gen) { // the formals' ops, ordered by name, then their placeholders replaced
      auto fvs = llvm::to_vector(h.fs |α| [&](Formal &f) -> Value {
        return nd::FormalOp::create(b, noLoc(), valTy(), arg, f.name, f.hasDef ? val(f.def) : Value(), at(f.pos)); });
      for (size_t i = 0; i < h.fs.size(); i++) {
        Value ph = member(ns, h.fs[i].name);
        ph.replaceAllUsesWith(fvs[i]);
        ph.getDefiningOp()->erase();
        bindTo(ns, h.fs[i].name, fvs[i]);
      }
    }
    if (mode != Mode::Show && ns.rows.second() != h.fs.size() + !h.arg.isNull())
      error("internal error: the heads of a formals list are not its formals", pos);
    expectChar(':');
  }

  void validate(Hdr &h, Pos pos) {
    auto &fs = h.fs;
    composite::sortRows(fs.data(), fs.size(), [](const Formal &a, const Formal &b) { return composite::lessChars(a.name.chars(), b.name.chars()); });
    const Formal *dup = nullptr;
    for (size_t i = 0; i + 1 < fs.size(); i++)
      if (fs[i].name == fs[i + 1].name) {
        const Formal *d = &fs[i + 1];
        if (!dup || d->pos.line < dup->pos.line || (d->pos.line == dup->pos.line && d->pos.col < dup->pos.col)) dup = d;
      }
    if (dup) error(composite::cat("duplicate formal function argument '", dup->name.str(), "'"), dup->pos);
    if (!h.arg.isNull())
      for (auto &f : fs)
        if (f.name == h.arg) error(composite::cat("duplicate formal function argument '", h.arg.str(), "'"), pos);
  }

  //===--------------------------------------------------------------------===//
  // Operators, application, selection
  //===--------------------------------------------------------------------===//

  Node parseIf() {
    if (cur().t == T_IF) {
      Pos pos = take().pos;
      Node c = parseExpr();
      expect(T_THEN, "'then'");
      Node t = parseExpr();
      expect(T_ELSE, "'else'");
      Node e = parseExpr();
      if (mode == Mode::Show) return text(composite::cat("(if ", txt(c), " then ", txt(t), " else ", txt(e), ")"), K_EXPR, pos);
      if (mode == Mode::Skip) return mk(K_EXPR, pos);
      Value cv = val(c), tv = val(t), ev = val(e);
      return mk(K_EXPR, pos, nd::IfOp::create(b, noLoc(), valTy(), cv, tv, ev, at(pos)));
    }
    Node lhs = parseOp(0);
    if (cur().t == T_PIPE_INTO) {
      while (cur().t == T_PIPE_INTO) {
        Pos p = take().pos;
        Node rhs = parseOp(0);
        lhs = call(p, rhs, llvm::MutableArrayRef<Node>(lhs));
      }
      if (cur().t == T_PIPE_FROM) unexpected();
      return lhs;
    }
    if (cur().t == T_PIPE_FROM) {
      Pos p = take().pos;
      Node rhs = parseIfPipeFromRhs();
      return call(p, lhs, llvm::MutableArrayRef<Node>(rhs));
    }
    return lhs;
  }
  Node parseIfPipeFromRhs() {
    Node lhs = parseOp(0);
    if (cur().t == T_PIPE_FROM) {
      Pos p = take().pos;
      Node rhs = parseIfPipeFromRhs();
      return call(p, lhs, llvm::MutableArrayRef<Node>(rhs));
    }
    if (cur().t == T_PIPE_INTO) unexpected();
    return lhs;
  }

  // Precedence levels (higher binds tighter).
  enum { P_IMPL = 1, P_OR, P_AND, P_EQ, P_CMP, P_UPDATE, P_NOT, P_ADD, P_MUL, P_CONCAT, P_HAS, P_NEG };

  /// The binary operators: the token, its level, its associativity, and what it lowers to: `bin` (a nix.* op of its own), a call of `fn`
  /// (arguments swapped, result negated: `a <= b` is `!(b < a)`), or, with neither, a concatenation of strings or paths.
  struct BinOp {
    Tok t;
    char ch;
    int prec;
    bool right, non;
    int bin;
    const char *fn;
    bool swap, neg;
  };
  static constexpr int kCall = -1, kConcat = -2;
  static constexpr BinOp kBinOps[] = {
      {T_IMPL, 0, P_IMPL, true, false, B_IMPL, nullptr, false, false}, {T_OR, 0, P_OR, false, false, B_OR, nullptr, false, false},
      {T_AND, 0, P_AND, false, false, B_AND, nullptr, false, false},   {T_EQ, 0, P_EQ, false, true, B_EQ, nullptr, false, false},
      {T_NEQ, 0, P_EQ, false, true, B_NEQ, nullptr, false, false},     {T_UPDATE, 0, P_UPDATE, true, false, B_UPDATE, nullptr, false, false},
      {T_CONCAT, 0, P_CONCAT, true, false, B_CONCAT, nullptr, false, false},
      {T_LEQ, 0, P_CMP, false, true, kCall, "__lessThan", true, true}, {T_GEQ, 0, P_CMP, false, true, kCall, "__lessThan", false, true},
      {T_CHAR, '<', P_CMP, false, true, kCall, "__lessThan", false, false}, {T_CHAR, '>', P_CMP, false, true, kCall, "__lessThan", true, false},
      {T_CHAR, '+', P_ADD, false, false, kConcat, nullptr, false, false},  {T_CHAR, '-', P_ADD, false, false, kCall, "__sub", false, false},
      {T_CHAR, '*', P_MUL, false, false, kCall, "__mul", false, false},    {T_CHAR, '/', P_MUL, false, false, kCall, "__div", false, false},
      {T_CHAR, '?', P_HAS, false, true, kCall, nullptr, false, false}};

  const BinOp *binOp(const Token &t) {
    for (const BinOp &d : kBinOps)
      if (d.t == t.t && (t.t != T_CHAR || d.ch == t.ch)) return &d;
    return nullptr;
  }

  Node lowerBin(const BinOp &d, Pos p, Node &l, Node &r) {
    if (d.bin == kConcat) {
      Node parts[2] = {std::move(l), std::move(r)};
      return concat(p, false, parts);
    }
    if (d.bin != kCall) return bin(Bin(d.bin), p, l, r);
    Node c = d.swap ? call2(p, d.fn, r, l) : call2(p, d.fn, l, r);
    return d.neg ? not_(p, std::move(c)) : c;
  }

  Node var(const char *n) { return var(Name::of(n), Pos{}); } // n is a literal: never freed
  Node call2(Pos p, const char *f, Node &a, Node &c) {
    Node fn = var(f);
    Node args[2] = {std::move(a), std::move(c)};
    return call(p, fn, args);
  }

  Node parseOp(int minPrec) {
    Node lhs;
    Pos pos = cur().pos;
    if (atChar('!')) {
      take();
      lhs = not_(pos, parseOp(P_NOT));
    } else if (atChar('-')) {
      take();
      Node zero = intLit(0, Pos{});
      Node e = parseOp(P_NEG);
      lhs = call2(pos, "__sub", zero, e);
    } else {
      lhs = parseApp();
    }
    int lastNonAssoc = -1;
    while (const BinOp *d = binOp(cur())) {
      if (d->prec < minPrec) break;
      if (d->non && d->prec == lastNonAssoc) unexpected();
      Pos opPos = take().pos;
      if (d->prec == P_HAS) {
        Path path = parseAttrPath();
        lhs = hasAttr(opPos, lhs, path);
      } else {
        Node rhs = parseOp(d->right ? d->prec : d->prec + 1);
        lhs = lowerBin(*d, opPos, lhs, rhs);
      }
      lastNonAssoc = d->non ? d->prec : -1;
    }
    return lhs;
  }

  bool startsSelect() {
    const Token &t = cur();
    switch (t.t) {
    case T_ID: case T_INT: case T_FLOAT: case T_IND_STRING_OPEN: case T_PATH:
    case T_HPATH: case T_SPATH: case T_URI: case T_REC:
      return true;
    case T_LET: return isChar(peek(), '{');
    case T_CHAR: return t.ch == '"' || t.ch == '(' || t.ch == '{' || t.ch == '[';
    default: return false;
    }
  }

  Node parseApp() {
    Pos pos = cur().pos;
    Node f = parseSelect();
    if (!startsSelect()) return f;
    llvm::SmallVector<Node, 4> args;
    while (startsSelect()) args.push_back(parseSelect());
    // Upstream's makeCall: an argument after a call is another argument of that call, so `(f a) b` is `f a b`.
    if (f.k == K_CALL) return extend(std::move(f), args);
    return call(pos, f, args);
  }

  Node parseSelect() {
    Pos pos = cur().pos;
    Node e = parseSimple();
    if (atChar('.')) {
      take();
      Path path = parseAttrPath();
      if (cur().t == T_OR_KW) {
        take();
        Node def = parseSelect();
        return select(pos, e, path, &def);
      }
      return select(pos, e, path, nullptr);
    }
    if (cur().t == T_OR_KW) { // "cursed or": `f or` is `f` applied to the variable `or`
      Pos op = take().pos;
      Node orv = var(Name::of("or"), op);
      return call(pos, e, llvm::MutableArrayRef<Node>(orv));
    }
    return e;
  }

  Path parseAttrPath(int64_t into = -1) {
    Path path;
    while (true) {
      if (cur().t == T_ID) path.push_back(Comp{nameOf(take()), {}});
      else if (cur().t == T_OR_KW) { take(); path.push_back(Comp{Name::of("or"), {}}); }
      else if (atChar('"') || cur().t == T_DOLLAR_CURLY) {
        // In a binding of set `into`, a computed component is parsed where the binding's value would be: in the set
        // that the static components before it reach.
        Scope *s0 = sc;
        if (into >= 0) sc = target(uint32_t(into), path).a;
        path.push_back(parseStringAttr());
        sc = s0;
      } else unexpected("identifier or 'or' or '${' or '\"'");
      if (atChar('.')) { take(); continue; }
      break;
    }
    return path;
  }

  Comp parseStringAttr() {
    Node e;
    if (cur().t == T_DOLLAR_CURLY) {
      take();
      e = parseExpr();
      expectChar('}');
      // `${"string"}` is treated as a static attribute name (NixOS/nix#14642).
    } else {
      Pos pos = cur().pos;
      take(); // '"'
      e = parseStringParts(pos);
      expectChar('"');
    }
    if (e.k == K_STR) return Comp{e.text, {}};
    return Comp{Name(), std::move(e)};
  }

  /// string_parts after an opening '"' (mode 0; stops before the closing '"'), an indented string's parts (1) or a
  /// path's (2).  The loops are nixfe_ts_strparts / nixfe_ts_partloop (lowered/nixfe/TextParts.mlir); the grammar
  /// actions are the nixfe_sp_* callbacks below, on a StrParts.
  struct StrParts {
    Parser *p;
    int mode;
    llvm::SmallVector<Node, 4> parts;
    Name single;
    composite::MutableSeries<composite::Join<Token, Node>> ind; // an indented string's parts: its IND_STR token, or the '${' and the expression
  };
  Node parseStringParts(Pos pos) {
    StrParts c{this, 0};
    int64_t k = nixfe_ts_strparts(&c); // 0 the empty literal, 1 c.single, 2 the interpolation of c.parts
    return k == 2 ? concat(pos, true, c.parts) : strLit(k ? c.single : Name::of(""), pos);
  }

  Node parseSimple() {
    const Token &t = cur();
    Pos pos = t.pos;
    switch (t.t) {
    case T_ID: {
      Name n = nameOf(take());
      if (n.str() != "__curPos") return var(n, pos);
      if (mode == Mode::Show) return text("__curPos", K_EXPR, pos);
      if (mode == Mode::Skip) return mk(K_EXPR, pos);
      if (origin->path.empty()) return mk(K_EXPR, pos, baseRef("null"));
      llvm::SmallVector<Name> names{Name::persist("column"), Name::persist("file"), Name::persist("line")};
      llvm::SmallVector<Value> vals{nd::IntOp::create(b, noLoc(), valTy(), b.getI64IntegerAttr(pos.col)),
                                    str(Name::persist(origin->path)),
                                    nd::IntOp::create(b, noLoc(), valTy(), b.getI64IntegerAttr(pos.line))};
      return mk(K_EXPR, pos, nd::AttrsOp::create(b, noLoc(), attrsTy(), names, vals, mlir::ValueRange{}, mlir::ValueRange{},
                                                 llvm::ArrayRef<int64_t>{}, at(pos)));
    }
    case T_INT: return intLit(take().i, pos);
    case T_FLOAT: {
      double f = take().f;
      if (mode == Mode::Show) {
        composite::Text shown;
        printFloat(shown, f);
        return text(composite::mv(shown), K_EXPR, pos);
      }
      return mk(K_EXPR, pos, mode == Mode::Gen ? Value(nd::FloatOp::create(b, noLoc(), valTy(), b.getF64FloatAttr(f))) : Value());
    }
    case T_IND_STRING_OPEN: {
      take();
      StrParts c{this, 1};
      nixfe_ts_partloop(&c);
      return stripIndentation(pos, c.ind);
    }
    case T_PATH:
    case T_HPATH: {
      Token pt = take();
      Node start = makePath(pt);
      if (cur().t == T_PATH_END) { take(); return start; }
      StrParts c{this, 2};
      c.parts.push_back(std::move(start));
      nixfe_ts_partloop(&c);
      return concat(pos, false, c.parts);
    }
    case T_SPATH: {
      Name s = nameOf(take());
      Node fn = var("__findFile");
      Node args[2] = {var("__nixPath"), strLit(Name::of(s.str().substr(1, s.size - 2)), Pos{})}; // between the brackets
      return call(pos, fn, args);
    }
    case T_URI: {
      if (opts.lintUrls != Lint::Ignore) // the message is built only when something will read it
        diagnose(opts.lintUrls, "lint-url-literals",
                 composite::cat("URL literals are ", opts.lintUrls == Lint::Fatal ? "disallowed" : "discouraged",
                                ". Consider using a string literal \"", lx.text(t), "\" instead"),
                 pos);
      return strLit(nameOf(take()), pos);
    }
    case T_LET: { // `let { ... }`: the old syntax, a rec set's `body`
      if (!isChar(peek(), '{')) unexpected();
      take();
      Node a = literal(pos, true, ~0u);
      Path path;
      path.push_back(Comp{Name::of("body"), {}});
      return select(Pos{}, a, path, nullptr);
    }
    case T_REC: {
      uint32_t first = t.offset;
      take();
      return literal(pos, true, first);
    }
    case T_CHAR:
      if (t.ch == '"') {
        take();
        Node e = parseStringParts(pos);
        take();
        return e;
      }
      if (t.ch == '(') {
        if (t.offset == valueAt) valueAt = peek().offset; // a set literal in parentheses is still the binding's value
        take();
        Node e = parseExpr();
        expectChar(')');
        return e;
      }
      if (t.ch == '{') return literal(pos, false, t.offset);
      if (t.ch == '[') {
        take();
        llvm::SmallVector<Node, 8> elems;
        while (!atChar(']')) {
          if (!startsSelect()) unexpected();
          elems.push_back(parseSelect());
        }
        take();
        if (mode == Mode::Show) {
          composite::Text s("[ ");
          for (Node &e : elems) s.put('(').put(txt(e)).put(") ");
          s.put(']');
          return text(composite::mv(s), K_EXPR, pos);
        }
        if (mode == Mode::Skip) return mk(K_EXPR, pos);
        auto vs = llvm::to_vector(elems |α| [&](Node &e) { return val(e); });
        return mk(K_EXPR, pos, nd::ListOp::create(b, noLoc(), listTy(), vs));
      }
      unexpected();
    default:
      unexpected();
    }
  }

  void diagnose(Lint setting, const char *name, composite::Text msg, Pos p) {
    if (setting == Lint::Ignore) return;
    msg.put(" (").put(name).put(')');
    ParseError e(msg, p, origin);
    if (setting == Lint::Fatal) throw e;
    if (opts.onWarning) opts.onWarning(e);
  }

  /// The lint classification, the messages and the home path's text are TextParts.mlir's; canonPath is CanonPath.mlir's.
  Node makePath(const Token &t) {
    std::string_view lit = lx.text(t); // a slice of the input; the messages below copy it, and are built only when linting
    int64_t kind = nixfe_ts_path_kind(t.t == T_HPATH, lit.data(), lit.size()); // 1 home, 2 absolute, 3 short, 0 none
    Lint lint = kind == 3 ? opts.lintShortPaths : opts.lintAbsolutePaths;
    if (kind && lint != Lint::Ignore) {
      composite::Text msg;
      msg.resize(2 * lit.size() + 128);
      msg.truncate(uint32_t(nixfe_ts_path_msg(kind, lit.data(), lit.size(), msg.begin(), msg.size())));
      diagnose(lint, kind == 3 ? "lint-short-path-literals" : "lint-absolute-path-literals", composite::mv(msg), t.pos);
    }
    static thread_local composite::Text path; // the literal's canonical text, written here and copied once (into the arena, or a node)
    path.resize(opts.home.size() + origin->baseDir.size() + lit.size() + 2);
    path.truncate(uint32_t(nixfe_ts_path_text(kind, opts.home.data(), opts.home.size(), origin->baseDir.data(), origin->baseDir.size(),
                                              lit.data(), lit.size(), path.begin(), path.size())));
    Pos pos = kind == 1 ? Pos{} : t.pos;
    if (mode == Mode::Show) return text(path.clone(), K_EXPR, pos);
    return mk(K_EXPR, pos, mode == Mode::Gen ? Value(nd::PathOp::create(b, noLoc(), composite::SeriesType::get(b.getContext(), b.getIntegerType(8)), Name::persist(llvm::StringRef(path.data(), path.size())))) : Value());
  }

  /// The indentation is stripped by nixfe_ts_strip (TextParts.mlir) into `piece`: a record a part (its text, and kind 0
  /// a literal with indent, 1 one without, 2 an antiquotation); it writes each literal's window, empty when dropped.
  Node stripIndentation(Pos pos, composite::MutableSeries<composite::Join<Token, Node>> &es) {
    if (es.empty()) return strLit(Name::of(""), Pos{});
    llvm::SmallVector<uint64_t, 24> recs;
    size_t total = 0;
    for (auto &[t, e] : es) {
      bool lit = t.t != T_DOLLAR_CURLY;
      std::string_view s = lit ? lx.text(t) : std::string_view();
      recs.append({uint64_t(uintptr_t(s.data())), s.size(), lit ? uint64_t(!t.hasIndent) : 2});
      total += s.size();
    }
    llvm::SmallVector<uint64_t, 16> wins(2 * es.size());
    piece.resize(total);
    piece.truncate(uint32_t(nixfe_ts_strip(recs.data(), es.size(), piece.begin(), total, wins.data())));
    llvm::SmallVector<Node, 4> es2;
    size_t k = 0;
    for (auto &[t, e] : es) {
      if (t.t == T_DOLLAR_CURLY) es2.push_back(std::move(e));
      else if (wins[2 * k + 1]) es2.push_back(strLit(Name::persist(llvm::StringRef(piece.data() + wins[2 * k], wins[2 * k + 1])), Pos{}));
      k++;
    }
    if (es2.empty()) return strLit(Name::of(""), Pos{});
    if (es2.size() == 1 && es2[0].k == K_STR) return std::move(es2[0]);
    return concat(pos, true, es2);
  }
};

/// parseStringParts' grammar actions, called back by nixfe_ts_strparts at the points the loop did them.
static Parser::StrParts &sp(void *c) { return *static_cast<Parser::StrParts *>(c); }
extern "C" int64_t nixfe_sp_peek(void *c) { // 0 the text token (T_IND_STR in an indented string), 1 '${', 2 '"', 3 other
  const Token &t = sp(c).p->cur();
  return t.t == (sp(c).mode == 1 ? T_IND_STR : T_STR) ? 0 : t.t == T_DOLLAR_CURLY ? 1 : Parser::isChar(t, '"') ? 2 : 3;
}
extern "C" void nixfe_sp_str(void *c, int64_t push) {
  Token t = sp(c).p->take();
  if (sp(c).mode == 1) return void(sp(c).ind.append(composite::Join<Token, Node>{t, Node{}}));
  sp(c).single = sp(c).p->nameOf(t);
  if (push) sp(c).parts.push_back(sp(c).p->strLit(sp(c).single, Pos{}));
}
extern "C" void nixfe_sp_push(void *c) { sp(c).parts.push_back(sp(c).p->strLit(sp(c).single, Pos{})); }
extern "C" void nixfe_sp_expr(void *c) {
  Token open = sp(c).p->take();
  Node e = sp(c).p->parseExpr();
  sp(c).p->expectChar('}');
  if (sp(c).mode == 1) sp(c).ind.append(composite::Join<Token, Node>{open, std::move(e)});
  else sp(c).parts.push_back(std::move(e));
}
extern "C" void nixfe_sp_close(void *c) {
  Parser &p = *sp(c).p;
  if (sp(c).mode == 0 && !p.atChar('"')) p.unexpected("'\"'");
  if (sp(c).mode == 1 && p.cur().t != T_IND_STRING_CLOSE) p.unexpected("end of an indented string");
  if (sp(c).mode == 2 && p.cur().t != T_PATH_END) p.unexpected();
  if (sp(c).mode) p.take();
}

} // namespace

// nixfe::canonPath's segment walk is hollowed out to MLIR: lowered/nixfe/CanonPath.mlir (trikeshed.at / slice / text /
// drain over the byte series), built into NixFrontend by lib/CMakeLists.txt.  The bridge sizes the Text (a segment writes
// at most its bytes + one '/', and a lone '/' when nothing is written) and adopts the drained size.
extern "C" size_t nixfe_ts_canonpath(const char *a, size_t an, const char *b, size_t bn, char *out, size_t from);

void canonPath(composite::Text &out, composite::Chars a, composite::Chars b) {
  size_t from = out.size();
  out.resize(from + a.size() + b.size() + 1);
  out.truncate(nixfe_ts_canonpath(a.data(), a.size(), b.data(), b.size(), out.begin(), from));
}

composite::Text canonPath(std::string_view path) {
  composite::Text t;
  canonPath(t, composite::chars(path.data(), uint32_t(path.size())));
  return t;
}

/// The fixed buffer of bands and statements, reused from source to source (a pool keeps its own, for its bodies' calls).
static confix::Bands &scratchBands() {
  static thread_local confix::Bands b;
  return b;
}

nd::ExprOp genExpr(mlir::ModuleOp module, Origin *origin, const ParseOptions &po, llvm::StringRef symName,
                   const GenOptions &opts) {
  confix::Bands &bands = opts.pool ? opts.pool->bands : scratchBands();
  bands.clear(origin->text->view());
  return Parser(Mode::Gen, origin, po, &bands, module, &opts).genTop(symName);
}

void mintBody(nd::LambdaOp lam, FilePool &pool, uint32_t row, const GenOptions &opts) {
  Parser(Mode::Gen, pool.origin, pool.opts, &pool.bands, lam->getParentOfType<mlir::ModuleOp>(), &opts).mint(lam, pool, row);
}

void showSource(composite::Text &out, Origin *origin, const ParseOptions &po) {
  confix::Bands &bands = scratchBands(); // the parse checks each statement's end against the scan's (layer 1)
  bands.clear();
  bool scannedOk = confix::scan(origin->text->view(), bands);
  out.put(Parser(Mode::Show, origin, po, scannedOk ? &bands : nullptr).show());
}

void skim(Origin *origin, const ParseOptions &po) {
  confix::Bands &bands = scratchBands();
  bands.clear(origin->text->view());
  Parser(Mode::Skip, origin, po, &bands).top();
}

// lexBands' layering is lowered/nixfe/BandLayers.mlir's: the tokens go in as a word each (kind | ch << 8 | offset << 16),
// the rows {open, close, kind, first, count} and the ends come back in scratch, and are adopted here.  A lex error stops
// the walk where the token loop stopped: before the token whose lookahead failed.
extern "C" int64_t nixfe_lb_layers(const uint64_t *toks, uint64_t n, uint64_t total, uint64_t ebase, uint64_t *rows,
                                   uint64_t *ends, uint64_t *stack, uint64_t *pend, uint64_t *counts);

bool confix::lexBands(Origin *origin, const ParseOptions &opts, confix::Bands &out) {
  composite::MutableSeries<uint64_t> toks;
  bool threw = false;
  try {
    Lexer lx(origin, opts);
    for (Token t = lx.nextToken();; t = lx.nextToken()) {
      toks.append(uint64_t(t.t) | uint64_t(uint8_t(t.ch)) << 8 | uint64_t(t.offset) << 16);
      if (t.t == T_EOF) break;
    }
  } catch (const ParseError &) {
    threw = true;
  }
  size_t n = toks.size(), walk = threw && n ? n - 1 : n;
  composite::MutableSeries<uint64_t> scratch(10 * n + 1, 0);
  uint64_t *rows = scratch.data(), *ends = rows + 5 * n, *stack = ends + n, *pend = stack + 3 * n, counts[2];
  uint32_t base = out.rows.size();
  bool ok = nixfe_lb_layers(toks.data(), walk, n, out.ends.size(), rows, ends, stack, pend, counts);
  for (uint32_t r = 0; r < counts[0]; r++) {
    const uint64_t *w = rows + 5 * r;
    out.rows.append(join::TwInt(uint32_t(w[0]), uint32_t(w[1])), uint8_t(w[2]), join::TwInt(uint32_t(w[3]), uint32_t(w[4])));
    out.opening.try_emplace(uint32_t(w[0]), base + r);
  }
  for (uint64_t e = 0; e < counts[1]; e++) out.ends.append(uint32_t(ends[e]));
  return ok;
}

} // namespace nixfe
