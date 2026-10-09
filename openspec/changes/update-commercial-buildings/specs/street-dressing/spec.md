## ADDED Requirements

### Requirement: Business Signs
Shops and street-level businesses from the map data SHALL get a sign over their shopfront showing their category or a generated generic name, lit at night, and SHALL NOT show real business names from the map data.

#### Scenario: A café on Bank Street
- **WHEN** the player walks past a building with a café mapped in it
- **THEN** a sign over its shopfront reads as a café, and not the café's real name

### Requirement: Posters By Tone
Blank street-level walls SHALL carry posters from a set chosen by the tone: propaganda and corporate posters in dystopia, flyers in gritty, community notices in clean, all original artwork.

#### Scenario: Switching to dystopia
- **WHEN** the player switches the tone to dystopia downtown
- **THEN** walls show dystopian posters and some towers carry banners
