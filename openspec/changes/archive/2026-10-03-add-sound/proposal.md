# Change: Sound

**Status: proposed 2026-10-01 (queue item: sound; approved in conversation "do the day night and sounds").**

## Why
The game is silent. Engine note, tyre roll and city hum change how driving feels more than any
visual, and an impact thump makes collisions land. No audio assets exist and none are needed:
everything here is synthesised at runtime, which keeps the repo free of licensing questions.

## What Changes
- **Procedural audio** through `AudioStreamGenerator`: an engine voice (two harmonics plus
  noise, pitch from speed and throttle), tyre roll (filtered noise by speed), city ambience
  (low hum scaled by nearby traffic), and impact thumps (decaying noise bursts scaled by the
  collision speed) when the player's car hits something.
- **Mixer:** Master, SFX and Ambience buses; volumes in settings; `--mute` flag.
- **Not in this change:** music, voices, pedestrian speech, horns, sirens, positional audio
  for traffic cars, radio.

## Impact
- Affected specs: `audio` (new).
- Affected code: `game/core/audio/` (new: synth helpers, engine, tyres, ambience, impacts),
  `placeholder_car.gd` (contact reporting), `play_testbed.gd`, `project.godot` (buses), tests.
- Performance: four generator streams at 22 kHz filled from GDScript; measured on the Deck.
