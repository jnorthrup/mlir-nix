# mlir-nix — build contract

All of mlir-nix builds to /Users/jim/work/TrikeShed/PRELOAD.md as MLIR. Period.

That is: the algebra (Join/Twin/Series, Cursor, Confix, CharSeries), the
taxonomical self-doc, the CCEK composition mandate, the ISAM/mmap and platform
codec rules, and the std::string/stdlib removal (composite::Text owning,
Chars/Views windows, no std::string or iostreams in the pure zone) are the
implementation contract. No exceptions, no rug pull, no excluded compiles.

In the IR: every MLIR dialect (nix, nix syntax, son, confix, kif, sumo, mlnix) is written in, or lowers to, the
`trikeshed` dialect (include/Composite/TrikeShed.td). docs/PRELOAD-DIALECTS.md maps each one and gives the order.

## C++ standards, not libstdc++

We value C++ standards — spans, ranges, modules, const — not libstdc++.
Nix depends on spans, ranges, modules and const; not on std::string and
std::vector. composite::Text owns; Chars/Views are windows; the owning string
is Text, never std::string.
