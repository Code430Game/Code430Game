# Change: Add tone modes and content tagging

**Status: PROPOSED, not approved.** Written at the human's request. The tagging rules are adopted into AGENTS.md now so the first content is authored correctly; the runtime switch is scheduled with Phase 4 (packs), not before.

## Why
The same city can tell very different stories: a sanitized version for a modern or younger audience, the raw street reality of GTA III–IV, or a neon dystopia where everything is for sale. The base game should not pick one tone for everyone. If every content item is tagged from the first pack and can carry variants, a tone mode becomes a data switch instead of a fork of the game. Billboards are the smallest visible proof: the same board shows a good-morning ad, a satirical ad, or a wild cyberpunk implant ad, or goes blank.

## What Changes
- New capability `content-modes`.
- A shared content-descriptor list in `docs/pack-format/content-descriptors.v0.json` (for example `violence`, `gore`, `drugs`, `sex_work`, `profanity`, `crime`, `horror`).
- Mode definitions as data (`docs/pack-format/tone-mode.schema.v0.json`): a mode has an id, a set of allowed descriptors, mechanic flags (for example `violence: false`), and a variant key. Base game ships `clean`, `gritty` (default), and `dystopia`.
- Every authored content item in pack data carries `descriptors[]` and may carry `variants{}` keyed by mode, with a required fallback.
- A `ContentMode` autoload that exposes the active mode, `allows(descriptor)`, and `pick_variant(item)`. Selected in settings; in co-op it is set by the host for the whole session.
- Pack manifests declare `supported_modes[]` and `max_descriptors[]` so the registry can filter and the game can refuse or warn when a pack does not support the active mode.
- First tone-aware content: a billboard system reading ad definitions from a pack with per-mode variants, plus a small first-party ad set for all three modes.
- **Not in this change:** rewriting mechanics for violence-free play (weapons, wanted level). Mechanic flags are exposed; systems adopt them in their own changes.

## Impact
- Affected specs: `content-modes` (new). Pack format v1 (Phase 4) gains descriptor and variant fields; the registry (Phase 6) reads `supported_modes`.
- Affected code: `game/core/content_mode.gd` (new), `game/world/billboards/` (new), `tools/` pack validator (descriptor and variant checks), `docs/pack-format/`.
- Content policy is unchanged: the mode system never expands what is allowed, it only narrows it.
