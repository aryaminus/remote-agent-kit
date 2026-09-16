# remote-agent-kit — operator entrypoint. Run `make help`.
SHELL := /bin/bash
-include .env
export

TF := terraform -chdir=terraform
ANS := ansible-playbook -i ansible/inventory/hosts.yml ansible/playbook.yml

.PHONY: help init plan apply deploy pair ssh doctor backup logs teardown check

help: ## show every command
	@grep -E '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

start: ## THE easy button: interactive zero-to-agent-box wizard
	./scripts/start.sh

init: ## one-time: terraform init + ansible collections
	$(TF) init
	ansible-galaxy collection install -r ansible/collections/requirements.yml -p ./ansible/collections
	@echo "Next: fill terraform/terraform.tfvars + ansible/inventory/hosts.yml + .env, then: make preflight"

preflight: ## Murphy's Law gate: fail free on your laptop before spending a cent
	./scripts/preflight.sh

plan: ## review what Terraform will create (no changes)
	$(TF) plan

apply: ## provision the VPS + firewall (~60s)
	$(TF) apply
	@echo "VPS up. Copy the server IPv4 into ansible/inventory/hosts.yml, then: make deploy"

deploy: ## configure everything via Ansible (~10 min). Needs TAILSCALE_AUTHKEY.
	@test -n "$(TAILSCALE_AUTHKEY)" || (echo "TAILSCALE_AUTHKEY is empty — set it in .env"; exit 1)
	$(ANS) --extra-vars "@.env.json" 2>/dev/null || $(ANS)
	@echo "Done. Then: make pair"

pair: ## print pairing info (Perch QR via server script + Telegram test)
	./scripts/pair.sh

ssh: ## ssh to the box over Tailscale (no public port needed)
	ssh hermes@$$(terraform -chdir=terraform output -raw tailscale_hint 2>/dev/null || echo '<server-ip — see terraform output>')

doctor: ## 7-point health check against the live box
	./scripts/doctor.sh

backup: ## snapshot reminder + pull a hermes-data tarball
	./scripts/backup.sh

rollback: ## restore ~/.hermes on the server from a local backup (asks first)
	./scripts/rollback.sh $(FILE)

logs: ## follow the gateway journal on the server
	ssh hermes@$$(terraform -chdir=terraform output -raw server_ipv4 2>/dev/null) \
	  'journalctl --user -u hermes-gateway -f'

teardown: ## DESTROYS the VPS (asks first). Snapshots survive if kept.
	$(TF) destroy

check: ## secret scan + syntax checks (also runs in CI)
	./scripts/repo_check.sh

verify: ## every local gate: repo_check + terraform validate (what CI runs)
	./scripts/repo_check.sh
	terraform -chdir=terraform init -backend=false
	terraform -chdir=terraform validate
	@if command -v ansible-playbook >/dev/null 2>&1; then \
	  ansible-playbook -i ansible/inventory/hosts.yml.example --syntax-check ansible/playbook.yml; \
	else echo "(ansible not installed — CI covers syntax check)"; fi
	@if command -v shellcheck >/dev/null 2>&1; then \
	  shellcheck -S warning scripts/*.sh; \
	else echo "(shellcheck not installed — CI covers it)"; fi
