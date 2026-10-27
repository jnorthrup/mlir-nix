//===- TrikeShedDialect.cpp - The dialect generated from TrikeShed.td ------===//
//
// The generated classes of borg.trikeshed.lib as IR (see Composite/TrikeShed.td for the laws, and Composite/Series.h for
// the C++ that interprets them).  This file is only the dialect's plumbing: the generated definitions, and registration.
//
//===----------------------------------------------------------------------===//

#include "Composite/TrikeShed.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/DialectImplementation.h"
#include "llvm/ADT/TypeSwitch.h"

#include "Composite/TrikeShedDialect.cpp.inc"

#define GET_TYPEDEF_CLASSES
#include "Composite/TrikeShedTypes.cpp.inc"

#define GET_OP_CLASSES
#include "Composite/TrikeShedOps.cpp.inc"

#define GET_ATTRDEF_CLASSES
#include "Composite/TrikeShedAttrDefs.cpp.inc"

namespace composite {

void TrikeShedDialect::initialize() {
  addTypes<
#define GET_TYPEDEF_LIST
#include "Composite/TrikeShedTypes.cpp.inc"
      >();
  addAttributes<
#define GET_ATTRDEF_LIST
#include "Composite/TrikeShedAttrDefs.cpp.inc"
      >();
  addOperations<
#define GET_OP_LIST
#include "Composite/TrikeShedOps.cpp.inc"
      >();
}

void registerTrikeShedDialect(mlir::DialectRegistry &registry) {
  registry.insert<TrikeShedDialect>();
}

} // namespace composite
