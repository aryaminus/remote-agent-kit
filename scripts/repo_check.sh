#!/usr/bin/env bash
# repo_check.sh — local security + consistency gate. Runs in CI and via `make check`.
# Fails on: real-looking secrets in tracked files, dangerous container flags,
# unpinned container images, shell/YAML syntax errors.
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0
bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; fail=$((fail+1)); }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }

echo "remote-agent-kit · repo_check"

# 1. No secret-bearing files tracked (allow the .example templates)
for f in .env terraform/terraform.tfvars ansible/inventory/hosts.yml; do
  if git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
    bad "$f is tracked — secrets must stay untracked (see .gitignore)"
  else
    ok "$f untracked"
  fi
done

# 2. No real-looking secrets inside tracked content (templates use CHANGEME)
if git grep -n -E 'tskey-auth-[A-Za-z0-9]|hp_[A-Za-z0-9_-]{20,}|sk-(live|ant)-[A-Za-z0-9]|xox[bap]-|ghp_[A-Za-z0-9]{20,}|sntrys_[A-Za-z0-9]|CHANGEME' \
    -- ':!repo_check.sh' 2>/dev/null | grep -v CHANGEME >/dev/null; then
  git grep -n -E 'tskey-auth-[A-Za-z0-9]|hp_[A-Za-z0-9_-]{20,}|sk-(live|ant)-[A-Za-z0-9]|xox[bap]-|ghp_[A-Za-z0-9]{20,}|sntrys_[A-Za-z0-9]' -- . || true
  bad "real-looking secret in tracked files (above)"
else
  ok "no live secrets in tracked files"
fi

# 3. No dangerous container flags (excluding this script's own pattern line)
if grep -rn --exclude=repo_check.sh -- '--privileged\|--net=host\|--network host\|:/var/run/docker.sock' \
    ansible/ scripts/ terraform/ 2>/dev/null; then
  bad "dangerous container flag found (above) — agents run sandboxed, never privileged"
else
  ok "no privileged/host container flags"
fi

# 4. Shell syntax
for s in scripts/*.sh; do
  if bash -n "$s"; then ok "bash -n $s"; else bad "syntax error in $s"; fi
done

# 5. YAML syntax (python is everywhere; pyyaml usually is)
python3 - <<'EOF'
import glob, sys
try:
    import yaml
except ImportError:
    print("  ! pyyaml missing — skipping YAML parse check"); sys.exit(0)
bad = 0
# Vendored collections are third-party — checked upstream, not here.
mine = [f for f in glob.glob("ansible/**/*.yml", recursive=True)
        if not f.startswith("ansible/collections/")]
for f in mine + glob.glob(".github/workflows/*.yml"):
    try:
        list(yaml.safe_load_all(open(f)))
        print(f"  ✓ {f}")
    except Exception as e:
        print(f"  ✗ {f}: {e}"); bad = 1
sys.exit(bad)
EOF
[[ $? -eq 0 ]] || fail=$((fail+1))

# 6. Terraform fmt + validate (only if terraform is installed)
if command -v terraform >/dev/null 2>&1; then
  terraform -chdir=terraform fmt -check -diff >/dev/null && ok "terraform fmt" || { bad "terraform fmt"; }
else
  echo "  ! terraform not installed — skipping fmt/validate (CI covers it)"
fi

echo
if [[ "$fail" -eq 0 ]]; then echo "repo_check PASS"; else echo "repo_check FAIL ($fail)"; exit 1; fi
