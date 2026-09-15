# Privacy & threat model (read before exposing anything)

* **Default posture: nothing public.** No 80/443 firewall rules ship; SSH/API/
  dashboard are tailnet-only; Telegram polls out. Adding a public reverse proxy
  or `tailscale funnel` widens this — do it consciously.
* **The API key is a shell.** `API_SERVER_KEY` executes commands as the agent
  user. The pairing QR carries it. Anyone holding it owns the box's agent.
* **Dashboard token reads files** (`/api/files`, `/api/media` measured in
  Perch's pair.sh notes). Same handling as the API key.
* **Telegram allow-list is mandatory.** A bot token without
  `TELEGRAM_ALLOWED_USERS` answers strangers.
* **Model traffic leaves the box** (Nous/OpenRouter/Anthropic) unless you run
  local inference. Memory/skills stay on your disk + snapshots.
* **Approvals fail closed** (default 300 s timeout). "No approval arrived"
  means "the agent didn't ask", never "it was checked safe".
* **Backups contain everything** (memory, skills, keys' neighbourhood).
  Encrypt with `age_public_key` and keep off-box copies private.
