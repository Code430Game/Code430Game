# Change: Packs in their own repositories, under a project organisation

**Status: proposed 2026-10-20 (human: "there should be an open spec to transition our packs to individual github repos. So ottawa would become a repo. This will allow multiple people to work on different regions and stories." and "we should look at moving this to its final repo").**

**Organisations:** `Code430Game`, created by the human on 2026-10-20; the game moved to
`Code430Game/Code430Game` the same day. Packs go in a second organisation, `Code430Packs`,
also created 2026-10-20 (human: "Second org? Code430Packs/location-ottawaonca (with nicer
casing)"). Check any new repository name on GitHub before using it.

**Layers added 2026-10-20** (human: "we want to encourage others to write their own stories in
the ottawa location. I wonder if we create basic versions of each and then say the ottawa pack
could reference a generic billboards for now. Then ideally someone could write their own …
story that uses the map and ads but makes a funny version for their friends where it places
them and items at their own locations in the map." and "I think we would need to mark a center
point or something if we reexport").

## Why
Everything lives in one repository today: the game, the importer, and every pack. The Ottawa
pack is 28 MB of the checkout and most of the churn: each re-export rewrites
`buildings.v0.json`, `road_graph.v0.json` and the terrain, and the history keeps every copy. Two
people working on different regions or stories would be editing the same repository and the
same CI, and a story writer would have to clone a city they don't touch. Map data is also under
a different licence (OpenStreetMap's ODbL) from the game, and that is clearer when it sits in
its own repository. The pack loader (`add-pack-loader`) already finds packs by folder, checks
their manifests and dependencies, and compares them in co-op, so packs can move out without the
game caring where they came from.

## What Changes
- **Two organisations on GitHub.** The game repository moves from `rjksn/Code430` to
  `Code430Game/Code430Game` by GitHub's repository transfer, which keeps issues, pull requests,
  stars and redirects from the old URL. Packs get their own repositories in `Code430Packs`, so
  pack maintainers get access to their pack without any access to the game, and the game
  organisation stays code only.
- **One repository per pack, or per city for maps.**
  - Repositories are named `<Kind>-<Name>` so each kind sorts together: `Location-OttawaOnCa`
    (city, ISO 3166 subdivision and country codes), `Story-FirstRide`, `Ads-Generic`,
    `Characters-<Name>`.
  - A location repository is a city and holds one pack per district: today's pack covers only
    Centretown, and the Glebe or the ByWard Market can join it later.
  - Every pack repository has a GitHub topic for its kind (`code430-location`,
    `code430-story`, …), so packs in people's own accounts can be found too.
  - Each pack repository has:
    - the pack folder;
    - the importer inputs that rebuild it: the region file, overrides and fixtures;
    - its own README, LICENSE and attribution (ODbL for OpenStreetMap-derived data);
    - a CI workflow that validates it with the game's pack validator at a pinned game version;
    - tagged releases with a zip and a sha256.
- **Packs in layers, with basic versions of each.** Each layer depends on the one below and may
  replace what it ships by id. The loader already orders packs by dependency; ads, placements and
  turf gain the "same id replaces" rule vehicles and factions have.
  - **The game:** code (gang behaviour, police, missions), the base factions, tone modes,
    strings and population, and the characters pack.
  - **`code430.ads-generic`:** billboards that suit any city, in `Ads-Generic`.
  - **Map packs (`Location-OttawaOnCa`):** the place. They hold the OSM data, terrain, hand fixes,
    and later the landmark models. They depend on `ads-generic` and may add ads of their own
    (Ottawa-only jokes).
  - **Story packs:** what happens there. Missions, dialogue, the story's gangs and their turf,
    and placements: named characters, items and cars at spots on the map. A story depends on a
    map, and it can replace that map's ads by id. A funny version for friends is a small story
    pack on top of the map, and it never copies or edits the map.
  - **`Story-FirstRide`** (from `add-story-pack`) is the example story and the template others
    copy.
- **Pack versions mean something.** `pack.json` versions and dependency ranges already
  exist; now a breaking change (a removed or renamed id, a moved origin, a new `engine_api`)
  needs a major bump, new content a minor one and fixes a patch, and each pack's CI refuses a
  changed pack without a bump. Stories depend on a map with a range (`^0.2`), so they get a
  map's fixes and new content but not its breaking releases.
- **A map keeps its centre.** Every map coordinate is metres from the manifest's `map.origin`,
  which the importer now takes from the bounding box's centre, so widening a map would move
  everything. The region file pins the origin, and a re-export that would move an existing
  pack's origin is refused unless asked for (`--new-origin`). Story placements and turf are
  written in latitude and longitude; the game converts them with the map's own projection at
  load. That way stories survive re-exports, and authors can take spots from any web map.
- **Privacy in stories.** The story template and `CONTRIBUTING.md` say not to publish real
  people's names or home locations: put characters near a park, a shop or a landmark instead. A
  personal story with friends' homes is meant to be shared offline (a folder or a private
  repository, which installs the same way). The pack validator warns when a story places a
  named character inside a residential building.
- **The game pins its packs.** A `packs.lock.json` in the game repository lists each pack's
  repository, tag, commit and sha256. `scripts/fetch-packs.sh` puts those packs in `packs/`
  (now ignored by git), and local CI, GitHub CI and `package-linux.sh` run it first. The tests
  that read Ottawa use the pinned pack.
- **What stays in the game repository:**
  - the importer (`tools/osm_import`) and the pack tools;
  - `code430.proving-ground`, the test district, built from committed inputs and checked by
    the tests on every run;
  - `code430.characters`, the built-in palettes and presets;
  - `packs/example`.

  A pack repository records which importer commit built it (`build.importer` in `pack.json`).
- **Install a pack from a repository.**
  - `scripts/install-pack.sh <owner>/<repo>[@tag]` downloads a release, checks its sha256,
    runs the validator, and puts the pack in the user pack folder (`user://packs`). The game
    lists it on the Packs tab as it does any pack.
  - In-game install from the Packs tab is a later stage (see `design.md`). It only takes
    data-only packs, as the loader does now.
- **A template repository** (`PackTemplate`) for new regions and stories. `CONTRIBUTING.md`
  gains "Make a region" and "Write a story pack" sections pointing at it.
- **Moving Ottawa out:**
  - its billboards move to `code430.ads-generic`, except any that only make sense in Ottawa,
    which stay in the map;
  - `Location-OttawaOnCa` starts from the current pack as `packs/centretown`, with its history
    split out of this repository (`git filter-repo --path packs/ottawa-centretown`) so blame
    still works;
  - `packs/ottawa-centretown` then leaves the game repository;
  - the game's old history is not rewritten: forks, pull request links and the 36 MB of
    packed history stay as they are.
- **Not in this change:** a pack browser or registry service, paid or private packs, code in
  packs (system packs stay refused), splitting the importer into its own repository.

## Impact
- Affected specs: `project-foundation` (ADDED: Packs In Their Own Repositories; ADDED: Pinned
  Pack Sources; ADDED: Installing A Pack From A Repository; ADDED: Packs In Layers; ADDED: A Map
  Keeps Its Origin; ADDED: Story Placements And Privacy; ADDED: Pack Versions).
- Affected code and config:
  - `packs.lock.json`, `scripts/fetch-packs.sh` and `scripts/install-pack.sh` (new);
  - `scripts/ci-local.sh`, `scripts/package-linux.sh`, `.github/workflows/*`, `.gitignore`;
  - `tools/pack_tools` (lock check, release zip and sha256), `pack.json` `build.importer`;
  - `PackLocator` (unchanged search directories; the user folder is where installs land);
  - `PackLoader.items()` (ads, placements and turf replace by id in dependency order), a
    placements file and schema, lat/lon conversion through the map's projection;
  - the importer (pinned origin from the region file, `--new-origin`);
  - README, CONTRIBUTING, `docs/pack-format/README.md`, `docs/open-work.md`.
- Outside the code, done by the human or with their approval:
  - create the two organisations and transfer the repository;
  - re-register the self-hosted runner under the organisation, or move public repositories
    back to GitHub-hosted runners, which are free for public repositories;
  - point the report relay's `REPO` and the "Code 430 Reporter" GitHub App installation at
    the new repository;
  - move the `relay-production` environment and its secrets if the transfer doesn't carry
    them.
- Depends on `add-pack-loader` (built; its Deck check 4.3 is still open). `add-story-pack`'s
  First Ride becomes the first `Story` repository.
