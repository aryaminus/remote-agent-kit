#!/usr/bin/env bash
# ask.sh — one question to your cloud agent, answered in your terminal.
#
#   ./scripts/ask.sh "what did you do today?"
#
# Creates/reuses a session (id kept in logs/ask-session), prints just the
# reply text. The gateway address is derived from your local tailnet (same
# logic as pair.sh) — or pin it with AGENT_URL in .env.
set -euo pipefail
cd "$(dirname "$0")/.."

MSG="${1:?usage: ask.sh \"your question\"}"
[[ -f .env ]] && { set -a; . ./.env; set +a; }

URL="${AGENT_URL:-}"
if [[ -z "$URL" ]]; then
  URL="$(tailscale status --json 2>/dev/null | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
    suf = d.get("MagicDNSSuffix", "")
    host = next((p.get("HostName","") for p in d.get("Peer", {}).values()
                 if p.get("HostName") == "hermes"), "")
    print(f"https://{host}.{suf}" if host and suf else "")
except Exception:
    print("")' || true)"
fi
[[ -n "$URL" ]] || { echo "Cannot derive the gateway address — is Tailscale running? (or set AGENT_URL in .env)"; exit 1; }
: "${API_SERVER_KEY:?API_SERVER_KEY missing from .env — run scripts/start.sh once}"

AUTH="Authorization: Bearer $API_SERVER_KEY"
mkdir -p logs

# Reuse the ask-session, else create it (survives as long as the gateway does).
SID="$(cat logs/ask-session 2>/dev/null || true)"
if [[ -z "$SID" ]] || ! curl -s -m 8 -o /dev/null -w '%{http_code}' -H "$AUTH" "$URL/api/sessions/$SID" | grep -q 200; then
  SID="$(curl -s -m 10 -X POST -H "$AUTH" -H 'Content-Type: application/json' \
    -d '{"title":"terminal"}' "$URL/api/sessions" | python3 -c 'import json,sys; print(json.load(sys.stdin)["session"]["id"])')"
  printf '%s' "$SID" > logs/ask-session
fi

# Build the payload with python so quotes/newlines in the message are safe.
PAYLOAD="$(MSG="$MSG" python3 -c 'import json,os; print(json.dumps({"message": os.environ["MSG"]}))')"

curl -s -m 120 -X POST -H "$AUTH" -H 'Content-Type: application/json' \
  -d "$PAYLOAD" "$URL/api/sessions/$SID/chat" \
  | python3 -c 'import json,sys
d = json.load(sys.stdin)
if "message" not in d:
    print(json.dumps(d)[:400]); sys.exit(1)
print(d["message"]["content"])'
