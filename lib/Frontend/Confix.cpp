//===- Confix.cpp - The scan of a Nix source's delimiters -----------------===//
//
// The lexer's state machine (Parser.cpp: DEFAULT, STRING, IND_STRING, INPATH, INPATH_SLASH, with the same
// stack) without tokens: only the transitions and the delimiters are kept.  Every decision that is not a
// transition comes from Nix/LexRules.h, the same functions the lexer calls.
//
//===----------------------------------------------------------------------===//

#include "Composite/Series.h"
#include "Nix/Confix.h"
#include "Nix/LexRules.h"

#include <cstring>
#include <vector>

namespace nixfe::confix {

namespace {

using namespace lex;

/// The bytes at which the text of a "..." string stops being plain (`"`, `\`, `$`), and at which an indented string's
/// does (`$`, `'`); a NUL byte is on both lists, because the lexer refuses one in a string.
struct StopTables {
  bool dq[256] = {};
  bool ind[256] = {};
  constexpr StopTables() {
    dq[uint8_t('"')] = dq[uint8_t('\\')] = dq[uint8_t('$')] = dq[0] = true;
    ind[uint8_t('$')] = ind[uint8_t('\'')] = ind[0] = true;
  }
};
constexpr StopTables kStop;

struct Scanner : Rules {
  Scanner(std::string_view s, Bands &b) : Rules(s), bands(b), layers(b) {}

  bool run() {
    if (src.size() >= UINT32_MAX) return false; // segments are 32-bit
    st.assign(1, S_INITIAL);
    const size_t n = src.size();
    bands.rows.reserve(n / 48 + 16); // about one band per 56 bytes of nixpkgs
    for (;;) {
      if (p >= stop && stop < n) return true; // the band a scan from `need` opened has closed
      if (p >= n) {
        // At the end of the input a path ends (the lexer emits its end token), and a path with a trailing slash is an error.
        if (st.back() == S_INPATH) { st.pop(); continue; }
        if (st.back() == S_INPATH_SLASH) return false;
        break;
      }
      bool ok;
      switch (st.back()) {
      case S_STRING: ok = string(); break;
      case S_IND_STRING: ok = indented(); break;
      case S_INPATH:
      case S_INPATH_SLASH: ok = inPath(); break;
      default: ok = deflt(); break;
      }
      if (!ok) return false;
    }
    return st.size() == 1 && layers.balanced();
  }

  enum State : uint8_t { S_INITIAL, S_DEFAULT, S_STRING, S_IND_STRING, S_INPATH, S_INPATH_SLASH };

  Bands &bands;
  Layers layers;              // the open bands, their statements
  composite::MutableSeries<State> st;      // the lexer's state stack
  size_t p = 0;
  size_t stop = src.size();   // where the scan ends: the source's end, or past the band a scan from `need` opened
  bool rooted = false;        // a scan from `need`: it ends where its first band closes

  void openBand(Kind k, size_t at) { layers.open(k, at); }
  bool closeBand(Kind a, Kind b, size_t at) {
    bool ok = layers.close(a, b, at);
    if (ok && rooted && layers.balanced()) stop = at + 1;
    return ok;
  }
  /// An identifier [i, i + len): `with` and `assert` are owed their band's next semicolon; `let` opens a band (unless a
  /// `{` follows: the old `let { ... }`, whose braces are the band) that its `in` closes.
  bool word(size_t i, size_t len) {
    std::string_view w = src.substr(i, len);
    if (w == "with" || w == "assert") layers.owe();
    else if (w == "let" && !braceNext(i + 3)) openBand(K_LET, i);
    else if (w == "in") return closeBand(K_LET, K_LET, i);
    return true;
  }
  /// Whether the next token after `j` (blanks and comments between) is `{`.
  bool braceNext(size_t j) const {
    for (;;) {
      while (j < src.size() && (src[j] == ' ' || src[j] == '\t' || src[j] == '\r' || src[j] == '\n')) j++;
      if (at(j) == '#') {
        while (j < src.size() && src[j] != '\n' && src[j] != '\r') j++;
      } else if (size_t l = mLongComment(j)) {
        j += l;
      } else {
        return at(j) == '{';
      }
    }
  }
  bool inDefault() const { return st.back() <= S_DEFAULT; }

  /// The default state, until the state stack takes a state that is not one of its own.
  ///
  /// Most characters need no rule: a character that cannot begin a token, or whose token cannot hide a delimiter, is
  /// stepped over.  A token can hide a delimiter only if it is a string, a comment, a URI (its characters include
  /// `'`, `$`, `*` and `/`), or a path (it swallows `/`), so the general matcher runs only where one of those could begin.
  /// A path begins at `.`, `-`, `+`, a digit, a letter or `/` and needs a `/` right after its run of path characters; a
  /// URI begins at a letter and needs a `:` there.  Each shortcut below is that argument for one character.
  bool deflt() {
    const char *s = src.data();
    const size_t n = src.size();
    while (p < stop) {
      const size_t i = p;
      const char c = s[i];
      if (isIdStart(c)) {
        // The characters that are both identifier and path characters: letters, digits, `_` and `-`.
        size_t j = i + 1;
        while (j < n && (isIdChar(s[j]) && s[j] != '\'')) j++;
        const char d = j < n ? s[j] : '\0';
        if (d != '.' && d != '+' && d != '\'' && d != '/' && d != ':') { // the identifier, nothing follows it
          if (j - i <= 6 && !word(i, j - i)) return false;
          p = j;
          continue;
        }
        size_t k = j;
        while (k < n && isPathChar(s[k])) k++;
        const char after = k < n ? s[k] : '\0';
        if (after != '/' && after != ':') { // the lexer's own shortcut (see lexDefault)
          const size_t l = mId(i);
          if (l <= 6 && !word(i, l)) return false;
          p = i + l;
          continue;
        }
        // a path or a URI may begin here
      } else {
        switch (c) {
        case ' ': case '\t': case '\r': case '\n':
          p = i + 1;
          while (p < n && (s[p] == ' ' || s[p] == '\t' || s[p] == '\r' || s[p] == '\n')) p++;
          continue;
        case '#':
          p = i + 1;
          while (p < n && s[p] != '\n' && s[p] != '\r') p++;
          continue;
        case '(': openBand(K_PAREN, i); p = i + 1; continue;
        case ')': if (!closeBand(K_PAREN, K_PAREN, i)) return false; p = i + 1; continue;
        case '[': openBand(K_BRACKET, i); p = i + 1; continue;
        case ']': if (!closeBand(K_BRACKET, K_BRACKET, i)) return false; p = i + 1; continue;
        case '{': st.append(S_DEFAULT); openBand(K_BRACE, i); p = i + 1; continue;
        case '}':
          if (st.back() != S_INITIAL) st.pop();
          if (!closeBand(K_BRACE, K_INTERP, i)) return false;
          p = i + 1;
          if (!inDefault()) return true; // the interpolation closed: back in the string or path around it
          continue;
        case '"': st.append(S_STRING); openBand(K_STRING, i); p = i + 1; return true;
        case '$':
          if (at(i + 1) == '{') { st.append(S_DEFAULT); openBand(K_INTERP, i); p = i + 2; continue; }
          p = i + 1;
          continue;
        case '\'':
          if (at(i + 1) == '\'') break; // the opening of an indented string
          p = i + 1;
          continue;
        case ';': layers.semi(i); p = i + 1; continue;
        case ',': layers.comma(i); p = i + 1; continue;
        case '@': case '?': case ':': case '*':
        case '=': case '!': case '&': case '|': case '>': // operators: no character of them begins a path or hides a delimiter
          p = i + 1;
          continue;
        case '<':
          if (isPathChar(at(i + 1))) break; // a search path <nixpkgs>
          p = i + 1;
          continue;
        case '.': case '-': case '+': {
          size_t e = i + 1;
          while (e < n && isPathChar(s[e])) e++;
          if (at(e) == '/') break; // a path
          p = i + 1;               // a selection, a minus, a float's dot: nothing to hide
          continue;
        }
        case '0': case '1': case '2': case '3': case '4': case '5': case '6': case '7': case '8': case '9': {
          size_t e = i + 1;
          while (e < n && isPathChar(s[e])) e++;
          if (at(e) == '/') break; // a path that begins with a digit
          p = i + 1;
          while (p < n && isDigit(s[p])) p++;
          continue;
        }
        case '/': {
          const char nx = at(i + 1);
          if (nx == '/') { p = i + 2; continue; } // the operator `//`, never a comment or a path
          if (nx == '*' || nx == '$' || isPathChar(nx)) break; // a comment, `/${`, an absolute path
          p = i + 1;
          continue;
        }
        case '~': break; // a home path
        default: // a character that begins nothing
          p = i + 1;
          continue;
        }
      }
      // The general case: the lexer's own choice among the rules that can begin here.
      Match m = matchDefault(i, c);
      p = i + m.len;
      if (m.rule >= R_KEYWORD && m.rule < R_OPERATOR && !word(i, m.len)) return false;
      switch (m.rule) {
      case R_DOLLAR_CURLY: st.append(S_DEFAULT); openBand(K_INTERP, i); break;
      case R_RBRACE:
        if (st.back() != S_INITIAL) st.pop();
        if (!closeBand(K_BRACE, K_INTERP, i)) return false;
        if (!inDefault()) return true;
        break;
      case R_LBRACE: st.append(S_DEFAULT); openBand(K_BRACE, i); break;
      case R_DQUOTE: st.append(S_STRING); openBand(K_STRING, i); return true;
      case R_IND_OPEN: st.append(S_IND_STRING); openBand(K_IND_STRING, i); return true;
      case R_PATH_START:
        p = c == '~' ? i + 2 : i + mPathSeg(i);
        st.append(S_INPATH_SLASH);
        return true;
      case R_PATH:
      case R_HPATH:
        st.append(s[i + m.len - 1] == '/' ? S_INPATH_SLASH : S_INPATH);
        return true;
      default: break; // keywords, operators, numbers, search paths, URIs, comments, a character: no transition
      }
    }
    return true;
  }

  /// Inside "...": pieces of text up to a `"` (the end), a `${` (an interpolation), or an escape.
  bool string() {
    const char *s = src.data();
    const size_t n = src.size();
    for (;;) {
      if (p >= n) return false; // not terminated: the lexer returns the end of the input
      const size_t i = p;
      if (s[i] == '$' && at(i + 1) == '{') { st.append(S_DEFAULT); openBand(K_INTERP, i); p = i + 2; return true; }
      if (s[i] == '"') {
        st.pop();
        if (!closeBand(K_STRING, K_STRING, i)) return false;
        p = i + 1;
        return true;
      }
      size_t j = i;
      while (j < n) {
        const char c = s[j];
        if (!kStop.dq[uint8_t(c)]) { j++; continue; }
        if (c == '"') break;
        if (c == '\0') return false; // the lexer refuses a NUL byte in a string
        if (c == '\\') {
          if (j + 1 >= n) break;
          if (s[j + 1] == '\0') return false;
          j += 2;
          continue;
        }
        // c == '$'
        if (j + 1 >= n) break;
        const char next = s[j + 1];
        if (next == '{') break;
        if (next == '"') { j++; break; } // the lexer's trailing-context rule: `$` before `"` belongs to the text
        if (next == '\0') return false;
        if (next == '\\') {
          if (j + 2 >= n) break;
          if (s[j + 2] == '\0') return false;
          j += 3;
          continue;
        }
        j += 2;
      }
      if (j == i) return false; // `$`, `\` or `$\` at the end of the input
      p = j;
    }
  }

  /// Inside ''...'': text, the escapes `''$`, `'''` and `''\x`, an interpolation, or the closing `''`.
  bool indented() {
    const char *s = src.data();
    const size_t n = src.size();
    for (;;) {
      if (p >= n) return false;
      const size_t i = p;
      size_t j = i;
      while (j < n) { // the main rule: ([^\$\']|\$[^\{\']|\'[^\'\$])+
        const char c = s[j];
        if (!kStop.ind[uint8_t(c)]) { j++; continue; }
        if (c == '\0') return false; // the lexer refuses a NUL byte in a string
        if (j + 1 >= n) break;
        const char next = s[j + 1];
        if (next == '\0') return false;
        if (c == '$' && next != '{' && next != '\'') { j += 2; continue; }
        if (c == '\'' && next != '\'' && next != '$') { j += 2; continue; }
        break;
      }
      if (j > i) { p = j; continue; }
      if (at(i) == '\'' && at(i + 1) == '\'') {
        if (at(i + 2) == '$') { p += 3; continue; }
        if (at(i + 2) == '\'') { p += 3; continue; }
        if (at(i + 2) == '\\' && !eof(i + 3)) { p += 4; continue; }
        st.pop();
        if (!closeBand(K_IND_STRING, K_IND_STRING, i)) return false;
        p += 2;
        return true;
      }
      if (at(i) == '$' && at(i + 1) == '{') { st.append(S_DEFAULT); openBand(K_INTERP, i); p += 2; return true; }
      if (at(i) == '$' || at(i) == '\'') { p++; continue; }
      return false;
    }
  }

  /// A path that continues after an interpolation, or after a segment and its slash.
  bool inPath() {
    const size_t i = p;
    if (at(i) == '$' && at(i + 1) == '{') {
      st.pop();
      st.append(S_INPATH);
      st.append(S_DEFAULT);
      openBand(K_INTERP, i);
      p += 2;
      return true;
    }
    size_t run = 0;
    while (!eof(i + run) && isPathChar(src[i + run])) run++;
    size_t l = std::max({mPath(i), mPathSeg(i), run});
    if (l) {
      st.pop();
      st.append(src[i + l - 1] == '/' ? S_INPATH_SLASH : S_INPATH);
      p += l;
      return true;
    }
    if (st.back() == S_INPATH_SLASH) return false; // a trailing slash
    st.pop();                                  // the end of the path
    return true;
  }
};

} // namespace

bool scan(std::string_view src, Bands &out) {
  out.src = src;
  return Scanner(src, out).run();
}

uint32_t Bands::need(uint32_t off) {
  if (uint32_t r = at(off); r != kNone) return r;
  Scanner s(src, *this);
  s.p = off;
  s.rooted = true;
  return s.run() ? at(off) : kNone;
}

} // namespace nixfe::confix

// The names and lookups of the kinds of tokens and bands, generated from NixDialect/NixSyntax.td.
#include "llvm/ADT/StringSwitch.h"
#include "NixDialect/NixSyntaxEnums.cpp.inc"
#include "Composite/TrikeShedEnums.cpp.inc"
