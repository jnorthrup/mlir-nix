// lib/Corepkgs/substitute.nix against a binary cache that is a directory: a signed narinfo and its NAR, served by
// curl as file://.  A path is fetched when a trusted key signed it, and not when the key is another's.  No network;
// needs an openssl with Ed25519 (the first on PATH).
//
// (RUN lines are rewritten for %s, so nothing below uses printf.)
//
// RUN: unset NIX_REMOTE; d=$(mktemp -d); mkdir -p $d/cache/nar; export MLNIX_STORE_ROOT=$d/src; p=$(env -u NIX_REMOTE mlnix eval --raw --read-write-mode -E 'builtins.toFile "payload" "hi\n"'); h=${p#/nix/store/}; h=${h%%-*}; mlnix store --dump $d/src$p > $d/cache/nar/$h.nar; nh=$(mlnix store --query --hash $p); ns=$(wc -c < $d/cache/nar/$h.nar | tr -d ' '); openssl genpkey -algorithm ed25519 -out $d/k.pem; openssl genpkey -algorithm ed25519 -out $d/other.pem; pub() { openssl pkey -in $1 -pubout -outform DER | tail -c 32 | base64; }; echo -n "1;$p;$nh;$ns;" > $d/fp; openssl pkeyutl -sign -rawin -inkey $d/k.pem -in $d/fp -out $d/sig; { echo "StorePath: $p"; echo "URL: nar/$h.nar"; echo "Compression: none"; echo "NarHash: $nh"; echo "NarSize: $ns"; echo "References: "; echo "Sig: test-1:$(base64 < $d/sig | tr -d '\n')"; } > $d/cache/$h.narinfo; ask() { env -u NIX_REMOTE MLNIX_STORE_ROOT=$d/$1 MLNIX_SUBSTITUTERS=file://$d/cache MLNIX_TRUSTED_KEYS="test-1:$2" mlnix eval --read-write-mode -E "(import <nix/substitute.nix> { }).substitute \"$p\""; }; { echo "OTHER-KEY $(ask dst1 $(pub $d/other.pem))"; echo "TRUSTED $(ask dst2 $(pub $d/k.pem))"; cat $d/dst2$p; } | FileCheck %s
// CHECK: OTHER-KEY false
// CHECK: TRUSTED true
// CHECK: hi
