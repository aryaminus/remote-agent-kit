#!/usr/bin/env bash
# backup.sh — pull the newest server-side tarball over Tailscale + remind about
# Hetzner snapshots. Nothing secret is printed.
set -euo pipefail

HOST="$(terraform -chdir=terraform output -raw server_ipv4 2>/dev/null || true)"
INV_USER="$(grep -m1 ansible_user ansible/inventory/hosts.yml 2>/dev/null | awk '{print $2}' || echo agentbox)"
[[ -n "$HOST" ]] || { echo "No terraform output. Run: make apply"; exit 2; }

echo "Server-side nightly tarballs live in ~/backups (14-day retention)."
echo "Enable a daily Hetzner snapshot in the console too (~€0.50/mo)."

DEST="./backups"
mkdir -p "$DEST"
LATEST="$(ssh "${INV_USER}@${HOST}" 'ls -t ~/backups/agent-*.tar.gz* 2>/dev/null | head -1' || true)"
if [[ -z "$LATEST" ]]; then
  echo "No tarball on the server yet (cron runs at 03:00, or run: hermes backup)."
  exit 0
fi
rsync -avz --progress "${INV_USER}@${HOST}:${LATEST}" "$DEST/"
echo "Saved to $DEST/"
