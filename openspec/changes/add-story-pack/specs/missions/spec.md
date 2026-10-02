## ADDED Requirements

### Requirement: Declarative Mission Definitions
Story packs SHALL define missions as data validated against the published mission schema: a giver placement, an ordered list of typed objectives (`go_to`, `enter_vehicle`, `follow`, `deliver`, `survive_until`) with positions, radii, texts and markers, fail conditions, descriptors and per-mode variants with a fallback. Missions SHALL contain no scripts.

#### Scenario: Unknown step type
- **WHEN** a mission file uses an objective type not in the schema
- **THEN** the validator fails naming the pack, the mission and the type

#### Scenario: Position off the map
- **WHEN** an objective's position lies outside the bounding box of the map pack the story depends on
- **THEN** the validator fails naming the mission and the objective

### Requirement: Mission Givers
Each placed mission SHALL have a giver character built from the character pipeline, standing at its declared position, that offers the mission through a controller-driven text dialogue when a player interacts within reach.

#### Scenario: Accept
- **WHEN** a player stands within 2.5 m of the giver, presses interact and accepts the last dialogue line
- **THEN** the mission becomes active, its first objective's text and marker appear, and the deadline starts

#### Scenario: Decline
- **WHEN** the player presses cancel during the dialogue
- **THEN** the dialogue closes and the giver can be talked to again

### Requirement: Objective Evaluation
The mission runner SHALL evaluate the current objective against world state every physics tick, advance on success, and fail the mission on its deadline or on abandonment, showing the outcome on the HUD and re-offering the mission at the giver.

#### Scenario: Deliver in time
- **WHEN** the player drives into the delivery radius before the deadline
- **THEN** the mission succeeds, the marker and countdown clear, and the HUD shows the success text for a few seconds

#### Scenario: Deadline passes
- **WHEN** the countdown reaches zero with objectives remaining
- **THEN** the mission fails, the HUD shows the failure text, and the giver offers it again

### Requirement: Mission Variants By Tone
The mission runner SHALL show the variant picked by the active tone mode for every text the player sees, and SHALL not place a mission that has no allowed variant in the active mode.

#### Scenario: Clean courier
- **WHEN** the active mode is `clean` and First Ride is enabled
- **THEN** the giver, objective texts and item name describe the bakery delivery and nothing from the gritty or dystopia variants appears

### Requirement: Host-Owned Mission State
In co-op the host SHALL own mission state and send it to peers on every change, any peer inside an objective's radius SHALL be able to complete that objective, and a mission whose accepting peer leaves SHALL fail.

#### Scenario: Guest delivers
- **WHEN** the host accepted the mission and a guest drives into the delivery radius first
- **THEN** the objective completes for the session and both players see the success text

### Requirement: First Story Pack
The base game SHALL ship a story pack with one complete mission on the Ottawa map, offered in all three tone modes, that validates in CI.

#### Scenario: Pack enabled
- **WHEN** the game starts with the Ottawa map and the first story pack enabled
- **THEN** the First Ride giver stands at its place in the ByWard Market and the mission can be completed
