#!/usr/bin/env bash
# perch-web.sh — run the Perch web app on THIS Mac, talking to your cloud box.
#
#   ./scripts/perch-web.sh              # build if needed, serve, print the URL
#   ./scripts/perch-web.sh --port 8081  # pick the local port (default 8081)
#   PERCH_REPO=~/Developer/nous ./scripts/perch-web.sh
#
# Nothing runs in the cloud for this: the gateway is already there. Two
# local requirements, both checked below:
#   1. This Mac must reach the tailnet (Tailscale app running — plain
#      public SSH is NOT enough for a browser).
#   2. The gateway must allow this page's origin (API_SERVER_CORS_ORIGINS
#      on the box must include http://localhost:<port> — set once via
#      deploy or finish.sh; this script verifies and tells you if missing).
set -euo pipefail
cd "$(dirname "$0")/.."

PORT=8081
while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) PORT="$2"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

PERCH_REPO="${PERCH_REPO:-$HOME/Developer/nous}"
APP_DIR="$PERCH_REPO/apps/mobile"
[[ -d "$APP_DIR" ]] || { echo "Perch checkout not found at $APP_DIR (set PERCH_REPO=...)"; exit 1; }
command -v node >/dev/null 2>&1 || { echo "node required (https://nodejs.org)"; exit 1; }

RK_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$RK_LIB_DIR/lib.sh"
# Gateway address: explicit override wins, else derive from the local tailnet
# (same derivation as pair.sh — never a hardcoded hostname in this repo).
GW_URL="${AGENT_URL:-$(rk_https_url)}"

# 1. Tailnet reachability from THIS machine (browser will need it too).
if [[ -z "$GW_URL" ]] || ! curl -s -m 8 -o /dev/null "$GW_URL/health" 2>/dev/null; then
  if command -v tailscale >/dev/null 2>&1 && tailscale status >/dev/null 2>&1; then
    echo "Tailnet is up but the gateway is unreachable at ${GW_URL:-<unknown>} — run: make doctor"
  else
    echo "Start Tailscale on this Mac first (App Store app, sign in, Connected)."
    echo "The browser reaches the box ONLY over the tailnet."
    echo "No tailnet at all? Set AGENT_URL=https://<your-box> explicitly."
  fi
  exit 1
fi
ok() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
ok "gateway answers at $GW_URL"

# 2. Build the web export if missing (Expo SDK 57 app, pnpm workspace).
if [[ ! -f "$APP_DIR/dist/index.html" ]]; then
  echo "Building Perch web export (one time, a few minutes)…"
  (cd "$APP_DIR" && pnpm install --frozen-lockfile=false >/dev/null 2>&1 || pnpm install >/dev/null 2>&1; pnpm export:web)
fi
[[ -f "$APP_DIR/dist/index.html" ]] || { echo "Build produced no dist/index.html — see output above."; exit 1; }
ok "web build present at $APP_DIR/dist"

# 3. Serve it (SPA fallback routing, like the box PWA role).
# NOTE: `serve -l <port>` is ignored by current serve versions (binds a
# random port) — the explicit tcp:// URI form is the one that sticks.
if command -v serve >/dev/null 2>&1; then
  SERVE=(serve -s "$APP_DIR/dist" --listen "tcp://127.0.0.1:$PORT")
else
  SERVE=(npx -y serve -s "$APP_DIR/dist" --listen "tcp://127.0.0.1:$PORT")
fi
pkill -f "serve.*$APP_DIR/dist" 2>/dev/null || true
nohup "${SERVE[@]}" > logs/perch-web.log 2>&1 < /dev/null &
disown 2>/dev/null || true
ready=0
for _ in $(seq 1 30); do
  curl -s -m 3 -o /dev/null "http://localhost:$PORT/" 2>/dev/null && { ready=1; break; }
  sleep 3
done
[[ "$ready" == "1" ]] || { echo "Server did not come up — see logs/perch-web.log"; exit 1; }
curl -s -m 6 -o /dev/null -w 'local app: %{http_code}\n' "http://localhost:$PORT/" || true

echo
echo "Open:  http://localhost:$PORT/"
echo "Then in Perch: Enter details instead —"
echo "  Address: $GW_URL"
echo "  API key: from 'make pair-qr' (or the server's pair.sh output)"
echo "If the app says it cannot reach the gateway: the box needs"
echo "  API_SERVER_CORS_ORIGINS=http://localhost:$PORT  + gateway restart."
