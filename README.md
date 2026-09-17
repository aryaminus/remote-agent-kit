# remote-agent-kit

**Your own always-on AI agent cloud — one command to deploy, yours to keep.**

Provisions a hardened [Hetzner Cloud](https://www.hetzner.com/cloud) VPS
(cx33, x86, Ubuntu 24.04), joins it to your [Tailscale](https://tailscale.com)
tailnet for private phone/API access, and installs [Hermes Agent](https://github.com/NousResearch/hermes-agent)
with an optional Telegram gateway, a tailnet API + dashboard for the
[Perch](https://aryaminus.github.io/perch-site/) phone client (native or PWA),
and isolated multi-agent coding sessions
([Agent of Empires](https://github.com/agent-of-empires/agent-of-empires):
Claude Code, Codex CLI, OpenCode, CommandCode).

> This is a **bootstrap / infra-template repo**, not dotfiles. Dotfiles configure
> a laptop; this repo provisions a server. Terraform owns provisioning
> (reproducible, stateful), Ansible owns configuration (idempotent roles),
> `make` is the operator entrypoint, `scripts/` holds small glue.

## Architecture

```
Terraform (terraform/)          Ansible (ansible/)                You
┌──────────────────┐            ┌────────────────────────┐        ┌──────────────────┐
│ hcloud_firewall  │   ssh      │ common: user, UFW,     │ tailnet│ Perch app / PWA  │
│ hcloud_server    ├───────────►│ fail2ban, swap         │◄──────►│ Telegram (opt)   │
│ hcloud_ssh_key   │            │ tailscale: up (+serve) │ public │ Mac terminal SSH │
└──────────────────┘            │ agent: gateway+dash  │  22    └──────────────────┘
                                │ telegram: bot (opt-in) │
                                │ perch: api 8642+--+dash│
                                │ aoe: claude/codex/open-│
                                │  code/cmd sandboxes    │
                                │ backups: cron+snapshots│
                                └────────────────────────┘
```

* SSH answers publicly too (key-only, edge-firewalled to your IP — for
  laptops without a VPN client); API (8642), dashboard (9119), serve ports
  and the web app (8443) answer on the tailnet only. Set
  `lock_ssh_to_tailnet: true` in `hosts.yml` for tailnet-only SSH.
* Telegram is **off unless configured** and polls out — nothing dials in.
* Each coding agent runs in its own container + `tmux` session via AoE.

## Quickstart — pick a path

[![Deploy to Hetzner Cloud](https://img.shields.io/badge/Deploy_to-Hetzner_Cloud-d50c2d)](https://console.hetzner.cloud)

**Path A — one-click (no tools installed, ~20 min).** Click the button above,
then Add Server: Ubuntu 24.04 · cx33 (x86) · your region · your SSH key. At
the bottom, expand **Cloud config** and paste exactly this (it pulls the
current setup from this repo — never rots, contains zero secrets):

```yaml
#include
https://raw.githubusercontent.com/aryaminus/remote-agent-kit/main/deploy/hetzner-cloud-init.yaml
```

Create, wait for CPU to idle in Graphs (~10 min), then SSH in as
`agentbox@<ip>` and run `bash ~/finish.sh` — it asks for the 2–3 secrets
(Tailscale key, model, optional Telegram) and completes the box. Why no true one-click button?
Hetzner only offers `console.hetzner.com/deploy/<app>` to registered Apps —
this redirect + paste is the closest the platform allows, and it's honest
about the one manual step (secrets can't live in cloud-init: user-data stays
readable via the metadata service).

**Path B — wizard, reproducible (`./scripts/start.sh` / `make start`).**

```bash
git clone https://github.com/aryaminus/remote-agent-kit.git
cd remote-agent-kit
./scripts/start.sh     # or: make start
```

That's the whole setup. `start.sh` checks tools (offers to install them),
asks for your API keys **with validation** (typed blind, never printed),
writes the three config files, shows you the Terraform plan for approval,
then provisions → configures → verifies → prints the phone-pairing steps.
Re-running resumes where you stopped; nothing done is redone.
Pass `--reset` to start over, `--yes` to skip confirmations.

You need 3 free accounts first (5 min): Hetzner, Tailscale, Telegram
(optional — the bot stays off unless you configure it) —
`docs/prereqs.md`. Trying costs cents (hourly billing, `make teardown`
destroys). Manual path (same steps the wizard runs): `make init`,
`make preflight`, `make plan`, `make apply`, `make deploy`, `make doctor`.

No laptop VPN needed for terminal use: `lock_ssh_to_tailnet: false`
(default) keeps SSH public + key-only + edge-firewalled to your IP, while
all services stay tailnet-only. Daily driver commands and the phone
setup: `docs/usage.md`.

Day to day: `make ssh`, `make logs`, `make backup`. Full lifecycle in
`docs/ops-runbook.md`. Costs in `docs/costs.md` (~€9.99/mo VPS + $5–20/mo model
usage). Other hosts evaluated in `docs/alternatives.md` (exe.dev, box, Eve);
agent-readable repo index in `docs/llms.txt`.

## Layout

```
Makefile                    operator entrypoint — run `make help`
.env.example                every secret key, placeholder values only
terraform/                  provisioning: firewall, ssh key, server, outputs
ansible/                    configuration: idempotent roles + playbook
scripts/                    ask/doctor/backup/pair/rollback/preflight/start/finish + repo_check
docs/                       usage (daily driver), access, runbook, costs, ADRs
.github/workflows/          CI: terraform validate + ansible syntax + secret scan
```

## Non-goals (YAGNI — deliberately out of scope)

* No multi-region / HA / autoscaling. One box, snapshots, backups. The failure
  domain is small on purpose; scale when Gilb's numbers say so, not before.
* No public reverse proxy / 80-443 rules shipped. Add them only per
  `docs/privacy-considerations.md`.
* No ARM support (gateway crash-loops under systemd there — documented, not fixed here).
* No secrets management service — `.env` 0600 + `.gitignore` + CI scan is the
  whole system at this scale (Tesler's complexity has to live somewhere; here
  it lives in operator discipline, written down in `docs/prereqs.md`).

## Safety

* `scripts/repo_check.sh` fails CI on leaked secrets, dangerous container
  flags, unpinned images, and syntax errors. Run it before every push.
* `.gitignore` blocks `.env`, `*.tfvars`, `*.tfstate*`, age keys.
* The pairing QR **is a credential** (full agent shell) — trusted camera only.
* x86 chosen deliberately: the Hermes gateway crash-loops on ARM/aarch64 under
  systemd (upstream issue); see `docs/costs.md`.

## Credits

Learns openly from `dbrennand/hermes-on-hetzner` (Ansible + Tailscale remote
backend), `scicco/hermzner` (hardened Terraform+Ansible, digest pinning,
repo_check), `paras200/hermes-anywhere` (Makefile ops, multi-cloud layout),
`benpetty/hermes-infra` (bake/provision/config layering), and the
`hermes-recipes/cheap-vps` reboot-survival notes. Perch pairing flow mirrors
`scripts/pair.sh` from the Perch repo.

Security: [SECURITY.md](SECURITY.md) — trust model + how to audit a clone.

License: [MIT](LICENSE).
