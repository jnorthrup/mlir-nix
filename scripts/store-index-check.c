// The store's index (lowered/nixstore/StoreIndex.mlir) against the info directory it is derived from, through its four
// calls, as lib/Store/LocalStore.cpp makes them.  The reference is the directory itself, read here with readdir.
// Built and run by scripts/store-index-check.sh (also with -DNO_STAMP: a directory whose time cannot be set, and
// -DNO_LOCK: a file system without locks).
//
//   store-index-check run SEED ROUNDS [MAXENTRIES]   random stores and operations in fresh directories under $SIDX_TMP (or /tmp)
//   store-index-check orphan                         the index file removed under a process that holds it
//   store-index-check child DIR SEED KIND            (run by `run`) a second process on a store: churn | once
//
// Every round: entries are written and removed behind the index's back (as an older mlnix does: a temporary and a
// rename, an unlink), registered and unlinked through the index, the index file is damaged, cut, removed or made
// read-only, other processes work on the store and are killed at any moment; and after each step
//   names        nixsi_names(dir/, 0)      is exactly the listed entries of the directory, in byte order;
//   candidates   nixsi_names(dir/q, 1)     is exactly the listed entries whose info has a reference with q's key, and
//                                          those whose info the index does not hold; so it contains every referrer of q;
//   info         nixsi_info(dir/n)         is the file's bytes, or -1; never -1 for an entry the index should hold
//                                          right after a query made it hold the directory.
#ifndef __APPLE__
#define _GNU_SOURCE
#endif
#include <dirent.h>
#include <errno.h>
#include <execinfo.h>
#include <fcntl.h>
#include <ftw.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

int64_t nixsi_info(const char *f, const char **text);
void nixsi_names(const char *f, int64_t referring, void *st, void *res);
int64_t nixsi_register(const char *f, const char *text, int64_t n);
void nixsi_unlink(const char *f);
int64_t nixstore_ts_infolines(const char *p, int64_t n, int64_t *recs);
int64_t nixstore_ts_parsehash(const char *p, int64_t n, int64_t known, uint8_t *out, uint8_t *scratch, int64_t *info);
int64_t nixstore_ts_basename(const char *p, int64_t n, char *out);
// StoreGraph.o's callbacks, never reached from here
void *nixstore_walk_room(void *c, int64_t w, int64_t n) { (void)c; (void)w; (void)n; abort(); }
const void *nixstore_walk_next(void *c, const char *p, int64_t n, int64_t w, int64_t *k) { (void)c; (void)p; (void)n; (void)w; (void)k; abort(); }
void nixstore_walk_gone(void *c, const char *p, int64_t n) { (void)c; (void)p; (void)n; abort(); }

static uint64_t rs;
// the index's own step of a sum (StoreIndex.mlir's nxsi_mix), to write first words that read back whole
static uint64_t mix64(uint64_t h, uint64_t w) {
  uint64_t k = w * 0x87c37b91114253d5ull;
  k = ((k << 31) | (k >> 33)) * 0x4cf5ad432745937full;
  h ^= k;
  return ((h << 27) | (h >> 37)) * 5 + 0x52dce729;
}
// The variants (compiled in): a directory whose time cannot be set (it is another's), a file system without locks.
#ifdef NO_STAMP
int futimens(int fd, const struct timespec t[2]) { (void)fd; (void)t; errno = EPERM; return -1; }
#define STAMPS 0
#else
#define STAMPS 1
#endif
#ifdef NO_LOCK
int flock(int fd, int op) { (void)fd; (void)op; errno = ENOLCK; return -1; }
#define LOCKS 0
#else
#define LOCKS 1
#endif
static uint64_t rnd(void) { rs ^= rs << 13; rs ^= rs >> 7; rs ^= rs << 17; return rs; }
static uint64_t below(uint64_t n) { return n ? rnd() % n : 0; }
static const char N32[] = "0123456789abcdfghijklmnpqrsvwxyz";

typedef struct { char **v; size_t n, cap; } Names;
static void namesAdd(Names *a, const char *p, size_t n) {
  if (a->n == a->cap) a->v = realloc(a->v, sizeof(char *) * (a->cap = a->cap ? a->cap * 2 : 64));
  char *s = malloc(n + 1);
  memcpy(s, p, n);
  s[n] = 0;
  a->v[a->n++] = s;
}
static void namesFree(Names *a) { for (size_t i = 0; i < a->n; i++) free(a->v[i]); free(a->v); a->v = 0; a->n = a->cap = 0; }
static int cmpName(const void *a, const void *b) { return strcmp(*(char *const *)a, *(char *const *)b); }
void nixsi_name(void *st, void *res, const char *p, int64_t n) { (void)st; namesAdd(res, p, (size_t)n); }
static void names(const char *f, int64_t referring, Names *into) { nixsi_names(f, referring, 0, into); }

static char dir[1024];   // <root>/info
static long step, fails;
static long infoAsked, infoGiven, candQueries, candGiven, candOf, quiet, ownEnds; // how much of the answers came from the index
int64_t nixsi_count(int64_t i);
static const char *what = "";
static char rootDirShown[900];
static const char *lastOp = "";
static void fail(const char *msg, const char *detail) {
  if (fails++ < 30) printf("FAIL step %ld (after %s; %s): %s %s   [%s]\n", step, lastOp, what, msg, detail ? detail : "", rootDirShown);
}
// a fault is reported and the process left by _exit: no crash report, and the round's store stays for a look
static void onFault(int sig, siginfo_t *si, void *uc) {
  (void)uc;
  char line[1400];
  int n = snprintf(line, sizeof line, "FAULT signal %d at %p, step %ld (after %s; %s)   [%s]\n", sig, si ? si->si_addr : 0, step, lastOp, what, rootDirShown);
  if (write(1, line, (size_t)n) < 0) {}
  void *frames[48];
  int k = backtrace(frames, 48);
  backtrace_symbols_fd(frames, k, 1);
  _exit(3);
}
static char altStack[1 << 16];
static void catchFaults(void) {
  stack_t ss = {.ss_sp = altStack, .ss_size = sizeof altStack, .ss_flags = 0};
  sigaltstack(&ss, 0);
  struct sigaction sa;
  memset(&sa, 0, sizeof sa);
  sa.sa_sigaction = onFault;
  sa.sa_flags = SA_SIGINFO | SA_ONSTACK;
  sigaction(SIGSEGV, &sa, 0);
  sigaction(SIGBUS, &sa, 0);
}

static char *slurp(const char *path, int64_t *n) {
  int fd = open(path, O_RDONLY);
  if (fd < 0) { *n = -1; return 0; }
  size_t cap = 65536, got = 0;
  char *b = malloc(cap);
  for (;;) {
    if (got == cap) b = realloc(b, cap *= 2);
    ssize_t k = read(fd, b + got, cap - got);
    if (k < 0) { close(fd); free(b); *n = -1; return 0; }
    if (k == 0) break;
    got += (size_t)k;
  }
  close(fd);
  *n = (int64_t)got;
  return b;
}
static void pathOf(char *out, size_t cap, const char *name) { snprintf(out, cap, "%s/%s", dir, name); }

static uint64_t keyOf(const char *p, size_t n) {
  uint64_t acc = 0;
  for (size_t i = 0; i < 12; i++) {
    uint64_t c = 0;
    if (i < n) { const char *q = memchr(N32, p[i], 32); c = q && p[i] ? (uint64_t)(q - N32) : ((uint8_t)p[i] & 31); }
    acc = (acc << 5) | c;
  }
  uint64_t c13 = 0;
  if (n > 12) { const char *q = memchr(N32, p[12], 32); c13 = q && p[12] ? (uint64_t)(q - N32) : ((uint8_t)p[12] & 31); }
  return (acc << 4) | (c13 >> 1);
}
static int listedName(const char *n) { return strlen(n) >= 34 && !strstr(n, ".tmp"); }

// an entry as the index should see it: whether its text is held (readable, a megabyte at most, every narHash one
// parseHash takes, every narSize one to nineteen digits) and whether it has a reference with the key `key`
typedef struct { int held, refers; } Seen;
static Seen look(const char *name, uint64_t key, const char *fullRef, int *trueRef) {
  Seen s = {0, 0};
  char path[2048];
  pathOf(path, sizeof path, name);
  int64_t n;
  struct stat lst;
  if (trueRef) *trueRef = 0;
  if (lstat(path, &lst) != 0 || !S_ISREG(lst.st_mode)) return s; // only a regular file is opened
  char *text = slurp(path, &n);
  if (!text || n > 1048576) { free(text); return s; }
  int64_t *recs = malloc(sizeof(int64_t) * 3 * (size_t)(n / 2 + 2));
  int64_t k = nixstore_ts_infolines(text, n, recs);
  uint8_t out[64];
  int64_t info[3];
  uint8_t *scratch = malloc((size_t)n + 64);
  char *base = malloc((size_t)n + 64);
  s.held = 1;
  for (int64_t i = 0; i < k; i++) {
    const char *v = text + recs[3 * i + 1];
    int64_t len = recs[3 * i + 2];
    if (recs[3 * i] == 0 && nixstore_ts_parsehash(v, len, -1, out, scratch, info) != 0) s.held = 0;
    if (recs[3 * i] == 1) {
      int plain = len >= 1 && len <= 19;
      for (int64_t j = 0; j < len; j++) if (v[j] < '0' || v[j] > '9') plain = 0;
      if (!plain) s.held = 0;
    }
    if (recs[3 * i] == 2) {
      int64_t bl = nixstore_ts_basename(v, len, base);
      uint64_t rk = keyOf(base, (size_t)bl);
      if (rk == key || rk == ~(uint64_t)0) s.refers = 1; // a reference whose own key is the key of all is a row every query reads
      if (trueRef && fullRef && (size_t)len == strlen(fullRef) && !memcmp(v, fullRef, (size_t)len)) *trueRef = 1;
    }
  }
  free(recs); free(scratch); free(base); free(text);
  return s;
}

static void listing(Names *all) { // every entry but . and ..
  DIR *d = opendir(dir);
  if (!d) return;
  struct dirent *e;
  while ((e = readdir(d)))
    if (strcmp(e->d_name, ".") && strcmp(e->d_name, "..")) namesAdd(all, e->d_name, strlen(e->d_name));
  closedir(d);
  qsort(all->v, all->n, sizeof(char *), cmpName);
}

static int sameNames(const Names *a, const Names *b) {
  if (a->n != b->n) return 0;
  for (size_t i = 0; i < a->n; i++) if (strcmp(a->v[i], b->v[i])) return 0;
  return 1;
}
// what the directory holds, as a number: its entries' names and file numbers
static uint64_t signature(void) {
  Names all = {0};
  listing(&all);
  uint64_t h = 1469598103934665603ull;
  for (size_t i = 0; i < all.n; i++) {
    char p[2048];
    struct stat st;
    pathOf(p, sizeof p, all.v[i]);
    uint64_t ino = lstat(p, &st) == 0 ? (uint64_t)st.st_ino : 0;
    for (const char *c = all.v[i]; *c; c++) h = (h ^ (uint8_t)*c) * 1099511628211ull;
    h = (h ^ ino) * 1099511628211ull;
  }
  namesFree(&all);
  return h;
}
static void showDiff(const Names *got, const Names *want) {
  if (fails > 30) return;
  printf("   got %zu, want %zu\n", got->n, want->n);
  size_t i = 0, j = 0, shown = 0;
  while ((i < got->n || j < want->n) && shown < 6) {
    int c = i >= got->n ? 1 : j >= want->n ? -1 : strcmp(got->v[i], want->v[j]);
    if (c == 0) { i++, j++; continue; }
    if (c < 0) printf("   + %s\n", got->v[i++]); else printf("   - %s\n", want->v[j++]);
    shown++;
  }
}

static void checkNames(void) {
  char f[2048];
  snprintf(f, sizeof f, "%s/", dir);
  Names got = {0}, all = {0}, want = {0};
  names(f, 0, &got);
  listing(&all);
  for (size_t i = 0; i < all.n; i++) if (listedName(all.v[i])) namesAdd(&want, all.v[i], strlen(all.v[i]));
  if (!sameNames(&got, &want)) { fail("names differ from the directory", 0); showDiff(&got, &want); }
  namesFree(&got); namesFree(&all); namesFree(&want);
}

// q: a name (the last component of the path asked about); storeDir: the path's directory, for the true referrers
static void checkCands(const char *q, const char *storeDir) {
  char f[2048], full[2048];
  pathOf(f, sizeof f, q);
  snprintf(full, sizeof full, "%s/%s", storeDir, q);
  Names got = {0}, all = {0}, want = {0};
  names(f, 1, &got);
  listing(&all);
  uint64_t key = keyOf(q, strlen(q));
  for (size_t i = 0; i < all.n; i++) {
    if (!listedName(all.v[i])) continue;
    int trueRef = 0;
    Seen s = look(all.v[i], key, full, &trueRef);
    if (!s.held || s.refers) namesAdd(&want, all.v[i], strlen(all.v[i]));
    else if (trueRef) fail("the reference's own key misses a referrer", all.v[i]);
  }
  if (!sameNames(&got, &want)) { fail("candidates differ", q); showDiff(&got, &want); }
  candQueries++; candGiven += (long)got.n;
  for (size_t i = 0; i < all.n; i++) candOf += listedName(all.v[i]);
  namesFree(&got); namesFree(&all); namesFree(&want);
}

// expect: 1 the index must answer when the entry's text is one it holds, 0 it may, -1 it must not
static void checkInfo(const char *name, int expect) {
  char f[2048];
  pathOf(f, sizeof f, name);
  const char *text = 0;
  int64_t n = nixsi_info(f, &text);
  int64_t fn;
  char *file = slurp(f, &fn);
  infoAsked++; infoGiven += n >= 0;
  if (n >= 0) {
    if (expect < 0) fail("an index that has not read the directory answered", name);
    if (fn != n || memcmp(file, text, (size_t)n)) fail("info is not the file's bytes", name);
    Seen s = look(name, 0, 0, 0);
    if (!s.held) fail("info answered for a text the index should not hold", name);
  } else if (expect > 0 && file) {
    struct stat st;
    Seen s = look(name, 0, 0, 0);
    if (s.held && lstat(f, &st) == 0) fail("no info for an entry the index holds", name);
  }
  free(file);
}

//===-- making entries -----------------------------------------------------------------------------------------------===//

static void hashPart(char *o) { for (int i = 0; i < 32; i++) o[i] = N32[below(32)]; }
static void randName(char *o, int kind, const Names *all) {
  char h[33] = {0};
  hashPart(h);
  if ((kind == 1 || kind == 2) && all->n) { // the hash part of another: the same key
    const char *other = all->v[below(all->n)];
    size_t take = kind == 1 ? 32 : 13 + below(6);
    if (strlen(other) >= take) memcpy(h, other, take);
  }
  switch (kind) {
  case 3: snprintf(o, 300, "%.*s", (int)(1 + below(33)), h); break;          // shorter than a store path's: not listed
  case 4: snprintf(o, 300, "%s-x%llu.tmp", h, (unsigned long long)below(1000)); break;
  case 5: snprintf(o, 300, "%s-a.tmp.b", h); break;
  case 6: snprintf(o, 300, "not a hash at all, only a long enough name %llu", (unsigned long long)below(100000)); break;
  case 7: snprintf(o, 300, "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz-all-%llu", (unsigned long long)below(100000)); break; // the key of all
  default: snprintf(o, 300, "%s-p%llu", h, (unsigned long long)below(1000000)); break;
  }
}
static size_t randText(char *o, size_t cap, const Names *all, int kind, const char *hot) {
  size_t n = 0;
  char h[53] = {0};
  for (int i = 0; i < 52; i++) h[i] = N32[i ? below(32) : below(2)];
  n += (size_t)snprintf(o + n, cap - n, "path: /nix/store/whatever\n");
  switch (kind) {
  case 1: n += (size_t)snprintf(o + n, cap - n, "narHash: sha256:%sX\n", h); break;                 // refused: too long
  case 2: n += (size_t)snprintf(o + n, cap - n, "narHash: sha256:z%s\n", h + 1); break;              // refused: bits above 256
  case 3: n += (size_t)snprintf(o + n, cap - n, "narHash: md5:00000000000000000000000000000000\n"); break; // another algorithm: taken
  default: n += (size_t)snprintf(o + n, cap - n, "narHash: sha256:%s\n", h); break;
  }
  switch (kind) {
  case 4: n += (size_t)snprintf(o + n, cap - n, "narSize: 12x\n"); break;
  case 5: n += (size_t)snprintf(o + n, cap - n, "narSize: -5\n"); break;
  case 6: n += (size_t)snprintf(o + n, cap - n, "narSize: 99999999999999999999\n"); break;
  case 7: n += (size_t)snprintf(o + n, cap - n, "narSize: \n"); break;
  case 8: n += (size_t)snprintf(o + n, cap - n, "narSize: 1234567890123456789\n"); break;               // 19 digits: plain
  default: n += (size_t)snprintf(o + n, cap - n, "narSize: %llu\n", (unsigned long long)below(100000)); break;
  }
  int refs = (int)below(below(4) ? 5 : 40);
  for (int i = 0; i < refs && n + 400 < cap; i++) {
    const char *t = all->n && below(8) ? all->v[below(all->n)] : "0000000000000000000000000000000-missing";
    switch (below(12)) {
    case 0: n += (size_t)snprintf(o + n, cap - n, "ref: /other/store/%s\n", t); break;
    case 1: n += (size_t)snprintf(o + n, cap - n, "ref: /nix/store/%s/\n", t); break;       // one trailing slash: baseNameOf drops it
    case 2: n += (size_t)snprintf(o + n, cap - n, "ref: %s\n", t); break;
    case 3: n += (size_t)snprintf(o + n, cap - n, "ref: \n"); break;
    default: n += (size_t)snprintf(o + n, cap - n, "ref: /nix/store/%s\n", t); break;
    }
  }
  if (hot && below(3)) n += (size_t)snprintf(o + n, cap - n, "ref: /nix/store/%s\n", hot);
  if (below(3) == 0) n += (size_t)snprintf(o + n, cap - n, "deriver: /nix/store/%s.drv\n", h);
  if (below(4) == 0) n += (size_t)snprintf(o + n, cap - n, "ca: fixed:r:sha256:%s\n", h);
  if (kind == 9) n = below(n);                                        // cut anywhere
  if (kind == 10) for (int i = 0; i < 8 && n; i++) o[below(n)] = (char)below(256);  // any bytes, NUL too
  if (kind == 11) n = 0;
  if (kind == 12 && n) n--;                                           // no newline at the end
  return n;
}
static void writeOld(const char *name, const char *text, size_t n) { // as an older mlnix: a temporary, renamed
  char f[2048], t[2048];
  pathOf(f, sizeof f, name);
  snprintf(t, sizeof t, "%s.tmp", f);
  int fd = open(t, O_WRONLY | O_CREAT | O_TRUNC, 0644);
  if (fd < 0) return;
  if (write(fd, text, n) < 0) perror("write");
  close(fd);
  rename(t, f);
}

static char rootDir[900];
int64_t nixsi_os_local(int fd);
static int trusted; // the info directory's file system is one an index file is kept beside: info answers are expected
#define quietKind (trusted && STAMPS && LOCKS) // this process uses the index file, and its tokens are held
static int otherBoot; // the index file was just rewritten as another boot's: it must be begun again
static int orphan;    // the index file this process holds was unlinked in this round: the file of that name is another
static int removeOne(const char *p, const struct stat *st, int flag, struct FTW *ftw) {
  (void)st; (void)flag; (void)ftw;
  chmod(p, 0700);
  return remove(p) ? 0 : 0;
}
static void freshStore(void) {
  static long count;
  const char *tmp = getenv("SIDX_TMP");
  snprintf(rootDir, sizeof rootDir, "%s/sidx-%d-%ld", tmp ? tmp : "/tmp", (int)getpid(), count++);
  snprintf(rootDirShown, sizeof rootDirShown, "%s", rootDir);
  mkdir(rootDir, 0755);
  snprintf(dir, sizeof dir, "%s/info", rootDir);
  mkdir(dir, 0755);
  int dfd = open(dir, O_RDONLY);
  trusted = nixsi_os_local(dfd) != 0;
  close(dfd);
  orphan = otherBoot = 0;
}
static void indexPath(char *o, size_t cap) { snprintf(o, cap, "%s.trie", dir); }

static char self[1024];
static pid_t spawnChild(uint64_t seed, const char *kind) {
  pid_t pid = fork();
  if (pid == 0) {
    char s[32];
    snprintf(s, sizeof s, "%llu", (unsigned long long)seed);
    execl(self, self, "child", dir, s, kind, (char *)0);
    _exit(127);
  }
  return pid;
}

// a child done: killed by this process, or gone by itself with nothing to say (a fault or a leaked descriptor is a failure)
static void reap(pid_t pid) {
  int st = 0;
  waitpid(pid, &st, 0);
  if (WIFSIGNALED(st) && WTERMSIG(st) == SIGKILL) return;
  if (WIFEXITED(st) && WEXITSTATUS(st) == 0) return;
  char how[64];
  snprintf(how, sizeof how, "status %#x", st);
  fail("a child process failed", how);
}

// a child's own entries: names with its mark, so that what it leaves is known whenever it stops
static int childMain(const char *d, uint64_t seed, const char *kind) {
  // nothing of the parent's is open here but the three streams: the index's files are not kept across an exec
  for (int fd = 3; fd < 64; fd++)
    if (fcntl(fd, F_GETFD) != -1) { printf("LEAK: descriptor %d open in a child\n", fd); return 4; }
  snprintf(dir, sizeof dir, "%s", d);
  rs = seed * 0x9e3779b97f4a7c15ull + 1;
  Names mine = {0}, none = {0};
  char name[400], f[2048], *text = malloc(1 << 16);
  int once = !strcmp(kind, "once");
  for (long i = 0; once ? i < 40 : 1; i++) {
    switch (below(6)) {
    case 0: case 1: {
      char h[33] = {0};
      hashPart(h);
      snprintf(name, sizeof name, "%s-kid%llu-%ld", h, (unsigned long long)seed, i);
      size_t n = randText(text, 1 << 16, &mine, 0, 0);
      pathOf(f, sizeof f, name);
      if (below(2)) nixsi_register(f, text, (int64_t)n); else writeOld(name, text, n);
      namesAdd(&mine, name, strlen(name));
      break;
    }
    case 2:
      if (mine.n) {
        size_t k = below(mine.n);
        pathOf(f, sizeof f, mine.v[k]);
        if (below(2)) nixsi_unlink(f); else unlink(f);
        free(mine.v[k]);
        mine.v[k] = mine.v[--mine.n];
      }
      break;
    case 3: { Names got = {0}; snprintf(f, sizeof f, "%s/", dir); names(f, 0, &got); namesFree(&got); break; }
    case 4: { Names got = {0}; pathOf(f, sizeof f, mine.n ? mine.v[below(mine.n)] : "nothing"); names(f, 1, &got); namesFree(&got); break; }
    default: { const char *t; pathOf(f, sizeof f, mine.n ? mine.v[below(mine.n)] : "nothing"); nixsi_info(f, &t); break; }
    }
  }
  (void)none;
  return 0;
}

static void checkAll(const Names *all, int expectInfo) {
  what = "names";
  checkNames();
  what = "candidates";
  for (int i = 0; i < 4; i++) {
    const char *q = all->n && below(5) ? all->v[below(all->n)] : below(2) ? "0000000000000000000000000000000-missing" : "x";
    checkCands(q, below(3) ? "/nix/store" : "/other/store");
  }
  what = "info";
  for (int i = 0; i < 4 && all->n; i++) checkInfo(all->v[below(all->n)], expectInfo);
  checkInfo("0000000000000000000000000000000-missing", 0);
}

// The index file removed while this process holds it: the process keeps the file it holds (which has no name now) and
// answers from it; another process makes the file anew under the name.  Shown once, with the two files told apart by a
// header of another boot's written into the new one.
static int orphanMain(void) {
  char text[4096], name[400], ip[2048];
  rs = 42;
  freshStore();
  indexPath(ip, sizeof ip);
  Names all = {0};
  for (int i = 0; i < 8; i++) {
    listing(&all);
    randName(name, 0, &all);
    size_t n = randText(text, sizeof text, &all, 0, 0);
    writeOld(name, text, n);
    namesFree(&all);
  }
  what = "the index made";
  checkNames();
  int64_t begun = nixsi_count(14);
  if (nixsi_count(1) != 1) fail("no index file in hand", 0);
  unlink(ip);
  what = "after the file was removed";
  checkNames();
  struct stat st;
  if (stat(ip, &st) == 0) fail("the process that held the file made another", 0);
  if (nixsi_count(14) != begun) fail("the index in hand was begun again", 0);
  reap(spawnChild(7, "once"));
  if (stat(ip, &st) != 0) fail("another process did not make the file anew", 0);
  int fd = open(ip, O_RDWR);
  uint64_t w[16];
  if (pread(fd, w, 128, 0) == 128 && w[0] == 0x4d4c4e4958534931ull) {
    w[9] ^= 0x5555;
    uint64_t sum = 0;
    for (uint64_t i = 0; i < 15; i++) sum += mix64(8 * i, w[i]);
    w[15] = sum;
    if (pwrite(fd, w, 128, 0) != 128) fail("the new file's first words not written", 0);
  } else fail("the new file is not an index", 0);
  close(fd);
  what = "after another made the file anew";
  begun = nixsi_count(14);
  listing(&all);
  checkAll(&all, 0);
  namesFree(&all);
  if (nixsi_count(14) != begun) fail("the process read the new file", 0);
  if (nixsi_count(1) != 1) fail("the process left the file it holds", 0);
  uint64_t other = w[9];
  reap(spawnChild(8, "once")); // a third process: the new file is another boot's to it, and it begins it again
  fd = open(ip, O_RDONLY);
  if (pread(fd, w, 128, 0) != 128 || w[9] == other) fail("a process read an index written under another boot", 0);
  close(fd);
  printf("orphan: a process keeps the index file it holds when the file is removed, and another makes it anew; %ld failures\n", fails);
  if (!fails) { chmod(rootDir, 0755); nftw(rootDir, removeOne, 16, FTW_DEPTH | FTW_PHYS); }
  return fails ? 1 : 0;
}

int main(int argc, char **argv) {
  catchFaults();
  if (argc >= 5 && !strcmp(argv[1], "child")) return childMain(argv[2], strtoull(argv[3], 0, 0), argv[4]);
  if (argc >= 2 && !strcmp(argv[1], "orphan")) { realpath(argv[0], self); return orphanMain(); }
  if (argc < 4 || strcmp(argv[1], "run")) { fprintf(stderr, "usage: store-index-check run SEED ROUNDS [MAXENTRIES] | orphan\n"); return 2; }
  realpath(argv[0], self);
  uint64_t seed = strtoull(argv[2], 0, 0);
  long rounds = atol(argv[3]);
  uint64_t maxEntries = argc > 4 ? strtoull(argv[4], 0, 0) : 120;
  rs = seed * 0x9e3779b97f4a7c15ull + 88172645463325252ull;
  char *text = malloc(1 << 21), name[400], f[2048], ip[2048];
  long ops = 0, kills = 0, damages = 0;
  for (long r = 0; r < rounds; r++) {
    freshStore();
    indexPath(ip, sizeof ip);
    uint64_t target = 1 + below(below(6) ? maxEntries / 4 + 1 : maxEntries);
    char hot[400] = {0};
    int steps = 20 + (int)below(60);
    for (int s = 0; s < steps; s++, step++) {
      Names all = {0};
      listing(&all);
      int expect = 0; // what the index must do for info right after this step's checks: set below
      int op = (int)below(100);
      uint64_t before = signature();
      ops++;
      if (op < 30) { // entries behind the index's back: a batch of them
        what = "old add";
        uint64_t k = 1 + below(all.n < target ? (target - all.n) / 2 + 2 : 3);
        for (uint64_t i = 0; i < k; i++) {
          randName(name, below(5) ? 0 : (int)below(8), &all);
          int tk = below(6) ? 0 : (int)below(13);
          size_t n = randText(text, 1 << 21, &all, tk, hot[0] ? hot : 0);
          writeOld(name, text, n);
          if (!hot[0] && below(4) == 0) snprintf(hot, sizeof hot, "%s", name);
        }
      } else if (op < 40) {
        what = "old remove";
        for (int i = 0; i < 1 + (int)below(4) && all.n; i++) { pathOf(f, sizeof f, all.v[below(all.n)]); unlink(f); }
      } else if (op < 48) {
        what = "old rewrite";
        if (all.n) {
          const char *nm = all.v[below(all.n)];
          size_t n = randText(text, 1 << 21, &all, below(4) ? 0 : (int)below(13), hot[0] ? hot : 0);
          writeOld(nm, text, n);
        }
      } else if (op < 62) {
        what = "register";
        int again = all.n && below(4) == 0;
        if (again) snprintf(name, sizeof name, "%s", all.v[below(all.n)]); else randName(name, below(6) ? 0 : (int)below(3), &all);
        size_t n = randText(text, 1 << 21, &all, below(10) ? 0 : (int)below(13), hot[0] ? hot : 0);
        pathOf(f, sizeof f, name);
        struct stat was;
        int overDir = lstat(f, &was) == 0 && S_ISDIR(was.st_mode); // a rename onto a directory fails, now as before: the temporary stays
        int64_t rc = nixsi_register(f, text, (int64_t)n);
        int64_t fn;
        char *file = slurp(f, &fn);
        char tmpf[2100];
        snprintf(tmpf, sizeof tmpf, "%s.tmp", f);
        struct stat st;
        if (overDir) {
          if (rc != 0 || lstat(tmpf, &st) != 0) fail("register onto a directory", name);
        } else {
          if (rc != 0 || !file || fn != (int64_t)n || memcmp(file, text, n)) fail("register did not write the file", name);
          if (lstat(tmpf, &st) == 0) fail("register left its temporary", name);
        }
        free(file);
        expect = -1; // the token is cleared until a query passes over the directory
      } else if (op < 72) {
        what = "unlink";
        if (all.n) {
          pathOf(f, sizeof f, all.v[below(all.n)]);
          nixsi_unlink(f);
          struct stat st;
          if (lstat(f, &st) == 0 && !S_ISDIR(st.st_mode)) fail("unlink left the file", f);
        } else { pathOf(f, sizeof f, "0000000000000000000000000000000-missing"); nixsi_unlink(f); }
      } else if (op < 76) {
        what = "odd entries";
        randName(name, 0, &all);
        pathOf(f, sizeof f, name);
        switch (below(5)) {
        case 0: mkdir(f, 0755); break;                                         // a directory where a file is expected
        case 1: if (all.n) { char t[2048]; pathOf(t, sizeof t, all.v[below(all.n)]); symlink(t, f); } break;
        case 2: symlink("/nowhere/at/all", f); break;
        case 3: { size_t n = randText(text, 1 << 21, &all, 0, 0); writeOld(name, text, n); chmod(f, 0); break; } // unreadable
        default: { // more than a megabyte: a thousand references and filler
          size_t n = randText(text, 1 << 21, &all, 0, 0);
          while (n < 1100000) n += (size_t)snprintf(text + n, (1 << 21) - n, "ref: /nix/store/%s\n", "0000000000000000000000000000000-filler-filler-filler");
          writeOld(name, text, n);
        }
        }
      } else if (op < 84) {
        what = "damage";
        damages++;
        struct stat st;
        if (stat(ip, &st) == 0) {
          int fd = open(ip, O_RDWR);
          int how = (int)below(8);
          if (getenv("SIDX_TRACE")) printf("trace: step %ld damage %d%s\n", step, how, orphan ? " (the file this process holds was unlinked before)" : "");
          switch (how) {
          case 0: unlink(ip); orphan = 1; break; // this process keeps the file it holds, which has no name now; another makes a new one
          case 1: if (st.st_size) { ftruncate(fd, (off_t)below((uint64_t)st.st_size)); ftruncate(fd, st.st_size); } break; // a tail lost (zeros)
          case 2: for (int i = 0; i < 1 + (int)below(20) && st.st_size; i++) { char b = (char)below(256); pwrite(fd, &b, 1, (off_t)below((uint64_t)st.st_size)); } break;
          case 3: { char z[256] = {0}; pwrite(fd, z, 256, 0); break; }                                   // the first words gone
          case 4: { uint64_t w = rnd(); pwrite(fd, &w, 8, (off_t)(8 * below(16))); break; }               // a word of the first ones
          case 5: { uint64_t w = rnd(); for (int i = 0; i < 4 && st.st_size > 256; i++) pwrite(fd, &w, 8, (off_t)(256 + below((uint64_t)st.st_size - 256) / 8 * 8)); break; }
          case 6: if (st.st_size > 256) { uint64_t w = 0; pwrite(fd, &w, 8, (off_t)(8 * (2 + below(9)))); } break; // a first word made 0: the token, a root, a count
          default: { // written under another boot: every word and the sum as they should be, but the boot's name
            uint64_t w[16];
            if (pread(fd, w, 128, 0) == 128 && w[0] == 0x4d4c4e4958534931ull) {
              w[9] ^= 0x5555;
              uint64_t sum = 0;
              for (uint64_t i = 0; i < 15; i++) sum += mix64(8 * i, w[i]);
              w[15] = sum;
              pwrite(fd, w, 128, 0);
              otherBoot = quietKind && !orphan && nixsi_count(1) == 1;
            }
          }
          }
          if (fd >= 0) close(fd);
        }
      } else if (op < 88) {
        what = "read-only";
        chmod(ip, 0444);
        chmod(rootDir, 0555);
        Names a2 = {0};
        listing(&a2);
        pid_t pid = spawnChild(rnd(), "once"); // a process that cannot write the index: still right answers (its own checks are the parent's below)
        reap(pid);
        chmod(rootDir, 0755);
        chmod(ip, 0644);
        namesFree(&a2);
      } else if (op < 94) {
        what = "killed writer";
        kills++;
        pid_t pid = spawnChild(rnd(), "churn");
        struct timespec ts = {0, (long)below(30000000)};
        nanosleep(&ts, 0);
        kill(pid, SIGKILL);
        reap(pid);
      } else {
        what = "writers at once";
        pid_t a = spawnChild(rnd(), "churn"), b = spawnChild(rnd(), "churn"), c = spawnChild(rnd(), "once");
        struct timespec ts = {0, (long)(5000000 + below(40000000))};
        nanosleep(&ts, 0);
        kill(a, SIGKILL);
        kill(b, SIGKILL);
        reap(a); reap(b); reap(c);
      }
      namesFree(&all);
      listing(&all);
      // a change of the directory by this process alone (through the index or behind its back): the index must not
      // answer for one path before a query has read the directory
      if (op < 76 && signature() != before) expect = -1;
      // before any query: the index must not answer from a directory it has not read (a change behind its back), may
      // after its own unlink
      const char *did = what;
      lastOp = did;
      if (all.n && below(2)) { what = "info before a query"; checkInfo(all.v[below(all.n)], expect < 0 ? -1 : 0); }
      what = did;
      int64_t begunBefore = nixsi_count(14);
      checkAll(&all, trusted ? (STAMPS ? 1 : 0) : -1);
      if (otherBoot && nixsi_count(14) == begunBefore) fail("an index written under another boot was read", 0);
      otherBoot = 0;
      namesFree(&all);
    }
    // what the index is for: after a query has made it hold the directory, an entry removed and written back through
    // it costs no reading of any file and no beginning again, whatever was asked in between
    if (nixsi_count(1) == 3) ownEnds++;
    if (!fails && quietKind && nixsi_count(1) == 1) {
      Names all = {0}, got = {0};
      listing(&all);
      what = "the quiet round";
      snprintf(f, sizeof f, "%s/", dir);
      names(f, 0, &got); namesFree(&got);
      const char *victim = 0;
      for (size_t i = 0; i < all.n && !victim; i++) {
        struct stat st;
        pathOf(f, sizeof f, all.v[i]);
        if (listedName(all.v[i]) && lstat(f, &st) == 0 && S_ISREG(st.st_mode) && look(all.v[i], 0, 0, 0).held) victim = all.v[i];
      }
      if (victim) {
        int64_t fn, begun = nixsi_count(14), read = nixsi_count(15);
        pathOf(f, sizeof f, victim);
        char *file = slurp(f, &fn);
        nixsi_unlink(f);
        checkCands(victim, "/nix/store");
        checkNames();
        nixsi_register(f, file, fn);
        checkCands(victim, "/nix/store");
        checkInfo(victim, 1);
        checkNames();
        if (nixsi_count(14) != begun) fail("the index was begun again for a change made through it", victim);
        if (nixsi_count(15) != read) fail("a file was read for a change made through the index", victim);
        free(file);
        quiet++;
      }
      namesFree(&all);
    }
    // the round's store is left for inspection only when something failed
    if (!fails) {
      chmod(rootDir, 0755);
      nftw(rootDir, removeOne, 16, FTW_DEPTH | FTW_PHYS);
    }
    if (fails) break;
  }
  printf("seed %llu: %ld rounds (%ld ended on an index of the process's own), %ld operations, %ld damages, %ld killed writers; %ld of %ld info texts given by the index, %ld candidates of %ld entries in %ld referrer queries, %ld quiet rounds, %lld indexes begun, %lld files read (%s); %ld failures\n",
         (unsigned long long)seed, rounds, ownEnds, ops, damages, kills, infoGiven, infoAsked, candGiven, candOf, candQueries, quiet, (long long)nixsi_count(14), (long long)nixsi_count(15), trusted ? "an index file" : "no index file here", fails);
  return fails ? 1 : 0;
}
