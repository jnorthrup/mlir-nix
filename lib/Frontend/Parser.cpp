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
#include "Nix/Pos.h"
#include "mlir/IR/Builders.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/StringMap.h"
#include "llvm/Support/xxhash.h"

#include <algorithm>
#include <cassert>
#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <map>
#include <optional>
#include <sstream>
#include <variant>

namespace nixfe {
std::unordered_set<std::string> *pathLiterals = nullptr;
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

std::string tokName(const Token &t) {
  if (t.t != T_CHAR) return stringifyTok(t.t).str();
  if ((unsigned char)t.ch >= 0x80) return "invalid token";
  return std::string("'") + t.ch + "'";
}

using namespace lex; // the character classes and matchers shared with the Confix scan

/// The keyword with exactly this text, else T_ID.  The identifier rule matches every keyword's text, so a keyword is
/// an identifier of the same length (the earlier rule wins the tie) and loses to a longer identifier (`iffy`).
Tok keywordOf(std::string_view w) {
  std::optional<Keyword> k = w.size() < 2 || w.size() > 7 ? std::nullopt : symbolizeKeyword(llvm::StringRef(w.data(), w.size()));
  return k ? Tok(uint8_t(*k)) : T_ID;
}

struct Lexer : public lex::Rules {
  Lexer(std::shared_ptr<Origin> o, const ParseOptions &opts)
      : Rules(o->text->view()), origin(std::move(o)), opts(opts) {
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
    stack.assign(1, S_INITIAL);
    if (wantPos && at.valid()) {
      line = at.line;
      lineStart = off - (at.col - 1);
      nextNl = newlineFrom(lineStart);
    }
  }
  /// Every state on the stack is the default one: what follows is not inside a string or a path.
  bool plain() const {
    for (State s : stack)
      if (s != S_INITIAL && s != S_DEFAULT) return false;
    return true;
  }

  /// Produce the next token (T_EOF at end, repeatedly).
  Token nextToken() {
    if (stack.empty()) stack.append(S_INITIAL);
    Token t;
    if (!next(t)) {
      t = Token();
      t.t = T_EOF;
      t.pos = posAt(src.size());
      t.offset = uint32_t(src.size());
    }
    return t;
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
    const void *q = std::memchr(src.data() + from, '\n', src.size() - from);
    return q ? static_cast<size_t>(static_cast<const char *>(q) - src.data()) : src.size();
  }

  [[noreturn]] void error(const std::string &msg, size_t off) {
    throw ParseError(msg, posAt(off), origin);
  }

  enum State { S_INITIAL, S_DEFAULT, S_STRING, S_IND_STRING, S_INPATH, S_INPATH_SLASH };
  std::shared_ptr<Origin> origin;
  const ParseOptions &opts;
  /// Texts that are not slices of the input (unescaped strings, `''$`, ...), appended and never
  /// mutated.  Deque: entries do not move.  The four fixed ones are kFixed (a span of second() 1).
  composite::MutableSeries<std::string, composite::Chunked<std::string>> derived;
  static constexpr std::string_view kFixed[] = {"$", "''", "'", "~/"};
  enum Fixed : uint32_t { F_DOLLAR, F_TWO_QUOTES, F_QUOTE, F_HOME };
  void setSlice(Token &t, size_t from, size_t to) { t.span = join::TwInt(uint32_t(from), uint32_t(to)); }
  void setFixed(Token &t, Fixed f) { t.derived = true; t.span = join::TwInt(uint32_t(f), 1); }
  void setDerived(Token &t, std::string s) {
    derived.append(std::move(s));
    t.derived = true;
    t.span = join::TwInt(uint32_t(derived.size() - 1), 0);
  }
  /// A string piece: the slice itself unless it has escapes to resolve.
  void setUnescaped(Token &t, size_t from, size_t to) {
    std::string_view seg = src.substr(from, to - from);
    if (seg.find_first_of("\\\r") == std::string_view::npos) setSlice(t, from, to);
    else setDerived(t, unescapeStr(seg));
  }
  composite::MutableSeries<State> stack;
  size_t p = 0;
  uint32_t line = 1;
  size_t lineStart = 0;          // the offset where `line` starts
  size_t nextNl = newlineFrom(0); // the first newline at or after lineStart

  State top() { return stack.back(); }
  void push(State s) { stack.append(s); }
  void pop() { if (stack.size() > 1) stack.pop(); }
  static std::string unescapeStr(std::string_view s) {
    std::string t;
    t.reserve(s.size());
    for (size_t i = 0; i < s.size();) {
      char c = s[i++];
      if (c == '\\') {
        c = i < s.size() ? s[i++] : '\0';
        if (c == 'n') t += '\n';
        else if (c == 'r') t += '\r';
        else if (c == 't') t += '\t';
        else t += c;
      } else if (c == '\r') {
        t += '\n';
        if (i < s.size() && s[i] == '\n') i++;
      } else {
        t += c;
      }
    }
    return t;
  }

  void checkNul(std::string_view s, size_t off) {
    if (s.find('\0') != std::string_view::npos)
      error("input string contains NUL byte", off);
  }

  bool next(Token &t) {
    while (true) {
      if (eof(p)) {
        State s = top();
        if (s == S_INPATH) {
          pop();
          t.t = T_PATH_END;
          t.pos = posAt(p);
          t.offset = uint32_t(p);
          return true;
        }
        if (s == S_INPATH_SLASH)
          error("path has a trailing slash", p);
        return false;
      }
      State st = top();
      if (st == S_INITIAL || st == S_DEFAULT) {
        // Between two tokens the commonest things are blanks and `#` comments: one loop, no token made for them.
        size_t q = p, n = src.size();
        for (;;) {
          while (q < n && (src[q] == ' ' || src[q] == '\n' || src[q] == '\t' || src[q] == '\r')) q++;
          if (q < n && src[q] == '#') {
            while (q < n && src[q] != '\n' && src[q] != '\r') q++;
            continue;
          }
          break;
        }
        p = q;
        if (eof(p)) continue; // the end of the input is handled at the top
      }
      t = Token();
      t.offset = uint32_t(p);
      t.pos = posAt(p);
      switch (st) {
      case S_STRING:
        return lexString(t);
      case S_IND_STRING:
        return lexIndString(t);
      case S_INPATH:
      case S_INPATH_SLASH:
        return lexInPath(t);
      default:
        if (lexDefault(t)) return true;
        continue; // whitespace / comment
      }
    }
  }

  bool lexString(Token &t) {
    size_t i = p;
    // ${
    if (at(i) == '$' && at(i + 1) == '{') {
      push(S_DEFAULT);
      p += 2;
      t.t = T_DOLLAR_CURLY;
      return true;
    }
    if (at(i) == '"') {
      pop();
      p++;
      t.t = T_CHAR;
      t.ch = '"';
      return true;
    }
    size_t j = i;
    while (!eof(j)) {
      char c = src[j];
      if (c == '"') break;
      if (c == '\\') {
        if (eof(j + 1)) break;
        j += 2;
        continue;
      }
      if (c == '$') {
        char n = at(j + 1);
        if (eof(j + 1)) break;
        if (n == '{') break;
        if (n == '"') { j++; break; } // trailing-context rule: `$` before `"`
        if (n == '\\') {
          if (eof(j + 2)) break;
          j += 3;
          continue;
        }
        j += 2;
        continue;
      }
      j++;
    }
    if (j == i) {
      // `$`, `\`, `$\` at EOF: return EOF to let the parser fail.
      p = src.size();
      t.t = T_EOF;
      t.pos = posAt(p);
      t.offset = uint32_t(p);
      return true;
    }
    t.t = T_STR;
    setUnescaped(t, i, j);
    checkNul(text(t), i);
    p = j;
    return true;
  }

  bool lexIndString(Token &t) {
    size_t i = p;
    // Main rule: ([^\$\']|\$[^\{\']|\'[^\'\$])+
    size_t j = i;
    while (!eof(j)) {
      char c = src[j];
      if (c != '$' && c != '\'') { j++; continue; }
      if (eof(j + 1)) break;
      char n = src[j + 1];
      if (c == '$' && n != '{' && n != '\'') { j += 2; continue; }
      if (c == '\'' && n != '\'' && n != '$') { j += 2; continue; }
      break;
    }
    if (j > i) {
      t.t = T_IND_STR;
      setSlice(t, i, j);
      t.hasIndent = true;
      checkNul(text(t), i);
      p = j;
      return true;
    }
    if (at(i) == '\'' && at(i + 1) == '\'') {
      if (at(i + 2) == '$') { t.t = T_IND_STR; setFixed(t, F_DOLLAR); p += 3; return true; }
      if (at(i + 2) == '\'') { t.t = T_IND_STR; setFixed(t, F_TWO_QUOTES); p += 3; return true; }
      if (at(i + 2) == '\\' && !eof(i + 3)) {
        t.t = T_IND_STR;
        setDerived(t, unescapeStr(src.substr(i + 2, 2)));
        // `''\` followed by CR LF: unescape handles "\\\r" as '\r' literal;
        // upstream matches exactly one char after the backslash.
        p += 4;
        return true;
      }
      pop();
      p += 2;
      t.t = T_IND_STRING_CLOSE;
      return true;
    }
    if (at(i) == '$' && at(i + 1) == '{') {
      push(S_DEFAULT);
      p += 2;
      t.t = T_DOLLAR_CURLY;
      return true;
    }
    if (at(i) == '$') { t.t = T_IND_STR; setFixed(t, F_DOLLAR); p++; return true; }
    if (at(i) == '\'') { t.t = T_IND_STR; setFixed(t, F_QUOTE); p++; return true; }
    // unreachable
    error("lexer error in indented string", i);
  }

  bool lexInPath(Token &t) {
    size_t i = p;
    if (at(i) == '$' && at(i + 1) == '{') {
      pop();
      push(S_INPATH);
      push(S_DEFAULT);
      p += 2;
      t.t = T_DOLLAR_CURLY;
      return true;
    }
    size_t l = std::max({mPath(i), mPathSeg(i), [&] {
                           size_t j = i;
                           while (!eof(j) && isPathChar(src[j])) j++;
                           return j - i;
                         }()});
    if (l) {
      pop();
      push(src[i + l - 1] == '/' ? S_INPATH_SLASH : S_INPATH);
      t.t = T_STR;
      setSlice(t, i, i + l);
      p += l;
      return true;
    }
    if (top() == S_INPATH_SLASH)
      error("path has a trailing slash", i);
    pop();
    t.t = T_PATH_END;
    return true;
  }

  bool lexDefault(Token &t) {
    size_t i = p;
    char c = at(i);
    // Whitespace and comments.
    if (c == ' ' || c == '\t' || c == '\r' || c == '\n') {
      while (!eof(p) && (src[p] == ' ' || src[p] == '\t' || src[p] == '\r' || src[p] == '\n')) p++;
      return false;
    }
    if (c == '#') {
      while (!eof(p) && src[p] != '\n' && src[p] != '\r') p++;
      return false;
    }

    // Characters that start no rule but the default one: the token is the character.
    switch (c) {
    case '(': case ')': case '[': case ']': case ';': case ',': case '@': case '?': case ':': case '*':
      p = i + 1;
      t.t = T_CHAR;
      t.ch = c;
      return true;
    default:
      break;
    }

    // An identifier or keyword is the commonest token.  Of the rules that can start with an identifier character only
    // a path (a '/' straight after the run of path characters) and a URI (a ':' after the scheme, which is that run)
    // can be longer than the identifier rule's match; when neither follows, no other matcher can fire, so none runs.
    if (isIdStart(c)) {
      size_t j = i + 1;
      while (!eof(j) && isPathChar(src[j])) j++;
      char after = at(j);
      if (after != '/' && after != ':') {
        size_t len = mId(i);
        t.t = keywordOf(src.substr(i, len));
        if (t.t == T_ID) setSlice(t, i, i + len);
        p = i + len;
        return true;
      }
    }

    // The commonest single characters.  Each case below is a character no other rule can continue, and it is the same
    // token matchDefault would return: `{`, `}` and `"` start no rule but their own; `=` is plain unless `==` follows; a
    // space after `-`, `+`, `<`, `>`, `!` leaves no operator (`->`, `++`, `<=`, `<|`, `>=`, `!=`), no path and no <spath>;
    // a `.` is plain unless a digit (float), `.` or `/` (operator, path) follows, or a run of path characters ends in `/`.
    switch (c) {
    case '{': p = i + 1; push(S_DEFAULT); t.t = T_CHAR; t.ch = c; return true;
    case '}': p = i + 1; if (top() != S_INITIAL) pop(); t.t = T_CHAR; t.ch = c; return true;
    case '\"': p = i + 1; push(S_STRING); t.t = T_CHAR; t.ch = c; return true;
    case '=':
      if (at(i + 1) == '=') break;
      p = i + 1; t.t = T_CHAR; t.ch = c; return true;
    case '-': case '+': case '<': case '>': case '!':
      if (at(i + 1) != ' ') break;
      p = i + 1; t.t = T_CHAR; t.ch = c; return true;
    case '.': {
      char n = at(i + 1);
      if (isDigit(n) || n == '.' || n == '/') break;
      if (isPathChar(n)) {
        size_t j = i + 2;
        while (!eof(j) && isPathChar(src[j])) j++;
        if (at(j) == '/') break;
      }
      p = i + 1; t.t = T_CHAR; t.ch = c; return true;
    }
    default:
      break;
    }

    static constexpr Tok kwTok[] = {T_IF, T_THEN, T_ELSE, T_ASSERT, T_WITH, T_LET, T_IN, T_REC, T_INHERIT, T_OR_KW};
    static constexpr Tok opTok[] = {T_ELLIPSIS, T_EQ, T_NEQ, T_LEQ, T_GEQ, T_AND, T_OR, T_IMPL, T_UPDATE, T_CONCAT, T_PIPE_FROM, T_PIPE_INTO};
    lex::Match best = matchDefault(i, c); // the longest rule, the earlier winning a tie (LexRules.h)

    size_t len = best.len;
    auto number = [&] { return std::string(src.substr(i, len)); }; // strtoull/strtod need a NUL
    int r = best.rule;
    p = i + len;
    if (r < lex::R_OPERATOR) { t.t = kwTok[r]; return true; }
    if (r < lex::R_OPERATOR + 12) {
      t.t = opTok[r - lex::R_OPERATOR];
      if ((t.t == T_PIPE_FROM || t.t == T_PIPE_INTO) && !opts.pipeOperators)
        error("experimental Nix feature 'pipe-operators' is disabled; add '--extra-experimental-features pipe-operators' to enable it", i);
      return true;
    }
    switch (r) {
    case lex::R_ID: t.t = T_ID; setSlice(t, i, i + len); return true;
    case lex::R_INT: {
      errno = 0;
      char *end;
      std::string txt = number();
      unsigned long long v = strtoull(txt.c_str(), &end, 10);
      if (errno || v > (unsigned long long)INT64_MAX)
        error("invalid integer '" + txt + "'", i);
      t.t = T_INT;
      t.i = (int64_t)v;
      return true;
    }
    case lex::R_FLOAT:
      errno = 0;
      {
        std::string txt = number();
        t.f = strtod(txt.c_str(), nullptr);
        if (errno) error("invalid float '" + txt + "'", i);
      }
      t.t = T_FLOAT;
      return true;
    case lex::R_DOLLAR_CURLY: push(S_DEFAULT); t.t = T_DOLLAR_CURLY; return true;
    case lex::R_RBRACE:
      if (top() != S_INITIAL) pop();
      t.t = T_CHAR; t.ch = '}';
      return true;
    case lex::R_LBRACE: push(S_DEFAULT); t.t = T_CHAR; t.ch = '{'; return true;
    case lex::R_DQUOTE: push(S_STRING); t.t = T_CHAR; t.ch = '"'; return true;
    case lex::R_IND_OPEN: push(S_IND_STRING); t.t = T_IND_STRING_OPEN; return true;
    case lex::R_PATH_START: {
      // PATH_START: re-lex as PATH_SEG / HPATH_START, then INPATH_SLASH.
      if (c == '~') { t.t = T_HPATH; setFixed(t, F_HOME); p = i + 2; }
      else { size_t l = mPathSeg(i); t.t = T_PATH; setSlice(t, i, i + l); p = i + l; }
      push(S_INPATH_SLASH);
      return true;
    }
    case lex::R_PATH:
    case lex::R_HPATH:
      setSlice(t, i, i + len);
      push(src[i + len - 1] == '/' ? S_INPATH_SLASH : S_INPATH);
      t.t = r == lex::R_PATH ? T_PATH : T_HPATH;
      return true;
    case lex::R_SPATH: t.t = T_SPATH; setSlice(t, i, i + len); return true;
    case lex::R_URI: t.t = T_URI; setSlice(t, i, i + len); return true;
    case lex::R_COMMENT: return false;
    default:
      t.t = T_CHAR;
      t.ch = c;
      return true;
    }
  }
};

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

struct Parser {
  Parser(Mode m, std::shared_ptr<Origin> o, const ParseOptions &po, confix::Bands *bands,
         mlir::ModuleOp module = {}, const GenOptions *go = nullptr)
      : mode(m), origin(std::move(o)), opts(po), lx(origin, opts), bands(bands), module(module),
        b(module ? module.getContext() : nullptr), go(go) {}

  /// The whole source.
  Node top() {
    Node e = parseExpr();
    if (cur().t != T_EOF) unexpected("end of file");
    done();
    return e;
  }
  std::string show() {
    Node e = top();
    return txt(e);
  }

  nd::ExprOp genTop(llvm::StringRef sym) {
    b.setInsertionPointToEnd(module.getBody());
    auto op = nd::ExprOp::create(b, noLoc(), b.getStringAttr(sym),
                                 origin->path.empty() ? mlir::StringAttr() : b.getStringAttr(origin->path),
                                 b.getStringAttr(origin->baseDir));
    topBlock = new mlir::Block();
    op.getBody().push_back(topBlock);
    b.setInsertionPointToEnd(topBlock);
    Value result;
    eagerAt = cur().offset;
    if (go->scoped) { // scope: <expr>, with the scope's names bound lexically
      auto lam = nd::LambdaOp::create(b, noLoc(), valTy(), mlir::ArrayAttr(), mlir::DenseBoolArrayAttr(), false,
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
    mlir::Operation *op = pool.rows.col<PoolCol::Op>()[row];
    uint32_t withs = pool.rows.col<PoolCol::Withs>()[row];
    ::join::TwInt names = pool.rows.col<PoolCol::Names>()[row];
    nixev::RegionInfo *anchor = pool.rows.col<PoolCol::Body>()[row];
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
  std::shared_ptr<Origin> origin;
  const ParseOptions &opts;
  Lexer lx;
  std::optional<Lexer> hl; // the heads': statement starts, read for the names they bind
  confix::Bands *bands; // written as the heads need it: a band is scanned when its names are first read
  mlir::ModuleOp module;
  mlir::OpBuilder b;
  const GenOptions *go;
  mlir::Block *topBlock = nullptr;
  llvm::StringMap<Value> builtinCache;
  Scope *sc = nullptr;                    // where the parse is
  std::optional<ParseError> undefinedErr; // the first undefined variable: upstream reports it once the source parses
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
  composite::MutableSeries<std::string> texts;
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
    std::string msg = "syntax error, unexpected " + tokName(cur());
    if (!expecting.empty()) msg += ", expecting " + std::string(expecting);
    throw ParseError(msg, cur().pos, origin);
  }
  [[noreturn]] void error(const std::string &msg, Pos p) { throw ParseError(msg, p, origin); }
  void expectChar(char c, std::string_view expecting = {}) {
    if (!atChar(c)) {
      if (expecting.empty()) unexpected(std::string("'") + c + "'");
      unexpected(expecting);
    }
    take();
  }
  void expect(Tok t, std::string_view what) {
    if (cur().t != t) unexpected(what);
    take();
  }
  std::string fmtPos(Pos p) { return origin->name + ":" + std::to_string(p.line) + ":" + std::to_string(p.col); }
  void done() {
    if (orphans) error("internal error: a set was given names ahead that no binding gave it", Pos{});
    if (undefinedErr) throw *undefinedErr;
  }

  //===--------------------------------------------------------------------===//
  // Ops (Gen)
  //===--------------------------------------------------------------------===//

  mlir::Type valTy() { return nd::ValueType::get(b.getContext()); }
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
  Value str(Name n) { return nd::StringOp::create(b, noLoc(), valTy(), n); }
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
    if (go->isBaseName && go->isBaseName(n.str())) return baseRef(n.str());
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
    ParseError e("undefined variable '" + n.toString() + "'", p, origin);
    if (minting) throw e;
    if (!undefinedErr) undefinedErr = e;
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
  Node text(std::string s, Kind k, Pos p) {
    Node n = mk(k, p);
    n.shownAt = texts.append(std::move(s));
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
  std::string txt(Node &n) {
    if (n.k == K_SET) {
      std::string s = showSet(n.set);
      n.shownAt = texts.append(std::move(s));
      n.k = K_EXPR;
    }
    return texts[n.shownAt];
  }
  static std::string ident(Name n) {
    std::ostringstream os;
    printIdentifier(os, n.str());
    return os.str();
  }
  std::string showPath(llvm::ArrayRef<Comp> path) {
    std::string s;
    for (const Comp &c : path) {
      if (!s.empty()) s += '.';
      s += c.computed() ? "\"${" + (mode == Mode::Show ? texts[c.expr.shownAt] : std::string()) + "}\"" : ident(c.name);
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
    if (go->isBaseName && go->isBaseName(name)) return mk(K_VAR, p, baseRef(name));
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
      std::string s = "(" + txt(f);
      for (Node &a : args) s += " " + txt(a);
      return text(s + ")", K_CALL, p);
    }
    if (mode == Mode::Skip) return mk(K_CALL, p);
    Value fv = val(f);
    auto av = llvm::to_vector(args |α| [&](Node &a) { return val(a); });
    return mk(K_CALL, p, nd::ApplyOp::create(b, noLoc(), valTy(), fv, av, at(p)));
  }
  /// `(f a) b` is `f a b` (upstream's makeCall): an argument after a call is one more argument of that call.
  Node extend(Node f, llvm::MutableArrayRef<Node> args) {
    if (mode == Mode::Show) {
      std::string s = texts[f.shownAt];
      s.pop_back();
      for (Node &a : args) s += " " + txt(a);
      f.shownAt = texts.append(s + ")");
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
      std::string s = "(" + txt(e) + ")." + showPath(path);
      if (def) s += " or (" + txt(*def) + ")";
      return text(s, K_EXPR, p);
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
      return text("((" + txt(e) + ") ? " + showPath(path) + ")", K_EXPR, p);
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
    if (mode == Mode::Show) return text("(! " + txt(e) + ")", K_EXPR, p);
    if (mode == Mode::Skip) return mk(K_EXPR, p);
    return mk(K_EXPR, p, nd::NotOp::create(b, noLoc(), valTy(), val(e), at(p)));
  }
  enum Bin { B_EQ, B_NEQ, B_AND, B_OR, B_IMPL, B_UPDATE, B_CONCAT };
  Node bin(Bin k, Pos p, Node &l, Node &r) {
    static const char *const ops[] = {"==", "!=", "&&", "||", "->", "//", "++"};
    if (mode == Mode::Show) return text("(" + txt(l) + " " + ops[k] + " " + txt(r) + ")", K_EXPR, p);
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
    case B_UPDATE: v = nd::UpdateOp::create(b, noLoc(), valTy(), a, c, w); break;
    case B_CONCAT: v = nd::ConcatListsOp::create(b, noLoc(), valTy(), a, c, w); break;
    }
    return mk(K_EXPR, p, v);
  }
  Node concat(Pos p, bool forceString, llvm::MutableArrayRef<Node> parts) {
    if (mode == Mode::Show) {
      std::string s = "(";
      for (Node &x : parts) s += (s.size() > 1 ? " + " : "") + txt(x);
      return text(s + ")", K_EXPR, p);
    }
    if (mode == Mode::Skip) return mk(K_EXPR, p);
    auto vs = llvm::to_vector(parts |α| [&](Node &x) { return positioned(val(x), x.pos); });
    return mk(K_EXPR, p, nd::ConcatStringsOp::create(b, noLoc(), valTy(), vs, forceString, at(p)));
  }
  Node intLit(int64_t v, Pos p) {
    if (mode == Mode::Show) return text(std::to_string(v), K_EXPR, p);
    return mk(K_EXPR, p, mode == Mode::Gen ? Value(nd::IntOp::create(b, noLoc(), valTy(), b.getI64IntegerAttr(v))) : Value());
  }
  Node strLit(Name t, Pos p) {
    Node n = mk(K_STR, p);
    n.text = t;
    if (mode == Mode::Show) {
      std::ostringstream os;
      printLiteralString(os, t.str());
      n.shownAt = texts.append(os.str());
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
      hl.emplace(origin, opts);
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
      size_t m = std::min(hd.path.size(), rel.size());
      if (m == 0 || !std::equal(hd.path.begin(), hd.path.begin() + m, rel.begin())) continue;
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
    return a.size == b.size && (a.size == 0 || std::memcmp(a.data, b.data, a.size) == 0);
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
    error("attribute '" + showPath(path) + "' already defined at " + fmtPos(prev), pos);
  }
  /// Where the value of `path = ...;` in set si is parsed, and the set a literal there merges with (NixOS/nix#9020: a
  /// binding that lands in a `rec` set is parsed in its scope).  A path goes through the sets that will be one when
  /// the literals being read merge: at each component, those of si and of what it merges into; the last is the one
  /// the others merge into.
  std::pair<Scope *, Set *> target(uint32_t si, llvm::ArrayRef<Comp> path) {
    llvm::SmallVector<Set *, 4> level, next;
    for (Set *s = &sets[si]; s; s = s->into) level.push_back(s);
    for (const Comp &c : path) {
      next.clear();
      for (Set *s : level)
        if (Def *d = c.computed() ? nullptr : findDef(*s, c.name); d && d->kind == D_PLAIN && d->val.k == K_SET)
          for (Set *t = &sets[d->val.set]; t; t = t->into) next.push_back(t);
      if (next.empty()) return {level.back()->values, nullptr};
      std::swap(level, next);
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
    if (!v) error("internal error: the heads of a set missed '" + n.toString() + "'", Pos{});
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
      r = nd::AttrsOp::create(b, noLoc(), valTy(), names, values, dynNames, dynValues, positions, at(s.pos));
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
      r = nd::AttrsOp::create(b, noLoc(), valTy(), names, finals, dynNames, dynValues, positions, at(s.pos));
      if (ov >= 0) r = nd::UpdateOp::create(b, noLoc(), valTy(), r, finals[ov], at(s.pos));
    }
    release(si);
    return r;
  }
  std::string showSet(uint32_t si) {
    std::string r = sets[si].rec ? "rec { " : "{ ";
    return r + bindings(si) + "}";
  }
  /// The bindings as `--parse` prints them: the inherits, those of each source, the plain ones, the dynamic ones.
  std::string bindings(uint32_t si) {
    Set &s = sets[si];
    order(s);
    std::string r, inherits;
    std::map<uint32_t, std::string> from;
    for (Def &d : s.defs)
      if (d.kind == D_INHERITED) inherits += " " + ident(d.name);
      else if (d.kind == D_FROM) from[d.from] += " " + ident(d.name);
    if (!inherits.empty()) r += "inherit" + inherits + "; ";
    for (auto &[i, names] : from) r += "inherit (" + txt(s.froms[i]) + ")" + names + "; ";
    for (Def &d : s.defs)
      if (d.kind == D_PLAIN) r += ident(d.name) + " = " + txt(d.val) + "; ";
    for (Dyn &d : s.dyns) r += "\"${" + txt(d.name) + "}\" = " + txt(d.val) + "; ";
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
            error("attribute '" + ident(name) + "' already defined at " + fmtPos(prev->pos), apos);
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
      if (mode == Mode::Show) return text("assert " + txt(c) + "; " + txt(body), K_EXPR, pos);
      if (mode == Mode::Skip) return mk(K_EXPR, pos);
      Value cv = val(c), bv = val(body);
      return mk(K_EXPR, pos, nd::AssertOp::create(b, noLoc(), valTy(), cv, bv, b.getStringAttr(shown(c0, cp)), at(pos)));
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
      if (mode == Mode::Show) return text("(with " + txt(a) + "; " + txt(body) + ")", K_EXPR, pos);
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
      std::string head;
      if (mode == Mode::Show) {
        head = "(let " + bindings(si) + "in ";
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
      if (mode == Mode::Show) return text(head + txt(body) + ")", K_EXPR, pos);
      return shared(body, pos);
    }
    return parseIf();
  }

  /// The text `--parse` prints for the expression at `off` (the message of a failed assertion), parsed again.
  std::string shown(uint32_t off, Pos pos) {
    ParseOptions quiet;
    quiet.pipeOperators = opts.pipeOperators;
    quiet.home = opts.home;
    Parser p(Mode::Show, origin, quiet, nullptr);
    p.jump(off, pos);
    Node e = p.parseExpr();
    return p.txt(e);
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
      std::string s = "(";
      if (h.formals) {
        s += "{ ";
        bool first = true;
        for (Formal &f : h.fs) {
          if (!first) s += ", ";
          first = false;
          s += ident(f.name);
          if (f.hasDef) s += " ? " + txt(f.def);
        }
        if (h.ellipsis) s += first ? "..." : ", ...";
        s += " }";
        if (!h.arg.isNull()) s += " @ ";
      }
      if (!h.arg.isNull()) s += ident(h.arg);
      return text(s + ": " + txt(body) + ")", K_LAMBDA, pos);
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
    return nd::LambdaOp::create(b, noLoc(), valTy(), h.formals ? b.getArrayAttr(names) : mlir::ArrayAttr(),
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
    if (dup) error("duplicate formal function argument '" + dup->name.toString() + "'", dup->pos);
    if (!h.arg.isNull())
      for (auto &f : fs)
        if (f.name == h.arg) error("duplicate formal function argument '" + h.arg.toString() + "'", pos);
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
      if (mode == Mode::Show) return text("(if " + txt(c) + " then " + txt(t) + " else " + txt(e) + ")", K_EXPR, pos);
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
        if (into >= 0) sc = target(uint32_t(into), path).first;
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

  /// string_parts after an opening '"'; stops before the closing '"'.
  Node parseStringParts(Pos pos) {
    llvm::SmallVector<Node, 4> parts;
    bool interpolated = false;
    Name single;
    bool haveSingle = false;
    if (cur().t == T_STR) {
      // The common string: one run of text, then the closing quote.  No parts, and no node but the result.
      Token t = take();
      Name s = nameOf(t);
      if (atChar('"')) return strLit(s, pos);
      parts.push_back(strLit(s, Pos{})); // interpolation or more text follows: this is its first part
    } else if (atChar('"')) {
      return strLit(Name::of(""), pos);
    }
    while (true) {
      if (cur().t == T_STR) {
        Token t = take();
        single = nameOf(t);
        haveSingle = true;
        parts.push_back(strLit(single, Pos{}));
      } else if (cur().t == T_DOLLAR_CURLY) {
        take();
        parts.push_back(parseExpr());
        expectChar('}');
        interpolated = true;
      } else {
        break;
      }
    }
    if (!atChar('"')) unexpected("'\"'");
    if (!interpolated) return strLit(haveSingle ? single : Name::of(""), pos);
    return concat(pos, true, parts);
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
      return mk(K_EXPR, pos, nd::AttrsOp::create(b, noLoc(), valTy(), names, vals, mlir::ValueRange{}, mlir::ValueRange{},
                                                 llvm::ArrayRef<int64_t>{}, at(pos)));
    }
    case T_INT: return intLit(take().i, pos);
    case T_FLOAT: {
      double f = take().f;
      if (mode == Mode::Show) {
        std::ostringstream os;
        os << f;
        return text(os.str(), K_EXPR, pos);
      }
      return mk(K_EXPR, pos, mode == Mode::Gen ? Value(nd::FloatOp::create(b, noLoc(), valTy(), b.getF64FloatAttr(f))) : Value());
    }
    case T_IND_STRING_OPEN: {
      take();
      composite::MutableSeries<std::pair<Pos, std::variant<Node, Token>>> parts;
      while (true) {
        if (cur().t == T_IND_STR) {
          Token tk = take();
          parts.emplace(tk.pos, tk);
        } else if (cur().t == T_DOLLAR_CURLY) {
          Pos p = take().pos;
          Node e = parseExpr();
          expectChar('}');
          parts.emplace(p, std::move(e));
        } else {
          break;
        }
      }
      if (cur().t != T_IND_STRING_CLOSE) unexpected("end of an indented string");
      take();
      return stripIndentation(pos, parts);
    }
    case T_PATH:
    case T_HPATH: {
      Token pt = take();
      Node start = makePath(pt);
      if (cur().t == T_PATH_END) { take(); return start; }
      llvm::SmallVector<Node, 4> parts;
      parts.push_back(std::move(start));
      while (true) {
        if (cur().t == T_STR) {
          Token s = take();
          parts.push_back(strLit(nameOf(s), Pos{}));
        } else if (cur().t == T_DOLLAR_CURLY) {
          take();
          parts.push_back(parseExpr());
          expectChar('}');
        } else {
          break;
        }
      }
      if (cur().t != T_PATH_END) unexpected();
      take();
      return concat(pos, false, parts);
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
                 std::string("URL literals are ") + (opts.lintUrls == Lint::Fatal ? "disallowed" : "discouraged") +
                     ". Consider using a string literal \"" + std::string(lx.text(t)) + "\" instead",
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
          std::string s = "[ ";
          for (Node &e : elems) s += "(" + txt(e) + ") ";
          return text(s + "]", K_EXPR, pos);
        }
        if (mode == Mode::Skip) return mk(K_EXPR, pos);
        auto vs = llvm::to_vector(elems |α| [&](Node &e) { return val(e); });
        return mk(K_EXPR, pos, nd::ListOp::create(b, noLoc(), valTy(), vs));
      }
      unexpected();
    default:
      unexpected();
    }
  }

  void diagnose(Lint setting, const char *name, std::string msg, Pos p) {
    if (setting == Lint::Ignore) return;
    msg += std::string(" (") + name + ")";
    ParseError e(msg, p, origin);
    if (setting == Lint::Fatal) throw e;
    if (opts.onWarning) opts.onWarning(e);
  }

  Node makePath(const Token &t) {
    std::string_view lit = lx.text(t); // a slice of the input; the messages below copy it, and are built only when linting
    if (t.t == T_HPATH) {
      if (opts.lintAbsolutePaths != Lint::Ignore)
        diagnose(opts.lintAbsolutePaths, "lint-absolute-path-literals",
                 "home path literals are not portable. Consider replacing path literal '" + std::string(lit) +
                     "' by a string, relative path, or parameter",
                 t.pos);
    } else if (lit[0] == '/') {
      if (opts.lintAbsolutePaths != Lint::Ignore)
        diagnose(opts.lintAbsolutePaths, "lint-absolute-path-literals",
                 "absolute path literals are not portable. Consider replacing path literal '" + std::string(lit) +
                     "' by a string, relative path, or parameter",
                 t.pos);
    } else if (lit[0] != '.') {
      if (opts.lintShortPaths != Lint::Ignore)
        diagnose(opts.lintShortPaths, "lint-short-path-literals",
                 "relative path literal '" + std::string(lit) + "' should be prefixed with '.' for clarity: './" +
                     std::string(lit) + "'",
                 t.pos);
    }
    std::string path;
    Pos pos = t.pos;
    if (t.t == T_HPATH) {
      path = opts.home + std::string(lit.substr(1));
      pos = Pos{};
    } else {
      path = canonPath(lit[0] == '/' ? std::string(lit) : origin->baseDir + "/" + std::string(lit));
      if (lit.size() > 1 && lit.back() == '/') path += '/';
    }
    if (mode == Mode::Show) return text(path, K_EXPR, pos);
    if (pathLiterals && mode == Mode::Gen) pathLiterals->insert(path);
    return mk(K_EXPR, pos, mode == Mode::Gen ? Value(nd::PathOp::create(b, noLoc(), valTy(), Name::persist(path))) : Value());
  }

  Node stripIndentation(Pos pos, composite::MutableSeries<std::pair<Pos, std::variant<Node, Token>>> &es) {
    if (es.empty()) return strLit(Name::of(""), Pos{});
    bool atStartOfLine = true;
    size_t minIndent = 1000000, curIndent = 0;
    for (auto &[p, i] : es) {
      auto *str = std::get_if<Token>(&i);
      if (!str || !str->hasIndent) {
        if (atStartOfLine) {
          atStartOfLine = false;
          if (curIndent < minIndent) minIndent = curIndent;
        }
        continue;
      }
      for (char c : lx.text(*str)) {
        if (atStartOfLine) {
          if (c == ' ') curIndent++;
          else if (c == '\n') curIndent = 0;
          else {
            atStartOfLine = false;
            if (curIndent < minIndent) minIndent = curIndent;
          }
        } else if (c == '\n') {
          atStartOfLine = true;
          curIndent = 0;
        }
      }
    }
    llvm::SmallVector<Node, 4> es2;
    atStartOfLine = true;
    size_t curDropped = 0;
    size_t n = es.size();
    for (auto it = es.begin(); it != es.end(); ++it, --n) {
      if (auto *e = std::get_if<Node>(&it->second)) {
        atStartOfLine = false;
        curDropped = 0;
        es2.push_back(std::move(*e));
        continue;
      }
      const Token &t = std::get<Token>(it->second);
      std::string s2;
      for (char c : lx.text(t)) {
        if (atStartOfLine) {
          if (c == ' ') {
            if (curDropped++ >= minIndent) s2 += c;
          } else if (c == '\n') {
            curDropped = 0;
            s2 += c;
          } else {
            atStartOfLine = false;
            curDropped = 0;
            s2 += c;
          }
        } else {
          s2 += c;
          if (c == '\n') atStartOfLine = true;
        }
      }
      if (n == 1) {
        auto p = s2.find_last_of('\n');
        if (p != std::string::npos && s2.find_first_not_of(' ', p + 1) == std::string::npos) s2 = s2.substr(0, p + 1);
      }
      if (!s2.empty()) es2.push_back(strLit(Name::persist(s2), Pos{}));
    }
    if (es2.empty()) return strLit(Name::of(""), Pos{});
    if (es2.size() == 1 && es2[0].k == K_STR) return std::move(es2[0]);
    return concat(pos, true, es2);
  }
};

} // namespace

std::string canonPath(std::string_view path) {
  composite::MutableSeries<std::string_view> parts;
  size_t i = 0;
  while (i < path.size()) {
    while (i < path.size() && path[i] == '/') i++;
    size_t j = i;
    while (j < path.size() && path[j] != '/') j++;
    std::string_view seg = path.substr(i, j - i);
    i = j;
    if (seg.empty() || seg == ".") continue;
    if (seg == "..") { if (!parts.empty()) parts.pop(); continue; }
    parts.append(seg);
  }
  if (parts.empty()) return "/";
  std::string out;
  for (auto s : parts) { out += '/'; out += s; }
  return out;
}

/// The fixed buffer of bands and statements, reused from source to source (a pool keeps its own, for its bodies' calls).
static confix::Bands &scratchBands() {
  static thread_local confix::Bands b;
  return b;
}

nd::ExprOp genExpr(mlir::ModuleOp module, std::shared_ptr<Origin> origin, const ParseOptions &po, llvm::StringRef symName,
                   const GenOptions &opts) {
  confix::Bands &bands = opts.pool ? opts.pool->bands : scratchBands();
  bands.clear(origin->text->view());
  return Parser(Mode::Gen, origin, po, &bands, module, &opts).genTop(symName);
}

void mintBody(nd::LambdaOp lam, FilePool &pool, uint32_t row, const GenOptions &opts) {
  Parser(Mode::Gen, pool.origin, pool.opts, &pool.bands, lam->getParentOfType<mlir::ModuleOp>(), &opts).mint(lam, pool, row);
}

void showSource(std::ostream &os, std::shared_ptr<Origin> origin, const ParseOptions &po) {
  confix::Bands &bands = scratchBands(); // the parse checks each statement's end against the scan's (layer 1)
  bands.clear();
  bool scannedOk = confix::scan(origin->text->view(), bands);
  os << Parser(Mode::Show, origin, po, scannedOk ? &bands : nullptr).show();
}

void skim(std::shared_ptr<Origin> origin, const ParseOptions &po) {
  confix::Bands &bands = scratchBands();
  bands.clear(origin->text->view());
  Parser(Mode::Skip, origin, po, &bands).top();
}

bool confix::lexBands(std::shared_ptr<Origin> origin, const ParseOptions &opts, confix::Bands &out) {
  try {
    Lexer lx(origin, opts);
    confix::Layers ls(out);
    for (Token t = lx.nextToken(), n;; t = n) {
      n = t.t == T_EOF ? t : lx.nextToken();
      switch (t.t) {
      case T_EOF: return ls.balanced();
      case T_DOLLAR_CURLY: ls.open(confix::K_INTERP, t.offset); break;
      case T_IND_STRING_OPEN: ls.open(confix::K_IND_STRING, t.offset); break;
      case T_IND_STRING_CLOSE:
        if (!ls.close(confix::K_IND_STRING, confix::K_IND_STRING, t.offset)) return false;
        break;
      case T_LET:
        if (!(n.t == T_CHAR && n.ch == '{')) ls.open(confix::K_LET, t.offset);
        break;
      case T_IN:
        if (!ls.close(confix::K_LET, confix::K_LET, t.offset)) return false;
        break;
      case T_WITH: case T_ASSERT: ls.owe(); break;
      case T_CHAR:
        switch (t.ch) {
        case '{': ls.open(confix::K_BRACE, t.offset); break;
        case '}':
          if (!ls.close(confix::K_BRACE, confix::K_INTERP, t.offset)) return false;
          break;
        case '(': ls.open(confix::K_PAREN, t.offset); break;
        case ')':
          if (!ls.close(confix::K_PAREN, confix::K_PAREN, t.offset)) return false;
          break;
        case '[': ls.open(confix::K_BRACKET, t.offset); break;
        case ']':
          if (!ls.close(confix::K_BRACKET, confix::K_BRACKET, t.offset)) return false;
          break;
        case '"':
          // Inside a string the next quote closes it (an interpolation would have opened a band of its own).
          if (ls.inside(confix::K_STRING)) {
            if (!ls.close(confix::K_STRING, confix::K_STRING, t.offset)) return false;
          } else {
            ls.open(confix::K_STRING, t.offset);
          }
          break;
        case ';': ls.semi(t.offset); break;
        case ',': ls.comma(t.offset); break;
        default: break;
        }
        break;
      default: break;
      }
    }
  } catch (const ParseError &) {
    return false;
  }
}

} // namespace nixfe
