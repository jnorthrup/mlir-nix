# mlnixos-darwin: a chroot on macOS holding the minimum needed to run darwin programs, built from Linux

A real `chroot(2)` on the Mac. Its `/` holds, of macOS, only a copy of dyld. Everything else in it is an mlnix
cross-built on Linux and nixpkgs' darwin bootstrap at its own store path, `/nix/store`. No Homebrew, no Xcode, no
Apple programs.

## The minimum, and why it is what it is

All of this is from Apple's sources (xnu-12377.1.9, dyld main) and was measured on macOS 27.2 (arm64, SIP on):

- **The kernel refuses static arm64 executables** (`bsd/kern/mach_loader.c`: "Check properties of static
  executables (disallowed except for development)"). Every native program therefore goes through a dynamic linker.
- **The dynamic linker must be `/usr/lib/dyld`** (release kernels refuse any other `LC_LOAD_DYLINKER`), but the
  kernel looks that path up from the process's root, so in a chroot it is `ROOT/usr/lib/dyld`. It need not be a
  platform binary: `CONFIG_ENFORCE_SIGNED_CODE` is off in `config/MASTER.arm64.MacOSX`.
- **libSystem, libc++ and the frameworks exist only in the dyld shared cache.** A process exec'd in a chroot gets a
  shared region of its own (`osfmk/vm/vm_shared_region.c`), which its dyld fills from cache files it opens. With SIP on,
  the kernel takes only SIP-protected cache files (`bsd/vm/vm_unix.c`: the file must carry `SF_RESTRICTED`), so no
  copy will do. It does not care where they are: on arm64 the expected-directory check is off (`scdir_enforce = 0`).
- **So the helper hands in the real cache.** It opens the real cache directory before entering ROOT. Then it runs, in
  ROOT, a plain copy of itself (`/usr/libexec/mlnixos-chroot`, which only exits) with
  `DYLD_SHARED_CACHE_DIR=/dev/fd/N`. That dyld maps the real files into ROOT's shared region. Every later process in
  ROOT finds them there, with no descriptor and no `DYLD_*` variable, and the region outlives its last user by 120 s
  (`shared_region_destroy_delay`).
- **Fallback.** If that mapping fails, and ROOT holds a copy of the cache (`CACHE_COPY=1 mkroot.sh`, 82 files,
  6.7 GB), the helper sets `DYLD_SHARED_REGION=private`, and each process maps the copy itself. Measured outside a
  chroot: hello (C and C++), mlnix and the seed's bash run that way, at 0.14 s per process start instead of 0.01 s.
  mlnix passes the variable on to every builder (`lib/Store/LocalStore.cpp`).
- **Apple's own programs are no use inside.** A copy of a platform binary is killed at exec (launch constraints), so
  `/bin/sh` is the seed's bash.
- **Host names.** macOS resolves them through mDNSResponder's socket, `/var/run/mDNSResponder`, which a chrooted
  process looks for inside ROOT. With only that socket denied (`sandbox-exec`), curl says "Could not resolve host".
  The helper therefore leaves a SOCKS5 proxy outside, running as you on 127.0.0.1, and sets
  `all_proxy=socks5h://...`. nixpkgs passes `all_proxy` to fixed-output derivations (`lib.fetchers.proxyImpureEnvVars`).
  Measured with that socket denied, through the proxy: http, https, a GNU mirror redirect and a GitHub archive.

That leaves a copy of `/usr/lib/dyld` (4 MB) and `/dev` as the only things of macOS in ROOT. Below that would be our
own dyld and our own libSystem: the kernel would take them, but nixpkgs' darwin programs need Apple's libSystem ABI.

## Isolation

- **`mlnixos-chroot ROOT CMD`** (`mlnixos-chroot.c`): installed setuid root.
  - As you: it opens ROOT and checks owner, mode and nosuid through that descriptor; opens the real cache directory;
    makes the proxy's socket.
  - As root: it sets your groups; `chroot`s through the descriptor; mounts devfs (nosuid, noexec) on `/dev`.
  - The proxy and the cache populator each drop to your uid before they do anything.
  - Then it drops to your uid and gid for good, closes every descriptor above 2, and execs CMD with a fresh environment.
- **ROOT must be on a nosuid file system:** a disk image you attached (`mkroot.sh` makes a sparse APFS one; macOS
  mounts a user's images nosuid and nodev). Without nosuid, a setuid-root program hard-linked into ROOT would start
  under your dyld, as root. The helper refuses any other ROOT.
- **What it does not isolate:** the network (and other local users can use the proxy while it runs), Mach services,
  and the user (builds run as you).

## Steps

On Linux (mlnix-os: Debian trixie arm64, LLVM 22; `apt install lld-22 libarchive-tools cpio xz-utils`):

    bash sdk.sh ~/darwin-cross/sdk                  # macOS SDK 15.2, NAR hash = nixpkgs' pin
    bash llvm-src.sh ~/darwin-cross/src             # LLVM 22.1.8, signature checked
    bash llvm-darwin.sh ~/darwin-cross 10           # LLVM + MLIR for arm64 macOS, static: 29 minutes
    bash mlnix-darwin.sh ~/darwin-cross SRC LINUX_BIN OUT   # mlnix for macOS (SRC: git archive; LINUX_BIN: same commit's
                                                    # Linux build, whose mlnix-opt lowers the .mlir at build time)
    bash seed.sh NIXPKGS SEED_DIR                   # the bootstrap seed, = nixpkgs' pins
    clang --target=arm64-apple-macos13.0 -isysroot SDK -fuse-ld=lld -O2 mlnixos-chroot.c -o mlnixos-chroot

On the Mac (BIN, SEED and HELPER default to ~/.local/share/mlnixos-darwin/{bin,seed,mlnixos-chroot}):

    bash mkroot.sh /Users/jim/mlnixos-chroot        # image, dyld, the populator, mlnix, nixpkgs, seed
    sudo install -o root -g wheel -m 4755 mlnixos-chroot /usr/local/sbin/mlnixos-chroot   # once
    bash chroot-boot2.sh /Users/jim/mlnixos-chroot ORACLE stage1 hello

`chroot-boot2.sh`:

1. Checks the 8 stdenv stages' derivations against Nix 2.28.4's on mlnixos (`oracle-mlnixos.sh`).
2. Imports the seed, and reports which way the cache reached the chroot.
3. Builds `bootstrapTools`, then fetches through the proxy with its curl.
4. Builds each attribute of `boot.nix`.
5. Compares every output it built with Hydra's NAR hash on cache.nixos.org. The store is `/nix/store`, so the store
   paths are Hydra's.

A source whose upstream URL has rotted is fetched by hash with `fod-rescue.sh`. `proxy-test.sh HELPER CURL` checks
the proxy without root, with `nouds.sb` denying only the mDNSResponder socket.
