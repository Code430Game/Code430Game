# Design: in-game issue reporter

## Getting a report into GitHub without an account
Not every player has a GitHub account, so the player never signs in. The game also cannot
carry a credential: anything in the `.pck` can be extracted, and a token with write access
would let anyone holding the build write to the repo. A report therefore has to go through
something that holds the credential on the game's behalf.

| | Save and hand off | GitHub sign-in (device flow) | Relay service (chosen) |
|---|---|---|---|
| Player needs a GitHub account | Yes | Yes | **No** |
| How | Desktop opens a prefilled `issues/new` page | Player enters a code at `github.com/login/device` once | Game posts to a small web service; the service files the issue as a bot |
| Screenshot | Dragged in by hand | Needs repo write access | Uploaded by the service |
| Deck in Gaming Mode | Poor | Good | Good |
| Setup | None | Register an App | Register an App, deploy a service |
| Cost | Free | Free | Free tier; a service to run |

The relay is the normal path. Save-and-hand-off stays as the offline and not-yet-deployed
fallback, so the game side can land before the relay exists. Device flow was the first draft
and is dropped: it locks out players without accounts.

## Relay
`tools/report_relay/` is Python, as `AGENTS.md` asks of tools. It is small on purpose: one
endpoint and no storage of its own. The logic lives in a plain package: validation, defusing,
the GitHub App token, the attachments commit, issue creation and idempotency. It takes its
HTTP client and rate limiter as parameters, so the existing pytest suite and CI test it with
GitHub mocked. A thin adapter, `worker.py`, runs it on Cloudflare's Python Workers. The same
package can sit behind any ASGI host if the human prefers one; only the rate limiter is
host-specific.

- `POST /v1/report`, `multipart/form-data` with `report` (JSON matching
  `docs/report-format/report.schema.v1.json`) and an optional `screenshot` (JPEG). It answers
  `201 {"issue_url": "…", "report_id": "…"}`, `200` with the same body when this report id was
  already filed, `400` with the failed check, `413`, `429` with `Retry-After`, or `503` when
  switched off.
- **Credentials.** A GitHub App (Issues read/write, Contents read/write, Metadata read,
  installed only on the target repo). Its private key and App id are Worker secrets. The relay
  mints a one-hour installation token per request burst (cached in memory) and files issues as
  `code430-reporter[bot]`.
- **Screenshot.** GitHub has no public API for issue attachments, so the relay commits the
  JPEG with `PUT /repos/{owner}/{repo}/contents/reports/{report_id}.jpg` on the
  `issue-attachments` branch (an orphan branch created on first use, never merged) and embeds
  `https://github.com/{owner}/{repo}/blob/issue-attachments/reports/{report_id}.jpg?raw=true`.
  That link renders for anyone who can see the issue.
- **Idempotent.** Before filing, the relay searches `in-game-report` issues for the report id
  carried in the body, so a game that retries after a dropped response cannot file twice.
- **Abuse controls.**
  - Rate limit per IP with the Workers rate-limiting binding: 5 reports an hour and 20 a day,
    plus a global ceiling of 200 a day.
  - Request cap of 2 MB. The screenshot must decode as a JPEG of at most 1920×1200.
  - Strict schema validation: title up to 120 characters, description up to 4,000, log tail up
    to 200 lines.
  - Text is defused before it reaches the issue: `@` gets a zero-width space after it so nobody is pinged, HTML is escaped, and
    links are shown as code.
  - Every issue gets `needs-triage`.
  - A `RELAY_ENABLED` variable switches the relay off at once, without a game update.
- **Privacy.** The relay never stores reports or IP addresses (the rate limiter keys on a
  salted hash that expires with its window). The optional "name to credit" is the only personal
  field, and it is free text.
- **Deploy.** `wrangler deploy` from `tools/report_relay/`, with secrets set once through
  `wrangler secret put`. `wrangler` is a deploy-time tool on the human's machine, not a build
  dependency. CI runs the relay tests but does not deploy.

## Game side
`relay_client.gd` posts with `HTTPRequest` (TLS) using `PROCESS_MODE_ALWAYS`, with a 20 s
timeout and backoff when queued reports are retried. The relay URL comes from
`game/core/report/report_config.json`; an empty URL means save-and-hand-off only. On `429` the
report stays queued until the `Retry-After` time has passed.

## Report body
```markdown
**Area:** Roads and junctions · **Severity:** Annoying · **Place:** x 237.0, z 18.0 (Elgin Street, edge w435115744.0, junction c901050337)

<description>

![screenshot](…?raw=true)

<details><summary>Diagnostics</summary>

| | |
|---|---|
| Build | 6ac9218 (main, 2026-10-03, clean) |
| Godot | 4.7.2.stable.official |
| Machine | Steam Deck (deck detected), SteamOS 3.7, AMD Custom APU 0405, RADV VANGOGH, 16 GB |
| Settings | preset deck, tone gritty, 1280×800 |
| Packs | code430.ottawa-centretown 0.x |
| Session | single player |
| Frame time | avg 9.7 ms, p99 15.1 ms (last 30 s) |
| Time of day | 13:10 |

```
<last 200 log lines, redacted>
```
</details>

<!-- code430-report {"id": "…", "version": 1, …} -->
```
The trailing comment carries the full report JSON so tools (and agents) can read it back
without scraping the table. The body stays under GitHub's 65,536-character limit: the log tail
is cut first if it would not fit.

## Redaction
Before anything is saved or sent, `diagnostics.gd` replaces the user's home directory with `~`
and the OS user name with `<user>` in every string, including the log tail, and drops
environment variables and command-line arguments other than the testbed flags it recognises.
Positions, road names and ids are kept: they are what the report is for.

## Local store and queue
`user://reports/<id>/` holds `report.json` (fields, diagnostics, state: `queued`, `sent` with
the issue URL, or `failed` with the last error), `screenshot.jpg` and `log_tail.txt`. The id is
the UTC timestamp plus eight random hex digits. The form lists queued reports with Send and
Delete. The reporter retries the queue when the form opens and once a minute while anything is
queued and the game is running. Sent reports are kept for 30 days, then deleted.

## Build stamp
`scripts/package-linux.sh` and the CI export step write `game/build_info.json` before
exporting (`commit`, `branch`, `date`, `dirty`), and the file is gitignored. At runtime the
reporter reads `res://build_info.json`. Run from source, it falls back to `dev` and the output
of `git rev-parse --short HEAD`, if git is available.

## Screen capture
When the pause menu opens, it awaits `RenderingServer.frame_post_draw` before showing itself
and keeps that frame's image. The capture includes the HUD on purpose: the HUD shows x, z and
the minimap. F8 does the same and opens the form directly. When the form opens with a thumbnail,
the image is downscaled to at most 1280×800 and encoded once.

## Open questions for the human
1. **Run the relay?** It is the only way to accept reports without accounts. Cloudflare Workers'
   free tier (100,000 requests a day) is far above what this needs. It does need a Cloudflare
   account, and it is a service you own: spam, its secret and its uptime. Alternatives with the
   same shape: any host that runs a Python ASGI app (Fly.io, Render, a small VPS). The package
   is portable apart from the rate limiter. Cloudflare's Python Workers run on Pyodide, so the
   package keeps to pure-Python dependencies.
2. **Register the App.** Name (for example "Code 430 Reporter"), owner `rjksn`, permissions
   Issues read/write, Contents read/write, Metadata read, no user authorisation, installed only
   on `rjksn/Code430`. Its private key goes into the Worker's secrets, never into the repo or the
   game.
3. **Attachments location.** An `issue-attachments` branch in `Code430` (recommended, one
   install), or a separate `Code430-reports` repo that keeps binary history out of the main
   repo.
4. **Public visibility.** While the repo is private, filed issues and screenshots are visible
   only to collaborators. Once it is public, every report is public. The send page says so, and
   the tone mode is recorded because gritty or dystopia screenshots may then be public.
5. **Areas and severities.** The lists in the proposal map one to one to labels. Change them
   now if triage wants something else.
