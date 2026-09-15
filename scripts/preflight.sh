#!/usr/bin/env bash
# preflight.sh — Murphy's Law gate: fail on YOUR laptop, for free, BEFORE
# `make apply` spends money or `make deploy` touches a server.
# Checks: tools installed, secret files exist + filled (no CHANGEME left),
# SSH key present, Terraform/Ansible parse. Read-only, never connects.
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; fail=$((fail+1)); }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }

echo "remote-agent-kit · preflight (nothing here spends money or touches servers)"

# 1. Tools
for t in terraform ansible-playbook ssh curl; do
  command -v "$t" >/dev/null 2>&1 && ok "$t installed" || bad "$t missing (see docs/prereqs.md)"
done

# 2. Secret files exist…
for f in .env terraform/terraform.tfvars ansible/inventory/hosts.yml; do
  [[ -f "$f" ]] && ok "$f exists" || bad "$f missing — copy the .example and fill it in"
done

# 3. …and contain no CHANGEME placeholders (the #1 failed-deploy cause)
if [[ -f .env && -f terraform/terraform.tfvars && -f ansible/inventory/hosts.yml ]]; then
  if grep -q CHANGEME .env terraform/terraform.tfvars ansible/inventory/hosts.yml 2>/dev/null; then
    bad "CHANGEME placeholders remain:"; grep -n CHANGEME .env terraform/terraform.tfvars ansible/inventory/hosts.yml | head -5
  else
    ok "no CHANGEME placeholders left"
  fi
  # 4. SSH private key referenced by inventory actually exists
  KEY="$(grep -E 'ansible_ssh_private_key_file:' ansible/inventory/hosts.yml | awk '{print $2}' | head -1)"
  KEY="${KEY/#\~/$HOME}"
  if [[ -n "$KEY" && -f "$KEY" ]]; then ok "SSH key $KEY exists";
  elif [[ -f ~/.ssh/id_ed25519 ]]; then ok "SSH key ~/.ssh/id_ed25519 exists (inventory key unset, using default)";
  else bad "no SSH key found (ssh-keygen -t ed25519)"; fi
fi

# 5. Static gates (same as CI)
./scripts/repo_check.sh >/dev/null 2>&1 && ok "repo_check passes" || bad "repo_check fails — run ./scripts/repo_check.sh"
terraform -chdir=terraform validate >/dev/null 2>&1 && ok "terraform validates" || warn "terraform validate failed (run make init first?)"

echo
if [[ "$fail" -eq 0 ]]; then echo "preflight PASS — safe to run: make plan"; else echo "preflight FAIL ($fail) — fix above, then re-run"; exit 1; fi
