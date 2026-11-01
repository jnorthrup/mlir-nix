//===- MlnixControlDialect.cpp - The dialect generated from MlnixControl.td ----===//

#include "NixDialect/MlnixControl.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/DialectImplementation.h"
#include "llvm/ADT/TypeSwitch.h"

#include "NixDialect/MlnixControlDialect.cpp.inc"
#include "NixDialect/MlnixControlEnums.cpp.inc"

#define GET_ATTRDEF_CLASSES
#include "NixDialect/MlnixControlAttrDefs.cpp.inc"

#define GET_OP_CLASSES
#include "NixDialect/MlnixControl.cpp.inc"

namespace mlir::mlnix {

void MlnixDialect::initialize() {
  addAttributes<
#define GET_ATTRDEF_LIST
#include "NixDialect/MlnixControlAttrDefs.cpp.inc"
      >();
  addOperations<
#define GET_OP_LIST
#include "NixDialect/MlnixControl.cpp.inc"
      >();
}

/// One setting of each kind at most: two `mlnix.schedule` would leave the order of the settings to decide.
LogicalResult SessionOp::verify() {
  unsigned schedules = 0, pipelines = 0, jits = 0, prelowers = 0, censuses = 0;
  for (Operation &op : getBody().front()) {
    schedules += isa<ScheduleOp>(op);
    pipelines += isa<PipelineOp>(op);
    jits += isa<JitOp>(op);
    prelowers += isa<PrelowerOp>(op);
    censuses += isa<CensusOp>(op);
  }
  if (schedules > 1 || pipelines > 1 || jits > 1 || prelowers > 1 || censuses > 1)
    return emitOpError("holds at most one each of mlnix.schedule, pipeline, jit, prelower and census");
  return success();
}

/// The threshold and the optimization level belong to a tier that compiles.
LogicalResult JitOp::verify() {
  if (getTier() == JitTier::Off && (getThreshold() || getOpt()))
    return emitOpError("takes no threshold or opt with tier off");
  return success();
}

} // namespace mlir::mlnix
