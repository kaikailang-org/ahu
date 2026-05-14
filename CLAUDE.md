# ahu

Concurrency and fault-tolerance framework for kaikai: three
composable layers — *streams*, *cells*, *restart helpers* — built on
`Actor[Msg]`, `Spawn`, `Cancel`, `Link`, `Monitor`, and the kaikai
effect system. **Not** an OTP clone; the patterns OTP got right are
reshaped to kaikai's primitives, the rest is dropped. The full
surface and rationale live in `docs/design.md`; this file is the
cross-cutting conventions agents must follow.

## Project language conventions

- **Commit messages, PR titles, PR bodies, and code comments are
  English. No exceptions.** This includes any technical jargon. If a
  brief reaches you in Spanish, the artefacts you produce are still
  English. Examples that have leaked from kaikai sessions and must be
  avoided here as well: "mentira" → "structural lie", "letra chica"
  → "fine print", "trampa" → "trap" or "pitfall", "aterrizó" →
  "landed".
- **All documentation in English** — `README.md`, `docs/`, source
  comments, anything user-facing.
- Conversation with the user (Spanish) is not documentation and does
  not appear in the repo.

## Inherited from kaikai

ahu inherits its principle stack and lane discipline from kaikai. The
relevant cross-cutting conventions are reproduced here in compact form
so an agent working on ahu does not need to keep `kaikai/CLAUDE.md`
open in another window. The full text lives upstream in
`kaikai/CLAUDE.md`.

### Tier 1 — Load-bearing

1. **Safe at compile time.** Every effect a callback or framework
   helper uses appears in its row. No null. Runtime escapes (`panic`,
   unfilled `?`, `todo!`, FFI) are explicit and audited.
2. **Runtime-efficient.** Monomorphisation, mandatory TCO, one-shot
   continuations as the zero-cost default. ahu does not pay for
   abstractions that the kaikai compiler can specialise away — the
   `Behavior` and `Supervisor` shapes monomorphise per use site.
3. **Fast compilation.** ahu does not introduce constructs that
   require constraint solvers, HKTs, or row-polymorphic dispatch
   beyond what kaikai already provides.

### Tier 2 — Aspirational

4. **Few forms, each with clear intent.** `Cell` is the one shape
   for long-running stateful entities. `Source` / `Flow` / `Sink`
   are the three shapes for stream-based data flow. `with_restart`
   / `restartable_cell` are the only two restart-policy helpers.
   No alternate framings (no `Agent`, no `Task`, no
   `GenStateMachine`, no `Supervisor` type) in ahu-Tongariki —
   the canonical surface stays small until usage data motivates
   additions.
5. **Approachable core, novel where it pays off.** Reactive-streams
   veterans recognise `Source`/`Flow`/`Sink` immediately;
   Akka-Typed users recognise the recursive-function cell shape.
   The novelty is in the typed mailboxes (`Pid[Msg]`), the
   region-branded scoping (kaikai), the effect rows in every
   signature (kaikai), and the recovery of OTP supervision
   strategies as nursery placement rather than as a separate enum.
6. **Few visible concepts, layered.** A program that uses only
   streams pays for nothing in cells or restart. A program with
   one cell and no crashes pays for nothing in restart. A program
   that uses kaikai primitives directly pays for none of ahu.

### Tier 3 — Strategic bet

7. **LLM authorability.** ahu's surface is intentionally narrow
   and structurally repetitive (recursive-function cells, algebraic
   stream combinators, two restart helpers). The structured form
   makes completion-by-template a viable LLM workflow once
   `kai lsp` ships in `kaikai-Anga Roa`.

### Tie-breakers

- Safety beats ergonomics.
- Fast compilation beats generality.
- Runtime efficiency beats expressive novelty.
- Approachability beats one-canonical-form.
- LLM-friendliness is not a veto.

## Working tree, lane, and integrator workflow

Inherited verbatim from kaikai. The summary every agent must follow
without being told:

- **Working tree must be clean** at every commit. No `git status`
  output left dirty between commits, no unrelated stashed work.
- **Lane discipline.** A worktree fixes one thing. Bugs found outside
  the lane are documented in `docs/known-regressions.md` (or, until
  that file exists, in `docs/design.md` under "External dependencies
  on kaikai" if the gap is upstream), not fixed inline.
- **VERSION + CHANGELOG.** Do **not** bump `VERSION` in a feature
  PR. Add the closing-commit entry to `CHANGELOG.md` under
  `## [Unreleased]` and leave `VERSION` untouched. The integrator —
  the human merging the PR — assigns the final version number after
  merge. This rule exists because parallel lanes cannot know each
  other's order of merge.
- **Integrator workflow B (post-CI).** Once tier1 is green on the
  PR (when CI exists; until then, integrator review):
  1. Merge via `gh pr merge <N> --merge`.
  2. Land a follow-up release commit on `main` that bumps `VERSION`
     and renames `[Unreleased]` to the chosen version. This commit
     goes direct to `main` (admin bypass on branch protection if any
     is configured).
  The release commit is its own commit, not bundled inside the merge
  commit. The integrator decides the version number after seeing
  what parallel lanes already took.

## Testing tiers (when implementation lands)

ahu-Tongariki shipped the first implementation; the test runner is
the repo `Makefile` driving the kaikai compiler. Tiers:

- **Tier 0 — pre-commit fast sanity (~30–60s).** ahu unit tests over
  the kaikai test runner.
- **Tier 1 — gated by CI on every PR.** Tier 0 plus integration tests
  that boot a small supervision tree and verify lifecycle behaviour
  (start, restart, shutdown).
- **Tier 2 — `make daily`.** Tier 1 plus stress fixtures: large
  supervision trees, mailbox saturation under `BlockSender`, link
  cascades.

The exact Make targets get pinned in the `ahu-Tongariki` implementation
lane. Until then this section is a forward-looking placeholder, not a
gate.

## Things to avoid

- **Do not re-design kaikai primitives.** `Actor[Msg]`, `Pid[Msg]`,
  `Spawn`, `Cancel`, `Link`, `Monitor` are upstream contracts. If
  ahu's design doc discovers a gap (e.g. a missing op the framework
  needs), document it in `docs/design.md` §*External dependencies on
  kaikai* and surface it as a kaikai issue. Do not patch kaikai from
  this repository.
- **Do not clone OTP.** Cells are not gen_servers; restart helpers
  are not Supervisors; `run_app` is not an OTP Application. If
  the design instinct is to "transliterate the gen_X callback
  table" or "add a `Strategy` enum", stop and re-read
  `docs/design.md` §*Why ahu is not OTP*. The patterns OTP got
  right are kept in shape; the OTP-specific machinery is not.
- **Do not introduce alternate cell shapes** in ahu-Tongariki.
  No `Agent`, no `Task`, no `GenStateMachine`. One cell shape,
  one stream shape, two restart helpers. Specialised forms come
  post-Tongariki with usage data, never pre-emptively.
- **Do not introduce a `Supervisor` type.** Supervision falls out
  of nursery placement plus restart helpers. See
  `docs/design.md` §*Decision 3*. If a use case really needs more
  than nurseries + restart, document it as a follow-up; do not
  invent a new abstraction inline.
- **Do not reach for a global registry, a global supervisor, or
  any other ambient state**. The kaikai region-brand on
  `Pid[Msg]` is load-bearing for safety. Designs that want to
  share Pids across unrelated nurseries must go through an
  explicit handoff or, post-Tongariki, a per-nursery `Registry`
  capability — see `docs/design.md` §*Decision 4*.
- **Do not design for hot code reload.** Kaikai compiles to native
  binaries via LLVM; versioned module loading is incompatible
  with the runtime model. See `docs/design.md` §*Decision 5*.
- **Do not design for distribution** in ahu-Tongariki or
  ahu-Anga Roa. Cross-node Pids land at the earliest in ahu-Orongo
  and depend on a serialisation protocol that is not yet
  specified.
- **Do not design against post-MVP targets** (Windows, WASM,
  multi-thread scheduler) but do not invest effort in them either.

## Repository layout

ahu follows the kaikai package convention: module names derive
from the `.kai` file's path relative to the package root (the
directory containing `kai.toml`). The three Layer 2 / Layer 3
modules live at the top level under `ahu/`:

```
kai.toml
ahu/
  cell.kai      # import ahu.cell
  restart.kai   # import ahu.restart
  app.kai       # import ahu.app
examples/
tests/
docs/
```

A downstream consumer adds the dependency with
`kai add github.com/kaikailang-org/ahu` and imports the modules
dotted as above. The Makefile passes `--path .` to `kaic2` so
in-repo fixtures resolve the same module names without
re-publishing.

Do not reintroduce a `src/` prefix. Putting `cell.kai` under
`src/ahu/cell.kai` would make its kaikai module name
`src.ahu.cell`, which breaks every `import ahu.cell` in fixtures
and downstream code.

## Current state

`docs/design.md` pins the design. `docs/roadmap.md` pins the
milestone series. ahu-Tongariki shipped 2026-05-02 (see
`docs/lane-experience-ahu-tongariki-mvp-close.md`).
