//===- Common.h - Shared by the per-continent translation units ------------===//
#ifndef NIXDIALECT_PRIMS_COMMON_H
#define NIXDIALECT_PRIMS_COMMON_H

#include "NixDialect/NixPrims.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/DialectImplementation.h"

namespace mlir::nix {
/// Record every op of a continent in the core dialect's primop table.
template <class... Ops>
void registerPrimOps(MLIRContext *ctx) {
  auto *core = ctx->getOrLoadDialect<NixDialect>();
  (core->registerPrim(Ops::primKey, Ops::primArity, OperationName(Ops::getOperationName(), ctx)), ...);
}
} // namespace mlir::nix

#endif
