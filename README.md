# ahu

OTP-style framework for [kaikai](https://github.com/lnds/kaikai). Builds
behaviors, supervision trees, and applications on top of kaikai's
`Actor[Msg]`, `Spawn`, `Cancel`, `Link`, and `Monitor` effects.

## Status

Design phase. The repository is in **ahu-Tongariki** (MVP) scoping:
`docs/design.md` pins the surface and the seven load-bearing decisions,
and `docs/roadmap.md` lays out the milestone series. No implementation
has landed yet.

`ahu-Tongariki` depends on `kaikai-Tongariki` shipping first so that
`kai fmt`, `kai test`, and `kai check` are available for ahu development
from day one. The actor and effect primitives ahu needs (`Actor[Msg]`,
`Pid[Msg]`, `Spawn`, `Cancel`, `Link`, `Monitor`, `set_trap_exit`) are
already in `kaikai/main` as of m8 and the v1 effects work.

## Position in the ecosystem

ahu sits in the second layer of the five-project stack:

```
kaikai      (the language)
   ↓
ahu         (this repository — OTP-style framework)
   ↓
ahu-db      (database / persistence layer)
   ↓
ahu-ddd     (DDD building blocks)
   ↓
manutara    (Phoenix-LiveView-style web framework)
```

Each project has its own repository, its own `docs/roadmap.md`, and its
own `Tongariki / Anga Roa / Orongo / Anakena` series. See
`kaikai/docs/roadmap.md` for the meta-roadmap.

## What ahu provides (MVP target)

The ahu-Tongariki surface, in order of stack depth:

- **`Behavior`** — the `gen_server` analogue. A small record of
  callbacks (`init`, `handle_call`, `handle_cast`, `terminate`)
  combined with a typed mailbox into a long-running, supervised
  process. Each callback carries its own effect row; the framework
  threads it through.
- **`Supervisor`** — the `one_for_one` strategy. A supervisor is itself
  a behavior that monitors a fixed set of children, restarts them
  according to declared restart policy, and surfaces unrecoverable
  failures to its own supervisor.
- **`Application`** — a top-level entry point that boots a supervision
  tree, installs a shutdown signal handler, and waits for the root
  supervisor to settle.

What is **not** in ahu-Tongariki: other supervision strategies, process
registry, distribution, and hot code reload. See `docs/design.md` §*Not
goals* and `docs/roadmap.md` for the full scope split.

## Design documents

- `docs/design.md` — surface, decisions, MVP scope, end-to-end
  verification, and repository layout.
- `docs/roadmap.md` — milestones (Tongariki / Anga Roa / Orongo /
  Anakena), scope, and definition-of-done per milestone.
- `docs/lane-experience-ahu-design.md` — retrospective for the
  initial design lane.

## Documentation language

All documentation, source comments, commit messages, and PR text in
this repository are written in English. See `CLAUDE.md` for the
project conventions inherited from kaikai.
