#include "Nix/Pipeline.h"
#include "NixDialect/NixDialect.h"
#include "mlir/Dialect/Transform/Transforms/Passes.h"
#include "mlir/IR/DialectRegistry.h"
#include "mlir/Tools/mlir-opt/MlirOptMain.h"

int main(int argc, char **argv) {
  mlir::DialectRegistry registry;
  mlir::nix::registerNixDialects(registry);
  // The Transform dialect (+ debug/tune/irdl/pdl extensions) and its
  // interpreter pass, so `--transform-interpreter` can run scripts over Nix IR.
  nixpipe::registerTransformDialects(registry);
  mlir::transform::registerTransformPasses();
  // nix-prims, nix-fold, nix-dce, nix-simplify and the stock cse, canonicalize, ...
  nixpipe::registerPasses();
  return mlir::asMainReturnCode(
      mlir::MlirOptMain(argc, argv, "Nix dialect optimizer\n", registry));
}
