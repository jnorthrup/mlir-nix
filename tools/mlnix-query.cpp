//===- mlnix-query.cpp - mlir-query with the Nix dialects -----------------===//
//
// The matcher language that ships with MLIR (anyOf/allOf/hasOpName/
// getDefinitions/...), over Nix IR.  Adapted from llvm-project's
// mlir/tools/mlir-query/mlir-query.cpp (Apache-2.0 WITH LLVM-exception): only the
// dialect registry differs.  Example:
//
//   mlnix-query FILE.mlir -c 'm allOf(hasOpName("nix.apply"), getDefinitions(hasOpName("nix.builtin"), 1))'
//
//===----------------------------------------------------------------------===//

#include "mlir/IR/Dialect.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/Matchers.h"
#include "NixDialect/NixDialect.h"
#include "mlir/Query/Matcher/Registry.h"
#include "mlir/Query/Matcher/SliceMatchers.h"
#include "mlir/Tools/mlir-query/MlirQueryMain.h"

using namespace mlir;

// This is needed because these matchers are defined as overloaded functions.
using HasOpAttrName = detail::AttrOpMatcher(StringRef);
using HasOpName = detail::NameOpMatcher(StringRef);
using IsConstantOp = detail::constant_op_matcher();

int main(int argc, char **argv) {

  DialectRegistry dialectRegistry;
  nix::registerNixDialects(dialectRegistry);

  query::matcher::Registry matcherRegistry;

  // Matchers registered in alphabetical order for consistency:
  matcherRegistry.registerMatcher("allOf", query::matcher::internal::allOf);
  matcherRegistry.registerMatcher("anyOf", query::matcher::internal::anyOf);
  matcherRegistry.registerMatcher(
      "getAllDefinitions",
      query::matcher::m_GetAllDefinitions<query::matcher::DynMatcher>);
  matcherRegistry.registerMatcher(
      "getDefinitions",
      query::matcher::m_GetDefinitions<query::matcher::DynMatcher>);
  matcherRegistry.registerMatcher(
      "getDefinitionsByPredicate",
      query::matcher::m_GetDefinitionsByPredicate<query::matcher::DynMatcher,
                                                  query::matcher::DynMatcher>);
  matcherRegistry.registerMatcher(
      "getUsersByPredicate",
      query::matcher::m_GetUsersByPredicate<query::matcher::DynMatcher,
                                            query::matcher::DynMatcher>);
  matcherRegistry.registerMatcher("hasOpAttrName",
                                  static_cast<HasOpAttrName *>(m_Attr));
  matcherRegistry.registerMatcher("hasOpName", static_cast<HasOpName *>(m_Op));
  matcherRegistry.registerMatcher("isConstantOp",
                                  static_cast<IsConstantOp *>(m_Constant));
  matcherRegistry.registerMatcher("isNegInfFloat", m_NegInfFloat);
  matcherRegistry.registerMatcher("isNegZeroFloat", m_NegZeroFloat);
  matcherRegistry.registerMatcher("isNonZero", m_NonZero);
  matcherRegistry.registerMatcher("isOne", m_One);
  matcherRegistry.registerMatcher("isOneFloat", m_OneFloat);
  matcherRegistry.registerMatcher("isPosInfFloat", m_PosInfFloat);
  matcherRegistry.registerMatcher("isPosZeroFloat", m_PosZeroFloat);
  matcherRegistry.registerMatcher("isZero", m_Zero);
  matcherRegistry.registerMatcher("isZeroFloat", m_AnyZeroFloat);

  MLIRContext context(dialectRegistry);

  return failed(mlirQueryMain(argc, argv, context, matcherRegistry));
}
