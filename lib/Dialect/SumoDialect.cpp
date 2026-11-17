//===- SumoDialect.cpp - The SUMO dialect, sumo-to-kif, and sumo.relation's lowering below TrikeShed ------------------===//

#include "NixDialect/Sumo.h"

#include "Composite/CursorLowering.h"
#include "Composite/TrikeShed.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/DialectImplementation.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Transforms/DialectConversion.h"
#include "llvm/ADT/SmallString.h"

#include "NixDialect/SumoDialect.cpp.inc"

#define GET_OP_CLASSES
#include "NixDialect/Sumo.cpp.inc"

namespace mlir::sumo {

namespace {
bool i32Series(Type t) {
  auto s = dyn_cast<composite::SeriesType>(t);
  return s && s.getElement().isSignlessInteger(32);
}
/// a cursor of this schema (any schema when empty) whose columns are i32, or this many columns of any type when width > 0
bool cursorOf(Type t, StringRef schema, size_t width, bool allI32) {
  auto c = dyn_cast<composite::CursorType>(t);
  if (!c || (!schema.empty() && c.getSchema().getValue() != schema)) return false;
  if (width && c.getColumns().size() != width) return false;
  if (allI32)
    for (Type column : c.getColumns())
      if (!column.isSignlessInteger(32)) return false;
  return !c.getColumns().empty();
}
} // namespace

LogicalResult RelationOp::verify() {
  if (!cursorOf(getFacts().getType(), "KifFact", 2, true))
    return emitOpError("reads the facts as kif.facts gives them: !trikeshed.cursor<\"KifFact\", [i32, i32]>");
  if (!cursorOf(getTerms().getType(), "KifTerm", 3, false))
    return emitOpError("reads the terms as kif.terms gives them: !trikeshed.cursor<\"KifTerm\", [i8, tp, tp]>");
  if (!i32Series(getKids().getType())) return emitOpError("reads the kids as a !trikeshed.series<i32>");
  if (!cursorOf(getRows().getType(), "", 0, true))
    return emitOpError("gives a cursor of one i32 column per argument (term rows)");
  return success();
}

namespace {
Value cIndex(OpBuilder &b, Location loc, int64_t v) { return arith::ConstantIndexOp::create(b, loc, v); }
Value cInt(OpBuilder &b, Location loc, Type t, int64_t v) { return arith::ConstantOp::create(b, loc, t, b.getIntegerAttr(t, v)); }
Value asIndex(OpBuilder &b, Location loc, Value v) {
  return v.getType().isIndex() ? v : arith::IndexCastOp::create(b, loc, b.getIndexType(), v).getResult();
}
Value load(OpBuilder &b, Location loc, Value buffer, Value i) {
  return memref::LoadOp::create(b, loc, buffer, ValueRange{asIndex(b, loc, i)});
}
void store(OpBuilder &b, Location loc, Value v, Value buffer, Value i) {
  memref::StoreOp::create(b, loc, v, buffer, ValueRange{asIndex(b, loc, i)});
}

/// sumo.relation: two passes over the facts, the first counting the rows a fact gives (one or none), the second writing
/// each kept fact's arguments into the columns.  A fact is kept when its term is a list (tag 2) of arity + 1 elements whose
/// first is the relation and none of whose arguments is a list.
struct RelationLowering : OpConversionPattern<RelationOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(RelationOp op, OneToNOpAdaptor a, ConversionPatternRewriter &rw) const override {
    Location loc = op.getLoc();
    if (a.getFacts().size() != 2 || a.getTerms().size() != 3 || a.getKids().size() != 1 || a.getRelation().size() != 1)
      return rw.notifyMatchFailure(op, "the tables are not the buffers of kif.facts and kif.terms");
    Value factTerm = a.getFacts()[0], tag = a.getTerms()[0], kids = a.getTerms()[2], kid = a.getKids().front();
    Value relation = a.getRelation().front();
    size_t arity = cast<composite::CursorType>(op.getRows().getType()).getColumns().size();
    Type i8 = rw.getI8Type(), i64 = rw.getI64Type(), idx = rw.getIndexType();
    Value zero = cIndex(rw, loc, 0), one = cIndex(rw, loc, 1);
    Value c32 = cInt(rw, loc, i64, 32), mask = cInt(rw, loc, i64, 0xffffffff), list = cInt(rw, loc, i8, 2);
    Value width = cInt(rw, loc, i64, int64_t(arity + 1));
    Value n = memref::DimOp::create(rw, loc, factTerm, 0);
    auto firstOf = [&](Value fc) -> Value {
      return arith::IndexCastUIOp::create(rw, loc, idx, arith::ShRUIOp::create(rw, loc, fc, c32));
    };
    // is term t one of the relation's rows
    auto kept = [&](Value t) -> Value {
      Value isList = arith::CmpIOp::create(rw, loc, arith::CmpIPredicate::eq, load(rw, loc, tag, t), list);
      auto ifList = scf::IfOp::create(rw, loc, TypeRange{rw.getI1Type()}, isList, /*withElseRegion=*/true);
      rw.setInsertionPointToStart(ifList.elseBlock());
      scf::YieldOp::create(rw, loc, ValueRange{cInt(rw, loc, rw.getI1Type(), 0)});
      rw.setInsertionPointToStart(ifList.thenBlock());
      Value fc = load(rw, loc, kids, t);
      Value sized = arith::CmpIOp::create(rw, loc, arith::CmpIPredicate::eq, arith::AndIOp::create(rw, loc, fc, mask), width);
      auto ifSized = scf::IfOp::create(rw, loc, TypeRange{rw.getI1Type()}, sized, /*withElseRegion=*/true);
      rw.setInsertionPointToStart(ifSized.elseBlock());
      scf::YieldOp::create(rw, loc, ValueRange{cInt(rw, loc, rw.getI1Type(), 0)});
      rw.setInsertionPointToStart(ifSized.thenBlock());
      Value first = firstOf(fc);
      Value ok = arith::CmpIOp::create(rw, loc, arith::CmpIPredicate::eq, load(rw, loc, kid, first), relation);
      for (size_t c = 0; c < arity; c++) {
        Value arg = load(rw, loc, kid, arith::AddIOp::create(rw, loc, first, cIndex(rw, loc, int64_t(c + 1))));
        Value notList = arith::CmpIOp::create(rw, loc, arith::CmpIPredicate::ne, load(rw, loc, tag, arg), list);
        ok = arith::AndIOp::create(rw, loc, ok, notList);
      }
      scf::YieldOp::create(rw, loc, ValueRange{ok});
      rw.setInsertionPointAfter(ifSized);
      scf::YieldOp::create(rw, loc, ifSized.getResults());
      rw.setInsertionPointAfter(ifList);
      return ifList.getResult(0);
    };
    auto counting = scf::ForOp::create(rw, loc, zero, n, one, ValueRange{zero});
    rw.setInsertionPointToEnd(counting.getBody());
    {
      Value t = load(rw, loc, factTerm, counting.getInductionVar());
      Value add = arith::SelectOp::create(rw, loc, kept(t), one, zero);
      scf::YieldOp::create(rw, loc, ValueRange{arith::AddIOp::create(rw, loc, counting.getRegionIterArgs()[0], add).getResult()});
    }
    rw.setInsertionPointAfter(counting);
    SmallVector<Value> columns;
    for (size_t c = 0; c < arity; c++)
      columns.push_back(composite::newSeriesBuffer(rw, loc, rw.getI32Type(), counting.getResult(0)));
    auto writing = scf::ForOp::create(rw, loc, zero, n, one, ValueRange{zero});
    rw.setInsertionPointToEnd(writing.getBody());
    {
      Value j = writing.getRegionIterArgs()[0];
      Value t = load(rw, loc, factTerm, writing.getInductionVar());
      auto ifKept = scf::IfOp::create(rw, loc, TypeRange{idx}, kept(t), /*withElseRegion=*/true);
      rw.setInsertionPointToStart(ifKept.thenBlock());
      Value first = firstOf(load(rw, loc, kids, t));
      for (size_t c = 0; c < arity; c++)
        store(rw, loc, load(rw, loc, kid, arith::AddIOp::create(rw, loc, first, cIndex(rw, loc, int64_t(c + 1)))), columns[c], j);
      scf::YieldOp::create(rw, loc, ValueRange{arith::AddIOp::create(rw, loc, j, one).getResult()});
      rw.setInsertionPointToStart(ifKept.elseBlock());
      scf::YieldOp::create(rw, loc, ValueRange{j});
      rw.setInsertionPointAfter(ifKept);
      scf::YieldOp::create(rw, loc, ifKept.getResults());
    }
    rw.setInsertionPointAfter(writing);
    SmallVector<SmallVector<Value>> results{columns};
    rw.replaceOpWithMultiple(op, std::move(results));
    return success();
  }
};

struct SumoCursorLowering : composite::CursorLoweringInterface {
  using CursorLoweringInterface::CursorLoweringInterface;
  void populateCursorLowering(const TypeConverter &types, RewritePatternSet &patterns, ConversionTarget &target) const override {
    patterns.add<RelationLowering>(types, patterns.getContext());
    target.addIllegalOp<RelationOp>();
  }
};
} // namespace

void SumoDialect::initialize() {
  addOperations<
#define GET_OP_LIST
#include "NixDialect/Sumo.cpp.inc"
      >();
  addInterfaces<SumoCursorLowering>();
}

namespace {
/// `(word word ..)` as a fact, just before op.
void fact(Operation *op, ArrayRef<StringRef> words) {
  OpBuilder b(op);
  auto term = b.getType<kif::TermType>();
  SmallVector<Value> atoms;
  for (StringRef w : words)
    atoms.push_back(kif::AtomOp::create(b, op->getLoc(), term, b.getStringAttr(w)));
  kif::FactOp::create(b, op->getLoc(), kif::ListOp::create(b, op->getLoc(), term, atoms), IntegerAttr());
}

struct SumoToKifPass : PassWrapper<SumoToKifPass, OperationPass<ModuleOp>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(SumoToKifPass)
  StringRef getArgument() const override { return "sumo-to-kif"; }
  StringRef getDescription() const override { return "Lower sumo relations to kif facts"; }
  void getDependentDialects(DialectRegistry &registry) const override { registry.insert<kif::KifDialect>(); }

  void runOnOperation() override {
    SmallVector<Operation *> ops;
    getOperation().walk([&](Operation *op) {
      if (isa<SubclassOp, InstanceOp, DomainOp, RangeOp, HoldsOp>(op))
        ops.push_back(op);
    });
    for (Operation *op : ops) {
      SmallString<16> pos; // a position's decimal digits: the one word not already held by the context
      if (auto s = dyn_cast<SubclassOp>(op))
        fact(op, {"subclass", s.getChild(), s.getParent()});
      else if (auto i = dyn_cast<InstanceOp>(op))
        fact(op, {"instance", i.getThing(), i.getClassName()});
      else if (auto d = dyn_cast<DomainOp>(op))
        fact(op, {"domain", d.getRelation(), Twine(d.getPosition()).toStringRef(pos), d.getClassName()});
      else if (auto r = dyn_cast<RangeOp>(op))
        fact(op, {"range", r.getRelation(), Twine(r.getPosition()).toStringRef(pos), r.getClassName()});
      else {
        auto h = cast<HoldsOp>(op);
        SmallVector<StringRef> words{h.getRelation()}; // views on the context's uniqued attributes
        for (Attribute a : h.getArgs())
          words.push_back(cast<StringAttr>(a).getValue());
        fact(op, words);
      }
      op->erase();
    }
  }
};
} // namespace

void registerSumoPasses() {
  static const bool registered = [] {
    PassRegistration<SumoToKifPass>();
    return true;
  }();
  (void)registered;
}

} // namespace mlir::sumo
