//===- MLIRGen.h - Lower the Nix AST to the nix dialect -------*- C++ -*-===//
#ifndef NIX_MLIRGEN_H
#define NIX_MLIRGEN_H

#include "Nix/AST.h"
#include "NixDialect/NixDialect.h"
#include "mlir/IR/BuiltinOps.h"

#include <functional>

namespace nixfe {

struct GenOptions {
  /// Names visible in the global base environment (true/false/null, map,
  /// builtins, __sub, ...).
  std::function<bool(llvm::StringRef)> isBaseName;
  /// Extra lexical scope for scopedImport.  When non-empty the generated
  /// expression is `scope: <expr>`, and these names resolve to `scope.name`.
  std::vector<std::string> scopeNames;
  bool scoped = false;
};

/// Lower `e` into a new `nix.expr @symName` appended to `module`.
/// Throws ParseError on static errors (undefined variables).
mlir::nix::ExprOp genExpr(mlir::ModuleOp module, const Expr *e,
                          std::shared_ptr<Origin> origin, llvm::StringRef symName,
                          const GenOptions &opts);

} // namespace nixfe

#endif
