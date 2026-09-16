#!/usr/bin/env bash
# start.sh — the "easy button" for remote-agent-kit.
#
# One command that takes you from zero to a working agent box: it checks tools,
# asks for API keys (with validation, never echoed), writes the three config
# files, reviews the Terraform plan with you, provisions, configures, verifies,
# and prints the pairing steps. Re-running resumes where you stopped —
# anything already done is kept (pass --reset to start over).
#
#   ./scripts/start.sh           # interactive, the normal path
#   ./scripts/start.sh --yes     # still asks for missing secrets, skips confirms
#   ./scripts/start.sh --reset   # delete generated config and start over
#
# Cost to try: a few cents (Hetzner bills hourly; `make teardown` destroys).
set -euo pipefail
cd "$(dirname "$0")/.."

YES=0
for a in "$@"; do
  case "$a" in
    --yes) YES=1 ;;
    --reset)
      read -r -p "Delete .env, terraform.tfvars and hosts.yml and start over? [y/N] " c
      [[ "$c" =~ ^[Yy]$ ]] && rm -f .env terraform/terraform.tfvars ansible/inventory/hosts.yml && echo "Reset. Run ./scripts/start.sh again."
      exit 0 ;;
    -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown flag: $a (try --help)"; exit 2 ;;
  esac
done

say()  { printf '\n\033[1m%s\033[0m\n' "$1"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }

confirm() { # confirm "prompt" — true on yes (auto-yes with --yes)
  [[ "$YES" == "1" ]] && return 0
  local reply=""; read -r -p "$1 [y/N] " reply || true
  [[ "$reply" =~ ^[Yy]$ ]]
}

# ask VAR "prompt" "default" [silent:0/1] [validate_fn] — keeps existing value on empty input
ask() {
  local var="$1" prompt="$2" def="$3" silent="${4:-0}" vfn="${5:-}" cur val
  cur="$(grep -m1 -E "^${var}=" .env 2>/dev/null | cut -d= -f2- || true)"
  if [[ -n "$cur" && "$cur" != CHANGEME* ]]; then
    ok "$var already set (kept)"
    return 0
  fi
  while true; do
    if [[ "$silent" == "1" ]]; then
      if [[ -n "$def" && "$def" != CHANGEME* ]]; then
        printf '%s [%s]: ' "$prompt" "(kept hidden)"; IFS= read -rs val || val=""; echo
        [[ -z "$val" ]] && val="$def"
      else
        printf '%s: ' "$prompt"; IFS= read -rs val || val=""; echo
      fi
    else
      if [[ -n "$def" ]]; then
        printf '%s [%s]: ' "$prompt" "$def"; IFS= read -r val || val=""
        [[ -z "$val" ]] && val="$def"
      else
        printf '%s: ' "$prompt"; IFS= read -r val || val=""
      fi
    fi
    # trim spaces
    val="$(printf '%s' "$val" | tr -d '[:space:]')"
    if [[ -z "$val" && ! -t 0 ]]; then echo "stdin closed with no usable input — aborting (run interactively)"; exit 1; fi
    if [[ -z "$val" ]]; then warn "empty — try again"; continue; fi
    if [[ -n "$vfn" ]] && ! "$vfn" "$val"; then continue; fi
    break
  done
  touch .env; chmod 600 .env
  grep -v -E "^${var}=" .env > .env.tmp || true; mv .env.tmp .env
  printf '%s=%s\n' "$var" "$val" >> .env
  ok "$var saved to .env (mode 600)"
}

v_hcloud() { [[ "$1" =~ ^[A-Za-z0-9]{32,}$ ]] || { bad "doesn't look like a Hetzner token (64 hex chars from console.hetzner.cloud → Security → API Tokens)"; return 1; }; }
v_tailscale() { [[ "$1" == tskey-auth-* && ${#1} -gt 20 ]] || { bad "must start with tskey-auth- (login.tailscale.com/admin/authkeys → reusable, 90 days)"; return 1; }; }
v_telegram() { [[ "$1" =~ ^[0-9]+:[A-Za-z0-9_-]{20,}$ ]] || { bad "must look like 123456:ABC-DEF... (from @BotFather /newbot)"; return 1; }; }
v_tgusers() { [[ "$1" =~ ^[0-9,]+$ ]] || { bad "numeric Telegram user ids only, comma-separated (from @userinfobot — the number, not @handle)"; return 1; }; }

echo "remote-agent-kit · start — zero to agent box in ~15 minutes"
echo "You need 3 free accounts first: Hetzner, Tailscale, Telegram (docs/prereqs.md)."
echo "Trying costs cents (hourly billing); 'make teardown' destroys everything."

# ── 1. tools ──────────────────────────────────────────────
say "1/7 · Tools"
need_install=0
for t in terraform ssh curl; do
  command -v "$t" >/dev/null 2>&1 && ok "$t" || { bad "$t missing"; need_install=1; }
done
if ! command -v ansible-playbook >/dev/null 2>&1; then
  bad "ansible-playbook missing"; need_install=1
else
  ok "ansible-playbook"
fi
if [[ "$need_install" == "1" ]]; then
  if [[ "$(uname -s)" == "Darwin" ]] && command -v brew >/dev/null 2>&1; then
    if confirm "Install missing tools with brew now?"; then
      brew install terraform ansible 2>&1 | tail -1
    else echo "Install manually (docs/prereqs.md) and re-run."; exit 1; fi
  else
    echo "Install: terraform >= 1.5, ansible >= 2.15 (docs/prereqs.md), then re-run."
    exit 1
  fi
fi
if [[ ! -f ~/.ssh/id_ed25519.pub && ! -f ~/.ssh/id_rsa.pub ]]; then
  if confirm "No SSH key found — generate ed25519 now?"; then
    ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519
  else echo "Create one (ssh-keygen -t ed25519) and re-run."; exit 1; fi
fi
PUBKEY_FILE="$(ls ~/.ssh/id_ed25519.pub 2>/dev/null || ls ~/.ssh/id_rsa.pub 2>/dev/null | head -1)"
ok "SSH key: $PUBKEY_FILE"

# ── 2. secrets (never echoed) ─────────────────────────────
say "2/7 · API keys (typed blind, validated, stored mode 600 — never printed, never committed)"
touch .env; chmod 600 .env
ask HCLOUD_TOKEN "Hetzner Cloud API token" "" 1 v_hcloud
ask TAILSCALE_AUTHKEY "Tailscale auth key" "" 1 v_tailscale
if confirm "Set up the Telegram bot? (optional — Enter n to skip, the phone app is enough)"; then
  ask TELEGRAM_BOT_TOKEN "Telegram bot token (@BotFather)" "" 1 v_telegram
  ask TELEGRAM_ALLOWED_USERS "Your numeric Telegram user id (@userinfobot)" "" 0 v_tgusers
else
  grep -v -E '^(TELEGRAM_BOT_TOKEN|TELEGRAM_ALLOWED_USERS)=' .env > .env.tmp || true; mv .env.tmp .env
  ok "Telegram skipped (re-run with --tags telegram anytime)"
fi
# shellcheck disable=SC1091
set -a; . ./.env; set +a

# ── 3. model ──────────────────────────────────────────────
say "3/7 · Model (who does the thinking — billed by them, not by us)"
if ! grep -q -E '^(OPENROUTER_API_KEY|ANTHROPIC_API_KEY)=.+' .env 2>/dev/null; then
  echo "  1) Nous Portal — OAuth in browser, free tier, nothing stored here (recommended)"
  echo "  2) OpenRouter — one key, many models (free models work; \$10 top-up lifts limits)"
  echo "  3) Anthropic — direct, pay-per-token"
  printf 'Choose [1]: '; IFS= read -r choice || choice=""; [[ -z "$choice" ]] && choice=1
  case "$choice" in
    2) ask OPENROUTER_API_KEY "OpenRouter key (sk-or-v1-...)" "" 1 ;;
    3) ask ANTHROPIC_API_KEY "Anthropic key (sk-ant-...)" "" 1 ;;
    *) ok "Nous Portal — you will approve OAuth over SSH during deploy" ;;
  esac
else
  ok "model key already set (kept)"
fi

# ── 4. server shape ───────────────────────────────────────
say "4/7 · Server (defaults are the tested sweet spot)"
TFV=terraform/terraform.tfvars
[[ -f "$TFV" ]] || cp terraform/terraform.tfvars.example "$TFV"
chmod 600 "$TFV"
set_var() { # set_var FILE KEY VALUE — regex tolerates fmt's = alignment
  grep -v -E "^$2[[:space:]]*=" "$1" > "$1.tmp" || true; mv "$1.tmp" "$1"
  printf '%s = "%s"\n' "$2" "$3" >> "$1"
}
cur_val() { grep -m1 -E "^$2 =" "$1" 2>/dev/null | sed -E 's/^.*= *"([^"]*)".*/\1/' || true; }
STYPE="$(cur_val "$TFV" server_type)"; [[ -n "$STYPE" ]] || STYPE=cx33
printf 'Size: 1) cx33 — 4 vCPU/8GB/80GB ~€9.99 (recommended, headroom)  2) cx23 — 2/4/40 ~€6.49 (tight) [%s]: ' "$STYPE"
IFS= read -r sc || sc=""; [[ -z "$sc" ]] && sc="$STYPE"; [[ "$sc" == "2" ]] && sc=cx23; [[ "$sc" == "1" ]] && sc=cx33
set_var "$TFV" server_type "$sc"
LOC="$(cur_val "$TFV" location)"; [[ -n "$LOC" ]] || LOC=fsn1
printf 'Region: fsn1/nbg1/hel1 (EU) or ash/hil (US) [%s]: ' "$LOC"
IFS= read -r lc || lc=""; [[ -z "$lc" ]] && lc="$LOC"; set_var "$TFV" location "$lc"
SNAME="$(cur_val "$TFV" server_name)"; [[ -n "$SNAME" ]] || SNAME=hermes
printf 'Server name [%s]: ' "$SNAME"; IFS= read -r sn || sn=""; [[ -z "$sn" ]] && sn="$SNAME"; set_var "$TFV" server_name "$sn"
set_var "$TFV" hcloud_token "$HCLOUD_TOKEN" # real token here (file is 600 + gitignored); provider has no env fallback when the var is set
set_var "$TFV" ssh_public_key "$(cat "$PUBKEY_FILE")"
set_var "$TFV" admin_username "hermes"
MYIP="$(curl -s -m 8 https://ifconfig.me 2>/dev/null || true)"
if [[ -n "$MYIP" ]]; then
  printf 'Your public IP is %s — allow bootstrap SSH from it? [Y/n]: ' "$MYIP"
  IFS= read -r yn || yn="y"; [[ -z "$yn" ]] && yn=y
  [[ "$yn" =~ ^[Yy]$ ]] && set_var "$TFV" my_ip "${MYIP}/32" || set_var "$TFV" my_ip ""
else
  warn "could not detect public IP — edge SSH stays closed (Hetzner console fallback)"
  set_var "$TFV" my_ip ""
fi
ok "terraform.tfvars written (mode 600)"
terraform -chdir=terraform fmt terraform.tfvars >/dev/null 2>&1 || true

# ── 5. init + preflight + plan ────────────────────────────
say "5/7 · Init, safety checks, plan review"
[[ -f ansible/inventory/hosts.yml ]] || cp ansible/inventory/hosts.yml.example ansible/inventory/hosts.yml
make init 2>&1 | tail -2
./scripts/preflight.sh || { bad "preflight failed — fix above and re-run ./scripts/start.sh (it resumes)"; exit 1; }
echo; echo "Terraform plan (what will be created — review it):"
make plan
confirm "Create this infrastructure?" || { echo "Aborted before spending anything."; exit 0; }

# ── 6. provision ──────────────────────────────────────────
say "6/7 · Provision (~60s) + configure (~10 min)"
mkdir -p logs
set +e
make apply 2>&1 | tee logs/start-apply.log | tail -3
APPLY_RC=${PIPESTATUS[0]}
set -e
if [[ "$APPLY_RC" != "0" ]]; then
  bad "apply failed (exit $APPLY_RC) — last lines above, full log: logs/start-apply.log"
  echo "Nothing was configured; fix the error and re-run ./scripts/start.sh (it resumes)."
  exit 1
fi
IP="$(terraform -chdir=terraform output -raw server_ipv4)"
ok "server up at $IP — writing ansible inventory"
cp ansible/inventory/hosts.yml.example ansible/inventory/hosts.yml
python3 - "$IP" <<'PYEOF'
import io, sys
ip = sys.argv[1]
p = 'ansible/inventory/hosts.yml'
s = io.open(p, encoding='utf-8').read()
s = s.replace('CHANGEME # e.g. 46.250.00.00, later 100.64.x.y', ip)
io.open(p, 'w', encoding='utf-8').write(s)
PYEOF
echo "Waiting for first boot + SSH (cloud-init takes a few minutes)…"
for _ in $(seq 1 30); do
  ssh -o BatchMode=yes -o ConnectTimeout=6 -o StrictHostKeyChecking=accept-new "hermes@${IP}" true 2>/dev/null && break
  sleep 10
done
ssh -o BatchMode=yes -o ConnectTimeout=6 "hermes@${IP}" true || { bad "SSH never came up — Hetzner console → web console, or re-run (it resumes)"; exit 1; }
ok "SSH answers"
export HCLOUD_TOKEN TAILSCALE_AUTHKEY
set +e
make deploy 2>&1 | tee logs/start-deploy.log | tail -5
DEPLOY_RC=${PIPESTATUS[0]}
set -e
if [[ "$DEPLOY_RC" != "0" ]]; then
  bad "deploy failed (exit $DEPLOY_RC) — full log: logs/start-deploy.log"
  echo "Re-run ./scripts/start.sh (it resumes); Ansible roles are idempotent."
  exit 1
fi

# ── 7. verify + handoff ───────────────────────────────────
say "7/7 · Verify + handoff"
make doctor || warn "doctor found issues — see above (often first-boot timing; re-run make doctor)"
echo
echo "Done. Two ways to reach your agent:"
echo "  Phone app : make pair   → scan the QR (Tailscale app must be on the phone)"
echo "  Telegram  : message your bot 'hello' (allow-listed to you only)"
echo "Daily: make ssh · make logs · make backup. Destroy: make teardown."
