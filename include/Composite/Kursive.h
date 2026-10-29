//===- Kursive.h - TrikeShed's kursive for the patterns Nix writes: a regular expression as a program of steps ---===//
//
// ../TrikeShed/src/commonMain/kotlin/borg/trikeshed/parse/kursive: parsers over a cursor, with a checkpoint and a rewind.  Here a POSIX
// extended regular expression (what builtins.match is given) compiles once into a program of steps over a Series<char>, and a match runs it
// with an explicit stack of checkpoints the caller owns: the captures are marks in a fixed array, and a match allocates nothing.
//
// The semantics are libstdc++'s for std::regex::extended under regex_match, which is what Nix on Linux answers with: a depth-first walk that
// tries the left alternative first and one more repetition before stopping, and keeps the first walk that reaches the end of the input (every
// full match has the same length, so POSIX's longest rule changes nothing); a group keeps the span of its last iteration.  The walk here
// stops at that first full match, where libstdc++ goes on exploring.
//
// What it does not take it says it does not take (Program::ok false), and the caller asks std::regex instead: a repetition over something
// that can match empty, collating symbols and equivalence classes ([. .] [= =]), a quantifier with nothing before it, an unbalanced
// parenthesis, a malformed interval, an unknown character class.  So std::regex keeps the errors and the corners, and this keeps the rest.
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

enum class Op : uint8_t { Char, Split, Jmp, Save, Bol, Eol, Match };
/// One step.  Char: the byte at the cursor is in sets[x]; Split: go on at x, and on a rewind at y; Jmp: go on at x; Save: mark slot x.
struct Step {
  Op op;
  uint32_t x = 0, y = 0;
};

/// A compiled pattern, in memory the caller gives: steps, sets, and how many groups (group 0, the whole match, not counted).
struct Program {
  Step *steps = nullptr;
  uint32_t nSteps = 0, capSteps = 0;
  Set *sets = nullptr;
  uint32_t nSets = 0, capSets = 0;
  uint32_t groups = 0;
  bool ok = false;
};

namespace detail {
/// The pattern as a tree first (a pool of nodes), so that alternation and repetition can be emitted knowing their sizes.
enum class Kind : uint8_t { Lit, Cat, Alt, Rep, Group, Bol, Eol, Empty };
struct Node {
  Kind kind;
  uint32_t a = 0, b = 0;   // Cat/Alt: children; Rep, Group: a = child; Lit: a = set
  uint32_t min = 0, max = 0; // Rep: bounds, max ~0u for no bound; Group: min = group number
};
constexpr uint32_t kNone = ~0u, kUnbounded = ~0u;

struct Compiler {
  const char *p, *end;
  Node *nodes;
  uint32_t nNodes = 0, capNodes;
  Program &prog;
  bool fail = false;

  uint32_t node(Node n) {
    if (nNodes == capNodes) { fail = true; return 0; }
    nodes[nNodes] = n;
    return nNodes++;
  }
  uint32_t set(const Set &s) {
    if (prog.nSets == prog.capSets) { fail = true; return 0; }
    prog.sets[prog.nSets] = s;
    return prog.nSets++;
  }
  bool at(char c) const { return p < end && *p == c; }

  // C-locale character classes: what regex_traits<char> answers for a byte under the C locale (and, for a high byte, under a UTF-8 one).
  static bool classMember(const char *name, uint32_t len, uint8_t c) {
    auto is = [&](const char *s) {
      uint32_t i = 0;
      for (; s[i] && i < len; i++)
        if (s[i] != name[i]) return false;
      return !s[i] && i == len;
    };
    bool upper = c >= 'A' && c <= 'Z', lower = c >= 'a' && c <= 'z', digit = c >= '0' && c <= '9';
    bool alpha = upper || lower, alnum = alpha || digit, space = c == ' ' || (c >= '\t' && c <= '\r');
    bool print = c >= 0x20 && c < 0x7f, graph = c > 0x20 && c < 0x7f, cntrl = c < 0x20 || c == 0x7f;
    if (is("alnum")) return alnum;
    if (is("alpha")) return alpha;
    if (is("digit")) return digit;
    if (is("space")) return space;
    if (is("upper")) return upper;
    if (is("lower")) return lower;
    if (is("xdigit")) return digit || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
    if (is("blank")) return c == ' ' || c == '\t';
    if (is("punct")) return graph && !alnum;
    if (is("print")) return print;
    if (is("graph")) return graph;
    if (is("cntrl")) return cntrl;
    return false;
  }
  static bool knownClass(const char *name, uint32_t len) {
    const char *names[] = {"alnum", "alpha", "digit", "space", "upper", "lower", "xdigit", "blank", "punct", "print", "graph", "cntrl"};
    for (const char *n : names) {
      uint32_t i = 0;
      while (n[i] && i < len && n[i] == name[i]) i++;
      if (!n[i] && i == len) return true;
    }
    return false;
  }

  // A bracket expression, after its '[': a backslash in it is a byte like any other (POSIX), ']' first is a member, '-' first or last too.
  uint32_t bracket() {
    Set s;
    bool neg = false;
    if (at('^')) { neg = true; p++; }
    bool first = true;
    int prev = -1; // the last single byte added, a range's possible start
    while (p < end && (first || *p != ']')) {
      if (*p == '[' && p + 1 < end && (p[1] == '.' || p[1] == '=')) { fail = true; return 0; }
      if (*p == '[' && p + 1 < end && p[1] == ':') {
        const char *q = p + 2, *name = q;
        while (q + 1 < end && !(q[0] == ':' && q[1] == ']')) q++;
        if (q + 1 >= end || !knownClass(name, uint32_t(q - name))) { fail = true; return 0; }
        for (unsigned c = 0; c < 256; c++)
          if (classMember(name, uint32_t(q - name), uint8_t(c))) s.add(uint8_t(c));
        p = q + 2;
        prev = -1;
        first = false;
        continue;
      }
      uint8_t c = uint8_t(*p++);
      if (c == '-' && !first && prev >= 0 && p < end && *p != ']') { // a range from the byte before to the byte after
        uint8_t hi = uint8_t(*p++);
        if (hi < uint8_t(prev)) { fail = true; return 0; }
        s.range(uint8_t(prev), hi);
        prev = -1;
      } else {
        s.add(c);
        prev = c;
      }
      first = false;
    }
    if (!at(']')) { fail = true; return 0; }
    p++;
    if (neg) s.invert();
    return node({Kind::Lit, set(s)});
  }

  bool number(uint32_t &v) {
    if (!(p < end && *p >= '0' && *p <= '9')) return false;
    v = 0;
    while (p < end && *p >= '0' && *p <= '9') {
      v = v * 10 + uint32_t(*p++ - '0');
      if (v > 1000) { fail = true; return false; }
    }
    return true;
  }

  uint32_t atom() {
    char c = *p++;
    Set s;
    switch (c) {
    case '.': s.invert(); s.w[0] &= ~uint64_t(1); return node({Kind::Lit, set(s)}); // any byte but NUL, as libstdc++'s POSIX '.'
    case '[': return bracket();
    case '^': return node({Kind::Bol});
    case '$': return node({Kind::Eol});
    case '(': {
      uint32_t g = ++prog.groups;
      uint32_t inner = at(')') ? node({Kind::Empty}) : alternation();
      if (!at(')')) { fail = true; return 0; }
      p++;
      Node n{Kind::Group, inner};
      n.min = g;
      return node(n);
    }
    case '\\':
      if (p == end) { fail = true; return 0; }
      s.add(uint8_t(*p++)); // an escaped byte is that byte (libstdc++ outside strict ANSI)
      return node({Kind::Lit, set(s)});
    case '*': case '+': case '?': case '{': case ')': case '|': fail = true; return 0; // a quantifier with nothing before it
    default: s.add(uint8_t(c)); return node({Kind::Lit, set(s)});
    }
  }

  uint32_t postfix(uint32_t a) {
    while (p < end && !fail) {
      uint32_t lo, hi;
      if (*p == '*') { lo = 0; hi = kUnbounded; p++; }
      else if (*p == '+') { lo = 1; hi = kUnbounded; p++; }
      else if (*p == '?') { lo = 0; hi = 1; p++; }
      else if (*p == '{') {
        p++;
        if (!number(lo)) { fail = true; return 0; }
        hi = lo;
        if (at(',')) { p++; if (!number(hi)) hi = kUnbounded; }
        if (!at('}') || (hi != kUnbounded && hi < lo)) { fail = true; return 0; }
        p++;
      } else break;
      Node n{Kind::Rep, a};
      n.min = lo;
      n.max = hi;
      a = node(n);
    }
    return a;
  }

  uint32_t sequence() {
    uint32_t acc = kNone;
    while (p < end && *p != '|' && *p != ')' && !fail) {
      uint32_t a = postfix(atom());
      acc = acc == kNone ? a : node({Kind::Cat, acc, a});
    }
    return acc == kNone ? node({Kind::Empty}) : acc;
  }

  uint32_t alternation() {
    uint32_t a = sequence();
    while (at('|') && !fail) {
      p++;
      a = node({Kind::Alt, a, sequence()});
    }
    return a;
  }

  bool nullable(uint32_t i) const {
    const Node &n = nodes[i];
    switch (n.kind) {
    case Kind::Lit: return false;
    case Kind::Cat: return nullable(n.a) && nullable(n.b);
    case Kind::Alt: return nullable(n.a) || nullable(n.b);
    case Kind::Rep: return n.min == 0 || nullable(n.a);
    case Kind::Group: return nullable(n.a);
    default: return true;
    }
  }

  uint32_t emit(Step s) {
    if (prog.nSteps == prog.capSteps) { fail = true; return 0; }
    prog.steps[prog.nSteps] = s;
    return prog.nSteps++;
  }

  void gen(uint32_t i) {
    if (fail) return;
    const Node &n = nodes[i];
    switch (n.kind) {
    case Kind::Lit: emit({Op::Char, n.a}); break;
    case Kind::Cat: gen(n.a); gen(n.b); break;
    case Kind::Alt: { // split L1 L2; L1: a; jmp end; L2: b; end:
      uint32_t split = emit({Op::Split});
      prog.steps[split].x = prog.nSteps;
      gen(n.a);
      uint32_t jmp = emit({Op::Jmp});
      prog.steps[split].y = prog.nSteps;
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
    case Kind::Rep: {
      if (n.max == kUnbounded && nullable(n.a)) { fail = true; return; } // a loop that may not advance: std::regex's corner
      for (uint32_t k = 0; k < n.min; k++) gen(n.a);
      if (n.max == kUnbounded) { // L: split body end; body: a; jmp L; end:   (the body first: greedy)
        uint32_t split = emit({Op::Split});
        prog.steps[split].x = prog.nSteps;
        gen(n.a);
        emit({Op::Jmp, split});
        prog.steps[split].y = prog.nSteps;
      } else { // (max - min) optional copies, each tried before the way out: split body end; body: a; ... end:
        uint32_t opt = n.max - n.min;
        if (opt > 256) { fail = true; return; }
        uint32_t splits[256];
        for (uint32_t k = 0; k < opt && !fail; k++) {
          splits[k] = emit({Op::Split});
          prog.steps[splits[k]].x = prog.nSteps;
          gen(n.a);
        }
        for (uint32_t k = 0; k < opt && !fail; k++) prog.steps[splits[k]].y = prog.nSteps; // every way out goes past the last copy
      }
      break;
    }
    }
  }
};
} // namespace detail

/// Compile `pattern` into `prog` (whose step and set arrays the caller gave), with `pool` and `poolCap` nodes for the tree.  ok false: not a
/// pattern this engine takes, or not enough room; the caller uses std::regex for it.
inline void compile(const char *pattern, uint32_t len, Program &prog, detail::Node *pool, uint32_t poolCap) {
  detail::Compiler c{pattern, pattern + len, pool, 0, poolCap, prog};
  uint32_t root = c.alternation();
  if (c.p != c.end) c.fail = true; // a ')' with no '(' before it
  if (!c.fail) {
    c.emit({Op::Save, 0});
    c.gen(root);
    c.emit({Op::Save, 1});
    c.emit({Op::Match});
  }
  prog.ok = !c.fail;
}

/// A checkpoint: where to go on at a rewind, or a mark to put back.
struct Entry {
  uint32_t a, b; // a branch: (step | kBranch, position); an undo: (slot, old value)
};
constexpr uint32_t kBranch = 0x80000000u;

enum class Result : uint8_t { NoMatch, Match, GaveUp };

/// regex_match: the whole of text[0, n) by `prog`.  `caps` has 2 * (groups + 1) slots, ~0u for a group that did not take part; `stack` and
/// `cap` the checkpoints, `budget` the steps a walk may take (GaveUp when either runs out, and the caller asks std::regex).
inline Result matchAll(const Program &prog, const char *text, uint32_t n, uint32_t *caps, Entry *stack, uint32_t cap,
                       uint64_t budget = uint64_t(1) << 22) {
  uint32_t slots = 2 * (prog.groups + 1);
  for (uint32_t i = 0; i < slots; i++) caps[i] = ~0u;
  uint32_t sp = 0, pc = 0, pos = 0;
  for (;;) {
    if (budget-- == 0) return Result::GaveUp;
    const Step &s = prog.steps[pc];
    bool ok = true;
    switch (s.op) {
    case Op::Char:
      if (pos < n && prog.sets[s.x].has(uint8_t(text[pos]))) { pos++; pc++; }
      else ok = false;
      break;
    case Op::Split:
      if (sp == cap) return Result::GaveUp;
      stack[sp++] = {s.y | kBranch, pos};
      pc = s.x;
      break;
    case Op::Jmp: pc = s.x; break;
    case Op::Save:
      if (sp == cap) return Result::GaveUp;
      stack[sp++] = {s.x, caps[s.x]};
      caps[s.x] = pos;
      pc++;
      break;
    case Op::Bol: if (pos == 0) pc++; else ok = false; break;
    case Op::Eol: if (pos == n) pc++; else ok = false; break;
    case Op::Match:
      if (pos == n) return Result::Match;
      ok = false;
      break;
    }
    if (ok) continue;
    for (;;) { // rewind: put marks back until a branch, and go on there
      if (sp == 0) return Result::NoMatch;
      Entry e = stack[--sp];
      if (e.a & kBranch) { pc = e.a & ~kBranch; pos = e.b; break; }
      caps[e.a] = e.b;
    }
  }
}

} // namespace composite::kursive

#endif
