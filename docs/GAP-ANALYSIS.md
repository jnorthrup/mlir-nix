# Gap analysis: the C++ relegated to MLIR

Asked for as: "continuous recursive gap analysis on the c++ relegation to mlir source code replacements in this project
following PRELOAD.md trikeshed ethos and fill-drain metaphors, using TRIES for cas and the btrfs-compressed heap stores"
(2026-11-27).  The census is `scripts/gap-census.py`; the numbers below are its run at `a8d3ae3`, sealed as that
revision's snapshot.  After every merge: `scripts/gap-census.py --seal`, then `--diff <the previous seal>` shows what
moved, scale by scale.  A gap closes when its row moves; a conversion that moves no row has not closed one.

## The yardstick

1. TrikeShed's PRELOAD.md: Join, Series and Cursor are the algebra; lazy views first, materialisation later; projection
   over mutation; side effects at the boundary.  In MLIR that means trikeshed/confix/kursive ops, not llvm loops over a
   record's fields (the bypass).
2. Fill-drain: a lazy composition (`combine`, `combineAll`, `series`, `slice`) drained once into cells sized ahead.  The
   drain is where a composition stops and cells begin.  A MutableSeries fills by append and drains once.
3. The trie CAS (TrikeShed `cas/CursorTrie.kt`): `HashTrie` keys rows by a digest's leading 8 bytes, one byte of fan-out a
   level, an open leaf filled by append and sealed, sorted by the digest's tail, as one immutable 16 KiB page; `LaneTrie`
   keeps a relation's fixed-width rows in 16 KiB segments with one appender and a published count, so a row never moves
   and a reader takes no lock.  Byte strings with shared prefixes (paths) keep the crit-bit trie (`Composite/Patricia.h`).
4. The heap store (docs/BTRFS-COMPRESSOR.md): clusters (a min-max heap and its pegs) fill and drain in key order, a
   drained block is sorted and emits as deltas into a sealed, compressed page (`BtrfsMetadataCompression`'s envelope);
   the funnel table answers point lookups past a dense window; inside the window a cell is computed, never probed.
   "Anything keyed by a sorted fixed-width tuple (an LSM run, a Nix store index, a CAS page) takes the same layer."

## Scale 0: the repository (`a8d3ae3`)

| measure | value |
|---|---:|
| C++ code lines (`scripts/cxx-lines.py`) | 22,822 |
| product MLIR (lowered/, utils/mlnixci/src): modules, lines, ops | 75, 36,796, 26,511 |
| ops in trikeshed/confix/kursive | 12.8% |
| ops in llvm | 12.8% (the rest: arith, scf, cf, memref, func) |
| functions that drain a composition | 64, 15.6% of the lines |
| GitHub linguist, C++ / MLIR bytes | 1,326,787 (25.6%) / 2,244,918 (43.3%) |

The census counts ops, not types (`!llvm.ptr` is not an llvm op), and a fill-drain function as one holding both a drain
and a combine or combineAll; the skill's ts-census.py and filldrain-census.py count more widely (11.0% with types; 80
functions with returned views).  Compare a census only with itself.

## Scale 1: subsystems

| C++ | code lines | | MLIR | lines | dialect ops | llvm ops | fill-drain lines |
|---|---:|---|---|---:|---:|---:|---:|
| lib/Eval | 4,691 | | lowered/nixeval | 14,510 | 12.3% | 14.6% | 30.0% |
| lib/Store | 1,941 | | lowered/nixstore | 9,139 | 14.5% | 9.3% | 9.0% |
| lib/Frontend | 2,102 | | lowered/nixfrontend | 3,260 | 0.0% | 8.6% | 0.0% |
| | | | lowered/nixfe | 1,037 | 6.8% | 4.2% | 33.0% |
| include/Composite, lib/Composite | 1,926 + 1,502 | | lowered/composite | 1,346 | 6.0% | 13.9% | 0.0% |
| tools | 1,280 | | lowered/tools | 464 | 19.6% | 2.8% | 44.4% |
| (mini-luci's server) | 0 | | utils/mlnixci/src | 6,929 | 18.7% | 17.8% | 0.3% |
| lib/Dialect | 4,998 | | lowered/kursive | 111 | 100% | 0 | 0 |
| include/Nix | 1,851 | | | | | | |
| scripts (*.cc checks) | 2,303 | | | | | | |

The writers are where fill-drain lives (nixeval 30%, nixfe 33%, tools 44%).  The readers (nixfrontend's scanners), the
store's kernels and the Composite ports are not: lowered/composite has no drain at all and 6% dialect ops.

The same C++ by role (scratch gap/cxx-roles.py; 0d02917, 22,817 code lines), which says what the recipe can still move:

| role | code lines | share | what moves it |
|---|---:|---:|---|
| the evaluator (Eval.cpp 2,459, Builtins.cpp 965, StoreBuiltins.cpp 816, Eval.h 703, Formats.cpp 413) | 5,460 | 23.9% | G8: the dispatch, forcing and calls; most of the rest is primop registration and forcing glue around algorithms already in MLIR |
| MLIR dialects, passes, lowering (CursorLowering.cpp 1,172, NixDialect, SonDialect, ConfixDialect, KursiveDialect) | 3,893 | 17.1% | nothing: MLIR's C++ API; a new lowering adds to it |
| KIF / SUMO (KifTptp 998, KifLean 723, KifChase 409, KifTrikeShed 222, SumoDialect 193) | 2,959 | 13.0% | the user's scope decision |
| the store (LocalStore 751, StorePaths 699, Store.h 352, Hash 227, Prefetch 217) | 2,713 | 11.9% | I/O and process glue around MLIR algorithms; G3b may move the index |
| differential checks and benches (confix-check 624, vocab-check 261, cluster-scales 203) | 2,303 | 10.1% | they retire with their subjects |
| the parser (Parser.cpp 1,960) | 2,102 | 9.2% | it builds nix ops through MLIR's builder API; only a grammar in kursive combinators would move it (the user's word, as G6) |
| the Composite vocabulary and bridges (Mutable.h 334, Text.h 273, Table.h 205, CharSeries.h 160) | 1,956 | 8.6% | shrinks as its C++ users go |
| the command-line tools (mlnix.cpp 821, mlnix-parse.cpp 231) | 1,122 | 4.9% | tools2 tried, held back (+20) |

The bridge surface, the extern "C" callbacks the MLIR calls (scratch gap/callbacks.py), is 57 functions and 388 code
lines: 8 do file I/O (the NAR walker's), 20 force or throw, 19 allocate.  So the sweeps of scale 3 raise the MLIR's
quality (its dialect share, the bypass) and leave the C++ count where it is: wave 1 moved ten modules into dialect
forms for a net C++ change of -5.  The C++ falls further by G8, and by decisions that are the user's: the KIF scope
(13%), the scanners and the parser as combinators, kursive2's lexer (-152 C++ at +5-9% time), the boundary primops.

## Scale 2: the store shapes

Every keyed or ordered store of the C++, the shape the yardstick gives it, and where its algorithm lives.

| shape now | C++ sites | users | algorithm | dialect ops | TrikeShed's shape | gap |
|---|---:|---|---|---:|---|---|
| crit-bit trie (`Patricia<V>`) | 16 | srcToStore, fileEvalCache, autoArgs (Eval.h); the store's `drvs` and `answers` (LocalStore); `prehashes`, filterSource's kept/given (StorePaths); Prefetch's seen lines | lowered/nixstore/Patricia.mlir, 351 lines | 0.5% | crit-bit over lane rows (paths); nodes and rows as series read with `at`, keys compared `unsigned`, the set's plan one drain | the right shape, written as an llvm line-port |
| funnel of clusters (`GrowFunnel`, `MinMaxHeap`, `Pegs`) | 18 | `drvByContent` (Store.h: a derivation's first record by content fingerprint, the one product client); `trikeshed.cluster_order` (no product user) | lowered/composite/ClusterOps.mlir, 663 lines | 0.0% | the heap store: fold/argMin over a cluster's rows, the level walk a lazy series of buckets | the right shape, written as an llvm line-port; no sealed page and no delta emit anywhere |
| open addressing (`WordTable`, `TextTable`) | 45 | symbols and baseEnv by name; opIdx, attrPositionBases, dynamicPositions, primForOp, attrSymbols, OpCounts by an address; the printers' seen sets; KifTptp; fromTOML's tables | include/Composite/Table.h, 205 C++ lines | C++ | by name: TrikeShed interns through the funnel (AtomLexicon over FunnelHashMap); by an address: a dense row, minted when the op is (append's row, anchor's mint) | C++; the address-keyed tables wait on G1 |
| sorted rows (`SortedSet`, `SortedMap`, `sortRows`) | 139 | a derivation's inputs, outputs and env; references and closures; the attrs rows | SortedRows.mlir (168 lines, 20.4%), Rows.mlir (683 lines, 11.0%) | 11-20% | fill, then one sorted drain: `sorted` + `bisect` + `zipnext` over split rows | an insert out of order rotates the rows (O(n) each); rows are bytes at a stride, not a dialect type |
| files at the boundary | 20 | the store's index: `<stateDir>/info/<hash>-<name>`, one text file per valid path; the prefetch replay list (~/.cache/mlnix) | LocalStore.cpp, Prefetch.cpp | C++ | HashTrie by the path's hash part (log, sealed sorted pages, directory); referrers as sorted (ref, referrer) rows | `allValidPaths` is a readdir and a sort, `queryReferrers` reads every info file, `deletePath` asks it before each deletion |

## Scale 3: functions

The C++ left, by span (code lines): `registerBuiltins` 636 and `registerStoreBuiltins` 203 (the primop tables),
`mlnix-parse` main 209, `derivationStrict` 202, `printStats` 163, `cmdStore` 144, `runEvalCommandIn` 128, mlnix-kif main
118, `registerBoundary` 103, `Indexer::index` 96, `callFunction` 86, `parseCommon` 82, `fetchGit` 81, `createBaseEnv` 79,
`Store::realise` 79, `runBuilder` 78, `fetchImpl` 76, `marshalDrv` 72, `loadPrimDialects` 70, `splitSeries` 67,
`printValueAsJSON` 64.  Most are glue the recipe keeps (registration, process, I/O, MLIR's API); the composition in
`derivationStrict`, `printStats`, `cmdStore` and `printValueAsJSON` already went to MLIR, leaving forcing and throws.

The bypass, by the census's rule (a product function of 30 ops or more that loops and has under 10% dialect ops, and is
not a scalar core: 60% or more arith ops, a digest's rounds or a hash's mixing): 60 functions, 6,204 ops; the scalar
cores apart, 24 functions, 1,742 ops.  The largest bypass rows: the scanners (`confix_scan_nix` 944, `lx_default` 482,
`lx_ind` 184, `lx_string` 136, `nixev_ts_toml_scan` 204, `tm_basic` 115, `confix_scan_checked` 125), mini-luci's
pre-dialect server (`query_run` 246, http `main` 171, `evaluate_with` 143, `serve` 108), `xw_value` 172,
`nixfe_ts_strip` 160, `mlnix_rows_sort_u32` 115 and `mlnix_rows_sort` 109, `nixstore_ts_drvparse` 112, `ceq_attrs_eq`
103, `nixev_ts_replace` 97, `narr_node` 94.

## Scale 4: the roots

Declared with no lowering: `trikeshed.append`, `anchor`, `cell`, `resolve`, `reversed`, `contains`, `rows`,
`cursorSelect`, `cursorCombine`, `cursorJoins`, `pivot`, `tensor`.  Lowered but in no product module: `reify`, `take`,
`splitSelect`, `row`, `joins`, `select`, `domain`, `facet`, `adjacency`, `closure`, `cluster_order`, `eitherLeft`,
`eitherRight`; `confix.scan/size/row/kid/bands`; `kursive.pattern/rejected/bol/eol/empty`.

## The gap tree

Each gap names what it blocks and what closes it.  A child gap closes only after its root.

- **G1, MutableSeries is not in the dialect** (root).  `append` and `anchor` have no lowering, and `append` has no count
  operand, so a growable series cannot be lowered without changing every cursor's ABI (the append lane, 2026-11-25).
  TrikeShed's answer is LaneTrie's: rows in fixed pages, a published count, a row that never moves; the fill is appends,
  the drain copies the pages into one buffer of the known count, and every series op reads the drained buffer.
  Blocks: the hand-spelled appends and anchors (43 and 10 in the 2026-11-22 audit), every grow callback a bridge keeps
  (JsonRead's stack, the room protocols), the LaneTrie and HashTrie leaves (G3), son's pool rows, and dense rows for the
  address-keyed tables.
- **G2, fixed-width rows have no dialect form in use** (root).  `reify`, `take`, `splitSelect` and `row` lower but no
  product module uses them, and `rows`/`cursorSelect` do not lower.  So Patricia's nodes, a cluster's rows, the Attr rows
  and the store's sorted rows are byte offsets in llvm.  Closes by reading such rows as series (`text` over the buffer,
  `at`, `compare unsigned`) and by lowering `rows`; the line-ports are the oracle.
- **G3, the trie CAS.**  (a) Patricia.mlir in dialect forms (after G2).  (b) The store's index as a HashTrie keyed by
  the path's hash part, with the referrers as sorted rows: today one text file per path, and the referrers of one path
  cost a read of every file (after G1).  Measured on synthetic stores (scratch gap/gen-store.py, store-times.sh; a
  reference DAG of up to 4 references a path, `mlnix store` of 0db2780): `--query --referrers` 0.07 / 0.23 / 0.97 s at
  1,000 / 5,000 / 20,000 paths (0.4 / 1.5 / 6.7 G instructions: linear in the store), `--gc --print-dead` 0.14 / 0.95 /
  10.0 s (0.7 / 4.7 / 55 G instructions), while `--references` and `--requisites` stay at start-up cost (0.03-0.04 s).
  The GC's cost is its algorithm, not the files: StoreGraph.mlir's nixstore_ts_gc reads each dead path's references
  once, but each sweep asks, for every dead path still there, whether any other one still there refers to it, by
  scanning them all (n^2 a sweep, a sweep per layer of the dead graph).  `trikeshed.adjacency` (lowered, no product
  user) gives each path's referrer count in one counting sort; a sweep then deletes the paths whose count is 0 and
  lowers their references' counts: the same order, linear a sweep.  The referrers query needs the index itself.
  A NixOS store of 50,000-100,000 paths puts a dry GC in minutes.  (c) The address-keyed tables as
  dense rows (after G1).  The name tables (symbols, baseEnv) stay open addressing until a funnel measures faster: they
  are the evaluator's hottest lookups.
- **G4, the heap store.**  (a) ClusterOps.mlir in dialect forms (after G2).  (b) SortedSet and SortedMap built out of
  order fill and drain once (`sortRows` + `uniqueFirst`, both lowered) instead of rotating per insert.  (c) The sealed,
  delta-compressed page: not built in mlir-nix or in TrikeShed's CursorTrie (its pages are sorted, not compressed); the
  store index (G3b) is its first client.
- **G5, the CAS digests.**  SHA-512 is MLIR (Sha512.mlir); SHA-256 goes to CommonCrypto, OpenSSL or llvm::SHA256, SHA-1
  and MD5 to llvm::.  Closes by the same recipe as Sha512.mlir, if the time holds: SHA-256 is hot (drvByContent exists
  to skip it), and CommonCrypto may use the SHA instructions.
- **G6, the scanners** (ConfixScan, LexScan, TomlScan, JsonRead: 0-1% dialect ops, the four largest bypass rows).  The
  ruling: regex only as kursive combinators; another scanner already merged as a cf machine is redone only on the
  user's word.  kursive2's lexer as a kursive walk cut 152 C++ lines and cost 5-9% (held back, `2fffc12`).
- **G7, mini-luci's pre-dialect modules** (api, http, eval, corpus, confix, series: about 3,500 lines of llvm).
- **G8, the eval core** (Eval.cpp 2,459 lines: dispatch, forcing, calls).  Either is lowered now (`eitherLeft/Right/Fold`,
  CmpOps' error channel), so a module can return its error and the bridge throw once; the dispatch itself waits on son
  ops the evaluator runs.
- **What stays C++ by the recipe**: MLIR's API (dialects, passes, the lowering itself: lib/Dialect, CursorLowering.cpp),
  the KIF tools (on the user's scope decision), registration tables, process and file I/O, Nix's error wording.

## The queue

Wave 1 (2026-11-27): G1 (lanes: append and anchor lowered with LaneTrie's shape, then their consumers), G3a (Patricia
in dialect forms), G4a (the clusters and the funnel in dialect forms), G5 (SHA-256, SHA-1, MD5 in MLIR, gated on time).
Wave 1b (same day, files no wave-1 lane touches): printValueAsJSON's composition as fill-drain (toJSON, `eval --json`,
structured attrs: the writer gap of lib/Eval/Formats.cpp), and G7's query path (utils/mlnixci/src/api.mlir: query_run's
hand-spelled fills, folds and offsets, then facet, page and report).
Wave 2, after G1: G3b with G4c (the store index as a HashTrie with sealed pages), G3c, G4b.  On the user's word: G6.
G3b and G4c started early (2026-11-27, lane `sidx` from b77b980): a HashTrie's leaves are fixed 16 KiB pages and its log
is a file, so the store index needs no growable series and does not wait on G1.  Lane `gc` (from 0db2780) takes the
quadratic referrer scan out of nixstore_ts_gc meanwhile, with trikeshed.adjacency's counts.

## Ledger

Each merge, `gap-census.py --seal` on the new master and `--diff` against the previous seal.

- `0db2780` (2026-11-27, wave 1 part 1: trie, digest, ciq; C++ 22,822 -> 22,815).  Patricia.mlir 0.5% -> 17.2% dialect
  ops, no llvm load, store or GEP left (318M sets old/new in lockstep).  MD5 and SHA-1 lowered (Md5.mlir, Sha1.mlir:
  1.07M inputs each against CommonCrypto and llvm::); SHA-256 stays on the platform code, the MLIR form measured 10x
  slower than CommonCrypto's SHA instructions (parked: branch digest-sha256-mlir).  query_run's counts, selections and
  offsets in trikeshed forms (mlnixci fill-drain lines 0.3% -> 4.3%; 2,173 replies identical).  Repository: fill-drain
  functions 64 -> 71 (15.6% -> 16.9% of the lines); bypass 60 -> 61 functions at 6,204 ops (Patricia's set left it;
  MD5's and SHA-1's update loops came in: they could buffer as Sha512.mlir does, with slices drained).
  Linux (mlnix-os, LLVM 22): mlir 52/0, lang 488/488 exact 231 on both schedules, prims 121, mlnixci 51 PASS, son wrong 0,
  the Composite checks plain and sanitized.  Held: the heap lane (inode-bench +6.2%: a row swap left out of line), the
  json lane (C++ +13, toJSON 1.18-1.43x on the microbenchmark).
- json, parked on branch gap/json-comp (f7c4ec1 + dda82d8; 24,472 runs identical, C++ -8 for the two).  Moving the
  JSON printer's stitching into one combineAll per set or list costs toJSON 1.2-1.9x, and moving the per-value dispatch
  in too costs 1.25-2.5x: a combineAll runs its region twice (size, then drain), and a recursive writer of many tiny
  pieces pays both passes at every level.  The sub-gap is G1's: a writer of that shape wants a single-pass fill (appends
  into a lane) and one drain, not a two-pass composition.  Re-measure it on the lanes lowering.
- wave 1 part 2 (2026-11-27, heap: 35e480c + 75a7fcb; C++ 22,815 -> 22,817, two static_asserts the trikeshed forms
  need: the index table bounds N <= 255 and N + P <= 256; wave 1 since a8d3ae3: 22,822 -> 22,817).  ClusterOps.mlir
  0.0% -> 6.5% dialect ops (row moves as drains, argMin and the drain's emits as folds over one index table, the
  funnel's levels as a slice of it); lowered/composite 6.0% -> 8.8% dialect, 13.9% -> 11.2% llvm; bypass 61 -> 60
  functions, 6,204 -> 6,173 ops.  Proof: 1.5M random sequences (1.43G comparator calls) against the a8d3ae3 object in
  lockstep, then 500k more (477M comparator calls) on the inlined form, 0 mismatches; minmax-check and funnel-check
  plain and sanitized on both platforms.  Time: the first form was 6.2% slower on inode-bench's cluster phase (an
  out-of-line row swap); with `--inline --symbol-dce` in ClusterOps' mlir-opt stage and the loop-idiom memcpy pass off
  for its clang steps, the 16-byte swap is register moves and the phase is 4.7% faster than the llvm port (min of 15
  interleaved runs; 12.7% fewer instructions retired).  Linux (LLVM 22, 5df9b19): mlir 52/0, lang 488/488 exact 231 on
  both schedules, prims 121, mlnixci 51 PASS, son wrong 0, the Composite checks plain and sanitized.
- wave 1 part 3 (2026-11-27, sweval 4677d80 + swstore 4964860; C++ +0).  The nixeval bypass walks (xw_value,
  ceq_attrs_eq, nixev_ts_replace, nixev_ts_concat_parts, nixev_ts_flake_unparse) read their records with trikeshed.at
  over word views made once per record (xw_value 33 -> 9 llvm ops, ceq_attrs_eq 29 -> 8, concat_parts 25 -> 1); MD5's
  and SHA-1's update read the context through one view and buffer as head / whole blocks / tail, as Sha512.mlir does;
  nixfe_ts_strip's measuring pass is one fold a literal part (it now counts as a scalar core; its second pass is still
  llvm).  Repository dialect ops 12.9% -> 13.2%, llvm 12.5% -> 12.0%; bypass 60 -> 54 functions, 6,173 -> 5,696 ops.
  Proof: object harnesses with recording stubs, each catching a seeded mutant (ceq 400k, XmlWalk 502k, replace 120k,
  concat 320k with 73k throws, flake 320k; MD5/SHA-1 2.2M with guard pages; strip 2.0M), 7,566 old/new mlnix probes,
  mlnix-parse over 39,646 nixpkgs files identical.  Time: instructions retired on the bench workloads -0.17%
  (nixos-toplevel) and -0.20% (nixpkgs-73), outputs identical (scripts/instr-ab.sh).  Left: narw_node and narr_node
  (they need a callback-order harness first) and nixstore_ts_samecontent (a walk that stops at its first mismatch).
