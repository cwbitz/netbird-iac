# ==============================================================================
# NetBird self-hosted IaC - Makefile wrapper
# ==============================================================================
# Thin, well-known entry points around ansible-playbook / ansible-lint. Run
# `make help` for the target list. TAGS=... narrows a run to a tag, HOST=...
# targets a single host.

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

.PHONY: help
help:
	@echo "NetBird self-hosted IaC"
	@echo ""
	@echo "  make ans-deps-tools   Install the pinned toolchain via mise/asdf (.tool-versions)"
	@echo "  make ans-deps         Install the pinned toolchain + Galaxy collections"
	@echo "  make ans-vault-init   Create the Ansible Vault password file (if missing)"
	@echo "  make host-init         Scaffold host_vars/<HOST> from the example/ template"
	@echo "  make host-bootstrap    Optional: set APT/Docker mirrors on the host"
	@echo "  make ans-lint         Playbook syntax check + ansible-lint"
	@echo "  make ans-check        Dry-run (--check --diff); add TAGS=..."
	@echo "  make ans-site         Deploy the server (full playbook)"
	@echo "  make ans-tags TAGS=x  Deploy only tasks tagged x"
	@echo "  make netbird-plan     Tenant config-as-code: read-only diff (safe)"
	@echo "  make netbird-apply    Tenant config-as-code: apply desired state"
	@echo "  make netbird-apply-strict  Apply + remove unmanaged resources"
	@echo "  make netbird-backup   Back up netbird_data + the encryption key"
	@echo "  make netbird-restore  Restore FROM=backup/<host>/<stamp>"
	@echo "  make ans-vars HOST=x  Print resolved host vars (incl. decrypted vault)"
	@echo "  make ans-ping         Test SSH connectivity"
	@echo "  make clean            Remove the local fact cache"

.PHONY: history
history:
	@git log --oneline -10

.PHONY: ans-deps-tools
ans-deps-tools:
	@if command -v mise >/dev/null 2>&1; then mise install; \
	elif command -v asdf >/dev/null 2>&1; then asdf install; \
	else echo "Neither mise nor asdf found; install one, or ensure ansible-core 2.19.x is on PATH." >&2; exit 1; fi

.PHONY: ans-deps
ans-deps: ans-deps-tools gal-deps

.PHONY: gal-deps
gal-deps:
	ansible-galaxy install -r requirements.yml

.PHONY: ans-vault-init
ans-vault-init:
	@mkdir -p "$(VAULT_PW_DIR)"
	@if [ ! -f "$(VAULT_PW_FILE)" ]; then \
		umask 077; openssl rand -base64 32 > "$(VAULT_PW_FILE)"; \
		echo "Created vault password: $(VAULT_PW_FILE)"; \
	else echo "Vault password already present: $(VAULT_PW_FILE)"; fi

.PHONY: host-init
host-init:
	@if [ -z "$(HOST)" ]; then echo "Usage: make host-init HOST=<hostname>" >&2; exit 1; fi
	@if [ -e "$(INVENTORY)" ]; then :; else cp inventory/hosts.yml.example $(INVENTORY); echo "Created $(INVENTORY) from example"; fi
	mkdir -p inventory/host_vars/$(HOST)
	cp -n inventory/host_vars/example/main.yml inventory/host_vars/$(HOST)/main.yml
	cp -n inventory/host_vars/example/vault.yml.example inventory/host_vars/$(HOST)/vault.yml
	@echo "Scaffolded inventory/host_vars/$(HOST)/ (edit main.yml + vault.yml, then: ansible-vault encrypt inventory/host_vars/$(HOST)/vault.yml)"

.PHONY: ans-lint
ans-lint: ans-vault-init
	ansible-playbook -i $(INVENTORY) --syntax-check playbooks/site.yml
	ansible-playbook -i $(INVENTORY) --syntax-check playbooks/tenant.yml
	ansible-playbook -i $(INVENTORY) --syntax-check playbooks/bootstrap.yml
	ansible-playbook -i $(INVENTORY) --syntax-check playbooks/backup.yml
	ansible-playbook -i $(INVENTORY) --syntax-check playbooks/restore.yml
	ansible-lint playbooks/site.yml playbooks/tenant.yml playbooks/bootstrap.yml playbooks/backup.yml playbooks/restore.yml

.PHONY: ans-check
ans-check: ans-vault-init
	$(ANSIBLE_PB) --check --diff $(if $(TAGS),--tags $(TAGS),)

.PHONY: ans-site
ans-site: ans-vault-init
	$(ANSIBLE_PB) $(if $(TAGS),--tags $(TAGS),)

.PHONY: ans-tags
ans-tags: ans-vault-init
	@if [ -z "$(TAGS)" ]; then echo "Usage: make ans-tags TAGS=<tag>[,<tag>]" >&2; exit 1; fi
	$(ANSIBLE_PB) --tags $(TAGS)

.PHONY: host-bootstrap
host-bootstrap: ans-vault-init
	ansible-playbook -i $(INVENTORY) playbooks/bootstrap.yml

.PHONY: netbird-plan
netbird-plan: ans-vault-init
	ansible-playbook -i $(INVENTORY) playbooks/tenant.yml

.PHONY: netbird-apply
netbird-apply: ans-vault-init
	ansible-playbook -i $(INVENTORY) playbooks/tenant.yml -e tenant_commit=true

.PHONY: netbird-apply-strict
netbird-apply-strict: ans-vault-init
	ansible-playbook -i $(INVENTORY) playbooks/tenant.yml -e tenant_commit=true -e tenant_strict=true

.PHONY: netbird-backup
netbird-backup: ans-vault-init
	ansible-playbook -i $(INVENTORY) playbooks/backup.yml

.PHONY: netbird-restore
netbird-restore: ans-vault-init
	@if [ -z "$(FROM)" ]; then echo "Usage: make netbird-restore FROM=backup/<host>/<timestamp>" >&2; exit 1; fi
	ansible-playbook -i $(INVENTORY) playbooks/restore.yml -e restore_from=$(abspath $(FROM))

.PHONY: ans-vars
ans-vars: ans-vault-init
	@if [ -z "$(HOST)" ]; then echo "Usage: make ans-vars HOST=<hostname>" >&2; exit 1; fi
	ansible -i $(INVENTORY) $(HOST) -m ansible.builtin.debug -a "var=hostvars[inventory_hostname]"

.PHONY: ans-ping
ans-ping: ans-vault-init
	ansible -i $(INVENTORY) netbird -m ansible.builtin.ping

.PHONY: clean
clean:
	rm -rf .ansible_cache
