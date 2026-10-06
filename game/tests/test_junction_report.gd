extends GdUnitTestSuite
## The junction report on the Ottawa pack (update-junction-surfaces): the junctions the human
## reported are clean, and the counts stay down. Before the change (2026-10-06): 464 of 1,938
## junctions bulged into the grass by over 1.5 m, 593 left part of an arm uncovered and 73 fell
## back to a convex hull; after: 2, 44 and 21, nearly all of them big clustered junctions.

const PACK_ID := "code430.ottawa-centretown"
## #78 "junction turns into ball" (Colonel By Drive) and #79 (a parking aisle off Graham Avenue).
const REPORTED := ["n901218147", "n6020506072"]


func test_the_reported_junctions_are_clean() -> void:
	var pack := MapPack.new()
	assert_bool(pack.load(PackLocator.find_pack(PACK_ID))).is_true()
	for nid: String in REPORTED:
		var j: JunctionBuilder.Junction = pack.junctions.get(nid)
		assert_object(j).override_failure_message("%s has no junction" % nid).is_not_null()
		assert_bool(j.fallback_hull).is_false()
		assert_float(JunctionReport.bulge_m(pack.graph, j)).override_failure_message("%s bulges" % nid).is_less_equal(JunctionReport.BULGE_M)
		assert_float(JunctionReport.gap_m(pack.graph, j)).override_failure_message("%s has a gap" % nid).is_less_equal(JunctionReport.GAP_M)


func test_few_junctions_bulge_leave_gaps_or_fall_back_to_a_hull() -> void:
	var pack := MapPack.new()
	assert_bool(pack.load(PackLocator.find_pack(PACK_ID))).is_true()
	var report := JunctionReport.analyse(pack, false)
	var c: Dictionary = report["counts"]
	print(JunctionReport.format(report, 10))
	assert_int(c["junctions"]).is_greater(1500)
	assert_int(c["bulging"]).is_less_equal(10)
	assert_int(c["gaps"]).is_less_equal(60)
	assert_int(c["hull"]).is_less_equal(30)
	assert_int(c["point_like"]).is_equal(0)
	assert_int(c["no_surface"]).is_equal(0)
