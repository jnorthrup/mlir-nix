{ pkgs ? import <nixpkgs> { }, llvm ? pkgs.llvmPackages_23 }:

# mlnix and mlnix-opt, built with CMake against nixpkgs' LLVM and MLIR 23.  Not 22: MLIR 22's IRDL loader has no case for an
# `irdl.base` inside an `irdl.any_of` (getBases ends in llvm_unreachable; 23 handles it), and NixPrims.irdl.mlir is made of them, so a
# 22 build loads it only by the luck of its optimizer (nixpkgs' 22.1.8 does not: "any_of constraints are not in the correct form").
#   nix-build                       (needs <nixpkgs> on NIX_PATH, or pass pkgs)
#   nix build                       (flake.nix: the same derivation)
#   result/bin/mlnix eval -E '1 + 1'
let
  inherit (pkgs) lib;
in
llvm.stdenv.mkDerivation {
  pname = "mlnix";
  version = "0.4.0";

  # The checkout's tracked files, as the flake sees them (a flake's ./. is already that tree, copied again under the name "source"
  # so that the path is the same): build directories, .cache and side branches are not input, and nix-build and nix build make the
  # same store path.
  src =
    if builtins.pathExists ./.git then lib.fileset.toSource { root = ./.; fileset = lib.fileset.gitTracked ./.; }
    else builtins.path { path = ./.; name = "source"; };

  # mlir-tblgen runs during the build; mlir-opt, mlir-translate and the stdenv's clang lower and compile the .mlir modules (lowered/,
  # lib/CMakeLists.txt's mlnix_lower_*); opt and llc make the Confix scanner's object.
  nativeBuildInputs = [ pkgs.cmake pkgs.ninja llvm.tblgen llvm.llvm llvm.mlir ];
  buildInputs = [ llvm.llvm.dev llvm.mlir.dev pkgs.openssl ] ++ lib.optional pkgs.stdenv.hostPlatform.isLinux pkgs.liburing;

  cmakeFlags = [
    "-DCMAKE_BUILD_TYPE=Release"
    "-DLLVM_DIR=${llvm.llvm.dev}/lib/cmake/llvm"
    "-DMLIR_DIR=${llvm.mlir.dev}/lib/cmake/mlir"
    "-DMLIR_TABLEGEN_EXE=${llvm.tblgen}/bin/mlir-tblgen" # MLIRConfig.cmake names it without a directory
  ];

  # The two programs; the other targets (query, parse, the C shim) are not part of this package.
  ninjaFlags = [ "mlnix" "mlnix-opt" ];

  installPhase = ''
    runHook preInstall
    install -Dm755 bin/mlnix bin/mlnix-opt -t $out/bin
    runHook postInstall
  '';

  meta.mainProgram = "mlnix";
}
