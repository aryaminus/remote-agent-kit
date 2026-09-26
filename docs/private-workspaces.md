# Private repos and client workspaces on the box

The box is a good place to keep long-running work: private repositories your
agents maintain, and client projects that ship their own devcontainer
toolkit. This page covers doing that without leaking one into the other.

## 1. Private repositories

* **Auth:** the `aoe` role creates the box's own ed25519 key and prints the
  public half — add it at github.com → Settings → SSH keys (or as a
  read/write deploy key on one repo). `make gh-login` adds `gh` API access.
* **Clone into `~/work/<repo>`.** Everything under `~/work` is attached to
  ControlKeel per repo (hooks, skills, MCP) and is where AoE sessions start.
* **Rewritten history needs a re-clone.** When a remote was force-pushed to
  scrub something, `git pull` cannot fast-forward — and the old checkout still
  holds the scrubbed objects. Move the old checkout out of `~/work`, clone
  fresh, check nothing was unique (`git log --branches --not --remotes`,
  `git status --ignored`), then delete the old one.
* **Repo-local agent config travels with the clone** (a tracked
  `.claude/settings.json`, skills, `AGENTS.md`). Machine-local files —
  `.claude/settings.local.json`, MCP registrations (`claude mcp add …`) — do
  not; recreate them per machine.

## 2. Confidential client material

Every agent on the box sends what it reads to its model provider: Hermes to
Nous/OpenRouter, opencode to its configured providers, Claude Code to Z.AI when
the bridge is active (usage.md §3), and so on. Decide per client which of
those providers may see their material — often none.

* **Keep client workspaces outside `~/work`** (e.g. `~/clients/<name>`), so
  the per-repo ControlKeel attach, AoE's default paths, and "look around in
  ~/work" prompts never reach them. Point agents at them only on purpose.
* **Unix permissions are not a boundary here.** The admin user is in the
  `docker` group (AoE sandboxes), which is root-equivalent; a separate user
  would not stop a container from mounting the directory. If a client's
  terms rule out every provider on the box, use a separate box.
* **A client toolkit brings its own credentials.** Keep its key file at
  `0600`, never in git, and check that the toolkit's containers use it rather
  than the host's agent config:
  - before the first `devcontainer up`, read the toolkit's
    `.devcontainer/devcontainer.json` for bind mounts of `~/.claude`,
    `~/.codex`, or `~/.config/opencode` — the host's copies carry this box's
    provider settings (e.g. the Z.AI bridge in `~/.claude/settings.json`);
  - inside the container, `env | grep -i base_url` should show the client's
    endpoint, and the agent's own status screen should agree.

## 3. Devcontainer toolkits

The `toolchain` role installs what they need: Docker with the **buildx**
plugin (BuildKit — the legacy builder rejects heredoc Dockerfiles), the
**devcontainer CLI**, and `unzip` (extract zips with it; some GUI extractors
drop symlinks).

```bash
scp toolkit.zip <box>:~/clients/<name>/          # or curl the download link on the box
ssh <box>
cd ~/clients/<name> && unzip toolkit.zip
cd <toolkit>/<devcontainer-folder>
devcontainer up --workspace-folder .             # or: npx @devcontainers/cli up
devcontainer exec --workspace-folder . bash
```

* **Long jobs:** run them inside `tmux` so a dropped SSH session doesn't
  stop them.
* **Browser access to an app inside a container:** forward the port over
  SSH (`ssh -L 3000:localhost:3000 <box>`) or reach it on the tailnet.
* **Editor:** VS Code Remote-SSH to the box, then Dev Containers → "Reopen in
  Container" works against the box's Docker.

## 4. Sizing

The default `cx33` (4 vCPU / 8 GB / 80 GB) runs the gateway and a few agents
comfortably, but many devcontainer toolkits ask for **16 GB RAM** and tens of
GB of disk for images and build caches. For that work set
`server_type = "cx43"` (8 vCPU / 16 GB / 160 GB, x86) in
`terraform/terraform.tfvars`, then `make plan` and `make apply` — the server
is powered off and resized in place; check the console for the current price
first. `docker system prune` reclaims image space between projects.
