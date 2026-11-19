module {
  // MLIRNix's interface: what other components use, as the compiler's ABI gives it (scripts/cxx-interfaces.py; do not edit).
  
// ── lib/Dialect/KifChase.cpp
  // mlir::kif::dumpClosure(mlir::kif::TheoryOp, llvm::raw_ostream&)
  llvm.func @_ZN4mlir3kif11dumpClosureENS0_8TheoryOpERN4llvm11raw_ostreamE(i64, !llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 48 : i64, llvm.nonnull, llvm.noundef})
  
// ── lib/Dialect/KifDialect.cpp
  // mlir::detail::TypeIDResolver<mlir::kif::KifDialect, void>::id
  llvm.mlir.global external @_ZN4mlir6detail14TypeIDResolverINS_3kif10KifDialectEvE2idE() {addr_space = 0 : i32} : !llvm.struct<"class.mlir::SelfOwningTypeID", (array<8 x i8>)>
  // mlir::detail::TypeIDResolver<mlir::kif::DerivedOp, void>::id
  llvm.mlir.global external @_ZN4mlir6detail14TypeIDResolverINS_3kif9DerivedOpEvE2idE() {addr_space = 0 : i32} : !llvm.struct<"class.mlir::SelfOwningTypeID", (array<8 x i8>)>
  // mlir::detail::TypeIDResolver<mlir::kif::FactOp, void>::id
  llvm.mlir.global external @_ZN4mlir6detail14TypeIDResolverINS_3kif6FactOpEvE2idE() {addr_space = 0 : i32} : !llvm.struct<"class.mlir::SelfOwningTypeID", (array<8 x i8>)>
  // mlir::detail::TypeIDResolver<mlir::kif::RuleOp, void>::id
  llvm.mlir.global external @_ZN4mlir6detail14TypeIDResolverINS_3kif6RuleOpEvE2idE() {addr_space = 0 : i32} : !llvm.struct<"class.mlir::SelfOwningTypeID", (array<8 x i8>)>
  // mlir::detail::TypeIDResolver<mlir::kif::TheoryOp, void>::id
  llvm.mlir.global external @_ZN4mlir6detail14TypeIDResolverINS_3kif8TheoryOpEvE2idE() {addr_space = 0 : i32} : !llvm.struct<"class.mlir::SelfOwningTypeID", (array<8 x i8>)>
  // mlir::kif::TheoryOp::getSymName()
  llvm.func @_ZN4mlir3kif8TheoryOp10getSymNameEv(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 8 : i64, llvm.nocapture, llvm.nonnull, llvm.noundef, llvm.readonly}) -> !llvm.array<2 x i64>
  // mlir::kif::TheoryOp::create(mlir::OpBuilder&, mlir::Location, mlir::StringAttr, mlir::ArrayAttr, mlir::FlatSymbolRefAttr)
  llvm.func @_ZN4mlir3kif8TheoryOp6createERNS_9OpBuilderENS_8LocationENS_10StringAttrENS_9ArrayAttrENS_17FlatSymbolRefAttrE(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 32 : i64, llvm.nonnull, llvm.noundef}, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr) -> i64
  // mlir::kif::registerKifPasses()
  llvm.func @_ZN4mlir3kif17registerKifPassesEv()
  
// ── lib/Dialect/KifImport.cpp
  // mlir::kif::newInterner(mlir::kif::TheoryOp)
  llvm.func @_ZN4mlir3kif11newInternerENS0_8TheoryOpE(i64) -> (!llvm.ptr {llvm.nonnull, llvm.noundef})
  // mlir::kif::freeInterner(mlir::kif::KifInterner*)
  llvm.func @_ZN4mlir3kif12freeInternerEPNS0_11KifInternerE(!llvm.ptr {llvm.noundef})
  // mlir::kif::internCounts(mlir::kif::KifInterner const&, unsigned long&, unsigned long&, unsigned long&)
  llvm.func @_ZN4mlir3kif12internCountsERKNS0_11KifInternerERmS4_S4_(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 224 : i64, llvm.nocapture, llvm.nonnull, llvm.noundef, llvm.readonly}, !llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 8 : i64, llvm.nocapture, llvm.nonnull, llvm.noundef, llvm.writeonly}, !llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 8 : i64, llvm.nocapture, llvm.nonnull, llvm.noundef, llvm.writeonly}, !llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 8 : i64, llvm.nocapture, llvm.nonnull, llvm.noundef, llvm.writeonly})
  // mlir::kif::importKif(mlir::kif::KifInterner&, llvm::StringRef, llvm::StringRef, int)
  llvm.func @_ZN4mlir3kif9importKifERNS0_11KifInternerEN4llvm9StringRefES4_i(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 224 : i64, llvm.nonnull, llvm.noundef}, !llvm.array<2 x i64>, !llvm.array<2 x i64>, i32 {llvm.noundef}) -> i8
  
// ── lib/Dialect/KifLean.cpp
  // mlir::kif::exportLean(mlir::kif::TheoryOp, llvm::raw_ostream&, unsigned int)
  llvm.func @_ZN4mlir3kif10exportLeanENS0_8TheoryOpERN4llvm11raw_ostreamEj(i64, !llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 48 : i64, llvm.nonnull, llvm.noundef}, i32 {llvm.noundef}) -> (i8 {llvm.range = #llvm.constant_range<i8, 0, 2>})
  
// ── lib/Dialect/KifTptp.cpp
  // mlir::kif::exportTptp(mlir::kif::TheoryOp, llvm::raw_ostream&)
  llvm.func @_ZN4mlir3kif10exportTptpENS0_8TheoryOpERN4llvm11raw_ostreamE(i64, !llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 48 : i64, llvm.nonnull, llvm.noundef}) -> (i8 {llvm.noundef})
  
// ── lib/Dialect/NixDialect.cpp
  // mlir::detail::TypeIDResolver<mlir::nix::ValueType, void>::id
  llvm.mlir.global external @_ZN4mlir6detail14TypeIDResolverINS_3nix9ValueTypeEvE2idE() {addr_space = 0 : i32} : !llvm.struct<"class.mlir::SelfOwningTypeID", (array<8 x i8>)>
  // mlir::detail::TypeIDResolver<mlir::nix::AndOp, void>::id
  llvm.mlir.global external @_ZN4mlir6detail14TypeIDResolverINS_3nix5AndOpEvE2idE() {addr_space = 0 : i32} : !llvm.struct<"class.mlir::SelfOwningTypeID", (array<8 x i8>)>
  // mlir::detail::TypeIDResolver<mlir::nix::ApplyOp, void>::id
  llvm.mlir.global external @_ZN4mlir6detail14TypeIDResolverINS_3nix7ApplyOpEvE2idE() {addr_space = 0 : i32} : !llvm.struct<"class.mlir::SelfOwningTypeID", (array<8 x i8>)>
  // mlir::detail::TypeIDResolver<mlir::nix::AssertOp, void>::id
  llvm.mlir.global external @_ZN4mlir6detail14TypeIDResolverINS_3nix8AssertOpEvE2idE() {addr_space = 0 : i32} : !llvm.struct<"class.mlir::SelfOwningTypeID", (array<8 x i8>)>
  // mlir::detail::TypeIDResolver<mlir::nix::AttrsOp, void>::id
  llvm.mlir.global external @_ZN4mlir6detail14TypeIDResolverINS_3nix7AttrsOpEvE2idE() {addr_space = 0 : i32} : !llvm.struct<"class.mlir::SelfOwningTypeID", (array<8 x i8>)>
  // mlir::detail::TypeIDResolver<mlir::nix::BoolOp, void>::id
  llvm.mlir.global external @_ZN4mlir6detail14TypeIDResolverINS_3nix6BoolOpEvE2idE() {addr_space = 0 : i32} : !llvm.struct<"class.mlir::SelfOwningTypeID", (array<8 x i8>)>
  // mlir::detail::TypeIDResolver<mlir::nix::BuiltinOp, void>::id
  llvm.mlir.global external @_ZN4mlir6detail14TypeIDResolverINS_3nix9BuiltinOpEvE2idE() {addr_space = 0 : i32} : !llvm.struct<"class.mlir::SelfOwningTypeID", (array<8 x i8>)>
  // mlir::detail::TypeIDResolver<mlir::nix::ConcatListsOp, void>::id
  llvm.mlir.global external @_ZN4mlir6detail14TypeIDResolverINS_3nix13ConcatListsOpEvE2idE() {addr_space = 0 : i32} : !llvm.struct<"class.mlir::SelfOwningTypeID", (array<8 x i8>)>
  // mlir::detail::TypeIDResolver<mlir::nix::ConcatStringsOp, void>::id
  llvm.mlir.global external @_ZN4mlir6detail14TypeIDResolverINS_3nix15ConcatStringsOpEvE2idE() {addr_space = 0 : i32} : !llvm.struct<"class.mlir::SelfOwningTypeID", (array<8 x i8>)>
  // mlir::detail::TypeIDResolver<mlir::nix::EqOp, void>::id
  llvm.mlir.global external @_ZN4mlir6detail14TypeIDResolverINS_3nix4EqOpEvE2idE() {addr_space = 0 : i32} : !llvm.struct<"class.mlir::SelfOwningTypeID", (array<8 x i8>)>
  // mlir::detail::TypeIDResolver<mlir::nix::ExprOp, void>::id
  llvm.mlir.global external @_ZN4mlir6detail14TypeIDResolverINS_3nix6ExprOpEvE2idE() {addr_space = 0 : i32} : !llvm.struct<"class.mlir::SelfOwningTypeID", (array<8 x i8>)>
  // mlir::detail::TypeIDResolver<mlir::nix::FloatOp, void>::id
  llvm.mlir.global external @_ZN4mlir6detail14TypeIDResolverINS_3nix7FloatOpEvE2idE() {addr_space = 0 : i32} : !llvm.struct<"class.mlir::SelfOwningTypeID", (array<8 x i8>)>
  // mlir::detail::TypeIDResolver<mlir::nix::FormalOp, void>::id
  llvm.mlir.global external @_ZN4mlir6detail14TypeIDResolverINS_3nix8FormalOpEvE2idE() {addr_space = 0 : i32} : !llvm.struct<"class.mlir::SelfOwningTypeID", (array<8 x i8>)>
  // mlir::detail::TypeIDResolver<mlir::nix::HasAttrOp, void>::id
  llvm.mlir.global external @_ZN4mlir6detail14TypeIDResolverINS_3nix9HasAttrOpEvE2idE() {addr_space = 0 : i32} : !llvm.struct<"class.mlir::SelfOwningTypeID", (array<8 x i8>)>
  // mlir::detail::TypeIDResolver<mlir::nix::IfOp, void>::id
  llvm.mlir.global external @_ZN4mlir6detail14TypeIDResolverINS_3nix4IfOpEvE2idE() {addr_space = 0 : i32} : !llvm.struct<"class.mlir::SelfOwningTypeID", (array<8 x i8>)>
  // mlir::detail::TypeIDResolver<mlir::nix::ImplOp, void>::id
  llvm.mlir.global external @_ZN4mlir6detail14TypeIDResolverINS_3nix6ImplOpEvE2idE() {addr_space = 0 : i32} : !llvm.struct<"class.mlir::SelfOwningTypeID", (array<8 x i8>)>
  // mlir::detail::TypeIDResolver<mlir::nix::IntOp, void>::id
  llvm.mlir.global external @_ZN4mlir6detail14TypeIDResolverINS_3nix5IntOpEvE2idE() {addr_space = 0 : i32} : !llvm.struct<"class.mlir::SelfOwningTypeID", (array<8 x i8>)>
  // mlir::detail::TypeIDResolver<mlir::nix::InterpolateOp, void>::id
  llvm.mlir.global external @_ZN4mlir6detail14TypeIDResolverINS_3nix13InterpolateOpEvE2idE() {addr_space = 0 : i32} : !llvm.struct<"class.mlir::SelfOwningTypeID", (array<8 x i8>)>
  // mlir::detail::TypeIDResolver<mlir::nix::LambdaOp, void>::id
  llvm.mlir.global external @_ZN4mlir6detail14TypeIDResolverINS_3nix8LambdaOpEvE2idE() {addr_space = 0 : i32} : !llvm.struct<"class.mlir::SelfOwningTypeID", (array<8 x i8>)>
  // mlir::detail::TypeIDResolver<mlir::nix::ListOp, void>::id
  llvm.mlir.global external @_ZN4mlir6detail14TypeIDResolverINS_3nix6ListOpEvE2idE() {addr_space = 0 : i32} : !llvm.struct<"class.mlir::SelfOwningTypeID", (array<8 x i8>)>
  // mlir::detail::TypeIDResolver<mlir::nix::NeqOp, void>::id
  llvm.mlir.global external @_ZN4mlir6detail14TypeIDResolverINS_3nix5NeqOpEvE2idE() {addr_space = 0 : i32} : !llvm.struct<"class.mlir::SelfOwningTypeID", (array<8 x i8>)>
  // mlir::detail::TypeIDResolver<mlir::nix::NotOp, void>::id
  llvm.mlir.global external @_ZN4mlir6detail14TypeIDResolverINS_3nix5NotOpEvE2idE() {addr_space = 0 : i32} : !llvm.struct<"class.mlir::SelfOwningTypeID", (array<8 x i8>)>
  // mlir::detail::TypeIDResolver<mlir::nix::NullOp, void>::id
  llvm.mlir.global external @_ZN4mlir6detail14TypeIDResolverINS_3nix6NullOpEvE2idE() {addr_space = 0 : i32} : !llvm.struct<"class.mlir::SelfOwningTypeID", (array<8 x i8>)>
  // mlir::detail::TypeIDResolver<mlir::nix::OrOp, void>::id
  llvm.mlir.global external @_ZN4mlir6detail14TypeIDResolverINS_3nix4OrOpEvE2idE() {addr_space = 0 : i32} : !llvm.struct<"class.mlir::SelfOwningTypeID", (array<8 x i8>)>
  // mlir::detail::TypeIDResolver<mlir::nix::PathOp, void>::id
  llvm.mlir.global external @_ZN4mlir6detail14TypeIDResolverINS_3nix6PathOpEvE2idE() {addr_space = 0 : i32} : !llvm.struct<"class.mlir::SelfOwningTypeID", (array<8 x i8>)>
  // mlir::detail::TypeIDResolver<mlir::nix::ReturnOp, void>::id
  llvm.mlir.global external @_ZN4mlir6detail14TypeIDResolverINS_3nix8ReturnOpEvE2idE() {addr_space = 0 : i32} : !llvm.struct<"class.mlir::SelfOwningTypeID", (array<8 x i8>)>
  // mlir::detail::TypeIDResolver<mlir::nix::SelectOp, void>::id
  llvm.mlir.global external @_ZN4mlir6detail14TypeIDResolverINS_3nix8SelectOpEvE2idE() {addr_space = 0 : i32} : !llvm.struct<"class.mlir::SelfOwningTypeID", (array<8 x i8>)>
  // mlir::detail::TypeIDResolver<mlir::nix::StringOp, void>::id
  llvm.mlir.global external @_ZN4mlir6detail14TypeIDResolverINS_3nix8StringOpEvE2idE() {addr_space = 0 : i32} : !llvm.struct<"class.mlir::SelfOwningTypeID", (array<8 x i8>)>
  // mlir::detail::TypeIDResolver<mlir::nix::UpdateOp, void>::id
  llvm.mlir.global external @_ZN4mlir6detail14TypeIDResolverINS_3nix8UpdateOpEvE2idE() {addr_space = 0 : i32} : !llvm.struct<"class.mlir::SelfOwningTypeID", (array<8 x i8>)>
  // mlir::detail::TypeIDResolver<mlir::nix::WithVarOp, void>::id
  llvm.mlir.global external @_ZN4mlir6detail14TypeIDResolverINS_3nix9WithVarOpEvE2idE() {addr_space = 0 : i32} : !llvm.struct<"class.mlir::SelfOwningTypeID", (array<8 x i8>)>
  // mlir::nix::NixEvalOpInterface::eval(nixev::EvalState&, nixev::Frame*, nixev::Value&)
  llvm.func @_ZN4mlir3nix18NixEvalOpInterface4evalERN5nixev9EvalStateEPNS2_5FrameERNS2_5ValueE(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 16 : i64, llvm.nocapture, llvm.nonnull, llvm.noundef, llvm.readonly}, !llvm.ptr {llvm.align = 1 : i64, llvm.nonnull, llvm.noundef}, !llvm.ptr {llvm.noundef}, !llvm.ptr {llvm.align = 1 : i64, llvm.nonnull, llvm.noundef})
  // mlir::nix::stringType(mlir::MLIRContext*)
  llvm.func @_ZN4mlir3nix10stringTypeEPNS_11MLIRContextE(!llvm.ptr {llvm.noundef}) -> i64
  // mlir::nix::isStringType(mlir::Type)
  llvm.func @_ZN4mlir3nix12isStringTypeENS_4TypeE(!llvm.ptr) -> (i1 {llvm.noundef})
  // mlir::nix::fnType(mlir::MLIRContext*)
  llvm.func @_ZN4mlir3nix6fnTypeEPNS_11MLIRContextE(!llvm.ptr {llvm.nonnull, llvm.noundef}) -> i64
  // mlir::nix::isFnType(mlir::Type)
  llvm.func @_ZN4mlir3nix8isFnTypeENS_4TypeE(!llvm.ptr) -> (i1 {llvm.noundef})
  // mlir::nix::AndOp::create(mlir::OpBuilder&, mlir::Location, mlir::Type, mlir::Value, mlir::Value, long)
  llvm.func @_ZN4mlir3nix5AndOp6createERNS_9OpBuilderENS_8LocationENS_4TypeENS_5ValueES6_l(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 32 : i64, llvm.nonnull, llvm.noundef}, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64 {llvm.noundef}) -> i64
  // mlir::nix::ApplyOp::getODSOperandIndexAndLength(unsigned int)
  llvm.func @_ZN4mlir3nix7ApplyOp27getODSOperandIndexAndLengthEj(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 8 : i64, llvm.nocapture, llvm.nonnull, llvm.noundef, llvm.readonly}, i32 {llvm.noundef}) -> i64
  // mlir::nix::ApplyOp::create(mlir::OpBuilder&, mlir::Location, mlir::Type, mlir::Value, mlir::ValueRange, long)
  llvm.func @_ZN4mlir3nix7ApplyOp6createERNS_9OpBuilderENS_8LocationENS_4TypeENS_5ValueENS_10ValueRangeEl(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 32 : i64, llvm.nonnull, llvm.noundef}, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.array<2 x i64>, i64 {llvm.noundef}) -> i64
  // mlir::nix::AssertOp::getText()
  llvm.func @_ZN4mlir3nix8AssertOp7getTextEv(!llvm.ptr {llvm.align = 8 : i64, llvm.noalias, llvm.nocapture, llvm.sret = !llvm.struct<"class.std::optional.236", (struct<"struct.std::_Optional_base.237", (struct<"struct.std::_Optional_payload.239", (struct<"struct.std::_Optional_payload_base.base.241", packed (struct<"union.std::_Optional_payload_base<llvm::StringRef>::_Storage", (struct<"class.llvm::StringRef", (ptr, i64)>)>, i8)>, array<7 x i8>)>)>)>, llvm.writeonly}, !llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 8 : i64, llvm.nocapture, llvm.nonnull, llvm.noundef, llvm.readonly})
  // mlir::nix::AssertOp::create(mlir::OpBuilder&, mlir::Location, mlir::Type, mlir::Value, mlir::Value, mlir::StringAttr, long)
  llvm.func @_ZN4mlir3nix8AssertOp6createERNS_9OpBuilderENS_8LocationENS_4TypeENS_5ValueES6_NS_10StringAttrEl(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 32 : i64, llvm.nonnull, llvm.noundef}, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64, i64 {llvm.noundef}) -> i64
  // mlir::nix::AttrsOp::getODSOperandIndexAndLength(unsigned int)
  llvm.func @_ZN4mlir3nix7AttrsOp27getODSOperandIndexAndLengthEj(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 8 : i64, llvm.nocapture, llvm.nonnull, llvm.noundef, llvm.readonly}, i32 {llvm.noundef}) -> i64
  // mlir::nix::AttrsOp::create(mlir::OpBuilder&, mlir::Location, mlir::Type, llvm::ArrayRef<nixfe::Name>, mlir::ValueRange, mlir::ValueRange, mlir::ValueRange, llvm::ArrayRef<long>, long)
  llvm.func @_ZN4mlir3nix7AttrsOp6createERNS_9OpBuilderENS_8LocationENS_4TypeEN4llvm8ArrayRefIN5nixfe4NameEEENS_10ValueRangeESB_SB_NS7_IlEEl(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 32 : i64, llvm.nonnull, llvm.noundef}, !llvm.ptr, !llvm.ptr, !llvm.array<2 x i64>, !llvm.array<2 x i64>, !llvm.array<2 x i64>, !llvm.array<2 x i64>, !llvm.array<2 x i64>, i64 {llvm.noundef}) -> i64
  // mlir::nix::BoolOp::getValue()
  llvm.func @_ZN4mlir3nix6BoolOp8getValueEv(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 8 : i64, llvm.nocapture, llvm.nonnull, llvm.noundef, llvm.readonly}) -> (i1 {llvm.noundef})
  // mlir::nix::BoolOp::create(mlir::OpBuilder&, mlir::Location, mlir::Type, mlir::BoolAttr)
  llvm.func @_ZN4mlir3nix6BoolOp6createERNS_9OpBuilderENS_8LocationENS_4TypeENS_8BoolAttrE(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 32 : i64, llvm.nonnull, llvm.noundef}, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
  // mlir::nix::BuiltinOp::create(mlir::OpBuilder&, mlir::Location, mlir::Type, nixfe::Name const&)
  llvm.func @_ZN4mlir3nix9BuiltinOp6createERNS_9OpBuilderENS_8LocationENS_4TypeERKN5nixfe4NameE(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 32 : i64, llvm.nonnull, llvm.noundef}, !llvm.ptr, !llvm.ptr, !llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 16 : i64, llvm.nocapture, llvm.nonnull, llvm.noundef, llvm.readonly}) -> i64
  // mlir::nix::ConcatListsOp::create(mlir::OpBuilder&, mlir::Location, mlir::Type, mlir::Value, mlir::Value, long)
  llvm.func @_ZN4mlir3nix13ConcatListsOp6createERNS_9OpBuilderENS_8LocationENS_4TypeENS_5ValueES6_l(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 32 : i64, llvm.nonnull, llvm.noundef}, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64 {llvm.noundef}) -> i64
  // mlir::nix::ConcatStringsOp::create(mlir::OpBuilder&, mlir::Location, mlir::Type, mlir::ValueRange, long)
  llvm.func @_ZN4mlir3nix15ConcatStringsOp6createERNS_9OpBuilderENS_8LocationENS_4TypeENS_10ValueRangeEl(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 32 : i64, llvm.nonnull, llvm.noundef}, !llvm.ptr, !llvm.ptr, !llvm.array<2 x i64>, i64 {llvm.noundef}) -> i64
  // mlir::nix::EqOp::create(mlir::OpBuilder&, mlir::Location, mlir::Type, mlir::Value, mlir::Value, long)
  llvm.func @_ZN4mlir3nix4EqOp6createERNS_9OpBuilderENS_8LocationENS_4TypeENS_5ValueES6_l(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 32 : i64, llvm.nonnull, llvm.noundef}, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64 {llvm.noundef}) -> i64
  // mlir::nix::ExprOp::getSymName()
  llvm.func @_ZN4mlir3nix6ExprOp10getSymNameEv(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 8 : i64, llvm.nocapture, llvm.nonnull, llvm.noundef, llvm.readonly}) -> !llvm.array<2 x i64>
  // mlir::nix::ExprOp::setSymName(llvm::StringRef)
  llvm.func @_ZN4mlir3nix6ExprOp10setSymNameEN4llvm9StringRefE(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 8 : i64, llvm.nocapture, llvm.nonnull, llvm.noundef, llvm.readonly}, !llvm.array<2 x i64>)
  // mlir::nix::ExprOp::create(mlir::OpBuilder&, mlir::Location, mlir::StringAttr, mlir::StringAttr, mlir::StringAttr)
  llvm.func @_ZN4mlir3nix6ExprOp6createERNS_9OpBuilderENS_8LocationENS_10StringAttrES5_S5_(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 32 : i64, llvm.nonnull, llvm.noundef}, !llvm.ptr, i64, i64, i64) -> i64
  // mlir::nix::FloatOp::getValue()
  llvm.func @_ZN4mlir3nix7FloatOp8getValueEv(!llvm.ptr {llvm.align = 8 : i64, llvm.noalias, llvm.sret = !llvm.struct<"class.llvm::APFloat", (struct<"union.llvm::APFloat::Storage", (struct<"class.llvm::detail::DoubleAPFloat", (ptr, ptr)>, array<8 x i8>)>)>}, !llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 8 : i64, llvm.nocapture, llvm.nonnull, llvm.noundef, llvm.readonly})
  // mlir::nix::FloatOp::create(mlir::OpBuilder&, mlir::Location, mlir::Type, mlir::FloatAttr, long)
  llvm.func @_ZN4mlir3nix7FloatOp6createERNS_9OpBuilderENS_8LocationENS_4TypeENS_9FloatAttrEl(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 32 : i64, llvm.nonnull, llvm.noundef}, !llvm.ptr, !llvm.ptr, i64, i64 {llvm.noundef}) -> i64
  // mlir::nix::FormalOp::create(mlir::OpBuilder&, mlir::Location, mlir::Type, mlir::Value, nixfe::Name const&, mlir::Value, long)
  llvm.func @_ZN4mlir3nix8FormalOp6createERNS_9OpBuilderENS_8LocationENS_4TypeENS_5ValueERKN5nixfe4NameES6_l(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 32 : i64, llvm.nonnull, llvm.noundef}, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 16 : i64, llvm.nocapture, llvm.nonnull, llvm.noundef, llvm.readonly}, !llvm.ptr, i64 {llvm.noundef}) -> i64
  // mlir::nix::HasAttrOp::create(mlir::OpBuilder&, mlir::Location, mlir::Type, mlir::Value, mlir::ValueRange, llvm::ArrayRef<nixfe::Name>, long)
  llvm.func @_ZN4mlir3nix9HasAttrOp6createERNS_9OpBuilderENS_8LocationENS_4TypeENS_5ValueENS_10ValueRangeEN4llvm8ArrayRefIN5nixfe4NameEEEl(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 32 : i64, llvm.nonnull, llvm.noundef}, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.array<2 x i64>, !llvm.array<2 x i64>, i64 {llvm.noundef}) -> i64
  // mlir::nix::IfOp::create(mlir::OpBuilder&, mlir::Location, mlir::Type, mlir::Value, mlir::Value, mlir::Value, long)
  llvm.func @_ZN4mlir3nix4IfOp6createERNS_9OpBuilderENS_8LocationENS_4TypeENS_5ValueES6_S6_l(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 32 : i64, llvm.nonnull, llvm.noundef}, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64 {llvm.noundef}) -> i64
  // mlir::nix::ImplOp::create(mlir::OpBuilder&, mlir::Location, mlir::Type, mlir::Value, mlir::Value, long)
  llvm.func @_ZN4mlir3nix6ImplOp6createERNS_9OpBuilderENS_8LocationENS_4TypeENS_5ValueES6_l(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 32 : i64, llvm.nonnull, llvm.noundef}, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64 {llvm.noundef}) -> i64
  // mlir::nix::IntOp::getValue()
  llvm.func @_ZN4mlir3nix5IntOp8getValueEv(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 8 : i64, llvm.nocapture, llvm.nonnull, llvm.noundef, llvm.readonly}) -> (i64 {llvm.noundef})
  // mlir::nix::IntOp::create(mlir::OpBuilder&, mlir::Location, mlir::Type, mlir::IntegerAttr, long)
  llvm.func @_ZN4mlir3nix5IntOp6createERNS_9OpBuilderENS_8LocationENS_4TypeENS_11IntegerAttrEl(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 32 : i64, llvm.nonnull, llvm.noundef}, !llvm.ptr, !llvm.ptr, i64, i64 {llvm.noundef}) -> i64
  // mlir::nix::InterpolateOp::create(mlir::OpBuilder&, mlir::Location, mlir::Type, mlir::ValueRange, long)
  llvm.func @_ZN4mlir3nix13InterpolateOp6createERNS_9OpBuilderENS_8LocationENS_4TypeENS_10ValueRangeEl(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 32 : i64, llvm.nonnull, llvm.noundef}, !llvm.ptr, !llvm.ptr, !llvm.array<2 x i64>, i64 {llvm.noundef}) -> i64
  // mlir::nix::LambdaOp::getODSOperandIndexAndLength(unsigned int)
  llvm.func @_ZN4mlir3nix8LambdaOp27getODSOperandIndexAndLengthEj(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 8 : i64, llvm.nocapture, llvm.nonnull, llvm.noundef, llvm.readonly}, i32 {llvm.noundef}) -> i64
  // mlir::nix::LambdaOp::getFormals()
  llvm.func @_ZN4mlir3nix8LambdaOp10getFormalsEv(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 8 : i64, llvm.nocapture, llvm.nonnull, llvm.noundef, llvm.readonly}) -> !llvm.array<2 x i64>
  // mlir::nix::LambdaOp::getFormalDefaults()
  llvm.func @_ZN4mlir3nix8LambdaOp17getFormalDefaultsEv(!llvm.ptr {llvm.align = 8 : i64, llvm.noalias, llvm.nocapture, llvm.sret = !llvm.struct<"class.std::optional.770", (struct<"struct.std::_Optional_base.771", (struct<"struct.std::_Optional_payload.773", (struct<"struct.std::_Optional_payload_base.base.776", packed (struct<"union.std::_Optional_payload_base<llvm::ArrayRef<bool>>::_Storage", (struct<"class.llvm::ArrayRef.775", (ptr, i64)>)>, i8)>, array<7 x i8>)>)>)>, llvm.writeonly}, !llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 8 : i64, llvm.nocapture, llvm.nonnull, llvm.noundef, llvm.readonly})
  // mlir::nix::LambdaOp::getEllipsis()
  llvm.func @_ZN4mlir3nix8LambdaOp11getEllipsisEv(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 8 : i64, llvm.nocapture, llvm.nonnull, llvm.noundef, llvm.readonly}) -> (i1 {llvm.noundef})
  // mlir::nix::LambdaOp::getArgName()
  llvm.func @_ZN4mlir3nix8LambdaOp10getArgNameEv(!llvm.ptr {llvm.align = 8 : i64, llvm.noalias, llvm.nocapture, llvm.sret = !llvm.struct<"class.std::optional.236", (struct<"struct.std::_Optional_base.237", (struct<"struct.std::_Optional_payload.239", (struct<"struct.std::_Optional_payload_base.base.241", packed (struct<"union.std::_Optional_payload_base<llvm::StringRef>::_Storage", (struct<"class.llvm::StringRef", (ptr, i64)>)>, i8)>, array<7 x i8>)>)>)>, llvm.writeonly}, !llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 8 : i64, llvm.nocapture, llvm.nonnull, llvm.noundef, llvm.readonly})
  // mlir::nix::LambdaOp::getName()
  llvm.func @_ZN4mlir3nix8LambdaOp7getNameEv(!llvm.ptr {llvm.align = 8 : i64, llvm.noalias, llvm.nocapture, llvm.sret = !llvm.struct<"class.std::optional.236", (struct<"struct.std::_Optional_base.237", (struct<"struct.std::_Optional_payload.239", (struct<"struct.std::_Optional_payload_base.base.241", packed (struct<"union.std::_Optional_payload_base<llvm::StringRef>::_Storage", (struct<"class.llvm::StringRef", (ptr, i64)>)>, i8)>, array<7 x i8>)>)>)>, llvm.writeonly}, !llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 8 : i64, llvm.nocapture, llvm.nonnull, llvm.noundef, llvm.readonly})
  // mlir::nix::LambdaOp::getFormalLocs()
  llvm.func @_ZN4mlir3nix8LambdaOp13getFormalLocsEv(!llvm.ptr {llvm.align = 8 : i64, llvm.noalias, llvm.nocapture, llvm.sret = !llvm.struct<"class.std::optional.779", (struct<"struct.std::_Optional_base.780", (struct<"struct.std::_Optional_payload.782", (struct<"struct.std::_Optional_payload_base.base.784", packed (struct<"union.std::_Optional_payload_base<llvm::ArrayRef<long>>::_Storage", (struct<"class.llvm::ArrayRef.312", (ptr, i64)>)>, i8)>, array<7 x i8>)>)>)>, llvm.writeonly}, !llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 8 : i64, llvm.nocapture, llvm.nonnull, llvm.noundef, llvm.readonly})
  // mlir::nix::LambdaOp::create(mlir::OpBuilder&, mlir::Location, mlir::Type, mlir::ArrayAttr, mlir::detail::DenseArrayAttrImpl<bool>, bool, mlir::StringAttr, mlir::StringAttr, mlir::detail::DenseArrayAttrImpl<long>, mlir::ValueRange, mlir::IntegerAttr, long)
  llvm.func @_ZN4mlir3nix8LambdaOp6createERNS_9OpBuilderENS_8LocationENS_4TypeENS_9ArrayAttrENS_6detail18DenseArrayAttrImplIbEEbNS_10StringAttrESA_NS8_IlEENS_10ValueRangeENS_11IntegerAttrEl(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 32 : i64, llvm.nonnull, llvm.noundef}, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64, i1 {llvm.noundef}, i64, i64, i64, !llvm.array<2 x i64>, i64, i64 {llvm.noundef}) -> i64
  // mlir::nix::ListOp::getODSOperandIndexAndLength(unsigned int)
  llvm.func @_ZN4mlir3nix6ListOp27getODSOperandIndexAndLengthEj(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 8 : i64, llvm.nocapture, llvm.nonnull, llvm.noundef, llvm.readonly}, i32 {llvm.noundef}) -> i64
  // mlir::nix::ListOp::create(mlir::OpBuilder&, mlir::Location, mlir::Type, mlir::ValueRange, long)
  llvm.func @_ZN4mlir3nix6ListOp6createERNS_9OpBuilderENS_8LocationENS_4TypeENS_10ValueRangeEl(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 32 : i64, llvm.nonnull, llvm.noundef}, !llvm.ptr, !llvm.ptr, !llvm.array<2 x i64>, i64 {llvm.noundef}) -> i64
  // mlir::nix::NeqOp::create(mlir::OpBuilder&, mlir::Location, mlir::Type, mlir::Value, mlir::Value, long)
  llvm.func @_ZN4mlir3nix5NeqOp6createERNS_9OpBuilderENS_8LocationENS_4TypeENS_5ValueES6_l(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 32 : i64, llvm.nonnull, llvm.noundef}, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64 {llvm.noundef}) -> i64
  // mlir::nix::NotOp::create(mlir::OpBuilder&, mlir::Location, mlir::Type, mlir::Value, long)
  llvm.func @_ZN4mlir3nix5NotOp6createERNS_9OpBuilderENS_8LocationENS_4TypeENS_5ValueEl(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 32 : i64, llvm.nonnull, llvm.noundef}, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64 {llvm.noundef}) -> i64
  // mlir::nix::NullOp::create(mlir::OpBuilder&, mlir::Location, mlir::Type)
  llvm.func @_ZN4mlir3nix6NullOp6createERNS_9OpBuilderENS_8LocationENS_4TypeE(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 32 : i64, llvm.nonnull, llvm.noundef}, !llvm.ptr, !llvm.ptr) -> i64
  // mlir::nix::OrOp::create(mlir::OpBuilder&, mlir::Location, mlir::Type, mlir::Value, mlir::Value, long)
  llvm.func @_ZN4mlir3nix4OrOp6createERNS_9OpBuilderENS_8LocationENS_4TypeENS_5ValueES6_l(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 32 : i64, llvm.nonnull, llvm.noundef}, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64 {llvm.noundef}) -> i64
  // mlir::nix::PathOp::create(mlir::OpBuilder&, mlir::Location, mlir::Type, nixfe::Name const&, long)
  llvm.func @_ZN4mlir3nix6PathOp6createERNS_9OpBuilderENS_8LocationENS_4TypeERKN5nixfe4NameEl(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 32 : i64, llvm.nonnull, llvm.noundef}, !llvm.ptr, !llvm.ptr, !llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 16 : i64, llvm.nocapture, llvm.nonnull, llvm.noundef, llvm.readonly}, i64 {llvm.noundef}) -> i64
  // mlir::nix::ReturnOp::create(mlir::OpBuilder&, mlir::Location, mlir::Value)
  llvm.func @_ZN4mlir3nix8ReturnOp6createERNS_9OpBuilderENS_8LocationENS_5ValueE(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 32 : i64, llvm.nonnull, llvm.noundef}, !llvm.ptr, !llvm.ptr) -> i64
  // mlir::nix::SelectOp::create(mlir::OpBuilder&, mlir::Location, mlir::Type, mlir::Value, mlir::ValueRange, mlir::Value, llvm::ArrayRef<nixfe::Name>, long)
  llvm.func @_ZN4mlir3nix8SelectOp6createERNS_9OpBuilderENS_8LocationENS_4TypeENS_5ValueENS_10ValueRangeES6_N4llvm8ArrayRefIN5nixfe4NameEEEl(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 32 : i64, llvm.nonnull, llvm.noundef}, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.array<2 x i64>, !llvm.ptr, !llvm.array<2 x i64>, i64 {llvm.noundef}) -> i64
  // mlir::nix::StringOp::create(mlir::OpBuilder&, mlir::Location, mlir::Type, nixfe::Name const&, long)
  llvm.func @_ZN4mlir3nix8StringOp6createERNS_9OpBuilderENS_8LocationENS_4TypeERKN5nixfe4NameEl(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 32 : i64, llvm.nonnull, llvm.noundef}, !llvm.ptr, !llvm.ptr, !llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 16 : i64, llvm.nocapture, llvm.nonnull, llvm.noundef, llvm.readonly}, i64 {llvm.noundef}) -> i64
  // mlir::nix::UpdateOp::create(mlir::OpBuilder&, mlir::Location, mlir::Type, mlir::Value, mlir::Value, long)
  llvm.func @_ZN4mlir3nix8UpdateOp6createERNS_9OpBuilderENS_8LocationENS_4TypeENS_5ValueES6_l(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 32 : i64, llvm.nonnull, llvm.noundef}, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64 {llvm.noundef}) -> i64
  // mlir::nix::WithVarOp::create(mlir::OpBuilder&, mlir::Location, mlir::Type, nixfe::Name const&, mlir::ValueRange, long)
  llvm.func @_ZN4mlir3nix9WithVarOp6createERNS_9OpBuilderENS_8LocationENS_4TypeERKN5nixfe4NameENS_10ValueRangeEl(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 32 : i64, llvm.nonnull, llvm.noundef}, !llvm.ptr, !llvm.ptr, !llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 16 : i64, llvm.nocapture, llvm.nonnull, llvm.noundef, llvm.readonly}, !llvm.array<2 x i64>, i64 {llvm.noundef}) -> i64
  // mlir::nix::NixDialect::promotionOf(mlir::Value) const
  llvm.func @_ZNK4mlir3nix10NixDialect11promotionOfENS_5ValueE(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 224 : i64, llvm.nocapture, llvm.nonnull, llvm.noundef, llvm.readonly}, !llvm.ptr) -> (i8 {llvm.noundef, llvm.range = #llvm.constant_range<i8, 0, 7>})
  // mlir::nix::setPos(mlir::Operation*, unsigned long)
  llvm.func @_ZN4mlir3nix6setPosEPNS_9OperationEm(!llvm.ptr {llvm.noundef}, i64 {llvm.noundef})
  // mlir::nix::getPos(mlir::Operation*)
  llvm.func @_ZN4mlir3nix6getPosEPNS_9OperationE(!llvm.ptr {llvm.noundef, llvm.readonly}) -> (i64 {llvm.noundef})
  // mlir::nix::decodePos(void const*)
  llvm.func @_ZN4mlir3nix9decodePosEPKv(!llvm.ptr {llvm.align = 8 : i64, llvm.noalias, llvm.nocapture, llvm.sret = !llvm.struct<"class.std::optional.1167", (struct<"struct.std::_Optional_base.1168", (struct<"struct.std::_Optional_payload.1170", (struct<"struct.std::_Optional_payload_base.base.1172", packed (struct<"union.std::_Optional_payload_base<mlir::nix::SrcPos>::_Storage", (struct<"struct.mlir::nix::SrcPos", (struct<"class.std::basic_string_view", (i64, ptr)>, i32, i32)>)>, i8)>, array<7 x i8>)>)>)>, llvm.writeonly}, !llvm.ptr {llvm.noundef})
  // mlir::nix::devirtualizePrims(mlir::Operation*)
  llvm.func @_ZN4mlir3nix17devirtualizePrimsEPNS_9OperationE(!llvm.ptr {llvm.noundef})
  // mlir::nix::registerNixPasses()
  llvm.func @_ZN4mlir3nix17registerNixPassesEv()
  
// ── lib/Dialect/NixPrimDialects.cpp
  // mlir::nix::registerNixDialects(mlir::DialectRegistry&)
  llvm.func @_ZN4mlir3nix19registerNixDialectsERNS_15DialectRegistryE(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 88 : i64, llvm.nonnull, llvm.noundef})
  // mlir::nix::loadNixDialects(mlir::MLIRContext&)
  llvm.func @_ZN4mlir3nix15loadNixDialectsERNS_11MLIRContextE(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 8 : i64, llvm.nonnull, llvm.noundef})
  
// ── lib/Dialect/SonDialect.cpp
  // mlir::son::forcedOnReturn(mlir::Block&, mlir::nix::NixDialect*, bool)
  llvm.func @_ZN4mlir3son14forcedOnReturnERNS_5BlockEPNS_3nix10NixDialectEb(!llvm.ptr {llvm.align = 8 : i64, llvm.noalias, llvm.sret = !llvm.struct<"struct.mlir::son::ForcedOnReturn", (struct<"class.llvm::DenseSet.293", (struct<"class.llvm::detail::DenseSetImpl.294", (struct<"class.llvm::DenseMap.295", packed (ptr, i32, i32, i32, array<4 x i8>)>)>)>, i8, array<7 x i8>)>}, !llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 72 : i64, llvm.nonnull, llvm.noundef, llvm.readonly}, !llvm.ptr {llvm.noundef}, i1 {llvm.noundef})
  
// ── lib/Dialect/SumoDialect.cpp
  // mlir::detail::TypeIDResolver<mlir::sumo::SumoDialect, void>::id
  llvm.mlir.global external @_ZN4mlir6detail14TypeIDResolverINS_4sumo11SumoDialectEvE2idE() {addr_space = 0 : i32} : !llvm.struct<"class.mlir::SelfOwningTypeID", (array<8 x i8>)>
}
