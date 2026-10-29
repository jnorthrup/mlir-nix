// A memory-pure Nix node can still throw, diverge, or force an effectful thunk.
// Stock LICM must not move those evaluations out of a possibly empty loop.
// Literal construction is total and may move. No Nix-specific pass is involved.
// RUN: mlnix-opt %s -loop-invariant-code-motion | FileCheck %s

// CHECK-LABEL: func.func @speculation
func.func @speculation(%trip: index, %lazy: !nix.value) -> !nix.value {
  %zero = arith.constant 0 : index
  %step = arith.constant 1 : index
  %yes = nix.bool true
  %no = nix.bool false
  %one = nix.int 1
  %max = nix.int 9223372036854775807
  // CHECK: nix.int 7
  // CHECK: nix.path "/tmp/literal"
  // CHECK: scf.for
  %result = scf.for %i = %zero to %trip step %step iter_args(%acc = %one) -> (!nix.value) {
    %literal = nix.int 7
    %path = nix.path "/tmp/literal"
    // Each operand is defined outside the loop: lack of speculation permission
    // is the only reason LICM must retain these operations here.
    // CHECK: nix.assert
    %assert = nix.assert %no in %lazy
    // CHECK: nix.if
    %branch = nix.if %yes then %lazy else %one
    // CHECK: nix.select
    %select = nix.select %lazy ["missing"]
    // CHECK: nix.has_attr
    %has = nix.has_attr %lazy ["missing"]
    // CHECK: nix.with_var
    %with = nix.with_var "missing" in %lazy
    // CHECK: nix.formal
    %formal = nix.formal %lazy "missing"
    // CHECK: nix.builtin "unknown"
    %builtin = nix.builtin "unknown"
    // CHECK: nix.not
    %not = nix.not %lazy
    // CHECK: nix.and
    %and = nix.and %yes, %lazy
    // CHECK: nix.or
    %or = nix.or %no, %lazy
    // CHECK: nix.impl
    %impl = nix.impl %yes, %lazy
    // CHECK: nix.eq
    %eq = nix.eq %lazy, %one
    // CHECK: nix.neq
    %neq = nix.neq %lazy, %one
    // Overflow is a runtime Nix error even though both inputs are constants.
    // CHECK: nix.concat_strings
    %overflow = nix.concat_strings %max, %one
    // Primop "pure" means memory-pure; it is not a totality declaration either.
    // CHECK: nixnum.add
    %add = nixnum.add(%lazy, %one)
    // Fresh identity must also survive speculative motion.
    // CHECK: nix.list
    %fresh = nix.list [%one]
    %all = nix.list [%literal, %path, %assert, %branch, %select, %has, %with,
                    %formal, %builtin, %not, %and, %or, %impl, %eq, %neq,
                    %overflow, %add, %fresh]
    // CHECK: scf.yield
    scf.yield %all : !nix.value
  }
  return %result : !nix.value
}
