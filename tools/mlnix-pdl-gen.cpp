//===- mlnix-pdl-gen.cpp - generate / inspect the PDL devirtualization rules ===//
//
//   mlnix-pdl-gen --count        number of rules and patterns
//   mlnix-pdl-gen --pdl          pdl.pattern module built with OpBuilder (text)
//   mlnix-pdl-gen --lowered      the same after PDL -> PDL interpreter lowering
//   mlnix-pdl-gen --pdll         PDLL source for the same rules
//   mlnix-pdl-gen --time [FILE]  cold setup timing (build/parse, lower, bytecode)
//   mlnix-pdl-gen --bench        ns per nix.apply of devirtualizePrims, by kind of callee
//                                (engine from MLNIX_DEVIRT, as in the evaluator)
//   mlnix-pdl-gen --time-split F cold setup timing of the `mlir-pdll -x=cpp` route:
//                                F holds one PDL pattern text per NUL-separated chunk,
//                                each parsed on its own and merged
//
//===----------------------------------------------------------------------===//

#include "NixDialect/NixDevirtPDL.h"
#include "NixDialect/NixPrims.h"

#include "mlir/Dialect/PDL/IR/PDL.h"
#include "mlir/Dialect/PDLInterp/IR/PDLInterp.h"
#include "mlir/IR/MLIRContext.h"
#include "llvm/Support/raw_ostream.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Parser/Parser.h"
#include "mlir/Rewrite/FrozenRewritePatternSet.h"
#include "llvm/Support/MemoryBuffer.h"

#include "llvm/Support/Format.h"
#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <cstring>

using namespace mlir;

int main(int argc, char **argv) {
  std::string mode = argc > 1 ? argv[1] : "--count";
  if (mode == "--bench")
    setenv("MLNIX_DEVIRT_TIME", "1", 1);
  if (mode == "--time") {
    setenv("MLNIX_DEVIRT", argc > 2 ? (std::string("pdl:") + argv[2]).c_str() : "pdl", 1);
    setenv("MLNIX_DEVIRT_TIME", "1", 1);
  }
  MLIRContext ctx;
  ctx.disableMultithreading(); // like the evaluator
  nix::loadNixDialects(ctx);
  auto *core = ctx.getLoadedDialect<nix::NixDialect>();

  if (mode == "--count") {
    llvm::outs() << "primops " << core->prims.size() << "  patterns " << nix::countDevirtPatterns(*core) << "\n";
  } else if (mode == "--pdll") {
    llvm::outs() << nix::emitDevirtPDLL(*core);
  } else if (mode == "--pdl" || mode == "--lowered") {
    ctx.getOrLoadDialect<pdl::PDLDialect>();
    ctx.getOrLoadDialect<pdl_interp::PDLInterpDialect>();
    OwningOpRef<ModuleOp> m = nix::buildDevirtPDLModule(&ctx);
    if (mode == "--lowered" && failed(nix::lowerDevirtPDL(*m)))
      return 1;
    m->print(llvm::outs());
    llvm::outs() << "\n";
  } else if (mode == "--time") {
    // Compiles the patterns exactly as the evaluator does on first use, then
    // exits; DevirtStats prints the breakdown.
    OwningOpRef<ModuleOp> m = ModuleOp::create(UnknownLoc::get(&ctx));
    nix::devirtualizePrimsPDL(*m);
  } else if (mode == "--bench") {
    constexpr unsigned N = 5000, RUNS = 15;
    struct Kind {
      const char *name;
      const char *callee; // ops defining %c, placed where the applies are
      const char *apply;  // the apply, with %c as callee
      bool inLambda;      // applies live in a lambda body (callee may use %arg0)
    };
    const Kind kinds[] = {
        {"callee = lambda parameter", "", "nix.apply %arg0(%x, %y)", true},
        {"callee = lib.foo (select on parameter)", "%c = nix.select %arg0 [\"foo\"]", "nix.apply %c(%x)", true},
        {"callee = builtins.nope (select on builtins, not a primop)", "%c = nix.select %b [\"nope\"]",
         "nix.apply %c(%x)", false},
        {"callee = nix.builtin \"nope\"", "%c = nix.builtin \"nope\"", "nix.apply %c(%x)", false},
        {"callee = nix.with_var", "%c = nix.with_var \"foo\" in %x", "nix.apply %c(%x)", false},
        {"__add 1 2 (match, direct)", "%c = nix.builtin \"__add\"", "nix.apply %c(%x, %y)", false},
        {"builtins.add 1 2 (match, select)", "%c = nix.select %b [\"add\"]", "nix.apply %c(%x, %y)", false},
        {"__add 1 (partial, no match)", "%c = nix.builtin \"__add\"", "nix.apply %c(%x)", false},
        {"__head l 1 (oversaturated, match)", "%c = nix.builtin \"__head\"", "nix.apply %c(%l, %x)", false},
        {"(not a nix.apply: nix.int)", "", "nix.int 7", false},
    };
    auto *devirtCfg = &nix::devirtConfig();
    llvm::outs() << "engine: " << (devirtCfg->mode == nix::DevirtMode::Cpp ? "cpp" : devirtCfg->mode == nix::DevirtMode::PDL ? "pdl" : "pdl-apply") << "\n";
    for (const Kind &k : kinds) {
      std::string text = "nix.expr @bench {\n  %x = nix.int 1\n  %y = nix.int 2\n  %b = nix.builtin \"builtins\"\n  %l = nix.list [%x]\n";
      std::string body = std::string("    ") + k.callee + "\n";
      for (unsigned i = 0; i < N; ++i) body += "    %a" + std::to_string(i) + " = " + k.apply + "\n";
      if (k.inLambda)
        text += "  %lam = nix.lambda {\n  ^bb0(%arg0: !nix.value):\n" + body + "    nix.return %arg0\n  }\n";
      else
        text += body;
      text += "  nix.return %x\n}\n";
      std::vector<double> per;
      for (unsigned r = 0; r < RUNS + 2; ++r) {
        OwningOpRef<ModuleOp> m = parseSourceString<ModuleOp>(text, &ctx);
        if (!m) return 1;
        Operation *expr = &m->getBody()->front();
        auto &st = nix::devirtStats();
        double before = st.walkMs;
        nix::devirtualizePrims(expr);
        if (r >= 2) per.push_back((st.walkMs - before) * 1e6 / N);
      }
      std::sort(per.begin(), per.end());
      llvm::outs() << llvm::format("  %-62s %8.1f ns/op (median of %u runs of %u)\n", k.name, per[per.size() / 2], RUNS, N);
    }
    // Fixed cost per call (the evaluator calls devirtualizePrims once per file).
    {
      OwningOpRef<ModuleOp> m = parseSourceString<ModuleOp>(
          "nix.expr @tiny {\n  %x = nix.int 1\n  %c = nix.builtin \"__add\"\n  %a = nix.apply %c(%x)\n  nix.return %a\n}\n", &ctx);
      Operation *expr = &m->getBody()->front();
      constexpr unsigned CALLS = 20000;
      auto &st = nix::devirtStats();
      double before = st.walkMs;
      for (unsigned i = 0; i < CALLS; ++i) nix::devirtualizePrims(expr);
      llvm::outs() << llvm::format("  %-62s %8.2f us/call (%u calls)\n", "per-call fixed cost (3-op expr, nothing to rewrite)", (st.walkMs - before) * 1e3 / CALLS, CALLS);
    }
  } else if (mode == "--time-split" && argc > 2) {
    auto ms = [](auto a, auto b) { return std::chrono::duration<double, std::milli>(b - a).count(); };
    auto buf = llvm::MemoryBuffer::getFile(argv[2]);
    if (!buf) return 1;
    auto t0 = std::chrono::steady_clock::now();
    ctx.getOrLoadDialect<pdl::PDLDialect>();
    ctx.getOrLoadDialect<pdl_interp::PDLInterpDialect>();
    RewritePatternSet set(&ctx);
    unsigned n = 0;
    StringRef all = (*buf)->getBuffer();
    while (!all.empty()) {
      auto [chunk, rest] = all.split('\0');
      all = rest;
      if (chunk.empty()) continue;
      set.add(PDLPatternModule(parseSourceString<ModuleOp>(chunk, &ctx)));
      ++n;
    }
    auto t1 = std::chrono::steady_clock::now();
    if (failed(nix::lowerDevirtPDL(set.getPDLPatterns().getModule()))) return 1;
    auto t2 = std::chrono::steady_clock::now();
    FrozenRewritePatternSet frozen(std::move(set));
    auto t3 = std::chrono::steady_clock::now();
    llvm::errs() << "patterns " << n << " build " << ms(t0, t1) << " ms  lower " << ms(t1, t2) << " ms  bytecode "
                 << ms(t2, t3) << " ms\n";
  } else {
    llvm::errs() << "usage: mlnix-pdl-gen --count|--pdl|--lowered|--pdll|--time [FILE]\n";
    return 2;
  }
  return 0;
}
