//===- MLIRGen.h - Parse a source into the nix dialect ----------*- C++ -*-===//
//
// No tree is built: the parser lowers as it reads (lib/Frontend/Parser.cpp).  A lambda whose body waits for its first
// call (the demand schedule) is kept as where it starts in its source, and its body is parsed again from there.
//
//===----------------------------------------------------------------------===//
#ifndef NIX_MLIRGEN_H
#define NIX_MLIRGEN_H

#include "Composite/Pack.h"
#include "Composite/Series.h"
#include "Nix/Confix.h"
#include "Nix/Source.h"
#include "NixDialect/NixDialect.h"
#include "mlir/IR/BuiltinOps.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"

#include <functional>
#include <memory>
#include <vector>

namespace nixev { struct RegionInfo; }

namespace nixfe {

/// A name free in a lambda: used in its body (or in a formal default) and bound outside it.
struct FreeName {
  Name name;
  Pos pos;     // the first use outside every inner `with`: where an undefined variable is reported
  bool strict; // some use is outside every inner `with`; inside one the name may be dynamic
};

/// The `body_index` of a deferred nix.lambda: `file j row`, packed in one word.  Issued by the generator,
/// so reading it back is unchecked.
using BodyIndex = ::join::TwInt;

/// The instance pool of deferred lambdas of one lowered file: the sea of nodes at lambda grain.  Rows accumulate as
/// lowering defers a lambda and drain as evaluation mints its body.  A body is parsed again from where its lambda
/// starts, with the source's bands and statements (kept here) for its groups; what a skim of an enclosing body learned
/// of a lambda in it (`seen`: where it ends, what it reads) spares it a second skim.
struct FilePool {
  struct Seen {
    uint32_t end;
    Pos endPos;
    ::join::TwInt free; // start j count, into freeCol
  };
  uint32_t file;                  // this pool's index in EvalState::pools: the `a` of every body_index
  std::shared_ptr<Origin> origin; // one origin for every row
  ParseOptions opts;              // the source's, without lints: a body parsed again warns no second time
  confix::Bands bands;
  composite::Cursor<uint32_t, Pos, mlir::Operation *, uint32_t, ::join::TwInt, nixev::RegionInfo *> rows{PoolCol{}};
  composite::MutableSeries<llvm::StringRef> nameCol; // the names of every row, one after another
  llvm::DenseMap<uint32_t, Seen> seen;
  std::vector<FreeName> freeCol;

  FilePool(uint32_t file, std::shared_ptr<Origin> origin, const ParseOptions &po)
      : file(file), origin(std::move(origin)), opts(po) {
    opts.lintAbsolutePaths = opts.lintShortPaths = opts.lintUrls = Lint::Ignore;
    opts.onWarning = nullptr;
  }

  /// Accumulate a lambda.  The result is its row, the `b` of its body_index.
  uint32_t defer(uint32_t at, Pos pos, unsigned withs, llvm::ArrayRef<llvm::StringRef> names) {
    ::join::TwInt span(nameCol.size(), names.size()); // start j count, into nameCol
    for (llvm::StringRef n : names) nameCol.append(n);
    return rows.append(at, pos, nullptr, withs, span, nullptr);
  }
  void attach(uint32_t row, mlir::Operation *op) { rows.col<PoolCol::Op>()[row] = op; }
  /// The body is minted: the op leaves the pool, the row keeps its anchor (Body).
  void drain(uint32_t row) { rows.col<PoolCol::Op>().drain(row); }
  void see(uint32_t at, uint32_t end, Pos endPos, llvm::ArrayRef<FreeName> free) {
    seen[at] = Seen{end, endPos, ::join::TwInt(uint32_t(freeCol.size()), uint32_t(free.size()))};
    freeCol.insert(freeCol.end(), free.begin(), free.end());
  }
};

struct GenOptions {
  /// Names visible in the global base environment (true/false/null, map,
  /// builtins, __sub, ...).
  std::function<bool(llvm::StringRef)> isBaseName;
  /// Extra lexical scope for scopedImport.  When non-empty the generated
  /// expression is `scope: <expr>`, and these names resolve to `scope.name`.
  composite::MutableSeries<std::string> scopeNames;
  bool scoped = false;
  /// Sea-of-nodes schedule (MLNIX_DEFER): mint no lambda body at lowering time.  The op carries
  /// the captures and a `body_index` into `pool`; the body is minted on the first call.
  bool deferBodies = false;
  FilePool *pool = nullptr;
};

/// Parse `origin` into a new `nix.expr @symName` appended to `module`.
/// Throws ParseError on syntax errors and static errors (undefined variables).
mlir::nix::ExprOp genExpr(mlir::ModuleOp module, std::shared_ptr<Origin> origin, const ParseOptions &po,
                          llvm::StringRef symName, const GenOptions &opts);

/// Mint the body of a deferred lambda from its pool row: the demand half of the schedule.  The same
/// parse as genExpr's, so eager and demand-minted bodies are the same ops.
void mintBody(mlir::nix::LambdaOp lam, FilePool &pool, uint32_t row, const GenOptions &opts);

} // namespace nixfe

#endif
