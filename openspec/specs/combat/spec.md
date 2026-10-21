# combat Specification

## Purpose
The player fights with fists, kicks and weapons, and the people of the city react: hits, falls, fleeing and fighting back, shaped by the tone mode.

## Requirements

### Requirement: Weapons As Tagged Data
Weapons SHALL be defined in data with a tone-neutral mechanic and per-mode variants, and the game SHALL equip the variant the active tone mode allows, refusing any variant marked lethal when the mode's `lethal_weapons` flag is off.

#### Scenario: Clean mode
- **WHEN** the active mode is `clean` and the player cycles to the sidearm slot
- **THEN** a paintball marker is in hand, firing paintballs, and no bullet weapon can be equipped

#### Scenario: Gritty mode
- **WHEN** the active mode is `gritty` and the player cycles to the sidearm slot
- **THEN** a pistol is in hand

#### Scenario: Dystopia mode
- **WHEN** the active mode is `dystopia`
- **THEN** the melee slot holds a sabre and the gun slot a blaster that fires glowing bolts

#### Scenario: Mode switch
- **WHEN** the mode changes from `gritty` to `clean` during play
- **THEN** every slot swaps to its clean variant and all impact decals are cleared

### Requirement: Aiming And Firing
A player on foot SHALL aim over the shoulder with a reticle, fire hitscan guns, launch paintball projectiles and swing melee weapons, with magazines and reloads, using one hit path for all three mechanics.

#### Scenario: Reload
- **WHEN** the magazine is empty and the player presses fire
- **THEN** the weapon reloads for its reload time and then fires

#### Scenario: Projectile hit
- **WHEN** a paintball strikes a wall
- **THEN** a paint splat decal appears at the contact point and the ball is gone
