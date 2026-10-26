//===- Pipeline.h - Optimization pipelines as data ------------*- C++ -*-===//
//
// The evaluator does not decide which optimizations run on a freshly lowered
// expression.  It owns a `Pipeline` and hands it a module that holds exactly
// that expression; *what* the pipeline does is data:
//
//   makePassPipeline       a textual MLIR pass pipeline, e.g.
//                              builtin.module(nix-prims,cse,nix-dce)
//   makeTransformPipeline  a Transform-dialect script, e.g. pipelines/*.mlir:
//                              transform.named_sequence @__transform_main(...)
//
// Both are built once (per EvalState) and run many times: one PassManager, one
// parsed script.  See experiments/PIPELINE.md for what this costs per call.
//
//===----------------------------------------------------------------------===//
#ifndef NIX_PIPELINE_H
#define NIX_PIPELINE_H

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/DialectRegistry.h"
#include "mlir/IR/MLIRContext.h"
#include "llvm/ADT/StringRef.h"

#include <memory>
#include <string>

namespace nixpipe {

/// What runs on the module of one freshly lowered expression.
class Pipeline {
public:
  virtual ~Pipeline() = default;
  /// Not re-entrant: a pipeline is run by one thread at a time, and never from
  /// inside one of its own passes.
  virtual mlir::LogicalResult run(mlir::ModuleOp module) = 0;
};

/// The pipeline used when nothing else is asked for.
inline constexpr llvm::StringLiteral defaultPipelineText = "builtin.module(nix-prims)";

/// Registers the nix passes, the stock Transforms passes (cse, canonicalize,
/// ...) and, in `registry`, the Transform dialect with the extensions that are
/// useful for scripts over Nix IR (debug, tune, irdl, pdl).  Idempotent for the
/// process-global pass registry.
void registerPasses();
void registerTransformDialects(mlir::DialectRegistry &registry);

/// `text` is a pass pipeline anchored on an op, e.g. `builtin.module(nix-prims)`.
/// Null (and `error` filled) when it does not parse.  No instrumentation is
/// installed, and the verifier is off between passes unless `verify` (it walks
/// the whole module after every pass: cost proportional to the payload).
std::unique_ptr<Pipeline> makePassPipeline(mlir::MLIRContext &ctx, llvm::StringRef text,
                                           std::string &error, bool verify = false);

/// `script` is the text of a module with a `transform.named_sequence
/// @__transform_main` that takes the payload root (the module).  Loads the
/// Transform dialect into `ctx`.  `expensiveChecks` turns on the interpreter's
/// handle-validity checks (several times slower).
std::unique_ptr<Pipeline> makeTransformPipeline(mlir::MLIRContext &ctx, llvm::StringRef script,
                                                llvm::StringRef name, std::string &error,
                                                bool expensiveChecks = false);

/// The Transform script that ships in the binary (pipelines/default.transform.mlir).
llvm::StringRef embeddedTransformScript();

/// The deprecated `MLNIX_PASSES` spelling (`devirt`, `fold`, `dce`, `all`,
/// comma separated, order irrelevant) as a pass pipeline.
std::string pipelineFromLegacyPasses(llvm::StringRef passes);

/// Chooses the driver from the environment, else from `defaultPipeline`:
///   MLNIX_TRANSFORM=embedded|FILE   Transform-dialect script
///   MLNIX_PIPELINE=TEXT             textual pass pipeline
///   MLNIX_PASSES=devirt,fold,dce    deprecated alias of MLNIX_PIPELINE
std::unique_ptr<Pipeline> makeFromEnvironment(mlir::MLIRContext &ctx,
                                              llvm::StringRef defaultPipeline,
                                              std::string &error);

} // namespace nixpipe

#endif
