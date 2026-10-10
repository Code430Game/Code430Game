## ADDED Requirements

### Requirement: Vehicle Models From The Art Kit
Vehicle catalogue entries SHALL be able to name a kit model (`model`) drawn at the near level of detail for the drivable car, traffic and parked cars, rebuilt into the same body, trim, headlight and tail-light surfaces as the generated body so tints and night lighting apply alike; the far level of detail and entries without a model SHALL use the generated body. Kit models SHALL be built by a repeatable tool from recipes (the source model, the body paint material, the length, and for derived vehicles the cab cut and the new body's dimensions), and the tool SHALL write the measured dims into the catalogue so the wheels and collision box match the model.

#### Scenario: Traffic in kit models
- **WHEN** the player drives downtown after the vehicle stage
- **THEN** traffic, parked cars and the player's car are kit models in palette colours, and police cars and ambulances carry their markings

#### Scenario: Nudging a derived vehicle
- **WHEN** a contributor changes a number in a recipe (for example the ambulance's box height) and runs the build script
- **THEN** the model, the catalogue dims and the lineup render are rebuilt from the unmodified sources, with no hand-edited model files
