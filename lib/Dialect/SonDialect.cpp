//===- SonDialect.cpp - The son dialect, nix-defer and son-mint ------------===//

#include "NixDialect/Son.h"

#include "mlir/IR/Builders.h"
#include "llvm/ADT/BitVector.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/SmallString.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Transforms/RegionUtils.h"

#include <deque>
#include <optional>

#include "NixDialect/SonDialect.cpp.inc"

using mlir::nix::parseNixValues; // son.defer prints its captures as the nix ops print their operands
using mlir::nix::printNixValues;

#define GET_OP_CLASSES
#include "NixDialect/Son.cpp.inc"

namespace mlir::son {

void SonDialect::initialize() {
  addOperations<
#define GET_OP_LIST
#include "NixDialect/Son.cpp.inc"
      >();
}

RegionKind BodyOp::getRegionKind(unsigned) { return RegionKind::Graph; }

LogicalResult BodyOp::verify() {
  Block &entry = getBody().front();
  if (entry.getNumArguments() != getCaptures() + 1)
    return emitOpError("takes its captures and then the lambda's argument: ") << getCaptures() + 1 << " block arguments";
  for (BlockArgument a : entry.getArguments())
    if (!isa<nix::ValueType>(a.getType()))
      return emitOpError("takes only !nix.value arguments");
  return success();
}

LogicalResult DeferOp::verifySymbolUses(SymbolTableCollection &symbols) {
  // From the module: a defer inside a body sits in the pool's own symbol table, and the reference starts at the pool.
  auto body = dyn_cast_or_null<BodyOp>(symbols.lookupSymbolIn((*this)->getParentOfType<ModuleOp>(), getRowAttr()));
  if (!body)
    return emitOpError("refers to ") << getRowAttr() << ", which is no son.body";
  if (body.getCaptures() != getCaptures().size())
    return emitOpError("binds ") << getCaptures().size() << " captures, the body takes " << body.getCaptures();
  return success();
}

namespace {
/// The values of a frame forced on every path on which its call returns: the schedule's half of the frame's lifecycle, read
/// by son.release (Son.td).  The return value is forced (the call returns it in weak head normal form), and forcing a value
/// forces, every time, the operands its op always forces:
///   nix.if        its condition, and what both of its arms force (one of them runs);
///   nix.assert    its condition and its body;            nix.not, nix.formal   their operand (a formal, the argument set);
///   nix.and/or/impl  the left side (the right only when it decides);
///   nix.eq/neq, nix.update, nix.concat_lists  both sides;   nix.concat_strings, nix.interpolate  every part;
///   nix.select, nix.has_attr  the base, and the first key when it is computed;   nix.with_var  the innermost scope;
///   nix.attrs     every computed name;                    nix.apply  the callee, and its first argument when the callee is a
///                 son.defer of this frame whose lambda takes an attribute pattern or whose body forces its argument;
///   a primop      applied to all its arguments: every operand of a nix.strict one, else its nix.first one (NixPrims.irdl.mlir).
/// A list, an attribute's value, an argument of an apply or a primop, a defer's capture: none (they are cells).  A primop that
/// never returns (throw, abort) forces everything, since no path through it returns.  A block argument is the caller's.
/// The set is an under-approximation: a cycle of forcing is cut (it never returns: infinite recursion), and a block too big
/// for the bit sets gets the return value alone.
class MustForce {
public:
  /// `may`: the values forced on some path that returns instead (the arms of an if joined, both sides of and/or/impl).
  MustForce(Block &block, nix::NixDialect *nixd, llvm::DenseMap<Operation *, bool> *argStrict = nullptr, bool may = false)
      : block(block), nixd(nixd), argStrict(argStrict), may(may) {
    for (BlockArgument a : block.getArguments()) if (index.try_emplace(a, index.size()).second) values.push_back(a);
    for (Operation &o : block)
      for (Value r : o.getResults()) if (index.try_emplace(r, index.size()).second) values.push_back(r);
    memo.resize(index.size());
    state.assign(index.size(), 0);
    top.assign(index.size(), false);
    if (block.empty() || !isa<nix::ReturnOp>(block.back())) return;
    Value ret = block.back().getOperand(0);
    auto it = index.find(ret);
    if (it == index.end()) return;
    if (!of(it->second, 0)) { never = true; return; } // the body never returns: nothing is released
    forcedSet = *memo[it->second];
  }
  /// v is computed when the call returns, on every path that returns.
  bool forced(Value v) const {
    if (never) return true;
    auto it = index.find(v);
    return it != index.end() && forcedSet.size() > it->second && forcedSet.test(it->second);
  }
  /// No path of the body returns (every one throws).
  bool neverReturns() const { return never; }

private:
  Block &block;
  nix::NixDialect *nixd;
  llvm::DenseMap<Operation *, bool> *argStrict; // per son.body: forces its argument (memo, shared across bodies)
  bool may;
  llvm::DenseMap<Value, unsigned> index;
  std::vector<Value> values; // by index
  std::vector<std::optional<llvm::BitVector>> memo;
  std::vector<uint8_t> state; // 0 not seen, 1 being computed (a cycle), 2 done
  std::vector<bool> top;      // done and forcing it never returns
  llvm::BitVector forcedSet;
  bool never = false;
  size_t bits = 0;
  static constexpr size_t kBitBudget = size_t(1) << 26; // 8 MB of sets for one frame

  /// The set forced when value i is, or null when forcing it never returns (it throws on every path).
  const llvm::BitVector *of(unsigned i, unsigned depth) {
    if (state[i] == 2) return top[i] ? nullptr : &*memo[i];
    llvm::BitVector self(index.size());
    self.set(i);
    if (state[i] == 1 || depth > 4096 || bits + index.size() > kBitBudget) return keep(i, std::move(self), false, state[i] == 1);
    state[i] = 1;
    Value v = valueAt(i);
    SmallVector<Value, 4> must, alts;
    bool throws = false;
    if (Operation *op = v.getDefiningOp()) demands(op, must, alts, throws);
    if (throws) return keep(i, std::move(self), true);
    for (Value m : must) {
      auto it = index.find(m);
      if (it == index.end()) continue;
      const llvm::BitVector *d = of(it->second, depth + 1);
      if (!d) return keep(i, std::move(self), true);
      self |= *d;
    }
    if (!alts.empty()) {
      std::optional<llvm::BitVector> meet; // what every arm that returns forces (`may`: some arm)
      for (Value a : alts) {
        auto it = index.find(a);
        if (it == index.end()) { // an arm from outside the frame: it forces nothing of it
          if (!may) { meet = llvm::BitVector(index.size()); break; }
          if (!meet) meet = llvm::BitVector(index.size());
          continue;
        }
        const llvm::BitVector *d = of(it->second, depth + 1);
        if (!d) continue; // this arm never returns
        if (!meet) meet = *d;
        else if (may) *meet |= *d;
        else *meet &= *d;
      }
      if (!meet) return keep(i, std::move(self), true); // no arm returns
      self |= *meet;
    }
    return keep(i, std::move(self), false);
  }
  const llvm::BitVector *keep(unsigned i, llvm::BitVector set, bool throws, bool cycle = false) {
    if (cycle) { // the value is being computed below us: what is known of it so far is itself (not memoized)
      scratch.push_back(std::move(set));
      return &scratch.back();
    }
    bits += set.size();
    state[i] = 2;
    top[i] = throws;
    memo[i] = std::move(set);
    return throws ? nullptr : &*memo[i];
  }
  std::deque<llvm::BitVector> scratch;

  Value valueAt(unsigned i) const { return values[i]; }

  void demands(Operation *op, SmallVectorImpl<Value> &must, SmallVectorImpl<Value> &alts, bool &throws) {
    auto firstKey = [](auto path, ValueRange keys, SmallVectorImpl<Value> &out) { // a computed first name: its key
      if (!path.empty() && !keys.empty() && path.front().isNull()) out.push_back(keys.front());
    };
    if (auto o = dyn_cast<nix::IfOp>(op)) { must.push_back(o.getCond()); alts.push_back(o.getThenValue()); alts.push_back(o.getElseValue()); }
    else if (auto o = dyn_cast<nix::AssertOp>(op)) { must.push_back(o.getCond()); must.push_back(o.getBody()); }
    else if (isa<nix::NotOp>(op)) must.push_back(op->getOperand(0));
    else if (isa<nix::AndOp, nix::OrOp, nix::ImplOp>(op)) { must.push_back(op->getOperand(0)); if (may) must.push_back(op->getOperand(1)); }
    else if (isa<nix::EqOp, nix::NeqOp, nix::UpdateOp, nix::ConcatListsOp>(op)) { must.push_back(op->getOperand(0)); must.push_back(op->getOperand(1)); }
    else if (isa<nix::ConcatStringsOp, nix::InterpolateOp>(op)) must.append(op->operand_begin(), op->operand_end());
    else if (auto o = dyn_cast<nix::SelectOp>(op)) { must.push_back(o.getBase()); firstKey(o.getPath(), o.getDynKeys(), must); }
    else if (auto o = dyn_cast<nix::HasAttrOp>(op)) { must.push_back(o.getBase()); firstKey(o.getPath(), o.getDynKeys(), must); }
    else if (auto o = dyn_cast<nix::FormalOp>(op)) must.push_back(o.getArg());
    else if (auto o = dyn_cast<nix::WithVarOp>(op)) { if (!o.getScopes().empty()) must.push_back(o.getScopes().front()); }
    else if (auto o = dyn_cast<nix::AttrsOp>(op)) must.append(o.getDynNames().begin(), o.getDynNames().end());
    else if (auto o = dyn_cast<nix::ApplyOp>(op)) {
      must.push_back(o.getCallee());
      if (!o.getArgs().empty() && calleeForcesArg(o.getCallee())) must.push_back(o.getArgs().front());
    } else if (const auto *prim = nixd ? nixd->primOf(op) : nullptr) {
      if (prim->key == "throw" || prim->key == "abort") { throws = true; return; }
      if (prim->key == "__tryEval") return; // catches: its operand's throwing returns, and a cell that threw stays unforced
      if (op->getNumOperands() != prim->arity) return; // a partial application forces nothing
      auto modes = nixd->modesOf(op->getName());
      for (unsigned k = 0; k < op->getNumOperands(); ++k)
        if ((modes.strict >> k) & 1) must.push_back(op->getOperand(k));
      if (modes.first && modes.first <= op->getNumOperands() && !((modes.strict >> (modes.first - 1)) & 1))
        must.push_back(op->getOperand(modes.first - 1));
    }
  }

  /// The callee is a lambda of this frame -- a son.defer, or a nix.lambda with its body -- and calling it forces the
  /// argument: it takes an attribute pattern (a call checks the set's names, which forces it), or its body forces the
  /// argument on every path that returns.
  bool calleeForcesArg(Value callee) {
    if (!argStrict) return false;
    Operation *key = nullptr;
    Block *body = nullptr;
    bool pattern = false;
    if (auto defer = callee.getDefiningOp<DeferOp>()) {
      auto module = defer->getParentOfType<ModuleOp>(); // the row is named from the module, as DeferOp verifies it
      auto row = module ? dyn_cast_or_null<BodyOp>(SymbolTable::lookupSymbolIn(module, defer.getRowAttr())) : BodyOp();
      if (!row || row.getBody().empty()) return false;
      key = row;
      body = &row.getBody().front();
      auto props = dyn_cast_or_null<DictionaryAttr>(row.getLambda());
      pattern = props && props.get("formals");
    } else if (auto lam = callee.getDefiningOp<nix::LambdaOp>()) {
      key = lam;
      pattern = bool(lam.getFormals());
      if (!lam.getBody().empty() && !lam.getBody().front().empty()) body = &lam.getBody().front();
      else if (!pattern) return false; // a deferred shell: its body is not minted yet
    } else {
      return false;
    }
    if (auto it = argStrict->find(key); it != argStrict->end()) return it->second;
    (*argStrict)[key] = false; // a body that calls itself: not known yet, so not strict
    bool strict = pattern;
    if (!strict && body) {
      MustForce inner(*body, nixd, argStrict);
      strict = inner.forced(body->getArgument(body->getNumArguments() - 1));
    }
    (*argStrict)[key] = strict;
    return strict;
  }
};

/// What a frame's cells can read when the call returns (son.release, Son.td).  A cell is an op result passed on without
/// forcing: an operand nix-truffle reads with `lazy` (graal/, Nodes.kt) -- a list's elements, an attribute set's values
/// (static and dynamic; not the dynamic names), an apply's arguments (not the callee), a defer's captures, every operand of a
/// primop -- or a value used inside a lambda not deferred yet, which captures it.  An argument passed on is the caller's cell,
/// as it came, and holds no frame.  A cell forced on every path that returns (MustForce) is a value by then and reads nothing:
/// the cells are the others, and their closure over operands, followed through the operands not forced either (a forced one
/// is kept as the value it is).  In the frame's order: arguments, results.  The Graal arm's keep set at a return is a subset:
/// it starts from the cells still unforced, and stops at a slot forced.
SmallVector<Value> frameReads(Block &block, nix::NixDialect *nixd) {
  llvm::DenseMap<Operation *, bool> argStrict;
  MustForce must(block, nixd, &argStrict);
  SmallVector<Value> work;
  auto pass = [&](ValueRange vs) {
    for (Value v : vs)
      if (isa<OpResult>(v) && v.getParentBlock() == &block && !must.forced(v)) work.push_back(v);
  };
  for (Operation &o : block) {
    if (auto list = dyn_cast<nix::ListOp>(o)) pass(list.getElements());
    else if (auto attrs = dyn_cast<nix::AttrsOp>(o)) { pass(attrs.getValues()); pass(attrs.getDynValues()); }
    else if (auto apply = dyn_cast<nix::ApplyOp>(o)) pass(apply.getArgs());
    else if (auto defer = dyn_cast<DeferOp>(o)) pass(defer.getCaptures());
    else if (nixd && nixd->primOf(&o)) pass(o.getOperands());
    for (Region &r : o.getRegions()) r.walk([&](Operation *inner) { pass(inner->getOperands()); });
  }
  llvm::DenseSet<Value> kept;
  while (!work.empty()) {
    Value v = work.pop_back_val();
    if (v.getParentBlock() != &block || !kept.insert(v).second) continue;
    if (must.forced(v)) continue; // computed by the return: kept as its value, its operands not needed again
    if (Operation *def = v.getDefiningOp()) for (Value u : def->getOperands()) work.push_back(u);
  }
  SmallVector<Value> ordered;
  for (BlockArgument a : block.getArguments()) if (kept.contains(a)) ordered.push_back(a);
  for (Operation &o : block) for (Value r : o.getResults()) if (kept.contains(r)) ordered.push_back(r);
  return ordered;
}
} // namespace

ForcedOnReturn forcedOnReturn(Block &block, nix::NixDialect *nixd, bool may) {
  llvm::DenseMap<Operation *, bool> argStrict;
  MustForce must(block, nixd, &argStrict, may);
  ForcedOnReturn out;
  out.never = must.neverReturns();
  if (!out.never) {
    for (BlockArgument a : block.getArguments()) if (must.forced(a)) out.forced.insert(a);
    for (Operation &o : block) for (Value r : o.getResults()) if (must.forced(r)) out.forced.insert(r);
  }
  return out;
}

LogicalResult ReleaseOp::verify() {
  for (Operation *o = getOperation()->getPrevNode(); o; o = o->getPrevNode())
    if (isa<ReleaseOp>(o)) return emitOpError("follows another in its frame: a frame is released once");
  llvm::DenseSet<Value> kept;
  kept.insert(getKept().begin(), getKept().end());
  for (Value v : frameReads(*getOperation()->getBlock(), getContext()->getLoadedDialect<nix::NixDialect>()))
    if (!kept.contains(v)) {
      InFlightDiagnostic d = emitOpError("releases a value a cell passed on can still read");
      d.attachNote(v.getLoc()) << "this value";
      return d;
    }
  return success();
}

namespace {
constexpr StringLiteral kPool = "bodies";

/// The module's pool, made at its end when there is none.
PoolOp poolOf(ModuleOp module) {
  if (auto pool = module.lookupSymbol<PoolOp>(kPool))
    return pool;
  OpBuilder b = OpBuilder::atBlockEnd(module.getBody());
  PoolOp pool = PoolOp::create(b, module.getLoc(), b.getStringAttr(kPool));
  pool.getRows().emplaceBlock();
  return pool;
}

struct NixDeferPass : PassWrapper<NixDeferPass, OperationPass<ModuleOp>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(NixDeferPass)
  StringRef getArgument() const override { return "nix-defer"; }
  StringRef getDescription() const override { return "Move each nix.lambda body to a son.pool row; the lambda becomes son.defer"; }
  void getDependentDialects(DialectRegistry &registry) const override { registry.insert<SonDialect>(); }

  void runOnOperation() override {
    ModuleOp module = getOperation();
    SmallVector<nix::LambdaOp> lambdas;
    module.walk([&](nix::LambdaOp l) { lambdas.push_back(l); }); // outer before inner: process in reverse
    if (lambdas.empty())
      return;
    PoolOp pool = poolOf(module);
    unsigned row = pool.getRows().front().getOperations().size();
    for (nix::LambdaOp lambda : llvm::reverse(lambdas)) {
      if (lambda.getBody().empty())
        continue; // a deferred shell of the evaluator: no body to move
      Region &body = lambda.getBody();
      SetVector<Value> captured;
      getUsedValuesDefinedAbove(body, captured);

      OpBuilder b = OpBuilder::atBlockEnd(&pool.getRows().front());
      Attribute props = lambda->getPropertiesAsAttribute();
      unsigned thisRow = row++;
      llvm::SmallString<16> nameBuf;
      (llvm::Twine("row") + llvm::Twine(thisRow)).toVector(nameBuf);
      llvm::StringRef name(nameBuf);
      auto bodyOp = BodyOp::create(b, lambda.getLoc(), b.getStringAttr(name), captured.size(), props);
      Type value = nix::ValueType::get(&getContext());
      SmallVector<Type> types(captured.size() + 1, value);
      SmallVector<Location> locs(captured.size() + 1, lambda.getLoc());
      Block *entry = &bodyOp.getBody().emplaceBlock();
      entry->addArguments(types, locs);

      Block &old = body.front();
      old.getArgument(0).replaceAllUsesWith(entry->getArgument(captured.size()));
      for (auto [i, c] : llvm::enumerate(captured)) {
        Value capture = c;
        capture.replaceUsesWithIf(entry->getArgument(i), [&](OpOperand &use) { return body.isAncestor(use.getOwner()->getParentRegion()); });
      }
      entry->getOperations().splice(entry->end(), old.getOperations());

      OpBuilder at(lambda);
      auto ref = SymbolRefAttr::get(&getContext(), kPool, {FlatSymbolRefAttr::get(&getContext(), name)});
      auto defer = DeferOp::create(at, lambda.getLoc(), lambda.getType(), ref, captured.getArrayRef());
      lambda.getResult().replaceAllUsesWith(defer);
      lambda.erase();
    }
  }
};

struct SonMintPass : PassWrapper<SonMintPass, OperationPass<ModuleOp>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(SonMintPass)
  StringRef getArgument() const override { return "son-mint"; }
  StringRef getDescription() const override { return "Make every son.defer a nix.lambda with its body; drop the pool"; }

  void runOnOperation() override {
    ModuleOp module = getOperation();
    module.walk([](ReleaseOp r) { r.erase(); }); // derived (son-release), and a minted lambda is not a frame
    auto pool = module.lookupSymbol<PoolOp>(kPool);
    if (!pool)
      return;
    for (bool again = true; again;) { // a minted body can hold defers of its own
      again = false;
      SmallVector<DeferOp> defers;
      module.walk([&](DeferOp d) {
        if (!d->getParentOfType<PoolOp>())
          defers.push_back(d);
      });
      for (DeferOp defer : defers) {
        auto row = cast<BodyOp>(SymbolTable::lookupSymbolIn(module, defer.getRowAttr()));
        OpBuilder b(defer);
        OperationState state(defer.getLoc(), nix::LambdaOp::getOperationName());
        state.addTypes(defer.getType());
        state.addRegion();
        Operation *lambda = b.create(state);
        if (failed(lambda->setPropertiesFromAttribute(row.getLambda(), [&] { return row.emitOpError(); })))
          return signalPassFailure();
        IRMapping mapping;
        row.getBody().cloneInto(&lambda->getRegion(0), mapping);
        Block &entry = lambda->getRegion(0).front();
        for (auto [i, c] : llvm::enumerate(defer.getCaptures()))
          entry.getArgument(i).replaceAllUsesWith(c);
        entry.eraseArguments(0, row.getCaptures());
        defer.getResult().replaceAllUsesWith(lambda->getResult(0));
        defer.erase();
        again = true;
      }
    }
    pool.erase();
  }
};
} // namespace

namespace {
/// son-release: each frame's son.release (Son.td), as the Graal arm keeps a frame (graal/, Nodes.kt): what frameReads finds.
struct SonReleasePass : PassWrapper<SonReleasePass, OperationPass<ModuleOp>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(SonReleasePass)
  StringRef getArgument() const override { return "son-release"; }
  StringRef getDescription() const override { return "Mark in each frame what its unforced cells can read when the call returns"; }

  void frame(Block &block, nix::NixDialect *nixd) {
    for (Operation &o : llvm::make_early_inc_range(block))
      if (isa<ReleaseOp>(o)) o.erase();
    SmallVector<Value> kept = frameReads(block, nixd);
    OpBuilder b(block.getTerminator());
    ReleaseOp::create(b, block.getTerminator()->getLoc(), kept);
  }

  void runOnOperation() override {
    auto *nixd = getContext().getLoadedDialect<nix::NixDialect>();
    getOperation().walk([&](Operation *o) {
      if (isa<BodyOp, nix::ExprOp>(o))
        for (Region &r : o->getRegions())
          for (Block &b : r)
            if (!b.empty() && b.back().hasTrait<OpTrait::IsTerminator>()) frame(b, nixd);
    });
  }
};

/// son-export: the module as JSON on stdout, for an executor outside this process (the Graal arm, docs/PRELOAD-DIALECTS.md step 3: a
/// Truffle interpreter builds its nodes from it).  Generic: every op is {"op", "res", "ins", "types", "attrs", "regions"}, a region a
/// list of blocks {"args", "ops"}, a value a number unique in the module (a graph region reads values before their definition, so a
/// number is given at the first sight, use or definition).  `attrs` are the op's properties and attributes as MLIR converts them,
/// without the packed source positions; a null name (a computed attribute path component) is null.  Run it after nix-defer, with
/// `-o /dev/null`: the module text would follow on stdout.
struct SonExportPass : PassWrapper<SonExportPass, OperationPass<ModuleOp>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(SonExportPass)
  StringRef getArgument() const override { return "son-export"; }
  StringRef getDescription() const override { return "Write the module as JSON to stdout, for an executor in another runtime"; }

  llvm::DenseMap<Value, unsigned> ids;
  unsigned id(Value v) { return ids.try_emplace(v, unsigned(ids.size())).first->second; }

  static void string(raw_ostream &os, StringRef s) {
    os << '"';
    for (unsigned char c : s) {
      if (c == '"' || c == '\\') os << '\\' << char(c);
      else if (c == '\n') os << "\\n";
      else if (c == '\t') os << "\\t";
      else if (c == '\r') os << "\\r";
      else if (c < 0x20) { os << "\\u00"; os.write_hex(c >> 4); os.write_hex(c & 15); }
      else os << char(c);
    }
    os << '"';
  }
  static void attr(raw_ostream &os, Attribute a, bool inArray) {
    if (auto b = dyn_cast<BoolAttr>(a)) os << (b.getValue() ? "true" : "false");
    else if (auto i = dyn_cast<IntegerAttr>(a)) os << i.getValue().getSExtValue();
    else if (auto f = dyn_cast<FloatAttr>(a)) { llvm::SmallString<32> s; f.getValue().toString(s, 17, 0); os << s; }
    else if (auto s = dyn_cast<StringAttr>(a)) string(os, s.getValue());
    else if (isa<UnitAttr>(a)) os << (inArray ? "null" : "true"); // a null name in a list; a unit flag set
    else if (auto arr = dyn_cast<ArrayAttr>(a)) { os << '['; llvm::interleaveComma(arr, os, [&](Attribute e) { attr(os, e, true); }); os << ']'; }
    else if (auto d = dyn_cast<DenseBoolArrayAttr>(a)) { os << '['; llvm::interleaveComma(d.asArrayRef(), os, [&](bool e) { os << (e ? "true" : "false"); }); os << ']'; }
    else if (auto d = dyn_cast<DenseI64ArrayAttr>(a)) { os << '['; llvm::interleaveComma(d.asArrayRef(), os); os << ']'; }
    else if (auto d = dyn_cast<DenseI32ArrayAttr>(a)) { os << '['; llvm::interleaveComma(d.asArrayRef(), os); os << ']'; }
    else if (auto d = dyn_cast<DictionaryAttr>(a)) { // son.body's `lambda`: the properties of the lambda it was
      os << '{';
      bool first = true;
      for (NamedAttribute n : d) {
        StringRef k = n.getName().getValue();
        if (k == "pos" || k == "formal_locs") continue;
        if (!first) os << ',';
        first = false;
        string(os, k);
        os << ':';
        attr(os, n.getValue(), false);
      }
      os << '}';
    } else if (auto r = dyn_cast<SymbolRefAttr>(a)) {
      os << '[';
      string(os, r.getRootReference().getValue());
      for (FlatSymbolRefAttr n : r.getNestedReferences()) { os << ','; string(os, n.getValue()); }
      os << ']';
    } else { llvm::SmallString<64> s; llvm::raw_svector_ostream(s) << a; string(os, s); }
  }
  void op(raw_ostream &os, Operation *o) {
    os << "{\"op\":";
    string(os, o->getName().getStringRef());
    os << ",\"res\":[";
    llvm::interleaveComma(o->getResults(), os, [&](Value v) { os << id(v); });
    os << "],\"ins\":[";
    llvm::interleaveComma(o->getOperands(), os, [&](Value v) { os << id(v); });
    os << "],\"types\":[";
    llvm::interleaveComma(o->getResultTypes(), os, [&](Type t) { llvm::SmallString<64> s; llvm::raw_svector_ostream(s) << t; string(os, s); });
    os << "],\"attrs\":{";
    bool first = true;
    auto field = [&](StringRef k, Attribute v) {
      if (k == "pos" || k == "formal_locs" || k == "positions") return; // packed source positions: meaningless outside this process
      if (!first) os << ',';
      first = false;
      string(os, k);
      os << ':';
      attr(os, v, false);
    };
    if (auto props = dyn_cast_or_null<DictionaryAttr>(o->getPropertiesAsAttribute()))
      for (NamedAttribute n : props) field(n.getName().getValue(), n.getValue());
    for (NamedAttribute n : o->getDiscardableAttrs()) field(n.getName().getValue(), n.getValue());
    if (auto *nixd = o->getContext()->getLoadedDialect<nix::NixDialect>()) // not loaded for a module of other dialects (kif)
      if (const auto *prim = nixd->primOf(o))                                // a primop: the builtin it runs
        field("prim_key", StringAttr::get(o->getContext(), prim->key));
    os << "},\"regions\":[";
    bool firstRegion = true;
    for (Region &r : o->getRegions()) {
      os << (firstRegion ? "[" : ",[");
      firstRegion = false;
      bool firstBlock = true;
      for (Block &b : r) {
        os << (firstBlock ? "{\"args\":[" : ",{\"args\":[");
        firstBlock = false;
        llvm::interleaveComma(b.getArguments(), os, [&](BlockArgument a) { os << id(a); });
        os << "],\"ops\":[";
        bool firstOp = true;
        for (Operation &inner : b) {
          if (!firstOp) os << ',';
          firstOp = false;
          op(os, &inner);
        }
        os << "]}";
      }
      os << ']';
    }
    os << "]}";
  }
  void runOnOperation() override {
    llvm::raw_ostream &os = llvm::outs();
    os << "{\"module\":[";
    bool first = true;
    for (Operation &o : *getOperation().getBody()) {
      if (!first) os << ',';
      first = false;
      op(os, &o);
    }
    os << "]}\n";
    os.flush();
  }
};
} // namespace

void registerSonPasses() {
  static const bool registered = [] {
    PassRegistration<NixDeferPass>();
    PassRegistration<SonMintPass>();
    PassRegistration<SonReleasePass>();
    PassRegistration<SonExportPass>();
    return true;
  }();
  (void)registered;
}

} // namespace mlir::son
