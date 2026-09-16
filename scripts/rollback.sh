#!/usr/bin/env bash
# rollback.sh — Law of Unintended Consequences, handled: every change must
# have a way back. Restores ~/.hermes on the server from a local backup
# tarball (made by scripts/backup.sh), after snapshotting current state.
# Interactive by design (Principle of Least Astonishment): restoring
# overwrites live agent memory/skills, so it always asks first.
set -euo pipefail
cd "$(dirname "$0")/.."

HOST="$(terraform -chdir=terraform output -raw server_ipv4 2>/dev/null || true)"
INV_USER="$(grep -m1 ansible_user ansible/inventory/hosts.yml 2>/dev/null | awk '{print $2}' || echo agentbox)"
[[ -n "$HOST" ]] || { echo "No terraform output. Run: make apply"; exit 2; }
SSH="ssh ${INV_USER}@${HOST}"

FILE="${1:-}"
if [[ -z "$FILE" ]]; then
  echo "Local backups:"
  ls -t backups/agent-*.tar.gz* 2>/dev/null || { echo "  (none — run: make backup)"; exit 1; }
  echo
  read -r -p "Restore which file? (path) " FILE
fi
[[ -f "$FILE" ]] || { echo "Not found: $FILE"; exit 1; }

echo
echo "This will OVERWRITE ~/.hermes on ${HOST} (memory, skills, sessions)"
echo "with: ${FILE}"
echo "Current state is snapshotted first to ~/backups/pre-rollback-<date>.tar.gz"
read -r -p "Type RESTORE to continue: " confirm
[[ "$confirm" == "RESTORE" ]] || { echo "Aborted. Nothing changed."; exit 0; }

TS="$(date +%Y%m%d-%H%M%S)"
echo "→ snapshotting current state on server…"
$SSH "tar -czf ~/backups/pre-rollback-${TS}.tar.gz -C ~/.hermes . 2>/dev/null; echo snapshot-ok"

echo "→ uploading ${FILE}…"
rsync -avz --progress "$FILE" "${INV_USER}@${HOST}:~/backups/restore-incoming.tgz"

echo "→ stopping gateway, restoring, restarting…"
$SSH 'systemctl --user stop hermes-gateway hermes-dashboard 2>/dev/null;
      tar -xzf ~/backups/restore-incoming.tgz -C ~/.hermes;
      rm ~/backups/restore-incoming.tgz;
      systemctl --user start hermes-gateway hermes-dashboard;
      sleep 5; systemctl --user is-active hermes-gateway'

echo
echo "Restore done. Verify: make doctor — and message the bot."
echo "Changed your mind? The pre-rollback snapshot is ~/backups/pre-rollback-${TS}.tar.gz"
