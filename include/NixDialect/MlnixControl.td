//===- MlnixControl.td - The control surface of the mlnix utility -*- tablegen -*-===//
//
// mlnix is configured three ways today: command-line flags (tools/mlnix.cpp), `MLNIX_*` environment variables read
// where they are used (lib/Eval, 50-odd names), and EvalSettings (include/Nix/Eval.h).  This dialect is the one place
// that says what can be set, as IR a module holds, prints, parses and verifies.  It is the control surface of the
// utility over the other dialects of the family:
//
//   nix, nix<area>   the language and its continents (NixOps.td, NixPrims.irdl.mlir): what is evaluated
//   trikeshed        the kernel algebra (Composite/TrikeShed.td): the geometry of the data the evaluator keeps
//   mlnix            this file: how the sea of nodes is scheduled and run -- eager or minted on demand, which passes
//                    rewrite the graph, which tier runs a hot lambda, how many helper threads lower files ahead
//
// A `mlnix.session` is one configured run: a symbol, isolated from above, whose body is a list of settings and
// requests.  A setting says which C++ reads it (an EvalSettings field or the environment variable that fills it); the
// law of each op is the text of its description.  Nothing in the evaluator emits or reads these ops yet: a reader
// (`mlnix --session FILE`, filling EvalSettings from a session) is the next step, and until it lands the ops are
// declaration, parsed, printed and verified by test/mlir/control.mlir.
//
//===----------------------------------------------------------------------===//

#ifndef MLNIX_CONTROL_TD
#define MLNIX_CONTROL_TD

include "mlir/IR/OpBase.td"
include "mlir/IR/AttrTypeBase.td"
include "mlir/IR/EnumAttr.td"
include "mlir/IR/SymbolInterfaces.td"

def Mlnix_Dialect : Dialect {
  let name = "mlnix";
  let cppNamespace = "::mlir::mlnix";
  let summary = "The control surface of the mlnix utility";
  let description = [{
    Settings of the schedule of the sea of nodes, its pass pipeline, the JIT tier, the prelowering helpers and the
    census, and the evaluation requests that run under them.  The Nix dialects say what a program is; this one says
    how the utility runs it.
  }];
  let useDefaultAttributePrinterParser = 1;
}

class Mlnix_Op<string mnemonic, list<Trait> traits = []> : Op<Mlnix_Dialect, mnemonic, traits>;

//===----------------------------------------------------------------------===//
// Enums
//===----------------------------------------------------------------------===//

def Mlnix_Eager : I32EnumAttrCase<"Eager", 0, "eager">;
def Mlnix_Demand : I32EnumAttrCase<"Demand", 1, "demand">;
def Mlnix_ScheduleKind : I32EnumAttr<"ScheduleKind", "when a lambda body becomes nodes", [Mlnix_Eager, Mlnix_Demand]> {
  let cppNamespace = "::mlir::mlnix";
  let genSpecializedAttr = 0;
}
def Mlnix_ScheduleAttr : EnumAttr<Mlnix_Dialect, Mlnix_ScheduleKind, "schedule">;

def Mlnix_JitOff : I32EnumAttrCase<"Off", 0, "off">;
def Mlnix_JitScalar : I32EnumAttrCase<"Scalar", 1, "scalar">;
def Mlnix_JitTier : I32EnumAttr<"JitTier", "the native tier for hot lambdas", [Mlnix_JitOff, Mlnix_JitScalar]> {
  let cppNamespace = "::mlir::mlnix";
  let genSpecializedAttr = 0;
}
def Mlnix_JitTierAttr : EnumAttr<Mlnix_Dialect, Mlnix_JitTier, "jit_tier">;

def Mlnix_InExpr : I32EnumAttrCase<"Expr", 0, "expr">;
def Mlnix_InFile : I32EnumAttrCase<"File", 1, "file">;
def Mlnix_InputKind : I32EnumAttr<"InputKind", "what an evaluation reads", [Mlnix_InExpr, Mlnix_InFile]> {
  let cppNamespace = "::mlir::mlnix";
  let genSpecializedAttr = 0;
}
def Mlnix_InputKindAttr : EnumAttr<Mlnix_Dialect, Mlnix_InputKind, "input_kind">;

def Mlnix_OutPrint : I32EnumAttrCase<"Print", 0, "print">;
def Mlnix_OutJson : I32EnumAttrCase<"Json", 1, "json">;
def Mlnix_OutXml : I32EnumAttrCase<"Xml", 2, "xml">;
def Mlnix_OutRaw : I32EnumAttrCase<"Raw", 3, "raw">;
def Mlnix_OutputKind : I32EnumAttr<"OutputKind", "how a result is written",
    [Mlnix_OutPrint, Mlnix_OutJson, Mlnix_OutXml, Mlnix_OutRaw]> {
  let cppNamespace = "::mlir::mlnix";
  let genSpecializedAttr = 0;
}
def Mlnix_OutputKindAttr : EnumAttr<Mlnix_Dialect, Mlnix_OutputKind, "output_kind">;

//===----------------------------------------------------------------------===//
// The session
//===----------------------------------------------------------------------===//

def Mlnix_SessionOp : Mlnix_Op<"session", [Symbol, SingleBlock, NoTerminator, IsolatedFromAbove]> {
  let summary = "one configured run of the utility";
  let description = [{
    The body holds at most one each of `mlnix.schedule`, `mlnix.pipeline`, `mlnix.jit`, `mlnix.prelower` and
    `mlnix.census` (the verifier counts them), and any number of `mlnix.eval` requests, run in order under those
    settings.  `store_root` is MLNIX_STORE_ROOT (tools/mlnix.cpp: the real directory that holds /nix/store) and
    `state_dir` is MLNIX_STATE_DIR.  A setting a session leaves out keeps the utility's default.
  }];
  let arguments = (ins SymbolNameAttr:$sym_name, OptionalAttr<StrAttr>:$store_root, OptionalAttr<StrAttr>:$state_dir);
  let regions = (region SizedRegion<1>:$body);
  let assemblyFormat = "$sym_name attr-dict-with-keyword $body";
  let hasVerifier = 1;
}

class Mlnix_Setting<string mnemonic> : Mlnix_Op<mnemonic, [HasParent<"SessionOp">]>;

//===----------------------------------------------------------------------===//
// Settings
//===----------------------------------------------------------------------===//

def Mlnix_ScheduleOp : Mlnix_Setting<"schedule"> {
  let summary = "when the nodes of a lambda body are made";
  let description = [{
    The sea-of-nodes schedule (docs/SEA-OF-NODES.md).  `eager` makes every node of a file when the file is lowered and
    is the oracle.  `demand` makes none for a lambda body until its first call: the `nix.lambda` carries a pool row and
    the body is minted then.  Read by EvalSettings::deferBodies, which MLNIX_DEFER fills (the variable's presence
    selects `demand`, whatever its value).
  }];
  let arguments = (ins Mlnix_ScheduleAttr:$kind);
  let assemblyFormat = "$kind attr-dict";
}

def Mlnix_PipelineOp : Mlnix_Setting<"pipeline"> {
  let summary = "the passes that rewrite each lowered expression";
  let description = [{
    A comma-separated list of registered pass names, with no `op(...)` wrapper (it would nest under child ops).
    Read by EvalSettings::pipeline, which MLNIX_PIPELINE overrides.  The default is `nix-prims`; `nix-fold` and
    `nix-dce` cost more than they save on real workloads (docs/PERFORMANCE.md).
  }];
  let arguments = (ins StrAttr:$passes);
  let assemblyFormat = "$passes attr-dict";
}

def Mlnix_JitOp : Mlnix_Setting<"jit"> {
  let summary = "the native tier for hot lambdas";
  let description = [{
    `scalar` is the guarded scalar tier (lib/Eval/ScalarJIT.cpp), on when MLNIX_JIT is 1.  `threshold` is the number
    of calls after which a lambda is compiled, 1 to 1,000,000, default 1024 (MLNIX_JIT_THRESHOLD) and `opt` the LLVM optimization level, 0 to 3
    (MLNIX_JIT_OPT).  Both are meaningful only for `scalar`; the verifier refuses them on `off`.
  }];
  let arguments = (ins Mlnix_JitTierAttr:$tier,
                       OptionalAttr<ConfinedAttr<I32Attr, [IntMinValue<1>, IntMaxValue<1000000>]>>:$threshold,
                       OptionalAttr<ConfinedAttr<I32Attr, [IntMinValue<0>, IntMaxValue<3>]>>:$opt);
  let assemblyFormat = "$tier (`threshold` $threshold^)? (`opt` $opt^)? attr-dict";
  let hasVerifier = 1;
}

def Mlnix_PrelowerOp : Mlnix_Setting<"prelower"> {
  let summary = "helper threads that lower files before the evaluator asks";
  let description = [{
    `threads` helpers, 1 to 8 (MLNIX_PRELOWER_THREADS; lib/Eval/Eval.cpp clamps the variable to the same range).  The
    files come from `list` (MLNIX_PRELOWER_LIST: a file of paths) or from a replayed prefetch record
    (MLNIX_PRELOWER with MLNIX_PREFETCH).
  }];
  let arguments = (ins ConfinedAttr<I32Attr, [IntMinValue<1>, IntMaxValue<8>]>:$threads, OptionalAttr<StrAttr>:$list);
  let assemblyFormat = "`threads` $threads (`list` $list^)? attr-dict";
}

def Mlnix_CensusOp : Mlnix_Setting<"census"> {
  let summary = "count what a run is made of";
  let description = [{
    Turns on the statistics of a run (MLNIX_STATS, written to stderr).  `top` bounds the ranked tables
    (MLNIX_STATS_TOP).  The counters sit behind one flag in out-of-line hooks, so a session without this op pays for
    none of them.
  }];
  let arguments = (ins OptionalAttr<ConfinedAttr<I32Attr, [IntMinValue<1>]>>:$top);
  let assemblyFormat = "(`top` $top^)? attr-dict";
}

//===----------------------------------------------------------------------===//
// Requests
//===----------------------------------------------------------------------===//

def Mlnix_EvalOp : Mlnix_Op<"eval", [HasParent<"SessionOp">]> {
  let summary = "evaluate an expression or a file under the session's settings";
  let description = [{
    `expr` is the text of a Nix expression (-E) and `file` a path.  `strict` forces the result deeply (--strict).
    `output` is how the value is written (--json, --xml, --raw; `print` is the default form).  The request is the
    tools/mlnix.cpp `nix-instantiate --eval` path; it produces no SSA value, since its result is the process's output.
  }];
  let arguments = (ins Mlnix_InputKindAttr:$input, StrAttr:$source, UnitAttr:$strict,
                       DefaultValuedAttr<Mlnix_OutputKindAttr, "::mlir::mlnix::OutputKind::Print">:$output);
  let assemblyFormat = "$input $source (`strict` $strict^)? (`output` $output^)? attr-dict";
}

#endif // MLNIX_CONTROL_TD
