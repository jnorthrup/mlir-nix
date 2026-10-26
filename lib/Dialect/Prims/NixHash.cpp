//===- NixHash.cpp - the Nixhash dialect ---------------------------------------===//
//
// Ops, verifiers, folders, effects, parser and printer are generated from
// NixPrims.td; only initialization and the constant materializer live here.
// (One translation unit per continent: ODS emits file-static helpers.)
//
//===----------------------------------------------------------------------===//

#include "Common.h"

using namespace mlir;
using namespace mlir::nix;

#include "NixDialect/NixhashDialect.cpp.inc"
#define GET_OP_CLASSES
#include "NixDialect/NixhashOps.cpp.inc"

void hash::NixHashDialect::initialize() {
  addOperations<
#define GET_OP_LIST
#include "NixDialect/NixhashOps.cpp.inc"
      >();
  registerPrimOps<
#define GET_OP_LIST
#include "NixDialect/NixhashOps.cpp.inc"
      >(getContext());
}

Operation *hash::NixHashDialect::materializeConstant(OpBuilder &b, Attribute value, Type type, Location loc) {
  return getContext()->getLoadedDialect<NixDialect>()->materializeConstant(b, value, type, loc);
}
