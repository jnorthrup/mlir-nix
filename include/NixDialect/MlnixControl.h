//===- MlnixControl.h - The control surface of the mlnix utility -----------===//
//
// Generated from NixDialect/MlnixControl.td: `mlnix.session` and the settings and requests it holds.  The laws are in the
// descriptions of the ops; registerNixDialects (NixDialect.h) registers the dialect with the rest of the family.
//
//===----------------------------------------------------------------------===//
#ifndef NIXDIALECT_MLNIXCONTROL_H
#define NIXDIALECT_MLNIXCONTROL_H

#include "mlir/Bytecode/BytecodeOpInterface.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/Dialect.h"
#include "mlir/IR/OpDefinition.h"
#include "mlir/IR/OpImplementation.h"
#include "mlir/IR/SymbolTable.h"

#include "NixDialect/MlnixControlEnums.h.inc"
#include "NixDialect/MlnixControlDialect.h.inc"

#define GET_ATTRDEF_CLASSES
#include "NixDialect/MlnixControlAttrDefs.h.inc"

#define GET_OP_CLASSES
#include "NixDialect/MlnixControl.h.inc"

#endif // NIXDIALECT_MLNIXCONTROL_H
