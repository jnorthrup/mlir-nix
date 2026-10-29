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

mlir::LogicalResult ClusterOrderOp::verify() {
  for (auto type : {getKeys().getType(), getOrder().getType()}) {
    auto memref = llvm::cast<mlir::MemRefType>(type);
    if (memref.getRank() != 1 || !memref.getElementType().isSignlessInteger(64) ||
        memref.getMemorySpaceAsInt() != 0)
      return emitOpError("requires rank-one signless i64 memrefs in host memory");
    mlir::SmallVector<int64_t> strides;
    int64_t offset;
    if (mlir::failed(memref.getStridesAndOffset(strides, offset)))
      return emitOpError("requires strided memrefs");
  }
  return mlir::success();
}

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
