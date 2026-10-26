//===- NixTy.cpp - the Nixty dialect ---------------------------------------===//
//
// Ops, verifiers, folders, effects, parser and printer are generated from
// NixPrims.td; only initialization and the constant materializer live here.
// (One translation unit per continent: ODS emits file-static helpers.)
//
//===----------------------------------------------------------------------===//

#include "Common.h"

using namespace mlir;
using namespace mlir::nix;

#include "NixDialect/NixtyDialect.cpp.inc"
#define GET_OP_CLASSES
#include "NixDialect/NixtyOps.cpp.inc"

void ty::NixTyDialect::initialize() {
  addOperations<
#define GET_OP_LIST
#include "NixDialect/NixtyOps.cpp.inc"
      >();
  registerPrimOps<
#define GET_OP_LIST
#include "NixDialect/NixtyOps.cpp.inc"
      >(getContext());
}

Operation *ty::NixTyDialect::materializeConstant(OpBuilder &b, Attribute value, Type type, Location loc) {
  return getContext()->getLoadedDialect<NixDialect>()->materializeConstant(b, value, type, loc);
}
