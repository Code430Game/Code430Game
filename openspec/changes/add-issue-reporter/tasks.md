## 1. Report data
- [x] 1.1 `docs/report-format/report.schema.v1.json`; `build_info.json` stamped by `package-linux.sh` and the CI export, gitignored, with a `dev` fallback; tests on the stamp and on a dev run
- [x] 1.2 `diagnostics.gd`: build, machine, settings, place, and the frame-time ring buffer shared with the debug overlay; log tail; redaction of the home directory and user name; tests on every field and on redaction with a fake home directory
- [x] 1.3 `report_store.gd`: save to `user://reports/<id>/` (`report.json` exactly the schema, queue state in `state.json`), queue and retry times, 30-day pruning, auto title, the browser hand-off URL under 7,500 characters; tests. The full issue body is rendered by the relay (3.1), the one place that defuses untrusted text

## 2. Game
- [x] 2.1 Frame capture when the pause menu opens and on F8 (`report_open` action, named as a keyboard shortcut in the input-map test); holding Menu for a second opens the form; the form scene with thumbnail and toggle, area and severity drop-downs, title and description using the on-screen keyboard, the "what will be sent" page, and the queue list; controller navigation tests
- [x] 2.2 `relay_client.gd`: post, `Retry-After`, timeout and backoff, retry while paused, idempotent resend; the browser hand-off fallback on desktop; tests against a fake HTTP transport, with no live network in tests
- [ ] 2.3 Mac run: a report from Elgin and Nepean saved and listed; the hand-off page opens prefilled with the screenshot folder revealed

## 3. Relay
- [ ] 3.1 `tools/report_relay/` package (Python, pure-Python dependencies): issue body rendering under GitHub's length limit (log tail cut first) with the trailing report JSON, schema validation, size and image checks, defusing, rate limits, kill switch, App installation token, attachments branch, issue creation, idempotency by report id; pytest with GitHub mocked, running in the existing tools suite (CI and `scripts/ci-local.sh`); `worker.py` adapter and `wrangler.toml`; `pywrangler` as a tools dev dependency
- [ ] 3.2 `scripts/setup-report-labels.sh`; README section for registering the App, setting the secrets in the dashboard and deploying with `uv run pywrangler deploy`
- [ ] 3.3 **Stop: human decides on the relay (design.md open questions 1–3), registers the App, and deploys or approves deploying the relay; the relay URL goes into `report_config.json`**

## 4. Verification
- [ ] 4.1 Mac: one real report filed through the deployed relay into the repo, its screenshot rendering in the issue; a retried send returns the same issue; a sixth report in an hour is refused and stays queued
- [ ] 4.2 Deck benchmark on the usual autodrive route: no regression from the frame-time ring buffer
- [ ] 4.3 **Stop: human files a report from the Deck in Gaming Mode, including one made offline that is sent after reconnecting**
