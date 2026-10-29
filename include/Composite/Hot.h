//===- Hot.h - the hottest headers of the TrikeShed algebra, as one precompiled package ---===//
//
// The standard: this set is closed.  Core.h (types, casts, traits, Arr, TODO, placement), Pack.h (the packed pair) and Series.h (Join, Series,
// Size, Marks, α, fold) include no standard header and name nothing from std::, and are what every translation unit pays for, so they are
// built once as a precompiled header (target_precompile_headers in lib/CMakeLists.txt).  Anything else the algebra offers is a mix-in a file
// includes by name: Folds.h, Views.h, Mutable.h, Pool.h; Laws.h (the self-tests) is included by a check, never by production code.
//
// scripts/hot-check.sh compiles this header with no standard include path at all.  It fails when a hot header grows an #include or a std::,
// and when the set outgrows its line budget: purity is held by the gate, not by good intentions.
//
//===----------------------------------------------------------------------===//

#ifndef COMPOSITE_HOT_H
#define COMPOSITE_HOT_H

#include "Composite/Core.h"
#include "Composite/Pack.h"
#include "Composite/Series.h"

#endif
