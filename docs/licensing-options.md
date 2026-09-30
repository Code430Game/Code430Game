# Licensing options for Code 430

**Decided 2026-09-30:** MIT for code (`LICENSE`), CC BY-SA 4.0 for first-party assets (`LICENSE-ASSETS`), ODbL for OSM-derived map data. The human accepted the recommendation; this can be revisited before the first public release since nothing has been distributed yet.

The rest of this page is the reasoning. Nothing here is legal advice; it is the practical summary an open-source game usually needs.

## What needs a license
There are three different things in this repo, and they get different licenses:

| Thing | Examples | Decision needed |
|---|---|---|
| Code | GDScript, Python tools, CI, schemas | Code license |
| First-party assets | Placeholder car, ads, textures, audio we make | Asset license |
| Map data derived from OSM | Road graphs, generated chunks in `packs/ottawa-*` | Not ours to choose: ODbL, see below |

Community packs choose their own license; the registry only requires that they state one.

## Code license: the realistic choices

| License | What it means | Fits the vision? |
|---|---|---|
| **MIT** (recommended) | Do anything, keep the copyright notice. Godot itself is MIT. | Yes. Simplest, most contributor-friendly, no friction with Steam or consoles. Someone could ship a closed fork; the vision says "free forever" but does not need to force that on others. |
| Apache 2.0 | Like MIT plus an explicit patent grant and a NOTICE file. | Yes. Slightly more paperwork. Pick this over MIT only if patents worry you. |
| GPL v3 | Forks must stay open source. | Partly. Guarantees openness, but it complicates system packs (`.pck` with code) and closed platforms, and scares some contributors. Also makes mixing with MIT addons one-directional. |
| MPL 2.0 | File-level copyleft: modified files stay open, new files can be closed. | Middle ground, rarely used for games. |

Recommendation: **MIT**. It matches Godot, most Godot addons (gdUnit4 is MIT), and the "welcome contributors and their agents" pillar.

## Asset license: the realistic choices

| License | What it means | Notes |
|---|---|---|
| **CC BY-SA 4.0** (recommended) | Use and remix with credit; derivatives must use the same license. | Keeps first-party art open in the same spirit as OSM's share-alike. Common for open game assets. |
| CC BY 4.0 | Use and remix with credit only. | Maximum reuse, no share-alike. Fine if you don't mind closed reuse of the art. |
| CC0 | Public domain. | No credit required. Simplest, least protective. |

Recommendation: **CC BY-SA 4.0** for first-party assets, stated in a `LICENSE-ASSETS` file and in each first-party pack's `pack.json`.

## Map data: ODbL, not optional
OpenStreetMap data is under the Open Database License. Anything we derive from it (the road graph, generated meshes) is a "derived database" and must be shared under ODbL with the credit "© OpenStreetMap contributors". AGENTS.md already requires this. Elevation from Natural Resources Canada is under the Open Government Licence – Canada, which needs an attribution line. Both credits go in the map pack manifest and the in-game credits.

Practical result: the Ottawa map pack will say `"license": "ODbL-1.0"` regardless of what we pick above.

## Distribution and licenses
- **GitHub Releases / self-built:** any of the above works. CI already plans Linux builds; Windows and macOS exports are the same step.
- **itch.io:** free to publish, any license.
- **Steam:** any license works, including GPL, but Steam Direct has a one-time fee (about USD 100 per game, recoupable). That is a paid service, so it is your call, not the agent's. Steamworks networking (free relay, invites, friends list) is only available through Steam.
- **Consoles:** Godot has no official console export; it goes through third-party porting partners. Not on the roadmap.

## Files that get created once you decide
- `LICENSE` at the root (code).
- `LICENSE-ASSETS` at the root (first-party assets).
- A `## Licensing` section in `README.md` explaining the three-way split.
- `license` and `attribution` fields in every first-party `pack.json`, validated in CI.

## What to tell me
Two words are enough, for example "MIT and CC BY-SA". If you want something not listed, say what you want to allow or forbid and I will map it to a license.
