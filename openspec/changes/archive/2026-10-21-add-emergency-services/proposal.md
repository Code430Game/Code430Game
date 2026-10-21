# Change: Emergency services (police stations, hospitals, fire stations, helipads)

**Status: proposed 2026-10-05 (human: "with the police, we should include police stations"; "We should also copy down hospitals and firestations then add those proposals"; "Are there helipads? XD").**

## Why
Police now chase and catch you, but being busted or wasted drops you back at the start, and
patrol cars appear from nowhere. Real places give the loop a shape: you're taken to the
police station or the hospital, and the police come from somewhere you can see on the map.
OpenStreetMap has them. A query on 2026-10-05 for the Ottawa bbox found:
- **Police (4):** Ottawa Police Headquarters (Elgin St), uOttawa Campus Protection, Rideau
  Centre Security, and an unnamed one
- **Hospitals (2):** Saint-Vincent Hospital, Élisabeth Bruyère Hospital
- **Fire stations (2):** Ottawa Fire Station 11, Ottawa Fire Station 13
- **Ambulance posts (3):** Catherine, St. Patrick, Gladstone
- **Helipads (1):** unnamed
- Plus 40-odd clinics, which are left out.

## What Changes
- **Importer.** A `services.py` stage with its own Overpass query (`amenity=police|hospital|
  fire_station`, `emergency=ambulance_station`, `aeroway=helipad|heliport`). Each place gets a
  kind, a name, a position (way centre or node) and the nearest road node, as the place a car
  leaves from or arrives at. Security desks (`police=` tags such as campus or private
  security, or a name containing "Security") are kept as `security`, not `police`.
  `services.v0.json`, a schema, and pack validation.
- **Map.** Icons on the overview map and the minimap: a badge for police, a cross for
  hospitals, a flame for fire stations, an H for helipads. They are labelled on hover.
- **Respawn at the right place.** Busted puts the player outside the nearest police station;
  wasted, outside the nearest hospital. Each falls back to the spawn point when the pack has
  none.
- **Police roll out from stations.** When a police station is within the spawn ring, the
  first patrol car of a chase leaves from it. The rest spawn out of view as now.
- **Ready for later.** Fire stations, ambulance posts and helipads are in the data and on the
  map for later changes: fire trucks and ambulances answering crashes, and the police
  helicopter (`add-police-helicopter`).
- **Not in this change:** station interiors, jail, hospital bills, fire, ambulances driving,
  the helicopter.

## Co-op authority
Static pack data. Respawn places are chosen by the host for the busted or wasted player.

## Impact
- Affected specs: `emergency-services` (new).
- Affected code: `tools/osm_import/services.py` (new), `__main__.py`, `pack.py`,
  `docs/pack-format/services.schema.v0.json`, `tools/pack_tools`; `game/world/packs/map_pack.gd`
  (load), `game/ui/map/map_renderer.gd` (icons), `game/actors/police/police_manager.gd` (station
  spawn), the testbed (respawn places); tests; Ottawa pack re-exported.
