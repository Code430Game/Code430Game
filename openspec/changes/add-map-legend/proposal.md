# Change: Map legend and places list

**Status: proposed 2026-10-07 from the human (2026-10-06): "We should add a todo to include a legend in the map and also a method of viewing items from each location. This is a feature of gta but lets be a little more plain search engine and instead of toggling through we click in or back. Say we have the legend, it'd be icon then name: [hospital icon] Hospital / [police icon] Police -> 2125 Bronson Ave (include real addresses) -> 134 St Other Street". The human asked for it to be built (2026-10-07: "Lets do a couple other fixes after that too").**

## Why
The full map shows the city and a few markers, but nothing says what the markers are or lists
the places the game knows. The pack has 12 services: 3 ambulance posts, 2 fire stations, 2
police, 2 hospitals, 2 campus security and 1 helipad. They have names but no addresses, so
the player can't find "the police station" except by stumbling on it.

## What Changes
- **Legend panel on the full map.** One line per kind of place, its icon then its name, in
  the shared menu theme. Only kinds the pack has are listed.
- **Click in, back out.**
  - A (or a click) on a kind opens its list of places: name and street address, nearest
    first.
  - A on a place centres the map on it and highlights its marker; B goes back a level.
  - No button-cycling through places.
- **Real addresses.**
  - The importer keeps OSM's `addr:housenumber` and `addr:street` (and `addr:unit` where
    present) on each service place, as an optional `address` in `services.v0.json`.
  - With no address tags, it falls back to "on <nearest street name>" from the road graph.
  - OSM addresses are ODbL like the rest of the map data and are credited the same way.
- **One icon set.** Small flat icons per kind (hospital, police, fire, ambulance, security,
  helipad, parking garage) in one style, used by the legend, the full map and the minimap's
  service markers.
- **Later, not in this change:** shops, mission markers, waypoints and routes to a place,
  search by typing.

## Co-op authority
Local UI over static pack data; nothing replicated.

## Impact
- Affected specs: `wayfinding` (ADDED: Map Legend And Places).
- Affected code:
  - `tools/osm_import` (service addresses, nearest-street fallback);
  - `docs/pack-format/services.schema.v0.json` (optional `address`; v0, pre-release);
  - the golden fixture; the pack re-exported;
  - `game/world/services/` (address on `Place`);
  - `game/ui/map/overview_map.gd` (legend, list, centring);
  - `game/ui/map/minimap.gd` and `map_renderer.gd` (shared icons);
  - new `game/ui/map/place_icons.gd` and icon SVGs;
  - tests.
