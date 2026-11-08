#include "mlnix-c/MlnixC.h"

#include "Composite/TrikeShed.h"
#include "NixDialect/NixDialect.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Async/IR/Async.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/Verifier.h"
#include "mlir/Parser/Parser.h"

#include <cstdlib>
#include <cstring>

struct MlnixSession {
  mlir::MLIRContext ctx;
  llvm::SmallString<256> error;
  explicit MlnixSession(const mlir::DialectRegistry &registry) : ctx(registry) {}
};

MlnixSession *mlnixOpen() {
  mlir::DialectRegistry registry; // the set mlnix-opt registers
  registry.insert<mlir::arith::ArithDialect, mlir::async::AsyncDialect, mlir::cf::ControlFlowDialect,
                  mlir::func::FuncDialect, mlir::memref::MemRefDialect, mlir::scf::SCFDialect>();
  mlir::nix::registerNixDialects(registry);
  composite::registerTrikeShedDialect(registry);
  return new MlnixSession(registry);
}

void mlnixClose(MlnixSession *session) { delete session; }

char *mlnixRoundTrip(MlnixSession *session, const char *text, size_t length) {
  session->error.clear();
  llvm::raw_svector_ostream diagnostics(session->error);
  mlir::ScopedDiagnosticHandler handler(&session->ctx, [&](mlir::Diagnostic &d) {
    diagnostics << d << '\n';
    return mlir::success();
  });
  mlir::OwningOpRef<mlir::ModuleOp> module =
      mlir::parseSourceString<mlir::ModuleOp>(llvm::StringRef(text, length), mlir::ParserConfig(&session->ctx));
  if (!module || mlir::failed(mlir::verify(*module)))
    return nullptr;
  llvm::SmallString<256> printed;
  llvm::raw_svector_ostream out(printed);
  module->print(out);
  out << '\n';
  return strdup(printed.c_str());
}

const char *mlnixError(MlnixSession *session) { return session->error.c_str(); }

void mlnixFree(char *text) { free(text); }
