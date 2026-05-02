# Lane experience report — ahu-Tongariki MVP close

Lane: closing pass for the ahu-Tongariki MVP. Consolidates
the implementation arc from PR #5 (Layer 1 streams) through
PR #10 (integration demos), updates the README to reflect
shipped state, and prepares the repo for the integrator to
bump `VERSION` to `0.1.0`.

This report is the second retrospective the project has
produced. The first
(`docs/lane-experience-ahu-tongariki-cells-restart.md`)
covered PRs #2 and #3 (cells + restart) and the four
upstream issues that were open at the time. This one
covers everything since.

## Result, up front

**ahu-Tongariki MVP is structurally complete.** All four
layers + bootstrap + cross-layer helper + three integration
demos. tier1 green at 13 fixtures. The `docs/design.md`
§*End-to-end MVP verification* command runs to completion.

## Objective metrics

- **Start**: design lane opened 2026-05-02 morning.
- **End**: PR #10 merged 2026-05-02 evening.
- **Wall-clock**: one full day (~10 hours of work, distributed
  across alternating implementation and upstream-issue lanes).
- **PRs merged**: 10
  ([#1](https://github.com/lnds/ahu/pull/1) design v2,
  [#2](https://github.com/lnds/ahu/pull/2) cells,
  [#3](https://github.com/lnds/ahu/pull/3) restart,
  [#4](https://github.com/lnds/ahu/pull/4) docs cleanup,
  [#5](https://github.com/lnds/ahu/pull/5) Layer 1 streams,
  [#6](https://github.com/lnds/ahu/pull/6) namespacing,
  [#7](https://github.com/lnds/ahu/pull/7) restart v2 BEAM-faithful,
  [#8](https://github.com/lnds/ahu/pull/8) restartable_cell,
  [#9](https://github.com/lnds/ahu/pull/9) run_app v1,
  [#10](https://github.com/lnds/ahu/pull/10) integration demos).
- **Upstream `lnds/kaikai` issues filed**: 6 (`#56`, `#59`,
  `#103`, `#104`, `#106`, `#107`). All closed.
- **Tier 1 fixtures**: 13 (8 unit + 4 example diff + 1
  example compile-only).
- **CI runtime per PR**: ~2 minutes (kaikai bootstrap +
  ahu tier1).
- **Source modules** (`src/ahu/`): 3 (`cell.kai`,
  `restart.kai`, `app.kai`).
- **Integration demos** (`examples/`): 4 (`counter`, `echo`,
  `pipeline`, `resilient_counter`).

## Per-PR summary

### PR #5 — Layer 1 streams (small)

`lnds/kaikai#106` closed within hours of being filed
(integrator implemented the proposed signatures verbatim
and added `range` as an explicit ahu-Layer-1 hand-off). The
ahu-side change is **one fixture and zero stream module**:
the entire pipeline shape lives in kaikai stdlib +
language sugars (`[a..b]`, `|`, `|>`, `list.map / filter /
foldl / foreach`). ahu's "Layer 1" contribution is the
canonical pattern documented in
`docs/design.md` §*Layer 1*.

### PR #6 — Namespacing (mechanical)

User feedback: ahu's modules at top-level `src/cell.kai` /
`src/restart.kai` would collide with hypothetical kaikai
top-level modules of the same name. Refactored to
`src/ahu/cell.kai` / `src/ahu/restart.kai`; imports become
`import ahu.cell` / `import ahu.restart`; function calls
go dotted (`cell.with_cell(...)`); types stay bare in their
position (the kaikai parser does not accept
module-qualified type names in type positions).

### PR #7 — Restart v2 BEAM-faithful (revert)

Once `lnds/kaikai#103` closed (kaikai PR #122 — runtime-
level bypass of user Cancel handlers under trap-exit'd
links), the `Outcome` workaround from PR #3 became
obsolete. `with_restart` reverted to BEAM-faithful
`Cancel.raise()` for escalation; layered supervision now
composes through the standard Link/trap-exit channel
without manual outcome inspection.

### PR #8 — `restartable_cell` (the marquee helper)

Once `lnds/kaikai#104` closed (the segfault on nested
mailbox + trap-exit + `spawn_actor`), the combined
Cell + restart helper became implementable. Three lines
of glue:

```kai
pub fn restartable_cell[State, Msg, e](...) =
  with_restart(policy, limit, (parent) => {
    Link.link(parent)
    with_mailbox { cell.with_cell(initial, step, driver) }
  })
```

State resets between restarts; the test fixture
`cross_restartable_cell_restart.kai` verifies the trace
shows `got 1` repeated, not `got 1 → got 2`.

### PR #9 — `run_app` v1 (sketch)

Lands `run_app(root)` following the kaikai-doc-pinned
"Typical use" pattern: `Signal.on(SigInt) +
Signal.on(SigTerm) + spawn root + Signal.await() + cancel
root`. Compiles cleanly; no tier1 fixture (signal-driven
testing needs an external harness out of tier1's diff loop
scope).

### PR #10 — Integration demos + `run_app` walk-back

Three example programs land:
`examples/echo/main.kai` (TCP echo, all four layers),
`examples/resilient_counter/main.kai` (Layer 3 fault
tolerance trace), `examples/pipeline/main.kai` (Layer 1
ETL with effects).

Empirical testing of echo revealed that `run_app` v1 from
PR #9 doesn't actually work under v1's Signal effect:
`Signal.await()` blocks the OS thread *before* the spawned
root fiber gets scheduled — root never runs. The kaikai
doc itself flags this in §Signal v1 limitations:
*"Other fibers cannot make progress while it is parked"*.
Reactor-driven non-blocking integration is m8.x scope.

`run_app` walked back to a thin pass-through:

```kai
pub fn run_app[e](root: () -> Unit / e) : Unit / e = root()
```

API does not change; only the implementation. When the
upstream reactor lands, `run_app` upgrades transparently to
the Signal-based shape PR #9 sketched.

## Upstream coordination

Six kaikai issues filed during the implementation arc:

| Issue | Topic | Severity | Closed via |
|---|---|---|---|
| `#56` | rename `ahu-db` / `ahu-ddd` → `kohau` / `henua` | Low | Coordinated PR (immediate) |
| `#59` | m8.x cooperative scheduler — promote to Tongariki Wave 3 | High | Doc alignment in 0.32.0 (the runtime had landed in 0.4.0; only the documentation was stale) |
| `#103` | trap-exit bypassed by outer Cancel handler | mvp-blocker | kaikai PR #122 in 0.36.0 |
| `#104` | nested mailbox + trap-exit + spawn_actor segfault | mvp-blocker | Closed in 0.36.x |
| `#106` | `core.list` missing `map / filter / foldl / foldr / length / reverse / zip / unzip` | Critical | kaikai PR #113 (signatures matched the issue's proposal verbatim) |
| `#107` | missing Signal effect for graceful shutdown | Medium | kaikai PR #116 |

**Two recurring patterns in the kaikai integrator's
responses worth noting**:

1. **Issues with self-contained reproducers got merged
   fastest.** Every issue I filed included a reproducer
   that the integrator could `kai run` directly. `#106`
   closed within hours because the proposal-as-design
   was actionable verbatim.

2. **Cross-project hand-offs were left in upstream code.**
   The kaikai-side fixture for `#106`
   (`examples/stdlib/list_pipeline.kai`) carries a
   comment saying *"`range`... ahu Layer 1 owns it"* —
   explicit handoff to ahu. That is unusually good
   coordination for a cross-repo workflow, and it made
   ahu's Layer 1 PR (#5) a single-fixture commit instead
   of a stream-module rewrite.

## What worked well

1. **Open the PR early, iterate against CI.** Every
   implementation lane opened a PR after the first
   meaningful slice (cells alone, not cells+restart;
   restart alone, not the full Tongariki). The integrator
   merged each as soon as CI was green, which kept the
   review surface manageable.

2. **Auto-merge after the third PR.** Configuring repo-
   level `allow_auto_merge` and using `gh pr merge --auto
   --merge` removed the polling-for-CI step from every
   lane. The integrator did not have to wait for me to
   confirm CI before merging; I did not have to write
   `until CI green; do sleep 10; done` loops.

3. **File upstream issues with reproducers AND proposed
   fixes.** Each kaikai issue I filed had a self-contained
   `.kai` file as reproducer plus a sketch of what the API
   shape should look like. The integrator could read the
   issue, run the reproducer, and start work without a
   round-trip clarifying anything.

4. **Honest walk-backs.** Two API decisions reverted
   during this lane (`Outcome` workaround in restart, and
   `Signal`-based `run_app`). Each walk-back was
   documented in the relevant CHANGELOG entry + design
   doc + module header. Nothing about the original
   decisions was hidden — the walk-back commits explain
   what changed and why, with cross-references to the
   kaikai PRs that made the new shape possible.

5. **Cross-checking with kaikai HEAD continuously.** Every
   lane started with `git pull` + `make all` in kaikai.
   Caught the runtime symbol shadowing rename (PR #110)
   that made my pre-built `kaic2` stale. Caught `0.35.0`
   shipping `core.list.*` mid-lane (the day after I filed
   `#106`).

## What did not work

1. **The cross-layer fixture as exploratory probe.** I
   spent ~30 min trying to make `tests/cross_cell_under_restart.kai`
   work before recognising it was a runtime gap (`#104`),
   not user-code error. **Lesson: validate the smallest
   possible composition first** — the diagnostic for
   `#104` was a 10-line repro
   (`/tmp/repro2_nested_after_trap.kai`); the fixture
   I started with was 40 lines. Smaller reproducer = faster
   diagnosis.

2. **`run_app` v1 sketch.** Wrote PR #9 against the kaikai
   doc's "Typical use" pattern without empirically testing
   that the spawned root actually runs. Discovered the v1
   limitation only when the echo demo (PR #10) failed to
   start the listener. Walked it back. **Lesson: empirical
   smoke-test before committing the design as code**.

3. **Initial design pivot (PR #1).** The original brief
   was OTP-shaped; the design started OTP-shaped. After
   user feedback, pivoted to streams + cells + restart —
   ~2 hours of design work undone. The signs that OTP
   duplication was wrong for kaikai were visible at M2
   (reference reading) — kaikai's structured concurrency
   already does half of what supervision trees are for —
   but the agent did not raise the tension during M2; the
   user caught it at PR review. **Lesson: when the brief
   contains a directional verb ("the X analog"), trigger
   one round of explicit challenge** before drafting.

## Tier 3 LLM-friendly bet evidence

Six places where structured kaikai output (typer
diagnostics, JSON tooling) shortened the implementation
arc:

1. **Sum-payload escape detection** (kaikai issue
   `#71` option (a)). Caught my early `start_cell` return
   type cleanly, with a diagnostic that pointed at the
   `fiber_producer_helpers` allow-list. Without that, the
   redesign to `with_cell` would have taken longer.

2. **Effect-row mismatch diagnostics**. When my
   `restartable_cell` initial sketch had `step` and
   `driver` with different effect rows, the typer
   output exactly which row each side had — let me
   immediately add the missing `+ Console + Cancel` to
   `step` to unify.

3. **The Cancel handler catching the wrong fiber's
   Cancel** in `#103` was caught empirically — the
   reproducer printed `OUTER HANDLER caught Cancel`
   instead of the expected `supervisor got: Crashed`,
   which was self-evidently the bug.

4. **Multi-handler effect resolution** (innermost-wins)
   was implicit but actionable: when `with_mailbox` of
   `Msg` was nested inside `Actor[String]`, the typer
   accepted it and runtime correctly routed `Actor.send`
   through the inner handler.

5. **Auto-discovered fixture loop in the Makefile** —
   pattern rules + `wildcard` mean adding a new fixture
   never requires Makefile edits beyond a one-line
   `TIER1_SKIP_RUN` carve-out for the interactive `echo`
   server.

6. **Auto-merge workflow** (after enabling `allow_auto_merge`)
   — `gh pr merge N --auto --merge` queues the merge for
   when CI passes. Reduced the polling overhead on every
   PR to zero.

## Score against the design v2

| Promise (PR #1) | Status |
|---|---|
| Layer 1 — Streams | ✓ shipped (lives in kaikai stdlib + sugars; no ahu module needed) |
| Layer 2 — Cells (recursive function shape) | ✓ shipped (`with_cell` shape forced by region-brand walker) |
| Layer 3 — Restart helpers | ✓ shipped (BEAM-faithful Cancel-based escalation) |
| `restartable_cell` (combined Layer 2 + 3) | ✓ shipped |
| `run_app` bootstrap | ⚠ v1 placeholder + documented upgrade path |
| TCP echo MVP integration | ✓ shipped end-to-end |
| Sum-typed Cell state for behavior switching | ✓ shipped + verified by `tests/cell_behavior_switch.kai` |
| Restart policies (Permanent / Transient / Temporary) | ✓ shipped |
| Intensity-over-period | ⚠ intensity only in v1 (period needs `Clock` effect) |
| No distribution | ✓ correctly deferred |
| No hot reload | ✓ permanent non-goal |
| No process registry | ✓ deferred to Anga Roa |
| Repository layout (CLAUDE.md, README.md, docs/, src/, tests/, examples/) | ✓ shipped |

**Match: ~95% to the design.** The 5% gap is `run_app`
walk-back + intensity-only RestartLimit, both documented
with upgrade paths.

## What's next

The Tongariki MVP is shipped. Next milestone is **ahu-Anga
Roa** per `docs/roadmap.md`. Notable items:

1. **Process registry** — per-nursery `Registry` capability,
   designed in a dedicated `docs/registry.md` at the start
   of the milestone.
2. **`Cell.ask(pid, build_msg)` helper** — synchronous
   request/reply pattern, if the Tongariki demos exercised
   it enough to warrant a helper.
3. **Stream extensions** — `Flow.window`, `Flow.broadcast`,
   `Flow.recover_with`. Once kaikai supports row-poly type
   parameters, lazy stream sources land too
   (`Source[T, e]`, `Sink[T, R, e]`).
4. **Specialised behaviours** — `Agent` candidate first
   (single-state value with get/update); other
   specialisations gated on usage data.
5. **Diagnostic surface** — restart trace pretty-printing,
   cell-tree dump on `SIGUSR1`, JSON output for restart
   events. Plugs into kaikai-Anga Roa's `kai lsp` and
   diagnostic JSON contract.

Plus the v1 limitations that lift as kaikai m8.x reactor
lands:

- `Signal`-based `run_app` graceful shutdown.
- Multi-connection concurrent echo (no longer
  one-at-a-time).
- Lazy / unbounded stream sources.

These are **not** Anga Roa work — they upgrade automatically
when upstream reactor lands. ahu's API surface stays
unchanged.

## Repository state at this writing

```
src/ahu/
  cell.kai        — Layer 2: with_cell, StepResult, keep, cell_done
  restart.kai     — Layer 3: with_restart, restartable_cell, RestartPolicy, RestartLimit
  app.kai         — Layer 4: run_app (v1 placeholder)

tests/
  cell_*.kai                       (3 fixtures)
  cross_restartable_cell*.kai      (2 fixtures)
  restart_*.kai                    (3 fixtures)
  stream_pipeline.kai              (1 fixture)

examples/
  counter/         — request/reply counter (Layer 2)
  echo/            — TCP echo (all 4 layers + NetTcp)
  pipeline/        — ETL with effects (Layer 1)
  resilient_counter/ — restart fault tolerance (Layer 3)
```

13 fixtures green in tier1. CI runs against fresh kaikai
HEAD on every push.

## For the integrator

The Tongariki MVP is shipped. Per CLAUDE.md §*VERSION +
CHANGELOG*, this lane does not bump `VERSION` — that is
the integrator's call. The CHANGELOG `[Unreleased]` section
is ready to be promoted to `0.1.0` (or whatever number you
pick) once you decide.

Suggested release command sequence:

```sh
git pull --ff-only origin main
$EDITOR VERSION CHANGELOG.md
# Bump VERSION to 0.1.0; rename [Unreleased] → [0.1.0] —
# 2026-05-02 (ahu-Tongariki MVP).
git add VERSION CHANGELOG.md
git commit -m "release: 0.1.0 — ahu-Tongariki MVP"
git push origin main
```

Working tree clean at the close of this lane.
