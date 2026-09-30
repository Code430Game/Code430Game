class_name WaterBuilder
extends RefCounted
## Loads water.v0.json from a map pack and builds flat water meshes per chunk.
## Triangles are pre-computed by the import tool; each goes to the chunk of its centroid.

const WATER_COLOR := Color(0.16, 0.32, 0.45)
const SURFACE_LIFT_M := 0.05


class WaterPolygon:
	extends RefCounted
	var id: String
	var name: String
	var kind: String
	var surface_y: float
	var vertices: PackedVector2Array  # x, z
	var triangles: PackedInt32Array


## Reads the file; returns an empty array when the pack has no water.
static func load_polygons(pack_dir: String) -> Array[WaterPolygon]:
	var out: Array[WaterPolygon] = []
	var path := pack_dir.path_join("water.v0.json")
	if not FileAccess.file_exists(path):
		return out
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("WaterBuilder: bad JSON in %s" % path)
		return out
	for p: Dictionary in parsed.get("polygons", []):
		var w := WaterPolygon.new()
		w.id = p["id"]
		w.name = str(p["name"]) if p["name"] != null else ""
		w.kind = p["kind"]
		w.surface_y = float(p["surface_y"])
		for v in p["vertices"]:
			w.vertices.append(Vector2(float(v[0]), float(v[1])))
		for i in p["triangles"]:
			w.triangles.append(int(i))
		out.append(w)
	return out


## Chunk -> ChunkTriangles of water surfaces.
static func build(polygons: Array[WaterPolygon]) -> Dictionary:
	var buckets := {}
	for w in polygons:
		var y := w.surface_y + SURFACE_LIFT_M
		for t in range(0, w.triangles.size(), 3):
			var a := _v(w, w.triangles[t], y)
			var b := _v(w, w.triangles[t + 1], y)
			var c := _v(w, w.triangles[t + 2], y)
			var chunk := RoadGeometry.chunk_of((a + b + c) / 3.0)
			if not buckets.has(chunk):
				buckets[chunk] = RoadMeshBuilder.ChunkTriangles.new()
			# Earcut is counter-clockwise in (x, z); with z pointing south that is clockwise seen from
			# above, which is Godot's front face, so the order is kept as is.
			buckets[chunk].add_triangle(a, b, c, WATER_COLOR)
	return buckets


static func _v(w: WaterPolygon, i: int, y: float) -> Vector3:
	var p := w.vertices[i]
	return Vector3(p.x, y, p.y)


static func material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = WATER_COLOR
	m.roughness = 0.12
	m.metallic = 0.0
	m.metallic_specular = 0.7
	return m
