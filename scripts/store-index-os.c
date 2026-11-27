// The system's words of the store index (lowered/nixstore/StoreIndexDarwin.mlir.in, StoreIndexLinux.mlir) against the
// headers of the system this is compiled on, and what lowered/nixstore/StoreIndex.mlir takes to be the same everywhere.
// Built and run by scripts/store-index-check.sh.
//   usage: store-index-os DIR     (DIR: an empty directory to work in; its file system is the one asked about)
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
#ifdef __APPLE__
#include <sys/mount.h>
#include <sys/param.h>
#include <sys/sysctl.h>
#define ST_ATIME st_atimespec
#define ST_MTIME st_mtimespec
#define ST_CTIME st_ctimespec
#else
#include <sys/vfs.h>
#define ST_ATIME st_atim
#define ST_MTIME st_mtim
#define ST_CTIME st_ctim
#endif

int64_t nixsi_os_name(void), nixsi_os_atime(void), nixsi_os_anon(void), nixsi_os_local(int fd), nixsi_os_boot(char *buf, int64_t cap);
int nixsi_os_open(const char *path, int64_t how), nixsi_os_fstat(int fd, void *buf), nixsi_os_lstat(const char *path, void *buf);
void *nixsi_os_opendir(const char *path), *nixsi_os_readdir(void *dir);

static int bad;
#define CHECK(what, cond) do { if (!(cond)) { printf("WRONG: %s\n", what); bad++; } } while (0)
#define SAME(what, got, want) do { long long g = (long long)(got), w = (long long)(want); if (g != w) { printf("WRONG: %s is %lld, the system's is %lld\n", what, g, w); bad++; } } while (0)

int main(int argc, char **argv) {
  if (argc < 2) { fprintf(stderr, "usage: store-index-os DIR\n"); return 2; }
  char p[2048], q[2048];
  // the layouts
  SAME("nixsi_os_name (a directory entry's name)", nixsi_os_name(), offsetof(struct dirent, d_name));
  SAME("a directory entry's type, the byte before its name", nixsi_os_name() - 1, offsetof(struct dirent, d_type));
  SAME("a directory entry's file number", 0, offsetof(struct dirent, d_ino));
  SAME("a regular file's type", 8, DT_REG);
  SAME("nixsi_os_atime (where a file's times begin)", nixsi_os_atime(), offsetof(struct stat, ST_ATIME));
  SAME("a file's modification time", nixsi_os_atime() + 16, offsetof(struct stat, ST_MTIME));
  SAME("a file's change time", nixsi_os_atime() + 32, offsetof(struct stat, ST_CTIME));
  SAME("a file's number", 8, offsetof(struct stat, st_ino));
  CHECK("what stat fills fits the 32 words given it", sizeof(struct stat) <= 256);
  CHECK("the times begin at a word", nixsi_os_atime() % 8 == 0);
  SAME("a time's words", 16, sizeof(struct timespec));
  SAME("a time's nanoseconds", 8, offsetof(struct timespec, tv_nsec));
  SAME("time_t", 8, sizeof(time_t));
  SAME("off_t", 8, sizeof(off_t));
  // what StoreIndex.mlir takes to be the same everywhere
  SAME("nixsi_os_anon", nixsi_os_anon(), MAP_PRIVATE | MAP_ANON | MAP_NORESERVE);
  SAME("LOCK_SH", 1, LOCK_SH); SAME("LOCK_EX", 2, LOCK_EX); SAME("LOCK_UN", 8, LOCK_UN);
  SAME("PROT_READ", 1, PROT_READ); SAME("PROT_READ | PROT_WRITE", 3, PROT_READ | PROT_WRITE); SAME("MAP_SHARED", 1, MAP_SHARED);
  SAME("SEEK_END", 2, SEEK_END);
  CHECK("MAP_FAILED is -1", (intptr_t)MAP_FAILED == -1);
  // a file opened
  umask(0);
  snprintf(p, sizeof p, "%s/os-check-file", argv[1]);
  unlink(p);
  CHECK("to read: none where there is no file", nixsi_os_open(p, 0) < 0 && errno == ENOENT);
  CHECK("to read and write: none where there is no file", nixsi_os_open(p, 1) < 0 && errno == ENOENT);
  int fd = nixsi_os_open(p, 2);
  CHECK("made when it is not there", fd >= 0);
  struct stat st;
  CHECK("a file made is rw-r--r--", fstat(fd, &st) == 0 && (st.st_mode & 07777) == 0644);
  CHECK("made to read and write", (fcntl(fd, F_GETFL) & O_ACCMODE) == O_RDWR);
  CHECK("not kept across an exec", fcntl(fd, F_GETFD) & FD_CLOEXEC);
  CHECK("written", write(fd, "twelve bytes", 12) == 12);
  close(fd);
  fd = nixsi_os_open(p, 2);
  CHECK("not cut when it is there", fd >= 0 && fstat(fd, &st) == 0 && st.st_size == 12);
  close(fd);
  fd = nixsi_os_open(p, 0);
  CHECK("to read", fd >= 0 && (fcntl(fd, F_GETFL) & O_ACCMODE) == O_RDONLY && (fcntl(fd, F_GETFD) & FD_CLOEXEC));
  close(fd);
  fd = nixsi_os_open(p, 1);
  CHECK("to read and write", fd >= 0 && (fcntl(fd, F_GETFL) & O_ACCMODE) == O_RDWR && (fcntl(fd, F_GETFD) & FD_CLOEXEC));
  close(fd);
  fd = nixsi_os_open(p, 3);
  CHECK("written anew: cut", fd >= 0 && fstat(fd, &st) == 0 && st.st_size == 0 && (fcntl(fd, F_GETFL) & O_ACCMODE) == O_WRONLY && (fcntl(fd, F_GETFD) & FD_CLOEXEC));
  close(fd);
  snprintf(q, sizeof q, "%s/os-check-new", argv[1]);
  unlink(q);
  fd = nixsi_os_open(q, 3);
  CHECK("written anew: made rw-r--r--", fd >= 0 && fstat(fd, &st) == 0 && (st.st_mode & 07777) == 0644);
  // stat under the system's names: the same bytes as the C library's
  uint64_t mine[32], theirs[32];
  memset(mine, 0, sizeof mine); memset(theirs, 0, sizeof theirs);
  CHECK("nixsi_os_fstat", nixsi_os_fstat(fd, mine) == 0 && fstat(fd, (struct stat *)theirs) == 0 && !memcmp(mine, theirs, sizeof(struct stat)));
  close(fd);
  memset(mine, 0, sizeof mine); memset(theirs, 0, sizeof theirs);
  CHECK("nixsi_os_lstat", nixsi_os_lstat(q, mine) == 0 && lstat(q, (struct stat *)theirs) == 0 && !memcmp(mine, theirs, sizeof(struct stat)));
  CHECK("nixsi_os_lstat of nothing", nixsi_os_lstat("/nowhere/at/all", mine) != 0);
  SAME("the file's number, the second word", mine[1], ((struct stat *)theirs)->st_ino);
  // the directory read: the same names and numbers as the C library's
  void *d = nixsi_os_opendir(argv[1]);
  DIR *e = opendir(argv[1]);
  CHECK("nixsi_os_opendir", d && e);
  int entries = 0;
  for (;;) {
    char *a = d ? nixsi_os_readdir(d) : 0;
    struct dirent *b = e ? readdir(e) : 0;
    if (!a || !b) { CHECK("the directory's entries end together", !a && !b); break; }
    uint64_t ino; memcpy(&ino, a, 8);
    CHECK("an entry's name", !strcmp(a + nixsi_os_name(), b->d_name));
    CHECK("an entry's number", ino == (uint64_t)b->d_ino);
    CHECK("an entry's type", (unsigned char)a[nixsi_os_name() - 1] == b->d_type);
    entries++;
  }
  CHECK("the directory has its two files and itself", entries >= 4);
  CHECK("nixsi_os_opendir of nothing", nixsi_os_opendir("/nowhere/at/all") == 0);
  // what the directory's file system is trusted with
  int dfd = open(argv[1], O_RDONLY);
  struct statfs sf;
  long long want = 0;
  if (fstatfs(dfd, &sf) == 0) {
#ifdef __APPLE__
    CHECK("what statfs fills fits the 272 words given it", sizeof sf <= 2176);
    want = (sf.f_flags & MNT_LOCAL) && (!strcmp(sf.f_fstypename, "apfs") || !strcmp(sf.f_fstypename, "hfs")) ? 2 : 0;
    printf("the directory's file system: %s, %s\n", sf.f_fstypename, sf.f_flags & MNT_LOCAL ? "local" : "not local");
#else
    CHECK("what statfs fills fits the 32 words given it", sizeof sf <= 256);
    unsigned long t = (unsigned long)sf.f_type;
    want = t == 0xEF53 || t == 0x58465342 || t == 0x9123683E || t == 0x01021994 || t == 0x2FC12FC1 || t == 0xF2F52010 || t == 0xCA451A4E || t == 0x794C7630;
    printf("the directory's file system: %#lx\n", t);
#endif
  }
  SAME("nixsi_os_local", nixsi_os_local(dfd), want);
  SAME("nixsi_os_local of no file", nixsi_os_local(-1), 0);
  close(dfd);
  // this boot's name
  char b1[64], b2[64];
  memset(b1, 0, sizeof b1); memset(b2, 0, sizeof b2);
  int64_t n1 = nixsi_os_boot(b1, sizeof b1), n2 = nixsi_os_boot(b2, sizeof b2);
  CHECK("this boot has a name, the same when asked again", n1 > 0 && n1 <= 64 && n1 == n2 && !memcmp(b1, b2, 64));
  printf("this boot: %.*s (%lld bytes)\n", (int)(n1 > 0 ? (n1 < 40 ? n1 : 40) : 0), b1, (long long)n1);
#ifdef __APPLE__
  char u[64]; size_t ul = sizeof u;
  CHECK("it is kern.bootsessionuuid", sysctlbyname("kern.bootsessionuuid", u, &ul, 0, 0) == 0 && (int64_t)ul == n1 && !memcmp(u, b1, ul));
#endif
  unlink(p); unlink(q);
  printf("%s: nixsi_os_local %lld, %d words wrong\n", argv[1], (long long)want, bad);
  return bad ? 1 : 0;
}
