#include "Composite/Composite.h"
#include "NixDialect/NixDialect.h"
#include "mlir/IR/DialectRegistry.h"
#include "mlir/Tools/mlir-opt/MlirOptMain.h"
#include "mlir/Transforms/Passes.h"

int main(int argc, char **argv) {
  mlir::DialectRegistry registry;
  mlir::nix::registerNixDialects(registry);
  mlir::join::registerCompositeDialects(registry);
  mlir::registerTransformsPasses();
  mlir::nix::registerNixPasses();
  mlir::join::registerCompositePasses();
  return mlir::asMainReturnCode(
      mlir::MlirOptMain(argc, argv, "Nix dialect optimizer\n", registry));
}
