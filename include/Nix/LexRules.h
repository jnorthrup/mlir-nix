//===- LexRules.h - What a Nix token is, as functions of the input --------*- C++ -*-===//
//
// The lexer (Parser.cpp) and the Confix scan (Confix.cpp) must agree on where every token begins and ends,
// down to which of two rules wins a tie, or a delimiter hidden inside a URI would be found by one and not
// the other.  So the rules live here once: the character classes, the matchers of the multi-character tokens,
// and the default state's longest-match choice.  Nothing here builds a token or a position.
//
//===----------------------------------------------------------------------===//
#ifndef NIX_LEXRULES_H
#define NIX_LEXRULES_H

#include <algorithm>
#include <cstddef>
#include <cstring>
#include <string_view>

namespace nixfe::lex {

inline bool isPathChar(char c) {
  return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
         (c >= '0' && c <= '9') || c == '.' || c == '_' || c == '-' || c == '+';
}
inline bool isIdStart(char c) {
  return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
}
inline bool isIdChar(char c) {
  return isIdStart(c) || (c >= '0' && c <= '9') || c == '\'' || c == '-';
}
inline bool isDigit(char c) { return c >= '0' && c <= '9'; }
inline bool isAlpha(char c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'); }
inline bool isUriChar(char c) {
  return isAlpha(c) || isDigit(c) || strchr("%/?:@&=+$,-_.!~*'", c) != nullptr;
}

/// The rule that matched in the default state.  Keywords are 0..9 and operators 10..21, in the order of the tables
/// in matchDefault; the rest are named.
enum Rule : int {
  R_KEYWORD = 0, R_OPERATOR = 10,
  R_ID = 30, R_INT = 31, R_FLOAT = 32, R_DOLLAR_CURLY = 33, R_RBRACE = 34, R_LBRACE = 35, R_DQUOTE = 36,
  R_IND_OPEN = 37, R_PATH_START = 38, R_PATH = 39, R_HPATH = 40, R_SPATH = 41, R_URI = 42, R_COMMENT = 43,
  R_CHAR = 99, // none of the above: the character is the token
};

struct Match {
  size_t len;
  int rule;
};

/// The input and the matchers over it.  Each returns the length of the match at position i, 0 for none.
struct Rules {
  std::string_view src; // the input, immutable
  explicit Rules(std::string_view s) : src(s) {}

  char at(size_t i) const { return i < src.size() ? src[i] : '\0'; }
  bool eof(size_t i) const { return i >= src.size(); }

  size_t mId(size_t i) const {
    if (!isIdStart(at(i)) || eof(i)) return 0;
    size_t j = i + 1;
    while (!eof(j) && isIdChar(src[j])) j++;
    return j - i;
  }
  size_t mInt(size_t i) const {
    size_t j = i;
    while (!eof(j) && isDigit(src[j])) j++;
    return j - i;
  }
  size_t mFloat(size_t i) const {
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
  size_t mPath(size_t i) const {
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
  size_t mPathSeg(size_t i) const {
    size_t j = i;
    while (!eof(j) && isPathChar(src[j])) j++;
    return at(j) == '/' ? j + 1 - i : 0;
  }
  // \~(\/{PATH_CHAR}+)+\/?
  size_t mHPath(size_t i) const {
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
  size_t mSPath(size_t i) const {
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
  size_t mUri(size_t i) const {
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
  size_t mLongComment(size_t i) const {
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

  /// The default state at i, past whitespace and `#` comments: the longest of the rules that can start with the
  /// character c = src[i], the earlier rule winning a tie (flex's choice).  The fallback is the character itself.
  Match matchDefault(size_t i, char c) const {
    Match best{0, 1000};
    auto consider = [&](size_t len, int rule) {
      if (len > best.len || (len == best.len && len > 0 && rule < best.rule)) best = {len, rule};
    };
    static constexpr std::string_view kw[] = {"if", "then", "else", "assert", "with", "let", "in", "rec", "inherit", "or"};
    static constexpr std::string_view ops[] = {"...", "==", "!=", "<=", ">=", "&&", "||", "->", "//", "++", "<|", "|>"};
    const bool idStart = isIdStart(c), digit = isDigit(c), pathStart = isPathChar(c) || c == '/';
    if (idStart)
      for (int k = 0; k < 10; k++)
        if (kw[k][0] == c && src.compare(i, kw[k].size(), kw[k]) == 0) consider(kw[k].size(), R_KEYWORD + k);
    for (int k = 0; k < 12; k++)
      if (ops[k][0] == c && src.compare(i, ops[k].size(), ops[k]) == 0) consider(ops[k].size(), R_OPERATOR + k);
    if (idStart) consider(mId(i), R_ID);
    if (digit) consider(mInt(i), R_INT);
    if (digit || c == '.') consider(mFloat(i), R_FLOAT);
    if (c == '$' && at(i + 1) == '{') consider(2, R_DOLLAR_CURLY);
    if (c == '}') consider(1, R_RBRACE);
    if (c == '{') consider(1, R_LBRACE);
    if (c == '"') consider(1, R_DQUOTE);
    if (c == '\'' && at(i + 1) == '\'') {
      size_t j = i + 2;
      while (at(j) == ' ') j++;
      consider(at(j) == '\n' ? j + 1 - i : 2, R_IND_OPEN);
    }
    if (pathStart) {
      size_t l = mPathSeg(i);
      if (l && at(i + l) == '$' && at(i + l + 1) == '{') consider(l + 2, R_PATH_START);
      consider(mPath(i), R_PATH);
    }
    if (c == '~') {
      if (at(i + 1) == '/' && at(i + 2) == '$' && at(i + 3) == '{') consider(4, R_PATH_START);
      consider(mHPath(i), R_HPATH);
    }
    if (c == '<') consider(mSPath(i), R_SPATH);
    if (isAlpha(c)) consider(mUri(i), R_URI);
    if (c == '/') consider(mLongComment(i), R_COMMENT); // doc comments and long comments
    if (best.len == 0) consider(1, R_CHAR);
    return best;
  }
};

} // namespace nixfe::lex

#endif // NIX_LEXRULES_H
