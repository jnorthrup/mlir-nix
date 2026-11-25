{
  description = "mlir-nix: an MLIR-based dialect and evaluator for the Nix expression language";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  # The package is default.nix's derivation, so `nix build` and `nix-build` make the same mlnix.
  outputs = { self, nixpkgs }: {
    formatter = builtins.mapAttrs (system: pkgs: pkgs.nixfmt-tree) nixpkgs.legacyPackages;

    packages = builtins.mapAttrs (system: pkgs: {
      default = import ./default.nix { inherit pkgs; };
    }) nixpkgs.legacyPackages;

    # The package's inputs and its compiler (LLVM 23's clang: the build compiles the lowered LLVM IR with it), plus python3 for
    # scripts/.
    devShells = builtins.mapAttrs (system: pkgs: {
      default = (pkgs.mkShell.override { stdenv = pkgs.llvmPackages_23.stdenv; }) {
        inputsFrom = [ self.packages.${system}.default ];
        packages = [ pkgs.python3 ];
        MLIR_DIR = "${pkgs.llvmPackages_23.mlir.dev}/lib/cmake/mlir";
      };
    }) nixpkgs.legacyPackages;
  };
}
