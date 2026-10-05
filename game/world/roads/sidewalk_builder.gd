class_name SidewalkBuilder
extends RefCounted
## Ribbons for pedestrian ways: sidewalks and paths with a curb (their y already
## includes it from the import), crossings flush with the road as light strips.

const SURFACE_LIFT_M := 0.02
const CROSSING_DROP_M := 0.0  # the import already places crossings 2 cm above the road, sidewalks on the curb
const VISIBLE_TO_M := 500.0
const COLORS := {
	"sidewalk": Color(0.72, 0.71, 0.68),
	"crossing": Color(0.62, 0.62, 0.62),
	"footway": Color(0.70, 0.69, 0.66),
	"pedestrian": Color(0.70, 0.69, 0.66),
	"steps": Color(0.60, 0.59, 0.57),
	"path": Color(0.55, 0.50, 0.40),
	"track": Color(0.52, 0.47, 0.38),
	"cycleway": Color(0.22, 0.5, 0.3),  # Ottawa paints bike lanes green
}


## chunk -> RoadMeshBuilder.ChunkTriangles for all pedestrian ways.
static func build(ways: Array[RoadGraph.PedestrianWay]) -> Dictionary:
	var buckets := {}
	for w in ways:
		if w.polyline.size() < 2 or w.covered:
			continue
		var lift := SURFACE_LIFT_M - (CROSSING_DROP_M if w.kind == "crossing" else 0.0)
		var color: Color = COLORS.get(w.kind, COLORS["footway"])
		var pl := RoadGeometry.split_at_chunk_bounds(w.polyline)
		var normals := RoadGeometry.miter_normals(pl)
		var left := PackedVector3Array()
		var right := PackedVector3Array()
		for i in range(pl.size()):
			var n := normals[i] * w.width_m * 0.5
			var p := pl[i] + Vector3(0.0, lift, 0.0)
			left.append(p + Vector3(n.x, 0.0, n.y))
			right.append(p - Vector3(n.x, 0.0, n.y))
		for i in range(pl.size() - 1):
			var chunk := RoadGeometry.chunk_of_segment(pl[i], pl[i + 1])
			if not buckets.has(chunk):
				buckets[chunk] = RoadMeshBuilder.ChunkTriangles.new()
			buckets[chunk].add_quad(right[i], left[i], right[i + 1], left[i + 1], color)
	return buckets


static func material() -> Material:
	return SurfaceDetail.material("concrete", 0.95)
