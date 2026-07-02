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
> with state-reset semantics; `run_app` spawns root in a
> nursery and traps `SIGINT`/`SIGTERM` for graceful shutdown.
>
> Open upstream issues that affect ahu against the current
> kaikai release are tracked in `docs/known-regressions.md`.
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

ahu builds on these kaikai primitives:

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
│   kaikai stdlib `stream` (Stream[t, e]) + | |> || |? sugars  │
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

**ahu ships no stream-layer code — neither for eager pipelines
nor for lazy streams.** Both live upstream: eager pipelines are
kaikai's `core.list` helpers plus the `[a..b]` / `|` / `|>`
sugars; the lazy stream is kaikai's stdlib `stream` module
(`Stream[t, e]`), imported as
`import stream`. ahu's contribution at this layer is the
canonical pipeline pattern plus fixtures demonstrating both
shapes with effectful callbacks (`tests/stream_pipeline.kai` for
the eager shape, `tests/stream_lazy.kai` for the stdlib stream).

The building blocks for the eager pipeline are:

| Piece | Where it lives |
|---|---|
| `[a..b]` range list literal | kaikai language sugar |
| `\|` map-pipe (`xs \| f` ≡ `list.map(xs, f)`) | kaikai language sugar |
| `\|>` apply-pipe | kaikai language |
| `list.map`, `list.filter`, `list.foldl`, `list.foldr`, `list.foreach`, `list.length`, `list.reverse`, `list.zip`, `list.unzip` | kaikai stdlib `core.list` |

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

The stdlib `stream` carries the general lazy shape `Stream[t, e]`
(a push-carrier recipe) with `from_list` / `read_lines` sources,
`map` / `flat_map` / `filter` / `take` / `take_while` stages, and
`fold` / `each` / `count` / `to_list` / `write_lines` sinks. The
stages match the canonical pipe signatures, so `|` / `||` / `|?`
dispatch on `Stream` by convention. ahu consumes this directly.

**What this Layer is NOT (yet):**

Specific lazy / unbounded sources are still missing upstream:

- `from_listener(port: Int)` — TCP listener that yields
  connections indefinitely.
- `tick(every: Duration)` — periodic timer.
- `from_websocket(ws)` — stream of incoming frames.

The carrier exists; what is missing is each source's
event-driven integration with the reactor (a `read_lines`-style
producer for sockets and timers). Until those land in the stdlib
`stream` module, the TCP echo example uses an explicit nursery +
per-connection cell (Layer 2) + restart wrapper (Layer 3) loop
instead of a streamed source — see §End-to-end verification.
These are upstream gaps, tracked in §External dependencies on
kaikai; ahu does not ship its own source module to fill them.

**Why ahu does not re-export the stdlib under `stream.*`:**

The stdlib spelling stays canonical. ahu neither aliases
`list.*` nor wraps the stdlib `stream` module behind its own
prefix — that would force users to remember which prefix ahu
prefers without adding any expressive power. ahu code uses
`list.*` plus the `[..]` / `|` / `|>` syntax for eager pipelines
and `import stream` directly for lazy streams. When the lazy
sources above land, they land in the stdlib `stream` module, not
in a new ahu module.

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
   user code cannot return a `Pid[Msg]` until wider `TyBranded`
   propagation lands upstream (the compiler's fiber-producer
   allow-list admits only a fixed set of helpers). When that gap
   closes, ahu can additionally expose a free
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
supervisor calls `Cancel.raise()`. The kaikai runtime converts a
trap-exit'd child's `Cancel.raise()` to `"Crashed"` *before* any
user-level Cancel handler can intercept, so layered supervision
composes
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

**`RestartLimit` simplification.** Carries only `intensity`. The
OTP-style sliding-window `period` requires a `Clock` effect for
timestamp comparison; that is a follow-up.

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

A fiber that is trap-exit'd by its parent and holds a nested
mailbox of a different `Msg` type may call `spawn_actor` inside
that scope — the composition works cleanly. Verified end-to-end by
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

Streams are a first-class layer alongside cells, treated as the
primary paradigm for data flow rather than a side concern. The
stream carrier itself lives in the kaikai stdlib (`stream`) — ahu
does not ship a competing implementation — but ahu's
design elevates it to Layer 1: the canonical shape for data flow,
documented and exercised here. For request/response, ETL, and
event broadcasting (the bulk of what manutara will do), streams
are structurally better than actors.

This is a revision of the original draft, which planned an
ahu-owned stream module (`ahu/stream.kai`, `Source`/`Flow`/`Sink`
shapes). When the stdlib grew its own `stream` (push-carrier
recipe with the canonical pipe signatures), that module became a
duplicate and was removed: re-implementing a stdlib primitive
violates ahu's "do not re-design kaikai primitives" rule, and the
stdlib carrier already composes through the pipes end-to-end. ahu
keeps the *decision* (streams are Layer 1) and drops the *code*.

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

1. **Layer 1 — Streams.** The canonical pipeline shapes over
   kaikai's stdlib + language sugars: the eager shape (`[a..b]`,
   `|`, `|>`, `list.map` / `filter` / `foldl` with row-poly
   callbacks) and the lazy shape (stdlib `stream`, `Stream[t, e]`,
   `import stream`). No `ahu/stream.kai` at all — convention and
   direct stdlib use over aliases or a re-implementation.
2. **Layer 2 — Cells.** `StepResult[State]`, `keep`,
   `cell_done`, `with_cell`. The recursive step-function shape:
   `(State, Msg) -> StepResult[State] / e`. The
   `receive { ... }` form desugars to `Actor.receive()` +
   `match`.
3. **Layer 3 — Restart helpers.** `RestartPolicy`,
   `RestartLimit`, `with_restart`, `restartable_cell`.
   Default limit `5 / 60s`.
4. **Bootstrap helper.** `app.run_app(root)` (in
   `ahu/app.kai`, imported as `import ahu.app`). It subscribes to
   `SIGINT` / `SIGTERM` via the kaikai `Signal` effect, spawns
   `root` as a child fiber in a nursery alongside a signal-waiter,
   and on either signal cancels the root fiber so its `Cancel`
   handlers run before the process exits. On natural root exit the
   signal-waiter is cancelled so the nursery joins it and returns.
   Type signature:
   ```kai
   pub fn run_app[e](root: () -> Unit / e)
     : Unit / Spawn + Signal + Cancel + e
   ```
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
    known-regressions.md
  kai.toml               # package manifest (name = "ahu")
  ahu/                   # module root — `import ahu.X`
    cell.kai             # Layer 2
    restart.kai          # Layer 3
    log.kai              # structured logging helpers
    app.kai              # bootstrap helper
                         # Layer 1 (streams) is the kaikai stdlib —
                         # no ahu module; see §Layer 1.
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

**Status:** all fixtures compile (tier0) and tier1 (run-and-diff)
passes under both backends, except `examples/log_demo` — see
`docs/known-regressions.md`.

## External dependencies on kaikai

ahu is built entirely on upstream kaikai primitives: `Actor[Msg]`,
`Spawn`, `Cancel`, `Link`, `Monitor`, the mailbox policies, the
`Signal` and `Clock` effects, the reactor that parks fibers on I/O,
and the stdlib `stream`, `log`, `time`, `fs`, `os`, and `net`
modules. Every primitive the shipped layers need is present; the
reactor parks fibers on `Clock.sleep`, `Signal.await`, file I/O, and
the `NetTcp` ops, so `with_restart_backoff` and `run_app` are
cooperative — siblings keep running during a wait.

Design-relevant capabilities and what they enable (follow-ups are
tracked in `docs/roadmap.md`):

- **Union types** (`type T = A | B | C` as a true union, with
  `bind : Type` narrowing) let a cell mailbox be composed from
  per-feature message types without wrapper sums, and pipeline or
  supervisor error types be composed from per-stage errors.
- **`Map[K, V]`** is an AVL carrier with `m[k]` indexing sugar — the
  carrier a per-nursery `Registry` capability would use (Decision 4).
- **`stdlib/fs/file`** (`read_file` / `write_file` / `append`) backs
  `ahu.log` sinks and any cell that persists snapshot state;
  **`stdlib/os/env`** backs a future `run_app` config loader.

Open shape questions the design leaves to usage data rather than
pre-emptive commitment:

- **A free `start_cell : ... -> Pid[Msg]` constructor.** The
  region-brand walker admits only a fixed set of fiber-producing
  helpers, so ahu ships `with_cell(initial, step, body)` (mirroring
  `with_mailbox`) as the canonical entry point; a free `start_cell`
  waits on wider `TyBranded` propagation upstream.
- **Structured `with_cell` shutdown.** When `body` returns the
  cell's fiber may still be alive, so a final message sent right
  before the body returns may not be processed before the program
  exits; `examples/counter/main.out.expected` reflects this
  honestly.
- **A cell fiber does not inherit an effect handler installed
  outside it.** A cell can perform only effects handled within its
  own fiber (`Actor`, plus the native `Console` leaves); logging
  directly from a cell step is unsupported — see `examples/log_demo`.
- **A unified `ChildOutcome[E]` over Link/trap-exit + a typed error
  result.** A parent observes a child through two channels today
  (`"Normal"` / `"Crashed"` strings on a trap-exit'd mailbox, and any
  `Result[E, T]` the child returns); union types make a unified
  `type ChildOutcome[E] = Normal | Crashed | Errored(E)` expressible.
  Whether to adopt it or keep the BEAM-style two-channel split is a
  decision for usage data.

Gaps are surfaced as kaikai issues coordinated separately, not
patched from this repository.

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
