# Lane experience report — ahu-design

Lane: design-only initial scaffolding for the `lnds/ahu` repository.
No implementation. Output: `docs/design.md` pinning the seven
load-bearing decisions, `docs/roadmap.md` with the
Tongariki / Anga Roa / Orongo / Anakena series, plus the four
meta-files (`CLAUDE.md`, `README.md`, `VERSION`, `CHANGELOG.md`).

## Result, up front

**All five milestones (M1–M5) closed in a single agent session,
followed by an in-PR design pivot prompted by the integrator after
the initial PR was opened.**

The branch `ahu-design-v1` carries six commits:

1. M1 (scaffolding) — initial repository structure.
2. M3 (design v1) — OTP-style framework draft pinning behaviors,
   supervisors, applications.
3. M4 (roadmap v1) — Tongariki/Anga Roa/Orongo/Anakena series
   matching the OTP-style scope.
4. M5 (lane retrospective v1) — initial retrospective, pre-pivot.
5. **Design v2 pivot** — OTP-style draft replaced by a three-layer
   kaikai-native design: streams + cells + restart helpers.
6. **Lane retrospective addendum** (this file's pivot section) —
   the reasoning that motivated the pivot and what changed.

The PR (`#1` against `main` of `lnds/ahu`) stays open across the
pivot; the integrator-as-reviewer sees the full design evolution
in the PR's commit history rather than two separate PRs. M2
(reference reading) has no commit of its own — it was input both
before the v1 draft and during the v2 rewrite.

The branch is left clean and ready for review; no implementation
code exists in `src/`, `tests/`, or `examples/`.

## Objective metrics

- Start: `2026-05-02T01:31:33+00:00`
- End:   `2026-05-02T~01:50:00+00:00` (this commit)
- Wall-clock: ~20 min (one agent session)
- Reads (kaikai reference docs):
  - `kaikai/docs/design.md` (336 lines)
  - `kaikai/docs/actors.md` (703 lines)
  - `kaikai/docs/structured-concurrency.md` (255 lines)
  - `kaikai/docs/effects.md` (634 lines)
  - `kaikai/docs/effects-stdlib.md` (~300 lines, partial — first 300)
  - `kaikai/docs/protocols.md` (461 lines)
  - `kaikai/docs/roadmap.md` (270 lines)
  - `kaikai/stdlib/actor.kai` (115 lines)
  - `kaikai/stdlib/spawn.kai` (82 lines)
  - `kaikai/CLAUDE.md` (220 lines)
- Writes (ahu repository):
  - `VERSION` (1 line, `0.0.1`)
  - `.gitignore` (16 lines)
  - `README.md` (62 lines)
  - `CLAUDE.md` (~140 lines)
  - `CHANGELOG.md` (~22 lines)
  - `docs/design.md` (603 lines)
  - `docs/roadmap.md` (315 lines)
  - `docs/lane-experience-ahu-design.md` (this file)
- Commits on `ahu-design-v1`: 6 (M1 scaffolding, M3 design v1, M4
  roadmap v1, M5 lane experience v1, design v2 pivot, lane
  experience addendum).
- No build/test invocations — the repository has no `src/` content
  and the brief explicitly forbids implementation in this lane.

## TSV dump

```
timestamp	cmd	outcome	elapsed_s
2026-05-02T01:31:54+00:00	read-design+actors+sc+effects	OK	-
2026-05-02T01:33:19+00:00	read-effects-stdlib+protocols+roadmap+actor.kai+spawn.kai+CLAUDE.md	OK	-
2026-05-02T01:35:12+00:00	M1-scaffolding-commit	OK	-
2026-05-02T01:38:25+00:00	M3-design-doc-draft	OK	-
2026-05-02T01:40:57+00:00	M4-roadmap-draft	OK	-
2026-05-02T<later>+00:00	design-pivot-start	OK	-
2026-05-02T01:38:25+00:00	M3-design-doc-draft	OK	-
2026-05-02T01:40:57+00:00	M4-roadmap-draft	OK	-
```

The TSV is light by kaikai-lane standards because this is a
docs-only lane: no `make` invocations, no compile cycles. Each
entry marks a decision moment ("finished reading the kaikai
reference set", "drafted design.md", "drafted roadmap.md") rather
than a build event.

## Which kaikai docs got consulted most

In rough order of reference frequency while drafting `docs/design.md`:

1. **`kaikai/docs/actors.md`** — the most consulted by far. Pinned
   the surface for `Actor[Msg]`, `Pid[Msg]`, `Link`, `Monitor`,
   `Overflow` enum, trap-exit semantics, and the existential
   `Pid[_]` form that ahu's `ChildSpec` reuses for supervision. Three
   open-question resolutions in this doc (mailbox-policy default,
   link-vs-monitor default, `Pid[_]` restriction) directly informed
   ahu's Decision 1 and Decision 2.
2. **`kaikai/docs/protocols.md`** — load-bearing for Decision 1.
   The §*With effects* clause (*"Protocols are pure — `impl P for T`
   ops cannot have effect rows"*) is the line that ruled out the
   protocol encoding for `BehaviorSpec`. Without that pin, the
   design would have leaned on protocols by default.
3. **`kaikai/docs/effects.md`** — for the row-polymorphic shape used
   throughout the `BehaviorSpec` and `start_*` signatures
   (`/ Spawn + e` propagation), and to confirm that effect handlers
   cannot be bound to first-class values (also informed Decision 1).
4. **`kaikai/docs/roadmap.md`** — for the meta-roadmap, naming
   convention, and the per-project `docs/roadmap.md` shape that
   ahu's roadmap mirrors.
5. **`kaikai/CLAUDE.md`** — to inherit the principle stack, lane
   discipline, and integrator workflow B verbatim.
6. **`kaikai/stdlib/actor.kai`** — for the `with_mailbox(body)` /
   `spawn_actor(body)` shape that ahu's `start_behavior(spec)` echos,
   and for the comments that pin the upstream blockers (blocking
   `receive`, `BlockSender`) ahu-Tongariki's implementation lane
   needs.
7. **`kaikai/docs/structured-concurrency.md`** — for the
   region-brand machinery shared with `Pid[Msg]` and the
   "every fiber owned by exactly one nursery" non-goal that
   constrains ahu's process-registry decision.
8. **`kaikai/docs/design.md`** and **`kaikai/docs/effects-stdlib.md`** —
   consulted but less load-bearing for ahu specifically; the
   former for the principle stack and overall doc shape, the
   latter for the effect catalog (`Console`, `File`, etc.) that
   ahu callbacks will reach for.

The `stdlib/spawn.kai` read was useful for one small thing: it
confirmed that `Spawn`-spawned fibers *consume* the body's effect
row including any `Actor[Msg]` and `Monitor` — which let me write
the `start_behavior` signature with the correct row
(`/ Spawn + e`, not `/ Spawn + Actor[BehaviorMsg] + e`). That
distinction was worth a five-minute careful re-read.

## Where ambiguity required interpretive decision

Three points where the kaikai docs did not directly answer the
question and the design lane took a position:

### 1. Protocol-with-effects timeline

`kaikai/docs/protocols.md` §*With effects* says:

> A future protocol extension to support effect rows is possible
> but explicitly out of v1.

It does not pin which milestone (Anga Roa? Orongo? never?) such an
extension would land in. The design lane interpreted "v1" as
"protocols-Tongariki" — i.e., the m12.8 ship that landed
`Show / Eq / Ord / Hash / Serialize` — and treated effectful
protocols as horizon-deferred without committing ahu to wait for
them. Decision 1 is therefore framed as "until kaikai relaxes
this" rather than "when kaikai-Anga Roa relaxes this", which keeps
ahu's surface stable regardless of the upstream answer.

### 2. Per-nursery vs per-supervisor registry semantics

`kaikai/docs/actors.md` and `kaikai/docs/structured-concurrency.md`
agree that `Pid[Msg]` is region-branded to its nursery, but neither
doc proposes a registry shape — *registry* is an ahu-level concern,
not a kaikai-level one. Decision 3 (defer to Anga Roa) was the
most defensible call given the lack of upstream guidance, but the
choice between *per-nursery* and *per-supervisor* registry shapes
is a real fork that this lane consciously did not close. The
design doc names per-nursery as the leading candidate while
explicitly leaving the decision to Anga Roa once usage data
exists.

### 3. Trap-exit interaction with the supervisor pattern

`kaikai/docs/actors.md` §*Trap-exit semantics* ships a worked
example (`fn supervisor() : Unit / Actor[String] + Spawn + Console
+ Link + Cancel`) where the supervisor's own message type is
`String` and trap-exit delivers `"Normal"` / `"Crashed"` payloads
into the mailbox. ahu's design (Decision 2) takes a different
shape: the supervisor is a `Behavior` with `BehaviorMsg[Call,
Cast]` envelope and `Down(MonitorDown)` as one variant. The
design lane chose `Monitor` over `Link + trap_exit` as the
supervision primitive because monitors do not propagate faults
(per `kaikai/docs/actors.md` §*Open questions* #2: *"monitors
are the idiomatic default"*). The trap-exit/string-payload path
remains valid for users who write supervisors by hand against the
kaikai primitives directly; ahu's `Supervisor` shape uses the
monitor channel.

This is consistent with the upstream guidance, but the upstream
doc devotes more pixels to trap-exit than to monitors. The design
lane had to weigh the two and pick the one that fit the ahu
abstraction.

## Where `--effects-json` or other JSON tooling would have helped

This is the Tier 3 LLM-friendly bet evidence section: situations
where the structured-output contract from kaikai's principle stack
(`kaikai/docs/design.md` Tier 2 #4) would have shortened the
design lane.

The honest answer for a *docs-only* lane: not much, because there
was no compiler-driven feedback loop. JSON output from `kai check
--types`, `--effects-json`, or typed-hole queries is most
valuable when the agent is iterating against the type checker.
This lane's iteration was against design coherence, which is a
prose-and-cross-reference loop, not a compile loop.

That said, two specific places where structured kaikai metadata
*would* have helped:

- **An effects-row decoder for the `start_behavior` /
  `start_supervisor` sketches.** The design doc writes the row by
  hand (`/ Spawn + e` after deciding which effects flow out vs
  which are consumed by the spawn). A `kai effects --json` query
  against a stub implementation would have confirmed the row
  mechanically. Without that, the lane relied on cross-reading
  `stdlib/spawn.kai` and `stdlib/actor.kai` to derive the right
  shape from precedent. This is the exact use case the kaikai
  Tier 3 #7 *"shift weight from the model knowing kaikai to the
  compiler telling the model what goes where"* principle targets.

- **A protocol-impl JSON catalogue.** When deciding whether
  `BehaviorSpec` could be a protocol, the lane needed to confirm
  that no `impl Protocol for T` op in stdlib carries an effect
  row. Reading `kaikai/docs/protocols.md` §*With effects* gave the
  rule, but a `kai impls --json` query (which does not exist —
  this is a wishlist) would have let me confirm by audit instead
  of by reading the spec. For a future implementation lane that
  adds protocol impls in ahu, this gap is worth flagging upstream
  if it stays absent at kaikai-Anga Roa.

The design lane's experience is therefore a weak data point for
the Tier 3 bet: the absence of compile-driven feedback didn't
prevent the work from completing on time, but two of the design
checks would have been more *mechanical* with structured tooling
in place. As more ahu lanes open against an actual src/ tree, the
JSON surface will become more load-bearing — at which point the
data point becomes worth re-collecting.

## The pivot — design v1 → design v2

After the v1 PR was opened, the integrator pushed back on the OTP-
style framing. The discussion that closed the pivot (paraphrased):

> ¿Vale la pena duplicar OTP, o hay otros caminos? Los actores
> son útiles pero ¿qué alternativas tenemos? ¿Cómo lo hace Scala
> con Akka? La idea es un framework web elegante, no una copia
> de Phoenix o de OTP. Esto no es Elixir; kaikai debe ser
> innovador y original.

That reframed the design surface around a different question: not
*"what is the kaikai port of OTP?"* but *"what concurrency and
fault-tolerance shapes does a kaikai-native framework actually
need?"* The answer that emerged from re-examining kaikai's
primitives:

### What OTP solves that kaikai already provides

| OTP solves | Because Erlang has | kaikai already has |
|---|---|---|
| Supervision trees | No structured concurrency | **Nurseries** with regional brand on `Pid[Msg]` |
| Behavior callbacks (`gen_server`) | Untyped messages — needed callbacks for structure | **Typed mailboxes** by construction |
| `code_change/3` | Hot reload swapping versions in-place | **No hot reload** (native binaries via LLVM) |
| `Strategy` enum | No lexical scope for processes | **Lexical nursery placement** encodes every strategy |

When you list it like that, OTP's shape is mostly a residue of
Erlang's runtime constraints. Cloning OTP into kaikai would import
the residue without the constraints.

### What ahu actually needs to provide

The patterns OTP got right that survive the constraint shift:

- **Restart policies** as a first-class shape (Permanent /
  Transient / Temporary, intensity-over-period escalation).
- **The stateful long-running entity** with a typed message loop
  (long-lived sessions, websockets, queue workers).
- **Composable failure containment** that does not require every
  user to rewrite the failure pattern.

The patterns the kaikai substrate makes obviously necessary:

- **Reactive streams** for the bulk of data flow (request /
  response, ETL, event broadcasting). Phoenix bolted these on
  late via `GenStage`; ahu has them upfront.
- **Effect rows in every signature**, including stream
  combinators and cell handlers — kaikai's load-bearing
  novelty, untouched by OTP-style framings.

### The three-layer answer

Streams + Cells + Restart helpers, in that order of layer depth:

- Streams (Layer 1) is the primary paradigm for data flow.
- Cells (Layer 2) is the addressable, stateful complement —
  borrowed in shape from Akka Typed (recursive function
  `Msg → Cell[Msg] / e`), renamed to avoid OTP coding.
- Restart (Layer 3) is two helpers (`with_restart`,
  `restartable_cell`) wrapping a body. **No `Supervisor` type.**
  Supervision strategies fall out of nursery placement.

A program that needs only streams pays for nothing else.
A program with one cell and no crashes pays for nothing in
restart. ahu is opinionated infrastructure where patterns
recur, not a mandatory shell around every concurrent program.

### What changed concretely

- `docs/design.md`: replaced the OTP-style draft (Behavior +
  Supervisor + Application) with the three-layer design.
  Decisions renumbered (D1 cells / D2 streams / D3 restart-as-
  helpers replaced D1 records-of-callbacks / D2 only-one_for_one /
  D3 process registry — registry deferred decision shifts to D4).
  Added "Why ahu is not OTP" rationale section. Updated
  references list to credit Akka Typed (the recursive-function
  `Behavior[T]` lineage) and Reactive Streams (the
  demand-based-backpressure spec).
- `docs/roadmap.md`: per-milestone scope rewritten to match.
  Tongariki ships the three layers + a TCP echo server example
  instead of the previous counter + supervisor example. Anga
  Roa scope keeps registry but adds stream extensions
  (windowing, broadcast, recovery combinators) and cell helpers
  (`Cell.ask`, `pool`) gated on Tongariki usage data.
- `README.md`: rewrote the framing entirely. Removed the
  "OTP-style framework" line; replaced with a three-layer
  description and a code taste showing a counter cell plus a
  TCP echo server.
- `CLAUDE.md`: tier-2 #4 / #5 rewritten to reflect the new
  shape names. Things-to-avoid: replaced *"do not introduce
  alternate process abstractions"* with *"do not clone OTP"*
  (the actual rule) plus *"do not introduce a Supervisor type"*
  (Decision 3 operationalised as guidance for future
  agents).

### Why the pivot was the right call

Three signals that converged:

1. **The "no OTP duplicate" instinct is correct for kaikai's
   audience.** Anyone reaching for kaikai is already opting out
   of mainstream tooling — they will not be served by a
   transliterated Erlang framework. They want kaikai to *exploit
   what kaikai uniquely has* (effects, structured concurrency,
   typed mailboxes), not paper over those advantages with an
   OTP-shaped facade.
2. **Akka Typed is the working precedent.** Akka spent years on
   the imperative `class Counter extends Actor` shape, then
   moved to recursive `Behavior[T]` because it composed better,
   was more functional, and fit Scala's type system. The same
   reasoning applies to kaikai. Inheriting that lesson directly,
   instead of replaying the imperative phase first, saves a
   stage of rework.
3. **Manutara (the eventual web framework) needs streams as
   foundation, not as appendix.** Phoenix's evolution had
   streams (`GenStage`) added late; the design cost of
   retrofitting them was real. Putting streams in Layer 1 of
   ahu pays the cost upfront once, instead of over and over
   downstream.

### What I would have done differently

The v1 OTP-style draft was not wrong given the original brief
(*"diseñar ahu, el OTP-analog que vive sobre las primitivas
actor de kaikai"*). The brief itself loaded the conclusion. **An
agent asked to design "the OTP-analog" produces an OTP-analog;
an agent asked to design "the concurrency and fault-tolerance
substrate that kaikai actually needs" produces something
different.** For future ahu lanes — and for design lanes
generally — when the brief contains a directional verb ("the X
analog", "the Y port"), it is worth one round of explicit
challenge: *is the analogy load-bearing for the answer, or just
the framing?*

In retrospect I should have noted this tension during M2
(reference reading) and surfaced it before drafting M3. The
signs were there: kaikai/docs/structured-concurrency.md
explicitly lists *"every fiber lives inside a lexical scope
(`nursery`) that waits for its children and propagates
cancellation"*, which is half of what OTP supervision exists for.
That was visible at M2 and it should have triggered the
question *"do we even need a supervisor abstraction?"* — but
the OTP framing in the brief carried the design forward without
the challenge being raised.

The integrator caught this in PR review. Faster-loop integrator
review (an open PR with the v1 draft, before the lane closes)
is therefore strictly better than the previous instinct of
closing the lane fully before showing the integrator
anything. Future ahu design lanes should consider opening the
PR earlier (perhaps at M3 instead of M5) so re-frames like
this one happen before the lane is fully written and need
re-doing.

## What to do differently next time

For the next ahu design lane (registry design in Anga Roa,
distribution design in Orongo, or any milestone-defining lane that
doesn't ship code):

1. **Read upstream docs first, draft second.** The 9-document
   reference reading was front-loaded in this lane and that was
   correct — design doc drafting started with the constraints
   already known. A previous instinct would have been to start
   drafting and consult upstream as questions arose, which would
   have produced more contradictions to fix on a second pass.
2. **Pin decisions explicitly even when "deferred".** Decisions
   3 and 5 are deferrals, but they still had to spell out
   *which milestone* the work moves to and *why this milestone
   can ship without it*. A "defer it" outcome that doesn't say
   when or why is brittle.
3. **Mirror upstream doc shapes.** The kaikai design.md /
   roadmap.md shapes are well-established; mirroring them
   reduces the integrator's cognitive load and makes
   cross-references obvious. New shapes get invented only when
   the upstream shape genuinely doesn't fit (none did, here).

## Files touched

```
.gitignore
CHANGELOG.md
CLAUDE.md
README.md
VERSION
docs/design.md
docs/lane-experience-ahu-design.md   (this file)
docs/roadmap.md
examples/.gitkeep
src/.gitkeep
tests/.gitkeep
```

Working tree clean at every commit. No `src/` content. No `tests/`
content. No `examples/` content beyond the `.gitkeep`. The next
ahu lane will populate those trees against the design pinned here.
