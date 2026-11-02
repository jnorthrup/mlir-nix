//===- Sumo.h - SUMO relations as KIF facts --------------------------------===//
//
// Generated from NixDialect/Sumo.td; `sumo-to-kif` is in lib/Dialect/SumoDialect.cpp.
//
//===----------------------------------------------------------------------===//
#ifndef NIXDIALECT_SUMO_H
#define NIXDIALECT_SUMO_H

#include "NixDialect/Kif.h"

#include "NixDialect/SumoDialect.h.inc"

#define GET_OP_CLASSES
#include "NixDialect/Sumo.h.inc"

namespace mlir::sumo {
void registerSumoPasses();
} // namespace mlir::sumo

#endif // NIXDIALECT_SUMO_H
