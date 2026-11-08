//===- KifImport.cpp - KIF text into a kif.theory ---------------------------===//
//
// The reader of sumo-nix/kif.nix, in the dialect: the same tokens (its tokenPattern), the same forms.  A term is made once:
// atoms by their text, lists by their elements, so the theory holds each distinct term as one node and a later text read into
// the same theory reuses the nodes of the earlier ones (Merge.kif's classes are one atom for all 78 files of sumo.full).
//
//===----------------------------------------------------------------------===//

#include "NixDialect/Kif.h"

#include "mlir/IR/Builders.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringMap.h"
#include "llvm/Support/Allocator.h"

namespace mlir::kif {

struct KifInterner {
  TheoryOp theory;
  OpBuilder b;
  Location loc;
  llvm::StringMap<Value> atoms;                    // an atom or a variable, by its text
  llvm::DenseMap<ArrayRef<Value>, Value> lists;     // a list, by its elements (the keys live in `keys`)
  llvm::BumpPtrAllocator keys;
  uint64_t nAtoms = 0, nVars = 0, nLists = 0;
  Type term;

  explicit KifInterner(TheoryOp t) : theory(t), b(t.getContext()), loc(t.getLoc()), term(TermType::get(t.getContext())) {
    Block &body = t.getBody().empty() ? t.getBody().emplaceBlock() : t.getBody().front();
    b.setInsertionPointToEnd(&body);
    // terms already in the theory are found again (a second import, or a theory read from text)
    for (Operation &op : body) {
      if (auto a = dyn_cast<AtomOp>(op)) atoms.try_emplace(a.getName(), a.getTerm());
      else if (auto v = dyn_cast<VarOp>(op)) atoms.try_emplace(v.getName(), v.getTerm());
      else if (auto l = dyn_cast<ListOp>(op)) {
        SmallVector<Value, 8> es(l.getElements().begin(), l.getElements().end());
        lists.try_emplace(copyKey(es), l.getTerm());
      }
    }
  }

  ArrayRef<Value> copyKey(ArrayRef<Value> es) {
    Value *p = keys.Allocate<Value>(es.size());
    for (size_t i = 0; i < es.size(); i++) new (p + i) Value(es[i]);
    return ArrayRef<Value>(p, es.size());
  }

  Value atom(StringRef text) {
    auto [it, fresh] = atoms.try_emplace(text, Value());
    if (!fresh) return it->second;
    // a variable is an atom that starts with ?, and has a name after it (a lone ? is an atom)
    if (text.size() >= 2 && text[0] == '?') {
      ++nVars;
      return it->second = VarOp::create(b, loc, term, it->first());
    }
    ++nAtoms;
    return it->second = AtomOp::create(b, loc, term, it->first());
  }

  Value list(ArrayRef<Value> es) {
    if (auto it = lists.find(es); it != lists.end()) return it->second;
    ++nLists;
    Value l = ListOp::create(b, loc, term, es);
    lists.try_emplace(copyKey(es), l);
    return l;
  }
};

KifInterner *newInterner(TheoryOp theory) { return new KifInterner(theory); }
void freeInterner(KifInterner *i) { delete i; }
void internCounts(const KifInterner &i, uint64_t &atoms, uint64_t &vars, uint64_t &lists) {
  atoms = i.nAtoms;
  vars = i.nVars;
  lists = i.nLists;
}

LogicalResult importKif(KifInterner &in, StringRef name, StringRef s, int32_t file) {
  // the lists being read, innermost last, as one stack of elements: `open` holds where each one starts
  SmallVector<Value, 256> elems;
  SmallVector<uint32_t, 32> open;
  IntegerAttr fileAttr = in.b.getI32IntegerAttr(file);
  auto isArrow = [](Value v) { auto a = v.getDefiningOp<AtomOp>(); return a && a.getName() == "=>"; };
  auto top = [&](Value t) {
    if (auto l = t.getDefiningOp<ListOp>(); l && l.getElements().size() == 3 && isArrow(l.getElements()[0])) {
      RuleOp::create(in.b, in.loc, l.getElements()[1], l.getElements()[2], fileAttr);
    } else {
      FactOp::create(in.b, in.loc, t, fileAttr);
    }
  };
  auto isOther = [](char c) { return c != ' ' && c != '\t' && c != '\n' && c != '(' && c != ')' && c != '"' && c != ';'; };
  size_t i = 0, n = s.size();
  while (i < n) {
    char c = s[i];
    if (c == '(') {
      open.push_back(uint32_t(elems.size()));
      i++;
      continue;
    }
    if (c == ')') {
      if (open.empty()) return emitError(in.loc) << name << ": unbalanced ')' at offset " << i;
      uint32_t at = open.pop_back_val();
      Value l = in.list(ArrayRef<Value>(elems).drop_front(at));
      elems.truncate(at);
      if (open.empty()) top(l);
      else elems.push_back(l);
      i++;
      continue;
    }
    if (c == ';') { // a comment, to the end of the line
      while (i < n && s[i] != '\n') i++;
      continue;
    }
    size_t st = i;
    if (c == '"') {
      // a string: "([^"\\]|\\.)*" -- kif.nix's regex; one that never closes is no token, and its characters are read as others
      size_t j = i + 1;
      while (j < n && s[j] != '"') j += (s[j] == '\\' && j + 1 < n) ? 2 : 1;
      if (j >= n) { // no closing quote: the regex matches nothing at this '"', which split keeps as text
        i++;
        continue;
      }
      i = j + 1;
    } else if (isOther(c)) {
      while (i < n && isOther(s[i])) i++;
    } else { // a space, a tab or a newline
      i++;
      continue;
    }
    Value a = in.atom(s.substr(st, i - st));
    if (open.empty()) top(a);
    else elems.push_back(a);
  }
  if (!open.empty()) return emitError(in.loc) << name << ": unclosed '('";
  return success();
}

} // namespace mlir::kif
