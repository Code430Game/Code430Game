extends GdUnitTestSuite
## Tests for the debug overlay text formatting.

const OverlayScript := preload("res://core/debug/debug_overlay.gd")


func test_format_includes_all_fields() -> void:
	var text := OverlayScript.format_stats(59.6, 16.72, 120, 4500, "deck", true)
	assert_str(text).contains("59 fps").contains("16.7 ms").contains("draw calls 120").contains("primitives 4500").contains("preset deck").contains("Steam Deck")


func test_format_omits_deck_tag_on_desktop() -> void:
	var text := OverlayScript.format_stats(144.0, 6.9, 10, 20, "high", false)
	assert_str(text).not_contains("Steam Deck").contains("preset high")
