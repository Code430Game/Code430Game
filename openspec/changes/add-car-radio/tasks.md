## 1. Synth and data
- [ ] 1.1 `ChipPlayer`: four-channel tracker voice on one generator stream, envelopes, vibrato, note parsing; tests on note frequencies, step timing from the sample clock, and a rendered loop's RMS staying under the clip ceiling
- [ ] 1.2 `music.schema.v0.json` and `radio.schema.v0.json`; `pack_tools` validates both and station variants against the modes; tests
- [ ] 1.3 First-party content: eight loops and three stations with fallback and dystopia variants in `game/core/audio/radio/`; names checked against the no-real-stations rule

## 2. Game
- [ ] 2.1 `Radio`: station cycle from base and packs, `pick_variant` on mode change, Off, remembered station, Music bus and volume setting; `radio_cycle` action and input-map test; tests in `test_audio.gd`
- [ ] 2.2 Start on entering a car, pause on exit, tune-in toast with name and tagline; `--radio=<station>` testbed flag; leak voice on `high` only
- [ ] 2.3 Mac run with the radio on through a car swap, confirming the track resumes

## 3. Verification
- [ ] 3.1 Deck benchmark: the bus-round night run with the radio playing; generator fill time inside render CPU and frame avg against 9.9 ms / p99 13.3
- [ ] 3.2 **Stop: human drives with the radio on the Deck and cycles the stations**
