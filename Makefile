# ==============================================================================
# NetBird self-hosted IaC - Makefile wrapper
# ==============================================================================
# Entry points around ansible-playbook / ansible-lint. Run `make help` for the
# target list. Override HOST=... (single host), TAGS=... (focused run),
# FROM=... (restore source).

SHELL := /bin/bash
.DEFAULT_GOAL := help

PLAYBOOK  ?= playbooks/site.yml
INVENTORY ?= inventory/hosts.yml
TAGS      ?=
HOST      ?=
FROM      ?=

VAULT_PW_DIR  := $(HOME)/.config/projects/netbird-iac
VAULT_PW_FILE := $(VAULT_PW_DIR)/ansible_vault_password
ANSIBLE_PB    := ansible-playbook -i $(INVENTORY) $(PLAYBOOK)

##@ General

.PHONY: help
help: ## Show grouped targets and overridable variables
	@printf '\nUsage: make <target> [VAR=value ...]\n'
	@awk 'BEGIN {FS = ":.*?## "} \
		/^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5); next } \
		/^[a-zA-Z0-9_-]+:.*?## / { printf "  \033[36m%-23s\033[0m %s\n", $$1, $$2 }' \
		$(MAKEFILE_LIST)
	@printf '\n\033[1mVariables (override on the command line)\033[0m\n'
	@printf '  \033[36m%-23s\033[0m %s\n' \
		'HOST'      'target host for host-init; optional for print, e.g. HOST=<hostname>' \
		'TAGS'      'focused tags for dry-run/deploy, e.g. TAGS=netbird' \
		'FROM'      'backup stamp for restore, e.g. FROM=backup/<host>/<stamp>' \
		'PLAYBOOK'  'playbook for dry-run/deploy (default: playbooks/site.yml)' \
		'INVENTORY' 'inventory file (default: inventory/hosts.yml)'
	@printf '\n'

##@ Dependencies

.PHONY: install
install: ## Install the pinned toolchain + Galaxy collections
	@if command -v mise >/dev/null 2>&1; then mise install; \
	elif command -v asdf >/dev/null 2>&1; then asdf install; \
	else echo "Neither mise nor asdf found; install one, or ensure ansible-core 2.19.x is on PATH." >&2; exit 1; fi
	ansible-galaxy install -r requirements.yml

##@ Vault

.PHONY: vault-init
vault-init: ## Create the Ansible Vault password file (if missing)
	@mkdir -p "$(VAULT_PW_DIR)"
	@if [ ! -f "$(VAULT_PW_FILE)" ]; then \
		umask 077; openssl rand -base64 32 > "$(VAULT_PW_FILE)"; \
		echo "Created vault password: $(VAULT_PW_FILE)"; \
	else echo "Vault password already present: $(VAULT_PW_FILE)"; fi

##@ Hosts

.PHONY: host-init
host-init: ## Scaffold host_vars/<HOST> from the example/ template
	@if [ -z "$(HOST)" ]; then echo "Usage: make host-init HOST=<hostname>" >&2; exit 1; fi
	@if [ -e "$(INVENTORY)" ]; then :; else cp inventory/hosts.yml.example $(INVENTORY); echo "Created $(INVENTORY) from example"; fi
	mkdir -p inventory/host_vars/$(HOST)
	cp -n inventory/host_vars/example/main.yml inventory/host_vars/$(HOST)/main.yml
	cp -n inventory/host_vars/example/vault.yml.example inventory/host_vars/$(HOST)/vault.yml
	@echo "Scaffolded inventory/host_vars/$(HOST)/ (edit main.yml + vault.yml, then: ansible-vault encrypt inventory/host_vars/$(HOST)/vault.yml)"

.PHONY: host-bootstrap
host-bootstrap: vault-init ## Optional: host tuning + service accounts (bootstrap.yml)
	ansible-playbook -i $(INVENTORY) playbooks/bootstrap.yml

##@ Server

.PHONY: lint
lint: vault-init ## Playbook syntax check + ansible-lint
	ansible-playbook -i $(INVENTORY) --syntax-check playbooks/site.yml
	ansible-playbook -i $(INVENTORY) --syntax-check playbooks/tenant.yml
	ansible-playbook -i $(INVENTORY) --syntax-check playbooks/bootstrap.yml
	ansible-playbook -i $(INVENTORY) --syntax-check playbooks/backup.yml
	ansible-playbook -i $(INVENTORY) --syntax-check playbooks/restore.yml
	ansible-lint playbooks/site.yml playbooks/tenant.yml playbooks/bootstrap.yml playbooks/backup.yml playbooks/restore.yml

.PHONY: dry-run
dry-run: vault-init ## Dry-run (--check --diff); add TAGS=...
	$(ANSIBLE_PB) --check --diff $(if $(TAGS),--tags $(TAGS),)

.PHONY: deploy
deploy: vault-init ## Deploy the server (full playbook)
	$(ANSIBLE_PB) $(if $(TAGS),--tags $(TAGS),)

##@ Tenant (config-as-code)

.PHONY: plan
plan: vault-init ## Tenant config-as-code: read-only diff (safe)
	ansible-playbook -i $(INVENTORY) playbooks/tenant.yml

.PHONY: apply
apply: vault-init ## Tenant config-as-code: apply desired state
	ansible-playbook -i $(INVENTORY) playbooks/tenant.yml -e tenant_commit=true

.PHONY: apply-strict
apply-strict: vault-init ## Apply + remove unmanaged resources
	ansible-playbook -i $(INVENTORY) playbooks/tenant.yml -e tenant_commit=true -e tenant_strict=true

##@ Backup

.PHONY: backup
backup: vault-init ## Back up the netbird_data volume (key stays in vault_managed.yml)
	ansible-playbook -i $(INVENTORY) playbooks/backup.yml

.PHONY: restore
restore: vault-init ## Restore FROM=backup/<host>/<stamp>
	@if [ -z "$(FROM)" ]; then echo "Usage: make restore FROM=backup/<host>/<timestamp>" >&2; exit 1; fi
	ansible-playbook -i $(INVENTORY) playbooks/restore.yml -e restore_from=$(abspath $(FROM))

##@ Operations

.PHONY: print
print: vault-init ## Print resolved host vars (incl. decrypted vault); HOST optional if single-host
	@host="$(HOST)"; \
	if [ -z "$$host" ]; then \
		host="$$(ansible-inventory -i $(INVENTORY) --list 2>/dev/null \
			| python3 -c 'import json,sys; h=list(json.load(sys.stdin).get("_meta",{}).get("hostvars",{})); print(h[0] if len(h)==1 else "")')"; \
	fi; \
	if [ -z "$$host" ]; then \
		echo "Usage: make print HOST=<hostname> (required when the inventory has no single host)" >&2; exit 1; \
	fi; \
	echo "Resolved host: $$host"; \
	ansible -i $(INVENTORY) "$$host" -m ansible.builtin.debug -a "var=hostvars[inventory_hostname]"

.PHONY: ping
ping: vault-init ## Test SSH connectivity
	ansible -i $(INVENTORY) netbird -m ansible.builtin.ping

##@ Housekeeping

.PHONY: clean
clean: ## Remove the local fact cache
	rm -rf .ansible_cache
