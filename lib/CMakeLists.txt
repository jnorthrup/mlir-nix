add_mlir_dialect_library(MLIRNix
  Dialect/NixDialect.cpp
  Dialect/NixPrims.cpp
  Dialect/Prims/NixNum.cpp
  Dialect/Prims/NixTy.cpp
  Dialect/Prims/NixStr.cpp
  Dialect/Prims/NixCtx.cpp
  Dialect/Prims/NixList.cpp
  Dialect/Prims/NixAttr.cpp
  Dialect/Prims/NixPath.cpp
  Dialect/Prims/NixStore.cpp
  Dialect/Prims/NixHash.cpp
  Dialect/Prims/NixFmt.cpp
  Dialect/Prims/NixCtl.cpp
  PARTIAL_SOURCES_INTENDED
  DEPENDS MLIRNixOpsIncGen
  LINK_LIBS PUBLIC MLIRIR MLIRPass MLIRTransforms MLIRTransformUtils MLIRRewrite MLIRSideEffectInterfaces)

add_library(NixStore STATIC Store/Hash.cpp Store/StorePaths.cpp Store/LocalStore.cpp Store/StructuredAttrs.cpp)
target_link_libraries(NixStore PUBLIC LLVMSupport)
llvm_update_compile_flags(NixStore)

add_library(NixFrontend STATIC Frontend/Parser.cpp Frontend/Printer.cpp Frontend/MLIRGen.cpp)
add_dependencies(NixFrontend MLIRNixOpsIncGen)
target_link_libraries(NixFrontend PUBLIC MLIRNix MLIRIR)
llvm_update_compile_flags(NixFrontend)

# Optimization pipelines as data: a textual pass pipeline or a Transform script
# (pipelines/default.transform.mlir is embedded into the binary).
set(NIX_DEFAULT_TRANSFORM_FILE ${PROJECT_SOURCE_DIR}/pipelines/default.transform.mlir)
file(READ ${NIX_DEFAULT_TRANSFORM_FILE} NIX_DEFAULT_TRANSFORM)
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${NIX_DEFAULT_TRANSFORM_FILE})
configure_file(Pipeline/Embedded.cpp.in ${CMAKE_CURRENT_BINARY_DIR}/Pipeline/Embedded.cpp @ONLY)
add_library(NixPipeline STATIC Pipeline/Pipeline.cpp ${CMAKE_CURRENT_BINARY_DIR}/Pipeline/Embedded.cpp)
add_dependencies(NixPipeline MLIRNixOpsIncGen)
target_link_libraries(NixPipeline PUBLIC MLIRNix MLIRIR MLIRParser MLIRPass MLIRTransforms
  MLIRTransformDialect MLIRTransformDialectTransforms MLIRTransformDebugExtension
  MLIRTransformTuneExtension MLIRTransformDialectIRDLExtension MLIRTransformPDLExtension)
llvm_update_compile_flags(NixPipeline)

add_library(NixEval STATIC Eval/Eval.cpp Eval/Builtins.cpp Eval/StoreBuiltins.cpp Eval/Formats.cpp Eval/EvalModels.cpp)
add_dependencies(NixEval MLIRNixOpsIncGen)
target_link_libraries(NixEval PUBLIC NixFrontend NixPipeline NixStore MLIRNix MLIRIR MLIRParser MLIRPass)
llvm_update_compile_flags(NixEval)
