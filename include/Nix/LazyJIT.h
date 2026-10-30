//===- LazyJIT.h - Bounded lazy demand/continuation compiler -*- C++ -*-===//
#ifndef NIX_LAZY_JIT_H
#define NIX_LAZY_JIT_H

#include "llvm/ADT/ArrayRef.h"

#include <array>
#include <cstdint>
#include "Composite/Vocab.h"

namespace mlir { class Operation; class Value; class ModuleOp; }
namespace llvm { class raw_ostream; }
namespace nixev {
struct EvalState;
struct Frame;
struct Value;

/// Native code inspects persistent cells and returns demand requests. All
/// forcing, source positions, and exceptions remain in the host evaluator.
class LazyJITPlan {
public:
  struct Runtime;
  using Fn = uint64_t (*)(uint32_t resume, Runtime *runtime);
  enum class Outcome { Done, Deopt, Invalid };
  struct RunResult {
    enum class Empty { None, Attrs, List, String };
    Outcome outcome = Outcome::Invalid;
    bool value = false;
    Value *cell = nullptr; // Done value result: existing WHNF cell, never temporary storage
    Empty empty = Empty::None; // Done recipe: host materializes only after trusted completion
    std::array<Value *, 4> listElements{}; // owned handle copy; elements may still be lazy
    unsigned listSize = 0; // 1..4 for a nonempty recipe, otherwise zero
    unsigned listHandleLookups = 0; // trusted nonforcing lookup calls for missing captures
    // String guards run only after lhs and rhs reach WHNF, in that order.
    unsigned stringComparisons = 0, stringGuardDeopts = 0;
    unsigned pathProjectionRequests = 0; // subset of projectionRequests for multi-key static paths
    unsigned demands = 0; // actual host forcing actions, not capture resolution
    unsigned resumes = 0; // native invocations, including the initial invocation
    unsigned inlineCalls = 0, guardMisses = 0, depthEntries = 0;
    unsigned saturatedInlineCalls = 0;
    // Requests include observe-only peeks; forces are zero in observe-only runs.
    // Like demands, these counters are aggregated only if the run returns.
    unsigned projectionRequests = 0, projectionForces = 0, projectionDeopts = 0;
    unsigned projectionFlat = 0, projectionLayered = 0, projectionCachedFlat = 0;
  };
  static composite::Own<LazyJITPlan> create(EvalState &, mlir::Operation *lambda,
                                             mlir::Value result);
  /// Exactly saturated direct unary-lambda chains, using only indexed bodies.
  /// The root environment belongs to the outer closure; no intermediate frame
  /// or closure is needed for substituted formal argument handles.
  static composite::Own<LazyJITPlan> createSaturated(EvalState &, mlir::Operation *outerLambda,
                                                      unsigned nargs);
  ~LazyJITPlan();
  bool needsSpecialization() const;
  /// Rebuild from existing WHNF callees and indexed bodies; never forces or mints.
  /// Failure leaves the cold plan intact so a later observed input can qualify.
  bool specialize(EvalState &, Frame *closureEnv, Value &arg);
  bool specialize(EvalState &, Frame *closureEnv, llvm::ArrayRef<Value *> args);
  unsigned argumentCount() const;
  unsigned inlineCallCount() const;
  unsigned saturatedInlineCallCount() const;
  unsigned projectionCount() const;
  unsigned valueReturnCount() const;
  unsigned listReturnCount() const;
  unsigned comparisonCount() const;
  unsigned pathProjectionCount() const;
  bool emit(mlir::ModuleOp module); // defines the entry point named "scalar"
  /// Post-oracle admission: reads existing cells without allocating or forcing.
  /// Value demands require WHNF; list element handles deliberately do not.
  RunResult observe(EvalState &, Frame *closureEnv, Value &arg) const;
  RunResult observe(EvalState &, Frame *closureEnv, llvm::ArrayRef<Value *> args) const;
  RunResult run(EvalState &, Frame *closureEnv, Value &arg, Fn, bool observeOnly, const void *callPos = nullptr);
  RunResult run(EvalState &, Frame *closureEnv, llvm::ArrayRef<Value *> args, Fn, bool observeOnly,
                const void *callPos = nullptr);
  unsigned nodeCount() const;
  unsigned leafCount() const;
  unsigned blockCount() const;
  void print(llvm::raw_ostream &) const;

private:
  struct Impl;
  explicit LazyJITPlan(composite::Own<Impl>);
  composite::Own<Impl> impl;
};
} // namespace nixev
#endif
