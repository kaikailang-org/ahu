# ahu design

Living document for the kaikai-native concurrency and fault-tolerance
framework that runs underneath manutara and friends.

> **Pivoted on 2026-05-02.** This document supersedes the OTP-style
> draft first written in this same lane. Rationale: Erlang's OTP
> solutions exist to compensate for things kaikai already has
> (structured concurrency, typed mailboxes, effects in the row).
> Cloning OTP would import baggage that kaikai does not need. The
> three-layer design pinned here — *streams*, *cells*, *restart
> helpers* — keeps the load-bearing patterns OTP got right while
> dropping everything that is downstream of Erlang's specific
> runtime constraints. The OTP draft is preserved in this file's
> git history; the lane retrospective documents the pivot.

## Context

ahu is the second layer of the five-project lnds ecosystem:

```
kaikai      (the language)
   ↓
ahu         (this project — concurrency and fault-tolerance layer)
   ↓
kohau       (database / persistence)
   ↓
henua       (DDD building blocks)
   ↓
manutara    (web framework, LiveView-shaped)
```

Names follow the Rapa Nui vocabulary established by `kaikai` and
`ahu`. `kohau` is the inscribed wooden tablet that carried the
rongorongo script — the substrate metaphor maps cleanly to a
persistence layer. `henua` means *land / territory / domain* — the
DDD-vocabulary mapping is direct.

ahu's job, in one sentence: **package kaikai's effect, fiber, and
mailbox primitives into three composable layers — streams, cells,
restart helpers — that manutara (and any other downstream user) can
build on without re-deriving the patterns each time.**

ahu is **not** an OTP clone. See §*Why ahu is not OTP* below.

This document is updated as decisions are closed.

## Why ahu is not OTP

OTP is the canonical example of a high-quality concurrency + fault-
tolerance framework. The temptation to copy it is real — gen_server,
supervisors, applications, and the supervision tree pattern have
worked well for decades on BEAM. But OTP's shape is **downstream of
Erlang's runtime constraints**, not upstream of "what concurrent
software needs". Concretely:

| OTP solves | Because Erlang/BEAM has | kaikai has |
|---|---|---|
| Supervision trees | No structured concurrency / no lexical scope for processes | **Nurseries with regional brand on `Pid[Msg]`** |
| Behavior callbacks (`gen_server`, `gen_event`, etc.) | Untyped messages — needed callbacks to recover some structure | **Typed mailboxes by construction (`Pid[Msg]` only carries one `Msg`)** |
| `code_change/3` | Hot code reload swapping versions in-place | **No hot reload (native binaries via LLVM)** |
| Process registry (`Registered.`) | No way to share Pids without manual passing | Region-brand makes registry harder, but explicit handoff fits the type system |
| Distribution Protocol | A demand for cross-node calls dating to telecom switches | Single-node first; distribution is a later, separately-designed concern |

What OTP got right and ahu *does* keep:

- **Restart policies** as a first-class shape. Permanent / Transient
  / Temporary semantics, with intensity-over-period escalation, are
  patterns that need to land in the framework rather than being
  rewritten by every user.
- **The "stateful entity with a typed message loop" pattern** for
  long-running connections, sessions, and services. ahu calls this
  a *cell* (deliberately not "behavior" — see §*Decision 1*).
- **Composable failure containment**. Failed work is contained, not
  catastrophic. ahu does this through nurseries + restart helpers,
  not through a separate `Supervisor` type.

What ahu deliberately drops compared to OTP:

- The full `gen_server` callback table (`init`, `handle_call`,
  `handle_cast`, `handle_info`, `terminate`, `code_change`).
  Replaced by a recursive function shape (Akka-Typed lineage).
- The `Supervisor` type as a separate abstraction. Replaced by
  `with_restart(policy, body)` helpers wrapped in nurseries.
- `Application` as a heavyweight lifecycle container. Replaced by
  a thin `run_app(root)` helper that installs signal handlers and
  blocks.
- Specialised behaviours (`gen_event`, `gen_statem`, `Agent`,
  `Task`). Each is either expressible as a cell + helpers, or
  belongs to a different paradigm (events → streams).
- DSL-style declarations (Elixir's `use GenServer` macro
  expansion). Kaikai has no macros and ahu does not pretend
  otherwise.

What ahu adds that OTP does not have:

- **Streams as a first-class layer.** Reactive streams with typed
  values, effect rows, and demand-based backpressure. For
  request/response flows, ETL, and event broadcasting, streams
  beat actors structurally. Phoenix had to bolt streams onto OTP
  late (via `GenStage` and friends). ahu has them from day one.
- **Effects in the row, throughout.** Every cell, every stream
  combinator, every restart helper carries its effect row in its
  type. There is no ambient `IO` capability hiding inside a
  callback — `Console`, `File`, `Net`, `Db` all appear in the
  signature.

## The substrate kaikai provides

ahu builds on these primitives, all already in kaikai's main
branch as of m8 + the v1 effects work:

- `Actor[Msg]` effect — typed mailboxes, `self() / send() /
  receive()` operations.
- `Pid[Msg]` — region-branded handle, scoped to the producing
  nursery.
- `Spawn` effect — `spawn / await / select / cancel /
  set_trap_exit`.
- `Cancel` effect — cooperative cancellation at yield points.
- `Link` and `Monitor` effects — bidirectional and unidirectional
  failure observation.
- `MailboxPolicy = Unbounded | Bounded(c, Overflow)` with
  `Overflow = DropOldest | DropNewest | BlockSender`.
- Nurseries as `Spawn` handler installation
  (`docs/structured-concurrency.md`).
- Single-dispatch protocols + `#derive(...)` (m12.8) for
  structural impls.
- Effect row polymorphism (`/ e`) — the load-bearing mechanism
  for ahu's signatures.

ahu does not redesign any of these. Where it discovers gaps, the
gap is documented in §*External dependencies on kaikai*.

## The three layers

ahu is three layers, used independently or composed:

```
┌──────────────────────────────────────────────────────────────┐
│ Layer 3 — Restart helpers                                    │
│   with_restart(policy, body), intensity/period escalation    │
│   Used by: cells that need to survive crashes                │
├──────────────────────────────────────────────────────────────┤
│ Layer 2 — Cells                                              │
│   Cell[Msg] = (Msg) -> Cell[Msg] / e (recursive function)    │
│   start_cell, done(), stop()                                 │
│   Used by: long-running stateful entities                    │
├──────────────────────────────────────────────────────────────┤
│ Layer 1 — Streams                                            │
│   Source[T, e], Flow[A, B, e], Sink[T, R, e]                 │
│   Used by: request/response, ETL, broadcasts                 │
├──────────────────────────────────────────────────────────────┤
│ Layer 0 — kaikai primitives                                  │
│   Actor[Msg], Pid[Msg], Spawn, Cancel, nursery, effects      │
└──────────────────────────────────────────────────────────────┘
```

A program that needs only streams pays for nothing else. A program
with one cell and no restart needs nothing from Layer 3. A program
that uses just kaikai primitives directly pays for none of ahu —
ahu is opinionated infrastructure for cases where the patterns
recur, not a mandatory shell around every concurrent program.

### Layer 1 — Streams

Reactive streams with typed values, demand-based backpressure, and
visible effect rows. The shape comes from Reactive Streams (the
JVM spec) and Akka Streams (the Scala implementation) — but
adapted to kaikai's effect system.

```kai
# A Source produces values of type T, possibly with effects e.
type Source[T, e]

# A Flow transforms values of type A to values of type B.
type Flow[A, B, e]

# A Sink consumes values of type T, producing a materialised result R.
type Sink[T, R, e]

# Composition: |> is the canonical operator.
let pipeline : Source[Request, Net] |> Flow[Request, Response, Db + Net] |> Sink[Response, Unit, Net] = ...

# Running materialises the pipeline and produces the sink's R.
let result : Unit / Net + Db + Spawn + Cancel = pipeline.run()
```

Combinators ship as ordinary functions on `Source` / `Flow` /
`Sink` (sketched, surface bikeshed deferred to implementation):

```kai
# On Source:
Source.from_list([1, 2, 3, 4])              : Source[Int, ∅]
Source.repeat(value: T)                      : Source[T, ∅]
Source.from_listener(port: Int)              : Source[Conn, Net]
Source.tick(every: Duration)                 : Source[Tick, Clock]

# On Flow:
flow.map(f: (A) -> B / e)                    : Flow[A, B, e]
flow.filter(p: (A) -> Bool)                  : Flow[A, A, ∅]
flow.flat_map(f: (A) -> Source[B, e])        : Flow[A, B, e]
flow.throttle(per: Duration, rate: Int)      : Flow[A, A, Clock]
flow.buffer(size: Int, on_full: Overflow)    : Flow[A, A, ∅]

# On Sink:
Sink.foreach(f: (T) -> Unit / e)             : Sink[T, Unit, e]
Sink.fold(z: R, f: (R, T) -> R / e)          : Sink[T, R, e]
Sink.collect()                               : Sink[T, [T], ∅]
```

Backpressure is demand-based: each downstream stage signals how
many elements it can accept; upstream stages produce only that
many. A bounded buffer between stages is the default; the user
chooses `BlockSender` / `DropOldest` / `DropNewest` (mirroring
kaikai's mailbox `Overflow` enum) when explicit policy is needed.

**Why streams as Layer 1, not as a side-library:**

For most data-flow problems — request/response, batch processing,
event broadcasting, parsing pipelines — streams are structurally
the right tool. Modeling them as actors (one actor per stage) is
work that the user has to redo every time. Akka split this off
into Akka Streams and Phoenix did the same with `GenStage`; ahu
takes that lesson upstream and ships streams as the first thing
the framework provides. Cells (Layer 2) are for the cases streams
do not cover — long-lived stateful entities with explicit
addressable identity.

### Layer 2 — Cells

A cell is a long-running stateful entity with a typed mailbox.
Its body is a **recursive function**: each iteration receives a
message, computes the next state, and returns the next iteration's
function (or `done()` to terminate). Borrowed in shape from Akka
Typed's `Behavior[T]`; renamed to *cell* to avoid OTP coding.

```kai
# Cell[Msg] is the type of the per-message dispatch function.
# Implementation-wise it is a closure over State.
type Cell[Msg, e]

# A counter cell:
fn counter(value: Int) : Cell[CounterMsg] / Console = receive {
  Increment            -> {
    Console.print("counter: now #{value + 1}")
    counter(value + 1)
  }
  GetValue(reply_to)   -> {
    reply_to.send(value)
    counter(value)              # state unchanged
  }
  Reset                -> counter(0)
  Stop                 -> done()
}

# Boot it:
fn main() : Unit / Spawn + Console = {
  let pid = start_cell(() => counter(0))
  pid.send(Increment)
  pid.send(Increment)
  pid.send(Stop)
}
```

Three things to notice:

1. **State is the recursion argument**, not internal mutation. No
   `var`, no implicit context. The transition `value → value + 1`
   is explicit in the next call. This is functional and matches
   how kaikai users already think about state.
2. **Effects flow through the row.** `counter` declared `/ Console`
   in its signature; `start_cell` propagates that into its caller
   via row polymorphism (`fn start_cell[Msg, e](body: () -> Cell[Msg, e]) : Pid[Msg] / Spawn + e`).
3. **Termination is structural.** `done()` returns a sentinel cell
   value that the runtime recognises as "this entity is finished".
   The cell's mailbox drains; the fiber exits cleanly. There is no
   `terminate(state, reason)` callback — cleanup happens before
   returning `done()`, in ordinary kaikai code.

The receive-shape (`receive { ... }`) sketched above desugars to
the kaikai `Actor.receive()` op plus a `match`. Implementation
details live in the eventual `src/cell.kai`.

**Composing cells:** request/reply uses `with_mailbox` on the
caller side (kaikai pattern from `actors.md` §*with_mailbox*):

```kai
fn ask_counter(c: Pid[CounterMsg]) : Int / Spawn + Actor[Int] = {
  with_mailbox { m ->
    c.send(GetValue(m.self()))
    m.receive()
  }
}
```

No "synchronous call" abstraction in ahu's surface — request/reply
is a pattern, not a primitive. If usage data shows the pattern is
common enough to warrant a helper, `Cell.ask(pid, build_request)`
ships in Anga Roa.

### Layer 3 — Restart helpers

Crashes happen. Sometimes the right answer is "let the cell die
and restart it from scratch"; sometimes "let the parent decide";
sometimes "log and continue". ahu does not introduce a
`Supervisor` type for this. Instead, it provides three small
helpers that wrap a cell or fiber with restart policy. These
helpers compose with nurseries — a nursery + N children + N
restart wrappers **is** your supervision tree.

```kai
type RestartPolicy =
  | Permanent       # restart on any termination
  | Transient       # restart only on abnormal termination
  | Temporary       # never restart

type RestartLimit = { intensity: Int, period: Duration }

# Wrap a fiber body with restart policy.
pub fn with_restart[T, e](
  policy: RestartPolicy,
  limit:  RestartLimit,             # default 5/60s
  body:   () -> T / e
) : T / Spawn + Cancel + e

# Convenience: wrap a cell directly.
pub fn restartable_cell[Msg, e](
  policy: RestartPolicy,
  limit:  RestartLimit,
  body:   () -> Cell[Msg, e]
) : Pid[Msg] / Spawn + e
```

`with_restart` returns the body's result on normal completion.
On crash, it consults the policy:

- `Permanent`: restart the body unconditionally.
- `Transient`: restart only if the cause was abnormal
  (`Crashed(_)` or `Cancelled`); on `Normal`, return.
- `Temporary`: never restart; propagate the cause up.

`RestartLimit` is the OTP intensity-over-period rule: at most
`intensity` restarts within `period`, otherwise the helper itself
crashes. The default `5 / 60s` matches OTP convention; users
override per-call.

**A "supervision tree" using these primitives:**

```kai
fn boot_workers(queue: Pid[Job]) : Unit / Spawn + Db + Net = {
  nursery { n ->
    n.spawn { restartable_cell(Permanent, default_limit, () => job_worker(queue)) }
    n.spawn { restartable_cell(Permanent, default_limit, () => job_worker(queue)) }
    n.spawn { restartable_cell(Permanent, default_limit, () => job_worker(queue)) }
    n.spawn { restartable_cell(Transient, default_limit, () => metrics_collector()) }
  }
}
```

That nursery + four `restartable_cell` calls **is** the supervisor.
No separate `Supervisor` type, no `SupervisorSpec` record, no
`one_for_one` strategy enum. The four children are independent
(any one's crash cancels none of the others — restart is local to
its own wrapper). This is `one_for_one` semantics by default.

For `one_for_all` semantics (any child's crash cancels its
siblings), the user writes the same nursery without
`with_restart`: the nursery's own cancel-on-fail behaviour
(`docs/structured-concurrency.md` §*Cancellation*: *"A sibling
fiber in the same nursery crashes"*) provides exactly that
semantics. **No new primitive required.**

For `rest_for_one` (cancel children started after the failing
one), the user nests nurseries:

```kai
nursery { outer ->
  let a = outer.spawn { restartable_cell(Permanent, ..., worker_a) }
  nursery { inner ->                      # b and c live in here
    inner.spawn { restartable_cell(Permanent, ..., worker_b) }
    inner.spawn { restartable_cell(Permanent, ..., worker_c) }
  }
  # if outer crashes, the inner nursery is already closed
  # if inner crashes, b and c go down together; a survives
}
```

This is a powerful insight: **kaikai's lexical nursery scopes
already encode every supervision-strategy distinction OTP needs a
strategy enum for**. The strategy enum exists in OTP because
Erlang processes have no lexical scope. Kaikai has lexical scope.
The strategy is encoded by where the nursery boundary is drawn.

`simple_one_for_one` (dynamic worker pool) is just a nursery + a
loop spawning `restartable_cell` instances — no separate primitive.
ahu may ship a `pool(n, body)` helper if usage data motivates it,
but Tongariki does not.

## Decisions

The seven load-bearing decisions for ahu-Tongariki, each closed.

### Decision 1 — Cells, not Behaviors

A cell is `Msg → Cell[Msg] / e` — a recursive function over
messages, where the next iteration's function carries the next
state. Not a record of callbacks (the previous draft's choice),
not a protocol impl, not an effect handler.

Rationale:

- **Functional shape matches kaikai idiom.** State as recursion
  argument is how kaikai users already write `loop`-shaped code.
  No `var`, no internal mutation, no `terminate(state, reason)`
  callback that imposes a separate cleanup phase.
- **State transitions are explicit.** `counting(value)` →
  `counting(value + 1)` is a visible call; you can grep for what
  changes a cell's state. Compare to `state.value += 1` inside a
  `handle_cast` — implicit and harder to audit.
- **Behaviour switches are first-class.** A cell that goes from
  "active" to "paused" to "draining" returns a different cell
  function in each transition (`active(...)` → `paused(...)` →
  `draining(...)`). OTP's gen_server reaches for `become/3`
  hacks for this; Akka Typed adopted the recursive-function
  shape exactly because of this case. ahu inherits the
  improvement.
- **No `terminate` callback.** Cleanup is ordinary code before
  returning `done()`. There is no separate phase the framework
  runs. This eliminates the gen_server question of *"what runs
  if `terminate` itself crashes?"* — there is no `terminate`.
- **Records-of-callbacks (the previous draft) was correct under
  the OTP framing.** It composed well, kept effects visible,
  monomorphised cleanly. The pivot abandons it because the
  recursive-function shape composes equally well *and* is more
  faithful to kaikai's functional core. It is also a smaller
  surface — one type (`Cell[Msg]`), one constructor
  (`start_cell`), one terminator (`done()`).

### Decision 2 — Streams as Layer 1 (primary paradigm for data flow)

Streams ship as a first-class layer alongside cells, not as a
side-library. For request/response, ETL, and event broadcasting
(the bulk of what manutara will do), streams are structurally
better than actors.

Rationale:

- **Backpressure is the framework's problem, not the user's.**
  Streams handle demand signaling automatically; cells require
  manual `BlockSender` mailbox configuration and per-cell
  reasoning about flow.
- **Composition is algebraic.** `source |> flow1 |> flow2 |>
  sink` is type-checked end-to-end. Composing actors is ad-hoc
  message protocol design.
- **The web-framework path forces this anyway.** manutara's
  request lifecycle is a stream by structure: bytes → HTTP
  parse → route → handler → render → bytes-out. Phoenix bolted
  this on after the fact; ahu has it from the start.
- **Cells exist for what streams cannot model**: long-lived
  identity (sessions, websockets) and state that outlives a
  single message. Streams are stateless transformers; cells are
  the addressable, stateful complement.

### Decision 3 — Restart as helpers, not abstractions

ahu does not ship a `Supervisor` type, a `SupervisorSpec` record,
or a `Strategy` enum. Restart policy is a pair of helpers
(`with_restart`, `restartable_cell`); supervision strategies fall
out of where the user draws nursery boundaries.

Rationale:

- **OTP's `Strategy` enum compensates for Erlang's lack of
  lexical scope.** Kaikai has nurseries; the strategies the
  enum encodes (`one_for_one`, `one_for_all`, `rest_for_one`)
  are recoverable from nursery placement. See §*Layer 3* worked
  examples.
- **Smaller surface to learn.** A user who learns `nursery` and
  `with_restart` can build any supervision tree OTP can build.
  No second vocabulary for "but a special kind of process that
  watches other processes".
- **Composability.** A `Supervisor` type would have to be a
  `Cell` (long-lived, stateful) but its API would be different
  from regular cells (it has children, not messages). Skipping
  the type means there is one shape (cells) for every long-
  lived stateful thing.

### Decision 4 — No process registry in Tongariki, deferred to Anga Roa

Same as the OTP-style draft. `Pid[Msg]` is region-branded;
explicit handoff fits the type system. Per-nursery `Registry`
capability is the leading candidate for Anga Roa once usage
data exists.

Unchanged by the pivot — registry is a cross-cutting concern
that lives orthogonally to streams-vs-cells.

### Decision 5 — No hot code reload, ever

Same as the OTP-style draft. Kaikai compiles to native binaries
via LLVM; there is no module loader at runtime. Permanent
non-goal.

The pivot makes this even more cleanly true: cells have no
`code_change/3` callback to even consider. State migration
during deployment is a rolling-restart concern, not a framework
concern.

### Decision 6 — No distribution in Tongariki or Anga Roa

Same as the OTP-style draft. Cross-node Pids land in Orongo at
earliest.

The pivot does not change this. Distributed streams (cross-node
sources / sinks) and distributed cells (remote pids) are both
post-Orongo concerns; the design surface for either is wider than
ahu-Tongariki should absorb.

### Decision 7 — ahu-Tongariki MVP scope (revised)

**In scope for ahu-Tongariki:**

1. **Layer 1 — Streams.** `Source[T, e]`, `Flow[A, B, e]`,
   `Sink[T, R, e]`, the canonical combinators (`map`, `filter`,
   `flat_map`, `merge`, `throttle`, `buffer`), `from_list`,
   `from_listener`, `tick`, `foreach`, `fold`, `collect`.
   Demand-based backpressure with the kaikai `Overflow` enum
   for buffer policy.
2. **Layer 2 — Cells.** `Cell[Msg, e]`, `start_cell`,
   `done()`, `stop()` (graceful termination from the outside).
   The `receive { ... }` macro-free desugaring to
   `Actor.receive()` + `match`.
3. **Layer 3 — Restart helpers.** `RestartPolicy`,
   `RestartLimit`, `with_restart`, `restartable_cell`.
   Default limit `5 / 60s`.
4. **Bootstrap helper.** `run_app(root: () -> Unit / e) : Unit`
   installs `SIGINT` / `SIGTERM` handlers, opens a root
   nursery, runs `root` inside it, blocks on signal, propagates
   cancellation through the tree.
5. **Reference example.** `examples/echo/` — a tiny TCP echo
   server using `Source.from_listener` + `Flow.flat_map` to
   handle each connection inside a per-connection nursery.
   Shows: streams as the request layer, cells for connection
   state, restart wrapping the listener loop, `run_app` at the
   top.

**Out of scope for ahu-Tongariki:**

- Process registry (Anga Roa).
- Distribution (Orongo+).
- Hot reload (never).
- Specialised cell shapes (`Agent`, `Task`-equivalents). Cells
  cover them; specialisation waits for usage data.
- Pre-built `pool(n, body)` helper. Trivial to write with the
  primitives; ships only if pattern recurs in real ahu code.
- `Cell.ask(pid, msg)` synchronous-request helper. Ships in
  Anga Roa if request/reply pattern is common.
- DSL macros for cell or stream declaration. Kaikai has no
  macros.
- Pre-built telemetry hooks. Orongo, alongside kaikai's
  diagnostic JSON surface.

### Repository layout

Same shape as the OTP-style draft:

```
ahu/
  CLAUDE.md
  README.md
  VERSION
  CHANGELOG.md
  docs/
    design.md            # this document
    roadmap.md
    lane-experience-*.md
  src/
    stream.kai           # Layer 1
    cell.kai             # Layer 2
    restart.kai          # Layer 3
    app.kai              # bootstrap helper
  tests/
  examples/
    echo/                # reference: TCP echo server
```

## End-to-end MVP verification

A user with `kaikai-Tongariki` installed must be able to:

```sh
git clone github.com/lnds/ahu
cd ahu
kai build
kai test tests/
kai run examples/echo/main.kai &           # echo server boots
echo "ping" | nc localhost 8080            # → "ping\n"
kill -INT $!                               # graceful shutdown
wait                                       # exit code 0
```

If this works, ahu-Tongariki is fulfilled.

## External dependencies on kaikai

Three known gaps to coordinate with upstream:

1. **Blocking `Actor.receive()` on an empty mailbox.** Cells
   spend their lifetime parked on `receive`. Today
   `kaikai/stdlib/actor.kai` says receive on empty is a runtime
   error — needs the m8.x cooperative scheduler. Hard blocker
   for the implementation lane; not for the design.
2. **`BlockSender` mailbox policy delivery.** Same upstream
   dependency. Streams' default buffer between stages will use
   `BlockSender`; until m8.x lands, fixtures use
   `DropOldest` / `DropNewest` for buffered stages.
3. **Effect-row propagation through closure types in record
   fields.** `Source[T, e]` and `Flow[A, B, e]` carry effect
   rows in their type parameters. Kaikai's effects spec
   (`docs/effects.md` §*Effect rows*: *"Effect rows do not
   appear inside ordinary types — they only appear in the
   effect position of function types"*) implies the row is
   carried through the `() -> T / e` closure inside the type;
   the design assumes this works. If a typer-level gap
   surfaces during implementation, it goes upstream as a
   kaikai issue, not patched in ahu.

The design lane does not patch any of these.

## Not goals

- **OTP duplication.** ahu is not a port of `gen_server`,
  supervisors, or applications. The patterns are reshaped to
  kaikai's primitives, not transliterated.
- **Hot code reload.** Permanent non-goal. See Decision 5.
- **Cross-node distribution in Tongariki / Anga Roa.** See
  Decision 6.
- **Process registry in Tongariki.** Anga Roa. See Decision 4.
- **DSL macros.** Kaikai has no macros.
- **Phoenix-LiveView clone.** That is manutara's surface, not
  ahu's. ahu provides the substrate (streams + cells + restart);
  manutara picks how to expose them to view authors.
- **Specialised cell shapes** (`Agent` for value containers,
  `Task` for one-shot computations). Cells are the one shape;
  specialisations come post-Tongariki only if usage data shows
  the recursive-function form gets in the way.
- **A `Supervisor` type.** Replaced by nurseries + restart
  helpers. See Decision 3.

## Roadmap pointer

The full ahu milestone series — Tongariki / Anga Roa / Orongo /
Anakena — lives in `docs/roadmap.md` of this repository. Each
milestone has scope, definition-of-done, and sequencing
constraints against kaikai milestones.

## References

- `kaikai/docs/design.md`, `kaikai/docs/actors.md`,
  `kaikai/docs/structured-concurrency.md`,
  `kaikai/docs/effects.md`, `kaikai/docs/effects-stdlib.md`,
  `kaikai/docs/protocols.md`, `kaikai/docs/roadmap.md`,
  `kaikai/stdlib/actor.kai`, `kaikai/stdlib/spawn.kai`,
  `kaikai/CLAUDE.md` — the upstream substrate.
- Akka Typed
  (`https://doc.akka.io/docs/akka/current/typed/index.html`) —
  primary lineage for the `Cell[Msg]` shape (Akka Typed's
  `Behavior[T]`).
- Reactive Streams specification
  (`https://www.reactive-streams.org/`) — demand-based
  backpressure model for Layer 1.
- Akka Streams documentation — prior art for stream
  combinators.
- Trio (`https://trio.readthedocs.io/`), Kotlin
  `coroutineScope`, OCaml 5 Eio — structured concurrency
  ancestors that kaikai's nursery model already adopts;
  relevant here as the reason ahu does not need an OTP
  `Supervisor` type.
- Erlang/OTP design principles — the prior art ahu
  deliberately diverges from in shape while inheriting the
  patterns OTP got right.
- Joe Armstrong, *Making reliable distributed systems in the
  presence of software errors* (2003) — the OTP rationale
  document, useful for understanding what stays vs what goes.
