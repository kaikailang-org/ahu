# Known regressions

External issues that block ahu but live outside this repository.
This file is the documented landing pad mandated by `CLAUDE.md`
§*Working tree, lane, and integrator workflow* — lanes do not fix
upstream issues inline; they record them here and leave the fix
to a dedicated upstream PR.

Status snapshot (2026-05-14, against kaikai 0.59.0):

**No active blockers.** Tier1 passes under both backends (C and LLVM)
with no Makefile pin. The LLVM regressions that haunted 0.56.x and
0.58 are all closed.

| Issue | Layer | Status | Blocks |
|---|---|---|---|
| [kaikai#565](https://github.com/lnds/kaikai/issues/565) — privacy check leaks across module boundary | typer | **fixed in 0.56.1** | nothing (closed) |
| [kaikai#567](https://github.com/lnds/kaikai/issues/567) — `kai build` cannot resolve a package's own modules from sibling dirs | frontend wrapper | **fixed in 0.56.x** | nothing (closed) |
| [kaikai#570](https://github.com/lnds/kaikai/issues/570) — `spawn_actor` segfaults at runtime under the LLVM backend | LLVM backend | **fully fixed in 0.59.0** | nothing (closed) |
| [kaikai#582](https://github.com/lnds/kaikai/issues/582) — LLVM `Cancel.raise()` from inside `fiber_spawn` segfaults when the parent has a mailbox | LLVM backend | **fixed in 0.58** | nothing (closed) |
| Residue of #582 — LLVM `Link.link` / `Monitor.monitor` from spawned fiber segfaults at body entry | LLVM backend | **fixed in 0.59.0** | nothing (closed) |
| [kaikai#571](https://github.com/lnds/kaikai/issues/571) — LLVM backend "lambda info missing" diagnostic | LLVM backend | **fixed in 0.59.0** (no longer emitted) | nothing (closed) |

## kaikai#567 — fixed

`kai build` now treats the manifest directory as an implicit search
path, so `import ahu.cell` resolves from `tests/*.kai` and
`examples/*/main.kai` without a self-dep. The
`ahu = { path = "." }` workaround was removed from `kai.toml`.
Tier0 stays green without it under kaikai 0.56.4.

## kaikai#570 — fully fixed in 0.59.0 (historical)

Under kaikai 0.56.4 every `spawn_actor` call segfaulted under the
LLVM backend. kaikai 0.56.6 fixed the bulk of that path
(cells, pipelines, plain `with_mailbox`, `log_basic`); kaikai
0.58 fixed the narrower #582 residue (`Cancel.raise()` from a
spawned fiber); and kaikai 0.59.0 closed the last residue
(`Link.link` / `Monitor.monitor` from a spawned fiber's body —
described under "kaikai#582 residue" below). The whole #570
arc is now history; tier1 passes under LLVM with no workaround.

## kaikai#582 — fixed in 0.58 (historical)

The 6 failing tier1 fixtures (`cross_restartable_cell{,_restart}`,
`restart_intensity_escalate`, `restart_temporary_crash`,
`restart_transient_normal`, `examples/resilient_counter`) all
share one shape: a parent inside `with_mailbox`, a child fiber
spawned via `fiber_spawn`, and the child eventually calling
`Cancel.raise()`. Under LLVM the child segfaulted *immediately
after* `Cancel.raise()` — the trampoline reached the resume
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

**Resolution**: kaikai 0.58 closed this minimal-shape segfault.
The Makefile pin (`KAI_BACKEND=c`) was retained until 0.59 because
a narrower residue (Link/Monitor in spawned bodies) still crashed
the restart fixtures even though #582's minimal repro was clean.
That residue is described next; both are now closed and the pin
was dropped.

## kaikai#582 residue — fixed in 0.59.0 (historical)

After 0.58 closed #582's minimal Cancel-raise repro, the 6 ahu
restart fixtures still segfaulted under LLVM. Ablation (May 2026)
isolated a different trigger: any `Link.link(_)` or
`Monitor.monitor(_)` from a fiber spawned via `fiber_spawn` —
no Cancel, no trap-exit, no parent mailbox required.

**Minimal reproducer that 0.59 closed** (12 lines):

```kai
import actor
import spawn

fn body() : Unit / Link + Actor[String] + Console = {
  let me = Actor.self()
  Link.link(me)
  Stdout.print("body: ran (linked to self)")
}

fn main() : Int / Console + Spawn + Link = {
  let f = fiber_spawn(() => with_mailbox { body() })
  fiber_await(f)
  0
}
```

The crash was at `kai_body + 44` with `ldr x1, [x0]` and
`x0 = NULL`, two trampoline frames deep — same shape as the
#582 backtrace, suggesting the same closure / continuation
lowering area in the LLVM emitter. Confirmed to also affect
`Monitor.monitor(_)` (not specific to Link). `Actor.send` from
the same shape was clean — the bug was specific to fiber-
relationship operations.

**Resolution**: kaikai 0.59.0 fixes the lowering. All 16 ahu
tier1 fixtures pass under LLVM at 0.59.0. Filed by ahu's
ablation lane; never opened as a separate upstream issue
because 0.59.0 dropped before that step happened.

## kaikai#571 — fixed in 0.59.0 (historical)

The LLVM backend used to print `llvm: lambda info missing at
<line>:<col>` to stderr whenever codegen descended into a nested
lambda whose body opened an effect handler block (typically
`with_mailbox`). The warning was cosmetic — compilation
succeeded — but it pointed at canonical ahu patterns
(`ahu/restart.kai:127`, `ahu/restart.kai:141`).

**Resolution**: kaikai 0.59.0 no longer emits the diagnostic.
Verified locally: `make tier0` produces no `llvm:` warnings.

## Workarounds applied in this repository

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
