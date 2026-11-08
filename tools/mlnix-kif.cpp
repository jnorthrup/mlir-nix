//===- mlnix-kif.cpp - KIF files into kif theories, and the chase -----------===//
//
//   mlnix-kif [--ontology F.kif]... [--chase] [--dump] [--stats] [-o OUT.mlir] F.kif...
//
// The files after the options are one theory, @kb (a bag: equal terms of all of them are one node); --ontology files are a
// second, @ontology, which @kb names (what `(instance X Class)` means in a premise).  --chase runs kif-chase; --dump prints
// the closure (KifChase.cpp's dumpClosure: the line format scripts/kif-oracle.py compares); --stats prints counts, time and
// peak RSS to stderr; -o writes the module (default: nothing when --dump or --stats is given, else stdout).
//
//===----------------------------------------------------------------------===//

#include "NixDialect/Kif.h"
#include "NixDialect/NixDialect.h"
#include "NixDialect/Sumo.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Pass/PassRegistry.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/Support/Format.h"
#include "llvm/Support/MemoryBuffer.h"
#include "llvm/Support/ToolOutputFile.h"
#include "llvm/Support/raw_ostream.h"

#include <sys/resource.h>
#include <time.h>

using namespace mlir;

static double seconds() {
  timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return double(t.tv_sec) + t.tv_nsec / 1e9;
}
static double peakMB() {
  rusage ru;
  getrusage(RUSAGE_SELF, &ru);
#ifdef __APPLE__
  return ru.ru_maxrss / 1048576.0;
#else
  return ru.ru_maxrss / 1024.0;
#endif
}

int main(int argc, char **argv) {
  llvm::SmallVector<llvm::StringRef> kb, onto;
  bool chase = false, dump = false, stats = false;
  llvm::StringRef out;
  for (int i = 1; i < argc; i++) {
    llvm::StringRef a = argv[i];
    if (a == "--ontology" && i + 1 < argc) onto.push_back(argv[++i]);
    else if (a == "--chase") chase = true;
    else if (a == "--dump") dump = true;
    else if (a == "--stats") stats = true;
    else if (a == "-o" && i + 1 < argc) out = argv[++i];
    else if (a.starts_with("-")) { llvm::errs() << "mlnix-kif: unknown option " << a << "\n"; return 2; }
    else kb.push_back(a);
  }
  double t0 = seconds();
  DialectRegistry registry;
  registry.insert<kif::KifDialect, sumo::SumoDialect>();
  MLIRContext ctx(registry);
  ctx.loadAllAvailableDialects();
  kif::registerKifPasses();
  OpBuilder b(&ctx);
  Location loc = UnknownLoc::get(&ctx);
  OwningOpRef<ModuleOp> module = ModuleOp::create(loc);
  b.setInsertionPointToEnd(module->getBody());

  uint64_t forms = 0;
  auto read = [&](llvm::StringRef name, llvm::ArrayRef<llvm::StringRef> files, FlatSymbolRefAttr ontology) -> bool {
    if (files.empty()) return true;
    llvm::SmallVector<llvm::StringRef> names(files.begin(), files.end());
    auto t = kif::TheoryOp::create(b, loc, b.getStringAttr(name), b.getStrArrayAttr(names), ontology);
    t.getBody().emplaceBlock();
    kif::KifInterner *in = kif::newInterner(t);
    for (auto [i, f] : llvm::enumerate(files)) {
      auto buf = llvm::MemoryBuffer::getFile(f, /*IsText=*/false, /*RequiresNullTerminator=*/false);
      if (!buf) { llvm::errs() << "mlnix-kif: " << f << ": " << buf.getError().message() << "\n"; return false; }
      if (failed(kif::importKif(*in, f, (*buf)->getBuffer(), int32_t(i)))) return false;
    }
    uint64_t atoms, vars, lists;
    kif::internCounts(*in, atoms, vars, lists);
    kif::freeInterner(in);
    uint64_t f = 0, r = 0;
    for (Operation &op : t.getBody().front()) f += isa<kif::FactOp>(op), r += isa<kif::RuleOp>(op);
    forms += f + r;
    if (stats)
      llvm::errs() << llvm::format("@%.*s: %zu files, %llu forms (%llu facts, %llu rules); %llu atoms, %llu variables, %llu lists\n",
                                   int(name.size()), name.data(), files.size(), (unsigned long long)(f + r), (unsigned long long)f,
                                   (unsigned long long)r, (unsigned long long)atoms, (unsigned long long)vars, (unsigned long long)lists);
    return true;
  };
  if (!read("ontology", onto, FlatSymbolRefAttr())) return 1;
  if (!read("kb", kb, onto.empty() ? FlatSymbolRefAttr() : FlatSymbolRefAttr::get(&ctx, "ontology"))) return 1;
  double t1 = seconds();
  if (stats) llvm::errs() << llvm::format("read: %.2f s, peak RSS %.0f MB\n", t1 - t0, peakMB());
  if (chase) {
    PassManager pm(&ctx);
    if (failed(parsePassPipeline("kif-chase", pm)) || failed(pm.run(*module))) return 1;
    if (stats) {
      uint64_t d = 0;
      module->walk([&](kif::DerivedOp) { d++; });
      llvm::errs() << llvm::format("chase: %llu derived, %.2f s, peak RSS %.0f MB\n", (unsigned long long)d, seconds() - t1, peakMB());
    }
  }
  if (dump)
    module->walk([&](kif::TheoryOp t) { if (t.getSymName() == "kb") kif::dumpClosure(t, llvm::outs()); });
  if (!out.empty() || (!dump && !stats)) {
    std::error_code ec;
    llvm::ToolOutputFile f(out.empty() ? "-" : out, ec, llvm::sys::fs::OF_None);
    if (ec) { llvm::errs() << "mlnix-kif: " << out << ": " << ec.message() << "\n"; return 1; }
    module->print(f.os());
    f.keep();
  }
  return 0;
}
