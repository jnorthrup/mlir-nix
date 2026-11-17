# life: lifetimes as IR

`life` is a dialect for how long things live and who waits for them: an element opened by its key, the channels it
admits through, the jobs and resources it owns, and its drain. It is TrikeShed's lifecycle contract (PRELOAD.md,
"Lifecycle — the Job and the Channel are the lifecycle") written as IR, so that one description can be checked before
it runs and lowered to the two places lifetimes live here: inside a process (a ring, its workers, its buffers) and
outside one (a service, its runtime directory, its mounts).

What is built: the types and ops (`include/NixDialect/Life.td`), registered with the family in `mlnix-opt`, parsed,
printed, and checked by op verifiers for the laws one op and its block can decide (`lib/Dialect/LifeDialect.cpp`).
`test/mlir/life.mlir` is mini-luci's server in the dialect; `test/mlir/inputs/life-laws.mlir` breaks each local law once.
What is not built: `life-verify` (the laws over a whole function), the two lowerings, and their runtime. Nothing emits
or reads these ops yet.

## Why: four lifetimes that went wrong in one day

Each of these happened while bringing up mini-luci and mlnixos (see `~/work/mini-luci`), and each is a law below.

| what happened | what it was | the law |
| --- | --- | --- |
| `make check` found the server's port still listening after the server had exited | the listener was released after the ring, whose teardown is deferred | L6, release order: `life.before %listener, %ring` |
| mlnixos restarted every minute | the job that holds a WSL distro alive (`wsl --exec /bin/sleep infinity`) failed at once: NixOS has no `/bin/sleep` | L9, an effect names what it runs by a path the configuration resolves |
| `wsl-mnt-guard.service` failed on every boot | the release step of the distro's view of `/mnt/wsl` (`/bin/mount --make-rslave`) did not exist, so a shutdown could unmount the store under Kali | L9, and L6: the view is made a slave before it is unmounted |
| `runtimes/<stamp>` piles up, and deleting one under a running server would break it | a running server holds the runtime it started with, and nothing records that | L2: the runtime is a resource the server's element owns; collecting it is a release |

## The contract, sentence by sentence

| PRELOAD says | in `life` |
| --- | --- |
| the Key is the factory and returns only an opened element | `life.key @K` is the factory; `life.open @K` returns `!life.element<@K>`; there is no unopened element and no op that asks whether one is open |
| no lifecycle enum or flag (CREATED/OPEN/ACTIVE/DRAINING/CLOSED) | no type, attribute or op names a state; `life.is_closed` does not exist, and the laws test says so |
| admission is the channel send; never check a state and then act on it | `life.send` returns `i1`, admitted or not; it is the only way closure is seen |
| a discarded claim is not processed work | the answer of `life.send` must be used (L7, op verifier) |
| drain: close the input, the worker empties it, join the worker, complete and join the supervisor | `life.drain`: close the element's channels; a channel closes after its senders complete; each `life.for_each` ends when its channel is closed and empty; the jobs are joined; resources are released in order |
| a submitted uring op is a child Job of the supervisor, completed by its CQE, so join waits on the kernel | `life.submit` returns `!life.job<T>` completed by its completion; `life.join` waits for it |
| detached work and hard cancellation do not substitute for drain | there is no detach; every job is owned by the region around it (L2); `life.fail` is the only cancellation, and only on the failure path |
| nested supervisor scopes, explicitly parented | every region of a `life` op is a supervisor: what is launched, submitted, opened or acquired in it is joined or released before it ends |
| mmap is an explicitly owned userspace memory lifecycle | a mapping is a `life.acquire` with its unmap as `release`; lent to the kernel only through `life.submit ... lent` |

## Types

| type | what |
| --- | --- |
| `!life.element<@K>` | an element opened by key `@K`. Made only by `life.open`, consumed by `life.drain` |
| `!life.chan<T>` | a bounded channel of `T`: an element's admission |
| `!life.job<T>` | an admitted effect (a worker or a kernel submission), owned by the supervisor around it; `T` is its result, `none` for none |
| `!life.owned<T>` | a resource (a descriptor, a ring, a mapping, a GC root, a mount) owned by the supervisor around it |

## Ops

| op | what | law it carries |
| --- | --- | --- |
| `life.key @K : (inputs) -> (!life.element<@K>, channels...) { body }` | the factory; the body is the element's supervisor and ends with `life.opened` | L1 |
| `life.opened channels` | the end of a key's body: the channels the element admits through | L1 |
| `life.open @K(args)` | the element and its channels, or the factory's failure to the supervisor around | L1, L2 |
| `life.drain %e` | the drain sequence above; `%e` is not used after it | L5 |
| `life.supervise { body }` | a supervisor: complete when everything in it has completed and been released | L2, L3 |
| `life.launch { body }` | a worker: a child job | L2 |
| `life.submit @op(args) lent [i...]` | an effect the kernel completes; the lent operands are the kernel's until the join | L2, L4 |
| `life.join %j` | wait; the job's result | L3 |
| `life.channel N` | a bounded channel | L2 |
| `life.send %v to %c` | admission; `i1` | L7 |
| `life.close %c` | stop admission; what was admitted is still delivered | |
| `life.for_each %c { ^bb0(%x): ... }` | the worker's loop, until the channel is closed and empty | |
| `life.acquire @make(args) release @free` | a resource, or a channel the kernel fills (a listener) | L2, L6 |
| `life.before %a, %b` | `%a` is released before `%b` | L6 |
| `life.fail "why"` | the failure path: cancel the other jobs, release, fail upward | L8 |
| `life.yield` | the end of a supervisor's, worker's or loop's body (implicit) | |

`life.drain` is not `trikeshed.drain`: that one empties a series into a buffer.

## Laws

"op verifier" means checked today, when the op and its block decide it. "life-verify" is the whole-function pass, not
built.

- **L1, opened only.** An element is made only by `life.open` of a `life.key`. Its type names its key, and the open is
  typed as the key's factory. A key's first result is its element, and `life.opened` hands out exactly the rest
  (op verifier).
- **L2, owned.** `life.launch`, `life.submit`, `life.channel`, `life.acquire`, `life.open` and `life.fail` are inside a
  supervisor: a `life.key`, `life.supervise`, `life.launch` or `life.for_each` region (op verifier). A job or resource
  does not leave the region that owns it, as a result or a value captured by another supervisor (life-verify).
- **L3, joined before completion.** A supervisor completes after all its jobs: those not joined are joined at its end.
  A `life.join` gives the job's result type (op verifier).
- **L4, lending.** An operand lent to `life.submit` is not used between the submission and the join of its job. If the
  block never joins it, the operand is not used after the submission at all (op verifier, within the block). Across
  blocks: life-verify.
- **L5, drained once.** An element is drained at most once and not used after its drain (op verifier, within the
  block). Every element is drained on every path, explicitly or by the end of the supervisor that opened it
  (life-verify).
- **L6, release order.** Resources are released in reverse acquisition order unless `life.before` says otherwise.
  `life.before` orders two acquisitions of its own block (op verifier). The orders form no cycle (life-verify).
- **L7, admission is answered.** The `i1` of `life.send` is used (op verifier).
- **L8, cancellation only on failure.** Drain never cancels. A pending kernel operation ends by its completion, or by
  closing what it waits on: the listener's close is what cancels the pending accept. `life.fail` is the only op that
  cancels jobs (by construction: there is no other).
- **L9, resolved effects.** For the out-of-process lowering, every `make`, `release` and spawned program is a path the
  configuration resolves (a store path), never a name looked up on the target (`/bin/...`). This is checked by
  `life-to-nix`, which produces those paths from packages.

## Lowerings (designed, not built)

### In process: `life-to-async` and a ring runtime

| `life` | lowers to |
| --- | --- |
| `life.supervise`, the body of a key | `async.create_group`; at the end `async.await_all`, then the releases in L6 order |
| `life.launch` | `async.execute` added to the group |
| `life.submit @op` | a runtime call that takes an SQE, prepares `@op`, sets the user data to a fresh token, and submits; the job is an `!async.token` the CQE loop sets |
| `life.join` | `async.await` (plus reading the completion's result) |
| `life.channel`, `life.send`, `life.close` | a bounded queue in the runtime (TrikeShed's `RingSeries`, which is not built in C++ yet); `send` answers `false` once it is closed |
| `life.for_each` | `scf.while` over a runtime receive that answers "closed and empty" at the end |
| `life.acquire` | a call to `make`, and its `release` pushed onto the supervisor's release list |
| `life.drain` | close the element's channels, `async.await_all` on its group, then run the release list |

The runtime is small and C, like `lib/Composite/ClusterRuntime.cpp`: a ring per supervisor tree, the CQE loop, and the
queue. The hand-written image of this lowering is mini-luci's `serve()`: the accept is a submission whose cancellation
is the listener's close, a signalfd read on the ring triggers the drain, and the listener is released before the ring.

### Out of process: `life-to-nix`

A key whose jobs are processes lowers to NixOS module values in the `nix` dialect, the same way `sumo` lowers to `kif`
and on to `nix`. The configuration that results is evaluated by mlnix like any other: `mlnixos-rebuild` checks it
against Nix and switches to it.

| `life` | NixOS |
| --- | --- |
| `life.key @K` with a spawned process | `systemd.services.K` |
| `life.submit @spawn(program, args)` | `ExecStart`, with the program from a package (L9) |
| `life.drain` of the element | `KillSignal=SIGTERM`, `TimeoutStopSec`: the process drains itself, and stop waits for its exit (the join) |
| `life.acquire @runtime_directory` | `RuntimeDirectory=` |
| `life.acquire` of a GC root | a `gcroots` entry tied to the unit's lifetime |
| `life.open @Other` in the body | `requires` and `after` on `Other`'s unit |
| `life.before %a, %b` on mounts or units | `before`/`after` between them (the `make-rslave` of a WSL view before its unmount) |
| `life.fail` | the parent's failure policy: `Restart=` on the unit that owns the job |

### Kotlin

The IR describes what TrikeShed's elements are: a `CoroutineContext.Element` whose companion `Key` is the factory, a
`SupervisorJob`, `Channel`s, and `drain()`. No translation is planned in either direction. The laws are PRELOAD's, so a
review of Kotlin code can cite them by number.

## Placement in the family

| dialect | says |
| --- | --- |
| `nix`, `nix<area>` | what is evaluated |
| `trikeshed` | the geometry of the data |
| `mlnix` | how the utility runs an evaluation |
| `kif`, `sumo` | what is known and inferred |
| `life` | how long things live and who waits for them |

## Next

1. `life-verify`: L2 (no escape), L5 on every path, the L6 cycle check, and L4 across blocks, by dataflow over
   the function.
2. `life-to-async` and the ring runtime, checked by running `test/mlir/life.mlir`'s server against mini-luci's `e2e.py`.
3. `life-to-nix` for the mlnixos keys: the store view, the runtime GC root, and mini-luci as a service. Checked by
   `mlnixos-rebuild eval`: the generated configuration must name the same derivation as `hyperv/nixos/mini-luci.nix`.

## Open questions

- **Who closes a channel.** "Closed after its senders complete" needs the senders. Here they are the jobs in the same
  key whose bodies send on it. Is a channel sent on from another element's body an error, or a fan-in that the owner
  closes?
- **A drain's deadline.** PRELOAD has none. systemd's `TimeoutStopSec` is one. Should `life.drain` carry one that
  becomes `life.fail` when it passes?
- **Kernel channels.** A listener is `!life.chan<fd>` filled by the kernel. Its capacity is the listen backlog, not
  `life.channel`'s. Should the backlog be stated on the acquire?
- **Elements shared by several owners.** The runtime directory is held by every server started on it. Ownership is
  single (the supervisor around). Is sharing a counted acquire, or a GC root per owner (the Nix answer)?
