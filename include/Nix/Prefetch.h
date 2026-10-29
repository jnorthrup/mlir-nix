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

#include "Composite/Series.h"

#include <string>

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

} // namespace nixprefetch

#endif
