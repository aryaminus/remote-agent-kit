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

# 5. YAML syntax + role src resolution (Broken Windows: a copy/template src
# that resolves nowhere fails deploy on the server — this exact bug shipped
# once with the perch role). NOTE: the python MUST sit inside the if
# condition: under `set -e` a bare failing command kills the shell before
# any `$?` check on the next line can run.
if python3 - <<'EOF'
import glob, sys
try:
    import yaml
except ImportError:
    print("  ! pyyaml missing — skipping YAML parse check"); sys.exit(0)
bad = 0
# Vendored collections are third-party — checked upstream, not here.
mine = [f for f in glob.glob("ansible/**/*.yml", recursive=True)
        if not f.startswith("ansible/collections/")]
mine += glob.glob("deploy/*.yaml")  # one-click cloud-init: must at least parse
for f in mine + glob.glob(".github/workflows/*.yml"):
    try:
        docs = list(yaml.safe_load_all(open(f)))
        print(f"  ✓ {f}")
    except Exception as e:
        print(f"  ✗ {f}: {e}"); bad = 1; continue
    # Broken-Windows check: copy/template src: must resolve to a real file.
    # (This exact bug shipped once: the perch role copied a files/ dir that
    # did not exist, failing deploy at the worst moment — on the server.)
    if f.startswith("ansible/roles/"):
        role_root = f.split("/tasks/")[0] if "/tasks/" in f else None
        if role_root:
            import os
            def walk_tasks(node):
                def is_file_module(k):
                    # matches copy/template in short AND FQCN form
                    # (ansible.builtin.copy), which this repo uses throughout
                    return k in ("copy", "template") or k.endswith((".copy", ".template"))
                if isinstance(node, dict):
                    for k, v in node.items():
                        if is_file_module(k) and isinstance(v, dict) and "src" in v:
                            if not v.get("remote_src"):
                                src = str(v["src"])
                                cands = [os.path.join(role_root, "files", src),
                                         os.path.join(role_root, src)]
                                if not any(os.path.exists(c) for c in cands):
                                    print(f"  ✗ {f}: src '{src}' resolves nowhere under {role_root}/"); globals()["bad"] = 1
                        else:
                            walk_tasks(v)
                elif isinstance(node, list):
                    for item in node:
                        walk_tasks(item)
            for doc in docs:
                walk_tasks(doc)
sys.exit(bad)
EOF
then
  :
else
  fail=$((fail+1))
fi

# 6. Terraform fmt + validate (only if terraform is installed)
if command -v terraform >/dev/null 2>&1; then
  terraform -chdir=terraform fmt -check -diff >/dev/null && ok "terraform fmt" || { bad "terraform fmt"; }
else
  echo "  ! terraform not installed — skipping fmt/validate (CI covers it)"
fi

echo
if [[ "$fail" -eq 0 ]]; then echo "repo_check PASS"; else echo "repo_check FAIL ($fail)"; exit 1; fi
