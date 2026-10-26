//===- NixDevirtPDL.cpp - primop devirtualization as PDL patterns ----------===//
//
// The rewrite of DevirtualizePrimCall (NixDialect.cpp) as `pdl.pattern` ops.
// There is no per-primop C++ here: the patterns are generated from the primop
// registry (NixDialect::prims) as the cross product
//
//     callee spelling  x  arity (from the registry)  x  { exact, oversaturated }
//
//   spelling "direct":  %f = nix.builtin "<key>"
//   spelling "select":  %b = nix.builtin "builtins"; %f = nix.select %b ["<n>"]
//                       where <n> is looked up as __<n> first, then <n>
//
// exact:         nix.apply %f(a0..a{N-1})            -> cont.op(a0..a{N-1})
// oversaturated: nix.apply %f(a0..a{N-1}, e, rest..) -> nix.apply cont.op(..)(e, rest..)
//
// (A partial application has fewer arguments than N: nothing matches it.)
// Dead callee cleanup is not expressed here; see devirtualizePrims().
//
//===----------------------------------------------------------------------===//

#include "NixDialect/NixDevirtPDL.h"

#include "mlir/Conversion/PDLToPDLInterp/PDLToPDLInterp.h"
#include "mlir/Dialect/PDL/IR/PDL.h"
#include "mlir/Dialect/PDL/IR/PDLOps.h"
#include "mlir/Dialect/PDL/IR/PDLTypes.h"
#include "mlir/Dialect/PDLInterp/IR/PDLInterp.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "mlir/Parser/Parser.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Rewrite/FrozenRewritePatternSet.h"
#include "mlir/Rewrite/PatternApplicator.h"
#include "mlir/Transforms/WalkPatternRewriteDriver.h"
#include "llvm/ADT/SmallString.h"
#include "llvm/ADT/StringExtras.h"
#include "llvm/ADT/StringSet.h"
#include "llvm/Support/Format.h"
#include "llvm/Support/raw_ostream.h"

#include <cstdlib>

using namespace mlir;
using namespace mlir::nix;

//===----------------------------------------------------------------------===//
// Configuration and statistics
//===----------------------------------------------------------------------===//

const DevirtConfig &mlir::nix::devirtConfig() {
  static const DevirtConfig cfg = [] {
    DevirtConfig c;
    if (const char *e = getenv("MLNIX_DEVIRT")) {
      StringRef v = e;
      if (v.empty() || v == "cpp") {
        c.mode = DevirtMode::Cpp;
      } else if (v.consume_front("pdl-apply")) {
        c.mode = DevirtMode::PDLApply;
        if (v.consume_front(":"))
          c.file = v.str();
        else if (!v.empty())
          llvm::report_fatal_error("MLNIX_DEVIRT: expected 'cpp', 'pdl[:FILE]' or 'pdl-apply[:FILE]'");
      } else if (v.consume_front("pdl")) {
        c.mode = DevirtMode::PDL;
        if (v.consume_front(":"))
          c.file = v.str();
        else if (!v.empty())
          llvm::report_fatal_error("MLNIX_DEVIRT: expected 'cpp', 'pdl[:FILE]' or 'pdl-apply[:FILE]'");
      } else {
        llvm::report_fatal_error("MLNIX_DEVIRT: expected 'cpp', 'pdl[:FILE]' or 'pdl-apply[:FILE]'");
      }
    }
    c.time = getenv("MLNIX_DEVIRT_TIME") != nullptr;
    return c;
  }();
  return cfg;
}

static bool statsEnabled;

DevirtStats &mlir::nix::devirtStats() {
  static DevirtStats s;
  statsEnabled = devirtConfig().time;
  return s;
}

DevirtStats::~DevirtStats() {
  if (!statsEnabled)
    return;
  const char *names[] = {"cpp", "pdl", "pdl-apply"};
  llvm::errs() << "== devirt (" << names[(int)devirtConfig().mode] << ")\n";
  if (devirtConfig().mode != DevirtMode::Cpp)
    llvm::errs() << llvm::format("  setup: build %.3f ms  lower %.3f ms  bytecode %.3f ms  (sum %.3f ms)\n", buildMs,
                                 lowerMs, bytecodeMs, buildMs + lowerMs + bytecodeMs);
  llvm::errs() << llvm::format("  calls %llu  ops %llu  nix.apply %llu\n", (unsigned long long)calls,
                               (unsigned long long)ops, (unsigned long long)applies);
  llvm::errs() << llvm::format("  walk %.3f ms  (%.1f ns/op, %.1f ns/apply)  cleanup %.3f ms\n", walkMs,
                               ops ? walkMs * 1e6 / ops : 0.0, applies ? walkMs * 1e6 / applies : 0.0, cleanupMs);
}

//===----------------------------------------------------------------------===//
// The rules: spelling x registry entry
//===----------------------------------------------------------------------===//

namespace {
struct Rule {
  bool select;         // false: nix.builtin "<name>"; true: builtins.<name>
  std::string name;    // builtin name / select key
  OperationName op;    // continent op
  unsigned arity;
  std::string primKey; // registry key it resolves to
};

/// Every callee spelling that DevirtualizePrimCall resolves: `nix.builtin
/// "<key>"` for each registry key, and `builtins.<n>` for each n with `__n` or
/// `n` in the registry (`__n` wins, exactly like the C++ pattern's lookup).
SmallVector<Rule> collectRules(NixDialect &core) {
  SmallVector<StringRef> keys;
  for (auto &e : core.prims)
    keys.push_back(e.getKey());
  llvm::sort(keys);
  SmallVector<Rule> rules;
  for (StringRef k : keys) {
    const auto &info = core.prims.find(k)->second;
    rules.push_back({false, k.str(), info.name, info.arity, k.str()});
  }
  llvm::StringSet<> seen;
  for (StringRef k : keys) {
    SmallVector<StringRef, 2> cands;
    if (k.starts_with("__"))
      cands.push_back(k.drop_front(2));
    cands.push_back(k);
    for (StringRef n : cands) {
      if (!seen.insert(n).second)
        continue;
      SmallString<48> internal("__");
      internal += n;
      auto it = core.prims.find(internal);
      if (it == core.prims.end())
        it = core.prims.find(n);
      if (it == core.prims.end())
        continue;
      rules.push_back({true, n.str(), it->second.name, it->second.arity, it->getKey().str()});
    }
  }
  return rules;
}

std::string patternName(const Rule &r, bool over) {
  return std::string(r.select ? "select:" : "direct:") + r.name + (over ? ":over" : ":exact");
}
} // namespace

size_t mlir::nix::countDevirtPatterns(NixDialect &core) { return collectRules(core).size() * 2; }

//===----------------------------------------------------------------------===//
// Building the pdl.pattern ops with OpBuilder
//===----------------------------------------------------------------------===//

namespace {
void buildPattern(OpBuilder &b, const Rule &r, bool over) {
  MLIRContext *ctx = b.getContext();
  Location loc = UnknownLoc::get(ctx);
  Type typeT = pdl::TypeType::get(ctx), valueT = pdl::ValueType::get(ctx);

  auto pattern = pdl::PatternOp::create(b, loc, /*benefit=*/1, StringRef(patternName(r, over)));
  OpBuilder::InsertionGuard guard(b);
  b.setInsertionPointToStart(pattern.getBody());

  auto anyType = [&]() -> Value { return pdl::TypeOp::create(b, loc, typeT, TypeAttr()); };
  auto op = [&](StringRef name, ValueRange operands, ArrayRef<StringRef> attrNames, ValueRange attrs,
                Value resultType) -> Value {
    return pdl::OperationOp::create(b, loc, std::optional<StringRef>(name), operands, attrNames, attrs, resultType);
  };
  auto result0 = [&](Value operation) -> Value { return pdl::ResultOp::create(b, loc, valueT, operation, 0u); };

  // The callee chain.  Result counts are fixed by giving each op one result
  // type, operand counts by listing the operands: `nix.builtin` has none,
  // `nix.select` exactly one (no dynamic keys, no default).
  Value callee;
  if (!r.select) {
    Value nameAttr = pdl::AttributeOp::create(b, loc, Attribute(b.getStringAttr(r.name)));
    callee = result0(op("nix.builtin", {}, {"name"}, nameAttr, anyType()));
  } else {
    Value builtins = pdl::AttributeOp::create(b, loc, Attribute(b.getStringAttr("builtins")));
    Value base = result0(op("nix.builtin", {}, {"name"}, builtins, anyType()));
    Value path = pdl::AttributeOp::create(b, loc, Attribute(b.getArrayAttr({b.getStringAttr(r.name)})));
    callee = result0(op("nix.select", base, {"path"}, path, anyType()));
  }

  // nix.apply %callee(a0..a{N-1} [, extra, rest...]) -> %ty
  Value resTy = anyType();
  SmallVector<Value> args, applyOperands{callee};
  for (unsigned i = 0; i < r.arity; ++i)
    args.push_back(pdl::OperandOp::create(b, loc));
  applyOperands.append(args.begin(), args.end());
  Value extra, rest;
  if (over) {
    extra = pdl::OperandOp::create(b, loc);
    rest = pdl::OperandsOp::create(b, loc);
    applyOperands.push_back(extra);
    applyOperands.push_back(rest);
  }
  Value call = op("nix.apply", applyOperands, {}, {}, resTy);

  auto rewrite = pdl::RewriteOp::create(b, loc, call, StringAttr(), ValueRange());
  Block *body = rewrite.getBodyRegion().empty() ? &rewrite.getBodyRegion().emplaceBlock() : &rewrite.getBodyRegion().front();
  b.setInsertionPointToStart(body);
  Value created = op(r.op.getStringRef(), args, {}, {}, resTy);
  if (over) {
    SmallVector<Value> applyArgs{result0(created), extra, rest};
    created = op("nix.apply", applyArgs, {}, {}, resTy);
  }
  pdl::ReplaceOp::create(b, loc, call, created, ValueRange());
}
} // namespace

OwningOpRef<ModuleOp> mlir::nix::buildDevirtPDLModule(MLIRContext *ctx) {
  ctx->getOrLoadDialect<pdl::PDLDialect>();
  auto *core = ctx->getOrLoadDialect<NixDialect>();
  OwningOpRef<ModuleOp> module = ModuleOp::create(UnknownLoc::get(ctx));
  OpBuilder b(ctx);
  b.setInsertionPointToEnd(module->getBody());
  for (const Rule &r : collectRules(*core))
    for (bool over : {false, true})
      buildPattern(b, r, over);
  return module;
}

//===----------------------------------------------------------------------===//
// PDLL source for the same rules
//===----------------------------------------------------------------------===//

std::string mlir::nix::emitDevirtPDLL(NixDialect &core) {
  std::string text;
  llvm::raw_string_ostream os(text);
  os << "// Generated by mlnix-pdl-gen --pdll from the primop registry; do not edit.\n"
        "// The core ops (nix.apply/builtin/select) are deliberately not described to\n"
        "// PDLL: with their ODS definition it cannot say \"exactly N arguments\".\n"
        "#include \"NixPrims.td\"\n\n";
  unsigned idx = 0;
  for (const Rule &r : collectRules(core)) {
    for (bool over : {false, true}) {
      std::string ident;
      for (char c : patternName(r, over))
        ident += llvm::isAlnum(c) ? c : '_';
      os << "Pattern P" << idx++ << "_" << ident << " {\n  let ty : Type;\n";
      if (!r.select) {
        os << "  let fn = op<nix.builtin> {name = attr<\"\\\"" << r.name << "\\\"\">};\n";
      } else {
        os << "  let b = op<nix.builtin> {name = attr<\"\\\"builtins\\\"\">};\n"
           << "  let fn = op<nix.select>(b.0) {path = attr<\"[\\\"" << r.name << "\\\"]\">};\n";
      }
      os << "  let call = op<nix.apply>(fn.0";
      std::string ops;
      for (unsigned i = 0; i < r.arity; ++i) {
        os << ", a" << i << " : Value";
        ops += (i ? ", a" : "a") + std::to_string(i);
      }
      if (over)
        os << ", extra : Value, rest : ValueRange";
      os << ") -> (ty);\n  rewrite call with {\n";
      os << "    let new = op<" << r.op.getStringRef() << ">(" << (r.arity > 1 ? "(" + ops + ")" : ops) << ") -> (ty);\n";
      if (over)
        os << "    let app = op<nix.apply>(new.0, extra, rest) -> (ty);\n    replace call with app;\n";
      else
        os << "    replace call with new;\n";
      os << "  };\n}\n\n";
    }
  }
  return text;
}

//===----------------------------------------------------------------------===//
// Compilation and the walk
//===----------------------------------------------------------------------===//

/// What FrozenRewritePatternSet does with a PDL module before it builds the
/// bytecode; split out so the two stages can be timed separately.  Afterwards
/// the module holds a pdl_interp matcher and FrozenRewritePatternSet skips its
/// own conversion (it only converts modules that still contain pdl.pattern).
LogicalResult mlir::nix::lowerDevirtPDL(ModuleOp module) {
  auto simplify = [](Operation *op) {
    if (isOpTriviallyDead(op))
      op->erase();
  };
  module.getBody()->walk(simplify);
  DenseMap<Operation *, PDLPatternConfigSet *> configMap;
  PassManager pm(module->getName());
  pm.enableVerifier(false);
  pm.addPass(createConvertPDLToPDLInterpPass(configMap));
  if (failed(pm.run(module)))
    return failure();
  module.getBody()->walk(simplify);
  return success();
}

static FrozenRewritePatternSet &patternsFor(MLIRContext *ctx) {
  auto *core = ctx->getOrLoadDialect<NixDialect>();
  if (core->devirtPDL)
    return *static_cast<FrozenRewritePatternSet *>(core->devirtPDL.get());

  const DevirtConfig &cfg = devirtConfig();
  DevirtStats &st = devirtStats();
  auto t0 = DevirtClock::now();
  ctx->getOrLoadDialect<pdl::PDLDialect>();
  ctx->getOrLoadDialect<pdl_interp::PDLInterpDialect>();
  OwningOpRef<ModuleOp> module =
      cfg.file.empty() ? buildDevirtPDLModule(ctx) : OwningOpRef<ModuleOp>(parseSourceFile<ModuleOp>(cfg.file, ctx));
  if (!module)
    llvm::report_fatal_error("MLNIX_DEVIRT: could not build/read the PDL module");
  auto t1 = DevirtClock::now();
  if (failed(lowerDevirtPDL(*module)))
    llvm::report_fatal_error("MLNIX_DEVIRT: PDL -> PDL interpreter lowering failed");
  auto t2 = DevirtClock::now();
  RewritePatternSet set(PDLPatternModule(std::move(module)));
  auto frozen = std::make_shared<FrozenRewritePatternSet>(std::move(set));
  auto t3 = DevirtClock::now();
  st.buildMs += devirtMs(t0, t1);
  st.lowerMs += devirtMs(t1, t2);
  st.bytecodeMs += devirtMs(t2, t3);
  core->devirtPDL = frozen;
  return *frozen;
}

namespace {
/// PDL has no way to give a created op a location: the bytecode creates every
/// op with a FusedLoc of the locations of *all matched ops* (`select`, `apply`,
/// ...), and the evaluator only understands a FileLineColLoc, so error positions
/// of devirtualized calls would silently disappear.  Give the ops created by a
/// rewrite the location of the op they replace, as DevirtualizePrimCall does.
/// MLNIX_DEVIRT_LOCFIX=0 turns this off (to see the difference).
struct InheritLocation : RewriterBase::Listener {
  SmallVector<Operation *, 2> created;
  void notifyOperationInserted(Operation *op, OpBuilder::InsertPoint) override { created.push_back(op); }
  void notifyOperationReplaced(Operation *op, ValueRange) override {
    for (Operation *c : created)
      c->setLoc(op->getLoc());
    created.clear();
  }
};
} // namespace

void mlir::nix::devirtualizePrimsPDL(Operation *root) {
  FrozenRewritePatternSet &patterns = patternsFor(root->getContext());
  static const bool locFix = [] {
    const char *e = getenv("MLNIX_DEVIRT_LOCFIX");
    return !e || StringRef(e) != "0";
  }();
  InheritLocation inherit;
  RewriterBase::Listener *listener = locFix ? &inherit : nullptr;
  if (devirtConfig().mode == DevirtMode::PDL) {
    walkAndApplyPatterns(root, patterns, listener);
    return;
  }
  // The bytecode matcher is not indexed by root op name: PatternApplicator runs
  // it on every op it is given.  Only hand it the ops the patterns are rooted at.
  PatternApplicator applicator(patterns);
  applicator.applyDefaultCostModel();
  PatternRewriter rewriter(root->getContext());
  rewriter.setListener(listener);
  root->walk([&](ApplyOp op) { (void)applicator.matchAndRewrite(op, rewriter); });
}
