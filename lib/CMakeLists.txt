add_mlir_dialect_library(MLIRNix
  Dialect/NixDialect.cpp
  Dialect/NixPrimDialects.cpp
  Dialect/MlnixControlDialect.cpp
  Dialect/KifDialect.cpp
  Dialect/KifImport.cpp
  Dialect/KifChase.cpp
  Dialect/KifLean.cpp
  Dialect/KifTptp.cpp
  Dialect/KifTrikeShed.cpp
  Dialect/SumoDialect.cpp
  Dialect/SonDialect.cpp
  Dialect/ConfixDialect.cpp
  PARTIAL_SOURCES_INTENDED
  DEPENDS MLIRNixOpsIncGen TrikeShedIncGen
  LINK_LIBS PUBLIC MLIRTrikeShed MLIRIR MLIRPass MLIRTransforms MLIRTransformUtils MLIRRewrite MLIRSideEffectInterfaces MLIRIRDL MLIRParser MLIRLLVMDialect)

# The Confix scanner is LLVM IR (Confix/confix.ll, freestanding: it calls nothing).  opt and llc make its object, which MLIRNix carries, so that
# whatever links the library can call confix_scan_json and confix_scan_cbor, which the confix-to-llvm pass lowers to.
find_program(MLNIX_OPT opt HINTS ${LLVM_TOOLS_BINARY_DIR})
find_program(MLNIX_LLC llc HINTS ${LLVM_TOOLS_BINARY_DIR})
if(NOT MLNIX_OPT OR NOT MLNIX_LLC)
  message(FATAL_ERROR "opt and llc are needed to build lib/Confix/confix.ll")
endif()
set(CONFIX_LL ${CMAKE_CURRENT_SOURCE_DIR}/Confix/confix.ll)
set(CONFIX_OBJ ${CMAKE_CURRENT_BINARY_DIR}/confix.o)
add_custom_command(OUTPUT ${CONFIX_OBJ}
  COMMAND ${MLNIX_OPT} -O3 ${CONFIX_LL} -o ${CMAKE_CURRENT_BINARY_DIR}/confix.bc
  COMMAND ${MLNIX_LLC} -O3 -filetype=obj -relocation-model=pic ${CMAKE_CURRENT_BINARY_DIR}/confix.bc -o ${CONFIX_OBJ}
  DEPENDS ${CONFIX_LL}
  COMMENT "Confix scanner (LLVM IR)")
set_source_files_properties(${CONFIX_OBJ} PROPERTIES EXTERNAL_OBJECT TRUE GENERATED TRUE)
target_sources(MLIRNix PRIVATE ${CONFIX_OBJ})

# TrikeShed's kernel as a dialect: Join, MetaSeries, Series, Series2, split, Cursor, α, ↺ and the combinators of
# borg.trikeshed.lib, generated from include/Composite/TrikeShed.td.
add_mlir_dialect_library(MLIRTrikeShed
  Composite/TrikeShedDialect.cpp
  Composite/ClusterLowering.cpp
  Composite/CursorLowering.cpp
  PARTIAL_SOURCES_INTENDED
  DEPENDS TrikeShedIncGen
  LINK_LIBS PUBLIC MLIRIR MLIRSideEffectInterfaces MLIRFuncDialect MLIRMemRefDialect MLIRPass
                   MLIRArithDialect MLIRSCFDialect MLIRSCFTransforms MLIRFuncTransforms MLIRTransformUtils)

add_library(TrikeShedRuntime SHARED Composite/ClusterRuntime.cpp)
set_target_properties(TrikeShedRuntime PROPERTIES LIBRARY_OUTPUT_DIRECTORY ${PROJECT_BINARY_DIR}/lib)

add_library(NixStore STATIC Store/Hash.cpp Store/StorePaths.cpp Store/LocalStore.cpp Store/StructuredAttrs.cpp Store/Prefetch.cpp Store/Ed25519.cpp)
target_link_libraries(NixStore PUBLIC LLVMSupport)
# SHA-256: CommonCrypto on macOS; elsewhere libcrypto when there is one (it picks the CPU's SHA extensions or AVX2, the code Nix hashes
# with), else LLVM's portable C, which costs 8-12% of a run on a machine whose hashing it slows (77de09c:docs/PERFORMANCE.md).  libcrypto.a is
# preferred: loading libcrypto.so is 0.6 ms of the 10 ms an `eval -E 1` takes, the static one 0.15 ms.
set(MLNIX_SHA256 "auto" CACHE STRING "SHA-256 code: auto (CommonCrypto on macOS, else OpenSSL if found, else LLVM's), openssl or llvm")
if(MLNIX_SHA256 STREQUAL "openssl" OR (MLNIX_SHA256 STREQUAL "auto" AND NOT APPLE))
  set(OPENSSL_USE_STATIC_LIBS ON)
  find_package(OpenSSL QUIET)
  if(NOT OPENSSL_FOUND)
    set(OPENSSL_USE_STATIC_LIBS OFF)
    find_package(OpenSSL)
  endif()
  if(OPENSSL_FOUND)
    target_compile_definitions(NixStore PRIVATE MLNIX_SHA256_OPENSSL=1)
    target_link_libraries(NixStore PUBLIC OpenSSL::Crypto)
  elseif(MLNIX_SHA256 STREQUAL "openssl")
    message(FATAL_ERROR "MLNIX_SHA256=openssl, but OpenSSL was not found")
  endif()
elseif(MLNIX_SHA256 STREQUAL "llvm")
  target_compile_definitions(NixStore PRIVATE MLNIX_SHA256_LLVM=1)
endif()
# io_uring replay of recorded file accesses (Linux, liburing); elsewhere Prefetch.cpp only records.
find_path(URING_INCLUDE_DIR liburing.h)
find_library(URING_LIBRARY uring)
if(URING_INCLUDE_DIR AND URING_LIBRARY)
  target_compile_definitions(NixStore PUBLIC MLNIX_HAVE_URING=1)
  target_include_directories(NixStore PRIVATE ${URING_INCLUDE_DIR})
  target_link_libraries(NixStore PUBLIC ${URING_LIBRARY} pthread)
endif()
llvm_update_compile_flags(NixStore)
# The hot set of the TrikeShed algebra (include/Composite/Hot.h) is the one precompiled package; scripts/hot-check.sh holds it pure.
target_precompile_headers(NixStore PRIVATE ${PROJECT_SOURCE_DIR}/include/Composite/Hot.h)

# Hollowing the C++ into MLIR (docs/interfaces, scripts/cxx-interfaces.py): an interface's C++ definition is deleted
# (the header keeps the declaration) and provided instead by a lowered .mlir, translated to LLVM IR and compiled to an
# object linked into the owning library.  The .mlir defines the exact mangled symbol with the ABI the extractor gives.
# mlower_interface(TARGET MLIR STEM) is one hollowed interface; adding another is one .mlir under lowered/ and one call.
find_program(MLNIX_MLIR_TRANSLATE mlir-translate HINTS ${LLVM_TOOLS_BINARY_DIR} REQUIRED)
find_program(MLNIX_LOWER_CLANG clang HINTS ${LLVM_TOOLS_BINARY_DIR} REQUIRED)
set(MLNIX_LOWERED_DIR ${CMAKE_CURRENT_BINARY_DIR}/lowered)
file(MAKE_DIRECTORY ${MLNIX_LOWERED_DIR})
function(mlnix_lower_interface target mlir stem)
  set(src ${PROJECT_SOURCE_DIR}/${mlir})
  set(ll ${MLNIX_LOWERED_DIR}/${stem}.ll)
  set(o ${MLNIX_LOWERED_DIR}/${stem}.o)
  add_custom_command(OUTPUT ${ll}
    COMMAND ${MLNIX_MLIR_TRANSLATE} --mlir-to-llvmir ${src} -o ${ll}
    DEPENDS ${src} COMMENT "lowering ${mlir} to LLVM IR")
  add_custom_command(OUTPUT ${o}
    COMMAND ${MLNIX_LOWER_CLANG} -O2 -c ${ll} -o ${o}
    DEPENDS ${ll} COMMENT "compiling lowered ${stem}.o")
  add_custom_target(mlnix_lowered_${stem} DEPENDS ${o})
  add_dependencies(${target} mlnix_lowered_${stem})
  target_sources(${target} PRIVATE ${o})
  set_source_files_properties(${o} PROPERTIES EXTERNAL_OBJECT TRUE GENERATED TRUE)
endfunction()
# A hollowed interface written in the TrikeShed dialect (not yet the llvm dialect): first --trikeshed-lower-cursors
# (mlnix-opt), then the stock buffer pipeline mlnixci and the LLVM arm lower with (scripts/nix-native.sh), then translate
# and compile.  Same object linkage as mlnix_lower_interface; the .mlir keeps the algebra in trikeshed ops.
find_program(MLNIX_MLIR_OPT mlir-opt HINTS ${LLVM_TOOLS_BINARY_DIR} REQUIRED)
set(MLNIX_TRIKESHED_PIPELINE
  --ownership-based-buffer-deallocation --canonicalize --buffer-deallocation-simplification
  --bufferization-lower-deallocations --convert-scf-to-cf --expand-strided-metadata --lower-affine
  --finalize-memref-to-llvm --convert-scf-to-cf --convert-arith-to-llvm --convert-index-to-llvm
  --convert-cf-to-llvm --convert-func-to-llvm --reconcile-unrealized-casts)
function(mlnix_lower_trikeshed target mlir stem)
  set(src ${PROJECT_SOURCE_DIR}/${mlir})
  set(cur ${MLNIX_LOWERED_DIR}/${stem}.cursors.mlir)
  set(low ${MLNIX_LOWERED_DIR}/${stem}.lowered.mlir)
  set(ll ${MLNIX_LOWERED_DIR}/${stem}.ll)
  set(o ${MLNIX_LOWERED_DIR}/${stem}.o)
  add_custom_command(OUTPUT ${cur}
    COMMAND $<TARGET_FILE:mlnix-opt> ${src} --trikeshed-lower-cursors -o ${cur}
    DEPENDS ${src} mlnix-opt COMMENT "trikeshed-lower-cursors ${mlir}")
  add_custom_command(OUTPUT ${low}
    COMMAND ${MLNIX_MLIR_OPT} ${cur} ${MLNIX_TRIKESHED_PIPELINE} -o ${low}
    DEPENDS ${cur} COMMENT "lowering ${stem} buffers to llvm")
  add_custom_command(OUTPUT ${ll}
    COMMAND ${MLNIX_MLIR_TRANSLATE} --mlir-to-llvmir ${low} -o ${ll}
    DEPENDS ${low} COMMENT "translating ${stem} to LLVM IR")
  add_custom_command(OUTPUT ${o}
    COMMAND ${MLNIX_LOWER_CLANG} -O2 -Wno-override-module -c ${ll} -o ${o}
    DEPENDS ${ll} COMMENT "compiling lowered ${stem}.o")
  add_custom_target(mlnix_lowered_${stem} DEPENDS ${o})
  add_dependencies(${target} mlnix_lowered_${stem})
  target_sources(${target} PRIVATE ${o})
  set_source_files_properties(${o} PROPERTIES EXTERNAL_OBJECT TRUE GENERATED TRUE)
endfunction()
# nixstore::Hash::operator== (lib/Store/Hash.cpp's definition is gone; include/Nix/Store.h keeps the declaration).
mlnix_lower_interface(NixStore lowered/nixstore/HashEq.mlir HashEq)
# nixstore::isInStore (lib/Store/StorePaths.cpp's definition is gone; include/Nix/Store.h keeps the declaration).
mlnix_lower_interface(NixStore lowered/nixstore/IsInStore.mlir IsInStore)

add_library(NixFrontend STATIC Frontend/Parser.cpp Frontend/Source.cpp Frontend/Confix.cpp)
add_dependencies(NixFrontend MLIRNixOpsIncGen TrikeShedIncGen)
target_link_libraries(NixFrontend PUBLIC MLIRNix MLIRIR)
llvm_update_compile_flags(NixFrontend)
target_precompile_headers(NixFrontend PRIVATE ${PROJECT_SOURCE_DIR}/include/Composite/Hot.h)

# The Nix sources the evaluator ships (lib/Corepkgs/*.nix: flakes) embedded as <nix/NAME>.
file(GLOB COREPKGS_NIX CONFIGURE_DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/Corepkgs/*.nix)
set(COREPKGS_INC ${CMAKE_CURRENT_BINARY_DIR}/Corepkgs.inc)
add_custom_command(OUTPUT ${COREPKGS_INC}
  COMMAND ${CMAKE_COMMAND} -DOUT=${COREPKGS_INC} -DDIR=${CMAKE_CURRENT_SOURCE_DIR}/Corepkgs -P ${CMAKE_CURRENT_SOURCE_DIR}/Corepkgs/Embed.cmake
  DEPENDS ${COREPKGS_NIX} ${CMAKE_CURRENT_SOURCE_DIR}/Corepkgs/Embed.cmake
  COMMENT "Corepkgs.inc (embedded Nix sources)")
set_source_files_properties(Eval/Eval.cpp PROPERTIES OBJECT_DEPENDS ${COREPKGS_INC})

add_library(NixEval STATIC Eval/Eval.cpp Eval/Builtins.cpp Eval/StoreBuiltins.cpp Eval/Formats.cpp Eval/EvalModels.cpp)
target_precompile_headers(NixEval PRIVATE ${PROJECT_SOURCE_DIR}/include/Composite/Hot.h)
add_dependencies(NixEval MLIRNixOpsIncGen TrikeShedIncGen)
target_include_directories(NixEval PRIVATE ${CMAKE_CURRENT_BINARY_DIR})
target_link_libraries(NixEval PUBLIC NixFrontend NixStore MLIRNix MLIRIR MLIRParser MLIRPass)
target_link_libraries(NixEval PRIVATE MLIRArithDialect MLIRControlFlowDialect MLIRFuncDialect MLIRLLVMDialect)
llvm_update_compile_flags(NixEval)
# nixev::EvalState::showType (lib/Eval/Eval.cpp's definition is gone; include/Nix/Eval.h keeps the declaration).
mlnix_lower_interface(NixEval lowered/nixeval/ShowType.mlir ShowType)
# The list primops __length, __elemAt, __genList, __foldl' (lib/Eval/Builtins.cpp's bodies are gone; the bridges force the
# operands and call these entries).  The list algebra is trikeshed.size / at / series / fold.
mlnix_lower_trikeshed(NixEval lowered/nixeval/ListOps.mlir ListOps)
