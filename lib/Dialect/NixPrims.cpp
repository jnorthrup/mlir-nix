//===- NixPrims.cpp - Registration of the continent dialects --------------===//
//
// The dialects themselves are in Prims/Nix<Continent>.cpp (one translation
// unit each).
//
//===----------------------------------------------------------------------===//

#include "NixDialect/NixPrims.h"

using namespace mlir;
using namespace mlir::nix;

void mlir::nix::registerNixDialects(DialectRegistry &registry) {
  registry.insert<NixDialect, num::NixNumDialect, ty::NixTyDialect, str::NixStrDialect, ctx::NixCtxDialect, list::NixListDialect, attr::NixAttrDialect, path::NixPathDialect, store::NixStoreDialect, hash::NixHashDialect, fmt::NixFmtDialect, ctl::NixCtlDialect>();
}

void mlir::nix::loadNixDialects(MLIRContext &ctx) {
  ctx.loadDialect<NixDialect, num::NixNumDialect, ty::NixTyDialect, str::NixStrDialect, ctx::NixCtxDialect, list::NixListDialect, attr::NixAttrDialect, path::NixPathDialect, store::NixStoreDialect, hash::NixHashDialect, fmt::NixFmtDialect, ctl::NixCtlDialect>();
}
