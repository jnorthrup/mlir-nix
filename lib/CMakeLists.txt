# The PRELOAD composite (../TrikeShed/PRELOAD.md): Join and what collapses to it.
add_mlir_dialect_library(MLIRComposite
  Composite/Composite.cpp
  PARTIAL_SOURCES_INTENDED
  DEPENDS MLIRJoinIncGen
  LINK_LIBS PUBLIC MLIRIR MLIRPass MLIRTransforms MLIRTransformUtils MLIRArithDialect MLIRFuncDialect MLIRFuncTransforms MLIRSideEffectInterfaces)

add_mlir_dialect_library(MLIRNix
  Dialect/NixDialect.cpp
  Dialect/NixPrimDialects.cpp
  PARTIAL_SOURCES_INTENDED
  DEPENDS MLIRNixOpsIncGen
  LINK_LIBS PUBLIC MLIRIR MLIRPass MLIRTransforms MLIRTransformUtils MLIRRewrite MLIRSideEffectInterfaces MLIRIRDL MLIRParser)

add_library(NixStore STATIC Store/Hash.cpp Store/StorePaths.cpp Store/LocalStore.cpp Store/StructuredAttrs.cpp)
target_link_libraries(NixStore PUBLIC LLVMSupport)
llvm_update_compile_flags(NixStore)

add_library(NixFrontend STATIC Frontend/Parser.cpp Frontend/Printer.cpp Frontend/MLIRGen.cpp Frontend/Source.cpp)
add_dependencies(NixFrontend MLIRNixOpsIncGen)
target_link_libraries(NixFrontend PUBLIC MLIRNix MLIRIR)
llvm_update_compile_flags(NixFrontend)

add_library(NixEval STATIC Eval/Eval.cpp Eval/Builtins.cpp Eval/StoreBuiltins.cpp Eval/Formats.cpp Eval/EvalModels.cpp)
add_dependencies(NixEval MLIRNixOpsIncGen)
target_link_libraries(NixEval PUBLIC NixFrontend NixStore MLIRNix MLIRIR MLIRParser MLIRPass)
llvm_update_compile_flags(NixEval)
