//===- TrikeShed.h - The TrikeShed kernel as a dialect ---------------------===//
//
// Generated from Composite/TrikeShed.td: !trikeshed.join, metaseries, series, series2, split, cursor, either, twinpacked
// and twin8, and the ops of borg.trikeshed.lib (j, alpha, joins, select, combine, slice, project, where, bisect, fold,
// ...).  The runtime that interprets them is Composite/Series.h; registering the dialect is what makes the geometry of
// this compiler's data printable, parseable and verifiable IR rather than implied C++.
//
//===----------------------------------------------------------------------===//
#ifndef COMPOSITE_TRIKESHED_H
#define COMPOSITE_TRIKESHED_H

#include "mlir/IR/Dialect.h"
#include "mlir/IR/OpDefinition.h"
#include "mlir/IR/OpImplementation.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"

#include "Composite/TrikeShedDialect.h.inc"

#define GET_TYPEDEF_CLASSES
#include "Composite/TrikeShedTypes.h.inc"

#define GET_OP_CLASSES
#include "Composite/TrikeShedOps.h.inc"

#define GET_ATTRDEF_CLASSES
#include "Composite/TrikeShedAttrDefs.h.inc"

namespace composite {
/// The dialect, plus the dialects its regions may hold (the nix values a series carries).
void registerTrikeShedDialect(mlir::DialectRegistry &registry);
void registerTrikeShedPasses();
} // namespace composite

#endif // COMPOSITE_TRIKESHED_H
