"""Report relay: files in-game issue reports as GitHub issues without the player having an account.

The package is plain Python with no compiled dependencies, so it runs on Cloudflare's Python
Workers (Pyodide) and under pytest alike. Everything that touches the outside world, HTTP, the
GitHub App key and the rate-limit store, is passed in; `worker.py` supplies the Cloudflare
versions.
"""
