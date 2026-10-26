//===- mlnix-pipebench.cpp - Per-call cost of the optimization drivers ----===//
//
// The evaluator runs its optimization pipeline once per lowered file, many
// thousands of times per run.  This tool measures what one such call costs for
// each way of running the same stages:
//
//   direct   mlir::nix::simplifyExpr(root, options)   (the code the evaluator had)
//   pm       mlir::PassManager built from a textual pipeline, reused
//   transform  a Transform-dialect script, interpreted in-process
//
// on a payload that is a lowered Nix file.  Each iteration clones a pristine
// copy of the payload, runs the driver on it and erases it; the cost of
// clone+erase alone is measured the same way, and subtracted.  The drivers are
// run in rotation over several rounds so that machine noise hits all of them
// alike; the median over rounds is reported.
//
//===----------------------------------------------------------------------===//

#include "Nix/Eval.h"
#include "Nix/Pipeline.h"
#include "NixDialect/NixDialect.h"

#include "mlir/IR/OwningOpRef.h"
#include "llvm/ADT/StringExtras.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/Format.h"
#include "llvm/Support/MemoryBuffer.h"
#include "llvm/Support/raw_ostream.h"

#include <algorithm>
#include <chrono>
#include <functional>
#include <sys/resource.h>
#include <vector>

using namespace mlir;
namespace nd = mlir::nix;

static llvm::cl::opt<unsigned> iters("n", llvm::cl::desc("iterations per driver per round"), llvm::cl::init(2000));
static llvm::cl::opt<unsigned> rounds("r", llvm::cl::desc("rounds (median is reported)"), llvm::cl::init(7));
static llvm::cl::opt<std::string> nixFile("nix", llvm::cl::desc("Nix file to lower and use as the payload"));
static llvm::cl::opt<std::string> nixExpr("E", llvm::cl::desc("Nix expression to use as the payload"),
                                          llvm::cl::init("let xs = [1 2 3]; in { n = builtins.length xs; u = builtins.map (x: x * 2) xs; s = builtins.add 1 2; }"));
static llvm::cl::opt<std::string> stages("stages", llvm::cl::desc("prims | all | empty"), llvm::cl::init("prims"));
static llvm::cl::opt<std::string> mode("mode", llvm::cl::desc("fresh: clone the payload every call; idle: rerun on an already optimized module"),
                                       llvm::cl::init("fresh"));
static llvm::cl::opt<bool> expensive("expensive-checks", llvm::cl::desc("Transform interpreter: expensive checks on"));
static llvm::cl::opt<std::string> only("only", llvm::cl::desc("comma list of drivers to run: direct,pm,pmverify,transform (default: all but pmverify; the baseline always runs)"));
static llvm::cl::opt<unsigned> startup("startup", llvm::cl::desc("instead: time building each pipeline this many times"), llvm::cl::init(0));

using Clock = std::chrono::steady_clock;

static double cpuSeconds() {
  rusage ru;
  getrusage(RUSAGE_SELF, &ru);
  return ru.ru_utime.tv_sec + ru.ru_stime.tv_sec + 1e-6 * (ru.ru_utime.tv_usec + ru.ru_stime.tv_usec);
}

static double median(std::vector<double> v) {
  std::sort(v.begin(), v.end());
  return v[v.size() / 2];
}

// prims, fold, dce as a script (the Transform equivalent of
// `builtin.module(nix-prims,nix-fold,nix-dce)`).
static const char *allStagesScript = R"MLIR(
module attributes {transform.with_named_sequence} {
  transform.named_sequence @__transform_main(%root: !transform.any_op {transform.consumed}) {
    %a = transform.apply_registered_pass "nix-prims" to %root : (!transform.any_op) -> !transform.any_op
    %b = transform.apply_registered_pass "nix-fold" to %a : (!transform.any_op) -> !transform.any_op
    %c = transform.apply_registered_pass "nix-dce" to %b : (!transform.any_op) -> !transform.any_op
    transform.yield
  }
}
)MLIR";

static const char *emptyScript = R"MLIR(
module attributes {transform.with_named_sequence} {
  transform.named_sequence @__transform_main(%root: !transform.any_op {transform.readonly}) {
    transform.yield
  }
}
)MLIR";

struct Driver {
  std::string name;
  std::function<void(ModuleOp)> run;
  std::vector<double> wall, cpu; // ns per call, one entry per round
};

int main(int argc, char **argv) {
  llvm::cl::ParseCommandLineOptions(argc, argv, "per-call cost of the nix optimization drivers\n");

  nixstore::StoreSettings ss;
  ss.readOnly = true;
  ss.realRoot = "/tmp/mlnix-pipebench-root";
  ss.stateDir = "/tmp/mlnix-pipebench-state";
  nixev::EvalSettings es;
  es.optimize = false; // the tool runs the drivers itself
  nixev::EvalState st(es, std::make_shared<nixstore::Store>(ss));

  std::string error;
  auto fail = [&](const char *what) {
    llvm::errs() << "mlnix-pipebench: " << what << ": " << error << "\n";
    return 1;
  };

  // ---- the three ways of building a pipeline ---------------------------------
  std::string pmText = stages == "prims" ? "builtin.module(nix-prims)"
                       : stages == "all" ? "builtin.module(nix-prims,nix-fold,nix-dce)"
                                         : "builtin.module()";
  const char *script = stages == "prims" ? nixpipe::embeddedTransformScript().data()
                       : stages == "all" ? allStagesScript
                                         : emptyScript;
  nd::SimplifyOptions direct;
  direct.devirtualize = stages != "empty";
  direct.fold = direct.dce = stages == "all";

  if (startup) {
    // Cost of *creating* the pipelines (once per EvalState in the evaluator).
    auto timeIt = [&](const char *what, auto &&build) {
      std::vector<double> t;
      for (unsigned i = 0; i < startup; i++) {
        auto t0 = Clock::now();
        auto p = build();
        auto t1 = Clock::now();
        if (!p) { llvm::errs() << what << ": " << error << "\n"; return; }
        t.push_back(std::chrono::duration<double, std::micro>(t1 - t0).count());
      }
      llvm::outs() << llvm::format("%-34s first %9.1f us   median of rest %9.1f us   (n=%u)\n", what, t[0],
                                   t.size() > 1 ? median(std::vector<double>(t.begin() + 1, t.end())) : 0.0, startup.getValue());
    };
    timeIt("PassManager from text (prims)", [&] { return nixpipe::makePassPipeline(st.ctx, "builtin.module(nix-prims)", error); });
    timeIt("PassManager from text (prims,fold,dce)", [&] { return nixpipe::makePassPipeline(st.ctx, "builtin.module(nix-prims,nix-fold,nix-dce)", error); });
    timeIt("Transform script (embedded default)", [&] { return nixpipe::makeTransformPipeline(st.ctx, nixpipe::embeddedTransformScript(), "<embedded>", error); });
    timeIt("Transform script (prims,fold,dce)", [&] { return nixpipe::makeTransformPipeline(st.ctx, allStagesScript, "<all>", error); });
    return 0;
  }

  auto pm = nixpipe::makePassPipeline(st.ctx, pmText, error);
  if (!pm) return fail("pass pipeline");
  auto pmv = nixpipe::makePassPipeline(st.ctx, pmText, error, /*verify=*/true);
  if (!pmv) return fail("pass pipeline (verify)");
  auto tr = nixpipe::makeTransformPipeline(st.ctx, script, "<bench>", error, expensive);
  if (!tr) return fail("transform script");

  // ---- the payload: a lowered Nix file, unoptimized ----------------------------
  std::string text, name = "«bench»", path, baseDir = "/tmp";
  if (!nixFile.empty()) {
    auto buf = llvm::MemoryBuffer::getFile(nixFile);
    if (!buf) { llvm::errs() << "cannot read " << nixFile << "\n"; return 1; }
    text = (*buf)->getBuffer().str();
    name = path = nixFile;
    baseDir = nixstore::dirOf(path);
  } else {
    text = nixExpr;
  }
  std::shared_ptr<nixfe::Origin> origin;
  nixfe::Expr *e = st.parseSource(text, name, path, baseDir, &origin);
  nd::ExprOp lowered = st.lowerToMLIR(e, origin);
  OwningOpRef<ModuleOp> pristine = ModuleOp::create(UnknownLoc::get(&st.ctx));
  pristine->getBody()->push_back(lowered->clone());
  size_t opsBefore = 0, opsAfter = 0;
  pristine->walk([&](Operation *) { ++opsBefore; });
  {
    OwningOpRef<ModuleOp> m(cast<ModuleOp>(pristine->clone()));
    (void)pm->run(*m);
    m->walk([&](Operation *) { ++opsAfter; });
  }

  std::vector<Driver> drivers;
  drivers.push_back({"clone+erase only (baseline)", [](ModuleOp) {}, {}, {}});
  auto wanted = [&](llvm::StringRef n) { return only.empty() ? n != "pmverify" : llvm::is_contained(llvm::split(only.getValue(), ','), n); };
  if (wanted("direct"))
    drivers.push_back({"direct simplifyExpr", [&](ModuleOp m) { nd::simplifyExpr(m, direct); }, {}, {}});
  if (wanted("pm"))
    drivers.push_back({"PassManager (text)", [&](ModuleOp m) { if (failed(pm->run(m))) abort(); }, {}, {}});
  if (wanted("pmverify"))
    drivers.push_back({"PassManager (text, verifier on)", [&](ModuleOp m) { if (failed(pmv->run(m))) abort(); }, {}, {}});
  if (wanted("transform"))
    drivers.push_back({"Transform script", [&](ModuleOp m) { if (failed(tr->run(m))) abort(); }, {}, {}});

  bool idle = mode == "idle";
  OwningOpRef<ModuleOp> idleModule;
  if (idle) {
    idleModule = cast<ModuleOp>(pristine->clone());
    (void)pm->run(*idleModule);
  }

  // Rotate the order of the drivers every round.
  for (unsigned r = 0; r < rounds; r++) {
    for (size_t k = 0; k < drivers.size(); k++) {
      Driver &d = drivers[(k + r) % drivers.size()];
      double c0 = cpuSeconds();
      auto t0 = Clock::now();
      if (idle) {
        if (&d == &drivers[0]) { // baseline of idle mode: the loop itself
          for (unsigned i = 0; i < iters; i++) asm volatile("" ::: "memory");
        } else {
          for (unsigned i = 0; i < iters; i++) d.run(*idleModule);
        }
      } else {
        for (unsigned i = 0; i < iters; i++) {
          OwningOpRef<ModuleOp> m(cast<ModuleOp>(pristine->clone()));
          d.run(*m);
        }
      }
      auto t1 = Clock::now();
      double c1 = cpuSeconds();
      d.wall.push_back(std::chrono::duration<double, std::nano>(t1 - t0).count() / iters);
      d.cpu.push_back((c1 - c0) * 1e9 / iters);
    }
  }

  llvm::outs() << "payload: " << (nixFile.empty() ? "-E expression" : nixFile.getValue()) << ", ops " << opsBefore
               << " lowered, " << opsAfter << " after nix-prims; stages=" << stages << " mode=" << mode
               << " n=" << iters << "x" << rounds << " rounds\n";
  double baseWall = median(drivers[0].wall), baseCpu = median(drivers[0].cpu);
  llvm::outs() << llvm::format("%-30s %12s %12s %12s %12s\n", "driver", "wall ns/call", "cpu ns/call", "net wall", "net cpu");
  for (Driver &d : drivers) {
    double w = median(d.wall), c = median(d.cpu);
    llvm::outs() << llvm::format("%-30s %12.0f %12.0f %12.0f %12.0f\n", d.name.c_str(), w, c, w - baseWall, c - baseCpu);
  }
  return 0;
}
