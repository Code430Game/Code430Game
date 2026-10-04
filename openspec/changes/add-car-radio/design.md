# Design: chip music radio

## Pattern format
A track is a grid of steps. Each channel is a string of tokens separated by spaces, one token
per step: a note (`C4`, `F#3`, `Bb2`), `~` to hold the previous note, `.` for a rest, and an
optional volume suffix (`C4:8` on a 0..15 scale). Bars are only a convention for authors; the
player reads the token list. Channels may have different lengths and loop independently, which
is how a two-bar bass line sits under an eight-bar lead; the track's length is its longest
channel, and the shorter ones must divide it so everything lines up at the loop point.

```json
{"tracks": [{
  "id": "hilltop", "title": "Hilltop Hop", "tempo_bpm": 132, "steps_per_beat": 4,
  "instruments": {
    "lead":  {"wave": "pulse", "duty": 0.25, "attack": 0.01, "decay": 0.08, "sustain": 0.6, "release": 0.06, "vibrato_hz": 5, "vibrato_cents": 10},
    "pad":   {"wave": "pulse", "duty": 0.5,  "attack": 0.05, "decay": 0.2,  "sustain": 0.4, "release": 0.2},
    "bass":  {"wave": "triangle", "attack": 0.005, "decay": 0.1, "sustain": 0.8, "release": 0.05},
    "drums": {"wave": "noise", "attack": 0.001, "decay": 0.06, "sustain": 0.0, "release": 0.02}},
  "channels": [
    {"instrument": "lead",  "pattern": "E5 ~ G5 . C6 ~ ~ . B5 ~ G5 ~ E5 ~ ~ ."},
    {"instrument": "pad",   "pattern": "C4 ~ ~ ~ ~ ~ ~ ~ G3 ~ ~ ~ ~ ~ ~ ~"},
    {"instrument": "bass",  "pattern": "C3 . G2 . C3 . G2 . F2 . C3 . G2 . B2 ."},
    {"instrument": "drums", "pattern": "C5:15 . C3:6 . C4:12 . C3:6 . C5:15 . C3:6 . C4:12 . C4:12 C3:6"}]}]}
```

Noise channels use the note only for the pitch of the noise band (kick low, hat high). Four
channels is a hard cap: the 16-bit chip feel the brief asks for, and a bound on fill cost.

## The loops
One loop per station, 30 to 60 seconds: at 100 to 140 bpm with four steps a beat that is 16 to
32 bars, enough that a drive across a few blocks does not hear the same phrase twice in a row.
Each loop is written so its last bar leads back into its first: the lead resolves on a pickup
into bar 1, the bass lands on the root, and the drums end on a fill. At the loop point the player
does not reset envelopes that are still sounding, so a note held across the seam rings on and
nothing clicks. A test renders two passes and checks there is no step discontinuity in the
samples at the seam.

| Station | Mood | Tempo, key | Instruments |
|---|---|---|---|
| Bright platformer | bouncy, cheerful | ~132 bpm, major | 12.5 % pulse lead with vibrato, 50 % pulse chords, triangle walking bass, shuffle noise drums |
| Overworld adventure | heroic, open | ~112 bpm, major with a borrowed minor chord | 25 % pulse fanfare lead, arpeggiated pulse, triangle bass, marching snare |
| Dungeon | creeping, cold | ~84 bpm, minor | triangle drone, slow pulse figure with echo (a delayed quieter repeat), sparse low noise hits |
| Talk radio (trial) | chatty | speech rhythm | two syllable voices and a jingle (below) |

All of it is composed here. Being in the style of a genre is fine; quoting another game's
melody, even a few notes of a famous phrase, is not, and the names and taglines are invented.

## Rendering once, playing a sample
Rendering a loop in GDScript costs about 9% of real time on the Mac's M1, so filling a generator
every frame would cost roughly 1.5 ms a frame there and several on the Deck. Instead `Radio`
renders each station's loop once on a `WorkerThreadPool` task when the radio first needs it,
into an `AudioStreamWAV` (16-bit mono, 22,050 Hz, about 2.5 MB a loop) with forward looping
over exactly one pass. Playback then costs what any sample costs. To make the wrap match the
loop's start, the render runs a pass and keeps the second one, so the echo tail and envelopes
at the end of the kept pass are what a real repeat would hand to its start. `ChipPlayer`'s
generator path stays for tests and short previews.

## Talk radio
Speech as chip babble, in the spirit of the "animalese" approach: no words, only syllables that
carry a voice's rhythm and intonation.
- **Talk object.** A talk track has a `talk` object instead of note channels' melody: named
  `voices` (base pitch, pitch range, syllables per second) and a list of `phrases`, each a voice
  and a text of syllables (`ba ko ri`, with `.` a pause and `?` or `!` ending a phrase to set its
  contour). Its music channels carry the jingle.
- **Synthesis.** Each syllable is a short burst: a noise consonant (a few milliseconds of
  filtered noise, its band chosen by the consonant) into a pulse or triangle vowel whose pitch
  glides along the phrase contour (falling for a statement, rising for `?`, a jump for `!`). The
  vowel's duty cycle changes with the vowel letter so `a`, `o` and `i` sound different.
- **Two hosts.** Two voices, one lower and slower, one higher and quicker, take turns phrase by
  phrase, with short pauses and the odd overlap ("laughter" as a run of rising syllables).
- **Segments.** Two or three exchanges, then a three-second jingle on the music channels, then
  the next exchange, looping at 30 to 60 seconds.

Talk radio is a trial: if it does not sound good on the Deck (gate 3.2), it is removed before
the change is archived, and the cycle is three music stations and Off.

## Stations
```json
{"stations": [{
  "id": "code430.base.hilltop", "descriptors": {},
  "variants": {"fallback": {"name": "Hilltop FM", "tagline": "Jump to it.", "track": "hilltop"}}}]}
```
`Radio` reads the four stations from `game/core/audio/radio/radio.v0.json` at load, in file order,
and adds Off at the end of the cycle. `ContentMode.pick_variant` picks each station's variant when
the mode changes; with only `fallback` today, every mode hears the same thing.

## Controls and memory
`radio_cycle` is D-pad left (joypad button 13) and R, read only while the local player drives and
the tree is not paused (the same rule as the D-pad camera and headlights). Settings gain
`[audio] music_volume` and `[radio] station`. The tune-in toast reuses the pause menu's status
label style.

## Getting back in
`VehicleAudio` was created once, under the car the player starts in. A car taken later (any
traffic car) had no engine voice at all, which is the silence the human heard after getting out
and into another car; getting back into the first car worked. Now one `VehicleAudio` serves the
local player: `attach(car)` on every entry reparents it under that car, follows that car's
collisions, and restarts any voice that stopped while nobody drove (headless tests do not show a
starved generator stopping, but a real audio device may). `Radio` starts on the same entry
signal. The full-testbed test gets out and back into the same car, and out and into another car,
and checks the engine is running and its player playing each time.
