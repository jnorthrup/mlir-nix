//===- Life.h - Lifetimes: elements, admission, owned effects, drain --------===//
//
// Generated from NixDialect/Life.td; the op verifiers (the local laws) are in lib/Dialect/LifeDialect.cpp, the design
// and the rest of the laws in docs/LIFE.md.  registerNixDialects (NixDialect.h) registers it with the family.
//
//===----------------------------------------------------------------------===//
#ifndef NIXDIALECT_LIFE_H
#define NIXDIALECT_LIFE_H

#include "mlir/Bytecode/BytecodeOpInterface.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Dialect.h"
#include "mlir/IR/OpDefinition.h"
#include "mlir/IR/OpImplementation.h"
#include "mlir/IR/SymbolTable.h"

#include "NixDialect/LifeDialect.h.inc"

#define GET_TYPEDEF_CLASSES
#include "NixDialect/LifeTypes.h.inc"

#define GET_OP_CLASSES
#include "NixDialect/Life.h.inc"

#endif // NIXDIALECT_LIFE_H
