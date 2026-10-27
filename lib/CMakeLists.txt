add_mlir_dialect_library(MLIRNix
  Dialect/NixDialect.cpp
  Dialect/NixPrimDialects.cpp
  PARTIAL_SOURCES_INTENDED
  DEPENDS MLIRNixOpsIncGen
  LINK_LIBS PUBLIC MLIRIR MLIRPass MLIRTransforms MLIRTransformUtils MLIRRewrite MLIRSideEffectInterfaces MLIRIRDL MLIRParser)

# TrikeShed's kernel as a dialect: Join, MetaSeries, Series, Series2, split, Cursor, α, ↺ and the combinators of
# borg.trikeshed.lib, generated from include/Composite/TrikeShed.td.
add_mlir_dialect_library(MLIRTrikeShed
  Composite/TrikeShedDialect.cpp
  PARTIAL_SOURCES_INTENDED
  DEPENDS TrikeShedIncGen
  LINK_LIBS PUBLIC MLIRIR MLIRSideEffectInterfaces)

add_library(NixStore STATIC Store/Hash.cpp Store/StorePaths.cpp Store/LocalStore.cpp Store/StructuredAttrs.cpp Store/Prefetch.cpp)
target_link_libraries(NixStore PUBLIC LLVMSupport)
# SHA-256: CommonCrypto on macOS; elsewhere libcrypto when there is one (it picks the CPU's SHA extensions or AVX2, the code Nix hashes
# with), else LLVM's portable C, which costs 8-12% of a run on a machine whose hashing it slows (docs/PERFORMANCE.md).  libcrypto.a is
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

add_library(NixFrontend STATIC Frontend/Parser.cpp Frontend/Source.cpp Frontend/Confix.cpp)
add_dependencies(NixFrontend MLIRNixOpsIncGen TrikeShedIncGen)
target_link_libraries(NixFrontend PUBLIC MLIRNix MLIRIR)
llvm_update_compile_flags(NixFrontend)

add_library(NixEval STATIC Eval/Eval.cpp Eval/Builtins.cpp Eval/StoreBuiltins.cpp Eval/Formats.cpp Eval/EvalModels.cpp)
add_dependencies(NixEval MLIRNixOpsIncGen TrikeShedIncGen)
target_link_libraries(NixEval PUBLIC NixFrontend NixStore MLIRNix MLIRIR MLIRParser MLIRPass)
llvm_update_compile_flags(NixEval)
