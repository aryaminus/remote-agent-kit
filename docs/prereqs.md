# Prerequisites (gather these before `make init`)

Takes ~10 minutes, all free except the VPS itself.

| # | What | Where | Notes |
|---|---|---|---|
| 1 | Hetzner account + Cloud API token | console.hetzner.cloud → Security → API Tokens (read+write) | Goes in `.env` as `HCLOUD_TOKEN`. Never commits. |
| 2 | Tailscale account + auth key | login.tailscale.com/admin/authkeys → Generate (reusable, 90d expiry) | `TAILSCALE_AUTHKEY` in `.env`. Rotate after first deploy. Install Tailscale on your laptop + phone too. |
| 3 | SSH key | `ssh-keygen -t ed25519` if `~/.ssh/id_ed25519.pub` is missing | Paste the **public** key into `terraform.tfvars`. |
| 4 | Telegram bot token | Message `@BotFather` → `/newbot` | `TELEGRAM_BOT_TOKEN`. Full walkthrough: `telegram-setup.md`. |
| 5 | Your Telegram user id | Message `@userinfobot` | Numeric id, **not** your @handle. `TELEGRAM_ALLOWED_USERS`. |
| 6 | Model access | Nous Portal (OAuth, free tier) **or** OpenRouter/Anthropic key | Nous = no key stored. OpenRouter free models work but top up $10 once to raise rate limits 50→1,000/day. |
| 7 | Local tools | `terraform >= 1.5`, `ansible >= 2.15`, `ssh`, `curl` | macOS: `brew install terraform ansible`. |

Then:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
cp ansible/inventory/hosts.yml.example ansible/inventory/hosts.yml
cp .env.example .env && chmod 600 .env
# fill in the three files, then: make init && make plan
```
