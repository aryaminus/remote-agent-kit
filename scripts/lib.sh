#!/usr/bin/env bash
# lib.sh — shared helpers for remote-agent-kit scripts. No side effects.
# rk_agent_host: box tailnet hostname. Precedence: local hosts.yml
# per-host override > group_vars default > agentbox.
rk_agent_host() {
  # Precedence: per-host override (hosts.yml) wins over the group default.
  # grep prints hosts.yml matches first, so take the FIRST value match.
  local h
  h="$(grep -h 'agent_hostname:' ansible/inventory/hosts.yml ansible/inventory/group_vars/all.yml 2>/dev/null | grep -v '^[[:space:]]*#' | head -1 | awk '{print $2}' || true)"
  printf '%s' "${h:-agentbox}"
}
# rk_tscli: argv of a working tailscale CLI (App-bundled first — the store
# app ships no PATH binary), or empty when none is up.
rk_tscli() {
  if /Applications/Tailscale.app/Contents/MacOS/Tailscale status >/dev/null 2>&1; then
    printf '%s' "/Applications/Tailscale.app/Contents/MacOS/Tailscale"; return
  fi
  command -v tailscale >/dev/null 2>&1 && printf '%s' "tailscale"
}
# rk_https_url: https://<host>.<tail>.ts.net or empty. Needs: tailnet up.
rk_https_url() {
  local cli host suf
  cli="$(rk_tscli)" || return 0
  [[ -z "$cli" ]] && return 0
  host="$(rk_agent_host)"
  suf="$("$cli" status --json 2>/dev/null | python3 -c 'import json,sys
try:
    print(json.load(sys.stdin).get("MagicDNSSuffix", ""))
except Exception:
    print("")' || true)"
  [[ -n "$host" && -n "$suf" ]] && printf 'https://%s.%s' "$host" "$suf"
}
