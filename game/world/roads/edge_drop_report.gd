class_name EdgeDropReport
## Wheel traps: places where the ground just past a road's edge sits well below the road, with
## nothing else (another road, a junction, a sidewalk or path) covering it, so a tyre that
## leaves the road drops in. Ground-level roads only (no bridges or tunnels). Each spot is one
## row with its x, z, the drop and the road, nearby samples merged.
## godot --headless --path game -s res://world/build/edge_drop_report.gd -- [pack id] [rows]

const DROP_M := 0.25  # a drop deeper than this traps a wheel (vehicle_damage.json small_bump_m is 0.3)
const STEP_M := 2.0  # along each road
const OUT_M := [0.4, 1.0]  # how far past the road's edge the ground is sampled
const MERGE_M := 12.0  # samples this close on one road are one spot
const CELL_M := 16.0
const COVER_DY_M := 1.0  # a surface this close in height covers the ground


## {"rows": [{x, z, drop_m, road, side}], "counts": {...}}, deepest first.
static func analyse(pack: MapPack) -> Dictionary:
	var g := pack.graph
	var grid := _cover_grid(pack)
	var rows: Array = []
	var counts := {"roads": 0, "samples": 0, "drops": 0, "spots": 0}
	for e: RoadGraph.RoadEdge in g.edges.values():
		if e.bridge or e.tunnel or e.polyline.size() < 2:
			continue
		counts["roads"] += 1
		var half := e.width_m * 0.5
		var last := {}  # side -> the row this road's spot on that side is growing
		var walked := 0.0
		for i in range(e.polyline.size() - 1):
			var a := e.polyline[i]
			var b := e.polyline[i + 1]
			var seg := Vector2(b.x - a.x, b.z - a.z)
			var length := seg.length()
			if length < 0.01:
				continue
			var n := Vector2(-seg.y, seg.x) / length
			var steps := maxi(1, int(length / STEP_M))
			for s in range(steps):
				var t := (s + 0.5) / steps
				var c := a.lerp(b, t)
				for side: int in [-1, 1]:
					var deepest := 0.0
					var at := Vector2.ZERO
					for out: float in OUT_M:
						var q := Vector2(c.x, c.z) + n * side * (half + out)
						counts["samples"] += 1
						var ground := pack.ground_height(q.x, q.y)
						if is_nan(ground) or _covered(grid, q, c.y):
							continue
						var drop := c.y - ground
						if drop > deepest:
							deepest = drop
							at = q
					if deepest <= DROP_M:
						continue
					counts["drops"] += 1
					var row: Dictionary = last.get(side, {})
					var along := walked + length * t
					if not row.is_empty() and along - float(row["_along"]) <= MERGE_M:
						row["_along"] = along
						if deepest > float(row["drop_m"]):
							row["drop_m"] = deepest
							row["x"] = at.x
							row["z"] = at.y
						continue
					row = {"x": at.x, "z": at.y, "drop_m": deepest, "road": e.name if e.name != "" else e.road_class, "class": e.road_class, "side": "left" if side > 0 else "right", "_along": along}
					rows.append(row)
					last[side] = row
			walked += length
	rows.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return float(p["drop_m"]) > float(q["drop_m"]))
	for r: Dictionary in rows:
		r.erase("_along")
	counts["spots"] = rows.size()
	return {"rows": rows, "counts": counts}


static func format(report: Dictionary, limit: int = 40) -> String:
	var c: Dictionary = report["counts"]
	var lines := PackedStringArray()
	lines.append("edge drop report: %d spots where the ground past a road's edge is more than %.2f m below it (%d of %d samples, %d ground-level roads)" % [c["spots"], DROP_M, c["drops"], c["samples"], c["roads"]])
	for r: Dictionary in (report["rows"] as Array).slice(0, limit):
		lines.append("  %5.2f m  x %.0f, z %.0f  %s (%s), %s side" % [r["drop_m"], r["x"], r["z"], r["road"], r["class"], r["side"]])
	return "\n".join(lines)


## Every surface that can cover the ground beside a road, by grid cell: road ribbons, junction
## outlines, and sidewalk, path and cycleway ribbons.
static func _cover_grid(pack: MapPack) -> Dictionary:
	var grid := {}
	for e: RoadGraph.RoadEdge in pack.graph.edges.values():
		if not e.tunnel:
			_add_ribbon(grid, e.polyline, e.width_m * 0.5)
	for w: RoadGraph.PedestrianWay in pack.graph.pedestrian:
		if not w.covered and w.profile != "tunnel":
			_add_ribbon(grid, w.polyline, maxf(w.width_m, 1.0) * 0.5)
	for j: JunctionBuilder.Junction in pack.junctions.values():
		if j.polygon_xz.size() < 3:
			continue
		var item := {"poly": j.polygon_xz, "y": j.centre.y}
		var box := Rect2(j.polygon_xz[0], Vector2.ZERO)
		for v in j.polygon_xz:
			box = box.expand(v)
		_add_box(grid, box, item)
	return grid


static func _add_ribbon(grid: Dictionary, pl: PackedVector3Array, half: float) -> void:
	for i in range(pl.size() - 1):
		var a := pl[i]
		var b := pl[i + 1]
		var item := {"a": Vector2(a.x, a.z), "b": Vector2(b.x, b.z), "ya": a.y, "yb": b.y, "half": half + 0.05}
		var box := Rect2(Vector2(a.x, a.z), Vector2.ZERO).expand(Vector2(b.x, b.z)).grow(half + 0.05)
		_add_box(grid, box, item)


static func _add_box(grid: Dictionary, box: Rect2, item: Dictionary) -> void:
	for cx in range(floori(box.position.x / CELL_M), floori(box.end.x / CELL_M) + 1):
		for cz in range(floori(box.position.y / CELL_M), floori(box.end.y / CELL_M) + 1):
			var key := Vector2i(cx, cz)
			if not grid.has(key):
				grid[key] = []
			(grid[key] as Array).append(item)


## Whether a surface within COVER_DY_M of `y` covers point `q`.
static func _covered(grid: Dictionary, q: Vector2, y: float) -> bool:
	for item: Dictionary in grid.get(Vector2i(floori(q.x / CELL_M), floori(q.y / CELL_M)), []):
		if item.has("poly"):
			if absf(float(item["y"]) - y) <= COVER_DY_M and Geometry2D.is_point_in_polygon(q, item["poly"]):
				return true
			continue
		var a: Vector2 = item["a"]
		var b: Vector2 = item["b"]
		var ab := b - a
		var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		if q.distance_to(a + ab * t) <= float(item["half"]) and absf(lerpf(float(item["ya"]), float(item["yb"]), t) - y) <= COVER_DY_M:
			return true
	return false
