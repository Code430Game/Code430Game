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

## Talk radio
Speech as chip babble, in the spirit of the "animalese" approach: no words, only syllables that
carry a voice's rhythm and intonation.
- **Syllable channel.** A track may have one `talk` channel whose tokens are syllables
  (`ba`, `ko`, `ri`, `.` for a pause, `?` and `!` marking a phrase's contour), with a `voice`:
  base pitch, pitch range, and speaking rate.
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
`VehicleAudio` feeds its engine and tyre generators only while the car is driven, so the parked
car makes no sound. While nobody drives, the generators run dry. The fix restarts any voice
that is no longer playing when a driver gets in, and `Radio` starts on the same signal, so both
come back together. The test drives in, out and back in through `Player` and checks
`engine_running()` and that the engine player is playing.
