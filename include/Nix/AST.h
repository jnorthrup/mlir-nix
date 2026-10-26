//===- AST.h - Nix abstract syntax tree -----------------------*- C++ -*-===//
//
// Mirrors upstream Nix's Expr hierarchy closely (same desugarings), so that
// `--parse` output and scoping semantics are identical.
//
//===----------------------------------------------------------------------===//
#ifndef NIX_AST_H
#define NIX_AST_H

#include <cstdint>
#include <deque>
#include <functional>
#include <map>
#include <memory>
#include <optional>
#include <ostream>
#include <stdexcept>
#include <string>
#include <vector>

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

struct Expr {
  ExprKind kind;
  Pos pos;
  explicit Expr(ExprKind k, Pos p = {}) : kind(k), pos(p) {}
  virtual ~Expr() = default;
};

struct ExprInt : Expr { int64_t v; ExprInt(int64_t v) : Expr(ExprKind::Int), v(v) {} };
struct ExprFloat : Expr { double v; ExprFloat(double v) : Expr(ExprKind::Float), v(v) {} };
struct ExprString : Expr {
  std::string v;
  ExprString(std::string v) : Expr(ExprKind::String), v(std::move(v)) {}
};
struct ExprPath : Expr {
  std::string v;
  ExprPath(std::string v) : Expr(ExprKind::Path), v(std::move(v)) {}
};
struct ExprVar : Expr {
  std::string name;
  ExprVar(Pos p, std::string n) : Expr(ExprKind::Var, p), name(std::move(n)) {}
};
struct ExprCurPos : Expr { ExprCurPos(Pos p) : Expr(ExprKind::CurPos, p) {} };

/// Placeholder for `inherit (e) ...`: refers to attrs->inheritFromExprs[displ].
struct ExprInheritFrom : Expr {
  size_t displ;
  ExprInheritFrom(Pos p, size_t d) : Expr(ExprKind::InheritFrom, p), displ(d) {}
};

struct AttrName {
  std::optional<std::string> symbol;
  Expr *expr = nullptr;
  AttrName(std::string s) : symbol(std::move(s)) {}
  AttrName(Expr *e) : expr(e) {}
};
using AttrPath = std::vector<AttrName>;

struct ExprSelect : Expr {
  Expr *e;
  AttrPath path;
  Expr *def;
  ExprSelect(Pos p, Expr *e, AttrPath path, Expr *def)
      : Expr(ExprKind::Select, p), e(e), path(std::move(path)), def(def) {}
};
struct ExprHasAttr : Expr {
  Expr *e;
  AttrPath path;
  ExprHasAttr(Pos p, Expr *e, AttrPath path)
      : Expr(ExprKind::HasAttr, p), e(e), path(std::move(path)) {}
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
  bool recursive = false;
  std::map<std::string, AttrDef> attrs; // ordered by name (deterministic)
  std::vector<DynamicAttrDef> dynamicAttrs;
  std::vector<Expr *> inheritFromExprs;
  ExprAttrs(Pos p = {}) : Expr(ExprKind::Attrs, p) {}
};

struct ExprList : Expr {
  std::vector<Expr *> elems;
  ExprList(Pos p) : Expr(ExprKind::List, p) {}
};

struct Formal {
  Pos pos;
  std::string name;
  Expr *def = nullptr;
};

struct ExprLambda : Expr {
  std::string arg;                // may be empty
  bool hasFormals = false;
  std::vector<Formal> formals;    // sorted by name
  bool ellipsis = false;
  Expr *body;
  std::string name;               // set when bound to an attribute
  ExprLambda(Pos p, Expr *body) : Expr(ExprKind::Lambda, p), body(body) {}
};

struct ExprCall : Expr {
  Expr *fun;
  std::vector<Expr *> args;
  ExprCall(Pos p, Expr *f, std::vector<Expr *> a)
      : Expr(ExprKind::Call, p), fun(f), args(std::move(a)) {}
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
struct ExprConcatStrings : Expr {
  bool forceString;
  std::vector<std::pair<Pos, Expr *>> es;
  ExprConcatStrings(Pos p, bool fs, std::vector<std::pair<Pos, Expr *>> es)
      : Expr(ExprKind::ConcatStrings, p), forceString(fs), es(std::move(es)) {}
};

/// Owns all nodes of one parse.
struct ExprArena {
  std::deque<std::unique_ptr<Expr>> nodes;
  template <typename T, typename... A> T *add(A &&...a) {
    auto p = std::make_unique<T>(std::forward<A>(a)...);
    T *r = p.get();
    nodes.push_back(std::move(p));
    return r;
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
