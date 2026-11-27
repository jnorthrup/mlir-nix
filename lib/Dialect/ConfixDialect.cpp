//===- ConfixDialect.cpp - The confix dialect, confix-to-llvm, and the index below TrikeShed -------===//
//
// The scan is LLVM IR (lib/Confix/confix.ll).  This file registers the dialect and lowers its ops: `confix.scan` to a call of the IR's
// confix_scan_json, confix_scan_cbor or confix_scan_yaml, `confix.bands` to a call of ConfixScan.mlir's confix_scan_nix (the Nix delimiter
// scan, lowered at build time), and the reads of a Flat record (include/NixDialect/Confix.td) to loads from it.
// `confix.index`, `confix.columns` and `confix.unescape` make and read TrikeShed's series and cursors; trikeshed-lower-cursors lowers
// them, with the patterns this dialect gives it through CursorLoweringInterface (Composite/CursorLowering.h), into calls of their
// bodies, the functions of lowered/confix/ConfixIndex.mlir, as it lowers
// `confix.checked` (builtins.fromJSON's scan) to a call of its body, JsonRead.mlir's confix_scan_checked.

#include "NixDialect/Confix.h"

#include "Composite/CursorLowering.h"
#include "Composite/TrikeShed.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
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

LogicalResult UnescapeOp::verify() {
  if (getSyntax() != SyntaxKind::Json) return emitOpError("takes JSON only: its escapes are JSON's");
  if (!isSeriesOf(getText().getType(), 8) || !isSeriesOf(getValue().getType(), 8))
    return emitOpError("reads a !trikeshed.series<i8> and gives one");
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

// ---- confix.index, confix.columns and confix.unescape, lowered in trikeshed-lower-cursors' conversion: each a call of
// its body, a function of lowered/confix/ConfixIndex.mlir (the confix dialect's reads of the scan's record and
// TrikeShed's ops), over the buffers its operands lowered to

/// A call of `name`, a function of ConfixIndex.mlir (declared when the module does not define it): its results.
ResultRange body(ConversionPatternRewriter &rw, Operation *op, StringRef name, ArrayRef<Type> results, ArrayRef<Value> args) {
  auto module = op->getParentOfType<ModuleOp>();
  if (!module.lookupSymbol(name)) {
    OpBuilder::InsertionGuard g(rw);
    rw.setInsertionPointToStart(module.getBody());
    func::FuncOp::create(rw, module.getLoc(), name, rw.getFunctionType(ValueRange(args).getTypes(), results)).setPrivate();
  }
  return func::CallOp::create(rw, op->getLoc(), name, results, args)->getResults();
}

/// `data` as a constant of the module, seen as a series' buffer.
Value constant(ConversionPatternRewriter &rw, Operation *op, DenseElementsAttr data) {
  auto module = op->getParentOfType<ModuleOp>();
  auto type = MemRefType::get(data.getType().getShape(), data.getElementType());
  unsigned k = 0;
  auto name = SymbolTable::generateSymbolName<32>("confix_names", [&](StringRef n) { return module.lookupSymbol(n) != nullptr; }, k);
  {
    OpBuilder::InsertionGuard g(rw);
    rw.setInsertionPointToStart(module.getBody());
    memref::GlobalOp::create(rw, module.getLoc(), name, rw.getStringAttr("private"), type, data, /*constant=*/true, IntegerAttr());
  }
  Value whole = memref::GetGlobalOp::create(rw, op->getLoc(), type, name);
  return memref::CastOp::create(rw, op->getLoc(), composite::seriesBuffer(data.getElementType()), whole);
}

/// confix_index(text, syntax): the rows' three columns, the kid series, the fault and where it was.
struct IndexLowering : OpConversionPattern<IndexOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(IndexOp op, OpAdaptor a, ConversionPatternRewriter &rw) const override {
    Type i32 = rw.getI32Type(), pairs = composite::seriesBuffer(rw.getI64Type());
    Value syntax = arith::ConstantOp::create(rw, op.getLoc(), i32, rw.getI32IntegerAttr(int32_t(op.getSyntax())));
    auto r = body(rw, op, "confix_index", {pairs, composite::seriesBuffer(rw.getI8Type()), pairs, composite::seriesBuffer(i32), i32, i32},
                  {a.getText(), syntax});
    SmallVector<SmallVector<Value>> results{{r[0], r[1], r[2]}, {r[3]}, {r[4]}, {r[5]}};
    rw.replaceOpWithMultiple(op, std::move(results));
    return success();
  }
};

/// The Columns facet: confix_columns makes the table, the names its data (one text, and each name's (start, length) in
/// it); confix_column gives each column of it cells of its own, as a cursor's column has.
struct ColumnsLowering : OpConversionPattern<ColumnsOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(ColumnsOp op, OneToNOpAdaptor a, ConversionPatternRewriter &rw) const override {
    Location loc = op.getLoc();
    SmallString<64> text;
    SmallVector<int64_t> at;
    for (Attribute n : op.getNames()) {
      StringRef name = cast<StringAttr>(n).getValue();
      at.push_back(int64_t(text.size()) << 32 | int64_t(name.size()));
      text += name;
    }
    Type column = composite::seriesBuffer(rw.getI32Type());
    auto shaped = [&](size_t n, Type element) { return RankedTensorType::get({int64_t(n)}, element); };
    SmallVector<Value> args(a.getRows());
    args.append({a.getKids().front(), a.getText().front(), a.getObjects().front(),
                 constant(rw, op, DenseElementsAttr::getFromRawBuffer(shaped(text.size(), rw.getI8Type()), ArrayRef<char>(text.data(), text.size()))),
                 constant(rw, op, DenseElementsAttr::get(shaped(at.size(), rw.getI64Type()), ArrayRef<int64_t>(at)))});
    Value table = body(rw, op, "confix_columns", {column}, args)[0];
    Value width = arith::ConstantIndexOp::create(rw, loc, at.size());
    SmallVector<SmallVector<Value>> results(1);
    for (size_t c = 0; c < at.size(); c++)
      results[0].push_back(body(rw, op, "confix_column", {column}, {table, width, arith::ConstantIndexOp::create(rw, loc, c)})[0]);
    rw.replaceOpWithMultiple(op, std::move(results));
    return success();
  }
};

/// confix_unescape(text): the value, the first cells of a buffer of its own.
struct UnescapeLowering : OpConversionPattern<UnescapeOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(UnescapeOp op, OpAdaptor a, ConversionPatternRewriter &rw) const override {
    rw.replaceOp(op, body(rw, op, "confix_unescape", {a.getText().getType()}, {a.getText()}));
    return success();
  }
};

/// confix.checked: a call of its body, JsonRead.mlir's confix_scan_checked (declared when the module does not define it).
struct CheckedLowering : OpConversionPattern<CheckedOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(CheckedOp op, OpAdaptor a, ConversionPatternRewriter &rw) const override {
    auto module = op->getParentOfType<ModuleOp>();
    auto type = rw.getFunctionType({a.getRec().getType()}, {rw.getI32Type()});
    if (!module.lookupSymbol("confix_scan_checked")) {
      OpBuilder::InsertionGuard g(rw);
      rw.setInsertionPointToStart(module.getBody());
      func::FuncOp::create(rw, module.getLoc(), "confix_scan_checked", type).setPrivate();
    }
    rw.replaceOpWithNewOp<func::CallOp>(op, "confix_scan_checked", TypeRange{rw.getI32Type()}, ValueRange{a.getRec()});
    return success();
  }
};

struct ConfixCursorLowering : composite::CursorLoweringInterface {
  using CursorLoweringInterface::CursorLoweringInterface;
  void populateCursorLowering(const TypeConverter &types, RewritePatternSet &patterns, ConversionTarget &target) const override {
    patterns.add<IndexLowering, ColumnsLowering, UnescapeLowering, CheckedLowering>(types, patterns.getContext());
    target.addIllegalOp<IndexOp, ColumnsOp, UnescapeOp, CheckedOp>();
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
      if (isa<ScanOp, SizeOp, RowOp, KidOp, BandsOp>(op))
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
      } else if (auto bands = dyn_cast<BandsOp>(op)) {
        // the Nix delimiter scan: ConfixScan.mlir's entry, linked into NixFrontend as confix.ll's scanner is into MLIRNix
        StringRef callee = "confix_scan_nix";
        if (!module.lookupSymbol(callee)) {
          OpBuilder::InsertionGuard g(b);
          b.setInsertionPointToStart(module.getBody());
          LLVM::LLVMFuncOp::create(b, module.getLoc(), callee, LLVM::LLVMFunctionType::get(l.i32, {l.ptr}));
        }
        Value status = LLVM::CallOp::create(b, op->getLoc(), LLVM::LLVMFunctionType::get(l.i32, {l.ptr}), callee,
                                            ValueRange{bands.getRec()}).getResult();
        op->replaceAllUsesWith(ValueRange{status});
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
