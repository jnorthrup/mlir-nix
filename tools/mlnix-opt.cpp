#include "Composite/TrikeShed.h"
#include "NixDialect/NixDialect.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Async/IR/Async.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/IR/DialectRegistry.h"
#include "mlir/Tools/mlir-opt/MlirOptMain.h"
#include "mlir/Transforms/Passes.h"

int main(int argc, char **argv) {
  mlir::DialectRegistry registry;
  registry.insert<mlir::arith::ArithDialect, mlir::async::AsyncDialect, mlir::cf::ControlFlowDialect,
                  mlir::func::FuncDialect, mlir::memref::MemRefDialect, mlir::scf::SCFDialect>();
  mlir::nix::registerNixDialects(registry);
  composite::registerTrikeShedDialect(registry);
  mlir::registerTransformsPasses();
  mlir::nix::registerNixPasses();
  composite::registerTrikeShedPasses();
  return mlir::asMainReturnCode(
      mlir::MlirOptMain(argc, argv, "Nix dialect optimizer\n", registry));
}
