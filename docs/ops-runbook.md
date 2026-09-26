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
  console usage + model provider dashboard. Expected ~€9.99 + $5–20; investigate
  drift before optimizing.
* Updates: snapshot → `hermes backup` → `hermes update` → `hermes doctor` →
  `systemctl --user restart hermes-gateway hermes-dashboard`.
* Resize (more RAM/disk, e.g. cx33 → cx43 for devcontainer toolkits): snapshot
  tagged `before-update` → set `server_type` in `terraform/terraform.tfvars` →
  `make plan` must say *updated in-place* with **0 to destroy** → `make apply`
  (the server shuts down, changes type, boots: a few minutes offline; SSH
  sessions and tmux drop) → `make doctor`. User services come back only with
  linger on (`loginctl show-user <user> -p Linger`). With `keep_disk = false`
  (the provider default) the disk grows too, and a grown disk cannot shrink
  back to the smaller type.
* Rotate: Tailscale auth key (90d expiry reminds you), Telegram token on leak
  (`/revoke`), `API_SERVER_KEY` yearly (`make deploy` regenerates if blanked).

## Failure modes

| Symptom | Check |
|---|---|
| Bot silent | `systemctl --user status hermes-gateway`; `TELEGRAM_ALLOWED_USERS` numeric? only one poller (stop foreground gateway)? |
| `gateway install` did nothing | known upstream prompt bug — this repo already pipes `printf 'n\nY\n'`; re-run `--tags telegram` |
| Dies on reboot | `loginctl show-user hermes -p Linger` must be `yes` |
| SSH times out after a reboot, gateway fine | sshd never started: `ssh.socket` disabled, `ssh.service` not enabled (fixed in the tailscale role). Recover: ask the agent (Perch/Telegram) to run `sudo systemctl enable --now ssh`, or Hetzner rescue → `mount /dev/sda1 /mnt && chroot /mnt systemctl enable ssh.service` → reboot. Deploys from this version on keep it enabled |
| Phone can't reach API | gateway bound to loopback? need `API_SERVER_HOST=0.0.0.0` + UFW tailnet rule; Tailscale up on both ends? |
| Perch 401 after dashboard restart | token wasn't pinned — re-run `--tags perch`, re-pair |
| Approval never arrives | normal when guardian auto-handles it; "no approval" ≠ "checked safe". Pending approvals time out closed (default 300 s). |
| Disk full | install is ~6.6 GB; `df -h`; prune Docker (`docker system prune`) |

## Teardown

`make teardown` destroys the VPS (asks first). Snapshots and local
`./backups/` survive. Delete the Tailscale machine entry afterwards.
