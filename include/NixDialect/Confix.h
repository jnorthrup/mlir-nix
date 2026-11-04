//===- Confix.h - TrikeShed's Confix scanner as a dialect -----------------------------===//
//
// Generated from NixDialect/Confix.td.  The scanner is lib/Confix/confix.ll (LLVM IR), which confix-to-llvm calls; nothing of the scan is
// in C++.  This header, lib/Dialect/ConfixDialect.cpp and the pass are the dialect's registration and its lowering.
//
//===----------------------------------------------------------------------===//
#ifndef NIXDIALECT_CONFIX_H
#define NIXDIALECT_CONFIX_H

#include "mlir/Bytecode/BytecodeOpInterface.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/Dialect.h"
#include "mlir/IR/OpDefinition.h"
#include "mlir/IR/OpImplementation.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"

#include "NixDialect/ConfixDialect.h.inc"

#include "NixDialect/ConfixEnums.h.inc"

#define GET_OP_CLASSES
#include "NixDialect/Confix.h.inc"

namespace mlir::confix {
/// `confix-to-llvm`: the ops become calls of the IR scanner (confix_scan_json, confix_scan_cbor, confix_scan_yaml) and loads of the Flat record.
void registerConfixPasses();
} // namespace mlir::confix

#endif // NIXDIALECT_CONFIX_H
