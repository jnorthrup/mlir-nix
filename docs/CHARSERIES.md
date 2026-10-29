# CharSeries in the evaluator: windows, facets and less libc

`include/Composite/CharSeries.h` is TrikeShed's `CharSeries` (`../TrikeShed/src/commonMain/kotlin/borg/trikeshed/lib/CharSeries.kt`) and
the facet keys of its `TextK` (`../TrikeShed/src/commonMain/kotlin/borg/trikeshed/charstr/TextK.kt`), in C++.

## The types

- **`CharWindow`**: where a run of characters starts and how long it is. 16 bytes, the weight of a `std::string_view`, and a
  `Series<char>`. Kotlin keeps a root and `TwInt` bounds so that a window of a window reads the same root instead of stacking accessors;
  in C++ the start is a pointer, so that flattening is the pointer arithmetic itself.
- **`CharSeries`**: a window and its cursor (`pos`, `limit`, `mark`): `get`, `mk`, `res`, `flip`, `rew`, `clr`, `lim`, `slice`, `skipWs`,
  `rtrim`, `trim`, `seekTo`. 24 bytes. Equality is the characters between `pos` and `limit`; there is no `std::hash` (a cursor is not a
  key, and the check proves it at compile time); `view()` is the gate to a `std::string_view`.
- **Facets**: `facet<K>(chars)`, where the key type fixes the result type (TextK's GADT) and the dispatch is resolved at compile time:
  `Bytes`, `Codepoints`, `FNV1a`, `Evidence` (all character-class counts in one pass), `Deduced` (the most specific type the text reads
  as), `Terminated` (whether the window's bytes are a C string as they stand) and `Integer<Base, Signed>`.

No loop is written in the header (every walk is a `fold` or `firstWhere`) and no libc is called (whitespace and digits are tested without
`<cctype>`; running past the limit is `TODO()`).

## In the evaluator

- **Concatenation** (`nix.concat_strings`) and **`builtins.concatStringsSep`** treat the result as the series of its pieces: a string
  piece is a window on its own arena bytes, only a coerced piece (a number, a path, a set with `__toString` or `outPath`) makes text,
  and the result is one arena buffer, written once (`EvalState::mkStringOf`). Before, every part went through a heap `std::string` and
  the whole was copied again into the arena.
- **`builtins.substring`** of a string is a window on the original bytes sharing its context: no copy at all (it was three).
  Nix string values were never read as C strings (the pointer always travels with its length), so a window need not be terminated.
- **`builtins.getEnv`** passes the name's own bytes when `facet<Terminated>` says they are a C string, and copies only a window.
- **Numbers in `fromJSON` and `fromTOML`** are read by `facet<Integer<Base, Signed>>`, the reading `strtoll` and `strtoull` make (leading
  whitespace, sign, `0x` for base 16, saturation and `ERANGE` on overflow, and where the reading stopped) without libc. The facets agree
  with `strtoll` and `strtoull` on 400,000 random strings in five bases. `<cctype>`, `atoll` and `snprintf` are gone from `Formats.cpp`:
  26 libc number and character calls became 1, `strtod`, which stays for floats (a correctly rounded decimal-to-double conversion is
  not hand-rolled here, and `std::from_chars` differs on `+`, `inf` and overflow).

All of it is invisible: language 487/487 on both schedules, both workloads byte-identical to the build before, 36 JSON and TOML number
cases and 22 substring and `concatStringsSep` cases identical to it (contexts, paths, coercion, overflow, errors, UTF-8).

## The weight, measured

The pieces of a string being built, 3,000,000 strings of 2 to 6 pieces, the same fold copy, the three arms rotated within each of 9
rounds (Mac, clang, relative only):

| piece | -O2 | -O3 |
|---|---:|---:|
| `std::string_view` (16 B) | 0.140 s | 0.140 s |
| `CharWindow` (16 B) | +2.8% | +2.7% |
| `CharSeries` (24 B) | +1.9% | +2.4% |

The weight is not the cost (the 24-byte cursor is no slower than the 16-byte window); both are within 2 to 3% of a bare view in the
tightest loop, and the arena's string bytes did not change (38 to 37 MB on nixos-toplevel): what the windows remove is the transient heap
`std::string` traffic.

## What the pools and the process hold outside the arena

`MLNIX_STATS=1` now reads `/proc/self/status` at exit (Linux) and totals what the per-file pools keep. Kali, demand schedule, a stats run:

| | nixos-toplevel | nixpkgs-drvs |
|---|---:|---:|
| resident, anonymous | 1,290 MB | 1,155 MB |
| of which the arena's slabs | 945 MB | 870 MB |
| of which heap, IR and the rest | **344 MB** | **285 MB** |
| resident, file-backed (mapped sources, the binary) | 95 MB | 85 MB |
| Confix bands, statement ends, opening index of the pools | 5.0 MB (102,366 bands) | 3.0 MB |
| lambda rows, names, free names, seen of the pools | 4.7 MB | 2.4 MB |

(A stats run inflates the arena with its per-frame census; an ordinary run peaks at about 1,180 MB.) The Confix tables are not where the
memory is: the scanner reuses one fixed buffer from source to source, and what the pools keep for deferred bodies is under 1% of the
peak. The 285 to 344 MB of anonymous memory outside the arena is the lowered IR, the heap and the MLIR context, and the mapped sources
are small. That is the next place to look; it has not been accounted by use.

## A libc difference the check found

`facet<text::Integer<2, false>>` is the C11 `strtoull` reading. glibc 2.38 and later also read a `0b` prefix in base 2 (C23), so the
random comparison with libc excludes strings that start (after whitespace and a sign) with `0b`; Apple's libc does not read it. The
evaluator is unaffected, because the TOML path strips `0b`, `0o` and `0x` itself before it asks for the digits.
