//===- ScalarJIT.h - Guarded, demand-compiled scalar lambda tier -*- C++ -*-===//
#ifndef NIX_SCALAR_JIT_H
#define NIX_SCALAR_JIT_H

#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/ArrayRef.h"
#include <array>
#include <memory>

namespace mlir { class Operation; class Value; }
namespace nixev {
struct EvalState;
struct Value;
struct Frame;

/// An optional tier for scalar arithmetic and structurally proven lazy value selectors.
/// Native code never forces a value. The host resolves each closure's captures and demands only the persistent
/// cells required by the original graph, in its original order. A miss runs the interpreter exactly once.
class ScalarJIT {
  struct CurriedCache { std::array<void *, 3> byArity{}; };
public:
  static std::unique_ptr<ScalarJIT> create();
  ~ScalarJIT();
  /// Refused regions stay on the inline interpreter path; diagnostics can still observe every call.
  bool accepts(const void *cache) const { return profiling || cache != refused; }
  bool acceptsSaturated(const void *cache, unsigned arity = 0) const {
    if (!curried || cache == refused) return false;
    if (!cache || arity < 2 || arity > 4) return true;
    return static_cast<const CurriedCache *>(cache)->byArity[arity - 2] != refused;
  }
  /// Returns true after producing out (natively or through the one oracle).
  bool evaluateSaturated(EvalState &, mlir::Operation *lambda, mlir::Value result, Frame *closureEnv,
                         llvm::ArrayRef<Value *> args, Value &out, const void *callPos, void *&cache,
                         llvm::function_ref<void()> interpret);
  void evaluate(EvalState &, mlir::Operation *lambda, mlir::Value result, Frame *closureEnv,
                Value &arg, Value &out, const void *callPos, void *&cache,
                llvm::function_ref<void()> interpret);
  void printStats() const;
private:
  ScalarJIT();
  struct Impl;
  std::unique_ptr<Impl> impl;
  const void *refused;
  const bool profiling;
  const bool curried;
};
} // namespace nixev
#endif
