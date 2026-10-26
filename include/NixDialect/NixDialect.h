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
#include "llvm/ADT/DenseMap.h"
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
// Effect resources for primops (see NixPrims.irdl.mlir, `nix.fx`).
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

} // namespace mlir::nix

namespace mlir::nix {
/// Marker trait of the `NixModes` ODS class (NixBase.td): the op class carries
/// `kStrictMask` / `kTailMask`, which the dialect collects into `operandModes`.
template <typename ConcreteType>
class NixModes : public OpTrait::TraitBase<ConcreteType, NixModes> {};
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

/// Define the continent dialects at run time from NixPrims.irdl.mlir (IRDL),
/// attach their effects and assembly, and fill the core dialect's primop
/// table.  Called by the dialect extension that `registerNixDialects` installs.
LogicalResult loadPrimDialects(MLIRContext *ctx, NixDialect &core);

/// Registers the passes `nix-prims` (devirtualize primop calls into continent ops),
/// `nix-fold` (canonicalize + constant-fold with the declared primops) and `nix-dce`
/// (drop unreferenced bindings, including dead recursive cycles), and the pipeline
/// `nix-simplify` = all three.  They run on any op: the evaluator hands them a
/// `nix.expr`, mlnix-opt a module.
void registerNixPasses();

/// `nix.apply (builtin|builtins.X) args` -> continent op (single walk).
void devirtualizePrims(Operation *root);
} // namespace mlir::nix

#endif
