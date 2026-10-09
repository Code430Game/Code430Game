# Change: Offices, business signs and posters

**Status: proposed 2026-10-09 (human: "The office buildings could likewise use some improvements. I wonder if businesses could get signs. In the dystopian add building posters.").**

## Why
Downtown reads as uniform glass grids: every office is a curtain-wall box with the same
window rhythm, no base, no entrance and no top. Shops have a glass ground floor
(`shopfront`) but nothing says what they are. And dystopia changes the look of vehicles and
weapons but not the city's walls.

## What Changes
- **Office and commercial buildings** get a base, middle and top:
  - a taller ground floor with an entrance (doors, a canopy over them) on the street side;
  - a facade type per building, picked by seed and tags, so neighbours differ: glass curtain
    wall with mullions, punched windows in concrete or stone, horizontal ribbon windows,
    precast panels;
  - setbacks for tall towers (a podium of 3–5 storeys under the tower where the footprint
    allows);
  - a roof with mechanical penthouses, parapets and, on the tallest, a crown or lit top.
- **Business signs.** The importer reads shop and amenity points (`shop=*`, `amenity=cafe`,
  `restaurant`, `pharmacy`, `bank`, …) and ties each to the building and facade it sits in.
  The game draws a sign over its shopfront: a fascia band with the business type, a projecting
  sign on some, lit at night. **Signs show generic names by category** ("Café", "Pharmacy",
  "Hardware", a generated name like "Elm Street Books"), never the real business names from
  OpenStreetMap, which are often trademarks (`AGENTS.md`, content policy).
- **Posters by tone.** A `building_posters` dressing places poster panels on blank wall
  stretches at street level, from a tone-tagged set (content modes):
  - dystopia: propaganda and corporate posters (original artwork; slogans like "COMPLIANCE IS
    COMFORT"), some torn, a few large banners on towers;
  - gritty: gig flyers and torn layers of paper;
  - clean: community notices and event posters.
  All poster art is original, made for the game, in `game/world/dressing/posters/`.
- **Not in this change:** interiors, animated or video billboards, the ad billboards (they
  exist), landmark buildings (`add-landmarks`).

## Impact
- Affected specs: `map-buildings` (ADDED: Office Facades With A Base And A Top),
  `street-dressing` (ADDED: Business Signs; ADDED: Posters By Tone).
- Affected code: `tools/osm_import/buildings.py` (entrance side), a new
  `tools/osm_import/businesses.py` (shop and amenity points tied to buildings) with
  `businesses.v0.json` and a schema; `building_builder.gd` and the building shader (facade
  types, base and top); a new `game/world/dressing/business_signs.gd` and
  `building_posters.gd`; the poster and sign art; content mode files (poster sets per tone);
  tests; Ottawa pack re-exported.
- Performance: signs and posters are a few MultiMeshes per chunk plus `Label3D`s within a short
  range; benchmark downtown against main.
