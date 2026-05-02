# ahu roadmap

Pinned 2026-05-02 alongside the initial design lane. Names follow
the Rapa Nui convention shared across the lnds ecosystem
(`kaikai/docs/roadmap.md` §*Meta-roadmap*): Tongariki → Anga Roa →
Orongo → Anakena tracks the arc from public face → daily life →
ceremonial culmination → horizon beyond.

This document is the milestone series for ahu specifically. The
ecosystem-wide meta-roadmap (where ahu sits relative to kaikai,
ahu-db, ahu-ddd, manutara) lives upstream in
`kaikai/docs/roadmap.md`.

## Status snapshot

- **HEAD**: `0f30f40 ahu: M1 — initial repository scaffolding` (no
  implementation; design lane in flight on `ahu-design-v1`).
- **Current target**: `ahu-Tongariki` (MVP definition). The design
  itself lives in `docs/design.md`.
- **Cross-cutting principles** (per `CLAUDE.md`, inherited from
  kaikai):
  - Tier 1 #1 (effects in types) — covered by ahu's row-polymorphic
    callback shape; defendible.
  - Tier 1 #2 (runtime efficiency) — depends on kaikai
    monomorphising `BehaviorSpec` records per use site; not yet
    measured.
  - Tier 1 #3 (fast compilation) — ahu does not introduce
    constraint solvers, HKTs, or row-polymorphic dispatch beyond
    what kaikai already provides; defendible.
- **Upstream blockers for implementation**: see
  `docs/design.md` §*External dependencies on kaikai* — the
  blocking-receive and `BlockSender` paths require kaikai m8.x's
  cooperative scheduler; until then the ahu-Tongariki
  implementation lane stays scoped to fixtures that match the
  inline-eager scheduler.

## Milestones — ahu framework

Each milestone has scope, definition-of-done, sequencing
constraint against upstream kaikai, and one optimisation thread
(so polish does not pile up to the end).

### Tongariki — MVP

The 15-moai platform: the public face. Ship the framework with
the minimum surface that lets early adopters write a real
supervised application and recognise the result as
"OTP for kaikai".

**Scope** (per `docs/design.md` §*Decision 6*):

- `src/behavior.kai` — the `BehaviorSpec` record, the
  `BehaviorMsg[Call, Cast]` envelope, `start_behavior`
  constructor, the canonical receive loop dispatching `Call` /
  `Cast` / `Down`, and `terminate` invocation on shutdown.
- `src/supervisor.kai` — `SupervisorSpec`, `ChildSpec`,
  `RestartPolicy` (`Permanent` / `Transient` / `Temporary`),
  `ShutdownTimeout`, `intensity / period` with sensible defaults
  (5 / 60 as a starting heuristic), `start_supervisor`,
  `one_for_one` strategy.
- `src/application.kai` — `Application` shape, `SIGINT` /
  `SIGTERM` graceful-shutdown wiring, root supervisor lifecycle,
  exit-code propagation.
- `examples/counter/` — counter behavior under a supervisor,
  driven by an application. Shows callback effect rows
  (`Console.print(...)` for trace lines), supervisor restart on
  intentional crash, application graceful shutdown.
- `tests/` — Tier 1 fixtures listed under `docs/design.md`
  §*Test criteria*: init-once, call/cast/down delivery, terminate
  on crash, one_for_one restart, transient-vs-permanent, root
  supervisor signal handling.
- `Makefile` — `make tier0` (selfhost the design / typecheck
  src/) and `make tier1` (Tier 1 fixtures via `kai test`).
- *Optimisation thread for this milestone*: callback specialisation.
  Confirm the kaikai compiler monomorphises the `BehaviorSpec`
  record and inlines each callback at the dispatch site so a
  behavior with one Cast handler costs the same as a hand-rolled
  receive loop. If it does not, file an upstream issue against
  kaikai's monomorphisation and gate on the fix.

**Definition of Done**:

1. `kai build` cleanly compiles `src/`, `tests/`, and
   `examples/counter/`.
2. `kai test tests/` is green (Tier 1 fixtures all pass).
3. The end-to-end command from `docs/design.md` §*End-to-end MVP
   verification* runs to completion:
   ```sh
   kai build && kai test tests/ && \
   kai run examples/counter/main.kai &
   sleep 1 && kill -INT $! && wait
   # exit code 0
   ```
4. CI green on every PR and on every push to `main`. The CI shape
   mirrors kaikai's `tier1.yml` and runs `make tier0 && make
   tier1`.
5. CLAUDE.md Tier 1 closure remains defendible — no new footnotes,
   no new "we lied" entries.
6. `docs/design.md` and `docs/roadmap.md` Status snapshots both
   updated to show ahu-Tongariki shipped.

**Sequencing**:

- **Cannot start until**: kaikai m8.x ships the cooperative
  scheduler (so blocking `Actor.receive()` and `BlockSender`
  work). Until then, ahu-Tongariki implementation can scope
  fixtures to the inline-eager scheduler subset, but the
  end-to-end DOD requires the full scheduler.
- **Recommended start gate**: `kaikai-Tongariki` shipped. That
  gives `kai test`, `kai check`, `kai bench`, `kai fmt` available
  for ahu development from day one.
- **Unlocks downstream**: `ahu-db-Tongariki` can start once
  ahu-Tongariki ships.

**Estimated cost**: ~3–4 weeks of agent work distributed across
~3 lanes (behavior + tests, supervisor + tests, application +
counter example + CI).

### Anga Roa — pre-1.0

"Hanga Roa" — the village where life happens. Polish the
framework to where teams (not just hobbyists) build production
systems with it.

**Scope**:

- **Other supervision strategies** — `one_for_all`,
  `rest_for_one`, `simple_one_for_one`. Each in its own sub-lane.
  The first two require modelling child startup-order as
  load-bearing; `simple_one_for_one` requires dynamic child
  specs and pulls in registry design (next bullet).
- **Process registry** — the proper shape decided with usage
  data from ahu-Tongariki users. Leading candidate per
  `docs/design.md` §*Decision 3*: per-nursery `Registry`
  capability with explicit handoff for cross-supervisor sharing.
  Final shape pinned in a dedicated design doc
  (`docs/registry.md`) at the start of this milestone.
- **Specialised behaviours** — `Agent` (single-state value with
  get/update API), `Task` (one-shot computation with `await`),
  `GenStateMachine` (FSM-shaped behaviour). Each is a layer on
  top of `Behavior` — no new primitives, just specialisations
  with smaller surfaces. Designed only after at least three
  ahu-Tongariki demos exist showing the underlying pattern.
- **Diagnostic surface** — pretty `terminate` traces, supervision
  tree dump on `SIGUSR1` (or kaikai equivalent), structured
  JSON output for behavior-startup events. Plugs into
  kaikai-Anga Roa's `kai lsp` / `m11 diagnostics quality pass`
  contract.
- **Reference applications** — beyond `counter`: a request/reply
  worker pool, a back-pressured pipeline using `BlockSender`,
  a keepalive-style health-check supervisor. These ship in
  `examples/` and double as integration fixtures.
- *Optimisation thread*: scheduler-aware mailbox sizing.
  Profile real ahu-Anga Roa applications and tune the default
  mailbox capacity (currently TBD — likely `1024` per the kaikai
  `spawn_actor_default` shape) to whatever the data shows.

**Definition of Done**:

1. All four restart strategies (`one_for_one`, `one_for_all`,
   `rest_for_one`, `simple_one_for_one`) ship with fixtures.
2. `Registry` capability shape pinned and implemented; ahu
   programs can register and look up Pids within the right
   scope.
3. At least one specialised behaviour (`Agent` is the strongest
   candidate) ships behind a small wrapper over `Behavior`.
4. `kai lsp`-driven editor shows correct callback signatures on
   hover for `BehaviorSpec` fields.
5. `make daily` (Tier 2) runs nightly stress fixtures: 1k-child
   supervisor, mailbox saturation under `BlockSender`, link
   cascade, `Transient` vs `Permanent` restart-storm window.

**Sequencing**:

- **Cannot start until**: `ahu-Tongariki` shipped and at least
  one downstream user (probably `ahu-db-Tongariki`) has reported
  back from real use.
- **Recommended start gate**: `kaikai-Anga Roa` shipped. That
  gives `kai lsp` for the diagnostic deliverable.
- **Unlocks downstream**: nothing new beyond what
  `ahu-Tongariki` already unlocked. `ahu-db-Anga Roa` and
  `manutara` can begin in parallel against either ahu milestone.

**Estimated cost**: ~6–8 weeks. Registry design is the long
pole; the three new strategies parallelise.

### Orongo — 1.0.0

The ceremonial village on Rano Kau. Mark ahu as 1.0.0:
distribution, complete observability, no honest-target
footnotes.

**Scope**:

- **Distributed actors** — cross-node Pids, node-up / node-down
  events, distributed supervision, handoff protocols. Depends on
  kaikai's `Serialize` protocol covering records and sum types
  (currently scoped post-m12.8 in
  `kaikai/docs/protocols.md` §*Stdlib protocols* row 5). Designed
  in a dedicated `docs/distributed-actors.md` upstream first
  (kaikai), then layered into ahu via a new `RemoteBehavior`
  abstraction and a `RemotePid[Msg]` distinct type that respects
  region-brand at node boundaries.
- **Failure detector** — heartbeat protocol, configurable
  timeouts, partition handling. Reuses whichever shape
  `docs/distributed-actors.md` lands upstream.
- **Telemetry / observability hooks** — every behavior emits a
  structured event for start, callback enter/exit, mailbox depth,
  termination cause. Drains into a `Telemetry` effect that
  programs can handle to log, trace, or dispatch into
  metrics. Ties into kaikai-Orongo's profiling tooling.
- **Multi-thread scheduler awareness** — kaikai-Orongo ships a
  work-stealing scheduler across N OS threads (per
  `kaikai/docs/roadmap.md` §*Orongo*). ahu must verify that
  cross-thread mailbox messages still respect typing and that
  supervisor restart is safe under concurrent fault delivery.
- *Optimisation thread*: cross-fiber unboxed messages.
  Coordinate with kaikai-Orongo's Tier 3b unboxing — `Cast`
  payloads of primitive types should not box on the way through
  the mailbox.

**Definition of Done**:

1. `RemotePid[Msg]` shape pinned, implemented, and exercised by
   a 2-node cross-machine integration test.
2. Distribution failure detector running under controlled
   network-partition fixture.
3. Telemetry effect installed at default Application boot;
   structured events round-trip through a sample handler that
   prints them to stdout.
4. Tier 1 #1, #2, #3 fully defendible without new footnotes.
5. `kaikai-Orongo` integration: ahu programs build under
   `--emit=llvm` with no perf regression vs `--emit=c`.

**Sequencing**:

- **Cannot start until**: `kaikai-Orongo` is in flight. The
  `Serialize` protocol gap, the multi-thread scheduler, and the
  cross-fiber unboxing all land upstream first.
- **Unlocks downstream**: `manutara-Orongo` can rely on a
  distributed ahu.

**Estimated cost**: ~3–4 months. Distribution is the long pole;
telemetry and multi-thread integration parallelise.

### Anakena — post-1.0 horizon

The historical landing beach of Hotu Matu'a — the
horizon-facing milestone. Reach beyond the founding platforms.

**Scope**:

- **Cross-platform support** — Linux arm64, macOS x86_64,
  Windows. Depends on kaikai-Anakena making each a first-class
  target.
- **WASM target** — ahu running in the browser is a real ask
  once kaikai-Anakena ships WASM. Limited surface (no
  signal handlers, no FFI to libc, single-thread by
  construction); ahu adapts where it can and documents the
  reduced contract elsewhere.
- **Per-target performance tuning** — aarch64-specific behavior
  dispatch, WASM-size optimisation for the framework runtime
  footprint.
- **Extended observability** — flame-graph integration with
  whatever profiling story kaikai-Anakena pins.
- **Package manager integration** — once kaikai-Anakena ships
  `kai new` / `kai add`, the ahu library publishes to that
  registry as the canonical install path. Until then, vendoring
  via git submodule is the documented workflow.
- *Optimisation thread*: same as kaikai-Anakena — close the gap
  between `--emit=c` and `--emit=llvm` for ahu programs across
  every supported target.

**Definition of Done**:

1. CI matrix runs all 5 platforms (the founding two plus Linux
   arm64, macOS x86_64, Windows, plus WASM as a separate path).
2. `kai add ahu` works against the kaikai package registry once
   kaikai-Anakena ships it.
3. ahu telemetry integrates with whichever profiling tool
   kaikai-Anakena standardises on.

**Sequencing**:

- **Cannot start until**: `kaikai-Anakena` is in flight. Each
  platform target is its own sub-lane upstream first.

**Estimated cost**: variable / ongoing — each platform is its
own sub-lane, gated on kaikai-Anakena's matrix.

## Sequencing summary

| Milestone | Can start when | Unlocks |
|---|---|---|
| `ahu-Tongariki` | `kaikai-Tongariki` shipped + kaikai m8.x cooperative scheduler in main | `ahu-db-Tongariki` |
| `ahu-Anga Roa` | `ahu-Tongariki` shipped + 1+ downstream user feedback + `kaikai-Anga Roa` shipped (for `kai lsp`) | `ahu-db-Anga Roa`; manutara can run against either ahu milestone |
| `ahu-Orongo` | `kaikai-Orongo` in flight (Serialize for records, multi-thread scheduler, cross-fiber unboxing all upstream) | `manutara-Orongo` |
| `ahu-Anakena` | `kaikai-Anakena` in flight (cross-platform matrix) | downstream Anakena milestones |

Each downstream project does not wait for ahu's 1.0.0 — it
waits for ahu's Tongariki at minimum (the same rule kaikai's
roadmap pins for the meta-stack). This unlocks parallelism
across the lnds tree once each layer's MVP ships.

## What this doc is NOT

- Not the roadmap for ahu-db, ahu-ddd, or manutara. Each owns its
  own `docs/roadmap.md` once the project starts.
- Not a calendar. Estimates assume each milestone has its primary
  agent focus; parallel work shifts the cost.
- Not a contract. Scope shifts item-by-item as upstream kaikai
  decisions and downstream consumer needs evolve.
- Not exhaustive. Items not listed (telemetry detail, specific
  `Registry` shape, distribution wire format) get their own
  design doc when they become load-bearing.
