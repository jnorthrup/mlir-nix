# ffmpeg's output path: about a hundred derivations, the closure asnix (github.com/tomberek/asnix) measures itself on.
{ nixpkgs ? ../.cache/nixpkgs, system ? "x86_64-linux" }:
(import nixpkgs { inherit system; config = { }; overlays = [ ]; }).ffmpeg.outPath
