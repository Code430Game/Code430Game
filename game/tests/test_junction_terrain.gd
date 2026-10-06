extends GdUnitTestSuite
## Grass through roads: on the Ottawa pack, how many junction surfaces have terrain poking up
## through them (JunctionReport.terrain_above: sampled 60% and 85% of the way from the centre to
## each outline vertex, at least 5 cm). Junctions with a tunnel arm are left out: the terrain over
## a tunnel mouth is the hillside the tunnel goes into (update-junction-surfaces).

const PACK_ID := "code430.ottawa-centretown"
## A regression guard as a share of junctions, so it holds as the graph grows: 2026-10-04, 16 of
## 915 (1.7%) on main's pack, 47 of 1,936 (2.4%) with parking aisles and driveways; 2026-10-06
## (update-junction-surfaces: outlines that follow their roads, corners flattened in the
## importer, tunnels apart) 14 of about 1,930, none over 0.25 m.
const MAX_POKING_SHARE := 0.01
const MAX_POKE_M := 0.5


func test_terrain_stays_under_junction_surfaces() -> void:
	var pack := MapPack.new()
	assert_bool(pack.load(PackLocator.find_pack(PACK_ID))).is_true()
	var report := JunctionReport.analyse(pack, true)
	var counts: Dictionary = report["counts"]
	var poking: Array[String] = []
	var worst := 0.0
	for r: Dictionary in report["rows"]:
		var above := float(r.get("terrain_m", -INF))
		if above > JunctionReport.POKE_M:
			poking.append("%s (+%.2f m)" % [r["node"], above])
			worst = maxf(worst, above)
	var checked := int(counts["junctions"]) - int(counts["tunnel"])
	print("junction terrain: %d of %d junctions have terrain above the surface by > %d cm (%d at tunnels not checked): %s" % [poking.size(), checked, int(JunctionReport.POKE_M * 100), counts["tunnel"], ", ".join(poking.slice(0, 12))])
	assert_int(checked).is_greater(500)
	assert_float(float(poking.size()) / checked).is_less_equal(MAX_POKING_SHARE)
	assert_float(worst).override_failure_message("terrain stands %.2f m above a junction" % worst).is_less_equal(MAX_POKE_M)
