//===- NixPrims.td - Nix primops as ops of per-continent dialects ---------===//
//
// Every primop of the Nix base environment is an op here, grouped into
// "continents": one dialect per area of the language runtime.  The generic
// `nix.apply (nix.builtin "__add") ...` is rewritten to these ops by the
// `nix-prims` pass; from then on what MLIR needs to know about a call is
// *declared* below instead of being rediscovered by conditionals in C++:
//
//   arity            the verifier rejects a malformed call
//   effects          Pure                  deterministic: CSE / fold freely
//                    MemRead <NixFS|Env>   reads the file system / environment
//                    MemWrite<NixTrace>    may run user code or emit diagnostics
//                    MemWrite<NixStore>    writes to the Nix store
//   foldability      `foldable` ops are evaluated at compile time when every
//                    operand is a scalar constant (by the evaluator's own
//                    implementation, through Nix_Dialect::primFolder)
//
// The list must match the runtime registry: scripts/check-prims.py compares it
// with `mlnix primops`.
//
//===----------------------------------------------------------------------===//

#ifndef NIX_PRIMS_TD
#define NIX_PRIMS_TD

include "NixBase.td"

class NixContinent<string n, string ns, string desc> : Dialect {
  let name = n;
  let cppNamespace = "::mlir::nix::" # ns;
  let summary = desc;
  let dependentDialects = ["::mlir::nix::NixDialect"];
  let hasConstantMaterializer = 1;
}

defvar FxPure   = [Pure];
defvar FxUser   = NixFxUser;
defvar FxFS     = [MemoryEffects<[MemRead<NixFSRes>]>];
defvar FxEnv    = [MemoryEffects<[MemRead<NixEnvRes>]>];
defvar FxStore  = [MemoryEffects<[MemWrite<NixStoreRes>]>];
defvar FxImport = [MemoryEffects<[MemRead<NixFSRes>, MemWrite<NixTraceRes>]>];

class NixPrim<NixContinent d, string mnemonic, string key, int arity,
              list<Trait> fx = FxPure, bit foldable = 0>
    : Op<d, mnemonic, !listconcat(fx, [NixPrimOpInterface])> {
  let summary = "the `" # key # "` primop";
  let arguments = (ins Variadic<NixVal>:$args);
  let results = (outs NixVal:$result);
  let assemblyFormat = "`(` $args `)` attr-dict";
  let hasVerifier = 1;
  let hasFolder = foldable;
  let extraClassDeclaration = [{
    static constexpr ::llvm::StringLiteral primKey = "}] # key # [{";
    static constexpr unsigned primArity = }] # !cast<string>(arity) # [{;
    ::llvm::StringRef getPrimKey() { return primKey; }
    unsigned getPrimArity() { return primArity; }
  }];
  let extraClassDefinition = [{
    ::llvm::LogicalResult $cppClass::verify() {
      return ::mlir::nix::verifyPrimArity(getOperation(), primArity);
    }
  }] # !if(foldable, [{
    ::mlir::OpFoldResult $cppClass::fold(FoldAdaptor adaptor) {
      return ::mlir::nix::foldPrim(getOperation(), primKey, adaptor.getArgs());
    }
  }], "");
}

// A primop whose result is a freshly allocated list or attribute set: pure (or
// reading the file system) but with observable identity, see NixFreshVal.
class NixFreshPrim<NixContinent d, string mnemonic, string key, int arity,
                   list<Trait> fx = []>
    : NixPrim<d, mnemonic, key, arity, fx, 0> {
  let results = (outs NixFreshVal:$result);
}

//===----------------------------------------------------------------------===//
// nixnum: Numbers: arithmetic, bit operations, rounding, ordering
//===----------------------------------------------------------------------===//

def NixNum_Dialect : NixContinent<"nixnum", "num", "Numbers: arithmetic, bit operations, rounding, ordering">;

def NixNum_AddOp : NixPrim<NixNum_Dialect, "add", "__add", 2, FxPure, 1>;
def NixNum_BitAndOp : NixPrim<NixNum_Dialect, "bit_and", "__bitAnd", 2, FxPure, 1>;
def NixNum_BitOrOp : NixPrim<NixNum_Dialect, "bit_or", "__bitOr", 2, FxPure, 1>;
def NixNum_BitXorOp : NixPrim<NixNum_Dialect, "bit_xor", "__bitXor", 2, FxPure, 1>;
def NixNum_CeilOp : NixPrim<NixNum_Dialect, "ceil", "__ceil", 1, FxPure, 1>;
def NixNum_DivOp : NixPrim<NixNum_Dialect, "div", "__div", 2, FxPure, 1>;
def NixNum_FloorOp : NixPrim<NixNum_Dialect, "floor", "__floor", 1, FxPure, 1>;
def NixNum_LessThanOp : NixPrim<NixNum_Dialect, "less_than", "__lessThan", 2, FxPure, 1>;
def NixNum_MulOp : NixPrim<NixNum_Dialect, "mul", "__mul", 2, FxPure, 1>;
def NixNum_SubOp : NixPrim<NixNum_Dialect, "sub", "__sub", 2, FxPure, 1>;

//===----------------------------------------------------------------------===//
// nixty: Types and reflection: type predicates, typeOf, functionArgs
//===----------------------------------------------------------------------===//

def NixTy_Dialect : NixContinent<"nixty", "ty", "Types and reflection: type predicates, typeOf, functionArgs">;

def NixTy_FunctionArgsOp : NixFreshPrim<NixTy_Dialect, "function_args", "__functionArgs", 1>;
def NixTy_IsAttrsOp : NixPrim<NixTy_Dialect, "is_attrs", "__isAttrs", 1, FxPure, 1>;
def NixTy_IsBoolOp : NixPrim<NixTy_Dialect, "is_bool", "__isBool", 1, FxPure, 1>;
def NixTy_IsFloatOp : NixPrim<NixTy_Dialect, "is_float", "__isFloat", 1, FxPure, 1>;
def NixTy_IsFunctionOp : NixPrim<NixTy_Dialect, "is_function", "__isFunction", 1, FxPure, 1>;
def NixTy_IsIntOp : NixPrim<NixTy_Dialect, "is_int", "__isInt", 1, FxPure, 1>;
def NixTy_IsListOp : NixPrim<NixTy_Dialect, "is_list", "__isList", 1, FxPure, 1>;
def NixTy_IsNullOp : NixPrim<NixTy_Dialect, "is_null", "isNull", 1, FxPure, 1>;
def NixTy_IsPathOp : NixPrim<NixTy_Dialect, "is_path", "__isPath", 1, FxPure, 1>;
def NixTy_IsStringOp : NixPrim<NixTy_Dialect, "is_string", "__isString", 1, FxPure, 1>;
def NixTy_TypeOfOp : NixPrim<NixTy_Dialect, "type_of", "__typeOf", 1, FxPure, 1>;

//===----------------------------------------------------------------------===//
// nixstr: Strings: slicing, search, replace, versions, coercion
//===----------------------------------------------------------------------===//

def NixStr_Dialect : NixContinent<"nixstr", "str", "Strings: slicing, search, replace, versions, coercion">;

def NixStr_CompareVersionsOp : NixPrim<NixStr_Dialect, "compare_versions", "__compareVersions", 2, FxPure, 1>;
def NixStr_ConcatStringsSepOp : NixPrim<NixStr_Dialect, "concat_strings_sep", "__concatStringsSep", 2, FxPure>;
def NixStr_MatchOp : NixFreshPrim<NixStr_Dialect, "match", "__match", 2>;
def NixStr_ParseDrvNameOp : NixFreshPrim<NixStr_Dialect, "parse_drv_name", "__parseDrvName", 1>;
def NixStr_PlaceholderOp : NixPrim<NixStr_Dialect, "placeholder", "placeholder", 1, FxPure, 1>;
def NixStr_ReplaceStringsOp : NixPrim<NixStr_Dialect, "replace_strings", "__replaceStrings", 3, FxPure>;
def NixStr_SplitOp : NixFreshPrim<NixStr_Dialect, "split", "__split", 2>;
def NixStr_SplitVersionOp : NixFreshPrim<NixStr_Dialect, "split_version", "__splitVersion", 1>;
def NixStr_StringLengthOp : NixPrim<NixStr_Dialect, "string_length", "__stringLength", 1, FxPure, 1>;
def NixStr_SubstringOp : NixPrim<NixStr_Dialect, "substring", "__substring", 3, FxPure, 1>;
def NixStr_ToStringOp : NixPrim<NixStr_Dialect, "to_string", "toString", 1, FxPure, 1>;

//===----------------------------------------------------------------------===//
// nixctx: String context: dependency tracking carried by strings
//===----------------------------------------------------------------------===//

def NixCtx_Dialect : NixContinent<"nixctx", "ctx", "String context: dependency tracking carried by strings">;

def NixCtx_AddDrvOutputDependenciesOp : NixPrim<NixCtx_Dialect, "add_drv_output_dependencies", "__addDrvOutputDependencies", 1, FxPure>;
def NixCtx_AppendContextOp : NixPrim<NixCtx_Dialect, "append_context", "__appendContext", 2, FxPure>;
def NixCtx_GetContextOp : NixFreshPrim<NixCtx_Dialect, "get_context", "__getContext", 1>;
def NixCtx_HasContextOp : NixPrim<NixCtx_Dialect, "has_context", "__hasContext", 1, FxPure, 1>;
def NixCtx_UnsafeDiscardOutputDependencyOp : NixPrim<NixCtx_Dialect, "unsafe_discard_output_dependency", "__unsafeDiscardOutputDependency", 1, FxPure>;
def NixCtx_UnsafeDiscardStringContextOp : NixPrim<NixCtx_Dialect, "unsafe_discard_string_context", "__unsafeDiscardStringContext", 1, FxPure>;

//===----------------------------------------------------------------------===//
// nixlist: Lists: access, construction, higher-order operations
//===----------------------------------------------------------------------===//

def NixList_Dialect : NixContinent<"nixlist", "list", "Lists: access, construction, higher-order operations">;

def NixList_AllOp : NixPrim<NixList_Dialect, "all", "__all", 2, FxUser>;
def NixList_AnyOp : NixPrim<NixList_Dialect, "any", "__any", 2, FxUser>;
def NixList_ConcatListsOp : NixFreshPrim<NixList_Dialect, "concat_lists", "__concatLists", 1>;
def NixList_ConcatMapOp : NixPrim<NixList_Dialect, "concat_map", "__concatMap", 2, FxUser>;
def NixList_ElemOp : NixPrim<NixList_Dialect, "elem", "__elem", 2, FxPure>;
def NixList_ElemAtOp : NixPrim<NixList_Dialect, "elem_at", "__elemAt", 2, FxPure>;
def NixList_FilterOp : NixPrim<NixList_Dialect, "filter", "__filter", 2, FxUser>;
def NixList_FoldlStrictOp : NixPrim<NixList_Dialect, "foldl_strict", "__foldl'", 3, FxUser>;
def NixList_GenListOp : NixPrim<NixList_Dialect, "gen_list", "__genList", 2, FxUser>;
def NixList_GenericClosureOp : NixPrim<NixList_Dialect, "generic_closure", "__genericClosure", 1, FxUser>;
def NixList_GroupByOp : NixPrim<NixList_Dialect, "group_by", "__groupBy", 2, FxUser>;
def NixList_HeadOp : NixPrim<NixList_Dialect, "head", "__head", 1, FxPure>;
def NixList_LengthOp : NixPrim<NixList_Dialect, "length", "__length", 1, FxPure>;
def NixList_MapOp : NixPrim<NixList_Dialect, "map", "map", 2, FxUser>;
def NixList_PartitionOp : NixPrim<NixList_Dialect, "partition", "__partition", 2, FxUser>;
def NixList_SortOp : NixPrim<NixList_Dialect, "sort", "__sort", 2, FxUser>;
def NixList_TailOp : NixFreshPrim<NixList_Dialect, "tail", "__tail", 1>;

//===----------------------------------------------------------------------===//
// nixattr: Attribute sets: access, construction, higher-order operations
//===----------------------------------------------------------------------===//

def NixAttr_Dialect : NixContinent<"nixattr", "attr", "Attribute sets: access, construction, higher-order operations">;

def NixAttr_AttrNamesOp : NixFreshPrim<NixAttr_Dialect, "attr_names", "__attrNames", 1>;
def NixAttr_AttrValuesOp : NixFreshPrim<NixAttr_Dialect, "attr_values", "__attrValues", 1>;
def NixAttr_CatAttrsOp : NixFreshPrim<NixAttr_Dialect, "cat_attrs", "__catAttrs", 2>;
def NixAttr_GetAttrOp : NixPrim<NixAttr_Dialect, "get_attr", "__getAttr", 2, FxPure>;
def NixAttr_HasAttrOp : NixPrim<NixAttr_Dialect, "has_attr", "__hasAttr", 2, FxPure>;
def NixAttr_IntersectAttrsOp : NixFreshPrim<NixAttr_Dialect, "intersect_attrs", "__intersectAttrs", 2>;
def NixAttr_ListToAttrsOp : NixFreshPrim<NixAttr_Dialect, "list_to_attrs", "__listToAttrs", 1>;
def NixAttr_MapAttrsOp : NixPrim<NixAttr_Dialect, "map_attrs", "__mapAttrs", 2, FxUser>;
def NixAttr_RemoveAttrsOp : NixFreshPrim<NixAttr_Dialect, "remove_attrs", "removeAttrs", 2>;
def NixAttr_UnsafeGetAttrPosOp : NixFreshPrim<NixAttr_Dialect, "unsafe_get_attr_pos", "__unsafeGetAttrPos", 2>;
def NixAttr_ZipAttrsWithOp : NixPrim<NixAttr_Dialect, "zip_attrs_with", "__zipAttrsWith", 2, FxUser>;

//===----------------------------------------------------------------------===//
// nixpath: Paths and environment: file system reads, path arithmetic
//===----------------------------------------------------------------------===//

def NixPath_Dialect : NixContinent<"nixpath", "path", "Paths and environment: file system reads, path arithmetic">;

def NixPath_BaseNameOfOp : NixPrim<NixPath_Dialect, "base_name_of", "baseNameOf", 1, FxPure>;
def NixPath_DirOfOp : NixPrim<NixPath_Dialect, "dir_of", "dirOf", 1, FxPure>;
def NixPath_FindFileOp : NixPrim<NixPath_Dialect, "find_file", "__findFile", 2, FxFS>;
def NixPath_GetEnvOp : NixPrim<NixPath_Dialect, "get_env", "__getEnv", 1, FxEnv>;
def NixPath_PathExistsOp : NixPrim<NixPath_Dialect, "path_exists", "__pathExists", 1, FxFS>;
def NixPath_ReadDirOp : NixFreshPrim<NixPath_Dialect, "read_dir", "__readDir", 1, FxFS>;
def NixPath_ReadFileOp : NixPrim<NixPath_Dialect, "read_file", "__readFile", 1, FxFS>;
def NixPath_ReadFileTypeOp : NixPrim<NixPath_Dialect, "read_file_type", "__readFileType", 1, FxFS>;
def NixPath_ToPathOp : NixPrim<NixPath_Dialect, "to_path", "__toPath", 1, FxPure>;

//===----------------------------------------------------------------------===//
// nixstore: Store: derivations, store paths, fetchers (writes to the store)
//===----------------------------------------------------------------------===//

def NixStore_Dialect : NixContinent<"nixstore", "store", "Store: derivations, store paths, fetchers (writes to the store)">;

def NixStore_DerivationStrictOp : NixPrim<NixStore_Dialect, "derivation_strict", "derivationStrict", 1, FxStore>;
def NixStore_FetchGitOp : NixPrim<NixStore_Dialect, "fetch_git", "fetchGit", 1, FxStore>;
def NixStore_FetchMercurialOp : NixPrim<NixStore_Dialect, "fetch_mercurial", "fetchMercurial", 1, FxStore>;
def NixStore_FetchTarballOp : NixPrim<NixStore_Dialect, "fetch_tarball", "fetchTarball", 1, FxStore>;
def NixStore_FetchurlOp : NixPrim<NixStore_Dialect, "fetchurl", "__fetchurl", 1, FxStore>;
def NixStore_FilterSourceOp : NixPrim<NixStore_Dialect, "filter_source", "__filterSource", 2, FxStore>;
def NixStore_PathOp : NixPrim<NixStore_Dialect, "path", "__path", 1, FxStore>;
def NixStore_StorePathOp : NixPrim<NixStore_Dialect, "store_path", "__storePath", 1, FxStore>;
def NixStore_ToFileOp : NixPrim<NixStore_Dialect, "to_file", "__toFile", 2, FxStore>;

//===----------------------------------------------------------------------===//
// nixhash: Hashing: digests and hash format conversion
//===----------------------------------------------------------------------===//

def NixHash_Dialect : NixContinent<"nixhash", "hash", "Hashing: digests and hash format conversion">;

def NixHash_ConvertHashOp : NixPrim<NixHash_Dialect, "convert_hash", "__convertHash", 1, FxPure>;
def NixHash_HashFileOp : NixPrim<NixHash_Dialect, "hash_file", "__hashFile", 2, FxFS>;
def NixHash_HashStringOp : NixPrim<NixHash_Dialect, "hash_string", "__hashString", 2, FxPure, 1>;

//===----------------------------------------------------------------------===//
// nixfmt: Serialization: JSON, XML, TOML, flake references
//===----------------------------------------------------------------------===//

def NixFmt_Dialect : NixContinent<"nixfmt", "fmt", "Serialization: JSON, XML, TOML, flake references">;

def NixFmt_FlakeRefToStringOp : NixPrim<NixFmt_Dialect, "flake_ref_to_string", "__flakeRefToString", 1, FxPure>;
def NixFmt_FromJsonOp : NixFreshPrim<NixFmt_Dialect, "from_json", "__fromJSON", 1>;
def NixFmt_FromTomlOp : NixFreshPrim<NixFmt_Dialect, "from_toml", "fromTOML", 1>;
def NixFmt_ParseFlakeRefOp : NixFreshPrim<NixFmt_Dialect, "parse_flake_ref", "__parseFlakeRef", 1>;
def NixFmt_ToJsonOp : NixPrim<NixFmt_Dialect, "to_json", "__toJSON", 1, FxStore>;
def NixFmt_ToXmlOp : NixPrim<NixFmt_Dialect, "to_xml", "__toXML", 1, FxStore>;

//===----------------------------------------------------------------------===//
// nixctl: Control and diagnostics: seq, throw, trace, import, tryEval
//===----------------------------------------------------------------------===//

def NixCtl_Dialect : NixContinent<"nixctl", "ctl", "Control and diagnostics: seq, throw, trace, import, tryEval">;

def NixCtl_AbortOp : NixPrim<NixCtl_Dialect, "abort", "abort", 1, FxPure>;
def NixCtl_AddErrorContextOp : NixPrim<NixCtl_Dialect, "add_error_context", "__addErrorContext", 2, FxPure>;
def NixCtl_BreakOp : NixPrim<NixCtl_Dialect, "break", "break", 1, FxPure>;
def NixCtl_DeepSeqOp : NixPrim<NixCtl_Dialect, "deep_seq", "__deepSeq", 2, FxPure>;
def NixCtl_ImportOp : NixPrim<NixCtl_Dialect, "import", "import", 1, FxImport>;
def NixCtl_ScopedImportOp : NixPrim<NixCtl_Dialect, "scoped_import", "scopedImport", 2, FxImport>;
def NixCtl_SeqOp : NixPrim<NixCtl_Dialect, "seq", "__seq", 2, FxPure>;
def NixCtl_ThrowOp : NixPrim<NixCtl_Dialect, "throw", "throw", 1, FxPure>;
def NixCtl_TraceOp : NixPrim<NixCtl_Dialect, "trace", "__trace", 2, FxUser>;
def NixCtl_TraceVerboseOp : NixPrim<NixCtl_Dialect, "trace_verbose", "__traceVerbose", 2, FxUser>;
def NixCtl_TryEvalOp : NixFreshPrim<NixCtl_Dialect, "try_eval", "__tryEval", 1>;
def NixCtl_WarnOp : NixPrim<NixCtl_Dialect, "warn", "__warn", 2, FxUser>;

#endif // NIX_PRIMS_TD
