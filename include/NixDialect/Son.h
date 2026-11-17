//===- Son.h - The sea of nodes: deferred lambda bodies --------------------===//
//
// Generated from NixDialect/Son.td; nix-defer and son-mint are in lib/Dialect/SonDialect.cpp.
//
//===----------------------------------------------------------------------===//
#ifndef NIXDIALECT_SON_H
#define NIXDIALECT_SON_H

#include "NixDialect/NixDialect.h"
#include "mlir/IR/SymbolTable.h"
#include "llvm/ADT/DenseSet.h"

#include "NixDialect/SonDialect.h.inc"

#define GET_OP_CLASSES
#include "NixDialect/Son.h.inc"

namespace mlir::son {
void registerSonPasses();

/// The values of a frame forced on every path on which its call returns: the schedule's must-force set, the half of the
/// frame's lifecycle son.release is made from (SonDialect.cpp, MustForce).  `never`: no path of the body returns (each one
/// throws), so each value counts as forced.  The block is a son.body's, a nix.expr's or a nix.lambda's body.
struct ForcedOnReturn {
  llvm::DenseSet<Value> forced;
  bool never = false;
  bool contains(Value v) const { return never || forced.contains(v); }
};
/// `may`: the values forced on some path that returns instead (an if's arms joined, not met).
ForcedOnReturn forcedOnReturn(Block &block, nix::NixDialect *nixd, bool may = false);
} // namespace mlir::son

#endif // NIXDIALECT_SON_H
