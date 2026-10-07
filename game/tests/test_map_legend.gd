extends GdUnitTestSuite
## The map legend and places list (add-map-legend; human, 2026-10-06: "[hospital icon] Hospital
## / [police icon] Police -> 2125 Bronson Ave ... instead of toggling through we click in or
## back"): one icon set, addresses on places, kinds then places nearest first, A opens and picks
## (centring the map), B goes back and then closes.

const OVERVIEW := preload("res://ui/map/overview_map.tscn")
const PACK_ID := "code430.ottawa-centretown"
const SCHEMA := "res://../docs/pack-format/services.schema.v0.json"


func _place(id: String, kind: String, name: String, at: Vector3, address: String = "") -> Services.Place:
	var p := Services.Place.new()
	p.id = id
	p.kind = kind
	p.name = name
	p.at = at
	p.address = address
	return p


func _places() -> Array:
	return [
		_place("h1", "hospital", "Far Hospital", Vector3(900, 0, 0), "60 Cambridge Street North"),
		_place("p1", "police", "Far Station", Vector3(0, 0, 600), "1 Far Street"),
		_place("p2", "police", "Ottawa Police Headquarters", Vector3(100, 0, 0), "474 Elgin Street"),
		_place("x1", "zeppelin_dock", "", Vector3(50, 0, 50)),
	]


## A full map with a renderer, a player at the origin and the places; opened.
func _map(places: Array) -> OverviewMap:
	var map: OverviewMap = auto_free(OVERVIEW.instantiate())
	var player: Node3D = auto_free(Node3D.new())
	add_child(player)
	var r := MapRenderer.new()
	r.set_bounds(Vector4(-1000, -1000, 1000, 1000))
	map.renderer = r
	map.player = player
	add_child(map)
	map.places = places
	map.open()
	return map


func after_test() -> void:
	get_tree().paused = false


func test_every_kind_has_its_own_icon_and_the_services_kinds_are_covered() -> void:
	var schema: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("../docs/pack-format/services.schema.v0.json")))
	var kinds: Array = schema["properties"]["places"]["items"]["properties"]["kind"]["enum"]
	for k: String in kinds:
		assert_bool(PlaceIcons.kinds().has(k)).override_failure_message("no legend entry for %s" % k).is_true()
	for k in PlaceIcons.kinds():
		assert_str(PlaceIcons.icon_name(k)).override_failure_message("%s has no icon" % k).is_not_equal("missing")
		assert_object(PlaceIcons.texture(k)).is_not_null()
		assert_str(PlaceIcons.label(k)).is_not_empty()
	assert_bool(PlaceIcons.kinds().has("garage")).is_true()


func test_an_unknown_kind_falls_back_to_the_missing_icon_and_its_id() -> void:
	assert_str(PlaceIcons.icon_name("zeppelin_dock")).is_equal("missing")
	assert_object(PlaceIcons.texture("zeppelin_dock")).is_not_null()
	assert_str(PlaceIcons.label("zeppelin_dock")).is_equal("Zeppelin Dock")
	assert_that(PlaceIcons.color("zeppelin_dock")).is_equal(PlaceIcons.UNKNOWN_COLOR)


func test_places_load_their_address_and_go_without_one() -> void:
	var dir := "user://test_map_legend_pack"
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("services.v0.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"schema_version": 0, "units": "m", "places": [
		{"id": "w1", "kind": "police", "name": "HQ", "at": [1, 2, 3], "road_node": "n1", "address": "474 Elgin Street"},
		{"id": "w2", "kind": "helipad", "name": null, "at": [4, 5, 6], "road_node": null},
	]}))
	f.close()
	var places := Services.load_places(dir)
	assert_int(places.size()).is_equal(2)
	assert_str(places[0].address).is_equal("474 Elgin Street")
	assert_str(places[1].address).is_equal("")
	DirAccess.remove_absolute(dir.path_join("services.v0.json"))
	DirAccess.remove_absolute(dir)


func test_a_garage_becomes_a_place_on_its_nearest_street() -> void:
	var graph := RoadGraph.new()
	var e := RoadGraph.RoadEdge.new()
	e.id = "e1"
	e.name = "Metcalfe Street"
	e.polyline = PackedVector3Array([Vector3(0, 0, -100), Vector3(0, 0, 100)])
	graph.edges["e1"] = e
	var lot := ParkingLotBuilder.Lot.new()
	lot.id = "lot1"
	lot.kind = "underground"
	lot.bounds = Rect2(20, -10, 20, 20)
	var surface := ParkingLotBuilder.Lot.new()
	surface.kind = "surface"
	surface.bounds = Rect2(0, 0, 10, 10)
	var out := Services.garage_places([lot, surface], graph, 120.0)
	assert_int(out.size()).is_equal(1)
	assert_str(out[0].kind).is_equal("garage")
	assert_str(out[0].address).is_equal("on Metcalfe Street")
	assert_float(out[0].at.x).is_equal_approx(30.0, 0.01)
	assert_str(Services.street_near(graph, Vector3(500, 0, 0), 120.0)).is_equal("")


func test_the_legend_lists_the_kinds_present_in_order_then_unknown_ones() -> void:
	var map := _map(_places())
	assert_array(Array(map.legend.kinds_present())).is_equal(["police", "hospital", "zeppelin_dock"])
	assert_int(map.legend.level).is_equal(MapLegend.Level.KINDS)
	assert_array(map.legend.entries()).is_equal(["police", "hospital", "zeppelin_dock"])


func test_opening_a_kind_lists_its_places_nearest_first() -> void:
	var map := _map(_places())
	map.legend.select(0)
	map.legend.accept()
	assert_int(map.legend.level).is_equal(MapLegend.Level.PLACES)
	assert_str(map.legend.kind).is_equal("police")
	var ids: Array = map.legend.entries().map(func(p: Services.Place) -> String: return p.id)
	assert_array(ids).is_equal(["p2", "p1"])
	assert_str(MapLegend.distance_text(96.0)).is_equal("100 m")
	assert_str(MapLegend.distance_text(1234.0)).is_equal("1.2 km")


func test_picking_a_place_centres_and_highlights_it_and_keeps_it_through_zoom() -> void:
	var map := _map(_places())
	map.legend.accept()  # police
	map.legend.move(1)  # the far station
	map.legend.accept()
	assert_object(map.focused).is_not_null()
	assert_str(map.focused.id).is_equal("p1")
	var at := map.world_to_screen(0.0, 600.0)
	assert_float(map.focus_offset().x).is_less(0.0)  # left of the legend panel
	assert_float(at.distance_to(map.focus_offset())).override_failure_message("not centred: %s" % at).is_less(0.5)
	map.zoom = 2.0
	await get_tree().process_frame
	var after := map.world_to_screen(0.0, 600.0)
	assert_float(after.distance_to(map.focus_offset())).override_failure_message("lost the centre on zoom").is_less(0.5)


func test_b_goes_back_a_level_then_closes_the_map() -> void:
	var map := _map(_places())
	map.legend.select(1)  # hospital
	map.legend.accept()
	assert_int(map.legend.level).is_equal(MapLegend.Level.PLACES)
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	assert_bool(map.legend_input(cancel)).is_true()
	assert_int(map.legend.level).is_equal(MapLegend.Level.KINDS)
	assert_int(map.legend.selected).override_failure_message("back should land on the kind it came from").is_equal(1)
	map.legend_input(cancel)
	assert_bool(map.visible).is_false()


func test_the_dpad_moves_the_selection_but_the_sticks_do_not() -> void:
	var map := _map(_places())
	var down := InputEventAction.new()
	down.action = "ui_down"
	down.pressed = true
	assert_bool(map.legend_input(down)).is_true()
	assert_int(map.legend.selected).is_equal(1)
	var stick := InputEventJoypadMotion.new()
	stick.axis = JOY_AXIS_LEFT_Y
	stick.axis_value = 1.0
	assert_bool(map.legend_input(stick)).is_false()
	assert_int(map.legend.selected).is_equal(1)


func test_a_click_on_a_row_opens_it() -> void:
	var map := _map(_places())
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	map.legend._on_row_input(1, click)
	assert_int(map.legend.level).is_equal(MapLegend.Level.PLACES)
	assert_str(map.legend.kind).is_equal("hospital")


func test_the_ottawa_pack_lists_police_with_real_addresses() -> void:
	var pack := MapPack.new()
	assert_bool(pack.load(PackLocator.find_pack(PACK_ID))).is_true()
	var police := pack.services.filter(func(p: Services.Place) -> bool: return p.kind == "police")
	assert_int(police.size()).is_greater(0)
	var addresses: Array = police.map(func(p: Services.Place) -> String: return p.address)
	assert_bool(addresses.has("474 Elgin Street")).is_true()
	var with_address := pack.services.filter(func(p: Services.Place) -> bool: return p.address != "")
	assert_int(with_address.size()).is_greater_equal(pack.services.size() - 1)


## Human, 2026-10-07: "Can we mention for the parking if it's underground? ... I wonder if we
## just say Kent St Parking?"
func test_street_names_shorten_like_a_sign() -> void:
	assert_str(PlaceIcons.abbreviate("Kent Street")).is_equal("Kent St")
	assert_str(PlaceIcons.abbreviate("Laurier Avenue West")).is_equal("Laurier Ave W")
	assert_str(PlaceIcons.abbreviate("Colonel By Drive")).is_equal("Colonel By Dr")
	assert_str(PlaceIcons.abbreviate("Rue Kent")).is_equal("Rue Kent")  # French: nothing at the end to shorten
	assert_str(PlaceIcons.abbreviate("Street")).is_equal("Street")  # a lone word is a name, not a suffix
	assert_str(PlaceIcons.abbreviate("North Avenue")).is_equal("North Ave")


func _garage(id: String, street: String, cross: String) -> Services.Place:
	var p := _place(id, "garage", "", Vector3.ZERO, "on " + street if street != "" else "")
	p.street = street
	p.cross = cross
	return p


func test_a_garage_is_named_for_its_street_and_marked_underground() -> void:
	var g := _garage("g1", "Kent Street", "Slater Street")
	var police := _place("p2", "police", "Ottawa Police Headquarters", Vector3.ZERO, "474 Elgin Street")
	PlaceIcons.assign_titles([g, police])
	assert_str(g.title).is_equal("Kent St Parking")
	assert_str(PlaceIcons.display_name(g)).is_equal("Kent St Parking")
	assert_str(police.title).is_equal("")  # other kinds keep their names and addresses
	assert_str(PlaceIcons.display_name(police)).is_equal("Ottawa Police Headquarters")
	assert_str(PlaceIcons.note("garage")).contains("Underground")
	assert_str(PlaceIcons.note("police")).is_equal("")
	var lone := _garage("g9", "", "")
	PlaceIcons.assign_titles([lone])
	assert_str(lone.title).is_equal("Parking garage")


func test_two_garages_on_one_street_get_their_cross_streets_then_numbers() -> void:
	var a := _garage("g2", "Kent Street", "Slater Street")
	var b := _garage("g1", "Kent Street", "Laurier Avenue West")
	var c := _garage("g3", "Bank Street", "Albert Street")
	var d := _garage("g5", "Elgin Street", "")
	var e := _garage("g4", "Elgin Street", "")
	PlaceIcons.assign_titles([a, b, c, d, e])
	assert_str(b.title).is_equal("Kent St Parking (Laurier)")
	assert_str(a.title).is_equal("Kent St Parking (Slater)")
	assert_str(PlaceIcons.bare("Laurier Avenue West")).is_equal("Laurier")
	assert_str(c.title).is_equal("Bank St Parking")
	assert_str(e.title).is_equal("Elgin St Parking")  # no cross street: numbered in id order
	assert_str(d.title).is_equal("Elgin St Parking 2")


func test_the_parking_list_reads_street_parking_with_the_underground_note() -> void:
	var map: OverviewMap = auto_free(OVERVIEW.instantiate())
	add_child(map)
	var places: Array = [_garage("g1", "Kent Street", ""), _place("p2", "police", "HQ", Vector3(100, 0, 0), "474 Elgin Street")]
	PlaceIcons.assign_titles(places)
	map.places = places
	map.open()
	map.legend.places = places
	map.legend.kind = "garage"
	map.legend.level = MapLegend.Level.PLACES
	map.legend.rebuild()
	var texts := _texts(map.legend)
	assert_bool(texts.has("Kent St Parking")).override_failure_message(str(texts)).is_true()
	assert_bool(texts.has(PlaceIcons.note("garage"))).override_failure_message(str(texts)).is_true()
	map.close()


func _texts(n: Node) -> PackedStringArray:
	var out := PackedStringArray()
	if n is Label:
		out.append((n as Label).text)
	for c in n.get_children():
		out.append_array(_texts(c))
	return out


func test_every_ottawa_garage_gets_its_own_street_parking_name() -> void:
	var pack := MapPack.new()
	assert_bool(pack.load(PackLocator.find_pack(PACK_ID))).is_true()
	var garages := Services.garage_places(pack.parking_lots, pack.graph, PlaceIcons.num("garage_street_m", 120.0))
	PlaceIcons.assign_titles(garages)
	var titles: Array = garages.map(func(p: Services.Place) -> String: return p.title)
	print("garage titles: ", "; ".join(PackedStringArray(titles)))
	assert_int(garages.size()).is_greater(0)
	for t: String in titles:
		assert_str(t).contains("Parking")
		assert_bool(t.contains(" on ")).is_false()
	var unique := {}
	for t: String in titles:
		unique[t] = true
	assert_int(unique.size()).is_equal(titles.size())


## Human, 2026-10-07: "the dual areas, we have text across the top and then an expander on the
## right for the listing. I wonder if we align those so the items are all on the right". The
## title, the legend and the hints are one column on the right, inside the screen's padding, and
## the legend never runs into the hints.
func test_all_map_ui_is_one_column_on_the_right() -> void:
	var map: OverviewMap = auto_free(OVERVIEW.instantiate())
	add_child(map)
	var view: Control = map.get_node("View")
	view.set_anchors_preset(Control.PRESET_TOP_LEFT)  # the headless viewport is tiny: the Deck's screen instead
	view.size = Vector2(1280, 800)
	map.places = _places()
	map.open()
	await get_tree().process_frame
	await get_tree().process_frame
	var screen := Rect2(view.global_position, view.size)
	var column: Control = map.get_node("View/Column")
	var footer: Control = map.get_node("View/Column/Footer")
	var col_rect := column.get_global_rect()
	assert_bool(screen.grow(-15.0).encloses(col_rect)).override_failure_message("column %s outside %s" % [col_rect, screen]).is_true()
	assert_float(col_rect.position.x).is_greater(screen.size.x * 0.5)  # on the right
	assert_bool(map.has_node("View/Header")).is_false()  # no strip across the top any more
	assert_object(map.legend.get_parent()).is_same(column)
	var legend_rect := map.legend.get_global_rect()
	assert_float(legend_rect.end.y).is_less_equal(footer.get_global_rect().position.y)
	assert_float(footer.get_global_rect().end.y).is_less_equal(col_rect.end.y + 0.5)
	var hints := map.hint_text()
	for word in ["pan", "cursor", "zoom", "places", "open", "back", "close"]:
		assert_str(hints).contains(word)
	map.focus_on(map.places[2])
	assert_float(map.focus_offset().x).is_less(0.0)  # a picked place sits left of the column
	map.close()


## The road label by the cursor never covers the column: near it, the label flips left.
func test_the_road_label_stays_off_the_column() -> void:
	var map: OverviewMap = auto_free(OVERVIEW.instantiate())
	add_child(map)
	var view: Control = map.get_node("View")
	view.set_anchors_preset(Control.PRESET_TOP_LEFT)
	view.size = Vector2(1280, 800)
	map.open()
	await get_tree().process_frame
	var label: Label = map.get_node("View/HoverLabel")
	var column: Control = map.get_node("View/Column")
	label.text = "Highway 417  (one-way)"
	map.cursor = Vector2(column.position.x - 640.0 - 20.0, 0.0)  # just left of the column
	map.call("_place_hover_label")
	assert_float(label.size.x).is_greater(40.0)
	assert_float(label.position.x + label.size.x).is_less_equal(column.position.x)
	map.cursor = Vector2(-300.0, 0.0)  # well clear: the label sits right of the cursor as before
	map.call("_place_hover_label")
	assert_float(label.position.x).is_greater(640.0 - 300.0)
	map.close()
