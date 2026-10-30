//===- Prefetch.h - Record the files an evaluation touches; replay them through io_uring -===//
//
// An evaluation of the same expression touches the same files, in the same order.  The first run
// records that order (MLNIX_PREFETCH=record:FILE); later runs replay it (MLNIX_PREFETCH=replay:FILE):
// a helper thread drives the whole list through one io_uring queue, 64 linked open->read->close
// chains and statx requests in flight, ahead of the evaluator, so that what the evaluator asks for
// is already in the page cache.  Cold, the evaluator spent 3 s of 10 s waiting for the disk one
// request at a time (docs/IO.md).  Replay is Linux with liburing; elsewhere it does nothing.
//
// The list is data: one `K path` per line, K = F file read or mapped, L lstat, S stat, D directory
// listed.
//
//===----------------------------------------------------------------------===//

#ifndef NIX_PREFETCH_H
#define NIX_PREFETCH_H

#include "Composite/Mutable.h"

#include <cstdint>
#include <string>
#include <string_view>

namespace nixprefetch {

/// Reads MLNIX_PREFETCH: record:FILE | replay:FILE | replay-wait:FILE (finish the replay before
/// evaluating: the best a prefetch can do, for measuring) | auto (the list lives under the state
/// directory, keyed by working directory and arguments: the first run records, later runs replay).
/// Call once, first thing.
void init(int argc = 0, char **argv = nullptr);

extern bool recording;
/// The files (`.nix`, kind F) a replayed list names, in order: what the evaluator will ask evalFile for (MLNIX_PRELOWER lowers them ahead).
extern composite::MutableSeries<std::string> replayFiles;
void noteSlow(char kind, const char *path);
/// Remember that the evaluation is touching `path` (kinds above).  One branch when not recording.
inline void note(char kind, const char *path) {
  if (recording) noteSlow(kind, path);
}
/// The lambda bodies a replayed list says were minted, by file, in the order they were (`M path row`; a row of a lambda nested in a
/// body exists only once that body is minted, so the order is part of the row numbers): MLNIX_PRELOWER mints them ahead, with the file.
const composite::MutableSeries<uint32_t> *replayMints(std::string_view path); // null: none recorded for the file
void noteMintSlow(const char *path, uint32_t row);
/// Remember that the evaluation minted the body of pool row `row` of `path`.
inline void noteMint(const char *path, uint32_t row) {
  if (recording) noteMintSlow(path, row);
}

/// The NAR hashes a replayed list says were made (`H path`; `G root` for a filtered tree, then `g path` for each entry its filter kept):
/// MLNIX_PRELOWER makes them again at start-up, off the evaluator's thread (nixstore::startPrehash).
struct ReplayHash {
  std::string root;
  bool filtered;
  composite::MutableSeries<std::string> kept;
};
extern composite::MutableSeries<ReplayHash> replayHashes;
bool noteRootSlow(char kind, const char *path);
void noteKeptSlow(const char *path);
/// Remember that the evaluation hashes the tree at `path` (`H`, or `G` with a filter): true the first time, when the walk that follows
/// should name the entries its filter keeps (noteKept).  A tree hashed again is not recorded again.
inline bool noteRoot(char kind, const char *path) { return recording && noteRootSlow(kind, path); }
/// An entry the filter of the tree last noted kept (`g`): not made unique, as it belongs to the root before it.
inline void noteKept(const char *path) { noteKeptSlow(path); }

} // namespace nixprefetch

#endif
