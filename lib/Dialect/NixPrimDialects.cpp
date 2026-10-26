//===- NixPrimDialects.cpp - The continent dialects, defined by IRDL data -===//
//
// The 105 primops live in 11 dialects (nixnum, nixstr, nixlist, ...).  Their
// declaration is NixPrims.irdl.mlir: IRDL, i.e. a *dialect definition written as
// IR*.  Everything IRDL can express (names, arity, result) is checked by the
// stock IRDL verifier.  What it cannot express rides along as attributes of each
// `irdl.operation` (`nix.key`, `nix.fx`, `nix.fold`), and this file turns those
// into behaviour *generically*, with no code per op:
//
//   effects      a MemoryEffectOpInterface fallback model, so the stock `cse`,
//                `canonicalize` and DCE treat the ops according to `nix.fx`
//   assembly     `nixnum.add(%a, %b)`, one parser/printer pair for every op
//   folding      a rewrite pattern per `nix.fold` op (dynamic dialects have no
//                constant materializer, so MLIR's own fold hook cannot be used)
//   primop table the core dialect's key -> op table used by the devirtualizer
//                and the evaluator
//
// Nothing here knows an op by name.
//
//===----------------------------------------------------------------------===//

#include "NixDialect/NixDialect.h"

#include "mlir/Dialect/IRDL/IR/IRDL.h"
#include "mlir/Dialect/IRDL/IRDLLoading.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/ExtensibleDialect.h"
#include "mlir/IR/Matchers.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Parser/Parser.h"
#include "llvm/ADT/StringSwitch.h"
#include "llvm/Support/ErrorHandling.h"
#include "llvm/Support/MemoryBuffer.h"
#include "llvm/Support/raw_ostream.h"

using namespace mlir;
using namespace mlir::nix;

static const char kPrimsIRDL[] =
#include "NixDialect/NixPrimsIRDL.inc"
    ;

namespace {

//===----------------------------------------------------------------------===//
// Effects, from `nix.fx`
//===----------------------------------------------------------------------===//

struct PrimEffects : public MemoryEffectOpInterface::FallbackModel<PrimEffects> {
  void getEffects(Operation *op, SmallVectorImpl<MemoryEffects::EffectInstance> &effects) const {
    auto *core = op->getContext()->getLoadedDialect<NixDialect>();
    const NixDialect::PrimInfo *info = core->primOf(op);
    switch (info ? info->fx : NixDialect::PrimFx::User) {
    case NixDialect::PrimFx::Pure:
      return;
    case NixDialect::PrimFx::User:
      effects.emplace_back(MemoryEffects::Write::get(), NixTraceResource::get());
      return;
    case NixDialect::PrimFx::FS:
      effects.emplace_back(MemoryEffects::Read::get(), NixFSResource::get());
      return;
    case NixDialect::PrimFx::Env:
      effects.emplace_back(MemoryEffects::Read::get(), NixEnvResource::get());
      return;
    case NixDialect::PrimFx::Store:
      effects.emplace_back(MemoryEffects::Write::get(), NixStoreResource::get());
      return;
    case NixDialect::PrimFx::Import:
      effects.emplace_back(MemoryEffects::Read::get(), NixFSResource::get());
      effects.emplace_back(MemoryEffects::Write::get(), NixTraceResource::get());
      return;
    }
  }
};

//===----------------------------------------------------------------------===//
// Folding, from `nix.fold`
//===----------------------------------------------------------------------===//

/// Every foldable primop is folded by the same code: hand the scalar constant
/// operands to the evaluator's own implementation of the primop.  If the call
/// throws nothing is folded and the error stays a runtime error.
struct FoldPrim : public RewritePattern {
  FoldPrim(StringRef opName, MLIRContext *ctx) : RewritePattern(opName, /*benefit=*/1, ctx) {}
  LogicalResult matchAndRewrite(Operation *op, PatternRewriter &rw) const override {
    auto *core = op->getContext()->getLoadedDialect<NixDialect>();
    const NixDialect::PrimInfo *info = core->primOf(op);
    if (!info || !core->primFolder)
      return failure();
    SmallVector<Attribute, 4> args;
    for (Value v : op->getOperands()) {
      Attribute a;
      if (!matchPattern(v, m_Constant(&a)))
        return failure();
      args.push_back(a);
    }
    Attribute r = core->primFolder(info->key, args);
    if (!r)
      return failure();
    Operation *c = core->materializeConstant(rw, r, op->getResult(0).getType(), op->getLoc());
    if (!c)
      return failure();
    rw.replaceOp(op, c->getResult(0));
    return success();
  }
};

//===----------------------------------------------------------------------===//
// Assembly: `nixnum.add(%a, %b)`
//===----------------------------------------------------------------------===//

ParseResult parsePrim(OpAsmParser &p, OperationState &st) {
  SmallVector<OpAsmParser::UnresolvedOperand> operands;
  if (p.parseLParen() || p.parseOperandList(operands) || p.parseRParen() ||
      p.parseOptionalAttrDict(st.attributes))
    return failure();
  Type v = ValueType::get(p.getContext());
  SmallVector<Type> types(operands.size(), v);
  if (p.resolveOperands(operands, types, p.getCurrentLocation(), st.operands))
    return failure();
  st.addTypes(v);
  return success();
}

void printPrim(Operation *op, OpAsmPrinter &p, StringRef defaultDialect) {
  // Unlike an ODS op, a dynamic op's print function must print its own name
  // (OpState::printOpName is protected; this is its whole body).
  StringRef name = op->getName().getStringRef();
  if (name.starts_with((defaultDialect + ".").str()) && name.count('.') == 1)
    name = name.drop_front(defaultDialect.size() + 1);
  p << name << "(";
  p.printOperands(op->getOperands());
  p << ")";
  p.printOptionalAttrDict(op->getAttrs());
}

//===----------------------------------------------------------------------===//
// Reaching the definition of an IRDL-defined op
//===----------------------------------------------------------------------===//

/// `irdl::loadDialects` is all-or-nothing: it registers the ops and returns, with
/// no hook for assembly or folding, and ExtensibleDialect has no lookup of an op's
/// DynamicOpDefinition.  OperationName::getImpl() is protected; this is the one
/// place that reaches through it.  (docs/COMBINATORS.md, failure F3.)
struct NameAccess : public OperationName {
  static DynamicOpDefinition *definition(OperationName name) {
    return static_cast<DynamicOpDefinition *>(reinterpret_cast<NameAccess &>(name).getImpl());
  }
};

std::optional<NixDialect::PrimFx> parseFx(StringRef s) {
  return llvm::StringSwitch<std::optional<NixDialect::PrimFx>>(s)
      .Case("pure", NixDialect::PrimFx::Pure)
      .Case("user", NixDialect::PrimFx::User)
      .Case("fs", NixDialect::PrimFx::FS)
      .Case("env", NixDialect::PrimFx::Env)
      .Case("store", NixDialect::PrimFx::Store)
      .Case("import", NixDialect::PrimFx::Import)
      .Default(std::nullopt);
}

} // namespace

LogicalResult mlir::nix::loadPrimDialects(MLIRContext *ctx, NixDialect &core) {
  if (!core.prims.empty()) // already defined (the extension can be applied twice)
    return success();
  ctx->getOrLoadDialect<irdl::IRDLDialect>();

  // The declaration is data, so it can be swapped without rebuilding:
  // MLNIX_PRIMS_IRDL=other.irdl.mlir (used by the mutation tests in test/mlir).
  StringRef source = kPrimsIRDL, name = "NixPrims.irdl.mlir";
  std::unique_ptr<llvm::MemoryBuffer> override;
  if (const char *path = getenv("MLNIX_PRIMS_IRDL")) {
    auto buf = llvm::MemoryBuffer::getFile(path);
    if (!buf) {
      emitError(UnknownLoc::get(ctx)) << "cannot read MLNIX_PRIMS_IRDL=" << path << ": " << buf.getError().message();
      return failure();
    }
    override = std::move(*buf);
    source = override->getBuffer();
    name = path;
  }
  OwningOpRef<ModuleOp> module = parseSourceString<ModuleOp>(source, ParserConfig(ctx), name);
  if (!module)
    return failure();
  if (failed(irdl::loadDialects(*module)))
    return failure();

  for (auto dialectOp : module->getOps<irdl::DialectOp>()) {
    auto scope = dialectOp->getAttrOfType<StringAttr>("nix.scope");
    auto continent = dialectOp->getAttrOfType<StringAttr>("nix.continent");
    core.continents[dialectOp.getSymName()] = {scope ? scope.getValue().str() : "", continent ? continent.getValue().str() : ""};
    for (auto opOp : dialectOp.getOps<irdl::OperationOp>()) {
      std::string full = (dialectOp.getSymName() + "." + opOp.getSymName()).str();
      OperationName name(full, ctx);
      if (!name.isRegistered())
        return opOp.emitError("IRDL did not register '") << full << "'";

      auto key = opOp->getAttrOfType<StringAttr>("nix.key");
      auto fxAttr = opOp->getAttrOfType<StringAttr>("nix.fx");
      if (!key || !fxAttr)
        return opOp.emitError("needs nix.key and nix.fx");
      std::optional<NixDialect::PrimFx> fx = parseFx(fxAttr.getValue());
      if (!fx)
        return opOp.emitError("unknown nix.fx '") << fxAttr.getValue() << "'";

      unsigned arity = 0;
      for (auto operands : opOp.getOps<irdl::OperandsOp>())
        arity = operands.getOperands().size();
      bool foldable = opOp->hasAttr("nix.fold");

      if (!core.registerPrim(key.getValue(), arity, name, *fx, foldable))
        return opOp.emitError("duplicate nix.key '") << key.getValue() << "'";

      DynamicOpDefinition *def = NameAccess::definition(name);
      def->setParseFn(parsePrim);
      def->setPrintFn(printPrim);
      if (foldable)
        def->setGetCanonicalizationPatternsFn(
            [full](RewritePatternSet &patterns, MLIRContext *c) { patterns.add<FoldPrim>(full, c); });
      name.attachInterface<PrimEffects>();
    }
  }
  return success();
}

//===----------------------------------------------------------------------===//
// Registration: the core dialect, with the continents defined as an extension
//===----------------------------------------------------------------------===//

/// Applied by MLIR once the core dialect is loaded (a DialectExtension): the
/// continents refer to its `!nix.value` type, so they can only be defined after it.
static void defineContinents(MLIRContext *ctx, NixDialect *core) {
  if (failed(loadPrimDialects(ctx, *core)))
    llvm::report_fatal_error("cannot define the primop dialects from NixPrims.irdl.mlir");
}

void mlir::nix::registerNixDialects(DialectRegistry &registry) {
  registry.insert<NixDialect>();
  registry.addExtension(defineContinents);
}

void mlir::nix::loadNixDialects(MLIRContext &ctx) {
  DialectRegistry registry;
  registerNixDialects(registry);
  ctx.appendDialectRegistry(registry);
  ctx.loadDialect<NixDialect>();
}
