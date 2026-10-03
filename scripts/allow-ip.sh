#!/usr/bin/env bash
# allow-ip.sh — home IP changed? Re-pin the edge firewall's SSH rule to this
# machine's current public IPv4. Symptom: `ssh <box>` on the public IP times
# out while ping still answers (ICMP is open to all; port 22 is pinned).
# Edits only my_ip in terraform.tfvars and applies only the firewall —
# a targeted apply can't drag in unrelated pending changes (e.g. a resize).
# Terraform shows the diff and asks first; extra args pass through to apply.
# Usage: ./scripts/allow-ip.sh   (or: make allow-ip)
set -euo pipefail

TFV=terraform/terraform.tfvars
[[ -f "$TFV" ]] || { echo "No $TFV. Run: make start"; exit 2; }

# -4: the rule is an IPv4 /32; an IPv6 answer would pin the wrong address.
IP="$(curl -4 -s -m 8 https://ifconfig.me 2>/dev/null || true)"
[[ "$IP" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || { echo "Could not detect your public IPv4 (got: '${IP}')."; exit 1; }

CUR="$(grep -m1 -E '^my_ip[[:space:]]*=' "$TFV" | sed -E 's/^.*= *"([^"]*)".*/\1/' || true)"
if [[ "$CUR" == "$IP/32" ]]; then
  echo "my_ip already $IP/32 — applying in case the live rule drifted."
else
  echo "Edge SSH: ${CUR:-<closed>} → $IP/32"
  if grep -q -E '^my_ip[[:space:]]*=' "$TFV"; then
    # In-place edit keeps the file's 600 mode and fmt alignment.
    sed -i.bak -E "s|^(my_ip[[:space:]]*=[[:space:]]*).*|\1\"$IP/32\"|" "$TFV"
    rm -f "$TFV.bak"
  else
    printf 'my_ip = "%s"\n' "$IP/32" >> "$TFV"
  fi
fi

terraform -chdir=terraform apply -target=hcloud_firewall.agent "$@"
echo "Done. Public SSH answers $IP again (the tailnet path never depended on it)."
