# Change: Code 430 splash screen

**Status: built 2026-10-22 (human: "Can we replace the splash screen with a Code 430 spash
screen? We should include godot and maybe osm on it and then the github repo link somewhere.
I think the github repo link should be a bit of a cta that says something like help us
improve at the link.").**

## Why
The game starts on Godot's default boot splash. Testers should see the game's name, who made
it possible, and where to help.

## What Changes
- **Boot splash** (`application/boot_splash/*`): a Code 430 card shown while the game loads,
  for at least 2.5 s, on the card's own dark background.
- **The card** (`game/ui/splash/splash_card.tscn`, rendered to
  `game/assets/splash/boot_splash.png` by `scripts/render-splash.sh` at 1920x1200):
  - the wordmark "CODE 430" over an accent rule and a one-line description;
  - a call to action: "Help us improve it" and `github.com/Code430Game/Code430Game`;
  - credits along the bottom: Godot's icon and "Made with Godot Engine" (the icon is CC BY
    4.0, receipt in `game/assets/splash/`), and "Map data © OpenStreetMap contributors" (text
    only: OSM's trademark policy limits its logo).
- The repository is private until release, so the link only works for testers once it is
  public.

## Impact
- Affected specs: `menus` (ADDED: Splash Screen).
- Affected code: `game/project.godot`, `game/ui/splash/`, `game/assets/splash/`,
  `scripts/render-splash.sh`, `LICENSE-ASSETS`; tests.
