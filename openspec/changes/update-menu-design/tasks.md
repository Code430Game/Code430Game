## 1. Theme
- [x] 1.1 `menu_theme.json` + `MenuTheme` building a Godot `Theme` (panel, border, shadow, radius, padding, row, tab, footer, key cap, scrollbar styles; accent from `ContentMode.hud_accent`, rebuilt on a tone change); tests that values come from the JSON and the accent follows the tone
  - 2026-10-06: `game/ui/menu_theme.gd` builds one Theme from `menu_theme.json`.
    - Panels: 96 % opaque, 1 px border, 12 px corners, an 18 px shadow and 24 px padding.
    - Rows: inset 18 px; the selected one filled at 24 % accent with a 4 px accent bar.
    - Tabs are chips on a strip, the active one filled with the accent.
    - Hints and bindings are key caps; scrollbars are 4 px; fields get an accent border while typing.
    - Section headings take the accent too.
    - The shared accent boxes are recoloured by `refresh_accent()` when a menu opens and when the tone changes.
    - Tests: values come from the data; the accent follows each tone; contrast of at least 4.5:1 for text, muted text, selected rows, the active tab and headings in every tone. Body and row text are 18–20 px; hints, notes and key caps are 16 px.

## 2. Menus
- [x] 2.1 Pause menu (every tab) on the theme: padded panel, tab strip, filled accent selection with a left bar (no "> " marker), footer hints with key caps, Controls values as key caps; tests that the selection stays inside the panel's padding
  - The "> " markers are gone; selection is the `MenuRowSelected` variation. The Controls list sits in a scroll frame with fades at its edges and a right gutter, so key caps clear the scrollbar. Tests: on every tab, each selected row lies inside the panel's padding and the others are plain.
- [x] 2.2 Character creator, report form, the full map's panels and the co-op join line on the theme
  - Character creator: compact rows, a gap before the action rows, footer hints.
  - Report form: compact row labels, saved reports as rows (`queue_text()` for tests), footer hints per page.
  - Full map: a header strip with key caps, and a tooltip-style hover label.
  - The co-op address box uses the field style.
- [x] 2.3 The HUD (minimap, position line, badges) hides while a menu is open and returns on resume; test
  - `play_testbed.menu_open()`: the HUD layer hides while the pause menu, map, creator or report form is open. Test in `test_testbed_menus.gd`.

## 3. Check
- [x] 3.1 Before and after Mac screenshots of every menu and tab, in clean and gritty
  - After shots: every pause tab, the creator, the report form and the map in gritty, plus the Game, Controls and Options tabs in clean.
  - Before shots: the pause menu (Game and Controls tabs) from main. Before shots of the creator, report form and map were skipped, because the agent's sandbox did not allow a second checkout of main.
- [ ] 3.2 Human looks through the menus on the Deck
