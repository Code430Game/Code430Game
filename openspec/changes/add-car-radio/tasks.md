## 1. Engine fix and synth
- [x] 1.1 Engine sound after getting back in: a test drives in, out and back in and finds the engine voice silent (reproducing the human's report), then `VehicleAudio` restarts its voices on entry and the test passes
  - Reproduced: back into the same car the engine resumed; into a different car it was silent, because the engine voice lived only on the starting car. `VehicleAudio.attach(car)` now follows the player into whichever car they take and restarts stopped voices; `test_testbed_vehicle_audio.gd` covers both cases.
- [x] 1.2 `ChipPlayer`: four-channel tracker voice on one generator stream, envelopes, vibrato, note parsing, sample-clock timing; tests on note frequencies, step timing, a rendered loop's RMS under the clip ceiling, and no click at the loop point
  - Split as `ChipSong` (renders a track to samples; all tests run on it, no audio device) and `ChipPlayer` (feeds a generator on the Music bus). `test_chip_song.gd`: note frequencies, tokens, steps on the sample clock, a pulse A4 at 440 Hz, a dense four-channel loop under the clip ceiling, no envelope jump across the loop seam, echo.
- [ ] 1.3 `music.schema.v0.json` (with the talk syllable channel) and `radio.schema.v0.json`; `pack_tools` validates both; tests

## 2. Stations
- [ ] 2.1 Three music loops, 30 to 60 s each: bright platformer, overworld adventure, dungeon. Original melodies; checked by ear on the Mac and against the no-reuse rule
- [ ] 2.2 Talk radio (trial): syllable synthesis with speech-like pitch contours, two hosts taking turns, a jingle between segments, as a loop
- [ ] 2.3 `Radio`: stations and Off, cycle on D-pad left or R while driving, remembered station, Music bus and volume, start on entry and pause on exit, tune-in toast; `radio_cycle` action and input-map test; `--radio=<station>` testbed flag; tests in `test_audio.gd`
- [ ] 2.4 Mac run: each station recorded for a minute through a car swap; the station resumes after getting back in, and so does the engine

## 3. Verification
- [ ] 3.1 Deck benchmark on the usual autodrive route with the radio playing: generator fill inside render CPU and no frame regression
- [ ] 3.2 **Stop: human drives on the Deck, cycles the stations, and decides whether talk radio stays**
