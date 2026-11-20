set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${PROJECT_BINARY_DIR}/bin)

add_executable(mlnix-opt mlnix-opt.cpp)
target_link_libraries(mlnix-opt PRIVATE MLIRNix MLIRTrikeShed MLIROptLib MLIRIR MLIRPass MLIRTransforms MLIRSupport MLIRParser)
target_link_libraries(mlnix-opt PRIVATE MLIRArithDialect MLIRAsyncDialect MLIRControlFlowDialect MLIRSCFDialect)
add_dependencies(mlnix-opt TrikeShedRuntime)
llvm_update_compile_flags(mlnix-opt)

add_executable(mlnix mlnix.cpp)
target_link_libraries(mlnix PRIVATE NixEval NixFrontend NixStore MLIRNix MLIRIR MLIRParser MLIRPass MLIRSupport)
llvm_update_compile_flags(mlnix)

# KIF files into a kif.theory, and the chase (lib/Dialect/KifImport.cpp, KifChase.cpp).
add_executable(mlnix-kif mlnix-kif.cpp)
target_link_libraries(mlnix-kif PRIVATE MLIRNix MLIRTrikeShed MLIRIR MLIRParser MLIRPass MLIRSupport)
llvm_update_compile_flags(mlnix-kif)

# Parse a list of files in one process (scripts/parse-corpus.py compares two builds with it).
add_executable(mlnix-parse mlnix-parse.cpp)
target_link_libraries(mlnix-parse PRIVATE NixFrontend)
llvm_update_compile_flags(mlnix-parse)

# The C surface of the dialects (include/mlnix-c/MlnixC.h): what Kotlin/Native's cinterop links (TrikeShed's mlirMain).
add_library(mlnix-c SHARED mlnix-c.cpp)
set_target_properties(mlnix-c PROPERTIES LIBRARY_OUTPUT_DIRECTORY ${PROJECT_BINARY_DIR}/lib)
target_link_libraries(mlnix-c PRIVATE MLIRNix MLIRTrikeShed MLIRParser MLIRIR MLIRSupport
  MLIRArithDialect MLIRAsyncDialect MLIRControlFlowDialect MLIRSCFDialect)
llvm_update_compile_flags(mlnix-c)

# Kursive against std::regex::extended (scripts/kursive-check.cc; libstdc++ is the oracle, so it is run on Linux): the
# patterns compile through the kursive dialect (MLIRNix) and walk in NixEval's lowered KursiveOps.  Not built by default.
add_executable(kursive-check EXCLUDE_FROM_ALL ${PROJECT_SOURCE_DIR}/scripts/kursive-check.cc)
target_link_libraries(kursive-check PRIVATE NixEval MLIRNix MLIRIR MLIRPass MLIRSupport)
# -std=c++20, not gnu++20: Nix's libstdc++ regex is strict (__STRICT_ANSI__), which rejects escapes like \a and \1
set_target_properties(kursive-check PROPERTIES CXX_EXTENSIONS OFF)
