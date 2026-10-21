## 0. Organisation (the human)
- [x] 0.1 **Stop: the human picks the organisation's name (checked free on GitHub right before) and creates it on github.com**
  - 2026-10-20: `Code430Game` (checked free that day), created by the human on the free plan. `Code430Packs` for the pack repositories, checked free and created the same day.
- [x] 0.2 Transfer `rjksn/Code430` to the organisation (with the human's go-ahead); update the local remote, the relay's `REPO` and GitHub App installation, the self-hosted runner, and the `relay-production` environment; CI green on the moved repository
  - 2026-10-20: transferred to `Code430Game/Code430Game` (private) by API after a PII scan (gitleaks over all refs, pattern scans of every blob, issues and comments; example names tidied in #124). The self-hosted runner, the `relay-production` environment, issues and PRs moved with it; the local remote points at the new URL; repository references updated. Left: the human transfers the "Code 430 Reporter" GitHub App to the organisation and installs it on the repository, then the relay is redeployed from the Mac with the new `REPO`. 2026-10-20: the App moved to `Code430Game` and is installed on the repository; the relay was redeployed and a test report filed issue #127 on the new repository

## 1. Pack repositories
- [x] 1.1 `Code430Packs/PackTemplate`: layout, README, LICENSE choices (ODbL for map data), `pack.yml` (validate at a pinned game tag, release zip and sha256 on tag); `tools/pack_tools` release command; tests
  - 2026-10-21: https://github.com/Code430Packs/PackTemplate (public, a template repository): README (names, layout, districts, stories and privacy, versions, releases), LICENSE.md choices, `code430.json` (pinned game commit), `.github/workflows/pack.yml` (validate and version-check with the game's pack tools on GitHub-hosted runners, release zip and sha256 on a `<folder>-v<version>` tag). The release step is the workflow's, so no separate `pack_tools` release command. While the game is private, a read-only deploy key on the game repository is each pack repository's `GAME_DEPLOY_KEY` secret
- [x] 1.2 `pack.json` `build.importer` and `build.inputs`, written by the importer; schema and validator; tests
  - 2026-10-21: written only with `--build-stamp` (the proving ground is checked byte for byte, so it stays unstamped); `inputs` comes from the road graph's per-layer sources
- [x] 1.2b Pack versions: the major, minor and patch rules in `docs/pack-format/README.md`; `pack_tools version check` against the last release tag (files changed without a bump, removed or renamed ids or a moved origin without a major bump, tag equals `<folder>-v<version>`); run in the template's CI; tests
  - 2026-10-21: `python -m pack_tools version check PACK (--ref TAG | --old DIR) [--tag TAG]` in `tools/pack_tools/versions.py`; ids come from the validator's tables; the template's CI wiring is part of 1.1
- [x] 1.2c District borders on the chunk grid of the city's origin, in chunk coordinates in the region file; the importer clips to them and refuses an off-grid or overlapping border; `pack_tools size check` (warn at 40 MB per file or 250 MB per pack, fail at 90 MB per file); tests
  - 2026-10-21: the size limits are done, as part of every validation run (`size_problems` in `validate.py`), not a separate command; borders in `tools/osm_import/region.py` (`border.chunks`, the lat/lon box around it for the import, `map.border` in pack.json, overlap with sibling region files refused). Centretown keeps its bbox until its next re-export moves it onto the grid (a breaking change, 0.3.0)
- [x] 1.3 `Code430Packs/Location-OttawaOnCa` (topic `code430-location`): history split out with `git filter-repo --path packs/ottawa-centretown` into `packs/centretown`, region file and overrides beside it, CI green, first release at `0.2.0`
  - 2026-10-21: https://github.com/Code430Packs/Location-OttawaOnCa (public, topics code430, code430-location): 42 commits split out with filter-repo, `#N` in messages rewritten to `Code430Game/Code430Game#N`, gitleaks clean; CI green; release `centretown-v0.2.0` (5.5 MB zip, sha256 verified on download)

## 1b. Layers
- [ ] 1.4 Same-id replacement for ads, placements and turf in `PackLoader.items()` in dependency order, with a logged conflict when unrelated packs share an id; tests
- [ ] 1.5 `code430.ads-generic` (the current billboards less any Ottawa-only ones) in `Code430Packs/Ads-Generic`; the Ottawa pack depends on it
- [x] 1.6 Pinned origin: `origin` in region files, the importer refuses a moved origin without `--new-origin`; Ottawa's current origin written into its region file; tests
  - 2026-10-21: `Projector.for_origin`; `check_origin` refuses a moved origin (crs, easting, northing) before any work; `regions/ottawa-centretown.json` pins lat 45.4200027, lon -75.6950007, which gives back the pack's 445625, 5029844
- [ ] 1.7 `placements.v0.json` (characters, items, cars at lat/lon) and lat/lon turf for story packs; schema, validator (the residential-building warning), the game converts through the map's projection; tests
- [x] 1.8 Privacy guidance in the story template and `CONTRIBUTING.md`; offline sharing documented
  - 2026-10-21: PackTemplate's README ("A story", Privacy) and CONTRIBUTING's "Make a region or write a story pack"; the validator's residential warning comes with placements (1.7)

## 2. The game pins its packs
- [x] 2.1 `packs.lock.json` and its schema; `scripts/fetch-packs.sh` (release zip, sha256, skip when current, `--source` to clone); `pack_tools lock check`; tests
  - 2026-10-21: `python -m pack_tools lock fetch|check` (`tools/pack_tools/lock.py`), schema `docs/pack-format/packs-lock.schema.v0.json`; fetched hashes in `packs/.fetched/`; `CODE430_PACK_BASE_URL` points downloads elsewhere (the tests use a file URL). No `--source` clone yet: a pack author copies or symlinks their checkout into `packs/` or `user://packs`
- [x] 2.2 `scripts/ci-local.sh`, GitHub CI and `package-linux.sh` fetch first; tests that read Ottawa fail with a fetch hint when it is missing; a clean clone builds and passes
  - 2026-10-21: `scripts/ci-local.sh` (which GitHub CI runs) fetches and lock-checks first; `package-linux.sh` fetches first; pytest stops at session start with the fetch hint when Ottawa is missing. A fresh clone of the branch (no Ottawa folder) fetched the release and passed scripts/ci-local.sh: 461 pytest, 667 gdUnit, 60 OpenSpec
- [x] 2.3 Remove `packs/ottawa-centretown` from the game repository; `.gitignore`; README, CONTRIBUTING ("Make a region", "Write a story pack"), `docs/pack-format/README.md`, `docs/open-work.md`
  - 2026-10-21: `packs/ottawa-centretown` untracked and ignored; README ("Get the packs", "Build a map pack"), CONTRIBUTING ("Make a region or write a story pack"), `docs/pack-format/README.md` (the lock file), `tools/tests/fixtures/README.md` (the three small OSM extracts credited under ODbL). The game repository's history still holds the old exports (not rewritten, as proposed)

## 3. Install from a repository
- [ ] 3.1 `scripts/install-pack.sh <owner>/<repo>[@tag]`: release lookup, sha256, validation, unpack into the user pack folder, refuse a duplicate map id without `--replace`; tests on a local fake release
- [ ] 3.2 Design note and tasks for installing from the Packs tab (stage 2)

## 4. Verification
- [ ] 4.1 Deck: package from a clean clone with fetched packs, deploy, benchmark against the previous build (unchanged)
- [ ] 4.2 **Stop: the human installs a pack from a repository on the Deck and sees it on the Packs tab**
