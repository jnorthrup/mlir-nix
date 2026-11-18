# MLNIX_STATS's research counters, 18 November 2026

What `MLNIX_STATS=1` printed at 5733d30 with every optional census on, on scripts/bench.py's two workloads:
nixpkgs-73.txt and toplevel.txt. Mac (M3 Pro), Homebrew LLVM 23.1.1 build, `MLNIX_DEFER=1`. Results: nixpkgs-73
5e8fff662dff, toplevel f1cfa7cd1464, the same as without the counters.

    MLNIX_DEFER=1 MLNIX_STATS=1 MLNIX_STATS_SHAPES=30 MLNIX_STATS_USES=1 MLNIX_STATS_IMPORTS=1 \
      build/bin/mlnix instantiate --readonly-mode --eval --strict --json test/nixpkgs-drvs.nix --argstr system x86_64-linux
    ... test/nixos-toplevel.nix --arg nixpkgs ./.cache/nixpkgs

The shapes census indexes the bodies it walks, so these files count more lambda bodies in son's account (904 of 24,362
on nixpkgs-73) than a plain run does (406 of 3,537). The returns and the frames are the same.

The counters below were then removed from the evaluator. What MLNIX_STATS keeps: the frames, values and arena by use,
the call ladder (stack frames, selectors, curried intermediates), son's account of the frames at their return, the sea
of nodes and the pools, and the static and dynamic mix of ops.

    counter                       question                                       nixpkgs-73        toplevel
    frame census (slot counts,    slots ever read; 1-slot frames' share of       12.0%; 61.8%      15.4%; 75.7%
      first touches, storage)       the frame storage
    frames by the defining file   whose lambdas make the frames                  nixpkgs/lib 71%   nixpkgs/lib 90%
    curried chains                frames that only capture an argument for       32.9%             36.9%
                                    the inner lambda of `a: b: ...`
    frames that cannot leak       heap frames of bodies that could be on the     1 frame           1 frame
                                    stack (such calls run on one now)
    the 40 busiest lambdas,       which lambdas make the frames                  (in the files)
      lambda shapes
    selects                       found / dynamic key / mean probes              88.9/17.0%/6.4    86.5/5.4%/4.5
                                  one-entry cache per site would hit             63.4%             60.2%
    thunks over a frame           projections of an argument or capture          6.1% of 3,778,186 15.5% of 5,327,902
    forced next                   frame thunks forced as the very next thing     0.3%              1.5%
    attribute-set builders        past the 12 inline rows                        2.56%             1.56%
    value-tag writes              tag writes by type, stack temporaries too      (in the files)
    Bindings::get                 calls, binary-search steps by set size         4,199,882 calls   5,733,537 calls
    import prediction             files named by a path literal lowered before   59.9%             88.4%
    nodeOf                        answered by the hash map                       10,534            13,702
    lookupImpl                    answered by a filled slot; frame hops 0        58.7%; 72.8%      58.8%; 72.4%
    cells made by lookup          by defining op, forced at once or a thunk      (in the files)
    builtins.match                calls repeating a (regex, input) pair          59.4%             53.2%
    IR read                       MB of the ops of the hottest 90% of evals      0.23 MB           0.20 MB
    single-use census             one-result ops by uses (MLNIX_STATS_USES)      (in the files)
    frame cells                   cells given to a value with no use             0.1%              0.1%

Two of the answers were acted on: builtins.match keeps a memo of its answers (lib/Eval/Builtins.cpp), and a body of
strict ops over its one argument runs on a stack frame (EvalState::stackFrameOK), which is why only one heap frame
could still leak. To bring the counters back: `git revert` the commit that removed them.
