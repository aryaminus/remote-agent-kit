# Security policy

## Reporting

Found something exploitable or leaking? Open a private security advisory:
GitHub → Security → "Report a vulnerability" on this repo. Please do not
open a public issue for it. Reports are read within a few days.

## Trust model — read before you run this kit

This repo configures **your** server with **your** credentials. Things worth
knowing before you trust it:

* **Everything it runs is in this repo.** Terraform, Ansible roles,
  cloud-init, and every shell script are readable here — including the two
  scripts fetched at runtime (`finish.sh` from this repo's own `main`, and
  Perch's public `pair.sh`/hardening scripts from the public
  [perch-site](https://github.com/aryaminus/perch-site)). Nothing is piped
  into a shell blind; download-then-run is the documented form.
* **Fetching `main` is a trust decision.** `finish.sh` and the cloud-init
  `#include` track this repository's default branch. If you want immutability,
  pin them to a release tag/commit SHA instead.
* **Secrets never belong in git.** `.env`, `terraform/terraform.tfvars`,
  `ansible/inventory/hosts.yml`, `logs/`, `controlkeel/`, `backups/` are
  gitignored; `scripts/repo_check.sh` fails CI on live-secret patterns and on
  Ansible `copy`/`template` sources that resolve nowhere.
* **The blast radius of each secret** is documented in
  `docs/privacy-considerations.md`: the gateway API key is a shell on the box,
  the pairing QR *is* that key, and the dashboard token reads files.

## Auditing a clone (do this to any repo like this one)

```sh
# secrets in ANY commit, not just the working tree:
git rev-list --all | while read c; do
  git grep -lE 'tskey-auth-[A-Za-z0-9]{10,}|hp_[A-Za-z0-9_-]{30,}|sk-ant-|sk-or-v1-|[0-9]{9,10}:AA[A-Za-z0-9_-]{30,}' $c --
done | sort -u

# anything sensitive ever committed to paths that should stay local:
git log --all --oneline -- .env '*.tfvars' ansible/inventory/hosts.yml logs/
```

Both return empty on this repository as of this writing.

## Hardening this kit applies by default

Edge firewall closed except operator SSH → host UFW deny-in → SSH and all
services bound tailnet-only (with `ssh.socket` disabled — socket activation
silently ignores `ListenAddress`) → key-only auth, no root password →
fail2ban + unattended security upgrades → secrets at 0600 with a
never-silently-rotate law → services under systemd with restart handlers.
