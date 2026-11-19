module {
  // MLIRTrikeShed's interface: what other components use, as the compiler's ABI gives it (scripts/cxx-interfaces.py; do not edit).
  
// ── lib/Composite/ClusterLowering.cpp
  // composite::registerTrikeShedPasses()
  llvm.func @_ZN9composite23registerTrikeShedPassesEv()
  
// ── lib/Composite/CursorLowering.cpp
  // mlir::detail::TypeIDResolver<composite::CursorLoweringInterface, void>::id
  llvm.mlir.global external @_ZN4mlir6detail14TypeIDResolverIN9composite23CursorLoweringInterfaceEvE2idE() {addr_space = 0 : i32} : !llvm.struct<"class.mlir::SelfOwningTypeID", (array<8 x i8>)>
  // composite::newSeriesBuffer(mlir::OpBuilder&, mlir::Location, mlir::Type, mlir::Value)
  llvm.func @_ZN9composite15newSeriesBufferERN4mlir9OpBuilderENS0_8LocationENS0_4TypeENS0_5ValueE(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 32 : i64, llvm.nonnull, llvm.noundef}, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
  
// ── lib/Composite/TrikeShedDialect.cpp
  // mlir::detail::TypeIDResolver<composite::TrikeShedDialect, void>::id
  llvm.mlir.global external @_ZN4mlir6detail14TypeIDResolverIN9composite16TrikeShedDialectEvE2idE() {addr_space = 0 : i32} : !llvm.struct<"class.mlir::SelfOwningTypeID", (array<8 x i8>)>
  // mlir::detail::TypeIDResolver<composite::TwinType, void>::id
  llvm.mlir.global external @_ZN4mlir6detail14TypeIDResolverIN9composite8TwinTypeEvE2idE() {addr_space = 0 : i32} : !llvm.struct<"class.mlir::SelfOwningTypeID", (array<8 x i8>)>
  // mlir::detail::TypeIDResolver<composite::TwinPackedType, void>::id
  llvm.mlir.global external @_ZN4mlir6detail14TypeIDResolverIN9composite14TwinPackedTypeEvE2idE() {addr_space = 0 : i32} : !llvm.struct<"class.mlir::SelfOwningTypeID", (array<8 x i8>)>
  // mlir::detail::TypeIDResolver<composite::SeriesType, void>::id
  llvm.mlir.global external @_ZN4mlir6detail14TypeIDResolverIN9composite10SeriesTypeEvE2idE() {addr_space = 0 : i32} : !llvm.struct<"class.mlir::SelfOwningTypeID", (array<8 x i8>)>
  // mlir::detail::TypeIDResolver<composite::Series2Type, void>::id
  llvm.mlir.global external @_ZN4mlir6detail14TypeIDResolverIN9composite11Series2TypeEvE2idE() {addr_space = 0 : i32} : !llvm.struct<"class.mlir::SelfOwningTypeID", (array<8 x i8>)>
  // mlir::detail::TypeIDResolver<composite::CursorType, void>::id
  llvm.mlir.global external @_ZN4mlir6detail14TypeIDResolverIN9composite10CursorTypeEvE2idE() {addr_space = 0 : i32} : !llvm.struct<"class.mlir::SelfOwningTypeID", (array<8 x i8>)>
  // composite::JoinType::get(mlir::MLIRContext*, mlir::Type, mlir::Type)
  llvm.func @_ZN9composite8JoinType3getEPN4mlir11MLIRContextENS1_4TypeES4_(!llvm.ptr {llvm.nonnull, llvm.noundef}, !llvm.ptr, !llvm.ptr) -> (i64 {llvm.noundef})
  // composite::TwinType::getElement() const
  llvm.func @_ZNK9composite8TwinType10getElementEv(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 8 : i64, llvm.nocapture, llvm.nonnull, llvm.noundef, llvm.readonly}) -> i64
  // composite::TwinPackedType::getElement() const
  llvm.func @_ZNK9composite14TwinPackedType10getElementEv(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 8 : i64, llvm.nocapture, llvm.nonnull, llvm.noundef, llvm.readonly}) -> i64
  // composite::SeriesType::get(mlir::MLIRContext*, mlir::Type)
  llvm.func @_ZN9composite10SeriesType3getEPN4mlir11MLIRContextENS1_4TypeE(!llvm.ptr {llvm.nonnull, llvm.noundef}, !llvm.ptr) -> (i64 {llvm.noundef})
  // composite::SeriesType::getElement() const
  llvm.func @_ZNK9composite10SeriesType10getElementEv(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 8 : i64, llvm.nocapture, llvm.nonnull, llvm.noundef, llvm.readonly}) -> i64
  // composite::Series2Type::get(mlir::MLIRContext*, mlir::Type, mlir::Type)
  llvm.func @_ZN9composite11Series2Type3getEPN4mlir11MLIRContextENS1_4TypeES4_(!llvm.ptr {llvm.nonnull, llvm.noundef}, !llvm.ptr, !llvm.ptr) -> (i64 {llvm.noundef})
  // composite::Series2Type::getA() const
  llvm.func @_ZNK9composite11Series2Type4getAEv(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 8 : i64, llvm.nocapture, llvm.nonnull, llvm.noundef, llvm.readonly}) -> i64
  // composite::Series2Type::getB() const
  llvm.func @_ZNK9composite11Series2Type4getBEv(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 8 : i64, llvm.nocapture, llvm.nonnull, llvm.noundef, llvm.readonly}) -> i64
  // composite::CursorType::getSchema() const
  llvm.func @_ZNK9composite10CursorType9getSchemaEv(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 8 : i64, llvm.nocapture, llvm.nonnull, llvm.noundef, llvm.readonly}) -> i64
  // composite::CursorType::getColumns() const
  llvm.func @_ZNK9composite10CursorType10getColumnsEv(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 8 : i64, llvm.nocapture, llvm.nonnull, llvm.noundef, llvm.readonly}) -> !llvm.array<2 x i64>
  // composite::registerTrikeShedDialect(mlir::DialectRegistry&)
  llvm.func @_ZN9composite24registerTrikeShedDialectERN4mlir15DialectRegistryE(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 88 : i64, llvm.nonnull, llvm.noundef})
}
