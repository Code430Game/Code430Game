# Design: Packs in their own repositories

## Organisation
- `code430` on GitHub is a user account created 2020-05-17 with no repositories and no
  activity since (checked 2026-10-20 with `gh api users/code430`). GitHub doesn't hand out
  dormant names as a rule (only for trademark claims), so plan on a different name.
- Free on 2026-10-20 (GitHub names are case-insensitive): `Code430Game`, `Code430Games`,
  `Code430Studio`, `Code430Dev`, `Code430Org`, `Code430HQ`, `code-430`, `Code430City`,
  `Code430Project`, `Play430`, `OpenCode430`. A name can be taken at any time, so check again
  (`gh api users/<name>`, 404 means free) right before creating it. The same goes for a new
  game name, if the game is renamed rather than only the organisation.
- An organisation can only be created on the website (github.com → New organisation → Free);
  the REST API has no endpoint for it on github.com. The human creates it and adds Claude's
  token user (the human's own account) as owner.
- The transfer can be done by API once the organisation exists:
  `gh api -X POST repos/rjksn/Code430/transfer -f new_owner=<org>` (and optionally
  `-f new_name=<game>`). GitHub redirects the old URL and remotes; local clones keep working
  but should be pointed at the new URL.

## Repository names
- Map: `<City><Region><Country>` in PascalCase with the region's postal abbreviation:
  `OttawaOnCanada`, `GatineauQcCanada`. A region repository holds one pack per district under
  `packs/<pack-id>/`, so Centretown and later the Glebe can sit together and share inputs.
- Story: `Story<Name>` (`StoryFirstRide`). Characters: `Characters<Name>`.
- Pack ids stay as they are (`code430.ottawa-centretown`). The id is what saves, co-op and
  dependencies use; the repository name is only where the pack is hosted.

## Pack repository layout
```
OttawaOnCanada/
  packs/ottawa-centretown/     the pack, as today (pack.json, *.v0.json, terrain/)
  regions/centretown.json      importer inputs (bbox, sources, overrides)
  LICENSE                      ODbL 1.0 for the data; attribution in pack.json
  README.md                    what it covers, how to rebuild, which game version
  .github/workflows/pack.yml   validate at the pinned game tag; release on tag
```
- A rebuild is `python -m osm_import --region regions/centretown.json --pack-out
  packs/ottawa-centretown`, run from a checkout of the game at the pinned tag. `pack.json`
  gains `build.importer` (game commit) and `build.inputs` (the cached source dates), so a
  diff can show whether data or code changed.
- A release is a zip of `packs/<id>/` (without `chunks/`, which the game builds), its sha256,
  and the pack version from `pack.json` as the tag (`ottawa-centretown-v0.4.0`).

## The lock file
```json
{"schema_version": 0, "packs": [
  {"id": "code430.ottawa-centretown", "repo": "<org>/OttawaOnCanada",
   "tag": "ottawa-centretown-v0.4.0", "commit": "<sha>", "sha256": "<zip sha256>"}]}
```
- `scripts/fetch-packs.sh` downloads each release zip (or clones at the commit when
  `--source` is given, for pack authors), checks the sha256, unpacks into `packs/<folder>`,
  and skips packs already at the locked hash. It needs no token for public repositories.
- `tools/pack_tools` gains `lock check`: every locked pack is present, at its hash, and
  validates. CI runs it after the fetch.
- A pack author testing a local change points the game at their checkout with the existing
  search folders (copy or symlink into `user://packs`), or with `--packs=` for one run.

## Install from a repository
- Stage 1 (this change): `scripts/install-pack.sh <owner>/<repo>[@tag]`. It reads the release
  through the GitHub API, downloads the zip, checks the published sha256, validates, and
  unpacks into the user pack folder. Map packs are refused if one with the same id is already
  there (no silent replacement); `--replace` overrides.
- Stage 2 (later, its own tasks here or a follow-up change): a Packs-tab "Add from GitHub"
  row with the on-screen keyboard. It runs the same steps in the game (HTTPRequest, sha256,
  the loader's manifest checks) and accepts data-only packs only. Network access from the game
  is new, so that stage starts with a short design note on what the game may fetch.

## Tests and CI after the move
- Game tests that read Ottawa (`test_in_ottawa_*`, `test_osm_golden` inputs, the streaming
  and benchmark tests) use the fetched pack. When it is absent they fail with a message to
  run `scripts/fetch-packs.sh`; they are not skipped silently.
- The proving ground stays here as the game's own test district, regenerated and checked
  byte for byte by `test_proving_ground_pack.py` as today.
- The self-hosted runner `code430-mac` is registered to the repository. After the transfer,
  re-register it at the organisation, or, once the repositories are public, move the jobs
  back to GitHub-hosted runners (free for public repositories). Fork pull requests must never
  run on the self-hosted runner.

## Migration order
1. The human creates the organisation (name checked on GitHub first).
2. Transfer the game repository; update the local remote, the relay's `REPO`, the GitHub App
   installation, the runner, and the `relay-production` environment.
3. Create `PackTemplate`, then `OttawaOnCanada` from the split-out history, with its CI and
   first release.
4. Add `packs.lock.json` and `fetch-packs.sh`, wire them into CI and packaging, prove a clean
   clone builds and passes, then remove `packs/ottawa-centretown` from the game repository.
5. `install-pack.sh`, docs, and the first story pack repository once `add-story-pack` lands.

## Open questions
1. The organisation's name (and whether the game itself is renamed).
2. Do the proving ground and the characters pack stay in the game repository (proposed), or
   move too?
3. Public from the start, or private until the game goes public? Private repositories use the
   self-hosted runner and count against Actions minutes; public ones don't.
4. Should the Ottawa repository keep the pack's history (filter-repo, proposed) or start
   fresh from the current files?
