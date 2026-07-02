# Changelog

All notable changes to ahu are tracked in this file. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project adheres
to [Semantic Versioning](https://semver.org/) once 1.0.0 ships.

## [Unreleased]

### Added

- **`examples/demo` — the full-stack flagship example.** A supervised
  in-memory counter service that wires every shipped layer together:
  a cell (Layer 2) for state, `restartable_cell` (Layer 3) for
  supervision, `ahu.log`'s pure formatters (Layer 4) for structured
  output, and `run_app` for graceful `SIGINT`/`SIGTERM` shutdown. It
  submits three jobs, asks the cell for the total with `cell.ask`,
  reports it, and exits cleanly. Runs deterministically in tier1.
- **`#[doc]` attributes across the whole public surface.** Every
  `pub` type and function in `ahu/cell.kai`, `ahu/restart.kai`,
  `ahu/app.kai`, and `ahu/log.kai` carries a `#[doc("...")]`
  attribute, and each file opens with a module `#[doc]`. The docs are
  surfaced by `kai doc ahu/<module>` and `kai doc ahu/<module>.<symbol>`
  (e.g. `kai doc ahu/cell`, `kai doc ahu/cell.with_cell`), and are
  also consumed by `kaic2 --doc-json` and typed-hole reports.

### Changed

- **Comments and docs: brief, timeless, non-contingent.** Source
  comments, `#[doc]` text, and the docs in this repository no longer
  name issue trackers, tickets, PRs, compiler version numbers, or
  "v1/v2" framing — that history lives in git and the upstream kaikai
  tracker. Deep design rationale that previously sat in module headers
  now points to `docs/design.md`; the headers became user-facing
  `#[doc]`. The convention is recorded in `CLAUDE.md`
  §*Comments and documentation*.
- **`run_app` cancels its signal-waiter once the root fiber
  completes.** The enclosing nursery joins every child it spawned
  before returning, so the signal-waiter — parked on `Signal.await()`
  — is cancelled explicitly with `n.cancel(w)` after `n.await(root)`
  returns. `n.cancel` wakes a fiber parked on `Signal.await()`, so the
  nursery joins it and the scope returns on natural root exit.
- **`examples/backpressured_etl` spawns the producer with
  `spawn_actor`.** The producer fiber gets its own `Actor[String]`
  handler for `Actor.send`; back-pressure against the bounded mailbox
  is unchanged.

### Known issues

- **`examples/log_demo` reports `effect not handled in fiber: Log`.**
  A cell runs in its own fiber, which does not inherit a `Log` handler
  installed outside it, so logging directly from a cell step is
  unsupported — a cell can perform only effects handled within its own
  fiber (`Actor`, plus the native `Console` leaves). Logging from a
  cell needs a different shape: route events through the cell's
  mailbox, or log from the driver/supervisor fiber. The fixture is
  left running so the limitation stays visible.

## [0.1.0] - 2026-06-14

### Removed

- **`ahu/stream.kai` deleted — Layer 1 now consumes the kaikai
  stdlib `stream` directly.** The kaikai stdlib grew its own
  lazy stream (`Stream[t, e]`, push-carrier recipe — issue #801),
  which made ahu's pull/cursor re-implementation a duplicate of an
  upstream primitive. Re-implementing a stdlib primitive violates
  ahu's "do not re-design kaikai primitives" rule, and `design.md`
  §Layer 1 already stated ahu ships no stream-layer code. The
  module is removed; `tests/stream_lazy.kai` is migrated to
  `import stream` (`foreach` → `each`) and pins the stdlib stream
  surface ahu depends on. `design.md` §Layer 1 / §Decision 2,
  the README status table, and the `[unstable]` opt-in in
  `kai.toml` are updated to match. Output goldens unchanged;
  tier1 stays at 20 fixtures.

### Changed

- **Public surface declared stable under the Hanga Roa edition.**
  Every `#[unstable]` annotation is removed from `ahu/cell.kai`,
  `ahu/log.kai`, `ahu/restart.kai`, and `ahu/app.kai`, and the
  `[unstable]` opt-in block is dropped from `kai.toml`. ahu's
  `pub` surface (`cell` including `ask`, `restart.*`, `log.*`,
  `app.run_app`) is now committed under the edition contract;
  consumers import it warning-free with no `[unstable]` opt-in.
  Planned follow-ups (`cell.ask_timeout`, cross-mailbox `ask`,
  `with_restart` backoff, wider log field types) land as additive
  `feat:` releases, not breaking changes. Module headers, the
  README stability section, and the historical
  `docs/hanga-roa-impacts-for-ahu.md` briefing are updated to
  reflect the reversal of the original "mark everything unstable"
  recommendation.

- **`ahu/app.kai` — `run_app` upgrades from pass-through to
  Signal-multiplex graceful shutdown.** Now that the kaikai
  R4 reactor (lnds/kaikai#671, shipped in 0.80.0) parks
  `Signal.await()` fiber-aware, `run_app` can spawn `root`
  inside a nursery alongside a sibling signal-waiter that
  subscribes to SIGINT + SIGTERM and cancels root on signal.
  Root's `Cancel` handlers — including cell `cell_done`
  cleanup, `with_restart` unwind, and any user-installed
  `Cancel.try` handlers — run before the process exits.
  Signature unchanged at the call site (`app.run_app(root)`),
  but the row gains `Spawn + Signal + Cancel`; callers must
  add `/ Signal` to `main`'s effect row so the runtime
  installs the default Signal handler around `main`. Three
  in-tree examples updated (`echo`, `resilient_counter`,
  plus the `echo` header). New fixture
  `tests/app_run_app_natural_exit.kai` locks down the
  natural-exit path (root returns normally, the sibling
  signal-waiter is cancelled cleanly by the nursery on
  exit); the signal-cancel path is exercised by the
  upstream kaikai `demos/signal_concurrent` proof. tier1
  grows from 19 to 20 fixtures. (The `#[unstable]` annotation
  this release originally carried has since been removed — see
  the 0.1.0 stability entry above.)

- **Doc sweep — align with the kaikai reactor (R1+R2+R3
  shipped).** The reactor has landed upstream in three phases:
  R1 (file + sleep + process), R2 (TCP sockets), R3 (stdin).
  After R2, every blocking `NetTcp` op parks the fiber instead
  of the OS thread, which removes the OS-thread-blocking cliff
  that several ahu module headers and docs were still pointing
  to as a future event. Four sites updated, no code change:
  `ahu/app.kai` header (drops the "Signal.await blocks the OS
  thread" framing; rewrites the planned-upgrade block as the
  next lane on this module, not a future runtime feature);
  `ahu/log.kai` async-fan-out follow-up (reactor is no longer
  the blocker — the blocker is the absence of an async
  `fs.file.append` surface); `docs/design.md` §*Open watch
  items* item 3 closed (was "OS-thread-blocking primitives",
  now reads "Closed"); `docs/roadmap.md` log async-fan-out
  bullet matches `log.kai`. No `pub` surface changes, no
  fixture changes, tier1 stays 19/19 green.

### Added

- **`ahu/stream.kai` — Layer 1 lazy streams.** Promotes the
  Layer 1 component from "designed" to "shipped" for the lazy
  case (the eager-pipeline case stays convention-over-stdlib).
  Function-value encoding `Stream[t, e] = () -> Option[t] /
  Mutable + e`: each pull consumes one element and advances
  the captured state via `Mutable.ref`. Surface: `from_list`
  source; `map`, `filter`, `flat_map`, `take` combinators;
  `foreach`, `fold`, `to_list` sinks. Pipe convention dispatch
  (kaikai 0.65+) routes `s | f`, `s |? p`, `s || f` through
  this module by head type. Pure named callbacks (`fn double(n:
  Int) : Int = n * 2`) compose without `[e] / e` boilerplate —
  the lane unblocked the day kaikai 0.70.0 closed RFC
  kaikai#645 (row subsumption for pure callbacks). Marked
  `#[unstable]` per-declaration for the Hanga Roa edition;
  ahu's `kai.toml` adds `stream = true` to the `[unstable]`
  block. Fixture `tests/stream_lazy.kai` exercises four
  realistic shapes (map/filter/fold, foreach with side
  effects, take, flat_map). Tier1 grows from 18 to 19
  fixtures. `docs/roadmap.md` Layer 1 component rewritten;
  the `from_lines` / `from_listener` follow-ups now describe
  the actual upstream gap (chunked-read primitives in
  `fs.file`, not row-poly records).

- **`examples/log_demo/` — cell + `ahu.log` + `with_restart_backoff`
  composed end-to-end.** A small job-runner: a `JobMsg` cell counts
  processed jobs and replies to a `Stats` request; a fragile
  driver processes two jobs, asks for stats, then raises
  `Cancel.raise()` to simulate a fault. The supervisor wraps
  everything in `with_restart_backoff(Permanent, Limit(3),
  millis(1), body)` and an outer `handle ... with Cancel` to
  observe escalation. Every cell op and every restart cycle
  emits a structured logfmt-like line through `ahu.log` (a
  captured-to-stdout `Log` handler at the outermost layer keeps
  the golden deterministic). The output trace witnesses the
  state-reset semantics of restartable cells (each cycle reads
  `total=1` then `total=2`, never accumulating across crashes)
  and the escalation path when the intensity budget exhausts.
  Tier1 grows from 17 to 18 fixtures. `docs/roadmap.md`
  reference-applications list updated.

- **`restart.with_restart_backoff` — sleep `Duration` between
  restarts.** Rate-limits a crashloop without changing the
  policy semantics. First body invocation is immediate; subsequent
  re-spawns wait `backoff` after the termination message lands.
  Row gains `Clock`: `with_restart_backoff(policy, limit,
  backoff, body) : Unit / Actor[String] + Spawn + Link + Cancel
  + Clock + e`. Why a separate function and not a `backoff:
  Option[Duration]` on `with_restart` — callers that don't need
  backoff stay clear of the `Clock` cost in their signature.
  Cooperative under kaikai 0.66+'s R1 reactor (the `Clock.sleep`
  parks the fiber rather than blocking the OS thread; other
  fibers continue to run during backoff). v1 ships fixed
  `Duration`; variable backoff strategies (Linear, Exponential,
  DecorrelatedJitter) layer on top by threading the next
  `Duration` per call. Marked `#[unstable]` for the Hanga Roa
  edition. Fixture `tests/restart_backoff.kai`; tier1 grows
  from 16 to 17 fixtures. `docs/roadmap.md` Layer 3 surface
  list and component description updated.

- **Hanga Roa edition contract.** `kai.toml` now declares
  `edition = "hanga-roa"`, pinning ahu to kaikai's first post-
  Tongariki edition (kaikai 0.63 adopted editions; 0.65 shipped
  the Hanga Roa pipe convention dispatch and `#[unstable]`
  attribute syntax; 0.66 the R1 reactor; 0.67 made the field
  load-bearing). Iterating `pub` decls carry per-declaration
  `#[unstable]` annotations so the contract pins only the surface
  that is genuinely settled. **Stable** under the contract:
  `ahu.cell.{StepResult, keep, cell_done, with_cell}` (the cell-
  loop core, unchanged since Tongariki). **`#[unstable]`**:
  `ahu.cell.ask`, every `pub` in `ahu.restart`, every `pub` in
  `ahu.log`, and `ahu.app.run_app`. ahu's own `kai.toml` opts in
  via `[unstable] cell = true; restart = true; log = true; app =
  true` so the in-tree fixtures build warning-free; downstream
  consumers do the same in their own `kai.toml`. README gains a
  `## Stability` section explaining the contract and listing the
  opt-in for downstream callers.

### Fixed

- **CI: `kai` is now exposed on `PATH` after building kaikai.** The
  Makefile's "use `kai` from PATH" refactor (PR landing the
  portable Makefile) was never reflected in `.github/workflows/tier1.yml`,
  which kept passing a vestigial `KAI_HOME=$GITHUB_WORKSPACE/kaikai`
  to `make` while the Makefile itself ignored that variable. Result:
  `make: kai: No such file or directory` on every CI run since the
  refactor (kaikai 0.56.x onwards). The workflow now adds an
  `Expose kai on PATH` step that appends
  `$GITHUB_WORKSPACE/kaikai/bin` to `$GITHUB_PATH` after the
  kaikai build, and the `KAI_HOME=` argument is dropped from both
  `make` invocations.

### Changed

- **`examples/counter/main.kai` migrated to `cell.ask`.** The
  driver no longer threads `Actor.self()` and a manual
  `Actor.receive` to coordinate the GetValue round-trip; one
  `cell.ask(counter, (me) => GetValue(me))` replaces the four
  lines. Same `.out.expected`, same protocol, fewer moving
  parts. Validates the helper at the canonical reference site
  that motivated shipping it.

- **Drop `KAI_BACKEND=c` pin — kaikai 0.59 closes the LLVM
  regression arc.** kaikai 0.58 fixed kaikai#582's minimal
  Cancel-raise repro; kaikai 0.59 fixed the residue (Link/Monitor
  from spawned fibers) that was still crashing the 6 restart-
  flavoured fixtures and silenced the cosmetic kaikai#571
  diagnostic. Local verification: `make tier1` (auto-detect
  → LLVM on clang-equipped hosts) and `KAI_BACKEND=c make tier1`
  both green at 16/16. The Makefile now leaves backend selection
  to `kai`'s auto-detect with overrides documented inline.
  `docs/known-regressions.md` snapshot rewritten — top-of-file
  table now reads "no active blockers" and the #570/#582/#571
  sections are recast as historical with resolution notes. The
  #582 residue (never opened upstream because 0.59 dropped first)
  is documented inline with its 12-line ablation repro for
  posterity. `docs/roadmap.md` Restart-component status flipped
  from "green under the C backend" to "green under both
  backends"; upstream-dependencies summary collapsed to a one-
  paragraph no-blockers statement.
- **Upstream-tracking refresh against kaikai 0.56.6.** kaikai#570
  is mostly fixed in 0.56.6 — under LLVM, cells, streams,
  `cell.ask`, plain mailboxes, and `ahu.log` all run identically
  to the C backend now (9 of 15 tier1 fixtures clean under both).
  A narrower residue remains: `Cancel.raise()` from a fiber
  spawned via `fiber_spawn` segfaults under LLVM when the parent
  is parked on its own mailbox, which still tumbles the 6
  restart-flavoured fixtures. Filed upstream as **kaikai#582**
  with a 14-line standalone reproducer (no `Link`, no trap-exit,
  no captures). The Makefile keeps `KAI_BACKEND ?= c` exported
  for now; comment updated to reference #582 and the reproducer.
  `docs/known-regressions.md` snapshot rewritten for 0.56.6:
  #570 marked mostly-fixed, new #582 section with the repro
  inline + lldb backtrace + ablation table, workaround list
  references #582 instead of #570. `docs/roadmap.md`
  Restart-component status and upstream-dependency summary
  updated to match.

### Added

- **`examples/backpressured_etl/` — back-pressure reference
  example.** A producer fiber feeds five strings into a
  `with_mailbox_policy(Bounded(2, BlockSender))` mailbox; the
  consumer (running on the main fiber) pops one at a time. The
  trace shows the producer parking after three sends because the
  mailbox has only two slots, then resuming as the consumer
  drains. Stays outside `with_cell` deliberately: `with_cell`
  spawns the cell with the unbounded `spawn_actor` and a
  `spawn_actor_policy` does not exist upstream yet
  (`stdlib/actor.kai` §`spawn_actor` v1 simplification). The
  example doubles as living documentation for that gap. Tier1
  grows to 16 fixtures.

- **`cell.ask` — synchronous request/reply helper over the cell
  mailbox.** Promotes the listed Layer 2 follow-up to shipped:
  `ask(cell_pid, build_request) : Msg / Actor[Msg] + e` automates
  the canonical `Actor.self → Actor.send → Actor.receive`
  triplet that every cell-using fixture currently writes by hand
  (see `tests/cell_state_record.kai` for the pre-existing
  pattern). The reply payload must be a variant of the cell's
  `Msg` union — kaikai's `Actor.send : Pid[T] -> T` ties the
  destination pid type to the active handler's `Msg`, so a typed
  reply-channel distinct from the per-fiber mailbox is upstream
  scope, not user-level. Documented at the call site, fixture
  `tests/cell_ask.kai`. Tier1 grows from 14 to 15 fixtures.

- **`ahu/log.kai` — structured-fields wrapper over the stdlib `Log`
  effect.** Promotes the Logging component from "idea" to "shipped"
  in `docs/roadmap.md`. Surface: `LogLevel = Debug | Info | Warn |
  Error`; `Field = StringField | IntField | BoolField` (closed sum,
  avoids a heterogeneous Map); `log.{debug,info,warn,error}_kv(msg,
  fields) : Unit / Log` formatting fields as `k=v` pairs and
  forwarding to the matching `Log` op; pure helpers `format_field`,
  `format_fields`, `format_event` for callers that render outside
  the `Log` effect. The implementation is a pure-formatting wrapper
  — no new effect, no handler combinators that re-emit `Log` — so
  the row stays `Log` and a user-installed `Log` handler observes
  the same already-formatted string the stdlib default handler
  would print. v1 deferrals (level-filter handler combinator, async
  fan-out to `fs.file`, timestamps via `Clock`, trace context,
  redaction, rotation) are documented in the module header with
  the upstream gaps that block each one. Tier1 grows from 13 to
  14 fixtures with `tests/log_basic.kai`.

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
