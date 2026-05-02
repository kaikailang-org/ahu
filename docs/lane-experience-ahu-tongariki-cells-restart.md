# Lane experience report — ahu-Tongariki cells + restart

Lane: implementation of ahu-Tongariki Layer 2 (cells) and Layer 3
(restart helpers) on top of kaikai 0.34.x. Output: PR #2 (cells)
and PR #3 (restart), both merged into `lnds/ahu` `main`. Three
kaikai issues filed during the work as upstream-coordination
artefacts.

## Result, up front

**Both layers shipped.** PR #2 and PR #3 both merged with CI
green and seven Tier 1 fixtures passing.

| Layer | PR | Module | Fixtures | Status |
|---|---|---|---|---|
| Layer 2 — cells | [#2](https://github.com/lnds/ahu/pull/2) | `src/cell.kai` | 4 | merged |
| Layer 3 — restart | [#3](https://github.com/lnds/ahu/pull/3) | `src/restart.kai` | 3 | merged |
| Layer 1 — streams | (paused) | — | — | blocked on `lnds/kaikai#106` |

The Tongariki MVP is **structurally 60% done**. The remaining
40% (Layer 1 + the integration TCP echo example) is upstream-
gated: kaikai stdlib does not yet ship the higher-order list
operations (`map` / `filter` / `foldl`) that ahu's stream
combinators are thin wrappers over, and rolling them in ahu
itself would create nominal collisions with the eventual
`core.list` exports.

## Objective metrics

- Start: `2026-05-02T~14:00Z` (after the design pivot lane closed
  in PR #1).
- End:   `2026-05-02T~15:30Z` (PR #3 merged + cleanup lane
  opened).
- Wall-clock: ~1.5 hours total across both implementation lanes.
- Commits on `main` from the two PRs:
  - PR #2: 2 commits (initial cells + CI/extended-fixtures).
  - PR #3: 1 commit (restart helpers + 3 fixtures + design
    revisions).
- Fixtures landed: 7 (`examples/counter/main` + 3 cell tests + 3
  restart tests).
- CI runs: `tier1.yml` workflow passed end-to-end on every PR
  push after the `KAIKAI_REPO_TOKEN` secret was configured.
- kaikai bootstrap time per CI run: ~1m 5s (stages 0/1/2 against
  HEAD of `main`).
- ahu tier1 time per CI run: ~5s (compile + run + diff for all
  7 fixtures).

## Layer 2 — cells (PR #2)

**What landed:**

- `src/cell.kai` (~84 lines) — `StepResult[State]` sum,
  `keep` / `cell_done` constructors, `with_cell(initial, step,
  body)` entry point, internal `cell_loop` dispatcher.
- `examples/counter/main.kai` — request/reply counter.
- `tests/cell_done_first.kai` — Done from first message.
- `tests/cell_state_record.kai` — record-typed state.
- `tests/cell_behavior_switch.kai` — sum-typed state encoding
  behavior switching (the load-bearing claim of the design).
- `Makefile` with `tier0` and `tier1` targets.
- `.github/workflows/tier1.yml` — fresh-kaikai CI.

**Design discoveries that updated `docs/design.md`:**

The original design v2 sketched `start_cell(initial, step) :
Pid[Msg]` as the canonical entry point. That shape does not
typecheck under current kaikai: the region-brand walker
(`fiber_producer_helpers` allow-list in
`kaikai/stage2/compiler.kai`) admits only `fiber_spawn`,
`spawn_actor`, and `alloc_for_policy` to return `Pid` /
`Fiber` from user code. The implementation pass discovered
this and substituted `with_cell(initial, step, body)` —
mirroring `kaikai/stdlib/actor.kai`'s `with_mailbox` shape,
where the pid is scoped to the body closure rather than
returned as a free value. The free `start_cell` form is added
when upstream lands full `TyBranded(Ty, BrandId)`
propagation
(`kaikai/docs/fibers-honesty-targets.md` §*Residual m8.x
items*).

A second discovery: kaikai's actor model is one mailbox per
fiber. The unified-message-protocol pattern (where
sender and receiver share the Msg type so a single
`Actor[Msg]` covers both) is the canonical shape. Cross-type
request/reply via two separate `Actor[A]` and `Actor[B]`
effects in the same fiber is not expressible today. The
`examples/counter/main.kai` fixture uses the unified pattern;
a `Cell.ask(pid, build_request)` helper that opens an inner
`with_mailbox` for the reply lands in ahu-Anga Roa once the
pattern recurs in real demos.

## Layer 3 — restart (PR #3)

**What landed:**

- `src/restart.kai` — `RestartPolicy` (`Permanent` / `Transient`
  / `Temporary`), `RestartLimit(Int)`, `Outcome` (`Completed` /
  `Escalated`), `with_restart(policy, limit, body) : Outcome /
  ...` built on kaikai's trap-exit mechanism.
- `tests/restart_temporary_crash.kai` — Temporary + crash.
- `tests/restart_transient_normal.kai` — Transient + Normal.
- `tests/restart_intensity_escalate.kai` — intensity exceeded.

**Design discoveries that updated `docs/design.md`:**

1. **Escalation as return value, not `Cancel.raise()`.** The
   original sketch raised `Cancel` for escalation so a parent
   supervisor would observe through its own Link / trap-exit
   channel. In current kaikai, an outer `handle { ... } with
   Cancel { raise(_) -> ... }` clause at the caller site
   intercepts the **child's** `Cancel.raise()` directly —
   before trap-exit gets to convert it to `"Crashed"` — so
   the supervisor's restart loop never gets to run. Switching
   escalation to a return value (`Outcome.Escalated`)
   sidesteps that interaction entirely. Filed upstream as
   `lnds/kaikai#103`.

2. **`restartable_cell` deferred.** A combined Cell + restart
   helper would require the supervised body to hold both
   `Actor[String]` (trap-exit) and `Actor[Msg]` (cell mailbox)
   in the same fiber. Current kaikai allows two `Actor`
   effects in the row at the type level but the runtime pairs
   each fiber with exactly one mailbox, which produces a
   segfault when the second `Actor.send` lookup hits the
   wrong handler. The cross-layer fixture I prototyped (cell
   + restart in one supervised body) hits this exact runtime
   gap. ahu-Tongariki therefore ships `with_restart` as the
   standalone restart primitive; `restartable_cell` waits on
   `lnds/kaikai#104`.

3. **`RestartLimit` period deferred.** v1 carries only
   `intensity` — the OTP sliding-window `period` requires a
   `Clock` effect for timestamp comparison; that arrives in
   a follow-up lane.

## Layer 1 — streams (paused)

The design v2 sketched `Source[T, e]` / `Flow[A, B, e]` /
`Sink[T, R, e]` records carrying effect rows in their type
parameters. The implementation pass for Layer 1 immediately hit
the same restriction that forced `Cell` to be a step function
instead of a `Behavior[Msg, e]` record: kaikai's effects spec
pins effect rows to the effect position of function types only
— they do NOT appear as type parameters of ordinary types
(`kaikai/docs/effects.md` §*Inference*).

The fallback shape — *list-based pipeline combinators with
effect rows in callbacks* — needs `core.list.map` /
`core.list.filter` / `core.list.foldl` as the substrate. Those
functions are documented in `kaikai/docs/stdlib-layout.md`
§`core.list` but are NOT actually present in
`stdlib/core/list.kai`. Filed upstream as `lnds/kaikai#106`.

The lane was paused with no commit — the half-written
`src/stream.kai` and `tests/stream_pipeline.kai` were
discarded rather than committed-and-reverted, since they would
have either nominally collided with the eventual `list.map`
upstream or shipped under different names that would need to
be retired later. Cleaner to wait.

## Upstream issues filed

Four coordinated artefacts (three discovered during cells +
restart, one during the cleanup lane that produced this
report):

| Issue | Title | Severity | Blocks |
|---|---|---|---|
| `lnds/kaikai#103` | trap-exit bypassed by outer Cancel handler | Medium | layered supervision via Cancel.raise |
| `lnds/kaikai#104` | nested mailbox + trap-exit + spawn_actor segfault | High | `restartable_cell` (combined Layer 2+3) |
| `lnds/kaikai#106` | core.list missing map / filter / foldl / etc | Critical | Layer 1 entirely |
| `lnds/kaikai#107` | missing Signal effect for graceful shutdown | Medium | `run_app` (Tongariki bootstrap) |

Each issue includes a minimal reproducer extracted from the
ahu lane, expected vs actual behavior, possible resolutions
ranked by BEAM-faithfulness, and a cross-reference to the
ahu PR where the gap was discovered. The reproducers are
self-contained kaikai files that the integrator can `kai run`
directly to confirm the bugs.

Two earlier issues from the design lane (`lnds/kaikai#56`
rename of `ahu-db` → `kohau`, `lnds/kaikai#59` m8.x cooperative
scheduler promotion) closed before the implementation lane
even opened — a sign that the design-lane filings were
well-scoped and timely.

## What worked well

1. **Open the PR early.** PR #2 was opened after the first
   significant slice (cells alone, no restart) rather than
   waiting for the full Tongariki. The CI feedback loop
   surfaced the `KAIKAI_REPO_TOKEN` setup gap immediately.
   The integrator merged PR #2 before PR #3 was even
   started, which made the design discoveries between the
   two PRs cleaner — each PR had a coherent scope.

2. **Verify against `kai` locally before committing.** Every
   fixture was compiled and run via `kaic2 + cc` directly
   before being committed. The Makefile's tier1 was a thin
   wrapper around the same path. By the time the PR was
   pushed, CI had ~zero new things to discover — it was
   just running what already worked locally on a different
   machine.

3. **File upstream issues with reproducers, not just
   descriptions.** Each of the three kaikai issues includes
   a self-contained `.kai` file the integrator can run.
   That makes the issue actionable in seconds rather than
   requiring a back-and-forth on "what exactly are you
   doing".

4. **Design discoveries documented in the same commit as
   the implementation that surfaced them.** PR #2's commit
   message has the full rationale for `with_cell` over
   `start_cell`. PR #3's commit message documents the
   `Outcome` choice and the `restartable_cell` deferral.
   The design.md updates land alongside, so the design
   doc tracks reality, not the original sketch.

## What did not work

1. **The cross-layer fixture was the wrong place to discover
   `lnds/kaikai#104`.** I spent ~30 minutes trying to make
   `tests/cross_cell_under_restart.kai` work before
   recognising the segfault was a runtime gap, not my code.
   The fixture would have been a great smoke test ONCE
   `restartable_cell` worked; trying to use it as an
   exploratory probe for an unverified pattern was the
   wrong shape. **Lesson: validate the smallest possible
   composition first** — two `with_mailbox` of different
   types in nested scope is a 10-line repro; a full cell +
   restart cross-layer fixture is 40 lines. Smaller
   reproducer = faster diagnosis.

2. **The original Layer 3 design sketched
   `restartable_cell` without verifying it was implementable
   under current kaikai.** The design v2 commit listed it as
   "in Tongariki scope". That turned out to be aspirational
   — it depends on `lnds/kaikai#104`. Better workflow: every
   item in §Decision 7's "in scope" list should have a
   one-line note about which kaikai primitives it depends
   on. The §External dependencies section catches this for
   blockers but not for "this depends on a feature interaction
   that is not yet verified".

3. **The `examples/counter/main.kai` `.out.expected` lacks
   the cell's `Stop` print.** The driver sends `Stop` right
   before returning from the with_cell body; the cell's
   fiber is still alive when `main` exits and may not have
   processed `Stop`. The expected output reflects this
   honestly, but the limitation is visible to anyone reading
   the fixture. A "structured shutdown" gap is documented
   in `docs/design.md` §Layer 2; closing it depends on
   kaikai's `nursery` helper actually waiting for children
   (currently a typed pass-through per
   `kaikai/stdlib/spawn.kai`).

## Tier 3 LLM-friendly bet evidence

The implementation pass exercised typed-hole-style feedback
loops in two places:

1. **Sum-payload escape detection** caught my `start_cell`
   return type cleanly. The diagnostic told me which
   helpers ARE allowed to return `Pid` (the
   `fiber_producer_helpers` allow-list); from there I
   could pivot to `with_cell` immediately. The error was
   actionable, not "type mismatch".

2. **Effect-row mismatch on `with_cell(...)` in the
   cross-layer attempt** told me precisely which row the
   typer expected vs found. Without that, the
   `Actor[String]` vs `Actor[CellMsg]` confusion would
   have been much harder to spot.

Where the JSON tooling would have helped:
- A typer query "is Pid[T] returnable from this function?"
  would have caught the `start_cell` issue at design time
  rather than implementation time.
- A `kai effects --json` query against a stub
  `restartable_cell` signature would have surfaced the
  two-Actor-effects-in-one-row gap before I wrote 40
  lines of fixture against it.

Both are good wishlist items for kaikai-Anga Roa's `kai lsp` /
diagnostic JSON surface. The pattern from this lane: the more
the typer can answer "what shape does this need to take?"
without compiling, the faster ahu (and other downstream
projects) can iterate.

## What to do next

In priority order, blocked on upstream:

1. **`lnds/kaikai#106`** unblocks Layer 1 entire. Once it
   lands, ahu opens `ahu-tongariki-streams-v1` with thin
   re-exports of `list.map` / `filter` / `foldl` plus
   ahu-specific additions like `range`.
2. **`lnds/kaikai#107`** unblocks `run_app` and graceful
   shutdown. The TCP echo example needs both #106 and #107
   to deliver on `docs/design.md` §End-to-end MVP
   verification.
3. **`lnds/kaikai#104`** unblocks `restartable_cell`. High
   leverage but not strictly required to ship Tongariki
   MVP — users can compose `with_cell` + `with_restart`
   manually by spawning the cell from a separate fiber.
4. **`lnds/kaikai#103`** unblocks layered supervision via
   `Cancel.raise()`. The `Outcome` workaround handles
   single-layer use cases; the upgrade is for Anga Roa
   multi-layer supervision trees.

All four are upstream-blocked. Doable in the meantime
without upstream changes are tracked in the cleanup lane
that produced this report.

## Files touched (across both PRs)

```
.github/workflows/tier1.yml      (PR #2)
CHANGELOG.md                      (both PRs)
CLAUDE.md                         (PR #2)
Makefile                          (both PRs — pattern rule + auto-discovery)
README.md                         (PR #2)
docs/design.md                    (both PRs — Layer 2 / Layer 3 sections)
src/cell.kai                      (PR #2)
src/restart.kai                   (PR #3)
examples/counter/main.kai         (PR #2)
examples/counter/main.out.expected (PR #2)
tests/cell_behavior_switch.{kai,out.expected}     (PR #2)
tests/cell_done_first.{kai,out.expected}          (PR #2)
tests/cell_state_record.{kai,out.expected}        (PR #2)
tests/restart_intensity_escalate.{kai,out.expected} (PR #3)
tests/restart_temporary_crash.{kai,out.expected}    (PR #3)
tests/restart_transient_normal.{kai,out.expected}   (PR #3)
docs/lane-experience-ahu-tongariki-cells-restart.md (this file, cleanup lane)
```

Working tree clean at every commit. `VERSION` untouched per
agent rules — integrator owns the bump when Tongariki MVP
ships.
