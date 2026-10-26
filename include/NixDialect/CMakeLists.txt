# Shared interfaces (NixBase.td)
set(LLVM_TARGET_DEFINITIONS NixBase.td)
mlir_tablegen(NixInterfaces.h.inc -gen-op-interface-decls)
mlir_tablegen(NixInterfaces.cpp.inc -gen-op-interface-defs)

# The language core
set(LLVM_TARGET_DEFINITIONS NixOps.td)
mlir_tablegen(NixOps.h.inc -gen-op-decls)
mlir_tablegen(NixOps.cpp.inc -gen-op-defs)
mlir_tablegen(NixDialect.h.inc -gen-dialect-decls -dialect=nix)
mlir_tablegen(NixDialect.cpp.inc -gen-dialect-defs -dialect=nix)
mlir_tablegen(NixTypes.h.inc -gen-typedef-decls -typedefs-dialect=nix)
mlir_tablegen(NixTypes.cpp.inc -gen-typedef-defs -typedefs-dialect=nix)

# One dialect per continent of primops (NixPrims.td).  `-dialect` selects the
# dialect definition; the ops of a dialect are selected by matching the regex
# against their full op name (`nixnum.add`).
set(NIX_CONTINENTS nixnum nixty nixstr nixctx nixlist nixattr nixpath nixstore
                   nixhash nixfmt nixctl)
set(LLVM_TARGET_DEFINITIONS NixPrims.td)
foreach(c ${NIX_CONTINENTS})
  string(SUBSTRING ${c} 0 1 _first)
  string(TOUPPER ${_first} _first)
  string(SUBSTRING ${c} 1 -1 _rest)
  set(D "${_first}${_rest}")
  mlir_tablegen(${D}Ops.h.inc -gen-op-decls "-op-include-regex=^${c}[.]")
  mlir_tablegen(${D}Ops.cpp.inc -gen-op-defs "-op-include-regex=^${c}[.]")
  mlir_tablegen(${D}Dialect.h.inc -gen-dialect-decls -dialect=${c})
  mlir_tablegen(${D}Dialect.cpp.inc -gen-dialect-defs -dialect=${c})
endforeach()

add_public_tablegen_target(MLIRNixOpsIncGen)
