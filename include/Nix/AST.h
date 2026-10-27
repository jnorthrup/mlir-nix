//===- AST.h - Nix abstract syntax tree -----------------------*- C++ -*-===//
//
// Mirrors upstream Nix's Expr hierarchy closely (same desugarings), so that
// `--parse` output and scoping semantics are identical.
//
//===----------------------------------------------------------------------===//
#ifndef NIX_AST_H
#define NIX_AST_H

#include <cstdint>
#include <algorithm>
#include <deque>
#include <functional>
#include <initializer_list>
#include <map>
#include <memory>
#include <optional>
#include <ostream>
#include <stdexcept>
#include <string>
#include <vector>

#include "Composite/Series.h"
#include "Nix/Arena.h"
#include "Nix/Name.h"

namespace nixfe {

struct Pos {
  uint32_t line = 0, col = 0;
  bool valid() const { return line != 0; }
};

/// The immutable bytes of one input.  A file is mapped read-only; anything else is owned.  Nothing
/// ever writes to it: the lexer's tokens are segments (start, end) of it, and text that is not a
/// slice of it (an unescaped string) is a separate, appended entry.
class Source {
public:
  Source(const Source &) = delete;
  Source &operator=(const Source &) = delete;
  ~Source();
  static std::shared_ptr<const Source> fromString(std::string text);
  /// Maps a regular, non-empty file; null when that is not possible (the caller reads it).
  static std::shared_ptr<const Source> mapFile(const std::string &path);
  std::string_view view() const { return {data_, size_}; }

private:
  Source() = default;
  const char *data_ = nullptr;
  size_t size_ = 0;
  std::string owned_;
  void *map_ = nullptr;
};

/// Origin of source text: a file path, or "«string»"/"«stdin»".
struct Origin {
  std::string name;   // what errors print
  std::string path;   // absolute file path if a file, else empty
  std::string baseDir;
  std::shared_ptr<const Source> text;
  uint32_t fileId = 0; // number in nixfe::FileTable, given the first time a position of this file is made
};

struct ParseError : std::runtime_error {
  Pos pos;
  std::shared_ptr<Origin> origin;
  ParseError(std::string msg, Pos p, std::shared_ptr<Origin> o)
      : std::runtime_error(std::move(msg)), pos(p), origin(std::move(o)) {}
};

enum class ExprKind {
  Int, Float, String, Path, Var, Select, HasAttr, Attrs, List, Lambda, Call,
  Let, With, If, Assert, Not, Eq, NEq, And, Or, Impl, Update, ConcatLists,
  ConcatStrings, CurPos, InheritFrom
};

/// A node is a plain struct: it is made in an ExprArena, found by its `kind` and never destroyed, so it has no virtual
/// destructor and holds no vector or map; the arrays of a node are Slices of the same arena.
struct Expr {
  ExprKind kind;
  Pos pos;
  explicit Expr(ExprKind k, Pos p = {}) : kind(k), pos(p) {}
};

struct ExprInt : Expr { int64_t v; ExprInt(int64_t v) : Expr(ExprKind::Int), v(v) {} };
struct ExprFloat : Expr { double v; ExprFloat(double v) : Expr(ExprKind::Float), v(v) {} };
/// Every name and literal text of the tree is a Name (Nix/Name.h): a slice of the input, which is never freed, or a copy
/// in an arena that is not either.  The tree owns no string.
struct ExprString : Expr {
  Name v;
  ExprString(Name v) : Expr(ExprKind::String), v(v) {}
};
struct ExprPath : Expr {
  Name v;
  ExprPath(Name v) : Expr(ExprKind::Path), v(v) {}
};
struct ExprVar : Expr {
  Name name;
  ExprVar(Pos p, Name n) : Expr(ExprKind::Var, p), name(n) {}
};
struct ExprCurPos : Expr { ExprCurPos(Pos p) : Expr(ExprKind::CurPos, p) {} };

/// Placeholder for `inherit (e) ...`: refers to attrs->inheritFromExprs[displ].
struct ExprInheritFrom : Expr {
  size_t displ;
  ExprInheritFrom(Pos p, size_t d) : Expr(ExprKind::InheritFrom, p), displ(d) {}
};

struct AttrName {
  Name symbol; // the null name when the component is computed: `expr`
  Expr *expr = nullptr;
  AttrName(Name s) : symbol(s) {}
  AttrName(Expr *e) : expr(e) {}
  bool computed() const { return symbol.isNull(); }
};
/// Orders names by their text, as the attribute sets of the tree and of its printing are ordered.
struct NameLess {
  bool operator()(const Name &a, const Name &b) const { return a.str() < b.str(); }
};
using AttrPath = composite::Slice<AttrName>;

struct ExprSelect : Expr {
  Expr *e;
  AttrPath path;
  Expr *def;
  ExprSelect(Pos p, Expr *e, AttrPath path, Expr *def) : Expr(ExprKind::Select, p), e(e), path(path), def(def) {}
};
struct ExprHasAttr : Expr {
  Expr *e;
  AttrPath path;
  ExprHasAttr(Pos p, Expr *e, AttrPath path) : Expr(ExprKind::HasAttr, p), e(e), path(path) {}
};

struct ExprAttrs : Expr {
  enum class DefKind { Plain, Inherited, InheritedFrom };
  struct AttrDef {
    Expr *e;
    Pos pos;
    DefKind kind = DefKind::Plain;
  };
  struct DynamicAttrDef {
    Expr *nameExpr, *valueExpr;
    Pos pos;
  };
  struct Entry {
    Name name;
    AttrDef def;
  };
  bool recursive = false;
  /// The attributes in the order they were written, while the file is being parsed.  Nothing but the parser reads this:
  /// entries() is the set, ordered by name.  Over a handful of entries `index` finds one by name (open addressing over
  /// positions in `written`, plus one; 0 is empty); it is the parser's, and entries() drops it.
  composite::Grow<Entry> written;
  mutable uint32_t *index = nullptr;
  mutable uint32_t indexMask = 0;
  mutable bool ordered = true;
  composite::Grow<DynamicAttrDef> dynamicAttrs;
  composite::Grow<Expr *> inheritFromExprs;
  ExprAttrs(Pos p = {}) : Expr(ExprKind::Attrs, p) {}

  /// The attributes ordered by name text (deterministic, and what `--parse` prints).  The first ask orders them in
  /// place: the parser appends in source order, and a set that nothing reads (most of nixpkgs) is never ordered.
  composite::Slice<Entry> entries() const {
    if (!ordered) {
      std::sort(written.begin(), written.end(), [](const Entry &a, const Entry &b) { return a.name.str() < b.name.str(); });
      index = nullptr; // its positions moved
      ordered = true;
    }
    return written.done();
  }
};

struct ExprList : Expr {
  composite::Slice<Expr *> elems;
  ExprList(Pos p) : Expr(ExprKind::List, p) {}
};

struct Formal {
  Pos pos;
  Name name;
  Expr *def = nullptr;
};

struct ExprLambda : Expr {
  Name arg;                       // the null name when there is none
  bool hasFormals = false;
  composite::Slice<Formal> formals; // sorted by name
  bool ellipsis = false;
  Expr *body;
  Name name;                      // set when bound to an attribute (else the null name)
  ExprLambda(Pos p, Expr *body) : Expr(ExprKind::Lambda, p), body(body) {}
};

struct ExprCall : Expr {
  Expr *fun;
  composite::Slice<Expr *> args;
  ExprCall(Pos p, Expr *f, composite::Slice<Expr *> a) : Expr(ExprKind::Call, p), fun(f), args(a) {}
};

struct ExprLet : Expr {
  ExprAttrs *attrs;
  Expr *body;
  ExprLet(Pos p, ExprAttrs *a, Expr *b) : Expr(ExprKind::Let, p), attrs(a), body(b) {}
};
struct ExprWith : Expr {
  Expr *attrs, *body;
  ExprWith(Pos p, Expr *a, Expr *b) : Expr(ExprKind::With, p), attrs(a), body(b) {}
};
struct ExprIf : Expr {
  Expr *cond, *then, *else_;
  ExprIf(Pos p, Expr *c, Expr *t, Expr *e)
      : Expr(ExprKind::If, p), cond(c), then(t), else_(e) {}
};
struct ExprAssert : Expr {
  Expr *cond, *body;
  ExprAssert(Pos p, Expr *c, Expr *b) : Expr(ExprKind::Assert, p), cond(c), body(b) {}
};
struct ExprNot : Expr {
  Expr *e;
  ExprNot(Pos p, Expr *e) : Expr(ExprKind::Not, p), e(e) {}
};
struct ExprBin : Expr {
  Expr *e1, *e2;
  ExprBin(ExprKind k, Pos p, Expr *a, Expr *b) : Expr(k, p), e1(a), e2(b) {}
};
/// One piece of a string or path with interpolation: where it starts, and what it is.
struct StrPart {
  Pos pos;
  Expr *e;
};
struct ExprConcatStrings : Expr {
  bool forceString;
  composite::Slice<StrPart> es;
  ExprConcatStrings(Pos p, bool fs, composite::Slice<StrPart> es) : Expr(ExprKind::ConcatStrings, p), forceString(fs), es(es) {}
};

/// Where the nodes of the trees, and every array they hold, are made: the bump arena of the thread (Nix/Arena.h), which
/// is never freed and is shared by every parse on it.  A node costs one pointer bump, an array one more, and nothing is
/// destroyed or released: the evaluator keeps the trees for the life of the process, and so does this.
struct ExprArena {
  ExprArena() : r(&ofThisThread()) {}
  template <typename T, typename... A> T *add(A &&...a) {
    static_assert(std::is_trivially_destructible_v<T>, "a node is never destroyed: its arrays are Slices of the arena");
    return new (r->Allocate(sizeof(T), alignof(T))) T(std::forward<A>(a)...);
  }
  /// What composite::Grow allocates from.
  nixev::Arena &region() { return *r; }
  /// The cells given, as a Slice in the arena.
  template <class T> composite::Slice<T> slice(std::initializer_list<T> xs) {
    T *p = r->template Allocate<T>(xs.size());
    std::uninitialized_copy(xs.begin(), xs.end(), p);
    return {p, static_cast<uint32_t>(xs.size())};
  }

private:
  nixev::Arena *r;
  static nixev::Arena &ofThisThread() {
    static thread_local nixev::Arena *arena = new nixev::Arena();
    return *arena;
  }
};

enum class Lint { Ignore, Warn, Fatal };

struct ParseOptions {
  bool pipeOperators = false;
  Lint lintAbsolutePaths = Lint::Ignore, lintShortPaths = Lint::Ignore, lintUrls = Lint::Ignore;
  /// Receives lint warnings (formatted by the caller).
  std::function<void(const ParseError &)> onWarning;
  std::string home;                     // for ~/ paths
  std::vector<std::string> *warnings = nullptr;
};

/// Parse Nix source text.  Throws ParseError.
Expr *parse(ExprArena &arena, std::shared_ptr<Origin> origin,
            const ParseOptions &opts);

/// Print an expression in the format of `nix-instantiate --parse`.
void showExpr(std::ostream &os, const Expr *e);

/// Print a string literal with Nix escaping.
void printLiteralString(std::ostream &os, std::string_view s);
/// Print an identifier, quoting it if necessary.
void printIdentifier(std::ostream &os, std::string_view s);
bool isValidIdentifier(std::string_view s);

/// Canonicalise an absolute path ('.', '..', duplicate slashes).
std::string canonPath(std::string_view path);

} // namespace nixfe

#endif
