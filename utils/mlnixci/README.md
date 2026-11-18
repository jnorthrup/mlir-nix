# mlnixci

mlnix's configuration interface, as LuCI (the Lua Configuration Interface) is OpenWrt's: mini-luci, moved into mlir-nix as
`utils/mlnixci/` (the server binary and its service are still called mini-luci). [docs/MLNIXCI.md](../../docs/MLNIXCI.md)
says what it is and where it goes next. A faceted, read-only page over the options of a NixOS-style configuration,
evaluated by [mlnix](../..) (the MLIR
Nix evaluator). Nothing is written to the system. A what-if overlay, held in memory, is evaluated with the configuration
at mkForce priority 50, and the page reports what it changes.

- Two pages read the same server. `www/index.html` is the faceted list. `www/luci.html` renders the corpus the way LuCI
  renders a router's configuration: a menu made of the compiled module facet, and a form whose every row is edited with
  the widget its facets name. Its edits are what-ifs too.
- The facets are Nix code. `facets.nix` puts on every row (through `corpus.nix`) what the page edits it with (`widget`:
  toggle, select, knob, number, text, lines, list, records, sections, table, ...), the `range` its type allows (read off
  the type's description: ints.between, u8 ... s32, port, positive, unsigned), and what an edit may do (`crud`).
  `runtime.nix` maps options to the running system (`/proc`, `/sys`, `/etc`): it says where each one's live value is,
  what agreeing with it means (nix.settings.cores = 0 is every core), and the command that would set it, which nothing
  here runs. `answer.nix` answers what a page asks about an option on demand:
  - `adhesion`: the file, line and column that declare it and the .nix files that define its value;
  - `entries`: an attrsOf submodule's entries, or a freeform set's keys. Each comes with what its modules set, the files
    defining it, how it is removed (the module's own way: `enable = false`, a sysctl key set to null, or dropping the
    what-if that made it), its runtime counterpart, and the form a new entry is made with;
  - `live`: the running system's value beside the configured one;
  - `module`: the what-if as the .nix module it would adhere as.
- `os/` is a seven-option module (options.nix, etc.nix, settings.json) to test with. `os/eval.nix` evaluates it with
  nixpkgs `lib.evalModules` and returns every option and the rendered /etc files. `nixos/eval.nix` does the same for a
  NixOS configuration (22,008 options on mlnixos).
- `query.mlir` is the faceted query, written in TrikeShed's cursor ops and lowered by mlnix-opt `--trikeshed-lower-cursors`.
- `src/index.mlir` is a JSON text's index in TrikeShed's forms, lowered the same way: `confix.index` (this repository's
  confix dialect) scans the text with TrikeShed's Confix scanner (`../../lib/Confix/confix.ll`) into ConfixIndexK's
  rows (Spans, Tags, DirectChildren) and kids, and every read of it (a tag, a span, a child, KeyToChild) is a trikeshed op.
- `src/columns.mlir` codes the corpus's columns and orders its rows, in TrikeShed's ops lowered the same way: the rows by
  the bytes of their pieces (`trikeshed.sorted`, its order an unsigned `compare` of two slices: Cursor.ordered), each
  name's run (`where`: groupClusters over the ordered rows), and each row's code (`bisect` among the names: DictColumn).
  The joins are there too: a corpus with its base by key (`mark`: KeyedJoin, base's order the index), and the /etc files
  of the two by name (`etc_join`: the same join made full outer, each side the index over the other, the entries in the
  order a merge of the two would give).  So are the cells the facets count (`opt_cells`): each option's section, shown value, state, kind (its type's first
  part at ' ', `trikeshed.parts`: Series.div) and module (two levels below the last "modules/" of its first declaration,
  found by a `fold`, the levels by `parts` at '/'), all pieces of the evaluation's text.  And so are the two texts a
  corpus makes (`opt_text`): each key, a path's segments with a '.' between each two (`trikeshed.combineAll`: Combine.kt's
  combine of a Series<Series<Char>>, each part's coordinates kept), and what a row is searched by, its key and its
  description with their escapes read (`confix.unescape`: KnownSchema.decodeEscaped) and lower-cased (`alpha`), a ' '
  between them (`combine`).
- `src/text.mlir` makes what the reply builder writes besides pieces of a text, in TrikeShed's ops lowered the same way:
  a string's inside as JSON writes it (`json_escape`: `combineAll` of each byte's escape, a slice of one constant table,
  then `drain` into the builder's room) and a number's digits as printf's `%ld` writes them (`decimal`: their count a
  `fold` over the powers of ten, each digit an element of a `series`).
- `src/*.mlir` is the rest of the server, written in the func/scf/arith/llvm dialects. The stock MLIR pipeline lowers it,
  and it links with libc and liburing-ffi only. There is no C++ and no C++ library.
  - `series.mlir`: coordinates into byte series (TrikeShed's TwinPacked: an i64, start << 32 | length, half-open), and
    the reply builder, which leaves room for the head in front of the body; its escapes and digits are text.mlir's.
  - `confix.mlir`: the handle of a JSON text's index (index.mlir's buffers, as descriptors) and the calls of index.mlir
    the rest of the server makes with it. A text is never decoded: its strings are coordinates into it, and keys are
    compared where they lie.
  - `corpus.mlir`: mlnix's output as six dictionary-coded columns, plus the keys and the search text (columns.mlir's
    `opt_text`), built once as series.
  - `eval.mlir`: mlnix as a child process (posix_spawn). Its output and errors are read into growing series.
  - `api.mlir`: the routes. An overlay edit is a splice at the coordinates of the overlay's index.
  - `http.mlir`: HTTP/1.1 on one io_uring ring. SIGTERM, read from the same ring, drains it.

API:

- `GET /` serves the page.
- `POST /api/query {"select": {"section": [...], ...}, "q": "text", "offset": 0, "limit": 150}` returns the hits and
  each column's counts.
- `GET /api/report` returns the overlay and, for each option and /etc file it changes, the value before and after.
- `POST /api/whatif/set {"path": [...], "value": json}`, `POST /api/whatif/reset {"path": [...]}` and
  `POST /api/whatif/clear` edit the overlay. An overlay is kept only if mlnix evaluates it; if the module system refuses
  it, its error is the reply (422).
- `POST /api/facet {"ask": [{"iface": "adhesion" | "entries" | "live" | "module", "path": [...]}, ...]}` asks for facets
  on demand. The server writes the request to `STATE/mini-luci-facet.json` and has mlnix evaluate the corpus's eval.nix
  with `--arg request FILE` and the overlay, which answers instead of making the corpus (answer.nix). The reply is
  `{"answers": [...]}`, one per ask, each with its own `error` when it does not evaluate. The server knows no facet: a
  new one is Nix code. A body that is not one JSON object is 400; an evaluation that fails is 422.

## Build and run (in the machine)

    # mlnix: this checkout built against apt.llvm.org LLVM/MLIR 22 (llvm-22-dev libmlir-22-dev mlir-22-tools clang-22)
    cmake -S ../.. -B ../../build -G Ninja -DCMAKE_CXX_COMPILER=clang++-22 \
      -DLLVM_DIR=/usr/lib/llvm-22/lib/cmake/llvm -DMLIR_DIR=/usr/lib/llvm-22/lib/cmake/mlir \
      -DMLIR_TABLEGEN_EXE=/usr/lib/llvm-22/bin/mlir-tblgen
    cmake --build ../../build --target mlnix mlnix-opt

    make                                                  # the server (also needs liburing-dev); MLIR_NIX is ../..
    make check NIXPKGS_LIB=/path/to/nixpkgs/lib          # facet-check, text-check, then the e2e test on os/
    sudo make install NIXPKGS_LIB=/path/to/nixpkgs/lib
    sudo systemctl enable --now mini-luci                 # http://mlnix-os.orb.local:8080/

On mlnixos (NixOS-WSL), `hyperv/builder/build.sh` builds the runtime and `hyperv/nixos/mini-luci.nix` runs it. The store
still builds it from the separate mini-luci repository (`build.sh MLIR-NIX-BRANCH MINI-LUCI-BRANCH`).

## Verified (2026-11-16, OrbStack machine `mlnix-os`, Debian trixie arm64, LLVM 22.1.8)

- `make check`: facet-check runs 2,000 random queries, the last over 22,000 rows, and the compiled query agrees with
  the hand count on every one. text-check writes 2,259 texts (every byte, random ones, 100 KB) and 10,105 numbers
  (both ends of i64) with text.mlir and finds them as the builder wrote them before. The e2e test passes 51/51,
  covering:
  - facets and counts, selections, text search, and paging;
  - what-if values the module system refuses (strMatching, port range, enum);
  - round-tripping of non-ASCII text, quotes, backslash and `${`;
  - reset, the emptied object dropped, and clear;
  - malformed requests;
  - settings.json left byte for byte as it was.
- `ldd mini-luci`: linux-vdso, liburing-ffi.so.2, libc.so.6 and the loader. The binary is 68,080 bytes stripped. The
  C++ server it replaces was 134,184 bytes and also loaded libstdc++, libm and libgcc_s.
- SIGTERM drains: the accept is cancelled, admitted connections are answered, and the listener is closed before the ring.

## Not done

- No authentication. The page is read-only, but anyone who can reach the port can run what-if evaluations, and each
  one is a full mlnix run.
- The ring waits on each mlnix evaluation (a child process), so other requests wait while one runs.
- mlnix itself is C++, built on MLIR's C++ API, and loads libstdc++. mini-luci's own code has no C++.
- `trikeshed-lower-cursors` does not lower groupBy, pivot, keyed joins or lazy series.
