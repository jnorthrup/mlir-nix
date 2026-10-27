{
  description = "mlir-nix: an MLIR-based dialect and evaluator for the Nix expression language";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, nixpkgs }: {
    formatter = builtins.mapAttrs (system: pkgs: pkgs.nixfmt-tree) nixpkgs.legacyPackages;

    packages = builtins.mapAttrs (system: pkgs: {
      default = pkgs.stdenv.mkDerivation {
        pname = "mlir-nix";
        version = "0.1.0";

        src = self;

        nativeBuildInputs = [
          pkgs.cmake
          pkgs.ninja
          pkgs.llvmPackages.tblgen # provides mlir-tblgen on PATH
        ];

        buildInputs = [
          pkgs.llvmPackages.llvm
          pkgs.llvmPackages.mlir
        ];

        cmakeFlags = [
          "-DMLIR_DIR=${pkgs.llvmPackages.mlir.dev}/lib/cmake/mlir"
          "-DCMAKE_BUILD_TYPE=Release"
        ];

        installPhase = ''
          runHook preInstall
          mkdir -p $out/bin
          cp bin/mlnix bin/mlnix-opt $out/bin/
          runHook postInstall
        '';
      };
    }) nixpkgs.legacyPackages;

    devShells = builtins.mapAttrs (system: pkgs: {
      default = pkgs.mkShell {
        nativeBuildInputs = [
          pkgs.cmake
          pkgs.ninja
          pkgs.llvmPackages.tblgen # provides mlir-tblgen on PATH
          pkgs.python3
        ];

        buildInputs = [
          pkgs.llvmPackages.llvm
          pkgs.llvmPackages.mlir
        ];

        MLIR_DIR = "${pkgs.llvmPackages.mlir.dev}/lib/cmake/mlir";
      };
    }) nixpkgs.legacyPackages;
  };
}
