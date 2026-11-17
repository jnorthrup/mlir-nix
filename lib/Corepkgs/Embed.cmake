# cmake -DOUT=Corepkgs.inc -DDIR=lib/Corepkgs -P Embed.cmake
# Writes one table entry per .nix file of DIR: {"/__corepkgs__/NAME", R"NIX(text)NIX"}, so that the Nix sources
# the evaluator ships (flake.nix) stay Nix files and the binary carries them.
file(GLOB files ${DIR}/*.nix)
list(SORT files)
set(body "")
foreach(f ${files})
  get_filename_component(name ${f} NAME)
  file(READ ${f} text)
  string(APPEND body "{\"/__corepkgs__/${name}\", R\"NIX(${text})NIX\"},\n")
endforeach()
file(WRITE ${OUT} "${body}")
