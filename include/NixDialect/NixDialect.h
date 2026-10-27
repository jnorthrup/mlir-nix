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
#include "mlir/Rewrite/FrozenRewritePatternSet.h"
#include "Nix/Name.h" // before the generated ops: their properties are Names
#include "llvm/ADT/DenseMap.h"
#include "llvm/Config/llvm-config.h"
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

// SideEffects::Resource::getName() became const in LLVM 23 (the distro packages are 22).
#if LLVM_VERSION_MAJOR >= 23
#define NIX_RESOURCE_NAME_CONST const
#else
#define NIX_RESOURCE_NAME_CONST
#endif

namespace mlir::nix {
// Effect resources for primops (see NixPrims.irdl.mlir, `nix.fx`).
struct NixTraceResource : public SideEffects::Resource::Base<NixTraceResource> {
  StringRef getName() NIX_RESOURCE_NAME_CONST final { return "NixTrace"; }
};
struct NixFSResource : public SideEffects::Resource::Base<NixFSResource> {
  StringRef getName() NIX_RESOURCE_NAME_CONST final { return "NixFS"; }
};
struct NixEnvResource : public SideEffects::Resource::Base<NixEnvResource> {
  StringRef getName() NIX_RESOURCE_NAME_CONST final { return "NixEnv"; }
};
struct NixStoreResource : public SideEffects::Resource::Base<NixStoreResource> {
  StringRef getName() NIX_RESOURCE_NAME_CONST final { return "NixStore"; }
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

#include "Nix/Pos.h"

#include <optional>
#include <string>

namespace mlir::nix {
/// Source positions.  An op that can fail carries its position in its `pos` property (a nixfe::PackedPos
/// word).  The evaluator passes positions around as a PosPtr (`const void *`), which is one of three things,
/// told apart by the top bits:
///   bit 63   a packed word: the position of an attribute definition (AttrsOp `positions`);
///   bit 62   an op, whose position is looked up only when a message prints it, so the happy path pays
///            what it paid for a Location pointer: nothing;
///   neither  a Location pointer: a devirtualized primop keeps the FileLineColLoc of its call, because an
///            IRDL op has no property to hold the word.
static_assert(sizeof(void *) == 8, "PosPtr tags live in the top bits of a 64-bit pointer");
inline constexpr uintptr_t kOpPosTag = uintptr_t(1) << 62;
inline const void *posOfOp(Operation *op) {
  return op ? reinterpret_cast<const void *>(reinterpret_cast<uintptr_t>(op) | kOpPosTag) : nullptr;
}
/// The position of the value `v`: what `v.getLoc()` was for the operands that report errors.  An op's result
/// has its op's position; a block argument was made at the position of the lambda it belongs to.
inline const void *posOfValue(Value v) {
  if (Operation *def = v.getDefiningOp()) return posOfOp(def);
  if (auto arg = dyn_cast<BlockArgument>(v)) return posOfOp(arg.getOwner()->getParentOp());
  return nullptr;
}
inline const void *posOfWord(uint64_t word) { return reinterpret_cast<const void *>(word); }

struct SrcPos {
  std::string file;
  unsigned line = 0, col = 0;
};
/// File, line and column of a PosPtr; nullopt when it holds none.
std::optional<SrcPos> decodePos(const void *pos);
/// The packed word of an op that has the `pos` property (0 for any other op), and its setter.
uint64_t getPos(Operation *op);
void setPos(Operation *op, uint64_t word);
/// The word of a FileLineColLoc (0 for any other Location), and the Location of a word.
uint64_t packLoc(Location loc);
Location locOfWord(MLIRContext *ctx, uint64_t word);
} // namespace mlir::nix

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

/// The same walk with the pattern set built by the caller.  Building it is most of the cost of a
/// small walk, and the demand schedule devirtualizes one lambda body per first call: a lambda is not
/// IsolatedFromAbove (it reads the values it captures), so no PassManager can run on it.
FrozenRewritePatternSet makeDevirtualizePatterns(MLIRContext *ctx);
void devirtualizePrims(Operation *root, const FrozenRewritePatternSet &patterns);
} // namespace mlir::nix

#endif
