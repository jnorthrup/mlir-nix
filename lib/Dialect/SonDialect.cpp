//===- SonDialect.cpp - The son dialect, nix-defer and son-mint ------------===//

#include "NixDialect/Son.h"

#include "mlir/IR/Builders.h"
#include "llvm/ADT/SmallString.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Transforms/RegionUtils.h"

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
    PassRegistration<SonExportPass>();
    return true;
  }();
  (void)registered;
}

} // namespace mlir::son
