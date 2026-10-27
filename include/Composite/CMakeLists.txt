# TrikeShed's kernel as a dialect (TrikeShed.td): the columns of the Cursors, generated for the C++
set(LLVM_TARGET_DEFINITIONS TrikeShed.td)
mlir_tablegen(TrikeShedEnums.h.inc -gen-enum-decls)
mlir_tablegen(TrikeShedEnums.cpp.inc -gen-enum-defs)
add_public_tablegen_target(TrikeShedIncGen)
