//===- CursorLowering.cpp - TrikeShed's series and cursor ops as loops over buffers ----------------------------------===//
//
// `trikeshed-lower-cursors`: the ops of borg.trikeshed.lib that a query is written in, lowered to scf, arith and memref, so
// the stock pipeline takes them on to LLVM.  The laws are the ones TrikeShed.td states for each op; this is one way to keep
// them with buffers.
//
//   !trikeshed.series<T>            memref<?xT>: a series is materialised where it is made (series, alpha, where, project)
//   !trikeshed.cursor<s, [T0..Tn]>  one memref<?xTi> per column (a 1:N conversion: a cursor argument becomes its columns)
//   trikeshed.key k                 read by `column` and `facet`, which take column k; erased once nothing reads it
//   column(c, k)                    the k-th buffer of c
//   size(xs), at(xs, i)             memref.dim, memref.load (an integer index is cast to index)
//   series(n) {k -> x}              a buffer of n, filled by a loop over the region
//   alpha(xs) {x -> y}              a buffer of size(xs), filled by a loop over the region
//   where(xs) {x -> b}              the elements for which the region yields true, in order: one loop into a buffer of
//                                   size(xs), whose first `count` cells are the result (a reinterpret_cast, no copy)
//   project(xs, idx)                a buffer of size(idx): xs[idx[i]]
//   fold(xs, z) {acc, x -> acc}     an scf.for carrying the accumulator
//   facet(c, k) {col -> r}          the region with col = column(c, k)
//   drain(xs, into)                 a loop storing xs into `into`; the result is size(xs)
//
// Buffers are allocated and never freed here: run --ownership-based-buffer-deallocation after this pass.  Casts the
// conversion leaves between a cursor and its buffers are reconciled at the end, so a caller that built its cursor from
// buffers ends up passing the buffers.  Not lowered:
// groupBy, pivot, keyedJoin and the other cursor combinators, the lazy (unmaterialised) form of a series, and series whose
// elements are not builtin types.
//
//===-----------------------------------------------------------------------------------------------------------------===//

#include "Composite/TrikeShed.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/Func/Transforms/FuncConversions.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Transforms/DialectConversion.h"

using namespace mlir;

namespace composite {
namespace {

MemRefType bufferOf(Type element) { return MemRefType::get({ShapedType::kDynamic}, element); }

struct CursorTypes : TypeConverter {
  CursorTypes() {
    addConversion([](Type t) { return t; });
    addConversion([](SeriesType t) -> Type { return bufferOf(t.getElement()); });
    addConversion([](CursorType t, SmallVectorImpl<Type> &out) -> std::optional<LogicalResult> {
      for (Type column : t.getColumns()) out.push_back(bufferOf(column));
      return success();
    });
  }
};

Value toIndex(OpBuilder &b, Location loc, Value v) {
  return v.getType().isIndex() ? v : arith::IndexCastOp::create(b, loc, b.getIndexType(), v).getResult();
}
Value length(OpBuilder &b, Location loc, Value buffer) { return memref::DimOp::create(b, loc, buffer, 0); }
Value newBuffer(OpBuilder &b, Location loc, Type element, Value n) {
  return memref::AllocOp::create(b, loc, bufferOf(element), ValueRange{n});
}

/// The column a key names: its trikeshed.key, checked against the cursor's schema and width.
FailureOr<unsigned> keyIndex(Operation *op, Value cursor, Value key, ConversionPatternRewriter &rw) {
  auto k = key.getDefiningOp<KeyOp>();
  if (!k) return rw.notifyMatchFailure(op, "the key is not a trikeshed.key");
  auto c = cast<CursorType>(cursor.getType());
  if (cast<ColKeyType>(key.getType()).getSchema() != c.getSchema()) return rw.notifyMatchFailure(op, "the key is of another schema");
  uint64_t i = k.getIndex();
  if (i >= c.getColumns().size()) return rw.notifyMatchFailure(op, "the key names no column of the cursor");
  return unsigned(i);
}

/// Inline the one block of `region` at the rewriter's insertion point, its arguments replaced by `args`; the values its
/// trikeshed.yield yielded.  The region's argument types are converted first (a series argument becomes its buffer).
FailureOr<SmallVector<Value>> inlineBody(ConversionPatternRewriter &rw, const TypeConverter &types, Region &region, ValueRange args) {
  if (failed(rw.convertRegionTypes(&region, types))) return failure();
  Block *block = &region.front();
  auto yield = dyn_cast<YieldOp>(block->getTerminator());
  if (!yield) return failure();
  SmallVector<Value> results(yield.getValues());
  rw.eraseOp(yield);
  rw.inlineBlockBefore(block, rw.getInsertionBlock(), rw.getInsertionPoint(), args);
  return results;
}

template <class Op> struct Lowering : OpConversionPattern<Op> {
  using OpConversionPattern<Op>::OpConversionPattern;
  const TypeConverter &types() const { return *this->getTypeConverter(); }
};

struct ColumnLowering : Lowering<ColumnOp> {
  using Lowering::Lowering;
  LogicalResult matchAndRewrite(ColumnOp op, OneToNOpAdaptor a, ConversionPatternRewriter &rw) const override {
    FailureOr<unsigned> i = keyIndex(op, op.getCursor(), op.getKey(), rw);
    if (failed(i)) return failure();
    rw.replaceOp(op, a.getCursor()[*i]);
    return success();
  }
};

struct FacetLowering : Lowering<FacetOp> {
  using Lowering::Lowering;
  LogicalResult matchAndRewrite(FacetOp op, OneToNOpAdaptor a, ConversionPatternRewriter &rw) const override {
    FailureOr<unsigned> i = keyIndex(op, op.getCursor(), op.getKey(), rw);
    if (failed(i)) return failure();
    auto body = inlineBody(rw, types(), op.getCompute(), ValueRange{a.getCursor()[*i]});
    if (failed(body) || body->size() != 1) return rw.notifyMatchFailure(op, "a facet's region yields one value");
    rw.replaceOp(op, (*body)[0]);
    return success();
  }
};

struct SizeLowering : Lowering<SizeOp> {
  using Lowering::Lowering;
  LogicalResult matchAndRewrite(SizeOp op, OpAdaptor a, ConversionPatternRewriter &rw) const override {
    rw.replaceOp(op, length(rw, op.getLoc(), a.getSeries()));
    return success();
  }
};

struct AtLowering : Lowering<AtOp> {
  using Lowering::Lowering;
  LogicalResult matchAndRewrite(AtOp op, OpAdaptor a, ConversionPatternRewriter &rw) const override {
    Value i = toIndex(rw, op.getLoc(), a.getIndex());
    rw.replaceOpWithNewOp<memref::LoadOp>(op, a.getSeries(), ValueRange{i});
    return success();
  }
};

/// series(n) {k -> x}, alpha(xs) {x -> y}: a buffer filled by a loop over the region.
struct SeriesLowering : Lowering<SeriesOp> {
  using Lowering::Lowering;
  LogicalResult matchAndRewrite(SeriesOp op, OpAdaptor a, ConversionPatternRewriter &rw) const override {
    Location loc = op.getLoc();
    Type element = cast<SeriesType>(op.getResult().getType()).getElement();
    Value n = a.getSize(), out = newBuffer(rw, loc, element, n);
    Value zero = arith::ConstantIndexOp::create(rw, loc, 0), one = arith::ConstantIndexOp::create(rw, loc, 1);
    auto loop = scf::ForOp::create(rw, loc, zero, n, one);
    rw.setInsertionPoint(loop.getBody()->getTerminator());
    auto body = inlineBody(rw, types(), op.getAt(), ValueRange{loop.getInductionVar()});
    if (failed(body) || body->size() != 1) return rw.notifyMatchFailure(op, "a series' region yields one value");
    memref::StoreOp::create(rw, loc, (*body)[0], out, ValueRange{loop.getInductionVar()});
    rw.setInsertionPointAfter(loop);
    rw.replaceOp(op, out);
    return success();
  }
};

struct AlphaLowering : Lowering<AlphaOp> {
  using Lowering::Lowering;
  LogicalResult matchAndRewrite(AlphaOp op, OpAdaptor a, ConversionPatternRewriter &rw) const override {
    Location loc = op.getLoc();
    Type element = cast<SeriesType>(op.getResult().getType()).getElement();
    Value xs = a.getSeries(), n = length(rw, loc, xs), out = newBuffer(rw, loc, element, n);
    Value zero = arith::ConstantIndexOp::create(rw, loc, 0), one = arith::ConstantIndexOp::create(rw, loc, 1);
    auto loop = scf::ForOp::create(rw, loc, zero, n, one);
    rw.setInsertionPoint(loop.getBody()->getTerminator());
    Value x = memref::LoadOp::create(rw, loc, xs, ValueRange{loop.getInductionVar()});
    auto body = inlineBody(rw, types(), op.getXform(), ValueRange{x});
    if (failed(body) || body->size() != 1) return rw.notifyMatchFailure(op, "α's region yields one value");
    memref::StoreOp::create(rw, loc, (*body)[0], out, ValueRange{loop.getInductionVar()});
    rw.setInsertionPointAfter(loop);
    rw.replaceOp(op, out);
    return success();
  }
};

/// where(xs) {x -> b}: one loop storing each element whose region yields true at the next free cell; the first `count`
/// cells, as a buffer of that size, are the result.
struct WhereLowering : Lowering<WhereOp> {
  using Lowering::Lowering;
  LogicalResult matchAndRewrite(WhereOp op, OpAdaptor a, ConversionPatternRewriter &rw) const override {
    Location loc = op.getLoc();
    Type element = cast<SeriesType>(op.getResult().getType()).getElement();
    Value xs = a.getSeries(), n = length(rw, loc, xs), out = newBuffer(rw, loc, element, n);
    Value zero = arith::ConstantIndexOp::create(rw, loc, 0), one = arith::ConstantIndexOp::create(rw, loc, 1);
    auto loop = scf::ForOp::create(rw, loc, zero, n, one, ValueRange{zero});
    Block *step = loop.getBody();
    rw.setInsertionPointToEnd(step);
    Value count = loop.getRegionIterArgs()[0];
    Value x = memref::LoadOp::create(rw, loc, xs, ValueRange{loop.getInductionVar()});
    auto body = inlineBody(rw, types(), op.getPredicate(), ValueRange{x});
    if (failed(body) || body->size() != 1) return rw.notifyMatchFailure(op, "where's region yields one i1");
    Value keep = (*body)[0];
    auto store = scf::IfOp::create(rw, loc, keep, /*withElseRegion=*/false);
    rw.setInsertionPoint(store.thenBlock()->getTerminator());
    memref::StoreOp::create(rw, loc, x, out, ValueRange{count});
    rw.setInsertionPointAfter(store);
    Value next = arith::SelectOp::create(rw, loc, keep, arith::AddIOp::create(rw, loc, count, one), count);
    scf::YieldOp::create(rw, loc, ValueRange{next});
    rw.setInsertionPointAfter(loop);
    Value kept = memref::ReinterpretCastOp::create(rw, loc, bufferOf(element), out, OpFoldResult(rw.getIndexAttr(0)),
                                                   ArrayRef<OpFoldResult>{loop.getResult(0)},
                                                   ArrayRef<OpFoldResult>{rw.getIndexAttr(1)}).getResult();
    rw.replaceOp(op, kept);
    return success();
  }
};

struct ProjectLowering : Lowering<ProjectOp> {
  using Lowering::Lowering;
  LogicalResult matchAndRewrite(ProjectOp op, OpAdaptor a, ConversionPatternRewriter &rw) const override {
    Location loc = op.getLoc();
    Type element = cast<SeriesType>(op.getResult().getType()).getElement();
    Value xs = a.getSeries(), idx = a.getIndex(), n = length(rw, loc, idx), out = newBuffer(rw, loc, element, n);
    Value zero = arith::ConstantIndexOp::create(rw, loc, 0), one = arith::ConstantIndexOp::create(rw, loc, 1);
    auto loop = scf::ForOp::create(rw, loc, zero, n, one);
    rw.setInsertionPoint(loop.getBody()->getTerminator());
    Value j = toIndex(rw, loc, memref::LoadOp::create(rw, loc, idx, ValueRange{loop.getInductionVar()}));
    Value x = memref::LoadOp::create(rw, loc, xs, ValueRange{j});
    memref::StoreOp::create(rw, loc, x, out, ValueRange{loop.getInductionVar()});
    rw.setInsertionPointAfter(loop);
    rw.replaceOp(op, out);
    return success();
  }
};

struct FoldLowering : Lowering<FoldOp> {
  using Lowering::Lowering;
  LogicalResult matchAndRewrite(FoldOp op, OpAdaptor a, ConversionPatternRewriter &rw) const override {
    Location loc = op.getLoc();
    Value xs = a.getSeries(), n = length(rw, loc, xs);
    Value zero = arith::ConstantIndexOp::create(rw, loc, 0), one = arith::ConstantIndexOp::create(rw, loc, 1);
    auto loop = scf::ForOp::create(rw, loc, zero, n, one, ValueRange{a.getZero()});
    rw.setInsertionPointToEnd(loop.getBody());
    Value x = memref::LoadOp::create(rw, loc, xs, ValueRange{loop.getInductionVar()});
    auto body = inlineBody(rw, types(), op.getCombine(), ValueRange{loop.getRegionIterArgs()[0], x});
    if (failed(body) || body->size() != 1) return rw.notifyMatchFailure(op, "fold's region yields one value");
    scf::YieldOp::create(rw, loc, ValueRange{(*body)[0]});
    rw.setInsertionPointAfter(loop);
    rw.replaceOp(op, loop.getResult(0));
    return success();
  }
};

struct DrainLowering : Lowering<DrainOp> {
  using Lowering::Lowering;
  LogicalResult matchAndRewrite(DrainOp op, OpAdaptor a, ConversionPatternRewriter &rw) const override {
    Location loc = op.getLoc();
    if (!isa<MemRefType>(a.getInto().getType())) return rw.notifyMatchFailure(op, "drain needs a memref to write into");
    Value xs = a.getSeries(), n = length(rw, loc, xs);
    Value zero = arith::ConstantIndexOp::create(rw, loc, 0), one = arith::ConstantIndexOp::create(rw, loc, 1);
    auto loop = scf::ForOp::create(rw, loc, zero, n, one);
    rw.setInsertionPoint(loop.getBody()->getTerminator());
    Value x = memref::LoadOp::create(rw, loc, xs, ValueRange{loop.getInductionVar()});
    memref::StoreOp::create(rw, loc, x, a.getInto(), ValueRange{loop.getInductionVar()});
    rw.setInsertionPointAfter(loop);
    Type end = op.getEnd().getType();
    rw.replaceOp(op, end.isIndex() ? n : arith::IndexCastOp::create(rw, loc, end, n).getResult());
    return success();
  }
};

struct LowerCursors : PassWrapper<LowerCursors, OperationPass<ModuleOp>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(LowerCursors)
  StringRef getArgument() const final { return "trikeshed-lower-cursors"; }
  StringRef getDescription() const final { return "Lower TrikeShed's series and cursor ops to scf, arith and memref"; }
  void getDependentDialects(DialectRegistry &r) const final {
    r.insert<arith::ArithDialect, func::FuncDialect, memref::MemRefDialect, scf::SCFDialect>();
  }
  void runOnOperation() final {
    MLIRContext *ctx = &getContext();
    CursorTypes types;
    ConversionTarget target(*ctx);
    target.addLegalDialect<arith::ArithDialect, memref::MemRefDialect, scf::SCFDialect>();
    target.addIllegalDialect<TrikeShedDialect>();
    target.addLegalOp<KeyOp>(); // read by the patterns, erased below
    target.addLegalOp<ClusterOrderOp>(); // trikeshed-lower-clusters' business
    target.addDynamicallyLegalOp<func::FuncOp>(
        [&](func::FuncOp f) { return types.isSignatureLegal(f.getFunctionType()) && types.isLegal(&f.getBody()); });
    target.addDynamicallyLegalOp<func::ReturnOp, func::CallOp>([&](Operation *op) { return types.isLegal(op); });

    RewritePatternSet patterns(ctx);
    patterns.add<ColumnLowering, FacetLowering, SizeLowering, AtLowering, SeriesLowering, AlphaLowering, WhereLowering,
                 ProjectLowering, FoldLowering, DrainLowering>(types, ctx);
    populateFunctionOpInterfaceTypeConversionPattern<func::FuncOp>(patterns, types);
    populateReturnOpTypeConversionPattern(patterns, types);
    populateCallOpTypeConversionPattern(patterns, types);
    if (failed(applyPartialConversion(getOperation(), target, std::move(patterns)))) return signalPassFailure();

    // A caller that made its cursor from buffers (a cast to !trikeshed.cursor) now hands it straight to a callee that takes
    // the buffers back (the conversion's cast from it): the pair cancels.  Casts not touching a trikeshed type are left.
    auto touches = [](TypeRange ts) { return llvm::any_of(ts, [](Type t) { return isa<SeriesType, CursorType>(t); }); };
    SmallVector<UnrealizedConversionCastOp> casts;
    getOperation().walk([&](UnrealizedConversionCastOp c) {
      if (touches(c.getInputs().getTypes()) || touches(c.getResultTypes())) casts.push_back(c);
    });
    reconcileUnrealizedCasts(casts);

    bool used = false;
    getOperation().walk([&](KeyOp k) {
      if (k->use_empty()) k->erase();
      else { k.emitError("a key still read after lowering"); used = true; }
    });
    if (used) signalPassFailure();
  }
};

} // namespace

void registerCursorLowering() { PassRegistration<LowerCursors>(); }

} // namespace composite
