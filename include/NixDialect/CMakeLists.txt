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

# The concentric layers of a source (NixSyntax.td): the kinds of tokens and bands the lexer and the scan use
set(LLVM_TARGET_DEFINITIONS NixSyntax.td)
mlir_tablegen(NixSyntaxEnums.h.inc -gen-enum-decls)
mlir_tablegen(NixSyntaxEnums.cpp.inc -gen-enum-defs)

# The control surface of the mlnix utility (MlnixControl.td): sessions, settings and evaluation requests
set(LLVM_TARGET_DEFINITIONS MlnixControl.td)
mlir_tablegen(MlnixControl.h.inc -gen-op-decls)
mlir_tablegen(MlnixControl.cpp.inc -gen-op-defs)
mlir_tablegen(MlnixControlDialect.h.inc -gen-dialect-decls -dialect=mlnix)
mlir_tablegen(MlnixControlDialect.cpp.inc -gen-dialect-defs -dialect=mlnix)
mlir_tablegen(MlnixControlEnums.h.inc -gen-enum-decls)
mlir_tablegen(MlnixControlEnums.cpp.inc -gen-enum-defs)
mlir_tablegen(MlnixControlAttrDefs.h.inc -gen-attrdef-decls -attrdefs-dialect=mlnix)
mlir_tablegen(MlnixControlAttrDefs.cpp.inc -gen-attrdef-defs -attrdefs-dialect=mlnix)

# The solver's layers above the nix dialect: SUO-KIF terms, facts and rules (Kif.td), and SUMO's relations (Sumo.td)
set(LLVM_TARGET_DEFINITIONS Kif.td)
mlir_tablegen(Kif.h.inc -gen-op-decls)
mlir_tablegen(Kif.cpp.inc -gen-op-defs)
mlir_tablegen(KifDialect.h.inc -gen-dialect-decls -dialect=kif)
mlir_tablegen(KifDialect.cpp.inc -gen-dialect-defs -dialect=kif)
mlir_tablegen(KifTypes.h.inc -gen-typedef-decls -typedefs-dialect=kif)
mlir_tablegen(KifTypes.cpp.inc -gen-typedef-defs -typedefs-dialect=kif)
set(LLVM_TARGET_DEFINITIONS Sumo.td)
mlir_tablegen(Sumo.h.inc -gen-op-decls)
mlir_tablegen(Sumo.cpp.inc -gen-op-defs)
mlir_tablegen(SumoDialect.h.inc -gen-dialect-decls -dialect=sumo)
mlir_tablegen(SumoDialect.cpp.inc -gen-dialect-defs -dialect=sumo)

set(LLVM_TARGET_DEFINITIONS Son.td)
mlir_tablegen(Son.h.inc -gen-op-decls)
mlir_tablegen(Son.cpp.inc -gen-op-defs)
mlir_tablegen(SonDialect.h.inc -gen-dialect-decls -dialect=son)
mlir_tablegen(SonDialect.cpp.inc -gen-dialect-defs -dialect=son)

add_public_tablegen_target(MLIRNixOpsIncGen)

# The continents' IRDL declaration, embedded in the binary as a raw string
# literal (NixPrimsIRDL.inc); editing the .irdl.mlir re-runs configure.
set(NIX_PRIMS_IRDL_FILE ${CMAKE_CURRENT_SOURCE_DIR}/NixPrims.irdl.mlir)
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${NIX_PRIMS_IRDL_FILE})
file(READ ${NIX_PRIMS_IRDL_FILE} NIX_PRIMS_IRDL_TEXT)
file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/NixPrimsIRDL.inc "R\"IRDL(${NIX_PRIMS_IRDL_TEXT})IRDL\"")
