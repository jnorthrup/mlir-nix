module {
  // NixFrontend's interface: what other components use, as the compiler's ABI gives it (scripts/cxx-interfaces.py; do not edit).
  
// ── lib/Frontend/Confix.cpp
  // nixfe::confix::scan(std::basic_string_view<char, std::char_traits<char>>, nixfe::confix::Bands&)
  llvm.func @_ZN5nixfe6confix4scanESt17basic_string_viewIcSt11char_traitsIcEERNS0_5BandsE(!llvm.array<2 x i64>, !llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 136 : i64, llvm.nonnull, llvm.noundef}) -> (i1 {llvm.noundef})
  // nixfe::confix::stringifyBandCol(nixfe::confix::BandCol)
  llvm.func @_ZN5nixfe6confix16stringifyBandColENS0_7BandColE(i32 {llvm.noundef}) -> !llvm.array<2 x i64>
  // nixfe::stringifyPoolCol(nixfe::PoolCol)
  llvm.func @_ZN5nixfe16stringifyPoolColENS_7PoolColE(i32 {llvm.noundef}) -> !llvm.array<2 x i64>
  
// ── lib/Frontend/Parser.cpp
  // nixfe::canonPath(std::basic_string_view<char, std::char_traits<char>>)
  llvm.func @_ZN5nixfe9canonPathESt17basic_string_viewIcSt11char_traitsIcEE(!llvm.ptr {llvm.align = 8 : i64, llvm.noalias, llvm.nonnull, llvm.sret = !llvm.struct<"struct.composite::Text", (struct<"struct.composite::MutableSeries", (struct<"struct.composite::Growable", (ptr, i32, i32)>)>)>}, !llvm.array<2 x i64>)
  // nixfe::genExpr(mlir::ModuleOp, nixfe::Origin*, nixfe::ParseOptions const&, llvm::StringRef, nixfe::GenOptions const&)
  llvm.func @_ZN5nixfe7genExprEN4mlir8ModuleOpEPNS_6OriginERKNS_12ParseOptionsEN4llvm9StringRefERKNS_10GenOptionsE(i64, !llvm.ptr {llvm.noundef}, !llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 40 : i64, llvm.nonnull, llvm.noundef}, !llvm.array<2 x i64>, !llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 48 : i64, llvm.nonnull, llvm.noundef}) -> i64
  // nixfe::mintBody(mlir::nix::LambdaOp, nixfe::FilePool&, unsigned int, nixfe::GenOptions const&)
  llvm.func @_ZN5nixfe8mintBodyEN4mlir3nix8LambdaOpERNS_8FilePoolEjRKNS_10GenOptionsE(i64, !llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 400 : i64, llvm.nonnull, llvm.noundef}, i32 {llvm.noundef}, !llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 48 : i64, llvm.nonnull, llvm.noundef})
  // nixfe::showSource(composite::Text&, nixfe::Origin*, nixfe::ParseOptions const&)
  llvm.func @_ZN5nixfe10showSourceERN9composite4TextEPNS_6OriginERKNS_12ParseOptionsE(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 16 : i64, llvm.nonnull, llvm.noundef}, !llvm.ptr {llvm.noundef}, !llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 40 : i64, llvm.nonnull, llvm.noundef})
  // nixfe::skim(nixfe::Origin*, nixfe::ParseOptions const&)
  llvm.func @_ZN5nixfe4skimEPNS_6OriginERKNS_12ParseOptionsE(!llvm.ptr {llvm.noundef}, !llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 40 : i64, llvm.nonnull, llvm.noundef})
  // nixfe::confix::lexBands(nixfe::Origin*, nixfe::ParseOptions const&, nixfe::confix::Bands&)
  llvm.func @_ZN5nixfe6confix8lexBandsEPNS_6OriginERKNS_12ParseOptionsERNS0_5BandsE(!llvm.ptr {llvm.noundef}, !llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 40 : i64, llvm.nonnull, llvm.noundef}, !llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 136 : i64, llvm.nonnull, llvm.noundef}) -> (i1 {llvm.noundef})
  
// ── lib/Frontend/Source.cpp
  // nixfe::newOrigin()
  llvm.func @_ZN5nixfe9newOriginEv() -> (!llvm.ptr {llvm.nonnull, llvm.noundef})
  // nixfe::Source::fromString(composite::Text)
  llvm.func @_ZN5nixfe6Source10fromStringEN9composite4TextE(!llvm.ptr {llvm.noundef}) -> (!llvm.ptr {llvm.nonnull, llvm.noundef})
  // nixfe::Source::mapFile(std::basic_string_view<char, std::char_traits<char>>)
  llvm.func @_ZN5nixfe6Source7mapFileESt17basic_string_viewIcSt11char_traitsIcEE(!llvm.array<2 x i64>) -> (!llvm.ptr {llvm.noundef})
  // nixfe::printLiteralString(composite::Text&, std::basic_string_view<char, std::char_traits<char>>)
  llvm.func @_ZN5nixfe18printLiteralStringERN9composite4TextESt17basic_string_viewIcSt11char_traitsIcEE(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 16 : i64, llvm.nonnull, llvm.noundef}, !llvm.array<2 x i64>)
  // nixfe::printFloat(composite::Text&, double)
  llvm.func @_ZN5nixfe10printFloatERN9composite4TextEd(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 16 : i64, llvm.nonnull, llvm.noundef}, f64 {llvm.noundef})
  // nixfe::fixedFloat(double)
  llvm.func @_ZN5nixfe10fixedFloatEd(!llvm.ptr {llvm.align = 8 : i64, llvm.noalias, llvm.sret = !llvm.struct<"struct.composite::Text", (struct<"struct.composite::MutableSeries.0", (struct<"struct.composite::Growable.1", (ptr, i32, i32)>)>)>}, f64 {llvm.noundef})
  // nixfe::isValidIdentifier(std::basic_string_view<char, std::char_traits<char>>)
  llvm.func @_ZN5nixfe17isValidIdentifierESt17basic_string_viewIcSt11char_traitsIcEE(!llvm.array<2 x i64>) -> (i1 {llvm.noundef})
  // nixfe::printIdentifier(composite::Text&, std::basic_string_view<char, std::char_traits<char>>)
  llvm.func @_ZN5nixfe15printIdentifierERN9composite4TextESt17basic_string_viewIcSt11char_traitsIcEE(!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 16 : i64, llvm.nonnull, llvm.noundef}, !llvm.array<2 x i64>)
}
