# Design: bridge structures

## Grouping edges into bridges
OSM splits a bridge wherever a tag changes, so one deck is often several ways, and a divided
highway is two. Consecutive `bridge=*` edges that share a node and a layer join into one
bridge. Two one-way carriageways run parallel (heading within 20°) with a ribbon gap up to
`bridge_merge_gap_m` (3 m) along at least half their length. Those share a deck with the gap
filled, unless an outline says otherwise. A `man_made=bridge` outline that covers the edges
wins: its polygon is the deck footprint.

## Deck section
From the top: the existing road ribbon and kerbs (unchanged), then a deck slab whose bottom
is `depth = clamp(0.06 × span, 0.8, 1.8)` m below the road surface, and fascia quads on both
long edges that carry the parapets. The soffit is one strip per segment, with normals
pointing down. Vertex colours come from the concrete detail material, so no new textures.

## Piers and abutments
- Piers are spaced at most `pier_spacing_m` (25 m over roads, 40 m over water). Each one is
  nudged along the span until it is at least 1.5 m clear of every road ribbon and sidewalk
  underneath.
- If no clear spot exists within a third of the spacing, the span is left without that pier.
  A longer span is fine; a pier in a lane is not.
- Pier tops meet the soffit, and bottoms go 1 m into the terrain or the water floor.
- At each end, an abutment face slopes from the deck edge to the terrain at 1:1. A terrain
  clamp under the deck's footprint keeps the ground at least the clearance below the soffit,
  which also hides the "terrain shows through" cases at bridge ends from the junction
  backlog.

## Walkways
A pedestrian way belongs to a bridge if:
- its OSM way shares a bridge outline with the deck, or
- it has `bridge=*` and runs within `walkway_range_m` of the deck edge for most of its
  length.

Belonging walkways take the deck's height profile and widen the deck; the parapet moves
outside them, as `barriers.py` already does for walkways it finds. Sidewalk tags on a bridge
road (`sidewalk=both|left|right`) make a 1.8 m walkway on that side unless a separate footway
already does that job. The ground sidewalks of a road on another layer never join a deck.

## Open questions for the human
- Named bridges over the water (Mackenzie King, Laurier, Corktown): plain concrete for now,
  or a simple railing or arch style per bridge from an overrides file?
- Should the under-bridge road get darker shading (ambient occlusion fakery) in the deck
  preset?
