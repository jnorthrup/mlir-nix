//===- NixDialect.cpp - Nix dialect implementation ------------------------===//

#include "NixDialect/NixDialect.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/DialectImplementation.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Pass/PassRegistry.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"
#include "mlir/Transforms/WalkPatternRewriteDriver.h"
#include "llvm/ADT/SetVector.h"
#include "llvm/ADT/SmallString.h"
#include "llvm/ADT/StringSet.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/TypeSwitch.h"
#include <mutex>

using namespace mlir;
using namespace mlir::nix;

#include "NixDialect/NixDialect.cpp.inc"
#include "NixDialect/NixInterfaces.cpp.inc"

#define GET_TYPEDEF_CLASSES
#include "NixDialect/NixTypes.cpp.inc"

namespace mlir::nix {
/// `[ "a", %k, "b" ]`: literal components are string attributes, computed ones
/// are operands (recorded as unit attributes in `path`).
static ParseResult parseAttrPath(OpAsmParser &p, ArrayAttr &path,
                                 SmallVectorImpl<OpAsmParser::UnresolvedOperand> &dyn) {
  Builder b(p.getContext());
  SmallVector<Attribute> comps;
  if (p.parseLSquare())
    return failure();
  do {
    std::string lit;
    OpAsmParser::UnresolvedOperand operand;
    if (succeeded(p.parseOptionalString(&lit))) {
      comps.push_back(b.getStringAttr(lit));
    } else {
      OptionalParseResult r = p.parseOptionalOperand(operand);
      if (!r.has_value())
        return p.emitError(p.getCurrentLocation(), "expected a string or an operand");
      if (failed(*r))
        return failure();
      dyn.push_back(operand);
      comps.push_back(b.getUnitAttr());
    }
  } while (succeeded(p.parseOptionalComma()));
  if (p.parseRSquare())
    return failure();
  path = b.getArrayAttr(comps);
  return success();
}

static void printAttrPath(OpAsmPrinter &p, Operation *, ArrayAttr path, OperandRange dyn) {
  p << "[";
  unsigned next = 0;
  llvm::interleaveComma(path, p, [&](Attribute a) {
    if (isa<StringAttr>(a))
      p.printAttribute(a);
    else
      p.printOperand(dyn[next++]);
  });
  p << "]";
}

static LogicalResult verifyAttrPath(Operation *op, ArrayAttr path, unsigned numDyn) {
  if (path.empty())
    return op->emitOpError("path must have at least one component");
  unsigned units = 0;
  for (Attribute a : path) {
    if (isa<UnitAttr>(a))
      ++units;
    else if (!isa<StringAttr>(a))
      return op->emitOpError("path components must be strings or units");
  }
  if (units != numDyn)
    return op->emitOpError("has ") << units << " computed path component(s) but " << numDyn << " operand(s)";
  return success();
}
} // namespace mlir::nix

#define GET_OP_CLASSES
#include "NixDialect/NixOps.cpp.inc"

namespace {
// Collects the operand modalities declared with the NixModes trait; names no op.
template <typename OpT> void collectModes(NixDialect &d, MLIRContext *ctx) {
  if constexpr (OpT::template hasTrait<NixModes>())
    d.operandModes[OperationName(OpT::getOperationName(), ctx).getAsOpaquePointer()] = {OpT::kStrictMask, OpT::kTailMask};
}
template <typename... Ops> void collectAllModes(NixDialect &d, MLIRContext *ctx) { (collectModes<Ops>(d, ctx), ...); }
} // namespace

void NixDialect::initialize() {
  addTypes<
#define GET_TYPEDEF_LIST
#include "NixDialect/NixTypes.cpp.inc"
      >();
  addOperations<
#define GET_OP_LIST
#include "NixDialect/NixOps.cpp.inc"
      >();
  collectAllModes<
#define GET_OP_LIST
#include "NixDialect/NixOps.cpp.inc"
      >(*this, getContext());
}

bool NixDialect::evaluatesInPlace(Value v) const {
  if (!v.hasOneUse()) return false;
  OpOperand &use = *v.use_begin();
  Operation *user = use.getOwner(), *def = v.getDefiningOp();
  if (!def || user == def || user->getBlock() != def->getBlock()) return false;
  unsigned i = use.getOperandNumber();
  OperandModes m = modesOf(user->getName());
  return i < 32 && (((m.strict | m.tail) >> i) & 1);
}

Operation *NixDialect::materializeConstant(OpBuilder &b, Attribute value,
                                           Type type, Location loc) {
  Operation *op = nullptr;
  if (auto bl = dyn_cast<BoolAttr>(value)) // before IntegerAttr: i1 integers
    return BoolOp::create(b, loc, type, bl);
  if (isa<UnitAttr>(value))
    return NullOp::create(b, loc, type);
  if (auto i = dyn_cast<IntegerAttr>(value))
    op = IntOp::create(b, loc, type, i);
  else if (auto f = dyn_cast<FloatAttr>(value))
    op = FloatOp::create(b, loc, type, f);
  else if (auto s = dyn_cast<StringAttr>(value))
    op = StringOp::create(b, loc, type, s);
  if (op) setPos(op, packLoc(loc)); // a folded call keeps the position its operands were reported at
  return op;
}

//===----------------------------------------------------------------------===//
// Positions
//===----------------------------------------------------------------------===//

/// Every op class with the `pos` property (NixPos in NixOps.td).
#define NIX_POSITIONED_OPS                                                                                 \
  LambdaOp, FormalOp, IntOp, FloatOp, StringOp, PathOp, WithVarOp, ListOp, AttrsOp, SelectOp, HasAttrOp, \
      ApplyOp, IfOp, AssertOp, EqOp, NeqOp, AndOp, OrOp, ImplOp, UpdateOp, ConcatListsOp, NotOp,          \
      ConcatStringsOp

uint64_t nix::getPos(Operation *op) {
  return llvm::TypeSwitch<Operation *, uint64_t>(op)
      .Case<NIX_POSITIONED_OPS>([](auto o) { return uint64_t(o.getPos()); })
      .Default([](Operation *) { return uint64_t(0); });
}

void nix::setPos(Operation *op, uint64_t word) {
  llvm::TypeSwitch<Operation *>(op).Case<NIX_POSITIONED_OPS>([&](auto o) { o.setPos(int64_t(word)); });
}

uint64_t nix::packLoc(Location loc) {
  auto f = dyn_cast<FileLineColLoc>(loc);
  if (!f) return 0;
  return nixfe::PackedPos::pack(nixfe::FileTable::get().add(f.getFilename().str()), f.getLine(), f.getColumn());
}

Location nix::locOfWord(MLIRContext *ctx, uint64_t word) {
  if (!nixfe::PackedPos::is(word)) return UnknownLoc::get(ctx);
  std::string file = nixfe::FileTable::get().name(nixfe::PackedPos::file(word));
  if (file.empty()) return UnknownLoc::get(ctx);
  return FileLineColLoc::get(ctx, file, nixfe::PackedPos::line(word), nixfe::PackedPos::col(word));
}

std::optional<SrcPos> nix::decodePos(const void *p) {
  uint64_t raw = reinterpret_cast<uintptr_t>(p);
  if (!raw) return std::nullopt;
  auto ofWord = [](uint64_t w) -> std::optional<SrcPos> {
    std::string file = nixfe::FileTable::get().name(nixfe::PackedPos::file(w));
    if (file.empty()) return std::nullopt;
    return SrcPos{std::move(file), nixfe::PackedPos::line(w), nixfe::PackedPos::col(w)};
  };
  auto ofLoc = [](Location l) -> std::optional<SrcPos> {
    if (auto f = dyn_cast<FileLineColLoc>(l)) return SrcPos{f.getFilename().str(), f.getLine(), f.getColumn()};
    return std::nullopt;
  };
  if (nixfe::PackedPos::is(raw)) return ofWord(raw);
  if (raw & kOpPosTag) {
    auto *op = reinterpret_cast<Operation *>(raw & ~uint64_t(kOpPosTag));
    if (uint64_t w = getPos(op)) return ofWord(w);
    return ofLoc(op->getLoc()); // an IRDL primop: the Location of its call
  }
  return ofLoc(Location::getFromOpaquePointer(p));
}

//===----------------------------------------------------------------------===//
// Region kinds: bodies are graph regions (recursive bindings = cyclic SSA).
//===----------------------------------------------------------------------===//

RegionKind ExprOp::getRegionKind(unsigned) { return RegionKind::Graph; }
RegionKind LambdaOp::getRegionKind(unsigned) { return RegionKind::Graph; }

//===----------------------------------------------------------------------===//
// Verifiers
//===----------------------------------------------------------------------===//

LogicalResult LambdaOp::verify() {
  Block &b = getBody().front();
  if (b.getNumArguments() != 1)
    return emitOpError("body must have exactly one block argument");
  if (!isa<ReturnOp>(b.back()))
    return emitOpError("body must end in nix.return");
  if (getFormals()) {
    if (!getFormalDefaults() ||
        getFormalDefaults()->size() != (int64_t)getFormals()->size())
      return emitOpError("formal_defaults must parallel formals");
  } else if (getEllipsis()) {
    return emitOpError("ellipsis requires formals");
  }
  return success();
}

LogicalResult SelectOp::verify() { return verifyAttrPath(*this, getPath(), getDynKeys().size()); }
LogicalResult HasAttrOp::verify() { return verifyAttrPath(*this, getPath(), getDynKeys().size()); }

LogicalResult AttrsOp::verify() {
  if (getNames().size() != getValues().size())
    return emitOpError("names and values must have equal length");
  if (getDynNames().size() != getDynValues().size())
    return emitOpError("dyn_names and dyn_values must have equal length");
  llvm::StringSet<llvm::MallocAllocator> seen;
  for (Attribute a : getNames())
    if (!seen.insert(cast<StringAttr>(a).getValue()).second)
      return emitOpError("duplicate attribute '")
             << cast<StringAttr>(a).getValue() << "'";
  return success();
}

//===----------------------------------------------------------------------===//
// Folders
//===----------------------------------------------------------------------===//

OpFoldResult IntOp::fold(FoldAdaptor) { return getValueAttr(); }
OpFoldResult FloatOp::fold(FoldAdaptor) { return getValueAttr(); }
OpFoldResult StringOp::fold(FoldAdaptor) { return getValueAttr(); }
OpFoldResult BoolOp::fold(FoldAdaptor) { return getValueAttr(); }
OpFoldResult NullOp::fold(FoldAdaptor) { return UnitAttr::get(getContext()); }

OpFoldResult ConcatStringsOp::fold(FoldAdaptor adaptor) {
  auto ops = adaptor.getParts();
  if (ops.empty())
    return {};
  for (Attribute a : ops)
    if (!a)
      return {};
  // `"a" + "b"`, `"${"a"}"`: all string literals.
  if (llvm::all_of(ops, [](Attribute a) { return isa<StringAttr>(a); })) {
    std::string s;
    for (Attribute a : ops)
      s += cast<StringAttr>(a).getValue();
    return StringAttr::get(getContext(), s);
  }
  if (getForceString())
    return {};
  // Integer addition with overflow check (overflow is a runtime error).
  if (llvm::all_of(ops, [](Attribute a) { return isa<IntegerAttr>(a); })) {
    int64_t acc = 0;
    for (Attribute a : ops)
      if (__builtin_add_overflow(acc, cast<IntegerAttr>(a).getInt(), &acc))
        return {};
    return IntegerAttr::get(IntegerType::get(getContext(), 64), acc);
  }
  return {};
}

//===----------------------------------------------------------------------===//
// nix-simplify: folding, builtin arithmetic folding, dead binding elimination
//===----------------------------------------------------------------------===//

namespace {

/// `nix.apply (builtin "__add"|builtins.add|...) a b` -> `nixnum.add(a, b)`:
/// the call of a known primop becomes an op of its continent dialect, whose
/// arity, effects and foldability are declared in NixPrims.irdl.mlir.  Calls with too
/// few arguments stay partial applications; extra arguments are applied to the
/// result.
struct DevirtualizePrimCall : OpRewritePattern<ApplyOp> {
  using OpRewritePattern::OpRewritePattern;
  LogicalResult matchAndRewrite(ApplyOp op, PatternRewriter &rw) const override {
    if (op.getArgs().empty())
      return failure();
    auto *core = getContext()->getLoadedDialect<NixDialect>();
    const NixDialect::PrimInfo *info = nullptr;
    Value callee = op.getCallee();
    if (auto b = callee.getDefiningOp<BuiltinOp>()) {
      auto it = core->prims.find(b.getName());
      if (it != core->prims.end())
        info = &it->second;
    } else if (auto sel = callee.getDefiningOp<SelectOp>()) {
      // builtins.<name>
      if (sel.getDefaultValue() || sel.getPath().size() != 1)
        return failure();
      auto base = sel.getBase().getDefiningOp<BuiltinOp>();
      auto key = dyn_cast<StringAttr>(sel.getPath()[0]);
      if (!base || base.getName() != "builtins" || !key)
        return failure();
      llvm::SmallString<48> internal("__");
      internal += key.getValue();
      auto it = core->prims.find(internal);
      if (it == core->prims.end())
        it = core->prims.find(key.getValue());
      if (it != core->prims.end())
        info = &it->second;
    }
    if (!info || op.getArgs().size() < info->arity)
      return failure();
    // An IRDL op has no property to hold the position, so a primop keeps the call's FileLineColLoc: made
    // here, for the calls that are primops, not for every op.
    OperationState st(locOfWord(op.getContext(), op.getPos()), info->name);
    st.addOperands(op.getArgs().take_front(info->arity));
    st.addTypes(op.getType());
    Value res = rw.create(st)->getResult(0);
    if (op.getArgs().size() > info->arity)
      res = ApplyOp::create(rw, UnknownLoc::get(op.getContext()), op.getType(), res,
                            op.getArgs().drop_front(info->arity), op.getPos());
    rw.replaceOp(op, res);
    return success();
  }
};

/// `nix.apply %v()` (application to zero arguments) is the identity; it only
/// exists to give a binding its own value identity.  When nothing else uses
/// %v that identity is unobservable, so forward %v directly.
struct ForwardUnobservableIdentity : OpRewritePattern<ApplyOp> {
  using OpRewritePattern::OpRewritePattern;
  LogicalResult matchAndRewrite(ApplyOp op, PatternRewriter &rw) const override {
    if (!op.getArgs().empty()) return failure();
    Value callee = op.getCallee();
    if (callee == op.getResult() || !callee.hasOneUse()) return failure();
    // Placeholders/cycles: only forward values defined by real nix ops or
    // block arguments.
    if (Operation *d = callee.getDefiningOp())
      if (!isa<NixDialect>(d->getDialect())) return failure();
    rw.replaceOp(op, callee);
    return success();
  }
};

/// Core dialect or one of the continent dialects (nixnum, nixstr, ...).
bool isNixFamily(Operation *op) {
  return op->getDialect() && op->getDialect()->getNamespace().starts_with("nix");
}

/// Graph regions can hold dead *cycles* (unused recursive bindings) that the
/// generic dead-code elimination never removes. Mark from each terminator.
void eliminateDeadBindings(Operation *root) {
  llvm::DenseSet<Operation *> live;
  llvm::SmallVector<Operation *> work;
  root->walk([&](ExprOp e) {
    if (!e.getBody().empty())
      work.push_back(&e.getBody().front().back());
  });
  auto markValue = [&](Value v) {
    if (Operation *d = v.getDefiningOp())
      if (live.insert(d).second)
        work.push_back(d);
  };
  while (!work.empty()) {
    Operation *op = work.pop_back_val();
    live.insert(op);
    for (Value v : op->getOperands())
      markValue(v);
    if (auto lam = dyn_cast<LambdaOp>(op)) {
      Operation *ret = &lam.getBody().front().back();
      if (live.insert(ret).second)
        work.push_back(ret);
    }
    // The parent lambda of a live op is necessarily live already.
  }
  llvm::SmallVector<Operation *> dead;
  root->walk([&](Operation *op) {
    if (isNixFamily(op) && !isa<ExprOp>(op) && !live.contains(op))
      dead.push_back(op);
  });
  // Drop all uses first (cycles), then erase outermost-first is unsafe; erase
  // after dropping references.
  for (Operation *op : dead)
    op->dropAllReferences();
  for (Operation *op : dead) {
    // Nested ops of a dead lambda are erased with it.
    Operation *p = op->getParentOp();
    bool nestedInDead = false;
    while (p) {
      if (llvm::is_contained(dead, p)) { nestedInDead = true; break; }
      p = p->getParentOp();
    }
    if (!nestedInDead)
      op->erase();
  }
}

} // namespace

FrozenRewritePatternSet mlir::nix::makeDevirtualizePatterns(MLIRContext *ctx) {
  RewritePatternSet patterns(ctx);
  patterns.add<DevirtualizePrimCall>(ctx);
  return FrozenRewritePatternSet(std::move(patterns));
}

/// One walk of the single devirtualization pattern, then the cleanup of the callee computations it
/// orphaned.
void mlir::nix::devirtualizePrims(Operation *root, const FrozenRewritePatternSet &patterns) {
  walkAndApplyPatterns(root, patterns);
  // The callee computations of rewritten calls are now unreferenced; erase
  // them, and whatever only they kept alive.
  llvm::SmallVector<Operation *> work;
  root->walk([&](Operation *op) {
    if (isa<BuiltinOp, SelectOp, StringOp>(op) && op->use_empty())
      work.push_back(op);
  });
  while (!work.empty()) {
    Operation *op = work.pop_back_val();
    llvm::SmallVector<Operation *, 4> producers;
    for (Value v : op->getOperands())
      if (Operation *d = v.getDefiningOp())
        producers.push_back(d);
    op->erase();
    for (Operation *d : producers)
      if (isa<BuiltinOp, SelectOp, StringOp>(d) && d->use_empty())
        work.push_back(d);
  }
}

void mlir::nix::devirtualizePrims(Operation *root) {
  devirtualizePrims(root, makeDevirtualizePatterns(root->getContext()));
}

namespace {

// The passes run on any op, so the same ones serve the evaluator (a `nix.expr`)
// and mlnix-opt (a module).  The continent dialects are defined when the core
// dialect loads, so a pass that creates or matches their ops makes sure it is.

struct NixPrimsPass : public PassWrapper<NixPrimsPass, OperationPass<>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(NixPrimsPass)
  StringRef getArgument() const override { return "nix-prims"; }
  StringRef getDescription() const override {
    return "Rewrite calls of known primops into continent-dialect ops";
  }
  void getDependentDialects(DialectRegistry &registry) const override { registerNixDialects(registry); }
  LogicalResult initialize(MLIRContext *ctx) override {
    frozen = makeDevirtualizePatterns(ctx);
    return success();
  }
  void runOnOperation() override { devirtualizePrims(getOperation(), frozen); }
  FrozenRewritePatternSet frozen;
};

struct NixFoldPass : public PassWrapper<NixFoldPass, OperationPass<>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(NixFoldPass)
  StringRef getArgument() const override { return "nix-fold"; }
  StringRef getDescription() const override {
    return "Canonicalize and constant-fold Nix IR (every foldable primop, generically)";
  }
  void getDependentDialects(DialectRegistry &registry) const override { registerNixDialects(registry); }
  LogicalResult initialize(MLIRContext *ctx) override {
    RewritePatternSet patterns(ctx);
    patterns.add<ForwardUnobservableIdentity>(ctx);
    for (RegisteredOperationName op : ctx->getRegisteredOperations())
      if (op.getDialect().getNamespace().starts_with("nix"))
        op.getCanonicalizationPatterns(patterns, ctx);
    frozen = FrozenRewritePatternSet(std::move(patterns));
    return success();
  }
  void runOnOperation() override {
    GreedyRewriteConfig cfg;
    cfg.setRegionSimplificationLevel(GreedySimplifyRegionLevel::Disabled);
    cfg.enableConstantCSE(false);
    (void)applyPatternsGreedily(getOperation(), frozen, cfg);
  }
  FrozenRewritePatternSet frozen;
};

// Marks the values the evaluator evaluates in place: single use, in the same region, by a
// strict or tail operand (the NixModes traits).  The evaluator makes the same decision
// per value with NixDialect::evaluatesInPlace; this pass makes it visible and testable.
struct NixInlineValuesPass : public PassWrapper<NixInlineValuesPass, OperationPass<>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(NixInlineValuesPass)
  StringRef getArgument() const override { return "nix-inline-values"; }
  StringRef getDescription() const override {
    return "Mark values the evaluator evaluates in place (nix.inline): single use by a strict or tail operand";
  }
  void getDependentDialects(DialectRegistry &registry) const override { registerNixDialects(registry); }
  void runOnOperation() override {
    auto *core = getContext().getLoadedDialect<NixDialect>();
    UnitAttr unit = UnitAttr::get(&getContext());
    getOperation()->walk([&](Operation *op) {
      if (op->getNumResults() == 1 && core->evaluatesInPlace(op->getResult(0))) op->setAttr("nix.inline", unit);
    });
  }
};

struct NixDcePass : public PassWrapper<NixDcePass, OperationPass<>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(NixDcePass)
  StringRef getArgument() const override { return "nix-dce"; }
  StringRef getDescription() const override {
    return "Remove unreferenced bindings, including dead recursive cycles";
  }
  void runOnOperation() override { eliminateDeadBindings(getOperation()); }
};
} // namespace

void mlir::nix::registerNixPasses() {
  static std::once_flag once;
  std::call_once(once, [] {
    PassRegistration<NixPrimsPass>();
    PassRegistration<NixFoldPass>();
    PassRegistration<NixDcePass>();
    PassRegistration<NixInlineValuesPass>();
    PassPipelineRegistration<>("nix-simplify",
                               "Devirtualize primops, fold constants, remove dead (cyclic) bindings",
                               [](OpPassManager &pm) {
                                 pm.addPass(std::make_unique<NixPrimsPass>());
                                 pm.addPass(std::make_unique<NixFoldPass>());
                                 pm.addPass(std::make_unique<NixDcePass>());
                               });
  });
}
