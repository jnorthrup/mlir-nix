//===- Composite.cpp - Join: folds and the densify conversion -------------===//

#include "Composite/Composite.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/Func/Transforms/FuncConversions.h"
#include "mlir/IR/DialectRegistry.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Transforms/DialectConversion.h"
#include "llvm/ADT/TypeSwitch.h"

using namespace mlir;
using namespace mlir::join;

#include "Composite/JoinDialect.cpp.inc"
#define GET_TYPEDEF_CLASSES
#include "Composite/JoinTypes.cpp.inc"
#define GET_OP_CLASSES
#include "Composite/JoinOps.cpp.inc"

void JoinDialect::initialize() {
  addTypes<
#define GET_TYPEDEF_LIST
#include "Composite/JoinTypes.cpp.inc"
      >();
  addOperations<
#define GET_OP_LIST
#include "Composite/JoinOps.cpp.inc"
      >();
}

//===----------------------------------------------------------------------===//
// Folds: the projections are the inverse of the constructor
//===----------------------------------------------------------------------===//

OpFoldResult MakeOp::fold(FoldAdaptor) {
  // (first p) j (second p) = p
  auto f = getA().getDefiningOp<FirstOp>();
  auto s = getB().getDefiningOp<SecondOp>();
  if (f && s && f.getPair() == s.getPair() && f.getPair().getType() == getType()) return f.getPair();
  return {};
}

OpFoldResult FirstOp::fold(FoldAdaptor) {
  if (auto m = getPair().getDefiningOp<MakeOp>()) return m.getA();
  return {};
}

OpFoldResult SecondOp::fold(FoldAdaptor) {
  if (auto m = getPair().getDefiningOp<MakeOp>()) return m.getB();
  return {};
}

//===----------------------------------------------------------------------===//
// join-densify: Join<A, B> of fixed-width scalars -> one integer, A in the high bits
//===----------------------------------------------------------------------===//

namespace {

std::optional<unsigned> scalarBits(Type t) {
  if (auto i = dyn_cast<IntegerType>(t)) return i.isSignless() ? std::optional<unsigned>(i.getWidth()) : std::nullopt;
  if (auto f = dyn_cast<FloatType>(t)) return f.getWidth();
  return std::nullopt;
}

struct DensifyTypes : TypeConverter {
  DensifyTypes() {
    addConversion([](Type t) { return t; });
    // A null result is a failure (a pair of something with no fixed width stays a join and
    // the conversion reports it); std::nullopt would fall through to the identity above.
    addConversion([this](PairType p) -> std::optional<Type> {
      Type a = convertType(p.getA()), b = convertType(p.getB());
      if (!a || !b) return Type();
      auto wa = scalarBits(a), wb = scalarBits(b);
      if (!wa || !wb) return Type();
      return IntegerType::get(p.getContext(), *wa + *wb);
    });
  }
};

/// Floats travel as their bits.
Value asInt(OpBuilder &b, Location loc, Value v) {
  if (auto f = dyn_cast<FloatType>(v.getType())) return arith::BitcastOp::create(b, loc, b.getIntegerType(f.getWidth()), v);
  return v;
}
Value fromInt(OpBuilder &b, Location loc, Value v, Type to) {
  return isa<FloatType>(to) ? arith::BitcastOp::create(b, loc, to, v).getResult() : v;
}
Value constant(OpBuilder &b, Location loc, IntegerType ty, unsigned v) {
  return arith::ConstantOp::create(b, loc, b.getIntegerAttr(ty, v));
}

struct MakeLowering : OpConversionPattern<MakeOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(MakeOp op, OpAdaptor ad, ConversionPatternRewriter &rw) const override {
    auto res = dyn_cast_or_null<IntegerType>(getTypeConverter()->convertType(op.getType()));
    if (!res) return rw.notifyMatchFailure(op, "the pair has no fixed width");
    Location loc = op.getLoc();
    Value a = asInt(rw, loc, ad.getA()), b = asInt(rw, loc, ad.getB());
    unsigned wb = cast<IntegerType>(b.getType()).getWidth();
    Value hi = arith::ExtUIOp::create(rw, loc, res, a);
    Value lo = arith::ExtUIOp::create(rw, loc, res, b);
    hi = arith::ShLIOp::create(rw, loc, hi, constant(rw, loc, res, wb));
    rw.replaceOpWithNewOp<arith::OrIOp>(op, hi, lo);
    return success();
  }
};

struct FirstLowering : OpConversionPattern<FirstOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(FirstOp op, OpAdaptor ad, ConversionPatternRewriter &rw) const override {
    auto &tc = *getTypeConverter();
    auto pair = dyn_cast<IntegerType>(ad.getPair().getType());
    Type a = tc.convertType(op.getType()), b = tc.convertType(cast<PairType>(op.getPair().getType()).getB());
    if (!pair || !a || !b || !scalarBits(a) || !scalarBits(b)) return rw.notifyMatchFailure(op, "the pair has no fixed width");
    Location loc = op.getLoc();
    Value hi = arith::ShRUIOp::create(rw, loc, ad.getPair(), constant(rw, loc, pair, *scalarBits(b)));
    Value bits = arith::TruncIOp::create(rw, loc, rw.getIntegerType(*scalarBits(a)), hi);
    rw.replaceOp(op, fromInt(rw, loc, bits, a));
    return success();
  }
};

struct SecondLowering : OpConversionPattern<SecondOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(SecondOp op, OpAdaptor ad, ConversionPatternRewriter &rw) const override {
    Type b = getTypeConverter()->convertType(op.getType());
    if (!isa<IntegerType>(ad.getPair().getType()) || !b || !scalarBits(b)) return rw.notifyMatchFailure(op, "the pair has no fixed width");
    Location loc = op.getLoc();
    Value bits = arith::TruncIOp::create(rw, loc, rw.getIntegerType(*scalarBits(b)), ad.getPair());
    rw.replaceOp(op, fromInt(rw, loc, bits, b));
    return success();
  }
};

struct DensifyPass : PassWrapper<DensifyPass, OperationPass<>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(DensifyPass)
  StringRef getArgument() const override { return "join-densify"; }
  StringRef getDescription() const override {
    return "Collapse Join<A,B> of fixed-width scalars into one integer: "
           "Twin<i32> -> i64 (TwInt), a segment <i32, <i32, i32>> -> i96, Twin<i64> -> i128";
  }
  void getDependentDialects(DialectRegistry &registry) const override { registry.insert<arith::ArithDialect, func::FuncDialect>(); }
  void runOnOperation() override {
    MLIRContext *ctx = &getContext();
    DensifyTypes tc;
    ConversionTarget target(*ctx);
    target.addLegalDialect<arith::ArithDialect>();
    target.addIllegalDialect<JoinDialect>();
    target.addDynamicallyLegalOp<func::FuncOp>(
        [&](func::FuncOp f) { return tc.isSignatureLegal(f.getFunctionType()) && tc.isLegal(&f.getBody()); });
    target.addDynamicallyLegalOp<func::ReturnOp, func::CallOp>([&](Operation *op) { return tc.isLegal(op); });
    target.markUnknownOpDynamicallyLegal([&](Operation *op) { return tc.isLegal(op); });
    RewritePatternSet patterns(ctx);
    patterns.add<MakeLowering, FirstLowering, SecondLowering>(tc, ctx);
    populateFunctionOpInterfaceTypeConversionPattern<func::FuncOp>(patterns, tc);
    populateReturnOpTypeConversionPattern(patterns, tc);
    populateCallOpTypeConversionPattern(patterns, tc);
    if (failed(applyFullConversion(getOperation(), target, std::move(patterns)))) signalPassFailure();
  }
};

} // namespace

void mlir::join::registerCompositeDialects(DialectRegistry &registry) {
  registry.insert<JoinDialect, arith::ArithDialect, func::FuncDialect>();
}

void mlir::join::registerCompositePasses() {
  static bool once = [] {
    PassRegistration<DensifyPass>();
    return true;
  }();
  (void)once;
}
