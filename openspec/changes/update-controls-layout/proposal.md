# Change: Controls layout aligned with the genre

**Status: proposed 2026-10-02 (human: "make R1 handbrake so that I don't keep blipping to nowhere ... we should look up the GTA 5, 4, 3 and Cyberpunk 2077 control mappings as an item").**

## Why
The handbrake and the car reset were both bound to RB, so every handbrake pull teleported the
car; that is fixed as a bug (reset moved to R3 as `docs/controls.md` always said). The larger
point stands: players arrive with muscle memory from GTA and Cyberpunk, and our layout grew one
action at a time. `design.md` tabulates the four reference layouts next to ours; this change
settles the layout once so the pending combat, radio and horn work bind to agreed buttons
instead of whichever are free.

## What Changes
- **Driving.** Handbrake RB (as GTA V). Horn on L3 (GTA V, III and Cyberpunk agree; `add-sound`
  deferred horns, this adds a synthesised one). Look behind on R3 tap (every reference) and
  car reset on R3 held for one second, so a stuck car is still one gesture away but never an
  accident. Radio cycle D-pad left (GTA V's radio wheel position; matches `add-car-radio`).
  Headlights move from D-pad up to D-pad right (GTA V), freeing D-pad up for a phone or
  mission log later. Camera stays on D-pad down and the map on View; the reference games put
  the camera on View and the map in pause, and the Deck's View button is awkward to reach
  while steering, so this is a deliberate deviation recorded in the doc.
- **On foot.** Sprint on L3 and jump on A stay (Cyberpunk's layout; GTA uses A sprint, X jump).
  Interact Y (all four). Weapons, when `add-weapons-and-combat` lands: aim LT, fire RT, weapon
  wheel on LB held with LB tap for next weapon (GTA V), reload B, take cover and crouch left
  for a later change. That proposal's D-pad cycle and RB reload are replaced by this layout.
- **Remappable.** A controls page in settings lists every action with its bindings and lets the
  player rebind a gamepad button or key with a press; conflicts within a context are refused
  with a message. Bindings persist in settings. A reset-to-default button.
- **Tabbed menus (added 2026-10-04, human: "the controls on the home screen are running off the
  screen so we should probably present them on the pause screen per device type ... Tabs like
  controls, options, settings").** The start and pause menus get tabs (Controls, Options,
  Settings, and the existing items under a first tab) instead of one long list. The controls
  hint list leaves the home screen and becomes the Controls tab, showing the layout for the
  device in use (controller or keyboard and mouse, switching with the last input as the HUD
  hints already do), with the remapping from the next bullet on the same tab. Tabs cycle with
  LB/RB (and Q/E) so the Deck needs no pointer.
- **Doc.** `docs/controls.md` regenerated from the input map by a tool so it cannot drift again.
- **Not in this change:** touchpad or gyro on the Deck, Steam Input configs, cover, crouch,
  phone, weapon wheel UI itself (combat change), drive-by.

## Co-op authority
Input is local. Nothing here is replicated.

## Impact
- Affected specs: `project-foundation` (Controller-First Input modified: context rule and
  remapping), `audio` (horn requirement added).
- Affected code: `game/project.godot` (input map), `game/actors/vehicles/placeholder_car.gd`
  (hold-to-reset, look behind, horn), `game/actors/vehicles/chase_camera.gd` (look behind),
  `game/core/audio/vehicle_audio.gd` and `synth.gd` (horn voice), `game/core/settings/settings.gd`
  (binding overrides), `game/ui/pause/` (controls page), `game/tests/test_input_map.gd`
  (context conflict test extended), `tools/` (controls doc generator), `docs/controls.md`,
  `openspec/changes/add-weapons-and-combat` and `add-car-radio` (binding paragraphs updated).
- Performance: none.
