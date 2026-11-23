/* mlnixos-chroot: chroot isolation for darwin, the simple kind.
 *
 *   mlnixos-chroot ROOT CMD [ARG...]      run CMD (a path inside ROOT) with ROOT as "/"
 *   mlnixos-chroot --release ROOT         unmount ROOT/dev (before detaching ROOT's disk image)
 *
 * chroot(2) needs root on macOS, so this is installed setuid root, once:
 *   sudo install -o root -g wheel -m 4755 mlnixos-chroot /usr/local/sbin/mlnixos-chroot
 * As root it sets the caller's groups, then chroot(ROOT), chdir("/"), and mounts devfs (nosuid, noexec) on /dev when
 * /dev/null is missing.  Then it drops to the caller's uid and gid for good, checks that root cannot be regained, and
 * execs CMD with a fresh environment.
 *
 * ROOT must be a directory the caller owns, writable by no one else, on a file system mounted nosuid: a disk image the
 * caller attached (mkroot.sh makes one; macOS mounts a user's images nosuid and nodev).  nosuid is what makes a setuid
 * chroot safe here: in a chroot the kernel loads /usr/lib/dyld from ROOT, and macOS takes any signed dyld there
 * (CONFIG_ENFORCE_SIGNED_CODE is off on macOS), so a setuid-root program hard-linked into a suid-honouring ROOT would run
 * the caller's dyld as root.  ROOT is opened once and checked through that descriptor, and the chroot is made through
 * it too, so the directory checked is the one entered.
 *
 * Inside, ROOT is "/" and the store is /nix/store.  macOS refuses static arm64 executables (mach_loader.c), so every
 * program goes through ROOT/usr/lib/dyld, a copy of Apple's dyld; libSystem exists only in the dyld shared cache, of
 * which ROOT holds a copy.  A chrooted process gets a shared region of its own (vm_shared_region.c), and with SIP on the
 * kernel maps only SIP-protected cache files into one (vm_unix.c: SF_RESTRICTED), which a copy can never be; so the
 * environment says DYLD_SHARED_REGION=private, and dyld maps the copy into each process instead (measured: 0.14 s per
 * process start against 0.01 s).  Mach services stay reachable and the network is not isolated.
 */
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <limits.h>
#include <pwd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/param.h>
#include <sys/stat.h>
#include <unistd.h>

extern char **environ;

static int fail(const char *what) {
  fprintf(stderr, "mlnixos-chroot: %s: %s\n", what, strerror(errno));
  return 1;
}

/* The environment a chrooted program starts with: a fixed base, then the caller's NIX_*, MLNIX_* and TERM. */
static char **fresh_env(const char *home, const char *user) {
  static char *env[256];
  static char homev[PATH_MAX + 8], userv[300];
  int n = 0;
  snprintf(homev, sizeof homev, "HOME=%s", home);
  snprintf(userv, sizeof userv, "USER=%s", user);
  env[n++] = "PATH=/bin";
  env[n++] = homev;
  env[n++] = userv;
  env[n++] = "TMPDIR=/tmp";
  env[n++] = "DYLD_SHARED_REGION=private";
  env[n++] = "NIX_PATH=nixpkgs=/src/nixpkgs";
  env[n++] = "MLNIX_STATE_DIR=/nix/var/mlnix";
  for (char **e = environ; *e && n < 254; e++)
    if (!strncmp(*e, "NIX_", 4) || !strncmp(*e, "MLNIX_", 6) || !strncmp(*e, "TERM=", 5)) env[n++] = *e;
  env[n] = NULL;
  return env;
}

int main(int argc, char **argv) {
  int release = argc == 3 && !strcmp(argv[1], "--release");
  if (argc < 3) {
    fprintf(stderr, "usage: mlnixos-chroot ROOT CMD [ARG...]\n       mlnixos-chroot --release ROOT\n");
    return 2;
  }
  const char *rootArg = release ? argv[2] : argv[1];
  uid_t uid = getuid();
  gid_t gid = getgid();
  struct passwd *pw = getpwuid(uid);
  if (!pw) return fail("getpwuid");
  char user[256];
  snprintf(user, sizeof user, "%s", pw->pw_name);
  int setuidRoot = geteuid() == 0;

  /* Open and check ROOT with the caller's own rights, not root's. */
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
  if (!setuidRoot) {
    fprintf(stderr, "mlnixos-chroot: not setuid root; install it once with\n"
                    "  sudo install -o root -g wheel -m 4755 %s /usr/local/sbin/mlnixos-chroot\n", argv[0]);
    return 1;
  }
  if (seteuid(0) != 0) return fail("seteuid 0");

  if (release) {  /* unmount ROOT/dev if a devfs is mounted there */
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

  if (initgroups(user, (int)gid) != 0) return fail("initgroups");
  if (fchdir(rfd) != 0) return fail("fchdir");
  if (chroot(".") != 0) return fail("chroot");
  if (chdir("/") != 0) return fail("chdir /");
  close(rfd);
  if (lstat("/dev/null", &st) != 0 && mount("devfs", "/dev", MNT_NOSUID | MNT_NOEXEC, NULL) != 0)
    return fail("mount devfs on /dev");

  /* Drop root for good; then make sure it cannot come back. */
  if (setgid(gid) != 0) return fail("setgid");
  if (setuid(uid) != 0) return fail("setuid");
  if (uid != 0 && (setuid(0) == 0 || seteuid(0) == 0)) {
    fprintf(stderr, "mlnixos-chroot: root could be regained; refusing\n");
    return 1;
  }

  char home[PATH_MAX];
  snprintf(home, sizeof home, "/home/%s", user);
  if (lstat(home, &st) != 0) snprintf(home, sizeof home, "/tmp");
  execve(argv[2], argv + 2, fresh_env(home, user));
  return fail(argv[2]);
}
