# Anga Roa decisions affecting ahu — pre-2026-05-21 briefing

> **Status (superseded in part):** This is a historical briefing.
> Two of its recommendations have since been reversed and should
> not be acted on:
> - The advice to mark ahu's `pub` surface `#[unstable]` (§2, §6,
>   §8) was applied and then **removed** — ahu's surface is now
>   declared stable under the Hanga Roa edition; there are no
>   `#[unstable]` decls and no `[unstable]` opt-in in `kai.toml`.
> - The plan for an ahu-owned stream module (`ahu/stream.kai`,
>   `Source`/`Flow`/`Sink`) was dropped once the kaikai stdlib grew
>   its own `stream` (issue #801). ahu consumes the stdlib stream
>   directly; see `docs/design.md` §Layer 1 / §Decision 2.
>
> The rest of the briefing (editions, pipe-signature audit, backend
> parity CI, HTTP server) remains accurate as background.

This document covers the kaikai decisions taken between 2026-05-14 and the Anga Roa cutover (planned 2026-05-21) that change how `ahu` declares its public surface, consumes the language, or ships against the kaikai compiler. Hand this to ahu's maintainers (you, in another seat) so the Tongariki → Anga Roa transition on the ahu side is informed, not surprise-driven.

The list is grouped by "what you have to change in ahu" vs "what the kaikai compiler will do differently". Each item links to the kaikai issue + PR + relevant doc.

---

## 1. Editions are now a Tier 1 principle in kaikai

**Background:** kaikai adopted Rust-style "stability without stagnation" on 2026-05-15. The current edition is **Tongariki**. Anga Roa (the edition) ships **2026-05-21**.

**What this means for ahu:**

- `ahu`'s `kai.toml` should declare which edition it compiles against. Today (Tongariki) it does not need the field; from Anga Roa onward it should declare it explicitly:
  ```toml
  name = "ahu"
  version = "0.x.y"
  edition = "anga-roa"
  ```
- The kaikai compiler (post-Anga-Roa) will respect the declared edition. A package declared `edition = "tongariki"` will continue to compile against the Tongariki rules even on an Anga-Roa-aware kaikai compiler. This is the contract — upgrade of the language never breaks ahu without ahu choosing to upgrade.
- **For Anga Roa cutover specifically:** ahu's first Anga-Roa-tagged release should be the version of ahu that declares `edition = "anga-roa"` and uses any new Anga-Roa features (e.g. the pipe convention dispatch in #594). Versions before that declaration are pinned to Tongariki semantics regardless of the compiler.

**Reference:**
- `kaikailang-org/kaikai` `docs/editions.md` (canonical policy).
- `kaikailang-org/kaikai` `CLAUDE.md` Tier 1 #4.
- `kaikailang-org/kaikai` `docs/decisions/editions-stability-without-stagnation-2026-05-15.md`.

---

## 2. `#unstable` annotation — mark APIs not yet edition-stable

**Issue:** `lnds/kaikai#602`. **Status: shipped in v0.64.0 (2026-05-15).**

**What it is:** an annotation that ahu can place on a `pub` declaration to say "this is public but the API contract is not edition-locked yet — I reserve the right to change it without an edition bump".

**Syntax** (mirrors `#derive(...)`):

```kai
#unstable
pub type Source[t, e] = { pid: Pid[Demand] }

#unstable
pub fn map[a, b, e](s: Source[a, e], f: (a) -> b / e) : Source[b, e] / Spawn = ...

#unstable
module ahu.stream { ... }  // covers every pub in the module
```

**Consumer-side opt-in** (this is what ahu's *consumers* will need to write):

```toml
[unstable]
ahu = true   # explicit opt-in to use #unstable APIs from ahu
```

Consumers that do not opt in receive a compile warning when they import an `#unstable` declaration. The warning does not fail the build — it documents that the API may shift between releases.

**What ahu should do for Anga Roa:**

1. **Tag the stream/cell/restart-helper APIs as `#unstable`** where their shape is still iterating. Recommendation: mark *every* `pub` in `ahu/stream.kai`, `ahu/cell.kai`, `ahu/restart.kai` as `#unstable` for the Anga Roa release, then remove the annotation case by case as each surface stabilises. This keeps you free to iterate post-release without breaking the edition contract.
2. **Update ahu's README and `docs/design.md`** to call out which modules are `#unstable` at Anga Roa.
3. **Module-level annotation** (`#unstable module ahu.stream { ... }`) is the cleanest way to mark a whole module — use it instead of one `#unstable` per `pub fn` when the whole module is in flux.

**Migration path:** when an API stabilises (say, after Anga Roa lands and you've used Source in henua/manutara for some weeks), drop the `#unstable` from the declaration. From that point onward, the API is edition-stable for the current edition. Downstream consumers stop seeing the warning.

---

## 3. Pipe dispatch becomes convention-based (issue #594)

**Issue:** `lnds/kaikai#594`. **Status: pending lane, will ship before Anga Roa cutover (target days 16–19 of Anga Roa window).**

**Background today (Tongariki):** the kaikai typer hardcodes which head types participate in `|`, `||`, `|?` pipe dispatch. The current table in `head_module_for` knows only `List`. Any other type's pipe support requires editing the kaikai compiler itself.

**What changes in Anga Roa:** the typer uses convention-based dispatch. If a module declares `pub type T[a, e] = ...` and the same module exports `pub fn map[a, b, e](s: T[a, e], f: (a) -> b / e) : T[b, e] / e` (canonical signature), the typer recognises `T` as pipe-dispatch-able automatically. No annotation needed, no compiler change needed.

**What this means for ahu:**

- **`Source[t, e]` becomes pipe-compatible automatically** once #594 lands. The signature ahu already exposes (`stream.map`, `stream.flat_map`, `stream.filter`) will match the canonical shape if it follows:
  ```kai
  pub fn map[a, b, e](s: Source[a, e], f: (a) -> b / e) : Source[b, e] / Spawn
  pub fn flat_map[a, b, e](s: Source[a, e], f: (a) -> Source[b, e] / e) : Source[b, e] / Spawn
  pub fn filter[a, e](s: Source[a, e], p: (a) -> Bool / e) : Source[a, e] / Spawn
  ```
- The receiver MUST be the first parameter. The function MUST be the second. The return MUST be the same head type. If ahu's existing signatures already follow this (verify), no change. If they have a different argument order, that needs adjustment before Anga Roa.
- After #594, downstream code can write:
  ```kai
  source_of_lines("input.txt")
    | parse_int            // dispatches to stream.map
    |? (n) => n > 0        // dispatches to stream.filter
    | (n) => n * 2         // dispatches to stream.map
    |> count               // apply pipe, no dispatch needed
  ```
- Users do NOT need to opt in. The convention is what makes the dispatch work.

**What ahu needs to verify or change:**

1. **Audit ahu's stream / cell APIs for canonical pipe signatures.** Confirm `map`, `flat_map`, `filter` take `(receiver, function)` in that order. If they're inverted or wrapped, fix them before tagging the release.
2. **No annotation required.** Convention is the whole mechanism.
3. **If two modules declare types with the same head name** (e.g. both ahu and henua declare a `Source` type), the typer emits an ambiguity error at the call site. This is unlikely in practice but document the constraint in ahu's design doc.

**Reference:** `lnds/kaikai` `docs/editions.md` "Pipe dispatch rules" section (one of the things the edition contract pins).

---

## 4. LLVM backend remains opt-in in Anga Roa

**Status confirmed 2026-05-15** after Eric/Linus/asu review of the Anga Roa plan.

**Background:** the kaikai LLVM backend (via `--backend=llvm`) was considered as the default for Anga Roa. After measurement, the C backend is faster (1.85s vs 2.48s on `empty.kai` baseline) and more stable. Decision: **C backend remains the default for Anga Roa**. LLVM stays opt-in via `--backend=llvm`. LLVM becomes default in Orongo when "direct emit" (liblld static, no clang shell-out) lands.

**What this means for ahu:**

- ahu's tier1 currently pins `KAI_BACKEND=c` in its Makefile or similar. **You can keep that pin for Anga Roa.** The C backend will be the supported default through this edition.
- The 4 LLVM bugs that ahu surfaced (`#570 spawn_actor`, `#571 lambda info`, `#582 Cancel.raise`, `#587 Link/Monitor`) are all closed, so the LLVM backend works for the patterns ahu exercises. If you want to test ahu's tier1 under LLVM as a forward-looking experiment, that's safe to do, but not required.
- Issue `#575 backend parity CI` (filed 2026-05-14, scheduled for Anga Roa) will add a CI gate to kaikai itself that verifies C ↔ LLVM produce byte-identical runtime behaviour for every fixture. Bugs that ahu's exotic patterns would have surfaced should be caught upstream from now on.

**Migration plan for Orongo:** when LLVM direct emit ships (Orongo), ahu's Makefile can drop the `KAI_BACKEND=c` pin. We'll provide explicit migration notes when the bump is announced.

---

## 5. Cache invalidation across editions (issue #603 subset minimo)

**Issue:** `lnds/kaikai#603`. **Status: pending lane, days 16–17 of Anga Roa window.**

**What it does for kaikai:** the prelude cache (`~/.cache/kaikai/preludes-v1/...`) is namespaced per edition. A cache built by a Tongariki compiler is invalid for an Anga Roa compiler, and vice versa. The hash header carries the edition name + version. The on-disk path includes the edition: `~/.cache/kaikai/preludes-v1/<edition>/<sha>.kab`.

**What this means for ahu:**

- **First compile on a new kaikai version is slow.** That has always been true. With editions, the first compile after an edition bump is also slow — the cache from the previous edition is invalidated. This is expected and acceptable.
- If ahu maintains its own CI cache (e.g. GitHub Actions cache step keyed on the kaikai binary version), the key needs to include the edition name to avoid serving stale cache data after a bump. Recommendation: include `${{ kaikai_edition }}` in the cache key.

---

## 6. Multi-edition compiler dispatch — subset minimo (issue #603)

**Issue:** `lnds/kaikai#603`. **Status: pending lane.**

**What ahu needs to know:** kaikai's compiler reads the `edition` field in `kai.toml` and uses it to route pipe-dispatch-related decisions. Other compiler decisions (parser rules, type system, effect system) still apply uniformly because Tongariki → Anga Roa is additive — no real breaking changes. Multi-edition threading expands when Orongo introduces real breaking changes.

**Action item for ahu:** declare `edition = "anga-roa"` in `ahu/kai.toml` in the Anga-Roa-tagged release. That's the marker.

---

## 7. HTTP server lands in stdlib (issue #605)

**Issue:** `lnds/kaikai#605`. **Status: pending lane.**

**Background:** kaikai's stdlib gains `stdlib/net/http_server` in Anga Roa — a minimal HTTP/1.1 server primitive marked `#unstable`. The shape is a `Http` effect with `serve(addr, handler)` where `handler: Request -> Response / Io`. Routing is pattern match. No DSL, no framework.

**What this means for ahu:**

- ahu probably wraps the HTTP server primitive in something opinionated for use in `manutara` (the web framework, post-Anga Roa). For Anga Roa, ahu does not need to do anything — the primitive lives in kaikai's stdlib.
- If ahu wants to expose its own HTTP-related modules (e.g. an `ahu.web` shim that combines streams + HTTP), build it on top of `stdlib.net.http_server` and mark it `#unstable`.

---

## 8. Demo todo-list integrates ahu + henua + kohau + HTTP (issue #606)

**Issue:** `lnds/kaikai#606`. **Status: pending lane.**

**Background:** kaikai's Anga Roa release will include a demo that exercises the full ecosystem stack: HTTP server (stdlib) → ahu actor for state → henua repository → kohau SQLite persistence. The demo lives in `lnds/kaikai/examples/demos/todo-server/` and is the marketing artefact for the release.

**What this means for ahu:**

- The demo will exercise ahu's `cell` / `restart` / `stream` APIs in a real (if minimal) application. **Bugs and API mismatches surface here.** Plan for 0.5–1 sesión of integration work post-merge of all upstream pieces.
- The demo's `kai.toml` will declare `edition = "anga-roa"` and opt in to `#unstable` APIs from ahu, henua, kohau. This will be the reference for users on how to do the same.

**Action item for ahu:** when the demo lane opens, be available for tight feedback if the integration surfaces an ergonomic gap in ahu's APIs.

---

## 9. Documentation alignment (issue #604)

**Issue:** `lnds/kaikai#604`. **Status: pending lane.**

The kaikai documentation pass (`docs/perceus-honesty-targets.md`, `docs/fibers-honesty-targets.md`, `docs/cache-design.md`) aligns docs with current code reality. Not direct impact for ahu, but if ahu's design doc references any of these (e.g. claims about Perceus behaviour or fiber semantics), verify the references are still accurate after the audit lands.

---

## Summary of what ahu needs to do before Anga Roa cutover

1. **Add `edition = "anga-roa"`** to ahu's `kai.toml` in the Anga-Roa-tagged release.
2. **Mark `pub` APIs in stream/cell/restart with `#unstable`** for the Anga-Roa release. Drop the annotation case by case as each API stabilises.
3. **Audit `map` / `flat_map` / `filter` signatures** in ahu's stream API to confirm canonical `(receiver, function)` argument order. Adjust if needed before convention-based pipe dispatch ships.
4. **Keep `KAI_BACKEND=c` pin** in ahu's tier1 Makefile for Anga Roa. Drop it in Orongo.
5. **Update ahu's README** to call out which modules are `#unstable` and reference the `kai.toml` opt-in for downstream consumers.
6. **Add `${{ kaikai_edition }}` to ahu's CI cache key** to avoid serving stale prelude cache across edition bumps.
7. **Be available for fast integration feedback** when the todo-server demo (kaikai #606) opens — ahu's ergonomic gaps surface there.

---

## Reference timeline

- **2026-05-15** — Tongariki declared as current edition; editions adopted as Tier 1 principle.
- **2026-05-15** — `#unstable` shipped (kaikai v0.64.0).
- **2026-05-16–20** — Pipe convention dispatch, multi-edition dispatch, HTTP server, backend parity CI, docs honesty audit, integrated demo land in kaikai.
- **2026-05-21** — Anga Roa edition cutover. ahu releases Anga-Roa-tagged version the same week.

---

## Open questions for ahu maintainer

1. Does ahu want `module-level #unstable` for entire `ahu/stream.kai`, or per-declaration? Per-declaration is more granular; module-level signals "this whole area is in flux".
2. Does ahu wish to provide a `kai migrate --from tongariki --to anga-roa` for its own consumers? kaikai itself does not need one (Tongariki → Anga Roa is additive), but ahu may have internal API renames worth automating.
3. Does ahu want to publish its own `edition` concept for ahu users, or piggyback on kaikai's edition?

Hand to ahu's maintainer after the pipe convention dispatch lane (kaikai #594) lands — that's the moment the convention surface is concrete enough to act on items 3 + verify API shape.
