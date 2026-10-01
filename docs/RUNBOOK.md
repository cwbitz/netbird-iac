# Runbook

[English](RUNBOOK.md) | [简体中文](RUNBOOK.zh-CN.md)

Operational procedures for the self-hosted NetBird server. See `README.md` for
the overview and `AGENTS.md` for design notes and gotchas.

## 0. Prerequisites (once)

- Public domain whose A record points at the host, with **TCP 80/443** and
  **UDP 3478** open — verify *before* the first deploy.
- Control node: ansible-core (pinned), Python 3, `openssl`, and the Galaxy
  collections: `make ans-deps`.
- A host entry: `make host-init HOST=<hostname>`, then edit
  `inventory/hosts.yml`, `inventory/host_vars/<host>/main.yml` (domain, ACME
  email) and `inventory/host_vars/<host>/vault.yml` (IP, SSH creds, owner), and
  encrypt the vault:
  `ansible-vault encrypt inventory/host_vars/<host>/vault.yml`.
- Create the non-root service account (as root, once): `make host-bootstrap`,
  then point the connection at it in `vault.yml`. Deploys refuse root unless
  `host_allow_root_login=true`.
- The vault password file is auto-created by the make targets
  (`~/.config/projects/netbird-iac/ansible_vault_password`); keep it safe.

## 1. Deploy

```bash
make ans-lint      # syntax check + ansible-lint
make ans-check     # dry run (--check --diff)
make ans-site      # deploy (add TAGS=... for a focused run)
```

Focused tags: `netbird`, `netbird_preflight`, `netbird_config`,
`netbird_deploy`, `netbird_owner` (`make ans-tags TAGS=<tag>`).

The deploy asserts inputs and the non-root account, generates missing secrets
into `vault_managed.yml`, renders `config.yaml` / `dashboard.env` /
`docker-compose.yml` to `{{ stack_dir }}` (`/opt/netbird`), starts the stack,
waits for TLS, then optionally creates the first owner.

Verify:

```bash
make ans-ping
curl -fsS https://<domain>/oauth2/.well-known/openid-configuration >/dev/null && echo ok
ssh <host> 'cd /opt/netbird && docker compose ps'
```

**First deploy / GeoLite2**: the server blocks startup while downloading the
GeoLite2 DBs from `pkgs.netbird.io`. If the readiness wait times out, re-run
`make ans-site` (the DBs persist), or pre-seed the DBs into the volume and set
`disable_geolite_update: true`.

## 2. First owner and access token

- With `vault_owner_email` set, the first owner is created automatically via
  `/api/setup` (works only while the instance has no accounts). The same run
  creates an `admin` service user and its PAT, stored as
  `vault_admin_service_user_access_token`.
- Without an email, open `https://<domain>/setup` and create the owner; then
  create an `admin` service user and an Access Token (Team → Service Users) and
  set `vault_admin_service_user_access_token` in `vault.yml`.
- PATs expire (max 365 days). When a tenant run reports the token rejected,
  recreate it in the Dashboard and update the vault.

## 3. Day-2 changes (server)

- Edit `inventory/host_vars/<host>/main.yml` (non-secret) or the vault (secret),
  then `make ans-site`. Config templates notify the restart handler, so the stack
  restarts when config changes.
- Image versions live in `roles/netbird_server/defaults/main.yml`
  (Renovate-tracked); the dashboard follows `latest`.
- Never edit rendered files under `{{ stack_dir }}` on the host — rendering is
  the source of truth.

## 4. Tenant configuration as code

```bash
make netbird-plan          # read-only diff (safe default)
make netbird-apply         # apply desired state
make netbird-apply-strict  # apply + remove unmanaged resources
```

Desired state uses the collection's native variables in
`inventory/host_vars/<host>/main.yml` (secret/PII in `vault.yml`). The play
renders a generated, gitignored directory
(`.ansible_cache/tenant_config/<host>/`) and applies it. Requires a valid
`vault_admin_service_user_access_token`.

Order for routed networks and exit nodes:

1. `make netbird-apply` — creates and persists the setup key,
2. enroll the client (consumes that setup key),
3. re-run `make netbird-apply` to activate networks whose gateway peer is now
   enrolled.

## 5. Backup and restore

```bash
make netbird-backup                              # -> backup/<host>/<stamp>/
make netbird-restore FROM=backup/<host>/<stamp>
```

- `netbird-backup` stops the container, archives the `netbird_data` volume
  (`netbird_data.tgz`), and restarts it. The archive holds user PII and hashed
  credentials.
- The encryption key is **not** in the archive. It is
  `inventory/host_vars/<host>/vault_managed.yml` on the control node — **back it
  up separately and protect it**. Losing `vault_datastore_encryption_key` makes
  the archived data unrecoverable.
- `netbird-restore` replaces the data volume, then redeploys. `config.yaml` is
  re-rendered from the control node's current `vault_managed.yml`, so that file
  must hold the **same** datastore key as when the data was archived.

Verify after restore: the OIDC discovery URL answers and users can log in.

## 6. Upgrade and rollback

- **Upgrade**: let Renovate bump the pinned tags (or edit
  `roles/netbird_server/defaults/main.yml`), then `make ans-site`.
- **Version rollback**: set the previous tag and re-run `make ans-site`.
- **Full rollback**: restore from a matching backup (data **and** the same
  `vault_managed.yml`).
- **Config rollback**: `git revert` or edit the per-host vars, then `make
  ans-site`.

## 7. Troubleshooting

| Symptom | Check / action |
|---|---|
| TLS / OIDC not answering | Domain A record resolves to the host; TCP 80/443 open; `docker logs netbird-traefik`. |
| STUN / relay clients fail | UDP 3478 open; Traefik owns `172.30.0.10`. |
| Readiness times out on first deploy | GeoLite2 download (§1); re-run or pre-seed the DBs. |
| Tenant run: token rejected | PAT expired — recreate it for the `admin` service user and update the vault (§2). |
| Routed network skipped | Gateway peer not enrolled yet; enroll the client, then re-run (§4). |
| "Agent-network settings have not been bootstrapped" | Bootstrap agent-network out-of-band first; leave `netbird_an_settings` unset until then. |
| A vault file is unreadable | It must be ansible-vault encrypted; the helpers re-encrypt a plaintext file on the next run. |

Useful commands:

```bash
make ans-vars HOST=<host>                          # resolved vars incl. vault
ssh <host> 'cd /opt/netbird && docker compose logs -f netbird-server'
ssh <host> 'cd /opt/netbird && docker compose ps'
```

## 8. Secrets and safety

- Never commit `vault.yml`, `vault_managed.yml`, or `backup/` (all gitignored).
- The vault password file is required to decrypt any vault.
- Keep a copy of `vault_managed.yml` off-host, separate from data backups.
