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

#include <algorithm>
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

bool isPathChar(char c) {
  return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
         (c >= '0' && c <= '9') || c == '.' || c == '_' || c == '-' || c == '+';
}
bool isIdStart(char c) {
  return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
}
bool isIdChar(char c) {
  return isIdStart(c) || (c >= '0' && c <= '9') || c == '\'' || c == '-';
}
bool isDigit(char c) { return c >= '0' && c <= '9'; }
bool isAlpha(char c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'); }
bool isUriChar(char c) {
  return isAlpha(c) || isDigit(c) || strchr("%/?:@&=+$,-_.!~*'", c) != nullptr;
}

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

class Lexer {
public:
  Lexer(std::shared_ptr<Origin> o, const ParseOptions &opts)
      : origin(std::move(o)), src(origin->text->view()), opts(opts), derived{"$", "''", "'", "~/"} {
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
  std::string_view src; // the input, immutable: tokens are segments of it
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
  char at(size_t i) { return i < src.size() ? src[i] : '\0'; }
  bool eof(size_t i) { return i >= src.size(); }

  // -- Matchers returning the match length at position i (0 = no match) ----
  size_t mId(size_t i) {
    if (!isIdStart(at(i)) || eof(i)) return 0;
    size_t j = i + 1;
    while (!eof(j) && isIdChar(src[j])) j++;
    return j - i;
  }
  size_t mInt(size_t i) {
    size_t j = i;
    while (!eof(j) && isDigit(src[j])) j++;
    return j - i;
  }
  size_t mFloat(size_t i) {
    // (([1-9][0-9]*\.[0-9]*)|(0?\.[0-9]+))([Ee][+-]?[0-9]+)?
    size_t best = 0;
    auto exp = [&](size_t j) {
      if (at(j) == 'e' || at(j) == 'E') {
        size_t k = j + 1;
        if (at(k) == '+' || at(k) == '-') k++;
        size_t d = k;
        while (!eof(k) && isDigit(src[k])) k++;
        if (k > d) return k;
      }
      return j;
    };
    if (at(i) >= '1' && at(i) <= '9') {
      size_t j = i + 1;
      while (!eof(j) && isDigit(src[j])) j++;
      if (at(j) == '.') {
        j++;
        while (!eof(j) && isDigit(src[j])) j++;
        best = std::max(best, exp(j) - i);
      }
    }
    {
      size_t j = i;
      if (at(j) == '0') j++;
      if (at(j) == '.' && isDigit(at(j + 1))) {
        j++;
        while (!eof(j) && isDigit(src[j])) j++;
        best = std::max(best, exp(j) - i);
      }
    }
    return best;
  }
  // {PATH_CHAR}*(\/{PATH_CHAR}+)+\/?
  size_t mPath(size_t i) {
    size_t j = i;
    while (!eof(j) && isPathChar(src[j])) j++;
    size_t segs = 0, end = 0;
    while (at(j) == '/' && isPathChar(at(j + 1))) {
      j++;
      while (!eof(j) && isPathChar(src[j])) j++;
      segs++;
      end = j;
    }
    if (!segs) return 0;
    if (at(end) == '/') end++;
    return end - i;
  }
  // {PATH_CHAR}*\/
  size_t mPathSeg(size_t i) {
    size_t j = i;
    while (!eof(j) && isPathChar(src[j])) j++;
    return at(j) == '/' ? j + 1 - i : 0;
  }
  // \~(\/{PATH_CHAR}+)+\/?
  size_t mHPath(size_t i) {
    if (at(i) != '~') return 0;
    size_t j = i + 1, segs = 0, end = 0;
    while (at(j) == '/' && isPathChar(at(j + 1))) {
      j++;
      while (!eof(j) && isPathChar(src[j])) j++;
      segs++;
      end = j;
    }
    if (!segs) return 0;
    if (at(end) == '/') end++;
    return end - i;
  }
  // \<{PATH_CHAR}+(\/{PATH_CHAR}+)*\>
  size_t mSPath(size_t i) {
    if (at(i) != '<') return 0;
    size_t j = i + 1;
    if (!isPathChar(at(j))) return 0;
    while (!eof(j) && isPathChar(src[j])) j++;
    while (at(j) == '/' && isPathChar(at(j + 1))) {
      j++;
      while (!eof(j) && isPathChar(src[j])) j++;
    }
    return at(j) == '>' ? j + 1 - i : 0;
  }
  // [a-zA-Z][a-zA-Z0-9\+\-\.]*\:[uri chars]+
  size_t mUri(size_t i) {
    if (!isAlpha(at(i))) return 0;
    size_t j = i + 1;
    while (!eof(j) && (isAlpha(src[j]) || isDigit(src[j]) || src[j] == '+' ||
                       src[j] == '-' || src[j] == '.'))
      j++;
    if (at(j) != ':') return 0;
    j++;
    size_t s = j;
    while (!eof(j) && isUriChar(src[j])) j++;
    return j > s ? j - i : 0;
  }
  // \/\*([^*]|\*+[^*/])*\*+\/
  size_t mLongComment(size_t i) {
    if (at(i) != '/' || at(i + 1) != '*') return 0;
    size_t j = i + 2;
    while (!eof(j)) {
      if (src[j] == '*') {
        size_t k = j;
        while (at(k) == '*') k++;
        if (at(k) == '/') return k + 1 - i;
        if (eof(k)) return 0;
        j = k + 1;
      } else {
        j++;
      }
    }
    return 0;
  }

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

    // Candidates: (length, rule index).  Earlier rule wins ties.  Every matcher returns 0
    // unless the current character can start it, so only those run.
    struct Cand { size_t len; int rule; };
    Cand best{0, 1000};
    auto consider = [&](size_t len, int rule) {
      if (len > best.len || (len == best.len && len > 0 && rule < best.rule))
        best = {len, rule};
    };
    static constexpr std::string_view kw[] = {"if", "then", "else", "assert", "with", "let", "in", "rec", "inherit", "or"};
    static constexpr Tok kwTok[] = {T_IF, T_THEN, T_ELSE, T_ASSERT, T_WITH, T_LET, T_IN, T_REC, T_INHERIT, T_OR_KW};
    static constexpr std::string_view ops[] = {"...", "==", "!=", "<=", ">=", "&&", "||", "->", "//", "++", "<|", "|>"};
    static constexpr Tok opTok[] = {T_ELLIPSIS, T_EQ, T_NEQ, T_LEQ, T_GEQ, T_AND, T_OR, T_IMPL, T_UPDATE, T_CONCAT, T_PIPE_FROM, T_PIPE_INTO};
    const bool idStart = isIdStart(c), digit = isDigit(c), pathStart = isPathChar(c) || c == '/';
    if (idStart)
      for (int k = 0; k < 10; k++)
        if (kw[k][0] == c && src.compare(i, kw[k].size(), kw[k]) == 0) consider(kw[k].size(), k);
    for (int k = 0; k < 12; k++)
      if (ops[k][0] == c && src.compare(i, ops[k].size(), ops[k]) == 0) consider(ops[k].size(), 10 + k);
    if (idStart) consider(mId(i), 30);
    if (digit) consider(mInt(i), 31);
    if (digit || c == '.') consider(mFloat(i), 32);
    if (c == '$' && at(i + 1) == '{') consider(2, 33);
    if (c == '}') consider(1, 34);
    if (c == '{') consider(1, 35);
    if (c == '"') consider(1, 36);
    if (c == '\'' && at(i + 1) == '\'') {
      size_t j = i + 2;
      while (at(j) == ' ') j++;
      consider(at(j) == '\n' ? j + 1 - i : 2, 37);
    }
    if (pathStart) {
      size_t l = mPathSeg(i);
      if (l && at(i + l) == '$' && at(i + l + 1) == '{') consider(l + 2, 38);
      consider(mPath(i), 39);
    }
    if (c == '~') {
      if (at(i + 1) == '/' && at(i + 2) == '$' && at(i + 3) == '{') consider(4, 38);
      consider(mHPath(i), 40);
    }
    if (c == '<') consider(mSPath(i), 41);
    if (isAlpha(c)) consider(mUri(i), 42);
    if (c == '/') consider(mLongComment(i), 43); // doc comments and long comments
    if (best.len == 0) consider(1, 99);

    size_t len = best.len;
    auto number = [&] { return std::string(src.substr(i, len)); }; // strtoull/strtod need a NUL
    int r = best.rule;
    p = i + len;
    if (r < 10) { t.t = kwTok[r]; return true; }
    if (r < 22) {
      t.t = opTok[r - 10];
      if ((t.t == T_PIPE_FROM || t.t == T_PIPE_INTO) && !opts.pipeOperators)
        error("experimental Nix feature 'pipe-operators' is disabled; add '--extra-experimental-features pipe-operators' to enable it", i);
      return true;
    }
    switch (r) {
    case 30: t.t = T_ID; setSlice(t, i, i + len); return true;
    case 31: {
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
    case 32:
      errno = 0;
      {
        std::string txt = number();
        t.f = strtod(txt.c_str(), nullptr);
        if (errno) error("invalid float '" + txt + "'", i);
      }
      t.t = T_FLOAT;
      return true;
    case 33: push(S_DEFAULT); t.t = T_DOLLAR_CURLY; return true;
    case 34:
      if (top() != S_INITIAL) pop();
      t.t = T_CHAR; t.ch = '}';
      return true;
    case 35: push(S_DEFAULT); t.t = T_CHAR; t.ch = '{'; return true;
    case 36: push(S_STRING); t.t = T_CHAR; t.ch = '"'; return true;
    case 37: push(S_IND_STRING); t.t = T_IND_STRING_OPEN; return true;
    case 38: {
      // PATH_START: re-lex as PATH_SEG / HPATH_START, then INPATH_SLASH.
      if (c == '~') { t.t = T_HPATH; setFixed(t, F_HOME); p = i + 2; }
      else { size_t l = mPathSeg(i); t.t = T_PATH; setSlice(t, i, i + l); p = i + l; }
      push(S_INPATH_SLASH);
      return true;
    }
    case 39:
    case 40:
      setSlice(t, i, i + len);
      push(src[i + len - 1] == '/' ? S_INPATH_SLASH : S_INPATH);
      t.t = r == 39 ? T_PATH : T_HPATH;
      return true;
    case 41: t.t = T_SPATH; setSlice(t, i, i + len); return true;
    case 42: t.t = T_URI; setSlice(t, i, i + len); return true;
    case 43: return false;
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

using StrPart = std::pair<Pos, std::variant<Expr *, Token>>;

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
  std::deque<Token> toks; // lookahead buffer
  bool sawEof = false;

  void fill(size_t n) {
    while (toks.size() <= n) {
      if (sawEof) { toks.push_back(toks.back()); continue; }
      toks.push_back(lx.nextToken());
      if (toks.back().t == T_EOF) sawEof = true;
    }
  }
  std::string str(const Token &t) { return std::string(lx.text(t)); }
  /// The text of a token as a Name: a slice of the input (never freed) unless the text was derived from it.
  Name nameOf(const Token &t) { return t.derived ? Name::persist(lx.text(t)) : Name::of(lx.text(t)); }
  const Token &cur() { fill(0); return toks[0]; }
  const Token &peek(size_t n = 1) { fill(n); return toks[n]; }
  bool isChar(const Token &t, char c) { return t.t == T_CHAR && t.ch == c; }
  bool atChar(char c) { return isChar(cur(), c); }
  Token take() {
    fill(0);
    Token t = toks.front();
    if (t.t != T_EOF) toks.pop_front();
    return t;
  }

  [[noreturn]] void unexpected(const std::string &expecting = "") {
    std::string msg = "syntax error, unexpected " + tokName(cur());
    if (!expecting.empty()) msg += ", expecting " + expecting;
    throw ParseError(msg, cur().pos, origin);
  }
  [[noreturn]] void error(const std::string &msg, Pos p) {
    throw ParseError(msg, p, origin);
  }
  void expectChar(char c, const std::string &expecting = "") {
    if (!atChar(c)) unexpected(expecting.empty() ? std::string("'") + c + "'" : expecting);
    take();
  }
  void expect(Tok t, const std::string &what) {
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
      lam->formals.push_back(f);
      if (atChar(',')) { take(); continue; }
      if (atChar('}')) { take(); break; }
      unexpected();
    }
  }

  void validateFormals(ExprLambda *lam, Pos pos) {
    std::stable_sort(lam->formals.begin(), lam->formals.end(),
                     [](const Formal &a, const Formal &b) { return a.name.str() < b.name.str(); });
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

  Expr *makeCall(Pos p, Expr *fn, Expr *arg) {
    if (fn->kind == ExprKind::Call) {
      auto *c = static_cast<ExprCall *>(fn);
      c->args.push_back(arg);
      return c;
    }
    return arena.add<ExprCall>(p, fn, std::vector<Expr *>{arg});
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
        lhs = arena.add<ExprCall>(p, rhs, std::vector<Expr *>{lhs});
      }
      if (cur().t == T_PIPE_FROM) unexpected();
      return lhs;
    }
    if (cur().t == T_PIPE_FROM) {
      Pos p = take().pos;
      Expr *rhs = parseIfPipeFromRhs();
      return arena.add<ExprCall>(p, lhs, std::vector<Expr *>{rhs});
    }
    return lhs;
  }
  Expr *parseIfPipeFromRhs() {
    Expr *lhs = parseOp(0);
    if (cur().t == T_PIPE_FROM) {
      Pos p = take().pos;
      Expr *rhs = parseIfPipeFromRhs();
      return arena.add<ExprCall>(p, lhs, std::vector<Expr *>{rhs});
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
      lhs = arena.add<ExprCall>(pos, var("__sub"),
                                std::vector<Expr *>{arena.add<ExprInt>(0), e});
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
        lhs = arena.add<ExprHasAttr>(opPos, lhs, std::move(path));
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
        lhs = arena.add<ExprNot>(opPos, arena.add<ExprCall>(opPos, var("__lessThan"), std::vector<Expr *>{rhs, lhs}));
        break;
      case T_GEQ:
        lhs = arena.add<ExprNot>(opPos, arena.add<ExprCall>(opPos, var("__lessThan"), std::vector<Expr *>{lhs, rhs}));
        break;
      case T_UPDATE: lhs = arena.add<ExprBin>(ExprKind::Update, opPos, lhs, rhs); break;
      case T_CONCAT: lhs = arena.add<ExprBin>(ExprKind::ConcatLists, opPos, lhs, rhs); break;
      default:
        switch (op.ch) {
        case '<': lhs = arena.add<ExprCall>(opPos, var("__lessThan"), std::vector<Expr *>{lhs, rhs}); break;
        case '>': lhs = arena.add<ExprCall>(opPos, var("__lessThan"), std::vector<Expr *>{rhs, lhs}); break;
        case '+': {
          std::vector<std::pair<Pos, Expr *>> es{{pos, lhs}, {rhs->pos, rhs}};
          lhs = arena.add<ExprConcatStrings>(opPos, false, std::move(es));
          break;
        }
        case '-': lhs = arena.add<ExprCall>(opPos, var("__sub"), std::vector<Expr *>{lhs, rhs}); break;
        case '*': lhs = arena.add<ExprCall>(opPos, var("__mul"), std::vector<Expr *>{lhs, rhs}); break;
        case '/': lhs = arena.add<ExprCall>(opPos, var("__div"), std::vector<Expr *>{lhs, rhs}); break;
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
    while (startsSelect()) {
      Expr *a = parseSelect();
      f = makeCall(pos, f, a);
    }
    return f;
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
      return arena.add<ExprSelect>(pos, e, std::move(path), def);
    }
    if (cur().t == T_OR_KW) {
      // "cursed or": `f or` is `f` applied to the variable `or`.
      Pos op = take().pos;
      return arena.add<ExprCall>(pos, e, std::vector<Expr *>{arena.add<ExprVar>(op, Name::of("or"))});
    }
    return e;
  }

  AttrPath parseAttrPath() {
    AttrPath path;
    while (true) {
      const std::string expecting = "identifier or 'or' or '${' or '\"'";
      if (cur().t == T_ID) path.emplace_back(nameOf(take()));
      else if (cur().t == T_OR_KW) { take(); path.emplace_back(Name::of("or")); }
      else if (atChar('"') || cur().t == T_DOLLAR_CURLY) path.push_back(parseStringAttr());
      else unexpected(expecting);
      if (atChar('.')) { take(); continue; }
      break;
    }
    return path;
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
    std::vector<std::pair<Pos, Expr *>> parts;
    bool interpolated = false;
    Name single;
    bool haveSingle = false;
    while (true) {
      if (cur().t == T_STR) {
        Token t = take();
        parts.emplace_back(t.pos, arena.add<ExprString>(nameOf(t)));
        single = nameOf(t);
        haveSingle = true;
      } else if (cur().t == T_DOLLAR_CURLY) {
        Pos p = take().pos;
        Expr *e = parseExpr();
        expectChar('}');
        parts.emplace_back(p, e);
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
    return arena.add<ExprConcatStrings>(pos, true, std::move(parts));
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
      std::vector<std::pair<Pos, Expr *>> parts{{pos, start}};
      while (true) {
        if (cur().t == T_STR) {
          Token s = take();
          parts.emplace_back(s.pos, arena.add<ExprString>(nameOf(s)));
        } else if (cur().t == T_DOLLAR_CURLY) {
          Pos p = take().pos;
          Expr *e = parseExpr();
          expectChar('}');
          parts.emplace_back(p, e);
        } else {
          break;
        }
      }
      if (cur().t != T_PATH_END) unexpected();
      take();
      return arena.add<ExprConcatStrings>(pos, false, std::move(parts));
    }
    case T_SPATH: {
      Name s = nameOf(take());
      Name path = Name::of(s.str().substr(1, s.size - 2)); // the text between the angle brackets
      return arena.add<ExprCall>(pos, var("__findFile"),
                                 std::vector<Expr *>{var("__nixPath"), arena.add<ExprString>(path)});
    }
    case T_URI: {
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
      return arena.add<ExprSelect>(Pos{}, a, AttrPath{AttrName(Name::of("body"))}, nullptr);
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
        while (!atChar(']')) {
          if (!startsSelect()) unexpected();
          l->elems.push_back(parseSelect());
        }
        take();
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
    std::string lit = str(t);
    if (t.t == T_HPATH)
      diagnose(opts.lintAbsolutePaths, "lint-absolute-path-literals",
               "home path literals are not portable. Consider replacing path literal '" + lit +
                   "' by a string, relative path, or parameter", t.pos);
    else if (lit[0] == '/')
      diagnose(opts.lintAbsolutePaths, "lint-absolute-path-literals",
               "absolute path literals are not portable. Consider replacing path literal '" + lit +
                   "' by a string, relative path, or parameter", t.pos);
    else if (lit[0] != '.')
      diagnose(opts.lintShortPaths, "lint-short-path-literals",
               "relative path literal '" + lit + "' should be prefixed with '.' for clarity: './" + lit + "'", t.pos);
    if (t.t == T_HPATH) {
      std::string path = opts.home + lit.substr(1);
      return arena.add<ExprPath>(Name::persist(path));
    }
    std::string path;
    if (lit[0] == '/') path = canonPath(lit);
    else path = canonPath(origin->baseDir + "/" + lit);
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
    std::vector<std::pair<Pos, Expr *>> es2;
    atStartOfLine = true;
    size_t curDropped = 0;
    size_t n = es.size();
    for (auto it = es.begin(); it != es.end(); ++it, --n) {
      if (auto *e = std::get_if<Expr *>(&it->second)) {
        atStartOfLine = false;
        curDropped = 0;
        es2.emplace_back(it->first, *e);
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
      if (!s2.empty()) es2.emplace_back(it->first, arena.add<ExprString>(Name::persist(s2)));
    }
    if (es2.empty()) return arena.add<ExprString>(Name::of(""));
    if (es2.size() == 1 && es2[0].second->kind == ExprKind::String) return es2[0].second;
    return arena.add<ExprConcatStrings>(pos, true, std::move(es2));
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
          attrs->inheritFromExprs.push_back(from);
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
          auto it = attrs->attrs.find(name);
          if (it != attrs->attrs.end())
            error("attribute '" + displayName(name.str()) + "' already defined at " + fmtPos(it->second.pos), apos);
          ExprAttrs::AttrDef def;
          def.pos = apos;
          if (fromRef) {
            def.e = arena.add<ExprSelect>(apos, fromRef, AttrPath{AttrName(name)}, nullptr);
            def.kind = ExprAttrs::DefKind::InheritedFrom;
          } else {
            def.e = arena.add<ExprVar>(apos, name);
            def.kind = ExprAttrs::DefKind::Inherited;
          }
          attrs->attrs.emplace(name, def);
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
        addAttr(attrs, std::move(path), apos, e);
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

  std::string showPath(const AttrPath &path) {
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

  void dupAttr(const AttrPath &path, Pos pos, Pos prev) {
    error("attribute '" + showPath(path) + "' already defined at " + fmtPos(prev), pos);
  }

  void addAttr(ExprAttrs *attrs, AttrPath path, Pos pos, Expr *e) {
    size_t i = 0;
    for (; i + 1 < path.size(); i++) {
      ExprAttrs *nested;
      if (!path[i].computed()) {
        auto j = attrs->attrs.find(path[i].symbol);
        if (j != attrs->attrs.end()) {
          nested = j->second.e->kind == ExprKind::Attrs ? static_cast<ExprAttrs *>(j->second.e) : nullptr;
          if (!nested || j->second.kind != ExprAttrs::DefKind::Plain) {
            AttrPath p2(path.begin(), path.begin() + i + 1);
            dupAttr(p2, pos, j->second.pos);
          }
        } else {
          nested = arena.add<ExprAttrs>();
          attrs->attrs[path[i].symbol] = ExprAttrs::AttrDef{nested, pos};
        }
      } else {
        nested = arena.add<ExprAttrs>();
        attrs->dynamicAttrs.push_back({path[i].expr, nested, pos});
      }
      attrs = nested;
    }
    if (!path[i].computed()) {
      addAttrSym(attrs, path, path[i].symbol, ExprAttrs::AttrDef{e, pos});
    } else {
      attrs->dynamicAttrs.push_back({path[i].expr, e, pos});
    }
  }

  void addAttrSym(ExprAttrs *attrs, AttrPath &path, const Name &sym, ExprAttrs::AttrDef def) {
    auto j = attrs->attrs.find(sym);
    if (j != attrs->attrs.end()) {
      auto *ae = def.e->kind == ExprKind::Attrs ? static_cast<ExprAttrs *>(def.e) : nullptr;
      auto *jAttrs = j->second.e->kind == ExprKind::Attrs && j->second.kind == ExprAttrs::DefKind::Plain
                         ? static_cast<ExprAttrs *>(j->second.e) : nullptr;
      if (jAttrs && ae) {
        size_t base = jAttrs->inheritFromExprs.size();
        for (auto &ad : ae->attrs) {
          if (ad.second.kind == ExprAttrs::DefKind::InheritedFrom) {
            auto *sel = static_cast<ExprSelect *>(ad.second.e);
            auto *from = static_cast<ExprInheritFrom *>(sel->e);
            from->displ += base;
          }
          path.emplace_back(ad.first);
          addAttrSym(jAttrs, path, ad.first, ad.second);
          path.pop_back();
        }
        ae->attrs.clear();
        for (auto &d : ae->dynamicAttrs) jAttrs->dynamicAttrs.push_back(d);
        ae->dynamicAttrs.clear();
        for (auto *x : ae->inheritFromExprs) jAttrs->inheritFromExprs.push_back(x);
        ae->inheritFromExprs.clear();
      } else {
        dupAttr(path, def.pos, j->second.pos);
      }
    } else {
      if (def.e->kind == ExprKind::Lambda) {
        auto *l = static_cast<ExprLambda *>(def.e);
        if (l->name.isNull()) l->name = sym;
      }
      attrs->attrs.emplace(sym, def);
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

} // namespace nixfe
