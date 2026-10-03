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

## Running it
- **Switch off** without a game update: set `RELAY_ENABLED` to `false` and deploy (or edit the
  variable in the dashboard). Games keep reports queued and retry later.
- **Limits:** 5 reports an hour and 20 a day per sender, 200 a day in all; counted in KV under a
  salted hash of the sender's IP, never the IP itself. Change them in `ratelimit.Limits`.
- **Screenshots** are committed to the `issue-attachments` branch (created on first use, never
  merged) and linked from the issue. Prune it by hand if it grows.
- Nothing is stored apart from the rate-limit counters, which expire within a day.
