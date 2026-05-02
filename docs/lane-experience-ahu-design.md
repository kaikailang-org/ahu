# Lane experience report — ahu-design

Lane: design-only initial scaffolding for the `lnds/ahu` repository.
No implementation. Output: `docs/design.md` pinning the seven
load-bearing decisions, `docs/roadmap.md` with the
Tongariki / Anga Roa / Orongo / Anakena series, plus the four
meta-files (`CLAUDE.md`, `README.md`, `VERSION`, `CHANGELOG.md`).

## Result, up front

**All five milestones (M1–M5) closed in a single agent session.**

The branch `ahu-design-v1` carries five commits — M1 (scaffolding),
M3 (design.md), M4 (roadmap.md), and this M5 retrospective. M2
(reference reading) had no separate commit because it was pure
input. The PR is opened against `main` of `lnds/ahu` for the
integrator to review.

The branch is left clean and ready for review; no implementation
code exists in `src/`, `tests/`, or `examples/`, matching the
brief's constraint that this lane ships design and scaffolding
only.

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
- Commits on `ahu-design-v1`: 4 (M1 scaffolding, M3 design doc, M4
  roadmap, M5 lane experience).
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
