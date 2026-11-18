# mlnixci: a configuration interface for Nix

`utils/mlnixci` was mini-luci, a repository of its own; it lives here now, under its own name. What OpenWrt's LuCI (the Lua Configuration Interface) is to a
router's configuration, mlnixci is to be to a Nix configuration. It renders a corpus of Nix options as a manifest: a
menu, sections, and a form whose rows are edited with the widget their facets name. `mlnix` evaluates the corpus, and a
what-if overlay held in memory is evaluated with it. Nothing is written to the system.

## What it is today

- **The corpus.** `nixos/eval.nix` evaluates a NixOS configuration with `lib.evalModules` and returns every option
  (22,008 on mlnixos) and the rendered /etc files. `os/eval.nix` does the same for the small module set the tests use.
- **Facets as Nix code.**
  - `facets.nix` gives every row three facets: the widget it is edited with, the range its type allows (read off the
    type's description) and what an edit may do (`crud`).
  - `runtime.nix` maps options to the running system (/proc, /sys, /etc) and says what agreeing with it means.
  - `answer.nix` answers per-option questions on demand through `POST /api/facet`:
    - `adhesion`: where an option is declared and which files define it;
    - `entries`: the entries of a set of submodules, how each is removed, and a form for a new one;
    - `live`: the running value beside the configured one;
    - `module`: the what-if as the .nix module it would be.
  - The server knows no facet: a new one is Nix code.
- **Two pages.** `www/index.html` is a faceted list. `www/luci.html` renders the corpus as LuCI renders a router's
  configuration, its edits being what-ifs.
- **No C++.** The server is MLIR (`src/*.mlir`) lowered to LLVM IR and linked with libc and liburing only. The faceted
  query (`query.mlir`), the JSON index, the columns, the escapes and digits a reply is written with and the query's
  and the report's replies themselves (`src/text.mlir`) are TrikeShed's cursor and Confix ops, lowered by `mlnix-opt --trikeshed-lower-cursors`
  (combine and combineAll as views, drained part by part into one buffer). The rest is hand-written in the
  func/scf/arith/llvm dialects.
- **Its check.** `make -C utils/mlnixci check` builds it against this checkout. It then runs the facet check, which
  compares the compiled query with the counted one over 2,000 queries, the text check (text.mlir against what the
  builder wrote before it) and the end-to-end test (51 checks).
- **Where it runs.** On mlnixos (NixOS-WSL), mlnixci serves the LuCI-style page on :8082. The store builds it from its
  clone of this repository (`hyperv/builder/build.sh`) and runs it beside the system's service (`hyperv/nixos/beside.sh`).
  - The system's own service is still mini-luci, built from the mini-luci repository: the list on :8080, and the
    LuCI-style page on :8081 beside it.
  - The program, its units and its NixOS module (`services.mlnixci`, `hyperv/nixos/mlnixci.nix`) carry the name
    mlnixci.

## Future direction

None of this is implemented but the first item's first half. The order is the order of dependence.

1. **One name, one home.** Done for mlnixci itself: its name, and the store building it from this repository. Left: the
   system's service. /etc/nixos/configuration.nix is to import `hyperv/nixos/configuration.nix` from the store's
   mlir-nix checkout instead of the mini-luci one, so :8080 runs mlnixci, and the mini-luci repository is then kept as
   history. That changes the running system, so it waits for the owner's go-ahead.
2. **Facets the corpus declares.** Today the server's columns are fixed: section, kind, state, module and what-if, in
   `src/corpus.mlir` and `src/columns.mlir`. Widget, range and runtime are only fields of a row. A corpus is to name its
   facets, and the server to compile each into the faceted query, with counts, as it compiles the fixed five now.
3. **Any Nix as a corpus.**
   - First, any module system through the same `eval.nix` contract (home-manager, nix-darwin).
   - Then a Nix value with no options at all: its attribute paths are the manifest's rows, and their types and
     positions (`builtins.unsafeGetAttrPos`) are its facets. It is a manifest of the value, not a hierarchy of files.
4. **Module-specific CRUD.**
   - Entries (a user, a service, a sysctl key) become rows of their own.
   - A module may ship its own forms and its own rule for removing an entry. Today removal is read off the submodule:
     disable it through `enable`, set it to null, or refuse.
5. **Dials and knobs on demand.**
   - More ranges from types: enums of numbers, `strMatching`, bounded lists.
   - Ranges and choices that only the running system knows, such as the machine's cores or the units that exist,
     answered by Nix code on demand like `answer.nix`'s facets.
6. **Adhesion as a write.** The what-if is already the module it would be. Writing it beside the configuration (for
   example `/etc/nixos/luci.nix`, imported by `configuration.nix`) would make that .nix file where the manifest
   adheres. This alters the system, so it waits for the owner's go-ahead.
7. **A runtime that acts.** `runtime.nix` reads, and only shows the command that would apply a value (`sysctl -w`,
   `systemctl set-property`). Applying it needs a privileged helper that reports what it changed. On mlnixos the kernel
   is shared with the other WSL distributions, so this waits for a go-ahead too.
