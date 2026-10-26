#ifndef COMPOSITE_COMPOSITE_H
#define COMPOSITE_COMPOSITE_H

#include "Composite/Pack.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Dialect.h"
#include "mlir/IR/DialectImplementation.h"
#include "mlir/IR/OpDefinition.h"
#include "mlir/IR/OpImplementation.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"

#include "Composite/JoinDialect.h.inc"
#define GET_TYPEDEF_CLASSES
#include "Composite/JoinTypes.h.inc"
#define GET_OP_CLASSES
#include "Composite/JoinOps.h.inc"

namespace mlir {
class DialectRegistry;
namespace join {
/// join, plus the dialects its passes and tests build on (arith, func).
void registerCompositeDialects(DialectRegistry &registry);
/// join-densify.
void registerCompositePasses();
} // namespace join
} // namespace mlir

#endif
