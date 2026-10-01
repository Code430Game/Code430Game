class_name WalkGraph
extends RefCounted
## Walkable network from a pack's pedestrian ways. Ways are joined where their ends meet
## (within JOIN_M), so a pedestrian reaching the end of one can continue onto another.
## Covered ways are skipped: they are not drawn.

const JOIN_M := 1.0


class WalkPath:
	extends RefCounted
	var id: int
	var way_id: String
	var kind: String
	var width_m: float
	var points: PackedVector3Array
	var cumulative: PackedFloat32Array
	var length: float = 0.0
	var start_key: Vector2i
	var end_key: Vector2i

	func position_at(distance: float) -> Vector3:
		if points.size() == 1:
			return points[0]
		var d := clampf(distance, 0.0, length)
		var i := 0
		while i < cumulative.size() - 2 and cumulative[i + 1] < d:
			i += 1
		var seg := cumulative[i + 1] - cumulative[i]
		var t := (d - cumulative[i]) / seg if seg > 0.0 else 0.0
		return points[i].lerp(points[i + 1], t)

	func direction_at(distance: float) -> Vector3:
		var a := position_at(maxf(distance - 0.5, 0.0))
		var b := position_at(minf(distance + 0.5, length))
		var d := b - a
		d.y = 0.0
		return d.normalized() if d.length_squared() > 1e-9 else Vector3.FORWARD


var paths: Array[WalkPath] = []
var _by_key: Dictionary = {}  # Vector2i join key -> Array[int] path ids touching it
var _cells: Dictionary = {}  # Vector2i (64 m cells) -> Array[int] path ids
const CELL_M := 64.0


static func build(ways: Array[RoadGraph.PedestrianWay]) -> WalkGraph:
	var g := WalkGraph.new()
	for w in ways:
		if w.covered or w.polyline.size() < 2:
			continue
		var p := WalkPath.new()
		p.id = g.paths.size()
		p.way_id = w.id
		p.kind = w.kind
		p.width_m = w.width_m
		p.points = w.polyline
		p.cumulative = PackedFloat32Array([0.0])
		var d := 0.0
		for i in range(w.polyline.size() - 1):
			d += Vector2(w.polyline[i + 1].x - w.polyline[i].x, w.polyline[i + 1].z - w.polyline[i].z).length()
			p.cumulative.append(d)
		p.length = d
		if d < 0.5:
			continue
		p.start_key = _key(w.polyline[0])
		p.end_key = _key(w.polyline[w.polyline.size() - 1])
		g.paths.append(p)
		for key in [p.start_key, p.end_key]:
			if not g._by_key.has(key):
				g._by_key[key] = []
			g._by_key[key].append(p.id)
		var mid := p.position_at(d * 0.5)
		var cell := Vector2i(int(floor(mid.x / CELL_M)), int(floor(mid.z / CELL_M)))
		if not g._cells.has(cell):
			g._cells[cell] = []
		g._cells[cell].append(p.id)
	return g


static func _key(p: Vector3) -> Vector2i:
	return Vector2i(int(round(p.x / JOIN_M)), int(round(p.z / JOIN_M)))


## Ids of the other paths touching the given end of `path` (true = its end, false = its start).
func connections(path: WalkPath, at_end: bool) -> Array:
	var key := path.end_key if at_end else path.start_key
	var out: Array = []
	for pid in _by_key.get(key, []):
		if pid != path.id:
			out.append(pid)
	return out


## Whether `other` is entered at its start (true) or its end (false) from the given key.
func enters_at_start(other: WalkPath, key: Vector2i) -> bool:
	return other.start_key == key


## Paths whose midpoint lies within `radius` of a position.
func paths_near(position: Vector3, radius: float) -> Array[WalkPath]:
	var out: Array[WalkPath] = []
	var cells := int(ceil(radius / CELL_M))
	var cx := int(floor(position.x / CELL_M))
	var cz := int(floor(position.z / CELL_M))
	for dx in range(-cells, cells + 1):
		for dz in range(-cells, cells + 1):
			for pid in _cells.get(Vector2i(cx + dx, cz + dz), []):
				var p: WalkPath = paths[pid]
				var mid := p.position_at(p.length * 0.5)
				if Vector2(mid.x - position.x, mid.z - position.z).length() <= radius:
					out.append(p)
	return out
