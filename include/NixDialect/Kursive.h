//===- Kursive.h - TrikeShed's kursive combinators as a dialect -----------===//
//
// Generated from NixDialect/Kursive.td; re2mlir and kursive-to-program are in lib/Dialect/KursiveDialect.cpp.
//
//===----------------------------------------------------------------------===//
#ifndef NIXDIALECT_KURSIVE_H
#define NIXDIALECT_KURSIVE_H

#include "mlir/Bytecode/BytecodeOpInterface.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/Dialect.h"
#include "mlir/IR/OpDefinition.h"
#include "mlir/IR/OpImplementation.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"

#include "NixDialect/KursiveDialect.h.inc"

#define GET_TYPEDEF_CLASSES
#include "NixDialect/KursiveTypes.h.inc"

#define GET_OP_CLASSES
#include "NixDialect/Kursive.h.inc"

namespace mlir::kursive {
/// `re2mlir`: each kursive.pattern becomes a kursive.regex of combinators, or a kursive.rejected.
/// `kursive-to-program`: each kursive.regex becomes the constant globals of its Step program.
void registerKursivePasses();
} // namespace mlir::kursive

#endif // NIXDIALECT_KURSIVE_H
