## Context
VISION.md pillar 7 ("One world, many tones") and the AGENTS.md section "Tone modes and content tagging" set the intent. This design makes it concrete enough that Phase 4 pack data can be authored against it, and that Phase 2–3 gameplay code can check mode flags without a rewrite later.

## Goals / Non-Goals
- Goals: one base game, author-chosen tone, no forks; graceful degradation when a variant is missing; content never leaks upward (a `clean` session never shows `gritty` content); registry-visible mode support per pack.
- Non-Goals: automatic content generation per mode, rating-board compliance, per-player modes inside one co-op session, a content-moderation pipeline for the registry.

## Decisions
- **Modes are data, not code.** A mode file lists allowed descriptors, mechanic flags, and its variant key. Adding a mode is a pack-level act. Base modes:
  - `clean`: allows none of `gore`, `drugs`, `sex_work`, `profanity`; `violence` allowed only as `stylized`; flags `violence: false`, `lethal_weapons: false`.
  - `gritty` (default): allows everything in the content policy.
  - `dystopia`: allows everything in the content policy, adds descriptor `dystopia_tech` so cyberpunk-only content (implants, corporate surveillance) appears only here.
- **Descriptors are a closed list with levels.** Each descriptor is `none | mild | strong`. A mode allows a maximum level per descriptor. A closed list keeps validation simple and lets the registry filter.
- **Variants are keyed by mode with a required fallback.** Example ad definition:
  ```json
  {
    "id": "ad.energy_drink",
    "descriptors": {"profanity": "mild"},
    "variants": {
      "clean": {"texture": "ads/good_morning.png", "descriptors": {}},
      "dystopia": {"texture": "ads/implant_clinic.png", "descriptors": {"dystopia_tech": "strong"}},
      "fallback": {"texture": "ads/energy_drink.png"}
    }
  }
  ```
  Selection: use the variant for the active mode if present and allowed; else the fallback if allowed; else the item is hidden (a billboard goes blank, an NPC archetype is not spawned, a line of dialogue is skipped and logged).
- **Leak prevention is a validator rule, not a runtime hope.** The pack validator rejects a variant whose descriptors exceed the mode it is keyed to, and warns when an item has no variant or fallback allowed in a mode the pack claims to support.
- **Runtime access is one autoload.** `ContentMode.current`, `ContentMode.allows(descriptor, level)`, `ContentMode.pick_variant(item)`. Gameplay systems call these; they never compare mode ids directly.
- **Mechanic flags are exposed now, adopted later.** `violence`, `lethal_weapons`, `drug_use`, `sex_work_services`. Each system that touches them adopts the flag in its own change and states the behavior in both `deck` and `high` (as with rendering) and in every base mode.
- **Billboards first.** A `Billboard` node reads an ad pool from the active map or story pack and picks a variant per mode, deterministic per billboard id and session seed. This is the smallest end-to-end proof and the one the human described.
- **Co-op.** Mode is session state owned by the host (see `add-coop-multiplayer`).

## Alternatives considered
- Separate packs per tone: forks the content, triples authoring effort, and makes co-op pack matching worse. Rejected.
- Free-form tags instead of a closed descriptor list: flexible but unvalidatable. Rejected for v0; the list can grow through a pack-format change.
- Rating-board style age ratings: too coarse for authors and not something an open registry can certify. Descriptors give authors and players finer control.

## Risks / Trade-offs
- Authors skip variants and everything falls back to `gritty`-flavored content in `clean`. Mitigation: validator warnings, registry shows which modes a pack really supports.
- Descriptor list too small or wrong. Mitigation: versioned schema; additions are a pack-format change with a migration note.
- "Clean" is not a safety guarantee; it is an authoring convention. Say so in creator docs.

## Migration Plan
- No shipped pack format yet, so no migration. Fields land in pack format v1 from the start.

## Open Questions
- Mode names: `clean` / `gritty` / `dystopia` are placeholders. Confirm or rename before creator docs are written.
- Should `clean` remove crime entirely or keep stylized crime (car chases without blood)? Recommended: keep stylized crime; it is still a crime game.
- Which descriptors need a `mild` level at all? Proposed: `violence`, `profanity`, `drugs`; the rest are none or strong.
