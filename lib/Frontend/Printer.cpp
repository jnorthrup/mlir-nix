//===- Printer.cpp - `nix-instantiate --parse` style AST printing ---------===//

#include "Nix/AST.h"

#include <algorithm>
#include <map>
#include <sstream>

namespace nixfe {

void printLiteralString(std::ostream &str, std::string_view s) {
  str << '"';
  for (size_t i = 0; i < s.size(); i++) {
    char c = s[i];
    if (c == '"' || c == '\\') str << '\\' << c;
    else if (c == '\n') str << "\\n";
    else if (c == '\r') str << "\\r";
    else if (c == '\t') str << "\\t";
    else if (c == '$' && i + 1 < s.size() && s[i + 1] == '{') str << "\\$";
    else str << c;
  }
  str << '"';
}

static bool isReservedKeyword(std::string_view s) {
  static const char *kws[] = {"if", "then", "else", "assert", "with", "let", "in", "rec", "inherit"};
  for (auto *k : kws)
    if (s == k) return true;
  return false;
}

bool isValidIdentifier(std::string_view s) {
  if (s.empty() || isReservedKeyword(s)) return false;
  char c = s[0];
  if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_')) return false;
  for (char c : s)
    if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') ||
          c == '_' || c == '\'' || c == '-'))
      return false;
  return true;
}

void printIdentifier(std::ostream &str, std::string_view s) {
  if (s.empty()) { str << "\"\""; return; }
  if (isReservedKeyword(s)) { str << '"' << s << '"'; return; }
  if (!isValidIdentifier(s)) { printLiteralString(str, s); return; }
  str << s;
}

static std::string_view sv(const Name &n) { return {n.data, n.size}; }

static void showAttrPath(std::ostream &os, const AttrPath &path) {
  bool first = true;
  for (auto &a : path) {
    if (!first) os << '.';
    first = false;
    if (!a.computed()) printIdentifier(os, sv(a.symbol));
    else { os << "\"${"; showExpr(os, a.expr); os << "}\""; }
  }
}

static void showBindings(std::ostream &str, const ExprAttrs *a) {
  // entries() are ordered by name: the order `--parse` prints.
  std::vector<Name> inherits;
  std::map<size_t, std::vector<Name>> inheritsFrom;
  for (auto &[name, def] : a->entries()) {
    if (def.kind == ExprAttrs::DefKind::Inherited) inherits.push_back(name);
    else if (def.kind == ExprAttrs::DefKind::InheritedFrom) {
      auto *sel = static_cast<const ExprSelect *>(def.e);
      auto *from = static_cast<const ExprInheritFrom *>(sel->e);
      inheritsFrom[from->displ].push_back(name);
    }
  }
  if (!inherits.empty()) {
    str << "inherit";
    for (auto &s : inherits) { str << ' '; printIdentifier(str, sv(s)); }
    str << "; ";
  }
  for (auto &[from, syms] : inheritsFrom) {
    str << "inherit (";
    showExpr(str, a->inheritFromExprs[from]);
    str << ")";
    for (auto &s : syms) { str << ' '; printIdentifier(str, sv(s)); }
    str << "; ";
  }
  for (auto &[name, def] : a->entries()) {
    if (def.kind != ExprAttrs::DefKind::Plain) continue;
    printIdentifier(str, sv(name));
    str << " = ";
    showExpr(str, def.e);
    str << "; ";
  }
  for (auto &d : a->dynamicAttrs) {
    str << "\"${";
    showExpr(str, d.nameExpr);
    str << "}\" = ";
    showExpr(str, d.valueExpr);
    str << "; ";
  }
}

void showExpr(std::ostream &str, const Expr *e) {
  switch (e->kind) {
  case ExprKind::Int: str << static_cast<const ExprInt *>(e)->v; break;
  case ExprKind::Float: {
    std::ostringstream os;
    os << static_cast<const ExprFloat *>(e)->v;
    str << os.str();
    break;
  }
  case ExprKind::String: printLiteralString(str, sv(static_cast<const ExprString *>(e)->v)); break;
  case ExprKind::Path: str << sv(static_cast<const ExprPath *>(e)->v); break;
  case ExprKind::Var: printIdentifier(str, sv(static_cast<const ExprVar *>(e)->name)); break;
  case ExprKind::CurPos: str << "__curPos"; break;
  case ExprKind::InheritFrom: str << "<inherit-from>"; break;
  case ExprKind::Select: {
    auto *s = static_cast<const ExprSelect *>(e);
    str << "(";
    showExpr(str, s->e);
    str << ").";
    showAttrPath(str, s->path);
    if (s->def) { str << " or ("; showExpr(str, s->def); str << ")"; }
    break;
  }
  case ExprKind::HasAttr: {
    auto *h = static_cast<const ExprHasAttr *>(e);
    str << "((";
    showExpr(str, h->e);
    str << ") ? ";
    showAttrPath(str, h->path);
    str << ")";
    break;
  }
  case ExprKind::Attrs: {
    auto *a = static_cast<const ExprAttrs *>(e);
    if (a->recursive) str << "rec ";
    str << "{ ";
    showBindings(str, a);
    str << "}";
    break;
  }
  case ExprKind::List: {
    str << "[ ";
    for (auto *i : static_cast<const ExprList *>(e)->elems) {
      str << "(";
      showExpr(str, i);
      str << ") ";
    }
    str << "]";
    break;
  }
  case ExprKind::Lambda: {
    auto *l = static_cast<const ExprLambda *>(e);
    str << "(";
    if (l->hasFormals) {
      str << "{ ";
      bool first = true;
      for (auto &f : l->formals) {
        if (first) first = false;
        else str << ", ";
        printIdentifier(str, sv(f.name));
        if (f.def) { str << " ? "; showExpr(str, f.def); }
      }
      if (l->ellipsis) {
        if (!first) str << ", ";
        str << "...";
      }
      str << " }";
      if (!l->arg.isNull()) str << " @ ";
    }
    if (!l->arg.isNull()) printIdentifier(str, sv(l->arg));
    str << ": ";
    showExpr(str, l->body);
    str << ")";
    break;
  }
  case ExprKind::Call: {
    auto *c = static_cast<const ExprCall *>(e);
    str << '(';
    showExpr(str, c->fun);
    for (auto *a : c->args) { str << ' '; showExpr(str, a); }
    str << ')';
    break;
  }
  case ExprKind::Let: {
    auto *l = static_cast<const ExprLet *>(e);
    str << "(let ";
    showBindings(str, l->attrs);
    str << "in ";
    showExpr(str, l->body);
    str << ")";
    break;
  }
  case ExprKind::With: {
    auto *w = static_cast<const ExprWith *>(e);
    str << "(with ";
    showExpr(str, w->attrs);
    str << "; ";
    showExpr(str, w->body);
    str << ")";
    break;
  }
  case ExprKind::If: {
    auto *i = static_cast<const ExprIf *>(e);
    str << "(if ";
    showExpr(str, i->cond);
    str << " then ";
    showExpr(str, i->then);
    str << " else ";
    showExpr(str, i->else_);
    str << ")";
    break;
  }
  case ExprKind::Assert: {
    auto *a = static_cast<const ExprAssert *>(e);
    str << "assert ";
    showExpr(str, a->cond);
    str << "; ";
    showExpr(str, a->body);
    break;
  }
  case ExprKind::Not:
    str << "(! ";
    showExpr(str, static_cast<const ExprNot *>(e)->e);
    str << ")";
    break;
  case ExprKind::Eq: case ExprKind::NEq: case ExprKind::And: case ExprKind::Or:
  case ExprKind::Impl: case ExprKind::Update: case ExprKind::ConcatLists: {
    auto *b = static_cast<const ExprBin *>(e);
    const char *op = e->kind == ExprKind::Eq ? "==" : e->kind == ExprKind::NEq ? "!="
                   : e->kind == ExprKind::And ? "&&" : e->kind == ExprKind::Or ? "||"
                   : e->kind == ExprKind::Impl ? "->" : e->kind == ExprKind::Update ? "//" : "++";
    str << "(";
    showExpr(str, b->e1);
    str << " " << op << " ";
    showExpr(str, b->e2);
    str << ")";
    break;
  }
  case ExprKind::ConcatStrings: {
    auto *c = static_cast<const ExprConcatStrings *>(e);
    bool first = true;
    str << "(";
    for (auto &[p, x] : c->es) {
      if (first) first = false;
      else str << " + ";
      showExpr(str, x);
    }
    str << ")";
    break;
  }
  }
}

} // namespace nixfe
