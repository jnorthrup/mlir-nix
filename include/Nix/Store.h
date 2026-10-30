//===- Store.h - Nix store primitives -------------------------*- C++ -*-===//
//
// Hashes and their encodings, NAR serialisation, store path computation,
// ATerm derivations (with hashDerivationModulo), and a local store with a
// builder.  All algorithms follow upstream Nix bit-for-bit so that store paths
// and .drv files are identical to those produced by Nix itself.
//
//===----------------------------------------------------------------------===//
#ifndef NIX_STORE_H
#define NIX_STORE_H

#include <cstdint>

#include "Composite/Funnel.h"
#include "Composite/Mutable.h"
#include "Composite/Patricia.h"
#include "Composite/Vocab.h"
#include <functional>
#include <map>
#include <memory>
#include <optional>
#include <set>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace nixstore {

struct Error : std::runtime_error {
  using std::runtime_error::runtime_error;
};

//===----------------------------------------------------------------------===//
// Sorted rows: the store's sets and maps by string
//===----------------------------------------------------------------------===//

/// A set of strings kept as one series sorted in byte order (std::set's): no node per entry.  An insert in order is an append, which is how a
/// derivation's inputs arrive (from a sorted context) and how its text is parsed (sorted).
struct SortedSet {
  composite::MutableSeries<std::string> rows;
  SortedSet() = default;
  SortedSet(SortedSet &&) = default;
  SortedSet &operator=(SortedSet &&) = default;
  SortedSet(const SortedSet &o) { rows.reserve(o.rows.size()); for (const std::string &r : o.rows) rows.append(r); }
  SortedSet &operator=(const SortedSet &o) { if (this != &o) { SortedSet t(o); *this = std::move(t); } return *this; }
  template <class It> SortedSet(It b, It e) { insert(b, e); }
  /// The set of one string.
  static SortedSet of(std::string_view one) {
    SortedSet s;
    s.insert(one);
    return s;
  }
  const std::string *begin() const { return rows.begin(); }
  const std::string *end() const { return rows.end(); }
  size_t size() const { return rows.size(); }
  bool empty() const { return rows.empty(); }
  size_t lowerBound(std::string_view k) const {
    size_t lo = 0, hi = rows.size();
    while (lo < hi) { size_t mid = (lo + hi) / 2; if (std::string_view(rows[uint32_t(mid)]) < k) lo = mid + 1; else hi = mid; }
    return lo;
  }
  size_t count(std::string_view k) const { size_t i = lowerBound(k); return i < rows.size() && rows[uint32_t(i)] == k; }
  bool insert(std::string_view k) {
    if (rows.empty() || std::string_view(rows.back()) < k) { rows.append(std::string(k)); return true; }
    size_t i = lowerBound(k);
    if (i < rows.size() && rows[uint32_t(i)] == k) return false;
    rows.append(std::string(k));
    for (size_t j = rows.size() - 1; j > i; j--) rows[uint32_t(j)].swap(rows[uint32_t(j - 1)]);
    return true;
  }
  template <class It> void insert(It b, It e) { for (; b != e; ++b) insert(std::string_view(*b)); }
  bool contains(std::string_view k) const { return count(k) != 0; }
  /// Drops k; false when it was not there.  The rows after it move down one.
  bool erase(std::string_view k) {
    size_t i = lowerBound(k);
    if (i >= rows.size() || rows[uint32_t(i)] != k) return false;
    for (size_t j = i; j + 1 < rows.size(); j++) rows[uint32_t(j)].swap(rows[uint32_t(j + 1)]);
    rows.pop();
    return true;
  }
  bool operator==(const SortedSet &o) const { return rows == o.rows; }
};

/// A map from strings kept as rows sorted in byte order (std::map's) in one series: no node per entry.  Lookups bisect; an entry added in key
/// order is an append, which is how a derivation's environment arrives (its attributes are visited by name) and how its text is parsed.
template <class V> struct SortedMap {
  struct Row {
    std::string first;
    V second;
  };
  composite::MutableSeries<Row> rows;
  SortedMap() = default;
  SortedMap(SortedMap &&) = default;
  SortedMap &operator=(SortedMap &&) = default;
  SortedMap(const SortedMap &o) { rows.reserve(o.rows.size()); for (const Row &r : o.rows) rows.append(Row{r.first, r.second}); }
  SortedMap &operator=(const SortedMap &o) { if (this != &o) { SortedMap t(o); *this = std::move(t); } return *this; }
  static void swapRows(Row &x, Row &y) { Row t{composite::mv(x.first), composite::mv(x.second)}; x = composite::mv(y); y = composite::mv(t); }
  Row *begin() { return rows.begin(); }
  Row *end() { return rows.end(); }
  const Row *begin() const { return rows.begin(); }
  const Row *end() const { return rows.end(); }
  size_t size() const { return rows.size(); }
  bool empty() const { return rows.empty(); }
  size_t lowerBound(std::string_view k) const {
    size_t lo = 0, hi = rows.size();
    while (lo < hi) { size_t mid = (lo + hi) / 2; if (std::string_view(rows[uint32_t(mid)].first) < k) lo = mid + 1; else hi = mid; }
    return lo;
  }
  Row *find(std::string_view k) { size_t i = lowerBound(k); return i < rows.size() && rows[uint32_t(i)].first == k ? begin() + i : end(); }
  const Row *find(std::string_view k) const { size_t i = lowerBound(k); return i < rows.size() && rows[uint32_t(i)].first == k ? begin() + i : end(); }
  size_t count(std::string_view k) const { return find(k) != end(); }
  /// The row for k, made (with V()) where k sorts when there is none.
  Row *place(std::string_view k) {
    if (rows.empty() || std::string_view(rows.back().first) < k) { rows.append(Row{std::string(k), V()}); return end() - 1; }
    size_t i = lowerBound(k);
    if (i < rows.size() && rows[uint32_t(i)].first == k) return begin() + i;
    rows.append(Row{std::string(k), V()});
    for (size_t j = rows.size() - 1; j > i; j--) swapRows(rows[uint32_t(j)], rows[uint32_t(j - 1)]);
    return begin() + i;
  }
  V &operator[](std::string_view k) { return place(k)->second; }
  V &at(std::string_view k) { Row *r = find(k); if (r == end()) throw std::out_of_range("no entry '" + std::string(k) + "'"); return r->second; }
  const V &at(std::string_view k) const { const Row *r = find(k); if (r == end()) throw std::out_of_range("no entry '" + std::string(k) + "'"); return r->second; }
  /// An entry, moved in: at the end when it sorts there (the hint is the end), else where it sorts; an existing key keeps its value.
  Row *emplace_hint(Row *, std::string k, V v) {
    if (rows.empty() || rows.back().first < k) { rows.append(Row{std::move(k), std::move(v)}); return end() - 1; }
    size_t i = lowerBound(k);
    if (i < rows.size() && rows[uint32_t(i)].first == k) return begin() + i;
    rows.append(Row{std::move(k), std::move(v)});
    for (size_t j = rows.size() - 1; j > i; j--) swapRows(rows[uint32_t(j)], rows[uint32_t(j - 1)]);
    return begin() + i;
  }
};

//===----------------------------------------------------------------------===//
// Hashes
//===----------------------------------------------------------------------===//

enum class HashAlgo { MD5, SHA1, SHA256, SHA512 };
enum class HashFormat { Base16, Nix32, Base64, SRI };

size_t hashSize(HashAlgo a);
std::string algoName(HashAlgo a);
composite::Maybe<HashAlgo> parseHashAlgo(std::string_view s);

struct Hash {
  HashAlgo algo = HashAlgo::SHA256;
  uint8_t bytes[64] = {0};
  size_t size() const { return hashSize(algo); }
  std::string to_string(HashFormat f, bool includeAlgo) const;
  bool operator==(const Hash &o) const;
  bool operator<(const Hash &o) const;
};

struct HashSink {
  explicit HashSink(HashAlgo a);
  ~HashSink();
  HashSink(const HashSink &) = delete;
  void update(std::string_view data);
  Hash finish();
  uint64_t bytes() const { return total; }

  HashAlgo algo;
  alignas(16) unsigned char impl[320]; // the algorithm's context, made in place: a sink allocates nothing (Hash.cpp checks each fits)
  uint64_t total = 0;
};

Hash hashString(HashAlgo a, std::string_view s);
Hash hashFile(HashAlgo a, const std::string &path);
/// Parse a hash in any supported encoding; `algo` is required when the string
/// carries no algorithm prefix.  Throws Error.
Hash parseHash(std::string_view s, composite::Maybe<HashAlgo> algo);
/// Like parseHash, but the empty string yields an all-zero hash (with a warning
/// returned via `warning`).
Hash parseHashAllowEmpty(std::string_view s, composite::Maybe<HashAlgo> algo,
                         std::string *warning);
Hash compressHash(const Hash &h, size_t newSize);

std::string base16Encode(const uint8_t *d, size_t n);
std::string nix32Encode(const uint8_t *d, size_t n);
/// The same, appended to `out` where it is built: a path or a fingerprint is one string, not a string per piece.
void appendBase16(std::string &out, const uint8_t *d, size_t n);
void appendNix32(std::string &out, const uint8_t *d, size_t n);
std::string base64Encode(std::string_view s);
composite::Maybe<std::string> base64Decode(std::string_view s);
composite::Maybe<std::string> nix32Decode(std::string_view s, size_t size);
extern const char nix32Chars[33];

//===----------------------------------------------------------------------===//
// NAR
//===----------------------------------------------------------------------===//

/// Whether an entry of a tree is kept: called with the entry's path and, when the caller knows it, its type as builtins.path's filter is
/// told it ("regular", "directory", "symlink", "unknown"); empty when it does not.
using PathFilter = composite::Fn<bool(const std::string &path, std::string_view type)>;
using Sink = composite::Fn<void(std::string_view)>;

/// Serialise `path` as a Nix ARchive.  Throws Error on I/O failure.
void dumpPath(const std::string &path, const Sink &sink,
              const PathFilter &filter = nullptr);
/// Restore a NAR into `path` (which must not exist).
void restorePath(const std::string &path, std::string_view nar);
/// sha256 of the NAR serialisation, and the NAR size.
composite::Join<Hash, uint64_t> hashPath(const std::string &path,
                                   const PathFilter &filter = nullptr,
                                   HashAlgo algo = HashAlgo::SHA256);
/// Source trees hashed ahead.  The NAR hashes a recorded run made (nixprefetch::replayHashes) are made again by a helper thread at start-up,
/// reading the files as they are then, and hashPath takes a tree's answer instead of walking, reading and hashing it on the evaluator's
/// thread: a filtered tree's when the filter, asked about the entries the helper saw in the order a walk asks, keeps what the recorded
/// run's kept.  MLNIX_PRELOWER starts it, on prelowering's terms: a file is read once, early in the run.
void startPrehash();

//===----------------------------------------------------------------------===//
// Store paths
//===----------------------------------------------------------------------===//

enum class FileIngestionMethod { Flat, NixArchive, Text };

/// Throws Error with upstream's message on invalid names.
void checkName(std::string_view name);
std::string makeStorePath(const std::string &storeDir, std::string_view type,
                          const Hash &hash, std::string_view name);
std::string makeType(const std::string &storeDir, std::string type,
                     const SortedSet &refs, bool hasSelfRef);
std::string makeTextPath(const std::string &storeDir, std::string_view name,
                         const Hash &hash, const SortedSet &refs);
std::string makeFixedOutputPath(const std::string &storeDir, std::string_view name,
                                FileIngestionMethod method, const Hash &hash,
                                const SortedSet &refs = {});
std::string makeOutputPath(const std::string &storeDir, std::string_view output,
                           const Hash &drvHash, std::string_view drvName);
std::string outputPathName(std::string_view drvName, std::string_view output);
/// "/<nix32 sha256("nix-output:" + output)>"
std::string hashPlaceholder(std::string_view output);

bool isInStore(const std::string &storeDir, std::string_view path);
/// The store path prefix of a path inside the store (strips sub paths).
std::string toStorePath(const std::string &storeDir, std::string_view path);
bool isStorePath(const std::string &storeDir, std::string_view path);
std::string storePathName(std::string_view storePath);
std::string storePathHashPart(std::string_view storePath);

//===----------------------------------------------------------------------===//
// Derivations
//===----------------------------------------------------------------------===//

using DrvInputs = SortedMap<SortedSet>;

struct DerivationOutput {
  enum Kind { InputAddressed, CAFixed, CAFloating, Deferred, Impure } kind = Deferred;
  std::string path;                 // InputAddressed
  FileIngestionMethod method = FileIngestionMethod::NixArchive;
  HashAlgo hashAlgo = HashAlgo::SHA256;
  Hash hash;                        // CAFixed
  std::string methodAlgo() const;   // "r:sha256", "sha256", "text:sha256"
  std::string fixedPath(const std::string &storeDir, std::string_view drvName,
                        std::string_view output) const;
};

struct Derivation {
  std::string name;
  SortedMap<DerivationOutput> outputs;
  DrvInputs inputDrvs;
  SortedSet inputSrcs;
  std::string platform, builder;
  composite::MutableSeries<std::string> args;
  SortedMap<std::string> env;
  composite::Maybe<std::string> structuredAttrs; // JSON text (env "__json")

  Derivation() = default;
  Derivation(Derivation &&) = default;
  Derivation &operator=(Derivation &&) = default;
  /// A derivation is cached and read back by value, so a copy is part of its meaning; the arguments are copied cell by cell, spelled out.
  Derivation(const Derivation &o)
      : name(o.name), outputs(o.outputs), inputDrvs(o.inputDrvs), inputSrcs(o.inputSrcs), platform(o.platform), builder(o.builder),
        env(o.env), structuredAttrs(o.structuredAttrs) { for (const std::string &a : o.args) args.append(a); }
  Derivation &operator=(const Derivation &o) {
    if (this != &o) { Derivation t(o); *this = static_cast<Derivation &&>(t); }
    return *this;
  }

  bool isFixed() const;
  std::string unparse(bool maskOutputs, const DrvInputs *actualInputs = nullptr) const;
  /// SHA-256 of unparse(...), the text fed to the hash as it is made and never kept.
  Hash hashUnparsed(bool maskOutputs, const DrvInputs *actualInputs = nullptr) const;
};

Derivation parseDerivation(std::string_view text, std::string name);
std::string escapeATermString(std::string_view s);

/// JSON rendering of a derivation in the format of `nix derivation show`.
std::string derivationToJSON(const std::string &storeDir, const std::string &drvPath,
                             const Derivation &drv);

//===----------------------------------------------------------------------===//
// Local store
//===----------------------------------------------------------------------===//

struct PathInfo {
  std::string path;
  Hash narHash;
  uint64_t narSize = 0;
  SortedSet references;
  std::string deriver;
  std::string ca;
};

struct StoreSettings {
  std::string storeDir = "/nix/store";   // logical store directory
  std::string realRoot;                  // physical prefix ("" = none)
  std::string stateDir;                  // metadata
  bool readOnly = false;                 // compute paths only (dummy://)
  int maxJobs = 1;
  unsigned cores = 0;
  bool keepFailed = false;
  bool verbose = false;
  std::string system;
};

struct Store {
  explicit Store(StoreSettings s);
  ~Store(); // waits for the hasher's jobs, which read the derivation cache
  const std::string &storeDir() const { return settings.storeDir; }
  const StoreSettings &config() const { return settings; }
  bool readOnly() const { return settings.readOnly; }

  /// Physical location of a logical store path.
  std::string toReal(const std::string &logical) const;

  bool isValidPath(const std::string &path);
  composite::Maybe<PathInfo> queryPathInfo(const std::string &path);
  void registerValidPath(const PathInfo &info);
  SortedSet queryReferrers(const std::string &path);
  composite::MutableSeries<std::string> allValidPaths();

  /// Copy a file system object into the store (content-addressed).
  std::string addToStore(std::string name, const std::string &srcPath,
                         FileIngestionMethod method = FileIngestionMethod::NixArchive,
                         HashAlgo algo = HashAlgo::SHA256,
                         const PathFilter &filter = nullptr,
                         const SortedSet &refs = {},
                         composite::Maybe<Hash> expected = nullptr);
  std::string addTextToStore(std::string_view name, std::string_view text,
                             const SortedSet &refs);
  /// Path addToStore would produce without writing anything.
  std::string computeStorePathForPath(std::string name, const std::string &srcPath,
                                      FileIngestionMethod method, HashAlgo algo,
                                      const PathFilter &filter = nullptr);

  /// The derivation's path; the derivation moves into the cache (readDerivation hands it back by reference).
  std::string writeDerivation(Derivation &&drv);
  std::string computeDerivationPath(const Derivation &drv) const;
  /// The cached derivation, read from the store the first time: by reference, kept as long as the store.
  const Derivation &readDerivation(const std::string &drvPath);
  /// For derivations we instantiated in read-only mode.
  void cacheDerivation(const std::string &drvPath, const Derivation &drv);

  /// hashDerivationModulo; returns per-output hashes for fixed outputs (key
  /// "out") or a single drv hash (key "").  `inputsOut`, when given, receives the input derivations as the hash saw them (their own
  /// modulo hashes), for the derivation's next hash (hashLater).
  SortedMap<Hash> hashDerivationModulo(const Derivation &drv, bool maskOutputs, DrvInputs *inputsOut = nullptr);
  void fillInOutputPaths(Derivation &drv, DrvInputs *inputsOut = nullptr);
  /// The modulo hash of a derivation this evaluation wrote (its third hash, after the masked one that names its outputs and the one that
  /// names its path), made off the evaluator's thread from the cached derivation and the inputs its first hash saw, and collected when a
  /// dependent's hash asks for it.  The cached derivation is never written again (writeDerivation keeps the first of a path).
  void hashLater(const std::string &drvPath, DrvInputs &&inputs);
  struct LaterHashes;
  bool takeLater(const std::string &drvPath, SortedMap<Hash> &out);
  LaterHashes *later = nullptr; // the hasher thread's too: never freed, as the thread may still wait on it when the process ends

  SortedSet computeFSClosure(const SortedSet &paths,
                                         bool includeOutputs = false);

  /// Realise derivation outputs (building as necessary).  Returns the output
  /// paths by name.
  SortedMap<std::string> buildDerivation(const std::string &drvPath);
  void ensurePath(const std::string &path);

  /// Add a symlink GC root.
  void addPermRoot(const std::string &storePath, const std::string &link);

  bool collectGarbage(bool dryRun, composite::MutableSeries<std::string> &deleted);
  bool deletePath(const std::string &path);

  void (*log)(const std::string &) = nullptr;

  StoreSettings settings;
  /// A derivation's modulo hashes as its dependents read them: hashDerivationModulo's answer, and for an input-addressed derivation (one
  /// hash, key "") that hash in base 16 already, as a dependent's text names the input.
  struct DrvModulo {
    SortedMap<Hash> hashes;
    std::string hex;
  };
  /// A derivation the store made or read, by its path: the derivation, and its modulo hashes once a dependent's hash asked for them.  A
  /// record never moves and lives as long as the store (the hasher reads its derivation where it lies); its path is its key in `drvs`, a
  /// crit-bit trie (Composite/Patricia.h): the paths share their store directory and a dependent looks its inputs up by path.
  struct DrvRecord {
    std::string path;
    Derivation drv;
    bool hasModulo = false;
    DrvModulo modulo;
  };
  composite::Patricia<DrvRecord *> drvs;
  DrvRecord *drvAt(const std::string &path);
  /// The record of `path`, made with `drv`; one there already keeps its derivation unless `replace`.
  DrvRecord &keepDerivation(const std::string &path, Derivation &&drv, bool replace);
  /// A content fingerprint's first derivation, its record, in Krapivin's table (Composite/Funnel.h): the keys are
  /// already 64-bit hashes.
  struct ContentRow {
    uint64_t k;
    const DrvRecord *rec;
    friend constexpr bool operator<(const ContentRow &a, const ContentRow &b) { return a.k < b.k; }
    friend constexpr bool operator==(const ContentRow &a, const ContentRow &b) { return a.k == b.k; }
  };
  struct ContentHash {
    constexpr uint64_t operator()(const ContentRow &r) const { return r.k; }
  };
  composite::GrowFunnel<ContentRow, 15, 8, 5, ContentHash> drvByContent;
  /// The path of a derivation this evaluation made before with the same content, or null.  `drv` is as derivationStrict has it before its
  /// output paths are filled in.  Some 40% of the derivations an evaluation makes are made again, by another call with equal attributes (a
  /// bootstrap stage's fetchurl, a package called twice); one found by a fingerprint of its strings and a compare skips both SHA-256 passes.
  /// `fingerprint` receives the fingerprint, for rememberDerivation when there is no such derivation.
  const std::string *sameDerivation(const Derivation &drv, uint64_t &fingerprint) const;
  void rememberDerivation(uint64_t fingerprint, const std::string &drvPath);
  std::string infoFile(const std::string &path) const;
  void makeStoreWritable();
  SortedMap<std::string> realise(const std::string &drvPath,
                                             SortedSet &visiting);
  void runBuilder(const std::string &drvPath, const Derivation &drv,
                  const SortedMap<std::string> &outputs);
  void builtinFetchurl(const Derivation &drv, const SortedMap<std::string> &outputs);
};

/// (.attrs.json, .attrs.sh) contents for a structured-attrs derivation.
composite::Join<std::string, std::string> structuredAttrsFiles(const std::string &json,
                                                         const SortedMap<std::string> &outputs,
                                                         const SortedMap<std::string> &rewrites);

/// Helpers.
std::string readFile(const std::string &path);
void writeFile(const std::string &path, std::string_view data, mode_t mode = 0644);
bool pathExists(const std::string &path);
void createDirs(const std::string &path);
void deletePathRecursive(const std::string &path);
std::string baseNameOf(std::string_view p);
std::string dirOf(std::string_view p);
/// JSON string escaping as done by nlohmann::json::dump().
std::string jsonEscape(std::string_view s);
/// Number formatting as done by nlohmann::json for doubles.
std::string jsonFloat(double d);
/// Run a program, capturing stdout. Returns exit status.
int runProgram(const std::string &prog, const composite::MutableSeries<std::string> &args,
               std::string *out, const std::string *input = nullptr,
               const std::string &cwd = "");

} // namespace nixstore

#endif
