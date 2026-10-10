# Change: Adopt a CC0 art kit (Quaternius) for people, vehicles, trees, props and buildings

**Status: proposed 2026-10-10 (human, after looking at Quaternius's packs: "if we used those buildings and people we would skyrocket the graphics … I think these would put us in the right graphics level for this style game").**

## Why
Everything visible is generated from primitives in code. People are capsules, cars are boxes,
buildings are extrusions, and the human wants "a level above this": bodies that read as
different genders, faces, clothes that look like what they are (a coat, a bomber, a puffer, a
dress), and cars and buildings to match. Quaternius publishes a large library in one consistent
low-poly style: modular men and women with swappable outfits and animations, cars, public
transport, trains, a modular city kit, nature and guns. The downloads carry a CC0 1.0
`License.txt` (see `design.md`, Licensing). Adopting it lifts the whole look at once, and its
flat palette style is easy to match with what we keep generating.

## What Changes
- **Third-party art, with receipts.** Curated models go in
  `game/assets/third_party/quaternius/<pack>/` as `.glb` (only the models we use, glTF only).
  Each pack folder keeps its original `License.txt`, a `SOURCE.md` with the download link and
  date, and the list of files taken. A CI check fails when a pack folder has no CC0
  `License.txt`, or when the third-party art passes a size budget (120 MB to start).
  `LICENSE-ASSETS` gets a third-party section crediting Quaternius.
- **Staged adoption**, each stage shippable and benchmarked on the Deck:
  1. **Vehicles.** Kit cars, the bus and the taxi replace `VehicleMesh` bodies through the
     vehicle catalogue (a `model` per entry, with the procedural body as the fallback).
     Liveries (police, ambulance, taxi) become material and decal overrides. Traffic keeps its
     MultiMeshes, one per model and LOD; wheels and lights keep working.
  2. **People.** The modular men and women (body, head, hair and outfit parts) replace
     `CharacterMesh` for the player, remote players, pedestrians, officers, paramedics and gang
     members.
     - The profile picks parts and colours.
     - Prints go on tops through a shader region (the `add-character-features` prints).
     - Police, paramedic and gang looks are recolours plus badges and prints.
     - The crowd's walk shader is adapted to the kit skeleton (bone index and pivots baked per
       pool, as today, with more bones). The player and the actors use the kit's animations.
     - Ragdolls are rebuilt on the kit skeleton.
     - Children in clean mode use a smaller kit body or the teen proportions.
  3. **Trees and street props.**
     - Kit trees and bushes replace `TreeMeshes` archetypes in the vegetation MultiMeshes.
     - Street pieces we lack (lamp posts, benches, hydrants, bins) join the dressing.
     - Billboards, signal heads and signs keep their behaviour with kit-style models where the
       kit has them.
  4. **Buildings.** Kit facade pieces dress our real OSM footprints:
     - wall and window sections tiled along each facade, with doors and storefronts at street
       level and cornices and roofs on top;
     - houses built from kit-style pieces (the kit has few houses), so
       `update-houses-and-yards` and `update-commercial-buildings` build on this stage.

  Landmarks (`add-landmarks`) use the same palette.
- **Matching what we keep generating.** Roads, junctions, markings, sidewalks, terrain, water and
  bridges stay generated (they follow the real map), restyled to the kit's flat palette.
  Anything new is made in the same style: a kit model, a code-built mesh on the kit palette, or a
  Blender model.
- **Not in this change:** paid Source kits (only free tiers whose download is CC0), interiors,
  replacing landmarks, new animations beyond the kit's.

## Impact
- Affected specs: `project-foundation` (ADDED: Third-Party Art With Licence Receipts),
  `vehicles` (ADDED: Vehicle Models From The Art Kit), `player-character` (ADDED: Characters From
  The Art Kit), `vegetation` (ADDED: Kit Trees), `map-buildings` (ADDED: Kit Facades On
  Footprints).
- Affected code: a new `game/assets/third_party/`, a glTF import and part-assembly layer
  (`game/actors/character/kit_character.gd`, `game/actors/vehicles/kit_vehicle.gd`), the vehicle
  catalogue, `CharacterProfile` (parts), the pedestrian walk shader and pools, ragdolls, the
  vegetation builder, the building builder (facade tiling), `tools/pack_tools` or a new
  `scripts/check-third-party.sh` (receipts and size budget), `LICENSE-ASSETS`; tests and
  screenshots at every stage.
- Supersedes: `add-character-features` 4.1 (garments as primitives) and 4.2 (primitive LODs);
  its body types, children, prints and creator pages carry over onto the kit bodies. Changes the
  starting point of `update-houses-and-yards` and `update-commercial-buildings`.
- Repo weight: about 40–80 MB of curated `.glb` (the repo is about 38 MB now); see `design.md`.
- Performance: the Deck decides triangle budgets per stage. Kit characters are low-poly, but
  `Universal Base Characters` (about 13k triangles) is too heavy for crowds and is used only if
  decimated.
