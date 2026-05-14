# Changelog

All notable changes to ahu are tracked in this file. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project adheres
to [Semantic Versioning](https://semver.org/) once 1.0.0 ships.

## [Unreleased]

### Changed

- **Upstream tracking refresh against kaikai 0.56.4.** kaikai#567
  landed: `kai build` now treats the manifest directory as an
  implicit search path, so the `ahu = { path = "." }` self-dep was
  removed from `kai.toml` (the Makefile note that described the
  workaround is gone too). kaikai#570 is now classified as
  LLVM-backend-only — the C backend produces working binaries for
  all 13 fixtures, while the LLVM backend still segfaults inside
  `spawn_actor`. The Makefile exports `KAI_BACKEND ?= c` so
  `make tier1` passes out of the box; drop the pin once kaikai#570
  lands upstream. `docs/known-regressions.md` snapshot rewritten
  accordingly (kaikai#567 closed, kaikai#570 reclassified, the
  workaround list now references the backend pin instead of the
  self-dep). `docs/roadmap.md` restart-component status flipped
  from "red against 0.56.x" to "green under the C backend"; the
  upstream-dependency summary at the bottom restated.
- **Roadmap model: components, not milestones.** `docs/roadmap.md`
  rewritten from the Tongariki / Anga Roa / Orongo / Anakena
  milestone series to a per-component layout (cells, restart,
  streams, registry, distribution, logging, config, diagnostics,
  reference applications, cross-platform). Each component carries
  one of four states (idea / designed / shipped / blocked), a
  list of possible follow-ups with no commitment, and its
  upstream dependencies. No definitions-of-done, no calendars, no
  milestone names. Repository version stays `0.0.1` indefinitely.
  README.md status block, design.md status and decision text, and
  CLAUDE.md tier-1 closure / "things to avoid" / "current state"
  sections updated to match. Source comments in `ahu/app.kai`,
  `ahu/cell.kai`, `tests/stream_pipeline.kai`, `examples/echo/`,
  and `examples/counter/` stripped of milestone references.
  `CHANGELOG.md` and `docs/lane-experience-*.md` are historical
  record and intentionally not rewritten.
- **Repository layout for kaikai package consumption.** ahu is now
  a kaikai package: `kai.toml` lives at the repo root and module
  sources moved from `src/ahu/*.kai` to top-level `ahu/*.kai`.
  This matches the kaikai package convention (module names derive
  from each `.kai` file's path relative to the package root) and
  unblocks downstream consumption via
  `kai add github.com/kaikailang-org/ahu`. User-visible imports
  (`import ahu.cell`, `import ahu.restart`, `import ahu.app`)
  are unchanged. README gained a "Using ahu as a dependency"
  section; CLAUDE.md documents the layout convention under a new
  `## Repository layout` section.
- **Makefile uses `kai` from `PATH` instead of a sibling kaikai
  checkout.** Removed the `KAI_HOME` / `KAIC2` / `STAGE0` /
  `STDLIB` variables, the manual prelude enumeration, and the
  separate `cc` invocation. The Makefile now invokes `kai build
  <src> -o <out>` for each fixture and lets the wrapper resolve
  the compiler, stdlib, preludes, and C linker internally. The
  Makefile shrank from ~120 to ~90 lines and is portable to any
  machine with `kai` installed (CI, contributors, Linux) without
  a dev checkout of kaikai.
- **`examples/echo/main.kai`: `session_step` declares `NetTcp` in
  its effect row.** `with_cell` requires step and body to share a
  single row variable (one open row variable per row, structural
  constraint of kaikai's row system). The echo example's body
  uses `NetTcp` for the echo loop while the step does not, which
  the 0.56 typer rejects under the stricter row unification. The
  one-line accommodation declares `NetTcp` in the step's row even
  though the step doesn't use it. Not a redesign of the cell
  API — just a row alignment at the use site. See
  `docs/known-regressions.md`.
- **`tests/stream_pipeline.kai`: qualify `list.filter` and
  `list.foldl`.** With the stdlib reshuffle in 0.5x, bare
  `filter` / `foldl` now resolve to `option.*` (Option is in the
  prelude). The pipeline operates on a list, so the calls have to
  be explicitly qualified.

### Added

- **`docs/known-regressions.md`** — landing pad mandated by
  CLAUDE.md for issues outside the current lane's scope. Documents
  the four upstream kaikai issues surfaced while bringing ahu onto
  kaikai 0.56.x:
  - [kaikai#565](https://github.com/lnds/kaikai/issues/565) —
    privacy check leaked across module boundaries; **fixed** in
    0.56.1 (unblocked `import ahu.cell` from downstream
    consumers).
  - [kaikai#567](https://github.com/lnds/kaikai/issues/567) —
    `kai build` cannot resolve a package's own modules from
    sibling dirs; worked around by `ahu = { path = "." }` in
    `kai.toml`.
  - [kaikai#570](https://github.com/lnds/kaikai/issues/570) —
    `spawn_actor` segfaults at runtime under 0.56.1; 12 of 13
    fixtures crash on entry. tier1 blocked until upstream fix.
  - [kaikai#571](https://github.com/lnds/kaikai/issues/571) —
    LLVM backend emits "lambda info missing" diagnostic for
    nested lambdas containing `with_mailbox`; cosmetic but
    unverified semantics.
- `docs/lane-experience-ahu-tongariki-mvp-close.md` —
  consolidated retrospective for the full MVP arc (PRs
  #5–#10), upstream coordination summary across the six
  kaikai issues filed (#56, #59, #103, #104, #106, #107),
  what worked / what did not, and what's next for ahu-Anga
  Roa.
- `README.md` rewritten to reflect the **Tongariki shipped**
  state. Contains a layer-by-layer status block, three
  short code tastes (cell, pipeline, restartable_cell),
  pointers to both lane-experience reports.

This version is **ready for the integrator to bump to
`0.1.0`** per CLAUDE.md §*Integrator workflow B*. The
shipped Tongariki surface (3 modules, 4 examples, 13 tier1
fixtures, 6 upstream issues coordinated) matches
`docs/design.md` §*MVP scope* line by line.



- `examples/echo/main.kai` — TCP echo server demo combining
  all four ahu layers + kaikai stdlib primitives (NetTcp v1,
  Signal placeholder via run_app). Per-session counter cell
  tracks frame count; `with_restart(Permanent, ...)` wraps
  the listener loop. Compile-only fixture in tier1
  (interactive server cannot enter the diff loop); verified
  manually via `nc 127.0.0.1 8080`.
- `examples/resilient_counter/main.kai` — Layer 3 fault-
  tolerance demo. A fragile driver crashes deterministically
  every cycle; `restartable_cell(Permanent, Limit(3), ...)`
  retries the driver three times each with fresh state, then
  the outer Cancel handler observes escalation. Output trace
  verifies state-reset-between-restarts (the cell counts to
  3 every cycle, never accumulates) and BEAM-faithful
  Cancel-based escalation.
- `examples/pipeline/main.kai` — Layer 1 ETL demo. Range
  literal `[1..10]` flows through `square` (effectful map),
  `list.filter`, `label` (effectful map), `list.foldl`. Sum
  of even squares = 220. Demonstrates the canonical
  `[..]` / `|` / `|>` / `list.X` shape with effects flowing
  through callbacks.
- Makefile: `TIER1_SKIP_RUN` list lets the compile gate
  cover an example whose runtime test cannot fit the diff
  loop (currently just `echo`). Such examples still get a
  "compile-only OK" line in tier1 output.

### Changed

- **`run_app` simplified to v1 placeholder.** PR #9 shipped
  `run_app` with the kaikai-doc-pinned shape (Signal.on +
  Signal.await + cancel root on signal). Empirical testing
  during this lane revealed that under v1's Signal effect,
  `Signal.await()` blocks the OS thread *before* spawned
  workers get scheduled — root never starts. The kaikai
  doc itself flags this: *"Other fibers cannot make progress
  while it is parked"*. Reactor-driven non-blocking
  integration is m8.x scope. ahu's `run_app` reverts to a
  thin pass-through (`run_app(root) = root()`) so user code
  can wrap its entry point today and inherit the Signal-based
  shutdown behaviour transparently when the upstream reactor
  lands. The API does not change; only the implementation.
  Documented in `src/ahu/app.kai` header.

- `src/ahu/app.kai` — `run_app(root)` bootstrap helper.
  Subscribes to SIGINT and SIGTERM via the kaikai `Signal`
  effect (closed in `lnds/kaikai#107` / PR #116, kaikai
  0.36.x), spawns `root` as a child fiber, parks on
  `Signal.await()` until either signal fires, then cancels
  the root fiber cleanly. Imported as `import ahu.app`;
  called as `app.run_app(root)`.
- Makefile `AHU_SRC` extended to glob `src/ahu/*.kai` so the
  pattern rule's dependency tracking picks up `app.kai` along
  with `cell.kai` and `restart.kai`.

(Tier 1 fixture coverage for `run_app` deferred to the TCP
echo lane — sending SIGINT to a running tier1 binary requires
an external harness out of scope for the diff-style fixture
loop. The function's signature is verified by standalone
compilation.)



- `restartable_cell(policy, limit, initial, step, driver)` in
  `src/ahu/restart.kai` — combined Layer 2 + Layer 3 helper.
  Boots a cell under restart supervision and runs a user's
  driver against it. Each restart re-spawns BOTH the
  supervised body AND a fresh cell with state reset to
  `initial`. Was deferred while `lnds/kaikai#104` was open
  (the nested-mailbox + trap-exit + spawn_actor segfault);
  unblocked when that issue closed in 0.36.x.
- `tests/cross_restartable_cell.kai` — Transient + body that
  uses cell + exits Normal → supervisor returns. Verifies the
  basic compose-the-two-layers shape works end-to-end.
- `tests/cross_restartable_cell_restart.kai` — Permanent + body
  that always crashes + intensity=2 → 2 full cycles each with
  fresh cell state, then escalation. The expected output
  (`got 1` repeated twice, not `got 1` then `got 2`) verifies
  state-reset-on-restart semantics.

### Changed

- **`with_restart` escalation semantics revert to BEAM-faithful
  `Cancel.raise()`.** When `lnds/kaikai#103` was open, ahu's
  `with_restart` returned an `Outcome = Completed | Escalated`
  enum to sidestep the bug where an outer Cancel handler
  intercepted the child's `Cancel.raise()` before trap-exit
  could convert it. With #103 closed in kaikai 0.36.0 (PR
  #122 — *"runtime: bypass user Cancel handlers under
  trap-exit'd link"*), the workaround is no longer needed.
  `with_restart` now returns `Unit` and calls `Cancel.raise()`
  when the intensity limit is exceeded. Layered supervision
  composes through the standard Link/trap-exit channel: a
  parent `with_restart` watching this one observes
  escalation as a `"Crashed"` message in its own mailbox,
  exactly like any other child crash. `Outcome` type
  retired. Three restart fixtures updated; tier1 still
  green at 8 fixtures.
- **ahu module namespacing.** `src/cell.kai` and
  `src/restart.kai` moved to `src/ahu/cell.kai` and
  `src/ahu/restart.kai`. User code now imports them as
  `import ahu.cell` and `import ahu.restart`; function calls
  use the dotted form (`cell.with_cell(...)`,
  `restart.with_restart(...)`, `cell.keep(s)`,
  `cell.cell_done()`, `restart.default_limit()`); types
  remain bare in their position (`StepResult[State]`,
  `RestartPolicy`, `Outcome`). The dotted-function form
  matches kaikai stdlib's `list.X` / `string.X` style and
  prevents nominal collisions if kaikai stdlib ever ships a
  module of the same bare name. All 7 fixtures + the counter
  example refactored. tier1 still 8 fixtures green.

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
