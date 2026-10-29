// The btrfs inode block compressor's first bench: the stdlib shape (a vector,
// filled and std::sort'd, per block) against the cluster shape (a dense bucket
// of min-max heap clusters over the window's tiny 96-bit address space, filled
// by arithmetic and drained in order).  docs/BTRFS-COMPRESSOR.md.
//
// Build: c++ -std=gnu++20 -O2 -I include scripts/inode-bench.cc -o /tmp/inode-bench
// The gate: both paths emit byte-identical streams.  3 interleaved runs,
// min/mean wall reported.

#include "Composite/MinMaxHeap.h"

#include <algorithm>
#include <array>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

using composite::Cluster;
using composite::InodeRow;
using composite::MinMaxHeap;

static const uint64_t kWindowObjectids = 128;   // the block window: objectid tails
static const uint32_t kHeap = 15, kPegs = 8;
static const uint32_t kBlocks = 4096;
static const uint32_t kSpillRuns = 31, kClusterRows = kHeap + kPegs;
using OrderingCluster = Cluster<InodeRow, kHeap, kPegs>;

struct Block { InodeRow *rows; uint32_t n; };

static uint32_t rngState = 1;
static uint32_t rng() {  // xorshift32: the arrival order is fixed by the seed
  rngState ^= rngState << 13; rngState ^= rngState >> 17; rngState ^= rngState << 5;
  return rngState;
}

int main(int argc, char **argv) {
  char *end = nullptr;
  const unsigned long extra = argc > 1 ? strtoul(argv[1], &end, 10) : 6;
  if (argc > 2 || extra > 512 || (end && (*end || end == argv[1]))) return 2;
  // ---- generate the stream once, outside every timed run --------------------
  std::vector<Block> blocks(kBlocks);
  uint64_t total = 0;
  rngState = 20261027;
  for (uint32_t b = 0; b < kBlocks; ++b) {
    const uint64_t base = 100 + uint64_t(b) * kWindowObjectids;
    std::vector<InodeRow> gen;
    for (uint64_t o = 0; o < kWindowObjectids; ++o) {
      gen.push_back(InodeRow::pack(base + o, 1, 0, base, uint32_t(gen.size())));   // INODE_ITEM
      gen.push_back(InodeRow::pack(base + o, 12, o / 10, base, uint32_t(gen.size())));  // INODE_REF
      gen.push_back(InodeRow::pack(base + o, 96, o, base, uint32_t(gen.size()))); // DIR_INDEX
      if (o % 20 == 7)  // 5% xattr floods: 20 rows -- the pegs settle the edges
        for (uint32_t j = 0; j < 20; ++j)
          gen.push_back(InodeRow::pack(base + o, 24, j, base, uint32_t(gen.size())));
      if (o % 100 == 7)  // add rows to a flood, so this really exceeds cluster capacity
        for (uint32_t j = 20; j < 20 + extra; ++j)
          gen.push_back(InodeRow::pack(base + o, 24, j, base, uint32_t(gen.size())));
    }
    if (gen.size() > kSpillRuns * kClusterRows) {
      fprintf(stderr, "block exceeds the bounded spill-run pool\n");
      return 2;
    }
    for (uint32_t i = uint32_t(gen.size()); i > 1; --i) std::swap(gen[i - 1], gen[rng() % i]);
    blocks[b].rows = (InodeRow *)malloc(gen.size() * sizeof(InodeRow));
    memcpy(blocks[b].rows, gen.data(), gen.size() * sizeof(InodeRow));
    blocks[b].n = uint32_t(gen.size());
    total += gen.size();
  }

  InodeRow *sinkA = (InodeRow *)malloc(total * sizeof(InodeRow));
  InodeRow *sinkB = (InodeRow *)malloc(total * sizeof(InodeRow));

  // Construct once, not raw malloc with uninitialized heap/peg counters.
  // Each unit is small; the whole bucket array is NOT claimed to fit in L1.
  std::array<OrderingCluster, kWindowObjectids> cells{};
  std::array<OrderingCluster, kSpillRuns> overflow{};
  uint64_t pegged = 0, spilled = 0;

  auto runVector = [&](InodeRow *sink) {  // A: the stdlib shape
    InodeRow *out = sink;
    std::vector<InodeRow> v;
    for (uint32_t b = 0; b < kBlocks; ++b) {
      v.assign(blocks[b].rows, blocks[b].rows + blocks[b].n);  // fill
      std::sort(v.begin(), v.end());                           // drain, after a sort
      memcpy(out, v.data(), v.size() * sizeof(InodeRow));
      out += v.size();
    }
    return uint64_t(out - sink);
  };
  auto runClusters = [&](InodeRow *sink) {  // B: the cluster shape
    InodeRow *out = sink;
    pegged = spilled = 0;
    for (uint32_t b = 0; b < kBlocks; ++b) {
      uint32_t spillRows = 0;
      for (uint32_t r = 0; r < blocks[b].n; ++r) {
        InodeRow row = blocks[b].rows[r];
        uint32_t cell = (row.hi >> 8);  // arithmetic: the tiny address space, no hash
        uint32_t took = cells[cell].insert(row);
        if (took == 1) pegged++;
        if (took == 2) {
          if (overflow[spillRows / kClusterRows].insert(row) == 2) return uint64_t(0);
          ++spillRows;
          ++spilled;
        }
      }
      if (!spillRows) {
        for (auto &cell : cells) cell.drain([&](InodeRow r) { *out++ = r; });
      } else {
        // One head per sorted spill run. Its val is a run index, not a payload.
        // Read the original row from that run when emitting it.
        MinMaxHeap<InodeRow, kSpillRuns> heads;
        auto head = [&](uint32_t i) { auto r = overflow[i].min(); r.val = i; heads.push(r); };
        for (uint32_t i = 0; i < (spillRows + kClusterRows - 1) / kClusterRows; ++i) head(i);
        auto pop = [&]() {
          uint32_t i = heads.popMin().val;
          InodeRow r = overflow[i].popMin();
          if (overflow[i].size()) head(i);
          return r;
        };
        for (auto &cell : cells) cell.drain([&](InodeRow r) {
          while (heads.size() && heads.min() < r) *out++ = pop();
          *out++ = r;
        });
        while (heads.size()) *out++ = pop();
      }
    }
    return uint64_t(out - sink);
  };

  // ---- interleave: A, B, A, B, A, B -------------------------------------------------
  double aTimes[3], bTimes[3];
  uint64_t aRows = 0, bRows = 0;
  bool identical = true;
  for (int r = 0; r < 3; ++r) {
    auto t0 = std::chrono::steady_clock::now();
    aRows = runVector(sinkA);
    auto t1 = std::chrono::steady_clock::now();
    bRows = runClusters(sinkB);
    auto t2 = std::chrono::steady_clock::now();
    aTimes[r] = std::chrono::duration<double>(t1 - t0).count();
    bTimes[r] = std::chrono::duration<double>(t2 - t1).count();
    identical &= aRows == total && bRows == total && memcmp(sinkA, sinkB, total * sizeof(InodeRow)) == 0;
  }

  // ---- the gate ---------------------------------------------------------------------
  const char *verdict = identical ? "identical" : "FAIL";
  printf("gate: %s (%llu rows each)\n", verdict, (unsigned long long)total);
  printf("routes: %llu pegged, %llu spilled; cluster %zu B; bucket array %zu B\n",
         (unsigned long long)pegged, (unsigned long long)spilled, sizeof(OrderingCluster), sizeof(cells));

  auto report = [](const char *name, double t[3], uint64_t rows) {
    double best = t[0], sum = 0;
    for (int i = 0; i < 3; ++i) { if (t[i] < best) best = t[i]; sum += t[i]; }
    printf("%-9s min %.3f s  mean %.3f s  %.1f M rows/s\n", name, best, sum / 3,
           rows / best / 1e6);
  };
  report("vector", aTimes, aRows);
  report("cluster", bTimes, bRows);

  for (auto &block : blocks) free(block.rows);
  free(sinkA);
  free(sinkB);
  return verdict[0] == 'i' ? 0 : 1;
}
