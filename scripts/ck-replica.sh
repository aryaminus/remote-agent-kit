#!/usr/bin/env bash
# ck-replica.sh — exact replica of LOCAL ControlKeel state onto the cloud box.
#
#   ./scripts/ck-replica.sh            # snapshot + transfer + verify
#   ./scripts/ck-replica.sh --verify-only
#
# WHAT: ~/controlkeel/controlkeel.db (WAL-safe online snapshot — the MCP
# server keeps running) + project.json  →  ~/controlkeel/ on the box,
# PLUS per-project controlkeel/ state dirs for the migrated projects →
# ~/work/<proj>/controlkeel/ on the box. Machine-specific shims (bin/),
# transient shm files are EXCLUDED (regenerate via `controlkeel init`).
# WHY NOT plain cp/rsync of the live db: SQLite WAL mode means the .db
# file alone can be a torn snapshot — `.backup` takes a consistent image
# through the online-backup API instead.
set -euo pipefail
cd "$(dirname "$0")/.."
RK_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

HOST="$(terraform -chdir=terraform output -raw server_ipv4 2>/dev/null || true)"
[[ -n "$HOST" ]] || { echo "No terraform output. Run: make apply"; exit 2; }
INV_USER="$(grep -m1 ansible_user ansible/inventory/hosts.yml 2>/dev/null | awk '{print $2}' || echo agentbox)"
SSH="ssh -o BatchMode=yes -o ConnectTimeout=10 ${INV_USER}@${HOST}"
SRC="$HOME/controlkeel/controlkeel.db"
[[ -f "$SRC" ]] || { echo "No local CK database at $SRC"; exit 2; }

# Projects whose local controlkeel/ state should follow them to ~/work.
# Project dirs whose local controlkeel/ state follows them to ~/work.
# Override with YOUR folder names — the default is intentionally empty so
# strangers replicate only the main store until they opt in:
#   CK_REPLICA_PROJECTS="mysite myapp" ./scripts/ck-replica.sh
PROJECTS="${CK_REPLICA_PROJECTS:-}"

COUNTS_SQL="SELECT (SELECT COUNT(*) FROM sessions),(SELECT COUNT(*) FROM findings);"
verify_one() { # label
  local l_cnt r_cnt
  l_cnt=$(sqlite3 "$SRC" "$COUNTS_SQL" 2>/dev/null || echo "?")
  r_cnt=$($SSH "sqlite3 \$HOME/controlkeel/controlkeel.db \"$COUNTS_SQL\"" 2>/dev/null || echo "?")
  if [[ "$l_cnt" == "$r_cnt" && "$l_cnt" != "?" ]]; then
    printf '  \033[32m✓\033[0m %s sessions|findings %s\n' "$1" "$l_cnt"
  else
    printf '  \033[31m✗\033[0m %s local=%s remote=%s\n' "$1" "$l_cnt" "$r_cnt"
    return 1
  fi
}

if [[ "${1:-}" == "--verify-only" ]]; then
  echo "remote-agent-kit · ck-replica verify"
  fails=0
  $SSH "sqlite3 \$HOME/controlkeel/controlkeel.db 'PRAGMA integrity_check;'" 2>/dev/null | grep -q "^ok$" \
    && echo "  ✓ main db integrity ok" || { echo "  ✗ main db integrity"; fails=1; }
  verify_one "main store" || fails=1
  exit $fails
fi

echo "remote-agent-kit · ck-replica (local → ${INV_USER}@${HOST})"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
# Local project checkouts live beside each other; override when yours differ.
DEV_ROOT="${CK_DEV_ROOT:-$HOME/Developer}"

echo "→ snapshotting live main db (online backup, server keeps running)"
sqlite3 "$SRC" ".backup '$STAGE/controlkeel.db'"
cp "$HOME/controlkeel/project.json" "$STAGE/" 2>/dev/null || echo '{"note":"no project.json"}' > "$STAGE/project.json"
$SSH 'mkdir -p ~/controlkeel' 
rsync -az "$STAGE/controlkeel.db" "$STAGE/project.json" "${INV_USER}@${HOST}:~/controlkeel/"
echo "  ✓ main store transferred"

for p in $PROJECTS; do
  if [[ -f ""$DEV_ROOT/$p/controlkeel/controlkeel.db"" ]]; then
    mkdir -p "$STAGE/$p"
    sqlite3 ""$DEV_ROOT/$p/controlkeel/controlkeel.db"" ".backup '$STAGE/$p/controlkeel.db'"
    # bin/ (machine shims), shm/locks (transient) stay behind; db + the rest go.
    rsync -az --exclude 'bin/' --exclude '*-shm' --exclude '*.lock' \
      "$STAGE/$p/controlkeel.db" "${INV_USER}@${HOST}:~/work/$p/controlkeel.db.tmp" \
    && $SSH "mkdir -p ~/work/$p/controlkeel && mv ~/work/$p/controlkeel.db.tmp ~/work/$p/controlkeel/controlkeel.db" \
    && rsync -az --exclude 'bin/' --exclude '*-shm' --exclude '*-wal' --exclude '*.lock' --exclude 'controlkeel.db*' \
      "$DEV_ROOT/$p/controlkeel/" "${INV_USER}@${HOST}:~/work/$p/controlkeel/"
    echo "  ✓ $p project state transferred"
  fi
done

echo "→ remapping Mac paths to box paths in project bindings"
scp -q "$RK_LIB_DIR/ck-remap.py" "${INV_USER}@${HOST}:/tmp/ck-remap.py"
$SSH "python3 /tmp/ck-remap.py ${INV_USER} ${DEV_ROOT}; rm -f /tmp/ck-remap.py"

echo "→ verifying"
fails=0
$SSH "sqlite3 \$HOME/controlkeel/controlkeel.db 'PRAGMA integrity_check;'" 2>/dev/null | grep -q "^ok$" \
  && echo "  ✓ main db integrity ok" || { echo "  ✗ main db integrity"; fails=1; }
verify_one "main store" || fails=1
[[ "$fails" -eq 0 ]] && echo "REPLICA OK — use it on the box via: controlkeel --project-root ~/controlkeel status"
exit $fails
