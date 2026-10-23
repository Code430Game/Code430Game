extends GdUnitTestSuite
## add-splash-screen: the boot splash is the Code 430 card, and the card credits Godot and
## OpenStreetMap and asks for help at the repository.

const SplashCard := preload("res://ui/splash/splash_card.gd")


func test_the_boot_splash_is_the_card() -> void:
	var path := str(ProjectSettings.get_setting("application/boot_splash/image"))
	assert_str(path).is_equal("res://assets/splash/boot_splash.png")
	var tex: Texture2D = load(path)
	assert_object(tex).is_not_null()
	assert_float(float(tex.get_width()) / tex.get_height()).is_equal_approx(1.6, 0.01)  # the Deck's 16:10


func test_the_card_credits_godot_and_osm_and_asks_for_help() -> void:
	var root: Control = auto_free(Control.new())
	SplashCard.build(root)
	var texts: Array[String] = []
	for l in root.find_children("*", "Label", true, false):
		texts.append((l as Label).text)
	assert_array(texts).contains(["CODE 430", "Made with Godot Engine", "Map data © OpenStreetMap contributors", "Help us improve it", SplashCard.REPO_URL])
	assert_int(root.find_children("*", "TextureRect", true, false).size()).is_equal(1)  # the Godot icon


func test_the_loading_bar_only_moves_forward_and_says_what_is_loading() -> void:
	var screen: LoadingScreen = auto_free(LoadingScreen.new())
	add_child(screen)
	screen.set_progress(0.4, "Loading ottawa-glebe: buildings")
	screen.set_progress(0.2, "Loading ottawa-glebe: sidewalks")
	assert_float(screen.progress()).is_equal_approx(0.4, 0.001)
	assert_str(screen.status_text()).is_equal("Loading ottawa-glebe: sidewalks")


func test_a_district_set_reports_progress_through_each_part_to_the_end() -> void:
	var pack := MapPack.new()
	var dirs := PackedStringArray(["res://tests/fixtures/districts/west", "res://tests/fixtures/districts/east"])
	assert_bool(pack.load_districts(dirs)).is_true()
	assert_float(pack.progress).is_greater_equal(0.85)
	assert_str(pack.progress_text).is_not_empty()
