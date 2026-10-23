extends SceneTree
## Headless dump of the game's junction outlines (JunctionBuilder) for a road graph file, as
## JSON: node id -> {"polygon": [[x, z], ...], "heights": [...], "hull": bool}. The importer's
## port of the outline (osm_import.junctions) is tested against this on the proving ground
## (update-junction-ground 2.1); tools/tests/fixtures/proving_ground_junctions.json is made by:
## godot --headless --path game -s res://world/build/junction_outline_dump.gd -- <road_graph.v0.json> <out.json>


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("usage: junction_outline_dump.gd -- <road_graph.v0.json> <out.json>")
		quit(1)
		return
	var graph := RoadGraph.load_from_file(args[0])
	if graph == null:
		quit(1)
		return
	var junctions := JunctionBuilder.build_all(graph)
	var out := {}
	for nid in junctions:
		var j: JunctionBuilder.Junction = junctions[nid]
		var polygon: Array = []
		for p in j.polygon_xz:
			polygon.append([snappedf(p.x, 0.001), snappedf(p.y, 0.001)])
		var heights: Array = []
		for h in j.heights:
			heights.append(snappedf(h, 0.001))
		out[nid] = {"polygon": polygon, "heights": heights, "hull": j.fallback_hull}
	out["_road_graph_sha256"] = FileAccess.get_sha256(args[0])
	var f := FileAccess.open(args[1], FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "", true) + "\n")
	f.close()
	print("junction outlines: %d written to %s" % [out.size(), args[1]])
	quit(0)
