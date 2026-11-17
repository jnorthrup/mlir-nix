// The ordering cluster (a min-max heap and its pegs, include/Composite/MinMaxHeap.h) at differing scales: the cluster's own shape
// (heap N, pegs P), the flood a cell meets (rows per cell), and the block window (cells per block).  docs/BTRFS-COMPRESSOR.md and
// docs/CLUSTER-SCALES.md.
//
// Each block is ordered four ways, and every way must emit the same stream (the gate):
//   vector    the block copied and std::sort'ed (inode-bench's A)
//   counting  the dense bucket without heaps: count rows per cell, scatter, insertion-sort each cell (the plain island)
//   cluster   a cell per objectid tail holding a Cluster<N, P>; a full cluster spills to overflow runs (clusters too), whose heads
//             merge with the cells' drain (inode-bench's B, with the run pool sized to the block)
//   cluster+  the same, with the pegs drained as a sorted run (one sort of the bag, then a pointer) instead of an argMin per pop
// Rows are InodeRow (16 B); keys are unique, so the streams must be byte-identical.  Time is the minimum of 5 interleaved rounds.
//
// Build: clang++ -std=c++20 -O3 -I include scripts/cluster-scales.cc -o build/cluster-scales
// Run:   build/cluster-scales [WINDOW FLOOD]...   (default: the sweep below)

#include "Composite/MinMaxHeap.h"

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

using composite::Cluster;
using composite::InodeRow;
using composite::MinMaxHeap;

namespace {

uint32_t rngState = 1;
uint32_t rng() { rngState ^= rngState << 13; rngState ^= rngState >> 17; rngState ^= rngState << 5; return rngState; }

struct Workload {
  uint32_t window, flood, blocks;
  std::vector<uint32_t> start;  // block b's rows: rows[start[b] .. start[b + 1])
  std::vector<InodeRow> rows;
  uint64_t total() const { return rows.size(); }
};

/// The inode workload of inode-bench, scaled: per objectid an INODE_ITEM, an INODE_REF and a DIR_INDEX; every 20th objectid an
/// xattr flood of `flood` rows.  Blocks are added until the workload holds about two million rows.
Workload make(uint32_t window, uint32_t flood) {
  Workload w{window, flood, 0, {}, {}};
  rngState = 20261027;
  std::vector<InodeRow> gen;
  while (w.rows.size() < 2000000) {
    const uint64_t base = 100 + uint64_t(w.blocks) * window;
    gen.clear();
    for (uint64_t o = 0; o < window; ++o) {
      gen.push_back(InodeRow::pack(base + o, 1, 0, base, uint32_t(gen.size())));
      gen.push_back(InodeRow::pack(base + o, 12, o / 10, base, uint32_t(gen.size())));
      gen.push_back(InodeRow::pack(base + o, 96, o, base, uint32_t(gen.size())));
      if (o % 20 == 7)
        for (uint32_t j = 0; j < flood; ++j) gen.push_back(InodeRow::pack(base + o, 24, j, base, uint32_t(gen.size())));
    }
    for (uint32_t i = uint32_t(gen.size()); i > 1; --i) std::swap(gen[i - 1], gen[rng() % i]);
    w.start.push_back(uint32_t(w.rows.size()));
    w.rows.insert(w.rows.end(), gen.begin(), gen.end());
    ++w.blocks;
  }
  w.start.push_back(uint32_t(w.rows.size()));
  return w;
}

uint64_t runVector(const Workload &w, InodeRow *out) {
  std::vector<InodeRow> v;
  InodeRow *o = out;
  for (uint32_t b = 0; b < w.blocks; ++b) {
    v.assign(w.rows.begin() + w.start[b], w.rows.begin() + w.start[b + 1]);
    std::sort(v.begin(), v.end());
    memcpy(o, v.data(), v.size() * sizeof(InodeRow));
    o += v.size();
  }
  return uint64_t(o - out);
}

/// The dense bucket without a heap: the cell of a row is arithmetic (its objectid tail), so a counting pass places every row in
/// its cell's segment, and each segment, a handful of rows, is insertion-sorted where it lies.
uint64_t runCounting(const Workload &w, InodeRow *out) {
  std::vector<uint32_t> count(w.window + 1);
  InodeRow *o = out;
  for (uint32_t b = 0; b < w.blocks; ++b) {
    const InodeRow *in = w.rows.data() + w.start[b];
    const uint32_t n = w.start[b + 1] - w.start[b];
    std::fill(count.begin(), count.end(), 0);
    for (uint32_t r = 0; r < n; ++r) ++count[(in[r].hi >> 8) + 1];
    for (uint32_t c = 1; c <= w.window; ++c) count[c] += count[c - 1];
    for (uint32_t r = 0; r < n; ++r) o[count[in[r].hi >> 8]++] = in[r];
    // count[c] is now the end of cell c's segment; the segment starts where the previous one ends
    uint32_t begin = 0;
    for (uint32_t c = 0; c < w.window; ++c) {
      const uint32_t end = count[c];
      for (uint32_t i = begin + 1; i < end; ++i) {
        InodeRow x = o[i];
        uint32_t j = i;
        while (j > begin && x < o[j - 1]) { o[j] = o[j - 1]; --j; }
        o[j] = x;
      }
      begin = end;
    }
    o += n;
  }
  return uint64_t(o - out);
}

/// A cluster whose pegs drain as a sorted run: at drain time the bag is sorted once (descending, so the least is at the end) and
/// popped from the end, instead of an argMin over the bag at every pop.  Same heap, same insert, same pegs; only the drain differs.
template <unsigned N, unsigned P>
struct SortedPegDrain {
  template <class Emit> static void drain(Cluster<InodeRow, N, P> &c, Emit &&emit) {
    InodeRow pegs[P];
    uint32_t np = c.pegs.size();
    for (uint32_t i = 0; i < np; ++i) pegs[i] = c.pegs.bag[i];
    std::sort(pegs, pegs + np, [](const InodeRow &x, const InodeRow &y) { return y < x; });
    while (c.heap.size() || np) {
      if (!np || (c.heap.size() && c.heap.min() < pegs[np - 1])) emit(c.heap.popMin());
      else emit(pegs[--np]);
    }
    while (c.pegs.size()) c.pegs.bag.removeSwap(c.pegs.size() - 1);  // the bag is drained
  }
};

template <unsigned N, unsigned P, bool SortedPegs>
struct ClusterPath {
  using C = Cluster<InodeRow, N, P>;
  static constexpr uint32_t kCap = N + P;
  std::vector<C> cells, overflow;
  uint64_t pegged = 0, spilled = 0;

  template <class Emit> void drainOne(C &c, Emit &&emit) {
    if constexpr (SortedPegs) SortedPegDrain<N, P>::drain(c, emit);
    else c.drain(emit);
  }

  uint64_t run(const Workload &w, InodeRow *out) {
    cells.assign(w.window, C{});
    // the worst block's spill, in runs of kCap rows: every flood cell may spill (flood + 3 - kCap) rows
    const uint32_t floods = (w.window + 12) / 20 + 1;
    const uint32_t spillPerFlood = w.flood + 3 > kCap ? w.flood + 3 - kCap : 0;
    overflow.assign((floods * spillPerFlood + kCap - 1) / kCap + 1, C{});
    pegged = spilled = 0;
    InodeRow *o = out;
    for (uint32_t b = 0; b < w.blocks; ++b) {
      uint32_t spillRows = 0;
      for (uint32_t r = w.start[b]; r < w.start[b + 1]; ++r) {
        const InodeRow row = w.rows[r];
        const uint32_t took = cells[row.hi >> 8].insert(row);
        pegged += took == 1;
        if (took == 2) {
          if (overflow[spillRows / kCap].insert(row) == 2) return 0;
          ++spillRows;
        }
      }
      spilled += spillRows;
      if (!spillRows) {
        for (auto &c : cells) drainOne(c, [&](InodeRow x) { *o++ = x; });
        continue;
      }
      // the spill runs (clusters), merged with the cells' drain by a heap of run heads, as inode-bench does: a head's val is its
      // run's index, and the row emitted is the run's own popMin
      const uint32_t runs = (spillRows + kCap - 1) / kCap;
      MinMaxHeap<InodeRow, 255> heads;
      auto head = [&](uint32_t i) { InodeRow h = overflow[i].min(); h.val = i; heads.push(h); };
      for (uint32_t i = 0; i < runs; ++i) head(i);
      auto pop = [&]() {
        const uint32_t i = heads.popMin().val;
        const InodeRow x = overflow[i].popMin();
        if (overflow[i].size()) head(i);
        return x;
      };
      for (auto &c : cells) drainOne(c, [&](InodeRow x) {
        while (heads.size() && heads.min() < x) *o++ = pop();
        *o++ = x;
      });
      while (heads.size()) *o++ = pop();
    }
    return uint64_t(o - out);
  }
};

struct Timed { const char *name; double best = 1e9; uint64_t rows = 0; uint64_t pegged = 0, spilled = 0; size_t cellBytes = 0; bool same = true; };

void sweep(uint32_t window, uint32_t flood) {
  const Workload w = make(window, flood);
  const uint64_t total = w.total();
  std::vector<InodeRow> ref(total), out(total);
  ClusterPath<7, 4, false> c7;   ClusterPath<7, 4, true> c7s;
  ClusterPath<15, 8, false> c15; ClusterPath<15, 8, true> c15s;
  ClusterPath<31, 16, false> c31; ClusterPath<31, 16, true> c31s;
  ClusterPath<63, 32, false> c63; ClusterPath<63, 32, true> c63s;
  Timed t[] = {{"vector"}, {"counting"}, {"heap 7+4"}, {"heap 7+4 sorted"}, {"heap 15+8"}, {"heap 15+8 sorted"},
               {"heap 31+16"}, {"heap 31+16 sorted"}, {"heap 63+32"}, {"heap 63+32 sorted"}};
  t[2].cellBytes = t[3].cellBytes = sizeof(Cluster<InodeRow, 7, 4>);
  t[4].cellBytes = t[5].cellBytes = sizeof(Cluster<InodeRow, 15, 8>);
  t[6].cellBytes = t[7].cellBytes = sizeof(Cluster<InodeRow, 31, 16>);
  t[8].cellBytes = t[9].cellBytes = sizeof(Cluster<InodeRow, 63, 32>);
  runVector(w, ref.data());
  for (int round = 0; round < 5; ++round) {
    for (int k = 0; k < 10; ++k) {
      auto t0 = std::chrono::steady_clock::now();
      uint64_t n = 0;
      switch (k) {
      case 0: n = runVector(w, out.data()); break;
      case 1: n = runCounting(w, out.data()); break;
      case 2: n = c7.run(w, out.data()); t[k].pegged = c7.pegged; t[k].spilled = c7.spilled; break;
      case 3: n = c7s.run(w, out.data()); t[k].pegged = c7s.pegged; t[k].spilled = c7s.spilled; break;
      case 4: n = c15.run(w, out.data()); t[k].pegged = c15.pegged; t[k].spilled = c15.spilled; break;
      case 5: n = c15s.run(w, out.data()); t[k].pegged = c15s.pegged; t[k].spilled = c15s.spilled; break;
      case 6: n = c31.run(w, out.data()); t[k].pegged = c31.pegged; t[k].spilled = c31.spilled; break;
      case 7: n = c31s.run(w, out.data()); t[k].pegged = c31s.pegged; t[k].spilled = c31s.spilled; break;
      case 8: n = c63.run(w, out.data()); t[k].pegged = c63.pegged; t[k].spilled = c63.spilled; break;
      case 9: n = c63s.run(w, out.data()); t[k].pegged = c63s.pegged; t[k].spilled = c63s.spilled; break;
      }
      const double s = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
      t[k].best = std::min(t[k].best, s);
      t[k].rows = n;
      t[k].same &= n == total && memcmp(out.data(), ref.data(), total * sizeof(InodeRow)) == 0;
    }
  }
  printf("window %u cells, flood %u (cells of 3 or %u rows), %u blocks of %llu rows, %llu rows\n", window, flood, flood + 3,
         w.blocks, (unsigned long long)(total / w.blocks), (unsigned long long)total);
  for (auto &x : t) {
    printf("  %-18s %6.2f ns/row  %s", x.name, x.best * 1e9 / double(total), x.same ? "identical" : "DIFFERS");
    if (x.cellBytes)
      printf("  cell %4zu B, cells %6zu B, pegged %5.2f%%, spilled %5.2f%%", x.cellBytes, x.cellBytes * window,
             100.0 * double(x.pegged) / double(total), 100.0 * double(x.spilled) / double(total));
    printf("\n");
  }
  fflush(stdout);
}

}  // namespace

int main(int argc, char **argv) {
  if (argc > 1) {
    for (int i = 1; i + 1 < argc; i += 2) sweep(uint32_t(atoi(argv[i])), uint32_t(atoi(argv[i + 1])));
    return 0;
  }
  for (uint32_t window : {32u, 128u, 512u})
    for (uint32_t flood : {20u, 44u, 92u}) sweep(window, flood);
  return 0;
}
