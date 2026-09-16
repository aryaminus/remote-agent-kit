# Using your agent — the daily driver's guide

You now own a small cloud with a brain on it. Three surfaces reach it,
plus a workshop of coding agents underneath. Nothing here opens a port
to the internet.

## 1. From your laptop terminal (zero apps beyond ssh)

The one-time setup on your Mac (already done on the owner's machine):

```bash
# ~/.ssh/config — 'agent' auto-attaches a persistent tmux on the box:
Host hermes agent
    HostName hermes.<your-tailnet>.ts.net
    User hermes
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
| `aoe` | The coding-agent workshop (below). |
| `tmux` | Anything long-running; detach with `Ctrl+b d`, reattach next login. |
| `journalctl --user -u hermes-gateway -f` | Watch the agent think (what Perch/Telegram rides on). |

**One-shot questions without SSH:**

```bash
./scripts/ask.sh "what did you do today?"
```

Creates/reuses a `terminal` session on the gateway and prints just the
reply. Warp users: an `agent-ask` workflow ships in this section's setup —
type `agent-ask <question>` anywhere. (Suggested `~/.warp/workflows/`:
`agent` → `ssh agent`, `agent-ask`, `agent-doctor`, `agent-logs`.)

Talking to the agent **from your Mac without SSH** — the API is your gateway,
key in `.env` (`API_SERVER_KEY`):

```bash
curl -H "Authorization: Bearer $API_SERVER_KEY" \
     -H 'Content-Type: application/json' \
     -d '{"message":"status report: what did you do today?"}' \
     https://hermes.<your-tailnet>.ts.net/api/sessions/<id>/chat
```

## 2. From your phone

- **Perch**: sessions, streaming, approvals, skills, cron — the polished path
  (`pair.sh --tailscale` QR, one time).
- **Telegram** (optional): message the bot; allow-listed to your numeric id.

## 3. The coding-agent workshop (AoE)

`ssh` in, run `aoe`. Each session = own `tmux` + git worktree, optionally
Docker-sandboxed; survives disconnects; web dashboard via `aoe serve`.

```bash
aoe                     # TUI dashboard
aoe add --cmd claude    # a Claude Code session
aoe add --cmd codex     # OpenAI Codex
aoe add --cmd opencode  # OpenCode
aoe agents              # what's detected
```

**One-time auth per CLI (yours, browser-based — we install binaries, never
your logins):**

| CLI | Auth |
|---|---|
| `claude` | **skipped for now** (owner's choice — needs Max/Pro sub or ANTHROPIC_API_KEY; add the key to `.env` and re-deploy to wire it) |
| `codex` | ChatGPT device login — then note the **free-tier usage cap** (Plus boundary is real; `codex exec` reports it plainly) |
| `opencode` | Any OpenRouter key (`OPENROUTER_API_KEY` in `.env` → server env, no prompt). Default Zen auth accepted the key, but its default endpoint can't run tools on some keys — pass an explicit model: `opencode run --model openrouter/anthropic/claude-sonnet-4 "do X"` (proven live) |
| `cmd` (CommandCode) | `COMMANDCODE_API_KEY` in `.env` → server env; one paste into `cmd login` writes `~/.commandcode/auth.json`, then `cmd -p "do X"` runs headless (proven live: `COMMANDCODE-OK`) |
| Z.AI/GLM via `opencode` | `ZAI_API_KEY` in `.env` → server env + `opencode auth login` → **Z.AI** provider → paste key once (writes `~/.local/share/opencode/auth.json`, 0600). Then `opencode run --model zai/<model> "do X"`. **Account reality, verified live:** if the call fails with *"Insufficient balance or no resource package. Please recharge"* the wiring is proven correct and the Z.AI account itself needs funds — top up at the Z.AI console. (Same free-tier boundary pattern as Codex: auth works, the meter is the vendor's.) |
| Antigravity | not auto-installed (Google's script URL isn't pinnable); see their docs, then AoE detects it |

Agent subscriptions are billed by their vendors — separate from the €9.99
box and the free-tier Nous model your Hermes brain uses.

## How it all fits together

```
                 internet (outbound only — nothing dials IN)
                              │
 ┌────────────────────────────┴─────────────────────────────┐
 │ Hetzner cx33 · Ubuntu 24.04 · UFW: no public ports      │
 │                                                          │
 │  Tailscale ── WireGuard mesh ──────────────────────────┐│
 │   ├── SSH (22, tailnet-only)      you ↔ box, private   ││
 │   └── serve 443 → gateway API     valid TLS, tailnet    ││
 │                                                          ││
 │  hermes-gateway (systemd) ◄── the brain: Nous model,    ││
 │   ├── API :8642  ← Perch / curl / Telegram polling      ││
 │   └── dashboard :9119 (basic-auth)                      ││
 │                                                          ││
 │  AoE + Docker ── claude/codex/opencode sandboxes        ││
 │  backups cron + Hetzner snapshots ── the undo buttons   ││
 └──────────────────────────────────────────────────────────┘
        your Mac / phone ── tailnet ── everything above
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
