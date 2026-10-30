//===- Source.h - A Nix source, and what reading it reports -----*- C++ -*-===//
//
// What the front end shares with the evaluator: a source (its immutable bytes and where they came from), positions,
// parse errors and options, and names and strings printed as `--parse` prints them.  No tree is built from a source:
// the parser (lib/Frontend/Parser.cpp) lowers it to the nix dialect as it reads it (Nix/MLIRGen.h), and prints it
// for `--parse` in the same pass.
//
//===----------------------------------------------------------------------===//
#ifndef NIX_SOURCE_H
#define NIX_SOURCE_H

#include <cstdint>
#include <stdexcept>
#include <string_view>

#include "Composite/Table.h"
#include "Composite/Text.h"
#include "Nix/Name.h"

namespace nixfe {
/// MLNIX_STATS_IMPORTS: when set, the parser adds every path literal it lowers (canonical text) to this set.
extern composite::TextSet *pathLiterals;


struct Pos {
  uint32_t line = 0, col = 0;
  bool valid() const { return line != 0; }
};

/// The immutable bytes of one input.  A file is mapped read-only; anything else is owned.  Nothing
/// ever writes to it: the lexer's tokens are segments (start, end) of it, and text that is not a
/// slice of it (an unescaped string) is a separate, appended entry.  A source is never freed (a Name,
/// and so the IR, may be a slice of it), so it is held by a plain pointer.
struct Source {
  Source(const Source &) = delete;
  Source &operator=(const Source &) = delete;
  ~Source();
  static const Source *fromString(composite::Text text);
  /// Maps a regular, non-empty file; null when that is not possible (the caller reads it).
  static const Source *mapFile(std::string_view path);
  std::string_view view() const { return {data_, size_}; }

  Source() = default;
  const char *data_ = nullptr;
  size_t size_ = 0;
  composite::Text owned_;
  void *map_ = nullptr;
};

/// Origin of source text: a file path, or "«string»"/"«stdin»".  Made by newOrigin() and never freed, as its source is not: positions,
/// errors and the IR name it for the whole run, so it too is held by a plain pointer.
struct Origin {
  composite::Text name;   // what errors print
  composite::Text path;   // absolute file path if a file, else empty
  composite::Text baseDir;
  const Source *text = nullptr;
  uint32_t fileId = 0; // number in nixfe::FileTable, given the first time a position of this file is made
};
/// A new origin, kept for the run (under the lock the sources are kept under: a prelowering helper makes them too).
Origin *newOrigin();

struct ParseError : std::runtime_error {
  Pos pos;
  Origin *origin;
  ParseError(std::string_view msg, Pos p, Origin *o) : std::runtime_error(composite::Text(msg).c_str()), pos(p), origin(o) {}
};

enum class Lint { Ignore, Warn, Fatal };

struct ParseOptions {
  bool pipeOperators = false;
  Lint lintAbsolutePaths = Lint::Ignore, lintShortPaths = Lint::Ignore, lintUrls = Lint::Ignore;
  /// Receives lint warnings (formatted by the caller).  A plain function: the options are copied into every file's pool.
  void (*onWarning)(const ParseError &) = nullptr;
  std::string_view home;                // for ~/ paths: a window on text that outlives the options (a literal, the environment's HOME)
};

/// A source in the format of `nix-instantiate --parse`, written to `out`.  Throws ParseError.
void showSource(composite::Text &out, Origin *origin, const ParseOptions &opts);
/// Parse a source and build nothing: its syntax errors, at the cost of the parse alone.  Throws ParseError.
void skim(Origin *origin, const ParseOptions &opts);

/// A string literal with Nix escaping.
void printLiteralString(composite::Text &out, std::string_view s);
/// An identifier, quoted if necessary.
void printIdentifier(composite::Text &out, std::string_view s);
/// A float as a C++ stream writes one by default (%g: six significant digits), which is what Nix writes.
void printFloat(composite::Text &out, double d);
/// A double as "%f" writes it, six decimals: what the standard library's to_string made of one.
composite::Text fixedFloat(double d);
bool isValidIdentifier(std::string_view s);

/// Canonicalise an absolute path ('.', '..', duplicate slashes).
composite::Text canonPath(std::string_view path);
/// The same for the paths `a` and `b` joined by a slash (`b` may be empty), appended to `out`: nothing but `out` is written, so a text
/// reused from one path to the next allocates nothing.  What `out` held stays, and a '..' never reaches into it.
void canonPath(composite::Text &out, composite::Chars a, composite::Chars b = {});

} // namespace nixfe

#endif
