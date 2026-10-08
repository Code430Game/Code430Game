# Change: Dress the proving ground: buildings on every block and trees

**Status: proposed 2026-10-08 (human, after driving it on the Deck: "a little sparse ... we need more buildings, there's a lot of flat open area for a city. There's also a lack of trees"); approved in the same breath, build follows.**

## Why
The first Double Cross pack proved the pipeline: 45 buildings and the services on an otherwise
empty grid, with the greenbelt's wood as the only mass of trees. Driven on the Deck it reads
as a plan, not a town. The grids need buildings on every block and the streets need trees so
that the district looks like somewhere, and so that the systems the district exists to test
(parking, pedestrians, police, the gang's turf, line of sight) have a town's worth of walls
and cover to work against.

## What Changes
- **A dressing pass in the generator** (`tools/proving_ground/dressing.py`, run after the
  streets and services, before stitching) that walks every straight street frontage and
  places lots along it, seeded, skipping anything that would land on a road, a sidewalk, the
  river banks, the greenbelt, the park, a bridge, the turf block, the roundabout or an
  existing building:
  - **residential south**: detached houses with varied footprints and two storeys, semis and
    terraces mixed in by seed, every other detached house with a driveway to its street, a
    yard tree behind each detached house;
  - **main city**: shopfront terraces along the avenues (retail with a shop tag each), three
    to six storey apartment and commercial blocks along the streets, a few towers of ten to
    sixteen storeys within reach of the roundabout, and surface parking lots behind some
    blocks;
  - **city top right**: four to eight storey offices along Riverside Avenue and the streets, a
    warehouse row along the rail on the north side of Station Avenue.
- **Trees**: tree rows on both sides of every avenue in all three grids and along the
  street-level bank road, a yard tree per detached house; the greenbelt wood, the park and
  the river banks keep their scatter. Bushes keep coming from the importer's frontage rule.
- **The town's name becomes one generator parameter** (`build(town=...)` and `--town`),
  still "Double Cross" until the human picks one.
- **Checklist tests gain minimum counts** per grid for buildings and trees, and the pack test
  checks them on the committed pack. The pack is regenerated and committed.
- **Not in this change:** street furniture beyond what the importer already produces,
  interiors, a new building style, the turf block (the gang change owns it), the Ottawa pack.

## Co-op authority
Static geometry; nothing replicated.

## Tone
Not content; no descriptors.

## Impact
- Affected specs: `proving-ground` (One Of Everything modified: a dressed town, not one
  instance of each).
- Affected code: `tools/proving_ground/dressing.py` (new), `layout.py` (hook, town
  parameter), `__main__.py` (`--town`), `tools/tests/test_proving_ground.py`,
  `test_proving_ground_pack.py`, `regions/proving-ground/*` and `packs/proving-ground/*`
  regenerated.
- Performance: more buildings and tree rows per chunk; the deck preset's per-chunk caps
  (400 trees, 600 bushes) already drop scatter first, so rows and yard trees survive. Deck
  measured on the loop against the 2026-10-08 baseline (render cpu 1.10 / gpu 8.20 ms).
