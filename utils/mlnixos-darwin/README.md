# mlnixos-darwin: a chroot on macOS holding the minimum needed to run darwin programs, built from Linux

A real `chroot(2)` on the Mac whose `/` holds almost nothing of macOS, an mlnix cross-built on Linux, and nixpkgs'
darwin bootstrap at its own store path, `/nix/store`. No Homebrew, no Xcode, no Apple programs.

## The minimum, and why it is what it is

All of this is from Apple's sources (xnu-12377.1.9, dyld main) and was measured on macOS 27.2 (arm64, SIP on):

- **The kernel refuses static arm64 executables** (`bsd/kern/mach_loader.c`: "Check properties of static
  executables (disallowed except for development)"). Every native program therefore goes through a dynamic linker.
- **The dynamic linker must be `/usr/lib/dyld`** (release kernels refuse any other `LC_LOAD_DYLINKER`), but the
  kernel looks that path up from the process's root, so in a chroot it is `ROOT/usr/lib/dyld`. It need not be a
  platform binary: `CONFIG_ENFORCE_SIGNED_CODE` is off in `config/MASTER.arm64.MacOSX`.
- **libSystem, libc++ and the frameworks exist only in the dyld shared cache.** ROOT holds a copy of dyld and of
  the arm64e cache (82 files, 6.7 GB).
- **A chrooted process gets a shared region of its own** (`osfmk/vm/vm_shared_region.c`). With SIP on, the kernel
  maps only SIP-protected cache files into one (`bsd/vm/vm_unix.c`: the file must carry `SF_RESTRICTED`), and a
  copy cannot carry that flag. So the kernel path is closed.
- **dyld can map the cache into the process itself** (`DYLD_SHARED_REGION=private`). AMFI allows it here for any
  program that is not a platform binary. Measured outside a chroot, on a jim-owned copy of the cache: hello (C and C++) and mlnix run,
  and a process start costs 0.14 s instead of 0.01 s. `mlnixos-chroot` sets the variable, and mlnix passes it on to
  every builder (`lib/Store/LocalStore.cpp`).
- **Apple's own programs are no use inside.** They are platform binaries, for which dyld ignores `DYLD_*`, so they
  cannot load libSystem in the chroot. `/bin/sh` is therefore the seed's bash.

That leaves `/usr/lib/dyld`, the cache and `/dev` as the only things of macOS in ROOT. Below that would be our own
dyld and our own libSystem: the kernel would take them, but nixpkgs' darwin programs need Apple's libSystem ABI.

## Isolation

- **`mlnixos-chroot ROOT CMD`** (`mlnixos-chroot.c`): setuid root, about 140 lines of C. As root it does only these:
  - sets your groups;
  - `chroot`s into ROOT, through a descriptor that was checked as you;
  - mounts devfs (nosuid, noexec) on `/dev`.

  Then it drops to your uid and gid for good and execs CMD with a fresh environment.
- **ROOT must be on a nosuid file system:** a disk image you attached (`mkroot.sh` makes a sparse APFS one; macOS
  mounts a user's images nosuid and nodev). Without nosuid, a setuid-root program hard-linked into ROOT would start
  under your dyld, as root. The helper refuses any other ROOT.
- **What it does not isolate:** the network, Mach services, and the user (builds run as you).

## Steps

On Linux (mlnix-os: Debian trixie arm64, LLVM 22; `apt install lld-22 libarchive-tools cpio xz-utils`):

    bash sdk.sh ~/darwin-cross/sdk                  # macOS SDK 15.2, NAR hash = nixpkgs' pin
    bash llvm-src.sh ~/darwin-cross/src             # LLVM 22.1.8, signature checked
    bash llvm-darwin.sh ~/darwin-cross 10           # LLVM + MLIR for arm64 macOS, static: 29 minutes
    bash mlnix-darwin.sh ~/darwin-cross SRC LINUX_BIN OUT   # mlnix for macOS (SRC: git archive; LINUX_BIN: same commit's
                                                    # Linux build, whose mlnix-opt lowers the .mlir at build time)
    bash seed.sh NIXPKGS SEED_DIR                   # the bootstrap seed, = nixpkgs' pins
    clang --target=arm64-apple-macos13.0 -isysroot SDK -fuse-ld=lld -O2 mlnixos-chroot.c -o mlnixos-chroot

On the Mac:

    bash mkroot.sh /Users/jim/mlnixos-chroot OUT/bin SEED_DIR       # image, dyld, cache, mlnix, nixpkgs, seed
    sudo install -o root -g wheel -m 4755 mlnixos-chroot /usr/local/sbin/mlnixos-chroot   # once
    bash chroot-boot2.sh /Users/jim/mlnixos-chroot ORACLE bootstrapTools stage1 hello

`chroot-boot2.sh`:

1. Checks the 8 stdenv stages' derivations against Nix 2.28.4's on mlnixos (`oracle-mlnixos.sh`).
2. Imports the seed.
3. Builds each attribute of `boot.nix`.
4. Compares every output it built with Hydra's NAR hash on cache.nixos.org. The store is `/nix/store`, so the store
   paths are Hydra's.

A source whose upstream URL has rotted is fetched by hash with `fod-rescue.sh`.
