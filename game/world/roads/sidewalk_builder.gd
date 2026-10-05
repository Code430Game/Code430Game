class_name SidewalkBuilder
extends RefCounted
## Ribbons for pedestrian ways: sidewalks and paths with a curb (their y already
## includes it from the import), crossings flush with the road as light strips.
## Vertices carry UV = (metres along the way, metres across from its centre line) and
## UV2 = (ribbon width, slab length) so the ground shader draws slab joints; a slab length of
## 0 (crossings, cycle lanes, steps) means no joints.

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
## Slab length by kind, metres; kinds not listed get no joints.
const SLAB_M := {"sidewalk": 1.5, "footway": 1.5, "pedestrian": 1.5, "path": 2.0}


## chunk -> RoadMeshBuilder.ChunkTriangles for all pedestrian ways.
static func build(ways: Array[RoadGraph.PedestrianWay]) -> Dictionary:
	var buckets := {}
	for w in ways:
		if w.polyline.size() < 2 or w.covered:
			continue
		var lift := SURFACE_LIFT_M - (CROSSING_DROP_M if w.kind == "crossing" else 0.0)
		var color: Color = COLORS.get(w.kind, COLORS["footway"])
		var slab := float(SLAB_M.get(w.kind, 0.0))
		var uv2 := Vector2(w.width_m, slab)
		var half := w.width_m * 0.5
		var pl := RoadGeometry.split_at_chunk_bounds(w.polyline)
		var along := PackedFloat32Array([0.0])
		for i in range(1, pl.size()):
			along.append(along[i - 1] + Vector2(pl[i].x - pl[i - 1].x, pl[i].z - pl[i - 1].z).length())
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
			var tris: RoadMeshBuilder.ChunkTriangles = buckets[chunk]
			# The same two triangles add_quad would make, with along/across UVs.
			var ur0 := Vector2(along[i], -half)
			var ul0 := Vector2(along[i], half)
			var ur1 := Vector2(along[i + 1], -half)
			var ul1 := Vector2(along[i + 1], half)
			tris.add_triangle_uv(right[i], right[i + 1], left[i], color, ur0, ur1, ul0, uv2)
			tris.add_triangle_uv(left[i], right[i + 1], left[i + 1], color, ul0, ur1, ul1, uv2)
	return buckets


static func material() -> Material:
	var m := SurfaceDetail.material("concrete", 0.95)
	m.set_shader_parameter("joints", true)
	return m
