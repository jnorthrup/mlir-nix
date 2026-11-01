// The mlnix dialect is the control surface of the utility (include/NixDialect/MlnixControl.td): a session holds the
// settings of one run -- the sea-of-nodes schedule, the pass pipeline, the JIT tier, the prelowering helpers, the
// census -- and the evaluations that run under them.  This test gates it being registered, parsed, printed and
// verified, and that the session names ride with the other dialects of the family.
// RUN: mlnix-opt %s | mlnix-opt | FileCheck %s
// RUN: mlnix-opt --help | FileCheck %s --check-prefix=HELP

// HELP: mlnix

// CHECK-LABEL: mlnix.session @demand
// CHECK-SAME: state_dir = "/tmp/state"
// CHECK-SAME: store_root = "/tmp/root"
mlnix.session @demand attributes {store_root = "/tmp/root", state_dir = "/tmp/state"} {
  // CHECK: mlnix.schedule{{ +}}demand
  mlnix.schedule demand
  // CHECK: mlnix.pipeline "nix-prims,cse"
  mlnix.pipeline "nix-prims,cse"
  // CHECK: mlnix.jit{{ +}}scalar threshold 64 opt 2
  mlnix.jit scalar threshold 64 opt 2
  // CHECK: mlnix.prelower threads 4 list "/tmp/files"
  mlnix.prelower threads 4 list "/tmp/files"
  // CHECK: mlnix.census top 10
  mlnix.census top 10
  // CHECK: mlnix.eval{{ +}}expr "1 + 1" strict output{{ +}}json
  mlnix.eval expr "1 + 1" strict output json
  // CHECK: mlnix.eval{{ +}}file "default.nix"
  mlnix.eval file "default.nix"
}

// A session with no settings keeps the utility's defaults.
// CHECK-LABEL: mlnix.session @bare
mlnix.session @bare {
  // CHECK: mlnix.jit{{ +}}off
  mlnix.jit off
  // CHECK: mlnix.census
  mlnix.census
}
