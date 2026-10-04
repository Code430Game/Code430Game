# Change: Car radio with chip music

**Status: revised 2026-10-03 (human: "Lets do 3 music stations and a 4th. I am really thinking each would just be a loopable file so they're not full stations ... mario, zelda, and a darker zelda dungeon style. And then we can try the talk radio and if it sounds good we can keep it ... probably more than a couple seconds so it's not too repetitive"; and "when you leave the car it turns off, but when you get back in the engine audio does not resume ... This would need to be expanded with the car radio ticket"). First proposed 2026-10-02 ("could we add radios? With simple SNES / vintage style music in the cars?"). Approved 2026-10-04 (human: "I want to test the music though").**

## Why
Driving is the core loop and it is silent apart from the engine. A radio gives every car a
mood, and vintage chip music fits the game's hand-made look. Synthesising it in-engine from
note data keeps the rule from `add-sound`: no audio assets, no licensing. Getting in and out of
the car is also where the engine sound breaks today: it does not come back after the player
gets back in, so the radio's enter/exit hooks fix that too.

## What Changes
- **Chip synth.** `game/core/audio/chip_player.gd` extends `Synth` with a four-channel tracker
  voice on one `AudioStreamGenerator`: two pulse channels with selectable duty, one triangle,
  one noise, each with an attack, decay, sustain and release envelope, vibrato and per-step
  volume. Timing comes from the sample clock, so it never drifts with frame rate.
- **Four stations and Off, each a single loop.** Not full stations with playlists: one original
  loop per station, 30 to 60 seconds long (16 to 32 bars), written so the end runs back into
  the start without a seam.
  - **Bright platformer:** bouncy major-key lead, walking bass, shuffle drums, in the spirit of
    16-bit platform games.
  - **Overworld adventure:** a heroic, open melody over arpeggios, in the spirit of 16-bit
    adventure-game overworlds.
  - **Dungeon:** slow, minor, sparse; low drones, a creeping bass line and echoing pulses.
  - **Talk radio (trial):** two hosts' "speech" as chip babble. Syllables are synthesised with
    speech-like pitch contours and rhythm but no real words, the hosts take turns, and a short
    jingle plays between segments, as a 30 to 60 second loop. It stays only if it sounds good on
    the Deck (gate 3.2); otherwise it is removed before the change is archived.
  - **Off.**

  All music is composed for this project. It is in the *style* of those games and never
  reuses their melodies, names, sound effects or characters, the same rule `AGENTS.md`
  applies to Rockstar's games. Station names and taglines are invented.
- **Tracks as data.** `docs/pack-format/music.schema.v0.json`: a track is a tempo, instruments
  and up to four channels of step patterns written as note strings (`C4 . E4 ~ G4 . . .`); talk
  radio adds a syllable channel. The tracks live in `game/core/audio/radio/music.v0.json` and
  the four stations in `radio.v0.json`; `pack_tools` validates both.
- **In the car.** The radio starts when a player gets in and pauses when they get out; the last
  station is remembered in settings. Cycle stations with D-pad left (or R) while driving; the
  station name and tagline show on the HUD for a few seconds. A `Music` bus with its own volume
  in settings, under Master so `--mute` still silences it.
- **Engine sound after getting back in.** `VehicleAudio` restarts its engine and tyre voices
  when a driver gets in. The voices stop feeding their generators while nobody drives, and they
  do not start again on their own. A test drives in, out and back in and checks the engine is
  audible.
- **Not in this change:** stations defined by packs, several tracks per station, a DJ with real
  speech, news or adverts, music on foot, other cars' radios heard nearby, exporting tracks as
  files.

## Co-op authority
The radio is local to each player: station choice, playback position and volume are never
replicated.

## Tone
Stations are content items: each carries content descriptors and a `fallback` variant (name,
tagline, track). `ContentMode.pick_variant` selects it for the active mode; with no
mode-specific variants yet, every mode gets the fallback. The music itself is tone-free.

## Impact
- Affected specs: `audio` (Car Radio added; the engine scenario gains getting back in).
- Affected code: `game/core/audio/chip_player.gd` (new), `radio.gd` (new: stations, cycle,
  memory, HUD hook), `radio/music.v0.json` and `radio/radio.v0.json` (new), `synth.gd`
  (envelope and oscillator helpers), `vehicle_audio.gd` (restart on entry),
  `game/default_bus_layout.tres` (Music bus), `game/core/settings/settings.gd` (music volume,
  last station), `game/actors/player/player.gd` (enter and exit hooks),
  `game/scenes/play_testbed.gd` (wiring, `--radio=<station>`), `game/project.godot`
  (`radio_cycle`), the HUD toast, `docs/pack-format/music.schema.v0.json`,
  `radio.schema.v0.json`, `tools/pack_tools`, `docs/controls.md`, tests.
- Performance: one more generator stream at 22 kHz filled from GDScript, four oscillators per
  sample, while driving with the radio on. Expected inside the 0.85 ms the existing voices cost
  together; measured on the Deck.
