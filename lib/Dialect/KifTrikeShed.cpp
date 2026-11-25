//===- KifTrikeShed.cpp - A KIF theory as TrikeShed's series and cursors: kif-to-trikeshed ------------------------===//
//
// PRELOAD-DIALECTS step 6: a theory's terms, facts and rules as TrikeShed's forms (`Series<Term>`; a theory's facts are a
// Cursor), so the queries over them are trikeshed ops that `trikeshed-lower-cursors` takes to loops, as sumo-nix's
// sumo.nix takes them to Nix.  `kif.terms`, `kif.facts` and `kif.rules` name a theory; this pass lays the theory's tables
// out as constant buffers (memref.global), hands each op's results over as those buffers seen as the series and cursors
// the op's types say, and then removes the theories, so what remains is the trikeshed and memref of the queries.
//
//   kif.terms  the terms in the theory's order, a term's number its row: tag (0 atom, 1 variable, 2 list), name (start,
//              length) in the names text, kids (first, count) in the kid series; plus the kid series and the names text
//   kif.facts  each kif.fact: (term, file)
//   kif.rules  each kif.rule: (antecedent, consequent, file)
//   kif.atom_row  the row of an atom, a constant (-1 when the theory has none)
//
// Not lowered: kif.derived (the chase's proofs), and sumo ops still in a theory (run sumo-to-kif first: an error).
//
//===-----------------------------------------------------------------------------------------------------------------===//

#include "NixDialect/Kif.h"

#include "Composite/Text.h"
#include "Composite/TrikeShed.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/Pass.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/StringMap.h"

namespace mlir::kif {

namespace {
bool isSeriesOf(Type t, unsigned width) {
  auto s = dyn_cast<composite::SeriesType>(t);
  return s && s.getElement().isSignlessInteger(width);
}
bool isPair(Type t) {
  auto p = dyn_cast<composite::TwinPackedType>(t);
  return p && p.getElement().isSignlessInteger(32);
}
/// a cursor of this schema whose columns pass these checks
bool isCursor(Type t, StringRef schema, ArrayRef<bool (*)(Type)> columns) {
  auto c = dyn_cast<composite::CursorType>(t);
  if (!c || c.getSchema().getValue() != schema || c.getColumns().size() != columns.size()) return false;
  for (auto [type, ok] : llvm::zip(c.getColumns(), columns))
    if (!ok(type)) return false;
  return true;
}
auto i32Column = [](Type t) { return t.isSignlessInteger(32); };
LogicalResult theoryUse(Operation *op, FlatSymbolRefAttr name, SymbolTableCollection &symbols) {
  if (!symbols.lookupNearestSymbolFrom<TheoryOp>(op, name)) return op->emitOpError("names no kif.theory: ") << name;
  return success();
}
} // namespace

LogicalResult TermsOp::verify() {
  if (!isCursor(getTerms().getType(), "KifTerm",
                {[](Type t) { return t.isSignlessInteger(8); }, isPair, isPair}))
    return emitOpError("gives the terms as !trikeshed.cursor<\"KifTerm\", [i8, !trikeshed.twinpacked<i32>, "
                       "!trikeshed.twinpacked<i32>]>");
  if (!isSeriesOf(getKids().getType(), 32)) return emitOpError("gives the kids as a !trikeshed.series<i32>");
  if (!isSeriesOf(getNames().getType(), 8)) return emitOpError("gives the names as a !trikeshed.series<i8>");
  return success();
}
LogicalResult TermsOp::verifySymbolUses(SymbolTableCollection &symbols) { return theoryUse(*this, getTheoryAttr(), symbols); }

LogicalResult FactsOp::verify() {
  if (!isCursor(getFacts().getType(), "KifFact", {i32Column, i32Column}))
    return emitOpError("gives the facts as !trikeshed.cursor<\"KifFact\", [i32, i32]>");
  return success();
}
LogicalResult FactsOp::verifySymbolUses(SymbolTableCollection &symbols) { return theoryUse(*this, getTheoryAttr(), symbols); }

LogicalResult RulesOp::verify() {
  if (!isCursor(getRules().getType(), "KifRule", {i32Column, i32Column, i32Column}))
    return emitOpError("gives the rules as !trikeshed.cursor<\"KifRule\", [i32, i32, i32]>");
  return success();
}
LogicalResult RulesOp::verifySymbolUses(SymbolTableCollection &symbols) { return theoryUse(*this, getTheoryAttr(), symbols); }
LogicalResult AtomRowOp::verifySymbolUses(SymbolTableCollection &symbols) { return theoryUse(*this, getTheoryAttr(), symbols); }

namespace {

/// A theory's tables, as kif.terms, kif.facts and kif.rules give them.
struct Tables {
  SmallVector<int8_t> tag;
  SmallVector<int64_t> name, kids; // (start << 32 | length), (first << 32 | count)
  SmallVector<int32_t> kid;
  composite::Text names;
  SmallVector<int32_t> factTerm, factFile, ruleAntecedent, ruleConsequent, ruleFile;
  llvm::StringMap<int32_t> atomRow; // an atom's row (its first, where a name repeats): kif.atom_row
};

int64_t pack(uint64_t a, uint64_t b) { return int64_t(a << 32 | (b & 0xffffffffu)); }

FailureOr<Tables> tablesOf(TheoryOp theory) {
  Tables t;
  llvm::DenseMap<Value, int32_t> row;
  Block &body = theory.getBody().front();
  // the rows first: a graph region may use a term before the op that makes it
  for (Operation &op : body)
    if (isa<AtomOp, VarOp, ListOp>(op)) row[op.getResult(0)] = int32_t(row.size());
  auto rowOf = [&](Value v) -> int32_t { return row.lookup(v); };
  for (Operation &op : body) {
    if (auto a = dyn_cast<AtomOp>(op)) {
      t.atomRow.try_emplace(a.getName(), int32_t(t.tag.size()));
      t.tag.push_back(0);
      t.name.push_back(pack(t.names.size(), a.getName().size()));
      t.names += a.getName();
      t.kids.push_back(0);
    } else if (auto v = dyn_cast<VarOp>(op)) {
      t.tag.push_back(1);
      t.name.push_back(pack(t.names.size(), v.getName().size()));
      t.names += v.getName();
      t.kids.push_back(0);
    } else if (auto l = dyn_cast<ListOp>(op)) {
      t.tag.push_back(2);
      t.name.push_back(0);
      t.kids.push_back(pack(t.kid.size(), l.getElements().size()));
      for (Value e : l.getElements()) t.kid.push_back(rowOf(e));
    } else if (auto f = dyn_cast<FactOp>(op)) {
      t.factTerm.push_back(rowOf(f.getTerm()));
      t.factFile.push_back(f.getFile() ? int32_t(*f.getFile()) : -1);
    } else if (auto r = dyn_cast<RuleOp>(op)) {
      t.ruleAntecedent.push_back(rowOf(r.getAntecedent()));
      t.ruleConsequent.push_back(rowOf(r.getConsequent()));
      t.ruleFile.push_back(r.getFile() ? int32_t(*r.getFile()) : -1);
    } else if (isa<DerivedOp>(op)) {
      // the chase's proofs: not lowered yet
    } else {
      return theory.emitOpError("holds an op kif-to-trikeshed does not lower (run sumo-to-kif first): ")
             << op.getName();
    }
  }
  if (t.names.size() > INT32_MAX || t.kid.size() > INT32_MAX) return theory.emitOpError("is larger than 2^31 names or kids");
  return t;
}

struct KifToTrikeShedPass : PassWrapper<KifToTrikeShedPass, OperationPass<ModuleOp>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(KifToTrikeShedPass)
  StringRef getArgument() const override { return "kif-to-trikeshed"; }
  StringRef getDescription() const override {
    return "Lay each kif.terms, kif.facts and kif.rules out as constant buffers seen as TrikeShed's series and cursors, "
           "and remove the theories";
  }
  void getDependentDialects(DialectRegistry &registry) const override {
    registry.insert<arith::ArithDialect, memref::MemRefDialect, composite::TrikeShedDialect>();
  }

  void runOnOperation() override {
    ModuleOp module = getOperation();
    SymbolTable symbols(module);
    llvm::DenseMap<Operation *, Tables> tables; // each theory's tables, read once: the layout and kif.atom_row use them
    auto tablesFor = [&](TheoryOp theory) -> Tables * {
      if (auto it = tables.find(theory); it != tables.end()) return &it->second;
      FailureOr<Tables> t = tablesOf(theory);
      return failed(t) ? nullptr : &tables.try_emplace(theory, std::move(*t)).first->second;
    };
    OpBuilder top(module.getBodyRegion());

    auto global = [&](TheoryOp theory, StringRef what, Type element, ArrayRef<char> raw, int64_t n) -> memref::GlobalOp {
      composite::Text name = composite::cat("__kif_", theory.getSymName(), '_', what);
      auto type = MemRefType::get({n}, element);
      auto data = DenseElementsAttr::getFromRawBuffer(RankedTensorType::get({n}, element), raw);
      top.setInsertionPointToEnd(module.getBody());
      auto g = memref::GlobalOp::create(top, theory.getLoc(), name, top.getStringAttr("private"), type, data,
                                        /*constant=*/true, /*alignment=*/IntegerAttr());
      symbols.insert(g); // renamed if the name is taken
      return g;
    };
    // the buffer of a table, seen as a series' buffer (memref<?xT, strided<[1], offset: ?>>)
    auto view = [&](OpBuilder &b, Location loc, memref::GlobalOp g) -> Value {
      auto type = cast<MemRefType>(g.getType());
      Value whole = memref::GetGlobalOp::create(b, loc, type, g.getSymName());
      auto series = MemRefType::get({ShapedType::kDynamic}, type.getElementType(),
                                    StridedLayoutAttr::get(b.getContext(), ShapedType::kDynamic, {1}));
      return memref::CastOp::create(b, loc, series, whole);
    };
    llvm::DenseMap<Operation *, SmallVector<memref::GlobalOp>> laid;
    auto layOut = [&](TheoryOp theory) -> FailureOr<SmallVector<memref::GlobalOp>> {
      auto it = laid.find(theory);
      if (it != laid.end()) return it->second;
      Tables *t = tablesFor(theory);
      if (!t) return failure();
      auto i8 = IntegerType::get(&getContext(), 8), i32 = IntegerType::get(&getContext(), 32),
           i64 = IntegerType::get(&getContext(), 64);
      auto bytes = [](auto &v) { return ArrayRef<char>(reinterpret_cast<const char *>(v.data()), v.size() * sizeof(v[0])); };
      SmallVector<memref::GlobalOp> g{
          global(theory, "tag", i8, bytes(t->tag), t->tag.size()),
          global(theory, "name", i64, bytes(t->name), t->name.size()),
          global(theory, "kids", i64, bytes(t->kids), t->kids.size()),
          global(theory, "kid", i32, bytes(t->kid), t->kid.size()),
          global(theory, "names", i8, ArrayRef<char>(t->names.data(), t->names.size()), t->names.size()),
          global(theory, "fact_term", i32, bytes(t->factTerm), t->factTerm.size()),
          global(theory, "fact_file", i32, bytes(t->factFile), t->factFile.size()),
          global(theory, "rule_antecedent", i32, bytes(t->ruleAntecedent), t->ruleAntecedent.size()),
          global(theory, "rule_consequent", i32, bytes(t->ruleConsequent), t->ruleConsequent.size()),
          global(theory, "rule_file", i32, bytes(t->ruleFile), t->ruleFile.size())};
      laid[theory] = g;
      return g;
    };

    // kif.atom_row: a constant, the atom's row in the theory's tables (-1 when the theory has no such atom)
    SmallVector<AtomRowOp> rowUses;
    module.walk([&](AtomRowOp op) { rowUses.push_back(op); });
    for (AtomRowOp op : rowUses) {
      auto theory = symbols.lookup<TheoryOp>(op.getTheory());
      if (!theory) {
        op.emitOpError("names no kif.theory: ") << op.getTheoryAttr();
        return signalPassFailure();
      }
      Tables *t = tablesFor(theory);
      if (!t) return signalPassFailure();
      auto found = t->atomRow.find(op.getName());
      int32_t row = found == t->atomRow.end() ? -1 : found->second;
      OpBuilder b(op);
      op.replaceAllUsesWith(arith::ConstantOp::create(b, op.getLoc(), b.getI32IntegerAttr(row)).getResult());
      op.erase();
    }

    SmallVector<Operation *> uses;
    module.walk([&](Operation *op) {
      if (isa<TermsOp, FactsOp, RulesOp>(op)) uses.push_back(op);
    });
    for (Operation *op : uses) {
      auto name = op->getAttrOfType<FlatSymbolRefAttr>("theory");
      auto theory = symbols.lookup<TheoryOp>(name.getValue());
      if (!theory) {
        op->emitOpError("names no kif.theory: ") << name;
        return signalPassFailure();
      }
      FailureOr<SmallVector<memref::GlobalOp>> g = layOut(theory);
      if (failed(g)) return signalPassFailure();
      OpBuilder b(op);
      Location loc = op->getLoc();
      auto seen = [&](Type to, ValueRange from) -> Value {
        return UnrealizedConversionCastOp::create(b, loc, TypeRange{to}, from).getResult(0);
      };
      SmallVector<Value> results;
      if (auto terms = dyn_cast<TermsOp>(op)) {
        results.push_back(seen(terms.getTerms().getType(), {view(b, loc, (*g)[0]), view(b, loc, (*g)[1]), view(b, loc, (*g)[2])}));
        results.push_back(seen(terms.getKids().getType(), {view(b, loc, (*g)[3])}));
        results.push_back(seen(terms.getNames().getType(), {view(b, loc, (*g)[4])}));
      } else if (auto facts = dyn_cast<FactsOp>(op)) {
        results.push_back(seen(facts.getFacts().getType(), {view(b, loc, (*g)[5]), view(b, loc, (*g)[6])}));
      } else {
        auto rules = cast<RulesOp>(op);
        results.push_back(seen(rules.getRules().getType(), {view(b, loc, (*g)[7]), view(b, loc, (*g)[8]), view(b, loc, (*g)[9])}));
      }
      op->replaceAllUsesWith(results);
      op->erase();
    }
    // the theories, their tables laid out where they were used
    SmallVector<TheoryOp> theories(module.getOps<TheoryOp>());
    for (TheoryOp t : theories) t.erase();
  }
};
} // namespace

void registerKifToTrikeShedPass() { PassRegistration<KifToTrikeShedPass>(); }

} // namespace mlir::kif
