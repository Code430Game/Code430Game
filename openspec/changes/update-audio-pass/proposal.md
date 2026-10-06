# Change: Audio pass

**Status: proposed 2026-10-06 from the backlog (human, 2026-10-02: "I'd rather leave this until we want to improve the audio across the board"). Written now so it is ready; start it when the human asks for an audio round.**

## Why
Sound is synthesised and mostly global: engine and tyre voices for the driven car, a city
bed, horn, sirens and rotor, and combat sounds. It works, but every car sounds the same and
the city doesn't place sounds around you.

## What Changes
- **Engine character per class** from the vehicle catalogue (bus, van, sports car, police):
  pitch, harmonics and idle, still synthesised.
- **Positional traffic.** The nearest few traffic cars get positional engine voices
  (`AudioStreamPlayer3D` pool, capped per preset) instead of one city bed.
- **Sirens and rotor** become positional too, with Doppler.
- **Pedestrians.** A few short, generic synthesised vocal reactions (startled, hit, shouting
  at the player), tone-gated.
- **Reverb** in underpasses, tunnels and garages through an audio bus effect zone.
- **Not in this change:** recorded audio, music beyond the radio.

## Impact
- Affected specs: `audio` (ADDED: Positional City Sound).
- Affected code: `game/audio/` (`Synth`, buses), `traffic_manager.gd` (voice pool), police and
  ambulance managers (positional sirens), the pedestrian manager (reactions), area zones from
  underpass and garage data; tests on pool caps; Deck benchmark (audio thread cost).
