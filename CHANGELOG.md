# Changelog

All notable changes to ahu are tracked in this file. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project adheres
to [Semantic Versioning](https://semver.org/) once 1.0.0 ships.

## [Unreleased]

### Added

- `tests/stream_pipeline.kai` — canonical Layer 1 pipeline
  fixture exercising `[0..5]` range literal + `|` map-pipe +
  `|>` apply-pipe + `list.filter` / `list.foldl` with an
  effectful callback (`Console`). Total output `total=24`
  locked in `.out.expected`. tier1 now runs 8 fixtures.
- `Makefile` — prelude chain expanded to mirror `bin/kai`'s
  full set (`encoding/*`, `collections/*`, `math/*`,
  `decimal`, `money`, `uuid`, `regexp`, `path` on top of
  the original `core/*` / `protocols` / `effects` /
  `random`). Without this, `list.X` dotted module paths do
  not resolve.

### Changed

- `docs/design.md` §*Layer 1 — Streams* rewritten. Original
  sketch had `Source[T, e]` / `Flow[A, B, e]` /
  `Sink[T, R, e]` records carrying effect rows in their
  type parameters; that shape does not type-check under
  current kaikai (effect rows live only in function-type
  effect positions). Replaced with the honest reality:
  ahu-Tongariki ships ZERO stream-layer code; the pipeline
  combinators all live in kaikai stdlib + language syntax
  (`[a..b]` literal, `|` map-pipe, `|>` apply-pipe,
  `list.map / filter / foldl / foreach / ...`). Documents
  what is NOT in this layer (lazy / unbounded sources like
  TCP listeners — those need upstream row-poly type
  parameters in records and are post-Tongariki) and why
  ahu does not re-export `list.*` under a `stream.*` alias
  (canonical spelling stays canonical).

- `docs/lane-experience-ahu-tongariki-cells-restart.md` —
  consolidated retrospective for the Layer 2 (cells) and
  Layer 3 (restart) implementation lanes (PRs `#2` and `#3`).
  Documents what landed, what design discoveries updated the
  spec, the four kaikai upstream issues filed during the
  work (`#103`, `#104`, `#106`, `#107`), what worked well,
  what did not, and what to do next.

### Changed

- `docs/design.md` §*External dependencies on kaikai*:
  upgraded from "two open gaps" to "four open issues, each
  with a `lnds/kaikai#NNN` cross-reference and a stated
  ahu-side workaround". Adds the runs-on-cleanup-lane
  finding `#107` (missing `Signal` effect — blocks
  `run_app`) alongside the three issues filed during the
  cells + restart lanes (`#103` / `#104` / `#106`).
  Status header at the top of the doc updated to show
  the Tongariki MVP is structurally 60% done with the
  remaining 40% upstream-gated.
- `docs/design.md` §*End-to-end MVP verification*: command
  trace updated to use `make tier1` (which works today
  against the Layer 2 + Layer 3 fixtures) and to flag the
  TCP echo step as gated on Layer 1 / `lnds/kaikai#106`.

- `src/restart.kai` — Layer 3 implementation. `RestartPolicy`
  (`Permanent` / `Transient` / `Temporary`), `RestartLimit(Int)`,
  `Outcome` (`Completed` / `Escalated`), `default_limit`, and
  `with_restart(policy, limit, body) : Outcome / ...`. Builds
  on kaikai's trap-exit semantics: the supervisor sets
  `fiber_set_trap_exit(true)`, spawns the body in a child
  fiber that links back via `Link.link(parent)`, and observes
  termination through the supervisor's String mailbox.
- `tests/restart_temporary_crash.kai` — fixture covering
  `Temporary` policy + body that crashes once → no restart,
  outcome `Completed`. Exercises trap-exit "Crashed"
  delivery.
- `tests/restart_transient_normal.kai` — fixture covering
  `Transient` policy + body that exits Normal → no restart,
  outcome `Completed`. Exercises trap-exit "Normal" delivery
  via the same channel.
- `tests/restart_intensity_escalate.kai` — fixture covering
  the intensity-exceeded path. Permanent policy + body that
  always crashes + intensity=2 → 2 body runs, then outcome
  `Escalated`. Verifies the limit-counting and the clean
  return-value escalation contract.
- `Makefile`: pattern rules now depend on every file under
  `src/*.kai` so adding new ahu modules automatically
  invalidates dependent fixtures.

### Changed

- `src/cell.kai` — Layer 2 implementation. `StepResult[State]` sum
  type (`Continue` / `Done`), `keep` / `cell_done` constructors,
  `with_cell(initial, step, body)` constructor, and the internal
  `cell_loop` dispatcher.
- `examples/counter/main.kai` + `main.out.expected` — reference
  cell example. A counter cell receiving Increment / GetValue /
  Stop, talking to a driver via the unified `CounterMsg`
  protocol. Verifies cell creation, message dispatch, request /
  reply, and tail-recursive state threading end-to-end.
- `Makefile` — `make tier0` (compile every fixture) and
  `make tier1` (compile + run + diff against `.out.expected`).
  Discovers fixtures under both `tests/*.kai` and
  `examples/*/main.kai` automatically. Wraps `kaic2` directly
  with `--path` for ahu's `src/` plus the kaikai stdlib.
- `tests/cell_done_first.kai` — fixture covering the `Done` path
  (cell exits on first message via request/ack).
- `tests/cell_state_record.kai` — fixture covering record-typed
  state threading (counter inside a `Stats { name, count }`
  record).
- `tests/cell_behavior_switch.kai` — fixture covering the
  load-bearing claim of the design: behavior switching encoded
  as a sum-typed state (`Active(v)` ↔ `Paused(v)`). Verifies
  `Tick` is dropped while paused and resumed-then-incremented
  arrives at `Active(v + 1)`.
- `.github/workflows/tier1.yml` — CI workflow that checks out a
  fresh `lnds/kaikai` HEAD on every run, bootstraps stages
  0/1/2, then runs `make tier1` against ahu. The `kaikai_ref`
  workflow input lets a manual run pin a specific kaikai SHA
  for reproducibility (default is `main`). Requires
  `KAIKAI_REPO_TOKEN` secret while `lnds/kaikai` is private.

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
