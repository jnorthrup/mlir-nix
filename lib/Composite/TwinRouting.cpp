//===- TwinRouting.cpp - A pair's representation chosen by how it is read ----------------------------------------------===//
//
// `trikeshed-route-twins`: the half of `!trikeshed.twin`'s rule that the type alone cannot decide.  The width rule (two
// halves that fit a word are that word, wider ones lie apart) is trikeshed-lower-cursors' type conversion; it holds
// wherever the type goes.  This pass runs before it and does two things with the laws of j:
//
//   first(a j b) = a, second(a j b) = b, first(p) j second(p) = p
//       applied until nothing folds, and a pair nothing reads erased: a pair made and taken apart again is never made.
//
//   at(n j { k -> a j b }, i).first = at(n j { k -> a }, i)          (and .second, and the same through α)
//       A series of pairs is packed for nothing when every read of it takes one half: a scan of that half walks twice
//       the bytes it reads.  Such a series is made as a column a half instead -- the region once for each half that is
//       read, so a half nothing reads is not computed at all -- whatever the width of the halves.  A read that takes
//       both halves (an at whose element feeds a first and a second, a fold, a sort) keeps the series whole: packing is
//       free there, and the width rule lays it out.
//
// The choice is made only where this pass sees every read: a series made by `series` or `alpha` in the function, read
// by size, at and alpha, whose region has no memory effect (it is run once a column).  A series that crosses a call or
// a return, or a cursor's column (confix's spans, whose layout the scanner's C ABI fixes), keeps the width rule's layout.
//
//===-----------------------------------------------------------------------------------------------------------------===//

#include "Composite/TrikeShed.h"
#include "Composite/Series.h"
#include "Composite/Vocab.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "mlir/Pass/Pass.h"

using namespace mlir;

namespace composite {
namespace {

/// The two sides of a pair type (a Join, a Twin, a TwinPacked).
Maybe<Join<Type, Type>> sides(Type t) {
  if (auto j = dyn_cast<JoinType>(t)) return Join{j.getA(), j.getB()};
  if (auto w = dyn_cast<TwinType>(t)) return Join{w.getElement(), w.getElement()};
  if (auto p = dyn_cast<TwinPackedType>(t)) return Join{p.getElement(), p.getElement()};
  return {};
}

/// The laws of j, applied in f until nothing folds; the pairs left unread are erased.
bool foldPairs(func::FuncOp f) {
  bool any = false;
  for (bool changed = true; changed;) {
    changed = false;
    SmallVector<Operation *> ops;
    f.walk([&](Operation *op) {
      if (isa<JOp, FirstOp, SecondOp>(op)) ops.push_back(op);
    });
    for (Operation *op : ops) {
      SmallVector<Attribute> constants(op->getNumOperands());
      SmallVector<OpFoldResult> to;
      if (failed(op->fold(constants, to)) || to.size() != 1 || !isa<Value>(to[0])) continue;
      op->replaceAllUsesWith(ValueRange{cast<Value>(to[0])});
      op->erase();
      changed = any = true;
    }
    for (bool erased = true; erased;) {
      erased = false;
      ops.clear();
      f.walk([&](Operation *op) {
        if (isa<JOp, FirstOp, SecondOp>(op) && op->use_empty()) ops.push_back(op);
      });
      for (Operation *op : ops) op->erase(), erased = any = true;
    }
  }
  return any;
}

/// The side every use of a pair takes (false the first, true the second), when they all take the same one.
Maybe<bool> halfRead(Value pair, Join<Type, Type> side) {
  Maybe<bool> read;
  for (Operation *user : pair.getUsers()) {
    bool second;
    if (auto f = dyn_cast<FirstOp>(user); f && f.getA().getType() == side.a) second = false;
    else if (auto s = dyn_cast<SecondOp>(user); s && s.getB().getType() == side.b) second = true;
    else return {};
    if (read && *read != second) return {};
    read = second;
  }
  return read;
}

/// A series of pairs made by `made` (a series or an alpha), every read of which takes one half: made as a column a half.
bool splitSeries(Operation *made) {
  Value xs = made->getResult(0);
  auto side = sides(cast<SeriesType>(xs.getType()).getElement());
  if (!side) return false;
  Region &region = made->getRegion(0);
  auto yield = dyn_cast<YieldOp>(region.front().getTerminator());
  if (!yield || yield.getValues().size() != 1) return false;
  bool pure = true;
  region.walk([&](Operation *op) { pure &= isMemoryEffectFree(op); });
  if (!pure) return false;

  SmallVector<Join<Operation *, bool>> reads;
  SmallVector<Operation *> sizes;
  for (OpOperand &use : xs.getUses()) {
    Operation *by = use.getOwner();
    Value element;
    if (isa<SizeOp>(by)) {
      sizes.push_back(by);
      continue;
    }
    if (auto at = dyn_cast<AtOp>(by); at && use.getOperandNumber() == 0) element = at.getElement();
    else if (auto alpha = dyn_cast<AlphaOp>(by)) element = alpha.getXform().front().getArgument(0);
    else return false;
    auto read = halfRead(element, *side);
    if (!read) return false;
    reads.push_back({by, *read});
  }
  if (reads.empty()) return false;

  Location loc = made->getLoc();
  Value column[2];
  auto half = [&](bool second) { return second ? side->b : side->a; };
  auto columnOf = [&](bool second) {
    if (column[second]) return column[second];
    Operation *c = made->clone();
    OpBuilder b(made);
    b.insert(c);
    c->getResult(0).setType(SeriesType::get(xs.getContext(), half(second)));
    Operation *y = c->getRegion(0).front().getTerminator();
    b.setInsertionPoint(y);
    Value pair = y->getOperand(0);
    y->setOperand(0, second ? SecondOp::create(b, loc, half(true), pair).getResult()
                            : FirstOp::create(b, loc, half(false), pair).getResult());
    return column[second] = c->getResult(0);
  };
  auto replaceHalves = [](Value pair, Value with) {
    for (OpOperand &use : llvm::make_early_inc_range(pair.getUses())) {
      Operation *taken = use.getOwner();
      taken->replaceAllUsesWith(ValueRange{with});
      taken->erase();
    }
  };
  for (auto [by, second] : reads) {
    Value col = columnOf(second);
    if (auto at = dyn_cast<AtOp>(by)) {
      OpBuilder b(by);
      replaceHalves(at.getElement(), AtOp::create(b, at.getLoc(), half(second), col, at.getIndex()).getResult());
      at->erase();
    } else {
      Value x = cast<AlphaOp>(by).getXform().front().getArgument(0);
      replaceHalves(x, x);
      x.setType(half(second));
      by->setOperand(0, col);
    }
  }
  for (Operation *size : sizes) size->setOperand(0, columnOf(reads[0].b));
  made->erase();
  return true;
}

struct RouteTwins : PassWrapper<RouteTwins, OperationPass<ModuleOp>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(RouteTwins)
  StringRef getArgument() const final { return "trikeshed-route-twins"; }
  StringRef getDescription() const final {
    return "Fold pairs by the laws of j; make a series of pairs read a half at a time as a column a half";
  }
  void runOnOperation() final {
    getOperation().walk([](func::FuncOp f) {
      for (bool changed = true; changed;) {
        changed = false;
        foldPairs(f);
        SmallVector<Operation *> made;
        f.walk([&](Operation *op) {
          if (isa<SeriesOp, AlphaOp>(op)) made.push_back(op);
        });
        for (Operation *op : made) changed |= splitSeries(op);
      }
    });
  }
};

} // namespace

void registerTwinRouting() { PassRegistration<RouteTwins>(); }

} // namespace composite
