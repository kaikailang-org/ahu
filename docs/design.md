# ahu design

Living document for the kaikai-native concurrency and fault-tolerance
framework that runs underneath manutara and friends.

> **Status (2026-05-02):** Layer 2 (cells), Layer 3 (restart
> helpers), and Layer 1 (streams) have all shipped against
> kaikai 0.35.x — see PRs `#2`, `#3`, and `#5`. Retrospective
> for the cells + restart lanes lives in
> `docs/lane-experience-ahu-tongariki-cells-restart.md`;
> Layer 1 closed within a single commit because the heavy
> lifting was done upstream by `lnds/kaikai#106`. The
> remaining MVP pieces — `run_app` bootstrap and the TCP
> echo integration example — are gated on `lnds/kaikai#107`
> (Signal effect for graceful shutdown) and on lazy stream
> sources for cross-fiber composition.
>
> **Origin (2026-05-02 earlier):** This document was pivoted
> from an OTP-style draft to the current three-layer shape.
> Rationale: Erlang's OTP solutions exist to compensate for
> things kaikai already has (structured concurrency, typed
> mailboxes, effects in the row). Cloning OTP would import
> baggage that kaikai does not need. The three-layer design
> — *streams*, *cells*, *restart helpers* — keeps the
> load-bearing patterns OTP got right while dropping
> everything that is downstream of Erlang's specific
> runtime constraints. The OTP draft is preserved in this
> file's git history.

## Context

ahu is the second layer of the five-project lnds ecosystem:

```
kaikai      (the language)
   ↓
ahu         (this project — concurrency and fault-tolerance layer)
   ↓
kohau       (database / persistence)
   ↓
henua       (DDD building blocks)
   ↓
manutara    (web framework, LiveView-shaped)
```

Names follow the Rapa Nui vocabulary established by `kaikai` and
`ahu`. `kohau` is the inscribed wooden tablet that carried the
rongorongo script — the substrate metaphor maps cleanly to a
persistence layer. `henua` means *land / territory / domain* — the
DDD-vocabulary mapping is direct.

ahu's job, in one sentence: **package kaikai's effect, fiber, and
mailbox primitives into three composable layers — streams, cells,
restart helpers — that manutara (and any other downstream user) can
build on without re-deriving the patterns each time.**

ahu is **not** an OTP clone. See §*Why ahu is not OTP* below.

This document is updated as decisions are closed.

## Why ahu is not OTP

OTP is the canonical example of a high-quality concurrency + fault-
tolerance framework. The temptation to copy it is real — gen_server,
supervisors, applications, and the supervision tree pattern have
worked well for decades on BEAM. But OTP's shape is **downstream of
Erlang's runtime constraints**, not upstream of "what concurrent
software needs". Concretely:

| OTP solves | Because Erlang/BEAM has | kaikai has |
|---|---|---|
| Supervision trees | No structured concurrency / no lexical scope for processes | **Nurseries with regional brand on `Pid[Msg]`** |
| Behavior callbacks (`gen_server`, `gen_event`, etc.) | Untyped messages — needed callbacks to recover some structure | **Typed mailboxes by construction (`Pid[Msg]` only carries one `Msg`)** |
| `code_change/3` | Hot code reload swapping versions in-place | **No hot reload (native binaries via LLVM)** |
| Process registry (`Registered.`) | No way to share Pids without manual passing | Region-brand makes registry harder, but explicit handoff fits the type system |
| Distribution Protocol | A demand for cross-node calls dating to telecom switches | Single-node first; distribution is a later, separately-designed concern |

What OTP got right and ahu *does* keep:

- **Restart policies** as a first-class shape. Permanent / Transient
  / Temporary semantics, with intensity-over-period escalation, are
  patterns that need to land in the framework rather than being
  rewritten by every user.
- **The "stateful entity with a typed message loop" pattern** for
  long-running connections, sessions, and services. ahu calls this
  a *cell* (deliberately not "behavior" — see §*Decision 1*).
- **Composable failure containment**. Failed work is contained, not
  catastrophic. ahu does this through nurseries + restart helpers,
  not through a separate `Supervisor` type.

What ahu deliberately drops compared to OTP:

- The full `gen_server` callback table (`init`, `handle_call`,
  `handle_cast`, `handle_info`, `terminate`, `code_change`).
  Replaced by a recursive function shape (Akka-Typed lineage).
- The `Supervisor` type as a separate abstraction. Replaced by
  `with_restart(policy, body)` helpers wrapped in nurseries.
- `Application` as a heavyweight lifecycle container. Replaced by
  a thin `run_app(root)` helper that installs signal handlers and
  blocks.
- Specialised behaviours (`gen_event`, `gen_statem`, `Agent`,
  `Task`). Each is either expressible as a cell + helpers, or
  belongs to a different paradigm (events → streams).
- DSL-style declarations (Elixir's `use GenServer` macro
  expansion). Kaikai has no macros and ahu does not pretend
  otherwise.

What ahu adds that OTP does not have:

- **Streams as a first-class layer.** Reactive streams with typed
  values, effect rows, and demand-based backpressure. For
  request/response flows, ETL, and event broadcasting, streams
  beat actors structurally. Phoenix had to bolt streams onto OTP
  late (via `GenStage` and friends). ahu has them from day one.
- **Effects in the row, throughout.** Every cell, every stream
  combinator, every restart helper carries its effect row in its
  type. There is no ambient `IO` capability hiding inside a
  callback — `Console`, `File`, `Net`, `Db` all appear in the
  signature.

## The substrate kaikai provides

ahu builds on these primitives, all already in kaikai's main
branch as of m8 + the v1 effects work:

- `Actor[Msg]` effect — typed mailboxes, `self() / send() /
  receive()` operations.
- `Pid[Msg]` — region-branded handle, scoped to the producing
  nursery.
- `Spawn` effect — `spawn / await / select / cancel /
  set_trap_exit`.
- `Cancel` effect — cooperative cancellation at yield points.
- `Link` and `Monitor` effects — bidirectional and unidirectional
  failure observation.
- `MailboxPolicy = Unbounded | Bounded(c, Overflow)` with
  `Overflow = DropOldest | DropNewest | BlockSender`.
- Nurseries as `Spawn` handler installation
  (`docs/structured-concurrency.md`).
- Single-dispatch protocols + `#derive(...)` (m12.8) for
  structural impls.
- Effect row polymorphism (`/ e`) — the load-bearing mechanism
  for ahu's signatures.

ahu does not redesign any of these. Where it discovers gaps, the
gap is documented in §*External dependencies on kaikai*.

## The three layers

ahu is three layers, used independently or composed:

```
┌──────────────────────────────────────────────────────────────┐
│ Layer 3 — Restart helpers                                    │
│   with_restart(policy, body), intensity/period escalation    │
│   Used by: cells that need to survive crashes                │
├──────────────────────────────────────────────────────────────┤
│ Layer 2 — Cells                                              │
│   Cell[Msg] = (Msg) -> Cell[Msg] / e (recursive function)    │
│   start_cell, done(), stop()                                 │
│   Used by: long-running stateful entities                    │
├──────────────────────────────────────────────────────────────┤
│ Layer 1 — Streams                                            │
│   Source[T, e], Flow[A, B, e], Sink[T, R, e]                 │
│   Used by: request/response, ETL, broadcasts                 │
├──────────────────────────────────────────────────────────────┤
│ Layer 0 — kaikai primitives                                  │
│   Actor[Msg], Pid[Msg], Spawn, Cancel, nursery, effects      │
└──────────────────────────────────────────────────────────────┘
```

A program that needs only streams pays for nothing else. A program
with one cell and no restart needs nothing from Layer 3. A program
that uses just kaikai primitives directly pays for none of ahu —
ahu is opinionated infrastructure for cases where the patterns
recur, not a mandatory shell around every concurrent program.

### Layer 1 — Streams

**ahu-Tongariki ships ZERO stream-layer code.** The pipeline
combinators all live in kaikai's stdlib + language syntax; ahu's
contribution at this layer is the canonical pipeline pattern
plus a fixture demonstrating it with effectful callbacks.

The building blocks are:

| Piece | Where it lives |
|---|---|
| `[a..b]` range list literal | kaikai language (m7b sugar) |
| `\|` map-pipe (`xs \| f` ≡ `list.map(xs, f)`) | kaikai language (m7b sugar) |
| `\|>` apply-pipe | kaikai language |
| `list.map`, `list.filter`, `list.foldl`, `list.foldr`, `list.foreach`, `list.length`, `list.reverse`, `list.zip`, `list.unzip` | kaikai stdlib `core.list` (closed by `lnds/kaikai#106` in 0.35.x) |

Each higher-order helper carries a row-poly callback:

```kai
list.map[a, b, e](xs: [a], f: (a) -> b / e) : [b] / e
```

so effects flow through. The canonical pipeline is:

```kai
fn double_traced(x: Int) : Int / Console = {
  Stdout.print("seen=" ++ int_to_string(x))
  x * 2
}

fn run() : Unit / Console = {
  let total = [0..5]
              | double_traced
              |> list.filter(_, (x) => x > 5)
              |> list.foldl(_, 0, (acc, x) => acc + x)
  Stdout.print("total=" ++ int_to_string(total))
}
```

`Console` from `double_traced` flows through `|` (map-pipe over
the range), survives the pure `list.filter` and `list.foldl`
calls, and lands in `run`'s row. Effects-in-types holds without
ahu adding any code.

Reference fixture: `tests/stream_pipeline.kai` (output frozen
in the sibling `.out.expected`).

**What this Layer is NOT (yet):**

Lazy / unbounded sources do not fit the eager-list shape:

- `Source.from_listener(port: Int)` — TCP listener that yields
  connections indefinitely.
- `Source.tick(every: Duration)` — periodic timer.
- `Source.from_websocket(ws)` — stream of incoming frames.

These need either upstream support for row-poly type
parameters in records (so `Source[T, e]` becomes expressible)
or a function-value-based encoding that composes through
`|>` end-to-end. Both are post-Tongariki work. The TCP echo
MVP target therefore uses an explicit nursery + per-connection
cell (Layer 2) + restart wrapper (Layer 3) loop instead of a
streamed source — see §End-to-end MVP verification.

**Why ahu does not re-export `list.*` under `stream.*`:**

The stdlib spelling stays canonical. Aliasing
`stream.map` ≡ `list.map` would force users to remember which
prefix ahu prefers without adding any expressive power.
Convention is the cheaper fix: ahu code uses `list.*` directly
plus the `[..]` / `|` / `|>` syntax. When lazy sources land,
they get their own ahu module (`src/source.kai` or similar) —
new surface, not aliases.

### Layer 2 — Cells

A cell is a long-running stateful entity with a typed mailbox.
The user writes a **step function** `(State, Msg) -> StepResult[State] / e`
and ahu runs it inside a fiber that parks on `Actor.receive()`
between iterations. State threads through the recursion (no
internal mutation); behaviour switches are encoded as a sum
type for State (Active → Paused → Draining as variants).

```kai
# In src/ahu/cell.kai (imported as `import ahu.cell`):
pub type StepResult[State] = Continue(State) | Done

pub fn keep[State](s: State) : StepResult[State] = Continue(s)
pub fn cell_done[State]() : StepResult[State] = Done

pub fn with_cell[State, Msg, R, e](
  initial: State,
  step:    (State, Msg) -> StepResult[State] / e,
  body:    (Pid[Msg]) -> R / e
) : R / Spawn + e
```

A counter cell, end-to-end:

```kai
type CounterMsg = Increment | GetValue(Pid[CounterMsg])
                | ReplyValue(Int) | Stop

fn counter_step(value: Int, msg: CounterMsg)
  : StepResult[Int] / Console + Actor[CounterMsg]
= match msg {
    Increment          -> {
      Stdout.print("++ to " ++ int_to_string(value + 1))
      keep(value + 1)
    }
    GetValue(reply_to) -> {
      Actor.send(reply_to, ReplyValue(value))
      keep(value)
    }
    ReplyValue(_)      -> keep(value)
    Stop               -> cell_done()
  }

fn run() : Unit / Spawn + Console + Actor[CounterMsg] = {
  let me = Actor.self()
  with_cell(0, counter_step, (counter) => {
    Actor.send(counter, Increment)
    Actor.send(counter, GetValue(me))
    match Actor.receive() {
      ReplyValue(v) -> Stdout.print("got " ++ int_to_string(v))
      _             -> Stdout.print("unexpected")
    }
    Actor.send(counter, Stop)
  })
}
```

Four things to notice:

1. **State is the recursion argument**, not internal mutation.
   The transition `value → value + 1` is explicit in `keep(value + 1)`.
2. **Effects flow through the row.** `counter_step` declared
   `/ Console + Actor[CounterMsg]`; `with_cell` propagates the
   union into its caller via the open row variable `e`.
3. **Termination is structural.** `cell_done()` returns the
   `Done` sentinel; the dispatcher recognises it and the fiber
   exits cleanly. There is no `terminate(state, reason)`
   callback — cleanup happens before returning `cell_done()`,
   in ordinary kaikai code.
4. **The pid is scoped to the body.** `with_cell` mirrors the
   shape of kaikai's `with_mailbox`: the cell's `Pid[Msg]` is
   handed to a body closure rather than returned as a free
   value. This is enforced by kaikai's region-brand walker —
   user code cannot return a `Pid[Msg]` until full
   `TyBranded` propagation lands upstream
   (`fibers-honesty-targets.md` §*Residual m8.x items*; the
   compiler's `fiber_producer_helpers` allow-list permits
   `fiber_spawn` / `spawn_actor` / `alloc_for_policy` only).
   When that gap closes, ahu can additionally expose a free
   `start_cell : (...) -> Pid[Msg] / Spawn + e` constructor;
   until then `with_cell` is the only cell entry point.

The unified-message-protocol pattern in the example (where the
driver and the cell share `CounterMsg` so `Actor[CounterMsg]`
covers both directions) is the canonical kaikai actor shape:
one `Actor[Msg]` effect can both send to and receive from any
pid of that Msg type. Cross-type request/reply via two separate
`Actor[A]` and `Actor[B]` effects is not expressible in current
kaikai (one mailbox per fiber; see `kaikai/docs/actors.md`
§*Open questions* #4). A `Cell.ask(pid, build_request)` helper
that opens an inner `with_mailbox` for the reply lands in
ahu-Anga Roa once the pattern recurs.

**Composing cells:** request/reply uses `with_mailbox` on the
caller side (kaikai pattern from `actors.md` §*with_mailbox*):

```kai
fn ask_counter(c: Pid[CounterMsg]) : Int / Spawn + Actor[Int] = {
  with_mailbox { m ->
    c.send(GetValue(m.self()))
    m.receive()
  }
}
```

No "synchronous call" abstraction in ahu's surface — request/reply
is a pattern, not a primitive. If usage data shows the pattern is
common enough to warrant a helper, `Cell.ask(pid, build_request)`
ships in Anga Roa.

### Layer 3 — Restart helpers

Crashes happen. Sometimes the right answer is "let the cell die
and restart it from scratch"; sometimes "let the parent decide";
sometimes "log and continue". ahu does not introduce a
`Supervisor` type for this. Instead, it provides three small
helpers that wrap a cell or fiber with restart policy. These
helpers compose with nurseries — a nursery + N children + N
restart wrappers **is** your supervision tree.

```kai
# In src/ahu/restart.kai (imported as `import ahu.restart`):
pub type RestartPolicy = Permanent | Transient | Temporary
pub type RestartLimit  = Limit(Int)               # intensity only in v1
pub type Outcome       = Completed | Escalated

pub fn with_restart[e](
  policy: RestartPolicy,
  limit:  RestartLimit,
  body:   (Pid[String]) -> Unit / Actor[String] + Link + e
) : Outcome / Actor[String] + Spawn + Link + Cancel + e
```

The implementation uses kaikai's trap-exit mechanism
(`docs/actors.md` §*Trap-exit semantics*): the supervisor
sets `fiber_set_trap_exit(true)`, spawns the body in a child
fiber that calls `Link.link(parent)`, and parks on
`Actor.receive()` to observe the termination as a `String`
message ("Normal" or "Crashed"). The policy decides whether
to spawn the body again or return.

On termination the supervisor consults the policy:

- `Permanent`: restart the body unconditionally.
- `Transient`: restart only on `"Crashed"`; on `"Normal"`, return
  `Completed`.
- `Temporary`: never restart; return `Completed`.

When the cumulative restart count reaches `intensity`, the
supervisor returns `Escalated` instead of looping again. A
parent that wants to react to escalation (e.g. another
`with_restart` watching the wrapper) inspects the returned
`Outcome` and re-raises as needed.

**Why escalation returns `Outcome.Escalated` instead of raising
`Cancel`:** the original sketch used `Cancel.raise()` so a
parent supervisor would observe escalation through its own
Link / trap-exit channel. In current kaikai, an outer
`handle { ... } with Cancel { raise(_) -> ... }` clause at the
caller site intercepts the *child*'s `Cancel.raise()` directly
(before trap-exit converts it), so the supervisor's restart
loop never gets to run. Returning `Outcome` avoids that
interaction entirely. Layered supervision still composes:
the outer `with_restart`'s body inspects the inner outcome
and re-raises by raising itself (e.g. via `Cancel.raise()` —
guarded by trap-exit at the *outer* layer, where there is no
intermediate Cancel handler). When kaikai's effect-handler
ordering vs trap-exit semantics is tightened upstream, this
escalation path may revert to direct propagation.

**`RestartLimit` v1 simplification.** Carries only `intensity`.
The OTP-style sliding-window `period` requires a `Clock` effect
for timestamp comparison; that arrives in a follow-up lane.

**`restartable_cell` deferred.** A combined Cell + restart
helper would require the supervised body to hold both
`Actor[String]` (for trap-exit) and `Actor[Msg]` (for the
cell mailbox) in the same fiber. Current kaikai allows two
`Actor` effects in the row at the type level but the runtime
pairs each fiber with exactly one mailbox, which produces a
runtime error or segfault when the second `Actor.send` lookup
hits the wrong handler. ahu-Tongariki ships `with_restart` as
the standalone restart primitive; users compose by spawning the
cell from inside a separate inner fiber that does not share
the supervisor's mailbox. A proper `restartable_cell` waits on
upstream support for two-mailbox fibers, or for a
multi-handler refactor of the trap-exit channel that does not
require a String mailbox specifically.

**A "supervision tree" using these primitives:**

```kai
fn boot_workers(queue: Pid[Job]) : Unit / Spawn + Db + Net = {
  nursery { n ->
    n.spawn { restartable_cell(Permanent, default_limit, () => job_worker(queue)) }
    n.spawn { restartable_cell(Permanent, default_limit, () => job_worker(queue)) }
    n.spawn { restartable_cell(Permanent, default_limit, () => job_worker(queue)) }
    n.spawn { restartable_cell(Transient, default_limit, () => metrics_collector()) }
  }
}
```

That nursery + four `restartable_cell` calls **is** the supervisor.
No separate `Supervisor` type, no `SupervisorSpec` record, no
`one_for_one` strategy enum. The four children are independent
(any one's crash cancels none of the others — restart is local to
its own wrapper). This is `one_for_one` semantics by default.

For `one_for_all` semantics (any child's crash cancels its
siblings), the user writes the same nursery without
`with_restart`: the nursery's own cancel-on-fail behaviour
(`docs/structured-concurrency.md` §*Cancellation*: *"A sibling
fiber in the same nursery crashes"*) provides exactly that
semantics. **No new primitive required.**

For `rest_for_one` (cancel children started after the failing
one), the user nests nurseries:

```kai
nursery { outer ->
  let a = outer.spawn { restartable_cell(Permanent, ..., worker_a) }
  nursery { inner ->                      # b and c live in here
    inner.spawn { restartable_cell(Permanent, ..., worker_b) }
    inner.spawn { restartable_cell(Permanent, ..., worker_c) }
  }
  # if outer crashes, the inner nursery is already closed
  # if inner crashes, b and c go down together; a survives
}
```

This is a powerful insight: **kaikai's lexical nursery scopes
already encode every supervision-strategy distinction OTP needs a
strategy enum for**. The strategy enum exists in OTP because
Erlang processes have no lexical scope. Kaikai has lexical scope.
The strategy is encoded by where the nursery boundary is drawn.

`simple_one_for_one` (dynamic worker pool) is just a nursery + a
loop spawning `restartable_cell` instances — no separate primitive.
ahu may ship a `pool(n, body)` helper if usage data motivates it,
but Tongariki does not.

## Decisions

The seven load-bearing decisions for ahu-Tongariki, each closed.

### Decision 1 — Cells, not Behaviors

A cell is `Msg → Cell[Msg] / e` — a recursive function over
messages, where the next iteration's function carries the next
state. Not a record of callbacks (the previous draft's choice),
not a protocol impl, not an effect handler.

Rationale:

- **Functional shape matches kaikai idiom.** State as recursion
  argument is how kaikai users already write `loop`-shaped code.
  No `var`, no internal mutation, no `terminate(state, reason)`
  callback that imposes a separate cleanup phase.
- **State transitions are explicit.** `counting(value)` →
  `counting(value + 1)` is a visible call; you can grep for what
  changes a cell's state. Compare to `state.value += 1` inside a
  `handle_cast` — implicit and harder to audit.
- **Behaviour switches are first-class.** A cell that goes from
  "active" to "paused" to "draining" returns a different cell
  function in each transition (`active(...)` → `paused(...)` →
  `draining(...)`). OTP's gen_server reaches for `become/3`
  hacks for this; Akka Typed adopted the recursive-function
  shape exactly because of this case. ahu inherits the
  improvement.
- **No `terminate` callback.** Cleanup is ordinary code before
  returning `done()`. There is no separate phase the framework
  runs. This eliminates the gen_server question of *"what runs
  if `terminate` itself crashes?"* — there is no `terminate`.
- **Records-of-callbacks (the previous draft) was correct under
  the OTP framing.** It composed well, kept effects visible,
  monomorphised cleanly. The pivot abandons it because the
  recursive-function shape composes equally well *and* is more
  faithful to kaikai's functional core. It is also a smaller
  surface — one type (`Cell[Msg]`), one constructor
  (`start_cell`), one terminator (`done()`).

### Decision 2 — Streams as Layer 1 (primary paradigm for data flow)

Streams ship as a first-class layer alongside cells, not as a
side-library. For request/response, ETL, and event broadcasting
(the bulk of what manutara will do), streams are structurally
better than actors.

Rationale:

- **Backpressure is the framework's problem, not the user's.**
  Streams handle demand signaling automatically; cells require
  manual `BlockSender` mailbox configuration and per-cell
  reasoning about flow.
- **Composition is algebraic.** `source |> flow1 |> flow2 |>
  sink` is type-checked end-to-end. Composing actors is ad-hoc
  message protocol design.
- **The web-framework path forces this anyway.** manutara's
  request lifecycle is a stream by structure: bytes → HTTP
  parse → route → handler → render → bytes-out. Phoenix bolted
  this on after the fact; ahu has it from the start.
- **Cells exist for what streams cannot model**: long-lived
  identity (sessions, websockets) and state that outlives a
  single message. Streams are stateless transformers; cells are
  the addressable, stateful complement.

### Decision 3 — Restart as helpers, not abstractions

ahu does not ship a `Supervisor` type, a `SupervisorSpec` record,
or a `Strategy` enum. Restart policy is a pair of helpers
(`with_restart`, `restartable_cell`); supervision strategies fall
out of where the user draws nursery boundaries.

Rationale:

- **OTP's `Strategy` enum compensates for Erlang's lack of
  lexical scope.** Kaikai has nurseries; the strategies the
  enum encodes (`one_for_one`, `one_for_all`, `rest_for_one`)
  are recoverable from nursery placement. See §*Layer 3* worked
  examples.
- **Smaller surface to learn.** A user who learns `nursery` and
  `with_restart` can build any supervision tree OTP can build.
  No second vocabulary for "but a special kind of process that
  watches other processes".
- **Composability.** A `Supervisor` type would have to be a
  `Cell` (long-lived, stateful) but its API would be different
  from regular cells (it has children, not messages). Skipping
  the type means there is one shape (cells) for every long-
  lived stateful thing.

### Decision 4 — No process registry in Tongariki, deferred to Anga Roa

Same as the OTP-style draft. `Pid[Msg]` is region-branded;
explicit handoff fits the type system. Per-nursery `Registry`
capability is the leading candidate for Anga Roa once usage
data exists.

Unchanged by the pivot — registry is a cross-cutting concern
that lives orthogonally to streams-vs-cells.

### Decision 5 — No hot code reload, ever

Same as the OTP-style draft. Kaikai compiles to native binaries
via LLVM; there is no module loader at runtime. Permanent
non-goal.

The pivot makes this even more cleanly true: cells have no
`code_change/3` callback to even consider. State migration
during deployment is a rolling-restart concern, not a framework
concern.

### Decision 6 — No distribution in Tongariki or Anga Roa

Same as the OTP-style draft. Cross-node Pids land in Orongo at
earliest.

The pivot does not change this. Distributed streams (cross-node
sources / sinks) and distributed cells (remote pids) are both
post-Orongo concerns; the design surface for either is wider than
ahu-Tongariki should absorb.

### Decision 7 — ahu-Tongariki MVP scope (revised)

**In scope for ahu-Tongariki:**

1. **Layer 1 — Streams.** `Source[T, e]`, `Flow[A, B, e]`,
   `Sink[T, R, e]`, the canonical combinators (`map`, `filter`,
   `flat_map`, `merge`, `throttle`, `buffer`), `from_list`,
   `from_listener`, `tick`, `foreach`, `fold`, `collect`.
   Demand-based backpressure with the kaikai `Overflow` enum
   for buffer policy.
2. **Layer 2 — Cells.** `Cell[Msg, e]`, `start_cell`,
   `done()`, `stop()` (graceful termination from the outside).
   The `receive { ... }` macro-free desugaring to
   `Actor.receive()` + `match`.
3. **Layer 3 — Restart helpers.** `RestartPolicy`,
   `RestartLimit`, `with_restart`, `restartable_cell`.
   Default limit `5 / 60s`.
4. **Bootstrap helper.** `run_app(root: () -> Unit / e) : Unit`
   installs `SIGINT` / `SIGTERM` handlers, opens a root
   nursery, runs `root` inside it, blocks on signal, propagates
   cancellation through the tree.
5. **Reference example.** `examples/echo/` — a tiny TCP echo
   server using `Source.from_listener` + `Flow.flat_map` to
   handle each connection inside a per-connection nursery.
   Shows: streams as the request layer, cells for connection
   state, restart wrapping the listener loop, `run_app` at the
   top.

**Out of scope for ahu-Tongariki:**

- Process registry (Anga Roa).
- Distribution (Orongo+).
- Hot reload (never).
- Specialised cell shapes (`Agent`, `Task`-equivalents). Cells
  cover them; specialisation waits for usage data.
- Pre-built `pool(n, body)` helper. Trivial to write with the
  primitives; ships only if pattern recurs in real ahu code.
- `Cell.ask(pid, msg)` synchronous-request helper. Ships in
  Anga Roa if request/reply pattern is common.
- DSL macros for cell or stream declaration. Kaikai has no
  macros.
- Pre-built telemetry hooks. Orongo, alongside kaikai's
  diagnostic JSON surface.

### Repository layout

Same shape as the OTP-style draft:

```
ahu/
  CLAUDE.md
  README.md
  VERSION
  CHANGELOG.md
  docs/
    design.md            # this document
    roadmap.md
    lane-experience-*.md
  src/
    stream.kai           # Layer 1
    cell.kai             # Layer 2
    restart.kai          # Layer 3
    app.kai              # bootstrap helper
  tests/
  examples/
    echo/                # reference: TCP echo server
```

## End-to-end MVP verification

The Tongariki MVP target is the TCP echo server: a user with
kaikai installed clones ahu, builds, tests, and runs the echo
example end-to-end. Concretely:

```sh
git clone github.com/lnds/ahu
cd ahu
KAI_HOME=../kaikai make tier1               # all fixtures green
kai run examples/echo/main.kai &            # echo server boots
echo "ping" | nc localhost 8080             # → "ping\n"
kill -INT $!                                # graceful shutdown
wait                                        # exit code 0
```

**Current status (2026-05-02):** the `make tier1` step works
today against the Layer 2 + Layer 3 fixtures (7 fixtures
pass). The `examples/echo` integration target is gated on
Layer 1 (streams) shipping — see *External dependencies* below
for the upstream `lnds/kaikai#106` blocker.

ahu-Tongariki is **fulfilled** when the full sequence above
runs to completion against an unmodified kaikai checkout.

## External dependencies on kaikai

### Closed (as of kaikai 0.35.x)

Five blockers from the original design have closed upstream:

1. **Blocking `Actor.receive()` on an empty mailbox.** Closed
   by kaikai m8.x runtime (landed v0.4.0; documentation
   alignment in v0.32.0 / Tongariki Wave 3, kaikai PR #73). A
   cell parked on `receive` now suspends via `swapcontext` and
   resumes when a message arrives.
2. **`BlockSender` mailbox policy delivery.** Same kaikai m8.x
   work. All four mailbox policies (`Unbounded`, `Bounded(c,
   DropOldest|DropNewest|BlockSender)`) reach the runtime in
   v0.32.0. Senders park on the per-mailbox `send_waiter`
   chain when full and resume when receivers pop a slot.
3. **Region-brand for `Pid[Msg]` flowing through sum-type
   payloads.** Closed by kaikai PR #74 / issue #71 option (a)
   in v0.34.0 — the deep `TyBranded` walker now correctly
   detects sum-payload escape and admits the legitimate
   ahu/stdlib patterns.
4. **`core.list` higher-order helpers.** Closed by
   `lnds/kaikai#106` / PR #113 in 0.35.x. `core.list.map` /
   `filter` / `foldl` / `foldr` / `foreach` / `length` /
   `reverse` / `zip` / `unzip` all ship with row-poly
   callbacks. Layer 1's pipeline shape ships against this
   without ahu adding a stream module — see §Layer 1.
5. **NetTcp v1.** Shipped in kaikai v0.33.0
   (`stdlib/net/tcp.kai`). Once lazy stream sources land
   post-Tongariki, `Source.from_listener(port)` will wrap the
   `NetTcp` ops directly.

### Open (filed as upstream issues)

Three concrete gaps remain open. Each is filed as a
`lnds/kaikai` issue with a self-contained reproducer; ahu
either ships a documented workaround or pauses the affected
lane.

1. **`lnds/kaikai#107` — missing `Signal` effect for graceful
   shutdown.** Kaikai's runtime installs a `SIGSEGV` handler
   internally for fiber-stack overflow detection but does
   not expose user-level signal trapping. **Blocks `run_app`
   bootstrap.** Without `Signal.on_cancel(SigInt)` or
   equivalent, `run_app(root)` reduces to a 1-line wrapper
   around `nursery` and ships no meaningful value beyond
   what users can write inline. The TCP echo example
   (Tongariki MVP target) needs Ctrl-C → graceful drain →
   exit 0; that path requires the upstream effect.

3. **`lnds/kaikai#104` — segfault: nested mailbox + trap-exit
   + `spawn_actor` inside.** A specific composition (a fiber
   spawned under `fiber_set_trap_exit(true)`, with a
   `with_mailbox` of one Msg type and a nested `with_mailbox`
   of a different Msg type, and `spawn_actor` called inside
   the nested scope) crashes the runtime. **Blocks
   `restartable_cell`** — the natural Cell + restart
   combined helper needs exactly this pattern. ahu-Tongariki
   ships `with_cell` and `with_restart` as standalone
   primitives; users who want both compose by spawning
   across separate fibers manually. `restartable_cell`
   lands once the upstream gap closes.

4. **`lnds/kaikai#103` — trap-exit bypassed by outer Cancel
   handler.** When a parent fiber sets `fiber_set_trap_exit(true)`
   but the call site that invokes the spawn-and-receive cycle
   is wrapped in `handle { ... } with Cancel { raise(_) -> ...
   }`, the outer Cancel handler intercepts the child's
   `Cancel.raise()` directly — before trap-exit can convert
   it into `"Crashed"`. **Blocks layered supervision via
   `Cancel.raise()`.** ahu-Tongariki's `with_restart` returns
   `Outcome.Escalated` instead of raising `Cancel`, sidestepping
   the interaction. Layered supervision still composes by
   inspecting the inner outcome and re-raising at a layer
   without an intermediate Cancel handler. The Cancel-based
   escalation path may revert to direct propagation once the
   upstream semantics is tightened.

### Open (watch items, not confirmed gaps)

Two items the implementation passes did NOT exercise but the
design depends on. Verification arrives during the streams
implementation lane:

1. **Free `start_cell : ... -> Pid[Msg]` constructor.** Kaikai's
   region-brand walker today consults a hardcoded allow-list
   (`fiber_producer_helpers` in
   `kaikai/stage2/compiler.kai`: `fiber_spawn`,
   `spawn_actor`, `alloc_for_policy`) for which functions may
   return `Pid[Msg]` / `Fiber[T]`. User-code helpers — including
   ahu's — are rejected. ahu-Tongariki ships `with_cell(initial,
   step, body)` as the canonical entry point (mirroring
   `with_mailbox`'s shape); a free `start_cell` form is added
   once full `TyBranded(Ty, BrandId)` propagation lands
   upstream (`docs/fibers-honesty-targets.md` §*Residual m8.x
   items*). Not yet filed as a concrete issue — the right
   shape needs a concrete proposal.
2. **Structured `with_cell` shutdown.** When `body` returns,
   the cell's fiber is still alive — the kaikai `nursery`
   helper is currently a typed pass-through
   (`stdlib/spawn.kai`: *"the nursery body itself does not
   yet implement the structured cancel-on-fail-and-rethrow
   semantics"*). ahu's `with_cell` therefore lets the cell
   outlive the body in v1; any final messages (e.g. a `Stop`
   sent right before the body returns) may not be processed
   before `main` exits. The `examples/counter/main.out.expected`
   reflects this honestly. Closes when the kaikai nursery
   wraps `Spawn` and observes child terminations through
   `Link`.

The design lane does not patch any of these — gaps are surfaced
as kaikai issues coordinated separately.

## Not goals

- **OTP duplication.** ahu is not a port of `gen_server`,
  supervisors, or applications. The patterns are reshaped to
  kaikai's primitives, not transliterated.
- **Hot code reload.** Permanent non-goal. See Decision 5.
- **Cross-node distribution in Tongariki / Anga Roa.** See
  Decision 6.
- **Process registry in Tongariki.** Anga Roa. See Decision 4.
- **DSL macros.** Kaikai has no macros.
- **Phoenix-LiveView clone.** That is manutara's surface, not
  ahu's. ahu provides the substrate (streams + cells + restart);
  manutara picks how to expose them to view authors.
- **Specialised cell shapes** (`Agent` for value containers,
  `Task` for one-shot computations). Cells are the one shape;
  specialisations come post-Tongariki only if usage data shows
  the recursive-function form gets in the way.
- **A `Supervisor` type.** Replaced by nurseries + restart
  helpers. See Decision 3.

## Roadmap pointer

The full ahu milestone series — Tongariki / Anga Roa / Orongo /
Anakena — lives in `docs/roadmap.md` of this repository. Each
milestone has scope, definition-of-done, and sequencing
constraints against kaikai milestones.

## References

- `kaikai/docs/design.md`, `kaikai/docs/actors.md`,
  `kaikai/docs/structured-concurrency.md`,
  `kaikai/docs/effects.md`, `kaikai/docs/effects-stdlib.md`,
  `kaikai/docs/protocols.md`, `kaikai/docs/roadmap.md`,
  `kaikai/stdlib/actor.kai`, `kaikai/stdlib/spawn.kai`,
  `kaikai/CLAUDE.md` — the upstream substrate.
- Akka Typed
  (`https://doc.akka.io/docs/akka/current/typed/index.html`) —
  primary lineage for the `Cell[Msg]` shape (Akka Typed's
  `Behavior[T]`).
- Reactive Streams specification
  (`https://www.reactive-streams.org/`) — demand-based
  backpressure model for Layer 1.
- Akka Streams documentation — prior art for stream
  combinators.
- Trio (`https://trio.readthedocs.io/`), Kotlin
  `coroutineScope`, OCaml 5 Eio — structured concurrency
  ancestors that kaikai's nursery model already adopts;
  relevant here as the reason ahu does not need an OTP
  `Supervisor` type.
- Erlang/OTP design principles — the prior art ahu
  deliberately diverges from in shape while inheriting the
  patterns OTP got right.
- Joe Armstrong, *Making reliable distributed systems in the
  presence of software errors* (2003) — the OTP rationale
  document, useful for understanding what stays vs what goes.
