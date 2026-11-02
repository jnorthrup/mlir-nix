//===- Kif.h - SUO-KIF as a dialect ---------------------------------------===//
//
// Generated from NixDialect/Kif.td; the passes are in lib/Dialect/KifDialect.cpp.
//
//===----------------------------------------------------------------------===//
#ifndef NIXDIALECT_KIF_H
#define NIXDIALECT_KIF_H

#include "mlir/Bytecode/BytecodeOpInterface.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/Dialect.h"
#include "mlir/IR/OpDefinition.h"
#include "mlir/IR/OpImplementation.h"
#include "mlir/IR/RegionKindInterface.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"

#include "NixDialect/KifDialect.h.inc"

#define GET_TYPEDEF_CLASSES
#include "NixDialect/KifTypes.h.inc"

#define GET_OP_CLASSES
#include "NixDialect/Kif.h.inc"

namespace mlir::kif {
/// `kif-to-nix`: a theory becomes a `nix.expr` of { facts = [..]; rules = [..]; } built from `nix.list` and `nix.str`.
void registerKifPasses();
} // namespace mlir::kif

#endif // NIXDIALECT_KIF_H
