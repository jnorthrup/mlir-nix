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

#include "Composite/Mutable.h"
#include <functional>
#include <map>
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
// Hashes
//===----------------------------------------------------------------------===//

enum class HashAlgo { MD5, SHA1, SHA256, SHA512 };
enum class HashFormat { Base16, Nix32, Base64, SRI };

size_t hashSize(HashAlgo a);
std::string algoName(HashAlgo a);
std::optional<HashAlgo> parseHashAlgo(std::string_view s);

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
  void *impl;
  uint64_t total = 0;
};

Hash hashString(HashAlgo a, std::string_view s);
Hash hashFile(HashAlgo a, const std::string &path);
/// Parse a hash in any supported encoding; `algo` is required when the string
/// carries no algorithm prefix.  Throws Error.
Hash parseHash(std::string_view s, std::optional<HashAlgo> algo);
/// Like parseHash, but the empty string yields an all-zero hash (with a warning
/// returned via `warning`).
Hash parseHashAllowEmpty(std::string_view s, std::optional<HashAlgo> algo,
                         std::string *warning);
Hash compressHash(const Hash &h, size_t newSize);

std::string base16Encode(const uint8_t *d, size_t n);
std::string nix32Encode(const uint8_t *d, size_t n);
std::string base64Encode(std::string_view s);
std::optional<std::string> base64Decode(std::string_view s);
std::optional<std::string> nix32Decode(std::string_view s, size_t size);
extern const char nix32Chars[33];

//===----------------------------------------------------------------------===//
// NAR
//===----------------------------------------------------------------------===//

using PathFilter = std::function<bool(const std::string &path)>;
using Sink = std::function<void(std::string_view)>;

/// Serialise `path` as a Nix ARchive.  Throws Error on I/O failure.
void dumpPath(const std::string &path, const Sink &sink,
              const PathFilter &filter = nullptr);
/// Restore a NAR into `path` (which must not exist).
void restorePath(const std::string &path, std::string_view nar);
/// sha256 of the NAR serialisation, and the NAR size.
std::pair<Hash, uint64_t> hashPath(const std::string &path,
                                   const PathFilter &filter = nullptr,
                                   HashAlgo algo = HashAlgo::SHA256);

//===----------------------------------------------------------------------===//
// Store paths
//===----------------------------------------------------------------------===//

enum class FileIngestionMethod { Flat, NixArchive, Text };

/// Throws Error with upstream's message on invalid names.
void checkName(std::string_view name);
std::string makeStorePath(const std::string &storeDir, std::string_view type,
                          const Hash &hash, std::string_view name);
std::string makeType(const std::string &storeDir, std::string type,
                     const std::set<std::string> &refs, bool hasSelfRef);
std::string makeTextPath(const std::string &storeDir, std::string_view name,
                         const Hash &hash, const std::set<std::string> &refs);
std::string makeFixedOutputPath(const std::string &storeDir, std::string_view name,
                                FileIngestionMethod method, const Hash &hash,
                                const std::set<std::string> &refs = {});
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
  std::map<std::string, DerivationOutput> outputs;
  std::map<std::string, std::set<std::string>> inputDrvs;
  std::set<std::string> inputSrcs;
  std::string platform, builder;
  composite::MutableSeries<std::string> args;
  std::map<std::string, std::string> env;
  std::optional<std::string> structuredAttrs; // JSON text (env "__json")

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
  std::string unparse(bool maskOutputs,
                      const std::map<std::string, std::set<std::string>> *actualInputs = nullptr) const;
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
  std::set<std::string> references;
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
  const std::string &storeDir() const { return settings.storeDir; }
  const StoreSettings &config() const { return settings; }
  bool readOnly() const { return settings.readOnly; }

  /// Physical location of a logical store path.
  std::string toReal(const std::string &logical) const;

  bool isValidPath(const std::string &path);
  std::optional<PathInfo> queryPathInfo(const std::string &path);
  void registerValidPath(const PathInfo &info);
  std::set<std::string> queryReferrers(const std::string &path);
  composite::MutableSeries<std::string> allValidPaths();

  /// Copy a file system object into the store (content-addressed).
  std::string addToStore(std::string name, const std::string &srcPath,
                         FileIngestionMethod method = FileIngestionMethod::NixArchive,
                         HashAlgo algo = HashAlgo::SHA256,
                         const PathFilter &filter = nullptr,
                         const std::set<std::string> &refs = {},
                         std::optional<Hash> expected = std::nullopt);
  std::string addTextToStore(std::string_view name, std::string_view text,
                             const std::set<std::string> &refs);
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
  /// "out") or a single drv hash (key "").
  std::map<std::string, Hash> hashDerivationModulo(const Derivation &drv, bool maskOutputs);
  void fillInOutputPaths(Derivation &drv);

  std::set<std::string> computeFSClosure(const std::set<std::string> &paths,
                                         bool includeOutputs = false);

  /// Realise derivation outputs (building as necessary).  Returns the output
  /// paths by name.
  std::map<std::string, std::string> buildDerivation(const std::string &drvPath);
  void ensurePath(const std::string &path);

  /// Add a symlink GC root.
  void addPermRoot(const std::string &storePath, const std::string &link);

  bool collectGarbage(bool dryRun, composite::MutableSeries<std::string> &deleted);
  bool deletePath(const std::string &path);

  std::function<void(const std::string &)> log;

  StoreSettings settings;
  std::map<std::string, std::map<std::string, Hash>> drvHashes;
  std::map<std::string, Derivation> drvCache;
  std::string infoFile(const std::string &path) const;
  void makeStoreWritable();
  std::map<std::string, std::string> realise(const std::string &drvPath,
                                             std::set<std::string> &visiting);
  void runBuilder(const std::string &drvPath, const Derivation &drv,
                  const std::map<std::string, std::string> &outputs);
  void builtinFetchurl(const Derivation &drv, const std::map<std::string, std::string> &outputs);
};

/// (.attrs.json, .attrs.sh) contents for a structured-attrs derivation.
std::pair<std::string, std::string> structuredAttrsFiles(const std::string &json,
                                                         const std::map<std::string, std::string> &outputs,
                                                         const std::map<std::string, std::string> &rewrites);

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
