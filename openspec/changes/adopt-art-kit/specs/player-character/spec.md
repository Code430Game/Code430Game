## ADDED Requirements

### Requirement: Characters From The Art Kit
The player, remote players, pedestrians, officers, paramedics and gang members SHALL be assembled from kit face, hair, beard, hat and outfit parts moved onto the game's character rig, picked and coloured by the character profile, with the two body types clearly distinct and clothes recognisable as what they are. The profile SHALL carry an outfit choice; the creator SHALL name hair, beards, hats and outfits as the kit does for the selected body. Without the kit models the primitive body SHALL still be drawn.

#### Scenario: A downtown crowd
- **WHEN** the player walks a busy street after the people stage
- **THEN** pedestrians wear varied kit outfits (hoodies, suits, dresses, shorts, work clothes) and walk with the crowd shader as before

#### Scenario: Picking an outfit in the creator
- **WHEN** the player steps the Outfit row and the Top colour row
- **THEN** the preview changes to the next kit outfit, its main garment takes the top colour, and the row reads the kit's name for it (for example "suit")

#### Scenario: Roles wear their outfits
- **WHEN** an officer, a paramedic or a gang member appears
- **THEN** the officer wears the uniform, the paramedic the work clothes with the vest in high-visibility yellow, and the gang member the crew's named outfit; random people never wear the uniform
