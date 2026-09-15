# Ops runbook

## Daily

| Command | What |
|---|---|
| `make ssh` | shell on the box (over Tailscale) |
| `make doctor` | 7 checks: SSH, Tailscale, /health, both services, UFW, disk |
| `make logs` | follow `hermes-gateway` journal |
| `aoe` (on server) | multi-agent TUI; `aoe add --cmd claude` for a new session |
| `aoe serve` (on server) | web dashboard (binds localhost — reach via `tailscale serve`) |

## Weekly / monthly

* `make backup` — pull the newest `~/backups/agent-*.tar.gz` off-box.
* `make rollback FILE=backups/agent-<date>.tar.gz` — restore the server from a
  tarball (snapshots current state first, always asks). The way back for every
  change, per the Law of Unintended Consequences.
* Hetzner console — confirm the daily snapshot ran; tag `before-update` first.
* Budget review (Goodhart's warning: watch the spend, not the gates): Hetzner
  console usage + model provider dashboard. Expected ~€7.55 + $5–20; investigate
  drift before optimizing.
* Updates: snapshot → `hermes backup` → `hermes update` → `hermes doctor` →
  `systemctl --user restart hermes-gateway hermes-dashboard`.
* Rotate: Tailscale auth key (90d expiry reminds you), Telegram token on leak
  (`/revoke`), `API_SERVER_KEY` yearly (`make deploy` regenerates if blanked).

## Failure modes

| Symptom | Check |
|---|---|
| Bot silent | `systemctl --user status hermes-gateway`; `TELEGRAM_ALLOWED_USERS` numeric? only one poller (stop foreground gateway)? |
| `gateway install` did nothing | known upstream prompt bug — this repo already pipes `printf 'n\nY\n'`; re-run `--tags telegram` |
| Dies on reboot | `loginctl show-user hermes -p Linger` must be `yes` |
| Phone can't reach API | gateway bound to loopback? need `API_SERVER_HOST=0.0.0.0` + UFW tailnet rule; Tailscale up on both ends? |
| Perch 401 after dashboard restart | token wasn't pinned — re-run `--tags perch`, re-pair |
| Approval never arrives | normal when guardian auto-handles it; "no approval" ≠ "checked safe". Pending approvals time out closed (default 300 s). |
| Disk full | install is ~6.6 GB; `df -h`; prune Docker (`docker system prune`) |

## Teardown

`make teardown` destroys the VPS (asks first). Snapshots and local
`./backups/` survive. Delete the Tailscale machine entry afterwards.
