//===- TrikeShedDialect.cpp - The dialect generated from TrikeShed.td ------===//
//
// The generated classes of borg.trikeshed.lib as IR (see Composite/TrikeShed.td for the laws, and Composite/Series.h for
// the C++ that interprets them).  This file is only the dialect's plumbing: the generated definitions, and registration.
//
//===----------------------------------------------------------------------===//

#include "Composite/TrikeShed.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/DialectImplementation.h"
#include "llvm/ADT/TypeSwitch.h"

#include "Composite/TrikeShedDialect.cpp.inc"

#define GET_TYPEDEF_CLASSES
#include "Composite/TrikeShedTypes.cpp.inc"

#define GET_OP_CLASSES
#include "Composite/TrikeShedOps.cpp.inc"

#define GET_ATTRDEF_CLASSES
#include "Composite/TrikeShedAttrDefs.cpp.inc"

namespace composite {

// The laws of j (TrikeShed.td): first(a j b) = a; second(a j b) = b; first(p) j second(p) = p.
mlir::OpFoldResult FirstOp::fold(FoldAdaptor) {
  auto j = getJoin().getDefiningOp<JOp>();
  return j && j.getA().getType() == getA().getType() ? mlir::OpFoldResult(j.getA()) : nullptr;
}

mlir::OpFoldResult SecondOp::fold(FoldAdaptor) {
  auto j = getJoin().getDefiningOp<JOp>();
  return j && j.getB().getType() == getB().getType() ? mlir::OpFoldResult(j.getB()) : nullptr;
}

mlir::OpFoldResult JOp::fold(FoldAdaptor) {
  auto a = getA().getDefiningOp<FirstOp>();
  auto b = getB().getDefiningOp<SecondOp>();
  return a && b && a.getJoin() == b.getJoin() && a.getJoin().getType() == getType() ? mlir::OpFoldResult(a.getJoin()) : nullptr;
}

mlir::LogicalResult ClusterOrderOp::verify() {
  for (auto type : {getKeys().getType(), getOrder().getType()}) {
    auto memref = llvm::cast<mlir::MemRefType>(type);
    if (memref.getRank() != 1 || !memref.getElementType().isSignlessInteger(64) ||
        memref.getMemorySpaceAsInt() != 0)
      return emitOpError("requires rank-one signless i64 memrefs in host memory");
    mlir::SmallVector<int64_t> strides;
    int64_t offset;
    if (mlir::failed(memref.getStridesAndOffset(strides, offset)))
      return emitOpError("requires strided memrefs");
  }
  return mlir::success();
}

mlir::LogicalResult PartsOp::verify() {
  auto s = llvm::dyn_cast<SeriesType>(getSeries().getType());
  if (!s || s.getElement() != getDelimiter().getType() || !s.getElement().isSignlessInteger())
    return emitOpError("splits a series of integers at a delimiter of the same type");
  auto r = llvm::dyn_cast<SeriesType>(getParts().getType());
  auto p = r ? llvm::dyn_cast<TwinPackedType>(r.getElement()) : TwinPackedType();
  if (!p || !p.getElement().isSignlessInteger(32))
    return emitOpError("gives the parts as a !trikeshed.series<!trikeshed.twinpacked<i32>> (start, length)");
  return mlir::success();
}

mlir::LogicalResult CombineOp::verify() {
  auto r = llvm::cast<SeriesType>(getResult().getType());
  for (mlir::Type t : getParts().getTypes())
    if (llvm::cast<SeriesType>(t).getElement() != r.getElement())
      return emitOpError("combines series of the result's element type");
  return mlir::success();
}

mlir::LogicalResult CombineAllOp::verify() {
  mlir::Block &body = getPart().front();
  if (body.getNumArguments() != 1 || !body.getArgument(0).getType().isIndex())
    return emitOpError("has a region of one index argument, k");
  auto yield = llvm::dyn_cast<YieldOp>(body.getTerminator());
  if (!yield || yield.getValues().size() != 1 || yield.getValues()[0].getType() != getResult().getType())
    return emitOpError("has a region that yields part k, a series of the result's type");
  auto c = llvm::cast<SeriesType>(getCoordinates().getType());
  auto p = llvm::dyn_cast<TwinPackedType>(c.getElement());
  if (!p || !p.getElement().isSignlessInteger(32))
    return emitOpError("gives the coordinates as a !trikeshed.series<!trikeshed.twinpacked<i32>> (start, length)");
  return mlir::success();
}

mlir::LogicalResult AdjacencyOp::verify() {
  auto nodes = [](mlir::Type t) {
    auto s = llvm::dyn_cast<SeriesType>(t);
    return s && s.getElement().isSignlessInteger(32);
  };
  auto s = llvm::dyn_cast<SeriesType>(getIndex().getType());
  auto p = s ? llvm::dyn_cast<TwinPackedType>(s.getElement()) : TwinPackedType();
  if (!nodes(getFrom().getType()) || !nodes(getTo().getType()) || !nodes(getEnds().getType()))
    return emitOpError("takes the edges' ends and gives the far ends as !trikeshed.series<i32>");
  if (!p || !p.getElement().isSignlessInteger(32))
    return emitOpError("gives each node's (first, count) as a !trikeshed.series<!trikeshed.twinpacked<i32>>");
  return mlir::success();
}

mlir::LogicalResult ClosureOp::verify() {
  auto pairs = [](mlir::Type t) {
    auto s = llvm::dyn_cast<SeriesType>(t);
    auto p = s ? llvm::dyn_cast<TwinPackedType>(s.getElement()) : TwinPackedType();
    return p && p.getElement().isSignlessInteger(32);
  };
  auto nodes = [](mlir::Type t) {
    auto s = llvm::dyn_cast<SeriesType>(t);
    return s && s.getElement().isSignlessInteger(32);
  };
  if (!pairs(getParents().getType()) || !pairs(getAncestors().getType()))
    return emitOpError("takes and gives each node's (first, count) as a !trikeshed.series<!trikeshed.twinpacked<i32>>");
  if (!nodes(getAbove().getType()) || !nodes(getMembers().getType()))
    return emitOpError("takes and gives the nodes they count as a !trikeshed.series<i32>");
  return mlir::success();
}

void TrikeShedDialect::initialize() {
  addTypes<
#define GET_TYPEDEF_LIST
#include "Composite/TrikeShedTypes.cpp.inc"
      >();
  addAttributes<
#define GET_ATTRDEF_LIST
#include "Composite/TrikeShedAttrDefs.cpp.inc"
      >();
  addOperations<
#define GET_OP_LIST
#include "Composite/TrikeShedOps.cpp.inc"
      >();
}

void registerTrikeShedDialect(mlir::DialectRegistry &registry) {
  registry.insert<TrikeShedDialect>();
}

} // namespace composite
