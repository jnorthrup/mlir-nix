//===- NixCtl.cpp - the Nixctl dialect ---------------------------------------===//
//
// Ops, verifiers, folders, effects, parser and printer are generated from
// NixPrims.td; only initialization and the constant materializer live here.
// (One translation unit per continent: ODS emits file-static helpers.)
//
//===----------------------------------------------------------------------===//

#include "Common.h"

using namespace mlir;
using namespace mlir::nix;

#include "NixDialect/NixctlDialect.cpp.inc"
#define GET_OP_CLASSES
#include "NixDialect/NixctlOps.cpp.inc"

void ctl::NixCtlDialect::initialize() {
  addOperations<
#define GET_OP_LIST
#include "NixDialect/NixctlOps.cpp.inc"
      >();
  registerPrimOps<
#define GET_OP_LIST
#include "NixDialect/NixctlOps.cpp.inc"
      >(getContext());
}

Operation *ctl::NixCtlDialect::materializeConstant(OpBuilder &b, Attribute value, Type type, Location loc) {
  return getContext()->getLoadedDialect<NixDialect>()->materializeConstant(b, value, type, loc);
}
