# ADR-002: Terraform + Ansible over bash-only or full-bake images

Date: 2026-09-15 · Status: accepted

## Context

Contenders for provisioning/configuring the box: imperative bash scripts,
Terraform+Ansible, or baked images (Packer + OpenTofu + cloud-init).

## Decision

**Terraform for provisioning, Ansible for configuration, Make as entrypoint,
bash only for glue** — split along change cadence (Gall's Law: grow the
working simple system):

* Terraform owns what is *stateful and reviewable*: firewall, server, key.
  `make plan` shows the diff before money moves (Map ≠ Territory guard).
* Ansible owns what is *re-runnable*: 7 idempotent roles. `make deploy`
  twice = no-op twice. cloud-init runs once (first boot minimum), Ansible
  runs forever — never put converge-logic in cloud-init.
* bash owns what is *small and linear*: preflight, doctor, backup, rollback,
  pair, repo_check. Anything growing branches/loops graduates to Ansible.

## Consequences

* No Packer baking until upgrade pain (Gilb) says so — weekly rebakes are
  process overhead we haven't earned (YAGNI).
* `ansible/roles/*` must stay applicable to ANY Ubuntu 24.04 x86 box so
  exe.dev/box alternatives work with a hosts.yml-only switch.
* Every role needs the `--tags` path re-runnable independently
  (telegram re-key, perch re-pair).
