# Tailscale + access (SSH, terminal, Telegram, Perch)

## Four ways in — pick any, mix freely

| Method | What you get | What you install | Cost |
|---|---|---|---|
| **SSH** (Termius / Blink / plain `ssh`) | Full shell on the box | Tailscale app + any SSH client | $0 |
| **Terminal multiplexers** (AoE TUI / Herdr / tmux) | Persistent agent sessions over that SSH | Same as SSH | $0 |
| **Telegram bot** | Chat with the agent from any phone, no other app | Telegram only (bot polls out — needs nothing inbound) | $0 |
| **Perch phone client** | Sessions, streaming, approvals, skills, cron | Perch + Tailscale app on the phone | $0 (open-source client) |

All four ride the same tailnet; none opens a public port.

## Tailscale costs $0 for this kit's shape

Personal plan, **free forever** (pricing v4, April 2026): **≤6 users**,
**unlimited devices**, MagicDNS, ACLs, Tailscale SSH, subnet routers, exit
nodes. That covers a household/small-team agent box with enormous headroom
(phones, laptops, tablets, the VPS, spares — devices are unlimited).
You pay ($8/user/mo Standard) only past 6 users or for business features
(SCIM/MDM). Personal = non-commercial use; a self-hosted agent box is
exactly what it's for.

## If Tailscale isn't for you

No lock-in: the Ansible roles only assume "SSH reachable", so any of these
replace the `tailscale` role with a `hosts.yml` change:

* **Headscale** — self-hosted open-source Tailscale control server (free;
  can run on this same box). Same WireGuard mesh, no Tailscale account.
  Most work to run, most control. The natural exit if you outgrow Personal
  or distrust the hosted control plane.
* **ZeroTier** — same idea, free tier 25 nodes. Fewer knobs than Tailscale,
  fine for one box + a few phones.
* **Plain WireGuard** — free, no accounts, maximum manual config (keys,
  peers, firewall per device). The honest fallback when you want zero
  third parties and don't mind the toil.
* **Cloudflare Tunnel** — free, no open ports, public HTTPS URLs. Trade:
  traffic passes through Cloudflare's edge (account + trust required),
  and SSH needs their client config. Best when you want public links,
  worst when "no third party sees my bytes" matters.

Default stays Tailscale: zero config, MagicDNS, and the Perch pairing flow
(`pair.sh --tailscale`) assumes it.

## Why Tailscale

SSH, the API (8642) and the dashboard (9119) answer **only on the tailnet**
(`100.64.0.0/10` + MagicDNS `hermes.<tailnet>.ts.net`). Scanners find nothing;
your phone reaches everything from anywhere with the Tailscale app signed in.

## First connection

1. Install Tailscale on laptop + phone, same account as the auth key.
   macOS: use the **App Store app** (proper network interface — SSH, Termius,
   and browsers all route transparently). The Homebrew CLI in userspace mode
   reaches the control plane but does NOT route data without a TUN device.
   Linux: official `install.sh` + `tailscale up` is enough.
2. `make ssh` (uses the tailnet once known) or bootstrap SSH to the public IP.
3. On the server: `tailscale ip -4` → note `100.x.y.z`.
4. `make pair` → follow the QR flow **on the server**. The pairing script is
   public — download-then-run, never piped (Perch's own rule: read it first):
   `curl -fsSL https://aryaminus.github.io/perch-site/pair.sh -o pair.sh`
   then `bash pair.sh --tailscale`. It reads the server key and prints the QR.
5. In Perch: *Scan to connect*. No camera? *Enter details instead* with the
   printed address + key.

## After pairing — finish the Perch setup (all public scripts)

Pairing connects the app; these three harden and complete it. Same
download-then-run form for each (`curl -fsSL
https://aryaminus.github.io/perch-site/<name> -o <name> && bash <name>`):

1. **`enable-approvals.sh`** — makes the agent ASK before dangerous commands
   (`approvals.mode: manual` + memory write approval). Do this: the default
   `smart` mode can fail open and execute without asking.
2. **`ntfy-setup.sh`** — generates your notification topic + prints the exact
   gateway config lines for it.
3. **`install-approval-bridge.sh`** — installs the hook plugin so approvals
   reach your phone while Perch is closed (this kit's Ansible already does
   this when `NTFY_TOPIC` is set — skip if deploy configured it).

## Editor + terminal access (beyond the phone app)

* **SSH from phone/tablet:** Termius (connection manager, cloud sync) or Blink
  Shell (keyboard-centric, Apple) — point at the tailnet IP or MagicDNS name.
* **VS Code:** Remote-SSH to the tailnet address for full IDE inspection of
  server checkouts; the Super CLI extension unifies the installed agent CLIs
  inside the editor. Agents themselves stay sandboxed in AoE containers.

## Rules

* The QR **is the API key**, and the key is a full agent shell. Trusted camera,
  trusted room, never screenshot into a chat.
* Dashboard token is pinned (`HERMES_DASHBOARD_SESSION_TOKEN`) — pairing
  survives restarts. If you pair before the fix role ran, re-pair after.
* Web build users: set `PERCH_WEB_ORIGIN` (exact origin) so the deploy writes
  `API_SERVER_CORS_ORIGINS`. Native apps need nothing.
* Locked out? Hetzner console → web console (VNC) → `tailscale status`,
  revert `/etc/ssh/sshd_config` `ListenAddress` lines, `systemctl restart ssh`.
