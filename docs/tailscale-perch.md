# Tailscale + Perch pairing

## Why Tailscale

SSH, the API (8642) and the dashboard (9119) answer **only on the tailnet**
(`100.64.0.0/10` + MagicDNS `hermes.<tailnet>.ts.net`). Scanners find nothing;
your phone reaches everything from anywhere with the Tailscale app signed in.

## First connection

1. Install Tailscale on laptop + phone, same account as the auth key.
2. `make ssh` (uses the tailnet once known) or bootstrap SSH to the public IP.
3. On the server: `tailscale ip -4` → note `100.x.y.z`.
4. `make pair` → follow the Perch QR flow **on the server**
   (Perch's `scripts/pair.sh --tailscale` reads the server key and prints the QR).
5. In Perch: *Scan to connect*. No camera? *Enter details instead* with the
   printed address + key.

## Rules

* The QR **is the API key**, and the key is a full agent shell. Trusted camera,
  trusted room, never screenshot into a chat.
* Dashboard token is pinned (`HERMES_DASHBOARD_SESSION_TOKEN`) — pairing
  survives restarts. If you pair before the fix role ran, re-pair after.
* Web build users: set `PERCH_WEB_ORIGIN` (exact origin) so the deploy writes
  `API_SERVER_CORS_ORIGINS`. Native apps need nothing.
* Locked out? Hetzner console → web console (VNC) → `tailscale status`,
  revert `/etc/ssh/sshd_config` `ListenAddress` lines, `systemctl restart ssh`.
