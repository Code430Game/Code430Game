## 1. Synthesis
- [x] 1.1 `synth.gd`: generator stream helpers (tone, noise, envelope); tests on sample counts and pitch mapping
- [x] 1.2 Engine, tyre, ambience and impact voices on the player's car and the scene; buses and `--mute`

## 2. Verification
- [x] 2.1 Deck (2026-10-01): the same night run with all four voices filling: frame avg 7.97 ms, p99 11.1 ms, no errors; the generator fill shows up inside render CPU 0.85 ms and process time, well inside budget
- [x] 2.2 Human (Deck, 2026-10-02): "sound is good"; polish deferred to a focused audio project
