# remote-agent-kit

**Your own always-on AI agent cloud — one command to deploy, yours to keep.**

Provisions a hardened [Hetzner Cloud](https://www.hetzner.com/cloud) VPS
(CPX21, x86, Ubuntu 24.04), joins it to your [Tailscale](https://tailscale.com)
tailnet (no public SSH, no open ports), installs
[Hermes Agent](https://github.com/NousResearch/hermes-agent) with a Telegram
gateway, exposes the API + dashboard for the [Perch](https://github.com/aryaminus/perch)
phone client, and sets up isolated multi-agent coding sessions
([Agent of Empires](https://github.com/agent-of-empires/agent-of-empires):
Claude Code, Codex CLI, OpenCode, Pi).

> This is a **bootstrap / infra-template repo**, not dotfiles. Dotfiles configure
> a laptop; this repo provisions a server. Terraform owns provisioning
> (reproducible, stateful), Ansible owns configuration (idempotent roles),
> `make` is the operator entrypoint, `scripts/` holds small glue.

## Architecture

```
Terraform (terraform/)          Ansible (ansible/)                Phone / laptop
┌──────────────────┐            ┌────────────────────────┐        ┌──────────────────┐
│ hcloud_firewall  │   ssh      │ common: user, UFW,     │ tailnet│ Perch app        │
│ hcloud_server    ├───────────►│ fail2ban, swap         │◄──────►│ Telegram bot     │
│ hcloud_ssh_key   │            │ tailscale: up + lock   │ 100.x  │ Termius / Blink  │
└──────────────────┘            │ hermes: agent+gateway  │        └──────────────────┘
                                │ telegram: bot polling  │
                                │ perch: api 8642+dash   │
                                │ aoe: multi-agent jail  │
                                │ backups: cron+snapshots│
                                └────────────────────────┘
```

* No inbound ports from the internet after Tailscale is up — SSH, API (8642),
  dashboard (9119) answer on the tailnet only.
* Telegram uses **polling**: the gateway dials out, nothing dials in.
* Each coding agent runs in its own container + `tmux` session via AoE.

## Quickstart

```bash
# 0. Prereqs — Hetzner account + API token, Tailscale account + auth key,
#    Telegram bot token + your numeric user id, an SSH key.
#    Read docs/prereqs.md first (5 min).

cp terraform/terraform.tfvars.example terraform/terraform.tfvars
cp ansible/inventory/hosts.yml.example ansible/inventory/hosts.yml
cp .env.example .env
# Edit the three files above — secrets live ONLY there, never committed.

make init      # terraform init + ansible-galaxy install
make preflight # fail free on your laptop before spending a cent
make plan      # review what will be created
make apply     # provision the VPS (~60s)
make deploy    # configure everything (~10 min)
make pair      # QR to scan with Perch / address for Telegram test
make doctor    # 7-point health check (logged to logs/doctor.log)
```

Day to day: `make ssh`, `make logs`, `make backup`. Full lifecycle in
`docs/ops-runbook.md`. Costs in `docs/costs.md` (~€7.55/mo VPS + $5–20/mo model
usage). Other hosts evaluated in `docs/alternatives.md` (exe.dev, box, Eve);
agent-readable repo index in `docs/llms.txt`.

## Layout

```
Makefile                    operator entrypoint — run `make help`
.env.example                every secret, placeholder values only
terraform/                  provisioning: firewall, ssh key, server, outputs
ansible/                    configuration: 7 idempotent roles + playbook
scripts/                    glue: doctor, backup, pair helper, repo_check
docs/                       prereqs, telegram, tailscale+perch, runbook, costs
.github/workflows/          CI: terraform validate + secret scan
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

License: [MIT](LICENSE).
