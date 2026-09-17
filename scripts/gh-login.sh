#!/usr/bin/env bash
# gh-login.sh — run GitHub's device-code login ON THE BOX from your Mac.
#
#   ./scripts/gh-login.sh
#
# WHY: gh on the box has no browser and no clipboard. The device flow
# needs both: it prints a one-time code you must approve at
# github.com/login/device. This helper runs the flow inside tmux on the
# box, fishes the code out of the log, prints it HERE, and waits for you
# to approve — then verifies the session. One command, one browser click.
#
# Per-user, one-time, unavoidable-by-design: GitHub only lets the
# ACCOUNT OWNER approve a device token, so every kit user does this once.
set -euo pipefail
cd "$(dirname "$0")/.."

HOST="$(terraform -chdir=terraform output -raw server_ipv4 2>/dev/null || true)"
[[ -n "$HOST" ]] || { echo "No terraform output. Run: make apply"; exit 2; }
INV_USER="$(grep -m1 ansible_user ansible/inventory/hosts.yml 2>/dev/null | awk '{print $2}' || echo agentbox)"
SSH="ssh -o BatchMode=yes -o ConnectTimeout=10 ${INV_USER}@${HOST}"
LOG=/tmp/ghlogin.log

if $SSH 'gh auth status >/dev/null 2>&1'; then
  echo "Already logged in:"
  $SSH 'gh auth status 2>&1 | grep -m1 "account"' || true
  exit 0
fi

echo "→ starting device flow on the box (tmux: ghlogin)"
$SSH "tmux kill-session -t ghlogin 2>/dev/null; rm -f $LOG; tmux new-session -d -s ghlogin 'gh auth login --git-protocol ssh --hostname github.com > $LOG 2>&1; echo DONE >> $LOG'"

# Poll the log for the one-time code (format: XXXX-XXXX).
CODE=""
for _ in $(seq 1 20); do
  sleep 2
  CODE="$($SSH "grep -oE '[A-Z0-9]{4}-[A-Z0-9]{4}' $LOG 2>/dev/null | head -1" || true)"
  [[ -n "$CODE" ]] && break
done
[[ -n "$CODE" ]] || { echo "No code appeared in ${_}0s. Try: ssh ${INV_USER}@${HOST} 'tmux attach -t ghlogin'"; exit 1; }

echo ""
echo "  1. Open:  https://github.com/login/device"
echo "  2. Code:  ${CODE}"
echo "     (expires ~15 min; rerun this script if it lapses)"
echo ""
echo "→ waiting for your approval…"

# Wait for DONE + a token in the log (approval completed).
for _ in $(seq 1 90); do
  sleep 5
  if $SSH "grep -q DONE $LOG" 2>/dev/null; then
    if $SSH 'gh auth status >/dev/null 2>&1'; then
      $SSH "tmux kill-session -t ghlogin 2>/dev/null || true"
      echo "✓ Logged in on the box:"
      $SSH 'gh auth status 2>&1 | grep -m1 "account"' || true
      echo "  API actions (pr comment/close/review, release, issue) now work from the box."
      exit 0
    fi
    # DONE but not logged in = user cancelled or code expired.
    echo "✗ Flow ended without a session (cancelled or expired). Rerun: ./scripts/gh-login.sh"
    $SSH "tmux kill-session -t ghlogin 2>/dev/null || true"
    exit 1
  fi
done
echo "Timed out after ~7 min. Rerun: ./scripts/gh-login.sh"
exit 1
