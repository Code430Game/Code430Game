# Change: Clustered junctions keep their arms straight

**Status: proposed 2026-10-02 (human, from a Deck screenshot at x 237, z 18: "the X is weird ... vehicles try and converge on the center point and drive oddly ... it's even in the little maps").**

## Why
The importer merges junction nodes that sit within a road class's cluster radius so a street
crossing a divided road becomes one junction (`tools/osm_import/cluster.py`). When it does, it
moves every touching edge's end point onto the cluster centroid. At Elgin and Nepean
(cluster `c901050337`, two OSM nodes about 20 m apart) both one-way Elgin carriageways and
Nepean all bend to one point: the ribbons and edge lines cross in an X, the minimap draws the
same X, and because lane paths follow the polylines the traffic aims at the centre before
turning back out. Ottawa has 76 such clusters, every divided crossing in the district.

## What Changes
- **Importer.** A touching edge no longer ends at the centroid. Its polyline is extended or
  shortened along its own last direction to the point nearest the centroid, so a carriageway
  stays straight and passes beside the cluster centre at its real offset. An edge whose
  original end is within a small tolerance of the centroid is snapped as before. The node keeps
  the centroid as its position; topology is unchanged. Cluster stats gain the largest arm offset
  per cluster for the validation report. Golden files re-baked; `test_osm_cluster.py` gains a
  divided-road case that asserts the carriageways stay parallel through the merged node.
- **Junction builder.** Arms are placed at the edge's actual end point, not at the node centre
  plus a side offset, so corner intersections, caps and trims are computed on the real ribbons.
  The polygon walk already copes with arms that do not meet at a point (convex hull fallback);
  the common case must still produce a simple polygon. `test_junction_builder.gd` gains an
  offset-arm case.
- **Downstream, no code change expected:** lane paths and connectors already run from the
  trimmed ends and aim at the tangent intersection; markings, stop lines, sidewalk returns and
  the minimap read the polylines. Each is checked at Elgin and Nepean and at one primary
  divided crossing on Mac screenshots before the Deck.
- **Not in this change:** separate signal phases per carriageway, median islands inside the
  junction, the cluster radius values themselves.

## Impact
- Affected specs: `road-network` (Drivable Generated Roads modified).
- Affected code: `tools/osm_import/cluster.py`, `validation.py` (report field),
  `tools/tests/test_osm_cluster.py`, `tools/tests/golden/*`, `game/world/roads/junction_builder.gd`,
  `game/tests/test_junction_builder.gd`, Ottawa pack re-exported.
- Performance: none expected; junction polygons change shape, not count. Deck measured.
