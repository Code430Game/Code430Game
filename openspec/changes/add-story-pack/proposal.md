# Change: First story pack with one mission

**Status: proposed 2026-10-02 (human asked for a slate of proposals that other agents can pick up in fresh contexts). Depends on `add-pack-loader`: the pack format v1 `story` section and the content registry must exist first.**

## Why
Phase 4 ends with "first story pack with one complete mission". Until a mission runs from pack
data, the platform promise is untested: a story author has no schema to write to, no runner to
evaluate it, no way to place a character on the map or put a marker on it. One courier run,
declared entirely in JSON, proves the whole path and gives the city its first reason to drive
somewhere.

## What Changes
- **Mission schema** `docs/pack-format/mission.schema.v1.json`: `id`, `title`, `descriptors`,
  `variants` keyed by mode plus `fallback` (title, giver lines, objective texts, item name), a
  `giver` (character profile or `random` with a seed, local `x`/`z`, facing), an ordered
  `objectives[]` of typed steps (`go_to`, `enter_vehicle`, `follow`, `deliver`, `survive_until`),
  each with a position and radius where it applies, HUD text and a marker, and `fail` conditions
  (`deadline_s`, `abandon_radius_m`). No rewards yet.
- **`MissionRunner`** (`game/core/missions/mission_runner.gd`, a node the testbed adds): loads
  `items("missions")` from the registry, places each mission's giver through the character
  pipeline (`CharacterRig` with the profile, idle, an interact prompt within 2.5 m like vehicle
  entry), opens a text dialogue box on interact (`game/ui/missions/dialogue_box.gd/.tscn`,
  controller-driven: accept to continue, cancel to decline), then evaluates objectives against
  world state each physics tick: player positions from `Players.all()`, driving state from
  `Player.is_driving()`, traffic agents for `follow`, a timer for `survive_until` and the
  deadline. Success and failure show a HUD line for a few seconds; the mission is offered again
  by the giver.
- **Markers:** the current objective draws on the minimap and the overview map
  (`map_renderer.gd` gains an overlay layer; `minimap.gd` and `overview_map.gd` draw it) and as
  a world marker (a tall thin beam, `Label3D` distance text) that is visible from the deck
  preset's draw distance. The HUD shows objective text and the countdown.
- **First story pack** `packs/code430-story-first-ride` (type `story`, v1, depends on
  `code430.ottawa-centretown`): one mission, "First Ride": meet the giver in the ByWard Market,
  take the package, get into a car, deliver it south of the Queensway before the deadline.
  Variants: `clean` a bakery delivery to a birthday party; `gritty` (fallback) a no-questions
  package, `crime: mild`; `dystopia` a black-market implant courier run, `dystopia_tech: mild`,
  `crime: mild`. Descriptors mean the mission exists in all three modes with different words.
- **Co-op:** the host runs mission state (offered, active, step index, timer) and sends it to
  peers reliably on every change; any peer inside an objective's radius completes that step; the
  dialogue is shown to the peer who talked to the giver, others see the HUD line. A mission
  with no allowed variant for the session mode is not placed at all.
- **Not in this change:** mission chains and unlocks, checkpoints and retry from a step,
  rewards or economy, cutscenes, voice, NPC vehicles that drive for the player, mission scripting
  beyond the typed steps, an in-game mission list.

## Impact
- Affected specs: `missions` (new), `wayfinding` (new requirement: Mission Markers).
- Affected code: `game/core/missions/mission_runner.gd`, `mission.gd` (parsed definition and
  step evaluators), `game/ui/missions/dialogue_box.gd/.tscn`, `mission_hud.gd` (new),
  `game/ui/map/map_renderer.gd`, `minimap.gd`, `overview_map.gd`, `game/actors/character/`
  (a placed idle NPC built from `CharacterRig`), `game/scenes/play_testbed.gd` (`--mission=id`
  starts a mission at spawn for screenshots), `game/core/net/world_sync.gd` (mission state RPC),
  `docs/pack-format/mission.schema.v1.json` and README, `tools/pack_tools/validate.py` (mission
  files through the generic descriptor checks plus position-inside-map-bbox), `packs/code430-story-first-ride/`,
  tests (`test_missions.gd`, validator tests).
- Performance: one placed NPC with a rig, one marker, a few distance checks per tick. No
  measurable cost expected; Deck measured.
- Authority: host-owned mission state, as `coop-session` Host-Owned World already requires.
  Tone: variants through `ContentMode.pick_variant`; the runner never reads mode ids.
