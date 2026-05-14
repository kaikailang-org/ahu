# Known regressions

External issues that block ahu but live outside this repository,
plus internal design defects discovered mid-lane that cannot be
fixed without their own dedicated lane. This file is the documented
landing pad mandated by `CLAUDE.md` §*Working tree, lane, and
integrator workflow* — lanes do not fix issues outside their scope
inline; they record them here and leave the fix to a follow-up.

## 2026-05-13 — `ahu/cell.kai` crosses stdlib `actor` privacy boundary

**Discovered:** during the package-layout lane (`ahu-pkg-layout`),
when validating that `kai add github.com/kaikailang-org/ahu` resolves
end-to-end against kaikai 0.56.x.

**Symptom.** Any consumer that does `import ahu.cell` and compiles
with kaikai 0.56.x sees two paired errors:

```
error: `overflow_code` is private to module `cell`; mark the
       declaration `pub` or call it through a qualified path
error: `alloc_for_policy` is private to module `cell`; mark the
       declaration `pub` or call it through a qualified path
```

Both `overflow_code` and `alloc_for_policy` are private helpers in
`stdlib/actor.kai`. The error reporter attributes them to module
`cell` because that is the consumer-facing module name (last
segment of `ahu.cell`).

**Minimal reproducer.** A `cell.kai` with only `pub type StepResult`
and `pub fn keep` / `pub fn cell_done` — *plus a single
`import actor` line* — already triggers the error in a consumer
that does nothing more than call `cell.keep(42)`. Removing the
`import actor` line makes the same consumer compile cleanly.

**Root cause (design defect in ahu, not a kaikai bug).** kaikai 0.56
correctly enforces module privacy: `pub` items are exported,
non-`pub` items are private to the declaring module. `ahu/cell.kai`
does an unqualified `import actor`, which brings into `cell`'s scope
identifiers that are private to `actor` (`overflow_code`,
`alloc_for_policy`, raw `mailbox_*` ops). The compiler detects that
the public surface of `cell` is reachable from privates of `actor`
and refuses to compile a consumer that imports `cell`. This is
working as intended — what was broken was the cell module's
assumption that "import actor" gave it free access to actor's
internals while still being safely consumable downstream.

kaikai 0.36.x (the version Tongariki shipped against) did not
enforce module privacy transitively, so the defect went unobserved
until the upgrade to 0.56.

**Why this is not a one-line fix.** Selective import
(`import actor.{spawn_actor}`) does not eliminate the error in this
context — the cell module's polymorphic signatures (`[State, Msg, e]`
on `with_cell`) force the type checker to re-elaborate the actor
module from cell's scope at the consumer's call site, which still
encounters the privates. The correct fix is to redesign `cell.kai`
so it does not depend on `actor.kai`'s implementation at all:
either re-spawn through `fiber_spawn` from `stdlib/spawn.kai` and
open the `Actor[Msg]` handler locally (the same way `with_mailbox`
does), or take a hard dependency only on `spawn_actor` via a
qualified path and rely on kaikai's existing public surface.

**Status:** out of scope for the package-layout lane. Follow-up lane
`ahu-cell-privacy-fix` will redesign Layer 2 to respect module
privacy. Until then, tier1 against kaikai 0.56.x is red. The
package-layout work in this lane is independently correct: external
consumers can still resolve `ahu/cell.kai` through `kai add`, the
compiler successfully walks the import graph to cell, and only then
hits the privacy violation that lives inside cell itself.

**Reproducer (post-fix verification check).** A 6-line `tiny.kai`:

```kai
import ahu.cell

fn main() : Int = {
  let x = cell.keep(42)
  match x {
    Continue(_) -> 0
    Done        -> 1
  }
}
```

with `ahu = { path = "..." }` in the consumer's `kai.toml` should
compile cleanly once the cell-privacy fix lands.
