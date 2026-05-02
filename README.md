# ahu

Concurrency and fault-tolerance framework for
[kaikai](https://github.com/lnds/kaikai). Three composable layers —
*streams*, *cells*, *restart helpers* — built on kaikai's
structured concurrency, typed mailboxes, and effects.

ahu is **not** an OTP clone. The patterns OTP got right (restart
policies, stateful message loops, composable failure containment)
are reshaped to kaikai's primitives, not transliterated. The shape
ahu does not need (untyped messages, hot code reload, hand-rolled
supervision trees) is dropped because kaikai already has the
type-system and language features that make those workarounds
unnecessary. See `docs/design.md` §*Why ahu is not OTP* for the
full rationale.

## Status

Design phase. The repository is in **ahu-Tongariki** (MVP)
scoping: `docs/design.md` pins the surface and the seven
load-bearing decisions; `docs/roadmap.md` lays out the milestone
series. No implementation has landed yet.

`ahu-Tongariki` depends on `kaikai-Tongariki` shipping first so
that `kai fmt`, `kai test`, and `kai check` are available for ahu
development from day one. The actor and effect primitives ahu
needs (`Actor[Msg]`, `Pid[Msg]`, `Spawn`, `Cancel`, `Link`,
`Monitor`) are already in `kaikai/main` as of m8 and the v1
effects work; the cooperative scheduler that makes blocking
`receive` and `BlockSender` work is the m8.x upstream gap that
gates the start of the implementation lane.

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

Names follow the Rapa Nui vocabulary already in use across the
ecosystem. `kohau` (*inscribed wooden tablet*, the substrate that
carried the rongorongo script) names the persistence layer.
`henua` (*land / territory / domain*) names the DDD building-block
layer — the metaphor for "domain" in Domain-Driven Design is
literal in the language. The earlier placeholder names
(`ahu-db`, `ahu-ddd`) were dropped because the `ahu-` prefix
implied submodule status, when each is actually a separate
framework with its own repository, roadmap, and release cycle.

Each project has its own repository, its own `docs/roadmap.md`,
and its own `Tongariki / Anga Roa / Orongo / Anakena` series.
See `kaikai/docs/roadmap.md` for the meta-roadmap.

## What ahu provides (MVP target)

Three composable layers, used independently or together:

- **Layer 1 — Streams.** `Source[T, e]`, `Flow[A, B, e]`,
  `Sink[T, R, e]` with demand-based backpressure. For
  request/response, ETL, and event broadcasting — the bulk of
  what manutara will do.
- **Layer 2 — Cells.** `Cell[Msg, e]` is a recursive function
  `Msg → Cell[Msg] / e`. State is the recursion argument; no
  internal mutation. For long-lived stateful entities:
  websocket connections, sessions, queue workers.
- **Layer 3 — Restart helpers.** `with_restart(policy, body)`
  and `restartable_cell(policy, body)`. Supervision trees
  fall out of where the user draws nursery boundaries — no
  separate `Supervisor` type.

Plus a thin `run_app(root)` bootstrap that installs signal
handlers, opens the root nursery, and waits.

What ahu **does not** provide: process registry (deferred to
Anga Roa), distribution (Orongo at earliest), hot code reload
(permanent non-goal), specialised cell shapes (`Agent`, `Task`,
`GenStateMachine`-equivalents — cells cover them), DSL macros
(kaikai has none), Phoenix-LiveView clone (that is manutara's
surface, not ahu's). See `docs/design.md` §*Not goals* for the
full list.

## A taste

```kai
# A counter cell — recursive function over messages.
fn counter(value: Int) : Cell[CounterMsg] / Console = receive {
  Increment            -> { Console.print("++"); counter(value + 1) }
  GetValue(reply_to)   -> { reply_to.send(value); counter(value) }
  Stop                 -> done()
}

# A TCP echo server — streams + per-connection cell.
fn echo() : Unit / Net + Spawn = {
  Source.from_listener(port: 8080)
    |> Flow.flat_map((conn) => handle_connection(conn))
    |> Sink.foreach((_) => ())
    |> Stream.run
}

# Bootstrap.
fn main() : Unit / Net + Spawn + Console =
  run_app { echo() }
```

(Surface details may shift in implementation; this is the design
intent.)

## Design documents

- `docs/design.md` — the three-layer surface, seven load-bearing
  decisions, MVP scope, external dependencies on kaikai, not
  goals, references.
- `docs/roadmap.md` — milestones (Tongariki / Anga Roa / Orongo /
  Anakena), per-milestone scope and definition-of-done.
- `docs/lane-experience-ahu-design.md` — retrospective for the
  initial design lane, including the OTP-style → streams+cells
  pivot.

## CI

Tier 1 runs on every PR and on every push to `main` via
`.github/workflows/tier1.yml`. The workflow checks out a fresh
copy of `lnds/kaikai` (HEAD of `main` by default; override via
the `kaikai_ref` workflow input), bootstraps stages 0/1/2, then
runs `make tier1` against ahu's fixtures (every `tests/*.kai`
and `examples/*/main.kai` plus its `.out.expected` sibling).

While `lnds/kaikai` remains private, the workflow needs a PAT
with `repo:read` scope on `lnds/kaikai` configured as the
repository secret `KAIKAI_REPO_TOKEN`. Once kaikai goes public,
the `token:` line in the workflow can be removed and the secret
retired.

Locally, `make tier1` does the same fixture loop. `KAI_HOME`
defaults to `../kaikai` for the sibling-checkout development
flow:

```sh
git clone github.com/lnds/kaikai     # ../kaikai
git clone github.com/lnds/ahu        # ./ahu
cd kaikai && make all                # bootstrap stages 0/1/2
cd ../ahu && make tier1
```

## Documentation language

All documentation, source comments, commit messages, and PR text
in this repository are written in English. See `CLAUDE.md` for
the project conventions inherited from kaikai.
