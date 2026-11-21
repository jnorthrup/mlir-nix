//===- CursorLowering.h - What trikeshed-lower-cursors offers the dialects below it ------------------------------------===//
//
// `trikeshed-lower-cursors` (lib/Composite/CursorLowering.cpp) lowers TrikeShed's series and cursors to buffers.  A dialect
// whose ops make or read series and cursors lowers them in the same conversion, through CursorLoweringInterface: confix's
// index and its Columns facet are series and cursors (PRELOAD-DIALECTS step 5), so their LLVM lowering sits below
// TrikeShed's, not beside it.
//
//===-----------------------------------------------------------------------------------------------------------------===//

#ifndef COMPOSITE_CURSORLOWERING_H
#define COMPOSITE_CURSORLOWERING_H

#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/DialectInterface.h"
#include "mlir/Support/TypeID.h"

namespace mlir {
class ConversionTarget;
class RewritePatternSet;
class TypeConverter;
} // namespace mlir

namespace composite {

/// The buffer a `!trikeshed.series<T>` lowers to: `memref<?xT, strided<[1], offset: ?>>`, so that a slice is a view of
/// the same buffer at an offset.  T is the element after conversion (a pair of two halves that fit a word is that word: Twin<i32> an i64).
mlir::MemRefType seriesBuffer(mlir::Type element);

/// A fresh buffer of n elements, as a series' buffer (allocated here, freed by --ownership-based-buffer-deallocation).
mlir::Value newSeriesBuffer(mlir::OpBuilder &b, mlir::Location loc, mlir::Type element, mlir::Value n);

/// A dialect whose ops make or read series and cursors adds the patterns that lower them to buffers, with the TypeConverter
/// of trikeshed-lower-cursors, and marks those ops illegal.
class CursorLoweringInterface : public mlir::DialectInterface::Base<CursorLoweringInterface> {
public:
  CursorLoweringInterface(mlir::Dialect *dialect) : Base(dialect) {}
  virtual void populateCursorLowering(const mlir::TypeConverter &types, mlir::RewritePatternSet &patterns,
                                      mlir::ConversionTarget &target) const = 0;
};

} // namespace composite

MLIR_DECLARE_EXPLICIT_TYPE_ID(composite::CursorLoweringInterface)

#endif // COMPOSITE_CURSORLOWERING_H
