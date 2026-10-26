//===- NixNum.cpp - the Nixnum dialect ---------------------------------------===//
//
// Ops, verifiers, folders, effects, parser and printer are generated from
// NixPrims.td; only initialization and the constant materializer live here.
// (One translation unit per continent: ODS emits file-static helpers.)
//
//===----------------------------------------------------------------------===//

#include "Common.h"

using namespace mlir;
using namespace mlir::nix;

#include "NixDialect/NixnumDialect.cpp.inc"
#define GET_OP_CLASSES
#include "NixDialect/NixnumOps.cpp.inc"

void num::NixNumDialect::initialize() {
  addOperations<
#define GET_OP_LIST
#include "NixDialect/NixnumOps.cpp.inc"
      >();
  registerPrimOps<
#define GET_OP_LIST
#include "NixDialect/NixnumOps.cpp.inc"
      >(getContext());
}

Operation *num::NixNumDialect::materializeConstant(OpBuilder &b, Attribute value, Type type, Location loc) {
  return getContext()->getLoadedDialect<NixDialect>()->materializeConstant(b, value, type, loc);
}
