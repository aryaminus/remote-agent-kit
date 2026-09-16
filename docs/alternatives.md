# Alternatives: other places to run this kit

This repo provisions **Hetzner** by default, but the Ansible layer is
provider-agnostic: anything that is **Ubuntu 24.04 x86_64 with SSH + sudo**
can be configured with `make deploy`. Terraform is the only Hetzner-specific
part — skip `make apply`, point `ansible/inventory/hosts.yml` at your own box,
and carry on.

Evaluated 2026-09-15 against [exe.dev](https://exe.dev),
[Vercel Eve](https://vercel.com/eve), and [box by ASCII](https://box.ascii.dev).
Prices/claims below are from their public pages on that date — re-check before
committing, especially box's comparison page (their own numbers favor them).

## The short version

| If you want… | Use | What changes in this repo |
|---|---|---|
| Cheapest predictable always-on box, full control | Hetzner cx33 (default) | Nothing — `make apply && make deploy` |
| Zero TLS/proxy work, private HTTPS links to share | [exe.dev](https://exe.dev/vps) VPS | Skip `make apply`; deploy Ansible onto your exe.dev VM (below) |
| Per-second billing, one VM per agent, instant fork | [box.ascii.dev](https://box.ascii.dev) | Same: deploy Ansible onto a box, or use boxes *instead of* AoE containers |
| A framework to **build your own** agent (not run Hermes) | [Vercel Eve](https://vercel.com/eve) | Nothing here — different layer (see below) |

## exe.dev VPS — the "batteries included" VM

What it is: real KVM Linux VMs (root, `apt`, `systemd`) plus per-second
disposable sandboxes. The VPS-relevant bits:

* **Per-VM hostname + real TLS at the edge** (`mybox.exe.xyz`, or your domain).
  No nginx/certbot/UFW-TLS dance — the edge terminates TLS and forwards to a
  port on the VM, WebSockets/SSE included.
* **Private by default.** The HTTPS proxy answers only accounts you share with
  (`share add user@…`); `share set-public` opens it. A half-built dashboard
  stays offline with no VPN work.
* **Key-only SSH**, no exposed ports (SSH brokered through exe.dev),
  maintained `exeuntu` image tracking Ubuntu security updates, SSH-signed API
  (`ssh exe.dev new myblog` → ready in ~0.8 s).
* **Pool pricing:** Personal $20/mo = 50 VMs sharing 100 GB disk; a stopped VM
  keeps disk, releases CPU/RAM. One big box or fifty small ones, same bill.

Using it with this kit:

```bash
ssh exe.dev new hermes            # or via their dashboard
# put the VM's address in ansible/inventory/hosts.yml, then:
make deploy                       # all 7 roles apply unchanged
```

Two things this replaces for exe.dev users: the Tailscale role becomes
*optional* (the exe.dev proxy already gives private HTTPS + IAM sharing —
handy for letting someone view the dashboard without joining your tailnet),
and Perch can pair via public HTTPS instead of tailnet:

```bash
# on the server (public pairing script from perch-site), public-URL mode:
bash pair.sh --url https://hermes.<you>.exe.xyz:8642   # must be https — the
# script refuses plain HTTP to public hosts, and the key would cross the net
```

Keep Tailscale anyway if you want SSH without exe.dev in the path, or
Perch-over-tailnet with no public surface at all.

## box.ascii.dev — per-second agent VMs

What it is: persistent Ubuntu VMs with SSH/SCP, Docker *inside*, dedicated
IPv6/IPv4 per box, disk-level **fork**, 60 fps virtual desktop, EU regions
(DE/FI/CZ→FR per their pages: Germany, Finland, France).

* **Billing:** $20/mo account minimum → ~555 h of 4 vCPU/8 GB
  box-time, billed by the second across one box or many (a recent
  announcement quotes **$0.036/vm-hr for 8c/16GB/100GB** boxes, up to
  **2,000 concurrent** VMs). Sizes: small
  (2 vCPU/4 GB, 0.5×), default (4 vCPU/8 GB, 1×), large (8 vCPU/16 GB, 2×).
  **Stopped = snapshotted (snapshots free), billing paused**, resume in seconds —
  but resume does NOT restore running processes or in-memory state (vendor:
  that would be expensive and cause time-slip bugs; their recommendation is
  **systemd services**, exactly what this kit already runs). 100–2,000
  active boxes per account; default TTL 1 h, overrideable.
* **Preinstalled:** Docker, VS Code, Chrome (scraping-ready), Ghostty, GH CLI,
  Rust, Node, Bun, plus agent harnesses. `box new / ssh / scp / prompt / fork
  / stop / desktop / list`, plus HTTP API + Python/TS SDKs and `--json` JSONL
  output. **Desktop** via Moonlight by default, VNC with `box desktop --vnc`.
  Bring any agent: Claude Code, Codex, OpenCode.
* Docs are clean markdown with an `llms.txt` index (a pattern copied in this
  repo's own `docs/llms.txt`).

Two ways to use it with this kit:

1. **As the always-on host** (Hetzner alternative): `box new`, then
   `make deploy` with the box as `ansible_host`. Same 7 roles.
2. **As the agent factory** (AoE alternative): instead of containers on one
   box, give each coding agent its own box and `box fork` to branch work —
   VM-level isolation instead of container-level. Better blast radius, ~$20
   minimum covers ~555 default-box hours. Worse for single-box simplicity;
   cross-box comms and per-box Hermes installs are your problem then.

## Vercel Eve — different layer, borrow the ideas

[Eve](https://vercel.com/eve) (open source, beta) is a **framework for building
agents**, not infrastructure for running Hermes. Our kit runs a complete agent
(Hermes); Eve is what you'd use to *write* one. No migration, no integration —
but four ideas worth stealing, three of which this repo already follows:

1. **Filesystem-first conventions** (`agent/tools/*.ts` = one tool per file,
   filename is the tool name). Our repo mirrors it: one Ansible role per
   concern, one script per job, docs as plain markdown. Keep it that way.
2. **Credentials brokered outside the prompt** (Eve connections/MCP + Vercel
   Connect; model never sees URLs/keys). Our equivalent: secrets only in
   `.env` → server env `0600`, never committed, never in chat. Same law.
3. **Approvals that park without burning compute** (Eve); Hermes has
   `approvals.mode` + fail-closed timeout, Perch renders the request's own
   `choices`. Nothing to change — just don't gate features on approvals being
   active (undetectable from the API side).
4. **`eve eval` as a deploy gate** (scored suites in CI). Our analog is
   `make doctor` (7 live checks) + `repo_check.sh` (static). If you outgrow
   them, add a scored post-deploy probe (pairing handshake, approval
   round-trip) before calling a deploy green — same shape as an Eve eval.

## Herdr vs AoE — the multi-agent layer (read before choosing)

[Herdr](https://herdr.dev) ([38.8k★, Apache-2.0, Rust](https://github.com/herdrdev/herdr))
is the heavyweight alternative to the Agent of Empires role this kit ships.
Both keep coding agents alive across disconnects; they differ in philosophy:

| | AoE (this kit's default) | Herdr |
|---|---|---|
| Community | ~2.7k★ | ~38.8k★, 875k+ installs, 1,133 plugins |
| Persistence | `tmux` sessions (standard, attachable with plain tmux) | Own multiplexer + server; restores layout across **reboots**, resumes supported sessions |
| Agent awareness | Status (running/waiting/idle/error) + diff viewer | Status (working/blocked/idle) + 22 CLIs auto-detected (**incl. Hermes**) |
| Isolation | **Docker/Podman sandboxing per agent** + git worktrees | Panes + machines; no container sandbox story |
| Remote/phone | **Web dashboard** over tailnet (Tailscale serve/Funnel) + mobile views | SSH-native multi-machine (`herdr machine add workbox` unifies laptop+VPS); no web UI |
| Platforms | Linux/macOS (+WSL2) | macOS/Linux/Windows, one binary |

Decision: **AoE stays default** — sandboxing plus a web dashboard is the
right shape for an always-on box you also visit from your phone. **Herdr is
the recommended switch for terminal-first operators**: install it
(`curl -fsSL https://herdr.dev/install.sh | sh`, or set
`enable_herdr: true` in `group_vars/all.yml` — the `herdr` role installs the
binary idempotently), then run agents under `herdr` instead of `aoe`. Both
can coexist; don't run the SAME checkout under both.

## Decision log (for this repo)

* Default stays **Hetzner + Tailscale**: cheapest predictable always-on,
  no vendor in the SSH/data path, snapshots cheap. (ADR-worthy if challenged.)
* exe.dev recommended when **sharing private HTTPS links** matters more than
  $/mo optimization, or when you refuse to run Tailscale clients everywhere.
* box recommended when usage is **bursty or multi-agent-per-VM**, or you want
  fork-as-branching without Docker.
* Eve is not a host for Hermes; revisit only if we ever build a custom agent
  instead of running Hermes.
