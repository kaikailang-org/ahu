# ahu design

Living document for the kaikai-native concurrency and fault-tolerance
framework that runs underneath manutara and friends.

> **Status:** Layers 2 and 3 (cells, restart helpers,
> `restartable_cell`), Layer 1 (streams as
> convention-over-stdlib), and the `run_app` bootstrap are
> shipped. The integration examples — `examples/echo/`
> (TCP echo), `examples/resilient_counter/` (restart fault
> tolerance), `examples/pipeline/` (Layer 1 ETL) and
> `examples/counter/` (request/reply cell) — all live in the
> repository. Component-by-component state is tracked in
> `docs/roadmap.md`; ahu has no milestones.
>
> `with_restart` uses `Cancel.raise()` for escalation;
> `restartable_cell` boots a cell under restart supervision
> with state-reset semantics; `run_app` is a v1 placeholder
> until kaikai's reactor lands the Signal-based
> graceful-shutdown integration.
>
> Open upstream issues that affect ahu against the current
> kaikai release are tracked in `docs/known-regressions.md`.
> At time of writing, `spawn_actor` (kaikai#570) regressed
> in kaikai 0.56.x and that puts tier1 (run-and-diff) in red;
> tier0 (compile-only) remains green at 13 fixtures.
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

ahu is the second layer of the lnds ecosystem:

```
kaikai      (the language)
   ↓
ahu         (this project — concurrency and fault-tolerance layer)
   ↓
kohau       (database / persistence)
   ↓
henua       (DDD building blocks)
   ↓
   ├──▶ manutara    (web framework, LiveView-shaped)
   └──▶ hopu        (background jobs / queue / scheduler)
```

`manutara` and `hopu` are sibling consumers of the lower stack:
`manutara` handles the synchronous request-response face (web), and
`hopu` handles the asynchronous job face (background workers,
persistent queues, periodic scheduling — the analog of Oban /
Sidekiq / Celery). Neither depends on the other.

Names follow the Rapa Nui vocabulary established by `kaikai` and
`ahu`. `kohau` is the inscribed wooden tablet that carried the
rongorongo script — the substrate metaphor maps cleanly to a
persistence layer. `henua` means *land / territory / domain* — the
DDD-vocabulary mapping is direct. `manutara` is the migratory bird
whose arrival opened the Tangata Manu rite; `hopu` is the swimmer-
messenger who crossed to Motu Nui to retrieve the manutara's egg —
the functional parallel: the framework that fetches and executes a
delegated task in background. Naming rationale lives in
`kaikai-docs/framework-naming.md`.

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

**ahu ships no stream-layer code for the eager pipeline shape.**
The combinators all live in kaikai's stdlib + language syntax;
ahu's contribution at this layer is the canonical pipeline
pattern plus a fixture demonstrating it with effectful
callbacks.

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
`|>` end-to-end. Neither is currently available. The TCP echo
example therefore uses an explicit nursery + per-connection
cell (Layer 2) + restart wrapper (Layer 3) loop instead of a
streamed source — see §End-to-end verification.

**Why ahu does not re-export `list.*` under `stream.*`:**

The stdlib spelling stays canonical. Aliasing
`stream.map` ≡ `list.map` would force users to remember which
prefix ahu prefers without adding any expressive power.
Convention is the cheaper fix: ahu code uses `list.*` directly
plus the `[..]` / `|` / `|>` syntax. When lazy sources land,
they get their own ahu module (`ahu/source.kai` or similar) —
new surface, not aliases.

### Layer 2 — Cells

A cell is a long-running stateful entity with a typed mailbox.
The user writes a **step function** `(State, Msg) -> StepResult[State] / e`
and ahu runs it inside a fiber that parks on `Actor.receive()`
between iterations. State threads through the recursion (no
internal mutation); behaviour switches are encoded as a sum
type for State (Active → Paused → Draining as variants).

```kai
# In ahu/cell.kai (imported as `import ahu.cell`):
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
§*Open questions* #4). A `cell.ask(pid, build_request)` helper
that opens an inner `with_mailbox` for the reply can land
once the pattern recurs in real code — see `docs/roadmap.md`
§*Layer 2 — Cells*.

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
common enough to warrant a helper, a `cell.ask(pid, build_request)`
function can be added — see `docs/roadmap.md` §*Layer 2 — Cells*.

### Layer 3 — Restart helpers

Crashes happen. Sometimes the right answer is "let the cell die
and restart it from scratch"; sometimes "let the parent decide";
sometimes "log and continue". ahu does not introduce a
`Supervisor` type for this. Instead, it provides three small
helpers that wrap a cell or fiber with restart policy. These
helpers compose with nurseries — a nursery + N children + N
restart wrappers **is** your supervision tree.

```kai
# In ahu/restart.kai (imported as `import ahu.restart`):
pub type RestartPolicy = Permanent | Transient | Temporary
pub type RestartLimit  = Limit(Int)               # intensity only in v1

pub fn with_restart[e](
  policy: RestartPolicy,
  limit:  RestartLimit,
  body:   (Pid[String]) -> Unit / Actor[String] + Link + e
) : Unit / Actor[String] + Spawn + Link + Cancel + e
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
- `Transient`: restart only on `"Crashed"`; on `"Normal"`,
  return Unit cleanly.
- `Temporary`: never restart; return Unit cleanly.

When the cumulative restart count reaches `intensity`, the
supervisor calls `Cancel.raise()`. The kaikai runtime
(post-`lnds/kaikai#103` / PR #122) converts trap-exit'd child
`Cancel.raise()` to `"Crashed"` *before* any user-level Cancel
handler can intercept, so layered supervision composes
through the standard Cancel/Link channel: a parent supervisor
watching `with_restart` observes escalation as a `"Crashed"`
message in its own mailbox, exactly like any other child
crash.

Callers who want explicit (non-Cancel) observability of
escalation wrap the call in their own Cancel handler:

```kai
handle {
  restart.with_restart(Permanent, restart.default_limit(), body)
} with Cancel {
  raise(resume) -> Stdout.print("supervisor: escalated")
}
```

That handler only catches the supervisor's own `Cancel.raise()`
at the escalation site — never the child's, which trap-exit
converts at the runtime boundary.

**`RestartLimit` v1 simplification.** Carries only `intensity`.
The OTP-style sliding-window `period` requires a `Clock` effect
for timestamp comparison; that arrives in a follow-up lane.

**`restartable_cell`** ships alongside `with_restart` — the
combined helper that boots a cell under restart supervision
and runs a user's driver against it:

```kai
pub fn restartable_cell[State, Msg, e](
  policy:  RestartPolicy,
  limit:   RestartLimit,
  initial: State,
  step:    (State, Msg) -> StepResult[State] / Actor[Msg] + e,
  driver:  (Pid[Msg]) -> Unit / Actor[Msg] + e
) : Unit / Actor[String] + Spawn + Link + Cancel + e
```

Each restart re-spawns BOTH the supervised body AND a fresh
cell — state resets to `initial`, the previous cell pid is
discarded. The composition is:

1. `with_restart` spawns a body fiber, links it back to the
   supervisor, installs trap-exit on the supervisor.
2. The body fiber installs a nested `with_mailbox` of `Msg`
   type — the inner mailbox the cell will read from.
3. Inside that inner scope, `cell.with_cell(initial, step,
   driver)` spawns the cell as its own fiber and runs the
   user's `driver(pid)` in the body fiber.
4. When `driver` returns, the body fiber returns Unit;
   trap-exit fires `"Normal"` / `"Crashed"` on the
   supervisor's mailbox. Restart policy applies as usual.

Pre-`lnds/kaikai#104` (closed in 0.36.x), step 2 → step 3
crashed the runtime: a fiber that was trap-exit'd by its
parent and held a nested mailbox of a different `Msg` type
segfaulted on the inner `spawn_actor`. With #104 closed,
this composition works cleanly. Verified end-to-end by
`tests/cross_restartable_cell.kai` (Transient + Normal exit
→ supervisor returns) and
`tests/cross_restartable_cell_restart.kai` (Permanent + body
crashes → 2 cycles + escalation, state resets between
restarts).

**v1 limitation:** the cell crashing mid-driver is NOT
observed by the supervised body. The body's most-recently-
allocated mailbox is `Msg` (not `String`), so a cell-link
trap-exit message would corrupt the typing. Cell crashes
therefore go silent from the supervisor's perspective; the
driver may discover the dead cell through stalled receives
or via its own protocol-level liveness checks. Cell-level
crash observation (linked cell with separate-channel exit
notification) is a follow-up once kaikai exposes typed
trap-exit channels.

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
ahu may ship a `pool(n, body)` helper if usage data motivates it
— see `docs/roadmap.md` §*Pool helper*.

## Decisions

The seven load-bearing decisions for ahu, each closed.

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

### Decision 4 — No process registry by default

Same as the OTP-style draft. `Pid[Msg]` is region-branded;
explicit handoff fits the type system. A per-nursery
`Registry` capability is the leading candidate when real-world
usage shows the need — see `docs/roadmap.md` §*Process
registry*.

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

### Decision 6 — No distribution in the current scope

Same as the OTP-style draft. Cross-node Pids are far-future
work tracked in `docs/roadmap.md` §*Distribution*; the design
surface for distributed streams (cross-node sources / sinks)
and distributed cells (remote pids) is wider than the current
local-only scope should absorb.

The pivot does not change this.

### Decision 7 — surface and scope

**In scope:**

1. **Layer 1 — Streams.** The canonical pipeline shape over
   kaikai's stdlib + language sugars (`[a..b]`, `|`, `|>`,
   `list.map` / `filter` / `foldl` with row-poly callbacks).
   No `ahu/stream.kai` for eager pipelines — convention over
   aliases.
2. **Layer 2 — Cells.** `StepResult[State]`, `keep`,
   `cell_done`, `with_cell`. The recursive step-function shape:
   `(State, Msg) -> StepResult[State] / e`. The
   `receive { ... }` form desugars to `Actor.receive()` +
   `match`.
3. **Layer 3 — Restart helpers.** `RestartPolicy`,
   `RestartLimit`, `with_restart`, `restartable_cell`.
   Default limit `5 / 60s`.
4. **Bootstrap helper.** `app.run_app(root)` (in
   `ahu/app.kai`, imported as `import ahu.app`). v1 placeholder;
   the planned shape subscribes to `SIGINT` / `SIGTERM` via the
   kaikai `Signal` effect, spawns `root` as a child fiber,
   parks on `Signal.await()` until either signal fires, then
   cancels the root fiber so its `Cancel` handlers run before
   the process exits. Type signature when shipped:
   ```kai
   pub fn run_app[e](root: () -> Unit / Cancel + e)
     : Unit / Spawn + Signal + Cancel + Console + e
   ```
   The v1 implementation just runs `root` directly. Signal
   integration follows when kaikai's reactor lands.
5. **Reference example.** `examples/echo/` — a TCP echo server
   showing all three layers together: streams as the request
   layer (eager today), cells for connection state, restart
   wrapping the listener loop, `run_app` at the top.

**Out of scope (see `docs/roadmap.md` for status of each):**

- Process registry. Held back until usage data exists.
- Distribution. Far-future.
- Hot reload. Permanent non-goal.
- Specialised cell shapes (`Agent`, `Task`-equivalents). Cells
  cover them; specialisation waits for usage data.
- Pre-built `pool(n, body)` helper. Trivial to write with the
  primitives; ships only if pattern recurs in real ahu code.
- `cell.ask(pid, msg)` synchronous-request helper. Adds when
  the request/reply pattern becomes common.
- DSL macros for cell or stream declaration. Kaikai has no
  macros.
- Pre-built telemetry hooks. Tracked in the diagnostics
  component.

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
  kai.toml               # package manifest (name = "ahu")
  ahu/                   # module root — `import ahu.X`
    stream.kai           # Layer 1
    cell.kai             # Layer 2
    restart.kai          # Layer 3
    app.kai              # bootstrap helper
  tests/
  examples/
    echo/                # reference: TCP echo server
```

## End-to-end verification

The TCP echo server is the integration target — a user with
kaikai installed clones ahu, builds, tests, and runs the echo
example end-to-end. Concretely:

```sh
git clone github.com/kaikailang-org/ahu
cd ahu
make tier1                                  # all fixtures green
kai run examples/echo/main.kai &            # echo server boots
echo "ping" | nc localhost 8080             # → "ping\n"
kill -INT $!                                # graceful shutdown
wait                                        # exit code 0
```

**Current status:** tier0 (compile-only) is green at 13 fixtures
against kaikai 0.56.x. tier1 (run-and-diff) is currently red
because of a runtime regression in `spawn_actor` upstream
(`kaikai#570`). See `docs/known-regressions.md` for the open
upstream issues.

## External dependencies on kaikai

### Closed (as of kaikai 0.36.x)

All blockers from the original design have closed upstream:

1. **Blocking `Actor.receive()` on an empty mailbox.** Closed
   by kaikai's m8.x runtime (landed v0.4.0; documentation
   alignment in v0.32.0, kaikai PR #73). A cell parked on
   `receive` now suspends via `swapcontext` and resumes when a
   message arrives.
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
   (`stdlib/net/tcp.kai`). Once lazy stream sources land,
   `Source.from_listener(port)` will wrap the `NetTcp` ops
   directly — see `docs/roadmap.md` §*Layer 1 — Streams*.
6. **trap-exit beats outer Cancel handler.** Closed by kaikai
   PR #122 / `lnds/kaikai#103` in 0.36.0 — the runtime now
   converts a trap-exit'd child's `Cancel.raise()` to
   `"Crashed"` *before* any user-level Cancel handler can
   intercept. ahu's `with_restart` reverted from the
   `Outcome` workaround to BEAM-faithful `Cancel.raise()`
   for escalation; layered supervision composes through the
   standard Link/trap-exit channel.
7. **Nested mailbox + trap-exit + `spawn_actor` segfault.**
   Closed by `lnds/kaikai#104`. The runtime bookkeeping for
   `mailbox_assign_owner` under nested `with_mailbox` scopes
   while a fiber is trap-exit'd no longer crashes. Unblocked
   `restartable_cell` (combined Layer 2 + Layer 3 helper).
8. **`Signal` effect for graceful shutdown.** Closed by
   `lnds/kaikai#107` / PR #116 in 0.36.x — `Signal.on(sig)`
   subscribes to `SigInt` / `SigTerm` / etc., `Signal.await()`
   parks until any subscribed signal fires. Will unblock the
   full `run_app` bootstrap once integrated.

### Newly available

Features that landed upstream more recently. These do not
retrofit existing components; they enable potential follow-up
work tracked in `docs/roadmap.md`:

1. **`stdlib/fs/file` v1.** `fs.file.read_file`,
   `fs.file.write_file`, `fs.file.append`. Tier S1 #1 of
   `kaikai/docs/stdlib-roadmap.md`, motivated explicitly by ahu
   (logging, supervisor checkpoints). `fs.dir.*` and `fs.path.*`
   are doc-only stubs pending runtime primitives + the m14
   module rename. **Unlocks**: `ahu.log` structured logging,
   any future cell that persists snapshot state.
2. **`stdlib/os/env` + `os/args`.** `env.get(name) :
   Option[String]`, `args.argv() : [String]`. Partial Tier S1 #2
   — `set_var` / `unset_var` / `vars` and `argv[0]` are blocked
   by `lnds/kaikai#127`; the entire `Process` family is blocked
   by `lnds/kaikai#126`. **Unlocks**: `run_app` config loader
   (read `PORT` / `AHU_LOG_LEVEL` etc. on startup, OTP analogue
   of `:application.get_env/2`).
3. **`Clock` default handler in `stdlib/time.kai`.**
   `time.now()` / `time.monotonic()` / `time.sleep(d)` work
   without the caller installing a handler. **Unlocks**:
   `with_restart` with backoff (sleep between retries).
   The OS-thread-blocking cliff that was open at first
   landing has since closed: kaikai's R1 reactor (file +
   sleep + process) parks the fiber on `Clock.sleep`
   instead of the OS thread, so other fibers under the
   same scheduler keep running during a backoff.
4. **`m[k]` indexing sugar + `Map[K, V]` AVL carrier.**
   `e1[e2]` over `Map[K, V]` lowers to `map_get(e1, e2) :
   Option[V]`; lookup/insert/remove are now O(log n). The
   kaikai changelog calls this out explicitly: *"Closes the
   unblock for ahu's Registry primitive"*. **Unlocks**: the
   per-nursery `Registry` capability (Decision 4) no longer
   has to wait on a better map carrier.
5. **Multi-arg `match` sugar.** `match a, b { p1, p2 -> body
   | ... }` for 2 ≤ N ≤ 4. **Impact**: stylistic — cell `step`
   functions and Layer 1 stream combinators that match on
   `(state, msg)` pairs can drop the synthetic tuple wrapper.
   No API change.
6. **LLVM backend Phase 2 unbox mirror (kaikai #87).**
   `--emit=llvm` now emits raw `i64` / `double` for hot
   numeric loops, matching the C backend's Tier 2.5 unbox. Was
   IR-shape-correct before but boxed every value. **Impact**:
   counter / accumulator cells with primitive payloads benefit
   transparently when ahu compiles via `--emit=llvm`; relevant
   for any future benchmarking work and load-bearing for a
   future multi-thread scheduler integration.
7. **Mailbox helper RC discipline (kaikai #82 audit).**
   `mailbox_send` / `_recv` / `_alloc_bounded` /
   `_assign_owner` / `_free` now decref correctly under
   Perceus. Pre-fix `mailbox_send` leaked one ref per call.
   **Impact**: long-running cells under high message volume
   no longer accumulate refcount leaks. The Tier 1 #2
   ("runtime-efficient") footnote in `docs/roadmap.md` moves
   closer to holding without asterisks.
8. **Union types (kaikai #187).** `type T = A | B | C` now
   means union of types, not only nominal sum. Components can
   be pre-existing types (records, sums, primitives, other
   unions) or auto-declared at first mention. Implicit upcast
   `T <: U` (one step) and `bind : Type` narrowing patterns
   shipped together. **No retrofit needed in shipped
   components**: the three sum types ahu already exposes
   (`RestartPolicy`, `RestartLimit`, `StepResult`) parse and
   behave unchanged under the unified model — kaikai's release
   explicitly confirms *"every `type T = A | B | ...` in
   stdlib worked unmodified through all five phases"*.
   **Unlocks**: composing cell mailbox types out of per-feature
   message types without wrapper sums (e.g.
   `type CombinedMsg = CounterMsg | LoggingMsg | AdminMsg`
   with `bind : Type` arms delegating to per-layer handlers);
   composing pipeline error types out of per-stage errors for
   `Flow.recover_with`; composing `Registry` errors
   (`LookupError | RegisterError`); composing telemetry
   events (`CellEvent | StreamEvent`) for a future
   `Telemetry` effect. The motivating use case in the kaikai
   doc — DDD bounded-context error composition — maps
   directly onto ahu's per-layer error story.

### Open watch items (not confirmed gaps)

Items the implementation passes did NOT exercise but the
design depends on. Verification arrives whenever a lane lands
that touches the relevant component:

1. **Free `start_cell : ... -> Pid[Msg]` constructor.** Kaikai's
   region-brand walker today consults a hardcoded allow-list
   (`fiber_producer_helpers` in
   `kaikai/stage2/compiler.kai`: `fiber_spawn`,
   `spawn_actor`, `alloc_for_policy`) for which functions may
   return `Pid[Msg]` / `Fiber[T]`. User-code helpers — including
   ahu's — are rejected. ahu ships `with_cell(initial, step,
   body)` as the canonical entry point (mirroring
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
3. **OS-thread-blocking primitives under v1 scheduler.**
   *Closed.* The reactor shipped in three phases — R1
   (file + sleep + process), R2 (TCP sockets), R3 (stdin)
   — and now parks the fiber rather than the OS thread on
   `Clock.sleep`, `Signal.await`, blocking file I/O, and
   the six `NetTcp` ops. `with_restart_backoff` already
   exercises this: the example fixture interleaves with
   other fibers during the backoff window. ahu's `run_app`
   stays pass-through pending its own Signal-multiplex
   upgrade — the constraint is no longer the scheduler,
   it is that the upgrade has not been written.
4. **Unified `ChildOutcome[E]` over Link/trap-exit + typed
   error result.** Today a parent observes a child through
   two distinct channels: `"Normal"` / `"Crashed"` strings
   delivered to a trap-exit'd parent's mailbox (runtime
   contract from Link), and any `Result[E, T]` the child
   chose to return on the normal path. Now that union types
   ship (kaikai #187), a unified shape is expressible:
   `type ChildOutcome[E] = Normal | Crashed | Errored(E)`,
   with `bind : Type` arms delegating per case. Whether to
   adopt this for a future supervisor helper, or keep the
   two-channel split that mirrors BEAM, is a decision to take
   with usage data — not pre-emptively. Filed as a watch item,
   not a commitment.

The design lane does not patch any of these — gaps are surfaced
as kaikai issues coordinated separately.

## Not goals

- **OTP duplication.** ahu is not a port of `gen_server`,
  supervisors, or applications. The patterns are reshaped to
  kaikai's primitives, not transliterated.
- **Hot code reload.** Permanent non-goal. See Decision 5.
- **Cross-node distribution in the current scope.** See
  Decision 6.
- **Process registry by default.** See Decision 4.
- **DSL macros.** Kaikai has no macros.
- **Phoenix-LiveView clone.** That is manutara's surface, not
  ahu's. ahu provides the substrate (streams + cells + restart);
  manutara picks how to expose them to view authors.
- **Specialised cell shapes** (`Agent` for value containers,
  `Task` for one-shot computations). Cells are the one shape;
  specialisations only land if usage data shows the
  recursive-function form gets in the way.
- **A `Supervisor` type.** Replaced by nurseries + restart
  helpers. See Decision 3.

## Roadmap pointer

ahu's component-level state lives in `docs/roadmap.md` of this
repository — one section per component (cells, restart,
streams, registry, distribution, logging, config, diagnostics)
with state, possible follow-ups, and upstream dependencies.
There are no milestones, no definitions-of-done, no calendar.

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
