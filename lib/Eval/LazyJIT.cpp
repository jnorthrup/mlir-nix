//===- LazyJIT.cpp - Lazy value graph -> resumable MLIR control flow ---------===//
#include "Nix/LazyJIT.h"
#include "Nix/Eval.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/Builders.h"
#include "llvm/ADT/StringSwitch.h"
#include "llvm/ADT/ScopeExit.h"
#include "llvm/Support/raw_ostream.h"

#include <array>
#include <cstddef>
#include <cstdlib>
#include <map>
#include <string>
#include <string_view>
#include <tuple>

namespace nixev {
namespace nd = mlir::nix;
namespace {
constexpr unsigned kMaxNodes = 64, kMaxLeaves = 16, kMaxBlocks = 256, kMaxResumes = 32;
constexpr unsigned kMaxInlineDepth = 4;
constexpr unsigned kMaxArguments = 4, kNoArgument = unsigned(-1);
constexpr unsigned kMaxListElements = 4;
constexpr unsigned kMaxLiteralBytes = 4096;
constexpr unsigned kMaxPathComponents = 4;
// The low three bits are the return kind; a demand carries its continuation ID.
constexpr uint64_t kFalse = 0, kTrue = 1, kDemand = 2, kDeopt = 3, kInvalid = 4;
constexpr uint64_t kDepthOverflow = 5, kValue = 6, kGuardMiss = 7;
// Continuation destinations 0/1/2 are false/true/deopt. Atomic continuations start at 3.
constexpr unsigned kFalseDest = 0, kTrueDest = 1, kDeoptDest = 2;
// Value completion has a separate terminal; the fixed Boolean terminal IDs stay put.
constexpr unsigned kValueDest = unsigned(-1), kNoValueDest = unsigned(-2);
using Empty = LazyJITPlan::RunResult::Empty;
constexpr unsigned emptyCode(Empty empty) { return kMaxLeaves + unsigned(empty); }
constexpr unsigned kListCodeBase = emptyCode(Empty::String) + 1;
const char *emptyName(Empty empty) {
  switch (empty) {
  case Empty::Attrs: return "attrs";
  case Empty::List: return "list";
  case Empty::String: return "string";
  case Empty::None: return "none";
  }
  return "invalid";
}
enum class Kind { Deopt, Constant, Leaf, Predicate, HasAttr, Not, And, Or, Impl, If, Call, Empty, List, StringCompare };
struct StringOperand {
  unsigned leaf = kNoArgument, literal = kNoArgument;
};
struct StringLiteral {
  mlir::Value value;
  std::string bytes; // immutable after plan construction; activeRuns pins its storage
};
struct PlanNode {
  Kind kind = Kind::Deopt;
  unsigned a = 0, b = 0, c = 0, leaf = 0;
  VType tag = VType::Null;
  bool literal = false, function = false, returnsValue = false;
  Empty empty = Empty::None;
  Symbol symbol = 0;
  mlir::Operation *op = nullptr;
  mlir::Operation *target = nullptr;
  const nixev::Node *targetNode = nullptr; // the node a closure of `target` holds: what a guard compares the callee with
  unsigned context = 0, arity = 0, recipe = 0;
  std::array<StringOperand, 2> strings;
  bool unequal = false;
};
struct ListRecipe {
  std::array<unsigned, kMaxListElements> elements{};
  unsigned size = 0;
  bool allowed = false; // set only by a tail ReturnList continuation
};
enum class LeafKind { Cell, Projection };
struct Leaf {
  mlir::Value value;
  unsigned context, argument;
  LeafKind kind = LeafKind::Cell;
  unsigned base = 0, key = kNoArgument;
  std::array<Symbol, kMaxPathComponents> path{};
  unsigned pathSize = 0;
  mlir::Operation *select = nullptr;
};
struct Context {
  mlir::Region *region;
  unsigned parent, depth;
  mlir::Operation *lambda;
  llvm::SmallVector<mlir::Value, kMaxArguments> formals;
  llvm::SmallVector<unsigned, kMaxArguments> arguments;
  llvm::SmallVector<mlir::Region *, kMaxArguments> regions;
  Context(mlir::Region *region, unsigned parent, unsigned depth, mlir::Operation *lambda)
      : region(region), parent(parent), depth(depth), lambda(lambda) {}
};
enum class Action { Atomic, Enter, Leave, ReturnValue, ReturnEmpty, ReturnList, StringDemand };
struct Continuation {
  unsigned node, yes, no;
  mlir::Operation *consumer;
  Action action = Action::Atomic;
  unsigned demandLeaf = kNoArgument;
};

// Read only an existing cell. This must not be replaced with lookup(): callee
// specialization and guards may not create or force a captured computation.
Value *existing(EvalState &st, Frame *env, mlir::Value value) {
  const nixev::Node *slot = st.nodeOf(value.getAsOpaquePointer());
  if (!slot) return nullptr;
  if (slot->fixed) return slot->fixed; // a literal or a builtin, once made: one cell for every frame
  if (slot->idx == kNoSlot) return nullptr;
  while (env && env->info != slot->ri) env = env->up();
  return env && slot->idx < env->info->numSlots ? env->slots[slot->idx] : nullptr;
}

int predicateTag(llvm::StringRef name) {
  return llvm::StringSwitch<int>(name)
      .Case("nixty.is_attrs", int(VType::Attrs)).Case("nixty.is_bool", int(VType::Bool))
      .Case("nixty.is_float", int(VType::Float)).Case("nixty.is_function", int(VType::Lambda))
      .Case("nixty.is_int", int(VType::Int)).Case("nixty.is_list", int(VType::List))
      .Case("nixty.is_null", int(VType::Null)).Case("nixty.is_path", int(VType::Path))
      .Case("nixty.is_string", int(VType::String)).Default(-1);
}

void countProjectionLookup(const Bindings &, LazyJITPlan::RunResult &result) { ++result.projectionFlat; }
} // namespace

// Private per-run ABI. Generated code addresses every member with offsetof;
// only live cells/active flags are initialized, and an env is read only while active.
struct LazyJITPlan::Runtime {
  Value *cells[kMaxLeaves];
  Frame *envs[kMaxNodes];
  uint8_t active[kMaxNodes];
  uint32_t initialDepth, maxDepth, depth, currentContext, inlineCalls, saturatedInlineCalls, resultLeaf;
  uint32_t stringComparisons, stringGuardDeopts;
};

struct LazyJITPlan::Impl {
  mlir::Region &region;
  EvalState &state;
  mlir::Value result;
  llvm::SmallVector<mlir::Value, kMaxArguments> arguments;
  llvm::SmallVector<mlir::Region *, kMaxArguments> chainRegions;
  llvm::SmallVector<PlanNode, 16> nodes;
  llvm::SmallVector<Leaf, 4> leaves;
  llvm::SmallVector<ListRecipe, 4> listRecipes;
  llvm::SmallVector<StringLiteral, 4> literals;
  std::map<std::pair<unsigned, const void *>, unsigned> visited;
  llvm::SmallVector<Context, 4> contexts;
  std::array<Frame *, kMaxNodes> observedEnvs{};
  llvm::ArrayRef<Value *> observedArgs;
  llvm::SmallVector<Continuation, 16> continuations;
  std::map<std::tuple<unsigned, unsigned, unsigned, mlir::Operation *, unsigned>, unsigned> cpsCache;
  unsigned root = kDeoptDest, blocks = 5, expansions = 0;
  bool failed = false, pending = false, specializing = false;
  const bool inlineEnabled = [] {
    const char *setting = std::getenv("MLNIX_JIT_INLINE");
    return !setting || std::string_view(setting) != "0";
  }();
  const bool projectionEnabled = [] {
    const char *setting = std::getenv("MLNIX_JIT_PROJECTION");
    return !setting || std::string_view(setting) != "0";
  }();
  const bool pathsEnabled = projectionEnabled && [] {
    const char *setting = std::getenv("MLNIX_JIT_PATHS");
    return !setting || std::string_view(setting) != "0";
  }();
  const bool valuesEnabled = [] {
    const char *setting = std::getenv("MLNIX_JIT_VALUES");
    return !setting || std::string_view(setting) != "0";
  }();
  const bool listsEnabled = valuesEnabled && [] {
    const char *setting = std::getenv("MLNIX_JIT_LISTS");
    return !setting || std::string_view(setting) != "0";
  }();
  const bool stringsEnabled = [] {
    const char *setting = std::getenv("MLNIX_JIT_STRINGS");
    return !setting || std::string_view(setting) != "0";
  }();
  unsigned inlineCalls = 0, saturatedInlineCalls = 0, projections = 0, valueReturns = 0, listReturns = 0;
  unsigned comparisons = 0, literalBytes = 0;
  unsigned projectionComponents = 0, pathProjections = 0;
  bool valueTerminal = false;
  std::array<bool, kMaxLeaves> returnLeaves{};
  unsigned returnEmpties = 0;
  Impl(EvalState &state, mlir::Region &region, mlir::Value result)
      : region(region), state(state), result(result) {
    contexts.emplace_back(&region, 0, 0, region.getParentOp());
    arguments.push_back(region.front().getArgument(0));
    chainRegions.push_back(&region);
  }

  unsigned argumentIndex(mlir::Value v) const {
    for (unsigned i = 0; i < arguments.size(); ++i)
      if (arguments[i] == v) return i;
    return kNoArgument;
  }
  bool acceptsArguments(llvm::ArrayRef<Value *> args) const {
    if (args.size() != arguments.size()) return false;
    for (Value *arg : args) if (!arg) return false;
    return true;
  }
  // Caller must first validate complete native scope unwind. Recipe codes are
  // disjoint from every bounded cell index and the initially invalid code.
  bool finishValue(unsigned code, Value *const *cells, RunResult &out) const {
    if (code < leaves.size()) {
      if (!returnLeaves[code] || !cells[code] || cells[code]->isThunk()) return false;
      out.cell = cells[code];
    } else if (code >= kListCodeBase) {
      unsigned index = code - kListCodeBase;
      if (index >= listRecipes.size()) return false;
      const auto &recipe = listRecipes[index];
      if (!recipe.allowed || !recipe.size || recipe.size > kMaxListElements) return false;
      std::array<Value *, kMaxListElements> elements{};
      for (unsigned i = 0; i < recipe.size; ++i) {
        unsigned leaf = recipe.elements[i];
        if (leaf >= leaves.size() || leaves[leaf].kind != LeafKind::Cell || !cells[leaf]) return false;
        elements[i] = cells[leaf]; // Thunk, App and Blackhole are valid lazy elements
      }
      out.listElements = elements;
      out.listSize = recipe.size;
    } else {
      if (code < emptyCode(Empty::Attrs) || code > emptyCode(Empty::String)) return false;
      unsigned recipe = code - kMaxLeaves;
      if (!(returnEmpties & (1u << recipe))) return false;
      out.empty = Empty(recipe);
    }
    out.outcome = Outcome::Done;
    return true;
  }
  unsigned argumentBinding(mlir::Value v, unsigned context) const {
    if (!context) return kNoArgument;
    const auto &c = contexts[context];
    for (unsigned i = 0; i < c.formals.size(); ++i)
      if (c.formals[i] == v) return c.arguments[i];
    return kNoArgument;
  }
  bool persistent(mlir::Value v, unsigned context) const {
    auto *r = contexts[context].region;
    if (!context && argumentIndex(v) != kNoArgument) return true;
    if (unsigned binding = argumentBinding(v, context); binding != kNoArgument)
      return leaves[binding].kind == LeafKind::Cell;
    if (v.getParentRegion() == r) return false;
    // Eliminated stages have no runtime frame. Their formals are explicitly
    // substituted above; local definitions must remain opaque fallbacks. This
    // restriction is context-local: a separately captured inline callee can
    // have a real environment containing the very same SSA definitions.
    const auto &eliminated = context ? contexts[context].regions : chainRegions;
    for (auto *chainRegion : eliminated)
      if (v.getParentRegion() == chainRegion) return false;
    const nixev::Node *found = state.nodeOf(v.getAsOpaquePointer());
    return found && found->persists();
  }
  bool projection(mlir::Value v, unsigned context) const {
    auto select = v.getDefiningOp<nd::SelectOp>();
    if (!projectionEnabled || !select || select->getParentRegion() != contexts[context].region ||
        select.getDefaultValue() || select.getPath().empty() || select.getPath().size() > kMaxPathComponents ||
        !persistent(select.getBase(), context))
      return false;
    if (select.getPath().size() > 1)
      return pathsEnabled && select.getDynKeys().empty() &&
          llvm::all_of(select.getPath(), [](const auto &name) { return !name.isNull(); });
    return select.getPath().front().isNull()
        ? select.getDynKeys().size() == 1 && persistent(select.getDynKeys().front(), context)
        : select.getDynKeys().empty();
  }
  bool demandable(mlir::Value v, unsigned context) const {
    return argumentBinding(v, context) != kNoArgument || persistent(v, context) || projection(v, context);
  }
  unsigned leaf(mlir::Value v, unsigned context) {
    if (unsigned binding = argumentBinding(v, context); binding != kNoArgument) return binding;
    unsigned argument = context ? kNoArgument : argumentIndex(v);
    for (unsigned i = 0; i < leaves.size(); ++i)
      if (leaves[i].value == v && leaves[i].context == context) return i;
    Leaf l{v, context, argument};
    if (!persistent(v, context) && projection(v, context)) {
      auto select = v.getDefiningOp<nd::SelectOp>();
      l.kind = LeafKind::Projection;
      l.select = select;
      l.base = leaf(select.getBase(), context);
      l.pathSize = select.getPath().size();
      if (select.getPath().front().isNull()) l.key = leaf(select.getDynKeys().front(), context);
      else for (unsigned i = 0; i < l.pathSize; ++i) l.path[i] = state.symbolOf(select.getPath()[i]);
      ++projections;
      pathProjections += l.pathSize > 1;
      projectionComponents += l.pathSize;
      if (visited.size() + projectionComponents + literals.size() > kMaxNodes) failed = true;
    }
    if (failed || leaves.size() + literals.size() >= kMaxLeaves) { failed = true; return 0; }
    leaves.push_back(l);
    return leaves.size() - 1;
  }
  bool stringOperand(mlir::Value value, unsigned context) const {
    return demandable(value, context) || bool(value.getDefiningOp<nd::StringOp>());
  }
  StringOperand stringOperandHandle(mlir::Value value, unsigned context) {
    if (demandable(value, context)) return {leaf(value, context), kNoArgument};
    for (unsigned i = 0; i < literals.size(); ++i)
      if (literals[i].value == value) return {kNoArgument, i};
    llvm::StringRef bytes = value.getDefiningOp<nd::StringOp>().getValue().str();
    if (leaves.size() + literals.size() >= kMaxLeaves ||
        visited.size() + projectionComponents + literals.size() >= kMaxNodes ||
        bytes.size() > kMaxLiteralBytes - literalBytes) {
      failed = true;
      return {};
    }
    unsigned index = literals.size();
    literalBytes += bytes.size();
    literals.push_back({value, bytes.str()});
    return {kNoArgument, index};
  }
  Value *observed(unsigned index) const {
    const auto &l = leaves[index];
    return l.argument != kNoArgument ? observedArgs[l.argument]
                                    : existing(state, observedEnvs[l.context], l.value);
  }
  // Pure post-oracle read. A projection must already have a ready key, base,
  // intermediate fields and final field. A missing symbol is never interned.
  Value *peek(EvalState &st, Frame *const *envs, const uint8_t *active,
              llvm::ArrayRef<Value *> args, Value **cells, unsigned index, RunResult &result) const {
    if (cells[index]) return cells[index];
    const Leaf &l = leaves[index];
    if (!active[l.context]) return nullptr;
    if (l.kind == LeafKind::Cell)
      return cells[index] = l.argument != kNoArgument ? args[l.argument] : existing(st, envs[l.context], l.value);
    ++result.projectionRequests;
    result.pathProjectionRequests += l.pathSize > 1;
    auto miss = [&]() -> Value * { ++result.projectionDeopts; return nullptr; };
    Symbol symbol = l.path[0];
    if (l.key != kNoArgument) {
      Value *key = peek(st, envs, active, args, cells, l.key, result);
      if (!key || key->type != VType::String || key->str.ctx) return miss();
      Symbol *found = st.symbols.map.find(key->str.s, key->aux); // a name never interned is in no set: a miss, no symbol made
      if (!found) return miss();
      symbol = *found;
    }
    Value *current = peek(st, envs, active, args, cells, l.base, result);
    for (unsigned i = 0; i < l.pathSize; ++i) {
      if (!current || current->type != VType::Attrs) return miss();
      const Attr *attr = current->attrs->get(i ? l.path[i] : symbol);
      countProjectionLookup(*current->attrs, result);
      if (!attr || attr->value->isThunk()) return miss();
      current = attr->value;
    }
    return cells[index] = current;
  }
  unsigned visit(mlir::Value v, unsigned context = 0, unsigned depth = 0) {
    auto key = std::make_pair(context, v.getAsOpaquePointer());
    if (auto it = visited.find(key); it != visited.end()) {
      if (!it->second) { failed = true; return 0; }
      return it->second - 1;
    }
    if (depth >= kMaxNodes || visited.size() + projectionComponents + literals.size() >= kMaxNodes) { failed = true; return 0; }
    visited[key] = 0; // gray until all supported children have been visited
    auto *currentRegion = contexts[context].region;
    PlanNode n;
    if (demandable(v, context)) {
      n.kind = Kind::Leaf;
      n.leaf = leaf(v, context);
    } else if (auto *op = v.getDefiningOp(); op && op->getParentRegion() == currentRegion) {
      n.op = op;
      if (auto c = mlir::dyn_cast<nd::BoolOp>(op)) {
        n.kind = Kind::Constant;
        n.literal = c.getValue();
      } else if (valuesEnabled && !op->getNumOperands() &&
                 (mlir::isa<nd::AttrsOp, nd::ListOp>(op) ||
                  (mlir::isa<nd::StringOp>(op) && mlir::cast<nd::StringOp>(op).getValue().str().empty()))) {
        n.kind = Kind::Empty;
        n.empty = mlir::isa<nd::AttrsOp>(op) ? Empty::Attrs :
            mlir::isa<nd::ListOp>(op) ? Empty::List : Empty::String;
      } else if (auto list = mlir::dyn_cast<nd::ListOp>(op);
                 listsEnabled && list && !list.getElements().empty() &&
                 list.getElements().size() <= kMaxListElements &&
                 llvm::all_of(list.getElements(), [&](mlir::Value v) { return persistent(v, context); })) {
        // Eligibility is all-or-nothing and never walks a rejected element's
        // operands. A virtual projection cannot provide an unforced list cell.
        ListRecipe recipe;
        for (mlir::Value element : list.getElements()) {
          unsigned id = leaf(element, context);
          if (failed || id >= leaves.size() || leaves[id].kind != LeafKind::Cell) { failed = true; break; }
          recipe.elements[recipe.size++] = id;
        }
        if (listRecipes.size() >= kMaxNodes) failed = true;
        if (!failed) {
          n.kind = Kind::List;
          n.recipe = listRecipes.size();
          listRecipes.push_back(recipe);
        }
      } else if (stringsEnabled && mlir::isa<nd::EqOp, nd::NeqOp>(op) &&
                 stringOperand(op->getOperand(0), context) && stringOperand(op->getOperand(1), context)) {
        n.kind = Kind::StringCompare;
        n.unequal = mlir::isa<nd::NeqOp>(op);
        n.strings[0] = stringOperandHandle(op->getOperand(0), context);
        n.strings[1] = stringOperandHandle(op->getOperand(1), context);
        ++comparisons;
      } else if (mlir::isa<nd::NotOp>(op)) {
        n.kind = Kind::Not;
        n.a = visit(op->getOperand(0), context, depth + 1);
      } else if (mlir::isa<nd::AndOp, nd::OrOp, nd::ImplOp>(op)) {
        n.kind = mlir::isa<nd::AndOp>(op) ? Kind::And : mlir::isa<nd::OrOp>(op) ? Kind::Or : Kind::Impl;
        n.a = visit(op->getOperand(0), context, depth + 1);
        n.b = visit(op->getOperand(1), context, depth + 1);
      } else if (auto i = mlir::dyn_cast<nd::IfOp>(op)) {
        n.kind = Kind::If;
        n.a = visit(i.getCond(), context, depth + 1);
        n.b = visit(i.getThenValue(), context, depth + 1);
        n.c = visit(i.getElseValue(), context, depth + 1);
      } else if (auto h = mlir::dyn_cast<nd::HasAttrOp>(op);
                 h && h.getPath().size() == 1 && h.getDynKeys().empty() && demandable(h.getBase(), context)) {
        n.kind = Kind::HasAttr;
        n.leaf = leaf(h.getBase(), context);
        n.symbol = state.symbolOf(h.getPath().front());
      } else if (int tag = predicateTag(op->getName().getStringRef());
                 tag >= 0 && op->getNumOperands() == 1 && demandable(op->getOperand(0), context)) {
        auto *prim = state.primFor(op);
        if (prim && prim->arity == 1) {
          n.kind = Kind::Predicate;
          n.tag = VType(tag);
          n.function = op->getName().getStringRef() == "nixty.is_function";
          n.leaf = leaf(op->getOperand(0), context);
        }
      } else if (auto call = mlir::dyn_cast<nd::ApplyOp>(op);
                 inlineEnabled && call && !call.getArgs().empty() && call.getArgs().size() <= kMaxArguments &&
                 persistent(call.getCallee(), context) && llvm::all_of(call.getArgs(), [&](mlir::Value arg) {
                   return demandable(arg, context);
                 })) {
        pending = true;
        n.leaf = leaf(call.getCallee(), context);
        llvm::SmallVector<unsigned, kMaxArguments> bindings;
        for (mlir::Value arg : call.getArgs()) bindings.push_back(leaf(arg, context));
        Value *callee = specializing && !failed ? observed(n.leaf) : nullptr;
        auto target = callee && callee->type == VType::Lambda ? mlir::dyn_cast<nd::LambdaOp>(callee->thunk.node->def) : nd::LambdaOp{};
        if (target && contexts[context].depth < kMaxInlineDepth && contexts.size() < kMaxNodes) {
          Context child(&target.getBody(), context, contexts[context].depth + 1, target);
          child.arguments = std::move(bindings);
          mlir::Value bodyResult;
          auto stage = target;
          bool eligible = true;
          for (unsigned i = 0; i < call.getArgs().size(); ++i) {
            if (!stage || stage.getFormals() || !llvm::hasSingleElement(stage.getBody()) ||
                stage.getBody().front().getNumArguments() != 1) { eligible = false; break; }
            for (unsigned c = context;; c = contexts[c].parent) {
              const auto &regions = c ? contexts[c].regions : chainRegions;
              for (auto *r : regions)
                if (r->getParentOp() == stage.getOperation()) eligible = false;
              if (!c) break;
            }
            for (auto *r : child.regions)
              if (r == &stage.getBody()) eligible = false;
            RegionInfo **body = state.regionInfos.find(uint64_t(uintptr_t(&stage.getBody())));
            if (!eligible || !body || !(*body)->result) { eligible = false; break; }
            child.region = &stage.getBody();
            child.regions.push_back(child.region);
            child.formals.push_back(child.region->front().getArgument(0));
            bodyResult = (*body)->result;
            if (i + 1 < call.getArgs().size()) {
              stage = bodyResult.getDefiningOp<nd::LambdaOp>();
              if (!stage || stage->getParentRegion() != child.region) { eligible = false; break; }
            }
          }
          // Only already-indexed, direct unary chains are combined. Their stages
          // run sequentially at one depth, using the actual OUTER closure env.
          if (eligible) {
            n.kind = Kind::Call;
            n.target = target;
            n.targetNode = callee->thunk.node;
            n.arity = call.getArgs().size();
            n.context = contexts.size();
            contexts.push_back(std::move(child));
            observedEnvs[n.context] = callee->thunk.env;
            n.a = visit(bodyResult, n.context, depth + 1);
            ++inlineCalls;
            saturatedInlineCalls += n.arity > 1;
          }
        }
      }
      // An unknown local is a branch-local deopt. Do not walk its operands:
      // recursive applies and effects behind a short circuit remain opaque.
    }
    if (!failed)
      n.returnsValue = n.kind == Kind::Leaf || n.kind == Kind::Empty || n.kind == Kind::List ||
          (n.kind == Kind::If && (nodes[n.b].returnsValue || nodes[n.c].returnsValue)) ||
          (n.kind == Kind::Call && nodes[n.a].returnsValue);
    unsigned index = nodes.size();
    nodes.push_back(n);
    visited[key] = index + 1;
    return index;
  }

  unsigned cps(unsigned index, unsigned yes, unsigned no, mlir::Operation *consumer,
               unsigned valueDest = kNoValueDest) {
    if (failed) return kDeoptDest;
    auto key = std::make_tuple(index, yes, no, consumer, valueDest);
    if (auto it = cpsCache.find(key); it != cpsCache.end()) return it->second;
    // Bound continuation specialization, including compound nodes whose shared
    // DAG could otherwise expand exponentially under different continuations.
    if (++expansions > kMaxBlocks) { failed = true; return kDeoptDest; }
    const PlanNode &n = nodes[index];
    unsigned result = kDeoptDest;
    switch (n.kind) {
    case Kind::Deopt: break;
    case Kind::Constant: result = n.literal ? yes : no; break;
    case Kind::Empty:
      // Constructors are never coerced to Bool. Their recipe is valid only in
      // a tail value context and is materialized by the host after all Leaves.
      if (valueDest == kNoValueDest) break;
      ++blocks;
      if (!valueTerminal) { valueTerminal = true; ++blocks; }
      if (blocks > kMaxBlocks) { failed = true; return kDeoptDest; }
      result = continuations.size() + 3;
      continuations.push_back({index, valueDest, valueDest, consumer, Action::ReturnEmpty});
      returnEmpties |= 1u << unsigned(n.empty);
      ++valueReturns;
      break;
    case Kind::List:
      if (valueDest == kNoValueDest) break;
      blocks += 3; // handle availability, one batched request, ready recipe
      if (!valueTerminal) { valueTerminal = true; ++blocks; }
      if (blocks > kMaxBlocks) { failed = true; return kDeoptDest; }
      result = continuations.size() + 3;
      continuations.push_back({index, valueDest, valueDest, consumer, Action::ReturnList});
      listRecipes[n.recipe].allowed = true;
      ++valueReturns;
      ++listReturns;
      break;
    case Kind::Not: result = cps(n.a, no, yes, n.op); break;
    case Kind::And: result = cps(n.a, cps(n.b, yes, no, n.op), no, n.op); break;
    case Kind::Or: result = cps(n.a, yes, cps(n.b, yes, no, n.op), n.op); break;
    case Kind::Impl: result = cps(n.a, cps(n.b, yes, no, n.op), yes, n.op); break;
    case Kind::If:
      result = cps(n.a, cps(n.b, yes, no, n.op, valueDest), cps(n.c, yes, no, n.op, valueDest), n.op);
      break;
    case Kind::Call: {
      bool returnValue = valueDest != kNoValueDest && nodes[n.a].returnsValue;
      blocks += 13 + (returnValue ? 2 : 0); // native enter plus Boolean and optional value leaves
      if (blocks > kMaxBlocks) { failed = true; return kDeoptDest; }
      unsigned leaveYes = continuations.size() + 3;
      continuations.push_back({index, yes, yes, n.op, Action::Leave});
      unsigned leaveNo = continuations.size() + 3;
      continuations.push_back({index, no, no, n.op, Action::Leave});
      unsigned leaveValue = kNoValueDest;
      if (returnValue) {
        leaveValue = continuations.size() + 3;
        continuations.push_back({index, valueDest, valueDest, n.op, Action::Leave});
      }
      unsigned body = cps(n.a, leaveYes, leaveNo, n.op, leaveValue);
      result = continuations.size() + 3;
      continuations.push_back({index, body, kDeoptDest, n.op, Action::Enter});
      break;
    }
    case Kind::StringCompare: {
      // Both WHNF demands precede the type guards, exactly like Eq/Neq. Each
      // resumption reloads the cells; no payload survives a host forcing action.
      blocks += 6;
      for (const auto &operand : n.strings) blocks += operand.leaf != kNoArgument ? 4 : 0;
      if (blocks > kMaxBlocks) { failed = true; return kDeoptDest; }
      result = continuations.size() + 3;
      continuations.push_back({index, yes, no, n.op});
      for (unsigned operand : {1u, 0u}) {
        if (n.strings[operand].leaf == kNoArgument) continue;
        unsigned next = continuations.size() + 3;
        continuations.push_back({index, result, result, n.op, Action::StringDemand, n.strings[operand].leaf});
        result = next;
      }
      break;
    }
    case Kind::Leaf:
      if (valueDest != kNoValueDest) {
        blocks += 4;
        if (!valueTerminal) { valueTerminal = true; ++blocks; }
        if (blocks > kMaxBlocks) { failed = true; return kDeoptDest; }
        result = continuations.size() + 3;
        continuations.push_back({index, valueDest, valueDest, consumer, Action::ReturnValue});
        returnLeaves[n.leaf] = true;
        ++valueReturns;
        break;
      }
      // Bare identities use the pointer tier's call-site tail position. A root
      // projection instead carries its own Select position for the final force.
      if (!consumer && leaves[n.leaf].kind != LeafKind::Projection) break;
      [[fallthrough]];
    case Kind::Predicate:
    case Kind::HasAttr:
      blocks += n.kind == Kind::HasAttr ? 9 : n.kind == Kind::Leaf ? 5 : 4;
      if (blocks > kMaxBlocks) { failed = true; return kDeoptDest; }
      result = continuations.size() + 3;
      continuations.push_back({index, yes, no, n.kind == Kind::Leaf
          ? (consumer ? consumer : leaves[n.leaf].select) : n.op});
      break;
    }
    cpsCache.emplace(key, result);
    return result;
  }
  bool completes(unsigned dest, llvm::SmallVectorImpl<bool> &seen) const {
    if (dest == kFalseDest || dest == kTrueDest || dest == kValueDest) return true;
    if (dest == kDeoptDest || seen[dest - 3]) return false;
    seen[dest - 3] = true;
    const auto &c = continuations[dest - 3];
    return completes(c.yes, seen) || completes(c.no, seen);
  }
};

LazyJITPlan::LazyJITPlan(std::unique_ptr<Impl> impl) : impl(std::move(impl)) {}
LazyJITPlan::~LazyJITPlan() = default;
std::unique_ptr<LazyJITPlan> LazyJITPlan::create(EvalState &st, mlir::Operation *lambda, mlir::Value result) {
  auto lam = mlir::dyn_cast<nd::LambdaOp>(lambda);
  if (!lam || lam.getFormals() || !llvm::hasSingleElement(lam.getBody()) ||
      lam.getBody().front().getNumArguments() != 1) return {};
  auto p = std::make_unique<Impl>(st, lam.getBody(), result);
  unsigned resultNode = p->visit(result);
  if (p->failed) return {};
  p->root = p->cps(resultNode, kTrueDest, kFalseDest, nullptr, p->valuesEnabled ? kValueDest : kNoValueDest);
  llvm::SmallVector<bool, 16> seen(p->continuations.size(), false);
  if (p->failed || (!p->completes(p->root, seen) && !p->pending)) return {};
  return std::unique_ptr<LazyJITPlan>(new LazyJITPlan(std::move(p)));
}
std::unique_ptr<LazyJITPlan> LazyJITPlan::createSaturated(EvalState &st, mlir::Operation *outerLambda,
                                                       unsigned nargs) {
  if (nargs < 2 || nargs > kMaxArguments) return {};
  llvm::SmallVector<mlir::Value, kMaxArguments> arguments;
  llvm::SmallVector<mlir::Region *, kMaxArguments> regions;
  auto lambda = mlir::dyn_cast<nd::LambdaOp>(outerLambda);
  mlir::Value result;
  for (unsigned i = 0; i < nargs; ++i) {
    if (!lambda || lambda.getFormals() || !llvm::hasSingleElement(lambda.getBody()) ||
        lambda.getBody().front().getNumArguments() != 1) return {};
    auto *region = &lambda.getBody();
    for (auto *previous : regions) if (previous == region) return {};
    RegionInfo **body = st.regionInfos.find(uint64_t(uintptr_t(region)));
    if (!body || !(*body)->result) return {};
    regions.push_back(region);
    arguments.push_back(region->front().getArgument(0));
    result = (*body)->result;
    if (i + 1 < nargs) {
      lambda = result.getDefiningOp<nd::LambdaOp>();
      if (!lambda || lambda->getParentRegion() != region) return {};
    }
  }
  // A returned closure is an underapplication, not a Boolean result. We also
  // never inspect or mint opaque descendant bodies: visit only compiles known
  // Boolean operations and keeps their unsupported branches as deopts.
  if (result.getDefiningOp<nd::LambdaOp>()) return {};
  auto p = std::make_unique<Impl>(st, *regions.back(), result);
  p->arguments = std::move(arguments);
  p->chainRegions = std::move(regions);
  unsigned resultNode = p->visit(result);
  if (p->failed) return {};
  p->root = p->cps(resultNode, kTrueDest, kFalseDest, nullptr, p->valuesEnabled ? kValueDest : kNoValueDest);
  llvm::SmallVector<bool, 16> seen(p->continuations.size(), false);
  if (p->failed || (!p->completes(p->root, seen) && !p->pending)) return {};
  return std::unique_ptr<LazyJITPlan>(new LazyJITPlan(std::move(p)));
}
unsigned LazyJITPlan::nodeCount() const { return impl->nodes.size() + impl->projectionComponents + impl->literals.size(); }
unsigned LazyJITPlan::leafCount() const { return impl->leaves.size(); }
unsigned LazyJITPlan::blockCount() const { return impl->blocks; }
unsigned LazyJITPlan::argumentCount() const { return impl->arguments.size(); }
unsigned LazyJITPlan::inlineCallCount() const { return impl->inlineCalls; }
unsigned LazyJITPlan::saturatedInlineCallCount() const { return impl->saturatedInlineCalls; }
unsigned LazyJITPlan::projectionCount() const { return impl->projections; }
unsigned LazyJITPlan::valueReturnCount() const { return impl->valueReturns; }
unsigned LazyJITPlan::listReturnCount() const { return impl->listReturns; }
unsigned LazyJITPlan::comparisonCount() const { return impl->comparisons; }
unsigned LazyJITPlan::pathProjectionCount() const { return impl->pathProjections; }
bool LazyJITPlan::needsSpecialization() const { return impl->pending; }
bool LazyJITPlan::specialize(EvalState &st, Frame *env, Value &arg) {
  Value *args[]{&arg};
  return specialize(st, env, args);
}
bool LazyJITPlan::specialize(EvalState &st, Frame *env, llvm::ArrayRef<Value *> args) {
  if (!impl->acceptsArguments(args)) return false;
  if (!impl->pending) return true;
  auto p = std::make_unique<Impl>(st, impl->region, impl->result);
  p->arguments = impl->arguments;
  p->chainRegions = impl->chainRegions;
  p->specializing = true;
  p->observedEnvs[0] = env;
  p->observedArgs = args;
  unsigned resultNode = p->visit(p->result);
  if (p->failed) return false;
  p->root = p->cps(resultNode, kTrueDest, kFalseDest, nullptr, p->valuesEnabled ? kValueDest : kNoValueDest);
  llvm::SmallVector<bool, 16> seen(p->continuations.size(), false);
  if (p->failed || !p->completes(p->root, seen)) return false;
  p->pending = false;
  p->observedArgs = {};
  p->observedEnvs.fill(nullptr); // observed environments are never retained by generated code
  impl = std::move(p);
  return true;
}

void LazyJITPlan::print(llvm::raw_ostream &os) const {
  static constexpr const char *names[]{"deopt", "constant", "leaf", "predicate", "has_attr",
                                      "not", "and", "or", "impl", "if", "call", "empty", "list", "string_compare"};
  os << "lazy-boolean-cps nodes=" << nodeCount() << "/" << kMaxNodes << " leaves=" << leafCount()
     << "/" << kMaxLeaves << " blocks=" << blockCount() << "/" << kMaxBlocks
     << " resume-limit=" << kMaxResumes << " inline-calls=" << inlineCallCount()
     << " saturated-inline-calls=" << saturatedInlineCallCount() << " projections=" << projectionCount()
     << " path-projections=" << pathProjectionCount() << " projection-components=" << impl->projectionComponents
     << " value-returns=" << valueReturnCount() << " list-returns=" << listReturnCount()
     << " string-comparisons=" << comparisonCount() << " literal-bytes=" << impl->literalBytes << "/" << kMaxLiteralBytes
     << " operand-slots=" << impl->leaves.size() + impl->literals.size() << "/" << kMaxLeaves
     << " inline-depth-limit=" << kMaxInlineDepth << " chain-count=" << argumentCount()
     << " entry=" << impl->root << "\n";
  os << "destinations: 0=false 1=true 2=deopt; resume=destination+1 (0=entry)\n"
        "value terminal: " << kValueDest << " (no resume entry)\n"
        "empty result codes: " << emptyCode(Empty::Attrs) << "=attrs " << emptyCode(Empty::List)
     << "=list " << emptyCode(Empty::String) << "=string\n"
        "list result codes: " << kListCodeBase << "+recipe-id (unforced persistent handles)\n"
        "statuses: 2=demand 5=depth-overflow 6=value 7=guard-miss; continuation in upper bits\n"
        "call entry/leave bookkeeping stays in native control flow\n";
  for (unsigned i = 0; i < impl->leaves.size(); ++i) {
    const Leaf &leaf = impl->leaves[i];
    os << "leaf " << i << " context=" << leaf.context;
    if (leaf.kind == LeafKind::Projection) {
      os << " projection base=" << leaf.base;
      if (leaf.key != kNoArgument) os << " dynamic-key=" << leaf.key;
      else {
        os << " static-path=";
        for (unsigned j = 0; j < leaf.pathSize; ++j) os << (j ? "," : "") << leaf.path[j];
      }
      os << "\n";
    } else if (leaf.argument != kNoArgument) os << " argument=" << leaf.argument << "\n";
    else os << " current-closure capture\n";
  }
  for (unsigned i = 0; i < impl->nodes.size(); ++i) {
    const PlanNode &n = impl->nodes[i];
    os << "node " << i << " " << names[unsigned(n.kind)];
    if (n.kind == Kind::Constant) os << " " << n.literal;
    if (n.kind == Kind::Empty) os << " recipe=" << emptyName(n.empty) << " code=" << emptyCode(n.empty);
    if (n.kind == Kind::List) {
      os << " recipe=" << n.recipe << " code=" << kListCodeBase + n.recipe << " leaves=";
      const auto &recipe = impl->listRecipes[n.recipe];
      for (unsigned j = 0; j < recipe.size; ++j) os << (j ? "," : "") << recipe.elements[j];
    }
    if (n.kind == Kind::Leaf || n.kind == Kind::Predicate || n.kind == Kind::HasAttr) os << " leaf=" << n.leaf;
    if (n.kind == Kind::Predicate) os << " tag=" << unsigned(n.tag) << " function=" << n.function;
    if (n.kind == Kind::HasAttr) os << " symbol=" << n.symbol;
    if (n.kind == Kind::StringCompare) {
      os << (n.unequal ? " neq" : " eq");
      for (unsigned j = 0; j < 2; ++j) {
        os << (j ? " rhs=" : " lhs=");
        const auto &operand = n.strings[j];
        if (operand.leaf != kNoArgument) os << "leaf:" << operand.leaf;
        else os << "literal:" << operand.literal << ":" << impl->literals[operand.literal].bytes.size() << "bytes";
      }
    }
    if (n.kind == Kind::Not || n.kind == Kind::And || n.kind == Kind::Or || n.kind == Kind::Impl || n.kind == Kind::If)
      os << " a=" << n.a;
    if (n.kind == Kind::And || n.kind == Kind::Or || n.kind == Kind::Impl || n.kind == Kind::If) os << " b=" << n.b;
    if (n.kind == Kind::If) os << " c=" << n.c;
    if (n.kind == Kind::Call)
      os << " callee-leaf=" << n.leaf << " context=" << n.context << " arity=" << n.arity << " body=" << n.a;
    os << "\n";
  }
  for (unsigned i = 0; i < impl->continuations.size(); ++i) {
    const auto &c = impl->continuations[i];
    os << "continuation " << i + 3 << " node=" << c.node << " action=" << unsigned(c.action)
       << " true=" << c.yes << " false=" << c.no;
    if (c.consumer) os << " consumer=" << c.consumer->getName().getStringRef();
    else if (c.action == Action::ReturnValue) os << " consumer=call-site";
    if (c.action == Action::StringDemand) os << " demand-leaf=" << c.demandLeaf;
    os << "\n";
  }
}

bool LazyJITPlan::emit(mlir::ModuleOp module) {
  using namespace mlir;
  OpBuilder b(module.getContext());
  auto loc = b.getUnknownLoc();
  auto i8 = b.getI8Type(), i32 = b.getI32Type(), i64 = b.getI64Type();
  auto ptr = LLVM::LLVMPointerType::get(module.getContext());
  b.setInsertionPointToEnd(module.getBody());
  auto fun = func::FuncOp::create(b, loc, "scalar", b.getFunctionType({i32, ptr}, {i64}));
  Block *entry = fun.addEntryBlock();
  auto newBlock = [&]() { auto *block = new Block; fun.getBody().push_back(block); return block; };
  llvm::SmallVector<Block *, 16> destinations;
  for (unsigned i = 0; i < impl->continuations.size() + 3; ++i) destinations.push_back(newBlock());
  Block *invalid = newBlock();
  Block *valueTerminal = impl->valueTerminal ? newBlock() : nullptr;
  auto destination = [&](unsigned id) { return id == kValueDest ? valueTerminal : destinations[id]; };
  auto cst = [&](int64_t n, unsigned bits = 64) -> mlir::Value {
    return arith::ConstantIntOp::create(b, loc, n, bits);
  };
  auto offset = [&](mlir::Value base, mlir::Value bytes) -> mlir::Value {
    return LLVM::GEPOp::create(b, loc, ptr, i8, base, ValueRange{bytes});
  };
  auto load = [&](Type type, mlir::Value base, size_t bytes) -> mlir::Value {
    return LLVM::LoadOp::create(b, loc, type, offset(base, cst(bytes)));
  };
  auto runtime = entry->getArgument(1);
  auto store = [&](mlir::Value value, size_t bytes) {
    LLVM::StoreOp::create(b, loc, value, offset(runtime, cst(bytes)));
  };
  auto cmp = [&](arith::CmpIPredicate p, mlir::Value x, mlir::Value y) -> mlir::Value {
    return arith::CmpIOp::create(b, loc, p, x, y);
  };
  auto branch = [&](mlir::Value cond, Block *yes, Block *no) {
    cf::CondBranchOp::create(b, loc, cond, yes, ValueRange{}, no, ValueRange{});
  };
  auto ret = [&](uint64_t status) { func::ReturnOp::create(b, loc, ValueRange{cst(status)}); };
  for (unsigned d = 0; d < 3; ++d) {
    b.setInsertionPointToEnd(destinations[d]);
    ret(d == kDeoptDest ? kDeopt : d);
  }
  if (valueTerminal) {
    b.setInsertionPointToEnd(valueTerminal);
    ret(kValue);
  }
  b.setInsertionPointToEnd(invalid);
  ret(kInvalid);
  b.setInsertionPointToEnd(entry);
  llvm::SmallVector<int32_t> cases{0};
  llvm::SmallVector<Block *> targets{destinations[impl->root]};
  llvm::SmallVector<ValueRange> operands{ValueRange{}};
  for (unsigned d = 0; d < destinations.size(); ++d) {
    cases.push_back(d + 1);
    targets.push_back(destinations[d]);
    operands.push_back(ValueRange{});
  }
  cf::SwitchOp::create(b, loc, entry->getArgument(0), invalid, ValueRange{}, cases, targets, operands);

  for (unsigned i = 0; i < impl->continuations.size(); ++i) {
    const Continuation &c = impl->continuations[i];
    const PlanNode &n = impl->nodes[c.node];
    if (n.kind == Kind::StringCompare && c.action == Action::Atomic) {
      Block *ready = newBlock(), *guardMiss = newBlock(), *loop = newBlock(), *probe = newBlock(), *step = newBlock();
      b.setInsertionPointToEnd(destinations[i + 3]);
      std::array<mlir::Value, 2> cells;
      mlir::Value strings = cst(1, 1);
      for (unsigned j = 0; j < 2; ++j) {
        const auto &operand = n.strings[j];
        if (operand.leaf == kNoArgument) continue;
        cells[j] = load(ptr, runtime, offsetof(Runtime, cells) + operand.leaf * sizeof(nixev::Value *));
        auto tag = load(i8, cells[j], offsetof(nixev::Value, type));
        strings = arith::AndIOp::create(b, loc, strings,
            cmp(arith::CmpIPredicate::eq, tag, cst(int(VType::String), 8)));
      }
      branch(strings, ready, guardMiss);
      b.setInsertionPointToEnd(guardMiss);
      auto misses = load(i32, runtime, offsetof(Runtime, stringGuardDeopts));
      store(arith::AddIOp::create(b, loc, misses, cst(1, 32)), offsetof(Runtime, stringGuardDeopts));
      cf::BranchOp::create(b, loc, destinations[kDeoptDest]);
      b.setInsertionPointToEnd(ready);
      auto comparisons = load(i32, runtime, offsetof(Runtime, stringComparisons));
      store(arith::AddIOp::create(b, loc, comparisons, cst(1, 32)), offsetof(Runtime, stringComparisons));
      std::array<mlir::Value, 2> data, lengths;
      for (unsigned j = 0; j < 2; ++j) {
        const auto &operand = n.strings[j];
        if (operand.literal != kNoArgument) {
          const auto &bytes = impl->literals[operand.literal].bytes;
          data[j] = LLVM::IntToPtrOp::create(b, loc, ptr, cst(reinterpret_cast<uintptr_t>(bytes.data())));
          lengths[j] = cst(bytes.size());
        } else {
          data[j] = load(ptr, cells[j], offsetof(nixev::Value, str.s));
          lengths[j] = arith::ExtUIOp::create(b, loc, i64, load(i32, cells[j], offsetof(nixev::Value, aux)));
        }
      }
      Block *equal = destinations[n.unequal ? c.no : c.yes];
      Block *different = destinations[n.unequal ? c.yes : c.no];
      loop->addArgument(i64, loc);
      cf::CondBranchOp::create(b, loc, cmp(arith::CmpIPredicate::eq, lengths[0], lengths[1]),
                              loop, ValueRange{cst(0)}, different, ValueRange{});
      b.setInsertionPointToEnd(loop);
      auto index = loop->getArgument(0);
      branch(cmp(arith::CmpIPredicate::ult, index, lengths[0]), probe, equal);
      b.setInsertionPointToEnd(probe);
      auto left = LLVM::LoadOp::create(b, loc, i8, offset(data[0], index));
      auto right = LLVM::LoadOp::create(b, loc, i8, offset(data[1], index));
      branch(cmp(arith::CmpIPredicate::eq, left, right), step, different);
      b.setInsertionPointToEnd(step);
      cf::BranchOp::create(b, loc, loop, ValueRange{arith::AddIOp::create(b, loc, index, cst(1))});
      continue;
    }
    if (c.action == Action::ReturnList) {
      Block *request = newBlock(), *ready = newBlock();
      b.setInsertionPointToEnd(destinations[i + 3]);
      mlir::Value present = cst(1, 1);
      const auto &recipe = impl->listRecipes[n.recipe];
      auto null = LLVM::ZeroOp::create(b, loc, ptr);
      for (unsigned j = 0; j < recipe.size; ++j) {
        auto cell = load(ptr, runtime, offsetof(Runtime, cells) + recipe.elements[j] * sizeof(nixev::Value *));
        auto nonnull = LLVM::ICmpOp::create(b, loc, LLVM::ICmpPredicate::ne, cell, null);
        present = arith::AndIOp::create(b, loc, present, nonnull);
      }
      branch(present, ready, request);
      b.setInsertionPointToEnd(request);
      ret((uint64_t(i + 3) << 3) | kDemand);
      b.setInsertionPointToEnd(ready);
      store(cst(kListCodeBase + n.recipe, 32), offsetof(Runtime, resultLeaf));
      cf::BranchOp::create(b, loc, destination(c.yes));
      continue;
    }
    if (c.action == Action::ReturnEmpty) {
      b.setInsertionPointToEnd(destinations[i + 3]);
      store(cst(emptyCode(n.empty), 32), offsetof(Runtime, resultLeaf));
      cf::BranchOp::create(b, loc, destination(c.yes));
      continue;
    }
    if (c.action == Action::Leave) {
      Block *leave = newBlock();
      b.setInsertionPointToEnd(destinations[i + 3]);
      auto depth = load(i32, runtime, offsetof(Runtime, depth));
      auto context = load(i32, runtime, offsetof(Runtime, currentContext));
      auto valid = arith::AndIOp::create(b, loc,
          cmp(arith::CmpIPredicate::eq, depth, cst(impl->contexts[n.context].depth, 32)),
          cmp(arith::CmpIPredicate::eq, context, cst(n.context, 32)));
      branch(valid, leave, invalid);
      b.setInsertionPointToEnd(leave);
      store(cst(0, 8), offsetof(Runtime, active) + n.context);
      store(cst(impl->contexts[n.context].parent, 32), offsetof(Runtime, currentContext));
      store(arith::SubIOp::create(b, loc, depth, cst(1, 32)), offsetof(Runtime, depth));
      cf::BranchOp::create(b, loc, destination(c.yes));
      continue;
    }
    Block *request = newBlock(), *resolved = newBlock(), *ready = newBlock();
    b.setInsertionPointToEnd(request);
    ret((uint64_t(i + 3) << 3) | kDemand);
    b.setInsertionPointToEnd(destinations[i + 3]);
    unsigned demandLeaf = c.action == Action::StringDemand ? c.demandLeaf : n.leaf;
    mlir::Value cell = load(ptr, runtime, offsetof(Runtime, cells) + demandLeaf * sizeof(nixev::Value *));
    auto null = LLVM::ZeroOp::create(b, loc, ptr);
    auto missing = LLVM::ICmpOp::create(b, loc, LLVM::ICmpPredicate::eq, cell, null);
    branch(missing, request, resolved);
    b.setInsertionPointToEnd(resolved);
    mlir::Value tag = load(i8, cell, offsetof(nixev::Value, type));
    if (c.action == Action::Enter) {
      Block *miss = newBlock(), *matched = newBlock(), *scoped = newBlock(), *overflow = newBlock(), *enter = newBlock();
      branch(cmp(arith::CmpIPredicate::eq, tag, cst(int(VType::Lambda), 8)), ready, miss);
      b.setInsertionPointToEnd(ready);
      auto actual = load(ptr, cell, offsetof(nixev::Value, thunk)); // thunk.node is its first member
      auto expected = LLVM::IntToPtrOp::create(b, loc, ptr, cst(reinterpret_cast<uintptr_t>(n.targetNode)));
      branch(LLVM::ICmpOp::create(b, loc, LLVM::ICmpPredicate::eq, actual, expected), matched, miss);
      b.setInsertionPointToEnd(miss);
      ret((uint64_t(i + 3) << 3) | kGuardMiss);
      b.setInsertionPointToEnd(matched);
      unsigned parent = impl->contexts[n.context].parent;
      auto depth = load(i32, runtime, offsetof(Runtime, depth));
      auto context = load(i32, runtime, offsetof(Runtime, currentContext));
      auto parentActive = load(i8, runtime, offsetof(Runtime, active) + parent);
      auto scopeMatches = arith::AndIOp::create(b, loc,
          cmp(arith::CmpIPredicate::eq, depth, cst(impl->contexts[parent].depth, 32)),
          cmp(arith::CmpIPredicate::eq, context, cst(parent, 32)));
      branch(arith::AndIOp::create(b, loc, scopeMatches,
          cmp(arith::CmpIPredicate::ne, parentActive, cst(0, 8))), scoped, invalid);
      b.setInsertionPointToEnd(scoped);
      auto initial = load(i32, runtime, offsetof(Runtime, initialDepth));
      auto maximum = load(i32, runtime, offsetof(Runtime, maxDepth));
      auto logicalDepth = arith::AddIOp::create(b, loc,
          arith::ExtUIOp::create(b, loc, i64, initial), arith::ExtUIOp::create(b, loc, i64, depth));
      branch(cmp(arith::CmpIPredicate::uge, logicalDepth,
          arith::ExtUIOp::create(b, loc, i64, maximum)), overflow, enter);
      b.setInsertionPointToEnd(overflow);
      ret((uint64_t(i + 3) << 3) | kDepthOverflow);
      b.setInsertionPointToEnd(enter);
      auto closureEnv = load(ptr, cell, offsetof(nixev::Value, thunk.env));
      store(closureEnv, offsetof(Runtime, envs) + n.context * sizeof(Frame *));
      store(cst(1, 8), offsetof(Runtime, active) + n.context);
      store(cst(n.context, 32), offsetof(Runtime, currentContext));
      store(arith::AddIOp::create(b, loc, depth, cst(1, 32)), offsetof(Runtime, depth));
      auto entered = load(i32, runtime, offsetof(Runtime, inlineCalls));
      store(arith::AddIOp::create(b, loc, entered, cst(1, 32)), offsetof(Runtime, inlineCalls));
      if (n.arity > 1) {
        auto saturated = load(i32, runtime, offsetof(Runtime, saturatedInlineCalls));
        store(arith::AddIOp::create(b, loc, saturated, cst(1, 32)), offsetof(Runtime, saturatedInlineCalls));
      }
      for (unsigned l = 0; l < impl->leaves.size(); ++l)
        if (impl->leaves[l].context == n.context)
          store(LLVM::ZeroOp::create(b, loc, ptr), offsetof(Runtime, cells) + l * sizeof(nixev::Value *));
      cf::BranchOp::create(b, loc, destination(c.yes));
      continue;
    }
    branch(cmp(arith::CmpIPredicate::ule, tag, cst(int(VType::Blackhole), 8)), request, ready);
    b.setInsertionPointToEnd(ready);
    if (c.action == Action::StringDemand) {
      cf::BranchOp::create(b, loc, destination(c.yes));
      continue;
    }
    if (c.action == Action::ReturnValue) {
      store(cst(n.leaf, 32), offsetof(Runtime, resultLeaf));
      cf::BranchOp::create(b, loc, destination(c.yes));
      continue;
    }
    if (n.kind == Kind::Leaf) {
      Block *boolean = newBlock();
      branch(cmp(arith::CmpIPredicate::eq, tag, cst(int(VType::Bool), 8)), boolean, destinations[kDeoptDest]);
      b.setInsertionPointToEnd(boolean);
      mlir::Value value = load(i8, cell, offsetof(nixev::Value, boolean));
      branch(cmp(arith::CmpIPredicate::ne, value, cst(0, 8)), destinations[c.yes], destinations[c.no]);
    } else if (n.kind == Kind::Predicate) {
      mlir::Value value = cmp(arith::CmpIPredicate::eq, tag, cst(int(n.tag), 8));
      if (n.function) {
        auto prim = cmp(arith::CmpIPredicate::eq, tag, cst(int(VType::PrimOp), 8));
        auto app = cmp(arith::CmpIPredicate::eq, tag, cst(int(VType::PrimOpApp), 8));
        value = arith::OrIOp::create(b, loc, value, arith::OrIOp::create(b, loc, prim, app));
      }
      branch(value, destinations[c.yes], destinations[c.no]);
    } else {
      Block *attrs = newBlock(), *flat = newBlock(), *loop = newBlock(), *probe = newBlock(), *step = newBlock();
      // All rows in Bindings are sorted by their interned Symbol, in one array (a `//` merges).
      branch(cmp(arith::CmpIPredicate::eq, tag, cst(int(VType::Attrs), 8)), attrs, destinations[c.no]);
      b.setInsertionPointToEnd(attrs);
      mlir::Value bindings = load(ptr, cell, offsetof(nixev::Value, attrs));
      mlir::Value size = load(i32, bindings, offsetof(Bindings, size_));
      cf::BranchOp::create(b, loc, flat);
      b.setInsertionPointToEnd(flat);
      mlir::Value count = arith::ExtUIOp::create(b, loc, i64, size);
      loop->addArgument(i64, loc);
      loop->addArgument(i64, loc);
      cf::BranchOp::create(b, loc, loop, ValueRange{cst(0), count});
      b.setInsertionPointToEnd(loop);
      auto lo = loop->getArgument(0), hi = loop->getArgument(1);
      branch(cmp(arith::CmpIPredicate::ult, lo, hi), probe, destinations[c.no]);
      b.setInsertionPointToEnd(probe);
      auto mid = arith::ShRUIOp::create(b, loc, arith::AddIOp::create(b, loc, lo, hi), cst(1));
      auto bytes = arith::AddIOp::create(b, loc, cst(offsetof(Bindings, attrs) + offsetof(Attr, name)),
                                       arith::MulIOp::create(b, loc, mid, cst(sizeof(Attr))));
      auto key = LLVM::LoadOp::create(b, loc, i32, offset(bindings, bytes));
      branch(cmp(arith::CmpIPredicate::eq, key, cst(n.symbol, 32)), destinations[c.yes], step);
      b.setInsertionPointToEnd(step);
      auto less = cmp(arith::CmpIPredicate::ult, key, cst(n.symbol, 32));
      auto nextLo = arith::SelectOp::create(b, loc, less, arith::AddIOp::create(b, loc, mid, cst(1)), lo);
      auto nextHi = arith::SelectOp::create(b, loc, less, hi, mid);
      cf::BranchOp::create(b, loc, loop, ValueRange{nextLo, nextHi});
    }
  }
  // Every terminal is currently dispatch-reachable. If dispatch cases are
  // pruned, remove unused terminals too:
  // FuncToLLVM does not rewrite returns in unreachable blocks.
  for (unsigned d = 0; d < 3; ++d)
    if (destinations[d]->hasNoPredecessors()) destinations[d]->erase();
  // The count includes entry, terminal blocks, and every helper block, not
  // merely source DAG nodes; continuation specialization is bounded separately.
  return std::distance(fun.getBody().begin(), fun.getBody().end()) <= kMaxBlocks;
}

LazyJITPlan::RunResult LazyJITPlan::observe(EvalState &st, Frame *env, Value &arg) const {
  Value *args[]{&arg};
  return observe(st, env, args);
}
LazyJITPlan::RunResult LazyJITPlan::observe(EvalState &st, Frame *env, llvm::ArrayRef<Value *> args) const {
  RunResult result;
  if (!impl->acceptsArguments(args)) return result;
  std::array<Value *, kMaxLeaves> cells{};
  std::array<Frame *, kMaxNodes> envs{};
  std::array<unsigned, kMaxInlineDepth> stack{};
  std::array<uint8_t, kMaxNodes> active{};
  envs[0] = env;
  active[0] = true;
  unsigned depth = 0, dest = impl->root, resultLeaf = kNoArgument;
  for (unsigned steps = 0; steps < kMaxBlocks; ++steps) {
    if (dest == kFalseDest || dest == kTrueDest) {
      if (depth) return result;
      result.outcome = Outcome::Done;
      result.value = dest == kTrueDest;
      return result;
    }
    if (dest == kValueDest) {
      if (depth || !active[0]) return result;
      impl->finishValue(resultLeaf, cells.data(), result);
      return result;
    }
    if (dest == kDeoptDest) { result.outcome = Outcome::Deopt; return result; }
    if (dest < 3 || dest - 3 >= impl->continuations.size()) return result;
    const Continuation &c = impl->continuations[dest - 3];
    const PlanNode &n = impl->nodes[c.node];
    if (n.kind == Kind::StringCompare && c.action == Action::Atomic) {
      std::array<std::string_view, 2> strings;
      for (unsigned i = 0; i < 2; ++i) {
        const auto &operand = n.strings[i];
        if (operand.literal != kNoArgument) strings[i] = impl->literals[operand.literal].bytes;
        else {
          Value *cell = cells[operand.leaf];
          if (!cell || cell->isThunk()) { result.outcome = Outcome::Deopt; return result; }
          if (cell->type != VType::String) {
            ++result.stringGuardDeopts;
            result.outcome = Outcome::Deopt;
            return result;
          }
          strings[i] = cell->sv();
        }
      }
      ++result.stringComparisons;
      bool value = (strings[0] == strings[1]) != n.unequal;
      dest = value ? c.yes : c.no;
      continue;
    }
    if (c.action == Action::ReturnList) {
      if (n.recipe >= impl->listRecipes.size()) return result;
      const auto &recipe = impl->listRecipes[n.recipe];
      if (!recipe.allowed || !recipe.size || recipe.size > kMaxListElements) return result;
      for (unsigned i = 0; i < recipe.size; ++i) {
        unsigned id = recipe.elements[i];
        if (id >= impl->leaves.size() || impl->leaves[id].kind != LeafKind::Cell ||
            !active[impl->leaves[id].context]) return result;
        if (!impl->peek(st, envs.data(), active.data(), args, cells.data(), id, result)) {
          result.outcome = Outcome::Deopt;
          return result;
        }
      }
      resultLeaf = kListCodeBase + n.recipe;
      dest = c.yes;
      continue;
    }
    if (c.action == Action::ReturnEmpty) {
      resultLeaf = emptyCode(n.empty);
      dest = c.yes;
      continue;
    }
    if (c.action == Action::Leave) {
      if (!depth || stack[depth - 1] != n.context) return result;
      active[n.context] = false;
      --depth;
      dest = c.yes;
      continue;
    }
    unsigned demandLeaf = c.action == Action::StringDemand ? c.demandLeaf : n.leaf;
    const Leaf &leaf = impl->leaves[demandLeaf];
    if (!active[leaf.context]) return result;
    Value *cell = impl->peek(st, envs.data(), active.data(), args, cells.data(), demandLeaf, result);
    if (!cell && leaf.kind == LeafKind::Projection) { result.outcome = Outcome::Deopt; return result; }
    if (c.action == Action::Enter) {
      if (!cell || cell->type != VType::Lambda || cell->thunk.node != n.targetNode) {
        ++result.guardMisses;
        result.outcome = Outcome::Deopt;
        return result;
      }
      if (depth == kMaxInlineDepth || impl->contexts[n.context].parent != (depth ? stack[depth - 1] : 0))
        return result;
      if (uint64_t(st.callDepth) + depth >= st.settings.maxCallDepth) return result;
      envs[n.context] = cell->thunk.env;
      active[n.context] = true;
      for (unsigned l = 0; l < impl->leaves.size(); ++l)
        if (impl->leaves[l].context == n.context) cells[l] = nullptr;
      stack[depth++] = n.context;
      ++result.inlineCalls;
      result.saturatedInlineCalls += n.arity > 1;
      ++result.depthEntries;
      dest = c.yes;
      continue;
    }
    if (!cell || cell->isThunk()) {
      if (c.action == Action::ReturnValue || c.action == Action::StringDemand) result.outcome = Outcome::Deopt;
      return result;
    }
    if (c.action == Action::StringDemand) {
      dest = c.yes;
      continue;
    }
    if (c.action == Action::ReturnValue) {
      resultLeaf = n.leaf;
      dest = c.yes;
      continue;
    }
    bool value;
    if (n.kind == Kind::Leaf) {
      if (cell->type != VType::Bool) { result.outcome = Outcome::Deopt; return result; }
      value = cell->boolean;
    } else if (n.kind == Kind::Predicate) {
      value = n.function ? cell->isFunction() : cell->type == n.tag;
    } else if (n.kind == Kind::HasAttr) {
      value = cell->type == VType::Attrs && cell->attrs->get(n.symbol);
    } else return result;
    dest = value ? c.yes : c.no;
  }
  return result;
}

LazyJITPlan::RunResult LazyJITPlan::run(EvalState &st, Frame *env, Value &arg, Fn fn, bool observeOnly,
                                     const void *callPos) {
  Value *args[]{&arg};
  return run(st, env, args, fn, observeOnly, callPos);
}
LazyJITPlan::RunResult LazyJITPlan::run(EvalState &st, Frame *env, llvm::ArrayRef<Value *> args,
                                     Fn fn, bool observeOnly, const void *callPos) {
  RunResult result;
  if (!impl->acceptsArguments(args)) return result;
  Runtime runtime; // intentionally leave unused cells and inactive environments untouched
  for (unsigned i = 0; i < impl->leaves.size(); ++i)
    runtime.cells[i] = impl->leaves[i].argument != kNoArgument ? args[impl->leaves[i].argument] : nullptr;
  for (unsigned i = 0; i < impl->contexts.size(); ++i) runtime.active[i] = 0;
  runtime.envs[0] = env;
  runtime.active[0] = 1;
  const unsigned initialDepth = st.callDepth;
  runtime.initialDepth = initialDepth;
  runtime.maxDepth = st.settings.maxCallDepth;
  runtime.depth = 0;
  runtime.currentContext = 0;
  runtime.inlineCalls = 0;
  runtime.saturatedInlineCalls = 0;
  runtime.resultLeaf = kNoArgument;
  runtime.stringComparisons = 0;
  runtime.stringGuardDeopts = 0;
  auto restoreDepth = llvm::make_scope_exit([&] { st.callDepth = initialDepth; });
  uint32_t pc = 0;
  while (result.resumes < kMaxResumes) {
    ++result.resumes;
    uint64_t status = fn(pc, &runtime);
    result.inlineCalls = runtime.inlineCalls;
    result.saturatedInlineCalls = runtime.saturatedInlineCalls;
    result.depthEntries = runtime.inlineCalls;
    result.stringComparisons = runtime.stringComparisons;
    result.stringGuardDeopts = runtime.stringGuardDeopts;
    if (runtime.depth > kMaxInlineDepth || runtime.currentContext >= impl->contexts.size() ||
        !runtime.active[runtime.currentContext] ||
        runtime.depth != impl->contexts[runtime.currentContext].depth) return result;
    if (status == kFalse || status == kTrue) {
      if (runtime.depth || runtime.currentContext) return result;
      result.outcome = Outcome::Done;
      result.value = status == kTrue;
      return result;
    }
    if (status == kValue) {
      if (runtime.depth || runtime.currentContext) return result;
      impl->finishValue(runtime.resultLeaf, runtime.cells, result);
      return result;
    }
    if (status == kDeopt) { result.outcome = Outcome::Deopt; return result; }
    unsigned action = status & 7;
    if ((action != kDemand && action != kDepthOverflow && action != kGuardMiss) ||
        (status >> 3) < 3 || (status >> 3) >= impl->continuations.size() + 3) return result;
    unsigned continuation = status >> 3;
    const Continuation &c = impl->continuations[continuation - 3];
    const PlanNode &n = impl->nodes[c.node];
    if (action == kDepthOverflow) {
      if (c.action != Action::Enter || observeOnly) return result;
      throw StackOverflowError("stack overflow; max-call-depth exceeded", nd::posOfOp(n.op));
    }
    if (action == kGuardMiss) {
      if (c.action != Action::Enter) return result;
      ++result.guardMisses;
      result.outcome = Outcome::Deopt;
      return result;
    }
    if (c.action == Action::ReturnList) {
      if (n.recipe >= impl->listRecipes.size()) return result;
      const auto &recipe = impl->listRecipes[n.recipe];
      if (!recipe.allowed || !recipe.size || recipe.size > kMaxListElements) return result;
      uint64_t logicalDepth = uint64_t(initialDepth) + runtime.depth;
      if (logicalDepth > runtime.maxDepth) return result;
      auto restoreHandleDepth = llvm::make_scope_exit([&] { st.callDepth = initialDepth; });
      st.callDepth = unsigned(logicalDepth);
      bool missing = false;
      for (unsigned i = 0; i < recipe.size; ++i) {
        unsigned id = recipe.elements[i];
        if (id >= impl->leaves.size()) return result;
        const Leaf &leaf = impl->leaves[id];
        if (leaf.kind != LeafKind::Cell || !runtime.active[leaf.context]) return result;
        Value *&cell = runtime.cells[id];
        if (cell) continue;
        missing = true;
        cell = leaf.argument != kNoArgument ? args[leaf.argument] : existing(st, runtime.envs[leaf.context], leaf.value);
        if (!cell && !observeOnly && leaf.argument == kNoArgument) {
          ++result.listHandleLookups;
          cell = st.lookup(runtime.envs[leaf.context], leaf.value);
        }
        if (!cell) { result.outcome = Outcome::Deopt; return result; }
      }
      if (!missing) return result; // a native request must have an unresolved handle
      pc = continuation + 1;
      continue;
    }
    if (c.action == Action::Leave || c.action == Action::ReturnEmpty ||
        (n.kind == Kind::StringCompare && c.action != Action::StringDemand)) return result;
    unsigned demandLeaf = c.action == Action::StringDemand ? c.demandLeaf : n.leaf;
    const Leaf &leaf = impl->leaves[demandLeaf];
    if (!runtime.active[leaf.context]) return result;
    Value *&cell = runtime.cells[demandLeaf];
    if (leaf.kind == LeafKind::Projection) {
      if (c.action == Action::Enter) return result; // projected callees are not admitted
      if (observeOnly) {
        cell = impl->peek(st, runtime.envs, runtime.active, args, runtime.cells, demandLeaf, result);
        if (!cell || cell->isThunk()) { result.outcome = Outcome::Deopt; return result; }
      } else {
        uint64_t logicalDepth = uint64_t(initialDepth) + runtime.depth;
        if (logicalDepth > runtime.maxDepth) return result;
        auto restoreForceDepth = llvm::make_scope_exit([&] { st.callDepth = initialDepth; });
        st.callDepth = unsigned(logicalDepth);
        ++result.projectionRequests;
        result.pathProjectionRequests += leaf.pathSize > 1;
        auto persistentCell = [&](unsigned index) -> Value * {
          const Leaf &component = impl->leaves[index];
          if (component.kind != LeafKind::Cell || !runtime.active[component.context]) return nullptr;
          Value *&value = runtime.cells[index];
          if (!value) value = component.argument != kNoArgument ? args[component.argument]
              : st.lookup(runtime.envs[component.context], component.value);
          return value;
        };
        auto forcing = [&](Value &value) {
          if (value.isThunk()) { ++result.demands; ++result.projectionForces; }
        };
        try {
          const PosPtr pos = nd::posOfOp(leaf.select);
          Symbol symbol = leaf.path[0];
          if (leaf.key != kNoArgument) {
            Value *key = persistentCell(leaf.key);
            if (!key) return result;
            forcing(*key);
            symbol = st.symbolOfString(st.forceStringNoCtx(*key, pos, "while evaluating an attribute name"));
          }
          Value *current = persistentCell(leaf.base);
          if (!current) return result;
          for (unsigned i = 0; i < leaf.pathSize; ++i) {
            forcing(*current);
            Value *base = current;
            current = st.selectField(*base, i ? leaf.path[i] : symbol, pos);
            countProjectionLookup(*base->attrs, result);
          }
          forcing(*current);
          st.forceValue(*current, pos);
          cell = current;
        } catch (EvalError &error) {
          // The original primitive forces the Select thunk inside callPrimOp.
          // Preserve that wrapper around key, base, missing-field and field
          // errors even though this virtual leaf needs no temporary thunk cell.
          if (n.kind == Kind::Predicate) {
            const PrimOp *prim = st.primFor(n.op);
            if (prim->name != "throw" && prim->name != "abort" && prim->name != "addErrorContext")
              error.addTrace(nd::posOfOp(n.op), "while calling the '" + prim->name + "' builtin");
          }
          throw;
        }
      }
      pc = continuation + 1;
      continue;
    }
    bool unresolved = !cell;
    if (unresolved) {
      // Native Enter installs each current closure environment before activating
      // it. This active check must dominate every read of an uninitialized env.
      cell = leaf.argument != kNoArgument ? args[leaf.argument] : (observeOnly || c.action == Action::Enter)
          ? existing(st, runtime.envs[leaf.context], leaf.value)
          : st.lookup(runtime.envs[leaf.context], leaf.value);
    }
    if (c.action == Action::Enter) {
      // Reached callee resolution is a peek, never a speculative force.
      if (!cell || cell->type != VType::Lambda || cell->thunk.node != n.targetNode) {
        ++result.guardMisses;
        result.outcome = Outcome::Deopt;
        return result;
      }
      if (!unresolved) return result;
    } else if (!cell) {
      if (c.action == Action::ReturnValue || c.action == Action::StringDemand) result.outcome = Outcome::Deopt;
      return result;
    } else if (cell->isThunk()) {
      if (observeOnly) {
        if (c.action == Action::ReturnValue || c.action == Action::StringDemand) result.outcome = Outcome::Deopt;
        return result;
      }
      uint64_t logicalDepth = uint64_t(initialDepth) + runtime.depth;
      if (logicalDepth > runtime.maxDepth) return result;
      // The demand can invoke arbitrary evaluator code, including this same
      // compiled entry. Its starting depth includes every active inlined call,
      // even when the demanded formal was substituted with a root argument.
      auto restoreForceDepth = llvm::make_scope_exit([&] { st.callDepth = initialDepth; });
      st.callDepth = unsigned(logicalDepth);
      ++result.demands;
      if (n.kind == Kind::Predicate) {
        Value *args[]{cell};
        Value ignored;
        st.callPrimOp(*st.primFor(n.op), args, ignored, nd::posOfOp(n.op));
      } else st.forceValue(*cell, c.consumer ? nd::posOfOp(c.consumer) : callPos);
    } else if (!unresolved) return result;
    pc = continuation + 1;
  }
  return result;
}
} // namespace nixev
