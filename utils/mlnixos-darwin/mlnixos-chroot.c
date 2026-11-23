/* mlnixos-chroot: chroot isolation for darwin, the simple kind.
 *
 *   mlnixos-chroot ROOT CMD [ARG...]      run CMD (a path inside ROOT) with ROOT as "/"
 *   mlnixos-chroot --release ROOT         unmount ROOT/dev (before detaching ROOT's disk image)
 *   mlnixos-chroot --proxy                the name-resolving proxy alone, never privileged; prints its port (tests)
 *   mlnixos-chroot --populate             exit 0 if this process's shared region holds a dyld cache (run inside ROOT as
 *                                         /usr/libexec/mlnixos-chroot; see the cache)
 *
 * chroot(2) needs root on macOS, so this is installed setuid root, once:
 *   sudo install -o root -g wheel -m 4755 mlnixos-chroot /usr/local/sbin/mlnixos-chroot
 * As root it sets the caller's groups, then chroot(ROOT), chdir("/"), and mounts devfs (nosuid, noexec) on /dev when
 * /dev/null is missing.  Then it drops to the caller's uid and gid for good, checks that root cannot be regained, closes
 * every descriptor but 0-2 (one to a directory outside would let a builder climb out), and execs CMD with a fresh
 * environment.
 *
 * ROOT must be a directory the caller owns, writable by no one else, on a file system mounted nosuid: a disk image the
 * caller attached (mkroot.sh makes one; macOS mounts a user's images nosuid and nodev).  nosuid is what makes a setuid
 * chroot safe here: in a chroot the kernel loads /usr/lib/dyld from ROOT, and macOS takes any signed dyld there
 * (CONFIG_ENFORCE_SIGNED_CODE is off on macOS), so a setuid-root program hard-linked into a suid-honouring ROOT would run
 * the caller's dyld as root.  ROOT is opened once and checked through that descriptor, and the chroot is made through
 * it too, so the directory checked is the one entered.
 *
 * The cache.  macOS refuses static arm64 executables (mach_loader.c), so every program goes through ROOT/usr/lib/dyld,
 * a copy of Apple's dyld, and libSystem, libc++ and the frameworks exist only in the dyld shared cache.  A process
 * exec'd in a chroot gets a shared region of its own, keyed by the chroot's root (vm_shared_region.c), which its dyld
 * fills from cache files it opens; with SIP on, the kernel accepts only cache files that SIP protects (vm_unix.c:
 * SF_RESTRICTED), and no copy can be one.  So, before entering ROOT, the helper opens the real cache directory.  Inside,
 * it first runs ROOT/usr/libexec/mlnixos-chroot (a plain copy of this program, which only exits) with that directory as
 * its working directory and DYLD_SHARED_CACHE_DIR=.: that dyld maps the REAL cache files into ROOT's shared region, and
 * every later process in ROOT finds them there (dyld's reuseExistingCache needs no cache directory).  The region
 * outlives its last user by 120 s (shared_region_destroy_delay), long enough for CMD to take it.  Only that first
 * program sees the directory; CMD gets no descriptor, and needs no DYLD_ variable at all.  Should that fail, and ROOT
 * holds a copy of the cache at /System/Library/dyld, the helper falls back to DYLD_SHARED_REGION=private: each process
 * maps the copy itself (measured outside a chroot: 0.14 s per process start against 0.01 s).  MLNIXOS_CACHE=shared|private
 * picks one.
 *
 * Host names: macOS resolves them through mDNSResponder's socket, /var/run/mDNSResponder, which a chrooted process
 * looks for inside ROOT (measured: curl says "Could not resolve host" when only that socket is denied).  So before it
 * enters ROOT the helper leaves a process outside, as the caller and not a child of CMD: a SOCKS5 proxy on 127.0.0.1
 * that resolves and connects on the chroot's behalf, and exits when CMD does.  The environment says
 * all_proxy=socks5h://127.0.0.1:PORT; nixpkgs gives all_proxy to fixed-output derivations (lib.fetchers
 * .proxyImpureEnvVars), and mlnix passes a fixed-output derivation's impureEnvVars on, so every fetch goes through it.
 * Other local users could use the proxy while it runs.  Mach services stay reachable, and the network is not isolated.
 */
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <limits.h>
#include <netdb.h>
#include <netinet/in.h>
#include <poll.h>
#include <pwd.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/event.h>
#include <sys/mount.h>
#include <sys/param.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;
/* The shared region's base address, 0 on success; what dyld's reuseExistingCache asks (libsystem_kernel exports it under
 * this name; the SDK's mach/shared_region.h declares a shared_region_check_np that nothing exports). */
extern int __shared_region_check_np(uint64_t *startaddress);

static int fail(const char *what) {
  fprintf(stderr, "mlnixos-chroot: %s: %s\n", what, strerror(errno));
  return 1;
}

/* Close every descriptor above 2 except `keep` (-1: none). */
static void close_others(int keep) {
  int n = getdtablesize();
  for (int fd = 3; fd < n; fd++)
    if (fd != keep) close(fd);
}

/* ---- the proxy: SOCKS5 (RFC 1928), CONNECT only, no authentication ---- */

static int readn(int fd, void *buf, size_t n) {
  for (size_t got = 0; got < n;) {
    ssize_t r = read(fd, (char *)buf + got, n - got);
    if (r < 0 && errno == EINTR) continue;
    if (r <= 0) return -1;
    got += (size_t)r;
  }
  return 0;
}

static int writen(int fd, const void *buf, size_t n) {
  for (size_t put = 0; put < n;) {
    ssize_t r = write(fd, (const char *)buf + put, n - put);
    if (r < 0 && errno == EINTR) continue;
    if (r <= 0) return -1;
    put += (size_t)r;
  }
  return 0;
}

static int socks_reply(int c, unsigned char code) {
  unsigned char r[10] = {5, code, 0, 1, 0, 0, 0, 0, 0, 0};
  return writen(c, r, sizeof r);
}

/* Bytes both ways until both directions have ended; the end of one is passed on as a half-close. */
static void relay(int a, int b) {
  static char buf[65536];
  int up = 1, down = 1; /* a -> b, b -> a */
  while (up || down) {
    struct pollfd p[2] = {{a, (short)(up ? POLLIN : 0), 0}, {b, (short)(down ? POLLIN : 0), 0}};
    if (poll(p, 2, -1) < 0) {
      if (errno == EINTR) continue;
      return;
    }
    if (up && p[0].revents) {
      ssize_t r = read(a, buf, sizeof buf);
      if (r < 0 && errno == EINTR) continue;
      if (r <= 0) {
        up = 0;
        shutdown(b, SHUT_WR);
      } else if (writen(b, buf, (size_t)r)) return;
    }
    if (down && p[1].revents) {
      ssize_t r = read(b, buf, sizeof buf);
      if (r < 0 && errno == EINTR) continue;
      if (r <= 0) {
        down = 0;
        shutdown(a, SHUT_WR);
      } else if (writen(a, buf, (size_t)r)) return;
    }
  }
}

static void socks_session(int c) {
  unsigned char b[262];
  char host[256], port[8];
  if (readn(c, b, 2) || b[0] != 5 || readn(c, b + 2, b[1])) return;
  if (!memchr(b + 2, 0, b[1])) { /* "no authentication" was not offered */
    writen(c, "\x05\xff", 2);
    return;
  }
  if (writen(c, "\x05\x00", 2) || readn(c, b, 4) || b[0] != 5) return;
  int cmd = b[1], atyp = b[3], numeric = 1;
  if (atyp == 1) {
    if (readn(c, b, 4)) return;
    inet_ntop(AF_INET, b, host, sizeof host);
  } else if (atyp == 4) {
    if (readn(c, b, 16)) return;
    inet_ntop(AF_INET6, b, host, sizeof host);
  } else if (atyp == 3) {
    if (readn(c, b, 1) || readn(c, host, b[0])) return;
    host[b[0]] = 0;
    numeric = 0;
  } else {
    socks_reply(c, 8); /* address type not supported */
    return;
  }
  if (readn(c, b, 2)) return;
  snprintf(port, sizeof port, "%u", (unsigned)(b[0] << 8 | b[1]));
  if (cmd != 1) {
    socks_reply(c, 7); /* command not supported */
    return;
  }
  struct addrinfo hints, *res, *ai;
  memset(&hints, 0, sizeof hints);
  hints.ai_socktype = SOCK_STREAM;
  hints.ai_flags = numeric ? AI_NUMERICHOST : AI_ADDRCONFIG;
  if (getaddrinfo(host, port, &hints, &res) != 0) {
    socks_reply(c, 4); /* host unreachable */
    return;
  }
  int s = -1;
  for (ai = res; ai && s < 0; ai = ai->ai_next) {
    s = socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);
    if (s >= 0 && connect(s, ai->ai_addr, ai->ai_addrlen) != 0) {
      close(s);
      s = -1;
    }
  }
  freeaddrinfo(res);
  if (s < 0) {
    socks_reply(c, 5); /* connection refused */
    return;
  }
  if (socks_reply(c, 0) == 0) relay(c, s);
  close(s);
}

/* A listening socket on 127.0.0.1 and an ephemeral port. */
static int socks_listen(unsigned *port) {
  int s = socket(AF_INET, SOCK_STREAM, 0);
  struct sockaddr_in a;
  socklen_t n = sizeof a;
  memset(&a, 0, sizeof a);
  a.sin_len = sizeof a;
  a.sin_family = AF_INET;
  a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  if (s < 0 || bind(s, (struct sockaddr *)&a, sizeof a) || listen(s, 64) || getsockname(s, (struct sockaddr *)&a, &n)) {
    if (s >= 0) close(s);
    return -1;
  }
  fcntl(s, F_SETFD, FD_CLOEXEC);
  *port = ntohs(a.sin_port);
  return s;
}

/* Accept until process `watch` exits (NOTE_EXIT needs no permission: kern_event.c filt_procattach), one forked
 * handler per connection. */
static void socks_serve(int ls, pid_t watch) {
  signal(SIGCHLD, SIG_IGN); /* the kernel reaps the handlers */
  signal(SIGPIPE, SIG_IGN);
  int kq = kqueue();
  struct kevent ev[2];
  EV_SET(&ev[0], ls, EVFILT_READ, EV_ADD, 0, 0, NULL);
  EV_SET(&ev[1], watch, EVFILT_PROC, EV_ADD, NOTE_EXIT, 0, NULL);
  if (kq < 0 || kevent(kq, ev, 2, NULL, 0, NULL) < 0) _exit(0); /* `watch` is gone already */
  for (;;) {
    struct kevent got;
    if (kevent(kq, NULL, 0, &got, 1, NULL) < 0) {
      if (errno == EINTR) continue;
      _exit(1);
    }
    if (got.filter == EVFILT_PROC) _exit(0);
    int c = accept(ls, NULL, NULL);
    if (c < 0) continue;
    if (fork() == 0) {
      close(ls);
      socks_session(c);
      _exit(0);
    }
    close(c);
  }
}

/* ---- the chroot ---- */

static int drop_root(uid_t uid, gid_t gid) {
  if (setgid(gid) != 0 || setuid(uid) != 0) return -1;
  if (uid != 0 && (setuid(0) == 0 || seteuid(0) == 0)) return -1; /* root could be regained */
  return 0;
}

/* Fill ROOT's shared region from the real cache directory `cfd`: run the populator inside ROOT, as the caller, with
 * that directory as its working directory (outside ROOT; DYLD_SHARED_CACHE_DIR=. names it).  0 when it ran, so its
 * dyld found or mapped the cache; else -1. */
static int populate(int cfd, uid_t uid, gid_t gid) {
  struct stat st;
  if (lstat("/usr/libexec/mlnixos-chroot", &st) != 0) return -1;
  pid_t p = fork();
  if (p < 0) return -1;
  if (p == 0) {
    if (drop_root(uid, gid) != 0 || fchdir(cfd) != 0) _exit(126);
    close_others(-1);
    int null = open("/dev/null", O_RDWR);
    if (null >= 0) dup2(null, 1), dup2(null, 2); /* a dyld that fails says so; the helper reports it once */
    char *args[] = {"mlnixos-chroot", "--populate", NULL}, *env[] = {"DYLD_SHARED_CACHE_DIR=.", NULL};
    execve("/usr/libexec/mlnixos-chroot", args, env);
    _exit(127);
  }
  int status;
  while (waitpid(p, &status, 0) < 0 && errno == EINTR) {}
  return WIFEXITED(status) && WEXITSTATUS(status) == 0 ? 0 : -1;
}

/* The environment a chrooted program starts with: a fixed base, then the caller's NIX_*, MLNIX_* and TERM. */
static char **fresh_env(const char *home, const char *user, unsigned port, int privateCache) {
  static char *env[256];
  static char homev[PATH_MAX + 8], userv[300], proxy[64], PROXY[64];
  int n = 0;
  snprintf(homev, sizeof homev, "HOME=%s", home);
  snprintf(userv, sizeof userv, "USER=%s", user);
  snprintf(proxy, sizeof proxy, "all_proxy=socks5h://127.0.0.1:%u", port);
  snprintf(PROXY, sizeof PROXY, "ALL_PROXY=socks5h://127.0.0.1:%u", port);
  env[n++] = "PATH=/bin";
  env[n++] = homev;
  env[n++] = userv;
  env[n++] = "TMPDIR=/tmp";
  env[n++] = privateCache ? "MLNIXOS_CACHE=private" : "MLNIXOS_CACHE=shared";
  if (privateCache) env[n++] = "DYLD_SHARED_REGION=private";
  env[n++] = "NIX_PATH=nixpkgs=/src/nixpkgs";
  env[n++] = "MLNIX_STATE_DIR=/nix/var/mlnix";
  env[n++] = proxy;
  env[n++] = PROXY;
  for (char **e = environ; *e && n < 254; e++)
    if (!strncmp(*e, "NIX_", 4) || !strncmp(*e, "MLNIX_", 6) || !strncmp(*e, "TERM=", 5)) env[n++] = *e;
  env[n] = NULL;
  return env;
}

int main(int argc, char **argv) {
  if (argc == 2 && !strcmp(argv[1], "--populate")) { /* dyld got here with a cache; is it in the shared region? */
    uint64_t base = 0;
    return __shared_region_check_np(&base) == 0 && base != 0 ? 0 : 3;
  }
  uid_t uid = getuid();
  gid_t gid = getgid();
  unsigned port = 0;
  if (argc == 2 && !strcmp(argv[1], "--proxy")) { /* the proxy alone: give up any setuid privilege first */
    if (setgid(gid) != 0 || setuid(uid) != 0) return fail("setuid");
    int ls = socks_listen(&port);
    if (ls < 0) return fail("proxy socket");
    printf("%u\n", port);
    fflush(stdout);
    socks_serve(ls, getppid());
  }
  int release = argc == 3 && !strcmp(argv[1], "--release");
  if (argc < 3) {
    fprintf(stderr, "usage: mlnixos-chroot ROOT CMD [ARG...]\n       mlnixos-chroot --release ROOT\n"
                    "       mlnixos-chroot --proxy\n");
    return 2;
  }
  const char *rootArg = release ? argv[2] : argv[1];
  const char *mode = getenv("MLNIXOS_CACHE"); /* shared, private, or unset: shared, else private */
  struct passwd *pw = getpwuid(uid);
  if (!pw) return fail("getpwuid");
  char user[256];
  snprintf(user, sizeof user, "%s", pw->pw_name);
  int setuidRoot = geteuid() == 0;

  /* Open and check ROOT, open the real cache directory, and make the proxy's socket, with the caller's own rights. */
  if (setuidRoot && seteuid(uid) != 0) return fail("seteuid");
  int rfd = open(rootArg, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  if (rfd < 0) return fail(rootArg);
  struct stat st;
  struct statfs sfs;
  if (fstat(rfd, &st) != 0 || fstatfs(rfd, &sfs) != 0) return fail(rootArg);
  if (st.st_uid != uid || (st.st_mode & (S_IWGRP | S_IWOTH))) {
    fprintf(stderr, "mlnixos-chroot: %s must be a directory owned by you and writable by no one else\n", rootArg);
    return 1;
  }
  if (!(sfs.f_flags & MNT_NOSUID)) {
    fprintf(stderr, "mlnixos-chroot: %s is on %s, which is not mounted nosuid (attach a disk image there: mkroot.sh)\n",
            rootArg, sfs.f_mntonname);
    return 1;
  }
  int cfd = -1, ls = -1;
  if (!release && !(mode && !strcmp(mode, "private"))) {
    cfd = open("/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld", O_RDONLY | O_DIRECTORY);
    if (cfd < 0) cfd = open("/System/Library/dyld", O_RDONLY | O_DIRECTORY);
  }
  if (!release && (ls = socks_listen(&port)) < 0) return fail("proxy socket");
  if (!setuidRoot) {
    fprintf(stderr, "mlnixos-chroot: not setuid root; install it once with\n"
                    "  sudo install -o root -g wheel -m 4755 %s /usr/local/sbin/mlnixos-chroot\n", argv[0]);
    return 1;
  }
  if (seteuid(0) != 0) return fail("seteuid 0");

  if (release) { /* unmount ROOT/dev if a devfs is mounted there */
    char dev[PATH_MAX];
    if (fcntl(rfd, F_GETPATH, dev) == -1) return fail("F_GETPATH");
    strlcat(dev, "/dev", sizeof dev);
    struct statfs dfs;
    if (statfs(dev, &dfs) == 0 && !strcmp(dfs.f_fstypename, "devfs") && !strcmp(dfs.f_mntonname, dev)) {
      if (unmount(dev, 0) != 0) return fail("unmount");
      printf("unmounted %s\n", dev);
    }
    return 0;
  }

  /* The proxy: a grandchild, so that CMD has no child it did not make; outside ROOT; root dropped for good before it
   * reads a byte from the network. */
  pid_t self = getpid();
  pid_t k = fork();
  if (k < 0) return fail("fork");
  if (k == 0) {
    if (initgroups(user, (int)gid) != 0 || drop_root(uid, gid) != 0) _exit(1);
    close_others(ls);
    if (fork() == 0) socks_serve(ls, self);
    _exit(0);
  }
  waitpid(k, NULL, 0);
  close(ls);

  if (initgroups(user, (int)gid) != 0) return fail("initgroups");
  if (fchdir(rfd) != 0) return fail("fchdir");
  if (chroot(".") != 0) return fail("chroot");
  if (chdir("/") != 0) return fail("chdir /");
  close(rfd);
  if (lstat("/dev/null", &st) != 0 && mount("devfs", "/dev", MNT_NOSUID | MNT_NOEXEC, NULL) != 0)
    return fail("mount devfs on /dev");

  /* The cache: ROOT's shared region from the real files, else each process maps ROOT's copy. */
  int privateCache = 1;
  if (cfd >= 0 && populate(cfd, uid, gid) == 0) privateCache = 0;
  if (cfd >= 0) close(cfd);
  if (privateCache) {
    if (mode && !strcmp(mode, "shared")) {
      fprintf(stderr, "mlnixos-chroot: the shared cache could not be mapped into %s (MLNIXOS_CACHE=shared)\n", rootArg);
      return 1;
    }
    if (lstat("/System/Library/dyld/dyld_shared_cache_arm64e", &st) != 0 && stat("/System/Library/dyld/dyld_shared_cache_arm64e", &st) != 0) {
      fprintf(stderr, "mlnixos-chroot: the shared cache could not be mapped into %s, and it holds no copy at "
                      "/System/Library/dyld for DYLD_SHARED_REGION=private\n", rootArg);
      return 1;
    }
    if (!mode) fprintf(stderr, "mlnixos-chroot: the shared cache could not be mapped into %s; each process maps the copy\n", rootArg);
  }

  /* Drop root for good; then make sure it cannot come back. */
  if (drop_root(uid, gid) != 0) {
    fprintf(stderr, "mlnixos-chroot: could not drop root for good; refusing\n");
    return 1;
  }
  close_others(-1);

  char home[PATH_MAX];
  snprintf(home, sizeof home, "/home/%s", user);
  if (lstat(home, &st) != 0) snprintf(home, sizeof home, "/tmp");
  execve(argv[2], argv + 2, fresh_env(home, user, port, privateCache));
  return fail(argv[2]);
}
