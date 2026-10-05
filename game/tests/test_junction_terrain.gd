extends GdUnitTestSuite
## Grass through roads: on the Ottawa pack, how many junction surfaces have terrain poking up
## through them. Each junction is sampled 60% and 85% of the way from its centre to each outline
## vertex (the corners between arms); the terrain must stay at least 5 cm below the surface.

const PACK_ID := "code430.ottawa-centretown"
const POKE_M := 0.05
## A regression guard as a share of junctions, so it holds as the graph grows: 2026-10-04, 16 of
## 915 (1.7%) on main's pack, 47 of 1,936 (2.4%) with parking aisles and driveways (backlog).
const MAX_POKING_SHARE := 0.03


func test_terrain_stays_under_junction_surfaces() -> void:
	var pack := MapPack.new()
	assert_bool(pack.load(PackLocator.find_pack(PACK_ID))).is_true()
	var chunks := {}
	for e in pack.terrain_index["chunks"]:
		chunks[Vector2i(int(e["cx"]), int(e["cz"]))] = e
	var loaded := {}
	var poking: Array[String] = []
	var checked := 0
	for nid in pack.junctions:
		var j: JunctionBuilder.Junction = pack.junctions[nid]
		if j.polygon_xz.size() < 3:
			continue
		var samples: Array = []  # [x, z, surface y]
		# Inside the surface only: at the outline itself the 4 m terrain grid is half road, half
		# hillside, so it can stand above the asphalt's edge without showing through it.
		for i in range(j.polygon_xz.size()):
			var v := j.polygon_xz[i]
			for f: float in [0.6, 0.85]:
				samples.append([lerpf(j.centre.x, v.x, f), lerpf(j.centre.z, v.y, f), lerpf(j.centre.y, j.heights[i], f)])
		var worst := -INF
		for s: Array in samples:
			var key := RoadGeometry.chunk_of(Vector3(s[0], 0.0, s[1]))
			if not chunks.has(key):
				continue
			if not loaded.has(key):
				loaded[key] = TerrainBuilder.load_chunk(pack.pack_dir, pack.terrain_index, chunks[key])
			var h: TerrainBuilder.ChunkHeights = loaded[key]
			if h == null:
				continue
			worst = maxf(worst, h.sample(s[0], s[1]) - float(s[2]))
		if worst == -INF:
			continue
		checked += 1
		if worst > POKE_M:
			poking.append("%s (+%.2f m)" % [nid, worst])
	print("junction terrain: %d of %d junctions have terrain above the surface by > %d cm: %s" % [poking.size(), checked, int(POKE_M * 100), ", ".join(poking.slice(0, 12))])
	assert_int(checked).is_greater(500)
	assert_float(float(poking.size()) / checked).is_less_equal(MAX_POKING_SHARE)
