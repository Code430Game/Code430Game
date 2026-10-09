## MODIFIED Requirements

### Requirement: Character Profile
The player character's look SHALL be described by a profile (body type a or b, skin, hair style and colour, beard, eyewear, eye colour, brow and mouth shape, top and its print and pattern, jacket or coat or hoodie, trousers or shorts or skirt, shoes, hat, accessories, height, build, belly, shoulders) that is random on first start so nothing blocks play, older saved profiles SHALL load with defaults for fields they lack and look as they did, the player's body SHALL always be an adult body, and the body built from it SHALL be worn by the on-foot player and by that player's replica on other peers at three levels of detail switched by distance.

#### Scenario: First start
- **WHEN** the game starts with no saved characters
- **THEN** the player spawns wearing a random adult profile, and that profile is saved as the last created character

#### Scenario: Old preset
- **WHEN** a preset saved before the new fields existed is loaded
- **THEN** the body looks as it did when the preset was saved

#### Scenario: Body types
- **WHEN** the profile's body is `b`
- **THEN** the body is built from the `b` proportions and the sliders scale from them

#### Scenario: Remote player far away
- **WHEN** another peer's character is 200 m away
- **THEN** its lowest-detail body is drawn, and the full body returns as it approaches within 60 m

#### Scenario: Co-op
- **WHEN** a guest with a saved character joins a host
- **THEN** the host sees the guest's body built from the guest's profile, walking when the guest walks

#### Scenario: Walking
- **WHEN** the player moves on foot
- **THEN** the body's legs and arms swing in step with the distance covered and rest when the player stops

### Requirement: Character Creator
The creator SHALL present the profile's rows on pages switched with the shoulder buttons, SHALL name the body type through a strings table with per-mode variants rather than a fixed label, SHALL offer a print picker showing the active mode's variant of each print, and SHALL work with a controller alone.

#### Scenario: Body label in clean
- **WHEN** the creator is open in the clean mode
- **THEN** the body row reads "Body" with the values "A" and "B"

#### Scenario: Body label in gritty
- **WHEN** the creator is open in the gritty mode
- **THEN** the body row's values read "man" and "woman"

#### Scenario: Pages
- **WHEN** the player presses the right shoulder button on the Body page
- **THEN** the Face page shows with its rows and the preview stays

#### Scenario: Tweak and keep
- **WHEN** the player changes the top colour and presses Done
- **THEN** the on-foot body shows the new colour, and the next start loads the same body

#### Scenario: Presets
- **WHEN** the player saves a preset, randomises, then loads that preset
- **THEN** the body matches the saved preset
