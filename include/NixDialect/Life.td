//===- Life.td - Lifetimes: elements, admission, owned effects, drain -*- tablegen -*-===//
//
// The life dialect says how long things live and who waits for them: an element opened by its key, the channels it
// admits through, the jobs and resources it owns, and its drain.  It is TrikeShed's lifecycle contract (PRELOAD.md,
// "Lifecycle -- the Job and the Channel are the lifecycle") as IR, for the in-process side (a ring, its workers, its
// buffers) and the out-of-process side (a service, its runtime directory, its mounts) alike.  Design and laws:
// docs/LIFE.md.
//
// There is no state in it.  No type or op names CREATED/OPEN/DRAINING/CLOSED, and no op reads whether a channel is
// closed or an element is open: an element exists only opened (life.open), admission is the send and its answer
// (life.send), completion is the join (life.join).  Every region of a life op is a supervisor: what is launched,
// submitted, opened or acquired in it is waited for or released before the region ends.
//
// What the op verifiers check is local (a law that one op and its block can decide).  The laws that need the whole
// function -- an element drained once on every path, no job outliving its supervisor across blocks, the release order
// as a whole -- are the life-verify pass of docs/LIFE.md, not built.
//
//===----------------------------------------------------------------------===//

#ifndef LIFE_TD
#define LIFE_TD

include "mlir/IR/OpBase.td"
include "mlir/IR/AttrTypeBase.td"
include "mlir/IR/SymbolInterfaces.td"
include "mlir/IR/BuiltinAttributeInterfaces.td"

def Life_Dialect : Dialect {
  let name = "life";
  let cppNamespace = "::mlir::life";
  let summary = "Lifetimes: elements opened by their keys, admission, owned effects, drain";
  let useDefaultTypePrinterParser = 1;
}

class Life_Type<string name, string typeMnemonic> : TypeDef<Life_Dialect, name> { let mnemonic = typeMnemonic; }

def Life_ElementType : Life_Type<"Element", "element"> {
  let summary = "an element opened by its key";
  let parameters = (ins "::mlir::FlatSymbolRefAttr":$key);
  let assemblyFormat = "`<` $key `>`";
}

def Life_ChanType : Life_Type<"Chan", "chan"> {
  let summary = "a bounded channel: an element's admission";
  let parameters = (ins "::mlir::Type":$element);
  let assemblyFormat = "`<` $element `>`";
}

def Life_JobType : Life_Type<"Job", "job"> {
  let summary = "an admitted effect, owned by the supervisor around it; its result (none: no result)";
  let parameters = (ins "::mlir::Type":$result);
  let assemblyFormat = "`<` $result `>`";
}

def Life_OwnedType : Life_Type<"Owned", "owned"> {
  let summary = "a resource owned by the supervisor around it, released when it ends";
  let parameters = (ins "::mlir::Type":$handle);
  let assemblyFormat = "`<` $handle `>`";
}

def Life_Element : Type<CPred<"::llvm::isa<::mlir::life::ElementType>($_self)">, "an element", "::mlir::life::ElementType">;
def Life_Chan : Type<CPred<"::llvm::isa<::mlir::life::ChanType>($_self)">, "a channel", "::mlir::life::ChanType">;
def Life_Job : Type<CPred<"::llvm::isa<::mlir::life::JobType>($_self)">, "a job", "::mlir::life::JobType">;

class Life_Op<string mnemonic, list<Trait> traits = []> : Op<Life_Dialect, mnemonic, traits>;

// ---- keys and elements

def Life_KeyOp : Life_Op<"key", [Symbol, IsolatedFromAbove, SingleBlock]> {
  let summary = "the singleton identity and factory of an element";
  let description = [{
    The body opens what the element owns -- its channels, resources, workers, the elements it is made of -- and ends
    with `life.opened`, which hands out the channels it admits through.  The body is the element's supervisor: drain
    ends it.  `function_type`: the factory's inputs; its results are the element, then those channels.  PRELOAD: "the
    Key is the factory and returns only an opened element".
  }];
  let arguments = (ins SymbolNameAttr:$sym_name, TypeAttrOf<FunctionType>:$function_type);
  let regions = (region SizedRegion<1>:$body);
  let assemblyFormat = "$sym_name attr-dict `:` $function_type $body";
  let hasVerifier = 1;
}

def Life_OpenedOp : Life_Op<"opened", [Terminator, HasParent<"KeyOp">]> {
  let summary = "the end of a key's body: the channels the element admits through";
  let arguments = (ins Variadic<Life_Chan>:$channels);
  let assemblyFormat = "($channels^ `:` type($channels))? attr-dict";
}

def Life_OpenOp : Life_Op<"open", [DeclareOpInterfaceMethods<SymbolUserOpInterface>]> {
  let summary = "open an element by its key";
  let description = [{
    The element and its channels, or the failure of the factory, which goes to the supervisor around (what the factory
    had acquired is released).  There is no element that is not open, so nothing asks whether one is.
  }];
  let arguments = (ins FlatSymbolRefAttr:$key, Variadic<AnyType>:$args);
  let results = (outs Life_Element:$element, Variadic<Life_Chan>:$channels);
  let assemblyFormat = "$key `(` $args `)` attr-dict `:` functional-type($args, results)";
  let hasVerifier = 1;
}

def Life_DrainOp : Life_Op<"drain"> {
  let summary = "drain an element: close its admission, let its workers finish, join, release, complete";
  let description = [{
    PRELOAD's drain: close the input, the worker empties it, join the worker, complete and join the supervisor.  The
    element's channels close; a channel whose senders have all completed closes after them; each `for_each` ends when
    its channel is closed and empty; the jobs are joined; the resources are released in their order (`life.before`, else
    the reverse of their acquisition).  The element is not used after it (local law, checked in the block).  Not
    `trikeshed.drain`, which empties a series into a buffer.
  }];
  let arguments = (ins Life_Element:$element);
  let assemblyFormat = "$element attr-dict `:` qualified(type($element))";
  let hasVerifier = 1;
}

// ---- supervisors, workers and effects

def Life_SuperviseOp : Life_Op<"supervise", [SingleBlockImplicitTerminator<"YieldOp">]> {
  let summary = "a supervisor: complete when everything admitted in it has completed and been released";
  let results = (outs Variadic<AnyType>:$results);
  let regions = (region SizedRegion<1>:$body);
  let assemblyFormat = "(`->` type($results)^)? $body attr-dict";
}

def Life_FailOp : Life_Op<"fail"> {
  let summary = "the failure path: the supervisor around fails";
  let description = [{
    It cancels its other jobs -- the only cancellation there is; drain never cancels -- and still releases what it
    owns, then fails its own supervisor in turn.
  }];
  let arguments = (ins StrAttr:$reason);
  let assemblyFormat = "$reason attr-dict";
  let hasVerifier = 1;
}

def Life_LaunchOp : Life_Op<"launch", [SingleBlockImplicitTerminator<"YieldOp">]> {
  let summary = "a worker: a child job of the supervisor around";
  let results = (outs Life_Job:$job);
  let regions = (region SizedRegion<1>:$body);
  let assemblyFormat = "attr-dict `:` qualified(type($job)) $body";
  let hasVerifier = 1;
}

def Life_SubmitOp : Life_Op<"submit"> {
  let summary = "an effect the kernel completes: a child job ended by its completion";
  let description = [{
    An io_uring submission (completed by its CQE) or a spawned process (by its exit).  PRELOAD: "a submitted uring op is
    a child Job of the supervisor, completed by its CQE, so join waits on the kernel".  The operands at the indices of
    `lent` are the kernel's from the submission until the job is joined: in the block, nothing else uses them in
    between (or after, when the job is joined only by the supervisor's end).
  }];
  let arguments = (ins FlatSymbolRefAttr:$op, Variadic<AnyType>:$args, DefaultValuedAttr<DenseI64ArrayAttr, "{}">:$lent);
  let results = (outs Life_Job:$job);
  let assemblyFormat = "$op `(` $args `)` (`lent` $lent^)? attr-dict `:` functional-type($args, $job)";
  let hasVerifier = 1;
}

def Life_JoinOp : Life_Op<"join"> {
  let summary = "wait for a job: its result";
  let arguments = (ins Life_Job:$job);
  let results = (outs Optional<AnyType>:$result);
  let assemblyFormat = "$job attr-dict `:` qualified(type($job)) (`->` type($result)^)?";
  let hasVerifier = 1;
}

// ---- admission

def Life_ChannelOp : Life_Op<"channel"> {
  let summary = "a bounded channel owned by the supervisor around";
  let arguments = (ins ConfinedAttr<I64Attr, [IntMinValue<1>]>:$capacity);
  let results = (outs Life_Chan:$chan);
  let assemblyFormat = "$capacity attr-dict `:` qualified(type($chan))";
  let hasVerifier = 1;
}

def Life_SendOp : Life_Op<"send"> {
  let summary = "admission: offer a value; true when admitted";
  let description = [{
    False when the channel no longer admits.  It is the only way closure is seen, so a check of a state followed by an
    act on it cannot be written.  The answer is used: a discarded claim is not processed work.
  }];
  let arguments = (ins AnyType:$value, Life_Chan:$chan);
  let results = (outs I1:$admitted);
  let assemblyFormat = "$value `to` $chan attr-dict `:` type($value) `to` qualified(type($chan))";
  let hasVerifier = 1;
}

def Life_CloseOp : Life_Op<"close"> {
  let summary = "stop admission; what was admitted is still delivered";
  let arguments = (ins Life_Chan:$chan);
  let assemblyFormat = "$chan attr-dict `:` qualified(type($chan))";
}

def Life_ForEachOp : Life_Op<"for_each", [SingleBlockImplicitTerminator<"YieldOp">]> {
  let summary = "the worker's loop: the body runs on each value admitted, until the channel is closed and empty";
  let arguments = (ins Life_Chan:$chan);
  let regions = (region SizedRegion<1>:$body);
  let assemblyFormat = "$chan attr-dict `:` qualified(type($chan)) $body";
  let hasVerifier = 1;
}

// ---- ownership

def Life_AcquireOp : Life_Op<"acquire"> {
  let summary = "a resource made by `make`, released by `release`, owned by the supervisor around";
  let description = [{
    A descriptor, a ring, a mapping, a GC root, a mount.  Its result may be a channel the kernel fills (a listening
    socket): closing it stops what the kernel admits.
  }];
  let arguments = (ins FlatSymbolRefAttr:$make, FlatSymbolRefAttr:$release, Variadic<AnyType>:$args);
  let results = (outs AnyType:$resource);
  let assemblyFormat = "$make `(` $args `)` `release` $release attr-dict `:` functional-type($args, $resource)";
  let hasVerifier = 1;
}

def Life_BeforeOp : Life_Op<"before"> {
  let summary = "`first` is released before `then`, whatever the order of their acquisition";
  let description = [{
    The default order is the reverse of acquisition.  Both are acquired in this block.  A cycle of these is an error of
    the release order as a whole (life-verify).
  }];
  let arguments = (ins AnyType:$first, AnyType:$then);
  let assemblyFormat = "$first `,` $then attr-dict `:` type($first) `,` type($then)";
  let hasVerifier = 1;
}

def Life_YieldOp : Life_Op<"yield", [Terminator, ParentOneOf<["SuperviseOp", "LaunchOp", "ForEachOp"]>]> {
  let summary = "the end of a supervisor's, worker's or loop's body";
  let arguments = (ins Variadic<AnyType>:$values);
  let builders = [OpBuilder<(ins), [{ /* no values */ }]>];
  let assemblyFormat = "($values^ `:` type($values))? attr-dict";
}

#endif // LIFE_TD
