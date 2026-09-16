# ADR-001: Hetzner VPS + Tailscale (hybrid) over PaaS or plain VPS

Date: 2026-09-15 · Status: accepted

## Context

The agent needs to be always-on, cheap, fully controllable (multi-CLI coding
tools in isolation), and reachable from phone + laptop anywhere.

## Options considered

1. **Plain VPS + public SSH/port-forwarding** — cheapest, but every service is
   internet-facing; dashboard access needs nginx + certbot + hardening per app.
2. **PaaS / serverless containers (Fly.io, Railway)** — fast deploy, scale to
   zero; but variable billing, less OS control, stateful multi-agent sessions
   are awkward (`tmux` + containers want a real box).
3. **Hybrid: budget VPS + Tailscale mesh (chosen)** — Hetzner cx33 x86 at
   ~€9.99/mo with full root; Tailscale (WireGuard) makes the box a tailnet
   device, so SSH/API/dashboard answer privately with zero public ports and
   zero TLS to manage. Telegram polls out, so no inbound rules at all.

## Decision

Option 3. x86 specifically: the Hermes gateway crash-loops on ARM/aarch64
under systemd (upstream issue), ruling out the cheaper CAX line for
unattended use.

## Consequences

* Tailscale account becomes a hard dependency (lockout recovery = Hetzner web
  console; documented in `docs/tailscale-perch.md`).
* Firewall ships edge-closed; any public surface must be a conscious addition
  (see `docs/privacy-considerations.md`).
* Alternatives that would overturn this: `docs/alternatives.md`.
