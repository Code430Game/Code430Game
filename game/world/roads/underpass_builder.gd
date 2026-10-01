class_name UnderpassBuilder
extends RefCounted
## Passages for pedestrian ways with the `tunnel` profile (see the importer's underpasses
## stage). The terrain is cut away in a strip HOLE_HALF_M wider than the path on each side
## (holes_by_chunk); the passage hides that cut: a floor across the strip, thick side walls
## filling the strip from the path edge out to the cut edge, a roof slab wider than the cut,
## and a headwall band plus wall ends at each portal. Faces are emitted with both windings
## so they read from inside and out, and everything carries collision.

const SURFACE_LIFT_M := 0.02
const WALL_IN_M := 0.3  # inner wall face stands this far outside the path edge
const HOLE_HALF_M := 4.0  # terrain cut and outer wall face: this far beyond the path edge
const ROOF_HALF_M := 8.0  # roof slab: this far beyond the path edge (covers the cut's ragged edge)
const HEADWALL_ABOVE_M := 0.6  # portal band from the roof up to here above it
# Linear colours (the material does not treat vertex colours as sRGB); the roof top matches the terrain.
const FLOOR_COLOR := Color(0.30, 0.29, 0.28)
const WALL_COLOR := Color(0.36, 0.35, 0.33)
const CEILING_COLOR := Color(0.22, 0.22, 0.21)
const ROOF_TOP_COLOR := TerrainBuilder.TERRAIN_COLOR


## chunk -> RoadMeshBuilder.ChunkTriangles for every tunnel way.
static func build(ways: Array[RoadGraph.PedestrianWay]) -> Dictionary:
	var buckets := {}
	for w in ways:
		if w.profile != "tunnel" or w.polyline.size() < 2:
			continue
		var pl := w.polyline
		var normals := RoadGeometry.miter_normals(pl)
		var hw := w.width_m * 0.5
		var inner := hw + WALL_IN_M
		var outer := hw + HOLE_HALF_M
		var roof := hw + ROOF_HALF_M
		for i in range(pl.size() - 1):
			var chunk := RoadGeometry.chunk_of_segment(pl[i], pl[i + 1])
			if not buckets.has(chunk):
				buckets[chunk] = RoadMeshBuilder.ChunkTriangles.new()
			var out: RoadMeshBuilder.ChunkTriangles = buckets[chunk]
			var top0 := _top(w, i)
			var top1 := _top(w, i + 1)
			var n0 := Vector3(normals[i].x, 0.0, normals[i].y)
			var n1 := Vector3(normals[i + 1].x, 0.0, normals[i + 1].y)
			var p0 := pl[i]
			var p1 := pl[i + 1]
			var f0 := p0 + Vector3.UP * SURFACE_LIFT_M
			var f1 := p1 + Vector3.UP * SURFACE_LIFT_M
			# Floor across the whole cut, so nothing is missing under the walls either.
			_both(out, f0 + n0 * outer, f0 - n0 * outer, f1 + n1 * outer, f1 - n1 * outer, FLOOR_COLOR)
			# Thick walls: inner face and outer face (buried in the terrain beyond the cut).
			for side: float in [-1.0, 1.0]:
				for d: float in [inner, outer]:
					var w0 := p0 + n0 * d * side
					var w1 := p1 + n1 * d * side
					_both(out, w0, w1, Vector3(w0.x, top0, w0.z), Vector3(w1.x, top1, w1.z), WALL_COLOR)
			# Roof slab: underside, and a terrain-coloured top that hides the cut from above.
			var c0l := Vector3(p0.x + n0.x * roof, top0, p0.z + n0.z * roof)
			var c0r := Vector3(p0.x - n0.x * roof, top0, p0.z - n0.z * roof)
			var c1l := Vector3(p1.x + n1.x * roof, top1, p1.z + n1.z * roof)
			var c1r := Vector3(p1.x - n1.x * roof, top1, p1.z - n1.z * roof)
			out.add_quad(c0l, c0r, c1l, c1r, CEILING_COLOR)
			out.add_quad(c0r, c0l, c1r, c1l, ROOF_TOP_COLOR)
			if i == 0:
				_portal(out, p0, n0, hw, top0)
			if i == pl.size() - 2:
				_portal(out, p1, n1, hw, top1)
	return buckets


## Vertex-coloured, with a little emission so the inside of a passage reads in the roof's shadow.
static func material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.95
	m.emission_enabled = true
	m.emission = Color(0.16, 0.16, 0.15)
	m.emission_energy_multiplier = 1.0
	return m


## chunk -> [{"a", "b", "half"}]: strips the terrain mesh leaves out under tunnels.
static func holes_by_chunk(ways: Array[RoadGraph.PedestrianWay]) -> Dictionary:
	var out := {}
	for w in ways:
		if w.profile != "tunnel" or w.polyline.size() < 2:
			continue
		var half := w.width_m * 0.5 + HOLE_HALF_M
		for i in range(w.polyline.size() - 1):
			var a := w.polyline[i]
			var b := w.polyline[i + 1]
			var hole := {"a": Vector2(a.x, a.z), "b": Vector2(b.x, b.z), "half": half}
			var lo := RoadGeometry.chunk_of(Vector3(minf(a.x, b.x) - half, 0.0, minf(a.z, b.z) - half))
			var hi := RoadGeometry.chunk_of(Vector3(maxf(a.x, b.x) + half, 0.0, maxf(a.z, b.z) + half))
			for cx in range(lo.x, hi.x + 1):
				for cz in range(lo.y, hi.y + 1):
					var key := Vector2i(cx, cz)
					if not out.has(key):
						out[key] = []
					(out[key] as Array).append(hole)
	return out


static func _top(w: RoadGraph.PedestrianWay, i: int) -> float:
	if i < w.top.size():
		return w.top[i]
	return w.polyline[i].y + 3.1


## Portal: the headwall band above the roof line and the wall ends between inner and outer faces.
static func _portal(out: RoadMeshBuilder.ChunkTriangles, p: Vector3, n: Vector3, hw: float, top: float) -> void:
	var roof := hw + ROOF_HALF_M
	var a := Vector3(p.x + n.x * roof, top - 0.05, p.z + n.z * roof)
	var b := Vector3(p.x - n.x * roof, top - 0.05, p.z - n.z * roof)
	_both(out, a, b, Vector3(a.x, top + HEADWALL_ABOVE_M, a.z), Vector3(b.x, top + HEADWALL_ABOVE_M, b.z), WALL_COLOR)
	for side: float in [-1.0, 1.0]:
		var e0 := p + n * (hw + WALL_IN_M) * side
		var e1 := p + n * (hw + HOLE_HALF_M) * side
		_both(out, e0, e1, Vector3(e0.x, top, e0.z), Vector3(e1.x, top, e1.z), WALL_COLOR)


## A quad with both windings so it is visible from either side.
static func _both(out: RoadMeshBuilder.ChunkTriangles, a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3, color: Color) -> void:
	out.add_quad(a0, a1, b0, b1, color)
	out.add_quad(a1, a0, b1, b0, color)
