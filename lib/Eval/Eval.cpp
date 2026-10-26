//===- Eval.cpp - Lazy evaluator over the nix dialect ---------------------===//

#include "Nix/Eval.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Pass/PassRegistry.h"
#include "mlir/Transforms/Passes.h"
#include <mutex>
#include "llvm/Support/Format.h"
#include "Nix/MLIRGen.h"

#include "mlir/IR/Builders.h"
#include "mlir/Parser/Parser.h"
#include "mlir/Pass/PassManager.h"
#include "llvm/ADT/TypeSwitch.h"
#include "llvm/Support/SourceMgr.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <iostream>
#include <pthread.h>
#include <sstream>
#include <sys/stat.h>
#include <unistd.h>

using namespace mlir;
namespace nd = mlir::nix;

namespace nixev {

//===----------------------------------------------------------------------===//
// Bindings
//===----------------------------------------------------------------------===//

const Attr *Bindings::get(Symbol s) const {
  size_t lo = 0, hi = size_;
  while (lo < hi) {
    size_t mid = (lo + hi) / 2;
    if (attrs[mid].name < s) lo = mid + 1;
    else hi = mid;
  }
  if (lo < size_ && attrs[lo].name == s) return &attrs[lo];
  return nullptr;
}

std::vector<const Attr *> Bindings::lexicographicOrder(const SymbolTable &st) const {
  std::vector<const Attr *> v;
  v.reserve(size_);
  for (auto &a : *this) v.push_back(&a);
  std::sort(v.begin(), v.end(), [&](const Attr *a, const Attr *b) { return st[a->name] < st[b->name]; });
  return v;
}

Bindings *EvalState::allocBindings(size_t n) {
  void *mem = alloc.Allocate(sizeof(Bindings) + n * sizeof(Attr), alignof(Bindings));
  auto *b = new (mem) Bindings();
  b->size_ = 0;
  return b;
}

Bindings *EvalState::BindingsBuilder::finish() {
  std::stable_sort(attrs.begin(), attrs.end(), [](const Attr &a, const Attr &b) { return a.name < b.name; });
  Bindings *b = st.allocBindings(attrs.size());
  size_t n = 0;
  for (size_t i = 0; i < attrs.size(); i++) {
    if (n && b->attrs[n - 1].name == attrs[i].name) continue; // first wins
    b->attrs[n++] = attrs[i];
  }
  b->size_ = n;
  return b;
}

Value **EvalState::allocList(size_t n) {
  if (!n) return nullptr;
  return static_cast<Value **>(alloc.Allocate(n * sizeof(Value *), alignof(Value *)));
}

const char *EvalState::copyString(std::string_view s) {
  char *p = static_cast<char *>(alloc.Allocate(s.size() + 1, 1));
  memcpy(p, s.data(), s.size());
  p[s.size()] = 0;
  return p;
}

const StringContext *EvalState::makeContext(const NixStringContext &c) {
  if (c.empty()) return nullptr;
  void *mem = alloc.Allocate(sizeof(StringContext) + c.size() * sizeof(const char *), alignof(StringContext));
  auto *ctx = new (mem) StringContext();
  ctx->n = c.size();
  size_t i = 0;
  for (auto &e : c) ctx->elems[i++] = copyString(e);
  return ctx;
}

void EvalState::mkString(Value &v, std::string_view s, const NixStringContext &ctx) {
  v.type = VType::String;
  v.str.s = copyString(s);
  v.str.len = s.size();
  v.str.ctx = makeContext(ctx);
}

void EvalState::mkPath(Value &v, std::string_view p) {
  v.type = VType::Path;
  v.path.s = copyString(p);
  v.path.len = p.size();
}

void EvalState::mkList(Value &v, size_t n) {
  v.type = VType::List;
  v.list.size = n;
  v.list.elems = allocList(n);
}

void EvalState::copyContext(const Value &v, NixStringContext &ctx) {
  if (v.type == VType::String && v.str.ctx)
    for (size_t i = 0; i < v.str.ctx->n; i++) ctx.insert(v.str.ctx->elems[i]);
}

//===----------------------------------------------------------------------===//
// Construction
//===----------------------------------------------------------------------===//

EvalState::EvalState(EvalSettings st, std::shared_ptr<nixstore::Store> store)
    : settings(std::move(st)), store(std::move(store)) {
  statsEnabled = getenv("MLNIX_STATS") != nullptr;
  settings.mapSources = !getenv("MLNIX_NOMMAP"); // ablation switch: read and copy every file, as before
  inPlaceEnabled = !getenv("MLNIX_NOINPLACE"); // ablation switch: every operand gets a thunk, as before
  // The evaluator is single-threaded.  With threading enabled every attribute
  // and location is uniqued through sharded, locked, thread-cached tables --
  // a quarter of the run time (measured) for no benefit.
  ctx.disableMultithreading();
  nd::loadNixDialects(ctx);
  registerEvalModels(ctx);
  ctx.getLoadedDialect<nd::NixDialect>()->primFolder = [this](llvm::StringRef key,
                                                              llvm::ArrayRef<mlir::Attribute> args) {
    return foldPrimOp(key, args);
  };
  ctx.allowUnregisteredDialects(false);
  module = ModuleOp::create(UnknownLoc::get(&ctx));
#define SYM(field, str) s.field = symbols.create(str)
  SYM(outPath, "outPath"); SYM(drvPath, "drvPath"); SYM(type, "type"); SYM(name, "name");
  SYM(value, "value"); SYM(functor, "__functor"); SYM(toString, "__toString"); SYM(file, "file");
  SYM(line, "line"); SYM(column, "column"); SYM(outputs, "outputs"); SYM(outputName, "outputName");
  SYM(all, "all"); SYM(drvAttrs, "drvAttrs"); SYM(success, "success"); SYM(key, "key");
  SYM(operator_, "operator"); SYM(startSet, "startSet"); SYM(data, "data"); SYM(path, "path");
  SYM(prefix, "prefix"); SYM(body, "body"); SYM(ignoreNulls, "__ignoreNulls");
  SYM(structuredAttrs, "__structuredAttrs"); SYM(args, "args"); SYM(builder, "builder");
  SYM(system, "system"); SYM(outputHash, "outputHash"); SYM(outputHashAlgo, "outputHashAlgo");
  SYM(outputHashMode, "outputHashMode"); SYM(contentAddressed, "__contentAddressed");
  SYM(impure, "__impure"); SYM(allowedReferences, "allowedReferences");
  SYM(allowedRequisites, "allowedRequisites"); SYM(disallowedReferences, "disallowedReferences");
  SYM(disallowedRequisites, "disallowedRequisites"); SYM(maxSize, "maxSize");
  SYM(maxClosureSize, "maxClosureSize"); SYM(json, "__json"); SYM(right, "right"); SYM(wrong, "wrong");
  SYM(attrsSym, "attrs"); SYM(sha256, "sha256"); SYM(url, "url"); SYM(rev, "rev"); SYM(ref, "ref");
  SYM(submodules, "submodules"); SYM(shallow, "shallow"); SYM(allRefs, "allRefs");
  SYM(narHash, "narHash"); SYM(recursive, "recursive"); SYM(filter, "filter");
  SYM(lastModified, "lastModified"); SYM(revCount, "revCount"); SYM(shortRev, "shortRev");
  SYM(lastModifiedDate, "lastModifiedDate"); SYM(outPathSym, "outPath");
  SYM(exportIgnore, "exportIgnore"); SYM(executable, "executable"); SYM(unpack, "unpack");
#undef SYM
  mkBool(vTrue, true);
  mkBool(vFalse, false);
  mkNull(vNull);
  mkAttrs(vEmptyAttrs, allocBindings(0));
  mkList(vEmptyList, 0);
  printTrace = [](const std::string &m) { std::cerr << m << std::endl; };
  createBaseEnv();
}

void EvalState::printStats() {
  // How many ops of real programs live where: per tier of the dialect hierarchy
  // (scope > continent > dialect), read from the IRDL declaration.
  auto *core = ctx.getLoadedDialect<nd::NixDialect>();
  llvm::StringMap<size_t> perDialect, perScope, perContinent;
  size_t total = 0;
  for (auto &e : opStats) {
    llvm::StringRef dialect = e.getKey().split('.').first;
    perDialect[dialect] += e.getValue();
    auto it = core->continents.find(dialect);
    perScope[it == core->continents.end() ? "core" : llvm::StringRef(it->second.scope)] += e.getValue();
    perContinent[it == core->continents.end() ? "core" : llvm::StringRef(it->second.continent)] += e.getValue();
    total += e.getValue();
  }
  auto sorted = [](llvm::StringMap<size_t> &m) {
    std::vector<std::pair<std::string, size_t>> v;
    for (auto &e : m) v.push_back({e.getKey().str(), e.getValue()});
    std::sort(v.begin(), v.end(), [](auto &a, auto &b) { return a.second > b.second; });
    return v;
  };
  auto section = [&](const char *title, llvm::StringMap<size_t> &m) {
    llvm::errs() << "== " << title << " (" << m.size() << ")\n";
    for (auto &[n, c] : sorted(m)) llvm::errs() << "  " << llvm::format("%-9s", n.c_str()) << llvm::format("%9zu", c) << "\n";
  };
  llvm::errs() << "== mlnix ops lowered: " << total << "\n";
  llvm::errs() << "== operands evaluated in place: " << nInPlace << ", thunks created by lookup(): " << nThunks << "\n";
  section("scopes", perScope);
  section("continents", perContinent);
  section("dialects", perDialect);
  std::vector<std::pair<std::string, size_t>> o;
  for (auto &e : opStats) o.push_back({e.getKey().str(), e.getValue()});
  std::sort(o.begin(), o.end(), [](auto &a, auto &b) { return a.second > b.second; });
  llvm::errs() << "== top ops\n";
  for (size_t i = 0; i < o.size() && i < 14; i++)
    llvm::errs() << "  " << llvm::format("%-22s", o[i].first.c_str()) << llvm::format("%9zu", o[i].second) << "\n";
}

EvalState::~EvalState() {
  if (statsEnabled) printStats();
  for (auto *a : arenas) delete a;
}

bool EvalState::isBaseName(llvm::StringRef name) const { return baseEnv.count(name); }

Value *EvalState::baseEnvValue(llvm::StringRef name) {
  auto it = baseEnv.find(name);
  return it == baseEnv.end() ? nullptr : it->second;
}

void EvalState::addPrimOp(const std::string &name, unsigned arity,
                          std::function<void(EvalState &, Value **, Value &, PosPtr)> fn) {
  auto *p = new PrimOp{name.rfind("__", 0) == 0 ? name.substr(2) : name, arity, std::move(fn)};
  Value *v = allocValue();
  if (arity == 0) {
    // A constant computed by calling fn immediately.
    p->fn(*this, nullptr, *v, nullptr);
  } else {
    v->type = VType::PrimOp;
    v->primOp = p;
  }
  addConstant(name, v);
}

void EvalState::addConstant(const std::string &name, Value *v) {
  baseEnv[name] = v;
  std::string bare = name.rfind("__", 0) == 0 ? name.substr(2) : name;
  (void)bare;
}

//===----------------------------------------------------------------------===//
// Positions & errors
//===----------------------------------------------------------------------===//

static std::optional<FileLineColLoc> toFileLoc(PosPtr pos) {
  if (!pos) return std::nullopt;
  Location loc = Location::getFromOpaquePointer(pos);
  if (auto f = dyn_cast<FileLineColLoc>(loc)) return f;
  return std::nullopt;
}

std::string EvalState::showPos(PosPtr pos) const {
  auto f = toFileLoc(pos);
  if (!f) return "«none»:0";
  return f->getFilename().str() + ":" + std::to_string(f->getLine()) + ":" + std::to_string(f->getColumn());
}

void EvalState::throwError(const std::string &msg, PosPtr pos) { throw EvalError(msg, pos); }

void EvalState::warn(const std::string &msg) {
  std::cerr << "warning: " << msg << std::endl;
  if (settings.abortOnWarn) throw EvalError(msg);
}

const char *EvalState::showType(const Value &v) {
  switch (v.type) {
  case VType::Int: return "an integer";
  case VType::Bool: return "a Boolean";
  case VType::String: return v.str.ctx ? "a string with context" : "a string";
  case VType::Path: return "a path";
  case VType::Null: return "null";
  case VType::Attrs: return "a set";
  case VType::List: return "a list";
  case VType::Lambda: return "a function";
  case VType::PrimOp: return "a built-in function";
  case VType::PrimOpApp: return "a partially applied built-in function";
  case VType::Float: return "a float";
  case VType::Thunk: case VType::App: return "a thunk";
  case VType::Blackhole: return "a thunk";
  }
  return "?";
}

const char *EvalState::typeOf(const Value &v) {
  switch (v.type) {
  case VType::Int: return "int";
  case VType::Bool: return "bool";
  case VType::String: return "string";
  case VType::Path: return "path";
  case VType::Null: return "null";
  case VType::Attrs: return "set";
  case VType::List: return "list";
  case VType::Lambda: case VType::PrimOp: case VType::PrimOpApp: return "lambda";
  case VType::Float: return "float";
  default: return "thunk";
  }
}

void EvalState::throwTypeError(const char *expected, Value &v, PosPtr pos, std::string_view ctx) {
  TypeError e(std::string("expected ") + expected + " but found " + showType(v) + ": " +
                  printValueForTrace(v),
              pos);
  if (!ctx.empty()) e.addTrace(pos, std::string(ctx));
  throw e;
}

//===----------------------------------------------------------------------===//
// Regions & frames
//===----------------------------------------------------------------------===//

void EvalState::indexRegion(Region &r) {
  auto *ri = new RegionInfo{&r, 0, {}};
  Block &blk = r.front();
  unsigned slot = 0;
  auto *core = ctx.getLoadedDialect<nd::NixDialect>();
  for (BlockArgument a : blk.getArguments()) slotMap[a.getAsOpaquePointer()] = {ri, slot++, false};
  for (Operation &op : blk) {
    if (auto ret = dyn_cast<nd::ReturnOp>(op)) {
      ri->result = ret.getValue();
      continue;
    }
    for (mlir::Value res : op.getResults()) slotMap[res.getAsOpaquePointer()] = {ri, slot++, inPlaceEnabled && core->evaluatesInPlace(res)};
    for (Region &nested : op.getRegions())
      if (!nested.empty()) indexRegion(nested);
  }
  ri->numSlots = slot;
  regionInfos[&r] = ri;
}

RegionInfo *EvalState::regionInfo(Region *r) {
  auto it = regionInfos.find(r);
  if (it != regionInfos.end()) return it->second;
  indexRegion(*r);
  return regionInfos[r];
}

Frame *EvalState::newFrame(RegionInfo *ri, Frame *up) {
  size_t sz = sizeof(Frame) + ri->numSlots * sizeof(Value *);
  auto *f = static_cast<Frame *>(alloc.Allocate(sz, alignof(Frame)));
  f->up = up;
  f->info = ri;
  memset(f->slots, 0, ri->numSlots * sizeof(Value *));
  return f;
}

Value *EvalState::lookup(Frame *f, mlir::Value v) {
  auto it = slotMap.find(v.getAsOpaquePointer());
  if (it == slotMap.end()) throw EvalError("internal error: unindexed SSA value");
  RegionInfo *ri = it->second.ri;
  unsigned idx = it->second.idx;
  while (f && f->info != ri) f = f->up;
  if (!f) throw EvalError("internal error: SSA value used outside its scope");
  Value *&slot = f->slots[idx];
  if (slot) return slot;
  Operation *op = v.getDefiningOp();
  if (!op) throw EvalError("internal error: unbound block argument");
  if (isa<nd::IntOp, nd::FloatOp, nd::StringOp, nd::PathOp, nd::BoolOp, nd::NullOp>(op)) {
    auto c = constCache.find(op);
    if (c != constCache.end()) return slot = c->second;
    Value *cv = allocValue();
    if (auto i = dyn_cast<nd::IntOp>(op)) mkInt(*cv, i.getValue());
    else if (auto fl = dyn_cast<nd::FloatOp>(op)) mkFloat(*cv, fl.getValue().convertToDouble());
    else if (auto s = dyn_cast<nd::StringOp>(op)) mkString(*cv, s.getValue());
    else if (auto bl = dyn_cast<nd::BoolOp>(op)) mkBool(*cv, bl.getValue());
    else if (isa<nd::NullOp>(op)) mkNull(*cv);
    else mkPath(*cv, cast<nd::PathOp>(op).getValue());
    constCache[op] = cv;
    return slot = cv;
  }
  if (auto b = dyn_cast<nd::BuiltinOp>(op)) {
    Value *bv = baseEnvValue(b.getName());
    if (!bv) throw EvalError("undefined variable '" + b.getName().str() + "'", op->getLoc().getAsOpaquePointer());
    return slot = bv;
  }
  Value *nv = allocValue();
  if (statsEnabled) nThunks++;
  if (isa<nd::LambdaOp>(op)) {
    nv->type = VType::Lambda;
  } else {
    nv->type = VType::Thunk;
  }
  nv->thunk.op = op;
  nv->thunk.env = f;
  return slot = nv;
}

/// Evaluates the defining op of an in-place value straight into `dest`.  Lambdas are
/// closures, built where lookup() would build them.
void EvalState::evalDefinition(mlir::Operation *def, Frame *f, Value &dest) {
  if (isa<nd::LambdaOp>(def)) {
    dest.type = VType::Lambda;
    dest.thunk.op = def;
    dest.thunk.env = f;
  } else {
    evalOp(def, f, dest);
  }
}

Value &EvalState::operand(Frame *f, mlir::Value v, Value &tmp) {
  auto it = slotMap.find(v.getAsOpaquePointer());
  if (it != slotMap.end() && it->second.inPlace && f && f->info == it->second.ri) {
    if (statsEnabled) nInPlace++;
    evalDefinition(v.getDefiningOp(), f, tmp);
    return tmp;
  }
  return *lookup(f, v);
}

void EvalState::evalTail(Frame *f, mlir::Value v, Value &out, PosPtr pos) {
  auto it = slotMap.find(v.getAsOpaquePointer());
  if (it != slotMap.end() && it->second.inPlace && f && f->info == it->second.ri) {
    if (statsEnabled) nInPlace++;
    evalDefinition(v.getDefiningOp(), f, out);
    return;
  }
  Value *p = lookup(f, v);
  forceValue(*p, pos);
  out = *p;
}

//===----------------------------------------------------------------------===//
// Forcing
//===----------------------------------------------------------------------===//

namespace {
struct DepthGuard {
  unsigned &d;
  DepthGuard(unsigned &d) : d(d) { ++d; }
  ~DepthGuard() { --d; }
};
} // namespace

void EvalState::forceValue(Value &v, PosPtr pos) {
  if (v.type == VType::Thunk) {
    Operation *op = v.thunk.op;
    Frame *env = v.thunk.env;
    v.type = VType::Blackhole;
    try {
      evalOp(op, env, v);
    } catch (...) {
      v.type = VType::Thunk;
      v.thunk.op = op;
      v.thunk.env = env;
      throw;
    }
  } else if (v.type == VType::App) {
    Value *l = v.app.left, *r = v.app.right;
    v.type = VType::Blackhole;
    try {
      callFunction(*l, 1, &r, v, pos);
    } catch (...) {
      v.type = VType::App;
      v.app.left = l;
      v.app.right = r;
      throw;
    }
  } else if (v.type == VType::Blackhole) {
    throw InfiniteRecursionError("infinite recursion encountered", pos);
  }
}

void EvalState::forceValueDeep(Value &v) {
  std::set<const void *> seen;
  std::function<void(Value &)> rec = [&](Value &v) {
    if (callDepth >= settings.maxCallDepth) throw StackOverflowError("stack overflow; max-call-depth exceeded");
    DepthGuard g(callDepth);
    forceValue(v);
    if (!seen.insert(&v).second) return;
    if (v.type == VType::Attrs) {
      for (auto &a : *v.attrs) {
        try {
          rec(*a.value);
        } catch (EvalError &e) {
          e.addTrace(a.pos, "while evaluating the attribute '" + symbols[a.name].str() + "'");
          throw;
        }
      }
    } else if (v.type == VType::List) {
      for (size_t i = 0; i < v.list.size; i++) rec(*v.list.elems[i]);
    }
  };
  rec(v);
}

int64_t EvalState::forceInt(Value &v, PosPtr pos, std::string_view c) {
  forceValue(v, pos);
  if (v.type != VType::Int) throwTypeError("an integer", v, pos, c);
  return v.integer;
}

double EvalState::forceFloat(Value &v, PosPtr pos, std::string_view c) {
  forceValue(v, pos);
  if (v.type == VType::Int) return (double)v.integer;
  if (v.type != VType::Float) throwTypeError("a float", v, pos, c);
  return v.fpoint;
}

bool EvalState::forceBool(Value &v, PosPtr pos, std::string_view c) {
  forceValue(v, pos);
  if (v.type != VType::Bool) throwTypeError("a Boolean", v, pos, c);
  return v.boolean;
}

void EvalState::forceAttrs(Value &v, PosPtr pos, std::string_view c) {
  forceValue(v, pos);
  if (v.type != VType::Attrs) throwTypeError("a set", v, pos, c);
}

void EvalState::forceList(Value &v, PosPtr pos, std::string_view c) {
  forceValue(v, pos);
  if (v.type != VType::List) throwTypeError("a list", v, pos, c);
}

void EvalState::forceFunction(Value &v, PosPtr pos, std::string_view c) {
  forceValue(v, pos);
  if (!v.isFunction() && !(v.type == VType::Attrs && v.attrs->get(s.functor)))
    throwTypeError("a function", v, pos, c);
}

std::string_view EvalState::forceString(Value &v, PosPtr pos, std::string_view c) {
  forceValue(v, pos);
  if (v.type != VType::String) throwTypeError("a string", v, pos, c);
  return v.sv();
}

std::string_view EvalState::forceString(Value &v, NixStringContext &ctx, PosPtr pos, std::string_view c) {
  auto s = forceString(v, pos, c);
  copyContext(v, ctx);
  return s;
}

std::string_view EvalState::forceStringNoCtx(Value &v, PosPtr pos, std::string_view c) {
  auto s = forceString(v, pos, c);
  if (v.str.ctx) {
    std::string first = v.str.ctx->elems[0];
    std::string what = first[0] == '=' ? first.substr(1) : first[0] == '!' ? first.substr(first.find('!', 1) + 1) : first;
    throw EvalError("the string '" + std::string(s) + "' is not allowed to refer to a store path (such as '" +
                        nixstore::baseNameOf(what) + "')",
                    pos);
  }
  return s;
}

//===----------------------------------------------------------------------===//
// Function calls
//===----------------------------------------------------------------------===//

void EvalState::callLambda(Value &fun, Value *arg, Value &out, PosPtr pos) {
  auto lam = cast<nd::LambdaOp>(fun.thunk.op);
  RegionInfo *ri = regionInfo(&lam.getBody());
  Frame *f = newFrame(ri, fun.thunk.env);
  f->slots[0] = arg;
  auto fnName = [&]() -> std::string {
    if (auto n = lam.getName()) return "function '" + n->str() + "'";
    return "function 'anonymous lambda'";
  };
  if (auto formals = lam.getFormals()) {
    try {
      forceAttrs(*arg, pos, "while evaluating the value passed for the lambda argument");
    } catch (EvalError &e) {
      e.addTrace(lam->getLoc().getAsOpaquePointer(), "while calling " + fnName());
      throw;
    }
    auto defs = *lam.getFormalDefaults();
    size_t nFound = 0;
    for (size_t i = 0; i < formals->size(); i++) {
      auto name = cast<StringAttr>((*formals)[i]).getValue();
      if (arg->attrs->get(symbols.create(name))) nFound++;
      else if (!defs[i])
        throw EvalError(fnName() + " called without required argument '" + name.str() + "'", pos)
            .addTrace(lam->getLoc().getAsOpaquePointer(), "from call site");
    }
    if (!lam.getEllipsis() && nFound != arg->attrs->size()) {
      for (auto &a : *arg->attrs) {
        bool known = false;
        for (Attribute fa : *formals)
          if (cast<StringAttr>(fa).getValue() == symbols[a.name]) { known = true; break; }
        if (!known)
          throw EvalError(fnName() + " called with unexpected argument '" + symbols[a.name].str() + "'", pos)
              .addTrace(lam->getLoc().getAsOpaquePointer(), "from call site");
      }
    }
  }
  if (callDepth >= settings.maxCallDepth)
    throw StackOverflowError("stack overflow; max-call-depth exceeded", pos);
  DepthGuard g(callDepth);
  evalTail(f, ri->result, out, pos);
}

void EvalState::callPrimOp(const PrimOp &op, Value **args, Value &out, PosPtr pos) {
  try {
    op.fn(*this, args, out, pos);
  } catch (EvalError &e) {
    if (op.name != "throw" && op.name != "abort" && op.name != "addErrorContext")
      e.addTrace(pos, "while calling the '" + op.name + "' builtin");
    throw;
  }
}

const PrimOp *EvalState::primOpByKey(llvm::StringRef key) {
  Value *v = baseEnvValue(key);
  return v && v->type == VType::PrimOp ? v->primOp : nullptr;
}

mlir::Attribute EvalState::foldPrimOp(llvm::StringRef key, llvm::ArrayRef<mlir::Attribute> args) {
  const PrimOp *op = primOpByKey(key);
  if (!op || op->arity != args.size()) return {};
  llvm::SmallVector<Value *, 4> vals;
  for (mlir::Attribute a : args) {
    Value *v = allocValue();
    if (auto b = mlir::dyn_cast<mlir::BoolAttr>(a)) mkBool(*v, b.getValue());
    else if (auto i = mlir::dyn_cast<mlir::IntegerAttr>(a)) mkInt(*v, i.getInt());
    else if (auto f = mlir::dyn_cast<mlir::FloatAttr>(a)) mkFloat(*v, f.getValueAsDouble());
    else if (auto s = mlir::dyn_cast<mlir::StringAttr>(a)) mkString(*v, s.getValue());
    else if (mlir::isa<mlir::UnitAttr>(a)) mkNull(*v);
    else return {};
    vals.push_back(v);
  }
  Value out;
  try {
    op->fn(*this, vals.data(), out, nullptr);
    forceValue(out, nullptr);
  } catch (std::exception &) {
    return {}; // stays a run-time error, with its original position and trace
  }
  mlir::Builder b(&ctx);
  switch (out.type) {
  case VType::Int: return b.getI64IntegerAttr(out.integer);
  case VType::Float: return b.getF64FloatAttr(out.fpoint);
  case VType::Bool: return b.getBoolAttr(out.boolean);
  case VType::Null: return b.getUnitAttr();
  case VType::String:
    if (out.str.ctx && out.str.ctx->n) return {}; // keep contexts out of constants
    return b.getStringAttr(out.sv());
  default: return {};
  }
}

void EvalState::callFunction(Value &fun, size_t nargs, Value **args, Value &out, PosPtr pos) {
  Value *cur = &fun;
  size_t i = 0;
  Value tmp;
  if (nargs == 0) {
    forceValue(fun, pos);
    out = fun;
    return;
  }
  while (true) {
    forceValue(*cur, pos);
    Value *res = (i + 1 == nargs) ? &out : allocValue();
    if (cur->type == VType::Lambda) {
      callLambda(*cur, args[i], *res, pos);
      i++;
    } else if (cur->type == VType::PrimOp || cur->type == VType::PrimOpApp) {
      // Collect already-applied arguments.
      std::vector<Value *> applied;
      Value *p = cur;
      while (p->type == VType::PrimOpApp) {
        applied.push_back(p->app.right);
        p = p->app.left;
      }
      std::reverse(applied.begin(), applied.end());
      const PrimOp *op = p->primOp;
      size_t need = op->arity - applied.size();
      size_t avail = nargs - i;
      if (avail < need) {
        // Partial application.
        Value *acc = cur;
        for (; i < nargs; i++) {
          Value *app = (i + 1 == nargs) ? &out : allocValue();
          Value *l = acc;
          if (app == &out && l == &out) { l = allocValue(); *l = out; }
          app->type = VType::PrimOpApp;
          app->app.left = l;
          app->app.right = args[i];
          acc = app;
        }
        return;
      }
      std::vector<Value *> all = applied;
      for (size_t k = 0; k < need; k++) all.push_back(args[i + k]);
      i += need;
      res = (i == nargs) ? &out : allocValue();
      callPrimOp(*op, all.data(), *res, pos);
    } else if (cur->type == VType::Attrs && cur->attrs->get(s.functor)) {
      const Attr *f = cur->attrs->get(s.functor);
      Value *self = cur;
      if (self == &out) { self = allocValue(); *self = *cur; }
      Value *fargs[2] = {self, args[i]};
      try {
        callFunction(*f->value, 2, fargs, *res, pos);
      } catch (EvalError &e) {
        e.addTrace(pos, "while calling a functor (an attribute set with a '__functor' attribute)");
        throw;
      }
      i++;
    } else {
      throw EvalError(std::string("attempt to call something which is not a function but ") +
                          showType(*cur) + ": " + printValueForTrace(*cur),
                      pos);
    }
    if (i >= nargs) return;
    cur = res;
  }
}

void EvalState::autoCallFunction(const std::map<std::string, Value *> &autoArgs, Value &fun, Value &out) {
  forceValue(fun);
  if (fun.type == VType::Attrs && fun.attrs->get(s.functor)) {
    Value *v = allocValue();
    callFunction(*fun.attrs->get(s.functor)->value, fun, *v, nullptr);
    autoCallFunction(autoArgs, *v, out);
    return;
  }
  if (fun.type != VType::Lambda) {
    out = fun;
    return;
  }
  auto lam = cast<nd::LambdaOp>(fun.thunk.op);
  if (!lam.getFormals()) {
    out = fun;
    return;
  }
  BindingsBuilder bb(*this);
  auto defs = *lam.getFormalDefaults();
  for (size_t i = 0; i < lam.getFormals()->size(); i++) {
    std::string name = cast<StringAttr>((*lam.getFormals())[i]).getValue().str();
    auto it = autoArgs.find(name);
    if (it != autoArgs.end()) bb.insert(name, it->second);
    else if (!defs[i])
      throw EvalError("cannot evaluate a function that has an argument without a value ('" + name +
                          "')\nNix attempted to evaluate a function as a top level expression; in this case it must have its arguments supplied either by default values, or passed explicitly with '--arg' or '--argstr'. See https://nix.dev/manual/nix/stable/language/syntax.html#functions.",
                      lam->getLoc().getAsOpaquePointer());
  }
  if (lam.getEllipsis())
    for (auto &[k, v] : autoArgs) bb.insert(k, v);
  Value *arg = allocValue();
  mkAttrs(*arg, bb.finish());
  callFunction(fun, *arg, out, nullptr);
}

//===----------------------------------------------------------------------===//
// Op semantics
//===----------------------------------------------------------------------===//

void EvalState::evalAttrs(nd::AttrsOp op, Frame *env, Value &out) {
  auto names = op.getNames();
  auto values = op.getValues();
  auto dynNames = op.getDynNames();
  std::optional<ArrayAttr> positions = op.getPositions();
  BindingsBuilder bb(*this);
  for (size_t i = 0; i < names.size(); i++) {
    PosPtr p = positions && i < positions->size()
                   ? cast<LocationAttr>((*positions)[i]).getAsOpaquePointer() : nullptr;
    bb.insert(symbolOf(cast<StringAttr>(names[i])), lookup(env, values[i]), p);
  }
  if (dynNames.empty()) {
    mkAttrs(out, bb.finish());
    return;
  }
  // Dynamic attributes are inserted one by one with duplicate checks.
  std::map<Symbol, PosPtr> seen;
  for (size_t i = 0; i < names.size(); i++)
    seen[symbolOf(cast<StringAttr>(names[i]))] = nullptr;
  auto dynValues = op.getDynValues();
  for (size_t j = 0; j < dynNames.size(); j++) {
    Value *nv = lookup(env, dynNames[j]);
    PosPtr p = dynNames[j].getLoc().getAsOpaquePointer();
    forceValue(*nv, p);
    if (nv->type == VType::Null) continue;
    auto name = forceStringNoCtx(*nv, p, "while evaluating the name of a dynamic attribute");
    Symbol sym = symbols.create(name);
    if (seen.count(sym))
      throw EvalError("dynamic attribute '" + std::string(name) + "' already defined at " +
                          showPos(seen[sym] ? seen[sym] : op->getLoc().getAsOpaquePointer()),
                      p);
    seen[sym] = p;
    bb.insert(sym, lookup(env, dynValues[j]), p);
  }
  mkAttrs(out, bb.finish());
}

void EvalState::evalConcatStrings(nd::ConcatStringsOp op, Frame *env, Value &out) {
  auto parts = op.getParts();
  bool forceString = op.getForceString();
  NixStringContext context;
  std::string str;
  int64_t n = 0;
  double nf = 0;
  bool first = !forceString;
  VType firstType = VType::String;
  for (mlir::Value pv : parts) {
    PosPtr ppos = pv.getLoc().getAsOpaquePointer();
    Value *v = lookup(env, pv);
    forceValue(*v, ppos);
    if (first) firstType = v->type;
    if (firstType == VType::Int) {
      if (v->type == VType::Int) {
        if (__builtin_add_overflow(n, v->integer, &n))
          throw EvalError("integer overflow in adding " + std::to_string(n) + " + " + std::to_string(v->integer), ppos);
      } else if (v->type == VType::Float) {
        firstType = VType::Float;
        nf = (double)n;
        nf += v->fpoint;
      } else {
        throw EvalError(std::string("cannot add ") + showType(*v) + " to an integer", ppos);
      }
    } else if (firstType == VType::Float) {
      if (v->type == VType::Int) nf += (double)v->integer;
      else if (v->type == VType::Float) nf += v->fpoint;
      else throw EvalError(std::string("cannot add ") + showType(*v) + " to a float", ppos);
    } else {
      str += coerceToString(*v, context, false, firstType == VType::String, ppos,
                            "while evaluating a path segment", !first);
    }
    first = false;
  }
  PosPtr pos = op->getLoc().getAsOpaquePointer();
  if (firstType == VType::Int) mkInt(out, n);
  else if (firstType == VType::Float) mkFloat(out, nf);
  else if (firstType == VType::Path) {
    if (!context.empty())
      throw EvalError("a string that refers to a store path cannot be appended to a path", pos);
    mkPath(out, nixfe::canonPath(str));
  } else {
    mkString(out, str, context);
  }
}

Symbol EvalState::pathSymbol(mlir::Attribute comp, mlir::OperandRange dyn, unsigned &nextDyn, Frame *env,
                             PosPtr pos) {
  if (auto lit = mlir::dyn_cast<mlir::StringAttr>(comp)) return symbolOf(lit);
  return symbols.create(forceStringNoCtx(*lookup(env, dyn[nextDyn++]), pos, "while evaluating an attribute name"));
}

void EvalState::evalOp(Operation *op, Frame *env, Value &out) {
  PosPtr pos = op->getLoc().getAsOpaquePointer();
  auto copyFrom = [&](Value *v) {
    forceValue(*v, pos);
    out = *v;
  };
  llvm::TypeSwitch<Operation *>(op)
      .Case<nd::ListOp>([&](nd::ListOp l) {
        auto elems = l.getElements();
        mkList(out, elems.size());
        for (size_t i = 0; i < elems.size(); i++) out.list.elems[i] = lookup(env, elems[i]);
      })
      .Case<nd::AttrsOp>([&](nd::AttrsOp a) { evalAttrs(a, env, out); })
      .Case<nd::SelectOp>([&](nd::SelectOp sel) {
        mlir::OperandRange dyn = sel.getDynKeys();
        Value tb;
        Value *cur = dyn.empty() ? &operand(env, sel.getBase(), tb) : lookup(env, sel.getBase());
        mlir::Value def = sel.getDefaultValue();
        unsigned nextDyn = 0;
        for (mlir::Attribute comp : sel.getPath()) {
          Symbol sym = pathSymbol(comp, dyn, nextDyn, env, pos);
          forceValue(*cur, pos);
          if (def) {
            if (cur->type != VType::Attrs) return copyFrom(lookup(env, def));
          } else if (cur->type != VType::Attrs) {
            throwTypeError("a set", *cur, pos, "while selecting an attribute");
          }
          const Attr *a = cur->attrs->get(sym);
          if (!a) {
            if (def) return copyFrom(lookup(env, def));
            throw EvalError("attribute '" + std::string(symbols[sym].str()) + "' missing", pos);
          }
          cur = a->value;
        }
        copyFrom(cur);
      })
      .Case<nd::HasAttrOp>([&](nd::HasAttrOp h) {
        mlir::OperandRange dyn = h.getDynKeys();
        Value tb;
        Value *cur = dyn.empty() ? &operand(env, h.getBase(), tb) : lookup(env, h.getBase());
        unsigned nextDyn = 0;
        for (mlir::Attribute comp : h.getPath()) {
          forceValue(*cur, pos);
          Symbol sym = pathSymbol(comp, dyn, nextDyn, env, pos);
          if (cur->type != VType::Attrs) return mkBool(out, false);
          const Attr *a = cur->attrs->get(sym);
          if (!a) return mkBool(out, false);
          cur = a->value;
        }
        mkBool(out, true);
      })
      .Case<nd::ApplyOp>([&](nd::ApplyOp ap) {
        Value *f = lookup(env, ap.getCallee());
        auto as = ap.getArgs();
        llvm::SmallVector<Value *, 4> args;
        for (mlir::Value a : as) args.push_back(lookup(env, a));
        callFunction(*f, args.size(), args.data(), out, pos);
      })
      .Case<nd::IfOp>([&](nd::IfOp i) {
        Value tc;
        bool c = forceBool(operand(env, i.getCond(), tc), pos, "while evaluating a branch condition");
        evalTail(env, c ? i.getThenValue() : i.getElseValue(), out, pos);
      })
      .Case<nd::AssertOp>([&](nd::AssertOp a) {
        Value tc;
        bool c = forceBool(operand(env, a.getCond(), tc), pos, "in the condition of the assert statement");
        if (!c) {
          std::string txt = a.getText() ? a.getText()->str() : "?";
          throw AssertionError("assertion '" + txt + "' failed", pos);
        }
        evalTail(env, a.getBody(), out, pos);
      })
      .Case<nd::NotOp>([&](nd::NotOp n) {
        Value t;
        mkBool(out, !forceBool(operand(env, n.getOperand(), t), pos, "in the argument of the not operator"));
      })
      .Case<nd::AndOp>([&](nd::AndOp a) {
        Value t1, t2;
        if (!forceBool(operand(env, a.getLhs(), t1), pos, "in the left operand of the AND (&&) operator"))
          return mkBool(out, false);
        mkBool(out, forceBool(operand(env, a.getRhs(), t2), pos, "in the right operand of the AND (&&) operator"));
      })
      .Case<nd::OrOp>([&](nd::OrOp o) {
        Value t1, t2;
        if (forceBool(operand(env, o.getLhs(), t1), pos, "in the left operand of the OR (||) operator"))
          return mkBool(out, true);
        mkBool(out, forceBool(operand(env, o.getRhs(), t2), pos, "in the right operand of the OR (||) operator"));
      })
      .Case<nd::ImplOp>([&](nd::ImplOp o) {
        Value t1, t2;
        if (!forceBool(operand(env, o.getLhs(), t1), pos, "in the left operand of the IMPL (->) operator"))
          return mkBool(out, true);
        mkBool(out, forceBool(operand(env, o.getRhs(), t2), pos, "in the right operand of the IMPL (->) operator"));
      })
      .Case<nd::EqOp>([&](nd::EqOp e) {
        Value ta, tb;
        Value &ra = operand(env, e.getLhs(), ta);
        forceValue(ra, pos);
        Value &rb = operand(env, e.getRhs(), tb);
        forceValue(rb, pos);
        Value a = ra, b = rb;
        mkBool(out, eqValues(a, b, pos));
      })
      .Case<nd::NeqOp>([&](nd::NeqOp e) {
        Value ta, tb;
        Value &ra = operand(env, e.getLhs(), ta);
        forceValue(ra, pos);
        Value &rb = operand(env, e.getRhs(), tb);
        forceValue(rb, pos);
        Value a = ra, b = rb;
        mkBool(out, !eqValues(a, b, pos));
      })
      .Case<nd::UpdateOp>([&](nd::UpdateOp u) {
        Value tl, tr;
        Value *l = &operand(env, u.getLhs(), tl);
        forceAttrs(*l, pos, "in the left operand of the update (//) operator");
        Value *r = &operand(env, u.getRhs(), tr);
        forceAttrs(*r, pos, "in the right operand of the update (//) operator");
        if (l->attrs->empty()) { out = *r; return; }
        if (r->attrs->empty()) { out = *l; return; }
        Bindings *b = allocBindings(l->attrs->size() + r->attrs->size());
        size_t i = 0, j = 0, n = 0;
        while (i < l->attrs->size() && j < r->attrs->size()) {
          const Attr &x = l->attrs->attrs[i], &y = r->attrs->attrs[j];
          if (x.name == y.name) { b->attrs[n++] = y; i++; j++; }
          else if (x.name < y.name) { b->attrs[n++] = x; i++; }
          else { b->attrs[n++] = y; j++; }
        }
        while (i < l->attrs->size()) b->attrs[n++] = l->attrs->attrs[i++];
        while (j < r->attrs->size()) b->attrs[n++] = r->attrs->attrs[j++];
        b->size_ = n;
        mkAttrs(out, b);
      })
      .Case<nd::ConcatListsOp>([&](nd::ConcatListsOp c) {
        Value tl, tr;
        Value *l = &operand(env, c.getLhs(), tl);
        forceList(*l, pos, "in the left operand of the list concatenation operator");
        Value *r = &operand(env, c.getRhs(), tr);
        forceList(*r, pos, "in the right operand of the list concatenation operator");
        if (l->list.size == 0) { out = *r; return; }
        if (r->list.size == 0) { out = *l; return; }
        size_t n1 = l->list.size, n2 = r->list.size;
        Value **e1 = l->list.elems, **e2 = r->list.elems;
        mkList(out, n1 + n2);
        memcpy(out.list.elems, e1, n1 * sizeof(Value *));
        memcpy(out.list.elems + n1, e2, n2 * sizeof(Value *));
      })
      .Case<nd::ConcatStringsOp>([&](nd::ConcatStringsOp c) { evalConcatStrings(c, env, out); })
      .Case<nd::WithVarOp>([&](nd::WithVarOp w) {
        Symbol sym = symbolOf(w.getNameAttr());
        for (mlir::Value sc : w.getScopes()) {
          Value *sv = lookup(env, sc);
          forceAttrs(*sv, sc.getLoc().getAsOpaquePointer(), "while evaluating the first subexpression of a with expression");
          if (const Attr *a = sv->attrs->get(sym)) return copyFrom(a->value);
        }
        throw EvalError("undefined variable '" + w.getName().str() + "'", pos);
      })
      .Case<nd::FormalOp>([&](nd::FormalOp f) {
        Value *arg = lookup(env, f.getArg());
        forceAttrs(*arg, pos);
        if (const Attr *a = arg->attrs->get(symbolOf(f.getNameAttr()))) return copyFrom(a->value);
        if (!f.getDefaultValue()) throw EvalError("missing formal argument '" + f.getName().str() + "'", pos);
        copyFrom(lookup(env, f.getDefaultValue()));
      })
      .Case<nd::IntOp>([&](nd::IntOp i) { mkInt(out, i.getValue()); })
      .Case<nd::BoolOp>([&](nd::BoolOp b) { mkBool(out, b.getValue()); })
      .Case<nd::NullOp>([&](nd::NullOp) { mkNull(out); })
      .Case<nd::FloatOp>([&](nd::FloatOp fl) { mkFloat(out, fl.getValue().convertToDouble()); })
      .Case<nd::StringOp>([&](nd::StringOp s) { mkString(out, s.getValue()); })
      .Case<nd::PathOp>([&](nd::PathOp p) { mkPath(out, p.getValue()); })
      .Case<nd::BuiltinOp>([&](nd::BuiltinOp b) { copyFrom(baseEnvValue(b.getName())); })
      .Default([&](Operation *o) {
        // Everything else (all primop ops of the continent dialects) runs
        // through the externally attached NixEvalOpInterface model.
        if (auto e = dyn_cast<nd::NixEvalOpInterface>(o)) return e.eval(*this, env, out);
        throw EvalError("internal error: cannot evaluate operation '" + o->getName().getStringRef().str() + "'", pos);
      });
}

//===----------------------------------------------------------------------===//
// Coercion
//===----------------------------------------------------------------------===//

bool EvalState::isDerivation(Value &v) {
  if (v.type != VType::Attrs) return false;
  const Attr *t = v.attrs->get(s.type);
  if (!t) return false;
  forceValue(*t->value);
  return t->value->type == VType::String && t->value->sv() == "derivation";
}

std::optional<std::string> EvalState::tryAttrsToString(Value &v, NixStringContext &ctx, bool coerceMore,
                                                       bool copyToStore) {
  const Attr *f = v.attrs->get(s.toString);
  if (!f) return std::nullopt;
  Value *r = allocValue();
  callFunction(*f->value, v, *r, nullptr);
  return coerceToString(*r, ctx, coerceMore, copyToStore, nullptr,
                        "while evaluating the result of the `__toString` attribute");
}

std::string EvalState::coerceToString(Value &v, NixStringContext &ctx, bool coerceMore, bool copyToStore,
                                      PosPtr pos, std::string_view errorCtx, bool canonicalizePath) {
  forceValue(v, pos);
  switch (v.type) {
  case VType::String:
    copyContext(v, ctx);
    return std::string(v.sv());
  case VType::Path: {
    std::string p(v.pathView());
    if (copyToStore) return copyPathToStore(ctx, p);
    return p;
  }
  case VType::Attrs: {
    if (auto s2 = tryAttrsToString(v, ctx, coerceMore, copyToStore)) return *s2;
    const Attr *o = v.attrs->get(s.outPath);
    if (!o) {
      TypeError e(std::string("cannot coerce ") + showType(v) + " to a string: " + printValueForTrace(v), pos);
      if (!errorCtx.empty()) e.addTrace(pos, std::string(errorCtx));
      throw e;
    }
    return coerceToString(*o->value, ctx, coerceMore, copyToStore, pos,
                          "while evaluating the `outPath` attribute", canonicalizePath);
  }
  default:
    break;
  }
  if (coerceMore) {
    if (v.type == VType::Bool) return v.boolean ? "1" : "";
    if (v.type == VType::Int) return std::to_string(v.integer);
    if (v.type == VType::Float) return std::to_string(v.fpoint);
    if (v.type == VType::Null) return "";
    if (v.type == VType::List) {
      std::string result;
      for (size_t n = 0; n < v.list.size; n++) {
        Value *e = v.list.elems[n];
        try {
          result += coerceToString(*e, ctx, coerceMore, copyToStore, pos, errorCtx);
        } catch (EvalError &err) {
          err.addTrace(pos, "while evaluating one element of the list");
          throw;
        }
        if (n < v.list.size - 1 && (e->type != VType::List || e->list.size != 0)) result += " ";
      }
      return result;
    }
  }
  TypeError e(std::string("cannot coerce ") + showType(v) + " to a string: " + printValueForTrace(v), pos);
  if (!errorCtx.empty()) e.addTrace(pos, std::string(errorCtx));
  throw e;
}

std::string EvalState::copyPathToStore(NixStringContext &ctx, const std::string &path) {
  std::string base = nixstore::baseNameOf(path);
  if (base.size() >= 4 && base.substr(base.size() - 4) == ".drv")
    throw EvalError("file names are not allowed to end in '.drv'");
  auto it = srcToStore.find(path);
  std::string dst;
  if (it != srcToStore.end()) {
    dst = it->second;
  } else {
    std::string real = path;
    if (nixstore::isInStore(store->storeDir(), path)) real = store->toReal(path);
    if (!nixstore::pathExists(real)) throw EvalError("path '" + path + "' does not exist");
    try {
      dst = store->addToStore(base, real);
    } catch (nixstore::Error &e) {
      throw EvalError(e.what());
    }
    srcToStore[path] = dst;
  }
  ctx.insert(dst);
  return dst;
}

std::string EvalState::coerceToPath(Value &v, NixStringContext &ctx, PosPtr pos, std::string_view errorCtx) {
  forceValue(v, pos);
  if (v.type == VType::Path) return std::string(v.pathView());
  std::string p = coerceToString(v, ctx, false, false, pos, errorCtx);
  if (p.empty() || p[0] != '/') {
    EvalError e("string '" + p + "' doesn't represent an absolute path", pos);
    if (!errorCtx.empty()) e.addTrace(pos, std::string(errorCtx));
    throw e;
  }
  return p;
}

std::string EvalState::coerceToStorePath(Value &v, NixStringContext &ctx, PosPtr pos, std::string_view errorCtx) {
  std::string p = coerceToString(v, ctx, false, false, pos, errorCtx);
  if (nixstore::isInStore(store->storeDir(), p)) return nixstore::toStorePath(store->storeDir(), p);
  EvalError e("path '" + p + "' is not in the Nix store", pos);
  if (!errorCtx.empty()) e.addTrace(pos, std::string(errorCtx));
  throw e;
}

//===----------------------------------------------------------------------===//
// Comparison
//===----------------------------------------------------------------------===//

bool EvalState::eqValues(Value &v1, Value &v2, PosPtr pos) {
  forceValue(v1, pos);
  forceValue(v2, pos);
  if (v1.type == VType::Int && v2.type == VType::Float) return (double)v1.integer == v2.fpoint;
  if (v1.type == VType::Float && v2.type == VType::Int) return v1.fpoint == (double)v2.integer;
  auto norm = [](VType t) { return t == VType::PrimOp || t == VType::PrimOpApp ? VType::Lambda : t; };
  if (norm(v1.type) != norm(v2.type)) return false;
  switch (v1.type) {
  case VType::Int: return v1.integer == v2.integer;
  case VType::Float: return v1.fpoint == v2.fpoint;
  case VType::Bool: return v1.boolean == v2.boolean;
  case VType::Null: return true;
  case VType::String: return v1.sv() == v2.sv();
  case VType::Path: return v1.pathView() == v2.pathView();
  case VType::List:
    if (v1.list.size != v2.list.size) return false;
    for (size_t i = 0; i < v1.list.size; i++) {
      Value *a = v1.list.elems[i], *b = v2.list.elems[i];
      if (a == b) continue; // value identity optimisation
      if (!eqValues(*a, *b, pos)) return false;
    }
    return true;
  case VType::Attrs: {
    if (v1.attrs == v2.attrs) return true;
    if (isDerivation(v1) && isDerivation(v2)) {
      const Attr *i = v1.attrs->get(s.outPath), *j = v2.attrs->get(s.outPath);
      if (i && j) {
        if (i->value == j->value) return true;
        return eqValues(*i->value, *j->value, pos);
      }
    }
    if (v1.attrs->size() != v2.attrs->size()) return false;
    for (size_t k = 0; k < v1.attrs->size(); k++) {
      const Attr &a = v1.attrs->attrs[k], &b = v2.attrs->attrs[k];
      if (a.name != b.name) return false;
      if (a.value == b.value) continue;
      if (!eqValues(*a.value, *b.value, pos)) return false;
    }
    return true;
  }
  case VType::Lambda: case VType::PrimOp: case VType::PrimOpApp:
    return false;
  default:
    throw EvalError(std::string("cannot compare ") + showType(v1) + " with " + showType(v2), pos);
  }
}

bool EvalState::lessThan(Value &v1, Value &v2, PosPtr pos) {
  forceValue(v1, pos);
  forceValue(v2, pos);
  if (v1.type == VType::Float && v2.type == VType::Int) return v1.fpoint < (double)v2.integer;
  if (v1.type == VType::Int && v2.type == VType::Float) return (double)v1.integer < v2.fpoint;
  if (v1.type != v2.type)
    throw EvalError(std::string("cannot compare ") + showType(v1) + " with " + showType(v2), pos);
  switch (v1.type) {
  case VType::Int: return v1.integer < v2.integer;
  case VType::Float: return v1.fpoint < v2.fpoint;
  case VType::String: return v1.sv() < v2.sv();
  case VType::Path: return v1.pathView() < v2.pathView();
  case VType::List:
    for (size_t i = 0;; i++) {
      if (i == v2.list.size) return false;
      if (i == v1.list.size) return true;
      if (!eqValues(*v1.list.elems[i], *v2.list.elems[i], pos))
        return lessThan(*v1.list.elems[i], *v2.list.elems[i], pos);
    }
  default:
    throw EvalError(std::string("cannot compare ") + showType(v1) + " with " + showType(v2) +
                        "; values of that type are incomparable",
                    pos);
  }
}

//===----------------------------------------------------------------------===//
// Printing
//===----------------------------------------------------------------------===//

static std::string fmtFloat(double d) {
  std::ostringstream os;
  os << d;
  return os.str();
}

void EvalState::printValue(std::ostream &str, Value &v, std::set<const void *> *seen, size_t depth) {
  if (depth > settings.maxCallDepth) throw StackOverflowError("stack overflow");
  switch (v.type) {
  case VType::Int: str << v.integer; break;
  case VType::Bool: str << (v.boolean ? "true" : "false"); break;
  case VType::String: nixfe::printLiteralString(str, v.sv()); break;
  case VType::Path: str << v.pathView(); break;
  case VType::Null: str << "null"; break;
  case VType::Attrs:
    if (seen && !v.attrs->empty() && !seen->insert(v.attrs).second) str << "«repeated»";
    else {
      str << "{ ";
      for (auto *a : v.attrs->lexicographicOrder(symbols)) {
        nixfe::printIdentifier(str, symbols[a->name]);
        str << " = ";
        printValue(str, *a->value, seen, depth + 1);
        str << "; ";
      }
      str << "}";
    }
    break;
  case VType::List:
    if (seen && v.list.size && !seen->insert(&v).second) str << "«repeated»";
    else {
      str << "[ ";
      for (size_t i = 0; i < v.list.size; i++) {
        printValue(str, *v.list.elems[i], seen, depth + 1);
        str << " ";
      }
      str << "]";
    }
    break;
  case VType::Thunk: case VType::App: str << "<CODE>"; break;
  case VType::Blackhole: str << "«potential infinite recursion»"; break;
  case VType::Lambda: str << "<LAMBDA>"; break;
  case VType::PrimOp: str << "<PRIMOP>"; break;
  case VType::PrimOpApp: str << "<PRIMOP-APP>"; break;
  case VType::Float: str << fmtFloat(v.fpoint); break;
  }
}

namespace {
struct TracePrinter {
  EvalState &st;
  std::ostream &out;
  bool force;
  size_t maxDepth = 10, maxAttrs = 10, maxList = 10, maxStr = 1024;
  size_t attrsPrinted = 0, listPrinted = 0;
  std::set<const void *> seen;

  void elided(size_t n, const char *one, const char *many) {
    out << "«" << n << " " << (n == 1 ? one : many) << " elided»";
  }
  void print(Value &v, size_t depth) {
    if (force) {
      try {
        st.forceValue(v);
      } catch (EvalError &e) {
        out << "«error: " << e.msg << "»";
        return;
      }
    }
    switch (v.type) {
    case VType::Int: out << v.integer; break;
    case VType::Float: out << fmtFloat(v.fpoint); break;
    case VType::Bool: out << (v.boolean ? "true" : "false"); break;
    case VType::Null: out << "null"; break;
    case VType::Path: out << v.pathView(); break;
    case VType::String: {
      auto s = v.sv();
      if (s.size() > maxStr) {
        nixfe::printLiteralString(out, s.substr(0, maxStr));
        out << " ";
        elided(s.size() - maxStr, "byte", "bytes");
      } else {
        nixfe::printLiteralString(out, s);
      }
      break;
    }
    case VType::Attrs: {
      if (!seen.insert(v.attrs).second) { out << "«repeated»"; break; }
      if (force && st.isDerivation(v)) {
        out << "«derivation";
        if (const Attr *d = v.attrs->get(st.s.drvPath)) {
          try {
            st.forceValue(*d->value);
            if (d->value->type == VType::String) out << " " << d->value->sv();
          } catch (EvalError &) {
          }
        }
        out << "»";
        break;
      }
      if (depth >= maxDepth) { out << "{ ... }"; break; }
      out << "{";
      std::vector<const Attr *> sorted;
      for (auto &a : *v.attrs) sorted.push_back(&a);
      std::sort(sorted.begin(), sorted.end(), [&](const Attr *a, const Attr *b) {
        auto an = st.symbols[a->name], bn = st.symbols[b->name];
        bool ai = an == "type" || an == "_type", bi = bn == "type" || bn == "_type";
        if (ai != bi) return ai;
        return an < bn;
      });
      size_t cur = 0;
      for (auto *a : sorted) {
        out << " ";
        if (attrsPrinted >= maxAttrs) {
          elided(sorted.size() - cur, "attribute", "attributes");
          break;
        }
        auto n = st.symbols[a->name];
        if (nixfe::isValidIdentifier(n)) out << n.str();
        else nixfe::printLiteralString(out, n);
        out << " = ";
        print(*a->value, depth + 1);
        out << ";";
        attrsPrinted++;
        cur++;
      }
      out << " }";
      break;
    }
    case VType::List: {
      if (v.list.size && !seen.insert(&v).second) { out << "«repeated»"; break; }
      if (depth >= maxDepth) { out << "[ ... ]"; break; }
      out << "[";
      size_t cur = 0;
      for (size_t i = 0; i < v.list.size; i++) {
        out << " ";
        if (listPrinted >= maxList) {
          elided(v.list.size - cur, "item", "items");
          break;
        }
        print(*v.list.elems[i], depth + 1);
        listPrinted++;
        cur++;
      }
      out << " ]";
      break;
    }
    case VType::Lambda: {
      auto lam = cast<nd::LambdaOp>(v.thunk.op);
      out << "«lambda";
      if (auto n = lam.getName()) out << " " << n->str();
      out << " @ " << st.showPos(lam->getLoc().getAsOpaquePointer()) << "»";
      break;
    }
    case VType::PrimOp: out << "«primop " << v.primOp->name << "»"; break;
    case VType::PrimOpApp: {
      Value *p = &v;
      while (p->type == VType::PrimOpApp) p = p->app.left;
      out << "«partially applied primop " << (p->type == VType::PrimOp ? p->primOp->name : "?") << "»";
      break;
    }
    case VType::Thunk: case VType::App: out << "«thunk»"; break;
    case VType::Blackhole: out << "«potential infinite recursion»"; break;
    }
  }
};
} // namespace

std::string EvalState::printValueForTrace(Value &v) {
  std::ostringstream os;
  TracePrinter p{*this, os, false};
  p.print(v, 0);
  return os.str();
}

//===----------------------------------------------------------------------===//
// Parsing, lowering, files
//===----------------------------------------------------------------------===//

nixfe::ParseOptions EvalState::parseOptions() {
  nixfe::ParseOptions po;
  po.pipeOperators = settings.pipeOperators;
  const char *home = getenv("HOME");
  po.home = home ? home : "/homeless-shelter";
  po.lintAbsolutePaths = settings.lintAbsolutePaths;
  po.lintShortPaths = settings.lintShortPaths;
  po.lintUrls = settings.lintUrls;
  po.onWarning = [](const nixfe::ParseError &e) { std::cerr << formatParseError(e, "warning") << std::endl; };
  return po;
}

nixfe::Expr *EvalState::parseSource(const std::string &text, const std::string &name, const std::string &path,
                                    const std::string &baseDir, std::shared_ptr<nixfe::Origin> *originOut) {
  auto *arena = new nixfe::ExprArena();
  arenas.push_back(arena);
  auto origin = std::make_shared<nixfe::Origin>();
  origin->name = name;
  origin->path = path;
  origin->baseDir = baseDir;
  origin->text = nixfe::Source::fromString(text);
  origins.push_back(origin);
  if (originOut) *originOut = origin;
  return nixfe::parse(*arena, origin, parseOptions());
}

nixfe::Expr *EvalState::parseString(nixfe::ExprArena &arena, const std::string &text, const std::string &baseDir,
                                    const std::string &originName) {
  auto origin = std::make_shared<nixfe::Origin>();
  origin->name = originName;
  origin->baseDir = baseDir;
  origin->text = nixfe::Source::fromString(text);
  origins.push_back(origin);
  nixfe::ParseOptions po = parseOptions();
  return nixfe::parse(arena, origin, po);
}

/// The optimization pipeline is data: MLIR pass-pipeline text (EvalSettings::pipeline,
/// overridden by MLNIX_PIPELINE), so any registered pass can be composed by name.
static std::unique_ptr<mlir::PassManager> makeOptimizer(mlir::MLIRContext &ctx, const EvalSettings &settings) {
  static std::once_flag once;
  std::call_once(once, [] {
    mlir::registerTransformsPasses();
    nd::registerNixPasses();
  });
  std::string text = settings.pipeline;
  if (const char *e = getenv("MLNIX_PIPELINE")) text = e;
  auto pm = std::make_unique<mlir::PassManager>(&ctx); // anchored on any op
  pm->enableVerifier(false);
  std::string err;
  llvm::raw_string_ostream os(err);
  if (mlir::failed(mlir::parsePassPipeline(text, *pm, os)))
    throw EvalError("invalid pass pipeline '" + text + "': " + err);
  return pm;
}

nd::ExprOp EvalState::lowerToMLIR(nixfe::Expr *e, std::shared_ptr<nixfe::Origin> origin,
                                  const std::vector<std::string> *scopeNames) {
  nixfe::GenOptions go;
  go.isBaseName = [this](llvm::StringRef n) { return isBaseName(n); };
  if (scopeNames) {
    go.scoped = true;
    go.scopeNames = *scopeNames;
  }
  std::string sym = "expr" + std::to_string(exprCounter++);
  nd::ExprOp op = nixfe::genExpr(*module, e, std::move(origin), sym, go);
  // The expression is IsolatedFromAbove and not yet referenced by any frame,
  // so it can be rewritten freely before evaluation starts.
  if (settings.optimize) {
    if (!optimizer) optimizer = makeOptimizer(ctx, settings);
    if (mlir::failed(optimizer->run(op))) throw EvalError("the optimization pipeline failed");
  }
  if (statsEnabled)
    op->walk([&](mlir::Operation *o) { ++opStats[o->getName().getStringRef()]; });
  return op;
}

Value *EvalState::evalExprOp(nd::ExprOp op) {
  RegionInfo *ri = regionInfo(&op.getBody());
  Frame *f = newFrame(ri, nullptr);
  return lookup(f, ri->result);
}

static const char *corepkgsFetchurl = R"NIX({
  system ? "", # obsolete
  url,
  hash ? "", # an SRI hash

  # Legacy hash specification
  md5 ? "",
  sha1 ? "",
  sha256 ? "",
  sha512 ? "",
  outputHash ?
    if hash != "" then
      hash
    else if sha512 != "" then
      sha512
    else if sha1 != "" then
      sha1
    else if md5 != "" then
      md5
    else
      sha256,
  outputHashAlgo ?
    if hash != "" then
      ""
    else if sha512 != "" then
      "sha512"
    else if sha1 != "" then
      "sha1"
    else if md5 != "" then
      "md5"
    else
      "sha256",

  executable ? false,
  unpack ? false,
  name ? baseNameOf (toString url),
  impure ? false,
}:

derivation (
  {
    builder = "builtin:fetchurl";

    # New-style output content requirements.
    outputHashMode = if unpack || executable then "recursive" else "flat";

    inherit
      name
      url
      executable
      unpack
      ;

    system = "builtin";

    # No need to double the amount of network traffic
    preferLocalBuild = true;

    # This attribute does nothing; it's here to avoid changing evaluation results.
    impureEnvVars = [
      "http_proxy"
      "https_proxy"
      "ftp_proxy"
      "all_proxy"
      "no_proxy"
    ];

    # To make "nix-prefetch-url" work.
    urls = [ url ];
  }
  // (if impure then { __impure = true; } else { inherit outputHashAlgo outputHash; })
)
)NIX";

static std::string readSource(const std::string &path) {
  if (path == "/__corepkgs__/fetchurl.nix") return corepkgsFetchurl;
  try {
    return nixstore::readFile(path);
  } catch (nixstore::Error &e) {
    throw EvalError(e.what());
  }
}

std::string EvalState::resolveExprPath(std::string path) {
  if (path.rfind("/__corepkgs__/", 0) == 0) return path;
  // Follow symlinks (to the final target), then use default.nix for dirs.
  for (int i = 0; i < 1024; i++) {
    struct stat st;
    if (lstat(path.c_str(), &st) != 0) throw EvalError("path '" + path + "' does not exist");
    if (!S_ISLNK(st.st_mode)) break;
    char buf[PATH_MAX + 1];
    ssize_t n = readlink(path.c_str(), buf, PATH_MAX);
    if (n < 0) break;
    std::string tgt(buf, n);
    if (tgt[0] != '/') tgt = nixstore::dirOf(path) + "/" + tgt;
    path = nixfe::canonPath(tgt);
  }
  struct stat st;
  if (stat(path.c_str(), &st) == 0 && S_ISDIR(st.st_mode)) path += "/default.nix";
  return path;
}

Value *EvalState::evalFile(const std::string &pathIn) {
  std::string path = pathIn;
  auto it = fileEvalCache.find(path);
  if (it != fileEvalCache.end()) return it->second;
  std::string real = realisePath(path, nullptr);
  std::string resolved = resolveExprPath(real);
  // Map back from the physical location when using a chroot store.
  std::string logical = resolved;
  if (!store->config().realRoot.empty() && resolved.rfind(store->config().realRoot, 0) == 0)
    logical = resolved.substr(store->config().realRoot.size());
  auto it2 = fileEvalCache.find(logical);
  if (it2 != fileEvalCache.end()) return fileEvalCache[path] = it2->second;

  Value *result;
  if (resolved.size() > 5 && resolved.substr(resolved.size() - 5) == ".mlir") {
    result = evalMLIRFile(resolved, "");
  } else {
    auto *arena = new nixfe::ExprArena();
    arenas.push_back(arena);
    auto origin = std::make_shared<nixfe::Origin>();
    origin->name = logical;
    origin->path = logical;
    origin->baseDir = nixstore::dirOf(logical);
    origin->text = settings.mapSources ? nixfe::Source::mapFile(resolved) : nullptr;
    if (!origin->text) origin->text = nixfe::Source::fromString(readSource(resolved));
    origins.push_back(origin);
    nixfe::ParseOptions po = parseOptions();
    nixfe::Expr *e = nixfe::parse(*arena, origin, po);
    nd::ExprOp op = lowerToMLIR(e, origin);
    result = evalExprOp(op);
  }
  fileEvalCache[path] = result;
  fileEvalCache[logical] = result;
  return result;
}

Value *EvalState::evalString(const std::string &text, const std::string &baseDir, const std::string &originName) {
  auto *arena = new nixfe::ExprArena();
  arenas.push_back(arena);
  auto origin = std::make_shared<nixfe::Origin>();
  origin->name = originName;
  origin->baseDir = baseDir;
  origin->text = nixfe::Source::fromString(text);
  origins.push_back(origin);
  nixfe::ParseOptions po = parseOptions();
  nixfe::Expr *e = nixfe::parse(*arena, origin, po);
  nd::ExprOp op = lowerToMLIR(e, origin);
  return evalExprOp(op);
}

Value *EvalState::evalMLIRFile(const std::string &path, const std::string &sym) {
  llvm::SourceMgr sm;
  OwningOpRef<ModuleOp> m = parseSourceFile<ModuleOp>(path, sm, ParserConfig(&ctx));
  if (!m) throw EvalError("failed to parse MLIR file '" + path + "'");
  nd::ExprOp found;
  // Move all ops into our module (renaming symbols to avoid clashes).
  llvm::SmallVector<nd::ExprOp> exprs;
  for (auto e : m->getOps<nd::ExprOp>()) exprs.push_back(e);
  for (auto e : exprs) {
    bool match = sym.empty() ? !found : e.getSymName() == sym;
    e->remove();
    e.setSymName("mlir" + std::to_string(exprCounter++));
    module->getBody()->push_back(e);
    if (match && !found) found = e;
  }
  if (!found) throw EvalError("no nix.expr found in '" + path + "'");
  return evalExprOp(found);
}

std::string EvalState::realisePath(const std::string &path, PosPtr pos) {
  // Store paths are realised through string context (realiseContext); here we
  // only map logical store paths to their physical location.
  const std::string &sd = store->storeDir();
  if (path == sd || path == sd + "/" || nixstore::isInStore(sd, path)) return store->toReal(path);
  return path;
}

void EvalState::realiseContext(const NixStringContext &ctx, PosPtr pos) {
  for (auto &c : ctx) {
    try {
      if (c[0] == '!') {
        auto p = c.find('!', 1);
        std::string drv = c.substr(p + 1);
        store->buildDerivation(drv);
      } else if (c[0] == '=') {
        store->buildDerivation(c.substr(1));
      } else if (!store->isValidPath(c)) {
        throw EvalError("path '" + c + "' is not valid", pos);
      }
    } catch (nixstore::Error &e) {
      throw EvalError(e.what(), pos);
    }
  }
}

std::string EvalState::findFile(Value &searchPath, std::string_view name, PosPtr pos) {
  forceList(searchPath, pos);
  for (size_t i = 0; i < searchPath.list.size; i++) {
    Value &e = *searchPath.list.elems[i];
    forceAttrs(e, pos);
    std::string prefix;
    if (const Attr *a = e.attrs->get(s.prefix)) prefix = std::string(forceStringNoCtx(*a->value, pos));
    const Attr *pa = e.attrs->get(s.path);
    if (!pa) throw EvalError("attribute 'path' missing", pos);
    NixStringContext ctx;
    std::string p = coerceToString(*pa->value, ctx, false, false, pos);
    realiseContext(ctx, pos);
    std::string rest;
    if (!prefix.empty()) {
      if (name.substr(0, prefix.size()) != prefix) continue;
      if (name.size() > prefix.size() && name[prefix.size()] != '/') continue;
      rest = std::string(name.substr(prefix.size()));
    } else {
      rest = "/" + std::string(name);
    }
    if (p.find("://") != std::string::npos) continue; // URL entries are not fetched implicitly
    std::string full = nixfe::canonPath(p + rest);
    if (nixstore::pathExists(realisePath(full, pos))) return full;
  }
  if (name.substr(0, 4) == "nix/") return "/__corepkgs__" + std::string(name.substr(3));
  if (settings.pureEval)
    throw ThrownError("cannot look up '<" + std::string(name) + ">' in pure evaluation mode (use '--impure' to override)", pos);
  throw ThrownError("file '" + std::string(name) +
                        "' was not found in the Nix search path (add it using $NIX_PATH or -I)",
                    pos);
}

//===----------------------------------------------------------------------===//
// Error formatting
//===----------------------------------------------------------------------===//

static std::string chomp(std::string s) {
  while (!s.empty() && (s.back() == ' ' || s.back() == '\t' || s.back() == '\n' || s.back() == '\r')) s.pop_back();
  return s;
}

static void appendCodeLines(std::string &out, std::string_view text, unsigned line, unsigned col,
                            unsigned indent = 7) {
  std::vector<std::string> lines;
  size_t start = 0;
  while (true) {
    size_t nl = text.find('\n', start);
    if (nl == std::string_view::npos) {
      lines.push_back(std::string(text.substr(start)));
      break;
    }
    lines.push_back(std::string(text.substr(start, nl - start)));
    start = nl + 1;
  }
  auto fmtLine = [&](unsigned n) {
    char buf[16];
    snprintf(buf, sizeof buf, "%5u", n);
    return chomp(std::string(indent + 1, ' ') + buf + "| " + lines[n - 1]);
  };
  if (line >= 2 && line - 1 <= lines.size()) out += "\n" + fmtLine(line - 1);
  if (line >= 1 && line <= lines.size()) {
    out += "\n" + fmtLine(line);
    if (col > 0) out += "\n" + std::string(indent, ' ') + "      |" + std::string(col, ' ') + "^";
  }
  if (line + 1 <= lines.size()) out += "\n" + fmtLine(line + 1);
}

static std::string sourceFor(EvalState *state, const std::string &file) {
  if (state)
    for (auto &o : state->origins)
      if (o->name == file && o->text) return std::string(o->text->view());
  if (!file.empty() && file[0] == '/' && nixstore::pathExists(file)) {
    try {
      return nixstore::readFile(file);
    } catch (...) {
    }
  }
  return "";
}

static void appendPos(std::string &out, EvalState *state, const std::string &file, unsigned line, unsigned col) {
  out += "\n       at " + file + ":" + std::to_string(line) + ":" + std::to_string(col) + ":";
  std::string text = sourceFor(state, file);
  if (!text.empty()) appendCodeLines(out, text, line, col);
}

std::string formatError(EvalState *state, const EvalError &e) {
  std::string out;
  // Traces are printed outermost first.
  if (state && state->settings.showTrace) {
    for (auto it = e.traces.rbegin(); it != e.traces.rend(); ++it) {
      out += "\n       … " + it->msg;
      if (auto f = toFileLoc(it->pos)) {
        appendPos(out, state, f->getFilename().str(), f->getLine(), f->getColumn());
        out += "\n";
      } else {
        out += "\n";
      }
    }
  }
  std::string msg = e.msg;
  // Indent continuation lines of the message.
  std::string ind;
  for (size_t i = 0; i < msg.size(); i++) {
    ind += msg[i];
    if (msg[i] == '\n') ind += "       ";
  }
  std::string res = out.empty() ? "error: " + ind : "error:" + out + "\n       error: " + ind;
  if (auto f = toFileLoc(e.pos)) appendPos(res, state, f->getFilename().str(), f->getLine(), f->getColumn());
  return res;
}

std::string formatParseError(const nixfe::ParseError &e, const char *kind) {
  unsigned indent = strlen(kind) + 2;
  std::string res = std::string(kind) + ": " + std::string(e.what());
  if (e.pos.valid() && e.origin) {
    res += "\n" + std::string(indent, ' ') + "at " + e.origin->name + ":" + std::to_string(e.pos.line) + ":" +
           std::to_string(e.pos.col) + ":";
    if (e.origin->text) appendCodeLines(res, e.origin->text->view(), e.pos.line, e.pos.col, indent);
  }
  return res;
}

int runWithLargeStack(std::function<int()> fn) {
  struct Ctx {
    std::function<int()> fn;
    int rc = 0;
    std::exception_ptr ex;
  } c{std::move(fn)};
  pthread_attr_t attr;
  pthread_attr_init(&attr);
  pthread_attr_setstacksize(&attr, size_t(1) << 30); // 1 GiB (virtual)
  pthread_t th;
  auto tramp = [](void *p) -> void * {
    auto *c = static_cast<Ctx *>(p);
    try {
      c->rc = c->fn();
    } catch (...) {
      c->ex = std::current_exception();
    }
    return nullptr;
  };
  if (pthread_create(&th, &attr, tramp, &c) != 0) return c.fn();
  pthread_join(th, nullptr);
  if (c.ex) std::rethrow_exception(c.ex);
  return c.rc;
}

} // namespace nixev
