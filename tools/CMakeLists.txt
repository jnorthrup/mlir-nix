set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${PROJECT_BINARY_DIR}/bin)

add_executable(mlnix-opt mlnix-opt.cpp)
target_link_libraries(mlnix-opt PRIVATE MLIRComposite MLIRNix MLIROptLib MLIRIR MLIRPass MLIRTransforms MLIRSupport MLIRParser)
llvm_update_compile_flags(mlnix-opt)

add_executable(mlnix mlnix.cpp)
target_link_libraries(mlnix PRIVATE NixEval NixFrontend NixStore MLIRNix MLIRIR MLIRParser MLIRPass MLIRSupport)
llvm_update_compile_flags(mlnix)

# mlir-query (the matcher-combinator language that ships with MLIR) over Nix IR.
add_executable(mlnix-query mlnix-query.cpp)
target_link_libraries(mlnix-query PRIVATE MLIRNix MLIRQueryLib MLIRQueryMatcher MLIRIR MLIRParser MLIRSupport)
llvm_update_compile_flags(mlnix-query)

# Parse a list of files in one process (scripts/parse-corpus.py compares two builds with it).
add_executable(mlnix-parse mlnix-parse.cpp)
target_link_libraries(mlnix-parse PRIVATE NixFrontend)
llvm_update_compile_flags(mlnix-parse)
