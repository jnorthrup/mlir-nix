//===- NixPrims.h - The continent dialects (nixnum, nixstr, ...) ----------===//
#ifndef NIXDIALECT_NIXPRIMS_H
#define NIXDIALECT_NIXPRIMS_H

#include "NixDialect/NixDialect.h"

#include "NixDialect/NixnumDialect.h.inc"
#define GET_OP_CLASSES
#include "NixDialect/NixnumOps.h.inc"
#include "NixDialect/NixtyDialect.h.inc"
#define GET_OP_CLASSES
#include "NixDialect/NixtyOps.h.inc"
#include "NixDialect/NixstrDialect.h.inc"
#define GET_OP_CLASSES
#include "NixDialect/NixstrOps.h.inc"
#include "NixDialect/NixctxDialect.h.inc"
#define GET_OP_CLASSES
#include "NixDialect/NixctxOps.h.inc"
#include "NixDialect/NixlistDialect.h.inc"
#define GET_OP_CLASSES
#include "NixDialect/NixlistOps.h.inc"
#include "NixDialect/NixattrDialect.h.inc"
#define GET_OP_CLASSES
#include "NixDialect/NixattrOps.h.inc"
#include "NixDialect/NixpathDialect.h.inc"
#define GET_OP_CLASSES
#include "NixDialect/NixpathOps.h.inc"
#include "NixDialect/NixstoreDialect.h.inc"
#define GET_OP_CLASSES
#include "NixDialect/NixstoreOps.h.inc"
#include "NixDialect/NixhashDialect.h.inc"
#define GET_OP_CLASSES
#include "NixDialect/NixhashOps.h.inc"
#include "NixDialect/NixfmtDialect.h.inc"
#define GET_OP_CLASSES
#include "NixDialect/NixfmtOps.h.inc"
#include "NixDialect/NixctlDialect.h.inc"
#define GET_OP_CLASSES
#include "NixDialect/NixctlOps.h.inc"

#endif
