//===- ConfixDialect.cpp - The confix dialect, confix-to-llvm, and the index below TrikeShed -------===//
//
// The scan is LLVM IR (lib/Confix/confix.ll).  This file registers the dialect and lowers its ops: `confix.scan` to a call of the IR's
// confix_scan_json, confix_scan_cbor or confix_scan_yaml, and the reads of a Flat record (include/NixDialect/Confix.td) to loads from it.
// `confix.index` and `confix.columns` make and read TrikeShed's series and cursors; trikeshed-lower-cursors lowers them, with the
// patterns this dialect gives it through CursorLoweringInterface (Composite/CursorLowering.h).

#include "NixDialect/Confix.h"

#include "Composite/CursorLowering.h"
#include "Composite/TrikeShed.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Transforms/DialectConversion.h"

#include "NixDialect/ConfixDialect.cpp.inc"

#include "NixDialect/ConfixEnums.cpp.inc"

#define GET_OP_CLASSES
#include "NixDialect/Confix.cpp.inc"

namespace mlir::confix {

namespace {
bool isSeriesOf(Type t, unsigned width) {
  auto s = dyn_cast<composite::SeriesType>(t);
  return s && s.getElement().isSignlessInteger(width);
}
/// !trikeshed.cursor<"ConfixIndex", [!trikeshed.twin<i32>, i8, !trikeshed.twinpacked<i32>]>
bool isIndexRows(Type t) {
  auto c = dyn_cast<composite::CursorType>(t);
  if (!c || c.getSchema().getValue() != "ConfixIndex" || c.getColumns().size() != 3) return false;
  auto span = dyn_cast<composite::TwinType>(c.getColumns()[0]);
  auto kids = dyn_cast<composite::TwinPackedType>(c.getColumns()[2]);
  return span && span.getElement().isSignlessInteger(32) && c.getColumns()[1].isSignlessInteger(8) && kids &&
         kids.getElement().isSignlessInteger(32);
}
} // namespace

LogicalResult IndexOp::verify() {
  if (getSyntax() == SyntaxKind::Yaml)
    return emitOpError("takes JSON or CBOR: a YAML text needs confix.scan and its retry on Room");
  if (!isSeriesOf(getText().getType(), 8)) return emitOpError("scans a !trikeshed.series<i8>");
  if (!isIndexRows(getRows().getType()))
    return emitOpError("makes rows of !trikeshed.cursor<\"ConfixIndex\", [!trikeshed.twin<i32>, i8, !trikeshed.twinpacked<i32>]>");
  if (!isSeriesOf(getKids().getType(), 32)) return emitOpError("makes its kids as a !trikeshed.series<i32>");
  return success();
}

LogicalResult ColumnsOp::verify() {
  if (getSyntax() != SyntaxKind::Json) return emitOpError("takes JSON only: a key is matched by its bytes between its quotes");
  if (!isIndexRows(getRows().getType())) return emitOpError("reads the rows confix.index makes");
  if (!isSeriesOf(getKids().getType(), 32) || !isSeriesOf(getObjects().getType(), 32))
    return emitOpError("reads kids and objects as !trikeshed.series<i32>");
  if (!isSeriesOf(getText().getType(), 8)) return emitOpError("reads the text as a !trikeshed.series<i8>");
  auto table = dyn_cast<composite::CursorType>(getTable().getType());
  if (!table || table.getColumns().size() != getNames().size() ||
      llvm::any_of(table.getColumns(), [](Type t) { return !t.isSignlessInteger(32); }))
    return emitOpError("makes a cursor of one i32 column per name");
  for (Attribute n : getNames())
    if (cast<StringAttr>(n).getValue().empty()) return emitOpError("a name is not empty");
  return success();
}

namespace {

// ---- confix.index and confix.columns, lowered in trikeshed-lower-cursors' conversion

Value cIndex(OpBuilder &b, Location loc, int64_t v) { return arith::ConstantIndexOp::create(b, loc, v); }
Value cInt(OpBuilder &b, Location loc, Type t, int64_t v) { return arith::ConstantOp::create(b, loc, t, b.getIntegerAttr(t, v)); }
Value asIndex(OpBuilder &b, Location loc, Value v) {
  return v.getType().isIndex() ? v : arith::IndexCastUIOp::create(b, loc, b.getIndexType(), v).getResult();
}
Value load(OpBuilder &b, Location loc, Value buffer, Value i) { return memref::LoadOp::create(b, loc, buffer, ValueRange{asIndex(b, loc, i)}); }
void store(OpBuilder &b, Location loc, Value v, Value buffer, Value i) {
  memref::StoreOp::create(b, loc, v, buffer, ValueRange{asIndex(b, loc, i)});
}
/// (a << 32) | b, of two i32
Value pack(OpBuilder &b, Location loc, Value hi, Value lo) {
  Type i64 = b.getI64Type();
  Value h = arith::ShLIOp::create(b, loc, arith::ExtUIOp::create(b, loc, i64, hi), cInt(b, loc, i64, 32));
  return arith::OrIOp::create(b, loc, h, arith::ExtUIOp::create(b, loc, i64, lo));
}

/// The text's scan: confix.ll's scanner fills arrays sized for the text (room = n + 1 rows, which a JSON or CBOR text of n
/// bytes cannot outgrow), given through a Flat record and a CharSeries on the stack; then the columns of the rows found are
/// made, and the arrays are left to the deallocation pass.
struct IndexLowering : OpConversionPattern<IndexOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(IndexOp op, OpAdaptor a, ConversionPatternRewriter &rw) const override {
    Location loc = op.getLoc();
    MLIRContext *ctx = rw.getContext();
    Value text = a.getText();
    if (!isa<MemRefType>(text.getType())) return rw.notifyMatchFailure(op, "the text is not a buffer");
    Type i8 = rw.getI8Type(), i32 = rw.getI32Type(), i64 = rw.getI64Type(), idx = rw.getIndexType();
    Type ptr = LLVM::LLVMPointerType::get(ctx);
    auto scanType = LLVM::LLVMFunctionType::get(i32, {ptr, ptr});
    StringRef callee = op.getSyntax() == SyntaxKind::Json ? "confix_scan_json" : "confix_scan_cbor";
    auto module = op->getParentOfType<ModuleOp>();
    if (!module.lookupSymbol(callee)) {
      OpBuilder::InsertionGuard g(rw);
      rw.setInsertionPointToStart(module.getBody());
      LLVM::LLVMFuncOp::create(rw, module.getLoc(), callee, scanType);
    }
    Value zero = cIndex(rw, loc, 0), one = cIndex(rw, loc, 1);
    Value n = memref::DimOp::create(rw, loc, text, 0);
    Value room = arith::AddIOp::create(rw, loc, n, one);
    auto address = [&](Value buffer, Value offset) -> Value {
      Value p = memref::ExtractAlignedPointerAsIndexOp::create(rw, loc, buffer);
      if (offset) p = arith::AddIOp::create(rw, loc, p, offset);
      Value word = arith::IndexCastUIOp::create(rw, loc, i64, p);
      return LLVM::IntToPtrOp::create(rw, loc, ptr, ValueRange{word});
    };
    // the text's bytes start at its view's offset (an i8 buffer: the offset is in bytes)
    auto meta = memref::ExtractStridedMetadataOp::create(rw, loc, text);
    Value textAt = address(text, meta.getOffset());
    auto scratch = [&](Type e, Value count) -> Value {
      return memref::AllocOp::create(rw, loc, MemRefType::get({ShapedType::kDynamic}, e), ValueRange{count});
    };
    Value span = scratch(i32, arith::MulIOp::create(rw, loc, room, cIndex(rw, loc, 2)));
    Value tag = scratch(i8, room), depth = scratch(i32, room), start = scratch(i32, arith::AddIOp::create(rw, loc, room, one));
    Value kid = scratch(i32, room), work = scratch(i32, arith::MulIOp::create(rw, loc, room, cIndex(rw, loc, 3)));
    // the Flat record and the CharSeries (Confix.td): total, fault, at, room, span, tag, depth, start, kid, work; size, data,
    // pos, limit, mark
    Type flatType = LLVM::LLVMStructType::getLiteral(ctx, {i32, i32, i32, i32, ptr, ptr, ptr, ptr, ptr, ptr});
    Type charsType = LLVM::LLVMStructType::getLiteral(ctx, {i32, ptr, i32, i32, i32});
    Value one32 = LLVM::ConstantOp::create(rw, loc, i32, rw.getI32IntegerAttr(1));
    Value flat = LLVM::AllocaOp::create(rw, loc, ptr, flatType, one32);
    Value chars = LLVM::AllocaOp::create(rw, loc, ptr, charsType, one32);
    auto field = [&](Value record, Type recordType, int32_t k) -> Value {
      return LLVM::GEPOp::create(rw, loc, ptr, recordType, record, ArrayRef<LLVM::GEPArg>{0, k});
    };
    auto put = [&](Value v, Value record, Type recordType, int32_t k) { LLVM::StoreOp::create(rw, loc, v, field(record, recordType, k)); };
    put(arith::IndexCastUIOp::create(rw, loc, i32, room), flat, flatType, 3);
    int32_t k = 4;
    for (Value buffer : {span, tag, depth, start, kid, work}) put(address(buffer, Value()), flat, flatType, k++);
    Value n32 = arith::IndexCastUIOp::create(rw, loc, i32, n);
    put(n32, chars, charsType, 0);
    put(textAt, chars, charsType, 1);
    put(cInt(rw, loc, i32, 0), chars, charsType, 2);
    put(n32, chars, charsType, 3);
    put(cInt(rw, loc, i32, -1), chars, charsType, 4);
    Value fault = LLVM::CallOp::create(rw, loc, scanType, callee, ValueRange{chars, flat}).getResult();
    Value total = LLVM::LoadOp::create(rw, loc, i32, field(flat, flatType, 0));
    Value at = LLVM::LoadOp::create(rw, loc, i32, field(flat, flatType, 2));
    Value ok = arith::CmpIOp::create(rw, loc, arith::CmpIPredicate::eq, fault, cInt(rw, loc, i32, 0));
    Value rows = arith::SelectOp::create(rw, loc, ok, asIndex(rw, loc, total), zero);
    // the columns: span (open, close) and kids (first, count) as pairs, the tag as it is
    Value spanCol = composite::newSeriesBuffer(rw, loc, i64, rows), tagCol = composite::newSeriesBuffer(rw, loc, i8, rows);
    Value kidsCol = composite::newSeriesBuffer(rw, loc, i64, rows);
    {
      auto loop = scf::ForOp::create(rw, loc, zero, rows, one);
      rw.setInsertionPoint(loop.getBody()->getTerminator());
      Value r = loop.getInductionVar();
      Value r2 = arith::MulIOp::create(rw, loc, r, cIndex(rw, loc, 2));
      Value open = load(rw, loc, span, r2), close = load(rw, loc, span, arith::AddIOp::create(rw, loc, r2, one));
      store(rw, loc, pack(rw, loc, open, close), spanCol, r);
      store(rw, loc, load(rw, loc, tag, r), tagCol, r);
      Value first = load(rw, loc, start, r), next = load(rw, loc, start, arith::AddIOp::create(rw, loc, r, one));
      store(rw, loc, pack(rw, loc, first, arith::SubIOp::create(rw, loc, next, first)), kidsCol, r);
      rw.setInsertionPointAfter(loop);
    }
    // the kid series: start[total] rows, every row but the root
    auto counted = scf::IfOp::create(rw, loc, TypeRange{idx}, ok, /*withElseRegion=*/true);
    rw.setInsertionPointToStart(counted.thenBlock());
    scf::YieldOp::create(rw, loc, ValueRange{asIndex(rw, loc, load(rw, loc, start, rows))});
    rw.setInsertionPointToStart(counted.elseBlock());
    scf::YieldOp::create(rw, loc, ValueRange{zero});
    rw.setInsertionPointAfter(counted);
    Value nk = counted.getResult(0);
    Value kids = composite::newSeriesBuffer(rw, loc, i32, nk);
    {
      auto loop = scf::ForOp::create(rw, loc, zero, nk, one);
      rw.setInsertionPoint(loop.getBody()->getTerminator());
      store(rw, loc, load(rw, loc, kid, loop.getInductionVar()), kids, loop.getInductionVar());
      rw.setInsertionPointAfter(loop);
    }
    SmallVector<SmallVector<Value>> results{{spanCol, tagCol, kidsCol}, {kids}, {fault}, {at}};
    rw.replaceOpWithMultiple(op, std::move(results));
    return success();
  }
};

/// The Columns facet: for each object, each member's key against each name (its length, then its bytes, unrolled from
/// the name), the value's row stored where they match; -1 elsewhere.
struct ColumnsLowering : OpConversionPattern<ColumnsOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(ColumnsOp op, OneToNOpAdaptor a, ConversionPatternRewriter &rw) const override {
    Location loc = op.getLoc();
    if (a.getRows().size() != 3) return rw.notifyMatchFailure(op, "the rows are not three buffers");
    Value spanCol = a.getRows()[0], tagCol = a.getRows()[1], kidsCol = a.getRows()[2];
    Value kids = a.getKids().front(), text = a.getText().front(), objects = a.getObjects().front();
    Type i8 = rw.getI8Type(), i32 = rw.getI32Type(), i64 = rw.getI64Type();
    Value zero = cIndex(rw, loc, 0), one = cIndex(rw, loc, 1), two = cIndex(rw, loc, 2);
    Value m = memref::DimOp::create(rw, loc, objects, 0);
    SmallVector<StringRef> names;
    for (Attribute n : op.getNames()) names.push_back(cast<StringAttr>(n).getValue());
    SmallVector<Value> columns;
    for (size_t c = 0; c < names.size(); c++) columns.push_back(composite::newSeriesBuffer(rw, loc, i32, m));
    Value none = cInt(rw, loc, i32, -1), mask = cInt(rw, loc, i64, 0xffffffff), c32 = cInt(rw, loc, i64, 32);
    auto rowsLoop = scf::ForOp::create(rw, loc, zero, m, one);
    rw.setInsertionPoint(rowsLoop.getBody()->getTerminator());
    Value r = rowsLoop.getInductionVar();
    for (Value column : columns) store(rw, loc, none, column, r);
    Value obj = load(rw, loc, objects, r);
    Value isObject = arith::CmpIOp::create(rw, loc, arith::CmpIPredicate::eq, load(rw, loc, tagCol, obj),
                                           cInt(rw, loc, i8, int64_t(TagKind::Object)));
    auto inObject = scf::IfOp::create(rw, loc, isObject, /*withElseRegion=*/false);
    rw.setInsertionPoint(inObject.thenBlock()->getTerminator());
    Value fc = load(rw, loc, kidsCol, obj);
    Value first = arith::IndexCastUIOp::create(rw, loc, rw.getIndexType(), arith::ShRUIOp::create(rw, loc, fc, c32));
    Value count = arith::IndexCastUIOp::create(rw, loc, rw.getIndexType(), arith::AndIOp::create(rw, loc, fc, mask));
    auto members = scf::ForOp::create(rw, loc, zero, arith::DivUIOp::create(rw, loc, count, two), one);
    rw.setInsertionPoint(members.getBody()->getTerminator());
    Value at = arith::AddIOp::create(rw, loc, first, arith::MulIOp::create(rw, loc, members.getInductionVar(), two));
    Value key = load(rw, loc, kids, at), value = load(rw, loc, kids, arith::AddIOp::create(rw, loc, at, one));
    Value isString = arith::CmpIOp::create(rw, loc, arith::CmpIPredicate::eq, load(rw, loc, tagCol, key),
                                           cInt(rw, loc, i8, int64_t(TagKind::String)));
    Value keySpan = load(rw, loc, spanCol, key);
    Value open = arith::ShRUIOp::create(rw, loc, keySpan, c32), close = arith::AndIOp::create(rw, loc, keySpan, mask);
    // between the quotes: [open + 1, close)
    Value inner = arith::AddIOp::create(rw, loc, open, cInt(rw, loc, i64, 1));
    Value len = arith::SubIOp::create(rw, loc, close, inner);
    for (size_t c = 0; c < names.size(); c++) {
      StringRef name = names[c];
      Value sized = arith::AndIOp::create(rw, loc, isString,
          arith::CmpIOp::create(rw, loc, arith::CmpIPredicate::eq, len, cInt(rw, loc, i64, int64_t(name.size()))));
      auto ifSized = scf::IfOp::create(rw, loc, sized, /*withElseRegion=*/false);
      rw.setInsertionPoint(ifSized.thenBlock()->getTerminator());
      Value same = cInt(rw, loc, rw.getI1Type(), 1);
      for (size_t j = 0; j < name.size(); j++) {
        Value byte = load(rw, loc, text, arith::AddIOp::create(rw, loc, inner, cInt(rw, loc, i64, int64_t(j))));
        same = arith::AndIOp::create(rw, loc, same,
            arith::CmpIOp::create(rw, loc, arith::CmpIPredicate::eq, byte, cInt(rw, loc, i8, int64_t(int8_t(name[j])))));
      }
      auto ifSame = scf::IfOp::create(rw, loc, same, /*withElseRegion=*/false);
      rw.setInsertionPoint(ifSame.thenBlock()->getTerminator());
      store(rw, loc, value, columns[c], r);
      rw.setInsertionPointAfter(ifSized);
    }
    rw.setInsertionPointAfter(rowsLoop);
    SmallVector<SmallVector<Value>> results{SmallVector<Value>(columns.begin(), columns.end())};
    rw.replaceOpWithMultiple(op, std::move(results));
    return success();
  }
};

struct ConfixCursorLowering : composite::CursorLoweringInterface {
  using CursorLoweringInterface::CursorLoweringInterface;
  void populateCursorLowering(const TypeConverter &types, RewritePatternSet &patterns, ConversionTarget &target) const override {
    patterns.add<IndexLowering, ColumnsLowering>(types, patterns.getContext());
    target.addIllegalOp<IndexOp, ColumnsOp>();
    target.addLegalDialect<LLVM::LLVMDialect>();
  }
};

} // namespace

void ConfixDialect::initialize() {
  addOperations<
#define GET_OP_LIST
#include "NixDialect/Confix.cpp.inc"
      >();
  addInterfaces<ConfixCursorLowering>();
}

namespace {
/// The fields of the Flat record: total, fault, at, room, span, tag, depth, start, kid, work.
enum Field : int32_t { Total = 0, Fault = 1, At = 2, Room = 3, Span = 4, Tag = 5, Depth = 6, Start = 7, Kid = 8, Work = 9 };

struct Lowering {
  OpBuilder &b;
  Location loc;
  Type i32, i64, ptr, flat;

  Lowering(OpBuilder &b, Location loc) : b(b), loc(loc) {
    MLIRContext *ctx = b.getContext();
    i32 = b.getI32Type();
    i64 = b.getI64Type();
    ptr = LLVM::LLVMPointerType::get(ctx);
    flat = LLVM::LLVMStructType::getLiteral(ctx, {i32, i32, i32, i32, ptr, ptr, ptr, ptr, ptr, ptr});
  }

  Value constant(Type t, int64_t v) { return LLVM::ConstantOp::create(b, loc, t, b.getIntegerAttr(t, v)); }
  Value field(Value record, Field f, Type t) {
    Value p = LLVM::GEPOp::create(b, loc, ptr, flat, record, ArrayRef<LLVM::GEPArg>{0, int32_t(f)});
    return LLVM::LoadOp::create(b, loc, t, p);
  }
  /// element i of the array at p, i an i64
  Value element(Value p, Type elem, Value i) {
    Value q = LLVM::GEPOp::create(b, loc, ptr, elem, p, ArrayRef<LLVM::GEPArg>{i});
    return LLVM::LoadOp::create(b, loc, elem, q);
  }
  Value widen(Value i) { return LLVM::ZExtOp::create(b, loc, i64, i); }
};

/// The scanner is declared once, in the module, as an external function: confix.ll defines it.
void declare(ModuleOp module, StringRef name, Type ptr, Type i32) {
  if (module.lookupSymbol(name))
    return;
  OpBuilder b(module.getBodyRegion());
  LLVM::LLVMFuncOp::create(b, module.getLoc(), name, LLVM::LLVMFunctionType::get(i32, {ptr, ptr}));
}

struct ConfixToLLVMPass : PassWrapper<ConfixToLLVMPass, OperationPass<ModuleOp>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(ConfixToLLVMPass)
  StringRef getArgument() const override { return "confix-to-llvm"; }
  StringRef getDescription() const override {
    return "Lower the confix scan to calls of the IR scanner and loads of the Flat record";
  }
  void getDependentDialects(DialectRegistry &registry) const override { registry.insert<LLVM::LLVMDialect>(); }

  void runOnOperation() override {
    ModuleOp module = getOperation();
    SmallVector<Operation *> ops;
    module.walk([&](Operation *op) {
      if (isa<ScanOp, SizeOp, RowOp, KidOp>(op))
        ops.push_back(op);
    });
    for (Operation *op : ops) {
      OpBuilder b(op);
      Lowering l(b, op->getLoc());
      if (auto scan = dyn_cast<ScanOp>(op)) {
        StringRef callee = scan.getSyntax() == SyntaxKind::Json   ? "confix_scan_json"
                           : scan.getSyntax() == SyntaxKind::Cbor ? "confix_scan_cbor"
                                                                  : "confix_scan_yaml";
        declare(module, callee, l.ptr, l.i32);
        Value fault = LLVM::CallOp::create(b, op->getLoc(), LLVM::LLVMFunctionType::get(l.i32, {l.ptr, l.ptr}), callee,
                                           ValueRange{scan.getSrc(), scan.getFlat()}).getResult();
        Value at = l.field(scan.getFlat(), At, l.i32);
        op->replaceAllUsesWith(ValueRange{fault, at});
      } else if (auto size = dyn_cast<SizeOp>(op)) {
        op->replaceAllUsesWith(ValueRange{l.field(size.getFlat(), Total, l.i32)});
      } else if (auto row = dyn_cast<RowOp>(op)) {
        Value flat = row.getFlat(), k = l.widen(row.getK());
        Value span = l.field(flat, Span, l.ptr), tag = l.field(flat, Tag, l.ptr), depth = l.field(flat, Depth, l.ptr),
              start = l.field(flat, Start, l.ptr);
        Value one = l.constant(l.i64, 1);
        Value k2 = LLVM::ShlOp::create(b, op->getLoc(), k, one);
        Value open = l.element(span, l.i32, k2);
        Value close = l.element(span, l.i32, LLVM::AddOp::create(b, op->getLoc(), k2, one));
        Value tag8 = l.element(tag, b.getI8Type(), k);
        Value tag32 = LLVM::ZExtOp::create(b, op->getLoc(), l.i32, tag8);
        Value depthv = l.element(depth, l.i32, k);
        Value first = l.element(start, l.i32, k);
        Value next = l.element(start, l.i32, LLVM::AddOp::create(b, op->getLoc(), k, one));
        Value count = LLVM::SubOp::create(b, op->getLoc(), next, first);
        op->replaceAllUsesWith(ValueRange{open, close, tag32, depthv, first, count});
      } else if (auto kid = dyn_cast<KidOp>(op)) {
        Value row = l.element(l.field(kid.getFlat(), Kid, l.ptr), l.i32, l.widen(kid.getAt()));
        op->replaceAllUsesWith(ValueRange{row});
      }
      op->erase();
    }
  }
};
} // namespace

void registerConfixPasses() {
  static const bool registered = [] {
    PassRegistration<ConfixToLLVMPass>();
    return true;
  }();
  (void)registered;
}

} // namespace mlir::confix
