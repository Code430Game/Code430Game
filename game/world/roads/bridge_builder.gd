class_name BridgeBuilder
extends RefCounted
## Solid bridges from bridges.v0.json (add-bridge-structures): a deck slab under every deck
## strip (road edges and the walkways that ride along them) with its top just under the
## road surface, fascia faces down both edges and a soffit underneath, so a bridge is concrete
## from below instead of a see-through ribbon; wall piers or round columns where the importer
## placed them; and an abutment at each end where the deck meets its approach.
##
## The importer's half-widths are left and right of travel along the strip's points (north
## when heading east); RoadGeometry.miter_normals points right, so left is minus the normal.

const TOP_BELOW_M := 0.04  # deck top sits just under the road and sidewalk ribbons
const PIER_THICKNESS_M := 0.9
const COLUMN_RADIUS_M := 0.7
const COLUMN_SIDES := 10
const ABUTMENT_THICKNESS_M := 1.4
const ABUTMENT_DEPTH_M := 12.0  # down into the embankment; the terrain hides what it covers
const DECK_COLOR := Color(0.6, 0.6, 0.58)
const SOFFIT_COLOR := Color(0.47, 0.47, 0.46)  # underside, out of the sun
const PIER_COLOR := Color(0.56, 0.56, 0.54)


class Deck:
	extends RefCounted
	var source: String
	var points: PackedVector3Array
	var left_m: PackedFloat32Array
	var right_m: PackedFloat32Array


class Bridge:
	extends RefCounted
	var id: String
	var kind: String
	var name: String
	var depth_m: float
	var decks: Array[Deck] = []
	var piers: Array[Dictionary] = []  # {pos: Vector3 (x, top_y, z), bottom_y, dir: Vector2, width_m, kind}
	var ends: Array[Dictionary] = []  # {pos: Vector3, dir: Vector2, width_m}


## Reads bridges.v0.json; empty when the pack has none.
static func load_bridges(pack_dir: String) -> Array[Bridge]:
	var out: Array[Bridge] = []
	var path := pack_dir.path_join("bridges.v0.json")
	if not FileAccess.file_exists(path):
		return out
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("BridgeBuilder: bad JSON in %s" % path)
		return out
	for b: Dictionary in parsed.get("bridges", []):
		var br := Bridge.new()
		br.id = b["id"]
		br.kind = b["kind"]
		br.name = str(b["name"]) if b["name"] != null else ""
		br.depth_m = float(b["depth_m"])
		for d: Dictionary in b["decks"]:
			var deck := Deck.new()
			deck.source = d["source"]
			for p in d["points"]:
				deck.points.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
			deck.left_m = PackedFloat32Array(d["left_m"])
			deck.right_m = PackedFloat32Array(d["right_m"])
			br.decks.append(deck)
		for p: Dictionary in b["piers"]:
			br.piers.append({
				"pos": Vector3(float(p["x"]), float(p["top_y"]), float(p["z"])),
				"bottom_y": float(p["bottom_y"]),
				"dir": Vector2(float(p["dir"][0]), float(p["dir"][1])),
				"width_m": float(p["width_m"]),
				"kind": p["kind"],
			})
		for e: Dictionary in b["ends"]:
			br.ends.append({
				"pos": Vector3(float(e["x"]), float(e["y"]), float(e["z"])),
				"dir": Vector2(float(e["dir"][0]), float(e["dir"][1])),
				"width_m": float(e["width_m"]),
			})
		out.append(br)
	return out


## chunk -> RoadMeshBuilder.ChunkTriangles for every bridge's deck, piers and abutments.
static func build(bridges: Array[Bridge]) -> Dictionary:
	var buckets := {}
	for b in bridges:
		for d in b.decks:
			_deck(buckets, d, b.depth_m)
		for p in b.piers:
			var out := _bucket(buckets, p["pos"])
			if p["kind"] == "column":
				_column(out, p["pos"], p["bottom_y"])
			else:
				_wall(out, p["pos"], p["bottom_y"], p["dir"], p["width_m"])
		for e in b.ends:
			_abutment(_bucket(buckets, e["pos"]), e["pos"], e["dir"], e["width_m"], b.depth_m)
	return buckets


static func _bucket(buckets: Dictionary, p: Vector3) -> RoadMeshBuilder.ChunkTriangles:
	var c := RoadGeometry.chunk_of(p)
	if not buckets.has(c):
		buckets[c] = RoadMeshBuilder.ChunkTriangles.new()
	return buckets[c]


## Deck slab along one strip: top (just under the ribbon), two fascia faces, the soffit, and
## end caps. Each segment goes to the chunk of its midpoint.
static func _deck(buckets: Dictionary, d: Deck, depth: float) -> void:
	var pl := d.points
	if pl.size() < 2:
		return
	var normals := RoadGeometry.miter_normals(pl)
	var lefts: Array[Vector3] = []
	var rights: Array[Vector3] = []
	for i in range(pl.size()):
		var n := Vector3(normals[i].x, 0.0, normals[i].y)
		var top := pl[i] - Vector3(0.0, TOP_BELOW_M, 0.0)
		lefts.append(top - n * d.left_m[i])
		rights.append(top + n * d.right_m[i])
	var down := Vector3(0.0, -(depth - TOP_BELOW_M), 0.0)
	for i in range(pl.size() - 1):
		var out := _bucket(buckets, (pl[i] + pl[i + 1]) * 0.5)
		var l0 := lefts[i]
		var l1 := lefts[i + 1]
		var r0 := rights[i]
		var r1 := rights[i + 1]
		var n := Vector3(normals[i].x, 0.0, normals[i].y)
		BarrierBuilder._quad_facing(out, l0, r0, l1, r1, Vector3.UP, DECK_COLOR)  # top
		BarrierBuilder._quad_facing(out, l0 + down, r0 + down, l1 + down, r1 + down, Vector3.DOWN, SOFFIT_COLOR)
		BarrierBuilder._quad_facing(out, l0, l0 + down, l1, l1 + down, -n, DECK_COLOR)  # left fascia
		BarrierBuilder._quad_facing(out, r0, r0 + down, r1, r1 + down, n, DECK_COLOR)  # right fascia
		if i == 0:
			var back := pl[0] - pl[1]
			back.y = 0.0
			BarrierBuilder._quad_facing(out, l0, l0 + down, r0, r0 + down, back.normalized(), DECK_COLOR)
		if i == pl.size() - 2:
			var fwd := pl[i + 1] - pl[i]
			fwd.y = 0.0
			BarrierBuilder._quad_facing(out, l1, l1 + down, r1, r1 + down, fwd.normalized(), DECK_COLOR)


## A box: `centre` at the top middle, `along` and `across` unit vectors, sizes, `height` down.
static func _box(out: RoadMeshBuilder.ChunkTriangles, top_centre: Vector3, along: Vector3, across: Vector3, half_along: float, half_across: float, height: float, color: Color, with_bottom: bool = false) -> void:
	var down := Vector3(0.0, -height, 0.0)
	var c: Array[Vector3] = []
	for sa in [-1.0, 1.0]:
		for sc in [-1.0, 1.0]:
			c.append(top_centre + along * (half_along * sa) + across * (half_across * sc))
	# c: 0 (-a,-c) 1 (-a,+c) 2 (+a,-c) 3 (+a,+c)
	BarrierBuilder._quad_facing(out, c[0], c[0] + down, c[1], c[1] + down, -along, color)
	BarrierBuilder._quad_facing(out, c[2], c[2] + down, c[3], c[3] + down, along, color)
	BarrierBuilder._quad_facing(out, c[0], c[0] + down, c[2], c[2] + down, -across, color)
	BarrierBuilder._quad_facing(out, c[1], c[1] + down, c[3], c[3] + down, across, color)
	BarrierBuilder._quad_facing(out, c[0], c[1], c[2], c[3], Vector3.UP, color)
	if with_bottom:
		BarrierBuilder._quad_facing(out, c[0] + down, c[1] + down, c[2] + down, c[3] + down, Vector3.DOWN, color)


static func _wall(out: RoadMeshBuilder.ChunkTriangles, top: Vector3, bottom_y: float, dir: Vector2, width: float) -> void:
	var along := Vector3(dir.x, 0.0, dir.y).normalized()
	var across := Vector3(-along.z, 0.0, along.x)
	_box(out, top, along, across, PIER_THICKNESS_M * 0.5, width * 0.5, top.y - bottom_y, PIER_COLOR)


static func _column(out: RoadMeshBuilder.ChunkTriangles, top: Vector3, bottom_y: float) -> void:
	for k in range(COLUMN_SIDES):
		var a0 := TAU * k / COLUMN_SIDES
		var a1 := TAU * (k + 1) / COLUMN_SIDES
		var p0 := top + Vector3(cos(a0), 0.0, sin(a0)) * COLUMN_RADIUS_M
		var p1 := top + Vector3(cos(a1), 0.0, sin(a1)) * COLUMN_RADIUS_M
		var b0 := Vector3(p0.x, bottom_y, p0.z)
		var b1 := Vector3(p1.x, bottom_y, p1.z)
		var outward := Vector3(cos((a0 + a1) * 0.5), 0.0, sin((a0 + a1) * 0.5))
		BarrierBuilder._quad_facing(out, p0, b0, p1, b1, outward, PIER_COLOR)


## A slab across the deck end, from under the deck down into the embankment, so the gap
## between deck and terrain is closed wherever the ground falls away.
static func _abutment(out: RoadMeshBuilder.ChunkTriangles, end: Vector3, dir: Vector2, width: float, depth: float) -> void:
	var off_deck := Vector3(dir.x, 0.0, dir.y).normalized()
	var across := Vector3(-off_deck.z, 0.0, off_deck.x)
	var top := end - off_deck * (ABUTMENT_THICKNESS_M * 0.5) - Vector3(0.0, depth, 0.0)
	_box(out, top, off_deck, across, ABUTMENT_THICKNESS_M * 0.5, width * 0.5 + 0.5, ABUTMENT_DEPTH_M, PIER_COLOR)


static func material() -> StandardMaterial3D:
	return BarrierBuilder.material()
