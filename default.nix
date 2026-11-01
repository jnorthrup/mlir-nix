{ pkgs ? import <nixpkgs> { } }:

# mlnix and mlnix-opt, built with CMake against nixpkgs' LLVM and MLIR.
#   nix-build                       (needs <nixpkgs> on NIX_PATH, or pass pkgs)
#   result/bin/mlnix eval -E '1 + 1'
let
  inherit (pkgs) lib;
  llvm = pkgs.llvmPackages_latest;
in
pkgs.stdenv.mkDerivation {
  pname = "mlnix";
  version = "0.4.0";

  # Build directories and side branches stay out of the source: they change the hash and are not input.
  src = lib.cleanSourceWith {
    src = lib.cleanSource ./.;
    filter = path: type:
      let name = baseNameOf path; in
      !(builtins.elem name [ "build" "build-asan" "build-g" "build-pgo-gen" "build-pgo-use" "tasktrees" ".git" "__pycache__" ".DS_Store" ]);
  };

  nativeBuildInputs = [ pkgs.cmake pkgs.ninja llvm.tblgen ]; # mlir-tblgen runs during the build
  buildInputs = [ llvm.llvm.dev llvm.mlir.dev pkgs.openssl ] ++ lib.optional pkgs.stdenv.isLinux pkgs.liburing;

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
