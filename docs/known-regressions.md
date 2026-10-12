# Known regressions

External issues that block or constrain ahu but live outside this
repository. This file tracks only what is **currently** active; the
history of past blockers and their fixes lives in git and in the
upstream kaikai issue tracker, not here.

## Active

**No active blockers for tier0/tier1.** Every fixture compiles and the
run-and-diff suite passes under both backends.

## Workarounds applied in this repository

- **`examples/echo/main.kai` row alignment.** `with_cell` requires a
  single open row variable shared by the cell's step and body, so the
  echo example's `session_step` declares `NetTcp` in its row even
  though the step itself does not call `NetTcp` — the body (the echo
  loop) does. This is a one-line accommodation of kaikai's row system
  (one open row variable per row, and it must be the last item), not
  a redesign of the cell API.
