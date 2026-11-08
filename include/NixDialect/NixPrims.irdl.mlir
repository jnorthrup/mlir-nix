// The Nix primops as dialects, declared in IRDL (https://mlir.llvm.org/docs/Dialects/IRDL/).
//
// This file is the single source of truth for the 'continent' dialects: every op's
// name, arity and result are *structure* (checked by the stock IRDL verifier); the
// attributes on each irdl.operation are the part IRDL cannot express and that
// lib/Dialect/NixPrimDialects.cpp turns into behaviour:
//
//   nix.key   key of the primop in the base environment (`builtins.<name>` is `__<name>`
//             unless it is a global alias)
//   nix.fx    effect class: pure | user (runs user code / traces) | fs (reads files)
//             | env (reads the environment) | store (writes the store) | import
//             "pure" describes memory effects, not permission to speculate:
//             primops may still throw, diverge, or force effectful lazy operands.
//   nix.fold  the primop may be evaluated at compile time on scalar constants
//   nix.strict every operand is forced before the op returns and none is kept (the NixModes of a core op, for a continent op):
//             the evaluator's frameless rule (EvalState::stackFrameOK) reads it
//   nix.first  the operand the primop forces before anything else it does, every time (an op with one strict operand: that one):
//             the evaluator makes that operand's cell evaluated instead of a thunk it would force at once
//   result   `irdl.is <type>` where every result of the primop has one kind (a list, an attribute set, a string, a path);
//             the rest take any kind.  Chosen where Nix fixes the kind and a census of every call in the language suite and the
//             workloads saw only that kind; MLNIX_CHECK_KINDS=1 makes a typed primop that returns another kind an internal error.
//   nix.fresh the result is a newly allocated list / attribute set with observable
//             identity: the op is pure but equal calls must not be merged (a
//             MemAlloc effect on the result, like memref.alloc)
//
// Dialect attributes: nix.scope (6 macro scopes) and nix.continent (the 11 areas the
// 24 dialects were split from) group the dialects; MLNIX_STATS=1 reports the ops of
// real programs per scope, continent and dialect.
//
// Stock tools: stock mlir-opt has no `nix` dialect, so `irdl.base "!nix.value"` does not
// resolve there.  With that constraint relaxed to `irdl.any` the file loads in
// `mlir-opt --irdl-file=` and `mlir-translate --irdl-to-cpp` emits a static C++ dialect
// from it (33k lines; compiles).  The declaration can also be replaced at run time:
// MLNIX_PRIMS_IRDL=other.irdl.mlir (test/mlir/declaration.mlir does this).

// ---- scope val ------------------------------------------------------------
irdl.dialect @nixnum attributes {nix.summary = "Arithmetic and ordering", nix.scope = "val", nix.continent = "nixnum"} {
  irdl.operation @add attributes {nix.key = "__add", nix.fx = "pure", nix.fold, nix.first = 0 : i64} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %o1 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0, a1: %o1)
    irdl.results(r: %r)
  }
  irdl.operation @ceil attributes {nix.key = "__ceil", nix.fx = "pure", nix.fold} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
  irdl.operation @div attributes {nix.key = "__div", nix.fx = "pure", nix.fold, nix.first = 0 : i64} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %o1 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0, a1: %o1)
    irdl.results(r: %r)
  }
  irdl.operation @floor attributes {nix.key = "__floor", nix.fx = "pure", nix.fold} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
  irdl.operation @less_than attributes {nix.key = "__lessThan", nix.fx = "pure", nix.fold, nix.first = 0 : i64} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %o1 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0, a1: %o1)
    irdl.results(r: %r)
  }
  irdl.operation @mul attributes {nix.key = "__mul", nix.fx = "pure", nix.fold, nix.first = 0 : i64} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %o1 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0, a1: %o1)
    irdl.results(r: %r)
  }
  irdl.operation @sub attributes {nix.key = "__sub", nix.fx = "pure", nix.fold, nix.first = 0 : i64} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %o1 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0, a1: %o1)
    irdl.results(r: %r)
  }
}

irdl.dialect @nixbit attributes {nix.summary = "Bit operations", nix.scope = "val", nix.continent = "nixnum"} {
  irdl.operation @and attributes {nix.key = "__bitAnd", nix.fx = "pure", nix.fold} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %o1 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0, a1: %o1)
    irdl.results(r: %r)
  }
  irdl.operation @or attributes {nix.key = "__bitOr", nix.fx = "pure", nix.fold} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %o1 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0, a1: %o1)
    irdl.results(r: %r)
  }
  irdl.operation @xor attributes {nix.key = "__bitXor", nix.fx = "pure", nix.fold} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %o1 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0, a1: %o1)
    irdl.results(r: %r)
  }
}

irdl.dialect @nixty attributes {nix.summary = "Type predicates", nix.scope = "val", nix.continent = "nixty"} {
  irdl.operation @is_attrs attributes {nix.key = "__isAttrs", nix.fx = "pure", nix.fold, nix.strict} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
  irdl.operation @is_bool attributes {nix.key = "__isBool", nix.fx = "pure", nix.fold, nix.strict} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
  irdl.operation @is_float attributes {nix.key = "__isFloat", nix.fx = "pure", nix.fold, nix.strict} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
  irdl.operation @is_function attributes {nix.key = "__isFunction", nix.fx = "pure", nix.fold, nix.strict} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
  irdl.operation @is_int attributes {nix.key = "__isInt", nix.fx = "pure", nix.fold, nix.strict} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
  irdl.operation @is_list attributes {nix.key = "__isList", nix.fx = "pure", nix.fold, nix.strict} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
  irdl.operation @is_null attributes {nix.key = "isNull", nix.fx = "pure", nix.fold, nix.strict} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
  irdl.operation @is_path attributes {nix.key = "__isPath", nix.fx = "pure", nix.fold, nix.strict} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
  irdl.operation @is_string attributes {nix.key = "__isString", nix.fx = "pure", nix.fold, nix.strict} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
}

irdl.dialect @nixrefl attributes {nix.summary = "Reflection: typeOf, functionArgs", nix.scope = "val", nix.continent = "nixty"} {
  irdl.operation @function_args attributes {nix.key = "__functionArgs", nix.fx = "pure", nix.fresh, nix.first = 0 : i64} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.series2<i32, !nix.value>
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
  irdl.operation @type_of attributes {nix.key = "__typeOf", nix.fx = "pure", nix.fold} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.join<!trikeshed.series<i8>, !trikeshed.series<!trikeshed.series<i8>>>
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
}

// ---- scope coll ------------------------------------------------------------
irdl.dialect @nixlist attributes {nix.summary = "Lists: structure and access", nix.scope = "coll", nix.continent = "nixlist"} {
  irdl.operation @concat_lists attributes {nix.key = "__concatLists", nix.fx = "pure", nix.fresh, nix.first = 0 : i64} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.series<!nix.value>
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
  irdl.operation @elem attributes {nix.key = "__elem", nix.fx = "pure", nix.first = 1 : i64} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %o1 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0, a1: %o1)
    irdl.results(r: %r)
  }
  irdl.operation @elem_at attributes {nix.key = "__elemAt", nix.fx = "pure", nix.first = 0 : i64} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %o1 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0, a1: %o1)
    irdl.results(r: %r)
  }
  irdl.operation @head attributes {nix.key = "__head", nix.fx = "pure", nix.first = 0 : i64} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
  irdl.operation @length attributes {nix.key = "__length", nix.fx = "pure", nix.strict} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
  irdl.operation @tail attributes {nix.key = "__tail", nix.fx = "pure", nix.fresh, nix.first = 0 : i64} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.series<!nix.value>
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
}

irdl.dialect @nixlistfn attributes {nix.summary = "Lists: higher-order (run user functions)", nix.scope = "coll", nix.continent = "nixlist"} {
  irdl.operation @all attributes {nix.key = "__all", nix.fx = "user", nix.first = 1 : i64} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %o1 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0, a1: %o1)
    irdl.results(r: %r)
  }
  irdl.operation @any attributes {nix.key = "__any", nix.fx = "user", nix.first = 1 : i64} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %o1 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0, a1: %o1)
    irdl.results(r: %r)
  }
  irdl.operation @concat_map attributes {nix.key = "__concatMap", nix.fx = "user", nix.first = 1 : i64} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %o1 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.series<!nix.value>
    irdl.operands(a0: %o0, a1: %o1)
    irdl.results(r: %r)
  }
  irdl.operation @filter attributes {nix.key = "__filter", nix.fx = "user", nix.first = 1 : i64} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %o1 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.series<!nix.value>
    irdl.operands(a0: %o0, a1: %o1)
    irdl.results(r: %r)
  }
  irdl.operation @foldl_strict attributes {nix.key = "__foldl'", nix.fx = "user", nix.first = 0 : i64} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %o1 = irdl.any_of(%n, %s, %t, %j, %f)
    %o2 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0, a1: %o1, a2: %o2)
    irdl.results(r: %r)
  }
  irdl.operation @gen_list attributes {nix.key = "__genList", nix.fx = "user", nix.first = 1 : i64} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %o1 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.series<!nix.value>
    irdl.operands(a0: %o0, a1: %o1)
    irdl.results(r: %r)
  }
  irdl.operation @generic_closure attributes {nix.key = "__genericClosure", nix.fx = "user", nix.first = 0 : i64} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.series<!nix.value>
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
  irdl.operation @group_by attributes {nix.key = "__groupBy", nix.fx = "user", nix.first = 1 : i64} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %o1 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.series2<i32, !nix.value>
    irdl.operands(a0: %o0, a1: %o1)
    irdl.results(r: %r)
  }
  irdl.operation @map attributes {nix.key = "map", nix.fx = "user", nix.first = 1 : i64} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %o1 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.series<!nix.value>
    irdl.operands(a0: %o0, a1: %o1)
    irdl.results(r: %r)
  }
  irdl.operation @partition attributes {nix.key = "__partition", nix.fx = "user", nix.first = 1 : i64} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %o1 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.series2<i32, !nix.value>
    irdl.operands(a0: %o0, a1: %o1)
    irdl.results(r: %r)
  }
  irdl.operation @sort attributes {nix.key = "__sort", nix.fx = "user", nix.first = 1 : i64} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %o1 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.series<!nix.value>
    irdl.operands(a0: %o0, a1: %o1)
    irdl.results(r: %r)
  }
}

irdl.dialect @nixattr attributes {nix.summary = "Attribute sets: structure and access", nix.scope = "coll", nix.continent = "nixattr"} {
  irdl.operation @attr_names attributes {nix.key = "__attrNames", nix.fx = "pure", nix.fresh, nix.first = 0 : i64} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.series<!nix.value>
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
  irdl.operation @attr_values attributes {nix.key = "__attrValues", nix.fx = "pure", nix.fresh, nix.first = 0 : i64} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.series<!nix.value>
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
  irdl.operation @cat_attrs attributes {nix.key = "__catAttrs", nix.fx = "pure", nix.fresh, nix.first = 0 : i64} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %o1 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.series<!nix.value>
    irdl.operands(a0: %o0, a1: %o1)
    irdl.results(r: %r)
  }
  irdl.operation @get_attr attributes {nix.key = "__getAttr", nix.fx = "pure", nix.first = 0 : i64} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %o1 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0, a1: %o1)
    irdl.results(r: %r)
  }
  irdl.operation @has_attr attributes {nix.key = "__hasAttr", nix.fx = "pure", nix.first = 0 : i64} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %o1 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0, a1: %o1)
    irdl.results(r: %r)
  }
  irdl.operation @intersect_attrs attributes {nix.key = "__intersectAttrs", nix.fx = "pure", nix.fresh, nix.first = 0 : i64} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %o1 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.series2<i32, !nix.value>
    irdl.operands(a0: %o0, a1: %o1)
    irdl.results(r: %r)
  }
  irdl.operation @list_to_attrs attributes {nix.key = "__listToAttrs", nix.fx = "pure", nix.fresh, nix.first = 0 : i64} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.series2<i32, !nix.value>
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
  irdl.operation @remove_attrs attributes {nix.key = "removeAttrs", nix.fx = "pure", nix.fresh, nix.first = 0 : i64} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %o1 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.series2<i32, !nix.value>
    irdl.operands(a0: %o0, a1: %o1)
    irdl.results(r: %r)
  }
  irdl.operation @unsafe_get_attr_pos attributes {nix.key = "__unsafeGetAttrPos", nix.fx = "pure", nix.fresh} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %o1 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0, a1: %o1)
    irdl.results(r: %r)
  }
}

irdl.dialect @nixattrfn attributes {nix.summary = "Attribute sets: higher-order", nix.scope = "coll", nix.continent = "nixattr"} {
  irdl.operation @map_attrs attributes {nix.key = "__mapAttrs", nix.fx = "user", nix.first = 1 : i64} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %o1 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.series2<i32, !nix.value>
    irdl.operands(a0: %o0, a1: %o1)
    irdl.results(r: %r)
  }
  irdl.operation @zip_attrs_with attributes {nix.key = "__zipAttrsWith", nix.fx = "user", nix.first = 1 : i64} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %o1 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.series2<i32, !nix.value>
    irdl.operands(a0: %o0, a1: %o1)
    irdl.results(r: %r)
  }
}

// ---- scope text ------------------------------------------------------------
irdl.dialect @nixstr attributes {nix.summary = "Strings: slicing, replace, coercion", nix.scope = "text", nix.continent = "nixstr"} {
  irdl.operation @concat_strings_sep attributes {nix.key = "__concatStringsSep", nix.fx = "pure", nix.first = 0 : i64} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %o1 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.join<!trikeshed.series<i8>, !trikeshed.series<!trikeshed.series<i8>>>
    irdl.operands(a0: %o0, a1: %o1)
    irdl.results(r: %r)
  }
  irdl.operation @placeholder attributes {nix.key = "placeholder", nix.fx = "pure", nix.fold} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.join<!trikeshed.series<i8>, !trikeshed.series<!trikeshed.series<i8>>>
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
  irdl.operation @replace_strings attributes {nix.key = "__replaceStrings", nix.fx = "pure", nix.first = 0 : i64} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %o1 = irdl.any_of(%n, %s, %t, %j, %f)
    %o2 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.join<!trikeshed.series<i8>, !trikeshed.series<!trikeshed.series<i8>>>
    irdl.operands(a0: %o0, a1: %o1, a2: %o2)
    irdl.results(r: %r)
  }
  irdl.operation @string_length attributes {nix.key = "__stringLength", nix.fx = "pure", nix.fold, nix.strict} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
  irdl.operation @substring attributes {nix.key = "__substring", nix.fx = "pure", nix.fold, nix.first = 0 : i64} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %o1 = irdl.any_of(%n, %s, %t, %j, %f)
    %o2 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.join<!trikeshed.series<i8>, !trikeshed.series<!trikeshed.series<i8>>>
    irdl.operands(a0: %o0, a1: %o1, a2: %o2)
    irdl.results(r: %r)
  }
  irdl.operation @to_string attributes {nix.key = "toString", nix.fx = "pure", nix.fold, nix.first = 0 : i64} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.join<!trikeshed.series<i8>, !trikeshed.series<!trikeshed.series<i8>>>
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
}

irdl.dialect @nixver attributes {nix.summary = "Versions and derivation names", nix.scope = "text", nix.continent = "nixstr"} {
  irdl.operation @compare_versions attributes {nix.key = "__compareVersions", nix.fx = "pure", nix.fold} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %o1 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0, a1: %o1)
    irdl.results(r: %r)
  }
  irdl.operation @parse_drv_name attributes {nix.key = "__parseDrvName", nix.fx = "pure", nix.fresh} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.series2<i32, !nix.value>
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
  irdl.operation @split_version attributes {nix.key = "__splitVersion", nix.fx = "pure", nix.fresh, nix.first = 0 : i64} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.series<!nix.value>
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
}

irdl.dialect @nixre attributes {nix.summary = "Regular expressions: match, split", nix.scope = "text", nix.continent = "nixstr"} {
  irdl.operation @match attributes {nix.key = "__match", nix.fx = "pure", nix.fresh, nix.first = 0 : i64} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %o1 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0, a1: %o1)
    irdl.results(r: %r)
  }
  irdl.operation @split attributes {nix.key = "__split", nix.fx = "pure", nix.fresh, nix.first = 0 : i64} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %o1 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.series<!nix.value>
    irdl.operands(a0: %o0, a1: %o1)
    irdl.results(r: %r)
  }
}

irdl.dialect @nixctx attributes {nix.summary = "String context", nix.scope = "text", nix.continent = "nixctx"} {
  irdl.operation @add_drv_output_dependencies attributes {nix.key = "__addDrvOutputDependencies", nix.fx = "pure"} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.join<!trikeshed.series<i8>, !trikeshed.series<!trikeshed.series<i8>>>
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
  irdl.operation @append_context attributes {nix.key = "__appendContext", nix.fx = "pure"} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %o1 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.join<!trikeshed.series<i8>, !trikeshed.series<!trikeshed.series<i8>>>
    irdl.operands(a0: %o0, a1: %o1)
    irdl.results(r: %r)
  }
  irdl.operation @get_context attributes {nix.key = "__getContext", nix.fx = "pure", nix.fresh} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.series2<i32, !nix.value>
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
  irdl.operation @has_context attributes {nix.key = "__hasContext", nix.fx = "pure", nix.fold} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
  irdl.operation @unsafe_discard_output_dependency attributes {nix.key = "__unsafeDiscardOutputDependency", nix.fx = "pure"} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.join<!trikeshed.series<i8>, !trikeshed.series<!trikeshed.series<i8>>>
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
  irdl.operation @unsafe_discard_string_context attributes {nix.key = "__unsafeDiscardStringContext", nix.fx = "pure"} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.join<!trikeshed.series<i8>, !trikeshed.series<!trikeshed.series<i8>>>
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
}

// ---- scope io ------------------------------------------------------------
irdl.dialect @nixpath attributes {nix.summary = "Paths: pure path manipulation", nix.scope = "io", nix.continent = "nixpath"} {
  irdl.operation @base_name_of attributes {nix.key = "baseNameOf", nix.fx = "pure", nix.first = 0 : i64} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.join<!trikeshed.series<i8>, !trikeshed.series<!trikeshed.series<i8>>>
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
  irdl.operation @dir_of attributes {nix.key = "dirOf", nix.fx = "pure", nix.first = 0 : i64} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
  irdl.operation @to_path attributes {nix.key = "__toPath", nix.fx = "pure"} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.join<!trikeshed.series<i8>, !trikeshed.series<!trikeshed.series<i8>>>
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
}

irdl.dialect @nixfs attributes {nix.summary = "World reads: files and environment", nix.scope = "io", nix.continent = "nixpath"} {
  irdl.operation @find_file attributes {nix.key = "__findFile", nix.fx = "fs"} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %o1 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.series<i8>
    irdl.operands(a0: %o0, a1: %o1)
    irdl.results(r: %r)
  }
  irdl.operation @get_env attributes {nix.key = "__getEnv", nix.fx = "env"} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.join<!trikeshed.series<i8>, !trikeshed.series<!trikeshed.series<i8>>>
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
  irdl.operation @path_exists attributes {nix.key = "__pathExists", nix.fx = "fs", nix.first = 0 : i64} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
  irdl.operation @read_dir attributes {nix.key = "__readDir", nix.fx = "fs", nix.fresh, nix.first = 0 : i64} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.series2<i32, !nix.value>
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
  irdl.operation @read_file attributes {nix.key = "__readFile", nix.fx = "fs", nix.first = 0 : i64} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.join<!trikeshed.series<i8>, !trikeshed.series<!trikeshed.series<i8>>>
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
  irdl.operation @read_file_type attributes {nix.key = "__readFileType", nix.fx = "fs"} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.join<!trikeshed.series<i8>, !trikeshed.series<!trikeshed.series<i8>>>
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
}

irdl.dialect @nixstore attributes {nix.summary = "Store writes: derivations, fetchers, sources", nix.scope = "io", nix.continent = "nixstore"} {
  irdl.operation @derivation_strict attributes {nix.key = "derivationStrict", nix.fx = "store"} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.series2<i32, !nix.value>
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
  irdl.operation @fetch_git attributes {nix.key = "fetchGit", nix.fx = "store"} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
  irdl.operation @fetch_mercurial attributes {nix.key = "fetchMercurial", nix.fx = "store"} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
  irdl.operation @fetch_tarball attributes {nix.key = "fetchTarball", nix.fx = "store"} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
  irdl.operation @fetchurl attributes {nix.key = "__fetchurl", nix.fx = "store"} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
  irdl.operation @filter_source attributes {nix.key = "__filterSource", nix.fx = "store"} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %o1 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.join<!trikeshed.series<i8>, !trikeshed.series<!trikeshed.series<i8>>>
    irdl.operands(a0: %o0, a1: %o1)
    irdl.results(r: %r)
  }
  irdl.operation @path attributes {nix.key = "__path", nix.fx = "store"} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.join<!trikeshed.series<i8>, !trikeshed.series<!trikeshed.series<i8>>>
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
  irdl.operation @store_path attributes {nix.key = "__storePath", nix.fx = "store"} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
  irdl.operation @to_file attributes {nix.key = "__toFile", nix.fx = "store"} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %o1 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.join<!trikeshed.series<i8>, !trikeshed.series<!trikeshed.series<i8>>>
    irdl.operands(a0: %o0, a1: %o1)
    irdl.results(r: %r)
  }
}

irdl.dialect @nixhash attributes {nix.summary = "Hashing", nix.scope = "io", nix.continent = "nixhash"} {
  irdl.operation @convert_hash attributes {nix.key = "__convertHash", nix.fx = "pure"} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.join<!trikeshed.series<i8>, !trikeshed.series<!trikeshed.series<i8>>>
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
  irdl.operation @hash_file attributes {nix.key = "__hashFile", nix.fx = "fs"} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %o1 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.join<!trikeshed.series<i8>, !trikeshed.series<!trikeshed.series<i8>>>
    irdl.operands(a0: %o0, a1: %o1)
    irdl.results(r: %r)
  }
  irdl.operation @hash_string attributes {nix.key = "__hashString", nix.fx = "pure", nix.fold, nix.first = 0 : i64} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %o1 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.join<!trikeshed.series<i8>, !trikeshed.series<!trikeshed.series<i8>>>
    irdl.operands(a0: %o0, a1: %o1)
    irdl.results(r: %r)
  }
}

// ---- scope meta ------------------------------------------------------------
irdl.dialect @nixjson attributes {nix.summary = "JSON", nix.scope = "meta", nix.continent = "nixfmt"} {
  irdl.operation @from_json attributes {nix.key = "__fromJSON", nix.fx = "pure", nix.fresh, nix.first = 0 : i64} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
  irdl.operation @to_json attributes {nix.key = "__toJSON", nix.fx = "store"} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.join<!trikeshed.series<i8>, !trikeshed.series<!trikeshed.series<i8>>>
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
}

irdl.dialect @nixtoml attributes {nix.summary = "TOML", nix.scope = "meta", nix.continent = "nixfmt"} {
  irdl.operation @from_toml attributes {nix.key = "fromTOML", nix.fx = "pure", nix.fresh} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.series2<i32, !nix.value>
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
}

irdl.dialect @nixxml attributes {nix.summary = "XML", nix.scope = "meta", nix.continent = "nixfmt"} {
  irdl.operation @to_xml attributes {nix.key = "__toXML", nix.fx = "store"} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.join<!trikeshed.series<i8>, !trikeshed.series<!trikeshed.series<i8>>>
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
}

irdl.dialect @nixflake attributes {nix.summary = "Flake references", nix.scope = "meta", nix.continent = "nixfmt"} {
  irdl.operation @flake_ref_to_string attributes {nix.key = "__flakeRefToString", nix.fx = "pure"} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.join<!trikeshed.series<i8>, !trikeshed.series<!trikeshed.series<i8>>>
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
  irdl.operation @parse_flake_ref attributes {nix.key = "__parseFlakeRef", nix.fx = "pure", nix.fresh} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.series2<i32, !nix.value>
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
}

// ---- scope ctl ------------------------------------------------------------
irdl.dialect @nixctl attributes {nix.summary = "Evaluation order and recovery", nix.scope = "ctl", nix.continent = "nixctl"} {
  irdl.operation @break attributes {nix.key = "break", nix.fx = "pure"} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
  irdl.operation @deep_seq attributes {nix.key = "__deepSeq", nix.fx = "pure", nix.first = 0 : i64} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %o1 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0, a1: %o1)
    irdl.results(r: %r)
  }
  irdl.operation @seq attributes {nix.key = "__seq", nix.fx = "pure", nix.first = 0 : i64} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %o1 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0, a1: %o1)
    irdl.results(r: %r)
  }
  irdl.operation @try_eval attributes {nix.key = "__tryEval", nix.fx = "pure", nix.fresh} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.is !trikeshed.series2<i32, !nix.value>
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
}

irdl.dialect @nixerr attributes {nix.summary = "Errors and error context", nix.scope = "ctl", nix.continent = "nixctl"} {
  irdl.operation @abort attributes {nix.key = "abort", nix.fx = "pure"} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
  irdl.operation @add_error_context attributes {nix.key = "__addErrorContext", nix.fx = "pure"} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %o1 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0, a1: %o1)
    irdl.results(r: %r)
  }
  irdl.operation @throw attributes {nix.key = "throw", nix.fx = "pure"} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
  irdl.operation @warn attributes {nix.key = "__warn", nix.fx = "user"} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %o1 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0, a1: %o1)
    irdl.results(r: %r)
  }
}

irdl.dialect @nixtrace attributes {nix.summary = "Tracing", nix.scope = "ctl", nix.continent = "nixctl"} {
  irdl.operation @trace attributes {nix.key = "__trace", nix.fx = "user"} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %o1 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0, a1: %o1)
    irdl.results(r: %r)
  }
  irdl.operation @trace_verbose attributes {nix.key = "__traceVerbose", nix.fx = "user"} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %o1 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0, a1: %o1)
    irdl.results(r: %r)
  }
}

irdl.dialect @nixload attributes {nix.summary = "Loading other Nix files", nix.scope = "ctl", nix.continent = "nixctl"} {
  irdl.operation @import attributes {nix.key = "import", nix.fx = "import", nix.first = 0 : i64} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0)
    irdl.results(r: %r)
  }
  irdl.operation @scoped_import attributes {nix.key = "scopedImport", nix.fx = "import"} {
    %n = irdl.base "!nix.value"
    %s = irdl.base "!trikeshed.series"
    %t = irdl.base "!trikeshed.series2"
    %j = irdl.base "!trikeshed.join"
    %f = irdl.base "!builtin.function"
    %o0 = irdl.any_of(%n, %s, %t, %j, %f)
    %o1 = irdl.any_of(%n, %s, %t, %j, %f)
    %r = irdl.any_of(%n, %s, %t, %j, %f)
    irdl.operands(a0: %o0, a1: %o1)
    irdl.results(r: %r)
  }
}
