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

# 1. SSH reachable
if $SSH true 2>/dev/null; then ok "SSH answers"; else bad "SSH unreachable"; fi
# 2. Tailscale up
TIP="$($TS || true)"
if [[ -n "$TIP" ]]; then ok "Tailscale up ($TIP)"; else bad "Tailscale down or no IP"; fi
# 3. Gateway API health (over the tailnet when known)
URL="http://${TIP:-$HOST}:8642/health"
if curl -s -m 8 -o /dev/null -w '%{http_code}' "$URL" | grep -q 200; then
  ok "Gateway /health → 200 at $URL"
else
  bad "Gateway /health not 200 at $URL"
fi
# 4. Gateway systemd running
if $SSH 'systemctl --user is-active hermes-gateway' 2>/dev/null | grep -q active; then
  ok "hermes-gateway active"
else
  bad "hermes-gateway not active (journalctl --user -u hermes-gateway)"
fi
# 5. Dashboard systemd running
if $SSH 'systemctl --user is-active hermes-dashboard' 2>/dev/null | grep -q active; then
  ok "hermes-dashboard active"
else
  bad "hermes-dashboard not active"
fi
# 6. UFW enabled, no public 8642/9119
if $SSH 'sudo ufw status' 2>/dev/null | grep -q 'Status: active'; then
  ok "UFW active"
else
  bad "UFW not active"
fi
# 7. Disk headroom (>5 GB free)
FREE="$($SSH 'df --output=avail / | tail -1' 2>/dev/null || echo 0)"
if [[ "$FREE" -gt 5000000 ]]; then ok "Disk OK ($((FREE/1024/1024)) GB free)"; else bad "Disk low"; fi

echo
echo "PASS $pass · FAIL $fail"
[[ "$fail" -eq 0 ]]
