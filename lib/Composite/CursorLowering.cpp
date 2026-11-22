//===- CursorLowering.cpp - TrikeShed's series and cursor ops as loops over buffers ----------------------------------===//
//
// `trikeshed-lower-cursors`: the ops of borg.trikeshed.lib that a query is written in, lowered to scf, arith and memref, so
// the stock pipeline takes them on to LLVM.  The laws are the ones TrikeShed.td states for each op; this is one way to keep
// them with buffers.
//
//   !trikeshed.series<T>            memref<?xT, strided<[1], offset: ?>>: a series is materialised where it is made
//                                   (series, alpha, where, project, sorted); a slice is a view at an offset
//   !trikeshed.cursor<s, [T0..Tn]>  one such buffer per column (a 1:N conversion: a cursor argument becomes its columns)
//   a pair of two equal halves      `!trikeshed.twin`'s rule, for Join<T, T>, Twin<T> and TwinPacked<T> of an integer or
//                                   a float T: 2 * width(T) <= 64 is one integer of that width, the first half high
//                                   (Pack.h's TwInt: Twin<i32> an i64; Twin<f32> the two floats' bits in an i64); a
//                                   wider T is its two halves apart (a 1:N conversion: a Twin<i64> is two i64, a series
//                                   of them two buffers, read by size, at, series, alpha and slice only)
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
//   j, first, second                shifts of the word a packed pair is (a bitcast more for a float half); the halves
//                                   themselves where the pair is split
//   facet(c, k) {col -> r}          the region with col = column(c, k)
//   drain(xs, into)                 a loop storing xs into `into`; the result is size(xs)
//   combine(a, b, ..)               Combine.kt's view, rewritten before the conversion (Combine.kt's views, below):
//   combineAll(n) {k -> part}       its size the parts' sizes added, its drain the parts' drains in turn, and a buffer
//                                   only where something reads it by index
//   parts(xs, d)                    Series.div: count the delimiters, then each part's (start, length)
//   text(buffer)                    a constant's 1-D buffer, cast to the series' strided layout
//   adjacency(from, to, n)          a counting sort: each node's (first, count) into the far ends, in edge order
//   closure(parents, above)         ClosureIndex: two walks from each node over its parents (count, then write)
//   joins, leftOf, rightOf, reify   a Series2 and a split as their two sides' buffers; zipnext, splitSelect and take
//                                   rewritten by their laws into views, projects and ats (ReifiedSplitSeries2, below)
//
// Buffers are allocated and never freed here: run --ownership-based-buffer-deallocation after this pass.  A slice's offset
// is an affine.apply once --expand-strided-metadata has run: run --lower-affine before --finalize-memref-to-llvm.  Casts the
// conversion leaves between a cursor and its buffers are reconciled at the end, so a caller that built its cursor from
// buffers ends up passing the buffers.  A dialect below TrikeShed (confix: its index and its Columns facet) adds its
// patterns through CursorLoweringInterface (Composite/CursorLowering.h).  groupBy and keyedJoin are rewritten first into
// sorted, where, project, bisect and series (GroupBy.kt and KeyedJoin.kt, below).  Not lowered: pivot and the other cursor
// combinators, contains, the lazy form of a series read otherwise than by at, size, slice and bisect, and series whose
// elements are neither builtin types nor pairs of two equal scalar halves.  trikeshed-route-twins (TwinRouting.cpp) runs
// before this pass where a series of pairs should be laid out by how it is read, not by its width alone.
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
#include "mlir/IR/IRMapping.h"
#include "mlir/IR/Matchers.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Transforms/DialectConversion.h"
#include "mlir/Transforms/RegionUtils.h"

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

/// The half type of a pair of two equal integers or floats (Join<T, T>, Twin<T>, TwinPacked<T>), else null.
Type pairHalf(Type t) {
  Type a, b;
  if (auto j = dyn_cast<JoinType>(t)) a = j.getA(), b = j.getB();
  else if (auto w = dyn_cast<TwinType>(t)) a = b = w.getElement();
  else if (auto p = dyn_cast<TwinPackedType>(t)) a = b = p.getElement();
  else return {};
  return a == b && (a.isSignlessInteger() || isa<FloatType>(a)) ? a : Type{};
}

/// A machine word: two halves that fit it are packed into one integer, wider ones lie apart.
constexpr unsigned kWordBits = 64;

struct CursorTypes : TypeConverter {
  CursorTypes() {
    addConversion([](Type t) { return t; });
    // the width rule (TrikeShed.td, !trikeshed.twin): a TwinPacked is a word by its name, so a wider one does not lower
    addConversion([](Type t, SmallVectorImpl<Type> &out) -> std::optional<LogicalResult> {
      Type half = isa<JoinType, TwinType, TwinPackedType>(t) ? pairHalf(t) : Type{};
      if (!half) return std::nullopt;
      unsigned bits = 2 * half.getIntOrFloatBitWidth();
      if (bits <= kWordBits) out.push_back(IntegerType::get(t.getContext(), bits));
      else if (isa<TwinPackedType>(t)) return std::nullopt;
      else out.append(2, half);
      return success();
    });
    addConversion([this](SeriesType t, SmallVectorImpl<Type> &out) -> std::optional<LogicalResult> {
      return buffers(t.getElement(), out) ? std::optional<LogicalResult>(success()) : std::nullopt;
    });
    addConversion([this](CursorType t, SmallVectorImpl<Type> &out) -> std::optional<LogicalResult> {
      SmallVector<Type> columns;
      for (Type column : t.getColumns())
        if (!buffers(column, columns)) return std::nullopt;
      out.append(columns);
      return success();
    });
  }

  /// The buffers of a series of `element`: one, or one a half where the element is a pair that lies apart.
  bool buffers(Type element, SmallVectorImpl<Type> &out) const {
    SmallVector<Type> es;
    if (failed(convertType(element, es))) return false;
    for (Type e : es) {
      if (!BaseMemRefType::isValidElementType(e)) return false;
      out.push_back(seriesBuffer(e));
    }
    return true;
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

/// The element type of a series after conversion (null where the element is a pair that lies apart).
Type elementOf(const TypeConverter &types, Type series) { return types.convertType(cast<SeriesType>(series).getElement()); }

/// What `t` converts to: one type, or two for a pair that lies apart; none where it does not convert.
SmallVector<Type, 2> converted(const TypeConverter &types, Type t) {
  SmallVector<Type, 2> to;
  if (failed(types.convertType(t, to))) to.clear();
  return to;
}

/// A series' element as it lies in the series' buffers, one value a buffer: read, written, and fresh buffers for n of it.
SmallVector<Value, 2> loadAll(OpBuilder &b, Location loc, ValueRange buffers, Value i) {
  SmallVector<Value, 2> vs;
  for (Value buffer : buffers) vs.push_back(load(b, loc, buffer, i));
  return vs;
}
void storeAll(OpBuilder &b, Location loc, ValueRange vs, ValueRange buffers, Value i) {
  for (auto [v, buffer] : llvm::zip_equal(vs, buffers)) store(b, loc, v, buffer, i);
}
SmallVector<Value, 2> newSeriesBuffers(OpBuilder &b, Location loc, ArrayRef<Type> elements, Value n) {
  SmallVector<Value, 2> out;
  for (Type e : elements) out.push_back(newSeriesBuffer(b, loc, e, n));
  return out;
}

/// `op`, which has one result, replaced by the values that result lowers to.
void replaceWith(ConversionPatternRewriter &rw, Operation *op, ValueRange values) {
  SmallVector<SmallVector<Value>> to(1, SmallVector<Value>(values.begin(), values.end()));
  rw.replaceOpWithMultiple(op, std::move(to));
}

/// The buffers of column i among a cursor's (a column of pairs that lie apart is two of them).
ValueRange columnBuffers(const TypeConverter &types, CursorType c, unsigned i, ValueRange buffers) {
  unsigned at = 0, n = 0;
  for (unsigned k = 0; k <= i; ++k) at += n, n = converted(types, c.getColumns()[k]).size();
  return buffers.slice(at, n);
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
/// trikeshed.yield yielded, as the converted values (a pair yielded by a j that is lowered after this is the i64 the j
/// becomes: the conversion casts it until then; a pair that lies apart is yielded as its two halves).  The region's
/// argument types are converted first (a series argument becomes its buffer, a pair that lies apart two arguments).
FailureOr<SmallVector<Value>> inlineBody(ConversionPatternRewriter &rw, const TypeConverter &types, Region &region, ValueRange args) {
  if (failed(rw.convertRegionTypes(&region, types))) return failure();
  Block *block = &region.front();
  auto yield = dyn_cast<YieldOp>(block->getTerminator());
  if (!yield) return failure();
  SmallVector<Value> yielded;
  {
    OpBuilder::InsertionGuard guard(rw);
    rw.setInsertionPoint(yield);
    for (Value v : yield.getValues()) {
      auto to = converted(types, v.getType());
      if (to.size() == 2) {
        yielded.push_back(FirstOp::create(rw, yield.getLoc(), to[0], v));
        yielded.push_back(SecondOp::create(rw, yield.getLoc(), to[1], v));
      } else yielded.push_back(v);
    }
  }
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
    replaceWith(rw, op, columnBuffers(types(), cast<CursorType>(op.getCursor().getType()), *i, a.getCursor()));
    return success();
  }
};

struct FacetLowering : Lowering<FacetOp> {
  using Lowering::Lowering;
  LogicalResult matchAndRewrite(FacetOp op, OneToNOpAdaptor a, ConversionPatternRewriter &rw) const override {
    FailureOr<unsigned> i = keyIndex(op, op.getCursor(), op.getKey(), rw);
    if (failed(i)) return failure();
    auto body = inlineBody(rw, types(), op.getCompute(), columnBuffers(types(), cast<CursorType>(op.getCursor().getType()), *i, a.getCursor()));
    if (failed(body) || body->size() != 1) return rw.notifyMatchFailure(op, "a facet's region yields one value");
    rw.replaceOp(op, (*body)[0]);
    return success();
  }
};

struct SizeLowering : Lowering<SizeOp> {
  using Lowering::Lowering;
  LogicalResult matchAndRewrite(SizeOp op, OneToNOpAdaptor a, ConversionPatternRewriter &rw) const override {
    rw.replaceOp(op, length(rw, op.getLoc(), a.getSeries()[0]));
    return success();
  }
};

struct AtLowering : Lowering<AtOp> {
  using Lowering::Lowering;
  LogicalResult matchAndRewrite(AtOp op, OneToNOpAdaptor a, ConversionPatternRewriter &rw) const override {
    if (a.getIndex().size() != 1) return rw.notifyMatchFailure(op, "an index is one value");
    replaceWith(rw, op, loadAll(rw, op.getLoc(), a.getSeries(), a.getIndex()[0]));
    return success();
  }
};

/// series(n) {k -> x}: a buffer filled by a loop over the region.
struct SeriesLowering : Lowering<SeriesOp> {
  using Lowering::Lowering;
  LogicalResult matchAndRewrite(SeriesOp op, OpAdaptor a, ConversionPatternRewriter &rw) const override {
    Location loc = op.getLoc();
    auto elements = converted(types(), cast<SeriesType>(op.getResult().getType()).getElement());
    Value n = a.getSize();
    auto out = newSeriesBuffers(rw, loc, elements, n);
    auto loop = scf::ForOp::create(rw, loc, cIndex(rw, loc, 0), n, cIndex(rw, loc, 1));
    rw.setInsertionPoint(loop.getBody()->getTerminator());
    auto body = inlineBody(rw, types(), op.getAt(), ValueRange{loop.getInductionVar()});
    if (failed(body) || out.empty() || body->size() != out.size()) return rw.notifyMatchFailure(op, "a series' region yields one element");
    storeAll(rw, loc, *body, out, loop.getInductionVar());
    rw.setInsertionPointAfter(loop);
    replaceWith(rw, op, out);
    return success();
  }
};

/// alpha(xs) {x -> y}: a buffer of size(xs) filled by a loop over the region.
struct AlphaLowering : Lowering<AlphaOp> {
  using Lowering::Lowering;
  LogicalResult matchAndRewrite(AlphaOp op, OneToNOpAdaptor a, ConversionPatternRewriter &rw) const override {
    Location loc = op.getLoc();
    auto elements = converted(types(), cast<SeriesType>(op.getResult().getType()).getElement());
    ValueRange xs = a.getSeries();
    Value n = length(rw, loc, xs[0]);
    auto out = newSeriesBuffers(rw, loc, elements, n);
    auto loop = scf::ForOp::create(rw, loc, cIndex(rw, loc, 0), n, cIndex(rw, loc, 1));
    rw.setInsertionPoint(loop.getBody()->getTerminator());
    auto x = loadAll(rw, loc, xs, loop.getInductionVar());
    auto body = inlineBody(rw, types(), op.getXform(), x);
    if (failed(body) || out.empty() || body->size() != out.size()) return rw.notifyMatchFailure(op, "α's region yields one element");
    storeAll(rw, loc, *body, out, loop.getInductionVar());
    rw.setInsertionPointAfter(loop);
    replaceWith(rw, op, out);
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
  LogicalResult matchAndRewrite(SliceOp op, OneToNOpAdaptor a, ConversionPatternRewriter &rw) const override {
    Location loc = op.getLoc();
    if (a.getOffset().size() != 1 || a.getCount().size() != 1) return rw.notifyMatchFailure(op, "a range is two values");
    SmallVector<Value, 2> views;
    for (Value xs : a.getSeries()) {
      Value view = memref::SubViewOp::create(rw, loc, xs, ArrayRef<OpFoldResult>{a.getOffset()[0]}, ArrayRef<OpFoldResult>{a.getCount()[0]},
                                             ArrayRef<OpFoldResult>{rw.getIndexAttr(1)});
      views.push_back(view.getType() != xs.getType() ? memref::CastOp::create(rw, loc, xs.getType(), view).getResult() : view);
    }
    replaceWith(rw, op, views);
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

/// a j b of two equal halves: (a << width) | b in the word that holds both, a float half as its bits; the two halves
/// themselves where they do not fit a word.
struct JLowering : Lowering<JOp> {
  using Lowering::Lowering;
  LogicalResult matchAndRewrite(JOp op, OpAdaptor a, ConversionPatternRewriter &rw) const override {
    Type pair = op.getResult().getType(), half = pairHalf(pair);
    auto to = converted(types(), pair);
    if (!half || a.getA().getType() != half || a.getB().getType() != half || to.empty() || to[0] == pair)
      return rw.notifyMatchFailure(op, "only a pair of two equal integer or float halves lowers");
    if (to.size() == 2) {
      replaceWith(rw, op, ValueRange{a.getA(), a.getB()});
      return success();
    }
    Location loc = op.getLoc();
    unsigned width = half.getIntOrFloatBitWidth();
    auto widen = [&](Value v) -> Value {
      if (!isa<IntegerType>(half)) v = arith::BitcastOp::create(rw, loc, rw.getIntegerType(width), v);
      return arith::ExtUIOp::create(rw, loc, to[0], v);
    };
    Value hi = arith::ShLIOp::create(rw, loc, widen(a.getA()), cInt(rw, loc, to[0], width));
    rw.replaceOp(op, arith::OrIOp::create(rw, loc, hi, widen(a.getB())).getResult());
    return success();
  }
};

/// first and second of a pair of two equal halves: the high and the low half of its word, or the half itself where the
/// pair lies apart.
template <class Op, bool High> struct HalfLowering : Lowering<Op> {
  using Lowering<Op>::Lowering;
  LogicalResult matchAndRewrite(Op op, typename OpConversionPattern<Op>::OneToNOpAdaptor a, ConversionPatternRewriter &rw) const override {
    Type half = pairHalf(op.getJoin().getType());
    ValueRange pair = a.getJoin();
    if (!half || op->getResult(0).getType() != half) return rw.notifyMatchFailure(op, "only a pair of two equal integer or float halves lowers");
    if (pair.size() == 2) {
      rw.replaceOp(op, pair[High ? 0 : 1]);
      return success();
    }
    Location loc = op.getLoc();
    unsigned width = half.getIntOrFloatBitWidth();
    Value word = pair[0];
    if (!word.getType().isSignlessInteger(2 * width)) return rw.notifyMatchFailure(op, "the pair is not its word yet");
    if (High) word = arith::ShRUIOp::create(rw, loc, word, cInt(rw, loc, word.getType(), width));
    word = arith::TruncIOp::create(rw, loc, rw.getIntegerType(width), word);
    rw.replaceOp(op, isa<IntegerType>(half) ? word : arith::BitcastOp::create(rw, loc, half, word).getResult());
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

//===-- Combine.kt's views ----------------------------------------------------------------------------------------===//
// Before the conversion, a combine and a combineAll are what Combine.kt makes them: views, their parts read where the view
// is read, never a buffer of their own unless something reads one by index.  The laws TrikeShed.td states give the rest:
//   size(combine(a, b))   size(a) + size(b); a combineAll's, its parts' sizes added by a loop over a copy of its region;
//                         a slice's, its count; a series', its n; a select's, the select of the two
//   drain(combine(a, b))  drain(a), then drain(b) where it ended; a combineAll's, its parts drained in turn by a loop over
//                         a copy of its region; a series' (of the cells' type), its elements stored where they go
// A view something else reads (at, a call, a return, an scf.yield) is made here: a buffer of its size with the view
// drained into it, and a combineAll's coordinates, when they are read, each part's (start, length) from a loop over a copy
// of its region.  So a part is made where it is drained, once, and copied once; a part that is a slice is never made at
// all.  What the views leave unread is erased before the conversion sees it.

/// The one block of a view's region, cloned at the builder's insertion point with k for its argument: what it yields.
Value cloneBody(OpBuilder &b, Region &region, Value k) {
  IRMapping map;
  map.map(region.getArgument(0), k);
  for (Operation &op : region.front().without_terminator()) b.clone(op, map);
  return map.lookupOrDefault(cast<YieldOp>(region.front().getTerminator()).getValues()[0]);
}

/// A loop over a combineAll's parts carrying a position from `from`: step(part k, position, k) gives the next.
Value overParts(OpBuilder &b, Location loc, CombineAllOp all, Value from, function_ref<Value(Value, Value, Value)> step) {
  auto loop = scf::ForOp::create(b, loc, cIndex(b, loc, 0), all.getCount(), cIndex(b, loc, 1), ValueRange{from});
  OpBuilder::InsertionGuard guard(b);
  b.setInsertionPointToEnd(loop.getBody());
  Value k = loop.getInductionVar();
  scf::YieldOp::create(b, loc, ValueRange{step(cloneBody(b, all.getPart(), k), loop.getRegionIterArgs()[0], k)});
  return loop.getResult(0);
}

/// size(xs) by the laws, without making xs.
Value sizeOf(OpBuilder &b, Location loc, Value xs) {
  Operation *def = xs.getDefiningOp();
  if (auto c = dyn_cast_or_null<CombineOp>(def)) {
    Value total = cIndex(b, loc, 0);
    for (Value part : c.getParts()) total = arith::AddIOp::create(b, loc, total, sizeOf(b, loc, part));
    return total;
  }
  if (auto all = dyn_cast_or_null<CombineAllOp>(def); all && xs == all.getResult())
    return overParts(b, loc, all, cIndex(b, loc, 0),
                     [&](Value part, Value at, Value) -> Value { return arith::AddIOp::create(b, loc, at, sizeOf(b, loc, part)); });
  if (auto s = dyn_cast_or_null<SliceOp>(def)) return s.getCount();
  if (auto s = dyn_cast_or_null<SeriesOp>(def)) return s.getSize();
  if (auto s = dyn_cast_or_null<arith::SelectOp>(def))
    return arith::SelectOp::create(b, loc, s.getCondition(), sizeOf(b, loc, s.getTrueValue()), sizeOf(b, loc, s.getFalseValue()));
  return SizeOp::create(b, loc, b.getIndexType(), xs);
}

/// drain(xs) into `into` from `at` on, by the laws: where it ended.
Value drainAt(OpBuilder &b, Location loc, Value xs, Value into, Value at) {
  Operation *def = xs.getDefiningOp();
  if (auto c = dyn_cast_or_null<CombineOp>(def)) {
    for (Value part : c.getParts()) at = drainAt(b, loc, part, into, at);
    return at;
  }
  if (auto all = dyn_cast_or_null<CombineAllOp>(def); all && xs == all.getResult())
    return overParts(b, loc, all, at, [&](Value part, Value from, Value) { return drainAt(b, loc, part, into, from); });
  // a series of the cells' type: each element stored where it goes, never a buffer of its own
  if (auto s = dyn_cast_or_null<SeriesOp>(def); s && s.getType().getElement() == cast<MemRefType>(into.getType()).getElementType()) {
    auto loop = scf::ForOp::create(b, loc, cIndex(b, loc, 0), s.getSize(), cIndex(b, loc, 1));
    b.setInsertionPoint(loop.getBody()->getTerminator());
    Value k = loop.getInductionVar();
    store(b, loc, cloneBody(b, s.getAt(), k), into, arith::AddIOp::create(b, loc, at, k));
    b.setInsertionPointAfter(loop);
    return arith::AddIOp::create(b, loc, at, s.getSize());
  }
  Value rest = arith::SubIOp::create(b, loc, memref::DimOp::create(b, loc, into, 0), at);
  Value cells = memref::SubViewOp::create(b, loc, into, ArrayRef<OpFoldResult>{at}, ArrayRef<OpFoldResult>{rest},
                                          ArrayRef<OpFoldResult>{b.getIndexAttr(1)});
  return arith::AddIOp::create(b, loc, at, DrainOp::create(b, loc, b.getIndexType(), xs, cells));
}

/// A use of a view by the view it is a part of: an operand of a combine, or what a combineAll's region yields.
bool partOf(OpOperand &use) {
  Operation *by = use.getOwner();
  return isa<CombineOp>(by) || (isa<YieldOp>(by) && isa<CombineAllOp>(by->getParentOp()));
}

/// A view something else reads, made: a buffer of its size, drained into; a combineAll's coordinates, if they are read.
/// The view it is a part of, if any, drains that buffer.
void makeView(Operation *view, const TypeConverter &types) {
  OpBuilder b(view);
  Location loc = view->getLoc();
  Value xs = view->getResult(0);
  if (!llvm::all_of(xs.getUses(), partOf)) {
    auto t = cast<SeriesType>(xs.getType());
    Value buffer = memref::AllocOp::create(b, loc, MemRefType::get({ShapedType::kDynamic}, types.convertType(t.getElement())),
                                           ValueRange{sizeOf(b, loc, xs)});
    drainAt(b, loc, xs, buffer, cIndex(b, loc, 0));
    xs.replaceAllUsesWith(TextOp::create(b, loc, t, buffer).getResult());
  }
  auto all = dyn_cast<CombineAllOp>(view);
  if (!all || all.getCoordinates().use_empty()) return;
  Type i64 = b.getI64Type();
  Value coordinates = memref::AllocOp::create(b, loc, MemRefType::get({ShapedType::kDynamic}, i64), ValueRange{all.getCount()});
  Value c32 = cInt(b, loc, i64, 32), mask = cInt(b, loc, i64, 0xffffffff);
  overParts(b, loc, all, cIndex(b, loc, 0), [&](Value part, Value at, Value k) -> Value {
    Value n = sizeOf(b, loc, part);
    Value s = arith::IndexCastUIOp::create(b, loc, i64, at), l = arith::IndexCastUIOp::create(b, loc, i64, n);
    store(b, loc, arith::OrIOp::create(b, loc, arith::ShLIOp::create(b, loc, s, c32), arith::AndIOp::create(b, loc, l, mask)),
          coordinates, k);
    return arith::AddIOp::create(b, loc, at, n);
  });
  all.getCoordinates().replaceAllUsesWith(TextOp::create(b, loc, all.getCoordinates().getType(), coordinates).getResult());
}

/// The views of f rewritten by the laws until none is left: sizes and drains of views first, then the views something
/// else still reads made; what is left unread is erased after each.
void rewriteViews(func::FuncOp f, const TypeConverter &types) {
  auto isView = [](Value xs) { return isa_and_nonnull<CombineOp, CombineAllOp>(xs.getDefiningOp()); };
  IRRewriter rw(f.getContext());
  for (;;) {
    SmallVector<Operation *> reads, views;
    f.walk([&](Operation *op) {
      if (isa<SizeOp>(op) || (isa<DrainOp>(op) && isa<MemRefType>(op->getOperand(1).getType())))
        if (isView(op->getOperand(0))) reads.push_back(op);
    });
    for (Operation *op : reads) {
      OpBuilder b(op);
      Location loc = op->getLoc();
      Value end = isa<SizeOp>(op) ? sizeOf(b, loc, op->getOperand(0)) : drainAt(b, loc, op->getOperand(0), op->getOperand(1), cIndex(b, loc, 0));
      if (end.getType() != op->getResult(0).getType()) end = arith::IndexCastOp::create(b, loc, op->getResult(0).getType(), end);
      op->replaceAllUsesWith(ValueRange{end});
      op->erase();
    }
    if (!reads.empty()) (void)runRegionDCE(rw, f->getRegions());
    f.walk([&](Operation *op) {
      // (a view of pairs that lie apart is not made: it is left to fail the conversion, not to be allocated as one buffer)
      if (isa<CombineOp, CombineAllOp>(op) && !llvm::all_of(op->getUses(), partOf) && elementOf(types, op->getResult(0).getType()))
        views.push_back(op);
    });
    if (views.empty()) return;
    for (Operation *view : views) makeView(view, types);
    (void)runRegionDCE(rw, f->getRegions());
  }
}

//===-- GroupBy.kt and KeyedJoin.kt -------------------------------------------------------------------------------===//
// Before the conversion, groupBy and keyedJoin are rewritten into the ops they decompose into, the op's order region
// cloned wherever the decomposition compares two elements (TrikeShed.td states the laws):
//   groupBy(xs) [ordered] by o   ids = 0 ..< size(xs); perm = sorted(ids) by o(xs[a], xs[b]), stable; the runs of equal
//                                elements start where o(xs[perm[p - 1]], xs[perm[p]]) != 0 (where), and runs = perm[starts]
//                                holds each run's first index, in o's order; the exemplars are runs (ordered), else runs
//                                sorted, first appearance; codes = alpha(ids) {i -> the run of i (bisect by o), then, but
//                                ordered, that run's first index among the exemplars (bisect)}
//   keyedJoin(l, r) by o         series(size(l)) {i -> j(lo, hi - lo)}, lo and hi the lower and upper bound of l[i] in r: a
//                                bisect each, by an order that is never 0 (o < 0, then o <= 0, sorts before)

/// A `Op` made of `args`, its region one block taking `types` that yields what `body` makes of them.
template <class Op, class... Args>
Op withBody(OpBuilder &b, Location loc, TypeRange types, function_ref<Value(ValueRange)> body, Args &&...args) {
  auto op = Op::create(b, loc, std::forward<Args>(args)...);
  OpBuilder::InsertionGuard guard(b);
  Block *block = b.createBlock(&op->getRegion(0), {}, types, SmallVector<Location>(types.size(), loc));
  YieldOp::create(b, loc, ValueRange{body(block->getArguments())});
  return op;
}

/// o(x, y): the order region cloned here, or the signed order of two integers.
Value orderOf(OpBuilder &b, Location loc, Region &order, Value x, Value y) {
  if (order.empty()) return threeWay(b, loc, x, y);
  IRMapping map;
  map.map(order.getArguments(), ValueRange{x, y});
  for (Operation &op : order.front().without_terminator()) b.clone(op, map);
  return map.lookupOrDefault(cast<YieldOp>(order.front().getTerminator()).getValues()[0]);
}

Value element(OpBuilder &b, Location loc, Value xs, Value i) {
  return AtOp::create(b, loc, cast<SeriesType>(xs.getType()).getElement(), xs, i);
}

void expandGroupBy(GroupByOp op) {
  OpBuilder b(op);
  Location loc = op.getLoc();
  Value xs = op.getSeries();
  Type idx = b.getIndexType(), codes = op.getCodes().getType(), code = cast<SeriesType>(codes).getElement();
  auto by = [&](Value i, Value j) { return orderOf(b, loc, op.getOrder(), element(b, loc, xs, i), element(b, loc, xs, j)); };
  Value ids = withBody<SeriesOp>(b, loc, idx, [&](ValueRange k) -> Value { return arith::IndexCastOp::create(b, loc, code, k[0]); },
                                 codes, SizeOp::create(b, loc, idx, xs));
  Value perm = withBody<SortedOp>(b, loc, {code, code}, [&](ValueRange a) { return by(a[0], a[1]); }, codes, ids);
  Value starts = withBody<WhereOp>(b, loc, code, [&](ValueRange p) -> Value {
    Value zero = cInt(b, loc, code, 0);
    Value prev = arith::MaxSIOp::create(b, loc, arith::SubIOp::create(b, loc, p[0], cInt(b, loc, code, 1)), zero);
    Value differs = arith::CmpIOp::create(b, loc, arith::CmpIPredicate::ne, by(element(b, loc, perm, prev), element(b, loc, perm, p[0])),
                                          cInt(b, loc, b.getI32Type(), 0));
    return arith::OrIOp::create(b, loc, arith::CmpIOp::create(b, loc, arith::CmpIPredicate::eq, p[0], zero), differs);
  }, codes, ids);
  Value runs = ProjectOp::create(b, loc, codes, perm, starts);
  Value exemplars = op.getOrdered() ? runs : SortedOp::create(b, loc, codes, runs).getResult();
  Value coded = withBody<AlphaOp>(b, loc, code, [&](ValueRange i) -> Value {
    Value k = withBody<BisectOp>(b, loc, {code, code}, [&](ValueRange a) { return by(a[0], a[1]); }, idx, runs, i[0]);
    if (!op.getOrdered()) k = BisectOp::create(b, loc, idx, exemplars, element(b, loc, runs, k));
    return arith::IndexCastOp::create(b, loc, code, k);
  }, codes, ids);
  op.getCodes().replaceAllUsesWith(coded);
  op.getExemplars().replaceAllUsesWith(exemplars);
  op.erase();
}

void expandKeyedJoin(KeyedJoinOp op) {
  OpBuilder b(op);
  Location loc = op.getLoc();
  Value l = op.getLeft(), r = op.getRight();
  Type idx = b.getIndexType(), pair = cast<SeriesType>(op.getMatches().getType()).getElement(), half = pairHalf(pair);
  Type le = cast<SeriesType>(l.getType()).getElement(), re = cast<SeriesType>(r.getType()).getElement(), i32 = b.getI32Type();
  Value matches = withBody<SeriesOp>(b, loc, idx, [&](ValueRange i) -> Value {
    Value key = element(b, loc, l, i[0]);
    auto bound = [&](arith::CmpIPredicate before) -> Value {
      Value at = withBody<BisectOp>(b, loc, {re, le}, [&](ValueRange a) -> Value {
        Value c = arith::CmpIOp::create(b, loc, before, orderOf(b, loc, op.getOrder(), a[0], a[1]), cInt(b, loc, i32, 0));
        return arith::SelectOp::create(b, loc, c, cInt(b, loc, i32, -1), cInt(b, loc, i32, 1));
      }, idx, r, key);
      return arith::IndexCastOp::create(b, loc, half, arith::SubIOp::create(b, loc, cIndex(b, loc, -1), at));
    };
    Value lo = bound(arith::CmpIPredicate::slt), hi = bound(arith::CmpIPredicate::sle);
    return JOp::create(b, loc, pair, lo, arith::SubIOp::create(b, loc, hi, lo));
  }, op.getMatches().getType(), SizeOp::create(b, loc, idx, l));
  op.getMatches().replaceAllUsesWith(matches);
  op.erase();
}

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

//===-- ReifiedSplitSeries2: split rows, and series read where they are made --------------------------------------===//
// A Series2<A, B> and a split (ReifiedSplitSeries2<A, B>) lower to A's buffers, then B's: the sides stored apart, so
//   joins(a, b)            is a's buffers, then b's viewed to size(a) (Series.h joins: as many rows as a)
//   leftOf, rightOf        the buffers of that side, no Join per element
//   reify                  the same buffers: a Series2 already lies apart
// Before the conversion, by the laws, nothing of their own:
//   zipnext(xs)            joins(xs[0, n - m], xs[m, n - m]), m = min(n, 1): Series.kt zipWithNext, two views of xs
//   splitSelect(s, idx)    reify(joins(project(leftOf(s), idx), project(rightOf(s), idx))): both sides in step
//   take(s, i)             at(leftOf(s), i) (valueAt), or at(rightOf(s), i) (rightAt) where the result is B and not A;
//                          take(c, i) of a cursor at a constant i is column(c, key i)
//   series(n) {k -> x}     read in place where its region is pure ops without regions and only at, size, slice and bisect
//                          read it (Series.kt: the region runs each time an element is read): at(.., i) is x at k = i, a
//                          slice the series of its count at k + offset, a bisect probes x at its midpoints.  So a search
//                          over keys read at a row stride reads log n of them and makes no buffer.
std::pair<Type, Type> sidesOf(Type t) {
  if (auto s = dyn_cast<SplitType>(t)) return {s.getA(), s.getB()};
  auto s = cast<Series2Type>(t);
  return {s.getA(), s.getB()};
}

void addSplitConversions(CursorTypes &types) {
  auto sides = [&types](Type t, SmallVectorImpl<Type> &out) -> std::optional<LogicalResult> {
    SmallVector<Type> bs;
    auto [a, b] = sidesOf(t);
    if (!types.buffers(a, bs) || !types.buffers(b, bs)) return std::nullopt;
    out.append(bs);
    return success();
  };
  types.addConversion([sides](Series2Type t, SmallVectorImpl<Type> &out) { return sides(t, out); });
  types.addConversion([sides](SplitType t, SmallVectorImpl<Type> &out) { return sides(t, out); });
}

struct JoinsLowering : Lowering<JoinsOp> {
  using Lowering::Lowering;
  LogicalResult matchAndRewrite(JoinsOp op, OneToNOpAdaptor a, ConversionPatternRewriter &rw) const override {
    Location loc = op.getLoc();
    SmallVector<Value, 4> sides(a.getA());
    Value n = length(rw, loc, sides[0]);
    for (Value b : a.getB()) {
      Value view = memref::SubViewOp::create(rw, loc, b, ArrayRef<OpFoldResult>{rw.getIndexAttr(0)}, ArrayRef<OpFoldResult>{n},
                                             ArrayRef<OpFoldResult>{rw.getIndexAttr(1)});
      sides.push_back(view.getType() != b.getType() ? memref::CastOp::create(rw, loc, b.getType(), view).getResult() : view);
    }
    replaceWith(rw, op, sides);
    return success();
  }
};

/// leftOf / rightOf (Left false) of a Series2 or a split, and reify (All): A's buffers come first.
template <class Op, bool Left, bool All = false> struct SideLowering : Lowering<Op> {
  using Lowering<Op>::Lowering;
  LogicalResult matchAndRewrite(Op op, typename OpConversionPattern<Op>::OneToNOpAdaptor a, ConversionPatternRewriter &rw) const override {
    ValueRange all = a.getSeries();
    size_t n = converted(this->types(), sidesOf(op.getSeries().getType()).first).size();
    if (!n || n >= all.size()) return rw.notifyMatchFailure(op, "a side whose elements do not lower");
    replaceWith(rw, op, All ? all : Left ? all.take_front(n) : all.drop_front(n));
    return success();
  }
};

/// The one block of `region` cloned at the builder's insertion point with `args` for its arguments: what it yields.
Value cloneWith(OpBuilder &b, Region &region, ValueRange args) {
  IRMapping map;
  map.map(region.getArguments(), args);
  for (Operation &op : region.front().without_terminator()) b.clone(op, map);
  return map.lookupOrDefault(cast<YieldOp>(region.front().getTerminator()).getValues()[0]);
}

/// zipnext, splitSelect and take, rewritten by the laws above.  A take this cannot place is left to fail the conversion.
void rewriteSplits(func::FuncOp f) {
  SmallVector<Operation *> ops;
  f.walk([&](Operation *op) { if (isa<ZipNextOp, SplitSelectOp, TakeOp>(op)) ops.push_back(op); });
  MLIRContext *ctx = f.getContext();
  for (Operation *op : ops) {
    OpBuilder b(op);
    Location loc = op->getLoc();
    auto side = [&](Value s, Type e, bool left) -> Value {
      Type t = SeriesType::get(ctx, e);
      return left ? LeftOfOp::create(b, loc, t, s).getResult() : RightOfOp::create(b, loc, t, s).getResult();
    };
    Value to;
    if (auto z = dyn_cast<ZipNextOp>(op)) {
      Value xs = z.getSeries(), n = sizeOf(b, loc, xs);
      Value m = arith::MinUIOp::create(b, loc, n, cIndex(b, loc, 1)), count = arith::SubIOp::create(b, loc, n, m);
      to = JoinsOp::create(b, loc, z.getType(), SliceOp::create(b, loc, xs.getType(), xs, cIndex(b, loc, 0), count),
                           SliceOp::create(b, loc, xs.getType(), xs, m, count));
    } else if (auto s = dyn_cast<SplitSelectOp>(op)) {
      auto [ta, tb] = sidesOf(s.getSplit().getType());
      Value l = ProjectOp::create(b, loc, SeriesType::get(ctx, ta), side(s.getSplit(), ta, true), s.getIndices());
      Value r = ProjectOp::create(b, loc, SeriesType::get(ctx, tb), side(s.getSplit(), tb, false), s.getIndices());
      to = ReifyOp::create(b, loc, s.getType(), JoinsOp::create(b, loc, Series2Type::get(ctx, ta, tb), l, r));
    } else {
      auto t = cast<TakeOp>(op);
      Type of = t.getOf().getType(), r = t.getType();
      APInt i;
      if (auto c = dyn_cast<CursorType>(of); c && matchPattern(t.getColumn(), m_ConstantInt(&i))) {
        Value k = KeyOp::create(b, loc, ColKeyType::get(ctx, c.getSchema()), b.getI64IntegerAttr(i.getZExtValue()));
        to = ColumnOp::create(b, loc, r, t.getOf(), k);
      } else if (isa<SplitType, Series2Type>(of) && (r == sidesOf(of).first || r == sidesOf(of).second)) {
        to = AtOp::create(b, loc, r, side(t.getOf(), r, r == sidesOf(of).first), t.getColumn());
      } else continue;
    }
    op->getResult(0).replaceAllUsesWith(to);
    op->erase();
  }
  // leftOf / rightOf of a joins (through a reify): the side itself, b viewed to size(a); so zipnext's sides stay slices
  SmallVector<Operation *> sides;
  f.walk([&](Operation *op) { if (isa<LeftOfOp, RightOfOp>(op)) sides.push_back(op); });
  for (Operation *op : sides) {
    auto r = op->getOperand(0).getDefiningOp<ReifyOp>();
    auto j = (r ? r.getSeries() : op->getOperand(0)).getDefiningOp<JoinsOp>();
    if (!j) continue;
    OpBuilder b(op);
    Location loc = op->getLoc();
    Value to = isa<LeftOfOp>(op) ? j.getA() : SliceOp::create(b, loc, j.getB().getType(), j.getB(), cIndex(b, loc, 0), sizeOf(b, loc, j.getA()));
    op->getResult(0).replaceAllUsesWith(to);
    op->erase();
    if (r && r->use_empty()) r->erase();
    if (j->use_empty()) j->erase();
  }
}

/// A series made where it is read: its region pure ops without regions, and only at, size, slice and bisect read it.
bool readInPlace(SeriesOp s) {
  for (Operation &op : s.getAt().front().without_terminator())
    if (op.getNumRegions() || !isMemoryEffectFree(&op)) return false;
  return llvm::all_of(s->getUses(), [](OpOperand &u) { return u.getOperandNumber() == 0 && isa<AtOp, SizeOp, SliceOp, BisectOp>(u.getOwner()); });
}

/// bisect(series(n) {k -> x}, key): BisectLowering's search with x made at each midpoint (and the order cloned there).
Value bisectInPlace(OpBuilder &b, BisectOp op, SeriesOp s) {
  Location loc = op.getLoc();
  Type idx = b.getIndexType(), i1 = b.getI1Type();
  Value zero = cIndex(b, loc, 0), one = cIndex(b, loc, 1), z32 = cInt(b, loc, b.getI32Type(), 0);
  SmallVector<Type> state{idx, idx, idx, i1}; // lo, hi, where it was found, found
  SmallVector<Location> locs(4, loc);
  auto search = scf::WhileOp::create(b, loc, TypeRange(state), ValueRange{zero, s.getSize(), zero, cInt(b, loc, i1, 0)});
  Block *before = b.createBlock(&search.getBefore(), {}, TypeRange(state), locs);
  Value open = arith::CmpIOp::create(b, loc, arith::CmpIPredicate::ult, before->getArgument(0), before->getArgument(1));
  Value notFound = arith::XOrIOp::create(b, loc, before->getArgument(3), cInt(b, loc, i1, 1));
  scf::ConditionOp::create(b, loc, arith::AndIOp::create(b, loc, open, notFound), before->getArguments());
  Block *after = b.createBlock(&search.getAfter(), {}, TypeRange(state), locs);
  Value lo = after->getArgument(0), hi = after->getArgument(1);
  Value mid = arith::ShRUIOp::create(b, loc, arith::AddIOp::create(b, loc, lo, hi), one);
  Value x = cloneWith(b, s.getAt(), ValueRange{mid});
  Value c = op.getOrder().empty() ? threeWay(b, loc, x, op.getKey()) : cloneWith(b, op.getOrder(), ValueRange{x, op.getKey()});
  Value below = arith::CmpIOp::create(b, loc, arith::CmpIPredicate::slt, c, z32);
  Value above = arith::CmpIOp::create(b, loc, arith::CmpIPredicate::sgt, c, z32);
  Value equal = arith::CmpIOp::create(b, loc, arith::CmpIPredicate::eq, c, z32);
  Value lo2 = arith::SelectOp::create(b, loc, below, arith::AddIOp::create(b, loc, mid, one), lo);
  scf::YieldOp::create(b, loc, ValueRange{lo2, arith::SelectOp::create(b, loc, above, mid, hi), mid, equal});
  b.setInsertionPointAfter(search);
  Value missing = arith::SubIOp::create(b, loc, arith::SubIOp::create(b, loc, zero, search.getResult(0)), one);
  return arith::SelectOp::create(b, loc, search.getResult(3), search.getResult(2), missing);
}

void fuseSeriesReads(func::FuncOp f) {
  for (bool again = true; again;) {
    again = false;
    SmallVector<SeriesOp> lazy;
    f.walk([&](SeriesOp s) { if (readInPlace(s)) lazy.push_back(s); });
    for (SeriesOp s : lazy) {
      for (OpOperand &u : llvm::make_early_inc_range(s->getUses())) {
        Operation *by = u.getOwner();
        OpBuilder b(by);
        Location loc = by->getLoc();
        Value to;
        if (auto at = dyn_cast<AtOp>(by)) to = cloneWith(b, s.getAt(), ValueRange{toIndex(b, loc, at.getIndex())});
        else if (isa<SizeOp>(by)) to = s.getSize();
        else if (auto bi = dyn_cast<BisectOp>(by)) to = bisectInPlace(b, bi, s);
        else {
          auto sl = cast<SliceOp>(by);
          auto view = SeriesOp::create(b, loc, sl.getType(), sl.getCount());
          Block *k = b.createBlock(&view.getAt(), {}, TypeRange{b.getIndexType()}, {loc});
          YieldOp::create(b, loc, ValueRange{cloneWith(b, s.getAt(), ValueRange{arith::AddIOp::create(b, loc, k->getArgument(0), sl.getOffset())})});
          to = view.getResult();
          again = true;
        }
        by->getResult(0).replaceAllUsesWith(to);
        by->erase();
      }
      s->erase();
    }
  }
}

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

    // the split rows by their laws, and the series read where they are made (ReifiedSplitSeries2, below)
    addSplitConversions(types);
    getOperation().walk([&](func::FuncOp f) { rewriteSplits(f), fuseSeriesReads(f); });
    // combine and combineAll first, by Combine.kt's laws: what is left of them are the drains of their parts
    // groupBy and keyedJoin first, into the ops they decompose into (GroupBy.kt and KeyedJoin.kt, above)
    SmallVector<Operation *> joins;
    getOperation().walk([&](Operation *op) { if (isa<GroupByOp, KeyedJoinOp>(op)) joins.push_back(op); });
    for (Operation *op : joins) isa<GroupByOp>(op) ? expandGroupBy(cast<GroupByOp>(op)) : expandKeyedJoin(cast<KeyedJoinOp>(op));
    getOperation().walk([&](func::FuncOp f) { rewriteViews(f, types); });

    RewritePatternSet patterns(ctx);
    patterns.add<ColumnLowering, FacetLowering, SizeLowering, AtLowering, SeriesLowering, AlphaLowering, WhereLowering,
                 ProjectLowering, SliceLowering, FoldLowering, CompareLowering, SortedLowering, BisectLowering, JLowering,
                 HalfLowering<FirstOp, true>, HalfLowering<SecondOp, false>, DrainLowering, PartsLowering, AdjacencyLowering, ClosureLowering, TextLowering>(types, ctx);
    patterns.add<JoinsLowering, SideLowering<LeftOfOp, true>, SideLowering<RightOfOp, false>, SideLowering<ReifyOp, true, true>>(types, ctx);
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
