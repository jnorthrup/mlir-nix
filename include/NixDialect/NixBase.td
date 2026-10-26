//===- NixBase.td - Shared definitions of the Nix dialect family -*- tablegen -*-===//
//
// The Nix language is not one dialect but a small family:
//
//   nix        the language core: lambdas, application, attribute sets, lists,
//              `if`, `with`, string interpolation, ...  (NixOps.td)
//   nix<area>  one dialect per "continent" of the runtime: every primop of the
//              base environment is an op of the continent it belongs to:
//              nixnum nixty nixstr nixctx nixlist nixattr nixpath nixstore
//              nixhash nixfmt nixctl.  They are *not* defined in TableGen: they
//              are declared in IRDL (NixPrims.irdl.mlir) and defined at load time.
//
// Everything here is the core: the dialect/type/value definitions and the
// interface through which the evaluator talks to ops without knowing their
// classes.
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

    /// How a primop may interact with the world (`nix.fx` of each op in
    /// NixPrims.irdl.mlir; drives the memory-effect interface).
    enum class PrimFx : uint8_t { Pure, User, FS, Env, Store, Import };

    /// Primops declared by the continent dialects (NixPrims.irdl.mlir), by
    /// base-environment key.
    struct PrimInfo {
      ::mlir::OperationName name;
      unsigned arity;
      PrimFx fx = PrimFx::Pure;
      bool foldable = false;
      /// The result is a freshly allocated list/attribute set whose identity is
      /// observable (`nix.fresh`): equal calls must not be merged.
      bool fresh = false;
      ::llvm::StringRef key; // owned by the map entry
    };
    ::llvm::StringMap<PrimInfo> prims;
    ::llvm::DenseMap<const void *, const PrimInfo *> primsByOp;
    /// Returns false (and registers nothing) when `key` is already declared.
    bool registerPrim(::llvm::StringRef key, unsigned arity, ::mlir::OperationName name,
                      PrimFx fx = PrimFx::Pure, bool foldable = false, bool fresh = false) {
      auto [it, inserted] = prims.try_emplace(key, PrimInfo{name, arity, fx, foldable, fresh, {}});
      if (inserted) {
        it->second.key = it->first();
        primsByOp[name.getAsOpaquePointer()] = &it->second;
      }
      return inserted;
    }
    /// Grouping of the continent dialects (`nix.scope` / `nix.continent` in the IRDL).
    struct DialectInfo {
      std::string scope, continent;
    };
    ::llvm::StringMap<DialectInfo> continents;

    /// The declaration of the primop `op` stands for (null for other ops).
    const PrimInfo *primOf(::mlir::Operation *op) const {
      return primsByOp.lookup(op->getName().getAsOpaquePointer());
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

//===----------------------------------------------------------------------===//
// Declarations that keep the generic passes (CSE, DCE, LICM) sound
//===----------------------------------------------------------------------===//

// May run user code (which can trace, throw and allocate) or emit diagnostics.
def NixTraceRes : Resource<"::mlir::nix::NixTraceResource">;

// A call may run user code: two equal calls are not interchangeable.
defvar NixFxUser = [MemoryEffects<[MemWrite<NixTraceRes>]>];

// A result that is a freshly allocated value whose *identity* is observable:
// lists, attribute sets and functions are compared and shown by identity in
// places (`(x: x) == (x: x)` is false; `let f = x: x; in [f f]` shows
// <REPEAT>), so two identical constructions must not be merged.  The op is
// otherwise pure, so it declares an allocation of its result (like
// memref.alloc): CSE keeps both, an unused one is still dead.
def NixFreshVal : Res<NixVal, "a fresh value with observable identity", [MemAlloc]>;

#endif // NIX_BASE_TD
