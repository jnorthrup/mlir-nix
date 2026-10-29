//===- Kursive.h - TrikeShed's kursive for the patterns Nix writes: a regular expression as a program of steps ---===//
//
// ../TrikeShed/src/commonMain/kotlin/borg/trikeshed/parse/kursive: parsers over a cursor, with a checkpoint and a rewind.  Here a POSIX
// extended regular expression (builtins.match, builtins.split) compiles once into a program of steps over the bytes of a window, and a walk
// runs it with an explicit stack of checkpoints the caller owns: a group is a pair of marks in a fixed array, and a walk allocates nothing.
//
// The semantics are libstdc++'s for std::regex::extended, which is what Nix on Linux answers with, read from its executor:
//   * a repeat tries one more iteration before stopping, and does not try stopping once a solution was found (its DFS executor);
//   * a loop may enter its body at the same position at most twice in a row (rep_count: what keeps `(a*)*` from looping forever);
//   * an alternation tries its left side, then its right with the "found" flag cleared, and keeps the flag of either;
//   * regex_match keeps the first walk that reaches the end (every full match has the same length); regex_search keeps, at the leftmost
//     start that matches, the longest match and the first of the longest;
//   * a group keeps the span of its last iteration.
// What libstdc++ rejects is rejected here (Program::error), with the message Nix gives for it; a pattern too large for the step and set
// arrays is reported as libstdc++ reports a pattern too large for its states.  Nix's libstdc++ is built strict (__STRICT_ANSI__): only
// the special characters ^$\.*+?()[]{}| may be escaped, and `\n` is an error, as `nix-instantiate --eval` 2.35.4 answers.
//
// No #include, no std::: Core.h and the caller's memory.
//
//===----------------------------------------------------------------------===//

#ifndef COMPOSITE_KURSIVE_H
#define COMPOSITE_KURSIVE_H

#include "Composite/Core.h"

namespace composite::kursive {

/// A set of bytes, one bit each.
struct Set {
  uint64_t w[4] = {0, 0, 0, 0};
  constexpr bool has(uint8_t c) const { return (w[c >> 6] >> (c & 63)) & 1; }
  constexpr void add(uint8_t c) { w[c >> 6] |= uint64_t(1) << (c & 63); }
  constexpr void range(uint8_t a, uint8_t b) { for (unsigned c = a; c <= b; c++) add(uint8_t(c)); }
  constexpr void invert() { for (auto &x : w) x = ~x; }
};

/// One step.  Char: the byte at the cursor is in sets[x].  Alt: x, then y.  Rep: the body at x (loop slot z), then the way out at y.
/// Jmp: x.  Save: mark slot x.  Bol, Eol: the cursor at the start, at the end.  Match: a solution.
enum class Op : uint8_t { Char, Alt, Rep, Jmp, Save, Bol, Eol, Match };
struct Step {
  Op op;
  uint32_t x = 0, y = 0, z = 0;
};

enum class Error : uint8_t { None, Invalid, Space };

/// A compiled pattern, in memory the caller gives: steps, sets, how many groups (group 0, the whole match, not counted) and loop slots.
struct Program {
  Step *steps = nullptr;
  uint32_t nSteps = 0, capSteps = 0;
  Set *sets = nullptr;
  uint32_t nSets = 0, capSets = 0;
  uint32_t groups = 0, loops = 0;
  Error error = Error::Invalid;
};

namespace detail {
/// The pattern as a tree first (a pool of nodes), so that alternation and repetition can be emitted knowing their sizes.
enum class Kind : uint8_t { Lit, Cat, Alt, Rep, Group, Bol, Eol, Empty };
struct Node {
  Kind kind;
  uint32_t a = 0, b = 0;     // Cat/Alt: children; Rep, Group: a = child; Lit: a = set
  uint32_t min = 0, max = 0; // Rep: bounds, max ~0u for no bound; Group: min = group number
};
constexpr uint32_t kNone = ~0u, kUnbounded = ~0u;

struct Compiler {
  const char *p, *end;
  Node *nodes;
  uint32_t nNodes = 0, capNodes;
  Program &prog;
  Error fail = Error::None;

  void bad(Error e) { if (fail == Error::None) fail = e; }
  uint32_t node(Node n) {
    if (nNodes == capNodes) { bad(Error::Space); return 0; }
    nodes[nNodes] = n;
    return nNodes++;
  }
  uint32_t set(const Set &s) {
    if (prog.nSets == prog.capSets) { bad(Error::Space); return 0; }
    prog.sets[prog.nSets] = s;
    return prog.nSets++;
  }
  bool at(char c) const { return p < end && *p == c; }

  static bool named(const char *name, uint32_t len, const char *s) {
    uint32_t i = 0;
    for (; s[i] && i < len; i++)
      if (s[i] != name[i]) return false;
    return !s[i] && i == len;
  }
  // C-locale character classes: what regex_traits<char> answers for a byte under the C locale (and, for a high byte, under a UTF-8 one).
  static bool classMember(const char *name, uint32_t len, uint8_t c, bool &known) {
    bool upper = c >= 'A' && c <= 'Z', lower = c >= 'a' && c <= 'z', digit = c >= '0' && c <= '9';
    bool alpha = upper || lower, alnum = alpha || digit, space = c == ' ' || (c >= '\t' && c <= '\r');
    bool print = c >= 0x20 && c < 0x7f, graph = c > 0x20 && c < 0x7f, cntrl = c < 0x20 || c == 0x7f;
    known = true;
    if (named(name, len, "alnum")) return alnum;
    if (named(name, len, "alpha")) return alpha;
    if (named(name, len, "digit") || named(name, len, "d")) return digit;
    if (named(name, len, "space") || named(name, len, "s")) return space;
    if (named(name, len, "upper")) return upper;
    if (named(name, len, "lower")) return lower;
    if (named(name, len, "xdigit")) return digit || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
    if (named(name, len, "blank")) return c == ' ' || c == '\t';
    if (named(name, len, "punct")) return graph && !alnum;
    if (named(name, len, "print")) return print;
    if (named(name, len, "graph")) return graph;
    if (named(name, len, "cntrl")) return cntrl;
    if (named(name, len, "w")) return alnum || c == '_';
    known = false;
    return false;
  }

  // A bracket expression, after its '[': a backslash in it is a byte like any other (POSIX), ']' first is a member, '-' first or last too;
  // [. .] and [= =] name one byte (the C locale has no longer collating elements Nix code uses).
  uint32_t bracket() {
    Set s;
    bool neg = false;
    if (at('^')) { neg = true; p++; }
    bool first = true;
    int prev = -1; // the last single byte added, a range's possible start
    while (p < end && (first || *p != ']')) {
      if (*p == '[' && p + 1 < end && p[1] == ':') {
        const char *q = p + 2, *name = q;
        while (q + 1 < end && !(q[0] == ':' && q[1] == ']')) q++;
        if (q + 1 >= end) { bad(Error::Invalid); return 0; }
        bool known = true;
        for (unsigned c = 0; c < 256 && known; c++)
          if (classMember(name, uint32_t(q - name), uint8_t(c), known)) s.add(uint8_t(c));
        if (!known) { bad(Error::Invalid); return 0; }
        p = q + 2;
        prev = -1;
        first = false;
        continue;
      }
      int c;
      if (*p == '[' && p + 1 < end && (p[1] == '.' || p[1] == '=')) { // one byte between [. and .] (or [= and =])
        char kind = p[1];
        if (p + 4 >= end || p[3] != kind || p[4] != ']') { bad(Error::Invalid); return 0; }
        c = uint8_t(p[2]);
        p += 5;
      } else c = uint8_t(*p++);
      if (c == '-' && !first && prev >= 0 && p < end && *p != ']') { // a range from the byte before to the byte after
        int hi;
        if (*p == '[' && p + 1 < end && (p[1] == '.' || p[1] == '=')) {
          char kind = p[1];
          if (p + 4 >= end || p[3] != kind || p[4] != ']') { bad(Error::Invalid); return 0; }
          hi = uint8_t(p[2]);
          p += 5;
        } else if (*p == '[' && p + 1 < end && p[1] == ':') { bad(Error::Invalid); return 0; }
        else hi = uint8_t(*p++);
        if (hi < prev) { bad(Error::Invalid); return 0; }
        s.range(uint8_t(prev), uint8_t(hi));
        prev = -1;
      } else {
        s.add(uint8_t(c));
        prev = c;
      }
      first = false;
    }
    if (!at(']')) { bad(Error::Invalid); return 0; }
    p++;
    if (neg) s.invert();
    return node({Kind::Lit, set(s)});
  }

  bool number(uint32_t &v) {
    if (!(p < end && *p >= '0' && *p <= '9')) return false;
    v = 0;
    while (p < end && *p >= '0' && *p <= '9') {
      v = v * 10 + uint32_t(*p++ - '0');
      if (v > 100000) { bad(Error::Space); return false; }
    }
    return true;
  }

  uint32_t atom(bool &assertion) {
    assertion = false;
    char c = *p++;
    Set s;
    switch (c) {
    case '.': s.invert(); s.w[0] &= ~uint64_t(1); return node({Kind::Lit, set(s)}); // any byte but NUL, as libstdc++'s POSIX '.'
    case '[': return bracket();
    case '^': assertion = true; return node({Kind::Bol});
    case '$': assertion = true; return node({Kind::Eol});
    case '(': {
      uint32_t g = ++prog.groups;
      uint32_t inner = at(')') ? node({Kind::Empty}) : alternation();
      if (!at(')')) { bad(Error::Invalid); return 0; }
      p++;
      Node n{Kind::Group, inner};
      n.min = g;
      return node(n);
    }
    case '\\': { // only a special character may be escaped: Nix's libstdc++ is built strict (__STRICT_ANSI__), where any other is an error
      if (p == end) { bad(Error::Invalid); return 0; }
      char e = *p++;
      const char *special = "^$\\.*+?()[]{}|";
      bool ok = false;
      for (const char *q = special; *q; q++) ok = ok || *q == e;
      if (!ok) { bad(Error::Invalid); return 0; }
      s.add(uint8_t(e));
      return node({Kind::Lit, set(s)});
    }
    case '*': case '+': case '?': case '{': case ')': case '|': bad(Error::Invalid); return 0; // a quantifier with nothing before it
    default: s.add(uint8_t(c)); return node({Kind::Lit, set(s)});
    }
  }

  uint32_t postfix(uint32_t a, bool assertion) {
    while (p < end && fail == Error::None) {
      uint32_t lo, hi;
      if (*p == '*') { lo = 0; hi = kUnbounded; }
      else if (*p == '+') { lo = 1; hi = kUnbounded; }
      else if (*p == '?') { lo = 0; hi = 1; }
      else if (*p == '{') {
        if (assertion) { bad(Error::Invalid); return 0; }
        p++;
        if (!number(lo)) { bad(Error::Invalid); return 0; }
        hi = lo;
        if (at(',')) { p++; if (!number(hi)) hi = kUnbounded; }
        if (!at('}') || (hi != kUnbounded && hi < lo)) { bad(Error::Invalid); return 0; }
        p++;
        Node n{Kind::Rep, a};
        n.min = lo;
        n.max = hi;
        a = node(n);
        continue;
      } else break;
      if (assertion) { bad(Error::Invalid); return 0; } // libstdc++: an anchor takes no quantifier
      p++;
      Node n{Kind::Rep, a};
      n.min = lo;
      n.max = hi;
      a = node(n);
    }
    return a;
  }

  uint32_t sequence() {
    uint32_t acc = kNone;
    while (p < end && *p != '|' && *p != ')' && fail == Error::None) {
      bool assertion;
      uint32_t a = atom(assertion);
      a = postfix(a, assertion);
      acc = acc == kNone ? a : node({Kind::Cat, acc, a});
    }
    return acc == kNone ? node({Kind::Empty}) : acc;
  }

  uint32_t alternation() {
    uint32_t a = sequence();
    while (at('|') && fail == Error::None) {
      p++;
      a = node({Kind::Alt, a, sequence()});
    }
    return a;
  }

  uint32_t emit(Step s) {
    if (prog.nSteps == prog.capSteps) { bad(Error::Space); return 0; }
    prog.steps[prog.nSteps] = s;
    return prog.nSteps++;
  }

  // One repeat state: its body, then the way out; a loop's body jumps back to it.
  void repeat(uint32_t body, bool loop) {
    uint32_t r = emit({Op::Rep});
    if (fail != Error::None) return;
    prog.steps[r].z = prog.loops++;
    prog.steps[r].x = prog.nSteps;
    gen(body);
    if (loop) emit({Op::Jmp, r});
    if (fail == Error::None) prog.steps[r].y = prog.nSteps;
  }

  void gen(uint32_t i) {
    if (fail != Error::None) return;
    const Node &n = nodes[i];
    switch (n.kind) {
    case Kind::Lit: emit({Op::Char, n.a}); break;
    case Kind::Cat: gen(n.a); gen(n.b); break;
    case Kind::Alt: { // alt L1 L2; L1: a; jmp end; L2: b; end:
      uint32_t alt = emit({Op::Alt});
      if (fail != Error::None) return;
      prog.steps[alt].x = prog.nSteps;
      gen(n.a);
      uint32_t jmp = emit({Op::Jmp});
      if (fail != Error::None) return;
      prog.steps[alt].y = prog.nSteps;
      gen(n.b);
      prog.steps[jmp].x = prog.nSteps;
      break;
    }
    case Kind::Group:
      emit({Op::Save, 2 * n.min});
      gen(n.a);
      emit({Op::Save, 2 * n.min + 1});
      break;
    case Kind::Bol: emit({Op::Bol}); break;
    case Kind::Eol: emit({Op::Eol}); break;
    case Kind::Empty: break;
    case Kind::Rep:
      for (uint32_t k = 0; k < n.min && fail == Error::None; k++) gen(n.a);
      if (n.max == kUnbounded) repeat(n.a, true);
      else
        for (uint32_t k = n.min; k < n.max && fail == Error::None; k++) repeat(n.a, false); // each optional copy a repeat state of its own
      break;
    }
  }
};
} // namespace detail

/// Compile `pattern` into `prog` (whose step and set arrays the caller gave), with `pool` and `poolCap` nodes for the tree; prog.error says
/// whether it took it, or why not.
inline void compile(const char *pattern, uint32_t len, Program &prog, detail::Node *pool, uint32_t poolCap) {
  detail::Compiler c{pattern, pattern + len, pool, 0, poolCap, prog};
  uint32_t root = c.alternation();
  if (c.fail == Error::None && c.p != c.end) c.bad(Error::Invalid); // a ')' with no '(' before it
  if (c.fail == Error::None) {
    c.emit({Op::Save, 0});
    c.gen(root);
    c.emit({Op::Save, 1});
    c.emit({Op::Match});
  }
  prog.error = c.fail;
}

/// A loop's last entry: where, and how many times in a row there.
struct LoopState {
  uint32_t pos, count;
};
/// A checkpoint: a branch to take at a rewind, or something to put back.
struct Entry {
  uint32_t tag, a, b;
};
enum Tag : uint32_t { kAltRight = 0, kAltJoin = 1, kRepOut = 2, kCap = 3, kLoop = 4 };
constexpr uint32_t tag(Tag t, uint32_t id) { return uint32_t(t) << 28 | id; }

enum class Result : uint8_t { NoMatch, Match, GaveUp };

/// The memory a walk works in: the groups' marks (2 * (groups + 1)), the loops' states (prog.loops), the checkpoints, a step budget.
struct Scratch {
  uint32_t *caps, *best;
  LoopState *loops;
  Entry *stack;
  uint32_t cap;
  uint64_t budget;
};

namespace detail {
/// One walk from `start`.  exact: regex_match's (a solution is the end of the text, the first wins); otherwise regex_search's at one start
/// (any position, the longest wins, the first of the longest; `notNull` refuses the empty match).  The answer's marks are in s.best.
inline Result walk(const Program &prog, const char *text, uint32_t n, uint32_t start, bool exact, bool notNull, Scratch &s) {
  uint32_t slots = 2 * (prog.groups + 1);
  for (uint32_t i = 0; i < slots; i++) s.caps[i] = ~0u;
  for (uint32_t i = 0; i < prog.loops; i++) s.loops[i] = {~0u, 0};
  uint32_t sp = 0, pc = 0, pos = start, bestEnd = ~0u;
  bool found = false; // libstdc++'s _M_has_sol
  auto push = [&](Entry e) {
    if (sp == s.cap) return false;
    s.stack[sp++] = e;
    return true;
  };
  for (;;) {
    if (s.budget == 0) return Result::GaveUp;
    s.budget--;
    const Step &st = prog.steps[pc];
    bool ok = true;
    switch (st.op) {
    case Op::Char:
      if (pos < n && prog.sets[st.x].has(uint8_t(text[pos]))) { pos++; pc++; }
      else ok = false;
      break;
    case Op::Alt:
      if (!push({tag(kAltRight, st.y), pos, 0})) return Result::GaveUp;
      pc = st.x;
      break;
    case Op::Rep: {
      LoopState &L = s.loops[st.z];
      bool fresh = L.count == 0 || L.pos != pos;
      if (fresh || L.count < 2) {
        if (!push({tag(kRepOut, st.y), pos, 0}) || !push({tag(kLoop, st.z), L.pos, L.count})) return Result::GaveUp;
        if (fresh) L = {pos, 1};
        else L.count++;
        pc = st.x;
      } else if (found) ok = false; // no more iterations here, and the way out is not tried once a solution was found
      else pc = st.y;
      break;
    }
    case Op::Jmp: pc = st.x; break;
    case Op::Save:
      if (!push({tag(kCap, st.x), s.caps[st.x], 0})) return Result::GaveUp;
      s.caps[st.x] = pos;
      pc++;
      break;
    case Op::Bol: if (pos == 0) pc++; else ok = false; break;
    case Op::Eol: if (pos == n) pc++; else ok = false; break;
    case Op::Match: {
      bool solution = (!exact || pos == n) && !(notNull && pos == start);
      if (solution) {
        if (exact) {
          for (uint32_t i = 0; i < slots; i++) s.best[i] = s.caps[i];
          return Result::Match;
        }
        found = true;
        if (bestEnd == ~0u || pos > bestEnd) {
          bestEnd = pos;
          for (uint32_t i = 0; i < slots; i++) s.best[i] = s.caps[i];
        }
      }
      ok = false; // go on: another walk may be longer
      break;
    }
    }
    if (ok) continue;
    for (;;) { // rewind
      if (sp == 0) return bestEnd != ~0u ? Result::Match : Result::NoMatch;
      Entry e = s.stack[--sp];
      uint32_t t = e.tag >> 28, id = e.tag & 0x0fffffffu;
      if (t == kCap) { s.caps[id] = e.a; continue; }
      if (t == kLoop) { s.loops[id] = {e.a, e.b}; continue; }
      if (t == kAltJoin) { found = found || e.a; continue; }
      if (t == kRepOut) {
        if (found) continue; // a solution was found: the repeat does not stop here
        pc = id;
        pos = e.a;
        break;
      }
      // kAltRight: the left side is done; the right side starts with the flag cleared, and the left's flag joins it after
      if (!push({tag(kAltJoin, 0), uint32_t(found), 0})) return Result::GaveUp;
      found = false;
      pc = id;
      pos = e.a;
      break;
    }
  }
}
} // namespace detail

/// regex_match: the whole of text[0, n).  The groups' marks are in s.best (~0u for a group that took no part).
inline Result matchAll(const Program &prog, const char *text, uint32_t n, Scratch &s) {
  return detail::walk(prog, text, n, 0, true, false, s);
}

/// regex_search from `from`: the leftmost start with a match, its longest match; `continuous` tries `from` only, `notNull` refuses an empty
/// match.  The marks are in s.best.
inline Result search(const Program &prog, const char *text, uint32_t n, uint32_t from, bool notNull, bool continuous, Scratch &s) {
  for (uint32_t start = from; start <= n; start++) {
    Result r = detail::walk(prog, text, n, start, false, notNull, s);
    if (r != Result::NoMatch) return r;
    if (continuous) break;
  }
  return Result::NoMatch;
}

} // namespace composite::kursive

#endif
