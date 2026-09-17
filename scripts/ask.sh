#!/usr/bin/env bash
# ask.sh — one question to your cloud agent, answered in your terminal.
#
#   ./scripts/ask.sh "what did you do today?"
#
# Transport: SSH by default (the curl runs INSIDE the box against
# 127.0.0.1:8642 — your Mac needs no VPN, no open ports, and never holds
# the API key in memory beyond the command). Set ASK_TRANSPORT=https to
# force the Tailscale URL instead (needs Tailscale running locally).
set -euo pipefail
cd "$(dirname "$0")/.."

MSG="${1:?usage: ask.sh \"your question\"}"
# Exec-door ssh alias. ssh -G answers for ANY name, so probe for a real
# configured host: try box-x (docs default), then hermes-x (owner's box).
# Override with ASK_SSH_HOST if your alias differs.
pick_host() {
  local a
  for a in box-x hermes-x; do
    a_cfg="$(ssh -G "$a" 2>/dev/null | awk -v h="$a" '$1=="hostname" && $2!=h {print "yes"; exit}')"
    [[ -n "$a_cfg" ]] && { echo "$a"; return; }
  done
  echo ""
}
ASK_HOST="${ASK_SSH_HOST:-$(pick_host)}"
[[ -n "$ASK_HOST" ]] || { echo "No ssh alias 'box-x' or 'hermes-x' in ~/.ssh/config (or set ASK_SSH_HOST)."; exit 1; }
SSH="ssh -o BatchMode=yes -o ConnectTimeout=10 ${ASK_HOST}"
MODE="${ASK_TRANSPORT:-auto}"
mkdir -p logs

if [[ "$MODE" == "https" ]] || ! $SSH true 2>/dev/null; then
  # Tailnet/direct-URL path (needs local Tailscale or explicit AGENT_URL).
  # Hostname follows group_vars agent_hostname (default agentbox).
  [[ -f .env ]] && { set -a; . ./.env; set +a; }
  URL="${AGENT_URL:-$(RK_AGENT_HOST="$(grep -m1 agent_hostname ansible/inventory/group_vars/all.yml 2>/dev/null | awk '{print $2}' || echo agentbox)" tailscale status --json 2>/dev/null | python3 -c 'import json,os,sys
try:
    d = json.load(sys.stdin)
    suf = d.get("MagicDNSSuffix", "")
    want = os.environ.get("RK_AGENT_HOST", "agentbox")
    host = next((p.get("HostName","") for p in d.get("Peer", {}).values()
                 if p.get("HostName") == want), "")
    print(f"https://{host}.{suf}" if host and suf else "")
except Exception:
    print("")' || true)}"
  [[ -n "$URL" ]] || { echo "No route: SSH unreachable and no tailnet URL (is Tailscale running? set AGENT_URL in .env)"; exit 1; }
  : "${API_SERVER_KEY:?API_SERVER_KEY missing from .env — run scripts/start.sh once}"
  AUTH="Authorization: Bearer $API_SERVER_KEY"
  sid_flow() {
    SID="$(cat logs/ask-session 2>/dev/null || true)"
    if [[ -z "$SID" ]] || ! curl -s -m 8 -o /dev/null -w '%{http_code}' -H "$AUTH" "$URL/api/sessions/$SID" | grep -q 200; then
      SID="$(curl -s -m 10 -X POST -H "$AUTH" -H 'Content-Type: application/json' \
        -d '{"title":"terminal"}' "$URL/api/sessions" | python3 -c 'import json,sys; print(json.load(sys.stdin)["session"]["id"])')"
      printf '%s' "$SID" > logs/ask-session
    fi
    PAYLOAD="$(MSG="$MSG" python3 -c 'import json,os; print(json.dumps({"message": os.environ["MSG"]}))')"
    curl -s -m 120 -X POST -H "$AUTH" -H 'Content-Type: application/json' \
      -d "$PAYLOAD" "$URL/api/sessions/$SID/chat" \
      | python3 -c 'import json,sys
d = json.load(sys.stdin)
if "message" not in d:
    print(json.dumps(d)[:400]); sys.exit(1)
print(d["message"]["content"])'
  }
  sid_flow
else
  # SSH path: everything executes on the box; nothing but the answer crosses.
  # NEVER pass "$MSG" as an ssh CLI arg: ssh re-joins/re-splits args on
  # spaces, so a multi-word message silently truncates to its first word
  # (live-caught: 'Compute 2+2' arrived as 'Compute'). base64 in an unquoted
  # heredoc is immune to quotes/spaces/$ alike.
  MSG_B64="$(printf '%s' "$MSG" | base64 | tr -d '\n')"
  # shellcheck disable=SC2029
  $SSH python3 - <<PYEOF
import base64, json, os, subprocess, sys
from datetime import datetime, timezone

msg = base64.b64decode("$MSG_B64").decode()
KEY = subprocess.run(
    "grep -m1 '^API_SERVER_KEY=' ~/.hermes/.env | cut -d= -f2-",
    shell=True, capture_output=True, text=True).stdout.strip()
SIDF = os.path.join(os.path.expanduser("~"), ".ask-session")

def api(method, path, data=None):
    cmd = ["curl", "-s", "-m", "120", "-X", method,
           "-H", f"Authorization: Bearer {KEY}"]
    if data is not None:
        cmd += ["-H", "Content-Type: application/json", "-d", json.dumps(data)]
    cmd.append("http://127.0.0.1:8642" + path)
    return subprocess.run(cmd, capture_output=True, text=True).stdout

def sessions():
    d = json.loads(api("GET", "/api/sessions"))
    data = d.get("data", d.get("sessions", []))
    return {s.get("id") for s in data if isinstance(s, dict) and s.get("id")}

import os as _os
KEEP = _os.environ.get("RK_ASK_KEEP") == "1"
if KEEP:
    try:
        with open(SIDF) as f:
            sid = f.read().strip()
        if sid not in sessions():
            raise ValueError("stale")
    except Exception:
        KEEP = False  # fall through to fresh
if KEEP:
    pass
else:
    ts = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S-%f")
    sid = json.loads(api("POST", "/api/sessions",
                         {"title": f"ask {ts}"}))["session"]["id"]
    with open(SIDF, "w") as f:
        f.write(sid)

ans = json.loads(api("POST", f"/api/sessions/{sid}/chat", {"message": msg}))
if "message" not in ans:
    print(json.dumps(ans)[:400]); sys.exit(1)
print(ans["message"]["content"])
PYEOF
fi
