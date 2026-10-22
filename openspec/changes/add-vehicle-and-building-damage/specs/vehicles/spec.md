## ADDED Requirements

### Requirement: Vehicle Damage
Drivable cars SHALL have health lost to hard crashes and weapon hits, and SHALL show it in stages: scuffed, dented, smoking (slower), and wrecked. Undamaged cars SHALL keep sharing the generated mesh.

#### Scenario: A gentle bump
- **WHEN** the player's car touches a wall below the crash threshold
- **THEN** it loses no health and shows nothing

#### Scenario: A hard crash
- **WHEN** the player drives into a wall at 60 km/h
- **THEN** the car is dented where it hit and keeps going

#### Scenario: Smoking
- **WHEN** a car's health falls below the smoking stage
- **THEN** smoke comes from its engine and its top speed is cut

#### Scenario: Reset keeps the damage
- **WHEN** the player holds reset in a dented car
- **THEN** the car is put back on the road still dented

### Requirement: Wrecks By Tone
A car at zero health SHALL be wrecked as the tone's `outcomes.vehicle` says: `conk_out` stalls it without flames and a reset mends it; `burn` makes it smoke, burn, explode after a few seconds (damaging and flinging what is near) and leave a shell. The player SHALL get out of a wreck, and wrecking someone else's car where the police see it SHALL be a crime.

#### Scenario: Wrecked in clean
- **WHEN** the player's car is wrecked in the clean tone
- **THEN** it stalls with puffs of smoke and no flames, and holding reset gives back a working car

#### Scenario: Wrecked in gritty
- **WHEN** the player's car is wrecked in the gritty tone
- **THEN** the player gets out, and the car smokes, burns, explodes, and is left a blackened shell

#### Scenario: A chain of wrecks
- **WHEN** a wreck explodes beside a badly damaged car
- **THEN** that car is wrecked by the blast and burns in turn

#### Scenario: Repair out of sight
- **WHEN** a wanted player drives a dented car into a parking garage with no officer seeing it
- **THEN** the car is mended; with an officer watching it is not

#### Scenario: Wrecking a traffic car in view of the police
- **WHEN** the player shoots a traffic car until it is wrecked while an officer sees it
- **THEN** its driver gets out and runs and the wanted level rises by one star
