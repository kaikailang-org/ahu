# ahu roadmap

ahu is organised by **component**, not by milestone. Each
component has its own state, its own next moves, and its own
set of upstream dependencies. Components advance independently;
the roadmap is the union of those states, not a calendar.

The repository version stays `0.0.1` indefinitely. There are no
release gates, no definitions-of-done, no milestone names —
just components with one of four states.

## Component states

| State | Meaning |
|---|---|
| **idea** | sketched in this doc; no design pinned yet |
| **designed** | shape pinned in `docs/design.md`; no code |
| **shipped** | implementation present in `ahu/`; fixtures exist |
| **blocked** | shape pinned but cannot ship — upstream gap, see `docs/known-regressions.md` |

A component never regresses by itself; it can be marked
**blocked** if a working dependency stops working (a kaikai
release that breaks a runtime path is the canonical case).

## Components

### Layer 1 — Streams (state: **designed**, no ahu code)

The pipeline shape ships against kaikai's stdlib + language
sugars (`[a..b]`, `|`, `|>`, `list.map` / `filter` / `foldl`,
each with row-poly callbacks). ahu's contribution at this
layer is convention plus the reference fixture in
`tests/stream_pipeline.kai`. No `ahu/stream.kai` exists and
none is planned for eager pipelines — see `docs/design.md`
§*Layer 1*.

**Possible follow-ups** (no commitment):

- **Lazy / unbounded sources** as a dedicated `ahu/source.kai`
  module — `from_listener(port)`, `tick(every)`,
  `from_websocket(ws)`. Needs either upstream support for
  row-poly type parameters in records (so `Source[T, e]`
  records become expressible) or a function-value-based
  encoding. Out of reach until kaikai's row polymorphism
  story closes.
- **Stream extensions** — windowing, grouping, broadcast/fanout,
  error-recovery combinators. `window` / `throttle` would lean
  on kaikai's `Clock` default handler (now in
  `stdlib/time.kai`). `recover_with` would carry a
  `PipelineError` union (kaikai's union types make this
  expressible).

### Layer 2 — Cells (state: **shipped**, ahu/cell.kai)

`StepResult[State]`, `keep`, `cell_done`, `with_cell`, `ask`.
A cell is a fiber + typed mailbox + recursive step function;
the user writes `(State, Msg) -> StepResult[State] / e` and
ahu drives it. Spec: `docs/design.md` §*Layer 2*.

**Constraint surfaced under kaikai 0.56**: `with_cell` shares a
single open row variable `e` between step and body. Callers
whose step and body diverge must reconcile rows at the call
site (see `examples/echo/main.kai` for the canonical
workaround). This is structural — kaikai allows only one open
row variable per row, and it must be the last item.

**Possible follow-ups**:

- **Cross-mailbox request/reply** — `ask` today requires the
  reply to be a variant of the cell's own `Msg` union, because
  kaikai's `Actor.send : Pid[T] -> T` ties the destination pid
  type to the active handler's Msg. A typed reply-channel
  primitive distinct from the per-fiber mailbox would lift the
  constraint; not implementable at user level today.
- **Behavior composition via union message types** — a cell
  whose mailbox carries `CounterMsg | LoggingMsg | AdminMsg`
  delegates to per-layer handlers via `bind : Type` narrowing.
  Documented as a recommended pattern rather than a new
  module. Depends on kaikai's union types being stable.

### Layer 3 — Restart helpers (state: **shipped**, ahu/restart.kai)

`RestartPolicy` (`Permanent` / `Transient` / `Temporary`),
`RestartLimit`, `with_restart`, `with_restart_backoff`,
`restartable_cell`. Default limit `5 / 60s`. Spec:
`docs/design.md` §*Layer 3*.

`with_restart_backoff` adds a `Duration` parameter that sleeps
between restarts via the `Clock` effect (cooperative under
kaikai 0.66+'s R1 reactor — other fibers keep running during
the backoff wait, departure from OTP's supervisor-blocks
behaviour). v1 ships fixed `Duration`; variable strategies
(Linear / Exponential / DecorrelatedJitter) layer on top.

Tier1 fixtures exercise the three policies under crash and
escalation conditions. **Green under both backends (C and LLVM)
on kaikai 0.59.0.** The LLVM regressions that haunted 0.56.x
through 0.58 (`kaikai#570`, `#582`, the `Link`/`Monitor`
residue) are all closed; the Makefile no longer pins the
backend. See `docs/known-regressions.md` for the historical
arc.

### Bootstrap (state: **shipped**, ahu/app.kai)

`run_app(root) : Unit / Console + Spawn` — v1 placeholder that
runs `root` directly. Signal-driven shutdown
(`SIGINT`/`SIGTERM` triggering cancellation of the root fiber
so `Cancel` handlers run) is deferred — see
`docs/design.md` §*Bootstrap*.

**Possible follow-ups**:

- **Signal-based shutdown** — install `SIGINT`/`SIGTERM`
  handlers, open root nursery, run root inside, park on
  `Signal.await()`, propagate cancellation. Depends on
  kaikai's `Signal` effect (landed 0.36.x) and a stable
  trap-exit / nursery cancellation story.

### Process registry (state: **idea**)

Per-nursery `Registry` capability. Carrier dependencies have
landed upstream: `Map[K, V]` is AVL-backed (O(log n)) and
`m[k]` is sugar for `map_get`. Error shape:
`type RegistryError = LookupError | RegisterError`, expressible
via kaikai's union types.

Design pending in `docs/registry.md` when ahu has real-world
usage that motivates the API. Held back deliberately — global
state and registries are easy to add and hard to remove. See
`docs/design.md` §*Decision 4* on why ambient state is rejected
as the default.

### Pool helper (state: **idea**)

`pool(n, body) : Pid[Msg]` — N identical workers under a
nursery, round-robin dispatch. A thin layer over Layer 2 + 3
primitives. Ships only if the pattern recurs in real
applications. No commitment.

### Diagnostics (state: **idea**)

Pretty restart traces, cell-tree dump on `SIGUSR1`, structured
JSON output for restart events. Would plug into kaikai's
`kai lsp` diagnostic JSON contract when that surface
stabilises. Persistence to disk via `fs.file.append`
(available in stdlib).

### Logging (state: **shipped**, ahu/log.kai)

Structured key/value events on top of `stdlib/log.kai`'s
four-level surface: `LogLevel`, `Field` (closed sum over
String/Int/Bool), `log.{debug,info,warn,error}_kv(msg, fields)`
emitting logfmt-like lines through the existing `Log` ops, and
pure formatters (`format_field`, `format_fields`,
`format_event`) for callers that render outside the `Log`
effect. The stdlib `log.kai` comment that pointed at ahu as the
home for this wrapper is now satisfied for the structured-fields
half. Spec: `ahu/log.kai` header.

**Possible follow-ups**:

- **Level filtering as a handler combinator**
  (`with_min_level`). The natural shape — a `Log` handler that
  drops or re-emits via `Log.X` — re-enters itself; a clean
  implementation needs either a `StructuredLog` effect parallel
  to `Log` or an outer-handler-delegate primitive that has not
  been designed upstream. Filtering today belongs in the user's
  own `Log` handler.
- **Async fan-out to multiple sinks** (stderr + `fs.file`).
  Depends on the kaikai m8.x reactor for non-blocking file
  writes; sync fan-out is straightforward in a user `Log`
  handler.
- **Wider field types** — `FloatField`, `BytesField`, etc. One-
  line additions to the `Field` sum once a real consumer needs
  them.

### Config (state: **idea**)

`ahu/config.kai` — config loading from environment via
`os.env.get`. Possibly small enough that stdlib direct calls
suffice and no ahu module is justified. Decide once real
consumers show what shape of config they want.

### Reference applications (state: **partial**)

Shipped in `examples/`: `counter` (request/reply cell),
`pipeline` (Layer 1 ETL), `resilient_counter` (restart fault
tolerance), `echo` (TCP echo, all layers + NetTcp),
`backpressured_etl` (`Bounded(c, BlockSender)` mailbox between
producer and consumer fibres; trace witnesses the producer
parking when slots fill).

**Possible additions** (no commitment):

- Websocket chat using cells per session + a broadcast
  stream.
- Cell-mediated back-pressure once `spawn_actor_policy` lands
  upstream (`stdlib/actor.kai` §`spawn_actor` v1
  simplification). The current `backpressured_etl` deliberately
  avoids cells for that reason; once the upstream gap closes,
  a sibling example can demonstrate the same pattern with a
  bounded cell mailbox.

### Distribution (state: **idea**, far-future)

Cross-node Pids (`RemotePid[Msg]` as a distinct type),
distributed sources/sinks, heartbeat-based failure detector,
multi-thread scheduler awareness. Depends on kaikai's
`Serialize` protocol covering records and sum types, plus
work-stealing across OS threads — neither is upstream yet.

When this becomes concrete, a `docs/distributed-ahu.md`
design doc opens. Not now.

### Cross-platform & WASM (state: **idea**, far-future)

Linux arm64, macOS x86_64, Windows, browser/WASM. Depends on
kaikai's own cross-platform story. The WASM target carries a
reduced contract (no signal handlers, no FFI to libc,
single-thread); ahu documents the gap rather than papering
over it.

## Upstream dependencies — current open items

Live tracking lives in `docs/known-regressions.md`. Against
kaikai 0.59.0: **no active blockers.** The LLVM regression arc
that ran from 0.56.x through 0.58 (`kaikai#570`, `#582`, the
`Link`/`Monitor` residue, the `#571` cosmetic diagnostic) is
fully closed. tier1 passes under both backends; the Makefile
no longer pins one.

## Optimisation themes (no ordering)

These cross-cut the components and matter whenever the
implementation hits one of them:

- **Stream-stage fusion**. Kaikai's monomorphisation should
  fuse adjacent `Flow.map` / `Flow.filter` into a single
  transformer when types permit. If the compiler does not do
  this, file an upstream issue rather than implementing
  fusion in ahu.
- **Cross-fiber unboxed messages**. Cell message payloads of
  primitive types should not box on the way through the
  mailbox. Coordinate with whatever kaikai unboxing pass
  exists at the time.

## What this doc is NOT

- Not a contract.
- Not a calendar.
- Not exhaustive — items not listed get their own design doc
  when they become load-bearing.
- Not the roadmap for kohau, henua, or manutara.
- Not a milestone series. ahu does not have milestones; each
  component advances independently.
