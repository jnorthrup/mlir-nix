set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${PROJECT_BINARY_DIR}/bin)

add_executable(mlnix-opt mlnix-opt.cpp)
target_link_libraries(mlnix-opt PRIVATE MLIRNix MLIROptLib MLIRIR MLIRPass MLIRTransforms MLIRSupport MLIRParser)
llvm_update_compile_flags(mlnix-opt)

add_executable(mlnix mlnix.cpp)
target_link_libraries(mlnix PRIVATE NixEval NixFrontend NixStore MLIRNix MLIRIR MLIRParser MLIRPass MLIRSupport)
llvm_update_compile_flags(mlnix)

add_executable(mlnix-pdl-gen mlnix-pdl-gen.cpp)
target_link_libraries(mlnix-pdl-gen PRIVATE MLIRNix MLIRIR MLIRSupport)
llvm_update_compile_flags(mlnix-pdl-gen)
