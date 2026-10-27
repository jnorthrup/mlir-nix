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

// A source position, nixfe::PackedPos: (file, line, column) in the 64 bits of a join::TwInt, stored in the
// op.  It replaces the FileLineColLoc every op used to carry, which the context hashed, probed for and
// allocated once per distinct position (a tenth of the evaluation).  Zero is "none".  No assembly
// format mentions it, so it is neither printed nor parsed, as a Location is not.
def Nix_PosProp : DefaultValuedProp<I64Prop, "0">;
/// The first row, in nixfe::PosTable, of the positions of an op's static names: name i is at row base + i; 0 is none.
def Nix_PosBaseProp : DefaultValuedProp<I64Prop, "0">;
defvar NixPos = (ins Nix_PosProp:$pos);

// A name, or the text of a literal: a nixfe::Name (include/Nix/Name.h), a pointer and a length into bytes that live
// as long as the process.  It is not an attribute: the context neither hashes nor uniques it, and the evaluator's
// Symbol for it is kept in the op the first time the op is evaluated, so a name in code nobody runs costs a copy.
// The null Name is "no name"; in a path it is the computed component, and as an attribute it is a unit.
def Nix_NameProp : Property<"::nixfe::Name", "name", "const ::nixfe::Name &"> {
  let convertFromStorage = "$_storage";
  let assignToStorage = "$_storage = $_value";
  let convertToAttribute = [{
    ::mlir::Attribute attr;
    if ($_storage.isNull())
      attr = ::mlir::UnitAttr::get($_ctxt);
    else
      attr = ::mlir::StringAttr::get($_ctxt, $_storage.str());
    return attr;
  }];
  let convertFromAttribute = [{
    if (::llvm::isa_and_present<::mlir::UnitAttr>($_attr)) {
      $_storage = ::nixfe::Name();
      return ::mlir::success();
    }
    auto text = ::llvm::dyn_cast_if_present<::mlir::StringAttr>($_attr);
    if (!text)
      return $_diag() << "expected a string";
    $_storage = ::nixfe::Name::persist(text.getValue());
    return ::mlir::success();
  }];
  let hashProperty = "::nixfe::hash_value($_storage)";
  let parser = [{
    std::string text;
    if (::mlir::failed($_parser.parseString(&text)))
      return ::mlir::failure();
    $_storage = ::nixfe::Name::persist(text);
  }];
  let optionalParser = [{
    std::string text;
    if (::mlir::failed($_parser.parseOptionalString(&text)))
      return std::nullopt;
    $_storage = ::nixfe::Name::persist(text);
  }];
  let printer = "$_printer.printString($_storage.str())";
  let readFromMlirBytecode = [{
    ::llvm::StringRef text;
    if (::mlir::failed($_reader.readString(text)))
      return ::mlir::failure();
    $_storage = ::nixfe::Name::persist(text);
  }];
  let writeToMlirBytecode = [{
    $_writer.writeOwnedString($_storage.str());
  }];
}
def Nix_NamesProp : ArrayProp<Nix_NameProp>;

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

    /// Operand modalities, collected from the `NixModes` traits of the ops: bit i of
    /// `strict` says operand i is forced before the op returns and never retained;
    /// bit i of `tail` says the op's result is that operand's value.
    struct OperandModes { unsigned strict = 0, tail = 0; };
    ::llvm::DenseMap<const void *, OperandModes> operandModes; // by OperationName
    OperandModes modesOf(::mlir::OperationName n) const {
      auto it = operandModes.find(n.getAsOpaquePointer());
      return it == operandModes.end() ? OperandModes{} : it->second;
    }
    /// True when the value has exactly one use, that use is a strict or tail operand,
    /// and the consumer is in the same region as the definition.  The consumer then
    /// runs at most once per frame, right when it needs the value, so the evaluator
    /// can evaluate the definition in place instead of allocating a thunk for it.
    bool evaluatesInPlace(::mlir::Value v) const;

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

//===----------------------------------------------------------------------===//
// Operand modalities: which operands the evaluator may evaluate in place
//===----------------------------------------------------------------------===//

// Every operand is lazy unless listed.  `strict`: if the op's evaluation uses the
// operand it forces it before returning, and does not keep the operand's Value (it
// copies out what it needs).  `tail`: the op's result is the operand's value, so it can
// be evaluated straight into the result.  Lists are operand indices.
class NixModes<list<int> strict, list<int> tail>
    : NativeOpTrait<"NixModes", [],
        "static constexpr unsigned kStrictMask = " # !foldl(0, strict, acc, i, !or(acc, !shl(1, i))) # "u;\n"
        "static constexpr unsigned kTailMask = " # !foldl(0, tail, acc, i, !or(acc, !shl(1, i))) # "u;"> {
  let cppNamespace = "::mlir::nix";
}

#endif // NIX_BASE_TD
