# Design: weapon wheel

## Our wheel
Radial selectors are common across games from many publishers, so a wheel is the expected
control and the human prefers it:
- GTA V: category wedges, and time slows while the wheel is open.
- Cyberpunk 2077: a different layout and look again.
- Baldur's Gate 3 on console: a series of wheels, one each for attacks, spells and potions.

What the design avoids is copying any one game's wheel. GTA V's is the one players of a crime
sandbox will compare against, so it is the reference to stay apart from:

| | GTA V | Code 430 |
|---|---|---|
| segments | eight fixed category wedges; several weapons per wedge, cycled inside it | one segment per slot, as many as the data has, spaced evenly |
| time | slows the game while open | never slows: co-op players share the world |
| hub | weapon render and ammo | the pointed-at icon's name and rounds, in the tone's accent |
| art | full-colour weapon renders | one-colour flat icons tinted by the tone |
| shape | wide wedges filling a large disc | separate round tiles on a thin ring with gaps, the disc open in the middle |
| closed | nothing on screen until you open it | an idle tile always shows what is in hand |

Picking is by direction (right stick or mouse) and a release, like most wheels.

## Pages
- A page is a kind of thing with its own segments, borrowed in spirit from Baldur's Gate 3's
  console wheels.
- `WheelPage` is a small interface:
  - `title()`
  - `entries()` (icon, name, sub-label such as rounds, enabled)
  - `current_index()`
  - `choose(index)`
- `WeaponPage` wraps `WeaponSet`. Later pages (throwables, consumables) implement the same
  interface and register with the wheel; none ship in this change.
- With more than one page, RB / Q (while the wheel is open) steps to the next page, and the
  page title shows above the hub with one dot per page. With one page, both stay hidden.

## Input
- **LB / Tab** has two gestures:
  - **Tap** (released before `hold_s`, default 0.2 s): steps to the next slot, as today, and
    flashes the idle tile.
  - **Hold:** opens the wheel.
- **While the wheel is open:**
  - The right stick, or the mouse moved from where the wheel opened, selects the segment
    nearest that direction once the stick passes `deadzone` (default 0.45) or the mouse
    passes 40 px. The camera does not turn.
  - **Release:** takes the selected slot. Released with no selection, the slot in hand stays.
  - **B / Esc:** closes the wheel without changing the slot.
  - **Other inputs:** the left stick walks. Fire and aim are ignored, so a release doesn't
    also fire.
- **Keys 1 to 9** pick by position without opening the wheel.

## Layout
- The ring is centred on the screen, with a radius of 150 px at 1280x800 and scaled with the
  HUD scale.
- Each segment is a round tile 64 px across.
- The first slot sits at the top and the rest go clockwise in slot order.
- The selected tile scales to 1.15 and takes the accent colour. The tile in hand has a thin
  accent ring.
- The hub, 110 px across, shows the selected weapon's name, and its rounds when it has a
  magazine.
- Past `max_segments` (default 8), the extra slots go on an outer ring at 1.6 times the
  radius.
- The idle tile is 40 px at the top right, under the weapon and ammo line and the wanted
  stars, at 70 % opacity. (Built 2026-10-06: the HUD has the minimap at the bottom left and
  the weapon line at the top right, so the tile sits with the weapon line.)
- The wheel sits on its own canvas layer added after the pause menu, so its `_input` sees
  B / Esc first and Esc closes the wheel rather than opening the menu.

## Icons
- Each icon is one closed silhouette on a 64x64 viewBox with a 4 px safe margin and no
  gradients or text, so it reads at 40 px on the Deck and tints cleanly.
- Godot imports the SVG at 2x for crisp edges on the high preset. Packs give PNGs, because
  data packs may not ship SVG (pack rules in `AGENTS.md`).
- Lookup order:
  1. the variant's `icon`;
  2. the variant's `model`;
  3. a generic icon for the mechanic (`melee`, `hitscan`, `projectile`);
  4. a question-mark tile.

  The game never crashes on a missing icon.
- The fists icon is a closed fist seen from the side, which keeps it apart from a raised-fist
  symbol.

## Data
- `ContentMode` gains `hud_accent() -> Color`, read from a new `hud.accent` in each mode file.
  The default is white when the mode leaves it out.
- `WeaponSet` gains `pick(index)`, `available()` (the slots the tone allows, in order) and
  `icon_name(def)`. A pick that lands on a slot the tone empties is refused.
- Tunables go in `game/ui/hud/hud_config.json`, which is created if it doesn't exist:
  - `hold_s`
  - `deadzone`
  - ring radius
  - tile size
  - `max_segments`
  - the flash time
- The pure maths sits in static functions so tests can cover it without a scene:
  - direction to segment;
  - segment angles for N slots;
  - which ring a slot goes on.
