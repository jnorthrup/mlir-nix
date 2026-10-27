# TrikeShed's kernel as a dialect (TrikeShed.td): the algebra of borg.trikeshed.lib as types and ops, and the columns of
# the Cursors, all generated for the C++ (include/Composite/TrikeShed.h, lib/Composite/TrikeShedDialect.cpp).
set(LLVM_TARGET_DEFINITIONS TrikeShed.td)
mlir_tablegen(TrikeShedDialect.h.inc -gen-dialect-decls -dialect=trikeshed)
mlir_tablegen(TrikeShedDialect.cpp.inc -gen-dialect-defs -dialect=trikeshed)
mlir_tablegen(TrikeShedTypes.h.inc -gen-typedef-decls -typedefs-dialect=trikeshed)
mlir_tablegen(TrikeShedTypes.cpp.inc -gen-typedef-defs -typedefs-dialect=trikeshed)
mlir_tablegen(TrikeShedOps.h.inc -gen-op-decls)
mlir_tablegen(TrikeShedOps.cpp.inc -gen-op-defs)
mlir_tablegen(TrikeShedAttrDefs.h.inc -gen-attrdef-decls -attrdefs-dialect=trikeshed)
mlir_tablegen(TrikeShedAttrDefs.cpp.inc -gen-attrdef-defs -attrdefs-dialect=trikeshed)
mlir_tablegen(TrikeShedEnums.h.inc -gen-enum-decls)
mlir_tablegen(TrikeShedEnums.cpp.inc -gen-enum-defs)
add_public_tablegen_target(TrikeShedIncGen)
