#!/bin/bash
# The cross toolchain's first proof: C and C++ programs built in mlnix-os for arm64 macOS, written where the Mac sees them.
#   hello.sh OUT_DIR_ON_USERS
set -euo pipefail
O=$1; mkdir -p "$O"
SDK=${DARWIN_SDK:-$HOME/darwin-cross/sdk/MacOSX15.2.sdk}
L=/usr/lib/llvm-22/bin
T="--target=arm64-apple-macos13.0 -isysroot $SDK -fuse-ld=lld"
cat > "$O/hello.c" <<'EOF'
#include <stdio.h>
#include <sys/utsname.h>
int main(void) { struct utsname u; uname(&u); printf("hello from Linux-built C on %s %s %s\n", u.sysname, u.release, u.machine); return 0; }
EOF
cat > "$O/hello.cpp" <<'EOF'
#include <iostream>
#include <map>
#include <string>
#include <stdexcept>
int main() {
  std::map<std::string, int> m{{"libc++", 1}, {"exceptions", 2}};
  try { throw std::runtime_error("caught"); } catch (const std::exception &e) { std::cout << "C++ " << e.what() << ", map size " << m.size() << "\n"; }
  return 0;
}
EOF
$L/clang $T -O2 "$O/hello.c" -o "$O/hello-c"
$L/clang++ $T -O2 -std=c++20 "$O/hello.cpp" -o "$O/hello-cpp"
file "$O/hello-c" "$O/hello-cpp" 2>/dev/null || true
$L/llvm-otool -L "$O/hello-cpp"
$L/llvm-objdump --macho --private-headers "$O/hello-c" | grep -A3 -E 'LC_CODE_SIGNATURE|LC_BUILD_VERSION' | head -12
