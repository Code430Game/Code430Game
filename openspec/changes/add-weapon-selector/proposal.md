# Change: Weapon wheel with icons

**Status: proposed 2026-10-06 (human, 2026-10-06: "I think we might even need to add a weapon selector — none (fist), brush/knife/laser sabre, paintball gun/pistol/blaster — it might be included but I did not see it while playing." Then: "We would need icons though — and while these circle selectors are common I think we need to make sure it does not copy GTA too much." Then, on a first draft with a straight belt: "I think we can do a wheel, and I think a wheel is better. A wheel is very common and is across multiple games from multiple publishers." And: "I tried to paste a gta wheel and cyberpunk and they are both quite different. But also baulders gate 3 had a series of wheels for the spells and potions and attacks on console.")**

## Why
The weapons are in the game (`add-weapons-and-combat`): LB / Tab cycles empty hands, the
melee weapon and the gun, and the HUD prints one line such as "Paintball gun 12 / 20". The
human played it and didn't find the cycle. Empty hands print nothing, so nothing on screen
says that the slots exist, how many there are or which one is in hand.

A wheel that shows every slot as an icon makes the weapons discoverable. It also gives later
weapons (more guns, pack weapons, throwables) a place to appear without more HUD work.

## What Changes
- **The wheel.**
  - **Opening:** hold LB / Tab to open it. A tap still steps to the next slot as it does
    today.
  - **Segments:** the wheel is a ring with one segment per slot, spaced evenly around it.
  - **Choosing:**
    - With the right stick or the mouse, point at a segment; releasing LB / Tab takes it.
    - Releasing with the stick centred, or pressing B / Esc, keeps the slot in hand.
  - **Centre:** the hub shows the pointed-at weapon's name and its rounds.
  - **No slowdown:** the game keeps running at full speed and the left stick still walks.
    Time doesn't slow, because co-op players share one world.
  - **Design:** the wheel's own design keeps it apart from any one game's wheel; see
    `design.md`, "Our wheel".
- **Pages for later items.** Like Baldur's Gate 3 on console, which keeps a separate wheel for
  each kind of thing, the wheel is built as a set of pages. Each page is one kind (weapons
  now; later, for example, throwables or consumables), and RB / Q step between pages while the
  wheel is open. This change ships one page, Weapons. With one page, the page control and its
  title stay hidden.
- **Idle tile.** When the wheel is closed, a small tile near the weapon and ammo line shows
  the slot in hand with its icon, so empty hands are visible too. After a tap-step it flashes
  in the accent colour.
- **Direct picks.** Keys 1 to 9 pick a slot by position on foot. These are new actions in
  `controls.json`, so `docs/controls.md` is regenerated.
- **Built from data.**
  - **Segments from `WeaponSet`:** the wheel reads its segments from `WeaponSet`, so a weapon
    added to `weapons.v0.json` or a pack gets a segment with no HUD code.
  - **Tone gaps:** slots the active tone leaves empty get no segment, the same as the cycle.
  - **More slots:** up to `max_segments` (default 8) share one ring; past that, an outer ring
    holds the rest.
- **Icons.** Original flat icons on a 64 px grid, one per held model plus fists:
  - fists
  - paint brush
  - knife
  - sabre
  - paintball gun
  - pistol
  - blaster

  They are hand-authored SVGs under `game/ui/hud/icons/weapons/`, licensed CC BY-SA 4.0 like
  the other assets. A weapon variant may name an `icon`; otherwise its `model` name is used, and
  an unknown name falls back to a generic silhouette for its mechanic. Icons are drawn in one
  colour and tinted by the HUD, so a tone can recolour them without new art.
- **Tone accent.** Each mode file gains a `hud` block with an accent colour for the selected
  segment and the idle tile:
  - clean: bright paint colours;
  - gritty: a muted amber;
  - dystopia: a cold neon.

  The wheel reads it from `ContentMode`; there are no mode ids in the HUD code.
- **Schema.** `weapons.schema.v0.json` gains an optional variant field `icon` (a name, or a
  PNG path for packs, since data packs may not ship SVG). This is additive, so existing files
  stay valid.
- **Not in this change:** slowing time while choosing, weapon categories with several
  weapons per segment, favourites, an inventory screen, wheel segments for items that are not
  weapons, a wheel in cars, any page other than Weapons.

## Co-op authority
The wheel is local UI on each player's machine and shows that player's own `WeaponSet`. The
slot in hand and its replication are unchanged from `add-weapons-and-combat`. Because the
world is shared, opening the wheel never changes time for anyone.

## Tone
Names and icons come from the resolved variant (`WeaponSet.resolve`). The accent colour comes
from the mode's `hud` block. A tone change rebuilds the wheel and the idle tile.

## Impact
- Affected specs: `combat` (ADDED: Weapon Wheel).
- Affected code:
  - new: `game/ui/hud/weapon_wheel.gd`, `game/ui/hud/weapon_tile.gd` and
    `game/ui/hud/icons/weapons/*.svg`
  - `game/actors/combat/weapon_set.gd` (pick by index, icon lookup)
  - `game/actors/combat/shooter.gd` (tap or hold on next weapon; the HUD line)
  - the player's look input (paused while the wheel is open)
  - `game/actors/combat/weapons.v0.json`
  - `docs/pack-format/weapons.schema.v0.json`
  - `game/core/content/modes/*.json` (`hud` accent)
  - `game/core/input/controls.json`, `game/project.godot`, `docs/controls.md`
  - `game/scenes/play_testbed.gd` (adds the wheel and the tile; a small edit)
  - tests
- Builds on `add-weapons-and-combat` (merged) and comes after `add-unarmed-combat`.
  `add-unarmed-combat` keeps fists out of `weapons.v0.json`: slot 0 is still "nothing in
  hand", and `Shooter.fist_weapon()` builds the fist's hit data. The weapon page therefore
  adds slot 0 itself, named "Fists" with the fists icon. It doesn't read slot 0 from the
  weapon list. So this change merges after `add-unarmed-combat`. Both edit `weapons.schema.v0.json` and
  `weapons.v0.json`; rebase on whichever lands first.
- Performance: the wheel draws only while open. The idle tile redraws only on a slot change.
- Content policy: original icons and an original wheel design. Nothing copies another game's
  weapon art, segment layout or colours, and nothing depicts real weapon brands.
