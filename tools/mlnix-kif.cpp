//===- mlnix-kif.cpp - KIF files into kif theories, and the chase -----------===//
//
//   mlnix-kif [--ontology F.kif]... [--chase] [--dump] [--lean OUT.ndjson [--lean-piece N]] [--tptp OUT.p] [--stats]
//             [--query Q.mlir]... [--pass PIPELINE]... [--emit-bytecode] [-o OUT.mlir] F.kif...
//
// The files after the options are one theory, @kb (a bag: equal terms of all of them are one node); --ontology files are a
// second, @ontology, which @kb names (what `(instance X Class)` means in a premise).  --chase runs kif-chase; --dump prints
// the closure (KifChase.cpp's dumpClosure: the line format scripts/kif-oracle.py compares); --lean writes the closure's
// proofs as one Lean theorem in lean4export's format (KifLean.cpp; `-` is stdout), for a Lean kernel to check, or as
// theorems of at most N lets each with --lean-piece N (a kernel's depth bounds one theorem); --tptp writes @kb as a TPTP
// problem in FOF, as SigmaKEE translates a KB (KifTptp.cpp; a test's (query F) is the conjecture); --stats
// prints counts, time and peak RSS to stderr; each --query reads a module of queries over the theories into the same module (a
// kif.terms @kb is the theory read here, never printed and parsed again: PRELOAD-DIALECTS step 6), and each --pass runs a
// pipeline on it after the chase (`--pass kif-to-trikeshed,trikeshed-lower-cursors` lays the tables out and lowers the
// queries); -o writes the module (default: nothing when --dump, --lean, --tptp or --stats is given, else stdout), as
// MLIR bytecode with --emit-bytecode (the tables' raw bytes, which mlir-opt reads as it reads text).
//
//===----------------------------------------------------------------------===//

#include "NixDialect/Kif.h"
#include "NixDialect/NixDialect.h"
#include "NixDialect/Sumo.h"

#include "Composite/TrikeShed.h"
#include "Composite/Vocab.h"

#include "mlir/Bytecode/BytecodeWriter.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/Verifier.h"
#include "mlir/Parser/Parser.h"
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
  llvm::SmallVector<llvm::StringRef> kb, onto, queries, passes;
  bool chase = false, dump = false, stats = false, bytecode = false;
  llvm::StringRef out, lean, tptp;
  unsigned piece = 0;
  for (int i = 1; i < argc; i++) {
    llvm::StringRef a = argv[i];
    if (a == "--ontology" && i + 1 < argc) onto.push_back(argv[++i]);
    else if (a == "--lean" && i + 1 < argc) lean = argv[++i];
    else if (a == "--tptp" && i + 1 < argc) tptp = argv[++i];
    else if (a == "--query" && i + 1 < argc) queries.push_back(argv[++i]);
    else if (a == "--pass" && i + 1 < argc) passes.push_back(argv[++i]);
    else if (a == "--emit-bytecode") bytecode = true;
    else if (a == "--lean-piece" && i + 1 < argc) {
      if (llvm::StringRef(argv[++i]).getAsInteger(10, piece) || !piece) {
        llvm::errs() << "mlnix-kif: --lean-piece takes a number of lets, more than 0\n";
        return 2;
      }
    }
    else if (a == "--chase") chase = true;
    else if (a == "--dump") dump = true;
    else if (a == "--stats") stats = true;
    else if (a == "-o" && i + 1 < argc) out = argv[++i];
    else if (a.starts_with("-")) { llvm::errs() << "mlnix-kif: unknown option " << a << "\n"; return 2; }
    else kb.push_back(a);
  }
  if (!lean.empty() && !chase) { llvm::errs() << "mlnix-kif: --lean writes the chase's proofs: give --chase too\n"; return 2; }
  if (piece && lean.empty()) { llvm::errs() << "mlnix-kif: --lean-piece divides what --lean writes: give --lean too\n"; return 2; }
  double t0 = seconds();
  DialectRegistry registry;
  registry.insert<kif::KifDialect, sumo::SumoDialect, arith::ArithDialect, func::FuncDialect, memref::MemRefDialect,
                  scf::SCFDialect>();
  composite::registerTrikeShedDialect(registry);
  MLIRContext ctx(registry);
  ctx.loadAllAvailableDialects();
  kif::registerKifPasses();
  composite::registerTrikeShedPasses();
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
  for (llvm::StringRef q : queries)
    if (failed(parseSourceFile(q, module->getBody(), ParserConfig(&ctx, /*verifyAfterParse=*/false)))) return 1;
  if (!queries.empty() && failed(verify(*module))) return 1; // once all of it is in one module: kif.terms names its theory
  for (llvm::StringRef p : passes) {
    double t4 = seconds();
    PassManager pm(&ctx);
    if (failed(parsePassPipeline(p, pm)) || failed(pm.run(*module))) return 1;
    if (stats) llvm::errs() << llvm::format("%.*s: %.2f s, peak RSS %.0f MB\n", int(p.size()), p.data(), seconds() - t4, peakMB());
  }
  kif::TheoryOp kbTheory;
  module->walk([&](kif::TheoryOp t) { if (t.getSymName() == "kb") kbTheory = t; });
  if (dump && kbTheory) kif::dumpClosure(kbTheory, llvm::outs());
  // a file written whole or not at all: kept only when `body` succeeds
  auto write = [&](llvm::StringRef path, llvm::StringRef shown, composite::Fn<bool(llvm::raw_ostream &)> body) {
    std::error_code ec; // raw_fd_ostream's constructor reports through one
    llvm::ToolOutputFile f(path, ec, llvm::sys::fs::OF_None);
    if (ec) { llvm::errs() << "mlnix-kif: " << shown << ": " << ec.message() << "\n"; return false; }
    if (!body(f.os())) return false;
    f.keep();
    return true;
  };
  double t2 = seconds();
  if (!lean.empty()) {
    auto proofs = [&](llvm::raw_ostream &os) { return kbTheory && succeeded(kif::exportLean(kbTheory, os, piece)); };
    if (!write(lean, lean, proofs)) return 1;
    if (stats) llvm::errs() << llvm::format("lean: %.2f s, peak RSS %.0f MB\n", seconds() - t2, peakMB());
  }
  double t3 = seconds();
  if (!tptp.empty()) {
    auto problem = [&](llvm::raw_ostream &os) { return kbTheory && succeeded(kif::exportTptp(kbTheory, os)); };
    if (!write(tptp, tptp, problem)) return 1;
    if (stats) llvm::errs() << llvm::format("tptp: %.2f s, peak RSS %.0f MB\n", seconds() - t3, peakMB());
  }
  auto ir = [&](llvm::raw_ostream &os) {
    if (bytecode) return succeeded(writeBytecodeToFile(*module, os));
    module->print(os);
    return true;
  };
  if ((!out.empty() || (!dump && !stats && lean.empty() && tptp.empty())) && !write(out.empty() ? "-" : out, out, ir)) return 1;
  return 0;
}
