# ahu roadmap

Pinned 2026-05-02 alongside the design pivot. Names follow the
Rapa Nui convention shared across the lnds ecosystem
(`kaikai/docs/roadmap.md` §*Meta-roadmap*): Tongariki → Anga Roa
→ Orongo → Anakena tracks the arc from public face → daily life
→ ceremonial culmination → horizon beyond.

This document is the milestone series for ahu specifically. The
ecosystem-wide meta-roadmap (where ahu sits relative to kaikai,
kohau, henua, manutara) lives upstream in
`kaikai/docs/roadmap.md`. (As of 2026-05-02, the upstream
roadmap still references the placeholder names `ahu-db` and
`ahu-ddd`; those are scheduled to be renamed to `kohau` and
`henua` in a coordinated kaikai PR.)

> **Pivot note (2026-05-02).** This roadmap was rewritten when
> the design pivoted from OTP-style to streams + cells +
> restart-helpers. Milestone *names* (Tongariki / Anga Roa /
> Orongo / Anakena) are unchanged; *scope per milestone* was
> rewritten to match the new design. See
> `docs/lane-experience-ahu-design.md` for rationale.

## Status snapshot

- **HEAD (2026-05-03)**: ahu-Tongariki **shipped**. Three
  modules under `ahu/` (`cell.kai`, `restart.kai`,
  `app.kai`), four examples (`counter`, `pipeline`,
  `resilient_counter`, `echo`), 13 tier1 fixtures. `VERSION`
  is `0.0.1`, ready for the integrator to bump to `0.1.0`
  per CLAUDE.md §*Integrator workflow B*.
- **Current target**: `ahu-Anga Roa`. Design itself for
  Tongariki is frozen in `docs/design.md`; Anga Roa scope is
  pinned in §*Anga Roa* below, awaiting downstream user
  feedback before lanes open.
- **Cross-cutting principles** (per `CLAUDE.md`, inherited from
  kaikai):
  - Tier 1 #1 (effects in types) — covered by row-polymorphic
    cell signatures (`Cell[Msg, e]`) and stream stage signatures
    (`Source[T, e]`, etc.); defendible.
  - Tier 1 #2 (runtime efficiency) — depends on kaikai
    monomorphising the recursive-function shape of cells and
    the type-parameterised stream combinators. Closer to
    holding without footnote after kaikai #82's mailbox-helper
    RC audit (no leak per `mailbox_send`); not yet benchmarked.
  - Tier 1 #3 (fast compilation) — ahu introduces no new
    constraint solvers, no HKTs, no row polymorphism in
    constraint position. Defendible.
- **Upstream status**: all eight Tongariki blockers have closed
  upstream; see `docs/design.md` §*External dependencies on
  kaikai → Closed*. Newly available kaikai pieces relevant to
  Anga Roa lanes (fs.file v1, os.env/args, Clock default
  handler, AVL `Map` + `m[k]` sugar, multi-arg match, LLVM
  Phase 2 unbox, mailbox RC audit, **union types**) are
  catalogued in §*Newly available* of the same document.

## Milestones — ahu framework

Each milestone has scope, definition-of-done, sequencing
constraint against upstream kaikai, and one optimisation thread
(so polish does not pile up to the end).

### Tongariki — MVP

The 15-moai platform: the public face. Ship the framework with
the minimum surface that lets early adopters write a real
streaming server and recognise the result as
"kaikai-native concurrency infrastructure".

**Scope** (per `docs/design.md` §*Decision 7*):

- **Layer 1 — Streams** (`ahu/stream.kai`).
  - Types: `Source[T, e]`, `Flow[A, B, e]`, `Sink[T, R, e]`.
  - Constructors: `Source.from_list`, `Source.repeat`,
    `Source.from_listener` (TCP), `Source.tick`.
  - Flow combinators: `map`, `filter`, `flat_map`, `merge`,
    `throttle`, `buffer` (with `Overflow` policy mirroring
    kaikai's mailbox enum).
  - Sinks: `Sink.foreach`, `Sink.fold`, `Sink.collect`.
  - Demand-based backpressure end-to-end.
  - Composition operator: `|>` (kaikai's existing apply-pipe).
  - `Stream.run(pipeline)` materialises a Source-...-Sink pipeline.

- **Layer 2 — Cells** (`ahu/cell.kai`).
  - Type: `Cell[Msg, e]` (a closure in the recursive function
    shape).
  - `start_cell(body) : Pid[Msg]` constructor.
  - `done()` and `stop(pid)` for normal termination.
  - The `receive { ... }` form desugaring to `Actor.receive()`
    + match.

- **Layer 3 — Restart helpers** (`ahu/restart.kai`).
  - `RestartPolicy = Permanent | Transient | Temporary`.
  - `RestartLimit = { intensity, period }` with default
    `5 / 60s`.
  - `with_restart(policy, limit, body)` for arbitrary fiber
    bodies.
  - `restartable_cell(policy, limit, body)` for cells.

- **Bootstrap** (`ahu/app.kai`).
  - `run_app(root) : Unit` — installs `SIGINT` / `SIGTERM`
    handlers, opens root nursery, runs root inside, blocks on
    signal, propagates cancellation.

- **Reference example** (`examples/echo/main.kai`).
  - TCP echo server: `Source.from_listener(8080)` +
    `Flow.flat_map` (per-connection nursery) + per-connection
    cell holding session state. `restartable_cell` wrapping
    the listener loop. `run_app` at top.

- **Tests** (`tests/`). Tier 1 fixtures:
  - Stream end-to-end: list-source through map+filter through
    collect-sink → expected list.
  - Backpressure: producer faster than consumer with
    `BlockSender` buffer → producer parks; with `DropOldest`
    → producer continues, oldest dropped.
  - Cell lifecycle: start, send, receive reply, stop.
  - Cell crash: panic during message handling triggers
    `restartable_cell` retry under `Permanent`.
  - Restart limits: 6 panics in 60s with `5/60s` limit
    escalates the wrapper.
  - Application: `run_app` boots, blocks, exits 0 on SIGINT.

- **CI** (`Makefile` + `.github/workflows/tier1.yml`).
  - `make tier0` — `kai build` + cheap unit tests (~30–60s).
  - `make tier1` — Tier 0 + integration fixtures (~2–5min).

- **Optimisation thread**: stream-stage fusion. Kaikai's
  monomorphisation should fuse adjacent `Flow.map` /
  `Flow.filter` calls into a single transformer when the types
  permit, eliminating intermediate allocations. If the kaikai
  compiler does not do this automatically, file an upstream
  issue rather than implementing fusion in ahu.

**Definition of Done**:

1. `kai build` cleanly compiles `ahu/`, `tests/`, and
   `examples/echo/`.
2. `kai test tests/` is green.
3. The end-to-end command from `docs/design.md` §*End-to-end
   MVP verification* runs:
   ```sh
   kai build && kai test tests/ && \
   kai run examples/echo/main.kai &
   sleep 1 && echo ping | nc localhost 8080 | grep -q ping && \
   kill -INT $! && wait
   ```
4. CI green on every PR and on every push to `main`.
5. CLAUDE.md Tier 1 closure remains defendible.
6. `docs/design.md` and `docs/roadmap.md` Status snapshots
   updated to show ahu-Tongariki shipped.

**Sequencing**:

- **Cannot start until**: kaikai m8.x ships the cooperative
  scheduler (blocking `receive`, `BlockSender` delivery).
- **Recommended start gate**: `kaikai-Tongariki` shipped
  (gives `kai test`, `kai check`, `kai bench`, `kai fmt`).
- **Unlocks downstream**: `kohau-Tongariki` can start.

**Estimated cost**: ~4–6 weeks across ~3 lanes (streams +
tests, cells + restart + tests, app + echo + CI).

### Anga Roa — pre-1.0

"Hanga Roa" — the village where life happens. Polish the
framework to where teams build production systems with it.

**Scope**:

- **Process registry** — per-nursery `Registry` capability,
  designed in a dedicated `docs/registry.md` at the start of
  this milestone. Decided shape pinned with usage data from
  ahu-Tongariki users. Carrier dependency cleared upstream:
  `Map[K, V]` is now AVL-backed (O(log n)) and `m[k]` is
  sugar for `map_get`; the kaikai changelog (0.37.0
  Unreleased) explicitly notes this *"closes the unblock for
  ahu's Registry primitive"*. Error type is the canonical
  union-of-errors shape unlocked by kaikai #187:
  `type RegistryError = LookupError | RegisterError`.
- **Cell.ask helper** — synchronous request/reply pattern as
  a first-class function over the `with_mailbox` shape, if
  Tongariki demos show the pattern is common.
- **Pool helper** — `pool(n, body) : Pid[Msg]` that spawns N
  identical workers under a nursery and round-robins
  messages. Trivial layer over Tongariki primitives, ships
  only if the pattern recurs.
- **Cell behavior composition via union message types** —
  unlocked by kaikai #187 union types. A cell whose mailbox
  carries the union of per-feature message types (e.g.
  `type CombinedMsg = CounterMsg | LoggingMsg | AdminMsg`)
  delegates by `bind : Type` narrowing arms to per-layer
  handlers, without the wrapper-sum tax. Documented as the
  recommended pattern when a cell aggregates concerns; not a
  new module.
- **Stream extensions** — windowing (`Flow.window`), grouping
  (`Flow.group_by`), broadcast / fanout, error-recovery
  combinators (`Flow.recover_with`). `Flow.window` /
  `throttle` benefit from the `Clock` default handler now
  shipping in `stdlib/time.kai`. `Flow.recover_with` carries
  a `PipelineError = SourceError | TransformError | SinkError`
  union, again courtesy of kaikai #187.
- **Diagnostic surface** — pretty restart traces, cell-tree
  dump on `SIGUSR1`, structured JSON output for restart
  events. Plugs into `kaikai-Anga Roa`'s `kai lsp` and
  diagnostic JSON contract. Persistence to disk uses
  `fs.file.append` (kaikai 0.37.0 Unreleased Tier S1 #1).
- **`ahu.log` / `ahu.config`** — structured logging on top of
  `fs.file` + `Clock` (timestamped entries) and config
  loading from environment via `os.env.get`. Both stdlib
  pieces newly available post-Tongariki.
- **Reference applications** — beyond `echo`: a websocket
  chat server using cells per session + a broadcast stream;
  a back-pressured ETL pipeline reading a file and writing
  to stdout with explicit `Bounded(c, BlockSender)` buffers.
- **Optimisation thread** — stream-stage fusion measurement:
  benchmark the fused vs unfused pipelines and either
  confirm the kaikai compiler does its job or file the
  upstream gap.

**Definition of Done**:

1. `Registry` capability shape pinned and implemented;
   programs can register and look up Pids within the right
   scope.
2. At least one of (`Cell.ask`, `pool`) ships if Tongariki
   demos exercised the pattern; otherwise neither, with
   rationale documented.
3. Stream extension combinators ship with fixtures.
4. `kai lsp`-driven editor shows correct combinator type
   signatures on hover.
5. `make daily` (Tier 2) runs nightly stress fixtures:
   1k-cell pool with random restarts, stream throughput
   under saturation, registry under churn.

**Sequencing**:

- **Cannot start until**: `ahu-Tongariki` shipped and at
  least one downstream user (likely `kohau-Tongariki`) has
  reported back from real use.
- **Recommended start gate**: `kaikai-Anga Roa` shipped
  (provides `kai lsp` for the diagnostic deliverable).
- **Unlocks downstream**: nothing new beyond what Tongariki
  unlocked.

**Estimated cost**: ~6–8 weeks. Registry design is the long
pole.

### Orongo — 1.0.0

The ceremonial village on Rano Kau. Mark ahu as 1.0.0:
distribution, complete observability, no honest-target
footnotes.

**Scope**:

- **Distributed cells and streams** — cross-node Pids
  (`RemotePid[Msg]` distinct type), distributed sources /
  sinks (a stream stage on node A feeding a stage on node
  B). Depends on kaikai's `Serialize` protocol covering
  records and sum types (post-m12.8). Designed in
  `docs/distributed-ahu.md` at the start of this milestone.
- **Failure detector** — heartbeat protocol, configurable
  timeouts, partition handling.
- **Telemetry effect** — every cell emits a structured event
  for start, message-handled, restart, terminate; every
  stream stage emits per-element / per-batch events. Drains
  through a `Telemetry` effect that programs handle to log,
  trace, or push to metrics. Event payload is the union
  `type TelemetryEvent = CellEvent | StreamEvent | RestartEvent`
  (kaikai #187), so handlers can pattern-match on the
  category they care about via `bind : Type` arms and ignore
  the rest.
- **Multi-thread scheduler awareness** — `kaikai-Orongo`
  ships work-stealing across N OS threads. ahu must verify
  that cross-thread mailbox messages, restart wrappers, and
  stream stages remain correct under concurrent fault
  delivery.
- **Optimisation thread** — cross-fiber unboxed messages.
  Coordinate with kaikai-Orongo's Tier 3b unboxing — cell
  message payloads of primitive types should not box on the
  way through the mailbox.

**Definition of Done**:

1. `RemotePid[Msg]` shape pinned, implemented, exercised by a
   2-node integration test.
2. Distributed stream demonstrably works across nodes with
   backpressure preserved.
3. Failure detector running under controlled
   network-partition fixture.
4. Telemetry effect installed at `run_app` boot;
   round-trips through a sample handler.
5. `kaikai-Orongo` integration: ahu programs build under
   `--emit=llvm` with no perf regression vs `--emit=c`.

**Sequencing**:

- **Cannot start until**: `kaikai-Orongo` is in flight
  (Serialize for records, multi-thread scheduler,
  cross-fiber unboxing all upstream).
- **Unlocks downstream**: `manutara-Orongo` can rely on
  distributed ahu.

**Estimated cost**: ~3–4 months. Distribution is the long pole.

### Anakena — post-1.0 horizon

The horizon-facing milestone. Reach beyond the founding
platforms.

**Scope**:

- **Cross-platform support** — Linux arm64, macOS x86_64,
  Windows. Depends on kaikai-Anakena.
- **WASM target** — ahu running in browser. Limited
  surface (no signal handlers, no FFI to libc, single-thread
  by construction); ahu adapts where it can and documents
  the reduced contract.
- **Per-target performance tuning**.
- **Extended observability** — flame-graph integration with
  whatever profiling story kaikai-Anakena pins.
- **Package manager integration** — once kaikai-Anakena
  ships `kai new` / `kai add`, ahu publishes to the
  registry as the canonical install path.
- **Optimisation thread** — close `--emit=c` / `--emit=llvm`
  gap for ahu programs across every target.

**Definition of Done**:

1. CI matrix runs all 5 platforms.
2. `kai add ahu` works against the registry once
   kaikai-Anakena ships it.
3. ahu telemetry integrates with the kaikai profiling
   tooling.

**Sequencing**:

- **Cannot start until**: `kaikai-Anakena` is in flight.

**Estimated cost**: variable / ongoing per platform.

## Sequencing summary

| Milestone | Can start when | Unlocks |
|---|---|---|
| `ahu-Tongariki` | `kaikai-Tongariki` shipped + kaikai m8.x cooperative scheduler in main | `kohau-Tongariki` |
| `ahu-Anga Roa` | `ahu-Tongariki` shipped + 1+ downstream user feedback + `kaikai-Anga Roa` shipped (for `kai lsp`) | `kohau-Anga Roa`; manutara can run against either ahu milestone |
| `ahu-Orongo` | `kaikai-Orongo` in flight (Serialize for records, multi-thread scheduler, cross-fiber unboxing) | `manutara-Orongo` |
| `ahu-Anakena` | `kaikai-Anakena` in flight (cross-platform matrix) | downstream Anakena milestones |

Each downstream project does not wait for ahu's 1.0.0 — it
waits for ahu's Tongariki at minimum (the same rule kaikai's
roadmap pins for the meta-stack).

## What this doc is NOT

- Not the roadmap for kohau, henua, or manutara.
- Not a calendar.
- Not a contract.
- Not exhaustive — items not listed get their own design doc
  when they become load-bearing.
