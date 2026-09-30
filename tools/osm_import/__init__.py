"""OSM to road graph import pipeline for Code 430.

Stages (see openspec/changes/add-osm-road-import/design.md):
fetch -> filter -> project -> build graph -> fill defaults -> cluster junctions
-> validate -> export. Elevation is a later stage; positions carry y=0 until then.
"""

__version__ = "0.1.0"
