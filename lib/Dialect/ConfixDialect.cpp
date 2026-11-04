//===- ConfixDialect.cpp - The confix dialect, and confix-to-llvm -----------------------===//
//
// The scan is LLVM IR (lib/Confix/confix.ll).  This file registers the dialect and lowers its ops: `confix.scan` to a call of the IR's
// confix_scan_json, confix_scan_cbor or confix_scan_yaml, and the reads of a Flat record (include/NixDialect/Confix.td) to loads from it.

#include "NixDialect/Confix.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/Pass/Pass.h"

#include "NixDialect/ConfixDialect.cpp.inc"

#include "NixDialect/ConfixEnums.cpp.inc"

#define GET_OP_CLASSES
#include "NixDialect/Confix.cpp.inc"

namespace mlir::confix {

void ConfixDialect::initialize() {
  addOperations<
#define GET_OP_LIST
#include "NixDialect/Confix.cpp.inc"
      >();
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
