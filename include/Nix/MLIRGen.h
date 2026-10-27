//===- MLIRGen.h - Lower the Nix AST to the nix dialect -------*- C++ -*-===//
#ifndef NIX_MLIRGEN_H
#define NIX_MLIRGEN_H

#include "Composite/Pack.h"
#include "Composite/Series.h"
#include "Nix/AST.h"
#include "NixDialect/NixDialect.h"
#include "mlir/IR/BuiltinOps.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"

#include <functional>
#include <memory>
#include <unordered_map>
#include <vector>

namespace nixev { struct RegionInfo; }

namespace nixfe {

/// A name free in a lambda: used in its body (or in a formal default) and bound outside it.
struct FreeName {
  llvm::StringRef name; // into the retained AST
  Pos pos;              // the first use outside every inner `with`: where an undefined variable is reported
  bool strict;          // some use is outside every inner `with`; inside one the name may be dynamic
};
/// The free names of each lambda, computed once.  A body is walked once however deep the lambdas nest:
/// an enclosing walk reads the set of a nested lambda instead of walking it again.
using FreeMemo = std::unordered_map<const ExprLambda *, std::vector<FreeName>>;

/// The `body_index` of a deferred nix.lambda: `file j row`, packed in one word.  Issued by the generator,
/// so reading it back is unchecked.
using BodyIndex = ::join::TwInt;

/// A pool row read out: the expression, the op that waits for its body, how many leading captures are
/// the `with` chain (innermost first), and the names of the captures after them.
struct Row {
  const ExprLambda *expr = nullptr;
  mlir::Operation *op = nullptr;
  unsigned withs = 0;
  llvm::SmallVector<llvm::StringRef, 8> names;
};

/// The instance pool of deferred lambdas of one lowered file: the sea of nodes at lambda grain.
/// Rows accumulate as lowering defers a lambda and drain as evaluation mints its body.
struct FilePool {
  struct Col {
    enum : size_t { Expr, Op, Withs, Names, Body };
  };
  uint32_t file;                  // this pool's index in EvalState::pools: the `a` of every body_index
  std::shared_ptr<Origin> origin; // one origin for every row
  composite::Cursor<const ExprLambda *, mlir::Operation *, uint32_t, ::join::TwInt, nixev::RegionInfo *> rows{
      {"expr", "op", "withs", "names", "body"}};
  composite::MutableSeries<llvm::StringRef> nameCol; // the names of every row, one after another

  FilePool(uint32_t file, std::shared_ptr<Origin> origin) : file(file), origin(std::move(origin)) {}

  /// Accumulate a lambda.  The result is its row, the `b` of its body_index.
  uint32_t defer(const ExprLambda *l, unsigned withs, llvm::ArrayRef<llvm::StringRef> names) {
    ::join::TwInt span(nameCol.size(), names.size()); // start j count, into nameCol
    for (llvm::StringRef n : names) nameCol.append(n);
    return rows.append(l, nullptr, withs, span, nullptr);
  }
  void attach(uint32_t row, mlir::Operation *op) { rows.col<Col::Op>()[row] = op; }
  Row read(uint32_t row) const {
    Row r;
    r.expr = rows.col<Col::Expr>()[row];
    r.op = rows.col<Col::Op>()[row];
    r.withs = rows.col<Col::Withs>()[row];
    ::join::TwInt span = rows.col<Col::Names>()[row];
    for (uint32_t i = 0; i < span.second(); i++) r.names.push_back(nameCol[span.first() + i]);
    return r;
  }
  /// The body is minted: the expression and the op leave the pool, the row keeps its anchor (Body).
  void drain(uint32_t row) {
    rows.col<Col::Expr>().drain(row);
    rows.col<Col::Op>().drain(row);
  }
};

struct GenOptions {
  /// Names visible in the global base environment (true/false/null, map,
  /// builtins, __sub, ...).
  std::function<bool(llvm::StringRef)> isBaseName;
  /// Extra lexical scope for scopedImport.  When non-empty the generated
  /// expression is `scope: <expr>`, and these names resolve to `scope.name`.
  std::vector<std::string> scopeNames;
  bool scoped = false;
  /// Sea-of-nodes schedule (MLNIX_DEFER): mint no lambda body at lowering time.  The op carries
  /// the captures and a `body_index` into `pool`; the body is minted on the first call.
  /// False (or no pool): mint everything, as before.
  bool deferBodies = false;
  FilePool *pool = nullptr;
  FreeMemo *freeMemo = nullptr;
};

/// Lower `e` into a new `nix.expr @symName` appended to `module`.
/// Throws ParseError on static errors (undefined variables).
mlir::nix::ExprOp genExpr(mlir::ModuleOp module, const Expr *e,
                          std::shared_ptr<Origin> origin, llvm::StringRef symName,
                          const GenOptions &opts);

/// Mint the body of a deferred lambda from its pool row: the demand half of the schedule.  The same
/// generator path as genExpr, so eager and demand-minted bodies are the same ops.
void mintBody(mlir::nix::LambdaOp lam, std::shared_ptr<Origin> origin, const Row &r,
              const GenOptions &opts);

} // namespace nixfe

#endif
