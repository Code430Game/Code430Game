# Report relay

Files in-game issue reports ("Report a problem", hold Menu, F8) as GitHub issues, so players
need no GitHub account and the game ships no credential. It runs as a Cloudflare Python Worker
at `https://code430-report-relay.<your-subdomain>.workers.dev`; no domain is needed.

The logic is the `report_relay` package (`src/report_relay/`), tested by the tools suite
(`cd tools && uv run pytest`). `src/worker.py` is the Cloudflare glue.

## One-time setup
Wrangler needs Node 22 or newer (`.nvmrc` here says 22). With nvm, prefix the commands below
with `nvm exec 22`, for example `nvm exec 22 uv run pywrangler deploy`.

1. **GitHub App.** github.com → Settings → Developer settings → GitHub Apps → New GitHub App.
   - Name: for example "Code 430 Reporter". Homepage: the repo URL. Webhook: off.
   - Repository permissions: Issues read and write, Contents read and write, Metadata read.
   - Install it on `rjksn/Code430` only. Note the App id, and generate a private key (a `.pem`
     file download). Keep the key out of the repo.
2. **Labels.** From the repo root: `scripts/setup-report-labels.sh` (uses `gh`).
3. **Cloudflare.** From this folder:
   ```
   uv run pywrangler login                      # opens the browser once
   uv run pywrangler kv namespace create REPORT_LIMITS
   ```
   Put the namespace id into `wrangler.toml` (`[[kv_namespaces]] id`; wrangler will not run
   while that id is empty, so leave the block commented out until then) and the App id into
   `[vars] APP_ID`.
4. **Secrets**, in the Cloudflare dashboard (Workers → code430-report-relay → Settings →
   Variables and Secrets) or with `uv run pywrangler secret put NAME`:
   - `PRIVATE_KEY`: the whole `.pem` file, BEGIN and END lines included.
   - `RATE_SALT`: any long random string (`openssl rand -hex 32`).
5. **Deploy:** `uv run pywrangler deploy`. Check `https://<worker>/health` answers
   `{"ok": true, "enabled": true}`.
6. **Point the game at it:** put the Worker URL into `game/core/report/report_config.json`
   (`relay_url`).

## Deploying from CI
`.github/workflows/relay.yml` deploys the relay whenever it changes on main (and on demand from
the Actions tab), then checks `/health` and re-runs the label script. Any machine that can push
to main can ship it; nobody needs a Cloudflare login.

One-time setup:
1. **A Cloudflare API token** for CI, separate from anyone's login: Cloudflare dashboard → My
   Profile → API Tokens → Create Token → the "Edit Cloudflare Workers" template, Account
   Resources limited to this account, Zone Resources none needed (the relay runs on
   `workers.dev`). Give it an expiry and roll it now and then.
2. **The GitHub environment** `relay-production` (Settings → Environments) is limited to the
   `main` branch. Put the token there as the secret `CLOUDFLARE_API_TOKEN`: on the Mac, run
   `gh secret set CLOUDFLARE_API_TOKEN --env relay-production` and paste it at the prompt.
3. Optional: add yourself as a required reviewer on the environment, so every deploy waits for a
   click.

Only the deploy job gets the token. Tests run in a job without it, so nothing from a pull
request or another branch can read it.

## Updating it
- **Quick tags (2026-10-07)** added an optional `tags` field to the report (schema still version
  1; a report without tags is unchanged). A relay deployed before that refuses tagged reports
  as an unknown key, and the game then keeps them for the player to resend. So deploy the relay
  (`uv run pywrangler deploy`) and re-run `scripts/setup-report-labels.sh` for the `tag:*`
  labels before players get a game build with tags.

## Running it
- **Switch off** without a game update: set `RELAY_ENABLED` to `false` and deploy (or edit the
  variable in the dashboard). Games keep reports queued and retry later.
- **Limits:** 5 reports an hour and 20 a day per sender, 200 a day in all; counted in KV under a
  salted hash of the sender's IP, never the IP itself. Change them in `ratelimit.Limits`.
- **Screenshots** are committed to the `issue-attachments` branch (created on first use, never
  merged) and linked from the issue. Prune it by hand if it grows.
- Nothing is stored apart from the rate-limit counters, which expire within a day.
