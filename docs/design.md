# ahu design

Living document for the OTP-style framework that runs on top of kaikai.
The decisions listed here guide implementation in `ahu-Tongariki` (the
MVP) and beyond.

## Context

ahu is the second layer of the five-project lnds ecosystem:

```
kaikai      (the language)
   ↓
ahu         (this project — OTP-style framework)
   ↓
ahu-db      (database / persistence)
   ↓
ahu-ddd     (DDD building blocks)
   ↓
manutara    (Phoenix-LiveView-style web framework)
```

Each project has its own repository, its own `Tongariki / Anga Roa /
Orongo / Anakena` series, and its own `docs/roadmap.md`. ahu's series
sits in `docs/roadmap.md` of this repository; the meta-roadmap and the
naming convention are pinned upstream in
`kaikai/docs/roadmap.md` §*Meta-roadmap*.

Erlang's OTP — gen_server, supervisors, applications — is the prior art
ahu inherits from at the surface level. The execution model differs:
ahu does not bring its own scheduler, its own message-passing runtime,
or its own process model. Those primitives are already in kaikai's main
branch as of the m8 effects + actor work:

- `Actor[Msg]` effect with `self()` / `send(...)` / `receive()` —
  typed mailboxes, one effect instance per message type.
- `Pid[Msg]` — a region-branded handle that cannot escape the nursery
  that produced it.
- `Spawn` effect — `spawn` / `await` / `select` / `cancel` /
  `set_trap_exit` operations.
- `Cancel` effect — cooperatively delivered at yield points.
- `Link` and `Monitor` effects — bidirectional cancellation cascade
  and unidirectional `MonitorDown` notifications respectively.
- `MailboxPolicy = Unbounded | Bounded(capacity, Overflow)` with
  `Overflow = DropOldest | DropNewest | BlockSender`.
- Single-dispatch protocols (`docs/protocols.md`, m12.8): `protocol`
  declarations, `impl` blocks, `#derive(...)` for structural impls.

ahu's job is to package those primitives into a small, opinionated
surface — *behaviors*, *supervisors*, *applications* — that Erlang
veterans recognise immediately and that a kaikai newcomer can learn
from a one-pager.

This document is updated as decisions are closed.

## Cross-cutting principles

ahu inherits kaikai's three-tier principle stack verbatim
(`kaikai/CLAUDE.md` §*Cross-cutting principles*). The reproduction in
`CLAUDE.md` of this repository is the authoritative copy for ahu
contributors. Two ahu-specific tightenings on top of the kaikai stack:

- **No alternate process abstractions in Tongariki.** One behavior
  shape, one supervisor shape, one application shape. Specialised
  forms (`Agent`, `Task`, `GenStateMachine`, `GenEvent`) wait for
  usage data — see §*Decision 6* and §*Not goals*.
- **No re-implementation of kaikai primitives.** Mailboxes, Pids,
  links, monitors, and trap-exit are kaikai contracts. ahu wraps and
  composes them; it does not paraphrase them. Gaps in the upstream
  surface are documented in §*External dependencies on kaikai*, not
  patched locally.

The tie-breakers (safety beats ergonomics, fast compilation beats
generality, runtime efficiency beats expressive novelty,
approachability beats one-canonical-form) carry over without change.

## Decisions

The seven load-bearing decisions for ahu-Tongariki, each closed.

### Decision 1 — Behavior is a record of callback functions

OTP's `gen_server` exposes five callbacks (`init/1`, `handle_call/3`,
`handle_cast/2`, `handle_info/2`, `terminate/2`); the framework dispatches
to them by name on each message. Three viable encodings exist in kaikai:

- **(a) Single-dispatch protocols.** Declare `protocol GenServer { ...
  }` with `Self`-parameterised callbacks; users write `impl GenServer
  for MyState { ... }`. Compatible with monomorphisation; reads like
  Rust traits or Elixir behaviours.
- **(b) Effect handler.** Declare `effect GenServer { init() : State;
  handle_call(msg) : (Reply, State); ... }`; users write `handle {
  behavior_loop() } with GenServer { init -> ..., handle_call -> ... }`.
  Callbacks are effect ops, dispatched through the handler stack.
- **(c) Record of callback functions.** Declare a `BehaviorSpec` record
  type whose fields are the callback functions; users construct one
  and pass it to `start_behavior(spec)`. Each field's type carries an
  open effect row (`/ e`) that flows into the framework's row.

**Decision: (c) — record of callback functions.**

Rationale:

- **(a) is blocked by kaikai's pure-protocol rule.** `docs/protocols.md`
  §*Composition with other features → With effects* pins:
  *"Protocols are pure — `impl P for T` ops cannot have effect rows."*
  GenServer callbacks routinely need `Console`, `File`, `Clock`,
  `Reader`, and similar effects to do useful work. Until kaikai
  relaxes this constraint (an explicit non-goal of the protocols v1
  per the same section), protocols cannot carry the surface ahu needs.
- **(b) is viable but more ceremonious for the common case.** An
  effect declaration adds a layer between the user's intent ("this is
  a counter behavior") and the framework ("this is a long-running
  process driven by a callback table"). The `handle ... with ...`
  body is the implementation site; the effect declaration is the
  schema. Both must be kept in sync, and the user pays one extra
  block of indentation. Effects also forbid re-binding the handler
  to a value (`docs/effects.md` §*Out of scope for v1* item:
  *"Named handlers as first-class values"*) — which is exactly what
  a supervisor needs to do when starting children with different
  callback tables.
- **(c) reuses the shape kaikai already uses.** `with_mailbox(body)`,
  `nursery(body)`, `try(body)`, `with_state(0)(body)` — every stdlib
  helper that takes "the user's logic" takes it as a closure or a
  record of closures. A `BehaviorSpec` is the same idea, just with
  multiple closures grouped by role. Each callback's effect row
  flows out via row polymorphism, so a callback that does
  `Console.print(...)` adds `Console` to the row of `start_behavior`
  without ceremony. Monomorphisation specialises per use site, so
  there is no runtime indirection: the kaikai compiler inlines the
  callback at every dispatch site.

The shape of `BehaviorSpec` (sketched, surface bikeshed deferred to
implementation):

```kai
type BehaviorSpec[State, Call, Cast, e] = {
  init:        ()                 -> State                 / e,
  handle_call: (State, Call)      -> (CallReply, State)    / e,
  handle_cast: (State, Cast)      -> State                 / e,
  terminate:   (State, ExitReason) -> Unit                 / e,
}

type BehaviorMsg[Call, Cast] =
  | Call(reply_to: Pid[CallReply], payload: Call)
  | Cast(payload: Cast)
  | Down(event: MonitorDown)        # supervision delivery channel

pub fn start_behavior[State, Call, Cast, e](
  spec: BehaviorSpec[State, Call, Cast, e]
) : Pid[BehaviorMsg[Call, Cast]] / Spawn + e
```

Two callbacks deliberately drop out compared to OTP:

- **No `handle_info/2`** (catch-all for non-typed messages). Kaikai
  mailboxes are typed by construction (`Pid[Msg]` only accepts a
  single `Msg`); there is no "untyped message" path to catch. The
  closest analogue, `MonitorDown`, ships through the `BehaviorMsg`
  variant explicitly.
- **No `code_change/3`** (in-place module upgrade). See §*Decision 4*.

The cast-vs-call distinction stays: `Call` is the payload type for
synchronous request/reply (the mailbox carries a reply-to `Pid`),
`Cast` is the payload type for fire-and-forget asynchronous messages.
Behaviors that need only one channel set the unused payload type to
`Nothing` and the framework prunes the variant at monomorphisation.

### Decision 2 — Supervision: only `one_for_one` in Tongariki

OTP ships four restart strategies (`one_for_one`, `one_for_all`,
`rest_for_one`, `simple_one_for_one`). Each is a distinct
implementation: `one_for_one` restarts only the failing child;
`one_for_all` restarts every child whenever any one fails;
`rest_for_one` restarts the failing child plus every child started
after it; `simple_one_for_one` is a dynamic variant for pools.

**Decision: ahu-Tongariki ships `one_for_one` only.** The other three
strategies wait for ahu-Anga Roa.

Rationale:

- `one_for_one` covers the supervised-counter, leaf-worker, and
  "supervise N independent backends" patterns — the 80%+ case in
  practice for a non-distributed framework. Erlang documents this.
- `one_for_all` and `rest_for_one` require modelling
  child-startup-order as a load-bearing concept; `simple_one_for_one`
  requires dynamic child specs and a child registry. Each adds
  surface area that should be designed against real usage data, not
  pre-emptively.
- Holding the line at `one_for_one` keeps the `Supervisor` shape
  declarative and small: a `RestartPolicy` per child plus a global
  `intensity / period` tuple on the supervisor itself.

The shape of `Supervisor` (sketched):

```kai
type RestartPolicy =
  | Permanent       # restart on any termination
  | Transient       # restart only on abnormal termination
  | Temporary       # never restart

type ChildSpec[Msg] = {
  id:      String,                       # human label for diagnostics
  start:   () -> Pid[Msg] / Spawn,       # closure that boots the child
  policy:  RestartPolicy,
  shutdown: ShutdownTimeout,              # graceful then forceful
}

type SupervisorSpec = {
  strategy:  Strategy,                    # OneForOne in Tongariki
  intensity: Int,                         # max restarts ...
  period:    Int,                         # ... per period (seconds)
  children:  [ChildSpec[_]],              # heterogeneous children
}

pub fn start_supervisor(
  spec: SupervisorSpec
) : Pid[SupervisorMsg] / Spawn
```

`ChildSpec[_]` uses the `Pid[_]` existential form pinned in
`kaikai/docs/actors.md` §*Open questions* #3 — supervision is
explicitly the place where `_` is allowed in the `Pid` parameter,
because the supervisor does not need to know each child's `Msg` type.
The brand discipline still applies at the boundary: each
`start: () -> Pid[Msg]` closure is region-branded to the supervisor's
nursery.

`intensity / period` is the OTP restart-window: at most `intensity`
restarts within `period` seconds before the supervisor itself
escalates. Tongariki ships sensible defaults (`5 / 60`) and lets the
user override.

The supervisor itself is a `Behavior` (Decision 1). The `init`
callback registers each child via `Monitor.monitor(child_pid)`; the
`handle_cast` channel takes `Down(event)` and applies the strategy.
The supervisor sets `set_trap_exit(true)` on entry so a child crash
delivers a `MonitorDown` event into the supervisor's mailbox instead
of cascading through `Cancel`. This pattern is documented in
`kaikai/docs/actors.md` §*Trap-exit semantics* and §*Supervision
trees*; ahu codifies the boilerplate so users do not write it
themselves.

### Decision 3 — Process registry: deferred to Anga Roa

OTP `register("name", pid)` lets any process look up another by name.
Kaikai's `Pid[Msg]` is region-branded to the nursery that produced it;
the brand is load-bearing for safety (see `kaikai/docs/actors.md`
§*Pid[Msg] — typed handle*).

Three options for ahu:

- **(a) Global registry that ignores brands.** Registered Pids escape
  their nursery; the registry becomes a brand-laundering tool.
- **(b) Per-nursery registry.** Each nursery installs a `Registry`
  effect handler; lookups are scoped to the nursery's children.
- **(c) No registry in Tongariki; design properly in Anga Roa.**

**Decision: (c) — no process registry in ahu-Tongariki.** Ship
without one; design the proper shape in ahu-Anga Roa with usage data.

Rationale:

- (a) breaks the brand discipline that `kaikai-Tongariki` already
  paid for. Surfaces the question "is the brand a contract or a
  hint?" — kaikai's answer is "contract", and ahu does not get to
  re-litigate that.
- (b) is the leading candidate for Anga Roa, but the right shape
  depends on details that only emerge from real ahu users:
  - Is the registry per-supervisor or per-nursery?
  - How does a child handed off across supervisor boundaries
    re-register?
  - What is the lookup-failure semantics — `Option[Pid]`, or a
    dedicated `Registry` effect with `not_found` as an op?
  - How does the registry interact with hot reconfiguration of a
    supervision tree?
  Designing the answer pre-emptively risks shipping a registry that
  needs to be replaced once anyone uses it.
- (c) keeps ahu-Tongariki small and lets the first wave of users
  reach for explicit Pid handoff (constructor argument, message
  payload), which is what the kaikai region-brand already encourages.
  When ahu-Anga Roa starts, the design surface is wider and the
  decision can be informed.

A consequence: in ahu-Tongariki, a behavior that needs to communicate
with a peer must receive the peer's `Pid` at construction time — via
its `init` argument or via a `Cast`/`Call` payload from a parent
that already holds both Pids. This forces explicit dependency wiring
in supervisor specs, which is good architecture by accident: there
is no "ambient lookup" hiding the topology.

### Decision 4 — No hot code reload, ever

Erlang's killer feature; orthogonal to language design and requires a
runtime with versioned module loading.

**Decision: ahu does not support hot code reload, in any milestone.**
This is a permanent non-goal, not a deferred one.

Rationale:

- Kaikai compiles to native binaries via LLVM (`kaikai/docs/design.md`
  §*Decisions*: *"Final format: single static binary with embedded
  runtime"*). There is no module loader at runtime; there is no
  versioned bytecode to swap; there is no abstract machine that can
  pause one version of a function and resume on another.
- Retrofitting hot reload would require either (i) abandoning native
  compilation in favour of an interpreter, or (ii) building a
  module-loader runtime that links new compiled objects in-process —
  effectively a separate language target. Both are out of scope for
  the lnds ecosystem.
- Production deployments target rolling restarts (process supervisor
  drains traffic, swaps binary, restarts). This is the
  industry-standard alternative; it works for ~99% of use cases and
  is what every runtime that lacks hot reload has been doing since
  the 1990s.
- The only `code_change/3`-style callback OTP exposes (per-process
  state migration during hot reload) is therefore N/A.

This decision is reproduced in §*Not goals* and in `CLAUDE.md`
§*Things to avoid* so an agent reading either alone reaches the same
conclusion.

### Decision 5 — No distribution in Tongariki or Anga Roa

Erlang's distribution protocol lets one node send to a Pid on
another node transparently. The runtime handles serialisation,
node-up/node-down detection, network failure modes, and security.

**Decision: ahu-Tongariki and ahu-Anga Roa are single-node only.**
Cross-node Pids are the earliest possible scope for ahu-Orongo, and
may slip to ahu-Anakena depending on prerequisites.

Rationale:

- Distribution requires a serialisation protocol for arbitrary
  message types. Kaikai's `Serialize` protocol (one of the m12.8 v1
  protocols, see `kaikai/docs/protocols.md`) handles strings round-
  tripping, but the v1 set explicitly defers `Serialize` for records
  and sum types to a follow-up — *"needs return-type-driven
  dispatch (post-v1)"*. Without serialisation for arbitrary
  user-defined types, distribution cannot ship.
- Distribution requires a failure detector (heartbeat, timeout
  tuning, network partitions). This is its own design surface,
  comparable in size to the entire single-node ahu surface.
- Distribution interacts with region-brand on `Pid[Msg]`: a
  cross-node Pid is by construction outside the local nursery's
  region. Either the brand becomes contextually unbranded across
  nodes (a special case carved into the type system), or every
  cross-node Pid is wrapped in a `RemotePid[Msg]` distinct type
  that carries its own discipline. The right shape needs design.
- Erlang's distribution shipped a decade after the language did; the
  ahu equivalent does not need to ship before the surface that runs
  on top of it is mature.

Single-node ahu still covers a large class of useful systems: any
program that fits on one machine and needs supervision,
backpressure, and graceful shutdown. That covers the vast majority
of real workloads encountered today. The distributed case is a real
niche, but not one ahu-Tongariki has to address.

### Decision 6 — ahu-Tongariki MVP scope

The minimum surface that lets a user write a real program against
ahu and recognise the result as "an OTP-style application".

**In scope for ahu-Tongariki:**

1. **`Behavior`** (Decision 1) — the gen_server analogue. The
   `BehaviorSpec` record, the `start_behavior` constructor, the
   `BehaviorMsg[Call, Cast]` envelope, the canonical receive loop
   that dispatches `Call` / `Cast` / `Down` to the right callback,
   and `terminate` invocation on shutdown.
2. **`Supervisor`** (Decision 2) — `one_for_one` only. The
   `SupervisorSpec`, `ChildSpec`, `RestartPolicy`, `ShutdownTimeout`,
   `intensity / period`, and `start_supervisor`. The supervisor is
   itself a `Behavior` instance.
3. **`Application`** — the top-level entry point. An `Application`
   wraps the boot sequence: install signal handlers (`SIGINT`,
   `SIGTERM`) for graceful shutdown, start the root supervisor,
   block until the root settles, exit cleanly.
4. **Reference example** — a counter behavior under a supervisor,
   driven by an application. Shows: behavior callbacks with effect
   rows, supervisor restart on intentional crash, application
   shutdown on signal. Lives in `examples/counter/` once the
   implementation lane lands.

**Out of scope for ahu-Tongariki (deferred to later milestones or
permanent non-goals):**

- Other supervision strategies — `one_for_all`, `rest_for_one`,
  `simple_one_for_one`. **Anga Roa.**
- Process registry — global, per-nursery, or otherwise.
  **Anga Roa.** See §*Decision 3*.
- Distribution — cross-node Pids, node-up/down events, distributed
  supervision. **Orongo at earliest, possibly Anakena.** See
  §*Decision 5*.
- Hot code reload — module versioning, `code_change/3`. **Never.**
  See §*Decision 4*.
- Specialised behaviours — `Agent`, `Task`, `GenStateMachine`,
  `GenEvent`. **Anga Roa or later.** Each is a viable add-on once
  `Behavior` has bedded in; designing them pre-emptively risks
  shipping shapes that don't compose.
- Pluggable mailbox policies beyond the kaikai catalog
  (`Unbounded`, `Bounded(c, DropOldest|DropNewest|BlockSender)`).
  **Anga Roa or later** — needs upstream cooperation if new
  policies are required.
- Pre-built telemetry / observability hooks. **Orongo** — plugs
  into kaikai's diagnostic JSON surface once that lands; see
  `kaikai/docs/design.md` §*Tier 2 #4*.
- A DSL for declaring behaviors (Elixir-style `use GenServer` with
  macro expansion). Kaikai has no macros and no plans for them
  (`kaikai/docs/design.md` §*Open decisions* — not listed, hence
  out of scope). The record-of-callbacks form is the canonical
  surface.

### Decision 7 — Repository layout

Standard kaikai-shaped layout. The implementation lane will
populate `src/`, `tests/`, and `examples/`; the design lane lands
only the `docs/` set.

```
ahu/
  CLAUDE.md           # cross-cutting principles inherited from kaikai
  README.md           # 1-pager: status, ecosystem position, scope
  VERSION             # 0.0.1 at design-lane scaffolding
  CHANGELOG.md        # [Unreleased] populated by each lane
  docs/
    design.md         # this document — surface, decisions, MVP
    roadmap.md        # ahu-specific Tongariki/Anga Roa/Orongo/Anakena
    lane-experience-*.md   # per-lane retrospectives
  src/                # implementation; empty in design lane
  tests/              # ahu test fixtures; empty in design lane
  examples/           # reference demos (counter app); empty in design lane
```

The `docs/lane-experience-*.md` convention mirrors kaikai (where the
filename pattern already exists across two dozen lanes). Each lane
opens with a TSV of build-and-decision events plus a narrative
section; the design lane's instance lives at
`docs/lane-experience-ahu-design.md`.

The layout deliberately does not include:

- `runtime/` — kaikai owns the runtime; ahu links against it via
  the same kaikai binary.
- `stage0/` / `stage1/` / `stage2/` — ahu is not bootstrap code; it
  compiles with `kai build` once the framework is implemented.
- `tools/` — no per-project build tooling beyond what kaikai
  provides through `kai build` / `kai test` / `kai check`.

## MVP scope — ahu-Tongariki

The implementation criteria the implementation lane(s) must hit before
ahu-Tongariki ships:

### Surface deliverables

1. `src/behavior.kai` — `BehaviorSpec`, `BehaviorMsg`,
   `start_behavior`, the dispatch loop, `terminate` plumbing.
2. `src/supervisor.kai` — `SupervisorSpec`, `ChildSpec`,
   `RestartPolicy`, `ShutdownTimeout`, `start_supervisor`,
   `one_for_one` strategy.
3. `src/application.kai` — `Application` shape, signal handler
   wiring, root supervisor lifecycle.
4. `examples/counter/` — counter behavior + supervisor +
   application; user runs `kai run examples/counter/main.kai` and
   the program (a) increments on `Cast`, (b) replies to a `Call`
   with the current value, (c) restarts on intentional crash and
   continues, (d) shuts down cleanly on SIGINT.

### Test criteria (ahu-Tongariki Tier 1)

The `kai test` corpus under `tests/` exercises:

- Behavior `init` runs once before any message is handled.
- A `Call` from a peer reaches the `handle_call` callback and the
  reply pid receives the response within the same nursery.
- A `Cast` from a peer reaches the `handle_cast` callback and
  updates state.
- A behavior that crashes during `handle_call` triggers
  `terminate` with the appropriate `ExitReason`.
- A supervisor with one child and `Permanent` policy restarts the
  child after a deliberate panic, up to `intensity` times in
  `period` seconds, then escalates.
- A supervisor with `Transient` policy restarts on `Crashed` but
  not on `Normal`.
- An `Application` boots its root supervisor, blocks until cancel
  signal, then propagates shutdown through the tree.

### End-to-end MVP verification

A user with `kaikai-Tongariki` installed (so `kai` is on PATH) must
be able to:

```sh
git clone github.com/lnds/ahu
cd ahu
kai build                                      # ahu library compiles
kai test tests/                                # all tier-1 tests pass
kai run examples/counter/main.kai &            # counter app boots
kill -INT $!                                   # graceful shutdown
wait                                           # exit code 0
```

If this works, ahu-Tongariki is fulfilled.

## External dependencies on kaikai

The design above leans on kaikai primitives that are either already
landed or scheduled. Two gaps the ahu-Tongariki implementation will
need addressed upstream first:

1. **Blocking `Actor.receive()` on an empty mailbox.** Today
   `kaikai/stdlib/actor.kai` notes: *"`receive()` on an empty mailbox
   is a runtime error in v1 — the inline-eager scheduler (m8 #3)
   cannot suspend the caller until a message arrives."* Behaviors
   inherently spend most of their lifetime parked on `receive`.
   ahu-Tongariki's implementation lane therefore requires the
   cooperative scheduler scheduled in kaikai's m8.x to land first.
   Confirmed dependency, not blocking the design.

2. **`BlockSender` mailbox policy delivery.** Same upstream note:
   `BlockSender` requires the m8.x cooperative scheduler to actually
   park the sender. Until then, behaviors that exercise backpressure
   must use `Bounded(c, DropOldest)` or `Bounded(c, DropNewest)`,
   both of which already work under the inline-eager scheduler.
   ahu-Tongariki tests must be written accordingly: backpressure
   fixtures gate on `BlockSender` availability.

3. **`Serialize` protocol for records and sum types.** Not needed for
   ahu-Tongariki (no distribution; no persistence in this layer), but
   noted here so ahu-db and the eventual distribution work surface
   the dependency. Currently scoped post-m12.8 in
   `kaikai/docs/protocols.md` §*Stdlib protocols*.

The design lane does not patch any of these into kaikai. Each is
either already in flight (m8.x), already pinned in a kaikai design
doc, or out of ahu's stack depth for Tongariki.

## Not goals

A list of capabilities ahu intentionally does **not** ship, separated
from §*Decisions* because each is a permanent or
horizon-deferred boundary, not a closed open question.

- **Hot code reload.** See §*Decision 4*. Permanent non-goal across
  every milestone.
- **Cross-node distribution in Tongariki / Anga Roa.** See §*Decision
  5*. Earliest possible: Orongo.
- **Process registry in Tongariki.** See §*Decision 3*. Earliest
  possible: Anga Roa.
- **`handle_info/2`-style untyped catch-all.** Mailboxes are typed by
  construction in kaikai; there is no untyped channel.
- **`code_change/3`** (state-shape migration during hot reload).
  N/A — see §*Decision 4*.
- **Macros for declaring behaviors.** Kaikai has no macros. The
  record-of-callbacks form is the canonical surface; no Elixir-style
  `use GenServer` ahu equivalent.
- **Multi-instance behaviors via `simple_one_for_one`.** Anga Roa or
  later, gated on registry design.
- **A separate `Agent` / `Task` shape.** Until usage data shows the
  callback shape gets in the way for one-off computations,
  `Behavior` is the only process abstraction.

## Roadmap pointer

The full ahu milestone series — Tongariki / Anga Roa / Orongo /
Anakena — lives in `docs/roadmap.md` of this repository. That
document tracks per-milestone scope, definition-of-done, sequencing
constraints against kaikai milestones, and explicit downstream
unlocks (when ahu-db, ahu-ddd, manutara can start).

The meta-roadmap covering the full lnds ecosystem stack lives
upstream in `kaikai/docs/roadmap.md` §*Meta-roadmap*. ahu's
`docs/roadmap.md` follows the same shape.

## References

- `kaikai/docs/design.md` — language redesign, principle stack, MVP
  contract.
- `kaikai/docs/actors.md` — `Actor[Msg]`, `Pid[Msg]`, mailbox
  policies, `Link`, `Monitor`, trap-exit, supervision-tree pattern.
- `kaikai/docs/structured-concurrency.md` — fibers, nurseries,
  `Spawn`, `Cancel`, region-branding.
- `kaikai/docs/effects.md` — effect rows, unification, `handle` /
  `resume`, capability passing.
- `kaikai/docs/effects-stdlib.md` — `Console`, `Stdin`, `Env`,
  `File`, `Clock`, `Random`, `Net*`, `Process`, `Fail`, `State[T]`,
  `Reader[T]`, `Writer[W]`, `Mutable`, `Cancel`, `Spawn`, `Ffi`.
- `kaikai/docs/protocols.md` — single-dispatch protocols (m12.8),
  `#derive`, the pure-protocol rule that constrains Decision 1.
- `kaikai/docs/roadmap.md` — kaikai milestones and the
  meta-roadmap that places ahu in the ecosystem.
- `kaikai/stdlib/actor.kai`, `kaikai/stdlib/spawn.kai` — the
  kaikai-side wrappers ahu builds on.
- Erlang/OTP design principles
  (`https://www.erlang.org/doc/system/design_principles.html`) —
  prior art for the behavior / supervisor / application split.
- Joe Armstrong, *Making reliable distributed systems in the
  presence of software errors* (2003) — the OTP rationale.
