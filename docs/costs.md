# Costs (Hetzner EU, mid-2026; US $ slightly higher)

## The promise: you pay for the box. Everything else is $0.

| What | Cost | Notes |
|---|---|---|
| **Hetzner VPS (the box)** | **~€9.99/mo cx33** (~€6.49 cx23 fallback) | The only mandatory spend. Hourly billing — destroy anytime. |
| Hetzner snapshot | ~€0.50/mo (40 GB) | Optional but recommended; the one cheap insurance. |
| **Tailscale** | **$0** | Personal plan, free forever: ≤6 users, **unlimited** devices, MagicDNS, ACLs, SSH. Paid ($8/user/mo) only past 6 users. |
| **Telegram bot** | **$0** | Bot API free; polling uses negligible traffic. |
| **Perch phone client** | **$0** | Open-source client; you talk to YOUR gateway, no relay fees. |
| **Agent CLIs + AoE/Herdr** | **$0** | All open-source (MIT/Apache-2.0). |
| **This kit** | **$0** | MIT licensed. |
| Model usage (the real variable) | $0–20/mo | NOT the box: Nous Portal free tier exists; OpenRouter free models work (+$10 one-time top-up lifts rate limits 50→1,000/day). Anthropic direct is pay-per-token. |
| Domain name | $0 (not needed) | MagicDNS replaces it. Only if you want a public URL. |

**Total mandatory: the box (~€9.99).** Realistic total with insurance + moderate
model use: **under ~$30/mo**. There is no relay, no SaaS seat, no per-message
fee anywhere in this design — if a step ever asks for a credit card beyond
Hetzner (and optionally your model provider), stop and re-read the docs.

## The box, specced

| Item | Price | Notes |
|---|---|---|
| VPS **cx33** (4 vCPU / 8 GB / 80 GB, x86) | ~€9.99/mo | Default. Room for gateway + dashboard + 2–3 agents + browser tools. |
| VPS **cx23** fallback (2 vCPU / 4 GB / 40 GB, x86) | ~€6.49/mo | Cheapest viable. Tight once browser/Playwright tasks run. |
| Snapshot | ~€0.012/GB/mo (~€0.50 for 40 GB) | Daily auto-snapshot recommended. |
| Egress | 20 TB/mo free | Effectively unlimited for agents. |

Managed equivalents run 3–5× the under-~$30/mo realistic total, and you
don't own the data.

## Alternatives at a glance (2026-09-15 public pricing)

| Option | Shape | When it wins |
|---|---|---|
| Hetzner cx33 (this default) | ~€9.99/mo fixed | Predictable always-on, full control |
| [exe.dev](https://exe.dev/vps) Personal | $20/mo pool (50 VMs, 100 GB disk) | Private HTTPS sharing + zero TLS work; many small VMs, one bill |
| [box.ascii.dev](https://box.ascii.dev) | $20 minimum → ~555 h of 4 vCPU/8 GB, per-second, pause-when-stopped (resume loses running processes — their own advice is systemd) | Bursty use, one VM per agent, fork-as-branching |

Full analysis: `alternatives.md`.

## Why not cheaper / ARM?

* **x86, not ARM.** The gateway crash-loops on ARM/aarch64 under systemd
  (upstream issue); CAX11 (€3.79 ARM) is tempting but unsafe for unattended use.
* **Disk, not RAM, is the limit.** The gateway idles ~280 MB; the install is
  ~6.6 GB (Chromium + node + python). A 20 GB disk is tight — hence 40 GB min.
* Pay-per-use PaaS (Fly/Railway) can be cheaper for sporadic use but costs
  unpredictably under load and gives less control; this repo optimizes for a
  predictable always-on box.
