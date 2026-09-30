extends GdUnitTestSuite
## Tests for DeckDetector.is_steam_deck with synthetic facts.


func _facts(os_name: String, screen: Vector2i = Vector2i.ZERO, env: bool = false, product: String = "") -> Dictionary:
	return {"os_name": os_name, "screen_size": screen, "has_steamdeck_env": env, "dmi_product_name": product}


func test_env_var_on_linux_is_deck() -> void:
	assert_bool(DeckDetector.is_steam_deck(_facts("Linux", Vector2i(1920, 1080), true))).is_true()


func test_dmi_product_jupiter_is_deck() -> void:
	assert_bool(DeckDetector.is_steam_deck(_facts("Linux", Vector2i(1920, 1080), false, "Jupiter"))).is_true()


func test_dmi_product_galileo_is_deck() -> void:
	assert_bool(DeckDetector.is_steam_deck(_facts("Linux", Vector2i.ZERO, false, "Galileo"))).is_true()


func test_linux_at_deck_resolution_is_deck() -> void:
	assert_bool(DeckDetector.is_steam_deck(_facts("Linux", Vector2i(1280, 800)))).is_true()


func test_linux_desktop_is_not_deck() -> void:
	assert_bool(DeckDetector.is_steam_deck(_facts("Linux", Vector2i(2560, 1440)))).is_false()


func test_macos_with_env_is_not_deck() -> void:
	assert_bool(DeckDetector.is_steam_deck(_facts("macOS", Vector2i(1280, 800), true, "Jupiter"))).is_false()


func test_windows_is_not_deck() -> void:
	assert_bool(DeckDetector.is_steam_deck(_facts("Windows", Vector2i(1280, 800)))).is_false()


func test_empty_facts_is_not_deck() -> void:
	assert_bool(DeckDetector.is_steam_deck({})).is_false()
