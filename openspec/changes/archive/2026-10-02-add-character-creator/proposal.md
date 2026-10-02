# Change: Character creator

**Status: proposed 2026-10-01 (human brief in docs/backlog.md: random first start, tweak that body, saved presets including "last created").**

## Why
The player is a blue capsule. A simple blocky person with a face, clothes and a few knobs to
turn makes the on-foot player and the other peers in co-op recognisable, and nothing should
ever block play: the first start hands the player a random character and gets on with it.

## What Changes
- **Profile:** a small dictionary (skin, hair style and colour, top, bottom, shoes, hat,
  height, build) with palettes, random generation and clamping (`CharacterProfile`).
- **Body:** one vertex-coloured ArrayMesh built from the profile (`CharacterMesh`): legs,
  shoes, torso, arms, hands, head with eyes, hair, hat; height scales the body, build scales
  its width. The on-foot player and remote peers wear it.
- **Store:** `user://characters.json` holds the last created character and named presets
  (`CharacterStore`). First start with no file: a random character is created, applied and
  saved as the last character.
- **Creator screen:** from the pause menu ("Character"): rows adjusted with left/right,
  live preview in a small viewport, Randomise, load a preset, save the current body as a
  new preset, delete a preset, Done. The live player updates as rows change; Done saves
  "last" and, in co-op, sends the profile to the other peers.
- **Co-op:** the profile travels with the hello/welcome; changes mid-session are broadcast.
- **Not in this change:** animation, pedestrians wearing profile bodies, typed preset names.

## Impact
- Affected specs: `player-character` (new requirements).
- Affected code: `game/actors/character/*` (new), `game/ui/character/*` (new),
  `player.gd/.tscn`, `remote_player.gd`, `session.gd`, `player_sync.gd`, `pause_menu`,
  `play_testbed.gd`, tests, `docs/controls.md`.
- Performance: one extra mesh per player, one draw call; nothing per frame.
