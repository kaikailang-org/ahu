# ahu

Concurrency and fault-tolerance framework for
[kaikai](https://github.com/lnds/kaikai). Three composable
layers — *streams*, *cells*, *restart helpers* — built on
kaikai's structured concurrency, typed mailboxes, and
effects. Plus a small `run_app` bootstrap and a combined
`restartable_cell` helper.

ahu is **not** an OTP clone. The patterns OTP got right
(restart policies, stateful message loops, composable
failure containment) are reshaped to kaikai's primitives,
not transliterated. The shape ahu does not need (untyped
messages, hot code reload, hand-rolled supervision trees)
is dropped because kaikai already has the type-system and
language features that make those workarounds unnecessary.
See `docs/design.md` §*Why ahu is not OTP* for the full
rationale.

## Status

Component states. Detail per component lives in
`docs/roadmap.md`. ahu organises its surface by component;
there are no milestones.

```
Layer 1 — Streams              shipped  (kaikai stdlib stream + sugars)
Layer 2 — Cells                shipped  (ahu/cell.kai — with_cell + ask)
Layer 3 — Restart helpers      shipped  (ahu/restart.kai)
restartable_cell               shipped  (ahu/restart.kai)
Logging                        shipped  (ahu/log.kai — structured fields)
run_app bootstrap              shipped  (ahu/app.kai)

Reference applications:
  examples/counter/            request/reply counter (Layer 2 + ask)
  examples/echo/               TCP echo (all three layers + NetTcp)
  examples/pipeline/           ETL with effects (Layer 1)
  examples/resilient_counter/  restart fault tolerance (Layer 3)
  examples/backpressured_etl/  Bounded(c, BlockSender) backpressure
```

All 20 fixtures compile (tier0). Tier1 (run-and-diff) passes for
every fixture except `examples/log_demo`: a cell fiber does not
inherit a `Log` handler installed outside it, so logging directly
from a cell step is unsupported (`effect not handled in fiber: Log`).
That fixture is left running so the limitation stays visible — see the
CHANGELOG. The repository version stays `0.0.1` indefinitely; ahu
organises by component state, not milestones — see `docs/roadmap.md`.

## Position in the ecosystem

ahu sits in the second layer of the five-project stack:

```
kaikai      (the language)
   ↓
ahu         (this repository — concurrency and fault-tolerance)
   ↓
kohau       (database / persistence layer)
   ↓
henua       (DDD building blocks)
   ↓
manutara    (web framework)
```

Each project has its own repository and its own
`docs/roadmap.md`. The other projects in the stack track
their own milestone conventions; ahu does not — see
`docs/roadmap.md` §*What this doc is NOT*.

## Using ahu as a dependency

ahu is a kaikai package. From any kaikai project (one with a
`kai.toml` at its root):

```sh
kai add github.com/kaikailang-org/ahu
```

That adds `ahu = { source = "github.com/kaikailang-org/ahu", ref = "main" }`
to `kai.toml`, pins the resolved SHA in `kai.lock`, and caches
the repo under `~/Library/Caches/kai/pkg/` (macOS) or
`~/.cache/kai/pkg/` (Linux). User code then imports the
modules dotted:

```kai
import ahu.cell
import ahu.restart
import ahu.app
```

The `kai.toml` at the root of this repository (with the
top-level `ahu/` directory) is what makes those imports
resolve — kaikai derives module names from each `.kai` file's
path relative to the package root.

## Stability

ahu ships against the **Hanga Roa** edition of kaikai
(`edition = "hanga-roa"` in `kai.toml`). The edition contract
pins ahu's `pub` declarations the same way it pins kaikai's
own surface — once a decl is in, breaking it requires an
edition bump.

ahu's entire `pub` surface is **stable** under the Hanga Roa
edition contract. There are no `#[unstable]` declarations and no
`[unstable]` opt-in to add to your `kai.toml` — import any ahu
module and use it directly, warning-free.

What "stable" commits to, per module:

- `ahu.cell`: `StepResult`, `keep`, `cell_done`, `with_cell`,
  and `ask`. The cell-loop core has not changed since Tongariki
  and the synchronous `ask` request/reply is committed to.
- `ahu.restart.*` — the full restart-helper surface.
- `ahu.log.*` — the structured-fields logging surface.
- `ahu.app.run_app` — the bootstrap helper.

Planned follow-ups (a `cell.ask_timeout` once the upstream
`Clock` effect lands, a cross-mailbox `ask` variant once a typed
reply-channel primitive ships, a `with_restart` backoff variant,
wider log field types) arrive as **additive** `feat:` releases.
They extend the surface; they do not break the signatures above.
A breaking change to any committed decl would require an edition
bump, the same guarantee kaikai gives its own surface.

## A taste

A cell that counts increments, replies on demand, exits on
Stop:

```kai
import ahu.cell

type CounterMsg = Increment | GetValue(Pid[CounterMsg])
                | ReplyValue(Int) | Stop

fn counter_step(value: Int, msg: CounterMsg)
  : StepResult[Int] / Console + Actor[CounterMsg]
= match msg {
    Increment           -> cell.keep(value + 1)
    GetValue(reply_to)  -> {
      Actor.send(reply_to, ReplyValue(value))
      cell.keep(value)
    }
    ReplyValue(_)       -> cell.keep(value)
    Stop                -> cell.cell_done()
  }

# in user code:
cell.with_cell(0, counter_step, (counter) => {
  Actor.send(counter, Increment)
  Actor.send(counter, Increment)
  Actor.send(counter, Stop)
})
```

A pipeline using kaikai stdlib + language sugars (Layer 1
ships zero ahu code; the canonical shape lives upstream):

```kai
let squares = [1..10] | square            # | is map-pipe
let evens   = list.filter(squares, even)
let labeled = evens | label
let total   = list.foldl(labeled, 0, add)
```

A supervised counter that tolerates 3 driver crashes
before escalating:

```kai
import ahu.cell
import ahu.restart

restart.restartable_cell(
  Permanent, Limit(3),
  0,                  # initial state
  counter_step,       # (Int, CounterMsg) -> StepResult[Int] / ...
  fragile_driver      # (Pid[CounterMsg]) -> Unit / ... + Cancel
)
```

Full runnable demos live under `examples/`.

## CI

Tier 1 runs on every PR and on every push to `main` via
`.github/workflows/tier1.yml`. The workflow installs `kai`
from the kaikai release artefacts and runs `make tier1`
against ahu's fixtures (every `tests/*.kai` and
`examples/*/main.kai` plus its `.out.expected` sibling).

Locally, install `kai` (e.g. via Homebrew —
`brew install kaikailang-org/kaikai/kaikai`) and run:

```sh
git clone github.com/kaikailang-org/ahu
cd ahu
make tier1
```

The Makefile uses `kai` from `PATH`; no kaikai dev checkout
is required.

## Documentation

- **API reference via `kai doc`.** Every `pub` type and function
  carries a `#[doc]` attribute, so the surface is browsable from the
  command line: `kai doc ahu/<module>` lists a module's items and
  `kai doc ahu/<module>.<symbol>` shows a signature with its full
  doc (e.g. `kai doc ahu/log`, `kai doc ahu/log.info_kv`).
- **`docs/design.md`** — surface, decisions, external
  dependencies on kaikai, not-goals, references.
- **`docs/roadmap.md`** — components and their state; the
  shape ahu uses instead of milestones.
- **`docs/known-regressions.md`** — open issues outside this
  repository that block or constrain ahu against the
  current kaikai release.

## Documentation language

All documentation, source comments, commit messages, and PR
text in this repository are written in English. See
`CLAUDE.md` for the project conventions inherited from
kaikai.
