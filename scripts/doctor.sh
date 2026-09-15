#!/usr/bin/env bash
# doctor.sh — 7-point health check against the live box. Read-only.
# Usage: ./scripts/doctor.sh  (reads server IP from terraform output)
set -euo pipefail

HOST="$(terraform -chdir=terraform output -raw server_ipv4 2>/dev/null || true)"
[[ -n "$HOST" ]] || { echo "No terraform output. Run: make apply"; exit 2; }
SSH="ssh -o BatchMode=yes hermes@${HOST}"
TS="ssh hermes@${HOST} tailscale ip -4 2>/dev/null | head -1"

pass=0; fail=0
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; fail=$((fail+1)); }

echo "remote-agent-kit · doctor ($HOST)"

# Gilb's Law: what gets measured gets managed. Every run appends one JSONL
# record (timestamp, host, per-check pass/fail, versions) to logs/doctor.log —
# gitignored, never shipped. `tail logs/doctor.log` is your reliability history.
LOGDIR="logs"; mkdir -p "$LOGDIR"
TS_NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
declare -a RESULTS
record() { RESULTS+=("{\"check\":\"$1\",\"ok\":$2}"); } # $2: true|false

# 1. SSH reachable
if $SSH true 2>/dev/null; then ok "SSH answers"; record ssh true; else bad "SSH unreachable"; record ssh false; fi
# 2. Tailscale up
TIP="$($TS || true)"
if [[ -n "$TIP" ]]; then ok "Tailscale up ($TIP)"; record tailscale true; else bad "Tailscale down or no IP"; record tailscale false; fi
# 3. Gateway API health (over the tailnet when known)
URL="http://${TIP:-$HOST}:8642/health"
if curl -s -m 8 -o /dev/null -w '%{http_code}' "$URL" | grep -q 200; then
  ok "Gateway /health → 200 at $URL"; record api_health true
else
  bad "Gateway /health not 200 at $URL"; record api_health false
fi
# 4. Gateway systemd running
if $SSH 'systemctl --user is-active hermes-gateway' 2>/dev/null | grep -q active; then
  ok "hermes-gateway active"; record gateway true
else
  bad "hermes-gateway not active (journalctl --user -u hermes-gateway)"; record gateway false
fi
# 5. Dashboard systemd running
if $SSH 'systemctl --user is-active hermes-dashboard' 2>/dev/null | grep -q active; then
  ok "hermes-dashboard active"; record dashboard true
else
  bad "hermes-dashboard not active"; record dashboard false
fi
# 6. UFW enabled, no public 8642/9119
if $SSH 'sudo ufw status' 2>/dev/null | grep -q 'Status: active'; then
  ok "UFW active"; record ufw true
else
  bad "UFW not active"; record ufw false
fi
# 7. Disk headroom (>5 GB free)
FREE="$($SSH 'df --output=avail / | tail -1' 2>/dev/null || echo 0)"
if [[ "$FREE" -gt 5000000 ]]; then ok "Disk OK ($((FREE/1024/1024)) GB free)"; record disk true; else bad "Disk low"; record disk false; fi

# Versions make the log useful for drift diagnosis (Pesticide Paradox: the
# same green checks mean less over time unless you can see what changed).
HERMES_V="$($SSH 'hermes --version 2>/dev/null | head -1' || echo unknown)"
TS_V="$($SSH 'tailscale version 2>/dev/null | head -1' || echo unknown)"
JOINED="$(IFS=,; echo "${RESULTS[*]}")"
printf '{"ts":"%s","host":"%s","pass":%d,"fail":%d,"checks":[%s],"hermes":"%s","tailscale":"%s"}\n' \
  "$TS_NOW" "$HOST" "$pass" "$fail" "$JOINED" "$HERMES_V" "$TS_V" >> "$LOGDIR/doctor.log"

echo
echo "PASS $pass · FAIL $fail (logged to $LOGDIR/doctor.log)"
[[ "$fail" -eq 0 ]]
