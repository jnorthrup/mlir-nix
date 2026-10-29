# A `lib` continent: the stdlib as IR instead of frames

The continent dialects declare the 105 builtins as ops (`include/NixDialect/NixPrims.irdl.mlir`): a name, an arity, an effect
class, and a primop in the base environment that the evaluator runs without a frame. `nixpkgs/lib` is the other half of what a
NixOS evaluation calls, and it is still lambdas.

## The measurement

`MLNIX_STATS=1 MLNIX_STATS_TOP=400` ranks lambdas by the frames they make. nixos-toplevel, demand schedule, 5,389,929 frames
(the counts do not depend on the machine):

- 91.3% of all frames are lambdas defined under `nixpkgs/lib`; 70% of all frame slots.
- 52% of frames hold one slot; a third (1.80M) are the outer half of a curried `a: b: ...`.
- Grouped by the source line that defines them, `lib` definitions cover this share of all frames:

| definitions (most frames first) | share of all frames |
|---|---:|
| top 10 | 28.4% |
| top 20 | 44.1% |
| top 40 | 64.0% |
| top 80 | 81.9% |
| all 204 in the 400-site list | 90.4% |

The head of the list, by definition: `trivial.nix:825` (`warnIf`, 355k frames in 3 lambdas), `lists.nix:345` (`imap1`),
`attrsets.nix:1353` (`optionalAttrs`), `strings.nix:769` (`hasPrefix`), `systems/default.nix:46`, `lists.nix:777`
(`optional`), `lists.nix:277` (`foldl'`), `trivial.nix:1023` (`isFunction`), `attrsets.nix:657` (`filterAttrs`), and a long run of
`modules.nix` internals (the module system's merge steps: lines 723, 457, 710, 795, 376, 977, ...).

## What a continent entry would be

A call site cannot name `lib.optional` statically: `lib` is an attrset read from an imported file, so `nix.apply` sees an unknown
callee. What is known is the callee's *definition*: a lambda value carries the op that defined it, so a closure created from
`lib/lists.nix:777` can be recognized when it is created or first called. An entry is therefore data:

    irdl.operation @optional attributes {nix.lib = "lists.nix:optional", nix.fingerprint = "<hash of the lambda's IR>", nix.fx = "pure"}

- **recognition** is by file suffix and attribute name, and **proof** is by structure: the lambda's IR must hash to the golden
  fingerprint, so an edited nixpkgs never runs a stale implementation (it falls back to the lambda);
- **execution** replaces the frames with one op over the call's arguments, written in the `Series` algebra (a size-0 Series is the
  constant empty list, a size-1 Series is its element), keeping `lib`'s laziness, traces and error messages;
- **inlining** of the expansion into the caller (the op rewritten to core ops) is what exposes CSE: repeated
  `optionalAttrs c x` or `hasPrefix p s` in one module merge in stock `cse`.

## Not done

Nothing here is implemented. The cost per entry, the equivalence checks (difftest against Nix over every entry), and the effect on
time and memory are unmeasured. The counts above are the upper bound on frames removed, not a prediction of speed: the earlier
JIT tiers handled `optionalAttrs`-shaped lambdas natively and were 3 to 5% slower end to end, so an entry has to cost less than the
guards it replaces.
