# IPNS demo: two builds of mlnix, one per host, each under its own name

The Mac and Kali build the same sources separately. Each host publishes its build under its own IPNS name: the binaries and a
`manifest.json` that says what the build is and what it did. Each host resolves the other's name, fetches the content and
checks it.

## The nodes

The breadcrumbs hive (`~/work/breadcrumbs/docs/HIVE.md`) runs one kubo node per host in a private swarm (`swarm.key`), with
`Routing.Type none`. There, a name published on one host is never found on another. The demo runs a second node on each host
(`scripts/ipns-demo/node.sh`), and the hive nodes are not touched:

| | Mac | Kali |
|---|---|---|
| repo | `~/.cache/bc-coop/ipfs-demo-mac` | `~/.cache/bc-coop/ipfs-demo-kali` |
| swarm, API, gateway | 4012, 5012, 8092 | 4032, 5032, 8094 |
| peer id | 12D3KooWFan9TMYbusCGRxehGeG5ZDNRJrJGQRJaNGEDBwFYrLzn | 12D3KooWQTsn2PRdW9AxNTSg6idcnR1SSkaP2WeJuHdWJGH3mRDg |
| IPNS name (key `mlnix-HOST`) | k51qzi5uqu5di97320tuvhu8p40ae22s56k938futfhlxqjwdu7m5p17j4abkd | k51qzi5uqu5dkhfrm0ehx3dmifbk1piwxkocetdr8s13nk0yrv0t7fcm4ud8f4 |

Each node:

- uses the hive's `swarm.key`, so only hive members can connect;
- uses no bootstrap and no mDNS, and keeps the other host connected through `Peering.Peers`;
- runs a DHT among its peers only (`dhtserver`), and IPNS over pubsub.

```
sh scripts/ipns-demo/node.sh init mac 4012 5012 8092
sh scripts/ipns-demo/node.sh peer mac /ip4/192.168.50.44/tcp/4032/p2p/<kali id>
sh scripts/ipns-demo/node.sh start mac            # stop: sh scripts/ipns-demo/node.sh stop mac
sh scripts/ipns-demo/publish.sh mac               # build/bin + manifest.json -> /ipfs/CID -> /ipns/<mlnix-mac>
sh scripts/ipns-demo/verify.sh mac <kali name> kali
```

To stop a demo node, run `node.sh stop HOST`. It stops the daemon of that one repo. Do not use pkill: the hive's daemon
is also an `ipfs daemon`.

## What a manifest holds

- The platform, the compiler, and the C++ library mlnix links (`otool -L` or `ldd`).
- The LLVM/MLIR that the build used.
- The sha256 of the sources: lib, include, tools and the top CMakeLists.txt, 93 files.
- The sha256 and size of each binary.
- The gates run on that host.
- sumo-nix's full ontology (`scripts/ipns-demo/onto.nix`: all 78 files, then sumo.nix forced): the answer, its time, and its
  peak memory. Peak memory is measured on Kali only, in a 12 GB cgroup with no swap.

## Run of 8 Nov 2026

| | Mac | Kali |
|---|---|---|
| platform | macOS 15.8.2 arm64 | Kali Rolling x86_64 (WSL2) |
| compiler, C++ library | Apple clang 17.0.0, libc++ | Debian clang 22.1.8, libstdc++ |
| sources | ef3b199a31fe… (93 files) | ef3b199a31fe… (the same) |
| mlnix sha256 | 3ef688a0301f… | 0eea653a8825… |
| lang (both schedules), primops | 488/488, 105/105 | 488/488, 105/105 |
| sumo-full ontology | 0.94 s (memory not measured) | 1.76 s, 902 MB |
| answer | 201,007 forms, 9,045 classes, 90,404 ancestor links | the same |

`verify.sh` passes in both directions:

- the name resolves in 0.04–0.05 s;
- the three fetched binaries have the sha256 that the manifest gives;
- the sources are the same, and the binaries differ;
- the sumo answers are equal.

When the Mac publishes again, Kali resolves the new record on its first try (within 5 s).
