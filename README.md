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

**ahu-Tongariki MVP shipped (2026-05-02).** Layers 1–4 +
`restartable_cell` + reference demos. tier1 green at 13
fixtures against kaikai 0.36.x. Retrospective at
`docs/lane-experience-ahu-tongariki-mvp-close.md`.

```
Layer 1 — Streams              ✓ kaikai stdlib + language sugars
Layer 2 — Cells                ✓ src/ahu/cell.kai
Layer 3 — Restart helpers      ✓ src/ahu/restart.kai
restartable_cell               ✓ src/ahu/restart.kai
run_app bootstrap              ✓ src/ahu/app.kai (v1 placeholder)

Demos:
  examples/counter/            request/reply counter (Layer 2)
  examples/echo/               TCP echo (all four layers + NetTcp)
  examples/pipeline/           ETL with effects (Layer 1)
  examples/resilient_counter/  restart fault tolerance (Layer 3)
```

The next milestone is **ahu-Anga Roa** — process registry,
Cell.ask helper, specialised behaviours, stream extensions,
diagnostic surface. See `docs/roadmap.md`.

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

Each project has its own repository, its own
`docs/roadmap.md`, and its own
`Tongariki / Anga Roa / Orongo / Anakena` series. See
`kaikai/docs/roadmap.md` for the meta-roadmap.

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
`.github/workflows/tier1.yml`. The workflow checks out a
fresh copy of `lnds/kaikai` (HEAD of `main` by default;
override via the `kaikai_ref` workflow input), bootstraps
stages 0/1/2, then runs `make tier1` against ahu's fixtures
(every `tests/*.kai` and `examples/*/main.kai` plus its
`.out.expected` sibling).

While `lnds/kaikai` remains private, the workflow needs a
PAT with `repo:read` scope on `lnds/kaikai` configured as
the repository secret `KAIKAI_REPO_TOKEN`. Once kaikai
goes public, the `token:` line in the workflow can be
removed and the secret retired.

Locally, `make tier1` does the same fixture loop. `KAI_HOME`
defaults to `../kaikai` for the sibling-checkout development
flow:

```sh
git clone github.com/lnds/kaikai     # ../kaikai
git clone github.com/lnds/ahu        # ./ahu
cd kaikai && make all                # bootstrap stages 0/1/2
cd ../ahu && make tier1
```

## Documentation

- **`docs/design.md`** — surface, decisions, MVP scope,
  external dependencies on kaikai, not-goals, references.
- **`docs/roadmap.md`** — milestones (Tongariki / Anga Roa
  / Orongo / Anakena), per-milestone scope and
  definition-of-done.
- **`docs/lane-experience-ahu-tongariki-cells-restart.md`**
  — retrospective for the cells + restart implementation
  (PRs #2, #3).
- **`docs/lane-experience-ahu-tongariki-mvp-close.md`** —
  retrospective for the full MVP arc (PRs #5–#10),
  upstream coordination summary, what worked / what did
  not.

## Documentation language

All documentation, source comments, commit messages, and PR
text in this repository are written in English. See
`CLAUDE.md` for the project conventions inherited from
kaikai.
