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

/// A pattern's Program by the combinators: a kursive.pattern of `re`, --re2mlir (pool/set caps) and
/// --kursive-to-program (step cap) run in a context of their own, the globals read back.  steps gets 4 words a step
/// (op, x, y, z), sets 4 words a set; counts {steps, sets, groups, loops}.  Answers 0 None, 1 Invalid, 2 Space.
int compileProgram(llvm::StringRef re, unsigned poolCap, unsigned capSteps, unsigned capSets, uint32_t *steps,
                   uint64_t *sets, uint32_t counts[4]);
} // namespace mlir::kursive

#endif // NIXDIALECT_KURSIVE_H
