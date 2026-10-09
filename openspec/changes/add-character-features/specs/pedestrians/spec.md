## MODIFIED Requirements

### Requirement: Walking Animation
Pedestrians SHALL swing their arms and legs with the same walk cycle as the player, with the stride phase following distance walked and the cycle blending to a standing pose while they wait, SHALL vary per instance in body type, skin, top and bottom tint and print beyond the number of body pools, and the crowd SHALL stay drawn in one draw call per body pool per level of detail.

#### Scenario: Walking
- **WHEN** a pedestrian walks along a sidewalk
- **THEN** its legs and arms swing in opposition, one full cycle per stride length walked

#### Scenario: Variety
- **WHEN** two pedestrians share a body pool
- **THEN** they can still differ in body type, skin and clothing tints and in the print on their top

#### Scenario: Waiting at a kerb
- **WHEN** a pedestrian waits for a crossing or for a player ahead
- **THEN** its limbs settle to the standing pose within half a second

#### Scenario: Crowd cost
- **WHEN** 120 pedestrians walk near the player
- **THEN** each body pool is still one MultiMesh draw and no per-person skeleton is created

## ADDED Requirements

### Requirement: Body Levels Of Detail
Pedestrians, officers and faction members SHALL wear the character body at the level of detail matching their distance from the nearest player, with the far body carrying no face or accessory geometry, within the Deck draw-call and triangle budget stated in the change.

#### Scenario: Far crowd is cheap
- **WHEN** a pedestrian is 200 m from every player
- **THEN** it is drawn with the lowest-detail body and no face or accessory geometry

#### Scenario: Officer approaches
- **WHEN** an officer walks from 200 m to 30 m from the player
- **THEN** its body steps up through the three levels of detail without a visible pop at the fade distances

### Requirement: Children In Clean Mode
Child pedestrians SHALL exist only in a mode that allows the `minors` descriptor and whose violence flag is off, SHALL never be a player body, and SHALL be excluded from every weapon, paint, vehicle, officer and faction interaction in every mode.

#### Scenario: Clean mode
- **WHEN** the clean mode is active and the pack's population includes children
- **THEN** children walk the sidewalks beside adults at the pack's share

#### Scenario: Gritty mode
- **WHEN** the gritty or dystopia mode is active
- **THEN** no child is spawned whatever the pack's population says

#### Scenario: Untargetable
- **WHEN** a car, a weapon, a paintball, an officer or a faction member would act on a child in the clean mode
- **THEN** the car stops as for an obstacle and the child steps aside, and nothing else happens to the child
