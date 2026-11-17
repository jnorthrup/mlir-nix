//===- CursorLowering.cpp - TrikeShed's series and cursor ops as loops over buffers ----------------------------------===//
//
// `trikeshed-lower-cursors`: the ops of borg.trikeshed.lib that a query is written in, lowered to scf, arith and memref, so
// the stock pipeline takes them on to LLVM.  The laws are the ones TrikeShed.td states for each op; this is one way to keep
// them with buffers.
//
//   !trikeshed.series<T>            memref<?xT, strided<[1], offset: ?>>: a series is materialised where it is made
//                                   (series, alpha, where, project, sorted); a slice is a view at an offset
//   !trikeshed.cursor<s, [T0..Tn]>  one such buffer per column (a 1:N conversion: a cursor argument becomes its columns)
//   a pair of two i32 halves        one i64, the first half high (Pack.h's TwInt): Join<i32, i32>, Twin<i32>, TwinPacked<i32>
//   trikeshed.key k                 read by `column` and `facet`, which take column k; erased once nothing reads it
//   column(c, k)                    the k-th buffer of c
//   size(xs), at(xs, i)             memref.dim, memref.load (an integer index is cast to index)
//   series(n) {k -> x}              a buffer of n, filled by a loop over the region
//   alpha(xs) {x -> y}              a buffer of size(xs), filled by a loop over the region
//   where(xs) {x -> b}              the elements for which the region yields true, in order: one loop into a buffer of
//                                   size(xs), whose first `count` cells are the result (a subview, no copy)
//   project(xs, idx)                a buffer of size(idx): xs[idx[i]]
//   slice(xs, off, n)               a subview: the same buffer at an offset
//   fold(xs, z) {acc, x -> acc}     an scf.for carrying the accumulator
//   compare(a, b) [unsigned]        a loop to the first difference, then the sizes: -1, 0 or 1
//   sorted(xs) [by {a, b -> c}]     a stable bottom-up merge sort into a new buffer; the region is the comparator
//   bisect(xs, k) [by {x, k -> c}]  a binary search: the index, or -(insertion) - 1
//   j, first, second                shifts of the i64 that a pair of i32 halves is
//   facet(c, k) {col -> r}          the region with col = column(c, k)
//   drain(xs, into)                 a loop storing xs into `into`; the result is size(xs)
//   parts(xs, d)                    Series.div: count the delimiters, then each part's (start, length)
//   text(buffer)                    a constant's 1-D buffer, cast to the series' strided layout
//   adjacency(from, to, n)          a counting sort: each node's (first, count) into the far ends, in edge order
//   closure(parents, above)         ClosureIndex: two walks from each node over its parents (count, then write)
//
// Buffers are allocated and never freed here: run --ownership-based-buffer-deallocation after this pass.  A slice's offset
// is an affine.apply once --expand-strided-metadata has run: run --lower-affine before --finalize-memref-to-llvm.  Casts the
// conversion leaves between a cursor and its buffers are reconciled at the end, so a caller that built its cursor from
// buffers ends up passing the buffers.  A dialect below TrikeShed (confix: its index and its Columns facet) adds its
// patterns through CursorLoweringInterface (Composite/CursorLowering.h).  Not lowered: groupBy, pivot, keyedJoin and the
// other cursor combinators, text, combine, joins, contains, zipnext, the lazy (unmaterialised) form of a series, and series
// whose elements are neither builtin types nor pairs of two i32.
//
//===-----------------------------------------------------------------------------------------------------------------===//

#include "Composite/CursorLowering.h"
#include "Composite/TrikeShed.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/Func/Transforms/FuncConversions.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/SCF/Transforms/Patterns.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Transforms/DialectConversion.h"

using namespace mlir;

MLIR_DEFINE_EXPLICIT_TYPE_ID(composite::CursorLoweringInterface)

namespace composite {

MemRefType seriesBuffer(Type element) {
  return MemRefType::get({ShapedType::kDynamic}, element,
                         StridedLayoutAttr::get(element.getContext(), ShapedType::kDynamic, {1}));
}

Value newSeriesBuffer(OpBuilder &b, Location loc, Type element, Value n) {
  Value fresh = memref::AllocOp::create(b, loc, MemRefType::get({ShapedType::kDynamic}, element), ValueRange{n});
  return memref::CastOp::create(b, loc, seriesBuffer(element), fresh);
}

namespace {

/// The half type of a pair of two equal 32-bit integers (Join<i32, i32>, Twin<i32>, TwinPacked<i32>), else null.
Type pairHalf(Type t) {
  Type a, b;
  if (auto j = dyn_cast<JoinType>(t)) a = j.getA(), b = j.getB();
  else if (auto w = dyn_cast<TwinType>(t)) a = b = w.getElement();
  else if (auto p = dyn_cast<TwinPackedType>(t)) a = b = p.getElement();
  else return {};
  return a == b && a.isSignlessInteger(32) ? a : Type{};
}

struct CursorTypes : TypeConverter {
  CursorTypes() {
    addConversion([](Type t) { return t; });
    addConversion([](Type t) -> std::optional<Type> {
      if (!isa<JoinType, TwinType, TwinPackedType>(t) || !pairHalf(t)) return std::nullopt;
      return IntegerType::get(t.getContext(), 64);
    });
    addConversion([this](SeriesType t) -> std::optional<Type> {
      Type e = convertType(t.getElement());
      if (!e || !BaseMemRefType::isValidElementType(e)) return std::nullopt;
      return seriesBuffer(e);
    });
    addConversion([this](CursorType t, SmallVectorImpl<Type> &out) -> std::optional<LogicalResult> {
      for (Type column : t.getColumns()) {
        Type e = convertType(column);
        if (!e || !BaseMemRefType::isValidElementType(e)) return std::nullopt;
        out.push_back(seriesBuffer(e));
      }
      return success();
    });
  }
};

Value toIndex(OpBuilder &b, Location loc, Value v) {
  return v.getType().isIndex() ? v : arith::IndexCastOp::create(b, loc, b.getIndexType(), v).getResult();
}
Value length(OpBuilder &b, Location loc, Value buffer) { return memref::DimOp::create(b, loc, buffer, 0); }
Value cIndex(OpBuilder &b, Location loc, int64_t v) { return arith::ConstantIndexOp::create(b, loc, v); }
Value cInt(OpBuilder &b, Location loc, Type t, int64_t v) { return arith::ConstantOp::create(b, loc, t, b.getIntegerAttr(t, v)); }
Value load(OpBuilder &b, Location loc, Value buffer, Value i) {
  return memref::LoadOp::create(b, loc, buffer, ValueRange{toIndex(b, loc, i)});
}
void store(OpBuilder &b, Location loc, Value v, Value buffer, Value i) {
  memref::StoreOp::create(b, loc, v, buffer, ValueRange{toIndex(b, loc, i)});
}

/// The element type of a series after conversion.
Type elementOf(const TypeConverter &types, Type series) { return types.convertType(cast<SeriesType>(series).getElement()); }

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
/// trikeshed.yield yielded, as the converted values (a pair yielded by a j that is lowered after this is the i64 the j
/// becomes: the conversion casts it until then).  The region's argument types are converted first (a series argument
/// becomes its buffer).
FailureOr<SmallVector<Value>> inlineBody(ConversionPatternRewriter &rw, const TypeConverter &types, Region &region, ValueRange args) {
  if (failed(rw.convertRegionTypes(&region, types))) return failure();
  Block *block = &region.front();
  auto yield = dyn_cast<YieldOp>(block->getTerminator());
  if (!yield) return failure();
  SmallVector<Value> yielded(yield.getValues());
  rw.eraseOp(yield);
  rw.inlineBlockBefore(block, rw.getInsertionBlock(), rw.getInsertionPoint(), args);
  SmallVector<Value> results;
  for (Value v : yielded) {
    Value r = rw.getRemappedValue(v);
    if (!r) return failure();
    results.push_back(r);
  }
  return results;
}

/// The order of two integers, signed or unsigned: -1, 0 or 1 as an i32.
Value threeWay(OpBuilder &b, Location loc, Value x, Value y, bool isUnsigned = false) {
  Type i32 = b.getI32Type();
  Value lt = arith::CmpIOp::create(b, loc, isUnsigned ? arith::CmpIPredicate::ult : arith::CmpIPredicate::slt, x, y);
  Value gt = arith::CmpIOp::create(b, loc, isUnsigned ? arith::CmpIPredicate::ugt : arith::CmpIPredicate::sgt, x, y);
  Value one = cInt(b, loc, i32, 1), zero = cInt(b, loc, i32, 0), minus = cInt(b, loc, i32, -1);
  return arith::SelectOp::create(b, loc, lt, minus, arith::SelectOp::create(b, loc, gt, one, zero));
}

/// The comparison of x and y: the op's order region, inlined here, or the signed order of two integers of one type.
FailureOr<Value> order(ConversionPatternRewriter &rw, const TypeConverter &types, Location loc, Region &region, Value x, Value y) {
  if (region.empty()) {
    if (!isa<IntegerType>(x.getType()) || x.getType() != y.getType()) return failure();
    return threeWay(rw, loc, x, y);
  }
  auto body = inlineBody(rw, types, region, ValueRange{x, y});
  if (failed(body) || body->size() != 1 || !(*body)[0].getType().isSignlessInteger(32)) return failure();
  return (*body)[0];
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
    rw.replaceOp(op, load(rw, op.getLoc(), a.getSeries(), a.getIndex()));
    return success();
  }
};

/// series(n) {k -> x}: a buffer filled by a loop over the region.
struct SeriesLowering : Lowering<SeriesOp> {
  using Lowering::Lowering;
  LogicalResult matchAndRewrite(SeriesOp op, OpAdaptor a, ConversionPatternRewriter &rw) const override {
    Location loc = op.getLoc();
    Type element = elementOf(types(), op.getResult().getType());
    Value n = a.getSize(), out = newSeriesBuffer(rw, loc, element, n);
    auto loop = scf::ForOp::create(rw, loc, cIndex(rw, loc, 0), n, cIndex(rw, loc, 1));
    rw.setInsertionPoint(loop.getBody()->getTerminator());
    auto body = inlineBody(rw, types(), op.getAt(), ValueRange{loop.getInductionVar()});
    if (failed(body) || body->size() != 1) return rw.notifyMatchFailure(op, "a series' region yields one value");
    store(rw, loc, (*body)[0], out, loop.getInductionVar());
    rw.setInsertionPointAfter(loop);
    rw.replaceOp(op, out);
    return success();
  }
};

/// alpha(xs) {x -> y}: a buffer of size(xs) filled by a loop over the region.
struct AlphaLowering : Lowering<AlphaOp> {
  using Lowering::Lowering;
  LogicalResult matchAndRewrite(AlphaOp op, OpAdaptor a, ConversionPatternRewriter &rw) const override {
    Location loc = op.getLoc();
    Type element = elementOf(types(), op.getResult().getType());
    Value xs = a.getSeries(), n = length(rw, loc, xs), out = newSeriesBuffer(rw, loc, element, n);
    auto loop = scf::ForOp::create(rw, loc, cIndex(rw, loc, 0), n, cIndex(rw, loc, 1));
    rw.setInsertionPoint(loop.getBody()->getTerminator());
    Value x = load(rw, loc, xs, loop.getInductionVar());
    auto body = inlineBody(rw, types(), op.getXform(), ValueRange{x});
    if (failed(body) || body->size() != 1) return rw.notifyMatchFailure(op, "α's region yields one value");
    store(rw, loc, (*body)[0], out, loop.getInductionVar());
    rw.setInsertionPointAfter(loop);
    rw.replaceOp(op, out);
    return success();
  }
};

/// where(xs) {x -> b}: one loop storing each element whose region yields true at the next free cell; the first `count`
/// cells, as a view of that size, are the result.
struct WhereLowering : Lowering<WhereOp> {
  using Lowering::Lowering;
  LogicalResult matchAndRewrite(WhereOp op, OpAdaptor a, ConversionPatternRewriter &rw) const override {
    Location loc = op.getLoc();
    Type element = elementOf(types(), op.getResult().getType());
    Value xs = a.getSeries(), n = length(rw, loc, xs), out = newSeriesBuffer(rw, loc, element, n);
    Value zero = cIndex(rw, loc, 0), one = cIndex(rw, loc, 1);
    auto loop = scf::ForOp::create(rw, loc, zero, n, one, ValueRange{zero});
    rw.setInsertionPointToEnd(loop.getBody());
    Value count = loop.getRegionIterArgs()[0];
    Value x = load(rw, loc, xs, loop.getInductionVar());
    auto body = inlineBody(rw, types(), op.getPredicate(), ValueRange{x});
    if (failed(body) || body->size() != 1) return rw.notifyMatchFailure(op, "where's region yields one i1");
    Value keep = (*body)[0];
    auto put = scf::IfOp::create(rw, loc, keep, /*withElseRegion=*/false);
    rw.setInsertionPoint(put.thenBlock()->getTerminator());
    store(rw, loc, x, out, count);
    rw.setInsertionPointAfter(put);
    Value next = arith::SelectOp::create(rw, loc, keep, arith::AddIOp::create(rw, loc, count, one), count);
    scf::YieldOp::create(rw, loc, ValueRange{next});
    rw.setInsertionPointAfter(loop);
    Value kept = memref::SubViewOp::create(rw, loc, out, ArrayRef<OpFoldResult>{rw.getIndexAttr(0)},
                                           ArrayRef<OpFoldResult>{loop.getResult(0)}, ArrayRef<OpFoldResult>{rw.getIndexAttr(1)});
    if (kept.getType() != out.getType()) kept = memref::CastOp::create(rw, loc, out.getType(), kept);
    rw.replaceOp(op, kept);
    return success();
  }
};

struct ProjectLowering : Lowering<ProjectOp> {
  using Lowering::Lowering;
  LogicalResult matchAndRewrite(ProjectOp op, OpAdaptor a, ConversionPatternRewriter &rw) const override {
    Location loc = op.getLoc();
    Type element = elementOf(types(), op.getResult().getType());
    Value xs = a.getSeries(), idx = a.getIndex(), n = length(rw, loc, idx), out = newSeriesBuffer(rw, loc, element, n);
    auto loop = scf::ForOp::create(rw, loc, cIndex(rw, loc, 0), n, cIndex(rw, loc, 1));
    rw.setInsertionPoint(loop.getBody()->getTerminator());
    Value j = load(rw, loc, idx, loop.getInductionVar());
    store(rw, loc, load(rw, loc, xs, j), out, loop.getInductionVar());
    rw.setInsertionPointAfter(loop);
    rw.replaceOp(op, out);
    return success();
  }
};

/// xs[off, n]: a view of the same buffer.
/// text(witness): a constant's 1-D buffer seen as the series' buffer (a cast to the strided layout).
struct TextLowering : Lowering<TextOp> {
  using Lowering::Lowering;
  LogicalResult matchAndRewrite(TextOp op, OpAdaptor a, ConversionPatternRewriter &rw) const override {
    auto buffer = dyn_cast<MemRefType>(a.getWitness().getType());
    auto want = dyn_cast_or_null<MemRefType>(getTypeConverter()->convertType(op.getResult().getType()));
    if (!buffer || !want || buffer.getRank() != 1 || buffer.getElementType() != want.getElementType())
      return rw.notifyMatchFailure(op, "the witness is not a 1-D buffer of the series' elements");
    rw.replaceOp(op, memref::CastOp::create(rw, op.getLoc(), want, a.getWitness()).getResult());
    return success();
  }
};
struct SliceLowering : Lowering<SliceOp> {
  using Lowering::Lowering;
  LogicalResult matchAndRewrite(SliceOp op, OpAdaptor a, ConversionPatternRewriter &rw) const override {
    Location loc = op.getLoc();
    Value xs = a.getSeries();
    Value view = memref::SubViewOp::create(rw, loc, xs, ArrayRef<OpFoldResult>{a.getOffset()}, ArrayRef<OpFoldResult>{a.getCount()},
                                           ArrayRef<OpFoldResult>{rw.getIndexAttr(1)});
    if (view.getType() != xs.getType()) view = memref::CastOp::create(rw, loc, xs.getType(), view);
    rw.replaceOp(op, view);
    return success();
  }
};

struct FoldLowering : Lowering<FoldOp> {
  using Lowering::Lowering;
  LogicalResult matchAndRewrite(FoldOp op, OpAdaptor a, ConversionPatternRewriter &rw) const override {
    Location loc = op.getLoc();
    Value xs = a.getSeries(), n = length(rw, loc, xs);
    auto loop = scf::ForOp::create(rw, loc, cIndex(rw, loc, 0), n, cIndex(rw, loc, 1), ValueRange{a.getZero()});
    rw.setInsertionPointToEnd(loop.getBody());
    Value x = load(rw, loc, xs, loop.getInductionVar());
    auto body = inlineBody(rw, types(), op.getCombine(), ValueRange{loop.getRegionIterArgs()[0], x});
    if (failed(body) || body->size() != 1) return rw.notifyMatchFailure(op, "fold's region yields one value");
    scf::YieldOp::create(rw, loc, ValueRange{(*body)[0]});
    rw.setInsertionPointAfter(loop);
    rw.replaceOp(op, loop.getResult(0));
    return success();
  }
};

/// compare(a, b) [unsigned]: walk to the first difference within the shorter length; there, the order of the two
/// elements (signed, or unsigned), else the order of the sizes.
struct CompareLowering : Lowering<CompareOp> {
  using Lowering::Lowering;
  LogicalResult matchAndRewrite(CompareOp op, OpAdaptor a, ConversionPatternRewriter &rw) const override {
    Location loc = op.getLoc();
    Value xs = a.getA(), ys = a.getB();
    Type ex = cast<MemRefType>(xs.getType()).getElementType(), ey = cast<MemRefType>(ys.getType()).getElementType();
    if (ex != ey || !isa<IntegerType>(ex)) return rw.notifyMatchFailure(op, "compare takes two series of one integer type");
    Type idx = rw.getIndexType(), i1 = rw.getI1Type();
    Value na = length(rw, loc, xs), nb = length(rw, loc, ys);
    Value m = arith::MinUIOp::create(rw, loc, na, nb);
    // the first i < m where they differ, or m
    auto walk = scf::WhileOp::create(rw, loc, TypeRange{idx}, ValueRange{cIndex(rw, loc, 0)});
    Block *before = rw.createBlock(&walk.getBefore(), walk.getBefore().end(), TypeRange{idx}, {loc});
    {
      Value i = before->getArgument(0);
      Value inside = arith::CmpIOp::create(rw, loc, arith::CmpIPredicate::ult, i, m);
      auto same = scf::IfOp::create(rw, loc, TypeRange{i1}, inside, /*withElseRegion=*/true);
      rw.setInsertionPointToStart(same.thenBlock());
      Value eq = arith::CmpIOp::create(rw, loc, arith::CmpIPredicate::eq, load(rw, loc, xs, i), load(rw, loc, ys, i));
      scf::YieldOp::create(rw, loc, ValueRange{eq});
      rw.setInsertionPointToStart(same.elseBlock());
      scf::YieldOp::create(rw, loc, ValueRange{cInt(rw, loc, i1, 0)});
      rw.setInsertionPointAfter(same);
      scf::ConditionOp::create(rw, loc, same.getResult(0), ValueRange{i});
    }
    Block *after = rw.createBlock(&walk.getAfter(), walk.getAfter().end(), TypeRange{idx}, {loc});
    scf::YieldOp::create(rw, loc, ValueRange{arith::AddIOp::create(rw, loc, after->getArgument(0), cIndex(rw, loc, 1)).getResult()});
    rw.setInsertionPointAfter(walk);
    Value i = walk.getResult(0);
    Value inside = arith::CmpIOp::create(rw, loc, arith::CmpIPredicate::ult, i, m);
    auto pick = scf::IfOp::create(rw, loc, TypeRange{rw.getI32Type()}, inside, /*withElseRegion=*/true);
    rw.setInsertionPointToStart(pick.thenBlock());
    scf::YieldOp::create(rw, loc, ValueRange{threeWay(rw, loc, load(rw, loc, xs, i), load(rw, loc, ys, i), op.getUnsignedOrder())});
    rw.setInsertionPointToStart(pick.elseBlock());
    Value na64 = arith::IndexCastOp::create(rw, loc, rw.getI64Type(), na), nb64 = arith::IndexCastOp::create(rw, loc, rw.getI64Type(), nb);
    scf::YieldOp::create(rw, loc, ValueRange{threeWay(rw, loc, na64, nb64)});
    rw.setInsertionPointAfter(pick);
    rw.replaceOp(op, pick.getResult(0));
    return success();
  }
};

/// sorted(xs) [by {a, b -> c}]: a stable bottom-up merge sort.  Runs of width w are merged pairwise from `runs` into
/// `merged`, which is then copied back, for w = 1, 2, 4, ...; a tie takes the left run's element, so equal elements keep
/// their order.  The comparator is inlined once, where the merge compares the heads of the two runs.
struct SortedLowering : Lowering<SortedOp> {
  using Lowering::Lowering;
  LogicalResult matchAndRewrite(SortedOp op, OpAdaptor a, ConversionPatternRewriter &rw) const override {
    Location loc = op.getLoc();
    Type element = elementOf(types(), op.getResult().getType());
    Type idx = rw.getIndexType(), i1 = rw.getI1Type();
    Value xs = a.getSeries(), n = length(rw, loc, xs);
    Value zero = cIndex(rw, loc, 0), one = cIndex(rw, loc, 1), two = cIndex(rw, loc, 2);
    Value runs = newSeriesBuffer(rw, loc, element, n), merged = newSeriesBuffer(rw, loc, element, n);
    auto copy = [&](Value from, Value to) {
      auto loop = scf::ForOp::create(rw, loc, zero, n, one);
      rw.setInsertionPoint(loop.getBody()->getTerminator());
      store(rw, loc, load(rw, loc, from, loop.getInductionVar()), to, loop.getInductionVar());
      rw.setInsertionPointAfter(loop);
    };
    copy(xs, runs);
    auto widths = scf::WhileOp::create(rw, loc, TypeRange{idx}, ValueRange{one});
    Block *before = rw.createBlock(&widths.getBefore(), widths.getBefore().end(), TypeRange{idx}, {loc});
    scf::ConditionOp::create(rw, loc, arith::CmpIOp::create(rw, loc, arith::CmpIPredicate::ult, before->getArgument(0), n),
                             ValueRange{before->getArgument(0)});
    Block *after = rw.createBlock(&widths.getAfter(), widths.getAfter().end(), TypeRange{idx}, {loc});
    Value w = after->getArgument(0), w2 = arith::MulIOp::create(rw, loc, w, two);
    auto pairs = scf::ForOp::create(rw, loc, zero, n, w2);
    rw.setInsertionPoint(pairs.getBody()->getTerminator());
    Value lo = pairs.getInductionVar();
    Value mid = arith::MinUIOp::create(rw, loc, arith::AddIOp::create(rw, loc, lo, w), n);
    Value hi = arith::MinUIOp::create(rw, loc, arith::AddIOp::create(rw, loc, lo, w2), n);
    auto merge = scf::ForOp::create(rw, loc, lo, hi, one, ValueRange{lo, mid});
    rw.setInsertionPointToEnd(merge.getBody());
    Value k = merge.getInductionVar(), i = merge.getRegionIterArgs()[0], j = merge.getRegionIterArgs()[1];
    Value leftLeft = arith::CmpIOp::create(rw, loc, arith::CmpIPredicate::ult, i, mid);
    Value rightLeft = arith::CmpIOp::create(rw, loc, arith::CmpIPredicate::ult, j, hi);
    Value both = arith::AndIOp::create(rw, loc, leftLeft, rightLeft);
    auto takeLeft = scf::IfOp::create(rw, loc, TypeRange{i1}, both, /*withElseRegion=*/true);
    rw.setInsertionPointToStart(takeLeft.thenBlock());
    FailureOr<Value> c = order(rw, types(), loc, op.getOrder(), load(rw, loc, runs, i), load(rw, loc, runs, j));
    if (failed(c)) return rw.notifyMatchFailure(op, "sorted's order yields one i32 (or the elements are integers)");
    Value leq = arith::CmpIOp::create(rw, loc, arith::CmpIPredicate::sle, *c, cInt(rw, loc, rw.getI32Type(), 0));
    scf::YieldOp::create(rw, loc, ValueRange{leq});
    rw.setInsertionPointToStart(takeLeft.elseBlock());
    scf::YieldOp::create(rw, loc, ValueRange{leftLeft});
    rw.setInsertionPointAfter(takeLeft);
    Value left = takeLeft.getResult(0);
    auto pick = scf::IfOp::create(rw, loc, TypeRange{element}, left, /*withElseRegion=*/true);
    rw.setInsertionPointToStart(pick.thenBlock());
    scf::YieldOp::create(rw, loc, ValueRange{load(rw, loc, runs, i)});
    rw.setInsertionPointToStart(pick.elseBlock());
    scf::YieldOp::create(rw, loc, ValueRange{load(rw, loc, runs, j)});
    rw.setInsertionPointAfter(pick);
    store(rw, loc, pick.getResult(0), merged, k);
    Value i2 = arith::SelectOp::create(rw, loc, left, arith::AddIOp::create(rw, loc, i, one), i);
    Value j2 = arith::SelectOp::create(rw, loc, left, j, arith::AddIOp::create(rw, loc, j, one));
    scf::YieldOp::create(rw, loc, ValueRange{i2, j2});
    rw.setInsertionPointToEnd(after);
    copy(merged, runs);
    scf::YieldOp::create(rw, loc, ValueRange{w2});
    rw.setInsertionPointAfter(widths);
    rw.replaceOp(op, runs);
    return success();
  }
};

/// bisect(xs, key) [by {x, key -> c}]: a binary search over [lo, hi); the index of an equal element, or -(lo) - 1 where
/// the search ended (the insertion point).
struct BisectLowering : Lowering<BisectOp> {
  using Lowering::Lowering;
  LogicalResult matchAndRewrite(BisectOp op, OpAdaptor a, ConversionPatternRewriter &rw) const override {
    Location loc = op.getLoc();
    Type idx = rw.getIndexType(), i1 = rw.getI1Type();
    Value xs = a.getSeries(), key = a.getKey(), n = length(rw, loc, xs);
    Value zero = cIndex(rw, loc, 0), one = cIndex(rw, loc, 1);
    SmallVector<Type> state{idx, idx, idx, i1}; // lo, hi, where it was found, found
    SmallVector<Location> locs(4, loc);
    auto search = scf::WhileOp::create(rw, loc, TypeRange(state), ValueRange{zero, n, zero, cInt(rw, loc, i1, 0)});
    Block *before = rw.createBlock(&search.getBefore(), search.getBefore().end(), TypeRange(state), locs);
    {
      Value open = arith::CmpIOp::create(rw, loc, arith::CmpIPredicate::ult, before->getArgument(0), before->getArgument(1));
      Value notFound = arith::XOrIOp::create(rw, loc, before->getArgument(3), cInt(rw, loc, i1, 1));
      scf::ConditionOp::create(rw, loc, arith::AndIOp::create(rw, loc, open, notFound), before->getArguments());
    }
    Block *after = rw.createBlock(&search.getAfter(), search.getAfter().end(), TypeRange(state), locs);
    Value lo = after->getArgument(0), hi = after->getArgument(1);
    Value mid = arith::ShRUIOp::create(rw, loc, arith::AddIOp::create(rw, loc, lo, hi), one);
    FailureOr<Value> c = order(rw, types(), loc, op.getOrder(), load(rw, loc, xs, mid), key);
    if (failed(c)) return rw.notifyMatchFailure(op, "bisect's order yields one i32 (or the elements and the key are integers of one type)");
    Value z32 = cInt(rw, loc, rw.getI32Type(), 0);
    Value below = arith::CmpIOp::create(rw, loc, arith::CmpIPredicate::slt, *c, z32);
    Value above = arith::CmpIOp::create(rw, loc, arith::CmpIPredicate::sgt, *c, z32);
    Value equal = arith::CmpIOp::create(rw, loc, arith::CmpIPredicate::eq, *c, z32);
    Value lo2 = arith::SelectOp::create(rw, loc, below, arith::AddIOp::create(rw, loc, mid, one), lo);
    Value hi2 = arith::SelectOp::create(rw, loc, above, mid, hi);
    scf::YieldOp::create(rw, loc, ValueRange{lo2, hi2, mid, equal});
    rw.setInsertionPointAfter(search);
    Value missing = arith::SubIOp::create(rw, loc, arith::SubIOp::create(rw, loc, zero, search.getResult(0)), one);
    rw.replaceOp(op, arith::SelectOp::create(rw, loc, search.getResult(3), search.getResult(2), missing).getResult());
    return success();
  }
};

/// a j b of two i32 halves: (a << 32) | b.
struct JLowering : Lowering<JOp> {
  using Lowering::Lowering;
  LogicalResult matchAndRewrite(JOp op, OpAdaptor a, ConversionPatternRewriter &rw) const override {
    Type half = pairHalf(op.getResult().getType());
    if (!half || a.getA().getType() != half || a.getB().getType() != half)
      return rw.notifyMatchFailure(op, "only a pair of two i32 halves lowers");
    Location loc = op.getLoc();
    Type i64 = rw.getI64Type();
    Value hi = arith::ShLIOp::create(rw, loc, arith::ExtUIOp::create(rw, loc, i64, a.getA()), cInt(rw, loc, i64, 32));
    rw.replaceOp(op, arith::OrIOp::create(rw, loc, hi, arith::ExtUIOp::create(rw, loc, i64, a.getB())).getResult());
    return success();
  }
};

/// first and second of a pair of two i32 halves: the high and the low word.
template <class Op, bool High> struct HalfLowering : Lowering<Op> {
  using Lowering<Op>::Lowering;
  LogicalResult matchAndRewrite(Op op, typename Op::Adaptor a, ConversionPatternRewriter &rw) const override {
    Type half = pairHalf(op.getJoin().getType());
    if (!half || op->getResult(0).getType() != half) return rw.notifyMatchFailure(op, "only a pair of two i32 halves lowers");
    Location loc = op.getLoc();
    Value word = a.getJoin();
    if (High) word = arith::ShRUIOp::create(rw, loc, word, cInt(rw, loc, rw.getI64Type(), 32));
    rw.replaceOp(op, arith::TruncIOp::create(rw, loc, half, word).getResult());
    return success();
  }
};

/// parts(xs, d): Series.div.  The delimiters counted, then each part's (start, length) written as a delimiter ends it, and
/// the last part after the loop.
struct PartsLowering : Lowering<PartsOp> {
  using Lowering::Lowering;
  LogicalResult matchAndRewrite(PartsOp op, OpAdaptor a, ConversionPatternRewriter &rw) const override {
    Location loc = op.getLoc();
    Type i64 = rw.getI64Type(), idx = rw.getIndexType();
    Value xs = a.getSeries(), d = a.getDelimiter();
    Value n = length(rw, loc, xs);
    Value zero = cIndex(rw, loc, 0), one = cIndex(rw, loc, 1);
    Value c32 = cInt(rw, loc, i64, 32), mask = cInt(rw, loc, i64, 0xffffffff);
    auto isDelimiter = [&](Value i) -> Value {
      return arith::CmpIOp::create(rw, loc, arith::CmpIPredicate::eq, load(rw, loc, xs, i), d);
    };
    auto pack = [&](Value start, Value end) -> Value {
      Value s = arith::IndexCastUIOp::create(rw, loc, i64, start);
      Value l = arith::IndexCastUIOp::create(rw, loc, i64, arith::SubIOp::create(rw, loc, end, start));
      return arith::OrIOp::create(rw, loc, arith::ShLIOp::create(rw, loc, s, c32), arith::AndIOp::create(rw, loc, l, mask));
    };
    auto counting = scf::ForOp::create(rw, loc, zero, n, one, ValueRange{one});
    rw.setInsertionPointToEnd(counting.getBody());
    {
      Value add = arith::SelectOp::create(rw, loc, isDelimiter(counting.getInductionVar()), one, zero);
      scf::YieldOp::create(rw, loc, ValueRange{arith::AddIOp::create(rw, loc, counting.getRegionIterArgs()[0], add).getResult()});
    }
    rw.setInsertionPointAfter(counting);
    Value parts = newSeriesBuffer(rw, loc, i64, counting.getResult(0));
    auto writing = scf::ForOp::create(rw, loc, zero, n, one, ValueRange{zero, zero});
    rw.setInsertionPointToEnd(writing.getBody());
    {
      Value i = writing.getInductionVar(), k = writing.getRegionIterArgs()[0], start = writing.getRegionIterArgs()[1];
      auto ends = scf::IfOp::create(rw, loc, TypeRange{idx, idx}, isDelimiter(i), /*withElseRegion=*/true);
      rw.setInsertionPointToStart(ends.thenBlock());
      store(rw, loc, pack(start, i), parts, k);
      scf::YieldOp::create(rw, loc, ValueRange{arith::AddIOp::create(rw, loc, k, one).getResult(),
                                               arith::AddIOp::create(rw, loc, i, one).getResult()});
      rw.setInsertionPointToStart(ends.elseBlock());
      scf::YieldOp::create(rw, loc, ValueRange{k, start});
      rw.setInsertionPointAfter(ends);
      scf::YieldOp::create(rw, loc, ends.getResults());
    }
    rw.setInsertionPointAfter(writing);
    store(rw, loc, pack(writing.getResult(1), n), parts, writing.getResult(0));
    rw.replaceOp(op, parts);
    return success();
  }
};

/// adjacency(from, to, n): a counting sort.  The counts of each node's edges, their running sum as each node's first
/// (packed with its count), then each edge's far end written at its node's next place, so a node's ends keep edge order.
struct AdjacencyLowering : Lowering<AdjacencyOp> {
  using Lowering::Lowering;
  LogicalResult matchAndRewrite(AdjacencyOp op, OpAdaptor a, ConversionPatternRewriter &rw) const override {
    Location loc = op.getLoc();
    Type i32 = rw.getI32Type(), i64 = rw.getI64Type(), idx = rw.getIndexType();
    Value from = a.getFrom(), to = a.getTo(), n = a.getNodes();
    Value m = length(rw, loc, from);
    Value zero = cIndex(rw, loc, 0), one = cIndex(rw, loc, 1);
    Value c32 = cInt(rw, loc, i64, 32);
    Value n32 = arith::IndexCastOp::create(rw, loc, i32, n);
    Value zero32 = cInt(rw, loc, i32, 0);
    // the node of edge e when it is one: 0 <= from[e] < n
    auto inRange = [&](Value f) -> Value {
      Value ge = arith::CmpIOp::create(rw, loc, arith::CmpIPredicate::sge, f, zero32);
      Value lt = arith::CmpIOp::create(rw, loc, arith::CmpIPredicate::slt, f, n32);
      return arith::AndIOp::create(rw, loc, ge, lt);
    };
    // counts, kept in the low half of the index while they are counted
    Value index = newSeriesBuffer(rw, loc, i64, n);
    {
      auto clear = scf::ForOp::create(rw, loc, zero, n, one);
      rw.setInsertionPoint(clear.getBody()->getTerminator());
      store(rw, loc, cInt(rw, loc, i64, 0), index, clear.getInductionVar());
      rw.setInsertionPointAfter(clear);
    }
    {
      auto count = scf::ForOp::create(rw, loc, zero, m, one);
      rw.setInsertionPoint(count.getBody()->getTerminator());
      Value f = load(rw, loc, from, count.getInductionVar());
      auto kept = scf::IfOp::create(rw, loc, inRange(f), /*withElseRegion=*/false);
      rw.setInsertionPoint(kept.thenBlock()->getTerminator());
      Value k = arith::IndexCastOp::create(rw, loc, idx, f);
      store(rw, loc, arith::AddIOp::create(rw, loc, load(rw, loc, index, k), cInt(rw, loc, i64, 1)).getResult(), index, k);
      rw.setInsertionPointAfter(count);
    }
    // firsts: the running sum, packed with each count; `next` starts at each first
    Value next = memref::AllocOp::create(rw, loc, MemRefType::get({ShapedType::kDynamic}, i64), ValueRange{n});
    auto sum = scf::ForOp::create(rw, loc, zero, n, one, ValueRange{cInt(rw, loc, i64, 0)});
    rw.setInsertionPointToEnd(sum.getBody());
    {
      Value k = sum.getInductionVar(), total = sum.getRegionIterArgs()[0];
      Value count = load(rw, loc, index, k);
      store(rw, loc, arith::OrIOp::create(rw, loc, arith::ShLIOp::create(rw, loc, total, c32), count).getResult(), index, k);
      store(rw, loc, total, next, k);
      scf::YieldOp::create(rw, loc, ValueRange{arith::AddIOp::create(rw, loc, total, count).getResult()});
    }
    rw.setInsertionPointAfter(sum);
    Value ends = newSeriesBuffer(rw, loc, i32, arith::IndexCastUIOp::create(rw, loc, idx, sum.getResult(0)));
    {
      auto fill = scf::ForOp::create(rw, loc, zero, m, one);
      rw.setInsertionPoint(fill.getBody()->getTerminator());
      Value e = fill.getInductionVar();
      Value f = load(rw, loc, from, e);
      auto kept = scf::IfOp::create(rw, loc, inRange(f), /*withElseRegion=*/false);
      rw.setInsertionPoint(kept.thenBlock()->getTerminator());
      Value k = arith::IndexCastOp::create(rw, loc, idx, f);
      Value at = load(rw, loc, next, k);
      store(rw, loc, load(rw, loc, to, e), ends, at);
      store(rw, loc, arith::AddIOp::create(rw, loc, at, cInt(rw, loc, i64, 1)).getResult(), next, k);
      rw.setInsertionPointAfter(fill);
    }
    rw.replaceOp(op, ValueRange{index, ends});
    return success();
  }
};

/// closure(parents, above): ClosureIndex.build as two walks from every node k over its parents, with a mark per node (the
/// stamp of the walk that met it last) and a stack a node is pushed on when it is first met, so it never holds more than
/// size(parents) nodes.  The first walk from k counts its ancestors, which gives each node's (first, count); the second
/// writes them, in the order they are met.  k is marked before its walk, so it is never its own ancestor.
struct ClosureLowering : Lowering<ClosureOp> {
  using Lowering::Lowering;
  LogicalResult matchAndRewrite(ClosureOp op, OpAdaptor a, ConversionPatternRewriter &rw) const override {
    Location loc = op.getLoc();
    Type i32 = rw.getI32Type(), i64 = rw.getI64Type(), idx = rw.getIndexType();
    Value parents = a.getParents(), above = a.getAbove();
    Value n = length(rw, loc, parents);
    Value zero = cIndex(rw, loc, 0), one = cIndex(rw, loc, 1);
    auto scratch = [&](Value count) -> Value {
      return memref::AllocOp::create(rw, loc, MemRefType::get({ShapedType::kDynamic}, i32), ValueRange{count});
    };
    Value mark = scratch(n), stack = scratch(n);
    {
      auto fill = scf::ForOp::create(rw, loc, zero, n, one);
      rw.setInsertionPoint(fill.getBody()->getTerminator());
      store(rw, loc, cInt(rw, loc, i32, -1), mark, fill.getInductionVar());
      rw.setInsertionPointAfter(fill);
    }
    Value c32 = cInt(rw, loc, i64, 32), mask = cInt(rw, loc, i64, 0xffffffff);
    // the walk from node k with this stamp: how many nodes it meets; with `out`, they are written at out[at ...]
    auto walk = [&](Value k, Value stamp, Value out, Value at) -> Value {
      store(rw, loc, stamp, mark, k);
      store(rw, loc, arith::IndexCastOp::create(rw, loc, i32, k).getResult(), stack, zero);
      auto w = scf::WhileOp::create(rw, loc, TypeRange{idx, idx}, ValueRange{one, zero});
      Block *before = rw.createBlock(&w.getBefore(), w.getBefore().end(), TypeRange{idx, idx}, {loc, loc});
      Value more = arith::CmpIOp::create(rw, loc, arith::CmpIPredicate::ugt, before->getArgument(0), zero);
      scf::ConditionOp::create(rw, loc, more, before->getArguments());
      Block *after = rw.createBlock(&w.getAfter(), w.getAfter().end(), TypeRange{idx, idx}, {loc, loc});
      Value top = arith::SubIOp::create(rw, loc, after->getArgument(0), one);
      Value v = load(rw, loc, stack, top);
      Value fc = load(rw, loc, parents, v);
      Value first = arith::IndexCastUIOp::create(rw, loc, idx, arith::ShRUIOp::create(rw, loc, fc, c32));
      Value count = arith::IndexCastUIOp::create(rw, loc, idx, arith::AndIOp::create(rw, loc, fc, mask));
      Value end = arith::AddIOp::create(rw, loc, first, count);
      auto edges = scf::ForOp::create(rw, loc, first, end, one, ValueRange{top, after->getArgument(1)});
      rw.setInsertionPointToEnd(edges.getBody());
      Value tp = edges.getRegionIterArgs()[0], met = edges.getRegionIterArgs()[1];
      Value p = load(rw, loc, above, edges.getInductionVar());
      Value fresh = arith::CmpIOp::create(rw, loc, arith::CmpIPredicate::ne, load(rw, loc, mark, p), stamp);
      auto meet = scf::IfOp::create(rw, loc, TypeRange{idx, idx}, fresh, /*withElseRegion=*/true);
      rw.setInsertionPointToStart(meet.thenBlock());
      store(rw, loc, stamp, mark, p);
      store(rw, loc, p, stack, tp);
      if (out) store(rw, loc, p, out, arith::AddIOp::create(rw, loc, at, met));
      scf::YieldOp::create(rw, loc, ValueRange{arith::AddIOp::create(rw, loc, tp, one).getResult(),
                                               arith::AddIOp::create(rw, loc, met, one).getResult()});
      rw.setInsertionPointToStart(meet.elseBlock());
      scf::YieldOp::create(rw, loc, ValueRange{tp, met});
      rw.setInsertionPointAfter(meet);
      scf::YieldOp::create(rw, loc, meet.getResults());
      rw.setInsertionPointToEnd(after);
      scf::YieldOp::create(rw, loc, edges.getResults());
      rw.setInsertionPointAfter(w);
      return w.getResult(1);
    };
    // the counts, and each node's (first, count)
    Value ancestors = newSeriesBuffer(rw, loc, i64, n);
    auto counting = scf::ForOp::create(rw, loc, zero, n, one, ValueRange{zero});
    rw.setInsertionPointToEnd(counting.getBody());
    {
      Value k = counting.getInductionVar(), total = counting.getRegionIterArgs()[0];
      Value met = walk(k, arith::IndexCastOp::create(rw, loc, i32, k), Value(), Value());
      Value hi = arith::ShLIOp::create(rw, loc, arith::IndexCastUIOp::create(rw, loc, i64, total), c32);
      Value packed = arith::OrIOp::create(rw, loc, hi, arith::IndexCastUIOp::create(rw, loc, i64, met));
      store(rw, loc, packed, ancestors, k);
      scf::YieldOp::create(rw, loc, ValueRange{arith::AddIOp::create(rw, loc, total, met).getResult()});
    }
    rw.setInsertionPointAfter(counting);
    Value members = newSeriesBuffer(rw, loc, i32, counting.getResult(0));
    Value n32 = arith::IndexCastOp::create(rw, loc, i32, n);
    auto writing = scf::ForOp::create(rw, loc, zero, n, one);
    rw.setInsertionPoint(writing.getBody()->getTerminator());
    {
      Value k = writing.getInductionVar();
      Value stamp = arith::AddIOp::create(rw, loc, arith::IndexCastOp::create(rw, loc, i32, k), n32);
      Value at = arith::IndexCastUIOp::create(rw, loc, idx, arith::ShRUIOp::create(rw, loc, load(rw, loc, ancestors, k), c32));
      walk(k, stamp, members, at);
    }
    rw.setInsertionPointAfter(writing);
    rw.replaceOp(op, ValueRange{ancestors, members});
    return success();
  }
};

struct DrainLowering : Lowering<DrainOp> {
  using Lowering::Lowering;
  LogicalResult matchAndRewrite(DrainOp op, OpAdaptor a, ConversionPatternRewriter &rw) const override {
    Location loc = op.getLoc();
    if (!isa<MemRefType>(a.getInto().getType())) return rw.notifyMatchFailure(op, "drain needs a memref to write into");
    Value xs = a.getSeries(), n = length(rw, loc, xs);
    auto loop = scf::ForOp::create(rw, loc, cIndex(rw, loc, 0), n, cIndex(rw, loc, 1));
    rw.setInsertionPoint(loop.getBody()->getTerminator());
    store(rw, loc, load(rw, loc, xs, loop.getInductionVar()), a.getInto(), loop.getInductionVar());
    rw.setInsertionPointAfter(loop);
    Type end = op.getEnd().getType();
    rw.replaceOp(op, end.isIndex() ? n : arith::IndexCastOp::create(rw, loc, end, n).getResult());
    return success();
  }
};

/// arith.select of a pair or a series (scf and arith take them as they are): the same select of what they lower to.
struct SelectLowering : OpConversionPattern<arith::SelectOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(arith::SelectOp op, OpAdaptor a, ConversionPatternRewriter &rw) const override {
    if (!getTypeConverter()->convertType(op.getType())) return rw.notifyMatchFailure(op, "a type that does not lower to one");
    rw.replaceOp(op, arith::SelectOp::create(rw, op.getLoc(), a.getCondition(), a.getTrueValue(), a.getFalseValue()).getResult());
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
                 ProjectLowering, SliceLowering, FoldLowering, CompareLowering, SortedLowering, BisectLowering, JLowering,
                 HalfLowering<FirstOp, true>, HalfLowering<SecondOp, false>, DrainLowering, PartsLowering, AdjacencyLowering, ClosureLowering, TextLowering>(types, ctx);
    populateFunctionOpInterfaceTypeConversionPattern<func::FuncOp>(patterns, types);
    populateReturnOpTypeConversionPattern(patterns, types);
    populateCallOpTypeConversionPattern(patterns, types);
    // scf.if/for/while and arith.select that carry a pair or a series: their types lowered with them
    scf::populateSCFStructuralTypeConversionsAndLegality(types, patterns, target);
    target.addDynamicallyLegalOp<arith::SelectOp>([&](arith::SelectOp op) { return types.isLegal(op.getOperation()); });
    patterns.add<SelectLowering>(types, ctx);
    // the dialects below TrikeShed: their ops that make or read series and cursors (confix's index, its Columns facet)
    for (Dialect *d : ctx->getLoadedDialects())
      if (auto *below = d->getRegisteredInterface<CursorLoweringInterface>()) below->populateCursorLowering(types, patterns, target);

    // A caller that makes a series or a cursor from buffers of another layout (a memref<?xi32> cast to
    // !trikeshed.cursor) has them viewed as the buffers a series lowers to first: a memref.cast to the strided layout,
    // so that its cast and the conversion's cancel.  The descriptor is the same; only the offset is read where it was 0.
    getOperation().walk([&](UnrealizedConversionCastOp c) {
      SmallVector<Type> want;
      for (Type t : c.getResultTypes())
        if (!isa<SeriesType, CursorType>(t) || failed(types.convertType(t, want))) return;
      SmallVector<Value> inputs(c.getInputs());
      if (want.size() != inputs.size()) return;
      OpBuilder b(c);
      for (auto [i, input] : llvm::enumerate(inputs))
        if (input.getType() != want[i] && isa<MemRefType>(input.getType()) &&
            memref::CastOp::areCastCompatible(input.getType(), want[i]))
          c->setOperand(i, memref::CastOp::create(b, c.getLoc(), want[i], input));
    });
    if (failed(applyPartialConversion(getOperation(), target, std::move(patterns)))) return signalPassFailure();

    // A caller that made its cursor from buffers (a cast to !trikeshed.cursor) now hands it straight to a callee that takes
    // the buffers back (the conversion's cast from it): the pair cancels.  Casts not touching a trikeshed type are left.
    auto touches = [](TypeRange ts) {
      return llvm::any_of(ts, [](Type t) { return isa<SeriesType, CursorType, JoinType, TwinType, TwinPackedType>(t); });
    };
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
