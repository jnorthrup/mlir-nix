#include "NixDialect/NixDialect.h"
#include "mlir/IR/DialectRegistry.h"
#include "mlir/Tools/mlir-opt/MlirOptMain.h"
#include "mlir/Transforms/Passes.h"

int main(int argc, char **argv) {
  mlir::DialectRegistry registry;
  registry.insert<mlir::nix::NixDialect>();
  mlir::registerTransformsPasses();
  mlir::nix::registerNixPasses();
  return mlir::asMainReturnCode(
      mlir::MlirOptMain(argc, argv, "Nix dialect optimizer\n", registry));
}
