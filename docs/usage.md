# Using your agent — the daily driver's guide

Everything runs on the box; your Mac and phone are thin clients. Close the
lid, pocket the phone — agents keep working. Public SSH (key-only, your IP)
is the laptop's door; the tailnet is the phone's; the gateway API never
faces the public internet.

## 1. From your laptop terminal (zero apps beyond ssh)

The one-time setup on your Mac (already done on the owner's machine):

```bash
# ~/.ssh/config — plain direct door + auto-tmux interactive door:
Host box-x
    HostName <box-ip>
    User <box-user>
Host agent
    HostName <box-ip>
    User <box-user>
    RemoteCommand tmux attach-session -t main 2>/dev/null || tmux new-session -A -s main
    RequestTTY yes
```

Then from any terminal (Warp included — see the workflows below):

```bash
ssh agent          # you're on the box, in a session that never dies
```

On the box you have, in order of power:

| Command | What you get |
|---|---|
| `hermes` | **The agent itself**, full interactive terminal REPL — chat, tools, skills, memory. This is the same brain Perch talks to. |
| `aoe` | The coding-agent workshop (§3). |
| `tmux` | Anything long-running; detach with `Ctrl+b d`, reattach next login. |
| `journalctl --user -u hermes-gateway -f` | Watch the agent think (what Perch/Telegram rides on). |

**One-shot questions without an SSH session:**

```bash
./scripts/ask.sh "what did you do today?"
```

Runs the whole request *inside* the box over SSH and prints just the reply
— your Mac needs no VPN and never holds the API key in memory beyond the
command. Warp users: an `agent-ask` workflow ships in this section's setup —
type `agent-ask <question>` anywhere. (Suggested `~/.warp/workflows/`:
`agent` → `ssh agent`, `agent-ask`, `agent-doctor`, `agent-logs`.)

Talking to the API **directly from your Mac** needs the tailnet (Tailscale
on the laptop) — the API is deliberately unreachable otherwise. Key in
`.env` (`API_SERVER_KEY`):

```bash
curl -H "Authorization: Bearer $API_SERVER_KEY" \
     -H 'Content-Type: application/json' \
     -d '{"message":"status report: what did you do today?"}' \
     https://<box>.<your-tailnet>.ts.net/api/sessions/<id>/chat
```

## 2. From your phone — native app, web PWA, or Mac web

**Easiest — one command, QR on your screen (native app path):**

```bash
make pair-qr
```

It SSHes to the box, runs the public pairing script with the correct
HTTPS address, and streams the QR into your terminal. Point the phone
camera at your own screen. No camera / prefer typing? The same output
shows the address + API key for *Enter details instead*.

Manual path (same result): `make pair` prints the steps — SSH in, run
perch-site's `pair.sh --url <https-address>`, scan.

**Perch web on your laptop** (same screens, no phone involved):

```bash
PERCH_REPO=~/src/perch make perch-web     # or: ./scripts/perch-web.sh --repo ~/src/perch
```

Serves the web export at `http://localhost:8081` — open it, *Enter details
instead*, same address + key as above. The script verifies the tailnet
route and tells you if the box needs your localhost origin allowlisted.

- **Perch native**: sessions, streaming, approvals, skills, cron — the polished
  path. Needs the Tailscale app signed in.
- **Perch web PWA** (no store/TestFlight needed): same screens from this box
  — see "Perch web PWA" in `tailscale-perch.md`. Needs the Tailscale app only.
- **Telegram** (OFF unless configured): message the bot; allow-listed to your
  numeric id. Needs nothing but Telegram itself.

## 3. The coding-agent workshop (AoE)

`ssh` in, run `aoe`. Each session = own `tmux` + git worktree, optionally
Docker-sandboxed; survives disconnects; web dashboard via `aoe serve`.

```bash
aoe                     # TUI dashboard
aoe add --cmd claude    # a Claude Code session
aoe add --cmd codex     # OpenAI Codex
aoe add --cmd opencode  # OpenCode
aoe add --cmd cmd       # CommandCode
aoe agents              # what's detected
```

**Governed by default:** every host is attached to ControlKeel twice —
per-repo (`~/work`: hooks, skills, MCP) and per-user (`~/.claude.json`,
`~/.codex/`, `~/.config/opencode/`), so governance follows you into any
project subdir. In opencode, press **Tab** and pick `controlkeel-operator`
(it's listed from every directory now — it used to hide because the file
only existed in `~/work/`); headless runs take
`opencode run --agent controlkeel-operator "do X"`. No config key for a
startup-default agent exists in this opencode version — Tab-select +
`--agent` is the whole answer. (`cmd` has no CK host adapter; it runs
plain, skills only.)

**One-time auth per CLI (yours, browser-based — we install binaries, never
your logins):**

| CLI | Auth |
|---|---|
| `claude` | **skipped for now** (owner's choice — needs Max/Pro sub or ANTHROPIC_API_KEY; add the key to `.env` and re-deploy to wire it) |
| `codex` | ChatGPT device login — then note the **free-tier usage cap** (Plus boundary is real; `codex exec` reports it plainly) |
| `opencode` | Any OpenRouter key (`OPENROUTER_API_KEY` in `.env` → server env, no prompt). Default Zen auth accepted the key, but its default endpoint can't run tools on some keys — pass an explicit model: `opencode run --model openrouter/anthropic/claude-sonnet-4 "do X"` (proven live) |
| `cmd` (CommandCode) | `COMMANDCODE_API_KEY` in `.env` → server env; one paste into `cmd login` writes `~/.commandcode/auth.json`, then `cmd -p "do X"` runs headless (proven live: `COMMANDCODE-OK`) |
| Z.AI/GLM via `opencode` | `ZAI_API_KEY` in `.env` → server env + `opencode auth login`. **Two entries = two billing tracks (verified live):** **"Z.AI"** → `zai/*` models bill the pay-as-you-go **API wallet** — an empty wallet answers *"Insufficient balance"* (wiring proven, wallet empty; top up at the Z.AI console). **"Z.AI Coding Plan"** → `zai-coding-plan/*` models bill your **GLM Coding Plan subscription** quota — if you hold the plan, this is your lane (proven live: `zai-coding-plan/glm-5.3` → `CP-OK`). Same key, different endpoint; both entries can coexist in `auth.json`. |
| OpenCode Zen via `OPENCODE_API_KEY` | Zen key (`sk-…` from opencode.ai/auth) in `.env` → server env; ALSO stored once via `opencode auth login` → OpenCode Zen (verified: stored hash matches `.env`, and headless runs authenticate). **Two failure signatures, know them apart:** *"Invalid API key"* = wrong key in the Zen slot (we fixed one live — an OpenRouter key had been pasted there); *"No payment method …/billing"* = key is valid, the Zen workspace needs billing set up. |
| Antigravity | not auto-installed (Google's script URL isn't pinnable); see their docs, then AoE detects it |

Agent subscriptions are billed by their vendors — separate from the ~€9.99
box and the free-tier Nous model your Hermes brain uses.

**GitHub on the box (`gh`, one-time, per-user — by design):** git over SSH
works out of the box, but `gh` API actions (PR comments/reviews, releases,
issues) need a login, and GitHub's device flow can *only* be approved by
the account owner in a browser — no script can or should do that for you.
One command from your Mac runs the flow on the box and prints the code
locally:

```bash
./scripts/gh-login.sh
# 1. Open:  https://github.com/login/device
# 2. Code:  XXXX-XXXX   (printed by the script, ~15-min expiry)
```

It waits for your approval, verifies the session, and cleans up after
itself. Already logged in? It just says so and exits 0. Codes expire —
rerun the script for a fresh one.

**OpenCode Zen + free models (verified live):** Zen's own auth accepts a
key, but its default endpoint may answer *"no payment method"* — pass an
explicit model, or set your own default. To make a working model the
default for bare `opencode run` (box-local, survives redeploys — Ansible
doesn't manage this file):

```bash
# ~/.config/opencode/opencode.json — add the top-level key:
{ "model": "zai-coding-plan/glm-5.3", … }
```

## How it all fits together

```
     public internet  (only SSH:22, key-only, edge-firewalled to your IP)
                              │
 ┌────────────────────────────┴─────────────────────────────┐
 │ <box> · Ubuntu 24.04 · UFW deny-by-default               │
 │                                                          │
 │  sshd (public, your IP) ───── you ↔ box, thin clients    │
 │  Tailscale ── WireGuard mesh ──────────────────────────┐ │
 │   └── serve 443 → gateway API     valid TLS, tailnet   │ │
 │   └── serve 8443 → phone web app  valid TLS, tailnet   │ │
 │                                                          │ │
 │  hermes-gateway (systemd) ◄── the brain: Nous model,    │ │
 │   ├── API :8642  ← Perch / curl / Telegram polling      │ │
 │   └── dashboard :9119 (basic-auth)                      │ │
 │                                                          │ │
 │  AoE + Docker ── claude/codex/opencode/cmd sandboxes    │ │
 │  backups cron + Hetzner snapshots ── the undo buttons   │ │
 └──────────────────────────────────────────────────────────┘
        your Mac (SSH) / phone (tailnet) ── same live system
```

- **The brain** (Hermes + Nous model) is your always-on assistant — phone,
  terminal, API. Free tier today; swap models with `hermes model`.
- **The hands** (coding agents under AoE) are separate tools with their own
  auth and billing — you drive them deliberately, sandboxed.
- **The rules**: secrets live in `.env` files at 0600, never in git; the
  pairing QR *is* the API key; `make doctor` is the heartbeat;
  `make rollback` + snapshots are the undo.

## Daily cheat sheet

```bash
make ssh        # straight onto the box (from the repo)
make doctor     # 7-point health, logged
make logs       # follow the gateway journal
make backup     # pull the newest tarball off-box
make pair       # phone pairing instructions + your HTTPS address
```
