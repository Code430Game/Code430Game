# Change: Car radio with chip music

**Status: proposed 2026-10-02 (human asked for a slate of proposals that other agents can pick up in fresh contexts). Human's brief: "could we add radios? With simple SNES / vintage style music in the cars?"**

## Why
Driving is the core loop and it is silent apart from the engine. A radio gives every car a
mood and the city a voice, and vintage chip music fits the game's hand-made look. Synthesising
it in-engine from note data keeps the rule from `add-sound`: no audio assets, no licensing, and
music becomes something a data-only pack can ship.

## What Changes
- **Chip synth.** `game/core/audio/chip_player.gd` extends `Synth` with a four-channel tracker
  voice on one `AudioStreamGenerator` stream: two pulse channels with selectable duty, one
  triangle, one noise, each with a simple attack, decay, sustain, release envelope, vibrato and
  per-step volume. Tempo, steps per beat and loop points come from the track.
- **Tracks as data.** `docs/pack-format/music.schema.v0.json`: a track is a tempo, instruments
  and up to four channels of step patterns written as note strings (`C4 . E4 ~ G4 . . .`). The
  first-party set lives in `game/core/audio/radio/music.v0.json`: eight short loops of 16 to 32
  bars in a few styles (driving, lounge, jingle, menace).
- **Stations as tagged content.** `docs/pack-format/radio.schema.v0.json`: a station has
  descriptors and per-mode `variants` with a required `fallback`; a variant is a name, a tagline
  shown on the HUD when tuned in, and an ordered track list. Base set in
  `game/core/audio/radio/radio.v0.json`: three stations, two or three loops each, plus Off.
  Names and taglines are invented, never real stations or parodies of another studio's. Packs of
  any type may ship `radio.v0.json` and `music.v0.json`; the loader merges their stations after
  the base set, and `pack_tools` validates both files.
- **In the car.** The radio starts when a player enters a car and pauses when they leave; the
  last station is remembered in settings. Cycle stations with D-pad left or the R key while
  driving (D-pad left is free; up is headlights, down is the camera). Tuning shows the station
  name and tagline on the HUD for a few seconds. A `Music` bus with its own volume in settings,
  under Master so `--mute` still silences it.
- **Other cars** leak a faint, low-passed version of their station when within a few metres of
  a player on `high`; off on `deck`.
- **Not in this change:** DJ speech, news or adverts between tracks, pedestrians' music, a
  music player on foot, exporting tracks as files, radio stations tied to vehicles.

## Co-op authority
The radio is local to each player: station choice, playback position and volume are never
replicated. Nearby leak on `high` plays the local peer's own copy of the station a remote car's
driver last broadcast in the player state (one byte), so peers hear something plausible without
synchronising audio.

## Tone
Stations are content items: `ContentMode.pick_variant` selects the name, tagline and track list
for the active mode, and a station with nothing allowed is skipped in the cycle. The track data
itself is tone-free.

## Impact
- Affected specs: `audio` (new requirement).
- Affected code: `game/core/audio/chip_player.gd` (new), `radio.gd` (new: station list, cycle,
  memory, HUD hook), `radio/music.v0.json` and `radio/radio.v0.json` (new), `synth.gd`
  (envelope and oscillator helpers), `game/default_bus_layout.tres` (Music bus),
  `game/core/settings/settings.gd` (music volume, last station), `game/actors/player/player.gd`
  (enter and exit hooks), `game/scenes/play_testbed.gd` (wiring, `--radio=<station>` for
  screenshots), `game/project.godot` (`radio_cycle`), `game/ui/` (tune-in toast),
  `docs/pack-format/music.schema.v0.json`, `radio.schema.v0.json`, `tools/pack_tools`, tests.
- Performance: one more generator stream at 22 kHz filled from GDScript, four oscillators per
  sample; expected inside the 0.85 ms the four existing voices cost together. Deck measured.
