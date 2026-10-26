#ifndef NIXDIALECT_NIXDIALECT_H
#define NIXDIALECT_NIXDIALECT_H

#include "mlir/Bytecode/BytecodeOpInterface.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Dialect.h"
#include "mlir/IR/DialectRegistry.h"
#include "mlir/IR/OpDefinition.h"
#include "mlir/IR/OpImplementation.h"
#include "mlir/IR/RegionKindInterface.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "mlir/Pass/Pass.h"
#include "llvm/ADT/StringMap.h"
#include <functional>
#include <memory>

// The evaluator library is a client of the dialects, never a dependency: the
// interfaces below only mention its types.
namespace nixev {
struct Value;
struct Frame;
class EvalState;
} // namespace nixev

namespace mlir::nix {
// Effect resources for primops (see NixBase.td).
struct NixTraceResource : public SideEffects::Resource::Base<NixTraceResource> {
  StringRef getName() const final { return "NixTrace"; }
};
struct NixFSResource : public SideEffects::Resource::Base<NixFSResource> {
  StringRef getName() const final { return "NixFS"; }
};
struct NixEnvResource : public SideEffects::Resource::Base<NixEnvResource> {
  StringRef getName() const final { return "NixEnv"; }
};
struct NixStoreResource : public SideEffects::Resource::Base<NixStoreResource> {
  StringRef getName() const final { return "NixStore"; }
};

// Helpers referenced by the generated primop classes.
LogicalResult verifyPrimArity(Operation *op, unsigned arity);
OpFoldResult foldPrim(Operation *op, StringRef key, ArrayRef<Attribute> args);
} // namespace mlir::nix

#include "NixDialect/NixInterfaces.h.inc"
#include "NixDialect/NixDialect.h.inc"

#define GET_TYPEDEF_CLASSES
#include "NixDialect/NixTypes.h.inc"

#define GET_OP_CLASSES
#include "NixDialect/NixOps.h.inc"

namespace mlir::nix {
/// Register / load the core dialect and all continent dialects.
void registerNixDialects(DialectRegistry &registry);
void loadNixDialects(MLIRContext &ctx);

/// Which stages of the nix pipeline to run (all are cheap walks except `fold`,
/// which drives the greedy rewriter).  This is the *direct-call* interface;
/// the evaluator no longer uses it: it runs a PassManager built from a textual
/// pipeline or a Transform-dialect script (Nix/Pipeline.h).  It stays as the
/// baseline for per-call overhead measurements.
struct SimplifyOptions {
  /// Rewrite saturated calls of known primops into continent-dialect ops.
  bool devirtualize = true;
  /// Constant-fold (generic: every foldable primop) with the greedy driver.
  bool fold = false;
  /// Remove unreferenced bindings, including dead recursive cycles.
  bool dce = false;
};

/// Registers the passes `nix-prims`, `nix-fold`, `nix-dce` and the pipeline
/// alias `nix-simplify` (= nix-prims,nix-fold,nix-dce).  Idempotent.
void registerNixPasses();
std::unique_ptr<Pass> createNixPrimsPass();
std::unique_ptr<Pass> createNixFoldPass();
std::unique_ptr<Pass> createNixDcePass();
/// The `nix-simplify` alias: prims, fold, dce.
void buildNixSimplifyPipeline(OpPassManager &pm);

/// Run the selected stages below `root` (an ExprOp or a ModuleOp) by direct
/// calls, without a pass manager.
void simplifyExpr(Operation *root, SimplifyOptions options = {});
/// `nix.apply (builtin|builtins.X) args` -> continent op (single walk).
void devirtualizePrims(Operation *root);
} // namespace mlir::nix

#endif
