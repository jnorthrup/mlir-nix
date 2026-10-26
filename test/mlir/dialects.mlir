// Every continent dialect loads, parses and prints; the pipeline is a fixpoint
// of print -> parse.
// RUN: mlnix-opt %s | mlnix-opt | FileCheck %s

// CHECK: nixnum.add(
// CHECK: nixty.is_int(
// CHECK: nixstr.string_length(
// CHECK: nixctx.has_context(
// CHECK: nixlist.length(
// CHECK: nixattr.attr_names(
// CHECK: nixfs.path_exists(
// CHECK: nixstore.to_file(
// CHECK: nixhash.hash_string(
// CHECK: nixjson.to_json(
// CHECK: nixctl.seq(
nix.expr @all {
  %a = nix.int 1
  %s = nix.str "x"
  %l = nix.list []
  %at = nix.attrs [](  )
  %0 = nixnum.add(%a, %a)
  %1 = nixty.is_int(%a)
  %2 = nixstr.string_length(%s)
  %3 = nixctx.has_context(%s)
  %4 = nixlist.length(%l)
  %5 = nixattr.attr_names(%at)
  %6 = nixfs.path_exists(%s)
  %7 = nixstore.to_file(%s, %s)
  %8 = nixhash.hash_string(%s, %s)
  %9 = nixjson.to_json(%a)
  %10 = nixctl.seq(%a, %s)
  nix.return %10
}
