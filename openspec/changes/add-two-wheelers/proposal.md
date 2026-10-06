# Change: Bicycles and motorcycles

**Status: proposed 2026-10-06 from the backlog (human asked 2026-10-02 whether to add motorcycles and bicycles).**

## Why
Ottawa has cycleways all through the pack and none of them are used. Cyclists in the bike
lanes and the odd motorcycle filtering through traffic make streets read as a city, and both
are fun to take.

## What Changes
- **Bicycles.** Cyclists ride the imported cycleways and bike lanes (`cycleway`, `cycleway:*`
  tags, and painted lanes where the road has them) at 15-25 km/h, stop at signals, and dismount
  at the end of a path. Rider bodies come from the character pipeline (`CharacterRig` on a seat
  pose).
- **Motorcycles.** A `motorcycle` vehicle class in the catalogue with traffic spawn weight;
  they filter between lanes slowly when traffic is stopped.
- **Riding.** Both are takeable like cars. Physics is a lean model on a capsule body (not four
  wheels): steering leans, braking hard tips you off at speed, falling off ragdolls the rider
  (`CharacterRagdoll`).
- **Design note from the human:** they like using the bike lane as a passing lane, so cyclists
  must populate it without fencing it off from cars; squeezing between cars is hard, which is
  right for OSM lane widths.
- **Not in this change:** bike racks, delivery riders, scooters.

## Co-op authority
The host owns AI riders; a riding player owns their bike like a car.

## Impact
- Affected specs: `vehicles` (ADDED: Two-Wheelers), `traffic` (ADDED: Cyclists In Bike Lanes).
- Affected code: `tools/osm_import` (cycle lane data on edges), `game/world/traffic/` (a cyclist
  agent kind and lane paths for bike lanes), `game/actors/vehicles/` (`two_wheeler.gd`, catalogue
  entries), the character rig (seat pose), `controls.json` (none new: same driving actions); tests.
- Overlaps: `add-character-features` touches the rig too; land one before the other.
