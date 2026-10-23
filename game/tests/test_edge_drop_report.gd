extends GdUnitTestSuite
## Wheel traps (EdgeDropReport): the ground past a road's edge must not drop away where a tyre
## falls in. The proving ground has one of everything, so its streets are the guard: none
## drops deeper than STREET_MAX_M. Motorway ramps beside bridge decks are still being worked on.

const STREET_MAX_M := 0.5


func test_the_proving_grounds_streets_have_no_deep_drops_at_their_edges() -> void:
	var pack: MapPack = auto_free(MapPack.new())
	assert_bool(pack.load(PackLocator.find_pack("code430.proving-ground"))).is_true()
	var report := EdgeDropReport.analyse(pack)
	var deep: Array = []
	for row: Dictionary in report["rows"]:
		if not str(row["class"]).begins_with("motorway") and float(row["drop_m"]) > STREET_MAX_M:
			deep.append("%.2f m at x %.0f, z %.0f (%s)" % [row["drop_m"], row["x"], row["z"], row["road"]])
	assert_array(deep).override_failure_message("deep drops at street edges: %s" % ", ".join(deep)).is_empty()
	assert_int(int(report["counts"]["roads"])).is_greater(100)


func test_format_lists_the_deepest_spots_first() -> void:
	var text := EdgeDropReport.format({"rows": [{"x": 1.0, "z": 2.0, "drop_m": 0.9, "road": "Bank Street", "class": "primary", "side": "left"}], "counts": {"roads": 1, "samples": 10, "drops": 1, "spots": 1}})
	assert_str(text).contains("1 spots").contains("0.90 m  x 1, z 2  Bank Street (primary), left side")
