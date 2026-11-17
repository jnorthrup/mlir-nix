//===- LifeDialect.cpp - The life dialect and its local laws ----------------===//
//
// Registration of the types and ops of NixDialect/Life.td, and the op verifiers: the laws of docs/LIFE.md that one op
// and its block decide.  The laws over a whole function are life-verify's (docs/LIFE.md), not built.
//
//===----------------------------------------------------------------------===//

#include "NixDialect/Life.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/DialectImplementation.h"
#include "llvm/ADT/SmallSet.h"
#include "llvm/ADT/TypeSwitch.h"

#include "NixDialect/LifeDialect.cpp.inc"

#define GET_TYPEDEF_CLASSES
#include "NixDialect/LifeTypes.cpp.inc"

#define GET_OP_CLASSES
#include "NixDialect/Life.cpp.inc"

using namespace mlir;
using namespace mlir::life;

void LifeDialect::initialize() {
  addTypes<
#define GET_TYPEDEF_LIST
#include "NixDialect/LifeTypes.cpp.inc"
      >();
  addOperations<
#define GET_OP_LIST
#include "NixDialect/Life.cpp.inc"
      >();
}

namespace {

/// Owned by a supervisor: some region around the op is a key's, a supervisor's, a worker's or a loop's.  Detached work
/// does not exist (PRELOAD: "detached work and hard cancellation do not substitute for drain").
LogicalResult supervised(Operation *op) {
  for (Operation *p = op->getParentOp(); p; p = p->getParentOp())
    if (isa<KeyOp, SuperviseOp, LaunchOp, ForEachOp>(p)) return success();
  return op->emitOpError("is owned by no supervisor: put it in a life.key, life.supervise, life.launch or life.for_each");
}

/// The op of `block` that is or holds `user`; null when `user` is not in the block.
Operation *inBlock(Block *block, Operation *user) { return block->findAncestorOpInBlock(*user); }

} // namespace

LogicalResult KeyOp::verify() {
  FunctionType fn = getFunctionType();
  auto element = ElementType::get(getContext(), FlatSymbolRefAttr::get(getSymNameAttr()));
  if (fn.getNumResults() == 0 || fn.getResult(0) != element)
    return emitOpError("opens ") << element << " first: the factory's first result is its element";
  Block &body = getBody().front();
  if (body.getArgumentTypes() != fn.getInputs()) return emitOpError("takes the factory's inputs as its body's arguments");
  auto opened = dyn_cast<OpenedOp>(body.getTerminator());
  if (!opened) return emitOpError("ends its body with life.opened");
  if (TypeRange(opened.getChannels().getTypes()) != fn.getResults().drop_front())
    return emitOpError("hands out, in life.opened, the channels its factory's results after the element name");
  return success();
}

LogicalResult OpenOp::verify() {
  if (getElement().getType().getKey() != getKeyAttr()) return emitOpError("makes an element of the key it opens");
  return supervised(*this);
}

LogicalResult OpenOp::verifySymbolUses(SymbolTableCollection &symbols) {
  auto key = symbols.lookupNearestSymbolFrom<KeyOp>(*this, getKeyAttr());
  if (!key) return emitOpError("opens ") << getKeyAttr() << ", which is no life.key";
  FunctionType fn = key.getFunctionType();
  if (TypeRange(getArgs().getTypes()) != fn.getInputs() || getResultTypes() != fn.getResults())
    return emitOpError("is typed as its key's factory: ") << fn;
  return success();
}

LogicalResult DrainOp::verify() {
  Block *block = (*this)->getBlock();
  for (Operation *user : getElement().getUsers())
    if (Operation *at = inBlock(block, user); at && (*this)->isBeforeInBlock(at))
      return emitOpError("drains an element that is used after it");
  return success();
}

LogicalResult FailOp::verify() { return supervised(*this); }
LogicalResult LaunchOp::verify() { return supervised(*this); }
LogicalResult ChannelOp::verify() { return supervised(*this); }
LogicalResult AcquireOp::verify() { return supervised(*this); }

LogicalResult SubmitOp::verify() {
  if (failed(supervised(*this))) return failure();
  llvm::SmallSet<int64_t, 4> seen;
  for (int64_t i : getLent()) {
    if (i < 0 || i >= int64_t(getArgs().size())) return emitOpError("lends operand ") << i << ", which it does not have";
    if (!seen.insert(i).second) return emitOpError("lends operand ") << i << " twice";
  }
  // A lent operand is the kernel's until the job is joined: in this block, no other use between the submission and the
  // join, or after the submission at all when the block does not join it.
  Block *block = (*this)->getBlock();
  Operation *join = nullptr;
  for (Operation *user : getJob().getUsers())
    if (Operation *at = inBlock(block, user); at && isa<JoinOp>(at) && (*this)->isBeforeInBlock(at))
      if (!join || at->isBeforeInBlock(join)) join = at;
  for (int64_t i : getLent()) {
    Value lent = getArgs()[i];
    for (Operation *user : lent.getUsers()) {
      Operation *at = inBlock(block, user);
      if (!at || at == getOperation() || !(*this)->isBeforeInBlock(at)) continue;
      if (!join || at->isBeforeInBlock(join))
        return emitOpError("lends operand ") << i << " to the kernel, and it is used before the job is joined";
    }
  }
  return success();
}

LogicalResult JoinOp::verify() {
  Type result = getJob().getType().getResult();
  bool none = isa<NoneType>(result);
  if (none != !getResult()) return emitOpError("gives the job's result: ") << (none ? "none" : "one");
  if (getResult() && getResult().getType() != result) return emitOpError("gives the job's result, of type ") << result;
  return success();
}

LogicalResult SendOp::verify() {
  if (getValue().getType() != getChan().getType().getElement())
    return emitOpError("offers a value of the channel's element type");
  if (getAdmitted().use_empty()) return emitOpError("drops the answer of an admission: a discarded claim is not processed work");
  return success();
}

LogicalResult ForEachOp::verify() {
  Block &body = getBody().front();
  if (body.getNumArguments() != 1 || body.getArgument(0).getType() != getChan().getType().getElement())
    return emitOpError("takes one value of the channel's element type in its body");
  return supervised(*this);
}

LogicalResult BeforeOp::verify() {
  auto first = getFirst().getDefiningOp<AcquireOp>(), then = getThen().getDefiningOp<AcquireOp>();
  if (!first || !then) return emitOpError("orders two resources acquired with life.acquire");
  if (first == then) return emitOpError("orders a resource before itself");
  if (first->getBlock() != (*this)->getBlock() || then->getBlock() != (*this)->getBlock())
    return emitOpError("orders resources acquired in its own block");
  return success();
}
