## ADDED Requirements

### Requirement: Packs In Their Own Repositories
Map, story and character packs other than the built-in ones SHALL each live in their own repository under the project's packs organisation, named `<Kind>-<Name>` with a GitHub topic for their kind (a location repository being a city that holds one pack per district), with the inputs that rebuild them, their own licence and attribution, a CI check by the game's pack validator, and tagged releases carrying a zip and its sha256.

#### Scenario: Two people work on different regions
- **WHEN** one contributor rebuilds the Ottawa pack while another edits a story pack
- **THEN** each works in that pack's own repository and neither change touches the game repository

#### Scenario: A second district joins a city
- **WHEN** a contributor maps the Glebe after Centretown
- **THEN** the Glebe is a new pack in the same `Location-OttawaOnCa` repository, sharing the city's origin, rather than a new repository

#### Scenario: A pack release
- **WHEN** a pack repository tags a release
- **THEN** its CI validates the pack with the pinned game version and publishes a zip of the pack with its sha256

### Requirement: Pinned Pack Sources
The game repository SHALL pin the packs it builds and tests with in a lock file (repository, tag, commit, sha256), and its CI and packaging SHALL fetch exactly those packs and check their hashes before running.

#### Scenario: A clean clone
- **WHEN** someone clones the game repository and runs the local CI
- **THEN** the locked packs are fetched, their hashes match, and the tests run against them

#### Scenario: A missing pack
- **WHEN** a test needs the Ottawa pack and it has not been fetched
- **THEN** the test fails with a message to run the fetch script instead of being skipped

### Requirement: Installing A Pack From A Repository
A player SHALL be able to install a data-only pack from a GitHub repository's release, which is checked against its sha256 and validated before it is placed in the user pack folder, where the game lists it like any other pack.

#### Scenario: Installing a story pack
- **WHEN** the player installs a story pack from its repository
- **THEN** the pack appears on the Packs tab after the next load

#### Scenario: A tampered download
- **WHEN** a downloaded release does not match its published sha256
- **THEN** nothing is installed and the reason is shown

### Requirement: Packs In Layers
Packs SHALL build on each other through dependencies (game, generic content, map, story), and a pack SHALL replace an ad, placement or turf of a pack it depends on when it ships the same id.

#### Scenario: A story replaces a billboard
- **WHEN** a story pack that depends on the Ottawa map ships an ad with the same id as one of the map's ads
- **THEN** the story's ad is shown on the billboards and the map pack is unchanged

### Requirement: A Map Keeps Its Origin
Re-exporting a map pack SHALL keep its origin unless a new origin is asked for, and story packs SHALL place things in latitude and longitude converted through the map's projection.

#### Scenario: A wider re-export
- **WHEN** the Ottawa map is re-exported with a larger bounding box
- **THEN** its origin stays where it was and a story's characters stand at the same spots

### Requirement: Story Placements And Privacy
Story packs SHALL be able to place named characters, items and cars on a map they depend on, and the pack tools SHALL warn when a published story places a named character inside a residential building.

#### Scenario: A story for friends
- **WHEN** someone writes a story that places their friends at spots on the Ottawa map
- **THEN** the characters appear there in the game, and the validator warns about any placed inside a house
