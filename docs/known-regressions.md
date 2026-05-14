# Known regressions

External issues that block ahu but live outside this repository.
This file is the documented landing pad mandated by `CLAUDE.md`
§*Working tree, lane, and integrator workflow* — lanes do not fix
upstream issues inline; they record them here and leave the fix
to a dedicated upstream PR.

Status snapshot (2026-05-13, against kaikai 0.56.1):

| Issue | Layer | Status | Blocks |
|---|---|---|---|
| [kaikai#565](https://github.com/lnds/kaikai/issues/565) — privacy check leaks across module boundary | typer | **fixed in 0.56.1** | unblocks `import ahu.cell` from downstream consumers |
| [kaikai#567](https://github.com/lnds/kaikai/issues/567) — `kai build` cannot resolve a package's own modules from sibling dirs | frontend wrapper | open | tier0 (worked around via self-dep in `kai.toml`) |
| [kaikai#570](https://github.com/lnds/kaikai/issues/570) — `spawn_actor` segfaults at runtime | runtime / codegen | open | tier1 (12 of 13 fixtures crash on entry) |
| [kaikai#571](https://github.com/lnds/kaikai/issues/571) — LLVM backend emits "lambda info missing" for nested lambdas with `with_mailbox` | LLVM backend | open | cosmetic — binaries are produced, semantics unverified |

## kaikai#567 — `kai build` needs a self-dep workaround for in-package fixtures

`kai build examples/<name>/main.kai` from inside ahu fails with
`cannot open module 'ahu.cell' (tried examples/<name>/ahu/cell.kai)`
unless `kai.toml` declares `ahu = { path = "." }` as a dependency.
The wrapper only emits `--path` flags for declared dependencies and
never adds the manifest directory itself as a search path, so the
package cannot compile its own examples or tests through `kai build`
without the self-reference.

The current `kai.toml` carries the workaround with a comment that
points at this issue. Remove the self-dep once the wrapper is
patched.

## kaikai#570 — runtime segfault in `spawn_actor`

Every fixture that calls `spawn_actor` (directly or transitively
via `cell.with_cell` → `spawn_actor`) crashes immediately with
`EXC_BAD_ACCESS` inside `kai_actor__spawn_actor`. The backtrace
points at the first dereference of the closure argument after entry
to the function — `x0` is null. The 18-line standalone reproducer in
the upstream issue does not touch ahu at all.

Effect on tier1: 12 of 13 fixtures crash on entry. The single
fixture that runs is `examples/pipeline/`, which uses no actor
primitives (pure `list.*` pipeline over a range literal). Tier0
(compile-only) is green at 13 fixtures.

Until kaikai patches the spawn path, tier1 against 0.56.x is a
hard fail for ahu and any downstream library that relies on
typed-actor patterns.

## kaikai#571 — LLVM backend lambda-info diagnostic

The LLVM backend prints `llvm: lambda info missing at <line>:<col>`
to stderr whenever codegen descends into a nested lambda whose body
opens an effect handler block (typically `with_mailbox`). It's
emitted as a warning — compilation succeeds and a binary is
produced — but it points at canonical patterns:

- `ahu/restart.kai:127`: `with_mailbox { cell.with_cell(initial, step, driver) }` inside the `with_restart` body.
- `ahu/restart.kai:141`: `fiber_spawn(() => with_mailbox { body(parent) })`.

We have not verified that the produced IR is correct in the
absence of whatever metadata the diagnostic complains about. The
6-line standalone reproducer in the issue reliably triggers it.

## Workarounds applied in this repository

- **`kai.toml` self-dep**: pinned for kaikai#567; comment in
  `kai.toml` points at the issue.
- **`examples/echo/main.kai` row alignment**: the echo example's
  `session_step` had effect row `Actor[SessionMsg] + Console`, but
  the body passed to `cell.with_cell` runs under
  `Actor[SessionMsg] + Console + NetTcp` (the echo loop calls
  `NetTcp.recv` / `NetTcp.send`). `with_cell` requires a single row
  variable shared by both — that's a structural constraint imposed
  by kaikai's row system (only one open row variable per row, must
  be the final item). The fix added `NetTcp` to `session_step`'s
  declared row even though the function does not use it. This is a
  one-line accommodation, not a redesign of the cell API.

## Past upstream issues (now closed)

- **kaikai#565**: privacy check did not preserve the home module of
  a declaration across import chains. Caused spurious "private to
  module X" errors when `actor.kai`'s internal helpers were
  visited via a transitive import. Closed and shipped in 0.56.1
  (commit `b3cafaa`, PR #566). The fix is the reason `kai add
  github.com/kaikailang-org/ahu` resolves end-to-end today.
