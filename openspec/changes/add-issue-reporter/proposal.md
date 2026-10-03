# Change: In-game issue reporter that files GitHub issues

**Status: approved 2026-10-03 (human: "Lets handle that PR that way I can more easily submit issues"; relay on Cloudflare at a workers.dev URL, no domain; defaults taken for the open questions). Proposed 2026-10-03 (human: "Can we add an open spec to create an issue form in the game itself? That could post direct to github issues? XD (That might be the hard part) I would think it would need a screenshot feature and a couple drop downs to sort the issue, and then contain the diagnostic information like build and machine data.").**

## Why
Field reports come from Deck drives and reach an agent as a chat message: "a curb on the
interior of a curved join", with no place, build or screenshot. `docs/backlog.md` asks every
entry to name its x,z, and entries still arrive without one. A report filed from inside the
game, at the moment the problem is on screen, can carry the screenshot, the exact place, the
build and the machine automatically, so a fresh session can go straight to it.

## What Changes
- **Report form.** "Report a problem" in the pause menu, and F8 on the keyboard. The frame
  under the menu is captured as the screenshot when the menu opens, with a thumbnail and an
  include toggle. Two drop-downs sort the report: **area** (Roads and junctions, Traffic,
  Pedestrians, Vehicles and handling, Buildings and world, Visuals, Performance, Controls and
  menus, Audio, Crash or freeze, Other) and **severity** (Cosmetic, Annoying, Blocks play,
  Crash). A one-line title, optional, filled from the area and the nearest road when left empty
  ("Roads and junctions: Elgin Street at x 237, z 18"), and an optional description; both use the
  Deck's on-screen keyboard like the Join address field. Fully driven by controller.
- **Diagnostics, shown before sending.** Build (commit, branch, build date, dirty flag),
  stamped into `build_info.json` by `package-linux.sh` and CI at export; `dev` plus the local
  commit when run from source. Godot version, OS and distribution, CPU, GPU and driver, memory,
  resolution, Deck detected, graphics preset, tone mode, loaded packs and versions, co-op role
  and peer count. Place: x, y, z, heading, on foot or in a car, nearest road name, edge id and
  junction node id, time of day. Frame time avg and p99 over the last 30 s. The last 200 lines
  of the Godot log with the home directory and user name redacted. A "what will be sent" page
  lists every field before anything leaves the machine.
- **Posting without an account** (see `design.md` for the options). Players do not sign in
  anywhere. The game sends the report over HTTPS to a small relay service,
  `tools/report_relay/` (Python, like every tool here), deployed to Cloudflare's Python Workers
  on the free tier at a `workers.dev` URL, so no domain is needed. The relay holds a GitHub App's private key as a deployment secret, files the issue as
  the App's bot in the configured repo (labels `in-game-report`, `needs-triage`, `area:<area>`
  and `severity:<severity>`, diagnostics in a collapsed section), and commits the screenshot as a
  JPEG to an `issue-attachments` branch that is never merged, linked from the issue. Nothing
  secret ships in the game: it knows only the relay URL. An optional "name to credit" field
  goes in the issue; no email or account is ever asked for.
- **Abuse and privacy at the relay.** Per-IP rate limit (5 reports an hour, 20 a day), a 2 MB
  request cap, JPEG and schema validation, text length limits, `@` mentions and HTML defused,
  and a kill switch that turns the relay off without a game update. The relay does not store IP
  addresses or reports; it only forwards them. The game shows exactly what will be sent and
  sends nothing without the player pressing Send.
- **Never lose a report.** Every report is first saved to `user://reports/<id>/` (report JSON,
  screenshot, log tail). When the relay is unreachable, not configured yet, or switched off,
  it stays queued; the form shows the queue and sends it when possible. On desktop a "file it
  in the browser" fallback opens GitHub's new-issue page prefilled with title, labels and body, and
  reveals the folder so the screenshot can be dragged in.
- **Setup script.** `scripts/setup-report-labels.sh` creates the labels with `gh` once.
- **Not in this change:** GitHub sign-in (reports are anonymous unless a name is given),
  video or multiple screenshots, crash-handler reports filed after a hard crash, duplicate
  detection across different reports, in-game reading of issue replies.

## Co-op authority
Reporting is local to each peer and nothing is replicated. The report records the peer's own
role (host or client) and the peer count. The form opens from the pause menu and pauses
exactly as the pause menu does today; what pausing means in a co-op session stays with
`add-coop-multiplayer`. The network requests run with `PROCESS_MODE_ALWAYS` so a paused tree
still sends.

## Tone
The form is UI, not authored content, and carries no descriptors. The active tone mode is
recorded in the diagnostics so triage knows what the screenshot may show.

## Impact
- Affected specs: `issue-reporting` (new capability).
- Affected code: `game/core/report/` (new: `diagnostics.gd`, `report_store.gd`,
  `relay_client.gd`, `report_config.json`), `tools/report_relay/` (new: the relay package, its
  Worker adapter, pytest tests and `wrangler.toml`), `docs/report-format/report.schema.v1.json` (new), `game/ui/report/` (new form
  scene), `game/ui/pause/pause_menu.gd` and `.tscn` (menu item, frame capture on open),
  `game/project.godot` (`report_open` action on F8), `game/core/debug/debug_overlay.gd` (frame
  time ring buffer shared with the report), `scripts/package-linux.sh` and
  `.github/workflows/ci.yml` (build stamp), `.gitignore` (`game/build_info.json`),
  `scripts/setup-report-labels.sh` (new), `docs/controls.md`, tests.
- Performance: no per-frame cost apart from the frame-time ring buffer (30 s of floats).
  Capture and JPEG encoding happen only when the form opens.
- Needs the human (`design.md`, open questions): yes to running the relay and where; register
  the GitHub App and install it on the repo; a Cloudflare account to deploy to. Until then the
  reporter runs in save-and-browser mode, so the game side can land first.
