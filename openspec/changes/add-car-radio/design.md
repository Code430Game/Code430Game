# Design: chip music radio

## Pattern format
A track is a grid of steps. Each channel is a string of tokens separated by spaces, one token
per step: a note (`C4`, `F#3`, `Bb2`), `~` to hold the previous note, `.` for a rest, and an
optional volume suffix (`C4:8` on a 0..15 scale). Bars are only a convention for authors; the
player reads the token list. Channels may have different lengths and loop independently, which
is how a two-bar bass line sits under an eight-bar lead.

```json
{"tracks": [{
  "id": "nightdrive", "title": "Night Drive", "tempo_bpm": 112, "steps_per_beat": 4,
  "instruments": {
    "lead":  {"wave": "pulse", "duty": 0.25, "attack": 0.01, "decay": 0.08, "sustain": 0.6, "release": 0.06, "vibrato_hz": 5, "vibrato_cents": 10},
    "pad":   {"wave": "pulse", "duty": 0.5,  "attack": 0.05, "decay": 0.2,  "sustain": 0.4, "release": 0.2},
    "bass":  {"wave": "triangle", "attack": 0.005, "decay": 0.1, "sustain": 0.8, "release": 0.05},
    "drums": {"wave": "noise", "attack": 0.001, "decay": 0.06, "sustain": 0.0, "release": 0.02}},
  "channels": [
    {"instrument": "lead",  "pattern": "E4 ~ G4 ~ B4 ~ ~ . A4 ~ G4 ~ E4 ~ ~ ."},
    {"instrument": "pad",   "pattern": "E3 ~ ~ ~ ~ ~ ~ ~ C3 ~ ~ ~ ~ ~ ~ ~"},
    {"instrument": "bass",  "pattern": "E2 . E2 . G2 . A2 . C2 . C2 . D2 . E2 ."},
    {"instrument": "drums", "pattern": "C5:15 . C3:6 . C4:12 . C3:6 . C5:15 . C3:6 . C4:12 . C4:12 C3:6"}]}]}
```

Noise channels use the note only for pitch of the noise band (kick low, hat high). Four channels
is a hard cap, the SNES-via-NES feel the brief asks for and a bound on fill cost.

## Synth
`ChipPlayer` fills one generator at `Synth.MIX_RATE` (22050 Hz) in `_process`, mixing four
channel oscillators: pulse by phase against duty, triangle by folded phase, noise from
`Synth.noise` through a one-pole filter set by the note. Envelopes are per channel in seconds;
a new note restarts the envelope. Output is clamped and scaled by a master gain so four full
channels do not clip. Every step boundary is computed from the sample clock, so timing does not
drift with frame rate. Pausing the game pauses the fill. The track loops at its end; a station
advances to the next track at a loop end, so switching cars mid-track resumes where it was.

## Stations and packs
```json
{"stations": [{
  "id": "code430.base.drive", "descriptors": {},
  "variants": {
    "fallback": {"name": "Drive 430", "tagline": "Four to the floor, all night.", "tracks": ["nightdrive", "overpass"]},
    "dystopia": {"name": "Drive 430 ∆", "tagline": "Sponsored by nobody you can sue.", "tracks": ["nightdrive", "overpass", "static_city"],
                 "descriptors": {"dystopia_tech": "mild"}}}}]}
```
`Radio` builds the station cycle at load: base stations from `game/core/audio/radio/`, then
every loaded pack's `radio.v0.json`; tracks are a flat id space with pack ids prefixed to avoid
clashes. A pack may add stations or tracks but never remove base ones. `pick_variant` runs when
the mode changes and the cycle is rebuilt.

## Controls and memory
`radio_cycle` is D-pad left (joypad button 13) and R, read only while `Player.is_driving()`.
Settings gain `[audio] music_volume` and `[radio] station`. Off is a station in the cycle so one
button covers everything. The tune-in toast reuses the pause menu's status label style.

## Leak on high
`VehicleAudio` on `high` adds a second, quiet `ChipPlayer` for the nearest remote or traffic car
within `leak_radius_m` playing that car's station (traffic cars pick a station from their colour
index; remote players send theirs), low-passed and attenuated by distance. On `deck` this is
skipped entirely, declared in `presets.json` as `radio_leak: false`.
