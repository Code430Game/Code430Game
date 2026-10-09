extends GdUnitTestSuite
## update-garage-polish: the minimap draws the garage floor while the player is on a garage
## level, and a ramp's terrain cut ends at the strip, under the coping, with no hole past it.

const PACK_ID := "code430.ottawa-centretown"

var _pack: MapPack


func before() -> void:
	_pack = MapPack.new()
	assert_bool(_pack.load(PackLocator.find_pack(PACK_ID))).is_true()


func _pack_garage(name: String) -> GarageBuilder.Garage:
	for g in _pack.garages:
		if g.name == name:
			return g
	return null


## A 40 m square level, floor 60, ceiling 63, with one 25 m ramp down from a street at 66.
static func _garage(tier: String = "garage") -> GarageBuilder.Garage:
	var g := GarageBuilder.Garage.new()
	g.id = "t"
	g.tier = tier
	g.floor_y = 60.0
	g.ceiling_y = 63.0
	g.outer = PackedVector2Array([Vector2(0, 0), Vector2(40, 0), Vector2(40, 40), Vector2(0, 40)])
	var r := GarageBuilder.Ramp.new()
	r.start = Vector3(20, 66, -25)
	r.end = Vector3(20, 60, 0)
	r.dir = Vector2(0, 1)
	g.ramps.append(r)
	return g


func test_level_at_is_the_floor_and_the_ramp_below_its_top() -> void:
	var g := _garage()
	var gs: Array[GarageBuilder.Garage] = [g]
	assert_object(GarageBuilder.level_at(gs, Vector3(20, 60.8, 20))).is_same(g)  # on the floor
	assert_object(GarageBuilder.level_at(gs, Vector3(5, 61.0, 35))).is_same(g)
	assert_object(GarageBuilder.level_at(gs, Vector3(20, 66.5, 20))).is_null()  # the street above
	assert_object(GarageBuilder.level_at(gs, Vector3(20, 65.9, -24))).is_null()  # top of the ramp
	assert_object(GarageBuilder.level_at(gs, Vector3(20, 63.6, -15))).is_same(g)  # 10 m down it
	assert_object(GarageBuilder.level_at(gs, Vector3(30, 66.0, -15))).is_null()  # beside the ramp, on the street
	assert_object(GarageBuilder.level_at(gs, Vector3(60, 60.8, 20))).is_null()  # outside
	var door: Array[GarageBuilder.Garage] = [_garage("door")]
	assert_object(GarageBuilder.level_at(door, Vector3(20, 63.6, -15))).is_null()  # a door ramp has no level


func test_minimap_switches_to_the_floor_and_back_on_the_ramp() -> void:
	var g := _garage()
	var map: Minimap = auto_free(Minimap.new())
	var body: Node3D = auto_free(Node3D.new())
	add_child(body)
	map.player = body
	var gs: Array[GarageBuilder.Garage] = [g]
	map.garages = gs
	body.global_position = Vector3(20, 66.3, -30)  # on the street, before the ramp
	map._process(0.0)
	assert_object(map.garage).is_null()
	for k in range(1, 26):  # down the ramp and onto the floor
		var t := k / 25.0
		body.global_position = Vector3(20, lerpf(66.0, 60.0, t) + 0.5, lerpf(-25.0, 0.0, t))
		map._process(0.0)
		if t * 25.0 > GarageBuilder.RAMP_TOP_M + 0.5:
			assert_object(map.garage).override_failure_message("not inside at %.2f" % t).is_same(g)
	body.global_position = Vector3(20, 60.5, 20)
	map._process(0.0)
	assert_object(map.garage).is_same(g)
	body.global_position = Vector3(20, 65.8, -23)  # back up near the top: the street again
	map._process(0.0)
	assert_object(map.garage).is_null()


func test_the_nac_floor_and_ramp_switch_in_the_pack() -> void:
	var nac := _pack_garage("NAC underground parking")
	assert_object(nac).is_not_null()
	var s: ParkingLotBuilder.Stall = nac.lot.stalls[0]
	assert_object(GarageBuilder.level_at(_pack.garages, Vector3(s.centre.x, nac.floor_y + 0.6, s.centre.y))).is_same(nac)
	var r: GarageBuilder.Ramp = nac.ramps[0]
	assert_object(GarageBuilder.level_at(_pack.garages, r.start + Vector3(0, 0.6, 0))).is_null()
	var mid := r.start.lerp(r.end, 0.6)
	assert_object(GarageBuilder.level_at(_pack.garages, mid + Vector3(0, 0.6, 0))).is_same(nac)


static func _sloped_chunk() -> TerrainBuilder.ChunkHeights:
	var ch := TerrainBuilder.ChunkHeights.new()
	ch.cx = 0
	ch.cz = 0
	ch.samples = 65
	ch.resolution_m = 4.0
	ch.heights.resize(65 * 65)
	for r in range(65):
		for c in range(65):
			ch.heights[r * 65 + c] = 50.0 + 0.05 * c * 4.0 + 0.02 * r * 4.0
	return ch


static func _xz_area(mesh: ArrayMesh) -> float:
	var arrays := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var s := 0.0
	for i in range(0, idx.size(), 3):
		var a := Vector2(v[idx[i]].x, v[idx[i]].z)
		var b := Vector2(v[idx[i + 1]].x, v[idx[i + 1]].z)
		var c := Vector2(v[idx[i + 2]].x, v[idx[i + 2]].z)
		s += absf((b - a).cross(c - a)) * 0.5
	return s


func test_a_clipped_cut_removes_exactly_the_strip_at_every_lod() -> void:
	var ch := _sloped_chunk()
	var hole := {"a": Vector2(101.3, 60.7), "b": Vector2(83.0, 71.6), "half": 3.8, "clip": true}  # diagonal, like the museum ramp
	var strip_area: float = Vector2(101.3, 60.7).distance_to(Vector2(83.0, 71.6)) * 3.8 * 2.0
	for lod in range(3):
		var full := TerrainBuilder.build_mesh(ch, lod)
		var cut := TerrainBuilder.build_mesh(ch, lod, [hole])
		assert_float(_xz_area(full) - _xz_area(cut)).override_failure_message("lod %d" % lod).is_equal_approx(strip_area, 0.05)
		var arrays := cut.surface_get_arrays(0)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in range(0, idx.size(), 3):
			var centroid := (v[idx[i]] + v[idx[i + 1]] + v[idx[i + 2]]) / 3.0
			assert_bool(TerrainBuilder._in_hole([hole], centroid)).override_failure_message("lod %d: terrain over the ramp at %s" % [lod, centroid]).is_false()
			# Same winding as the grid: every face looks up.
			var face := (v[idx[i + 2]] - v[idx[i]]).cross(v[idx[i + 1]] - v[idx[i]])
			assert_float(face.y).is_greater(0.0)
		for i in range(v.size()):  # new vertices lie on the terrain's surface (a plane here)
			assert_float(v[i].y).is_equal_approx(50.0 + 0.05 * v[i].x + 0.02 * v[i].z, 0.001)
			assert_float(normals[i].y).is_greater(0.9)


## xz triangles of a mesh bucketed by 4 m cell, for coverage queries.
static func _buckets(mesh: ArrayMesh) -> Dictionary:
	var arrays := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var out := {}
	for i in range(0, idx.size(), 3):
		var tri := PackedVector2Array([Vector2(v[idx[i]].x, v[idx[i]].z), Vector2(v[idx[i + 1]].x, v[idx[i + 1]].z), Vector2(v[idx[i + 2]].x, v[idx[i + 2]].z)])
		var lo := Vector2i(floori(minf(tri[0].x, minf(tri[1].x, tri[2].x)) / 4.0), floori(minf(tri[0].y, minf(tri[1].y, tri[2].y)) / 4.0))
		var hi := Vector2i(floori(maxf(tri[0].x, maxf(tri[1].x, tri[2].x)) / 4.0), floori(maxf(tri[0].y, maxf(tri[1].y, tri[2].y)) / 4.0))
		for cx in range(lo.x, hi.x + 1):
			for cz in range(lo.y, hi.y + 1):
				var key := Vector2i(cx, cz)
				if not out.has(key):
					out[key] = []
				(out[key] as Array).append(tri)
	return out


static func _covered(buckets: Dictionary, p: Vector2) -> bool:
	for tri: PackedVector2Array in buckets.get(Vector2i(floori(p.x / 4.0), floori(p.y / 4.0)), []):
		if Geometry2D.point_is_inside_triangle(p, tri[0], tri[1], tri[2]):
			return true
	return false


## No terrain hole lies outside a ramp's walls: beside every ramp (under the wall and the
## coping, out to its far edge) and just past its ends the ground is still there, at every
## LOD, and over the ramp itself it is gone.
func test_no_terrain_hole_lies_outside_a_ramps_walls() -> void:
	var entries := {}
	for e: Dictionary in _pack.terrain_index["chunks"]:
		entries[Vector2i(int(e["cx"]), int(e["cz"]))] = e
	var meshes := {}  # "cx,cz,lod" -> buckets
	var half := GarageBuilder.RAMP_WIDTH_M * 0.5 + GarageBuilder.HOLE_PAD_M
	var outer := GarageBuilder.RAMP_WIDTH_M * 0.5 + GarageBuilder.WALL_M + GarageBuilder.COPING_M
	var checked := 0
	var museum_checked := 0
	for g in _pack.garages:
		for r in g.ramps:
			var a := Vector2(r.start.x, r.start.z)
			var b := Vector2(r.end.x, r.end.z)
			var along := (b - a).normalized()
			var side := Vector2(-along.y, along.x)
			var probes: Array = []  # [point, should_have_ground]
			for k in range(1, 10):
				var t := k / 10.0
				var on := a.lerp(b, t)
				probes.append([on, false])
				probes.append([on + side * (half - 0.3), false])
				for d: float in [half + 0.2, (half + outer) * 0.5, outer - 0.1]:
					probes.append([on + side * d, true])
					probes.append([on - side * d, true])
			probes.append([a - along * 0.3, true])  # just before the top of the ramp
			if g.tier == "door":
				probes.append([b + along * 0.3, true])  # past the door
			for pr: Array in probes:
				var p: Vector2 = pr[0]
				var coord := RoadGeometry.chunk_of(Vector3(p.x, 0.0, p.y))
				if not entries.has(coord):
					continue
				var holes: Array = _pack.terrain_holes.get(coord, [])
				if pr[1] and _near_other_hole(holes, p, r):
					continue
				for lod in range(3):
					var key := "%d,%d,%d" % [coord.x, coord.y, lod]
					if not meshes.has(key):
						var heights := TerrainBuilder.load_chunk(_pack.pack_dir, _pack.terrain_index, entries[coord])
						meshes[key] = _buckets(TerrainBuilder.build_mesh(heights, lod, holes))
					assert_bool(_covered(meshes[key], p)).override_failure_message("%s ramp at %s, lod %d: ground %s" % [g.id, p, lod, "missing" if pr[1] else "over the ramp"]).is_equal(pr[1])
					checked += 1
					if g.name == "Victoria Memorial Museum Building":
						museum_checked += 1
	assert_int(checked).is_greater(5000)
	assert_int(museum_checked).is_greater(100)


## True when `p` is in, or within a cell of, a hole other than ramp `r`'s (two ramps side by
## side, or an underpass whose quads are skipped whole).
static func _near_other_hole(holes: Array, p: Vector2, r: GarageBuilder.Ramp) -> bool:
	var own_a := Vector2(r.start.x, r.start.z)
	for h: Dictionary in holes:
		if (h["a"] as Vector2) == own_a:
			continue
		var grown := h.duplicate()
		grown["half"] = float(h["half"]) + 12.0
		var a: Vector2 = h["a"]
		var b: Vector2 = h["b"]
		var d := (b - a).normalized() * 12.0
		grown["a"] = a - d
		grown["b"] = b + d
		if TerrainBuilder._in_hole([grown], Vector3(p.x, 0.0, p.y)):
			return true
	return false


## #89, #90: a public garage's ramp mouth has a header with a P sign, and its walls carry lights;
## a private garage's ramp gets the lights but keeps its closed door instead of a sign.
func test_public_garage_entrances_are_signed_and_ramps_are_lit() -> void:
	var g := GarageBuilder.Garage.new()
	g.tier = "garage"
	var r := GarageBuilder.Ramp.new()
	r.start = Vector3(0, 10, 0)
	r.end = Vector3(0, 6, 20)
	r.dir = Vector2(0, 1)
	g.ramps.append(r)
	var built := GarageBuilder.build([g] as Array[GarageBuilder.Garage])
	var glow := 0
	var sign_glow := 0
	for t: RoadMeshBuilder.ChunkTriangles in (built["lights"] as Dictionary).values():
		var verts: PackedVector3Array = t.to_mesh().surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		glow += verts.size()
		for v in verts:
			if v.y > 10.0 + GarageBuilder.CLEARANCE_M:
				sign_glow += 1  # the P, above the header
	assert_int(sign_glow).is_greater(0)
	assert_int(glow - sign_glow).is_greater(0)  # wall lights down the ramp
	g.tier = "door"
	built = GarageBuilder.build([g] as Array[GarageBuilder.Garage])
	for t: RoadMeshBuilder.ChunkTriangles in (built["lights"] as Dictionary).values():
		for v in t.to_mesh().surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			assert_float(v.y).is_less(10.0 + GarageBuilder.CLEARANCE_M)  # no sign on a private ramp
