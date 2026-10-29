cmake_minimum_required(VERSION 3.20)
project(mlir-nix LANGUAGES CXX C)

# 20 unless the configure line says otherwise (-DCMAKE_CXX_STANDARD=23): LLVM and MLIR themselves are C++17, so any of them links.
if(NOT CMAKE_CXX_STANDARD)
  set(CMAKE_CXX_STANDARD 20)
endif()
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

if(NOT MLIR_DIR AND EXISTS /opt/homebrew/opt/llvm/lib/cmake/mlir)
  set(MLIR_DIR /opt/homebrew/opt/llvm/lib/cmake/mlir)
endif()
find_package(MLIR REQUIRED CONFIG)
message(STATUS "Using MLIRConfig.cmake in: ${MLIR_DIR}")

list(APPEND CMAKE_MODULE_PATH "${MLIR_CMAKE_DIR}" "${LLVM_CMAKE_DIR}")
include(TableGen)
include(AddLLVM)
include(AddMLIR)
include(HandleLLVMOptions)

include_directories(${LLVM_INCLUDE_DIRS} ${MLIR_INCLUDE_DIRS})
include_directories(${PROJECT_SOURCE_DIR}/include ${PROJECT_BINARY_DIR}/include)
link_directories(${LLVM_BUILD_LIBRARY_DIR})
# LLVM_DEFINITIONS is one string of -D flags; add_definitions needs them as a list.
separate_arguments(LLVM_DEFINITIONS_LIST NATIVE_COMMAND "${LLVM_DEFINITIONS}")
add_definitions(${LLVM_DEFINITIONS_LIST})

# The evaluator relies on C++ exceptions for Nix errors (throw/assert/tryEval).
set(LLVM_REQUIRES_EH ON)
set(LLVM_REQUIRES_RTTI ON)
string(REPLACE "-fno-exceptions" "" CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS}")
string(REPLACE "-fno-rtti" "" CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS}")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fexceptions -frtti -Wno-unused-parameter")

add_subdirectory(include/Composite)
add_subdirectory(include/NixDialect)
add_subdirectory(lib)
add_subdirectory(tools)

# The hot set of the algebra is pure and small: `ninja hot-check`.
add_custom_target(hot-check COMMAND bash ${PROJECT_SOURCE_DIR}/scripts/hot-check.sh WORKING_DIRECTORY ${PROJECT_SOURCE_DIR} VERBATIM)
