//===- Son.h - The sea of nodes: deferred lambda bodies --------------------===//
//
// Generated from NixDialect/Son.td; nix-defer and son-mint are in lib/Dialect/SonDialect.cpp.
//
//===----------------------------------------------------------------------===//
#ifndef NIXDIALECT_SON_H
#define NIXDIALECT_SON_H

#include "NixDialect/NixDialect.h"
#include "mlir/IR/SymbolTable.h"

#include "NixDialect/SonDialect.h.inc"

#define GET_OP_CLASSES
#include "NixDialect/Son.h.inc"

namespace mlir::son {
void registerSonPasses();
} // namespace mlir::son

#endif // NIXDIALECT_SON_H
