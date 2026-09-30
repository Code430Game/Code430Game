class_name DeckDetector
extends RefCounted
## Decides whether the game is running on a Steam Deck.
##
## Approach: pure function over a dictionary of facts so tests can feed any
## combination. `collect_facts()` reads the real machine. Any one strong signal
## (SteamDeck env var, DMI product name) is enough; the weak signal (Linux at
## 1280x800) is only accepted on its own because the Deck is our baseline and a
## false positive costs a lower preset, which the player can override.

const DECK_SCREEN_SIZE := Vector2i(1280, 800)
const DECK_PRODUCT_NAMES: PackedStringArray = ["Jupiter", "Galileo"]
const DMI_PRODUCT_PATH := "/sys/devices/virtual/dmi/id/product_name"


## Reads the facts about the current machine that `is_steam_deck` needs.
static func collect_facts() -> Dictionary:
	var product := ""
	if FileAccess.file_exists(DMI_PRODUCT_PATH):
		var f := FileAccess.open(DMI_PRODUCT_PATH, FileAccess.READ)
		if f != null:
			product = f.get_line().strip_edges()  # sysfs reports a 4 KiB size; get_as_text would warn
	var screen := Vector2i.ZERO
	if DisplayServer.get_name() != "headless":
		screen = DisplayServer.screen_get_size()
	return {
		"os_name": OS.get_name(),
		"screen_size": screen,
		"has_steamdeck_env": OS.has_environment("SteamDeck"),
		"dmi_product_name": product,
	}


## Returns true when the facts describe a Steam Deck.
static func is_steam_deck(facts: Dictionary) -> bool:
	var os_name: String = facts.get("os_name", "")
	if os_name != "Linux":
		return false
	if facts.get("has_steamdeck_env", false):
		return true
	var product: String = facts.get("dmi_product_name", "")
	for name in DECK_PRODUCT_NAMES:
		if product.begins_with(name):
			return true
	var screen: Vector2i = facts.get("screen_size", Vector2i.ZERO)
	return screen == DECK_SCREEN_SIZE
