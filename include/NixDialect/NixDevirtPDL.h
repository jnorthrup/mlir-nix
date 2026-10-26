//===- NixDevirtPDL.h - primop devirtualization as PDL patterns -----------===//
//
// Experiment: the rewrite `nix.apply (builtin|builtins.X) args -> continent op`
// (DevirtualizePrimCall in NixDialect.cpp) as pdl.pattern ops generated from the
// primop registry NixDialect::prims, selected at run time by
//
//   MLNIX_DEVIRT=pdl            patterns built with OpBuilder at startup, run by
//                               walkAndApplyPatterns (the bytecode matcher runs
//                               on every op of the walk)
//   MLNIX_DEVIRT=pdl-apply      same patterns, matcher only run on nix.apply ops
//   MLNIX_DEVIRT=pdl:FILE | pdl-apply:FILE
//                               PDL module read from FILE (mlnix-pdl-gen --pdl,
//                               or the output of `mlir-pdll -x=mlir`)
//   MLNIX_DEVIRT unset | cpp    the hand-written C++ pattern (default)
//   MLNIX_DEVIRT_TIME=1         print setup/walk timings at exit (either mode)
//
//===----------------------------------------------------------------------===//
#ifndef NIXDIALECT_NIXDEVIRTPDL_H
#define NIXDIALECT_NIXDEVIRTPDL_H

#include "NixDialect/NixDialect.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/OwningOpRef.h"
#include <chrono>
#include <cstdint>
#include <string>

namespace mlir::nix {

enum class DevirtMode { Cpp, PDL, PDLApply };
struct DevirtConfig {
  DevirtMode mode = DevirtMode::Cpp;
  std::string file; // PDL module to load instead of generating one
  bool time = false;
};
/// Parsed once from the environment.
const DevirtConfig &devirtConfig();

/// Accumulated timings (ms) of the devirtualization stage; printed at exit when
/// MLNIX_DEVIRT_TIME is set.
struct DevirtStats {
  double buildMs = 0;    // generate (or parse) the pdl.pattern module
  double lowerMs = 0;    // PDL -> PDL interpreter (predicate tree)
  double bytecodeMs = 0; // PDL interpreter -> bytecode, FrozenRewritePatternSet
  double walkMs = 0;     // the pattern walk, summed over all calls
  double cleanupMs = 0;  // dead-callee worklist, summed over all calls
  uint64_t calls = 0, ops = 0, applies = 0;
  ~DevirtStats();
};
DevirtStats &devirtStats();
using DevirtClock = std::chrono::steady_clock;
inline double devirtMs(DevirtClock::time_point a, DevirtClock::time_point b) {
  return std::chrono::duration<double, std::milli>(b - a).count();
}

/// Run the compiled PDL patterns with walkAndApplyPatterns below `root`.
void devirtualizePrimsPDL(Operation *root);

/// The pdl.pattern module for every (callee spelling x arity x exact|over).
OwningOpRef<ModuleOp> buildDevirtPDLModule(MLIRContext *ctx);
/// The same rules as PDLL source (core ops unregistered for PDLL, continent ops
/// from NixPrims.td); `mlir-pdll -x=mlir` turns it into the PDL module.
std::string emitDevirtPDLL(NixDialect &core);
/// Number of patterns the generators emit.
size_t countDevirtPatterns(NixDialect &core);
/// PDL -> PDL interpreter lowering as FrozenRewritePatternSet does it.
LogicalResult lowerDevirtPDL(ModuleOp module);

} // namespace mlir::nix

#endif
