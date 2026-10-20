## 0. Organisation (the human)
- [x] 0.1 **Stop: the human picks the organisation's name (checked free on GitHub right before) and creates it on github.com**
  - 2026-10-20: `Code430Game` (checked free that day), created by the human on the free plan.
- [ ] 0.2 Transfer `rjksn/Code430` to the organisation (with the human's go-ahead); update the local remote, the relay's `REPO` and GitHub App installation, the self-hosted runner, and the `relay-production` environment; CI green on the moved repository
  - 2026-10-20: transferred to `Code430Game/Code430Game` (private) by API after a PII scan (gitleaks over all refs, pattern scans of every blob, issues and comments; example names tidied in #124). The self-hosted runner, the `relay-production` environment, issues and PRs moved with it; the local remote points at the new URL; repository references updated. Left: the human transfers the "Code 430 Reporter" GitHub App to the organisation and installs it on the repository, then the relay is redeployed from the Mac with the new `REPO`

## 1. Pack repositories
- [ ] 1.1 `PackTemplate`: layout, README, LICENSE choices (ODbL for map data), `pack.yml` (validate at a pinned game tag, release zip and sha256 on tag); `tools/pack_tools` release command; tests
- [ ] 1.2 `pack.json` `build.importer` and `build.inputs`, written by the importer; schema and validator; tests
- [ ] 1.3 `OttawaOnCanada`: history split out with `git filter-repo --path packs/ottawa-centretown` into `packs/`, region file and overrides beside it, CI green, first release

## 2. The game pins its packs
- [ ] 2.1 `packs.lock.json` and its schema; `scripts/fetch-packs.sh` (release zip, sha256, skip when current, `--source` to clone); `pack_tools lock check`; tests
- [ ] 2.2 `scripts/ci-local.sh`, GitHub CI and `package-linux.sh` fetch first; tests that read Ottawa fail with a fetch hint when it is missing; a clean clone builds and passes
- [ ] 2.3 Remove `packs/ottawa-centretown` from the game repository; `.gitignore`; README, CONTRIBUTING ("Make a region", "Write a story pack"), `docs/pack-format/README.md`, `docs/open-work.md`

## 3. Install from a repository
- [ ] 3.1 `scripts/install-pack.sh <owner>/<repo>[@tag]`: release lookup, sha256, validation, unpack into the user pack folder, refuse a duplicate map id without `--replace`; tests on a local fake release
- [ ] 3.2 Design note and tasks for installing from the Packs tab (stage 2)

## 4. Verification
- [ ] 4.1 Deck: package from a clean clone with fetched packs, deploy, benchmark against the previous build (unchanged)
- [ ] 4.2 **Stop: the human installs a pack from a repository on the Deck and sees it on the Packs tab**
