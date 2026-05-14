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

`StepResult[State]`, `keep`, `cell_done`, `with_cell`.
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

- **`cell.ask` helper** — synchronous request/reply over the
  `with_mailbox` shape. Adds a function, not a new
  abstraction. Worth shipping if usage data shows the
  request/reply pattern is common enough that hand-rolling it
  per cell becomes noise.
- **Behavior composition via union message types** — a cell
  whose mailbox carries `CounterMsg | LoggingMsg | AdminMsg`
  delegates to per-layer handlers via `bind : Type` narrowing.
  Documented as a recommended pattern rather than a new
  module. Depends on kaikai's union types being stable.

### Layer 3 — Restart helpers (state: **shipped**, ahu/restart.kai)

`RestartPolicy` (`Permanent` / `Transient` / `Temporary`),
`RestartLimit`, `with_restart`, `restartable_cell`. Default
limit `5 / 60s`. Spec: `docs/design.md` §*Layer 3*.

Tier1 fixtures exercise the three policies under crash and
escalation conditions. Currently **red against kaikai 0.56.x**
because of a runtime regression in `spawn_actor`
(`kaikai#570`) — every fixture that touches an actor primitive
crashes on entry. Tier0 (compile-only) is green. See
`docs/known-regressions.md`.

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

### Logging (state: **idea**)

`ahu/log.kai` — structured key/value events on top of
`stdlib/log.kai`'s four-level surface. Adds level filtering,
structured fields, async fan-out to multiple sinks
(stderr + `fs.file`), timestamp via `Clock`. The stdlib
`log.kai` comment explicitly points at ahu as the home for
this wrapper. Concrete enough that a lane could open at any
time.

### Config (state: **idea**)

`ahu/config.kai` — config loading from environment via
`os.env.get`. Possibly small enough that stdlib direct calls
suffice and no ahu module is justified. Decide once real
consumers show what shape of config they want.

### Reference applications (state: **partial**)

Shipped in `examples/`: `counter` (request/reply cell),
`pipeline` (Layer 1 ETL), `resilient_counter` (restart fault
tolerance), `echo` (TCP echo, all layers + NetTcp).

**Possible additions** (no commitment):

- Websocket chat using cells per session + a broadcast
  stream.
- Back-pressured file → stdout ETL with explicit
  `Bounded(c, BlockSender)` buffers.

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

Live tracking lives in `docs/known-regressions.md`. Summary
of what currently blocks ahu against kaikai 0.56.x:

- **`kaikai#570`** — `spawn_actor` runtime segfault. Blocks
  tier1: 12 of 13 fixtures crash on entry. Hard block on any
  component that uses actor primitives.
- **`kaikai#567`** — `kai build` cannot resolve a package's own
  modules from sibling dirs. Worked around with
  `ahu = { path = "." }` in `kai.toml`; remove when fixed.
- **`kaikai#571`** — LLVM backend "lambda info missing"
  diagnostic on nested lambdas with `with_mailbox`. Cosmetic.

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
