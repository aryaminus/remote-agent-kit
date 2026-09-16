#!/usr/bin/env bash
# finish.sh — runs ON the server as the hermes user. Completes the one-click
# path (deploy/hetzner-cloud-init.yaml): joins Tailscale, wires the model,
# optionally sets up Telegram, starts the gateway + dashboard, and prints the
# phone-pairing steps. Re-running resumes (completed steps are detected).
#
#   bash ~/finish.sh
set -euo pipefail

BIN="$HOME/.local/bin/hermes"
ENV="$HOME/.hermes/.env"
API_PORT=8642
DASH_PORT=9119

say()  { printf '\n\033[1m%s\033[0m\n' "$1"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }
confirm() {
  local reply=""; read -r -p "$1 [y/N] " reply || true
  [[ "$reply" =~ ^[Yy]$ ]]
}

[[ -x "$BIN" ]] || { echo "Hermes not installed yet — cloud-init still working? Wait for CPU to idle, then re-run."; exit 1; }
touch "$ENV"; chmod 600 "$ENV"
putenv() { # putenv KEY VALUE (no spaces around =)
  grep -v -E "^$1=" "$ENV" > "$ENV.tmp" || true; mv "$ENV.tmp" "$ENV"
  printf '%s=%s\n' "$1" "$2" >> "$ENV"
}

echo "remote-agent-kit · finish — completing this box (re-runnable)"

# ── 1. Tailscale ──────────────────────────────────────────
say "1/5 · Tailscale (private network — no public ports afterwards)"
if tailscale status >/dev/null 2>&1; then
  ok "already on tailnet ($(tailscale ip -4 2>/dev/null | head -1))"
else
  printf 'Tailscale auth key (login.tailscale.com/admin/authkeys, tskey-auth-...): '
  IFS= read -rs TSKEY || TSKEY=""; echo
  [[ "$TSKEY" == tskey-auth-* ]] || { echo "That doesn't look like an auth key. Re-run when you have one."; exit 1; }
  sudo tailscale up --authkey="$TSKEY" --hostname=hermes
  unset TSKEY
  TIP="$(tailscale ip -4 | head -1)"
  ok "joined tailnet ($TIP)"
  # Lock SSH + UFW to the tailnet (keep this SSH session open till verified).
  sudo sed -i -E '/^ListenAddress/d' /etc/ssh/sshd_config
  printf 'ListenAddress %s\nListenAddress 127.0.0.1\n' "$TIP" | sudo tee -a /etc/ssh/sshd_config >/dev/null
  sudo systemctl restart ssh
  sudo ufw allow from 100.64.0.0/10 to any port 22 proto tcp
  sudo ufw allow from 100.64.0.0/10 to any port "$API_PORT" proto tcp
  sudo ufw allow from 100.64.0.0/10 to any port "$DASH_PORT" proto tcp
  ok "SSH/API/dashboard answer on the tailnet only"
fi

# ── 1b. HTTPS for iPhone (Tailscale Serve) ────────────────
# iOS App Transport Security refuses cleartext HTTP to 100.x, so the phone
# app can ONLY reach https://<host>.<tail>.ts.net. Mirrors the Ansible role.
if tailscale serve status 2>/dev/null | grep -q "https://"; then
  ok "HTTPS serve already on: $(tailscale serve status | head -1)"
else
  sudo tailscale set --operator="$USER" 2>/dev/null || true
  if tailscale serve --bg --https=443 "http://127.0.0.1:$API_PORT" 2>&1 | grep -q "tailnet"; then
    sudo ufw allow from 100.64.0.0/10 to any port 443 proto tcp
    HTTPS_NAME="$(tailscale status --json 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("Self",{}).get("DNSName","").rstrip("."))' 2>/dev/null || true)"
    ok "HTTPS serve on${HTTPS_NAME:+: https://$HTTPS_NAME}"
    echo "  ⚠️  If this FAILED with 'Serve is not enabled': open the printed URL"
    echo "      once in your Tailscale admin (DNS → HTTPS certificates), then re-run."
  else
    warn "tailscale serve failed — see message above (likely the one-time tailnet approval)"
  fi
fi

# ── 2. Model ──────────────────────────────────────────────
say "2/5 · Model (who thinks — billed by them, free options exist)"
if "$BIN" doctor >/dev/null 2>&1; then
  ok "model already configured"
else
  echo "  1) Nous Portal — OAuth in your browser now (free tier, recommended)"
  echo "  2) I have an OpenRouter/Anthropic key to paste"
  printf 'Choose [1]: '; IFS= read -r mc || mc=""; [[ -z "$mc" ]] && mc=1
  if [[ "$mc" == "1" ]]; then
    "$BIN" setup --portal
  else
    printf 'Paste model key: '; IFS= read -rs MKEY || MKEY=""; echo
    [[ "$MKEY" == sk-or-v1-* ]] && putenv OPENROUTER_API_KEY "$MKEY"
    [[ "$MKEY" == sk-ant-* ]] && putenv ANTHROPIC_API_KEY "$MKEY"
    unset MKEY
  fi
  "$BIN" doctor || { echo "doctor unhappy — fix the model config, then re-run."; exit 1; }
fi

# ── 3. API + dashboard (Perch phone client) ───────────────
say "3/5 · API + dashboard (what your phone talks to)"
if ! grep -q -E '^API_SERVER_KEY=.+' "$ENV" 2>/dev/null; then
  putenv API_SERVER_KEY "hp_$(head -c 64 /dev/urandom | base64 | tr -d '/+=\n' | cut -c1-43)"
fi
putenv API_SERVER_ENABLED true
putenv API_SERVER_HOST 0.0.0.0
putenv API_SERVER_PORT "$API_PORT"
if ! grep -q -E '^HERMES_DASHBOARD_SESSION_TOKEN=.+' "$ENV" 2>/dev/null; then
  putenv HERMES_DASHBOARD_SESSION_TOKEN "$(head -c 64 /dev/urandom | base64 | tr -d '/+=\n' | cut -c1-43)"
fi
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/hermes-dashboard.service <<EOF
[Unit]
Description=Hermes dashboard + remote backend (tailnet only)
After=network-online.target tailscaled.service hermes-gateway.service
Wants=network-online.target
[Service]
ExecStart=$BIN dashboard --host 0.0.0.0 --port $DASH_PORT --no-open
Restart=on-failure
RestartSec=5
[Install]
WantedBy=default.target
EOF
systemctl --user daemon-reload
systemctl --user enable --now hermes-dashboard
ok "dashboard on :$DASH_PORT (tailnet only, token pinned)"

# ── 4. Telegram (OPTIONAL — skip if the phone app is enough) ──
say "4/5 · Telegram bot (optional — Enter to skip)"
if systemctl --user is-active hermes-gateway >/dev/null 2>&1; then
  ok "gateway already running"
else
  printf 'Bot token from @BotFather (empty = skip Telegram): '
  IFS= read -rs BTOK || BTOK=""; echo
  if [[ -z "$BTOK" ]]; then
    warn "Telegram skipped — start the gateway anyway so the API works:"
    printf 'n\nY\n' | "$BIN" gateway install 2>/dev/null || true
  else
    printf 'Your numeric Telegram id (@userinfobot, not @handle): '
    IFS= read -r TUID || TUID=""
    putenv TELEGRAM_BOT_TOKEN "$BTOK"
    putenv TELEGRAM_ALLOWED_USERS "$(printf '%s' "$TUID" | tr -d ' ')"
    unset BTOK
    "$BIN" gateway setup --platform telegram 2>/dev/null || true
    printf 'n\nY\n' | "$BIN" gateway install 2>/dev/null || true
  fi
  sudo loginctl enable-linger "$USER" 2>/dev/null || true
  systemctl --user enable --now hermes-gateway
  for _ in $(seq 1 30); do
    curl -s -m 3 -o /dev/null "http://127.0.0.1:$API_PORT/health" && break
    sleep 5
  done
  ok "gateway running (survives reboot via linger)"
fi

# ── 5. handoff ────────────────────────────────────────────
say "5/5 · Done — reach your agent"
echo "  Telegram (if set up): message your bot 'hello'"
echo "  Phone app (Perch): Tailscale on the phone, then download-then-run:"
echo "    curl -fsSL https://aryaminus.github.io/perch-site/pair.sh -o pair.sh"
echo "    bash pair.sh --tailscale"
echo "  Then, still on this box, harden approvals + notifications:"
echo "    curl -fsSL https://aryaminus.github.io/perch-site/enable-approvals.sh -o enable-approvals.sh && bash enable-approvals.sh"
echo "    curl -fsSL https://aryaminus.github.io/perch-site/ntfy-setup.sh -o ntfy-setup.sh && bash ntfy-setup.sh"
echo "  Logs: journalctl --user -u hermes-gateway -f"
