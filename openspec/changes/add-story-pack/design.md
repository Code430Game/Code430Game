# Design: declarative missions

## Why typed steps and not a script
Story packs are data-only by the constitution. A closed set of step types keeps the author's
power inside what the validator can check and the host can replicate. Five steps cover a courier
loop; later changes add types rather than a scripting language.

## Step semantics
- `go_to {x, z, radius_m}`: done when any peer's controlled body is within the radius.
- `enter_vehicle {}`: done when the peer who holds the item is driving (`Player.is_driving()`).
- `follow {target: "nearest_traffic" | "bus", keep_within_m, for_s}`: the runner picks the
  nearest matching traffic agent when the step starts and succeeds after `for_s` seconds within
  range; leaving the range resets the clock, not the mission.
- `deliver {x, z, radius_m}`: `go_to` that also clears the carried item and ends the mission.
- `survive_until {s}`: a timer; failing conditions can still end it early.
- The item is a flag on the mission state, not an inventory: "who carries it" is the peer that
  accepted the mission. Abandonment (`abandon_radius_m` from the current objective for 30 s) and
  the deadline fail the mission.

## Positions
- Local metres, as the HUD prints them, so the human can author a mission from a Deck drive.
  The validator checks each position lies inside the dependency map pack's bbox projected to
  local coordinates (it reads that pack's manifest from the same root). Y comes from a terrain
  raycast at placement.
- First Ride: giver on the sidewalk by the ByWard Market square (George at William; the
  implementing agent takes the exact x,z from the HUD), delivery south of the Queensway inside
  the district; deadline generous enough for the Nicholas or Bank crossing at the speed limit
  plus one wrong turn, measured with `--autodrive`.

## Giver
- A `PlacedCharacter` scene: `CharacterRig` with the mission's profile, a static idle pose with
  a slow breathing bob, a collision capsule so it can be bumped, and an interact prompt that
  reuses the vehicle-entry prompt label. It does not walk and is not a pedestrian agent;
  pedestrians treat it as an obstacle via `PedestrianManager.obstacles`.

## Dialogue box
- Bottom panel: speaker name, one line at a time, accept advances, cancel declines. Lines come
  from the picked variant. Text only; a future change can add portraits or voice. Works with the
  Deck's controller and pauses nothing (traffic keeps moving behind it).

## Replication
- `mission_state` reliable RPC from the host on change: `{mission_id, phase, step, deadline_at,
  holder_peer}`. Clients render markers and HUD from it and send `mission_interact(mission_id)`
  and nothing else; the host evaluates every step using the positions it already has for every
  peer. A holder who leaves the session fails the mission.

## Markers
- `MapRenderer` gets `set_overlay(points)`; the minimap draws the current objective as a ring
  clamped to its edge when out of view, the overview map as a ring at its position. The world
  beam is a `MeshInstance3D` cylinder with an unshaded additive material, 40 m tall, visible to
  600 m on both presets.
