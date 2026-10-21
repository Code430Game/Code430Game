# menus Specification

## Purpose
Every menu in the game shares one look and works the same on a controller, a keyboard and a mouse, with the Steam Deck as the first target.

## Requirements

### Requirement: Shared Menu Look
Every menu SHALL use one shared theme from data, with padding that keeps text and selections clear of panel edges, defined panels, a filled selection in the tone's accent, and the HUD hidden while a menu is open.

#### Scenario: Selection inside the padding
- **WHEN** the player moves the selection to any row of any pause menu tab
- **THEN** the highlighted row lies inside the panel's padding and never touches its edge

#### Scenario: The HUD steps back
- **WHEN** the pause menu opens
- **THEN** the minimap, position line and badges are hidden, and they return when play resumes

#### Scenario: Accent follows the tone
- **WHEN** the tone changes from gritty to clean while the menu is open
- **THEN** the selection highlight takes the clean accent colour
