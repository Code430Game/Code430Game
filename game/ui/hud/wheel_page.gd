class_name WheelPage
extends RefCounted
## One page of the wheel (add-weapon-selector): a kind of thing with its own segments, like
## Baldur's Gate 3's console wheels. Weapons are the first page; later kinds (throwables,
## consumables) implement the same four calls and are added to `WeaponWheel.pages`.


## The page's name, shown above the hub when the wheel has more than one page.
func title() -> String:
	return ""


## One dictionary per segment, in wheel order: `icon` (Texture2D), `name`, `sub` (a short line
## under the name, such as rounds) and `enabled`.
func entries() -> Array[Dictionary]:
	return []


## The segment for what is in use now, or -1.
func current_index() -> int:
	return -1


## Puts segment `index` in use.
func choose(_index: int) -> void:
	pass
