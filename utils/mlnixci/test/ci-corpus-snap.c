// ci-corpus-snap.c LIB CASE: the corpus stack of LIB on one case, in its own process (a crash is the exit status).
//
// LIB is a stack dylib (corpus_load, corpus_why, corpus_why_n, corpus_mark, corpus_free, cx_rows, cx_raw, cx_str, cx_tag,
// cx_nkids).  CASE is a file: u64 text length, u64 mutation length (all ones for none), the ms as f64 bits, the text, the
// mutation.  It prints the base's load (every slot, or the refusal's wording); with a mutation that loads, the mutation's
// load and corpus_mark against the base, and the marks.  A text's cx_str inside is printed with a negative length as 0.
//
// build: clang -O1 ci-corpus-snap.c -o ci-corpus-snap        (macOS and Linux; dlopen is in libc on macOS)
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void *(*load)(void *, int64_t, double);
static void *(*why)(void);
static int64_t (*whyn)(void);
static void (*mark)(void *, void *);
static void (*corpus_free)(void *);
static int64_t (*cx_rows)(void *);
static int64_t (*cx_raw)(void *, int64_t);
static int64_t (*cx_str)(void *, int64_t);
static int64_t (*cx_tag)(void *, int64_t);
static int64_t (*cx_nkids)(void *, int64_t);

static void hexbytes(const char *label, const unsigned char *p, uint64_t n) {
  printf("%s %llu ", label, (unsigned long long)n);
  for (uint64_t i = 0; i < n; i++) printf("%02x", p[i]);
  printf("\n");
}

static void i64s(const char *label, const int64_t *p, uint64_t n) {
  printf("%s %llu", label, (unsigned long long)n);
  for (uint64_t i = 0; i < n; i++) printf(" %lld", (long long)p[i]);
  printf("\n");
}

static void i32s(const char *label, const int32_t *p, uint64_t n) {
  printf("%s %llu", label, (unsigned long long)n);
  for (uint64_t i = 0; i < n; i++) printf(" %d", (int)p[i]);
  printf("\n");
}

// every slot of a corpus record (corpus.mlir's layout), and its rows' spans as cx_* read them
static void snap(const char *tag, void *c) {
  uint64_t *s = (uint64_t *)c;
  uint64_t n = s[3], len = s[1], keysLen = s[29];
  printf("%s len=%llu n=%llu ms=%llu etc=%lld keysLen=%llu\n", tag, (unsigned long long)len, (unsigned long long)n,
         (unsigned long long)s[26], (long long)s[25], (unsigned long long)keysLen);
  hexbytes("text", (const unsigned char *)s[0], len + 7);
  i64s("obj", (const int64_t *)s[4], n);
  i64s("value", (const int64_t *)s[5], n);
  i64s("state", (const int64_t *)s[6], n);
  if (keysLen) hexbytes("keys", (const unsigned char *)s[7], keysLen);
  else printf("keys 0\n");
  i64s("key", (const int64_t *)s[8], n);
  i64s("hayAt", (const int64_t *)s[10], n);
  int64_t hl = 0;
  for (uint64_t i = 0; i < n; i++) {
    int64_t h = ((const int64_t *)s[10])[i];
    int64_t e = (h >> 32) + (h & 0xffffffffLL);
    if (i == 0 || e > hl) hl = e;
  }
  if (hl > 0) hexbytes("hay", (const unsigned char *)s[9], (uint64_t)hl);
  else printf("hay 0\n");
  for (int k = 0; k < 6; k++) {
    char label[16];
    snprintf(label, sizeof label, "col%d", k);
    i32s(label, (const int32_t *)s[11 + k], n);
  }
  for (int k = 0; k < 4; k++) {
    char label[16];
    snprintf(label, sizeof label, "dict%d", k);
    printf("count%d %llu\n", k, (unsigned long long)s[21 + k]);
    i64s(label, (const int64_t *)s[17 + k], s[21 + k]);
  }
  i32s("order", (const int32_t *)s[27], n);
  i32s("baseOf", (const int32_t *)s[28], n);
  void *f = (void *)s[2];
  int64_t nr = cx_rows(f);
  printf("rows %lld\n", (long long)nr);
  for (int64_t r = 0; r < nr; r++) {
    int64_t st = cx_str(f, r);
    uint64_t start = (uint64_t)(st >> 32), inside = (uint64_t)(st & 0xffffffffLL);
    if (inside >= 0x80000000ULL) inside = 0;
    printf("row %lld raw=%lld str=%llu+%llu tag=%lld nkids=%lld\n", (long long)r, (long long)cx_raw(f, r),
           (unsigned long long)start, (unsigned long long)inside, (long long)cx_tag(f, r), (long long)cx_nkids(f, r));
  }
}

static void *copy_of(const unsigned char *b, uint64_t n) {
  unsigned char *p = (unsigned char *)malloc(n + 8);
  if (n) memcpy(p, b, n);
  return p;
}

int main(int argc, char **argv) {
  if (argc != 3) {
    fprintf(stderr, "usage: %s LIB CASE\n", argv[0]);
    return 2;
  }
  void *h = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
  if (!h) {
    fprintf(stderr, "dlopen: %s\n", dlerror());
    return 2;
  }
  *(void **)&load = dlsym(h, "corpus_load");
  *(void **)&why = dlsym(h, "corpus_why");
  *(void **)&whyn = dlsym(h, "corpus_why_n");
  *(void **)&mark = dlsym(h, "corpus_mark");
  *(void **)&corpus_free = dlsym(h, "corpus_free");
  *(void **)&cx_rows = dlsym(h, "cx_rows");
  *(void **)&cx_raw = dlsym(h, "cx_raw");
  *(void **)&cx_str = dlsym(h, "cx_str");
  *(void **)&cx_tag = dlsym(h, "cx_tag");
  *(void **)&cx_nkids = dlsym(h, "cx_nkids");
  if (!load || !why || !whyn || !mark || !corpus_free || !cx_rows || !cx_raw || !cx_str || !cx_tag || !cx_nkids) {
    fprintf(stderr, "a symbol is missing in %s\n", argv[1]);
    return 2;
  }
  FILE *f = fopen(argv[2], "rb");
  if (!f) {
    fprintf(stderr, "cannot read %s\n", argv[2]);
    return 2;
  }
  uint64_t tl = 0, ml = 0, msbits = 0;
  if (fread(&tl, 8, 1, f) != 1 || fread(&ml, 8, 1, f) != 1 || fread(&msbits, 8, 1, f) != 1) return 2;
  double ms;
  memcpy(&ms, &msbits, 8);
  unsigned char *text = (unsigned char *)malloc(tl + 1);
  if (tl && fread(text, 1, tl, f) != tl) return 2;
  int hasMut = ml != UINT64_MAX;
  unsigned char *mut = (unsigned char *)malloc(hasMut ? ml + 1 : 1);
  if (hasMut && ml && fread(mut, 1, ml, f) != ml) return 2;
  fclose(f);

  void *base = load(copy_of(text, tl), (int64_t)tl, ms);
  if (!base) {
    printf("base refused %.*s\n", (int)whyn(), (const char *)why());
  } else {
    snap("base", base);
  }
  if (hasMut) {
    void *cur = load(copy_of(mut, ml), (int64_t)ml, ms);
    if (!cur) {
      printf("mut refused %.*s\n", (int)whyn(), (const char *)why());
    } else {
      snap("mut", cur);
      if (base) {
        mark(cur, base);
        uint64_t *s = (uint64_t *)cur;
        i32s("marks", (const int32_t *)s[15], s[3]);
        i32s("markBase", (const int32_t *)s[28], s[3]);
      }
      corpus_free(cur);
    }
  }
  if (base) corpus_free(base);
  return 0;
}
