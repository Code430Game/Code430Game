# Code 430 — Vision

Codename: **Code 430** (repo `Code430`). "Streetlevel" was the earlier working title; the final name is an open question.

## One-line pitch
A free, open-source, AI-built open-world crime game in the spirit of GTA III–IV, set on real city road networks pulled from OpenStreetMap, where anyone can publish their own maps, characters, and stories as packs.

## Why this exists
- Big-studio open-world crime games take a decade between releases and give players no way to tell their own stories in the world.
- Community GTA clones tend to be low-effort one-shots. We want one solid, shared base that keeps improving.
- Hand-designed game roads are often incoherent (dead ends, ramps that conflict, junctions that force U-turns). Real cities already solved road layout. We import it.
- AI agents can now write most of a game's code. This project is built that way on purpose, openly, and welcomes contributors and their agents.
- Mainstream games increasingly pick one tone for everyone and argue about it. We would rather ship a shell that lets the author pick: a sanitized city for a modern audience, the raw street reality of the GTA III–V era, or a dystopia where every sin is on a billboard. Same roads, same engine, the author's story.

## Pillars
1. **Real roads, real cities.** Road networks come from OpenStreetMap: topology, one-ways, lanes, ramps, bridges. Driving should make sense the way real driving does. Buildings can be approximate; roads cannot.
2. **Gritty street life.** The world is populated by the full spectrum of city life: dealers, sex workers, homeless people, people in crisis yelling on corners, commuters, cops. Mature (M-rated) tone. Stories are about characters, not lectures.
3. **Players are authors.** The base game is a platform. Map packs, character packs, and story packs from the community are the real content. Placing a character on a street and giving them a routine and a mission should require no programming.
4. **Free forever, open forever.** No fees for anyone, ever. Open-source engine (Godot), open-source code, packs hosted in public GitHub repos.
5. **Runs on a Steam Deck.** The Deck is the baseline target. If it runs well there, it runs well everywhere. Desktop gets a High preset on top.
6. **AI-built, in the open.** Code is written primarily by AI agents under human direction, using spec-driven development (OpenSpec). No apologies for it.
7. **One world, many tones.** The base city is neutral data. Content is tagged and can carry variants, so a player or story pack chooses a tone mode: `clean`, `gritty` (the default, see pillar 2), or `dystopia`. The same intersection can show wholesome good-morning ads, biting satirical ads, or neon cyberpunk ads, depending on the mode. Violence-free play is a mode, not a fork.
8. **Small-group co-op.** Up to 4 players, drop-in, playing in the same city. Not massive, not competitive. Systems from Phase 2 on are built co-op-ready so this is not a retrofit.

## What it is NOT (for now)
- Not a GTA V/VI-scale content game at launch. We start with one district.
- Not massively multiplayer and not PvP-first. Co-op for up to 4 friends is in scope (see pillar 8), but networking ships only after the single-player loop is solid.
- Not a mod of any Rockstar game. No Rockstar names, logos, assets, or close parodies of their brands.
- Not a place for content sexualizing minors or depicting real, identifiable people. (See AGENTS.md content policy.)

## Starting scope: one Ottawa district
Centretown, the ByWard Market / Lowertown area, and a stretch of Highway 417 (the Queensway) with at least one real interchange. Small enough to finish, varied enough to prove the pipeline: downtown grid, a market district, one-way pairs, a highway, ramps, and bridges.

## Pack types
| Type | What it contains | Code allowed? |
|---|---|---|
| Map pack | Road graph, terrain, generated city meshes, points of interest | No |
| Character pack | Models, animations, voices, behavior parameters, routines | No |
| Story pack | Characters placed on a map, dialogue, missions (declarative) | No |
| System pack | New mechanics, vehicles with custom logic, tools | Yes (trusted only) |

Data-only packs are safe for anyone to install. System packs run code and are marked trusted and reviewed.

## Tone modes
The base game ships three modes. Packs can add more or restrict which modes they support.

| Mode | Feel | Example: the same billboard |
|---|---|---|
| `clean` | Sanitized city for a modern or younger audience. No blood, no drugs, no sex work, mild language. Crime is stylized. | A cheerful "Good morning, Ottawa!" ad, or the billboard is simply blank. |
| `gritty` | Default. Street realism in the spirit of GTA III–IV: the full spectrum of city life, mature tone. | A satirical ad for a payday lender or an energy drink. |
| `dystopia` | Cyberpunk-leaning, everything exposed and for sale. Corporations, implants, surveillance, excess. | A wild neon ad for a black-market implant clinic. |

How it works, in short: every authored content item (ads, dialogue, NPC archetypes, radio, missions) carries content descriptors (violence, drugs, sex work, profanity, ...) and may carry per-mode variants. A mode is a filter plus a variant selector plus a set of mechanic flags (for example `violence: false`). Systems ask the active mode instead of hard-coding a tone. The default remains `gritty`; the other modes are not promoted at launch, but the tagging exists from the first content pack so nothing has to be rewritten later.

## Roadmap (phases)
- **Phase 0 — Foundations.** Repo, pinned Godot 4.x, AGENTS.md constitution, OpenSpec, CI with Linux builds, Deck and High presets.
- **Phase 1 — OSM road import.** Offline pipeline turns the Ottawa district into drivable roads, intersections, interchanges, and terrain. Drive a placeholder car on the Deck.
- **Phase 2 — Player.** On-foot movement, enter/exit vehicles, camera, controller-first controls. Built with a declared authority model so a second player can be added without rewrites.
- **Phase 3 — City life.** AI traffic on the imported road graph, pedestrians with routines and archetypes. Host-simulated, relevance-filtered, so it can later be replicated to co-op peers.
- **Phase 4 — Packs and tones.** Pack loader, pack format v1 with content descriptors and tone variants, the tone-mode switch, first character pack, first story pack with one complete mission. Billboards are the first tone-aware content.
- **Phase 5 — Co-op.** Host/join for up to 4 players over LAN or direct IP, pack-set verification on join, replicated players, vehicles, traffic, and mission state. Internet relay (for example Steam networking) is decided when a distribution channel is chosen.
- **Phase 6 — Registry.** In-game pack browser (works in Deck Game Mode), registry repo, creator docs.

## Success at the end of Phase 1
Someone who has driven in Ottawa can drive the Queensway, take a real exit, and get to the ByWard Market by a route that makes sense, on a Steam Deck, at a stable frame rate.
