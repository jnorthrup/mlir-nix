//===- Kif.h - SUO-KIF as a dialect ---------------------------------------===//
//
// Generated from NixDialect/Kif.td; the passes are in lib/Dialect/KifDialect.cpp.
//
//===----------------------------------------------------------------------===//
#ifndef NIXDIALECT_KIF_H
#define NIXDIALECT_KIF_H

#include "mlir/Bytecode/BytecodeOpInterface.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/Dialect.h"
#include "mlir/IR/OpDefinition.h"
#include "mlir/IR/OpImplementation.h"
#include "mlir/IR/RegionKindInterface.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"

#include "NixDialect/KifDialect.h.inc"

#define GET_TYPEDEF_CLASSES
#include "NixDialect/KifTypes.h.inc"

#define GET_OP_CLASSES
#include "NixDialect/Kif.h.inc"

namespace mlir::kif {
/// `kif-to-nix`: a theory becomes a `nix.expr` of { facts = [..]; rules = [..]; } built from `nix.list` and `nix.str`.
/// `kif-chase`: every theory with rules gets a `kif.derived` for each fact its rules give (lib/Dialect/KifChase.cpp).
void registerKifPasses();

/// KIF text into `theory`'s block (lib/Dialect/KifImport.cpp), read as sumo-nix/kif.nix reads it: a parenthesis, a quoted string
/// (it keeps its quotes), a `;` comment (dropped) or a run of other characters is a token.  Each top-level form is a `kif.rule`
/// when it is `(=> antecedent consequent)`, else a `kif.fact`, with `file` set to `file`.  Equal terms are one node: across the
/// texts read into one theory too, so `intern` keeps its tables between calls.  An unbalanced text is an error at its offset.
struct KifInterner;
KifInterner *newInterner(TheoryOp theory);
void freeInterner(KifInterner *);
LogicalResult importKif(KifInterner &intern, StringRef name, StringRef text, int32_t file);
/// How many atoms, variables and lists the interner made.
void internCounts(const KifInterner &, uint64_t &atoms, uint64_t &vars, uint64_t &lists);

/// The facts of a chased theory as lines `fact\trule\tfrom1\tfrom2...` (asserted: rule `-`), sorted by fact, a term printed as
/// datalog.nix's `show` prints it: what scripts/kif-oracle.py compares across the engines.
void dumpClosure(TheoryOp theory, raw_ostream &os);
} // namespace mlir::kif

#endif // NIXDIALECT_KIF_H
