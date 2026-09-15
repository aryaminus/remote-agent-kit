# Costs (Hetzner EU, mid-2026; US $ slightly higher)

| Item | Price | Notes |
|---|---|---|
| VPS **CPX21** (3 vCPU / 4 GB / 80 GB, x86) | ~€7.55/mo | Default. Room for gateway + dashboard + 2–3 agents + browser tools. |
| VPS **CX22** fallback (2 vCPU / 4 GB / 40 GB, x86) | ~€3.79/mo | Cheapest viable. Tight once browser/Playwright tasks run. |
| Snapshot | ~€0.012/GB/mo (~€0.50 for 40 GB) | Daily auto-snapshot recommended. |
| Egress | 20 TB/mo free | Effectively unlimited for agents. |
| Tailscale personal | free (100 devices) | |
| Model usage (moderate daily) | $5–20/mo | Nous Portal free tier exists; OpenRouter free models + $10 top-up for limits. |

**Total: under ~$30/mo** for an always-on agent you phone from anywhere.
Managed equivalents run 3–5× that and don't give you the data.

## Alternatives at a glance (2026-09-15 public pricing)

| Option | Shape | When it wins |
|---|---|---|
| Hetzner CPX21 (this default) | ~€7.55/mo fixed | Predictable always-on, full control |
| [exe.dev](https://exe.dev/vps) Personal | $20/mo pool (50 VMs, 100 GB disk) | Private HTTPS sharing + zero TLS work; many small VMs, one bill |
| [box.ascii.dev](https://box.ascii.dev) | $20 minimum → ~555 h of 4 vCPU/8 GB, per-second, pause-when-stopped | Bursty use, one VM per agent, fork-as-branching |

Full analysis: `alternatives.md`.

## Why not cheaper / ARM?

* **x86, not ARM.** The gateway crash-loops on ARM/aarch64 under systemd
  (upstream issue); CAX11 (€3.79 ARM) is tempting but unsafe for unattended use.
* **Disk, not RAM, is the limit.** The gateway idles ~280 MB; the install is
  ~6.6 GB (Chromium + node + python). A 20 GB disk is tight — hence 40 GB min.
* Pay-per-use PaaS (Fly/Railway) can be cheaper for sporadic use but costs
  unpredictably under load and gives less control; this repo optimizes for a
  predictable always-on box.
