# Known regressions

External issues that block or constrain ahu but live outside this
repository. This file tracks only what is **currently** active; the
history of past blockers and their fixes lives in git and in the
upstream kaikai issue tracker, not here.

## Active

**No active blockers for tier0/tier1.** All fixtures compile and the
run-and-diff suite passes under both backends, with one documented
limitation:

- **`examples/log_demo`** reports `effect not handled in fiber: Log`.
  A cell runs in its own fiber and does not inherit a `Log` handler
  installed outside it, so logging directly from a cell step is
  unsupported — a cell can perform only effects handled within its
  own fiber (`Actor`, plus the native `Console` leaves). The fixture
  is left running so the limitation stays visible; logging from a
  cell needs a different shape (route events through the cell's
  mailbox, or log from the driver/supervisor fiber).

## Workarounds applied in this repository

- **`examples/echo/main.kai` row alignment.** `with_cell` requires a
  single open row variable shared by the cell's step and body, so the
  echo example's `session_step` declares `NetTcp` in its row even
  though the step itself does not call `NetTcp` — the body (the echo
  loop) does. This is a one-line accommodation of kaikai's row system
  (one open row variable per row, and it must be the last item), not
  a redesign of the cell API.
