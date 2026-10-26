set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${PROJECT_BINARY_DIR}/bin)

add_executable(mlnix-opt mlnix-opt.cpp)
target_link_libraries(mlnix-opt PRIVATE NixPipeline MLIRNix MLIROptLib MLIRIR MLIRPass MLIRTransforms MLIRSupport MLIRParser)
llvm_update_compile_flags(mlnix-opt)

add_executable(mlnix mlnix.cpp)
target_link_libraries(mlnix PRIVATE NixEval NixFrontend NixStore MLIRNix MLIRIR MLIRParser MLIRPass MLIRSupport)
llvm_update_compile_flags(mlnix)

# Per-call cost of the optimization drivers (direct / PassManager / Transform).
add_executable(mlnix-pipebench mlnix-pipebench.cpp)
target_link_libraries(mlnix-pipebench PRIVATE NixEval NixPipeline NixFrontend NixStore MLIRNix MLIRIR MLIRParser MLIRPass MLIRSupport)
llvm_update_compile_flags(mlnix-pipebench)
