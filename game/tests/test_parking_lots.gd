extends GdUnitTestSuite
## Parking lots: stall layout from aisles, a virtual aisle, diagonal stalls, capacity; the
## asphalt follows the terrain; markings, curb stops and a sign get built.


func _graph_with_aisle() -> RoadGraph:
	var nodes := [
		{"id": "a", "position": [30.0, 0.0, 0.0], "ground_y": 0, "junction_type": "junction"},
		{"id": "b", "position": [30.0, 0.0, 48.0], "ground_y": 0, "junction_type": "dead_end"},
	]
	var edges := [{"id": "w2.0", "from": "a", "to": "b", "polyline": [[30.0, 0.0, 0.0], [30.0, 0.0, 48.0]], "class": "parking",
		"lanes_forward": 1, "lanes_backward": 1, "oneway": false, "speed_kph": 15, "width_m": 5.5, "layer": 0, "bridge": false,
		"tunnel": false, "name": "", "osm_way_id": 2, "defaulted_fields": [], "access": null, "length_m": 48.0, "bus": "", "bus_lane": -1}]
	return RoadGraph.from_dict({"meta": {}, "nodes": nodes, "edges": edges, "pedestrian_ways": [], "bus_stops": []})


func _lot(rings: Array, extra: Dictionary = {}) -> Dictionary:
	var d := {"id": "w10.0", "kind": "surface", "stall_dir": [0, 1], "ground_y": 70.0, "rings": rings, "aisles": [], "entrances": [], "osm_id": 10}
	d.merge(extra, true)
	return d


const SQUARE := [[[0, 2], [60, 2], [60, 50], [0, 50]]]


func test_stalls_line_both_sides_of_the_aisle_inside_the_lot() -> void:
	var lot := ParkingLotBuilder.lot_from_dict(_lot(SQUARE, {"aisles": ["w2.0"]}), _graph_with_aisle())
	assert_int(lot.stalls.size()).is_greater(20)  # a 60 x 48 m lot with an aisle down the middle
	var left := 0
	var right := 0
	for s in lot.stalls:
		for c in ParkingLotBuilder.stall_corners(s):
			assert_bool(ParkingLotBuilder.contains(lot, c)).is_true()
		assert_float(absf(s.centre.x - 30.0)).is_greater(2.75)  # clear of the aisle
		if s.centre.x < 30.0:
			left += 1
			assert_float(s.facing.x).is_less(-0.99)  # nose away from the aisle
		else:
			right += 1
	assert_int(left).is_equal(right)
	for i in range(lot.stalls.size()):
		for j in range(i + 1, lot.stalls.size()):
			assert_float(lot.stalls[i].centre.distance_to(lot.stalls[j].centre)).is_greater(2.4)


func test_a_lot_without_aisles_gets_a_virtual_one() -> void:
	var lot := ParkingLotBuilder.lot_from_dict(_lot([[[100, 20], [140, 20], [140, 34], [100, 34]]], {"stall_dir": [1, 0]}), null)
	assert_int(lot.stalls.size()).is_greater(4)
	for s in lot.stalls:
		assert_float(absf(s.facing.y)).is_greater(0.99)  # stalls off an east-west aisle face north or south


func test_diagonal_stalls_are_angled_and_capacity_caps_the_count() -> void:
	var diag := ParkingLotBuilder.lot_from_dict(_lot(SQUARE, {"aisles": ["w2.0"], "orientation": "diagonal"}), _graph_with_aisle())
	assert_int(diag.stalls.size()).is_greater(0)
	for s in diag.stalls:
		assert_float(absf(s.facing.x)).is_between(0.6, 0.8)  # about 45 degrees
	var capped := ParkingLotBuilder.lot_from_dict(_lot(SQUARE, {"aisles": ["w2.0"], "capacity": 7}), _graph_with_aisle())
	assert_int(capped.stalls.size()).is_equal(7)


func _sloped_heights() -> TerrainBuilder.ChunkHeights:
	var h := TerrainBuilder.ChunkHeights.new()
	h.cx = 0
	h.cz = 0
	h.samples = 65
	h.resolution_m = 4.0
	for r in range(65):
		for c in range(65):
			h.heights.append(70.0 + c * 4.0 * 0.05)  # rises 5 cm per metre eastward
	return h


func test_asphalt_follows_the_terrain_and_props_get_built() -> void:
	var lot := ParkingLotBuilder.lot_from_dict(_lot(SQUARE, {"aisles": ["w2.0"], "entrances": [[30, 70, 0]]}), _graph_with_aisle())
	var heights := _sloped_heights()
	var built := ParkingLotBuilder.build_chunk([lot], Vector2i(0, 0), heights, 256.0)
	var surface: RoadMeshBuilder.ChunkTriangles = built["surface"]
	assert_bool(surface.is_empty()).is_false()
	var area := 0.0
	for t in range(0, surface.vertices.size(), 3):
		var a := surface.vertices[t]
		var b := surface.vertices[t + 1]
		var c := surface.vertices[t + 2]
		for v in [a, b, c]:
			assert_float(v.y).is_equal_approx(heights.sample(v.x, v.z) + ParkingLotBuilder.LIFT_M, 0.001)
		var n := (b - a).cross(c - a)
		assert_float(n.y).is_less(0.0)  # wound to face up (cross product points away from the viewer)
		area += absf(n.y) * 0.5
	assert_float(area).is_equal_approx(60.0 * 48.0, 1.0)  # covers the lot, no more, no less
	assert_bool((built["markings"] as RoadMeshBuilder.ChunkTriangles).is_empty()).is_false()
	assert_bool((built["props"] as RoadMeshBuilder.ChunkTriangles).is_empty()).is_false()
	var labels: Array = built["labels"]
	assert_int(labels.size()).is_equal(1)
	assert_str(str(labels[0][2])).is_equal("P")  # no operator: a plain P


func test_lots_are_bucketed_into_every_chunk_they_touch() -> void:
	var lot := ParkingLotBuilder.lot_from_dict(_lot([[[250, 10], [262, 10], [262, 30], [250, 30]]]), null)
	var buckets := ParkingLotBuilder.by_chunk([lot], 256.0)
	assert_bool(buckets.has(Vector2i(0, 0))).is_true()
	assert_bool(buckets.has(Vector2i(1, 0))).is_true()


func test_stalls_keep_off_a_street_the_lot_outline_overlaps() -> void:
	# The lot's south edge runs over the middle of a 7 m street along z = 6.
	var nodes := [
		{"id": "a", "position": [-50.0, 0.0, 6.0], "ground_y": 0, "junction_type": "junction"},
		{"id": "b", "position": [200.0, 0.0, 6.0], "ground_y": 0, "junction_type": "junction"},
	]
	var edges := [{"id": "w5.0", "from": "a", "to": "b", "polyline": [[-50.0, 0.0, 6.0], [200.0, 0.0, 6.0]], "class": "residential",
		"lanes_forward": 1, "lanes_backward": 1, "oneway": false, "speed_kph": 40, "width_m": 7.0, "layer": 0, "bridge": false,
		"tunnel": false, "name": "", "osm_way_id": 5, "defaulted_fields": [], "access": null, "length_m": 250.0, "bus": "", "bus_lane": -1}]
	var g := RoadGraph.from_dict({"meta": {}, "nodes": nodes, "edges": edges, "pedestrian_ways": [], "bus_stops": []})
	var lot := ParkingLotBuilder.lot_from_dict(_lot([[[0, 2], [60, 2], [60, 30], [0, 30]]], {"stall_dir": [1, 0]}), g, ParkingLotBuilder.street_grid(g))
	assert_int(lot.stalls.size()).is_greater(0)
	for s in lot.stalls:
		for c in ParkingLotBuilder.stall_corners(s):
			assert_float(c.y).is_greater(6.0 + 3.5)  # clear of the carriageway


func test_a_strip_lot_too_shallow_for_an_aisle_gets_one_row() -> void:
	var lot := ParkingLotBuilder.lot_from_dict(_lot([[[0, 0], [40, 0], [40, 9], [0, 9]]], {"stall_dir": [1, 0]}), null)
	assert_int(lot.stalls.size()).is_greater(10)
	for s in lot.stalls:
		assert_float(s.centre.y).is_equal_approx(4.5, 0.01)  # down the middle
		for c in ParkingLotBuilder.stall_corners(s):
			assert_bool(ParkingLotBuilder.contains(lot, c)).is_true()


## #88: a lot's entrance sign stood in the street's travel lane (an offset from the entrance
## point, which is on the street). Every sign now stands inside its lot, clear of every road and
## aisle and of the stalls; most lots with an entrance still get one.
func test_in_ottawa_lot_signs_stand_inside_the_lot_and_off_the_roads() -> void:
	var pack := MapPack.new()
	assert_bool(pack.load(PackLocator.find_pack("code430.ottawa-centretown"))).is_true()
	var with_entrance := 0
	var signed := 0
	for lot: ParkingLotBuilder.Lot in pack.parking_lots:
		if lot.entrances.is_empty():
			continue
		with_entrance += 1
		if lot.sign_spot == Vector2.INF:
			continue
		signed += 1
		var p := lot.sign_spot
		assert_bool(ParkingLotBuilder.contains(lot, p)).override_failure_message("%s: sign outside the lot" % lot.id).is_true()
		var hit := pack.graph.nearest_edge(Vector3(p.x, 0.0, p.y), 30.0)
		if not hit.is_empty():
			var half := (hit["edge"] as RoadGraph.RoadEdge).width_m * 0.5
			assert_float(float(hit["distance"])).override_failure_message("%s: sign on %s at %s" % [lot.id, hit["edge"].id, p]).is_greater(half + 1.0)
	print("lot signs: %d of %d lots with an entrance" % [signed, with_entrance])
	assert_float(float(signed) / float(maxi(with_entrance, 1))).is_greater(0.5)
