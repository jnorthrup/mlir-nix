/* ci-api differential: old api.mlir (renamed old_*) against the new one, linked into this one executable with the glue
   (glue.mlir).  Each unit runs in a forked child, so a crash ends only the case it is on: the parent records the line,
   keeps the rest of the unit going in a new child, and never calls into the server code itself.
   usage: ci-api-walks CASES   (CASES from ci-api-gen.py: one case per line, tab-separated, hex-encoded bytes)
     R  ov body want   a what-if request: old and new request, then set (want 1) or reset (0) when framed
     F  status text    fail_with's reply
     N  method path    the 404
     C  corpus         a corpus: the Q lines after it are its queries (g_init once per child)
     Q  body twflag    a query body (twflag 1: its coordinates in the request; 0: tw = 0)
   Output per line: "ok LINE CLASS", "diff LINE WHAT", "skip LINE", "crash LINE SIGNAL" (LINE is 1-based). */
#define _DEFAULT_SOURCE
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#ifndef MAP_ANONYMOUS
#define MAP_ANONYMOUS MAP_ANON
#endif

typedef int64_t i64;

void g_request(void *bp, i64 bn, bool want, void *out);
void g_set(void *ov, i64 ovn, void *bp, i64 bn, void *segs, i64 ns, i64 value, void *out);
void g_remove(void *ov, i64 ovn, void *bp, i64 bn, void *segs, i64 ns, void *out);
void g_free(void *f, void *segs);
void g_fail(i64 status, void *p, i64 n, void *out);
void g_404(void *in, i64 m, i64 p, void *out);
i64 g_init(void *a, void *b, i64 n);
void g_query(void *in, i64 body, void *out);

/* a builder's reply: its status, and the bytes after the 256 bytes of head room (what the server sends) */
typedef struct {
  i64 status;
  i64 n;
  unsigned char *b;
} Got;

/* a made buffer: its bytes (none when null) and ok */
typedef struct {
  i64 n;
  unsigned char *b;
  i64 ok;
} Made;

static volatile i64 *cur; /* the 0-based line the child is on: shared with the parent */

static int nibble(int c) { return c <= '9' ? c - '0' : (c | 32) - 'a' + 10; }

static unsigned char *unhex(const char *h, i64 *n) {
  size_t L = strlen(h) / 2;
  unsigned char *b = malloc(L + 1);
  for (size_t i = 0; i < L; i++) b[i] = (unsigned char)(nibble(h[2 * i]) * 16 + nibble(h[2 * i + 1]));
  b[L] = 0;
  *n = (i64)L;
  return b;
}

/* out[k] = status, out[k+1] = length, out[k+2] = the builder's buffer (glue.mlir's g_take) */
static Got taken(i64 *out, int k) {
  unsigned char *p = (unsigned char *)(uintptr_t)out[k + 2];
  i64 n = out[k + 1];
  Got g = {out[k], 0, malloc(1)};
  if (p && n >= 256) {
    g.n = n - 256;
    free(g.b);
    g.b = malloc((size_t)g.n + 1);
    memcpy(g.b, p + 256, (size_t)g.n);
  }
  if (p) free(p);
  return g;
}

static Made made(i64 *out, int k) {
  unsigned char *p = (unsigned char *)(uintptr_t)out[k];
  i64 n = out[k + 1];
  Made m = {0, malloc(1), out[k + 2]};
  if (p && n > 0) {
    free(m.b);
    m.n = n;
    m.b = malloc((size_t)n + 1);
    memcpy(m.b, p, (size_t)n);
  }
  if (p) free(p);
  return m;
}

static int same_got(Got a, Got b) { return a.status == b.status && a.n == b.n && memcmp(a.b, b.b, (size_t)a.n) == 0; }

static int same_made(Made a, Made b) { return a.n == b.n && a.ok == b.ok && memcmp(a.b, b.b, (size_t)a.n) == 0; }

/* the query's timing: "queryMs":<digits> reads as "queryMs":T (printf's %f: not compared) */
static Got mask_qms(Got g) {
  static const char needle[] = "\"queryMs\":";
  const i64 nl = (i64)sizeof needle - 1;
  Got r = {g.status, 0, malloc((size_t)g.n + 8)};
  i64 i = 0;
  while (i < g.n) {
    if (g.n - i >= nl && memcmp(g.b + i, needle, (size_t)nl) == 0) {
      memcpy(r.b + r.n, needle, (size_t)nl);
      r.n += nl;
      i += nl;
      r.b[r.n++] = 'T';
      while (i < g.n && ((g.b[i] >= '0' && g.b[i] <= '9') || g.b[i] == '.')) i++;
    } else {
      r.b[r.n++] = g.b[i++];
    }
  }
  return r;
}

static void diff(int line, const char *what) { printf("diff %d %s\n", line, what); }

/* the fields of a line: f[0] is the kind, f[1..] the hex fields (an empty field is kept: "\t\t" is one empty field) */
static int split(const char *ln, char **f, int max) {
  char *t = strdup(ln);
  int k = 0;
  char *s = t;
  while (k < max) {
    f[k++] = s;
    char *tab = strchr(s, '\t');
    if (!tab) break;
    *tab = 0;
    s = tab + 1;
  }
  return k;
}


static void case_R(int line, char *f1, char *f2, char *f3) {
  i64 ovn, bn;
  unsigned char *ov = unhex(f1, &ovn), *body = unhex(f2, &bn);
  bool want = atoi(f3) != 0;
  i64 out[32];
  memset(out, 0, sizeof out);
  g_request(body, bn, want, out);
  i64 o_seg0 = out[1], o_ns = out[2], o_vt = out[3], o_ok = out[4];
  i64 n_f = out[8], n_segs = out[9], n_ns = out[10], n_vt = out[11], n_ok = out[12];
  Got ob = taken(out, 5), nb = taken(out, 13);
  if (o_ns != n_ns || o_vt != n_vt || o_ok != n_ok || !same_got(ob, nb)) return diff(line, "request");
  if (n_ok && n_ns > 0 && *(i64 *)(uintptr_t)n_segs != o_seg0) return diff(line, "request-segs");
  if (!n_ok) {
    g_free((void *)(uintptr_t)n_f, (void *)(uintptr_t)n_segs);
    printf("ok %d request-%lld\n", line, (long long)nb.status);
    return;
  }
  if (want)
    g_set(ov, ovn, body, bn, (void *)(uintptr_t)n_segs, n_ns, n_vt, out);
  else
    g_remove(ov, ovn, body, bn, (void *)(uintptr_t)n_segs, n_ns, out);
  Made o = made(out, 0);
  Got ob2 = taken(out, 3);
  Made n = made(out, 6);
  Got nb2 = taken(out, 9);
  if (!same_made(o, n) || !same_got(ob2, nb2)) return diff(line, want ? "set" : "reset");
  g_free((void *)(uintptr_t)n_f, (void *)(uintptr_t)n_segs);
  printf("ok %d %s-%s\n", line, want ? "set" : "reset", o.ok ? "made" : "refused");
}

static void case_F(int line, char *f1, char *f2) {
  i64 n;
  unsigned char *t = unhex(f2, &n);
  i64 out[32];
  memset(out, 0, sizeof out);
  g_fail(atoll(f1), t, n, out);
  Got o = taken(out, 0), nw = taken(out, 3);
  if (!same_got(o, nw)) return diff(line, "fail_with");
  printf("ok %d fail_with\n", line);
}

static void case_N(int line, char *f1, char *f2) {
  i64 mn, pn;
  unsigned char *m = unhex(f1, &mn), *p = unhex(f2, &pn);
  i64 tn = mn + 1 + pn;
  unsigned char *t = malloc((size_t)tn + 1);
  memcpy(t, m, (size_t)mn);
  t[mn] = ' ';
  memcpy(t + mn + 1, p, (size_t)pn);
  t[tn] = 0;
  i64 tw1 = (0LL << 32) | (mn & 0xffffffffLL);
  i64 tw2 = ((mn + 1) << 32) | ((tn - (mn + 1)) & 0xffffffffLL);
  i64 out[32];
  memset(out, 0, sizeof out);
  g_404(t, tw1, tw2, out);
  Got o = taken(out, 0), nw = taken(out, 3);
  if (!same_got(o, nw)) return diff(line, "404");
  printf("ok %d 404\n", line);
}

/* the corpus at lines[ci], then the queries lines[from..to) of its unit (g_init once in this child) */
static void run_queries(char **lines, int ci, int from, int to) {
  char *f[3];
  split(lines[ci], f, 3);
  i64 cl;
  unsigned char *js = unhex(f[1], &cl);
  unsigned char *a = malloc((size_t)cl + 8), *b = malloc((size_t)cl + 8);
  memcpy(a, js, (size_t)cl);
  memcpy(b, js, (size_t)cl);
  if (!g_init(a, b, cl)) {
    printf("skip %d\n", ci + 1);
    return;
  }
  for (int l = from; l < to; l++) {
    *cur = l;
    char *q[3];
    split(lines[l], q, 3);
    i64 bn;
    unsigned char *body = unhex(q[1], &bn);
    const char *head = "POST /api/query HTTP/1.1\r\n\r\n";
    i64 hn = (i64)strlen(head);
    unsigned char *req = malloc((size_t)(hn + bn) + 1);
    memcpy(req, head, (size_t)hn);
    memcpy(req + hn, body, (size_t)bn);
    req[hn + bn] = 0;
    i64 tw = atoi(q[2]) ? ((hn << 32) | bn) : 0;
    i64 out[32];
    memset(out, 0, sizeof out);
    g_query(req, tw, out);
    Got o = mask_qms(taken(out, 0)), nw = mask_qms(taken(out, 3));
    if (!same_got(o, nw))
      diff(l + 1, "query");
    else
      printf("ok %d query-%lld\n", l + 1, (long long)o.status);
    fflush(stdout);
  }
}

/* the case at lines[at] (its unit is one line) */
static void run_case(char **lines, int at) {
  char *f[4];
  int k = split(lines[at], f, 4);
  int line = at + 1;
  switch (lines[at][0]) {
    case 'R':
      if (k == 4) case_R(line, f[1], f[2], f[3]);
      break;
    case 'F':
      if (k == 3) case_F(line, f[1], f[2]);
      break;
    case 'N':
      if (k == 3) case_N(line, f[1], f[2]);
      break;
    default:
      printf("skip %d\n", line);
  }
}

int main(int argc, char **argv) {
  if (argc != 2) {
    fprintf(stderr, "usage: ci-api-walks CASES\n");
    return 2;
  }
  cur = mmap(NULL, sizeof(i64), PROT_READ | PROT_WRITE, MAP_SHARED | MAP_ANONYMOUS, -1, 0);
  if (cur == MAP_FAILED) {
    perror("mmap");
    return 2;
  }
  FILE *fp = fopen(argv[1], "r");
  if (!fp) {
    perror("cases");
    return 2;
  }
  size_t cap = 1024, n = 0;
  char **lines = malloc(cap * sizeof *lines);
  char *buf = NULL;
  size_t bcap = 0;
  ssize_t len;
  while ((len = getline(&buf, &bcap, fp)) >= 0) {
    while (len > 0 && (buf[len - 1] == '\n' || buf[len - 1] == '\r')) buf[--len] = 0;
    if (n == cap) {
      cap *= 2;
      lines = realloc(lines, cap * sizeof *lines);
    }
    lines[n++] = strdup(buf);
  }
  fclose(fp);

  int unit = 0;
  while (unit < (int)n) {
    char kind = lines[unit][0];
    int end = unit + 1;
    if (kind == 'C')
      while (end < (int)n && lines[end][0] == 'Q') end++;
    if (kind == 'Q') {
      printf("skip %d\n", unit + 1); /* a query with no corpus above it */
      unit++;
      continue;
    }
    int pos = unit;
    while (pos < end) {
      fflush(stdout);
      *cur = pos;
      pid_t pid = fork();
      if (pid == 0) {
        if (kind == 'C')
          run_queries(lines, unit, pos == unit ? unit + 1 : pos, end);
        else
          run_case(lines, pos);
        fflush(stdout);
        _exit(0);
      }
      int status = 0;
      if (waitpid(pid, &status, 0) < 0) {
        perror("waitpid");
        return 2;
      }
      if (!WIFSIGNALED(status)) break;
      int at = (int)*cur;
      printf("crash %d signal %d\n", at + 1, WTERMSIG(status));
      fflush(stdout);
      if (kind == 'C' && at == unit) break; /* the corpus itself: its queries cannot run */
      pos = at + 1;
    }
    unit = end;
  }
  return 0;
}
