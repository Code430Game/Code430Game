# Change: Menu design pass

**Status: proposed 2026-10-06 (human, Deck session: "We should also do a round of menu design improvements. More padding on outer elements so the text is separated a bit from the edges. And more definition of the ui."). Approved to build straight after.**

## Why
The menus work but look unfinished. In screenshots of the pause menu (Game and Controls
tabs):
- **No padding.** The selected row's outline runs into the panel's edges; the "On foot"
  heading sits flush against the left edge; rows run edge to edge.
- **Little definition.**
  - The panel is a flat translucent grey with no border or shadow, so the game shows through
    it.
  - The selection is a "> " text marker plus a thin outline.
  - The tabs, the hint line and the list run together, with no separation.
- **The HUD shows through underneath.** The minimap and the position line overlap the bottom
  of the panel.

Each menu builds its own look in code, so the character creator, the report form and the full
map's panels don't match each other either.

## What Changes
- **One menu theme.** A shared Godot `Theme`, built in code at start from
  `game/ui/menu_theme.json`, which holds:
  - colours: panel, border, text, muted text, accent;
  - spacing: outer padding, row height and padding, gaps;
  - corner radius, border width, shadow;
  - font sizes.

  Every menu uses it: the pause menu (all tabs), the character creator, the report form, the
  full map's panels and the co-op join line. No per-menu colours or margins in code.
- **Padding.**
  - Outer padding inside panels is 24 px by default at 1280x800, scaled with the HUD scale.
  - List rows are inset 12 px from the panel's edge, and the selection never touches it.
  - Section headings get space above them.
- **Definition.**
  - Panels are nearly opaque with a 1–2 px border, rounded corners and a soft shadow.
  - The selected row is a filled highlight in the tone's accent (`ContentMode.hud_accent`)
    with a bar on its left. The "> " text marker goes.
  - Tabs look like tabs: the active one filled, the rest outlined, on a strip separated from
    the content.
  - Hints sit in a footer strip with controller glyph-style key caps such as `[LB]` and `[A]`.
  - Values in the Controls list sit in key caps too.
  - Scrollbars are thin, with fades at the top and bottom of lists that scroll.
- **HUD while paused.** The minimap, the position line and the badges hide while a menu is
  open, and come back on resume.
- **Readability on the Deck.** Body text stays at least 18 px at 1280x800, with contrast of
  at least 4.5:1 against the panel.
- **Not in this change:**
  - new menu screens or a main or title menu;
  - the map legend (in the backlog);
  - fonts other than the current one;
  - animation beyond a short fade.

## Tone
- The accent colour follows the tone.
- Everything else is neutral, so the menus read the same in every mode.

## Impact
- Affected specs: `menus` (ADDED: Shared Menu Look).
- Affected code:
  - new `game/ui/menu_theme.gd` and `menu_theme.json`;
  - `game/ui/pause/pause_menu.gd` / `.tscn`;
  - `game/ui/character/character_creator.gd` / `.tscn`;
  - `game/ui/report/report_form.gd` / `.tscn`;
  - `game/ui/map/overview_map.gd`;
  - `game/scenes/play_testbed.gd` (hide the HUD while paused; small);
  - tests.
- Before and after screenshots of every menu.
- Performance: no change in play; menus only.
