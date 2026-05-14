# Known regressions

External issues that block ahu but live outside this repository.
This file is the documented landing pad mandated by `CLAUDE.md`
§*Working tree, lane, and integrator workflow* — lanes do not fix
upstream issues inline; they record them here and leave the fix
to a dedicated upstream PR.

Status snapshot (2026-05-13, against kaikai 0.56.4):

| Issue | Layer | Status | Blocks |
|---|---|---|---|
| [kaikai#565](https://github.com/lnds/kaikai/issues/565) — privacy check leaks across module boundary | typer | **fixed in 0.56.1** | unblocks `import ahu.cell` from downstream consumers |
| [kaikai#567](https://github.com/lnds/kaikai/issues/567) — `kai build` cannot resolve a package's own modules from sibling dirs | frontend wrapper | **fixed in 0.56.x** | self-dep workaround dropped from `kai.toml` |
| [kaikai#570](https://github.com/lnds/kaikai/issues/570) — `spawn_actor` segfaults at runtime under the LLVM backend | LLVM backend | open | tier1 under LLVM (12 of 13 fixtures crash on entry); worked around by pinning backend to C |
| [kaikai#571](https://github.com/lnds/kaikai/issues/571) — LLVM backend emits "lambda info missing" for nested lambdas with `with_mailbox` | LLVM backend | open | cosmetic — moot while backend is pinned to C |

## kaikai#567 — fixed

`kai build` now treats the manifest directory as an implicit search
path, so `import ahu.cell` resolves from `tests/*.kai` and
`examples/*/main.kai` without a self-dep. The
`ahu = { path = "." }` workaround was removed from `kai.toml`.
Tier0 stays green without it under kaikai 0.56.4.

## kaikai#570 — runtime segfault in `spawn_actor` (LLVM backend only)

Every fixture that calls `spawn_actor` (directly or transitively
via `cell.with_cell` → `spawn_actor`) crashes immediately with
`EXC_BAD_ACCESS` inside `kai_actor__spawn_actor` **when the binary
is produced by the LLVM backend**. The backtrace points at the first
dereference of the closure argument after entry to the function —
`x0` is null. The 18-line standalone reproducer in the upstream
issue does not touch ahu at all.

The C backend (`KAI_BACKEND=c` or `kai build --backend=c`) produces
working binaries for all 13 fixtures. The bug is therefore localised
to LLVM codegen — most likely closure-argument lowering on the
`spawn_actor` call site — not to the kaikai runtime.

**Workaround active in this repository**: `Makefile` exports
`KAI_BACKEND ?= c`, so `make tier0` and `make tier1` pass against
kaikai 0.56.4 without manual intervention. Drop the export once
upstream lands a fix on the LLVM side.

Effect on tier1 under LLVM: 12 of 13 fixtures crash on entry. The
single fixture that runs is `examples/pipeline/`, which uses no
actor primitives (pure `list.*` pipeline over a range literal).
Tier0 (compile-only) is green at 13 fixtures regardless of backend.

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

- **`Makefile` exports `KAI_BACKEND ?= c`**: pinned for kaikai#570;
  forces every fixture to be built with the C backend so tier1
  passes against kaikai 0.56.4. Drop once kaikai#570 lands.
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
