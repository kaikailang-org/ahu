# Known regressions

External issues that block ahu but live outside this repository.
This file is the documented landing pad mandated by `CLAUDE.md`
§*Working tree, lane, and integrator workflow* — lanes do not fix
upstream issues inline; they record them here and leave the fix
to a dedicated upstream PR.

Status snapshot (2026-05-14, against kaikai 0.56.6):

| Issue | Layer | Status | Blocks |
|---|---|---|---|
| [kaikai#565](https://github.com/lnds/kaikai/issues/565) — privacy check leaks across module boundary | typer | **fixed in 0.56.1** | unblocks `import ahu.cell` from downstream consumers |
| [kaikai#567](https://github.com/lnds/kaikai/issues/567) — `kai build` cannot resolve a package's own modules from sibling dirs | frontend wrapper | **fixed in 0.56.x** | self-dep workaround dropped from `kai.toml` |
| [kaikai#570](https://github.com/lnds/kaikai/issues/570) — `spawn_actor` segfaults at runtime under the LLVM backend | LLVM backend | **mostly fixed in 0.56.6** | cells / streams / `cell.ask` / `with_mailbox` now run under LLVM; a narrower residue still crashes restart fixtures (see *Residue* below) |
| [kaikai#582](https://github.com/lnds/kaikai/issues/582) — LLVM `Cancel.raise()` from inside `fiber_spawn` segfaults when the parent has a mailbox | LLVM backend | open | tier1 under LLVM: 6 of 15 fixtures crash (all the `with_restart` / `restartable_cell` paths). Worked around by pinning backend to C |
| [kaikai#571](https://github.com/lnds/kaikai/issues/571) — LLVM backend emits "lambda info missing" for nested lambdas with `with_mailbox` | LLVM backend | open | cosmetic — moot while backend is pinned to C |

## kaikai#567 — fixed

`kai build` now treats the manifest directory as an implicit search
path, so `import ahu.cell` resolves from `tests/*.kai` and
`examples/*/main.kai` without a self-dep. The
`ahu = { path = "." }` workaround was removed from `kai.toml`.
Tier0 stays green without it under kaikai 0.56.4.

## kaikai#570 — mostly fixed in 0.56.6

Under kaikai 0.56.4 every `spawn_actor` call segfaulted under the
LLVM backend. kaikai 0.56.6 fixes the bulk of that path: cells
(`cell.with_cell`, `cell.ask`), pipelines, plain `with_mailbox`,
and `log_basic` now compile and run under LLVM identically to the
C backend. **9 of 15 tier1 fixtures pass under LLVM** at 0.56.6;
they did not under 0.56.4.

A narrower residue remains and still tumbles the rest of tier1
— filed as kaikai#582. See the next section.

## kaikai#582 — `Cancel.raise()` from a spawned fiber, parent in `with_mailbox`

The 6 failing tier1 fixtures (`cross_restartable_cell{,_restart}`,
`restart_intensity_escalate`, `restart_temporary_crash`,
`restart_transient_normal`, `examples/resilient_counter`) all
share one shape: a parent inside `with_mailbox`, a child fiber
spawned via `fiber_spawn`, and the child eventually calling
`Cancel.raise()`. Under LLVM the child segfaults *immediately
after* `Cancel.raise()` — the trampoline reaches the resume
continuation with a null pointer.

**Minimal reproducer** (no `ahu.restart`, no `Link`, no
`fiber_set_trap_exit`, no captures):

```kai
import actor
import spawn

fn main_inner() : Unit / Actor[String] + Spawn + Cancel + Console = {
  let _ = fiber_spawn(() => {
    Stdout.print("child: about to raise")
    Cancel.raise()
  })
  Stdout.print("main: parking on receive")
  let r = Actor.receive()
  Stdout.print("main: got " ++ r)
}

fn main() : Int / Console + Spawn + Cancel = {
  with_mailbox { main_inner() }
  0
}
```

- C backend (`kai build --backend=c`): prints both lines, then
  `kai: fiber finished with empty run queue (1 parked) — deadlock`
  and exits 1. Expected behaviour: the child raised Cancel without
  trap-exit or Link, so nothing wakes the parent.
- LLVM backend (`kai build --backend=llvm`): prints both lines,
  then segfaults inside the child fiber's lambda
  (`_kai_lam_18 + 144`, `ldr x1, [x0]` with `x0 = NULL`),
  trampoline two frames deep.

The minimal case rules out: `Link`, `fiber_set_trap_exit`, the
inner `with_mailbox`, the captured `parent: Pid[String]`, and any
indirection through ahu. The shape that triggers it is
specifically *Cancel.raise from a fiber whose parent is parked on
its own mailbox*. The crash address — null on the first dereference
after the resume — points at the LLVM lowering of the `Cancel`
op's continuation pointer, not at runtime data.

The kaikai 0.56.4 bug — every `spawn_actor` segfaulting on entry —
was much wider; this residue is the same general area (closure /
continuation lowering under LLVM) but a small leftover slice. It
needs its own upstream issue.

**Workaround active in this repository**: `Makefile` exports
`KAI_BACKEND ?= c`, so `make tier0` and `make tier1` pass against
kaikai 0.56.6 without manual intervention. Drop the export once
kaikai#582 lands.

Effect on tier1 under LLVM: 6 of 15 fixtures crash, all in the
restart paths. The other 9 (cells, ask, log, pipeline, streams,
counter example) are clean under LLVM at 0.56.6. Tier0
(compile-only) is green at 15 fixtures regardless of backend.

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

- **`Makefile` exports `KAI_BACKEND ?= c`**: pinned for kaikai#582
  (residue of #570 still active under LLVM in 0.56.6); forces
  every fixture to be built with the C backend so tier1 passes
  against kaikai 0.56.6. Drop once kaikai#582 lands.
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
