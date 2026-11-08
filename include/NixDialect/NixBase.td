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
  // A string attribute read with a type of its own (none), so that a trailing `: type` is left alone; its text is copied into the Name.
  let parser = [{
    ::mlir::StringAttr text;
    if (::mlir::failed($_parser.parseAttribute(text, $_parser.getBuilder().getNoneType())))
      return ::mlir::failure();
    $_storage = ::nixfe::Name::persist(text.getValue());
  }];
  let optionalParser = [{
    ::mlir::StringAttr text;
    ::mlir::OptionalParseResult parsed = $_parser.parseOptionalAttribute(text, $_parser.getBuilder().getNoneType());
    if (!parsed.has_value())
      return std::nullopt;
    if (::mlir::failed(*parsed))
      return ::mlir::failure();
    $_storage = ::nixfe::Name::persist(text.getValue());
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
def Nix_I64sProp : ArrayProp<I64Prop>;

def Nix_Dialect : Dialect {
  let name = "nix";
  let cppNamespace = "::mlir::nix";
  let summary = "The Nix expression language";
  let description = [{
    A lazy, purely functional dialect modelling the Nix expression language.
    Values are lazy thunks; regions are graph regions.  A value is `!nix.value` (its kind known only when it is forced) or, where the
    op that makes it fixes its kind, the TrikeShed type of that kind (PRELOAD.md): a list is `!trikeshed.series<!nix.value>`, an
    attribute set `!trikeshed.series2<i32, !nix.value>`, a string `!trikeshed.join<!trikeshed.series<i8>,
    !trikeshed.series<!trikeshed.series<i8>>>`, a path `!trikeshed.series<i8>`, a function
    `(!nix.value) -> !nix.value`.
  }];
  let dependentDialects = ["::composite::TrikeShedDialect"];
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
    /// `first`: one more than the operand a continent op always forces before anything else it does (0: none), from nix.first.  Its
    /// evaluator may make that operand's cell evaluated, where a lazy one would be forced the moment the op starts.
    struct OperandModes { unsigned strict = 0, tail = 0; unsigned first = 0; };
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
    /// True when the value has exactly one use, in the same body, by another op: that consumer runs at most once per frame, so the cell it
    /// makes when it runs is the only one the frame would ever hold for the value, and the frame needs no slot to keep it.
    bool madeByItsUse(::mlir::Value v) const;

    /// What a value is promoted to: decided once, here, and read by the evaluator (which cell, if any), the JITs (what they may read
    /// back or replay) and the optimizer (what may be merged).  The sea of nodes says which abstraction each value gets.
    enum class Promotion : uint8_t {
      InPlace,  ///< one strict or tail use in the same body (evaluatesInPlace): evaluated into its consumer, no cell
      Once,     ///< one lazy use in the same body: the consumer runs at most once per frame and makes the cell then; no frame slot
      Fixed,    ///< a literal or a builtin: the same value in every frame, one cell for all of them; value-numbered
      Shared,   ///< any other value of an op with no memory effect: a cell per frame, made lazily; value-numbered
      Distinct, ///< every evaluation is its own (an allocation with observable identity, or effects): a cell per frame, never merged
      Closure,  ///< a lambda: a cell per frame, made at its first touch, which keeps the frame it captures
      Argument, ///< a block argument: the frame's own cell, filled by the call
    };
    Promotion promotionOf(::mlir::Value v) const;
    static ::llvm::StringRef promotionName(Promotion p);

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
      /// The kind every result has, where the declaration fixes one (`irdl.is`): a list, a set, a string or a path.  Null: any.
      ::mlir::Type result;
    };
    ::llvm::StringMap<PrimInfo> prims;
    ::llvm::DenseMap<const void *, const PrimInfo *> primsByOp;
    /// Returns false (and registers nothing) when `key` is already declared.
    bool registerPrim(::llvm::StringRef key, unsigned arity, ::mlir::OperationName name,
                      PrimFx fx = PrimFx::Pure, bool foldable = false, bool fresh = false) {
      auto [it, inserted] = prims.try_emplace(key, PrimInfo{name, arity, fx, foldable, fresh, {}, {}});
      if (inserted) {
        it->second.key = it->first();
        primsByOp[name.getAsOpaquePointer()] = &it->second;
      }
      return inserted;
    }
    /// Grouping of the continent dialects (`nix.scope` / `nix.continent` in the IRDL).
    struct DialectInfo {
      ::llvm::StringRef scope, continent; // views on the IRDL declaration's attributes, which the context keeps for its whole life
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

// The kinds a value's maker fixes, as TrikeShed types (docs/PRELOAD-DIALECTS.md, step 1).  Each is buildable, so a result of one prints
// no type, as a !nix.value result does; an operand of one prints its type after it (NixValue / NixValues in NixDialect.cpp).
def NixList : Type<
    CPred<"::llvm::isa<::composite::SeriesType>($_self) && "
          "::llvm::isa<::mlir::nix::ValueType>(::llvm::cast<::composite::SeriesType>($_self).getElement())">,
    "a Nix list: Series<!nix.value>", "::composite::SeriesType">,
  BuildableType<"::composite::SeriesType::get($_builder.getContext(), ::mlir::nix::ValueType::get($_builder.getContext()))">;

// An attribute set: its rows in name order, the name's symbol and the value (Bindings in the evaluator: Series2<Symbol, Value>).
def NixAttrs : Type<
    CPred<"::llvm::isa<::composite::Series2Type>($_self) && "
          "::llvm::cast<::composite::Series2Type>($_self).getA().isInteger(32) && "
          "::llvm::isa<::mlir::nix::ValueType>(::llvm::cast<::composite::Series2Type>($_self).getB())">,
    "a Nix attribute set: Series2<i32, !nix.value>", "::composite::Series2Type">,
  BuildableType<"::composite::Series2Type::get($_builder.getContext(), $_builder.getIntegerType(32), "
                "::mlir::nix::ValueType::get($_builder.getContext()))">;

// A string: its characters and its context, the store paths it refers to (Join<CharSeries, Series<CharSeries>>).
def NixString : Type<
    CPred<"::mlir::nix::isStringType($_self)">,
    "a Nix string: Join<Series<i8>, Series<Series<i8>>>", "::composite::JoinType">,
  BuildableType<"::mlir::nix::stringType($_builder.getContext())">;

// A path: its characters, no context (a CharSeries: Series<i8>).
def NixPath : Type<
    CPred<"::llvm::isa<::composite::SeriesType>($_self) && "
          "::llvm::cast<::composite::SeriesType>($_self).getElement().isInteger(8)">,
    "a Nix path: Series<i8>", "::composite::SeriesType">,
  BuildableType<"::composite::SeriesType::get($_builder.getContext(), $_builder.getIntegerType(8))">;

// A function: one value to one value (PRELOAD's `(A) -> B`), the builtin function type.
def NixFn : Type<CPred<"::mlir::nix::isFnType($_self)">, "a Nix function: (!nix.value) -> !nix.value", "::mlir::FunctionType">,
  BuildableType<"::mlir::nix::fnType($_builder.getContext())">;

// What an operand takes: a value of any kind.
def NixAny : AnyTypeOf<[NixVal, NixList, NixAttrs, NixString, NixPath, NixFn], "a Nix value">;

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
def NixFreshList : Res<NixList, "a fresh list with observable identity", [MemAlloc]>;
def NixFreshAttrs : Res<NixAttrs, "a fresh attribute set with observable identity", [MemAlloc]>;
def NixFreshFn : Res<NixFn, "a fresh closure with observable identity", [MemAlloc]>;

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
