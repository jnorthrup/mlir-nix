//===- NixBase.td - Shared definitions of the Nix dialect family -*- tablegen -*-===//
//
// The Nix language is not one dialect but a small family:
//
//   nix        the language core: lambdas, application, attribute sets, lists,
//              `if`, `with`, string interpolation, ...  (NixOps.td)
//   nix<area>  one dialect per "continent" of the runtime: every primop of the
//              base environment is an op of the continent it belongs to
//              (NixPrims.td): nixnum nixty nixstr nixctx nixlist nixattr
//              nixpath nixstore nixhash nixfmt nixctl.
//
// Everything here is shared: the dialect/type/value definitions, the two
// interfaces through which the evaluator and the passes talk to ops without
// knowing their classes, and the effect resources used to *declare* what a
// primop may do (so CSE/DCE/folding follow from declarations, not from
// conditionals in C++).
//
//===----------------------------------------------------------------------===//

#ifndef NIX_BASE_TD
#define NIX_BASE_TD

include "mlir/IR/OpBase.td"
include "mlir/IR/AttrTypeBase.td"
include "mlir/Interfaces/SideEffectInterfaces.td"

def Nix_Dialect : Dialect {
  let name = "nix";
  let cppNamespace = "::mlir::nix";
  let summary = "The Nix expression language";
  let description = [{
    A lazy, purely functional dialect modelling the Nix expression language.
    Values are untyped (`!nix.value`) lazy thunks; regions are graph regions.
  }];
  let useDefaultTypePrinterParser = 1;
  let hasConstantMaterializer = 1;
  let extraClassDeclaration = [{
    /// Evaluates a primop on constant operands.  Installed by the evaluator
    /// (the dialects themselves know nothing about evaluation); returns a null
    /// attribute when the call cannot be folded (it throws, or yields a
    /// non-scalar).
    using PrimFolder = std::function<::mlir::Attribute(
        ::llvm::StringRef key, ::llvm::ArrayRef<::mlir::Attribute> args)>;
    PrimFolder primFolder;

    /// Primops declared by the continent dialects, by base-environment key.
    struct PrimInfo {
      ::mlir::OperationName name;
      unsigned arity;
    };
    ::llvm::StringMap<PrimInfo> prims;
    void registerPrim(::llvm::StringRef key, unsigned arity, ::mlir::OperationName name) {
      prims.try_emplace(key, PrimInfo{name, arity});
    }
  }];
}

class Nix_Type<string name, string typeMnemonic> : TypeDef<Nix_Dialect, name> {
  let mnemonic = typeMnemonic;
}

def Nix_ValueType : Nix_Type<"Value", "value"> {
  let summary = "a lazy Nix value";
}

defvar NixVal = Nix_ValueType;

//===----------------------------------------------------------------------===//
// Interfaces
//===----------------------------------------------------------------------===//

def NixEvalOpInterface : OpInterface<"NixEvalOpInterface"> {
  let cppNamespace = "::mlir::nix";
  let description = [{
    An operation the lazy evaluator can run.  The dialects do not implement it:
    the evaluator library attaches *external models* (see EvalModels.cpp), so
    the IR stays independent of its interpreter and any other back end (a JIT,
    a symbolic executor, ...) can attach its own interface the same way.
  }];
  let methods = [
    InterfaceMethod<
      "Evaluate the operation in activation `env`, storing the result in `out`.",
      "void", "eval",
      (ins "::nixev::EvalState &":$st, "::nixev::Frame *":$env,
           "::nixev::Value &":$out)>
  ];
}

def NixPrimOpInterface : OpInterface<"NixPrimOpInterface"> {
  let cppNamespace = "::mlir::nix";
  let description = [{
    An op that stands for one primop of the base environment.
  }];
  let methods = [
    InterfaceMethod<"Key of the primop in the base environment (e.g. `__add`).",
                    "::llvm::StringRef", "getPrimKey">,
    InterfaceMethod<"Number of arguments the primop takes.",
                    "unsigned", "getPrimArity">
  ];
}

//===----------------------------------------------------------------------===//
// Effect resources
//===----------------------------------------------------------------------===//

// May run user code (which can trace/throw) or emit diagnostics.
def NixTraceRes : Resource<"::mlir::nix::NixTraceResource">;
// Reads the file system.
def NixFSRes    : Resource<"::mlir::nix::NixFSResource">;
// Reads the process environment.
def NixEnvRes   : Resource<"::mlir::nix::NixEnvResource">;
// Writes to the Nix store.
def NixStoreRes : Resource<"::mlir::nix::NixStoreResource">;

//===----------------------------------------------------------------------===//
// Declarations that keep generic passes (CSE, DCE, LICM) sound
//===----------------------------------------------------------------------===//

// A call may run user code, which can trace, throw and allocate: two equal calls
// are not interchangeable.
defvar NixFxUser = [MemoryEffects<[MemWrite<NixTraceRes>]>];

// A result that is a freshly allocated value whose *identity* is observable:
// lists, attribute sets and functions print as «repeated» when the same one
// occurs twice, and lists of distinct functions compare unequal.  Such an op is
// pure but two identical ones must not be merged, so it declares an
// allocation of its result (like memref.alloc); an unused one is still dead.
def NixFreshVal : Res<NixVal, "a fresh value with observable identity", [MemAlloc]>;

#endif // NIX_BASE_TD
