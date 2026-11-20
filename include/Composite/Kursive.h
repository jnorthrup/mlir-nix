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
// the special characters .[\()*+?{|^$ may be escaped (libstdc++'s extended set: not ] or }), and `\n` or `\]` is an error, as
// `nix-instantiate --eval` 2.35.4 answers.
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
} // namespace detail

/// The compiler is hollowed into MLIR (lowered/nixeval/KursiveCompile.mlir, mlnix_kursive_compile): the extended-regex
/// parser building the tree in the caller's Node pool (20B: kind u8@0, a/b/min/max u32@4..16), then the generator writing
/// the Step program and the Sets into prog's arrays.  counts is {nSteps, nSets, groups, loops}, in and out; the answer is
/// the Error.  Nothing is allocated.
extern "C" int32_t mlnix_kursive_compile(const char *pattern, uint32_t len, Step *steps, uint32_t capSteps, Set *sets,
    uint32_t capSets, detail::Node *pool, uint32_t poolCap, uint32_t *counts);

/// Compile `pattern` into `prog` (whose step and set arrays the caller gave), with `pool` and `poolCap` nodes for the tree; prog.error says
/// whether it took it, or why not.
inline void compile(const char *pattern, uint32_t len, Program &prog, detail::Node *pool, uint32_t poolCap) {
  uint32_t n[4] = {prog.nSteps, prog.nSets, prog.groups, prog.loops};
  prog.error = Error(mlnix_kursive_compile(pattern, len, prog.steps, prog.capSteps, prog.sets, prog.capSets, pool, poolCap, n));
  prog.nSteps = n[0], prog.nSets = n[1], prog.groups = n[2], prog.loops = n[3];
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

/// The walk is hollowed into MLIR (lowered/nixeval/KursiveOps.mlir, mlnix_kursive_walk): the backtracking state machine
/// over the Step program, as libstdc++'s std::regex::extended executor answers.  The caller owns every array; the walk
/// allocates nothing.  Step is 16B (op u8@0, x/y/z u32@4/8/12), Set 4 u64, LoopState 2 u32 (pos,count), Entry 3 u32
/// (tag,a,b); a checkpoint tag is Tag << 28 | id (Tag above).  The entry returns Result: 0 NoMatch, 1 Match, 2 GaveUp.
extern "C" int32_t mlnix_kursive_walk(const void *steps, const void *sets, uint32_t groups, uint32_t loops,
    const char *text, uint32_t n, uint32_t start, int32_t exact, int32_t notNull,
    uint32_t *caps, uint32_t *best, void *loopsArr, void *stack, uint32_t cap, uint64_t *budget);

/// regex_match: the whole of text[0, n).  The groups' marks are in s.best (~0u for a group that took no part).
inline Result matchAll(const Program &prog, const char *text, uint32_t n, Scratch &s) {
  return Result(mlnix_kursive_walk(prog.steps, prog.sets, prog.groups, prog.loops, text, n, 0, 1, 0,
      s.caps, s.best, s.loops, s.stack, s.cap, &s.budget));
}

/// regex_search from `from`: the leftmost start with a match, its longest match; `continuous` tries `from` only, `notNull` refuses an empty
/// match.  The marks are in s.best.  The start enumeration stays here; each start's walk is the MLIR state machine.
inline Result search(const Program &prog, const char *text, uint32_t n, uint32_t from, bool notNull, bool continuous, Scratch &s) {
  for (uint32_t start = from; start <= n; start++) {
    Result r = Result(mlnix_kursive_walk(prog.steps, prog.sets, prog.groups, prog.loops, text, n, start, 0, notNull ? 1 : 0,
        s.caps, s.best, s.loops, s.stack, s.cap, &s.budget));
    if (r != Result::NoMatch) return r;
    if (continuous) break;
  }
  return Result::NoMatch;
}

} // namespace composite::kursive

#endif
