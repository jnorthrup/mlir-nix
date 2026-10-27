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
#include <functional>
#include <memory>
#include <ostream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

#include "Nix/Name.h"

namespace nixfe {

struct Pos {
  uint32_t line = 0, col = 0;
  bool valid() const { return line != 0; }
};

/// The immutable bytes of one input.  A file is mapped read-only; anything else is owned.  Nothing
/// ever writes to it: the lexer's tokens are segments (start, end) of it, and text that is not a
/// slice of it (an unescaped string) is a separate, appended entry.
struct Source {
  Source(const Source &) = delete;
  Source &operator=(const Source &) = delete;
  ~Source();
  static std::shared_ptr<const Source> fromString(std::string text);
  /// Maps a regular, non-empty file; null when that is not possible (the caller reads it).
  static std::shared_ptr<const Source> mapFile(const std::string &path);
  std::string_view view() const { return {data_, size_}; }

  Source() = default;
  const char *data_ = nullptr;
  size_t size_ = 0;
  std::string owned_;
  void *map_ = nullptr;
};

/// Origin of source text: a file path, or "«string»"/"«stdin»".
struct Origin {
  std::string name;   // what errors print
  std::string path;   // absolute file path if a file, else empty
  std::string baseDir;
  std::shared_ptr<const Source> text;
  uint32_t fileId = 0; // number in nixfe::FileTable, given the first time a position of this file is made
};

struct ParseError : std::runtime_error {
  Pos pos;
  std::shared_ptr<Origin> origin;
  ParseError(std::string msg, Pos p, std::shared_ptr<Origin> o)
      : std::runtime_error(std::move(msg)), pos(p), origin(std::move(o)) {}
};

enum class Lint { Ignore, Warn, Fatal };

struct ParseOptions {
  bool pipeOperators = false;
  Lint lintAbsolutePaths = Lint::Ignore, lintShortPaths = Lint::Ignore, lintUrls = Lint::Ignore;
  /// Receives lint warnings (formatted by the caller).
  std::function<void(const ParseError &)> onWarning;
  std::string home;                     // for ~/ paths
  std::vector<std::string> *warnings = nullptr;
};

/// Print a source in the format of `nix-instantiate --parse`.  Throws ParseError.
void showSource(std::ostream &os, std::shared_ptr<Origin> origin, const ParseOptions &opts);
/// Parse a source and build nothing: its syntax errors, at the cost of the parse alone.  Throws ParseError.
void skim(std::shared_ptr<Origin> origin, const ParseOptions &opts);

/// Print a string literal with Nix escaping.
void printLiteralString(std::ostream &os, std::string_view s);
/// Print an identifier, quoting it if necessary.
void printIdentifier(std::ostream &os, std::string_view s);
bool isValidIdentifier(std::string_view s);

/// Canonicalise an absolute path ('.', '..', duplicate slashes).
std::string canonPath(std::string_view path);

} // namespace nixfe

#endif
