// The sealed page of lowered/nixstore/StoreIndex.mlir against a reference written here: random row sets sealed, the page
// compared byte for byte with the reference's, read back, searched; a page that does not compress must be kept as its
// rows (codec 0); a damaged page must be refused.  Every buffer ends at a page with no access, so a read or a write past
// what was given faults.  Built and run by scripts/store-index-check.sh.   usage: store-index-pages SEED CASES [MAXN]
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

int64_t nixsi_page_seal(const uint64_t *rows, int64_t n, int64_t tag, void *into, int64_t cap);
int64_t nixsi_page_rows(const void *page, int64_t avail, uint64_t *out, int64_t cap);
int64_t nixsi_page_find(const void *page, int64_t avail, uint64_t key, uint64_t *out, int64_t cap);
// what the pages do not use of the index's object and of StoreGraph.o's, so that this links
void nixsi_name(void *st, void *res, const char *p, int64_t n) { (void)st; (void)res; (void)p; (void)n; abort(); }
void *nixstore_walk_room(void *c, int64_t w, int64_t n) { (void)c; (void)w; (void)n; abort(); }
const void *nixstore_walk_next(void *c, const char *p, int64_t n, int64_t w, int64_t *k) { (void)c; (void)p; (void)n; (void)w; (void)k; abort(); }
void nixstore_walk_gone(void *c, const char *p, int64_t n) { (void)c; (void)p; (void)n; abort(); }

static uint64_t rs;
static uint64_t rnd(void) { rs ^= rs << 13; rs ^= rs >> 7; rs ^= rs << 17; return rs; }
static uint64_t below(uint64_t n) { return n ? rnd() % n : 0; }

// a buffer of n bytes that ends where a page without access begins
typedef struct { uint8_t *base; size_t len; } Guard;
static uint8_t *guarded(Guard *g, size_t n) {
  size_t pg = (size_t)sysconf(_SC_PAGESIZE), body = (n + pg - 1) / pg * pg;
  if (g->len < body + pg) {
    if (g->base) munmap(g->base, g->len);
    g->len = (body + pg) * 2;
    g->base = mmap(0, g->len, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (g->base == MAP_FAILED) { perror("mmap"); exit(2); }
    mprotect(g->base, g->len, PROT_READ | PROT_WRITE);
  }
  // the guard right after the body's last page; the rest of the mapping before it writable
  mprotect(g->base, g->len, PROT_READ | PROT_WRITE);
  mprotect(g->base + body, pg, PROT_NONE);
  return g->base + body - n;
}

static uint64_t rotl(uint64_t x, int r) { return (x << r) | (x >> (64 - r)); }
static uint64_t mix(uint64_t h, uint64_t w) {
  uint64_t k = w * 0x87c37b91114253d5ull;
  k = rotl(k, 31) * 0x4cf5ad432745937full;
  h ^= k;
  return rotl(h, 27) * 5 + 0x52dce729;
}
static uint64_t sum(const uint8_t *p, uint64_t n, uint64_t seed) {
  uint64_t h = seed;
  for (uint64_t i = 0; i < n; i++) { uint64_t w; memcpy(&w, p + 8 * i, 8); h = mix(h, w); }
  h ^= n; h ^= h >> 33; h *= 0xff51afd7ed558ccdull; h ^= h >> 33; h *= 0xc4ceb9fe1a85ec53ull; h ^= h >> 33;
  return h;
}
static int cmpRow(const void *a, const void *b) {
  const uint64_t *x = a, *y = b;
  if (x[0] != y[0]) return x[0] < y[0] ? -1 : 1;
  if (x[1] != y[1]) return x[1] < y[1] ? -1 : 1;
  return 0;
}
static size_t putVarint(uint8_t *o, uint64_t v) {
  int nb = 1;
  for (int k = 1; k <= 9; k++) if (v >= ((uint64_t)1 << (7 * k))) nb++;
  for (int j = 0; j < nb; j++) o[j] = (uint8_t)(((v >> (7 * (nb - 1 - j))) & 127) | (j < nb - 1 ? 128 : 0));
  return (size_t)nb;
}
// the reference page of the sorted rows; returns its bytes
static size_t refSeal(const uint64_t *sorted, uint64_t n, uint64_t tag, uint8_t *o, uint8_t *scratch) {
  size_t s = 0;
  uint64_t nr = (n + 15) / 16;
  uint16_t *starts = malloc(sizeof(uint16_t) * (nr + 1));
  int wide = 0;
  for (uint64_t k = 0; k < n; k++) {
    int restart = k % 16 == 0;
    if (restart) { if (s > 65535) wide = 1; starts[k / 16] = (uint16_t)s; }
    uint64_t pk = restart ? 0 : sorted[2 * (k - 1)], pv = restart ? 0 : sorted[2 * (k - 1) + 1];
    uint64_t dv = sorted[2 * k + 1] - pv;
    s += putVarint(scratch + s, sorted[2 * k] - pk);
    s += putVarint(scratch + s, (dv << 1) ^ (uint64_t)((int64_t)dv >> 63));
  }
  size_t psz = s + 2 * nr, raw = 16 * n;
  int delta = psz < raw && psz < 65536;
  (void)wide;
  size_t pay = delta ? psz : raw, padded = (pay + 7) & ~(size_t)7;
  uint64_t w0 = tag | 3 | ((uint64_t)delta << 24) | (n << 32), w1 = pay;
  memset(o + 24, 0, padded);
  if (delta) {
    memcpy(o + 24, scratch, s);
    for (uint64_t j = 0; j < nr; j++) { o[24 + s + 2 * j] = (uint8_t)(starts[j] & 255); o[24 + s + 2 * j + 1] = (uint8_t)(starts[j] >> 8); }
  } else {
    memcpy(o + 24, sorted, raw);
  }
  uint64_t w2 = sum(o + 24, padded / 8, w0 ^ w1);
  memcpy(o, &w0, 8); memcpy(o + 8, &w1, 8); memcpy(o + 16, &w2, 8);
  free(starts);
  return 24 + padded;
}

static long fails;
static void fail(const char *what, long c, uint64_t n) {
  if (fails++ < 20) printf("FAIL %s: case %ld n %llu\n", what, c, (unsigned long long)n);
}

int main(int argc, char **argv) {
  rs = strtoull(argv[1], 0, 0) * 0x9e3779b97f4a7c15ull + 88172645463325252ull;
  long cases = atol(argv[2]);
  uint64_t maxn = argc > 3 ? strtoull(argv[3], 0, 0) : 1100;
  Guard gr = {0}, gp = {0}, go = {0}, gf = {0};
  uint64_t *sorted = malloc(16 * (maxn + 8)), *plain = malloc(16 * (maxn + 8));
  uint8_t *ref = malloc(16 * (maxn + 8) + 64), *scratch = malloc(20 * (maxn + 8) + 64);
  long codec1 = 0, codec0 = 0, finds = 0, damaged = 0, refused = 0;
  uint64_t rawBytes = 0, pageBytes = 0;
  for (long c = 0; c < cases; c++) {
    uint64_t n;
    switch (below(12)) {
    case 0: n = below(3); break;
    case 1: n = 14 + below(5); break;
    case 2: n = maxn >= 1026 ? 1022 + below(4) : below(maxn + 1); break;
    case 3: n = below(maxn + 1); break;
    default: n = below(maxn < 48 ? maxn + 1 : 48); break;
    }
    if (n > maxn) n = maxn;
    int kd = (int)below(9), vd = (int)below(7);
    uint64_t kbase = rnd(), vbase = rnd() & 0xffffffffffull, kstep = 1 + below(1 << (below(40))), prefix = rnd() << 40;
    for (uint64_t i = 0; i < n; i++) {
      uint64_t k, v;
      switch (kd) {
      case 0: k = rnd(); break;                                  // nothing shared: does not compress
      case 1: k = kbase + below(64); break;                      // dense, many equal
      case 2: k = kbase; break;                                  // all equal
      case 3: k = below(2) ? 0 : ~(uint64_t)0; break;            // the two ends: the largest step
      case 4: k = kbase + i * kstep; break;                      // a run
      case 5: k = prefix | (rnd() >> 24); break;                 // a leaf's rows: a prefix shared
      case 6: k = below(3) ? kbase : rnd(); break;
      case 7: k = (uint64_t)1 << below(64); break;               // every varint length
      default: k = rnd() >> below(64); break;
      }
      switch (vd) {
      case 0: v = rnd(); break;
      case 1: v = vbase + 8 * below(100000); break;              // record offsets
      case 2: v = vbase + 400 * i; break;                        // records laid out in order
      case 3: v = vbase; break;
      case 4: v = (vbase + 8 * below(16)) | below(2); break;     // a row and its tombstone
      case 5: v = below(2) ? 0 : ~(uint64_t)0; break;
      default: v = rnd() >> below(64); break;
      }
      plain[2 * i] = k, plain[2 * i + 1] = v;
    }
    memcpy(sorted, plain, 16 * n);
    qsort(sorted, n, 16, cmpRow);
    uint64_t tag = (below(2) << 8) | (below(9) << 16);
    size_t want = refSeal(sorted, n, tag, ref, scratch);
    // the rows where a read past them faults, the page where a write past its bytes faults
    uint64_t *rows = (uint64_t *)guarded(&gr, 16 * n);
    memcpy(rows, plain, 16 * n);
    uint8_t *page = guarded(&gp, want);
    int64_t got = nixsi_page_seal(rows, (int64_t)n, (int64_t)tag, page, (int64_t)want);
    if (got != (int64_t)want) { fail("seal's size", c, n); continue; }
    if (memcmp(page, ref, want)) { fail("page bytes", c, n); continue; }
    if (memcmp(rows, plain, 16 * n)) fail("seal changed its rows", c, n);
    int isDelta = (page[3] & 1);
    if (isDelta) codec1++; else codec0++;
    if (isDelta && want - 24 >= 16 * n + 8) fail("a page longer than its rows", c, n);
    rawBytes += 16 * n, pageBytes += want - 24;
    if (want >= 8 && below(8) == 0) { // too little room: refused with the size, nothing written past cap
      size_t cap = below(want);
      uint8_t *small = guarded(&gf, cap);
      if (nixsi_page_seal(rows, (int64_t)n, (int64_t)tag, small, (int64_t)cap) != -(int64_t)want) fail("seal into too little room", c, n);
    }
    uint64_t *out = (uint64_t *)guarded(&go, 16 * n);
    if (nixsi_page_rows(page, (int64_t)want, out, (int64_t)n) != (int64_t)n) { fail("rows' count", c, n); continue; }
    if (memcmp(out, sorted, 16 * n)) { fail("rows", c, n); continue; }
    if (n && nixsi_page_rows(page, (int64_t)want, out, (int64_t)n - 1) != -1) fail("rows into too little room", c, n);
    if (nixsi_page_rows(page, (int64_t)want - 1, out, (int64_t)n) != -1) fail("a page cut short accepted", c, n);
    // the rows of a key: keys that are there, their neighbours, the ends, anything
    for (int f = 0; f < 6; f++) {
      uint64_t key = f == 0 ? 0 : f == 1 ? ~(uint64_t)0 : f == 2 ? rnd() : n ? sorted[2 * below(n)] + (f == 5 ? below(3) - 1 : 0) : rnd();
      uint64_t lo = 0, cnt = 0;
      while (lo < n && sorted[2 * lo] < key) lo++;
      while (lo + cnt < n && sorted[2 * (lo + cnt)] == key) cnt++;
      uint64_t cap = below(3) ? cnt + below(3) : below(cnt + 1);
      uint64_t *vals = (uint64_t *)guarded(&gf, 8 * cap);
      int64_t k = nixsi_page_find(page, (int64_t)want, key, vals, (int64_t)cap);
      finds++;
      if (k != (int64_t)cnt) { fail("find's count", c, n); break; }
      for (uint64_t i = 0; i < cnt && i < cap; i++)
        if (vals[i] != sorted[2 * (lo + i) + 1]) { fail("find's values", c, n); break; }
    }
    // one bit turned: the page is refused when read back; a search of it stays inside its bytes (the guard would fault)
    if (below(4) == 0) {
      size_t bit = below(want * 8);
      page[bit / 8] ^= (uint8_t)(1 << (bit % 8));
      damaged++;
      int64_t r = nixsi_page_rows(page, (int64_t)want, out, (int64_t)n);
      if (r != -1) fail("a damaged page read back", c, n); else refused++;
      uint64_t *vals = (uint64_t *)guarded(&gf, 8 * 4);
      int64_t k = nixsi_page_find(page, (int64_t)want, n ? sorted[2 * below(n)] : 0, vals, 4);
      if (k < -1) fail("find's answer on a damaged page", c, n);
    }
  }
  printf("seed %s: %ld cases, %ld delta pages, %ld kept as rows, %ld searches, %ld damaged (%ld refused), payload %.1f%% of the rows, %ld failures\n",
         argv[1], cases, codec1, codec0, finds, damaged, refused, rawBytes ? 100.0 * (double)pageBytes / (double)rawBytes : 0.0, fails);
  return fails ? 1 : 0;
}
