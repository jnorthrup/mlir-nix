//===- Parser.cpp - Nix lexer and parser ----------------------------------===//
//
// The lexer is a faithful hand translation of upstream lexer.l: the same start
// conditions (DEFAULT, STRING, IND_STRING, INPATH, INPATH_SLASH) with the same
// state stack, and flex's longest-match / first-rule tie breaking for the
// DEFAULT state.  Because the lexer's state never depends on the parser, the
// whole input is tokenised up front.
//
// The parser is recursive descent + precedence climbing implementing the same
// grammar, precedences and desugarings as upstream parser.y.
//
//===----------------------------------------------------------------------===//

#include "Composite/Pack.h"
#include "Nix/AST.h"
#include "Nix/Confix.h"
#include "Nix/LexRules.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/Support/xxhash.h"

#include <algorithm>
#include <cassert>
#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <set>
#include <variant>
#include <sstream>

namespace nixfe {

namespace {

enum Tok {
  T_EOF, T_ID, T_INT, T_FLOAT, T_STR, T_IND_STR, T_PATH, T_HPATH, T_SPATH,
  T_URI, T_PATH_END, T_DOLLAR_CURLY, T_IND_STRING_OPEN, T_IND_STRING_CLOSE,
  T_IF, T_THEN, T_ELSE, T_ASSERT, T_WITH, T_LET, T_IN, T_REC, T_INHERIT,
  T_OR_KW, T_ELLIPSIS, T_EQ, T_NEQ, T_LEQ, T_GEQ, T_AND, T_OR, T_IMPL,
  T_UPDATE, T_CONCAT, T_PIPE_FROM, T_PIPE_INTO,
  T_CHAR, // single character token, value in `ch`
};

struct Token {
  Tok t;
  char ch = 0;
  bool hasIndent = false; // IND_STR from the main rule
  bool derived = false;   // the text is not a slice of the input: span.first() indexes the lexer's pool
  join::TwInt span;       // [start, end) of the lexeme in the input: a segment, never a copy
  int64_t i = 0;
  double f = 0;
  Pos pos;
  size_t offset = 0;
};

std::string tokName(const Token &t) {
  switch (t.t) {
  case T_EOF: return "end of file";
  case T_ID: return "identifier";
  case T_INT: return "integer";
  case T_FLOAT: return "floating-point literal";
  case T_STR: return "string";
  case T_IND_STR: return "string";
  case T_PATH: return "path";
  case T_HPATH: return "'~/…' path";
  case T_SPATH: return "'<…>' path";
  case T_URI: return "URI";
  case T_PATH_END: return "end of path";
  case T_DOLLAR_CURLY: return "'${'";
  case T_IND_STRING_OPEN: return "start of an indented string";
  case T_IND_STRING_CLOSE: return "end of an indented string";
  case T_IF: return "'if'";
  case T_THEN: return "'then'";
  case T_ELSE: return "'else'";
  case T_ASSERT: return "'assert'";
  case T_WITH: return "'with'";
  case T_LET: return "'let'";
  case T_IN: return "'in'";
  case T_REC: return "'rec'";
  case T_INHERIT: return "'inherit'";
  case T_OR_KW: return "'or'";
  case T_ELLIPSIS: return "'...'";
  case T_EQ: return "'=='";
  case T_NEQ: return "'!='";
  case T_LEQ: return "'<='";
  case T_GEQ: return "'>='";
  case T_AND: return "'&&'";
  case T_OR: return "'||'";
  case T_IMPL: return "'->'";
  case T_UPDATE: return "'//'";
  case T_CONCAT: return "'++'";
  case T_PIPE_FROM: return "'<|'";
  case T_PIPE_INTO: return "'|>'";
  case T_CHAR:
    if ((unsigned char)t.ch >= 0x80) return "invalid token";
    return std::string("'") + t.ch + "'";
  }
  return "?";
}

using namespace lex; // the character classes and matchers shared with the Confix scan

/// The keyword with exactly this text, else T_ID.  The identifier rule matches every keyword's text, so a keyword is
/// an identifier of the same length (the earlier rule wins the tie) and loses to a longer identifier (`iffy`).
Tok keywordOf(std::string_view w) {
  switch (w.size()) {
  case 2:
    if (w == "if") return T_IF;
    if (w == "in") return T_IN;
    if (w == "or") return T_OR_KW;
    return T_ID;
  case 3:
    if (w == "let") return T_LET;
    if (w == "rec") return T_REC;
    return T_ID;
  case 4:
    if (w == "then") return T_THEN;
    if (w == "else") return T_ELSE;
    if (w == "with") return T_WITH;
    return T_ID;
  case 6: return w == "assert" ? T_ASSERT : T_ID;
  case 7: return w == "inherit" ? T_INHERIT : T_ID;
  default: return T_ID;
  }
}

class Lexer : public lex::Rules {
public:
  Lexer(std::shared_ptr<Origin> o, const ParseOptions &opts)
      : Rules(o->text->view()), origin(std::move(o)), opts(opts), derived{"$", "''", "'", "~/"} {
    if (src.size() >= UINT32_MAX) throw ParseError("input too large (segments are 32-bit)", Pos{1, 1}, origin);
  }

  /// The text of a token: a slice of the input, or an entry of the pool of derived texts.
  std::string_view text(const Token &t) const {
    if (t.derived) return derived[t.span.first()];
    return src.substr(t.span.first(), t.span.second() - t.span.first());
  }

  /// Produce the next token (T_EOF at end, repeatedly).
  Token nextToken() {
    if (stack.empty()) stack.push_back(S_INITIAL);
    Token t;
    if (!next(t)) {
      t = Token();
      t.t = T_EOF;
      t.pos = posAt(src.size());
      t.offset = src.size();
    }
    return t;
  }

  Pos posAt(size_t off) {
    // Positions are computed incrementally (offsets are monotonic).
    while (lineScan < off && lineScan < src.size()) {
      if (src[lineScan] == '\n') { line++; lineStart = lineScan + 1; }
      lineScan++;
    }
    return Pos{line, uint32_t(off - lineStart + 1)};
  }

  [[noreturn]] void error(const std::string &msg, size_t off) {
    throw ParseError(msg, posAt(off), origin);
  }

private:
  enum State { S_INITIAL, S_DEFAULT, S_STRING, S_IND_STRING, S_INPATH, S_INPATH_SLASH };
  std::shared_ptr<Origin> origin;
  const ParseOptions &opts;
  /// Texts that are not slices of the input (unescaped strings, `''$`, ...), appended and never
  /// mutated; the first four are fixed.  Deque: entries do not move.
  std::deque<std::string> derived;
  enum Fixed : uint32_t { F_DOLLAR, F_TWO_QUOTES, F_QUOTE, F_HOME };
  void setSlice(Token &t, size_t from, size_t to) { t.span = join::TwInt(uint32_t(from), uint32_t(to)); }
  void setFixed(Token &t, Fixed f) { t.derived = true; t.span = join::TwInt(uint32_t(f), 0); }
  void setDerived(Token &t, std::string s) {
    derived.push_back(std::move(s));
    t.derived = true;
    t.span = join::TwInt(uint32_t(derived.size() - 1), 0);
  }
  /// A string piece: the slice itself unless it has escapes to resolve.
  void setUnescaped(Token &t, size_t from, size_t to) {
    std::string_view seg = src.substr(from, to - from);
    if (seg.find_first_of("\\\r") == std::string_view::npos) setSlice(t, from, to);
    else setDerived(t, unescapeStr(seg));
  }
  std::vector<State> stack;
  size_t p = 0;
  uint32_t line = 1;
  size_t lineStart = 0, lineScan = 0;

  State top() { return stack.back(); }
  void push(State s) { stack.push_back(s); }
  void pop() { if (stack.size() > 1) stack.pop_back(); }
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
          t.offset = p;
          return true;
        }
        if (s == S_INPATH_SLASH)
          error("path has a trailing slash", p);
        return false;
      }
      t = Token();
      t.offset = p;
      t.pos = posAt(p);
      switch (top()) {
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
      t.offset = p;
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
// Parser
//===----------------------------------------------------------------------===//


class Parser {
public:
  Parser(ExprArena &a, std::shared_ptr<Origin> o, const ParseOptions &opts,
         Lexer &lx)
      : arena(a), origin(std::move(o)), opts(opts), lx(lx) {}

  Expr *parseTop() {
    Expr *e = parseExpr();
    if (cur().t != T_EOF) unexpected("end of file");
    return e;
  }

private:
  ExprArena &arena;
  std::shared_ptr<Origin> origin;
  const ParseOptions &opts;
  Lexer &lx;
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
  std::string str(const Token &t) { return std::string(lx.text(t)); }
  /// The text of a token as a Name: a slice of the input (never freed) unless the text was derived from it.
  Name nameOf(const Token &t) { return t.derived ? Name::persist(lx.text(t)) : Name::of(lx.text(t)); }
  const Token &cur() { if (count == 0) fill(0); return ring[head]; }
  const Token &peek(size_t n = 1) { fill(n); return ring[(head + n) % kLook]; }
  bool isChar(const Token &t, char c) { return t.t == T_CHAR && t.ch == c; }
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
  [[noreturn]] void error(const std::string &msg, Pos p) {
    throw ParseError(msg, p, origin);
  }
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

  std::string fmtPos(Pos p) {
    return origin->name + ":" + std::to_string(p.line) + ":" + std::to_string(p.col);
  }

  // expr: expr_function
  Expr *parseExpr() { return parseFunction(); }

  bool looksLikeFormals() {
    // Called with cur() == '{'.
    const Token &a = peek(1);
    if (a.t == T_ELLIPSIS) return true;
    if (isChar(a, '}')) {
      const Token &b = peek(2);
      return isChar(b, ':') || isChar(b, '@');
    }
    if (a.t == T_ID) {
      const Token &b = peek(2);
      return isChar(b, ',') || isChar(b, '?') ||
             (isChar(b, '}') && (isChar(peek(3), ':') || isChar(peek(3), '@')));
    }
    return false;
  }

  Expr *parseFunction() {
    const Token &t = cur();
    Pos pos = t.pos;
    if (t.t == T_ID && isChar(peek(), ':')) {
      Name arg = nameOf(take());
      take();
      auto *lam = arena.add<ExprLambda>(pos, nullptr);
      lam->arg = arg;
      lam->body = parseFunction();
      return lam;
    }
    if (t.t == T_ID && isChar(peek(), '@') && isChar(peek(2), '{')) {
      Name arg = nameOf(take());
      take();
      auto *lam = arena.add<ExprLambda>(pos, nullptr);
      lam->arg = arg;
      parseFormals(lam);
      validateFormals(lam, pos);
      expectChar(':');
      lam->body = parseFunction();
      return lam;
    }
    if (atChar('{') && looksLikeFormals()) {
      auto *lam = arena.add<ExprLambda>(pos, nullptr);
      parseFormals(lam);
      if (atChar('@')) {
        take();
        if (cur().t != T_ID) unexpected("identifier");
        lam->arg = nameOf(take());
      }
      validateFormals(lam, pos);
      expectChar(':');
      lam->body = parseFunction();
      return lam;
    }
    if (t.t == T_ASSERT) {
      take();
      Expr *c = parseExpr();
      expectChar(';');
      Expr *b = parseFunction();
      return arena.add<ExprAssert>(pos, c, b);
    }
    if (t.t == T_WITH) {
      take();
      Expr *a = parseExpr();
      expectChar(';');
      Expr *b = parseFunction();
      return arena.add<ExprWith>(pos, a, b);
    }
    if (t.t == T_LET && !isChar(peek(), '{')) {
      take();
      ExprAttrs *binds = parseBinds(/*allowEmpty=*/true);
      if (cur().t != T_IN) unexpected("'in'");
      take();
      if (!binds->dynamicAttrs.empty())
        error("dynamic attributes not allowed in let", pos);
      Expr *b = parseFunction();
      return arena.add<ExprLet>(pos, binds, b);
    }
    return parseIf();
  }

  void parseFormals(ExprLambda *lam) {
    lam->hasFormals = true;
    composite::Grow<Formal> formals;
    expectChar('{');
    while (true) {
      if (atChar('}')) { take(); break; }
      if (cur().t == T_ELLIPSIS) {
        take();
        lam->ellipsis = true;
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
      }
      formals.push(arena.region(), f);
      if (atChar(',')) { take(); continue; }
      if (atChar('}')) { take(); break; }
      unexpected();
    }
    lam->formals = formals.done();
  }

  void validateFormals(ExprLambda *lam, Pos pos) {
    const composite::Slice<Formal> &fs = lam->formals;
    auto byName = [](const Formal &a, const Formal &b) { return a.name.str() < b.name.str(); };
    if (fs.size() > 24) {
      std::stable_sort(fs.begin(), fs.end(), byName);
    } else { // insertion: stable, and std::stable_sort allocates a buffer even for two
      for (size_t i = 1; i < fs.size(); i++) {
        Formal f = fs[i];
        size_t j = i;
        for (; j > 0 && byName(f, fs[j - 1]); j--) fs[j] = fs[j - 1];
        fs[j] = f;
      }
    }
    const Formal *dup = nullptr;
    for (size_t i = 0; i + 1 < lam->formals.size(); i++)
      if (lam->formals[i].name == lam->formals[i + 1].name) {
        const Formal *d = &lam->formals[i + 1];
        if (!dup || d->pos.line < dup->pos.line ||
            (d->pos.line == dup->pos.line && d->pos.col < dup->pos.col))
          dup = d;
      }
    if (dup)
      error("duplicate formal function argument '" + dup->name.toString() + "'", dup->pos);
    if (!lam->arg.isNull())
      for (auto &f : lam->formals)
        if (f.name == lam->arg)
          error("duplicate formal function argument '" + lam->arg.toString() + "'", pos);
  }

  Expr *parseIf() {
    if (cur().t == T_IF) {
      Pos pos = take().pos;
      Expr *c = parseExpr();
      expect(T_THEN, "'then'");
      Expr *t = parseExpr();
      expect(T_ELSE, "'else'");
      Expr *e = parseExpr();
      return arena.add<ExprIf>(pos, c, t, e);
    }
    Expr *lhs = parseOp(0);
    if (cur().t == T_PIPE_INTO) {
      while (cur().t == T_PIPE_INTO) {
        Pos p = take().pos;
        Expr *rhs = parseOp(0);
        lhs = arena.add<ExprCall>(p, rhs, arena.slice<Expr *>({lhs}));
      }
      if (cur().t == T_PIPE_FROM) unexpected();
      return lhs;
    }
    if (cur().t == T_PIPE_FROM) {
      Pos p = take().pos;
      Expr *rhs = parseIfPipeFromRhs();
      return arena.add<ExprCall>(p, lhs, arena.slice<Expr *>({rhs}));
    }
    return lhs;
  }
  Expr *parseIfPipeFromRhs() {
    Expr *lhs = parseOp(0);
    if (cur().t == T_PIPE_FROM) {
      Pos p = take().pos;
      Expr *rhs = parseIfPipeFromRhs();
      return arena.add<ExprCall>(p, lhs, arena.slice<Expr *>({rhs}));
    }
    if (cur().t == T_PIPE_INTO) unexpected();
    return lhs;
  }

  // Precedence levels (higher binds tighter).
  enum { P_IMPL = 1, P_OR, P_AND, P_EQ, P_CMP, P_UPDATE, P_NOT, P_ADD, P_MUL, P_CONCAT, P_HAS, P_NEG };

  int binPrec(const Token &t, bool &rightAssoc, bool &nonAssoc) {
    rightAssoc = nonAssoc = false;
    switch (t.t) {
    case T_IMPL: rightAssoc = true; return P_IMPL;
    case T_OR: return P_OR;
    case T_AND: return P_AND;
    case T_EQ: case T_NEQ: nonAssoc = true; return P_EQ;
    case T_LEQ: case T_GEQ: nonAssoc = true; return P_CMP;
    case T_UPDATE: rightAssoc = true; return P_UPDATE;
    case T_CONCAT: rightAssoc = true; return P_CONCAT;
    case T_CHAR:
      switch (t.ch) {
      case '<': case '>': nonAssoc = true; return P_CMP;
      case '+': case '-': return P_ADD;
      case '*': case '/': return P_MUL;
      case '?': nonAssoc = true; return P_HAS;
      }
      return 0;
    default: return 0;
    }
  }

  Expr *var(const char *n) { return arena.add<ExprVar>(Pos{}, Name::of(n)); } // n is a literal: never freed

  Expr *parseOp(int minPrec) {
    Expr *lhs;
    Pos pos = cur().pos;
    if (atChar('!')) {
      take();
      lhs = arena.add<ExprNot>(pos, parseOp(P_NOT));
    } else if (atChar('-')) {
      take();
      Expr *e = parseOp(P_NEG);
      lhs = arena.add<ExprCall>(pos, var("__sub"), arena.slice<Expr *>({arena.add<ExprInt>(0), e}));
    } else {
      lhs = parseApp();
    }
    int lastNonAssoc = -1;
    while (true) {
      bool ra, na;
      int prec = binPrec(cur(), ra, na);
      if (!prec || prec < minPrec) break;
      if (na && prec == lastNonAssoc) unexpected();
      Token op = take();
      Pos opPos = op.pos;
      if (prec == P_HAS) {
        AttrPath path = parseAttrPath();
        lhs = arena.add<ExprHasAttr>(opPos, lhs, path);
        lastNonAssoc = prec;
        continue;
      }
      Expr *rhs = parseOp(ra ? prec : prec + 1);
      switch (op.t) {
      case T_IMPL: lhs = arena.add<ExprBin>(ExprKind::Impl, opPos, lhs, rhs); break;
      case T_OR: lhs = arena.add<ExprBin>(ExprKind::Or, opPos, lhs, rhs); break;
      case T_AND: lhs = arena.add<ExprBin>(ExprKind::And, opPos, lhs, rhs); break;
      case T_EQ: lhs = arena.add<ExprBin>(ExprKind::Eq, opPos, lhs, rhs); break;
      case T_NEQ: lhs = arena.add<ExprBin>(ExprKind::NEq, opPos, lhs, rhs); break;
      case T_LEQ:
        lhs = arena.add<ExprNot>(opPos, arena.add<ExprCall>(opPos, var("__lessThan"), arena.slice<Expr *>({rhs, lhs})));
        break;
      case T_GEQ:
        lhs = arena.add<ExprNot>(opPos, arena.add<ExprCall>(opPos, var("__lessThan"), arena.slice<Expr *>({lhs, rhs})));
        break;
      case T_UPDATE: lhs = arena.add<ExprBin>(ExprKind::Update, opPos, lhs, rhs); break;
      case T_CONCAT: lhs = arena.add<ExprBin>(ExprKind::ConcatLists, opPos, lhs, rhs); break;
      default:
        switch (op.ch) {
        case '<': lhs = arena.add<ExprCall>(opPos, var("__lessThan"), arena.slice<Expr *>({lhs, rhs})); break;
        case '>': lhs = arena.add<ExprCall>(opPos, var("__lessThan"), arena.slice<Expr *>({rhs, lhs})); break;
        case '+': lhs = arena.add<ExprConcatStrings>(opPos, false, arena.slice<StrPart>({{pos, lhs}, {rhs->pos, rhs}})); break;
        case '-': lhs = arena.add<ExprCall>(opPos, var("__sub"), arena.slice<Expr *>({lhs, rhs})); break;
        case '*': lhs = arena.add<ExprCall>(opPos, var("__mul"), arena.slice<Expr *>({lhs, rhs})); break;
        case '/': lhs = arena.add<ExprCall>(opPos, var("__div"), arena.slice<Expr *>({lhs, rhs})); break;
        }
      }
      lastNonAssoc = na ? prec : -1;
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

  Expr *parseApp() {
    Pos pos = cur().pos;
    Expr *f = parseSelect();
    if (!startsSelect()) return f;
    // Upstream's makeCall: an argument after a call is another argument of that call, so `(f a) b` is `f a b`.
    ExprCall *call = f->kind == ExprKind::Call ? static_cast<ExprCall *>(f) : nullptr;
    composite::Grow<Expr *> args;
    if (call) args = composite::Grow<Expr *>::from(arena.region(), call->args, 4);
    while (startsSelect()) args.push(arena.region(), parseSelect());
    if (call) {
      call->args = args.done();
      return call;
    }
    return arena.add<ExprCall>(pos, f, args.done());
  }

  Expr *parseSelect() {
    Pos pos = cur().pos;
    Expr *e = parseSimple();
    if (atChar('.')) {
      take();
      AttrPath path = parseAttrPath();
      Expr *def = nullptr;
      if (cur().t == T_OR_KW) {
        take();
        def = parseSelect();
      }
      return arena.add<ExprSelect>(pos, e, path, def);
    }
    if (cur().t == T_OR_KW) {
      // "cursed or": `f or` is `f` applied to the variable `or`.
      Pos op = take().pos;
      return arena.add<ExprCall>(pos, e, arena.slice<Expr *>({arena.add<ExprVar>(op, Name::of("or"))}));
    }
    return e;
  }

  AttrPath parseAttrPath() {
    composite::Grow<AttrName> path;
    while (true) {
      if (cur().t == T_ID) path.push(arena.region(), AttrName(nameOf(take())));
      else if (cur().t == T_OR_KW) { take(); path.push(arena.region(), AttrName(Name::of("or"))); }
      else if (atChar('"') || cur().t == T_DOLLAR_CURLY) path.push(arena.region(), parseStringAttr());
      else unexpected("identifier or 'or' or '${' or '\"'");
      if (atChar('.')) { take(); continue; }
      break;
    }
    return path.done();
  }

  AttrName parseStringAttr() {
    if (cur().t == T_DOLLAR_CURLY) {
      take();
      Expr *e = parseExpr();
      expectChar('}');
      // `${"string"}` is treated as a static attribute name (NixOS/nix#14642).
      if (e->kind == ExprKind::String) return AttrName(static_cast<ExprString *>(e)->v);
      return AttrName(e);
    }
    Pos pos = cur().pos;
    take(); // '"'
    Expr *e = parseStringParts(pos);
    expectChar('"');
    if (e->kind == ExprKind::String)
      return AttrName(static_cast<ExprString *>(e)->v);
    return AttrName(e);
  }

  /// string_parts after an opening '"'; stops before the closing '"'.
  Expr *parseStringParts(Pos pos) {
    composite::Grow<StrPart> parts;
    bool interpolated = false;
    Name single;
    bool haveSingle = false;
    if (cur().t == T_STR) {
      // The common string: one run of text, then the closing quote.  No parts, and no node but the result.
      Token t = take();
      Name text = nameOf(t);
      if (atChar('"')) {
        auto *s = arena.add<ExprString>(text);
        s->pos = pos;
        return s;
      }
      // Interpolation or more text follows (so the loop below runs, or the string is an error): this is its first part.
      parts.push(arena.region(), StrPart{t.pos, arena.add<ExprString>(text)});
    } else if (atChar('"')) {
      auto *s = arena.add<ExprString>(Name::of(""));
      s->pos = pos;
      return s;
    }
    while (true) {
      if (cur().t == T_STR) {
        Token t = take();
        parts.push(arena.region(), StrPart{t.pos, arena.add<ExprString>(nameOf(t))});
        single = nameOf(t);
        haveSingle = true;
      } else if (cur().t == T_DOLLAR_CURLY) {
        Pos p = take().pos;
        Expr *e = parseExpr();
        expectChar('}');
        parts.push(arena.region(), StrPart{p, e});
        interpolated = true;
      } else {
        break;
      }
    }
    if (!atChar('"')) unexpected("'\"'");
    if (!interpolated) {
      auto *s = arena.add<ExprString>(haveSingle ? single : Name::of(""));
      s->pos = pos;
      return s;
    }
    return arena.add<ExprConcatStrings>(pos, true, parts.done());
  }

  Expr *parseSimple() {
    const Token &t = cur();
    Pos pos = t.pos;
    switch (t.t) {
    case T_ID: {
      Name n = nameOf(take());
      if (n.str() == "__curPos") return arena.add<ExprCurPos>(pos);
      return arena.add<ExprVar>(pos, n);
    }
    case T_INT: { auto *e = arena.add<ExprInt>(take().i); e->pos = pos; return e; }
    case T_FLOAT: { auto *e = arena.add<ExprFloat>(take().f); e->pos = pos; return e; }
    case T_IND_STRING_OPEN: {
      take();
      std::vector<std::pair<Pos, std::variant<Expr *, Token>>> parts;
      while (true) {
        if (cur().t == T_IND_STR) {
          Token tk = take();
          parts.emplace_back(tk.pos, tk);
        } else if (cur().t == T_DOLLAR_CURLY) {
          Pos p = take().pos;
          Expr *e = parseExpr();
          expectChar('}');
          parts.emplace_back(p, e);
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
      Expr *start = makePath(pt);
      if (cur().t == T_PATH_END) { take(); return start; }
      composite::Grow<StrPart> parts;
      parts.push(arena.region(), StrPart{pos, start});
      while (true) {
        if (cur().t == T_STR) {
          Token s = take();
          parts.push(arena.region(), StrPart{s.pos, arena.add<ExprString>(nameOf(s))});
        } else if (cur().t == T_DOLLAR_CURLY) {
          Pos p = take().pos;
          Expr *e = parseExpr();
          expectChar('}');
          parts.push(arena.region(), StrPart{p, e});
        } else {
          break;
        }
      }
      if (cur().t != T_PATH_END) unexpected();
      take();
      return arena.add<ExprConcatStrings>(pos, false, parts.done());
    }
    case T_SPATH: {
      Name s = nameOf(take());
      Name path = Name::of(s.str().substr(1, s.size - 2)); // the text between the angle brackets
      return arena.add<ExprCall>(pos, var("__findFile"), arena.slice<Expr *>({var("__nixPath"), arena.add<ExprString>(path)}));
    }
    case T_URI: {
      if (opts.lintUrls != Lint::Ignore) // the message is built only when something will read it
        diagnose(opts.lintUrls, "lint-url-literals",
                 std::string("URL literals are ") + (opts.lintUrls == Lint::Fatal ? "disallowed" : "discouraged") +
                     ". Consider using a string literal \"" + str(t) + "\" instead", pos);
      auto *e = arena.add<ExprString>(nameOf(take()));
      e->pos = pos;
      return e;
    }
    case T_LET: {
      if (!isChar(peek(), '{')) unexpected();
      take();
      take();
      ExprAttrs *a = parseBinds(true);
      expectChar('}');
      a->recursive = true;
      a->pos = pos;
      return arena.add<ExprSelect>(Pos{}, a, arena.slice<AttrName>({AttrName(Name::of("body"))}), nullptr);
    }
    case T_REC: {
      take();
      expectChar('{');
      ExprAttrs *a = parseBinds(true);
      expectChar('}');
      a->recursive = true;
      a->pos = pos;
      return a;
    }
    case T_CHAR:
      if (t.ch == '"') {
        take();
        Expr *e = parseStringParts(pos);
        take();
        return e;
      }
      if (t.ch == '(') {
        take();
        Expr *e = parseExpr();
        expectChar(')');
        return e;
      }
      if (t.ch == '{') {
        take();
        ExprAttrs *a = parseBinds(true);
        expectChar('}');
        a->pos = pos;
        return a;
      }
      if (t.ch == '[') {
        take();
        auto *l = arena.add<ExprList>(pos);
        composite::Grow<Expr *> elems;
        while (!atChar(']')) {
          if (!startsSelect()) unexpected();
          elems.push(arena.region(), parseSelect());
        }
        take();
        l->elems = elems.done();
        return l;
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

  Expr *makePath(const Token &t) {
    std::string_view lit = lx.text(t); // a slice of the input; the messages below copy it, and are built only when linting
    if (t.t == T_HPATH) {
      if (opts.lintAbsolutePaths != Lint::Ignore)
        diagnose(opts.lintAbsolutePaths, "lint-absolute-path-literals",
                 "home path literals are not portable. Consider replacing path literal '" + std::string(lit) +
                     "' by a string, relative path, or parameter", t.pos);
    } else if (lit[0] == '/') {
      if (opts.lintAbsolutePaths != Lint::Ignore)
        diagnose(opts.lintAbsolutePaths, "lint-absolute-path-literals",
                 "absolute path literals are not portable. Consider replacing path literal '" + std::string(lit) +
                     "' by a string, relative path, or parameter", t.pos);
    } else if (lit[0] != '.') {
      if (opts.lintShortPaths != Lint::Ignore)
        diagnose(opts.lintShortPaths, "lint-short-path-literals",
                 "relative path literal '" + std::string(lit) + "' should be prefixed with '.' for clarity: './" +
                     std::string(lit) + "'", t.pos);
    }
    if (t.t == T_HPATH) {
      std::string path = opts.home + std::string(lit.substr(1));
      return arena.add<ExprPath>(Name::persist(path));
    }
    std::string path;
    if (lit[0] == '/') path = canonPath(lit);
    else path = canonPath(origin->baseDir + "/" + std::string(lit));
    if (lit.size() > 1 && lit.back() == '/') path += '/';
    auto *e = arena.add<ExprPath>(Name::persist(path));
    e->pos = t.pos;
    return e;
  }

  Expr *stripIndentation(Pos pos, std::vector<std::pair<Pos, std::variant<Expr *, Token>>> &es) {
    if (es.empty()) return arena.add<ExprString>(Name::of(""));
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
    composite::Grow<StrPart> es2;
    atStartOfLine = true;
    size_t curDropped = 0;
    size_t n = es.size();
    for (auto it = es.begin(); it != es.end(); ++it, --n) {
      if (auto *e = std::get_if<Expr *>(&it->second)) {
        atStartOfLine = false;
        curDropped = 0;
        es2.push(arena.region(), StrPart{it->first, *e});
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
        if (p != std::string::npos && s2.find_first_not_of(' ', p + 1) == std::string::npos)
          s2 = s2.substr(0, p + 1);
      }
      if (!s2.empty()) es2.push(arena.region(), StrPart{it->first, arena.add<ExprString>(Name::persist(s2))});
    }
    if (es2.empty()) return arena.add<ExprString>(Name::of(""));
    if (es2.size() == 1 && es2[0].e->kind == ExprKind::String) return es2[0].e;
    return arena.add<ExprConcatStrings>(pos, true, es2.done());
  }

  // binds: sequence of `attrpath = expr;` / `inherit ...;`
  ExprAttrs *parseBinds(bool allowEmpty) {
    auto *attrs = arena.add<ExprAttrs>();
    while (true) {
      if (cur().t == T_INHERIT) {
        Pos ipos = take().pos;
        (void)ipos;
        Expr *from = nullptr;
        ExprInheritFrom *fromRef = nullptr;
        if (atChar('(')) {
          take();
          from = parseExpr();
          expectChar(')');
          attrs->inheritFromExprs.push(arena.region(), from);
          fromRef = arena.add<ExprInheritFrom>(from->pos, attrs->inheritFromExprs.size() - 1);
        }
        while (!atChar(';')) {
          Pos apos = cur().pos;
          Name name;
          if (cur().t == T_ID) name = nameOf(take());
          else if (cur().t == T_OR_KW) { take(); name = Name::of("or"); }
          else if (atChar('"') || cur().t == T_DOLLAR_CURLY) {
            AttrName an = parseStringAttr();
            if (an.computed()) error("dynamic attributes not allowed in inherit", apos);
            name = an.symbol;
          } else {
            unexpected();
          }
          if (Entry *prev = findAttr(attrs, name))
            error("attribute '" + displayName(name.str()) + "' already defined at " + fmtPos(prev->def.pos), apos);
          ExprAttrs::AttrDef def;
          def.pos = apos;
          if (fromRef) {
            def.e = arena.add<ExprSelect>(apos, fromRef, arena.slice<AttrName>({AttrName(name)}), nullptr);
            def.kind = ExprAttrs::DefKind::InheritedFrom;
          } else {
            def.e = arena.add<ExprVar>(apos, name);
            def.kind = ExprAttrs::DefKind::Inherited;
          }
          appendAttr(attrs, name, def);
        }
        take();
        continue;
      }
      if (cur().t == T_ID || cur().t == T_OR_KW || atChar('"') || cur().t == T_DOLLAR_CURLY) {
        Pos apos = cur().pos;
        AttrPath path = parseAttrPath();
        expectChar('=');
        Expr *e = parseExpr();
        expectChar(';');
        addAttr(attrs, path, apos, e);
        continue;
      }
      break;
    }
    (void)allowEmpty;
    return attrs;
  }

  std::string displayName(std::string_view s) {
    std::ostringstream os;
    printIdentifier(os, s);
    return os.str();
  }

  std::string showPath(llvm::ArrayRef<AttrName> path) {
    std::ostringstream os;
    bool first = true;
    for (auto &a : path) {
      if (!first) os << '.';
      first = false;
      if (!a.computed()) printIdentifier(os, a.symbol.str());
      else { os << "\"${"; showExpr(os, a.expr); os << "}\""; }
    }
    return os.str();
  }

  void dupAttr(llvm::ArrayRef<AttrName> path, Pos pos, Pos prev) {
    error("attribute '" + showPath(path) + "' already defined at " + fmtPos(prev), pos);
  }

  // The attributes of a set while it is being parsed (ExprAttrs::written).  A set of a handful is searched by comparing;
  // a larger one has an index of its own, open addressing over the positions in `written`.
  using Entry = ExprAttrs::Entry;
  static constexpr uint32_t kScan = 8;

  static bool sameName(const Name &a, const Name &b) {
    return a.size == b.size && (a.size == 0 || std::memcmp(a.data, b.data, a.size) == 0);
  }
  static uint32_t hashOf(const Name &n) {
    return static_cast<uint32_t>(llvm::xxh3_64bits(llvm::ArrayRef<uint8_t>(reinterpret_cast<const uint8_t *>(n.data), n.size)));
  }

  Entry *findAttr(ExprAttrs *a, const Name &n) {
    if (!a->index) {
      for (Entry &e : a->written)
        if (sameName(e.name, n)) return &e;
      return nullptr;
    }
    for (uint32_t h = hashOf(n) & a->indexMask;; h = (h + 1) & a->indexMask) {
      uint32_t k = a->index[h];
      if (!k) return nullptr;
      Entry &e = a->written[k - 1];
      if (sameName(e.name, n)) return &e;
    }
  }

  void indexEntry(ExprAttrs *a, uint32_t k) { // k: the position in `written`, plus one
    uint32_t h = hashOf(a->written[k - 1].name) & a->indexMask;
    while (a->index[h]) h = (h + 1) & a->indexMask;
    a->index[h] = k;
  }

  void buildIndex(ExprAttrs *a) {
    uint32_t count = a->written.size(), cap = 32;
    while (cap < count * 4) cap *= 2; // at most a quarter full when built, a half before it is built again
    a->index = arena.region().Allocate<uint32_t>(cap);
    std::memset(a->index, 0, cap * sizeof(uint32_t));
    a->indexMask = cap - 1;
    for (uint32_t k = 1; k <= count; k++) indexEntry(a, k);
  }

  /// Add an attribute that the set does not have.
  void appendAttr(ExprAttrs *a, const Name &n, ExprAttrs::AttrDef def) {
    a->written.push(arena.region(), Entry{n, def});
    uint32_t count = a->written.size();
    a->ordered = count <= 1;
    if (a->index && count * 2 <= a->indexMask + 1) indexEntry(a, count);
    else if (count > kScan) buildIndex(a);
  }

  void addAttr(ExprAttrs *attrs, AttrPath path, Pos pos, Expr *e) {
    size_t i = 0;
    for (; i + 1 < path.size(); i++) {
      ExprAttrs *nested;
      if (!path[i].computed()) {
        Entry *j = findAttr(attrs, path[i].symbol);
        if (j) {
          nested = j->def.e->kind == ExprKind::Attrs ? static_cast<ExprAttrs *>(j->def.e) : nullptr;
          if (!nested || j->def.kind != ExprAttrs::DefKind::Plain)
            dupAttr(llvm::ArrayRef<AttrName>(path.data(), i + 1), pos, j->def.pos);
        } else {
          nested = arena.add<ExprAttrs>();
          appendAttr(attrs, path[i].symbol, ExprAttrs::AttrDef{nested, pos});
        }
      } else {
        nested = arena.add<ExprAttrs>();
        attrs->dynamicAttrs.push(arena.region(), ExprAttrs::DynamicAttrDef{path[i].expr, nested, pos});
      }
      attrs = nested;
    }
    if (!path[i].computed()) {
      addAttrSym(attrs, llvm::ArrayRef<AttrName>(path.data(), path.size()), path[i].symbol, ExprAttrs::AttrDef{e, pos});
    } else {
      attrs->dynamicAttrs.push(arena.region(), ExprAttrs::DynamicAttrDef{path[i].expr, e, pos});
    }
  }

  void addAttrSym(ExprAttrs *attrs, llvm::ArrayRef<AttrName> path, const Name &sym, ExprAttrs::AttrDef def) {
    Entry *j = findAttr(attrs, sym);
    if (j) {
      auto *ae = def.e->kind == ExprKind::Attrs ? static_cast<ExprAttrs *>(def.e) : nullptr;
      auto *jAttrs = j->def.e->kind == ExprKind::Attrs && j->def.kind == ExprAttrs::DefKind::Plain
                         ? static_cast<ExprAttrs *>(j->def.e) : nullptr;
      if (jAttrs && ae) {
        size_t base = jAttrs->inheritFromExprs.size();
        std::vector<AttrName> full(path.begin(), path.end()); // the path to the merged set, for the messages
        for (const Entry &ad : ae->entries()) { // by name, so the duplicate reported first is the least
          if (ad.def.kind == ExprAttrs::DefKind::InheritedFrom) {
            auto *sel = static_cast<ExprSelect *>(ad.def.e);
            auto *from = static_cast<ExprInheritFrom *>(sel->e);
            from->displ += base;
          }
          full.emplace_back(ad.name);
          addAttrSym(jAttrs, full, ad.name, ad.def);
          full.pop_back();
        }
        ae->written = composite::Grow<Entry>();
        ae->index = nullptr;
        for (auto &d : ae->dynamicAttrs) jAttrs->dynamicAttrs.push(arena.region(), d);
        ae->dynamicAttrs = composite::Grow<ExprAttrs::DynamicAttrDef>();
        for (auto *x : ae->inheritFromExprs) jAttrs->inheritFromExprs.push(arena.region(), x);
        ae->inheritFromExprs = composite::Grow<Expr *>();
      } else {
        dupAttr(path, def.pos, j->def.pos);
      }
    } else {
      if (def.e->kind == ExprKind::Lambda) {
        auto *l = static_cast<ExprLambda *>(def.e);
        if (l->name.isNull()) l->name = sym;
      }
      appendAttr(attrs, sym, def);
    }
  }
};

} // namespace

std::string canonPath(std::string_view path) {
  std::vector<std::string_view> parts;
  size_t i = 0;
  while (i < path.size()) {
    while (i < path.size() && path[i] == '/') i++;
    size_t j = i;
    while (j < path.size() && path[j] != '/') j++;
    std::string_view seg = path.substr(i, j - i);
    i = j;
    if (seg.empty() || seg == ".") continue;
    if (seg == "..") { if (!parts.empty()) parts.pop_back(); continue; }
    parts.push_back(seg);
  }
  if (parts.empty()) return "/";
  std::string out;
  for (auto s : parts) { out += '/'; out += s; }
  return out;
}

Expr *parse(ExprArena &arena, std::shared_ptr<Origin> origin, const ParseOptions &opts) {
  Lexer lx(origin, opts);
  Parser p(arena, origin, opts, lx);
  return p.parseTop();
}

/// The band table from the lexer's tokens: the oracle of confix::scan (Nix/Confix.h).
bool confix::lexBands(std::shared_ptr<Origin> origin, const ParseOptions &opts, confix::Bands &out) {
  try {
    Lexer lx(origin, opts);
    std::vector<uint32_t> open;
    for (;;) {
      Token t = lx.nextToken();
      auto openBand = [&](confix::Kind k) { open.push_back(out.rows.append(join::TwInt(uint32_t(t.offset), 0), k)); };
      auto closeBand = [&](confix::Kind a, confix::Kind b) {
        if (open.empty()) return false;
        uint32_t row = open.back();
        uint8_t k = out.rows.col<1>()[row];
        if (k != a && k != b) return false;
        open.pop_back();
        join::TwInt &sp = out.rows.col<0>()[row];
        sp = join::TwInt(sp.first(), uint32_t(t.offset));
        return true;
      };
      switch (t.t) {
      case T_EOF: return open.empty();
      case T_DOLLAR_CURLY: openBand(confix::K_INTERP); break;
      case T_IND_STRING_OPEN: openBand(confix::K_IND_STRING); break;
      case T_IND_STRING_CLOSE:
        if (!closeBand(confix::K_IND_STRING, confix::K_IND_STRING)) return false;
        break;
      case T_CHAR:
        switch (t.ch) {
        case '{': openBand(confix::K_BRACE); break;
        case '}':
          if (!closeBand(confix::K_BRACE, confix::K_INTERP)) return false;
          break;
        case '(': openBand(confix::K_PAREN); break;
        case ')':
          if (!closeBand(confix::K_PAREN, confix::K_PAREN)) return false;
          break;
        case '[': openBand(confix::K_BRACKET); break;
        case ']':
          if (!closeBand(confix::K_BRACKET, confix::K_BRACKET)) return false;
          break;
        case '"':
          // Inside a string the next quote closes it (an interpolation would have opened a band of its own).
          if (!open.empty() && out.rows.col<1>()[open.back()] == confix::K_STRING) {
            if (!closeBand(confix::K_STRING, confix::K_STRING)) return false;
          } else {
            openBand(confix::K_STRING);
          }
          break;
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
