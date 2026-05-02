# Changelog

All notable changes to ahu are tracked in this file. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project adheres
to [Semantic Versioning](https://semver.org/) once 1.0.0 ships.

## [Unreleased]

### Added

- `src/cell.kai` — Layer 2 implementation. `StepResult[State]` sum
  type (`Continue` / `Done`), `keep` / `cell_done` constructors,
  `with_cell(initial, step, body)` constructor, and the internal
  `cell_loop` dispatcher.
- `examples/counter/main.kai` + `main.out.expected` — reference
  cell example. A counter cell receiving Increment / GetValue /
  Stop, talking to a driver via the unified `CounterMsg`
  protocol. Verifies cell creation, message dispatch, request /
  reply, and tail-recursive state threading end-to-end.
- `Makefile` — `make tier0` (compile) and `make tier1` (compile +
  run + diff against `.out.expected`). Wraps `kaic2` directly
  with `--path` for ahu's `src/` plus the kaikai stdlib.

### Changed

- `docs/design.md` §*Layer 2 — Cells*: surface revised from a
  free `start_cell : ... -> Pid[Msg]` constructor to
  `with_cell(initial, step, body)`. Reason: kaikai's region-brand
  walker (`fiber_producer_helpers` allow-list) only permits
  `fiber_spawn`, `spawn_actor`, and `alloc_for_policy` to return
  `Pid` / `Fiber` from user-code; everything else is rejected
  until full `TyBranded` propagation lands upstream. The
  `with_cell` shape mirrors kaikai stdlib's `with_mailbox` and
  fits the typer cleanly. The free `start_cell` form is added
  back once the upstream gap closes.
- `docs/design.md` §*External dependencies on kaikai*: split
  into *Closed* (3 original blockers + NetTcp v1 bonus, all in
  kaikai 0.32.0–0.34.0) and *Open* (residual gaps:
  free-`start_cell`, structured `with_cell` shutdown, effect-row
  through stream record types — none blocking, all shape the
  current API).


- Initial repository scaffolding: `README.md`, `CLAUDE.md`, `VERSION`
  (`0.0.1`), `CHANGELOG.md`, and empty `src/` / `tests/` / `examples/`
  trees.
- `docs/design.md` — design specification for ahu, the kaikai-native
  concurrency and fault-tolerance framework. Pivoted on 2026-05-02
  from an OTP-style draft to a three-layer design: streams, cells,
  and restart helpers. Pins the seven load-bearing decisions, the
  `ahu-Tongariki` MVP scope, and the rationale for diverging from OTP.
- `docs/roadmap.md` — milestone series for ahu following the Rapa Nui
  naming convention shared with kaikai (Tongariki, Anga Roa, Orongo,
  Anakena), with scope, definition-of-done, and sequencing
  constraints. Rewritten alongside the design pivot.
- `docs/lane-experience-ahu-design.md` — retrospective for the design
  lane, including the pivot from OTP-style to streams + cells +
  restart helpers and the reasoning that motivated it.

### Changed

- **2026-05-02 ecosystem rename.** The placeholder names `ahu-db` and
  `ahu-ddd` for the persistence and DDD layers were dropped in favour
  of standalone Rapa Nui names: `kohau` (inscribed wooden tablet, the
  substrate that carried the rongorongo script — maps cleanly to a
  persistence layer's substrate role) and `henua` (land / territory /
  domain — direct mapping to DDD's "domain" vocabulary). The
  `ahu-` prefix implied submodule status, but each is a separate
  framework with its own repository, roadmap, and release cycle.
  Updated `README.md`, `docs/design.md`, and `docs/roadmap.md`. The
  upstream `kaikai/docs/roadmap.md` still uses the placeholder names
  and will be updated in a coordinated kaikai PR.
- **2026-05-02 design pivot.** The first iteration of `docs/design.md`
  pinned an OTP-style framework (`Behavior` as record of callbacks,
  `Supervisor` with `one_for_one` strategy, `Application`). The
  rewritten document supersedes that draft with a three-layer
  kaikai-native design: streams as Layer 1 (the primary paradigm
  for data flow), cells as Layer 2 (recursive-function shape from
  Akka Typed), and restart helpers as Layer 3 (no `Supervisor`
  type — supervision strategies fall out of nursery placement).
  Rationale: OTP's shape compensates for Erlang runtime constraints
  (no structured concurrency, untyped messages, hot reload) that
  kaikai does not have. The earlier draft is preserved in
  `docs/design.md`'s git history.
