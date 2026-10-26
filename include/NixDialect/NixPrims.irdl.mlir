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
//   nix.fold  the primop may be evaluated at compile time on scalar constants
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
  irdl.operation @add attributes {nix.key = "__add", nix.fx = "pure", nix.fold} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v, a1: %v)
    irdl.results(r: %v)
  }
  irdl.operation @ceil attributes {nix.key = "__ceil", nix.fx = "pure", nix.fold} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
  irdl.operation @div attributes {nix.key = "__div", nix.fx = "pure", nix.fold} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v, a1: %v)
    irdl.results(r: %v)
  }
  irdl.operation @floor attributes {nix.key = "__floor", nix.fx = "pure", nix.fold} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
  irdl.operation @less_than attributes {nix.key = "__lessThan", nix.fx = "pure", nix.fold} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v, a1: %v)
    irdl.results(r: %v)
  }
  irdl.operation @mul attributes {nix.key = "__mul", nix.fx = "pure", nix.fold} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v, a1: %v)
    irdl.results(r: %v)
  }
  irdl.operation @sub attributes {nix.key = "__sub", nix.fx = "pure", nix.fold} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v, a1: %v)
    irdl.results(r: %v)
  }
}

irdl.dialect @nixbit attributes {nix.summary = "Bit operations", nix.scope = "val", nix.continent = "nixnum"} {
  irdl.operation @and attributes {nix.key = "__bitAnd", nix.fx = "pure", nix.fold} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v, a1: %v)
    irdl.results(r: %v)
  }
  irdl.operation @or attributes {nix.key = "__bitOr", nix.fx = "pure", nix.fold} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v, a1: %v)
    irdl.results(r: %v)
  }
  irdl.operation @xor attributes {nix.key = "__bitXor", nix.fx = "pure", nix.fold} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v, a1: %v)
    irdl.results(r: %v)
  }
}

irdl.dialect @nixty attributes {nix.summary = "Type predicates", nix.scope = "val", nix.continent = "nixty"} {
  irdl.operation @is_attrs attributes {nix.key = "__isAttrs", nix.fx = "pure", nix.fold} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
  irdl.operation @is_bool attributes {nix.key = "__isBool", nix.fx = "pure", nix.fold} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
  irdl.operation @is_float attributes {nix.key = "__isFloat", nix.fx = "pure", nix.fold} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
  irdl.operation @is_function attributes {nix.key = "__isFunction", nix.fx = "pure", nix.fold} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
  irdl.operation @is_int attributes {nix.key = "__isInt", nix.fx = "pure", nix.fold} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
  irdl.operation @is_list attributes {nix.key = "__isList", nix.fx = "pure", nix.fold} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
  irdl.operation @is_null attributes {nix.key = "isNull", nix.fx = "pure", nix.fold} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
  irdl.operation @is_path attributes {nix.key = "__isPath", nix.fx = "pure", nix.fold} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
  irdl.operation @is_string attributes {nix.key = "__isString", nix.fx = "pure", nix.fold} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
}

irdl.dialect @nixrefl attributes {nix.summary = "Reflection: typeOf, functionArgs", nix.scope = "val", nix.continent = "nixty"} {
  irdl.operation @function_args attributes {nix.key = "__functionArgs", nix.fx = "pure"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
  irdl.operation @type_of attributes {nix.key = "__typeOf", nix.fx = "pure", nix.fold} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
}

// ---- scope coll ------------------------------------------------------------
irdl.dialect @nixlist attributes {nix.summary = "Lists: structure and access", nix.scope = "coll", nix.continent = "nixlist"} {
  irdl.operation @concat_lists attributes {nix.key = "__concatLists", nix.fx = "pure"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
  irdl.operation @elem attributes {nix.key = "__elem", nix.fx = "pure"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v, a1: %v)
    irdl.results(r: %v)
  }
  irdl.operation @elem_at attributes {nix.key = "__elemAt", nix.fx = "pure"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v, a1: %v)
    irdl.results(r: %v)
  }
  irdl.operation @head attributes {nix.key = "__head", nix.fx = "pure"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
  irdl.operation @length attributes {nix.key = "__length", nix.fx = "pure"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
  irdl.operation @tail attributes {nix.key = "__tail", nix.fx = "pure"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
}

irdl.dialect @nixlistfn attributes {nix.summary = "Lists: higher-order (run user functions)", nix.scope = "coll", nix.continent = "nixlist"} {
  irdl.operation @all attributes {nix.key = "__all", nix.fx = "user"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v, a1: %v)
    irdl.results(r: %v)
  }
  irdl.operation @any attributes {nix.key = "__any", nix.fx = "user"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v, a1: %v)
    irdl.results(r: %v)
  }
  irdl.operation @concat_map attributes {nix.key = "__concatMap", nix.fx = "user"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v, a1: %v)
    irdl.results(r: %v)
  }
  irdl.operation @filter attributes {nix.key = "__filter", nix.fx = "user"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v, a1: %v)
    irdl.results(r: %v)
  }
  irdl.operation @foldl_strict attributes {nix.key = "__foldl'", nix.fx = "user"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v, a1: %v, a2: %v)
    irdl.results(r: %v)
  }
  irdl.operation @gen_list attributes {nix.key = "__genList", nix.fx = "user"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v, a1: %v)
    irdl.results(r: %v)
  }
  irdl.operation @generic_closure attributes {nix.key = "__genericClosure", nix.fx = "user"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
  irdl.operation @group_by attributes {nix.key = "__groupBy", nix.fx = "user"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v, a1: %v)
    irdl.results(r: %v)
  }
  irdl.operation @map attributes {nix.key = "map", nix.fx = "user"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v, a1: %v)
    irdl.results(r: %v)
  }
  irdl.operation @partition attributes {nix.key = "__partition", nix.fx = "user"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v, a1: %v)
    irdl.results(r: %v)
  }
  irdl.operation @sort attributes {nix.key = "__sort", nix.fx = "user"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v, a1: %v)
    irdl.results(r: %v)
  }
}

irdl.dialect @nixattr attributes {nix.summary = "Attribute sets: structure and access", nix.scope = "coll", nix.continent = "nixattr"} {
  irdl.operation @attr_names attributes {nix.key = "__attrNames", nix.fx = "pure"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
  irdl.operation @attr_values attributes {nix.key = "__attrValues", nix.fx = "pure"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
  irdl.operation @cat_attrs attributes {nix.key = "__catAttrs", nix.fx = "pure"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v, a1: %v)
    irdl.results(r: %v)
  }
  irdl.operation @get_attr attributes {nix.key = "__getAttr", nix.fx = "pure"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v, a1: %v)
    irdl.results(r: %v)
  }
  irdl.operation @has_attr attributes {nix.key = "__hasAttr", nix.fx = "pure"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v, a1: %v)
    irdl.results(r: %v)
  }
  irdl.operation @intersect_attrs attributes {nix.key = "__intersectAttrs", nix.fx = "pure"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v, a1: %v)
    irdl.results(r: %v)
  }
  irdl.operation @list_to_attrs attributes {nix.key = "__listToAttrs", nix.fx = "pure"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
  irdl.operation @remove_attrs attributes {nix.key = "removeAttrs", nix.fx = "pure"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v, a1: %v)
    irdl.results(r: %v)
  }
  irdl.operation @unsafe_get_attr_pos attributes {nix.key = "__unsafeGetAttrPos", nix.fx = "pure"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v, a1: %v)
    irdl.results(r: %v)
  }
}

irdl.dialect @nixattrfn attributes {nix.summary = "Attribute sets: higher-order", nix.scope = "coll", nix.continent = "nixattr"} {
  irdl.operation @map_attrs attributes {nix.key = "__mapAttrs", nix.fx = "user"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v, a1: %v)
    irdl.results(r: %v)
  }
  irdl.operation @zip_attrs_with attributes {nix.key = "__zipAttrsWith", nix.fx = "user"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v, a1: %v)
    irdl.results(r: %v)
  }
}

// ---- scope text ------------------------------------------------------------
irdl.dialect @nixstr attributes {nix.summary = "Strings: slicing, replace, coercion", nix.scope = "text", nix.continent = "nixstr"} {
  irdl.operation @concat_strings_sep attributes {nix.key = "__concatStringsSep", nix.fx = "pure"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v, a1: %v)
    irdl.results(r: %v)
  }
  irdl.operation @placeholder attributes {nix.key = "placeholder", nix.fx = "pure", nix.fold} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
  irdl.operation @replace_strings attributes {nix.key = "__replaceStrings", nix.fx = "pure"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v, a1: %v, a2: %v)
    irdl.results(r: %v)
  }
  irdl.operation @string_length attributes {nix.key = "__stringLength", nix.fx = "pure", nix.fold} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
  irdl.operation @substring attributes {nix.key = "__substring", nix.fx = "pure", nix.fold} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v, a1: %v, a2: %v)
    irdl.results(r: %v)
  }
  irdl.operation @to_string attributes {nix.key = "toString", nix.fx = "pure", nix.fold} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
}

irdl.dialect @nixver attributes {nix.summary = "Versions and derivation names", nix.scope = "text", nix.continent = "nixstr"} {
  irdl.operation @compare_versions attributes {nix.key = "__compareVersions", nix.fx = "pure", nix.fold} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v, a1: %v)
    irdl.results(r: %v)
  }
  irdl.operation @parse_drv_name attributes {nix.key = "__parseDrvName", nix.fx = "pure"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
  irdl.operation @split_version attributes {nix.key = "__splitVersion", nix.fx = "pure"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
}

irdl.dialect @nixre attributes {nix.summary = "Regular expressions: match, split", nix.scope = "text", nix.continent = "nixstr"} {
  irdl.operation @match attributes {nix.key = "__match", nix.fx = "pure"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v, a1: %v)
    irdl.results(r: %v)
  }
  irdl.operation @split attributes {nix.key = "__split", nix.fx = "pure"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v, a1: %v)
    irdl.results(r: %v)
  }
}

irdl.dialect @nixctx attributes {nix.summary = "String context", nix.scope = "text", nix.continent = "nixctx"} {
  irdl.operation @add_drv_output_dependencies attributes {nix.key = "__addDrvOutputDependencies", nix.fx = "pure"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
  irdl.operation @append_context attributes {nix.key = "__appendContext", nix.fx = "pure"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v, a1: %v)
    irdl.results(r: %v)
  }
  irdl.operation @get_context attributes {nix.key = "__getContext", nix.fx = "pure"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
  irdl.operation @has_context attributes {nix.key = "__hasContext", nix.fx = "pure", nix.fold} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
  irdl.operation @unsafe_discard_output_dependency attributes {nix.key = "__unsafeDiscardOutputDependency", nix.fx = "pure"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
  irdl.operation @unsafe_discard_string_context attributes {nix.key = "__unsafeDiscardStringContext", nix.fx = "pure"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
}

// ---- scope io ------------------------------------------------------------
irdl.dialect @nixpath attributes {nix.summary = "Paths: pure path manipulation", nix.scope = "io", nix.continent = "nixpath"} {
  irdl.operation @base_name_of attributes {nix.key = "baseNameOf", nix.fx = "pure"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
  irdl.operation @dir_of attributes {nix.key = "dirOf", nix.fx = "pure"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
  irdl.operation @to_path attributes {nix.key = "__toPath", nix.fx = "pure"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
}

irdl.dialect @nixfs attributes {nix.summary = "World reads: files and environment", nix.scope = "io", nix.continent = "nixpath"} {
  irdl.operation @find_file attributes {nix.key = "__findFile", nix.fx = "fs"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v, a1: %v)
    irdl.results(r: %v)
  }
  irdl.operation @get_env attributes {nix.key = "__getEnv", nix.fx = "env"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
  irdl.operation @path_exists attributes {nix.key = "__pathExists", nix.fx = "fs"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
  irdl.operation @read_dir attributes {nix.key = "__readDir", nix.fx = "fs"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
  irdl.operation @read_file attributes {nix.key = "__readFile", nix.fx = "fs"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
  irdl.operation @read_file_type attributes {nix.key = "__readFileType", nix.fx = "fs"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
}

irdl.dialect @nixstore attributes {nix.summary = "Store writes: derivations, fetchers, sources", nix.scope = "io", nix.continent = "nixstore"} {
  irdl.operation @derivation_strict attributes {nix.key = "derivationStrict", nix.fx = "store"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
  irdl.operation @fetch_git attributes {nix.key = "fetchGit", nix.fx = "store"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
  irdl.operation @fetch_mercurial attributes {nix.key = "fetchMercurial", nix.fx = "store"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
  irdl.operation @fetch_tarball attributes {nix.key = "fetchTarball", nix.fx = "store"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
  irdl.operation @fetchurl attributes {nix.key = "__fetchurl", nix.fx = "store"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
  irdl.operation @filter_source attributes {nix.key = "__filterSource", nix.fx = "store"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v, a1: %v)
    irdl.results(r: %v)
  }
  irdl.operation @path attributes {nix.key = "__path", nix.fx = "store"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
  irdl.operation @store_path attributes {nix.key = "__storePath", nix.fx = "store"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
  irdl.operation @to_file attributes {nix.key = "__toFile", nix.fx = "store"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v, a1: %v)
    irdl.results(r: %v)
  }
}

irdl.dialect @nixhash attributes {nix.summary = "Hashing", nix.scope = "io", nix.continent = "nixhash"} {
  irdl.operation @convert_hash attributes {nix.key = "__convertHash", nix.fx = "pure"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
  irdl.operation @hash_file attributes {nix.key = "__hashFile", nix.fx = "fs"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v, a1: %v)
    irdl.results(r: %v)
  }
  irdl.operation @hash_string attributes {nix.key = "__hashString", nix.fx = "pure", nix.fold} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v, a1: %v)
    irdl.results(r: %v)
  }
}

// ---- scope meta ------------------------------------------------------------
irdl.dialect @nixjson attributes {nix.summary = "JSON", nix.scope = "meta", nix.continent = "nixfmt"} {
  irdl.operation @from_json attributes {nix.key = "__fromJSON", nix.fx = "pure"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
  irdl.operation @to_json attributes {nix.key = "__toJSON", nix.fx = "store"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
}

irdl.dialect @nixtoml attributes {nix.summary = "TOML", nix.scope = "meta", nix.continent = "nixfmt"} {
  irdl.operation @from_toml attributes {nix.key = "fromTOML", nix.fx = "pure"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
}

irdl.dialect @nixxml attributes {nix.summary = "XML", nix.scope = "meta", nix.continent = "nixfmt"} {
  irdl.operation @to_xml attributes {nix.key = "__toXML", nix.fx = "store"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
}

irdl.dialect @nixflake attributes {nix.summary = "Flake references", nix.scope = "meta", nix.continent = "nixfmt"} {
  irdl.operation @flake_ref_to_string attributes {nix.key = "__flakeRefToString", nix.fx = "pure"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
  irdl.operation @parse_flake_ref attributes {nix.key = "__parseFlakeRef", nix.fx = "pure"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
}

// ---- scope ctl ------------------------------------------------------------
irdl.dialect @nixctl attributes {nix.summary = "Evaluation order and recovery", nix.scope = "ctl", nix.continent = "nixctl"} {
  irdl.operation @break attributes {nix.key = "break", nix.fx = "pure"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
  irdl.operation @deep_seq attributes {nix.key = "__deepSeq", nix.fx = "pure"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v, a1: %v)
    irdl.results(r: %v)
  }
  irdl.operation @seq attributes {nix.key = "__seq", nix.fx = "pure"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v, a1: %v)
    irdl.results(r: %v)
  }
  irdl.operation @try_eval attributes {nix.key = "__tryEval", nix.fx = "pure"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
}

irdl.dialect @nixerr attributes {nix.summary = "Errors and error context", nix.scope = "ctl", nix.continent = "nixctl"} {
  irdl.operation @abort attributes {nix.key = "abort", nix.fx = "pure"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
  irdl.operation @add_error_context attributes {nix.key = "__addErrorContext", nix.fx = "pure"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v, a1: %v)
    irdl.results(r: %v)
  }
  irdl.operation @throw attributes {nix.key = "throw", nix.fx = "pure"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
  irdl.operation @warn attributes {nix.key = "__warn", nix.fx = "user"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v, a1: %v)
    irdl.results(r: %v)
  }
}

irdl.dialect @nixtrace attributes {nix.summary = "Tracing", nix.scope = "ctl", nix.continent = "nixctl"} {
  irdl.operation @trace attributes {nix.key = "__trace", nix.fx = "user"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v, a1: %v)
    irdl.results(r: %v)
  }
  irdl.operation @trace_verbose attributes {nix.key = "__traceVerbose", nix.fx = "user"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v, a1: %v)
    irdl.results(r: %v)
  }
}

irdl.dialect @nixload attributes {nix.summary = "Loading other Nix files", nix.scope = "ctl", nix.continent = "nixctl"} {
  irdl.operation @import attributes {nix.key = "import", nix.fx = "import"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v)
    irdl.results(r: %v)
  }
  irdl.operation @scoped_import attributes {nix.key = "scopedImport", nix.fx = "import"} {
    %v = irdl.base "!nix.value"
    irdl.operands(a0: %v, a1: %v)
    irdl.results(r: %v)
  }
}
