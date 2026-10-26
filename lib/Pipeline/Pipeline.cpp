//===- Pipeline.cpp - Pass pipelines and Transform scripts as data --------===//

#include "Nix/Pipeline.h"

#include "NixDialect/NixDialect.h"

#include "mlir/Dialect/Transform/DebugExtension/DebugExtension.h"
#include "mlir/Dialect/Transform/IR/TransformDialect.h"
#include "mlir/Dialect/Transform/IRDLExtension/IRDLExtension.h"
#include "mlir/Dialect/Transform/Interfaces/TransformInterfaces.h"
#include "mlir/Dialect/Transform/PDLExtension/PDLExtension.h"
#include "mlir/Dialect/Transform/Transforms/TransformInterpreterUtils.h"
#include "mlir/Dialect/Transform/TuneExtension/TuneExtension.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/Parser/Parser.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Pass/PassRegistry.h"
#include "mlir/Transforms/Passes.h"
#include "llvm/ADT/StringExtras.h"
#include "llvm/Support/MemoryBuffer.h"
#include "llvm/Support/raw_ostream.h"

using namespace mlir;

namespace nixpipe {

//===----------------------------------------------------------------------===//
// Registration
//===----------------------------------------------------------------------===//

void registerPasses() {
  static bool done = [] {
    nix::registerNixPasses();
    registerTransformsPasses(); // cse, canonicalize, symbol-dce, sccp, ...
    return true;
  }();
  (void)done;
}

void registerTransformDialects(DialectRegistry &registry) {
  registry.insert<transform::TransformDialect>();
  transform::registerDebugExtension(registry);
  transform::registerTuneExtension(registry);
  transform::registerIRDLExtension(registry);
  transform::registerPDLExtension(registry);
}

//===----------------------------------------------------------------------===//
// Driver 1: a PassManager built from text
//===----------------------------------------------------------------------===//

namespace {
class PassPipeline final : public Pipeline {
public:
  PassPipeline(OpPassManager &&parsed, MLIRContext &ctx, bool verify)
      : pm(&ctx, std::string(parsed.getOpAnchorName())) {
    static_cast<OpPassManager &>(pm) = std::move(parsed);
    // Per-call cost: no verification between passes, no instrumentation, no
    // crash reproducer, no timing.  (mlnix-opt keeps the verifier.)
    pm.enableVerifier(verify);
  }
  LogicalResult run(ModuleOp module) override { return pm.run(module); }

private:
  PassManager pm;
};
} // namespace

std::unique_ptr<Pipeline> makePassPipeline(MLIRContext &ctx, StringRef text, std::string &error,
                                           bool verify) {
  registerPasses();
  llvm::raw_string_ostream os(error);
  FailureOr<OpPassManager> parsed = parsePassPipeline(text, os);
  if (failed(parsed)) {
    os.flush();
    error = "invalid pass pipeline '" + text.str() + "': " + error;
    return nullptr;
  }
  return std::make_unique<PassPipeline>(std::move(*parsed), ctx, verify);
}

//===----------------------------------------------------------------------===//
// Driver 2: a Transform-dialect script, interpreted in-process
//===----------------------------------------------------------------------===//

namespace {
class TransformPipeline final : public Pipeline {
public:
  TransformPipeline(OwningOpRef<ModuleOp> script, Operation *entry, bool expensiveChecks)
      : script(std::move(script)), entry(entry) {
    options.enableExpensiveChecks(expensiveChecks);
  }
  LogicalResult run(ModuleOp module) override {
    // `transformModule` is null: the script is self-contained.  (A non-null
    // library module would be cloned and merged on *every* call.)
    return transform::applyTransformNamedSequence(module, entry, ModuleOp(), options);
  }

private:
  OwningOpRef<ModuleOp> script;
  Operation *entry;
  transform::TransformOptions options;
};
} // namespace

std::unique_ptr<Pipeline> makeTransformPipeline(MLIRContext &ctx, StringRef text, StringRef name,
                                                std::string &error, bool expensiveChecks) {
  registerPasses();
  DialectRegistry registry;
  registerTransformDialects(registry);
  ctx.appendDialectRegistry(registry);
  ctx.getOrLoadDialect<transform::TransformDialect>();

  llvm::raw_string_ostream os(error);
  OwningOpRef<ModuleOp> script;
  Operation *entry = nullptr;
  {
    ScopedDiagnosticHandler handler(&ctx, [&](Diagnostic &d) {
      os << d << "\n";
      return success();
    });
    script = parseSourceString<ModuleOp>(text, ParserConfig(&ctx), name);
    if (script)
      if (transform::TransformOpInterface ep = transform::detail::findTransformEntryPoint(*script, ModuleOp()))
        entry = ep.getOperation();
  }
  os.flush();
  if (!script || !entry) {
    error = "invalid Transform script '" + name.str() + "':\n" + error;
    return nullptr;
  }
  return std::make_unique<TransformPipeline>(std::move(script), entry, expensiveChecks);
}

//===----------------------------------------------------------------------===//
// Choosing a driver
//===----------------------------------------------------------------------===//

std::string pipelineFromLegacyPasses(StringRef passes) {
  // The stage names of the old MLNIX_PASSES and the passes they became.  The
  // old spelling was a set (order irrelevant); the stages always ran in this
  // order.
  static constexpr std::pair<StringLiteral, StringLiteral> stages[] = {
      {"devirt", "nix-prims"}, {"fold", "nix-fold"}, {"dce", "nix-dce"}};
  SmallVector<StringRef> tokens;
  passes.split(tokens, ',', /*MaxSplit=*/-1, /*KeepEmpty=*/false);
  bool all = llvm::is_contained(tokens, "all");
  SmallVector<StringRef> selected;
  for (auto &[stage, pass] : stages)
    if (all || llvm::is_contained(tokens, stage))
      selected.push_back(pass);
  return "builtin.module(" + llvm::join(selected, ",") + ")";
}

std::unique_ptr<Pipeline> makeFromEnvironment(MLIRContext &ctx, StringRef defaultPipeline,
                                              std::string &error) {
  if (const char *t = getenv("MLNIX_TRANSFORM")) {
    if (StringRef(t) == "embedded")
      return makeTransformPipeline(ctx, embeddedTransformScript(), "<embedded>", error);
    auto buf = llvm::MemoryBuffer::getFile(t);
    if (!buf) {
      error = "cannot read MLNIX_TRANSFORM script '" + std::string(t) + "': " + buf.getError().message();
      return nullptr;
    }
    return makeTransformPipeline(ctx, (*buf)->getBuffer(), t, error);
  }
  if (const char *p = getenv("MLNIX_PIPELINE"))
    return makePassPipeline(ctx, p, error);
  if (const char *p = getenv("MLNIX_PASSES")) // deprecated spelling
    return makePassPipeline(ctx, pipelineFromLegacyPasses(p), error);
  return makePassPipeline(ctx, defaultPipeline, error);
}

} // namespace nixpipe
